import BipboxCore
import BipboxMacOSAdapters
import XCTest

final class SecurityScopedBookmarkPermissionStoreTests: XCTestCase {
    func testSavesAndQueriesLibraryRootPermission() async throws {
        let directory = try TemporaryDirectory(name: "permissions-library-\(UUID().uuidString)")
        let targetURL = try directory.createFolder(named: "Library")
        let resolver = MockBookmarkResolver()
        let store = try SecurityScopedBookmarkPermissionStore(directoryURL: directory.url, resolver: resolver)
        let record = PermissionRecord(scope: .libraryRoot, url: targetURL, state: .missing)

        try await store.save(record)
        let records = try await store.records(scope: .libraryRoot)

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.scope, .libraryRoot)
        XCTAssertEqual(records.first?.url, targetURL)
        XCTAssertEqual(records.first?.state, .granted)
        XCTAssertNotNil(records.first?.bookmarkData)
    }

    func testStoresWatchedFolderSeparatelyFromLibraryRoot() async throws {
        let directory = try TemporaryDirectory(name: "permissions-scopes-\(UUID().uuidString)")
        let libraryURL = try directory.createFolder(named: "Library")
        let watchedURL = try directory.createFolder(named: "Downloads")
        let store = try SecurityScopedBookmarkPermissionStore(directoryURL: directory.url, resolver: MockBookmarkResolver())

        try await store.save(PermissionRecord(scope: .libraryRoot, url: libraryURL, state: .missing))
        try await store.save(PermissionRecord(scope: .watchedFolder, url: watchedURL, state: .missing))

        let libraryRecords = try await store.records(scope: .libraryRoot)
        let watchedRecords = try await store.records(scope: .watchedFolder)

        XCTAssertEqual(libraryRecords.map(\.url), [libraryURL])
        XCTAssertEqual(watchedRecords.map(\.url), [watchedURL])
    }

    func testStaleBookmarkStateIsReported() async throws {
        let directory = try TemporaryDirectory(name: "permissions-stale-\(UUID().uuidString)")
        let targetURL = try directory.createFolder(named: "Downloads")
        let resolver = MockBookmarkResolver(staleURLs: [targetURL])
        let store = try SecurityScopedBookmarkPermissionStore(directoryURL: directory.url, resolver: resolver)

        try await store.save(PermissionRecord(scope: .watchedFolder, url: targetURL, state: .missing))
        let records = try await store.records(scope: nil)

        XCTAssertEqual(records.first?.state, .stale)
        XCTAssertEqual(records.first?.message, "Bookmark is stale and should be refreshed.")
    }

    func testMissingBookmarkStateIsReportedWhenResolveFails() async throws {
        let directory = try TemporaryDirectory(name: "permissions-missing-\(UUID().uuidString)")
        let targetURL = try directory.createFolder(named: "Downloads")
        let resolver = MockBookmarkResolver(failingResolveURLs: [targetURL])
        let store = try SecurityScopedBookmarkPermissionStore(directoryURL: directory.url, resolver: resolver)

        try await store.save(PermissionRecord(scope: .watchedFolder, url: targetURL, state: .missing))
        let records = try await store.records(scope: nil)

        XCTAssertEqual(records.first?.state, .missing)
        XCTAssertTrue(records.first?.message?.contains("resolve failed") == true)
    }

    func testRemovePermissionPersistsAcrossReopen() async throws {
        let directory = try TemporaryDirectory(name: "permissions-remove-\(UUID().uuidString)")
        let targetURL = try directory.createFolder(named: "Downloads")
        let resolver = MockBookmarkResolver()
        let store = try SecurityScopedBookmarkPermissionStore(directoryURL: directory.url, resolver: resolver)
        let id = UUID(uuidString: "40000000-0000-0000-0000-000000000001")!

        try await store.save(PermissionRecord(id: id, scope: .watchedFolder, url: targetURL, state: .missing))
        try await store.remove(id: id)

        let reopened = try SecurityScopedBookmarkPermissionStore(directoryURL: directory.url, resolver: resolver)
        let records = try await reopened.records(scope: nil)

        XCTAssertEqual(records, [])
    }

    func testExistingBookmarkDataIsPreservedOnSave() async throws {
        let directory = try TemporaryDirectory(name: "permissions-existing-bookmark-\(UUID().uuidString)")
        let targetURL = try directory.createFolder(named: "Downloads")
        let resolver = MockBookmarkResolver()
        let store = try SecurityScopedBookmarkPermissionStore(directoryURL: directory.url, resolver: resolver)
        let bookmarkData = MockBookmarkResolver.bookmarkData(for: targetURL)

        try await store.save(
            PermissionRecord(
                scope: .watchedFolder,
                url: targetURL,
                state: .granted,
                bookmarkData: bookmarkData
            )
        )
        let records = try await store.records(scope: nil)

        XCTAssertEqual(records.first?.bookmarkData, bookmarkData)
        XCTAssertEqual(resolver.createdBookmarkURLsSnapshot, [])
    }

    func testPermissionMetadataSurvivesSaveResolveAndReopen() async throws {
        let directory = try TemporaryDirectory(name: "permissions-metadata-\(UUID().uuidString)")
        let targetURL = try directory.createFolder(named: "Downloads")
        let resolver = MockBookmarkResolver()
        let store = try SecurityScopedBookmarkPermissionStore(directoryURL: directory.url, resolver: resolver)

        try await store.save(
            PermissionRecord(
                scope: .watchedFolder,
                url: targetURL,
                state: .missing,
                metadata: ["captureLocation": "downloads"]
            )
        )

        let reopened = try SecurityScopedBookmarkPermissionStore(directoryURL: directory.url, resolver: resolver)
        let records = try await reopened.records(scope: .watchedFolder)

        XCTAssertEqual(records.first?.metadata["captureLocation"], "downloads")
        XCTAssertEqual(records.first?.state, .granted)
    }

    func testLegacyPermissionRecordDecodesWithEmptyMetadata() throws {
        let json = """
        {
          "id": "40000000-0000-0000-0000-000000000002",
          "scope": "watchedFolder",
          "url": "file:\\/\\/\\/tmp\\/Downloads",
          "state": "missing"
        }
        """

        let record = try JSONDecoder().decode(PermissionRecord.self, from: Data(json.utf8))

        XCTAssertEqual(record.metadata, [:])
        XCTAssertEqual(record.url.path, "/tmp/Downloads")
    }
}

