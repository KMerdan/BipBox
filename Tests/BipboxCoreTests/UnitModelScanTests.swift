import BipboxCore
import XCTest

/// End-to-end: a recursive cold-start scan applies the descent/collection node
/// model — projects and collections become single tagged aggregate units with
/// composed unit text, members stay individually indexed, and exact duplicates
/// are indexed but never embedded.
final class UnitModelScanTests: XCTestCase {

    func testRecursiveScanProducesUnitModel() async throws {
        let directory = try TemporaryDirectory(name: "unit-model-\(UUID().uuidString)")
        let rootURL = try directory.createFolder(named: "Root")
        _ = try directory.createFolder(named: "Root/myrepo/Sources")
        _ = try directory.createFolder(named: "Root/Reports")
        _ = try directory.createFile(named: "Root/notes.md", contents: "energy audit meeting notes")
        _ = try directory.createFile(named: "Root/myrepo/Package.swift", contents: "// swift-tools-version: 6.0")
        _ = try directory.createFile(named: "Root/myrepo/README.md", contents: "A fault tree analysis engine")
        _ = try directory.createFile(named: "Root/myrepo/Sources/main.swift", contents: "print(1)")
        _ = try directory.createFile(named: "Root/Reports/march.md", contents: "march incident report")
        _ = try directory.createFile(named: "Root/Reports/april.md", contents: "april incident report")
        // Renamed exact copy of notes.md — must dedup name-independently.
        _ = try directory.createFile(named: "Root/Reports/copy-of-notes.md", contents: "energy audit meeting notes")

        let permissionID = UUID(uuidString: "70000000-0000-0000-0000-000000000001")!
        let permissionStore = MockPermissionStore()
        try await permissionStore.save(
            PermissionRecord(id: permissionID, scope: .watchedFolder, url: rootURL, state: .granted))
        let searchService = MockSearchService()
        let vectorIndex = RecordingVectorIndex()
        let scanner = DefaultColdStartScanner(
            permissionStore: permissionStore,
            inspector: FileSystemItemInspector(),
            knowledgeStore: MockKnowledgeStore(),
            searchService: searchService,
            metadataExtractionService: DefaultMetadataExtractionService(),
            vectorIndex: vectorIndex,
            embedder: ConstantEmbedder()
        )

        _ = try await scanner.scan(
            ColdStartScanRequest(permissionRecordID: permissionID, recursive: true, receivedAt: TestClock.now))

        func item(_ name: String) -> IndexedItem? { searchService.items.first { $0.displayName == name } }

        // Project: one unit, internals not indexed, represented by composed text.
        let repo = try XCTUnwrap(item("myrepo"))
        XCTAssertTrue(repo.tags.contains("unit:project"))
        XCTAssertTrue(repo.extractedText?.contains("project: myrepo") == true)
        XCTAssertTrue(repo.extractedText?.contains("fault tree analysis") == true, "README feeds the unit text")
        XCTAssertNil(item("main.swift"), "project internals are not individual items")

        // Collection: one unit + individually indexed members tagged with its id.
        let reports = try XCTUnwrap(item("Reports"))
        XCTAssertTrue(reports.tags.contains("unit:collection"))
        XCTAssertTrue(reports.extractedText?.contains("collection: Reports") == true)
        XCTAssertTrue(reports.extractedText?.contains("march") == true, "member titles feed the unit text")
        let march = try XCTUnwrap(item("march.md"))
        XCTAssertTrue(march.tags.contains("unit:member"))
        XCTAssertTrue(march.tags.contains("collection:\(reports.id.uuidString)"),
                      "members carry their collection's item id")

        // Loose file + name-independent dedup: the renamed copy is indexed for
        // search but tagged dup and never embedded.
        XCTAssertTrue(try XCTUnwrap(item("notes.md")).tags.contains("unit:loose"))
        let dup = try XCTUnwrap(item("copy-of-notes.md"))
        XCTAssertTrue(dup.tags.contains("dup"))
        let embedded = await vectorIndex.itemIDs
        XCTAssertFalse(embedded.contains(dup.id), "duplicates are not embedded")
        XCTAssertTrue(embedded.contains(repo.id) && embedded.contains(reports.id) && embedded.contains(march.id))
    }
}

private struct ConstantEmbedder: TextEmbedder {
    let modelID = "constant"
    func embed(_ text: String) async -> [Float]? { [1, 0, 0] }
}

private actor RecordingVectorIndex: VectorIndex {
    private var records: [VectorRecord] = []
    var itemIDs: Set<UUID> { Set(records.map(\.itemID)) }
    func upsertVector(_ record: VectorRecord) async throws { records.append(record) }
    func deleteVector(itemID: UUID, modelID: String) async throws {}
    func nearest(to query: VectorSearchQuery) async throws -> [VectorMatch] { [] }
    func vectors(modelID: String) async throws -> [VectorRecord] { records }
}
