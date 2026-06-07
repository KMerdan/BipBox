import BipboxCore
import BipboxPersistence
import XCTest

/// Slice 1 foundation: SQLite vector index, the on-device embedder, and hybrid
/// (lexical + vector) retrieval.
final class SemanticRetrievalTests: XCTestCase {

    // MARK: SQLiteVectorIndex — mirrors the VectorIndex contract

    private func makeIndex() throws -> SQLiteVectorIndex {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("bipbox-vec-\(UUID().uuidString)", isDirectory: true)
        return try SQLiteVectorIndex(directoryURL: dir)
    }

    func testVectorIndexKeepsModelsSeparated() async throws {
        let index = try makeIndex()
        let a = UUID(); let b = UUID()
        try await index.upsertVector(VectorRecord(itemID: a, modelID: "apple-nl", vector: [1, 0]))
        try await index.upsertVector(VectorRecord(itemID: b, modelID: "local-embed", vector: [1, 0]))

        let apple = try await index.nearest(to: VectorSearchQuery(modelID: "apple-nl", vector: [1, 0]))
        let local = try await index.nearest(to: VectorSearchQuery(modelID: "local-embed", vector: [1, 0]))
        XCTAssertEqual(apple.map(\.itemID), [a])
        XCTAssertEqual(local.map(\.itemID), [b])
    }

    func testVectorIndexRanksByCosineAndAppliesItemFilter() async throws {
        let index = try makeIndex()
        let near = UUID(); let far = UUID()
        try await index.upsertVector(VectorRecord(itemID: near, modelID: "m", vector: [1, 0]))
        try await index.upsertVector(VectorRecord(itemID: far, modelID: "m", vector: [0, 1]))

        let ranked = try await index.nearest(to: VectorSearchQuery(modelID: "m", vector: [1, 0], limit: 2))
        XCTAssertEqual(ranked.first?.itemID, near, "Closest vector ranks first")

        let filtered = try await index.nearest(
            to: VectorSearchQuery(modelID: "m", vector: [1, 0], filters: VectorSearchFilters(itemIDs: [far]))
        )
        XCTAssertEqual(filtered.map(\.itemID), [far], "Item filter restricts candidates")
    }

    func testVectorIndexEnforcesDimensionPerModelAndUnknownModel() async throws {
        let index = try makeIndex()
        try await index.upsertVector(VectorRecord(itemID: UUID(), modelID: "m", vector: [1, 0]))
        do {
            try await index.upsertVector(VectorRecord(itemID: UUID(), modelID: "m", vector: [1, 0, 0]))
            XCTFail("Expected dimension mismatch")
        } catch {
            XCTAssertEqual(error as? VectorIndexError, .invalidDimension(expected: 2, actual: 3))
        }
        do {
            _ = try await index.nearest(to: VectorSearchQuery(modelID: "missing", vector: [1, 0]))
            XCTFail("Expected unsupported model")
        } catch {
            XCTAssertEqual(error as? VectorIndexError, .unsupportedModel("missing"))
        }
    }

