import BipboxAppSupport
import BipboxCore
import XCTest

final class DefaultSourceLifecycleCoordinatorTests: XCTestCase {
    func testAddWatchedFolderSavesPermissionUpsertsSourceScansAndReloadsWatcher() async throws {
        let directory = try TemporaryDirectory()
        let folderURL = try directory.createFolder(named: "Downloads")
        let permissionStore = MockPermissionStore()
        let sourceStore = MockSourceStore()
        let scanner = CapturingColdStartScanner(rootURL: folderURL)
        let watcher = CapturingSourceWatcherReloader()
        let coordinator = DefaultSourceLifecycleCoordinator(
            permissionStore: permissionStore,
            sourceStore: sourceStore,
            scanner: scanner,
            watcherReloader: watcher,
            now: { TestClock.now }
        )

        let result = try await coordinator.addWatchedFolder(
            SourceLifecycleRequest(url: folderURL, displayName: "Downloads")
        )

        let permissions = try await permissionStore.records(scope: .watchedFolder)
        let sources = try await sourceStore.sources()
        XCTAssertEqual(permissions.count, 1)
        XCTAssertEqual(sources.count, 1)
        XCTAssertEqual(result.source.url, folderURL)
        XCTAssertEqual(result.source.permissionRecordID, permissions.first?.id)
        XCTAssertEqual(result.source.indexState, .completed)
        XCTAssertEqual(result.source.watchState, .running)
        XCTAssertEqual(result.scanResult?.scannedItemCount, 2)
        XCTAssertEqual(scanner.requests.map(\.permissionRecordID), permissions.map(\.id))
        XCTAssertEqual(watcher.reloadCount, 1)
    }

    func testChangeWatchedFolderPreservesSourceIDAndUpdatesPermissionReference() async throws {
        let directory = try TemporaryDirectory()
        let oldURL = try directory.createFolder(named: "Old Downloads")
        let newURL = try directory.createFolder(named: "New Downloads")
        let oldPermission = SourceFixtures.permissionRecord(
            id: UUID(uuidString: "60000000-0000-0000-0000-000000000001")!,
            url: oldURL
        )
        let existingSource = SourceFixtures.watchedFolder(
            id: UUID(uuidString: "60000000-0000-0000-0000-000000000002")!,
            url: oldURL,
            displayName: "Old Downloads",
            permissionRecordID: oldPermission.id
        )
        let permissionStore = MockPermissionStore()
        try await permissionStore.save(oldPermission)
        let sourceStore = MockSourceStore(sourceRecords: [existingSource])
        let coordinator = DefaultSourceLifecycleCoordinator(
            permissionStore: permissionStore,
            sourceStore: sourceStore,
            scanner: CapturingColdStartScanner(rootURL: newURL),
            watcherReloader: CapturingSourceWatcherReloader(),
            now: { TestClock.now }
        )

        let result = try await coordinator.changeWatchedFolder(
            id: existingSource.id,
            to: SourceLifecycleRequest(url: newURL, displayName: "New Downloads")
        )

        let storedSource = try await sourceStore.source(id: existingSource.id)
        let updated = try XCTUnwrap(storedSource)
        XCTAssertEqual(result.source.id, existingSource.id)
        XCTAssertEqual(updated.url, newURL)
        XCTAssertNotEqual(updated.permissionRecordID, oldPermission.id)
        XCTAssertEqual(updated.createdAt, existingSource.createdAt)
    }

    func testRemoveSourceRemovesSourcePermissionAndReloadsWatcher() async throws {
        let source = SourceFixtures.watchedFolder()
        let permission = SourceFixtures.permissionRecord(id: SourceFixtures.permissionID, url: source.url!)
        let permissionStore = MockPermissionStore()
        try await permissionStore.save(permission)
        let sourceStore = MockSourceStore(sourceRecords: [source])
        let watcher = CapturingSourceWatcherReloader()
        let coordinator = DefaultSourceLifecycleCoordinator(
            permissionStore: permissionStore,
            sourceStore: sourceStore,
            watcherReloader: watcher,
            now: { TestClock.now }
        )

        let result = try await coordinator.removeSource(id: source.id, removePermission: true)

        XCTAssertEqual(result.source.id, source.id)
        let storedSource = try await sourceStore.source(id: source.id)
        let storedPermissions = try await permissionStore.records(scope: .watchedFolder)
        XCTAssertNil(storedSource)
        XCTAssertEqual(storedPermissions, [])
        XCTAssertEqual(watcher.reloadCount, 1)
    }

