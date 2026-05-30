import BipboxCore
import Foundation
import XCTest

enum TestClock {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
}

final class TemporaryDirectory {
    let url: URL

    init(name: String = UUID().uuidString) throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("BipboxTests", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    func createFile(named name: String, contents: String = "fixture") throws -> URL {
        let fileURL = url.appendingPathComponent(name, isDirectory: false)
        try contents.data(using: .utf8)?.write(to: fileURL)
        return fileURL
    }

    func createFile(named name: String, in folderURL: URL, contents: String = "fixture") throws -> URL {
        let fileURL = folderURL.appendingPathComponent(name, isDirectory: false)
        try contents.data(using: .utf8)?.write(to: fileURL)
        return fileURL
    }

    func createFolder(named name: String) throws -> URL {
        let folderURL = url.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        return folderURL
    }

    func createFolder(named name: String, in folderURL: URL) throws -> URL {
        let childFolderURL = folderURL.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: childFolderURL, withIntermediateDirectories: true)
        return childFolderURL
    }

    func createWatchedSource(named name: String = "Downloads") throws -> WatchedSourceFixture {
        let sourceURL = try createFolder(named: name)
        let topLevelFileURL = try createFile(
            named: "quarterly-report.pdf",
            in: sourceURL,
            contents: "Revenue and customer notes"
        )
        let topLevelFolderURL = try createFolder(named: "Client Project", in: sourceURL)
        let nestedFileURL = try createFile(
            named: "meeting-notes.md",
            in: topLevelFolderURL,
            contents: "Do not capture unless recursion is explicitly enabled"
        )
        let packageURL = try createFolder(named: "Prototype.app", in: sourceURL)
        _ = try createFile(named: "Info.plist", in: packageURL, contents: "<plist />")
        let missingURL = sourceURL.appendingPathComponent("missing.pdf", isDirectory: false)
        let permissionRecord = SourceFixtures.permissionRecord(url: sourceURL)
        let sourceRecord = SourceFixtures.watchedFolder(
            url: sourceURL,
            displayName: name,
            permissionRecordID: permissionRecord.id
        )
        return WatchedSourceFixture(
            sourceURL: sourceURL,
            topLevelFileURL: topLevelFileURL,
            topLevelFolderURL: topLevelFolderURL,
            packageURL: packageURL,
            nestedFileURL: nestedFileURL,
            missingURL: missingURL,
            permissionRecord: permissionRecord,
            sourceRecord: sourceRecord
        )
    }
}

struct WatchedSourceFixture {
    let sourceURL: URL
    let topLevelFileURL: URL
    let topLevelFolderURL: URL
    let packageURL: URL
    let nestedFileURL: URL
    let missingURL: URL
    let permissionRecord: PermissionRecord
    let sourceRecord: SourceRecord

    var topLevelCaptureURLs: [URL] {
        [topLevelFileURL, topLevelFolderURL, packageURL]
    }

    var recursiveCaptureURLs: [URL] {
        topLevelCaptureURLs + [nestedFileURL]
    }
}

enum SourceFixtures {
    static let watchedFolderID = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
    static let menuBarDropID = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
    static let manualImportID = UUID(uuidString: "20000000-0000-0000-0000-000000000003")!
    static let permissionID = UUID(uuidString: "20000000-0000-0000-0000-000000000004")!

    static func permissionRecord(
        id: UUID = permissionID,
        url: URL = URL(fileURLWithPath: "/tmp/Downloads", isDirectory: true),
        state: PermissionState = .granted
    ) -> PermissionRecord {
        PermissionRecord(
            id: id,
            scope: .watchedFolder,
            url: url,
            state: state,
            bookmarkData: Data("bookmark-\(id.uuidString)".utf8),
            metadata: ["fixture": "watched-source"]
        )
    }

