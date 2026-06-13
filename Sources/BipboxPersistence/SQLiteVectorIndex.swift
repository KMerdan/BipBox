import BipboxCore
import Foundation
import SQLite3

/// SQLite-backed `VectorIndex`. Stores unit vectors as BLOBs and ranks by dot
/// product (== cosine for unit vectors) with a brute-force scan — ample for a
/// personal-scale library; swap for ANN later if needed. Enforces one dimension
/// per model, matching the in-memory contract.
public actor SQLiteVectorIndex: VectorIndex {
    private let databaseURL: URL
    nonisolated(unsafe) private var database: OpaquePointer?

    public init(directoryURL: URL, fileManager: FileManager = .default) throws {
        self.databaseURL = directoryURL.appendingPathComponent("vectors.sqlite", isDirectory: false)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        var opened: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &opened) == SQLITE_OK else {
            throw VectorIndexError.backendUnavailable(Self.errorMessage(opened))
        }
        database = opened
        do {
            try Self.migrate(opened)
        } catch {
            sqlite3_close(database); database = nil
            throw error
        }
    }

    /// 1: initial versioned schema. Pre-versioning (user_version 0) databases
    /// have the identical table shape, so they are adopted in place — vectors
    /// are derived data; if a future version changes the shape, the policy is
    /// drop + rebuild via backfill, not hand-written migration.
    public static let schemaVersion = 1

    private static func migrate(_ database: OpaquePointer?) throws {
        var versionStatement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "PRAGMA user_version", -1, &versionStatement, nil) == SQLITE_OK,
              sqlite3_step(versionStatement) == SQLITE_ROW else {
            sqlite3_finalize(versionStatement)
            throw VectorIndexError.backendUnavailable(errorMessage(database))
        }
        let onDiskVersion = Int(sqlite3_column_int(versionStatement, 0))
        sqlite3_finalize(versionStatement)
        guard onDiskVersion <= schemaVersion else {
            throw VectorIndexError.backendUnavailable(
                "Vector index schema v\(onDiskVersion) is newer than this app supports (v\(schemaVersion)). Update Bipbox.")
        }

        let sql = """
        CREATE TABLE IF NOT EXISTS vectors (
            item_id TEXT NOT NULL,
            model_id TEXT NOT NULL,
            dim INTEGER NOT NULL,
            vector BLOB NOT NULL,
            PRIMARY KEY (item_id, model_id)
        );
        CREATE INDEX IF NOT EXISTS vectors_model ON vectors(model_id);
        PRAGMA user_version = \(schemaVersion);
        """
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw VectorIndexError.backendUnavailable(errorMessage(database))
        }
    }

    deinit {
        if let database { sqlite3_close(database) }
    }

    public func upsertVector(_ record: VectorRecord) async throws {
        try record.validate(expectedDimension: existingDimension(modelID: record.modelID))
        let stmt = try prepare("INSERT OR REPLACE INTO vectors (item_id, model_id, dim, vector) VALUES (?, ?, ?, ?)")
        defer { sqlite3_finalize(stmt) }
        bindText(record.itemID.uuidString, at: 1, stmt)
        bindText(record.modelID, at: 2, stmt)
        sqlite3_bind_int64(stmt, 3, Int64(record.vector.count))
        bindBlob(Self.encode(record.vector), at: 4, stmt)
        try stepDone(stmt)
    }

    public func deleteVector(itemID: UUID, modelID: String) async throws {
        let stmt = try prepare("DELETE FROM vectors WHERE item_id = ? AND model_id = ?")
        defer { sqlite3_finalize(stmt) }
        bindText(itemID.uuidString, at: 1, stmt)
        bindText(modelID, at: 2, stmt)
        try stepDone(stmt)
    }

    public func nearest(to query: VectorSearchQuery) async throws -> [VectorMatch] {
        guard let dimension = existingDimension(modelID: query.modelID) else {
            throw VectorIndexError.unsupportedModel(query.modelID)
        }
        try query.validate(expectedDimension: dimension)

        let allowed = Set(query.filters.itemIDs)
        let stmt = try prepare("SELECT item_id, vector FROM vectors WHERE model_id = ?")
        defer { sqlite3_finalize(stmt) }
        bindText(query.modelID, at: 1, stmt)

        var matches: [VectorMatch] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let idC = sqlite3_column_text(stmt, 0),
                  let itemID = UUID(uuidString: String(cString: idC)) else { continue }
            if !allowed.isEmpty && !allowed.contains(itemID) { continue }
            let vector = Self.decode(blob(at: 1, stmt))
            matches.append(VectorMatch(itemID: itemID, modelID: query.modelID, score: Self.dot(query.vector, vector)))
        }

        matches.sort { lhs, rhs in
            if lhs.score == rhs.score { return lhs.itemID.uuidString < rhs.itemID.uuidString }
            return lhs.score > rhs.score
        }
        return Array(matches.prefix(query.limit))
    }

    public func vectors(modelID: String) async throws -> [VectorRecord] {
        let stmt = try prepare("SELECT item_id, vector FROM vectors WHERE model_id = ?")
        defer { sqlite3_finalize(stmt) }
        bindText(modelID, at: 1, stmt)
        var records: [VectorRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let idC = sqlite3_column_text(stmt, 0),
                  let itemID = UUID(uuidString: String(cString: idC)) else { continue }
            records.append(VectorRecord(itemID: itemID, modelID: modelID, vector: Self.decode(blob(at: 1, stmt))))
        }
        return records
    }

    // MARK: dimension

    private func existingDimension(modelID: String) -> Int? {
        guard let stmt = try? prepare("SELECT dim FROM vectors WHERE model_id = ? LIMIT 1") else { return nil }
        defer { sqlite3_finalize(stmt) }
        bindText(modelID, at: 1, stmt)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    // MARK: vector <-> blob

    private static func encode(_ vector: [Float]) -> Data {
        vector.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    private static func decode(_ data: Data) -> [Float] {
        guard !data.isEmpty else { return [] }
        return data.withUnsafeBytes { raw in
            Array(raw.bindMemory(to: Float.self))
        }
    }

    private static func dot(_ a: [Float], _ b: [Float]) -> Double {
        guard a.count == b.count else { return 0 }
        var sum: Float = 0
        for i in a.indices { sum += a[i] * b[i] }
        return Double(sum)
    }

    // MARK: sqlite helpers

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw VectorIndexError.backendUnavailable(Self.errorMessage(database))
        }
        return stmt
    }

    private func stepDone(_ stmt: OpaquePointer?) throws {
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw VectorIndexError.backendUnavailable(Self.errorMessage(database))
        }
    }

    private func bindText(_ value: String, at index: Int32, _ stmt: OpaquePointer?) {
        sqlite3_bind_text(stmt, index, value, -1, SQLITE_TRANSIENT_VEC)
    }

    private func bindBlob(_ data: Data, at index: Int32, _ stmt: OpaquePointer?) {
        data.withUnsafeBytes { raw in
            _ = sqlite3_bind_blob(stmt, index, raw.baseAddress, Int32(raw.count), SQLITE_TRANSIENT_VEC)
        }
    }

    private func blob(at index: Int32, _ stmt: OpaquePointer?) -> Data {
        guard let bytes = sqlite3_column_blob(stmt, index) else { return Data() }
        let count = Int(sqlite3_column_bytes(stmt, index))
        return Data(bytes: bytes, count: count)
    }

    private static func errorMessage(_ database: OpaquePointer?) -> String {
        guard let database, let message = sqlite3_errmsg(database) else { return "unknown sqlite error" }
        return String(cString: message)
    }
}

private let SQLITE_TRANSIENT_VEC = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
