import BipboxCore
import BipboxPersistence
import XCTest

/// The incremental-rescan engine: a second scan over unchanged content does no
/// work (no FTS writes, no embeddings, no capture events); changed content is
/// re-extracted + re-embedded; vanished files are marked missing; items the
/// unit model no longer accounts for are dropped from the index.
final class IncrementalRescanTests: XCTestCase {
    private var root: URL!
    private var dataDir: URL!
    private var permissionID: UUID!
    private var permissionStore: MockPermissionStore!
    private var searchService: SQLiteSearchIndex!
    private var vectorIndex: CountingVectorIndex!
    private var knowledgeStore: MockKnowledgeStore!

    override func setUp() async throws {
        let fm = FileManager.default
        root = fm.temporaryDirectory.appendingPathComponent("rescan-root-\(UUID().uuidString)", isDirectory: true)
        dataDir = fm.temporaryDirectory.appendingPathComponent("rescan-data-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root.appendingPathComponent("Reports"), withIntermediateDirectories: true)
        try "energy audit notes".write(to: root.appendingPathComponent("notes.md"), atomically: true, encoding: .utf8)
        try "march incident report".write(
            to: root.appendingPathComponent("Reports/march.md"), atomically: true, encoding: .utf8)

        permissionID = UUID()
        permissionStore = MockPermissionStore()
        try await permissionStore.save(
            PermissionRecord(id: permissionID, scope: .watchedFolder, url: root, state: .granted))
        searchService = try SQLiteSearchIndex(directoryURL: dataDir)
        vectorIndex = CountingVectorIndex()
        knowledgeStore = MockKnowledgeStore()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: dataDir)
    }

    private func makeScanner(embedder: TextEmbedder = ConstantEmbedder()) -> DefaultColdStartScanner {
        DefaultColdStartScanner(
            permissionStore: permissionStore,
            inspector: FileSystemItemInspector(),
            knowledgeStore: knowledgeStore,
            searchService: searchService,
            metadataExtractionService: DefaultMetadataExtractionService(),
            vectorIndex: vectorIndex,
            embedder: embedder
        )
    }

    private func scan(_ scanner: DefaultColdStartScanner) async throws -> ColdStartScanResult {
        try await scanner.scan(
            ColdStartScanRequest(permissionRecordID: permissionID, recursive: true, receivedAt: TestClock.now))
    }

    private func item(named name: String) async throws -> IndexedItem? {
        let results = try await searchService.search(SearchQuery(text: "", limit: 1000))
        return results.items.first { $0.displayName == name }
    }

    func testSecondScanOverUnchangedTreeDoesNoWork() async throws {
        let scanner = makeScanner()
        _ = try await scan(scanner)
        let upsertsAfterFirst = await vectorIndex.upsertCount
        let eventsAfterFirst = knowledgeStore.captureEvents.count
        XCTAssertGreaterThan(upsertsAfterFirst, 0)

        let second = try await scan(scanner)

        let upsertsAfterSecond = await vectorIndex.upsertCount
        XCTAssertEqual(upsertsAfterSecond, upsertsAfterFirst, "unchanged items must not re-embed")
        XCTAssertEqual(knowledgeStore.captureEvents.count, eventsAfterFirst,
                       "unchanged items must not append capture events")
        XCTAssertEqual(second.failures, [])
    }

    func testModifiedFileIsReextractedAndReembedded() async throws {
        let scanner = makeScanner()
        _ = try await scan(scanner)
        let upsertsAfterFirst = await vectorIndex.upsertCount

        try "completely new content about solar panels"
            .write(to: root.appendingPathComponent("notes.md"), atomically: true, encoding: .utf8)
        _ = try await scan(scanner)

        let maybeNotes = try await item(named: "notes.md")
        let notes = try XCTUnwrap(maybeNotes)
        XCTAssertEqual(notes.extractedText?.contains("solar panels"), true, "changed content is re-extracted")
        let upsertsAfterSecond = await vectorIndex.upsertCount
        XCTAssertGreaterThan(upsertsAfterSecond, upsertsAfterFirst, "changed content is re-embedded")
    }

    func testModifiedFileWithUnreadyEmbedderDropsStaleVector() async throws {
        _ = try await scan(makeScanner())
        let maybeNotes = try await item(named: "notes.md")
        let notes = try XCTUnwrap(maybeNotes)
        let hadVector = await vectorIndex.contains(itemID: notes.id)
        XCTAssertTrue(hadVector)

        try "edited while the model is not provisioned"
            .write(to: root.appendingPathComponent("notes.md"), atomically: true, encoding: .utf8)
        _ = try await scan(makeScanner(embedder: NeverReadyEmbedder()))

        let stillHasVector = await vectorIndex.contains(itemID: notes.id)
        XCTAssertFalse(stillHasVector,
                       "the stale vector must be dropped so backfill re-embeds the new content")
    }

    func testVanishedFileIsMarkedMissing() async throws {
        let scanner = makeScanner()
        _ = try await scan(scanner)
        try FileManager.default.removeItem(at: root.appendingPathComponent("notes.md"))

        _ = try await scan(scanner)

        let maybeNotes = try await item(named: "notes.md")
        let notes = try XCTUnwrap(maybeNotes)
        XCTAssertEqual(notes.status, .missing)
    }

    func testItemSubsumedByNewProjectIsRemovedFromIndex() async throws {
        // First scan: Reports is a collection, march.md an indexed member.
        let scanner = makeScanner()
        _ = try await scan(scanner)
        let march = try await item(named: "march.md")
        XCTAssertNotNil(march)

        // The folder becomes a PROJECT -> its internals are one unit now.
        try "// swift-tools-version: 6.0"
            .write(to: root.appendingPathComponent("Reports/Package.swift"), atomically: true, encoding: .utf8)
        _ = try await scan(scanner)

        let marchAfter = try await item(named: "march.md")
        XCTAssertNil(marchAfter, "members of a new project unit are dropped from the index")
        let maybeReports = try await item(named: "Reports")
        let reports = try XCTUnwrap(maybeReports)
        XCTAssertTrue(reports.tags.contains("unit:project"), "the folder re-classified as a project")
    }
}

private struct ConstantEmbedder: TextEmbedder {
    let modelID = "constant"
    func embed(_ text: String) async -> [Float]? { [1, 0, 0] }
}

private struct NeverReadyEmbedder: TextEmbedder {
    let modelID = "constant" // same model id: it IS the constant model, just not loaded yet
    func embed(_ text: String) async -> [Float]? { nil }
}

private actor CountingVectorIndex: VectorIndex {
    private var records: [String: VectorRecord] = [:]
    private(set) var upsertCount = 0

    func contains(itemID: UUID) -> Bool {
        records.values.contains { $0.itemID == itemID }
    }
    func upsertVector(_ record: VectorRecord) async throws {
        records["\(record.itemID):\(record.modelID)"] = record
        upsertCount += 1
    }
    func deleteVector(itemID: UUID, modelID: String) async throws {
        records["\(itemID):\(modelID)"] = nil
    }
    func nearest(to query: VectorSearchQuery) async throws -> [VectorMatch] { [] }
    func vectors(modelID: String) async throws -> [VectorRecord] {
        records.values.filter { $0.modelID == modelID }
    }
}
