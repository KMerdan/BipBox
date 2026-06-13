import BipboxCore
import BipboxPersistence
import XCTest

final class EmbeddingBackfillServiceTests: XCTestCase {

    func testEmbedsOnlyItemsMissingAVector() async throws {
        let a = item(name: "fault tree analysis", path: "/x/fta.md")
        let b = item(name: "energy report", path: "/x/energy.md")
        let search = StubSearch([a, b])
        let vectors = try makeIndex()
        let embedder = MapEmbedder(map: ["fault tree analysis": [1, 0], "energy report": [0, 1]])

        // `a` already has a vector under the embedder's model; only `b` should be filled.
        try await vectors.upsertVector(VectorRecord(itemID: a.id, modelID: embedder.modelID, vector: [1, 0]))

        let backfill = DefaultEmbeddingBackfillService(
            searchService: search, embedder: embedder, vectorIndex: vectors)
        let count = await backfill.backfill(limit: 100)

        XCTAssertEqual(count, 1, "only the item missing a vector is embedded")
        let stored = try await vectors.vectors(modelID: embedder.modelID)
        XCTAssertEqual(Set(stored.map(\.itemID)), [a.id, b.id], "both items now have a vector")
    }

    func testEmbedsNothingWhenModelNotReady() async throws {
        let a = item(name: "doc", path: "/x/doc.md")
        let search = StubSearch([a])
        let vectors = try makeIndex()
        let backfill = DefaultEmbeddingBackfillService(
            searchService: search, embedder: NotReadyEmbedder(), vectorIndex: vectors)

        let count = await backfill.backfill(limit: 100)
        XCTAssertEqual(count, 0, "an unprovisioned embedder (embed -> nil) writes no vectors")
    }

    private func makeIndex() throws -> SQLiteVectorIndex {
        try SQLiteVectorIndex(directoryURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("bipbox-backfill-\(UUID().uuidString)", isDirectory: true))
    }

    private func item(name: String, path: String) -> IndexedItem {
        IndexedItem(currentPath: path, displayName: name, kind: .file,
                    importedAt: Date(timeIntervalSince1970: 1_800_000_000),
                    extractedText: nil, status: .indexedOnly)
    }
}

private struct MapEmbedder: TextEmbedder {
    let modelID = "map-embed"
    let map: [String: [Float]]
    func embed(_ text: String) async -> [Float]? {
        map[text] ?? map[text.split(separator: " ").first.map(String.init) ?? text]
    }
}

private struct NotReadyEmbedder: TextEmbedder {
    let modelID = "not-ready"
    func embed(_ text: String) async -> [Float]? { nil }
}

private final class StubSearch: SearchService, @unchecked Sendable {
    private let items: [IndexedItem]
    init(_ items: [IndexedItem]) { self.items = items }
    func index(_ item: IndexedItem) async throws {}
    func update(_ item: IndexedItem) async throws {}
    func search(_ query: SearchQuery) async throws -> SearchResults {
        SearchResults(items: Array(items.prefix(query.limit)), totalCount: items.count)
    }
}
