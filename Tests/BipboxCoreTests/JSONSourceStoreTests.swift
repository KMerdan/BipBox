import BipboxCore
import BipboxPersistence
import XCTest

final class JSONSourceStoreTests: XCTestCase {
    func testMissingStoreFileReturnsEmptySources() async throws {
        let directory = try TemporaryDirectory()
        let store = try JSONSourceStore(directoryURL: directory.url)

        let sources = try await store.sources()

        XCTAssertEqual(sources, [])
    }

    func testSaveUpdateRemoveAndReloadSources() async throws {
        let directory = try TemporaryDirectory()
        let store = try JSONSourceStore(directoryURL: directory.url)
        let sourceURL = try directory.createFolder(named: "Downloads")
        let source = SourceFixtures.watchedFolder(url: sourceURL, displayName: "Downloads")

        let inserted = try await store.upsert(source)
        var updated = source
        updated.displayName = "Downloads Archive"
        updated.updatedAt = TestClock.now.addingTimeInterval(60)
        let updateChange = try await store.upsert(updated)

        let reloadedStore = try JSONSourceStore(directoryURL: directory.url)
        let reloaded = try await reloadedStore.sources()
        let removed = try await reloadedStore.remove(id: source.id)
        let empty = try await reloadedStore.sources()

        XCTAssertEqual(inserted, .inserted(source))
        XCTAssertEqual(updateChange, .updated(updated))
        XCTAssertEqual(reloaded, [updated])
        XCTAssertEqual(removed, .removed(updated))
        XCTAssertEqual(empty, [])
    }

    func testSourcesAreListedDeterministically() async throws {
        let directory = try TemporaryDirectory()
        let store = try JSONSourceStore(directoryURL: directory.url)
        let downloads = SourceFixtures.watchedFolder(
            id: UUID(uuidString: "50000000-0000-0000-0000-000000000001")!,
            url: try directory.createFolder(named: "Downloads"),
            displayName: "Downloads"
        )
        let desktop = SourceFixtures.watchedFolder(
            id: UUID(uuidString: "50000000-0000-0000-0000-000000000002")!,
            url: try directory.createFolder(named: "Desktop"),
            displayName: "Desktop"
        )

        try await store.upsert(downloads)
        try await store.upsert(desktop)

        let names = try await store.sources().map(\.displayName)

        XCTAssertEqual(names, ["Desktop", "Downloads"])
    }

    func testRejectsDuplicateSourcePaths() async throws {
        let directory = try TemporaryDirectory()
        let store = try JSONSourceStore(directoryURL: directory.url)
        let sourceURL = try directory.createFolder(named: "Downloads")
        let first = SourceFixtures.watchedFolder(
            id: UUID(uuidString: "50000000-0000-0000-0000-000000000003")!,
            url: sourceURL,
            displayName: "Downloads"
        )
        let duplicate = SourceFixtures.watchedFolder(
            id: UUID(uuidString: "50000000-0000-0000-0000-000000000004")!,
            url: sourceURL,
            displayName: "Also Downloads"
        )

        try await store.upsert(first)

        do {
            try await store.upsert(duplicate)
            XCTFail("Expected duplicate path to be rejected.")
        } catch SourceStoreError.duplicatePath(let url) {
            XCTAssertEqual(url.standardizedFileURL, sourceURL.standardizedFileURL)
        }
    }

    func testInvalidJSONSurfacesExplicitStorageError() async throws {
        let directory = try TemporaryDirectory()
        let fileURL = directory.url.appendingPathComponent("sources.json", isDirectory: false)
        try Data("{ nope".utf8).write(to: fileURL)
        let store = try JSONSourceStore(directoryURL: directory.url)

        do {
            _ = try await store.sources()
            XCTFail("Expected invalid source storage error.")
        } catch SourceStoreError.invalidStorage(let url, let reason) {
            XCTAssertEqual(url, fileURL)
            XCTAssertFalse(reason.isEmpty)
        }
    }

    func testEnabledSourcesCanFilterByKind() async throws {
        let directory = try TemporaryDirectory()
        let store = try JSONSourceStore(directoryURL: directory.url)
        let watched = SourceFixtures.watchedFolder(url: try directory.createFolder(named: "Downloads"))
        let disabledManual = SourceFixtures.manualImport(enabled: false)
        let menuBarDrop = SourceFixtures.menuBarDrop()

        try await store.upsert(disabledManual)
        try await store.upsert(menuBarDrop)
        try await store.upsert(watched)

        let watchedSources = try await store.enabledSources(kind: .watchedFolder)
        let allEnabled = try await store.enabledSources(kind: nil)

        XCTAssertEqual(watchedSources.map(\.id), [watched.id])
        XCTAssertEqual(allEnabled.map(\.id), [watched.id, menuBarDrop.id])
    }
}
