import Foundation

/// A discovered topic: a dense region of the (mean-centered) embedding space,
/// labeled extractively, with the items soft-assigned to it.
public struct DiscoveredTopic: Sendable, Identifiable {
    public let id: Int
    public let label: String
    public let memberIDs: [UUID]      // soft members (top-k assigned to this topic)
    public let centroid: [Float]      // mean-centered, unit-normalized

    public init(id: Int, label: String, memberIDs: [UUID], centroid: [Float]) {
        self.id = id
        self.label = label
        self.memberIDs = memberIDs
        self.centroid = centroid
    }
}

public struct TopicGraph: Sendable {
    public let topics: [DiscoveredTopic]
    public let membership: [UUID: [Int]]                  // item -> topic ids (overlapping)
    public let edges: [(a: Int, b: Int, weight: Double)]  // topic<->topic by centroid cosine

    public init(topics: [DiscoveredTopic], membership: [UUID: [Int]], edges: [(a: Int, b: Int, weight: Double)]) {
        self.topics = topics
        self.membership = membership
        self.edges = edges
    }

    public static let empty = TopicGraph(topics: [], membership: [:], edges: [])
}

/// Topic discovery — the algorithm validated in scripts/experiments/topic-graph:
/// mean-center (kills embedding anisotropy) -> cosine kNN graph -> Louvain
/// community detection -> soft, overlapping top-k membership. Pure Swift, no deps.
public enum TopicDiscovery {

    /// `vectors` are the discovery SEEDS (aggregate units: projects, collections,
    /// loose docs, capped member samples). `assign` vectors never drive community
    /// detection — they are only soft-assigned to the discovered topics. This is
    /// the experiment's "discover from aggregates, assign everyone" rule that
    /// keeps 7k-file dumps from flooding/shattering discovery.
    public static func discover(
        vectors: [(id: UUID, vector: [Float])],
        assign: [(id: UUID, vector: [Float])] = [],
        names: [UUID: String],
        k: Int = 15,
        resolution: Double = 2.0,
        edgeFloor: Double = 0.30,
        membershipThreshold: Double = 0.30,
        topKTopics: Int = 3,
        minTopicSize: Int = 3,
        edgeTopK: Int = 4,
        preCentered: Bool = false
    ) -> TopicGraph {
        let n = vectors.count
        guard n >= minTopicSize, let dim = vectors.first?.vector.count, dim > 0 else { return .empty }
        let ids = vectors.map(\.id) + assign.map(\.id)
        var V = vectors.map(\.vector) + assign.map(\.vector)
        let total = V.count

        // 1. Mean-center + renormalize (anisotropy removal — the key fix).
        //    The mean is taken over EVERYTHING (seeds + assign), like the
        //    experiment's global mean over the full corpus. Skipped when the
        //    caller already centered+normalized (shared semantic index).
        if !preCentered {
            var mu = [Float](repeating: 0, count: dim)
            var muCount = 0
            for v in V where v.count == dim { for d in 0..<dim { mu[d] += v[d] }; muCount += 1 }
            guard muCount > 0 else { return .empty }
            for d in 0..<dim { mu[d] /= Float(muCount) }
            for i in 0..<total where V[i].count == dim {
                for d in 0..<dim { V[i][d] -= mu[d] }
                normalize(&V[i])
            }
        }

        let cosine: @Sendable ([Float], [Float]) -> Double = { a, b in
            guard a.count == dim, b.count == dim else { return 0 }
            var s: Float = 0
            for d in 0..<dim { s += a[d] * b[d] }
            return Double(s)
        }

        // 2. Cosine kNN graph (symmetric, weighted), edges below the floor dropped.
        //    Neighbor lists are independent per row -> computed concurrently
        //    (the O(n^2 * dim) scan dominates the whole pipeline).
        let centered = V
        var neighborLists = [[(Int, Double)]](repeating: [], count: n)
        neighborLists.withUnsafeMutableBufferPointer { buffer in
            // Safe: each iteration writes only its own slot.
            nonisolated(unsafe) let lists = buffer
            DispatchQueue.concurrentPerform(iterations: n) { i in
                var sims: [(Int, Double)] = []
                for j in 0..<n where j != i {
                    let c = cosine(centered[i], centered[j])
                    if c >= edgeFloor { sims.append((j, c)) }
                }
                sims.sort { $0.1 > $1.1 }
                lists[i] = Array(sims.prefix(k))
            }
        }
        var edgeW: [Int: Double] = [:]   // key a*n+b with a<b
        for i in 0..<n {
            for (j, w) in neighborLists[i] {
                let (a, b) = i < j ? (i, j) : (j, i)
                edgeW[a * n + b] = max(edgeW[a * n + b] ?? 0, w)
            }
        }

        // 3. Louvain local-moving (modularity).
        let comm = louvain(n: n, edges: edgeW, resolution: resolution)

        // 4. Communities -> topic centroids + labels (min size).
        var groups: [Int: [Int]] = [:]
        for i in 0..<n { groups[comm[i], default: []].append(i) }
        let kept = groups.values.filter { $0.count >= minTopicSize }.sorted { $0.count > $1.count }

        var centroids: [[Float]] = []
        var labels: [String] = []
        for members in kept {
            var c = [Float](repeating: 0, count: dim)
            for mi in members where V[mi].count == dim { for d in 0..<dim { c[d] += V[mi][d] } }
            normalize(&c)
            centroids.append(c)
            labels.append(label(members: members, ids: ids, names: names, V: V, centroid: c))
        }

        // 5. Soft membership: EVERY item (seeds AND assign-only) -> its top-k
        //    nearest topics above threshold.
        var membership: [UUID: [Int]] = [:]
        var topicMembers = Array(repeating: [UUID](), count: centroids.count)
        for i in 0..<total {
            var scored = centroids.enumerated().map { ($0.offset, cosine(V[i], $0.element)) }
            scored.sort { $0.1 > $1.1 }
            var assigned: [Int] = []
            for (ti, w) in scored.prefix(topKTopics) where w >= membershipThreshold {
                assigned.append(ti)
                topicMembers[ti].append(ids[i])
            }
            if !assigned.isEmpty { membership[ids[i]] = assigned }
        }

        let topics = centroids.indices.map {
            DiscoveredTopic(id: $0, label: labels[$0], memberIDs: topicMembers[$0], centroid: centroids[$0])
        }

        // 6. Topic<->topic edges by centroid cosine (top-k, thresholded) — replaces
        //    the old "two clusters share a parent folder" hairball. Top-k lists are
        //    asymmetric, so pairs are deduped by (min, max) keeping the edge if
        //    EITHER endpoint nominated it (same as the kNN step).
        let t = centroids.count
        var topicEdgeW: [Int: Double] = [:]   // key a*t+b with a<b
        for a in centroids.indices {
            var sims: [(Int, Double)] = []
            for b in centroids.indices where b != a { sims.append((b, cosine(centroids[a], centroids[b]))) }
            sims.sort { $0.1 > $1.1 }
            for (b, w) in sims.prefix(edgeTopK) where w >= membershipThreshold {
                let (x, y) = a < b ? (a, b) : (b, a)
                topicEdgeW[x * t + y] = max(topicEdgeW[x * t + y] ?? 0, w)
            }
        }
        let edges = topicEdgeW
            .map { (a: $0.key / t, b: $0.key % t, weight: $0.value) }
            .sorted { $0.weight > $1.weight }

        return TopicGraph(topics: topics, membership: membership, edges: edges)
    }

