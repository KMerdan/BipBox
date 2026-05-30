import BipboxCore
import XCTest

final class SourceModelTests: XCTestCase {
    func testSourceEnumsRoundTripThroughJSON() throws {
        try assertRoundTrips(SourceKind.watchedFolder)
        try assertRoundTrips(SourceKind.menuBarDrop)
        try assertRoundTrips(SourceKind.manualImport)
        try assertRoundTrips(SourceKind.browserExtension)
        try assertRoundTrips(SourceKind.shareExtension)
        try assertRoundTrips(SourceKind.cli)
        try assertRoundTrips(SourceKind.agentRequest)

        try assertRoundTrips(SourceRecursivePolicy.never)
        try assertRoundTrips(SourceRecursivePolicy.explicit)
        try assertRoundTrips(SourceRecursivePolicy.always)

        try assertRoundTrips(SourceIndexState.pending)
        try assertRoundTrips(SourceIndexState.running)
        try assertRoundTrips(SourceIndexState.completed)
        try assertRoundTrips(SourceIndexState.failed)

        try assertRoundTrips(SourceWatchState.stopped)
        try assertRoundTrips(SourceWatchState.running)
        try assertRoundTrips(SourceWatchState.paused)
        try assertRoundTrips(SourceWatchState.permissionNeeded)
        try assertRoundTrips(SourceWatchState.missing)
        try assertRoundTrips(SourceWatchState.error)
    }

    func testSourceRecordRoundTripsThroughJSON() throws {
        let source = SourceRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!,
            kind: .watchedFolder,
            displayName: "Downloads",
            url: URL(fileURLWithPath: "/Users/example/Downloads", isDirectory: true),
            permissionRecordID: UUID(uuidString: "00000000-0000-0000-0000-000000000102")!,
            enabled: true,
            recursivePolicy: .never,
            indexState: .completed,
            watchState: .running,
            lastScanAt: Date(timeIntervalSince1970: 1_800_000_100),
            lastScanSummary: SourceScanSummary(
                discoveredCount: 5,
                indexedCount: 4,
                stagedCount: 1,
                organizedCount: 2,
                failedCount: 0,
                message: "Indexed 4 item(s)."
            ),
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_800_000_100),
            metadata: ["captureLocation": "downloads"]
        )

        try assertRoundTrips(source)
    }

    func testWatchedFolderDefaultsAreNonRecursiveEnabledAndUnscanned() {
        let permissionID = UUID(uuidString: "00000000-0000-0000-0000-000000000103")!
        let url = URL(fileURLWithPath: "/Users/example/Downloads", isDirectory: true)
        let source = SourceRecord.watchedFolder(
            url: url,
            permissionRecordID: permissionID,
            createdAt: TestClock.now
        )

        XCTAssertEqual(source.kind, .watchedFolder)
        XCTAssertEqual(source.displayName, "Downloads")
        XCTAssertEqual(source.url, url)
        XCTAssertEqual(source.permissionRecordID, permissionID)
        XCTAssertTrue(source.enabled)
        XCTAssertEqual(source.recursivePolicy, .never)
        XCTAssertEqual(source.indexState, .pending)
        XCTAssertEqual(source.watchState, .stopped)
        XCTAssertNil(source.lastScanAt)
        XCTAssertNil(source.lastScanSummary)
    }

    func testPermissionRecordRemainsSeparateAndIsReferencedOnlyByID() {
        let permissionID = UUID(uuidString: "00000000-0000-0000-0000-000000000104")!
        let permission = PermissionRecord(
            id: permissionID,
            scope: .watchedFolder,
            url: URL(fileURLWithPath: "/Users/example/Downloads", isDirectory: true),
            state: .granted,
            bookmarkData: Data([1, 2, 3]),
            metadata: ["permission": "bookmark"]
        )

        let source = SourceRecord.watchedFolder(
            url: permission.url,
            permissionRecordID: permission.id,
            createdAt: TestClock.now
        )

        XCTAssertEqual(source.permissionRecordID, permission.id)
        XCTAssertNil(source.metadata["permission"])
        XCTAssertFalse(source.metadata.values.contains("bookmark"))
    }

    func testCaptureSurfaceHelpersRepresentNonFolderSources() {
        let menuBar = SourceRecord.menuBarDrop(createdAt: TestClock.now)
        let manualImport = SourceRecord.manualImport(
            url: URL(fileURLWithPath: "/Users/example/Inbox", isDirectory: true),
            createdAt: TestClock.now
        )

        XCTAssertEqual(menuBar.kind, .menuBarDrop)
        XCTAssertNil(menuBar.url)
        XCTAssertNil(menuBar.permissionRecordID)
        XCTAssertEqual(menuBar.indexState, .completed)
        XCTAssertEqual(menuBar.watchState, .stopped)
        XCTAssertEqual(menuBar.recursivePolicy, .never)

        XCTAssertEqual(manualImport.kind, .manualImport)
        XCTAssertEqual(manualImport.url?.path, "/Users/example/Inbox")
        XCTAssertNil(manualImport.permissionRecordID)
        XCTAssertEqual(manualImport.recursivePolicy, .never)
    }

    private func assertRoundTrips<T: Codable & Equatable>(_ value: T) throws {
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(T.self, from: data)
        XCTAssertEqual(decoded, value)
    }
}
