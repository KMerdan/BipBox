import BipboxCore
import XCTest

final class DefaultColdStartScannerTests: XCTestCase {
    func testShallowScanCapturesTopLevelItemsAndFolderContext() async throws {
        let directory = try TemporaryDirectory(name: "cold-start-shallow-\(UUID().uuidString)")
        let rootURL = try directory.createFolder(named: "Downloads")
        let fileURL = try directory.createFile(named: "Downloads/report.pdf", contents: "report")
        let folderURL = try directory.createFolder(named: "Downloads/Project")
        _ = try directory.createFile(named: "Downloads/Project/inside.txt", contents: "nested")
        let permissionID = UUID(uuidString: "60000000-0000-0000-0000-000000000001")!
        let permissionStore = MockPermissionStore()
        try await permissionStore.save(
            PermissionRecord(
                id: permissionID,
                scope: .watchedFolder,
                url: rootURL,
                state: .granted,
                metadata: ["captureLocation": "downloads"]
            )
        )
        let knowledgeStore = MockKnowledgeStore()
        let searchService = MockSearchService()
        let activityLog = MockActivityLog()
        let scanner = DefaultColdStartScanner(
            permissionStore: permissionStore,
            inspector: FileSystemItemInspector(),
            knowledgeStore: knowledgeStore,
            searchService: searchService,
            activityLog: activityLog
        )
        let progressRecorder = ProgressRecorder()

        let result = try await scanner.scan(
            ColdStartScanRequest(permissionRecordID: permissionID, receivedAt: TestClock.now)
        ) { progress in
            await progressRecorder.append(progress)
        }
        let progressEvents = await progressRecorder.events

        XCTAssertEqual(result.scannedItemCount, 2)
        XCTAssertEqual(result.failures, [])
        XCTAssertEqual(Set(knowledgeStore.items.values.map(\.displayName)), ["Project", "report.pdf"])
        XCTAssertEqual(Set(searchService.items.map(\.displayName)), ["Project", "report.pdf"])
        XCTAssertEqual(Set(searchService.items.map(\.status)), [.indexedOnly])
        XCTAssertTrue(searchService.items.allSatisfy { $0.tags.contains("downloads") })
        XCTAssertTrue(searchService.items.allSatisfy { $0.tags.contains(CaptureSource.existingLibraryScan.rawValue) })
        XCTAssertFalse(knowledgeStore.items.values.contains { $0.displayName == "inside.txt" })
        XCTAssertEqual(knowledgeStore.captureEvents.count, 2)
        XCTAssertEqual(Set(knowledgeStore.captureEvents.map(\.source)), [.existingLibraryScan])
        XCTAssertEqual(knowledgeStore.captureEvents.first?.sourceDetail["captureLocation"], "downloads")
        XCTAssertEqual(knowledgeStore.contexts.values.first?.kind, .folder)
        XCTAssertEqual(knowledgeStore.contexts.values.first?.name, "Downloads")
        XCTAssertEqual(knowledgeStore.relationshipsByID.values.count, 2)
        XCTAssertEqual(Set(knowledgeStore.relationshipsByID.values.map(\.predicate)), [.belongsTo])
        XCTAssertTrue(activityLog.events.contains { $0.kind == .indexed && $0.message.contains(fileURL.lastPathComponent) })
        XCTAssertTrue(activityLog.events.contains { $0.kind == .indexed && $0.message.contains(folderURL.lastPathComponent) })
        XCTAssertEqual(progressEvents.first?.phase, .preparing)
        XCTAssertEqual(progressEvents.last?.phase, .completed)
    }