private final class MockBookmarkResolver: BookmarkResolving, @unchecked Sendable {
    static func bookmarkData(for url: URL) -> Data {
        Data(url.absoluteString.utf8)
    }

    private let staleURLs: Set<URL>
    private let failingResolveURLs: Set<URL>
    private let lock = NSLock()
    private var createdBookmarkURLs: [URL] = []

    var createdBookmarkURLsSnapshot: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return createdBookmarkURLs
    }

    init(staleURLs: Set<URL> = [], failingResolveURLs: Set<URL> = []) {
        self.staleURLs = staleURLs
        self.failingResolveURLs = failingResolveURLs
    }

    func makeBookmarkData(for url: URL) throws -> Data {
        lock.lock()
        createdBookmarkURLs.append(url)
        lock.unlock()
        return Self.bookmarkData(for: url)
    }

    func resolveBookmarkData(_ data: Data) throws -> BookmarkResolution {
        guard
            let string = String(data: data, encoding: .utf8),
            let url = URL(string: string)
        else {
            throw MockBookmarkError.resolveFailed
        }

        if failingResolveURLs.contains(url) {
            throw MockBookmarkError.resolveFailed
        }

        return BookmarkResolution(url: url, isStale: staleURLs.contains(url))
    }
}

private enum MockBookmarkError: Error, LocalizedError {
    case resolveFailed

    var errorDescription: String? {
        "resolve failed"
    }
}
