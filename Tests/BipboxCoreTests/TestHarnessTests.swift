import BipboxCore
import XCTest

final class TestHarnessTests: XCTestCase {
    func testTemporaryDirectoryCreatesFileAndFolderInIsolatedLocation() throws {
        let directory = try TemporaryDirectory(name: "harness-\(UUID().uuidString)")

        let fileURL = try directory.createFile(named: "report.pdf")
        let folderURL = try directory.createFolder(named: "Project")

        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: folderURL.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
        XCTAssertTrue(fileURL.path.contains("BipboxTests"))
        XCTAssertTrue(folderURL.path.contains("BipboxTests"))
    }

    func testFolderFixtureKeepsRecursiveInspectionDisabled() {
        let profile = ItemFixtures.folderProfile()

        XCTAssertEqual(profile.kind, .folder)
        XCTAssertEqual(profile.folderChildSummary?.recursiveInspectionRequested, false)
    }

    func testMockSearchIndexesFolderItems() async throws {
        let search = MockSearchService()
        let folder = ItemFixtures.folderProfile()
        let indexed = IndexedItem(
            id: folder.id,
            currentPath: folder.url.path,
            displayName: folder.displayName,
            kind: folder.kind,
            importedAt: TestClock.now,
            status: .organized
        )

        try await search.index(indexed)
        let results = try await search.search(SearchQuery(text: "Project", kinds: [.folder]))

        XCTAssertEqual(results.items.first?.kind, .folder)
    }
}