    func testShallowScanDoesNotExplodeNestedFolderContents() async throws {
        let directory = try TemporaryDirectory(name: "cold-start-folder-\(UUID().uuidString)")
        let rootURL = try directory.createFolder(named: "Root")
        let topLevelFolder = try directory.createFolder(named: "Root/Project")
        _ = try directory.createFile(named: "Root/Project/inside.txt")
        let permissionID = UUID(uuidString: "60000000-0000-0000-0000-000000000002")!
        let permissionStore = MockPermissionStore()
        try await permissionStore.save(
            PermissionRecord(id: permissionID, scope: .watchedFolder, url: rootURL, state: .granted)
        )
        let knowledgeStore = MockKnowledgeStore()
        let scanner = DefaultColdStartScanner(
            permissionStore: permissionStore,
            inspector: FileSystemItemInspector(),
            knowledgeStore: knowledgeStore
        )

        _ = try await scanner.scan(ColdStartScanRequest(permissionRecordID: permissionID))

        XCTAssertEqual(knowledgeStore.items.count, 1)
        XCTAssertEqual(knowledgeStore.items.values.first?.currentURL?.lastPathComponent, topLevelFolder.lastPathComponent)
        XCTAssertEqual(knowledgeStore.items.values.first?.kind, .folder)
    }

    func testSourceAwareScanWritesSourceIDsToMemoryCaptureAndLibrary() async throws {
        let directory = try TemporaryDirectory(name: "cold-start-source-aware-\(UUID().uuidString)")
        let fixture = try directory.createWatchedSource()
        let permissionStore = MockPermissionStore()
        try await permissionStore.save(
            PermissionRecord(
                id: fixture.permissionRecord.id,
                scope: .watchedFolder,
                url: fixture.sourceURL,
                state: .granted,
                metadata: fixture.permissionRecord.metadata
            )
        )
        let knowledgeStore = MockKnowledgeStore()
        let searchService = MockSearchService()
        let scanner = DefaultColdStartScanner(
            permissionStore: permissionStore,
            inspector: FileSystemItemInspector(),
            knowledgeStore: knowledgeStore,
            searchService: searchService
        )

        let result = try await scanner.scan(
            ColdStartScanRequest(
                permissionRecordID: fixture.permissionRecord.id,
                sourceID: fixture.sourceRecord.id,
                receivedAt: TestClock.now,
                sourceDetail: fixture.sourceRecord.captureDetail
            )
        )

        XCTAssertEqual(result.scannedItemCount, 3)
        XCTAssertTrue(knowledgeStore.items.values.allSatisfy { $0.sourceID == fixture.sourceRecord.id })
        XCTAssertEqual(Set(knowledgeStore.captureEvents.map(\.source)), [.watchedFolder])
        XCTAssertTrue(knowledgeStore.captureEvents.allSatisfy { $0.sourceID == fixture.sourceRecord.id })
        XCTAssertTrue(searchService.items.allSatisfy { $0.tags.contains(CaptureSource.watchedFolder.rawValue) })
        XCTAssertTrue(searchService.items.allSatisfy { $0.tags.contains("source:\(fixture.sourceRecord.id.uuidString)") })
        XCTAssertFalse(searchService.items.contains { $0.displayName == fixture.nestedFileURL.lastPathComponent })
    }

    func testRetryingSourceAwareScanReusesKnowledgeItemIDs() async throws {
        let directory = try TemporaryDirectory(name: "cold-start-source-retry-\(UUID().uuidString)")
        let fixture = try directory.createWatchedSource()
        let permissionStore = MockPermissionStore()
        try await permissionStore.save(
            PermissionRecord(
                id: fixture.permissionRecord.id,
                scope: .watchedFolder,
                url: fixture.sourceURL,
                state: .granted,
                metadata: fixture.permissionRecord.metadata
            )
        )
        let knowledgeStore = MockKnowledgeStore()
        let scanner = DefaultColdStartScanner(
            permissionStore: permissionStore,
            inspector: FileSystemItemInspector(),
            knowledgeStore: knowledgeStore
        )
        let request = ColdStartScanRequest(
            permissionRecordID: fixture.permissionRecord.id,
            sourceID: fixture.sourceRecord.id,
            receivedAt: TestClock.now,
            sourceDetail: fixture.sourceRecord.captureDetail
        )

        _ = try await scanner.scan(request)
        _ = try await scanner.scan(request)

        XCTAssertEqual(knowledgeStore.items.count, 3)
        XCTAssertEqual(Set(knowledgeStore.items.values.map(\.sourceID)), [fixture.sourceRecord.id])
    }

