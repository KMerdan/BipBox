import BipboxCore
import Foundation
import SQLite3

public enum SearchIndexError: Error, Equatable, LocalizedError {
    case invalidLimit(Int)
    case storageUnavailable(URL, String)
    case sqlite(String)

    public var errorDescription: String? {
        switch self {
        case .invalidLimit(let limit):
            "Search limit must be positive: \(limit)"
        case .storageUnavailable(let url, let reason):
            "Search index storage is unavailable at \(url.path): \(reason)"
        case .sqlite(let message):
            "SQLite search index error: \(message)"
        }
    }
}

public actor SQLiteSearchIndex: SearchService, SearchIndexRemoving {
    // 2: content_fingerprint column (incremental rescan change detection).
    public static let schemaVersion = 2

    private let databaseURL: URL
    nonisolated(unsafe) private var database: OpaquePointer?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(directoryURL: URL, fileManager: FileManager = .default) throws {
        self.databaseURL = directoryURL.appendingPathComponent("search.sqlite", isDirectory: false)
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601

        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        } catch {
            throw SearchIndexError.storageUnavailable(directoryURL, error.localizedDescription)
        }

        var openedDatabase: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &openedDatabase) == SQLITE_OK else {
            throw SearchIndexError.storageUnavailable(databaseURL, Self.errorMessage(openedDatabase))
        }
        database = openedDatabase

        do {
            try Self.migrate(database)
        } catch {
            sqlite3_close(database)
            database = nil
            throw error
        }
    }

    deinit {
        if let database {
            sqlite3_close(database)
        }
    }

    public func index(_ item: IndexedItem) async throws {
        try upsert(item)
    }

    public func update(_ item: IndexedItem) async throws {
        try upsert(item)
    }

    public func remove(id: UUID) async throws {
        let deleteItem = try prepare("DELETE FROM indexed_items WHERE id = ?")
        defer { sqlite3_finalize(deleteItem) }
        try bind(id.uuidString, at: 1, in: deleteItem)
        try stepDone(deleteItem)

        let deleteFTS = try prepare("DELETE FROM indexed_items_fts WHERE item_id = ?")
        defer { sqlite3_finalize(deleteFTS) }
        try bind(id.uuidString, at: 1, in: deleteFTS)
        try stepDone(deleteFTS)
    }

    public func search(_ query: SearchQuery) async throws -> SearchResults {
        guard query.limit > 0 else {
            throw SearchIndexError.invalidLimit(query.limit)
        }

        let candidateIDs = try candidateIDs(for: query)
        let filteredItems = try candidateIDs
            .compactMap(loadItem(id:))
            .filter { matchesFilters($0, query: query) }
        let limitedItems = Array(filteredItems.prefix(query.limit))

        return SearchResults(items: limitedItems, totalCount: filteredItems.count)
    }

    public func schemaVersion() async throws -> Int {
        let statement = try prepare("PRAGMA user_version")
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw SearchIndexError.sqlite(lastErrorMessage)
        }

        return Int(sqlite3_column_int(statement, 0))
    }

    private static func migrate(_ database: OpaquePointer?) throws {
        // Refuse data dirs written by a NEWER app version — additive migrations
        // only run forward.
        let onDiskVersion = try readUserVersion(database)
        guard onDiskVersion <= schemaVersion else {
            throw SearchIndexError.sqlite(
                "Search index schema v\(onDiskVersion) is newer than this app supports (v\(schemaVersion)). Update Bipbox.")
        }

        try execute("PRAGMA journal_mode=WAL", database: database)
        try execute(
            """
            CREATE TABLE IF NOT EXISTS indexed_items (
                id TEXT PRIMARY KEY NOT NULL,
                current_path TEXT NOT NULL,
                original_path TEXT,
                display_name TEXT NOT NULL,
                kind TEXT NOT NULL,
                uniform_type_identifier TEXT,
                size_bytes INTEGER,
                created_at REAL,
                modified_at REAL,
                imported_at REAL NOT NULL,
                routed_at REAL,
                rule_id TEXT,
                tags_json TEXT NOT NULL,
                extracted_text TEXT,
                ai_summary TEXT,
                status TEXT NOT NULL,
                content_fingerprint TEXT
            )
            """,
            database: database
        )
        // v1 -> v2: additive column (no-op on fresh databases).
        try addColumnIfMissing(
            table: "indexed_items", column: "content_fingerprint", definition: "TEXT", database: database)
        try execute(
            """
            CREATE VIRTUAL TABLE IF NOT EXISTS indexed_items_fts USING fts5(
                item_id UNINDEXED,
                display_name,
                current_path,
                original_path,
                tags,
                extracted_text,
                ai_summary
            )
            """,
            database: database
        )
        try execute("PRAGMA user_version = \(Self.schemaVersion)", database: database)
    }

    private static func readUserVersion(_ database: OpaquePointer?) throws -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "PRAGMA user_version", -1, &statement, nil) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_ROW else {
            sqlite3_finalize(statement)
            throw SearchIndexError.sqlite(errorMessage(database))
        }
        defer { sqlite3_finalize(statement) }
        return Int(sqlite3_column_int(statement, 0))
    }

    private static func addColumnIfMissing(
        table: String, column: String, definition: String, database: OpaquePointer?
    ) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "PRAGMA table_info(\(table))", -1, &statement, nil) == SQLITE_OK else {
            throw SearchIndexError.sqlite(errorMessage(database))
        }
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW {
            if let name = sqlite3_column_text(statement, 1), String(cString: name) == column {
                return
            }
        }
        try execute("ALTER TABLE \(table) ADD COLUMN \(column) \(definition)", database: database)
    }

    private func upsert(_ item: IndexedItem) throws {
        let statement = try prepare(
            """
            INSERT OR REPLACE INTO indexed_items (
                id,
                current_path,
                original_path,
                display_name,
                kind,
                uniform_type_identifier,
                size_bytes,
                created_at,
                modified_at,
                imported_at,
                routed_at,
                rule_id,
                tags_json,
                extracted_text,
                ai_summary,
                status,
                content_fingerprint
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
        )
        defer { sqlite3_finalize(statement) }

        try bind(item.id.uuidString, at: 1, in: statement)
        try bind(item.currentPath, at: 2, in: statement)
        try bind(item.originalPath, at: 3, in: statement)
        try bind(item.displayName, at: 4, in: statement)
        try bind(item.kind.rawValue, at: 5, in: statement)
        try bind(item.uniformTypeIdentifier, at: 6, in: statement)
        try bind(item.sizeBytes, at: 7, in: statement)
        try bind(item.createdAt, at: 8, in: statement)
        try bind(item.modifiedAt, at: 9, in: statement)
        try bind(item.importedAt, at: 10, in: statement)
        try bind(item.routedAt, at: 11, in: statement)
        try bind(item.ruleID?.uuidString, at: 12, in: statement)
        try bind(jsonString(item.tags), at: 13, in: statement)
        try bind(item.extractedText, at: 14, in: statement)
        try bind(item.aiSummary, at: 15, in: statement)
        try bind(item.status.rawValue, at: 16, in: statement)
        try bind(item.contentFingerprint, at: 17, in: statement)

        try stepDone(statement)
        try replaceFTSRecord(for: item)
    }

    private func replaceFTSRecord(for item: IndexedItem) throws {
        let deleteStatement = try prepare("DELETE FROM indexed_items_fts WHERE item_id = ?")
        defer { sqlite3_finalize(deleteStatement) }
        try bind(item.id.uuidString, at: 1, in: deleteStatement)
        try stepDone(deleteStatement)

        let insertStatement = try prepare(
            """
            INSERT INTO indexed_items_fts (
                item_id,
                display_name,
                current_path,
                original_path,
                tags,
                extracted_text,
                ai_summary
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            """
        )
        defer { sqlite3_finalize(insertStatement) }

        try bind(item.id.uuidString, at: 1, in: insertStatement)
        try bind(item.displayName, at: 2, in: insertStatement)
        try bind(item.currentPath, at: 3, in: insertStatement)
        try bind(item.originalPath, at: 4, in: insertStatement)
        try bind(item.tags.joined(separator: " "), at: 5, in: insertStatement)
        try bind(item.extractedText, at: 6, in: insertStatement)
        try bind(item.aiSummary, at: 7, in: insertStatement)
        try stepDone(insertStatement)
    }

    private func candidateIDs(for query: SearchQuery) throws -> [String] {
        let searchText = query.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if searchText.isEmpty {
            return try allCandidateIDs()
        }

        let ftsQuery = makeFTSQuery(searchText)
        guard !ftsQuery.isEmpty else {
            return try allCandidateIDs()
        }

        let statement = try prepare(
            """
            SELECT item_id
            FROM indexed_items_fts
            WHERE indexed_items_fts MATCH ?
            ORDER BY rank
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(ftsQuery, at: 1, in: statement)

        return try collectStringColumn(statement, column: 0)
    }

    private func allCandidateIDs() throws -> [String] {
        let statement = try prepare("SELECT id FROM indexed_items ORDER BY imported_at DESC")
        defer { sqlite3_finalize(statement) }
        return try collectStringColumn(statement, column: 0)
    }

    private func loadItem(id: String) throws -> IndexedItem? {
        let statement = try prepare(
            """
            SELECT
                id,
                current_path,
                original_path,
                display_name,
                kind,
                uniform_type_identifier,
                size_bytes,
                created_at,
                modified_at,
                imported_at,
                routed_at,
                rule_id,
                tags_json,
                extracted_text,
                ai_summary,
                status,
                content_fingerprint
            FROM indexed_items
            WHERE id = ?
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(id, at: 1, in: statement)

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }

        guard
            let uuid = UUID(uuidString: try requiredString(statement, column: 0)),
            let kind = ItemKind(rawValue: try requiredString(statement, column: 4)),
            let status = IndexedItemStatus(rawValue: try requiredString(statement, column: 15))
        else {
            throw SearchIndexError.sqlite("Stored indexed item has invalid enum or UUID values.")
        }

        return IndexedItem(
            id: uuid,
            currentPath: try requiredString(statement, column: 1),
            originalPath: optionalString(statement, column: 2),
            displayName: try requiredString(statement, column: 3),
            kind: kind,
            uniformTypeIdentifier: optionalString(statement, column: 5),
            sizeBytes: optionalInt64(statement, column: 6),
            createdAt: optionalDate(statement, column: 7),
            modifiedAt: optionalDate(statement, column: 8),
            importedAt: try requiredDate(statement, column: 9),
            routedAt: optionalDate(statement, column: 10),
            ruleID: optionalString(statement, column: 11).flatMap(UUID.init(uuidString:)),
            tags: try tags(from: try requiredString(statement, column: 12)),
            extractedText: optionalString(statement, column: 13),
            aiSummary: optionalString(statement, column: 14),
            status: status,
            contentFingerprint: optionalString(statement, column: 16)
        )
    }

    private func matchesFilters(_ item: IndexedItem, query: SearchQuery) -> Bool {
        if !query.kinds.isEmpty && !query.kinds.contains(item.kind) {
            return false
        }

        if !query.uniformTypeIdentifiers.isEmpty &&
            !query.uniformTypeIdentifiers.contains(item.uniformTypeIdentifier ?? "") {
            return false
        }

        if !query.statuses.isEmpty && !query.statuses.contains(item.status) {
            return false
        }

        if !query.tags.isEmpty && !query.tags.allSatisfy({ item.tags.contains($0) }) {
            return false
        }

        if let importedFrom = query.importedFrom, item.importedAt < importedFrom {
            return false
        }

        if let importedThrough = query.importedThrough, item.importedAt > importedThrough {
            return false
        }

        return true
    }

    private func collectStringColumn(_ statement: OpaquePointer?, column: Int32) throws -> [String] {
        var values: [String] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_ROW {
                values.append(try requiredString(statement, column: column))
            } else if result == SQLITE_DONE {
                return values
            } else {
                throw SearchIndexError.sqlite(lastErrorMessage)
            }
        }
    }

    private func makeFTSQuery(_ text: String) -> String {
        text
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { !$0.isEmpty }
            .map { "\($0)*" }
            .joined(separator: " ")
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SearchIndexError.sqlite(lastErrorMessage)
        }
        return statement
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw SearchIndexError.sqlite(lastErrorMessage)
        }
    }

    private static func execute(_ sql: String, database: OpaquePointer?) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw SearchIndexError.sqlite(errorMessage(database))
        }
    }

    private func stepDone(_ statement: OpaquePointer?) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SearchIndexError.sqlite(lastErrorMessage)
        }
    }

    private func bind(_ value: String?, at index: Int32, in statement: OpaquePointer?) throws {
        if let value {
            guard sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT) == SQLITE_OK else {
                throw SearchIndexError.sqlite(lastErrorMessage)
            }
        } else {
            try bindNull(at: index, in: statement)
        }
    }

    private func bind(_ value: Int64?, at index: Int32, in statement: OpaquePointer?) throws {
        if let value {
            guard sqlite3_bind_int64(statement, index, value) == SQLITE_OK else {
                throw SearchIndexError.sqlite(lastErrorMessage)
            }
        } else {
            try bindNull(at: index, in: statement)
        }
    }

    private func bind(_ value: Date?, at index: Int32, in statement: OpaquePointer?) throws {
        if let value {
            guard sqlite3_bind_double(statement, index, value.timeIntervalSince1970) == SQLITE_OK else {
                throw SearchIndexError.sqlite(lastErrorMessage)
            }
        } else {
            try bindNull(at: index, in: statement)
        }
    }

    private func bindNull(at index: Int32, in statement: OpaquePointer?) throws {
        guard sqlite3_bind_null(statement, index) == SQLITE_OK else {
            throw SearchIndexError.sqlite(lastErrorMessage)
        }
    }

    private func requiredString(_ statement: OpaquePointer?, column: Int32) throws -> String {
        guard let value = optionalString(statement, column: column) else {
            throw SearchIndexError.sqlite("Expected non-null text column \(column).")
        }
        return value
    }

    private func optionalString(_ statement: OpaquePointer?, column: Int32) -> String? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL else {
            return nil
        }
        guard let cString = sqlite3_column_text(statement, column) else {
            return nil
        }
        return String(cString: cString)
    }

    private func optionalInt64(_ statement: OpaquePointer?, column: Int32) -> Int64? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL else {
            return nil
        }
        return sqlite3_column_int64(statement, column)
    }

    private func requiredDate(_ statement: OpaquePointer?, column: Int32) throws -> Date {
        guard let date = optionalDate(statement, column: column) else {
            throw SearchIndexError.sqlite("Expected non-null date column \(column).")
        }
        return date
    }

    private func optionalDate(_ statement: OpaquePointer?, column: Int32) -> Date? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL else {
            return nil
        }
        return Date(timeIntervalSince1970: sqlite3_column_double(statement, column))
    }

    private func jsonString(_ tags: [String]) throws -> String {
        let data = try encoder.encode(tags)
        return String(decoding: data, as: UTF8.self)
    }

    private func tags(from string: String) throws -> [String] {
        try decoder.decode([String].self, from: Data(string.utf8))
    }

    private var lastErrorMessage: String {
        Self.errorMessage(database)
    }

    private static func errorMessage(_ database: OpaquePointer?) -> String {
        guard let database else {
            return "Database is not open."
        }
        return String(cString: sqlite3_errmsg(database))
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