    // MARK: - Louvain

    private static func louvain(n: Int, edges: [Int: Double], resolution: Double) -> [Int] {
        var adj = Array(repeating: [(Int, Double)](), count: n)
        var deg = [Double](repeating: 0, count: n)
        var m = 0.0
        for (key, w) in edges {
            let a = key / n, b = key % n
            adj[a].append((b, w)); adj[b].append((a, w))
            deg[a] += w; deg[b] += w; m += w
        }
        var comm = Array(0..<n)
        guard m > 0 else { return comm }
        var ctot = deg
        var improved = true
        var passes = 0
        while improved && passes < 20 {
            improved = false
            passes += 1
            for i in 0..<n {
                let ci = comm[i], ki = deg[i]
                var wto: [Int: Double] = [:]
                for (j, w) in adj[i] where j != i { wto[comm[j], default: 0] += w }
                ctot[ci] -= ki
                var bestC = ci, bestGain = 0.0
                for (c, wic) in wto {
                    let gain = wic - resolution * ctot[c] * ki / (2 * m)
                    if gain > bestGain { bestGain = gain; bestC = c }
                }
                comm[i] = bestC
                ctot[bestC] += ki
                if bestC != ci { improved = true }
            }
        }
        return comm
    }

    // MARK: - labeling

    private static func label(members: [Int], ids: [UUID], names: [UUID: String],
                              V: [[Float]], centroid: [Float]) -> String {
        var counts: [String: Int] = [:]
        for mi in members {
            // Label from the name STEM — the extension would otherwise dominate
            // shared tokens ("pdf · docx" topics).
            let stem = ((names[ids[mi]] ?? "") as NSString).deletingPathExtension
            for token in tokens(stem) { counts[token, default: 0] += 1 }
        }
        let top = counts.filter { $0.value > 1 }.sorted { $0.value > $1.value }.prefix(3).map(\.key)
        if !top.isEmpty { return top.joined(separator: " · ") }
        // else: the member nearest the centroid is the representative title
        let dim = centroid.count
        var best = members.first ?? 0
        var bestSim = -Float.greatestFiniteMagnitude
        for mi in members where V[mi].count == dim {
            var s: Float = 0
            for d in 0..<dim { s += V[mi][d] * centroid[d] }
            if s > bestSim { bestSim = s; best = mi }
        }
        let name = names[ids[best]] ?? "Topic"
        return (name as NSString).deletingPathExtension
    }

    private static let stopWords: Set<String> = [
        "the", "and", "for", "report", "final", "copy", "data", "doc", "docs", "new", "untitled"
    ]

    private static func tokens(_ text: String) -> [String] {
        text.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            // length > 1 (not > 2): two-character CJK compounds are common, real words.
            .filter { $0.count > 1 && !stopWords.contains($0) && !$0.allSatisfy(\.isNumber) }
    }

    private static func normalize(_ v: inout [Float]) {
        var norm: Float = 0
        for x in v { norm += x * x }
        norm = norm.squareRoot()
        guard norm > 0 else { return }
        for i in v.indices { v[i] /= norm }
    }
}