    func testScanStoresExtractedMetadataSnapshotWhenServiceIsConfigured() async throws {
        let directory = try TemporaryDirectory(name: "cold-start-metadata-\(UUID().uuidString)")
        let rootURL = try directory.createFolder(named: "Root")
        let fileURL = try directory.createFile(named: "Root/notes.md", contents: "Research notes for invoice planning.")
        let permissionID = UUID(uuidString: "60000000-0000-0000-0000-000000000005")!
        let permissionStore = MockPermissionStore()
        try await permissionStore.save(
            PermissionRecord(id: permissionID, scope: .watchedFolder, url: rootURL, state: .granted)
        )
        let knowledgeStore = MockKnowledgeStore()
        let scanner = DefaultColdStartScanner(
            permissionStore: permissionStore,
            inspector: FileSystemItemInspector(),
            knowledgeStore: knowledgeStore,
            metadataExtractionService: DefaultMetadataExtractionService()
        )

        _ = try await scanner.scan(ColdStartScanRequest(permissionRecordID: permissionID))

        let itemID = try XCTUnwrap(knowledgeStore.items.values.first { $0.currentURL?.lastPathComponent == fileURL.lastPathComponent }?.id)
        XCTAssertTrue(knowledgeStore.metadataSnapshots[itemID]?["nl.tokens"]?.contains("research") == true)
    }

    func testPermissionFailureIsExplicit() async throws {
        let directory = try TemporaryDirectory(name: "cold-start-permission-\(UUID().uuidString)")
        let rootURL = try directory.createFolder(named: "Root")
        let permissionID = UUID(uuidString: "60000000-0000-0000-0000-000000000003")!
        let permissionStore = MockPermissionStore()
        try await permissionStore.save(
            PermissionRecord(id: permissionID, scope: .watchedFolder, url: rootURL, state: .missing)
        )
        let scanner = DefaultColdStartScanner(
            permissionStore: permissionStore,
            inspector: FileSystemItemInspector(),
            knowledgeStore: MockKnowledgeStore()
        )

        do {
            _ = try await scanner.scan(ColdStartScanRequest(permissionRecordID: permissionID))
            XCTFail("Expected permission failure.")
        } catch let error as ColdStartScannerError {
            XCTAssertEqual(error, .permissionRequired(permissionID, .missing))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCancellationStopsScanWithProgressCount() async throws {
        let directory = try TemporaryDirectory(name: "cold-start-cancel-\(UUID().uuidString)")
        let rootURL = try directory.createFolder(named: "Root")
        _ = try directory.createFile(named: "Root/one.txt")
        _ = try directory.createFile(named: "Root/two.txt")
        let permissionID = UUID(uuidString: "60000000-0000-0000-0000-000000000004")!
        let permissionStore = MockPermissionStore()
        try await permissionStore.save(
            PermissionRecord(id: permissionID, scope: .watchedFolder, url: rootURL, state: .granted)
        )
        let scanner = DefaultColdStartScanner(
            permissionStore: permissionStore,
            inspector: SlowItemInspector(),
            knowledgeStore: MockKnowledgeStore()
        )

        let task = Task {
            try await scanner.scan(ColdStartScanRequest(permissionRecordID: permissionID))
        }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation.")
        } catch let error as ColdStartScannerError {
            XCTAssertEqual(error, .cancelled(scannedCount: 0))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private final class SlowItemInspector: ItemInspector, @unchecked Sendable {
    func inspect(_ request: OrganizationRequest, options: InspectionOptions) async throws -> ItemProfile {
        try await Task.sleep(nanoseconds: 50_000_000)
        return try await FileSystemItemInspector().inspect(request, options: options)
    }
}

private actor ProgressRecorder {
    private var recordedEvents: [ColdStartScanProgress] = []

    var events: [ColdStartScanProgress] {
        recordedEvents
    }

    func append(_ progress: ColdStartScanProgress) {
        recordedEvents.append(progress)
    }
}