    static func watchedFolder(
        id: UUID = watchedFolderID,
        url: URL = URL(fileURLWithPath: "/tmp/Downloads", isDirectory: true),
        displayName: String = "Downloads",
        permissionRecordID: UUID? = permissionID,
        enabled: Bool = true,
        recursivePolicy: SourceRecursivePolicy = .never,
        indexState: SourceIndexState = .completed,
        watchState: SourceWatchState = .running,
        scanSummary: SourceScanSummary? = scanSummary(),
        metadata: [String: String] = [:]
    ) -> SourceRecord {
        SourceRecord(
            id: id,
            kind: .watchedFolder,
            displayName: displayName,
            url: url,
            permissionRecordID: permissionRecordID,
            enabled: enabled,
            recursivePolicy: recursivePolicy,
            indexState: indexState,
            watchState: watchState,
            lastScanAt: TestClock.now,
            lastScanSummary: scanSummary,
            createdAt: TestClock.now,
            updatedAt: TestClock.now,
            metadata: ["fixture": "source"].merging(metadata) { _, new in new }
        )
    }

    static func menuBarDrop(
        id: UUID = menuBarDropID,
        enabled: Bool = true
    ) -> SourceRecord {
        SourceRecord.menuBarDrop(
            id: id,
            displayName: "Menu Bar Drop",
            enabled: enabled,
            createdAt: TestClock.now,
            metadata: ["fixture": "source"]
        )
    }

    static func manualImport(
        id: UUID = manualImportID,
        url: URL? = URL(fileURLWithPath: "/tmp/Manual", isDirectory: true),
        enabled: Bool = true
    ) -> SourceRecord {
        SourceRecord.manualImport(
            id: id,
            displayName: "Manual Import",
            url: url,
            enabled: enabled,
            createdAt: TestClock.now,
            metadata: ["fixture": "source"]
        )
    }

    static func scanSummary(
        discoveredCount: Int = 3,
        indexedCount: Int = 2,
        stagedCount: Int = 1,
        organizedCount: Int = 0,
        failedCount: Int = 0,
        message: String? = "Fixture scan completed."
    ) -> SourceScanSummary {
        SourceScanSummary(
            discoveredCount: discoveredCount,
            indexedCount: indexedCount,
            stagedCount: stagedCount,
            organizedCount: organizedCount,
            failedCount: failedCount,
            message: message
        )
    }
}

enum ItemFixtures {
    static func request(
        url: URL = URL(fileURLWithPath: "/tmp/report.pdf"),
        kind: ItemKind = .file,
        mode: OrganizationMode = .organize
    ) -> OrganizationRequest {
        OrganizationRequest(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
            source: .dragDrop,
            itemURL: url,
            itemKind: kind,
            receivedAt: TestClock.now,
            mode: mode
        )
    }

    static func fileProfile(url: URL = URL(fileURLWithPath: "/tmp/report.pdf")) -> ItemProfile {
        ItemProfile(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000002")!,
            url: url,
            kind: .file,
            displayName: url.lastPathComponent,
            fileExtension: url.pathExtension.isEmpty ? nil : url.pathExtension,
            uniformTypeIdentifier: "com.adobe.pdf",
            sizeBytes: 128,
            createdAt: TestClock.now,
            modifiedAt: TestClock.now,
            source: .dragDrop
        )
    }

    static func folderProfile(url: URL = URL(fileURLWithPath: "/tmp/Project")) -> ItemProfile {
        ItemProfile(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000003")!,
            url: url,
            kind: .folder,
            displayName: url.lastPathComponent,
            createdAt: TestClock.now,
            modifiedAt: TestClock.now,
            source: .dragDrop,
            folderChildSummary: FolderChildSummary(
                visibleChildCount: 2,
                visibleFileCount: 1,
                visibleFolderCount: 1,
                topLevelExtensions: ["pdf": 1],
                recursiveInspectionRequested: false
            )
        )
    }
}

enum MemoryFixtures {
    static let itemID = UUID(uuidString: "30000000-0000-0000-0000-000000000001")!
    static let requestID = UUID(uuidString: "30000000-0000-0000-0000-000000000002")!
    static let sessionID = UUID(uuidString: "30000000-0000-0000-0000-000000000003")!

