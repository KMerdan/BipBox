import BipboxAppSupport
import BipboxCore
import BipboxWorkspaceUI
import XCTest

/// The indexing status line: rate-based ETA math, backfill progress reporting,
/// and scan progress flowing through the source-lifecycle coordinator.
final class IndexingProgressTests: XCTestCase {

    // MARK: - ETA math (pure)

    func testEtaIsWithheldUntilThereIsSignal() {
        let start = Date()
        let early = IndexingActivity(kind: .embedding, completed: 2, total: 100, startedAt: start)
        XCTAssertNil(early.etaDescription(now: start.addingTimeInterval(10)), "needs >= 5 items done")
        let instant = IndexingActivity(kind: .embedding, completed: 50, total: 100, startedAt: start)
        XCTAssertNil(instant.etaDescription(now: start.addingTimeInterval(1)), "needs >= 2s elapsed")
    }

    func testEtaScalesWithRate() {
        let start = Date()
        // 100 of 700 in 60s -> 6 min remaining.
        let activity = IndexingActivity(kind: .scanning(sourceName: "Downloads"),
                                        completed: 100, total: 700, startedAt: start)
        XCTAssertEqual(activity.etaDescription(now: start.addingTimeInterval(60)), "~6 min left")
        // 6000 of 6050 after an hour (~1.7/s) -> ~30s remaining.
        let nearlyDone = IndexingActivity(kind: .embedding, completed: 6000, total: 6050, startedAt: start)
        XCTAssertEqual(nearlyDone.etaDescription(now: start.addingTimeInterval(3600)), "less than a minute left")
        // 100 of 10100 in 60s -> 100 minutes -> hours form.
        let long = IndexingActivity(kind: .embedding, completed: 100, total: 10100, startedAt: start)
        XCTAssertEqual(long.etaDescription(now: start.addingTimeInterval(60)), "~1 hr 40 min left")
    }

    func testStatusLineNamesTheWork() {
        let start = Date()
        let scan = IndexingActivity(kind: .scanning(sourceName: "Downloads"),
                                    completed: 100, total: 700, startedAt: start)
        XCTAssertEqual(scan.statusLine(now: start.addingTimeInterval(60)),
                       "Indexing Downloads · 100 of 700 · ~6 min left")
        let embed = IndexingActivity(kind: .embedding, completed: 1, total: 9, startedAt: start)
        XCTAssertEqual(embed.statusLine(now: start), "Embedding for semantic search · 1 of 9")
    }

    // MARK: - backfill reports (processed, total)

    func testBackfillReportsProgressWithUpfrontTotal() async throws {
        let items = (0..<4).map { index in
            IndexedItem(currentPath: "/tmp/file\(index).md", displayName: "file\(index).md",
                        kind: .file, importedAt: Date(), extractedText: "text \(index)", status: .indexedOnly)
        }
        let service = DefaultEmbeddingBackfillService(
            searchService: StaticSearch(items),
            embedder: UnitEmbedder(),
            vectorIndex: SinkVectorIndex())

        let recorder = ProgressRecorder()
        let embedded = await service.backfill(limit: 100) { processed, total in
            await recorder.record((processed, total))
        }

        XCTAssertEqual(embedded, 4)
        let updates = await recorder.updates
        XCTAssertEqual(updates.first?.1, 4, "total known up front")
        XCTAssertEqual(updates.map(\.0), [0, 1, 2, 3, 4], "monotonic processed counts")
    }

    // MARK: - scan progress flows through the coordinator

    func testCoordinatorForwardsScanProgressWithSourceName() async throws {
        let directory = try TemporaryDirectory(name: "scan-progress-\(UUID().uuidString)")
        let root = try directory.createFolder(named: "Stuff")
        _ = try directory.createFile(named: "Stuff/a.md", contents: "alpha")
        _ = try directory.createFile(named: "Stuff/b.md", contents: "beta")

        let permissionStore = MockPermissionStore()
        let sourceStore = MockSourceStore()
        let scanner = DefaultColdStartScanner(
            permissionStore: permissionStore,
            inspector: FileSystemItemInspector(),
            knowledgeStore: MockKnowledgeStore(),
            searchService: MockSearchService())
        let coordinator = DefaultSourceLifecycleCoordinator(
            permissionStore: permissionStore, sourceStore: sourceStore, scanner: scanner)

        let permission = SourceFixtures.permissionRecord(id: UUID(), url: root)
        let source = SourceFixtures.watchedFolder(
            id: UUID(), url: root, displayName: "Stuff",
            permissionRecordID: permission.id, recursivePolicy: .always)
        try await permissionStore.save(permission)
        try await sourceStore.upsert(source)

        let recorder = ScanProgressRecorder()
        await coordinator.setScanProgress { name, progress in
            await recorder.record(name: name, progress: progress)
        }
        _ = try await coordinator.scanSource(id: source.id)

        let names = await recorder.names
        let phases = await recorder.phases
        let totals = await recorder.totals
        XCTAssertTrue(names.allSatisfy { $0 == "Stuff" }, "progress carries the source display name")
        XCTAssertEqual(phases.first, .preparing)
        XCTAssertEqual(phases.last, .completed)
        XCTAssertTrue(totals.contains { ($0 ?? 0) >= 2 }, "total candidate count is known during scanning")
    }
}

private actor ProgressRecorder {
    private(set) var updates: [(Int, Int)] = []
    func record(_ update: (Int, Int)) { updates.append(update) }
}

private actor ScanProgressRecorder {
    private(set) var names: [String] = []
    private(set) var phases: [ColdStartScanPhase] = []
    private(set) var totals: [Int?] = []
    func record(name: String, progress: ColdStartScanProgress) {
        names.append(name)
        phases.append(progress.phase)
        totals.append(progress.totalCount)
    }
}

private struct UnitEmbedder: TextEmbedder {
    let modelID = "unit"
    func embed(_ text: String) async -> [Float]? { [1, 0] }
}

private final class StaticSearch: SearchService, @unchecked Sendable {
    private let items: [IndexedItem]
    init(_ items: [IndexedItem]) { self.items = items }
    func index(_ item: IndexedItem) async throws {}
    func update(_ item: IndexedItem) async throws {}
    func search(_ query: SearchQuery) async throws -> SearchResults {
        SearchResults(items: Array(items.prefix(query.limit)), totalCount: items.count)
    }
}

private actor SinkVectorIndex: VectorIndex {
    func upsertVector(_ record: VectorRecord) async throws {}
    func deleteVector(itemID: UUID, modelID: String) async throws {}
    func nearest(to query: VectorSearchQuery) async throws -> [VectorMatch] { [] }
    func vectors(modelID: String) async throws -> [VectorRecord] { [] }
}
