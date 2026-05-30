import BipboxCore
import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public enum KnowledgeStoreError: Error, Equatable, LocalizedError {
    case storageUnavailable(URL, String)
    case sqlite(String)

    public var errorDescription: String? {
        switch self {
        case .storageUnavailable(let url, let reason):
            "Knowledge store is unavailable at \(url.path): \(reason)"
        case .sqlite(let message):
            "SQLite knowledge store error: \(message)"
        }
    }
}

public actor SQLiteKnowledgeStore: KnowledgeStore {
    public static let schemaVersion = 2

    private let databaseURL: URL
    nonisolated(unsafe) private var database: OpaquePointer?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(directoryURL: URL, fileManager: FileManager = .default) throws {
        databaseURL = directoryURL.appendingPathComponent("knowledge.sqlite", isDirectory: false)
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601

        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        } catch {
            throw KnowledgeStoreError.storageUnavailable(directoryURL, error.localizedDescription)
        }

        var openedDatabase: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &openedDatabase) == SQLITE_OK else {
            throw KnowledgeStoreError.storageUnavailable(databaseURL, Self.errorMessage(openedDatabase))
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

    public func schemaVersion() async throws -> Int {
        let statement = try prepare("PRAGMA user_version")
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw KnowledgeStoreError.sqlite(lastErrorMessage)
        }

        return Int(sqlite3_column_int(statement, 0))
    }

    public func upsertKnowledgeItem(_ item: KnowledgeItem) async throws {
        let statement = try prepare(
            """
            INSERT OR REPLACE INTO file_records (
                id,
                kind,
                display_name,
                source_id,
                current_url,
                original_url,
                bookmark_id,
                content_fingerprint,
                filesystem_identity,
                created_at,
                modified_at,
                first_seen_at,
                last_seen_at,
                state
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
        )
        defer { sqlite3_finalize(statement) }

        try bind(item.id.uuidString, at: 1, in: statement)
        try bind(item.kind.rawValue, at: 2, in: statement)
        try bind(item.displayName, at: 3, in: statement)
        try bind(item.sourceID?.uuidString, at: 4, in: statement)
        try bind(item.currentURL?.path, at: 5, in: statement)
        try bind(item.originalURL?.path, at: 6, in: statement)
        try bind(item.bookmarkID?.uuidString, at: 7, in: statement)
        try bind(item.contentFingerprint, at: 8, in: statement)
        try bind(item.filesystemIdentity, at: 9, in: statement)
        try bind(item.createdAt, at: 10, in: statement)
        try bind(item.modifiedAt, at: 11, in: statement)
        try bind(item.firstSeenAt, at: 12, in: statement)
        try bind(item.lastSeenAt, at: 13, in: statement)
        try bind(item.state.rawValue, at: 14, in: statement)

        try stepDone(statement)
    }

    public func knowledgeItem(id: UUID) async throws -> KnowledgeItem? {
        let statement = try prepare(
            """
            SELECT
                id,
                kind,
                display_name,
                source_id,
                current_url,
                original_url,
                bookmark_id,
                content_fingerprint,
                filesystem_identity,
                created_at,
                modified_at,
                first_seen_at,
                last_seen_at,
                state
            FROM file_records
            WHERE id = ?
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(id.uuidString, at: 1, in: statement)

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }

        guard
            let storedID = UUID(uuidString: try requiredString(statement, column: 0)),
            let kind = ItemKind(rawValue: try requiredString(statement, column: 1)),
            let state = KnowledgeItemState(rawValue: try requiredString(statement, column: 13))
        else {
            throw KnowledgeStoreError.sqlite("Stored file record has invalid enum or UUID values.")
        }

        return KnowledgeItem(
            id: storedID,
            kind: kind,
            displayName: try requiredString(statement, column: 2),
            sourceID: optionalString(statement, column: 3).flatMap(UUID.init(uuidString:)),
            currentURL: optionalFileURL(statement, column: 4),
            originalURL: optionalFileURL(statement, column: 5),
            bookmarkID: optionalString(statement, column: 6).flatMap(UUID.init(uuidString:)),
            contentFingerprint: optionalString(statement, column: 7),
            filesystemIdentity: optionalString(statement, column: 8),
            createdAt: optionalDate(statement, column: 9),
            modifiedAt: optionalDate(statement, column: 10),
            firstSeenAt: try requiredDate(statement, column: 11),
            lastSeenAt: try requiredDate(statement, column: 12),
            state: state
        )
    }

    public func appendCaptureEvent(_ event: CaptureEvent) async throws {
        let statement = try prepare(
            """
            INSERT OR REPLACE INTO capture_events (
                id,
                item_id,
                source,
                source_id,
                source_detail_json,
                received_at,
                session_id,
                parent_context_id,
                raw_url,
                requested_mode
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
        )
        defer { sqlite3_finalize(statement) }

        try bind(event.id.uuidString, at: 1, in: statement)
        try bind(event.itemID.uuidString, at: 2, in: statement)
        try bind(event.source.rawValue, at: 3, in: statement)
        try bind(event.sourceID?.uuidString, at: 4, in: statement)
        try bind(jsonString(event.sourceDetail), at: 5, in: statement)
        try bind(event.receivedAt, at: 6, in: statement)
        try bind(event.sessionID.uuidString, at: 7, in: statement)
        try bind(event.parentContextID?.uuidString, at: 8, in: statement)
        try bind(event.rawURL.path, at: 9, in: statement)
        try bind(event.requestedMode.rawValue, at: 10, in: statement)

        try stepDone(statement)
    }

    public func captureEvents(itemID: UUID) async throws -> [CaptureEvent] {
        try captureEvents(whereClause: "item_id = ?", value: itemID.uuidString)
    }

    public func captureEvents(sessionID: UUID) async throws -> [CaptureEvent] {
        try captureEvents(whereClause: "session_id = ?", value: sessionID.uuidString)
    }

    public func upsertContext(_ context: ContextNode) async throws {
        let statement = try prepare(
            """
            INSERT OR REPLACE INTO context_nodes (
                id,
                kind,
                name,
                confidence,
                provenance,
                created_at,
                updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            """
        )
        defer { sqlite3_finalize(statement) }

        try bind(context.id.uuidString, at: 1, in: statement)
        try bind(context.kind.rawValue, at: 2, in: statement)
        try bind(context.name, at: 3, in: statement)
        try bind(context.confidence.rawValue, at: 4, in: statement)
        try bind(context.provenance.rawValue, at: 5, in: statement)
        try bind(context.createdAt, at: 6, in: statement)
        try bind(context.updatedAt, at: 7, in: statement)

        try stepDone(statement)
    }

    public func context(id: UUID) async throws -> ContextNode? {
        let statement = try prepare(
            """
            SELECT id, kind, name, confidence, provenance, created_at, updated_at
            FROM context_nodes
            WHERE id = ?
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(id.uuidString, at: 1, in: statement)

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }

        return try context(from: statement)
    }

    public func upsertRelationship(_ relationship: RelationshipEdge) async throws {
        let statement = try prepare(
            """
            INSERT OR REPLACE INTO relationship_edges (
                id,
                subject_id,
                subject_kind,
                predicate,
                object_id,
                object_kind,
                confidence,
                provenance,
                created_at,
                updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
        )
        defer { sqlite3_finalize(statement) }

        try bind(relationship.id.uuidString, at: 1, in: statement)
        try bind(relationship.subjectID.uuidString, at: 2, in: statement)
        try bind(relationship.subjectKind.rawValue, at: 3, in: statement)
        try bind(relationship.predicate.rawValue, at: 4, in: statement)
        try bind(relationship.objectID.uuidString, at: 5, in: statement)
        try bind(relationship.objectKind.rawValue, at: 6, in: statement)
        try bind(relationship.confidence.rawValue, at: 7, in: statement)
        try bind(relationship.provenance.rawValue, at: 8, in: statement)
        try bind(relationship.createdAt, at: 9, in: statement)
        try bind(relationship.updatedAt, at: 10, in: statement)

        try stepDone(statement)
    }

    public func relationships(subjectID: UUID) async throws -> [RelationshipEdge] {
        try relationships(whereClause: "subject_id = ?", value: subjectID.uuidString)
    }

    public func relationships(objectID: UUID) async throws -> [RelationshipEdge] {
        try relationships(whereClause: "object_id = ?", value: objectID.uuidString)
    }

    public func upsertCollection(_ collection: KnowledgeCollection) async throws {
        let statement = try prepare(
            """
            INSERT OR REPLACE INTO collections (
                id,
                name,
                kind,
                query,
                manual_membership_allowed,
                created_by,
                created_at,
                updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """
        )
        defer { sqlite3_finalize(statement) }

        try bind(collection.id.uuidString, at: 1, in: statement)
        try bind(collection.name, at: 2, in: statement)
        try bind(collection.kind.rawValue, at: 3, in: statement)
        try bind(collection.query, at: 4, in: statement)
        try bind(collection.manualMembershipAllowed ? Int64(1) : Int64(0), at: 5, in: statement)
        try bind(collection.createdBy.rawValue, at: 6, in: statement)
        try bind(collection.createdAt, at: 7, in: statement)
        try bind(collection.updatedAt, at: 8, in: statement)

        try stepDone(statement)
    }

    public func collection(id: UUID) async throws -> KnowledgeCollection? {
        let statement = try prepare(
            """
            SELECT
                id,
                name,
                kind,
                query,
                manual_membership_allowed,
                created_by,
                created_at,
                updated_at
            FROM collections
            WHERE id = ?
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(id.uuidString, at: 1, in: statement)

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }

        return try collection(from: statement)
    }

    public func collections() async throws -> [KnowledgeCollection] {
        let statement = try prepare(
            """
            SELECT
                id,
                name,
                kind,
                query,
                manual_membership_allowed,
                created_by,
                created_at,
                updated_at
            FROM collections
            ORDER BY name ASC, id ASC
            """
        )
        defer { sqlite3_finalize(statement) }

        var collections: [KnowledgeCollection] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_ROW {
                collections.append(try collection(from: statement))
            } else if result == SQLITE_DONE {
                return collections
            } else {
                throw KnowledgeStoreError.sqlite(lastErrorMessage)
            }
        }
    }

    public func addItem(_ itemID: UUID, toCollection collectionID: UUID, createdAt: Date) async throws {
        let statement = try prepare(
            """
            INSERT OR REPLACE INTO collection_memberships (
                collection_id,
                item_id,
                created_at
            ) VALUES (?, ?, ?)
            """
        )
        defer { sqlite3_finalize(statement) }

        try bind(collectionID.uuidString, at: 1, in: statement)
        try bind(itemID.uuidString, at: 2, in: statement)
        try bind(createdAt, at: 3, in: statement)

        try stepDone(statement)
    }

    public func removeItem(_ itemID: UUID, fromCollection collectionID: UUID) async throws {
        let statement = try prepare(
            """
            DELETE FROM collection_memberships
            WHERE collection_id = ? AND item_id = ?
            """
        )
        defer { sqlite3_finalize(statement) }

        try bind(collectionID.uuidString, at: 1, in: statement)
        try bind(itemID.uuidString, at: 2, in: statement)

        try stepDone(statement)
    }

    public func collectionItemIDs(collectionID: UUID) async throws -> [UUID] {
        let statement = try prepare(
            """
            SELECT item_id
            FROM collection_memberships
            WHERE collection_id = ?
            ORDER BY created_at ASC
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(collectionID.uuidString, at: 1, in: statement)

        return try collectUUIDColumn(statement, column: 0)
    }

    public func upsertMetadataSnapshot(itemID: UUID, metadata: [String: String], capturedAt: Date) async throws {
        let statement = try prepare(
            """
            INSERT OR REPLACE INTO metadata_snapshots (
                item_id,
                metadata_json,
                captured_at
            ) VALUES (?, ?, ?)
            """
        )
        defer { sqlite3_finalize(statement) }

        try bind(itemID.uuidString, at: 1, in: statement)
        try bind(jsonString(metadata), at: 2, in: statement)
        try bind(capturedAt, at: 3, in: statement)

        try stepDone(statement)
    }

    public func metadataSnapshot(itemID: UUID) async throws -> [String: String]? {
        let statement = try prepare(
            """
            SELECT metadata_json
            FROM metadata_snapshots
            WHERE item_id = ?
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(itemID.uuidString, at: 1, in: statement)

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }

        return try dictionary(from: try requiredString(statement, column: 0))
    }

    private static func migrate(_ database: OpaquePointer?) throws {
        try execute("PRAGMA journal_mode=WAL", database: database)
        try execute(
            """
            CREATE TABLE IF NOT EXISTS file_records (
                id TEXT PRIMARY KEY NOT NULL,
                kind TEXT NOT NULL,
                display_name TEXT NOT NULL,
                source_id TEXT,
                current_url TEXT,
                original_url TEXT,
                bookmark_id TEXT,
                content_fingerprint TEXT,
                filesystem_identity TEXT,
                created_at REAL,
                modified_at REAL,
                first_seen_at REAL NOT NULL,
                last_seen_at REAL NOT NULL,
                state TEXT NOT NULL
            )
            """,
            database: database
        )
        try execute(
            """
            CREATE TABLE IF NOT EXISTS capture_events (
                id TEXT PRIMARY KEY NOT NULL,
                item_id TEXT NOT NULL,
                source TEXT NOT NULL,
                source_id TEXT,
                source_detail_json TEXT NOT NULL,
                received_at REAL NOT NULL,
                session_id TEXT NOT NULL,
                parent_context_id TEXT,
                raw_url TEXT NOT NULL,
                requested_mode TEXT NOT NULL
            )
            """,
            database: database
        )
        try addColumnIfMissing("source_id", to: "file_records", definition: "TEXT", database: database)
        try addColumnIfMissing("source_id", to: "capture_events", definition: "TEXT", database: database)
        try execute(
            """
            CREATE INDEX IF NOT EXISTS capture_events_item_id
            ON capture_events(item_id, received_at)
            """,
            database: database
        )
        try execute(
            """
            CREATE INDEX IF NOT EXISTS capture_events_session_id
            ON capture_events(session_id, received_at)
            """,
            database: database
        )
        try execute(
            """
            CREATE TABLE IF NOT EXISTS context_nodes (
                id TEXT PRIMARY KEY NOT NULL,
                kind TEXT NOT NULL,
                name TEXT NOT NULL,
                confidence REAL NOT NULL,
                provenance TEXT NOT NULL,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            )
            """,
            database: database
        )
        try execute(
            """
            CREATE TABLE IF NOT EXISTS relationship_edges (
                id TEXT PRIMARY KEY NOT NULL,
                subject_id TEXT NOT NULL,
                subject_kind TEXT NOT NULL,
                predicate TEXT NOT NULL,
                object_id TEXT NOT NULL,
                object_kind TEXT NOT NULL,
                confidence REAL NOT NULL,
                provenance TEXT NOT NULL,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            )
            """,
            database: database
        )
        try execute(
            """
            CREATE INDEX IF NOT EXISTS relationship_edges_subject
            ON relationship_edges(subject_id)
            """,
            database: database
        )
        try execute(
            """
            CREATE INDEX IF NOT EXISTS relationship_edges_object
            ON relationship_edges(object_id)
            """,
            database: database
        )
        try execute(
            """
            CREATE TABLE IF NOT EXISTS collections (
                id TEXT PRIMARY KEY NOT NULL,
                name TEXT NOT NULL,
                kind TEXT NOT NULL,
                query TEXT,
                manual_membership_allowed INTEGER NOT NULL,
                created_by TEXT NOT NULL,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            )
            """,
            database: database
        )
        try execute(
            """
            CREATE TABLE IF NOT EXISTS collection_memberships (
                collection_id TEXT NOT NULL,
                item_id TEXT NOT NULL,
                created_at REAL NOT NULL,
                PRIMARY KEY(collection_id, item_id)
            )
            """,
            database: database
        )
        try execute(
            """
            CREATE TABLE IF NOT EXISTS metadata_snapshots (
                item_id TEXT PRIMARY KEY NOT NULL,
                metadata_json TEXT NOT NULL,
                captured_at REAL NOT NULL
            )
            """,
            database: database
        )
        try execute("PRAGMA user_version = \(Self.schemaVersion)", database: database)
    }

    private func captureEvents(whereClause: String, value: String) throws -> [CaptureEvent] {
        let statement = try prepare(
            """
            SELECT
                id,
                item_id,
                source,
                source_id,
                source_detail_json,
                received_at,
                session_id,
                parent_context_id,
                raw_url,
                requested_mode
            FROM capture_events
            WHERE \(whereClause)
            ORDER BY received_at ASC, id ASC
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(value, at: 1, in: statement)

        var events: [CaptureEvent] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_ROW {
                events.append(try captureEvent(from: statement))
            } else if result == SQLITE_DONE {
                return events
            } else {
                throw KnowledgeStoreError.sqlite(lastErrorMessage)
            }
        }
    }

    private func relationships(whereClause: String, value: String) throws -> [RelationshipEdge] {
        let statement = try prepare(
            """
            SELECT
                id,
                subject_id,
                subject_kind,
                predicate,
                object_id,
                object_kind,
                confidence,
                provenance,
                created_at,
                updated_at
            FROM relationship_edges
            WHERE \(whereClause)
            ORDER BY created_at ASC, id ASC
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(value, at: 1, in: statement)

        var relationships: [RelationshipEdge] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_ROW {
                relationships.append(try relationship(from: statement))
            } else if result == SQLITE_DONE {
                return relationships
            } else {
                throw KnowledgeStoreError.sqlite(lastErrorMessage)
            }
        }
    }

    private func captureEvent(from statement: OpaquePointer?) throws -> CaptureEvent {
        guard
            let id = UUID(uuidString: try requiredString(statement, column: 0)),
            let itemID = UUID(uuidString: try requiredString(statement, column: 1)),
            let source = CaptureSource(rawValue: try requiredString(statement, column: 2)),
            let sessionID = UUID(uuidString: try requiredString(statement, column: 6)),
            let mode = OrganizationMode(rawValue: try requiredString(statement, column: 9))
        else {
            throw KnowledgeStoreError.sqlite("Stored capture event has invalid enum or UUID values.")
        }

        return CaptureEvent(
            id: id,
            itemID: itemID,
            source: source,
            sourceID: optionalString(statement, column: 3).flatMap(UUID.init(uuidString:)),
            sourceDetail: try dictionary(from: try requiredString(statement, column: 4)),
            receivedAt: try requiredDate(statement, column: 5),
            sessionID: sessionID,
            parentContextID: optionalString(statement, column: 7).flatMap(UUID.init(uuidString:)),
            rawURL: URL(fileURLWithPath: try requiredString(statement, column: 8)),
            requestedMode: mode
        )
    }

    private func context(from statement: OpaquePointer?) throws -> ContextNode {
        guard
            let id = UUID(uuidString: try requiredString(statement, column: 0)),
            let kind = ContextKind(rawValue: try requiredString(statement, column: 1)),
            let provenance = GraphProvenance(rawValue: try requiredString(statement, column: 4))
        else {
            throw KnowledgeStoreError.sqlite("Stored context has invalid enum or UUID values.")
        }

        return ContextNode(
            id: id,
            kind: kind,
            name: try requiredString(statement, column: 2),
            confidence: ConfidenceScore(sqlite3_column_double(statement, 3)),
            provenance: provenance,
            createdAt: try requiredDate(statement, column: 5),
            updatedAt: try requiredDate(statement, column: 6)
        )
    }

    private func relationship(from statement: OpaquePointer?) throws -> RelationshipEdge {
        guard
            let id = UUID(uuidString: try requiredString(statement, column: 0)),
            let subjectID = UUID(uuidString: try requiredString(statement, column: 1)),
            let subjectKind = GraphNodeKind(rawValue: try requiredString(statement, column: 2)),
            let predicate = RelationshipPredicate(rawValue: try requiredString(statement, column: 3)),
            let objectID = UUID(uuidString: try requiredString(statement, column: 4)),
            let objectKind = GraphNodeKind(rawValue: try requiredString(statement, column: 5)),
            let provenance = GraphProvenance(rawValue: try requiredString(statement, column: 7))
        else {
            throw KnowledgeStoreError.sqlite("Stored relationship has invalid enum or UUID values.")
        }

        return RelationshipEdge(
            id: id,
            subjectID: subjectID,
            subjectKind: subjectKind,
            predicate: predicate,
            objectID: objectID,
            objectKind: objectKind,
            confidence: ConfidenceScore(sqlite3_column_double(statement, 6)),
            provenance: provenance,
            createdAt: try requiredDate(statement, column: 8),
            updatedAt: try requiredDate(statement, column: 9)
        )
    }

    private func collection(from statement: OpaquePointer?) throws -> KnowledgeCollection {
        guard
            let id = UUID(uuidString: try requiredString(statement, column: 0)),
            let kind = KnowledgeCollectionKind(rawValue: try requiredString(statement, column: 2)),
            let createdBy = GraphProvenance(rawValue: try requiredString(statement, column: 5))
        else {
            throw KnowledgeStoreError.sqlite("Stored collection has invalid enum or UUID values.")
        }

        return KnowledgeCollection(
            id: id,
            name: try requiredString(statement, column: 1),
            kind: kind,
            query: optionalString(statement, column: 3),
            manualMembershipAllowed: sqlite3_column_int64(statement, 4) != 0,
            createdBy: createdBy,
            createdAt: try requiredDate(statement, column: 6),
            updatedAt: try requiredDate(statement, column: 7)
        )
    }

    private func collectUUIDColumn(_ statement: OpaquePointer?, column: Int32) throws -> [UUID] {
        var values: [UUID] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_ROW {
                guard let uuid = UUID(uuidString: try requiredString(statement, column: column)) else {
                    throw KnowledgeStoreError.sqlite("Stored UUID column is invalid.")
                }
                values.append(uuid)
            } else if result == SQLITE_DONE {
                return values
            } else {
                throw KnowledgeStoreError.sqlite(lastErrorMessage)
            }
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw KnowledgeStoreError.sqlite(lastErrorMessage)
        }
        return statement
    }

    private static func execute(_ sql: String, database: OpaquePointer?) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw KnowledgeStoreError.sqlite(errorMessage(database))
        }
    }

    private static func addColumnIfMissing(
        _ column: String,
        to table: String,
        definition: String,
        database: OpaquePointer?
    ) throws {
        guard try !columnExists(column, in: table, database: database) else {
            return
        }
        try execute("ALTER TABLE \(table) ADD COLUMN \(column) \(definition)", database: database)
    }

    private static func columnExists(_ column: String, in table: String, database: OpaquePointer?) throws -> Bool {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "PRAGMA table_info(\(table))", -1, &statement, nil) == SQLITE_OK else {
            throw KnowledgeStoreError.sqlite(errorMessage(database))
        }
        defer { sqlite3_finalize(statement) }

        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_ROW {
                if let cString = sqlite3_column_text(statement, 1),
                   String(cString: cString) == column {
                    return true
                }
            } else if result == SQLITE_DONE {
                return false
            } else {
                throw KnowledgeStoreError.sqlite(errorMessage(database))
            }
        }
    }

    private func stepDone(_ statement: OpaquePointer?) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw KnowledgeStoreError.sqlite(lastErrorMessage)
        }
    }

    private func bind(_ value: String?, at index: Int32, in statement: OpaquePointer?) throws {
        if let value {
            guard sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT) == SQLITE_OK else {
                throw KnowledgeStoreError.sqlite(lastErrorMessage)
            }
        } else {
            try bindNull(at: index, in: statement)
        }
    }

    private func bind(_ value: Int64?, at index: Int32, in statement: OpaquePointer?) throws {
        if let value {
            guard sqlite3_bind_int64(statement, index, value) == SQLITE_OK else {
                throw KnowledgeStoreError.sqlite(lastErrorMessage)
            }
        } else {
            try bindNull(at: index, in: statement)
        }
    }

    private func bind(_ value: Double?, at index: Int32, in statement: OpaquePointer?) throws {
        if let value {
            guard sqlite3_bind_double(statement, index, value) == SQLITE_OK else {
                throw KnowledgeStoreError.sqlite(lastErrorMessage)
            }
        } else {
            try bindNull(at: index, in: statement)
        }
    }

    private func bind(_ value: Date?, at index: Int32, in statement: OpaquePointer?) throws {
        if let value {
            try bind(value.timeIntervalSince1970, at: index, in: statement)
        } else {
            try bindNull(at: index, in: statement)
        }
    }

    private func bindNull(at index: Int32, in statement: OpaquePointer?) throws {
        guard sqlite3_bind_null(statement, index) == SQLITE_OK else {
            throw KnowledgeStoreError.sqlite(lastErrorMessage)
        }
    }

    private func requiredString(_ statement: OpaquePointer?, column: Int32) throws -> String {
        guard let value = optionalString(statement, column: column) else {
            throw KnowledgeStoreError.sqlite("Expected non-null text column \(column).")
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

    private func optionalDate(_ statement: OpaquePointer?, column: Int32) -> Date? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL else {
            return nil
        }
        return Date(timeIntervalSince1970: sqlite3_column_double(statement, column))
    }

    private func requiredDate(_ statement: OpaquePointer?, column: Int32) throws -> Date {
        guard let date = optionalDate(statement, column: column) else {
            throw KnowledgeStoreError.sqlite("Expected non-null date column \(column).")
        }
        return date
    }

    private func optionalFileURL(_ statement: OpaquePointer?, column: Int32) -> URL? {
        optionalString(statement, column: column).map { URL(fileURLWithPath: $0) }
    }

    private func jsonString(_ dictionary: [String: String]) throws -> String {
        let data = try encoder.encode(dictionary)
        return String(decoding: data, as: UTF8.self)
    }

    private func dictionary(from string: String) throws -> [String: String] {
        try decoder.decode([String: String].self, from: Data(string.utf8))
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