    func testPermissionFailureDoesNotCreateSource() async throws {
        let permissionStore = ThrowingSourcePermissionStore(error: SourceLifecycleTestError.permissionDenied)
        let sourceStore = MockSourceStore()
        let coordinator = DefaultSourceLifecycleCoordinator(
            permissionStore: permissionStore,
            sourceStore: sourceStore,
            scanner: CapturingColdStartScanner(rootURL: URL(fileURLWithPath: "/tmp", isDirectory: true)),
            watcherReloader: CapturingSourceWatcherReloader(),
            now: { TestClock.now }
        )

        do {
            _ = try await coordinator.addWatchedFolder(
                SourceLifecycleRequest(url: URL(fileURLWithPath: "/tmp/Downloads", isDirectory: true))
            )
            XCTFail("Expected permission failure.")
        } catch SourceLifecycleTestError.permissionDenied {
            let storedSources = try await sourceStore.sources()
            XCTAssertEqual(storedSources, [])
        }
    }

    func testScanFailureMarksSourceFailedAndDoesNotReloadWatcher() async throws {
        let directory = try TemporaryDirectory()
        let folderURL = try directory.createFolder(named: "Downloads")
        let sourceStore = MockSourceStore()
        let scanner = CapturingColdStartScanner(
            rootURL: folderURL,
            error: SourceLifecycleTestError.scanFailed
        )
        let watcher = CapturingSourceWatcherReloader()
        let coordinator = DefaultSourceLifecycleCoordinator(
            permissionStore: MockPermissionStore(),
            sourceStore: sourceStore,
            scanner: scanner,
            watcherReloader: watcher,
            now: { TestClock.now }
        )

        do {
            _ = try await coordinator.addWatchedFolder(SourceLifecycleRequest(url: folderURL))
            XCTFail("Expected scan failure.")
        } catch SourceLifecycleTestError.scanFailed {
            let storedSources = try await sourceStore.sources()
            let source = try XCTUnwrap(storedSources.first)
            XCTAssertEqual(source.indexState, .failed)
            XCTAssertEqual(source.watchState, .error)
            XCTAssertEqual(watcher.reloadCount, 0)
        }
    }

    func testWatcherReloadFailureMarksSourceError() async throws {
        let directory = try TemporaryDirectory()
        let folderURL = try directory.createFolder(named: "Downloads")
        let sourceStore = MockSourceStore()
        let watcher = CapturingSourceWatcherReloader(error: SourceLifecycleTestError.watcherFailed)
        let coordinator = DefaultSourceLifecycleCoordinator(
            permissionStore: MockPermissionStore(),
            sourceStore: sourceStore,
            scanner: CapturingColdStartScanner(rootURL: folderURL),
            watcherReloader: watcher,
            now: { TestClock.now }
        )

        do {
            _ = try await coordinator.addWatchedFolder(SourceLifecycleRequest(url: folderURL))
            XCTFail("Expected watcher failure.")
        } catch SourceLifecycleTestError.watcherFailed {
            let storedSources = try await sourceStore.sources()
            let source = try XCTUnwrap(storedSources.first)
            XCTAssertEqual(source.indexState, .completed)
            XCTAssertEqual(source.watchState, .error)
            XCTAssertEqual(watcher.reloadCount, 1)
        }
    }
}

private enum SourceLifecycleTestError: Error, Equatable {
    case permissionDenied
    case scanFailed
    case watcherFailed
}

private final class CapturingColdStartScanner: ColdStartScanner, @unchecked Sendable {
    private(set) var requests: [ColdStartScanRequest] = []
    var result: ColdStartScanResult
    var error: Error?

    init(rootURL: URL, error: Error? = nil) {
        self.result = ColdStartScanResult(
            sessionID: MemoryFixtures.sessionID,
            rootURL: rootURL,
            scannedItemCount: 2,
            contextCount: 1
        )
        self.error = error
    }

    func scan(
        _ request: ColdStartScanRequest,
        progress: (@Sendable (ColdStartScanProgress) async -> Void)?
    ) async throws -> ColdStartScanResult {
        requests.append(request)
        if let error {
            throw error
        }
        return result
    }
}

private final class CapturingSourceWatcherReloader: SourceWatcherReloading, @unchecked Sendable {
    private(set) var reloadCount = 0
    var error: Error?

    init(error: Error? = nil) {
        self.error = error
    }

    func reloadWatchedFolders() async throws {
        reloadCount += 1
        if let error {
            throw error
        }
    }
}

private final class ThrowingSourcePermissionStore: PermissionStore, @unchecked Sendable {
    let error: Error

    init(error: Error) {
        self.error = error
    }

    func save(_ record: PermissionRecord) async throws {
        throw error
    }

    func remove(id: UUID) async throws {
        throw error
    }

    func records(scope: PermissionScope?) async throws -> [PermissionRecord] {
        throw error
    }
}
