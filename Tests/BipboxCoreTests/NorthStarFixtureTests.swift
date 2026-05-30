import BipboxCore
import XCTest

final class NorthStarFixtureTests: XCTestCase {
    func testSourceFixturesProduceValidSourceRecords() throws {
        let watched = SourceFixtures.watchedFolder()
        let menuBarDrop = SourceFixtures.menuBarDrop()
        let manualImport = SourceFixtures.manualImport()

        XCTAssertEqual(watched.kind, .watchedFolder)
        XCTAssertEqual(watched.url?.isFileURL, true)
        XCTAssertEqual(watched.permissionRecordID, SourceFixtures.permissionID)
        XCTAssertEqual(watched.recursivePolicy, .never)
        XCTAssertEqual(watched.lastScanSummary?.discoveredCount, 3)

        XCTAssertEqual(menuBarDrop.kind, .menuBarDrop)
        XCTAssertNil(menuBarDrop.url)
        XCTAssertEqual(menuBarDrop.indexState, .completed)

        XCTAssertEqual(manualImport.kind, .manualImport)
        XCTAssertEqual(manualImport.recursivePolicy, .never)
    }

    func testMemoryFixturesProduceSourceAwareRecords() throws {
        let source = SourceFixtures.watchedFolder()
        let item = MemoryFixtures.knowledgeItem(source: source)
        let event = MemoryFixtures.captureEvent(source: source)
        let results = MemoryFixtures.libraryResults()

        XCTAssertEqual(item.sourceID, source.id)
        XCTAssertEqual(event.sourceID, source.id)
        XCTAssertEqual(event.source, .watchedFolder)
        XCTAssertEqual(event.sourceDetail["sourceID"], source.id.uuidString)
        XCTAssertEqual(results.totalCount, 1)
        XCTAssertTrue(results.items[0].tags.contains(CaptureSource.watchedFolder.rawValue))
    }

    func testWatchedSourceFixtureDoesNotExpandFoldersByDefault() throws {
        let directory = try TemporaryDirectory()
        let fixture = try directory.createWatchedSource()

        XCTAssertEqual(fixture.sourceRecord.recursivePolicy, .never)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.topLevelFileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.topLevelFolderURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.packageURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.nestedFileURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.missingURL.path))

        XCTAssertEqual(
            fixture.topLevelCaptureURLs.map(\.lastPathComponent),
            ["quarterly-report.pdf", "Client Project", "Prototype.app"]
        )
        XCTAssertFalse(fixture.topLevelCaptureURLs.contains(fixture.nestedFileURL))
        XCTAssertTrue(fixture.recursiveCaptureURLs.contains(fixture.nestedFileURL))
    }

    func testMockSourceStoreReturnsDeterministicOrdering() async throws {
        let downloads = SourceFixtures.watchedFolder(
            id: UUID(uuidString: "40000000-0000-0000-0000-000000000001")!,
            url: URL(fileURLWithPath: "/tmp/Downloads", isDirectory: true),
            displayName: "Downloads"
        )
        let desktop = SourceFixtures.watchedFolder(
            id: UUID(uuidString: "40000000-0000-0000-0000-000000000002")!,
            url: URL(fileURLWithPath: "/tmp/Desktop", isDirectory: true),
            displayName: "Desktop"
        )
        let store = MockSourceStore(sourceRecords: [downloads, desktop])

        let names = try await store.sources().map(\.displayName)

        XCTAssertEqual(names, ["Desktop", "Downloads"])
    }
}