    static func sourceAwareRequest(
        url: URL = URL(fileURLWithPath: "/tmp/Downloads/quarterly-report.pdf", isDirectory: false),
        kind: ItemKind = .file,
        source: SourceRecord = SourceFixtures.watchedFolder(),
        mode: OrganizationMode = .indexOnly
    ) -> OrganizationRequest {
        OrganizationRequest(
            id: requestID,
            source: IntakeSource(sourceKind: source.kind) ?? .automation,
            sourceID: source.id,
            itemURL: url,
            itemKind: kind,
            receivedAt: TestClock.now,
            mode: mode,
            userContext: source.captureDetail
        )
    }

    static func knowledgeItem(
        id: UUID = itemID,
        source: SourceRecord = SourceFixtures.watchedFolder(),
        url: URL = URL(fileURLWithPath: "/tmp/Downloads/quarterly-report.pdf", isDirectory: false),
        kind: ItemKind = .file,
        state: KnowledgeItemState = .active
    ) -> KnowledgeItem {
        KnowledgeItem(
            id: id,
            kind: kind,
            displayName: url.lastPathComponent,
            sourceID: source.id,
            currentURL: url,
            originalURL: url,
            contentFingerprint: "fixture-\(id.uuidString)",
            createdAt: TestClock.now,
            modifiedAt: TestClock.now,
            firstSeenAt: TestClock.now,
            lastSeenAt: TestClock.now,
            state: state
        )
    }

    static func captureEvent(
        itemID: UUID = itemID,
        source: SourceRecord = SourceFixtures.watchedFolder(),
        url: URL = URL(fileURLWithPath: "/tmp/Downloads/quarterly-report.pdf", isDirectory: false),
        mode: OrganizationMode = .indexOnly
    ) -> CaptureEvent {
        let request = sourceAwareRequest(url: url, source: source, mode: mode)
        return CaptureEvent.draft(
            from: request,
            sourceRecord: source,
            itemID: itemID,
            sessionID: sessionID,
            sourceDetail: ["fixture": "capture-event"]
        )
    }

    static func libraryItem(
        id: UUID = itemID,
        source: SourceRecord = SourceFixtures.watchedFolder(),
        path: String = "/tmp/Downloads/quarterly-report.pdf",
        name: String = "quarterly-report.pdf",
        kind: ItemKind = .file,
        status: IndexedItemStatus = .indexedOnly,
        tags: [String] = []
    ) -> IndexedItem {
        IndexedItem(
            id: id,
            currentPath: path,
            originalPath: path,
            displayName: name,
            kind: kind,
            uniformTypeIdentifier: kind == .folder ? nil : "com.adobe.pdf",
            sizeBytes: kind == .folder ? nil : 128,
            createdAt: TestClock.now,
            modifiedAt: TestClock.now,
            importedAt: TestClock.now,
            tags: [CaptureSource(sourceKind: source.kind).rawValue] + tags,
            extractedText: "Quarterly revenue customer notes",
            aiSummary: nil,
            status: status
        )
    }

    static func libraryResults(
        items: [IndexedItem] = [libraryItem()]
    ) -> SearchResults {
        SearchResults(items: items, totalCount: items.count)
    }
}

enum WorkflowFixtures {
    static func folderWorkflow(destination: URL = URL(fileURLWithPath: "/tmp/Bipbox/Projects")) -> Workflow {
        let action = ActionDescriptor(
            operationKind: .move,
            parameters: ["destination": destination.path],
            recursiveFolderProcessing: false
        )
        let actionNode = WorkflowNode(kind: .action, name: "Move Folder", actions: [action])
        let branch = WorkflowBranch(
            name: "Folder Items",
            conditions: [
                ConditionDescriptor(field: .itemKind, operation: .equals, value: ItemKind.folder.rawValue)
            ],
            node: actionNode
        )
        let fallback = WorkflowNode(kind: .review, name: "Needs Review")
        let root = WorkflowNode(kind: .router, name: "Root", branches: [branch], fallback: fallback)
        return Workflow(name: "Folder Workflow", root: root)
    }
}

