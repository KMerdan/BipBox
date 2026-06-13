import BipboxCore
import BipboxPersistence
import XCTest

/// Exercises the embedding-model provisioning lifecycle and its effect on retrieval
/// WITHOUT a real model download — covers the gap opened by the MLX embedder:
///   - `embed` returns nil until the model is provisioned (no silent download),
///   - retrieval degrades to lexical until ready, then gains the semantic boost,
///   - the provisioning status transitions needsDownload → (progress) → ready.
final class EmbedderProvisioningTests: XCTestCase {

    func testEmbedReturnsNilUntilProvisioned() async throws {
        let embedder = ScriptedProvisioningEmbedder(map: ["invoice": [1, 0]])
        let before = await embedder.embed("invoice")
        XCTAssertNil(before, "embed must return nil before provisioning — no silent download")

        let status = await embedder.prepare { _ in }
        XCTAssertEqual(status, .ready)

        let after = await embedder.embed("invoice")
        XCTAssertEqual(after, [1, 0], "embed works once provisioned")
    }

    func testProvisioningStatusTransitionsAndReportsProgress() async throws {
        let embedder = ScriptedProvisioningEmbedder(map: [:], steps: [0.3, 0.6, 1.0])
        let initial = await embedder.provisioningStatus()
        XCTAssertEqual(initial, .needsDownload)

        let collector = ProgressCollector()
        let final = await embedder.prepare { collector.add($0) }
        XCTAssertEqual(final, .ready)
        XCTAssertEqual(collector.values, [0.3, 0.6, 1.0], "progress is reported during prepare")
        let afterStatus = await embedder.provisioningStatus()
        XCTAssertEqual(afterStatus, .ready)
    }

    func testNLEmbedderNeverNeedsDownload() async {
        let status = await NLEmbeddingTextEmbedder().provisioningStatus()
        switch status {
        case .needsDownload, .downloading:
            XCTFail("The on-device NL embedder ships with the OS — it never downloads")
        case .ready, .failed:
            break  // .ready when the model is present; .failed if the OS lacks it
        }
    }

    func testRetrievalFallsBackToLexicalUntilProvisionedThenSemantic() async throws {
        let finance = indexedItem(name: "annual_finance.pdf", path: "/x/annual_finance.pdf")
        let cats = indexedItem(name: "kitten_photos.zip", path: "/x/kitten_photos.zip")
        let search = StubSearch([finance, cats])
        let embedder = ScriptedProvisioningEmbedder(map: [
            "invoice": [1, 0], "annual_finance.pdf": [1, 0], "kitten_photos.zip": [0, 1]
        ])
        let vectors = try makeIndex()
        try await vectors.upsertVector(VectorRecord(itemID: finance.id, modelID: embedder.modelID, vector: [1, 0]))
        try await vectors.upsertVector(VectorRecord(itemID: cats.id, modelID: embedder.modelID, vector: [0, 1]))

        let retrieval = DefaultRetrievalService(
            searchService: search, vectorIndex: vectors, embedder: embedder, semanticWeight: 0.6
        )

        // Not yet provisioned: embed→nil → no semantic boost (graceful lexical fallback, no crash).
        let before = try await retrieval.retrieve(RetrievalQuery(text: "invoice"))
        XCTAssertFalse(
            before.items.contains { $0.item.id == finance.id && $0.explanations.contains("Semantically related.") },
            "No semantic boost before the model is provisioned"
        )

        // Provision, then the same query gains the semantic boost.
        _ = await embedder.prepare { _ in }
        let after = try await retrieval.retrieve(RetrievalQuery(text: "invoice"))
        let surfaced = try XCTUnwrap(after.items.first { $0.item.id == finance.id })
        XCTAssertTrue(surfaced.explanations.contains("Semantically related."),
                      "Semantic boost appears once the model is provisioned")
    }

    private func makeIndex() throws -> SQLiteVectorIndex {
        try SQLiteVectorIndex(directoryURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("bipbox-prov-\(UUID().uuidString)", isDirectory: true))
    }
}

// MARK: - test doubles

/// Mirrors the real MLXTextEmbedder lifecycle: needs an explicit `prepare()`, and
/// `embed` returns nil until then.
private actor ScriptedProvisioningEmbedder: TextEmbedder, EmbedderProvisioning {
    let modelID = "scripted-embed"
    private let map: [String: [Float]]
    private let steps: [Double]
    private var ready = false

    init(map: [String: [Float]], steps: [Double] = [0.5, 1.0]) {
        self.map = map
        self.steps = steps
    }

    func provisioningStatus() async -> EmbedderModelStatus { ready ? .ready : .needsDownload }

    @discardableResult
    func prepare(progress: @Sendable @escaping (Double) -> Void) async -> EmbedderModelStatus {
        for step in steps { progress(step) }
        ready = true
        return .ready
    }

    func embed(_ text: String) async -> [Float]? {
        guard ready else { return nil }
        let key = text.split(separator: " ").first.map(String.init) ?? text
        return map[text] ?? map[key]
    }
}

private final class ProgressCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Double] = []
    var values: [Double] { lock.lock(); defer { lock.unlock() }; return storage }
    func add(_ value: Double) { lock.lock(); storage.append(value); lock.unlock() }
}

private func indexedItem(name: String, path: String) -> IndexedItem {
    IndexedItem(currentPath: path, displayName: name, kind: .file,
                importedAt: Date(timeIntervalSince1970: 1_800_000_000), status: .indexedOnly)
}

private final class StubSearch: SearchService, @unchecked Sendable {
    private let items: [IndexedItem]
    init(_ items: [IndexedItem]) { self.items = items }
    func index(_ item: IndexedItem) async throws {}
    func update(_ item: IndexedItem) async throws {}
    func search(_ query: SearchQuery) async throws -> SearchResults {
        let text = query.text.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered = text.isEmpty ? items : items.filter {
            $0.displayName.lowercased().contains(text) || $0.currentPath.lowercased().contains(text)
        }
        return SearchResults(items: Array(filtered.prefix(query.limit)), totalCount: filtered.count)
    }
}
