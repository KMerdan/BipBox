import BipboxCore
import BipboxPersistence
import SQLite3
import XCTest

final class SQLiteKnowledgeStoreTests: XCTestCase {
    func testSchemaVersionSmokeTest() async throws {
        let directory = try TemporaryDirectory(name: "knowledge-schema-\(UUID().uuidString)")
        let store = try SQLiteKnowledgeStore(directoryURL: directory.url)

        let version = try await store.schemaVersion()

        XCTAssertEqual(version, SQLiteKnowledgeStore.schemaVersion)
    }

    func testKnowledgeItemPersistsAcrossReopen() async throws {
        let directory = try TemporaryDirectory(name: "knowledge-reopen-\(UUID().uuidString)")
        let item = knowledgeItem(displayName: "invoice.pdf")

        do {
            let store = try SQLiteKnowledgeStore(directoryURL: directory.url)
            try await store.upsertKnowledgeItem(item)
        }

        let reopenedStore = try SQLiteKnowledgeStore(directoryURL: directory.url)
        let loaded = try await reopenedStore.knowledgeItem(id: item.id)

        XCTAssertEqual(loaded, item)
    }

    func testCaptureEventsPreserveGroupedSessionID() async throws {
        let directory = try TemporaryDirectory(name: "knowledge-capture-\(UUID().uuidString)")
        let store = try SQLiteKnowledgeStore(directoryURL: directory.url)
        let sessionID = UUID(uuidString: "40000000-0000-0000-0000-000000000010")!
        let itemA = knowledgeItem(id: UUID(uuidString: "40000000-0000-0000-0000-000000000011")!, displayName: "a.pdf")
        let itemB = knowledgeItem(id: UUID(uuidString: "40000000-0000-0000-0000-000000000012")!, displayName: "b.pdf")
        let eventA = captureEvent(itemID: itemA.id, sessionID: sessionID, rawURL: itemA.currentURL!)
        let eventB = captureEvent(
            id: UUID(uuidString: "40000000-0000-0000-0000-000000000013")!,
            itemID: itemB.id,
            sessionID: sessionID,
            rawURL: itemB.currentURL!,
            receivedAt: TestClock.now.addingTimeInterval(1)
        )

        try await store.upsertKnowledgeItem(itemA)
        try await store.upsertKnowledgeItem(itemB)
        try await store.appendCaptureEvent(eventA)
        try await store.appendCaptureEvent(eventB)

        let sessionEvents = try await store.captureEvents(sessionID: sessionID)
        let itemEvents = try await store.captureEvents(itemID: itemA.id)

        XCTAssertEqual(sessionEvents.map(\.id), [eventA.id, eventB.id])
        XCTAssertEqual(sessionEvents.map(\.sessionID), [sessionID, sessionID])
        XCTAssertEqual(itemEvents, [eventA])
    }

    func testSourceIDsPersistForKnowledgeItemsAndCaptureEvents() async throws {
        let directory = try TemporaryDirectory(name: "knowledge-source-\(UUID().uuidString)")
        let store = try SQLiteKnowledgeStore(directoryURL: directory.url)
        let sourceID = UUID(uuidString: "40000000-0000-0000-0000-000000000014")!
        let sessionID = UUID(uuidString: "40000000-0000-0000-0000-000000000015")!
        let item = knowledgeItem(displayName: "source-aware.pdf", sourceID: sourceID)
        let event = captureEvent(
            itemID: item.id,
            sourceID: sourceID,
            sessionID: sessionID,
            rawURL: item.currentURL!
        )

        try await store.upsertKnowledgeItem(item)
        try await store.appendCaptureEvent(event)

        let loadedItem = try await store.knowledgeItem(id: item.id)
        let loadedEvents = try await store.captureEvents(itemID: item.id)

        XCTAssertEqual(loadedItem?.sourceID, sourceID)
        XCTAssertEqual(loadedEvents.first?.sourceID, sourceID)
        XCTAssertEqual(loadedEvents.first?.source, .watchedFolder)
    }

    func testMissingAndPermissionNeededStatesPersistAcrossReopen() async throws {
        let directory = try TemporaryDirectory(name: "knowledge-state-\(UUID().uuidString)")
        let missing = knowledgeItem(
            id: UUID(uuidString: "40000000-0000-0000-0000-000000000016")!,
            displayName: "missing.pdf",
            state: .missing
        )
        let permissionNeeded = knowledgeItem(
            id: UUID(uuidString: "40000000-0000-0000-0000-000000000017")!,
            displayName: "private.pdf",
            state: .permissionNeeded
        )

        do {
            let store = try SQLiteKnowledgeStore(directoryURL: directory.url)
            try await store.upsertKnowledgeItem(missing)
            try await store.upsertKnowledgeItem(permissionNeeded)
        }

        let reopenedStore = try SQLiteKnowledgeStore(directoryURL: directory.url)
        let loadedMissing = try await reopenedStore.knowledgeItem(id: missing.id)
        let loadedPermissionNeeded = try await reopenedStore.knowledgeItem(id: permissionNeeded.id)

        XCTAssertEqual(loadedMissing?.state, .missing)
        XCTAssertEqual(loadedPermissionNeeded?.state, .permissionNeeded)
    }