final class MockIntakeService: IntakeService, @unchecked Sendable {
    private(set) var submitted: [OrganizationRequest] = []

    func submit(_ request: OrganizationRequest) async throws -> IntakeResult {
        submitted.append(request)
        return IntakeResult(request: request, accepted: true)
    }
}

final class MockItemInspector: ItemInspector, @unchecked Sendable {
    var profile: ItemProfile
    private(set) var requests: [OrganizationRequest] = []

    init(profile: ItemProfile) {
        self.profile = profile
    }

    func inspect(_ request: OrganizationRequest, options: InspectionOptions) async throws -> ItemProfile {
        requests.append(request)
        return profile
    }
}

final class MockItemStabilizer: ItemStabilizer, @unchecked Sendable {
    private(set) var requests: [OrganizationRequest] = []

    func waitUntilStable(_ request: OrganizationRequest) async throws -> OrganizationRequest {
        requests.append(request)
        return request
    }
}

final class MockWorkflowEngine: WorkflowEngine, @unchecked Sendable {
    var decision: RouteDecision
    private(set) var lastItem: ItemProfile?
    private(set) var lastContext: WorkflowEvaluationContext?

    init(decision: RouteDecision) {
        self.decision = decision
    }

    func evaluate(
        workflow: Workflow,
        item: ItemProfile,
        context: WorkflowEvaluationContext
    ) async throws -> RouteDecision {
        lastItem = item
        lastContext = context
        return decision
    }
}

final class MockOperationPlanner: OperationPlanner, @unchecked Sendable {
    var plan: OperationPlan

    init(plan: OperationPlan) {
        self.plan = plan
    }

    func plan(
        decision: RouteDecision,
        item: ItemProfile,
        context: PlanningContext
    ) async throws -> OperationPlan {
        plan
    }
}

final class MockOperationExecutor: OperationExecutor, @unchecked Sendable {
    private(set) var executedPlans: [OperationPlan] = []
    var errorToThrow: Error?

    func execute(_ plan: OperationPlan, context: ExecutionContext) async throws -> ExecutionResult {
        if let errorToThrow {
            throw errorToThrow
        }

        executedPlans.append(plan)
        let results = plan.operations.map {
            OperationExecutionResult(
                operationID: $0.id,
                status: .completed,
                resultingURL: $0.destinationURL,
                undoOperation: $0.reversible ? $0 : nil
            )
        }
        return ExecutionResult(planID: plan.id, operationResults: results)
    }
}

final class MockToolRegistry: ToolRegistry, @unchecked Sendable {
    private var descriptors: [String: ToolDescriptor] = [:]

    func register(_ descriptor: ToolDescriptor) async throws {
        descriptors[descriptor.name] = descriptor
    }

    func descriptor(named name: String) async -> ToolDescriptor? {
        descriptors[name]
    }

    func descriptors() async -> [ToolDescriptor] {
        descriptors.values.sorted { $0.name < $1.name }
    }

    func execute(_ call: ToolCall, context: ExecutionContext) async throws -> ToolResult {
        ToolResult(toolName: call.toolName, output: call.input, message: context.dryRun ? "dry-run" : nil)
    }
}

final class MockSearchService: SearchService, SearchIndexRemoving, @unchecked Sendable {
    private(set) var items: [IndexedItem] = []

    func index(_ item: IndexedItem) async throws {
        items.append(item)
    }

    func update(_ item: IndexedItem) async throws {
        items.removeAll { $0.id == item.id }
        items.append(item)
    }

    func remove(id: UUID) async throws {
        items.removeAll { $0.id == id }
    }