    func testVectorIndexPersistsAcrossReopen() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("bipbox-vec-\(UUID().uuidString)", isDirectory: true)
        let id = UUID()
        do {
            let index = try SQLiteVectorIndex(directoryURL: dir)
            try await index.upsertVector(VectorRecord(itemID: id, modelID: "m", vector: [1, 0]))
        }
        let reopened = try SQLiteVectorIndex(directoryURL: dir)
        let matches = try await reopened.nearest(to: VectorSearchQuery(modelID: "m", vector: [1, 0]))
        XCTAssertEqual(matches.map(\.itemID), [id], "Vectors survive a reopen (persisted)")
    }

    // MARK: NLEmbedding embedder (smoke; skip if model unavailable on this host)

    func testNLEmbedderProducesUnitVector() async throws {
        let embedder = NLEmbeddingTextEmbedder()
        try XCTSkipUnless(embedder.isAvailable, "NLEmbedding model unavailable on this host")
        let vector = await embedder.embed("quarterly financial report")
        let v = try XCTUnwrap(vector)
        XCTAssertFalse(v.isEmpty)
        let norm = (v.reduce(Float(0)) { $0 + $1 * $1 }).squareRoot()
        XCTAssertEqual(norm, 1, accuracy: 0.01, "Embedding is unit-normalized")
        let blank = await embedder.embed("   ")
        XCTAssertNil(blank, "Blank text is not embeddable")
    }

    // MARK: hybrid retrieval with a deterministic fake embedder

    func testHybridRetrievalSurfacesSemanticMatchWithoutLexicalOverlap() async throws {
        // Two items; neither shares a token with the query "invoice".
        let taxes = indexedItem(name: "annual_finance.pdf", path: "/x/annual_finance.pdf")
        let cats = indexedItem(name: "kitten_photos.zip", path: "/x/kitten_photos.zip")
        let search = StubSearchService(items: [taxes, cats])

        // Fake embedder: "invoice" and the finance doc map to the same direction;
        // the cat archive points orthogonally.
        let embedder = FakeEmbedder(map: [
            "invoice": [1, 0],
            "annual_finance.pdf": [1, 0],
            "kitten_photos.zip": [0, 1]
        ])
        let vectors = try makeIndex()
        try await vectors.upsertVector(VectorRecord(itemID: taxes.id, modelID: embedder.modelID, vector: [1, 0]))
        try await vectors.upsertVector(VectorRecord(itemID: cats.id, modelID: embedder.modelID, vector: [0, 1]))

        let lexicalOnly = DefaultRetrievalService(searchService: search)
        let hybrid = DefaultRetrievalService(
            searchService: search, vectorIndex: vectors, embedder: embedder, semanticWeight: 0.6
        )

        let lexical = try await lexicalOnly.retrieve(RetrievalQuery(text: "invoice"))
        XCTAssertFalse(lexical.items.contains { $0.item.id == taxes.id && $0.score > 0 },
                       "Lexical search alone shouldn't rank the finance doc for 'invoice'")

        let semantic = try await hybrid.retrieve(RetrievalQuery(text: "invoice"))
        let finance = try XCTUnwrap(semantic.items.first { $0.item.id == taxes.id })
        XCTAssertGreaterThan(finance.score, 0, "Semantic retrieval surfaces the related doc")
        XCTAssertTrue(finance.explanations.contains("Semantically related."))
        XCTAssertEqual(semantic.items.first?.item.id, taxes.id, "Semantic match ranks above the unrelated item")
    }
}

// MARK: - test doubles

private func indexedItem(name: String, path: String) -> IndexedItem {
    IndexedItem(currentPath: path, displayName: name, kind: .file,
                importedAt: Date(timeIntervalSince1970: 1_800_000_000), status: .indexedOnly)
}

private final class StubSearchService: SearchService, @unchecked Sendable {
    private let items: [IndexedItem]
    init(items: [IndexedItem]) { self.items = items }
    func index(_ item: IndexedItem) async throws {}
    func update(_ item: IndexedItem) async throws {}
    func search(_ query: SearchQuery) async throws -> SearchResults {
        // Mimic the FTS candidate set: empty text returns everything.
        let text = query.text.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered = text.isEmpty ? items : items.filter {
            $0.displayName.lowercased().contains(text) || $0.currentPath.lowercased().contains(text)
        }
        return SearchResults(items: Array(filtered.prefix(query.limit)), totalCount: filtered.count)
    }
}

private struct FakeEmbedder: TextEmbedder {
    let modelID = "fake-embed"
    let map: [String: [Float]]
    func embed(_ text: String) async -> [Float]? {
        let key = text.split(separator: " ").first.map(String.init) ?? text
        return map[text] ?? map[key]
    }
}
