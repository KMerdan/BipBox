import BipboxCore
import XCTest

final class DefaultMissingFileRecoveryServiceTests: XCTestCase {
    func testRefreshMarksMissingPathInKnowledgeAndSearch() async throws {
        let missingURL = URL(fileURLWithPath: "/tmp/bipbox-missing-\(UUID().uuidString).pdf")
        let itemID = UUID(uuidString: "68000000-0000-0000-0000-000000000001")!
        let knowledge = MockKnowledgeStore()
        let search = MockSearchService()
        try await knowledge.upsertKnowledgeItem(
            MemoryFixtures.knowledgeItem(id: itemID, url: missingURL, state: .active)
        )
        try await search.index(
            MemoryFixtures.libraryItem(id: itemID, path: missingURL.path, name: missingURL.lastPathComponent, status: .indexedOnly)
        )
        let service = DefaultMissingFileRecoveryService(
            knowledgeStore: knowledge,
            searchService: search,
            searchRemover: search,
            now: { TestClock.now }
        )

        let result = try await service.refreshStatus(itemID: itemID)

        XCTAssertEqual(result.item.state, KnowledgeItemState.missing)
        XCTAssertEqual(search.items.first?.status, .missing)
    }

    func testLocateUpdatesCurrentURLAndState() async throws {
        let directory = try TemporaryDirectory(name: "recovery-locate-\(UUID().uuidString)")
        let oldURL = URL(fileURLWithPath: "/tmp/missing.pdf")
        let newURL = try directory.createFile(named: "found.pdf")
        let itemID = UUID(uuidString: "68000000-0000-0000-0000-000000000002")!
        let knowledge = MockKnowledgeStore()
        let search = MockSearchService()
        try await knowledge.upsertKnowledgeItem(
            MemoryFixtures.knowledgeItem(id: itemID, url: oldURL, state: .missing)
        )
        try await search.index(
            MemoryFixtures.libraryItem(id: itemID, path: oldURL.path, name: "missing.pdf", status: .missing)
        )
        let service = DefaultMissingFileRecoveryService(
            knowledgeStore: knowledge,
            searchService: search,
            searchRemover: search,
            now: { TestClock.now }
        )

        let result = try await service.locate(itemID: itemID, at: newURL)

        XCTAssertEqual(result.item.currentURL, newURL)
        XCTAssertEqual(result.item.state, KnowledgeItemState.active)
        XCTAssertEqual(result.indexedItem?.currentPath, newURL.path)
        XCTAssertEqual(result.indexedItem?.status, .indexedOnly)
    }

    func testRemoveFromLibraryDoesNotDeleteRealFile() async throws {
        let directory = try TemporaryDirectory(name: "recovery-remove-\(UUID().uuidString)")
        let fileURL = try directory.createFile(named: "keep.pdf")
        let itemID = UUID(uuidString: "68000000-0000-0000-0000-000000000003")!
        let knowledge = MockKnowledgeStore()
        let search = MockSearchService()
        try await knowledge.upsertKnowledgeItem(MemoryFixtures.knowledgeItem(id: itemID, url: fileURL))
        try await search.index(MemoryFixtures.libraryItem(id: itemID, path: fileURL.path, name: fileURL.lastPathComponent))
        let service = DefaultMissingFileRecoveryService(
            knowledgeStore: knowledge,
            searchService: search,
            searchRemover: search,
            now: { TestClock.now }
        )

        try await service.removeFromLibrary(itemID: itemID)

        let archived = try await knowledge.knowledgeItem(id: itemID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertEqual(archived?.state, .archived)
        XCTAssertEqual(search.items, [])
    }

    func testReindexPreservesItemIdentity() async throws {
        let directory = try TemporaryDirectory(name: "recovery-reindex-\(UUID().uuidString)")
        let fileURL = try directory.createFile(named: "report.pdf", contents: "updated")
        let itemID = UUID(uuidString: "68000000-0000-0000-0000-000000000004")!
        let knowledge = MockKnowledgeStore()
        let search = MockSearchService()
        try await knowledge.upsertKnowledgeItem(
            MemoryFixtures.knowledgeItem(id: itemID, url: fileURL, state: .missing)
        )
        try await search.index(
            MemoryFixtures.libraryItem(id: itemID, path: fileURL.path, name: fileURL.lastPathComponent, status: .missing)
        )
        let service = DefaultMissingFileRecoveryService(
            knowledgeStore: knowledge,
            searchService: search,
            searchRemover: search,
            now: { TestClock.now.addingTimeInterval(60) }
        )

        let result = try await service.reindex(itemID: itemID)

        XCTAssertEqual(result.item.id, itemID)
        XCTAssertEqual(result.indexedItem?.id, itemID)
        XCTAssertEqual(result.indexedItem?.status, .indexedOnly)
        XCTAssertEqual(result.indexedItem?.importedAt, TestClock.now.addingTimeInterval(60))
    }
}