    func search(_ query: SearchQuery) async throws -> SearchResults {
        let matches = items.filter { item in
            let textMatches = query.text.isEmpty
                || item.displayName.localizedCaseInsensitiveContains(query.text)
                || item.currentPath.localizedCaseInsensitiveContains(query.text)
                || item.originalPath?.localizedCaseInsensitiveContains(query.text) == true
                || item.extractedText?.localizedCaseInsensitiveContains(query.text) == true
                || item.tags.contains { $0.localizedCaseInsensitiveContains(query.text) }
            let kindMatches = query.kinds.isEmpty || query.kinds.contains(item.kind)
            let typeMatches = query.uniformTypeIdentifiers.isEmpty
                || query.uniformTypeIdentifiers.contains(item.uniformTypeIdentifier ?? "")
            let tagMatches = query.tags.isEmpty || !Set(query.tags).isDisjoint(with: Set(item.tags))
            let statusMatches = query.statuses.isEmpty || query.statuses.contains(item.status)
            let importedFromMatches = query.importedFrom.map { item.importedAt >= $0 } ?? true
            let importedThroughMatches = query.importedThrough.map { item.importedAt <= $0 } ?? true
            return textMatches && kindMatches && typeMatches && tagMatches && statusMatches && importedFromMatches && importedThroughMatches
        }
        return SearchResults(items: Array(matches.prefix(query.limit)), totalCount: matches.count)
    }
}

final class MockKnowledgeStore: KnowledgeStore, @unchecked Sendable {
    private(set) var items: [UUID: KnowledgeItem] = [:]
    private(set) var captureEvents: [CaptureEvent] = []
    private(set) var contexts: [UUID: ContextNode] = [:]
    private(set) var relationshipsByID: [UUID: RelationshipEdge] = [:]
    private(set) var collections: [UUID: KnowledgeCollection] = [:]
    private(set) var collectionMemberships: [UUID: [UUID]] = [:]
    private(set) var metadataSnapshots: [UUID: [String: String]] = [:]

    func upsertKnowledgeItem(_ item: KnowledgeItem) async throws {
        items[item.id] = item
    }

    func knowledgeItem(id: UUID) async throws -> KnowledgeItem? {
        items[id]
    }

    func appendCaptureEvent(_ event: CaptureEvent) async throws {
        captureEvents.append(event)
    }

    func captureEvents(itemID: UUID) async throws -> [CaptureEvent] {
        captureEvents.filter { $0.itemID == itemID }
    }

    func captureEvents(sessionID: UUID) async throws -> [CaptureEvent] {
        captureEvents.filter { $0.sessionID == sessionID }
    }

    func upsertContext(_ context: ContextNode) async throws {
        contexts[context.id] = context
    }

    func context(id: UUID) async throws -> ContextNode? {
        contexts[id]
    }

    func upsertRelationship(_ relationship: RelationshipEdge) async throws {
        relationshipsByID[relationship.id] = relationship
    }

    func relationships(subjectID: UUID) async throws -> [RelationshipEdge] {
        relationshipsByID.values.filter { $0.subjectID == subjectID }
    }

    func relationships(objectID: UUID) async throws -> [RelationshipEdge] {
        relationshipsByID.values.filter { $0.objectID == objectID }
    }

    func upsertCollection(_ collection: KnowledgeCollection) async throws {
        collections[collection.id] = collection
    }

    func collection(id: UUID) async throws -> KnowledgeCollection? {
        collections[id]
    }

