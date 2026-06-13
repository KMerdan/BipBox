import BipboxAppSupport
import BipboxCore
import BipboxPersistence
import SQLite3
import XCTest

/// Watcher arrivals trigger a DEBOUNCED source rescan (unit-model
/// reclassification) on top of the immediate per-file intake (rules).
final class WatcherRescanDebounceTests: XCTestCase {

    func testArrivalsTriggerOneDebouncedRescanPerSource() async throws {
        let directory = try TemporaryDirectory(name: "watch-debounce-\(UUID().uuidString)")
        let downloadsURL = try directory.createFolder(named: "Downloads")
        let permissionStore = MockPermissionStore()
        let sourceStore = MockSourceStore()
        let permission = SourceFixtures.permissionRecord(id: UUID(), url: downloadsURL)
        let source = SourceFixtures.watchedFolder(
            id: UUID(), url: downloadsURL, displayName: "Downloads",
            permissionRecordID: permission.id, watchState: .stopped)
        try await permissionStore.save(permission)
        try await sourceStore.upsert(source)

        let automation = WatchFolderAutomationService(
            permissionStore: permissionStore,
            sourceStore: sourceStore,
            intakeService: MockIntakeService(),
            appSettingsStore: MockAppSettingsStore(),
            rescanDebounceNanoseconds: 150_000_000 // 0.15s for the test
        )
        let rescans = RescanRecorder()
        await automation.setRescanHandler { id in await rescans.record(id) }
        try await automation.reloadWatchedFolders()

        // A burst of arrivals across two poll ticks -> ONE rescan after quiet.
        _ = try directory.createFile(named: "Downloads/a.pdf")
        _ = try await automation.scanOnce(receivedAt: TestClock.now)
        _ = try directory.createFile(named: "Downloads/b.pdf")
        _ = try await automation.scanOnce(receivedAt: TestClock.now.addingTimeInterval(1))

        var calls = await rescans.calls
        XCTAssertTrue(calls.isEmpty, "rescan must wait for the debounce window")
        try await Task.sleep(nanoseconds: 600_000_000)
        calls = await rescans.calls
        XCTAssertEqual(calls, [source.id], "one rescan for the burst, keyed by source id")

        // A scan tick with NO arrivals schedules nothing further.
        _ = try await automation.scanOnce(receivedAt: TestClock.now.addingTimeInterval(2))
        try await Task.sleep(nanoseconds: 300_000_000)
        let after = await rescans.calls
        XCTAssertEqual(after.count, 1)
    }
}

private actor RescanRecorder {
    private(set) var calls: [UUID] = []
    func record(_ id: UUID) { calls.append(id) }
}

/// Data-directory-wide versioning: legacy dirs (stores but no meta.json) need a
/// full rescan; fresh and current dirs do not; newer dirs are left untouched.
final class DataDirectoryMetaTests: XCTestCase {
    private var dataDir: URL!

    override func setUpWithError() throws {
        dataDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("meta-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dataDir)
    }

    func testFreshDirectoryStartsCurrentWithoutRescan() {
        let result = DataDirectoryMetaStore.reconcile(dataDirectoryURL: dataDir)
        XCTAssertEqual(result.meta.appDataVersion, DataDirectoryMetaStore.currentVersion)
        XCTAssertFalse(result.needsFullRescan)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: DataDirectoryMetaStore.metaURL(dataDirectoryURL: dataDir).path), "meta.json is stamped")
    }

    func testLegacyDirectoryWithStoresNeedsRescan() throws {
        // A pre-versioning data dir is recognized by its existing search store.
        let searchDir = dataDir.appendingPathComponent("Search", isDirectory: true)
        try FileManager.default.createDirectory(at: searchDir, withIntermediateDirectories: true)
        try Data().write(to: searchDir.appendingPathComponent("search.sqlite"))

        let result = DataDirectoryMetaStore.reconcile(dataDirectoryURL: dataDir)
        XCTAssertTrue(result.needsFullRescan, "legacy data needs the unit-model/fingerprint rescan")

        let second = DataDirectoryMetaStore.reconcile(dataDirectoryURL: dataDir)
        XCTAssertFalse(second.needsFullRescan, "stamped after the first reconcile")
    }

    func testNewerDirectoryIsLeftUntouched() throws {
        let url = DataDirectoryMetaStore.metaURL(dataDirectoryURL: dataDir)
        let newer = DataDirectoryMeta(appDataVersion: DataDirectoryMetaStore.currentVersion + 5)
        try JSONEncoder().encode(newer).write(to: url)

        let result = DataDirectoryMetaStore.reconcile(dataDirectoryURL: dataDir)
        XCTAssertFalse(result.needsFullRescan)
        let onDisk = try JSONDecoder().decode(DataDirectoryMeta.self, from: Data(contentsOf: url))
        XCTAssertEqual(onDisk, newer, "a newer app's meta must not be downgraded")
    }
}

