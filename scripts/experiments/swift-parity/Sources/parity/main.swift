import BipboxCore
import Foundation

struct Row: Decodable { let name: String; let vector: [Float] }

// usage: parity <seeds.json> [<assign.json>] [resolution]
let path = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "../topic-graph/rich_vectors.json"
let assignPath = CommandLine.arguments.count > 2 && CommandLine.arguments[2].hasSuffix(".json")
    ? CommandLine.arguments[2] : nil
let resolution = CommandLine.arguments.last.flatMap(Double.init) ?? 2.0

func load(_ path: String) throws -> ([(id: UUID, vector: [Float])], [UUID: String]) {
    let rows = try JSONDecoder().decode([Row].self, from: Data(contentsOf: URL(fileURLWithPath: path)))
    var vectors: [(id: UUID, vector: [Float])] = []
    var names: [UUID: String] = [:]
    for row in rows {
        let id = UUID()
        vectors.append((id: id, vector: row.vector))
        names[id] = row.name
    }
    return (vectors, names)
}

let (vectors, seedNames) = try load(path)
var (assign, names) = try assignPath.map(load) ?? ([], [:])
names.merge(seedNames) { _, new in new }

let start = Date()
let graph = TopicDiscovery.discover(vectors: vectors, assign: assign, names: names, resolution: resolution)
let elapsed = Date().timeIntervalSince(start)

print("seeds=\(vectors.count) assign=\(assign.count) dim=\(vectors.first?.vector.count ?? 0) resolution=\(resolution)")
print("topics: \(graph.topics.count) | membership entries: \(graph.membership.count) | topic edges: \(graph.edges.count) | \(String(format: "%.2f", elapsed))s")
for topic in graph.topics.sorted(by: { $0.memberIDs.count > $1.memberIDs.count }) {
    let sample = topic.memberIDs.prefix(2).compactMap { names[$0] }.joined(separator: ", ")
    print(String(format: "[%4d members] %@  (e.g. %@)", topic.memberIDs.count, topic.label, sample))
}