    func testMigratesVersionOneKnowledgeSchemaToSourceFields() async throws {
        let directory = try TemporaryDirectory(name: "knowledge-migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory.url, withIntermediateDirectories: true)
        let databaseURL = directory.url.appendingPathComponent("knowledge.sqlite", isDirectory: false)
        try createVersionOneKnowledgeDatabase(at: databaseURL)
        let sourceID = UUID(uuidString: "40000000-0000-0000-0000-000000000018")!
        let migratedItem = knowledgeItem(displayName: "migrated.pdf", sourceID: sourceID)

        let store = try SQLiteKnowledgeStore(directoryURL: directory.url)
        let version = try await store.schemaVersion()
        try await store.upsertKnowledgeItem(migratedItem)
        let loaded = try await store.knowledgeItem(id: migratedItem.id)

        XCTAssertEqual(version, SQLiteKnowledgeStore.schemaVersion)
        XCTAssertEqual(loaded?.sourceID, sourceID)
    }

    func testRelationshipsAllowOneItemInMultipleContexts() async throws {
        let directory = try TemporaryDirectory(name: "knowledge-relationships-\(UUID().uuidString)")
        let store = try SQLiteKnowledgeStore(directoryURL: directory.url)
        let item = knowledgeItem(displayName: "proposal.pdf")
        let project = contextNode(kind: .project, name: "Bipbox")
        let topic = contextNode(
            id: UUID(uuidString: "40000000-0000-0000-0000-000000000020")!,
            kind: .topic,
            name: "retrieval"
        )
        let projectEdge = relationship(
            subjectID: item.id,
            predicate: .belongsTo,
            objectID: project.id,
            confidence: 0.9
        )
        let topicEdge = relationship(
            id: UUID(uuidString: "40000000-0000-0000-0000-000000000021")!,
            subjectID: item.id,
            predicate: .hasTopic,
            objectID: topic.id,
            confidence: 0.7
        )

        try await store.upsertKnowledgeItem(item)
        try await store.upsertContext(project)
        try await store.upsertContext(topic)
        try await store.upsertRelationship(projectEdge)
        try await store.upsertRelationship(topicEdge)

        let loadedProject = try await store.context(id: project.id)
        let outgoing = try await store.relationships(subjectID: item.id)
        let incoming = try await store.relationships(objectID: topic.id)

        XCTAssertEqual(loadedProject, project)
        XCTAssertEqual(outgoing.map(\.predicate), [.belongsTo, .hasTopic])
        XCTAssertEqual(incoming, [topicEdge])
    }

    func testCollectionsOverlapAndMembershipRemovalDoesNotDeleteItem() async throws {
        let directory = try TemporaryDirectory(name: "knowledge-collections-\(UUID().uuidString)")
        let store = try SQLiteKnowledgeStore(directoryURL: directory.url)
        let item = knowledgeItem(displayName: "research.pdf")
        let manual = collection(name: "Research")
        let project = collection(
            id: UUID(uuidString: "40000000-0000-0000-0000-000000000030")!,
            name: "Bipbox Project",
            kind: .ruleBacked
        )

        try await store.upsertKnowledgeItem(item)
        try await store.upsertCollection(manual)
        try await store.upsertCollection(project)
        try await store.addItem(item.id, toCollection: manual.id, createdAt: TestClock.now)
        try await store.addItem(item.id, toCollection: project.id, createdAt: TestClock.now)

        let loadedManual = try await store.collection(id: manual.id)
        let manualItemIDs = try await store.collectionItemIDs(collectionID: manual.id)
        let projectItemIDs = try await store.collectionItemIDs(collectionID: project.id)

        XCTAssertEqual(loadedManual, manual)
        XCTAssertEqual(manualItemIDs, [item.id])
        XCTAssertEqual(projectItemIDs, [item.id])

        try await store.removeItem(item.id, fromCollection: manual.id)

        let updatedManualItemIDs = try await store.collectionItemIDs(collectionID: manual.id)
        let updatedProjectItemIDs = try await store.collectionItemIDs(collectionID: project.id)
        let loadedItem = try await store.knowledgeItem(id: item.id)

        XCTAssertEqual(updatedManualItemIDs, [])
        XCTAssertEqual(updatedProjectItemIDs, [item.id])
        XCTAssertEqual(loadedItem, item)
    }

    func testMetadataSnapshotRoundTrips() async throws {
        let directory = try TemporaryDirectory(name: "knowledge-metadata-\(UUID().uuidString)")
        let store = try SQLiteKnowledgeStore(directoryURL: directory.url)
        let item = knowledgeItem(displayName: "paper.pdf")
        let metadata = [
            "title": "Personal File Memory",
            "source": "spotlight"
        ]

        try await store.upsertKnowledgeItem(item)
        try await store.upsertMetadataSnapshot(itemID: item.id, metadata: metadata, capturedAt: TestClock.now)

        let loaded = try await store.metadataSnapshot(itemID: item.id)

        XCTAssertEqual(loaded, metadata)
    }
}

private func knowledgeItem(
    id: UUID = UUID(uuidString: "40000000-0000-0000-0000-000000000001")!,
    displayName: String,
    kind: ItemKind = .file,
    sourceID: UUID? = nil,
    state: KnowledgeItemState = .active
) -> KnowledgeItem {
    KnowledgeItem(
        id: id,
        kind: kind,
        displayName: displayName,
        sourceID: sourceID,
        currentURL: URL(fileURLWithPath: "/tmp/\(displayName)"),
        originalURL: URL(fileURLWithPath: "/Users/example/Downloads/\(displayName)"),
        bookmarkID: UUID(uuidString: "40000000-0000-0000-0000-000000000002")!,
        contentFingerprint: "hash-\(displayName)",
        filesystemIdentity: "dev:1-inode:\(displayName)",
        createdAt: TestClock.now.addingTimeInterval(-20),
        modifiedAt: TestClock.now.addingTimeInterval(-10),
        firstSeenAt: TestClock.now,
        lastSeenAt: TestClock.now,
        state: state
    )
}

private func createVersionOneKnowledgeDatabase(at url: URL) throws {
    var database: OpaquePointer?
    guard sqlite3_open(url.path, &database) == SQLITE_OK else {
        throw KnowledgeMigrationFixtureError.openFailed
    }
    defer { sqlite3_close(database) }

    let statements = [
        """
        CREATE TABLE file_records (
            id TEXT PRIMARY KEY NOT NULL,
            kind TEXT NOT NULL,
            display_name TEXT NOT NULL,
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
        """
        CREATE TABLE capture_events (
            id TEXT PRIMARY KEY NOT NULL,
            item_id TEXT NOT NULL,
            source TEXT NOT NULL,
            source_detail_json TEXT NOT NULL,
            received_at REAL NOT NULL,
            session_id TEXT NOT NULL,
            parent_context_id TEXT,
            raw_url TEXT NOT NULL,
            requested_mode TEXT NOT NULL
        )
        """,
        "PRAGMA user_version = 1"
    ]

    for statement in statements {
        guard sqlite3_exec(database, statement, nil, nil, nil) == SQLITE_OK else {
            throw KnowledgeMigrationFixtureError.execFailed(String(cString: sqlite3_errmsg(database)))
        }
    }
}

private enum KnowledgeMigrationFixtureError: Error {
    case openFailed
    case execFailed(String)
}

private func captureEvent(
    id: UUID = UUID(uuidString: "40000000-0000-0000-0000-000000000003")!,
    itemID: UUID,
    sourceID: UUID? = nil,
    sessionID: UUID,
    rawURL: URL,
    receivedAt: Date = TestClock.now
) -> CaptureEvent {
    CaptureEvent(
        id: id,
        itemID: itemID,
        source: .watchedFolder,
        sourceID: sourceID,
        sourceDetail: ["folder": "Downloads"],
        receivedAt: receivedAt,
        sessionID: sessionID,
        rawURL: rawURL,
        requestedMode: .organize
    )
}

private func contextNode(
    id: UUID = UUID(uuidString: "40000000-0000-0000-0000-000000000004")!,
    kind: ContextKind,
    name: String
) -> ContextNode {
    ContextNode(
        id: id,
        kind: kind,
        name: name,
        confidence: ConfidenceScore(0.8),
        provenance: .existingFolderScan,
        createdAt: TestClock.now,
        updatedAt: TestClock.now
    )
}

private func relationship(
    id: UUID = UUID(uuidString: "40000000-0000-0000-0000-000000000005")!,
    subjectID: UUID,
    predicate: RelationshipPredicate,
    objectID: UUID,
    confidence: Double
) -> RelationshipEdge {
    RelationshipEdge(
        id: id,
        subjectID: subjectID,
        subjectKind: .knowledgeItem,
        predicate: predicate,
        objectID: objectID,
        objectKind: .context,
        confidence: ConfidenceScore(confidence),
        provenance: .existingFolderScan,
        createdAt: TestClock.now,
        updatedAt: TestClock.now
    )
}

private func collection(
    id: UUID = UUID(uuidString: "40000000-0000-0000-0000-000000000006")!,
    name: String,
    kind: KnowledgeCollectionKind = .manual
) -> KnowledgeCollection {
    KnowledgeCollection(
        id: id,
        name: name,
        kind: kind,
        manualMembershipAllowed: true,
        createdBy: .user,
        createdAt: TestClock.now,
        updatedAt: TestClock.now
    )
}