/// SQLite store versioning: v1 search databases gain the fingerprint column in
/// place; databases from a NEWER app version are refused, not corrupted.
final class SchemaMigrationTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("schema-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    private func executeRaw(_ sql: String, at url: URL) {
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK, String(cString: sqlite3_errmsg(db)))
        sqlite3_close(db)
    }

    func testV1SearchIndexGainsFingerprintColumnInPlace() async throws {
        // Build a v1-shaped database (no content_fingerprint, user_version=1)
        // with one existing row, exactly what a pre-upgrade data dir contains.
        let dbURL = dir.appendingPathComponent("search.sqlite")
        executeRaw("""
            CREATE TABLE indexed_items (
                id TEXT PRIMARY KEY NOT NULL, current_path TEXT NOT NULL, original_path TEXT,
                display_name TEXT NOT NULL, kind TEXT NOT NULL, uniform_type_identifier TEXT,
                size_bytes INTEGER, created_at REAL, modified_at REAL, imported_at REAL NOT NULL,
                routed_at REAL, rule_id TEXT, tags_json TEXT NOT NULL, extracted_text TEXT,
                ai_summary TEXT, status TEXT NOT NULL
            );
            CREATE VIRTUAL TABLE indexed_items_fts USING fts5(
                item_id UNINDEXED, display_name, current_path, original_path, tags, extracted_text, ai_summary);
            INSERT INTO indexed_items (id, current_path, display_name, kind, imported_at, tags_json, status)
            VALUES ('11111111-2222-3333-4444-555555555555', '/tmp/old.pdf', 'old.pdf', 'file',
                    1800000000, '[]', 'indexedOnly');
            PRAGMA user_version = 1;
            """, at: dbURL)

        let index = try SQLiteSearchIndex(directoryURL: dir)
        let version = try await index.schemaVersion()
        XCTAssertEqual(version, SQLiteSearchIndex.schemaVersion, "v1 database upgraded in place")

        // The v1 row survives, and the new column round-trips.
        let old = try await index.search(SearchQuery(text: "", limit: 10))
        XCTAssertEqual(old.items.first?.displayName, "old.pdf")
        XCTAssertNil(old.items.first?.contentFingerprint)
        var migrated = try XCTUnwrap(old.items.first)
        migrated.contentFingerprint = "21:abcdef0123456789"
        try await index.update(migrated)
        let reloaded = try await index.search(SearchQuery(text: "", limit: 10))
        XCTAssertEqual(reloaded.items.first?.contentFingerprint, "21:abcdef0123456789")
    }

    func testNewerSearchIndexIsRefused() throws {
        let dbURL = dir.appendingPathComponent("search.sqlite")
        executeRaw("PRAGMA user_version = 99;", at: dbURL)
        XCTAssertThrowsError(try SQLiteSearchIndex(directoryURL: dir)) { error in
            XCTAssertTrue("\(error)".contains("newer"), "refusal names the version problem: \(error)")
        }
    }

    func testNewerVectorIndexIsRefused() throws {
        let dbURL = dir.appendingPathComponent("vectors.sqlite")
        executeRaw("PRAGMA user_version = 99;", at: dbURL)
        XCTAssertThrowsError(try SQLiteVectorIndex(directoryURL: dir))
    }

    func testPreVersioningVectorIndexIsAdoptedInPlace() async throws {
        // user_version 0 with the identical table shape (pre-versioning build).
        let dbURL = dir.appendingPathComponent("vectors.sqlite")
        executeRaw("""
            CREATE TABLE vectors (
                item_id TEXT NOT NULL, model_id TEXT NOT NULL, dim INTEGER NOT NULL,
                vector BLOB NOT NULL, PRIMARY KEY (item_id, model_id));
            CREATE INDEX vectors_model ON vectors(model_id);
            """, at: dbURL)

        let index = try SQLiteVectorIndex(directoryURL: dir)
        let itemID = UUID()
        try await index.upsertVector(VectorRecord(itemID: itemID, modelID: "m", vector: [1, 0]))
        let stored = try await index.vectors(modelID: "m")
        XCTAssertEqual(stored.map(\.itemID), [itemID], "adopted without dropping data")
    }
}