    func collections() async throws -> [KnowledgeCollection] {
        collections.values.sorted {
            if $0.name == $1.name {
                return $0.id.uuidString < $1.id.uuidString
            }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    func addItem(_ itemID: UUID, toCollection collectionID: UUID, createdAt: Date) async throws {
        var itemIDs = collectionMemberships[collectionID, default: []]
        if !itemIDs.contains(itemID) {
            itemIDs.append(itemID)
        }
        collectionMemberships[collectionID] = itemIDs
    }

    func removeItem(_ itemID: UUID, fromCollection collectionID: UUID) async throws {
        collectionMemberships[collectionID]?.removeAll { $0 == itemID }
    }

    func collectionItemIDs(collectionID: UUID) async throws -> [UUID] {
        collectionMemberships[collectionID] ?? []
    }

    func upsertMetadataSnapshot(itemID: UUID, metadata: [String: String], capturedAt: Date) async throws {
        metadataSnapshots[itemID] = metadata
    }

    func metadataSnapshot(itemID: UUID) async throws -> [String: String]? {
        metadataSnapshots[itemID]
    }
}

final class MockActivityLog: ActivityLog, @unchecked Sendable {
    private(set) var events: [ActivityEvent] = []

    func append(_ event: ActivityEvent) async throws {
        events.append(event)
    }

    func recent(limit: Int) async throws -> [ActivityEvent] {
        Array(events.suffix(limit).reversed())
    }

    func events(forItemID itemID: UUID) async throws -> [ActivityEvent] {
        events.filter { $0.itemID == itemID }
    }
}

final class MockPermissionStore: PermissionStore, @unchecked Sendable {
    private(set) var permissionRecords: [PermissionRecord] = []

    func save(_ record: PermissionRecord) async throws {
        permissionRecords.removeAll { $0.id == record.id }
        permissionRecords.append(record)
    }

    func remove(id: UUID) async throws {
        permissionRecords.removeAll { $0.id == id }
    }

    func records(scope: PermissionScope?) async throws -> [PermissionRecord] {
        guard let scope else { return permissionRecords }
        return permissionRecords.filter { $0.scope == scope }
    }
}

final class MockSourceStore: SourceStore, @unchecked Sendable {
    private(set) var sourceRecords: [SourceRecord]

    init(sourceRecords: [SourceRecord] = []) {
        self.sourceRecords = []
        for source in sourceRecords {
            try? validate(source)
            self.sourceRecords.append(source)
        }
    }

    @discardableResult
    func upsert(_ source: SourceRecord) async throws -> SourceStoreChange {
        try validate(source)
        if let url = source.url {
            let standardizedPath = url.standardizedFileURL.path
            if sourceRecords.contains(where: { $0.id != source.id && $0.url?.standardizedFileURL.path == standardizedPath }) {
                throw SourceStoreError.duplicatePath(url)
            }
        }

        if let index = sourceRecords.firstIndex(where: { $0.id == source.id }) {
            sourceRecords[index] = source
            return .updated(source)
        }

        sourceRecords.append(source)
        return .inserted(source)
    }

    @discardableResult
    func remove(id: UUID) async throws -> SourceStoreChange {
        guard let index = sourceRecords.firstIndex(where: { $0.id == id }) else {
            throw SourceStoreError.missingSource(id)
        }
        let removed = sourceRecords.remove(at: index)
        return .removed(removed)
    }

    func source(id: UUID) async throws -> SourceRecord? {
        sourceRecords.first { $0.id == id }
    }

    func sources() async throws -> [SourceRecord] {
        sourceRecords.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    func enabledSources(kind: SourceKind?) async throws -> [SourceRecord] {
        try await sources().filter { source in
            source.enabled && (kind == nil || source.kind == kind)
        }
    }

    private func validate(_ source: SourceRecord) throws {
        guard let url = source.url else {
            return
        }
        guard url.isFileURL else {
            throw SourceStoreError.invalidURL(url)
        }
    }
}

final class MockAppSettingsStore: AppSettingsStore, @unchecked Sendable {
    var settings: AppSettings

    init(settings: AppSettings = .defaults) {
        self.settings = settings
    }

    func load() async throws -> AppSettings {
        settings
    }

    func save(_ settings: AppSettings) async throws {
        self.settings = settings
    }
}

final class MockAIOrchestrator: AIOrchestrator, @unchecked Sendable {
    var classification = AIClassification(
        confidence: 0,
        reason: "No model configured.",
        reviewRequirement: .required
    )

    func classify(_ request: AIRequest) async throws -> AIClassification {
        classification
    }

    func callTool(_ call: ToolCall, context: ExecutionContext) async throws -> ToolResult {
        ToolResult(toolName: call.toolName, output: call.input)
    }
}
