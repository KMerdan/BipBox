import BipboxCore
import XCTest

final class SourceStoreContractTests: XCTestCase {
    func testUpsertFetchListAndRemoveSourceRecords() async throws {
        let store = MockSourceStore()
        let source = SourceRecord.watchedFolder(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000201")!,
            url: URL(fileURLWithPath: "/Users/example/Downloads", isDirectory: true),
            createdAt: TestClock.now
        )

        let insertChange = try await store.upsert(source)
        let fetched = try await store.source(id: source.id)
        let allSources = try await store.sources()
        let updated = SourceRecord(
            id: source.id,
            kind: source.kind,
            displayName: "Incoming",
            url: source.url,
            permissionRecordID: source.permissionRecordID,
            enabled: false,
            recursivePolicy: source.recursivePolicy,
            indexState: .completed,
            watchState: .paused,
            createdAt: source.createdAt,
            updatedAt: Date(timeIntervalSince1970: 1_800_000_300)
        )
        let updateChange = try await store.upsert(updated)
        let removeChange = try await store.remove(id: source.id)
        let remainingSources = try await store.sources()

        XCTAssertEqual(insertChange, .inserted(source))
        XCTAssertEqual(fetched, source)
        XCTAssertEqual(allSources, [source])
        XCTAssertEqual(updateChange, .updated(updated))
        XCTAssertEqual(removeChange, .removed(updated))
        XCTAssertEqual(remainingSources, [])
    }

    func testRemoveMissingSourceThrowsExplicitError() async throws {
        let store = MockSourceStore()
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000202")!

        do {
            _ = try await store.remove(id: id)
            XCTFail("Expected missing source error.")
        } catch let error as SourceStoreError {
            XCTAssertEqual(error, .missingSource(id))
        }
    }

    func testDuplicatePathUsesStandardizedFileURL() async throws {
        let store = MockSourceStore()
        let first = SourceRecord.watchedFolder(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000203")!,
            url: URL(fileURLWithPath: "/Users/example/Downloads", isDirectory: true),
            createdAt: TestClock.now
        )
        let duplicate = SourceRecord.watchedFolder(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000204")!,
            url: URL(fileURLWithPath: "/Users/example/Documents/../Downloads", isDirectory: true),
            createdAt: TestClock.now
        )

        try await store.upsert(first)

        do {
            _ = try await store.upsert(duplicate)
            XCTFail("Expected duplicate path error.")
        } catch let error as SourceStoreError {
            XCTAssertEqual(error, .duplicatePath(duplicate.url!))
        }
    }

    func testInvalidURLThrowsExplicitError() async throws {
        let store = MockSourceStore()
        let url = URL(string: "https://example.com/file.pdf")!
        let source = SourceRecord(
            kind: .watchedFolder,
            displayName: "Remote",
            url: url,
            createdAt: TestClock.now,
            updatedAt: TestClock.now
        )

        do {
            _ = try await store.upsert(source)
            XCTFail("Expected invalid URL error.")
        } catch let error as SourceStoreError {
            XCTAssertEqual(error, .invalidURL(url))
        }
    }

    func testEnabledSourcesExcludeDisabledSourcesAndCanFilterByKind() async throws {
        let store = MockSourceStore()
        let downloads = SourceRecord.watchedFolder(
            url: URL(fileURLWithPath: "/Users/example/Downloads", isDirectory: true),
            createdAt: TestClock.now
        )
        let disabledDesktop = SourceRecord.watchedFolder(
            url: URL(fileURLWithPath: "/Users/example/Desktop", isDirectory: true),
            enabled: false,
            createdAt: TestClock.now
        )
        let menuBar = SourceRecord.menuBarDrop(createdAt: TestClock.now)

        try await store.upsert(downloads)
        try await store.upsert(disabledDesktop)
        try await store.upsert(menuBar)

        let allEnabled = try await store.enabledSources(kind: nil)
        let watchedEnabled = try await store.enabledSources(kind: .watchedFolder)

        XCTAssertEqual(Set(allEnabled.map(\.id)), Set([downloads.id, menuBar.id]))
        XCTAssertEqual(watchedEnabled.map(\.id), [downloads.id])
    }

    func testSourceStoreContractDoesNotExposeBookmarkData() async throws {
        let store = MockSourceStore()
        let permissionID = UUID(uuidString: "00000000-0000-0000-0000-000000000205")!
        let source = SourceRecord.watchedFolder(
            url: URL(fileURLWithPath: "/Users/example/Downloads", isDirectory: true),
            permissionRecordID: permissionID,
            createdAt: TestClock.now
        )

        try await store.upsert(source)
        let fetchedSource = try await store.source(id: source.id)
        let fetched = try XCTUnwrap(fetchedSource)

        XCTAssertEqual(fetched.permissionRecordID, permissionID)
        XCTAssertNil(fetched.metadata["bookmarkData"])
    }
}
