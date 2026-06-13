import BipboxCore
import XCTest

final class TopicDiscoveryTests: XCTestCase {

    func testDiscoversSeparatedClustersIntoDistinctTopics() {
        let dim = 8
        func vec(axis: Int, jitter: Float) -> [Float] {
            var v = [Float](repeating: 0, count: dim)
            v[axis] = 1.0
            v[(axis + 1) % dim] = jitter
            return v
        }
        var vectors: [(id: UUID, vector: [Float])] = []
        var names: [UUID: String] = [:]
        var groupOf: [UUID: Int] = [:]
        for g in 0..<3 {
            for i in 0..<6 {
                let id = UUID()
                vectors.append((id, vec(axis: g * 2, jitter: Float(i) * 0.02)))
                names[id] = "group\(g)_item\(i)"
                groupOf[id] = g
            }
        }

        let graph = TopicDiscovery.discover(vectors: vectors, names: names, k: 4, minTopicSize: 3)

        XCTAssertGreaterThanOrEqual(graph.topics.count, 2, "well-separated inputs should yield multiple topics")
        for topic in graph.topics {
            // Each topic should be dominated by a single input group (clean separation)…
            let groups = topic.memberIDs.compactMap { groupOf[$0] }
            let dominant = Dictionary(grouping: groups, by: { $0 }).values.map(\.count).max() ?? 0
            XCTAssertGreaterThan(Double(dominant), Double(groups.count) * 0.5,
                                 "a topic should be dominated by one input group")
            // …and labeled by the shared significant token, never "Group N".
            XCTAssertTrue(topic.label.contains("group"),
                          "label should be the shared token (got '\(topic.label)')")
        }
    }

    func testAssignOnlyVectorsJoinTopicsWithoutDrivingThem() {
        let dim = 8
        func vec(axis: Int, jitter: Float) -> [Float] {
            var v = [Float](repeating: 0, count: dim)
            v[axis] = 1.0
            v[(axis + 1) % dim] = jitter
            return v
        }
        var seeds: [(id: UUID, vector: [Float])] = []
        var names: [UUID: String] = [:]
        for g in [0, 4] {
            for i in 0..<6 {
                let id = UUID()
                seeds.append((id, vec(axis: g, jitter: Float(i) * 0.02)))
                names[id] = "seed\(g)_doc\(i)"
            }
        }
        // A flood of near-identical records (a 7k-file dump) close to group 0 —
        // as ASSIGN vectors they must not shatter discovery into micro-topics.
        var flood: [(id: UUID, vector: [Float])] = []
        for i in 0..<30 {
            let id = UUID()
            flood.append((id, vec(axis: 0, jitter: Float(i % 5) * 0.01)))
            names[id] = "record\(i)"
        }

        let withFlood = TopicDiscovery.discover(vectors: seeds, assign: flood, names: names,
                                                k: 4, minTopicSize: 3)
        let seedsOnly = TopicDiscovery.discover(vectors: seeds, names: names,
                                                k: 4, minTopicSize: 3)

        XCTAssertEqual(withFlood.topics.count, seedsOnly.topics.count,
                       "assign vectors must not create or shatter topics")
        let assignedFlood = flood.filter { withFlood.membership[$0.id] != nil }
        XCTAssertEqual(assignedFlood.count, flood.count,
                       "every assign vector near a topic gets soft membership")
        let floodIDs = Set(flood.map(\.id))
        XCTAssertTrue(withFlood.topics.contains { !floodIDs.isDisjoint(with: $0.memberIDs) },
                      "assigned records appear in topic member lists")
    }

    func testEmptyBelowMinimumSize() {
        let graph = TopicDiscovery.discover(
            vectors: [(UUID(), [1, 0]), (UUID(), [0, 1])], names: [:], minTopicSize: 3)
        XCTAssertTrue(graph.topics.isEmpty, "too few items -> no topics (no fallback)")
    }
}
