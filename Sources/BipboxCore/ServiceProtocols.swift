import Foundation

public protocol IntakeService: Sendable {
    func submit(_ request: OrganizationRequest) async throws -> IntakeResult
}

public protocol FolderWatcher {
    var state: FolderWatcherState { get async }
    func start() async throws
    func pause() async
    func resume() async throws
    func stop() async
}

public protocol DropIntakeHandling: Sendable {
    func submit(
        fileURLs: [URL],
        source: IntakeSource,
        mode: OrganizationMode,
        receivedAt: Date
    ) async -> DropIntakeSummary
}

public protocol ItemInspector {
    func inspect(_ request: OrganizationRequest, options: InspectionOptions) async throws -> ItemProfile
}

public protocol ItemStabilizer {
    func waitUntilStable(_ request: OrganizationRequest) async throws -> OrganizationRequest
}

public protocol WorkflowEngine {
    func evaluate(
        workflow: Workflow,
        item: ItemProfile,
        context: WorkflowEvaluationContext
    ) async throws -> RouteDecision
}

public protocol OperationPlanner {
    func plan(
        decision: RouteDecision,
        item: ItemProfile,
        context: PlanningContext
    ) async throws -> OperationPlan
}

public protocol OperationExecutor {
    func execute(_ plan: OperationPlan, context: ExecutionContext) async throws -> ExecutionResult
}

public protocol ToolRegistry: Sendable {
    func register(_ descriptor: ToolDescriptor) async throws
    func descriptor(named name: String) async -> ToolDescriptor?
    func descriptors() async -> [ToolDescriptor]
    func execute(_ call: ToolCall, context: ExecutionContext) async throws -> ToolResult
}

public protocol SearchService: Sendable {
    func index(_ item: IndexedItem) async throws
    func update(_ item: IndexedItem) async throws
    func search(_ query: SearchQuery) async throws -> SearchResults
}

public protocol SearchIndexRemoving: Sendable {
    func remove(id: UUID) async throws
}

public protocol KnowledgeItemStore: Sendable {
    func upsertKnowledgeItem(_ item: KnowledgeItem) async throws
    func knowledgeItem(id: UUID) async throws -> KnowledgeItem?
}

public protocol CaptureEventStore: Sendable {
    func appendCaptureEvent(_ event: CaptureEvent) async throws
    func captureEvents(itemID: UUID) async throws -> [CaptureEvent]
    func captureEvents(sessionID: UUID) async throws -> [CaptureEvent]
}

public protocol RelationshipStore: Sendable {
    func upsertContext(_ context: ContextNode) async throws
    func context(id: UUID) async throws -> ContextNode?
    func upsertRelationship(_ relationship: RelationshipEdge) async throws
    func relationships(subjectID: UUID) async throws -> [RelationshipEdge]
    func relationships(objectID: UUID) async throws -> [RelationshipEdge]
}

public protocol CollectionStore: Sendable {
    func upsertCollection(_ collection: KnowledgeCollection) async throws
    func collection(id: UUID) async throws -> KnowledgeCollection?
    func collections() async throws -> [KnowledgeCollection]
    func addItem(_ itemID: UUID, toCollection collectionID: UUID, createdAt: Date) async throws
    func removeItem(_ itemID: UUID, fromCollection collectionID: UUID) async throws
    func collectionItemIDs(collectionID: UUID) async throws -> [UUID]
}

public protocol MetadataSnapshotStore: Sendable {
    func upsertMetadataSnapshot(itemID: UUID, metadata: [String: String], capturedAt: Date) async throws
    func metadataSnapshot(itemID: UUID) async throws -> [String: String]?
}

public typealias KnowledgeStore = KnowledgeItemStore
    & CaptureEventStore
    & RelationshipStore
    & CollectionStore
    & MetadataSnapshotStore

public protocol KnowledgeGraphService: Sendable {
    func upsertContext(_ context: ContextNode) async throws
    func context(id: UUID) async throws -> ContextNode?
    func relate(
        subjectID: UUID,
        subjectKind: GraphNodeKind,
        predicate: RelationshipPredicate,
        objectID: UUID,
        objectKind: GraphNodeKind,
        confidence: ConfidenceScore,
        provenance: GraphProvenance,
        now: Date
    ) async throws -> RelationshipEdge
    func relationships(subjectID: UUID) async throws -> [RelationshipEdge]
    func relationships(objectID: UUID) async throws -> [RelationshipEdge]
    func contexts(relatedTo itemID: UUID) async throws -> [ContextRelationship]
    func upsertCollection(_ collection: KnowledgeCollection) async throws
    func collection(id: UUID) async throws -> KnowledgeCollection?
    func collections() async throws -> [KnowledgeCollection]
    func addItem(_ itemID: UUID, toCollection collectionID: UUID, createdAt: Date) async throws
    func removeItem(_ itemID: UUID, fromCollection collectionID: UUID) async throws
    func itemIDs(inCollection collectionID: UUID) async throws -> [UUID]
}

public protocol RelatednessService: Sendable {
    func relatedItems(to itemID: UUID, limit: Int) async throws -> [RelatedItem]
}

public protocol RetrievalService: Sendable {
    func retrieve(_ query: RetrievalQuery) async throws -> RetrievalResults
}

public protocol MissingFileRecoveryService: Sendable {
    func refreshStatus(itemID: UUID) async throws -> LibraryRecoveryResult
    func locate(itemID: UUID, at url: URL) async throws -> LibraryRecoveryResult
    func removeFromLibrary(itemID: UUID) async throws
    func reindex(itemID: UUID) async throws -> LibraryRecoveryResult
}

public protocol RelatedContextService: Sendable {
    func overview(for itemID: UUID, relatedLimit: Int) async throws -> RelatedContextOverview
}

public protocol ColdStartScanner: Sendable {
    func scan(
        _ request: ColdStartScanRequest,
        progress: (@Sendable (ColdStartScanProgress) async -> Void)?
    ) async throws -> ColdStartScanResult
}

public protocol MetadataExtractionService: Sendable {
    func extractMetadata(for item: ItemProfile) async throws -> MetadataExtractionResult
}

public protocol ActivityLog: Sendable {
    func append(_ event: ActivityEvent) async throws
    func recent(limit: Int) async throws -> [ActivityEvent]
    func events(forItemID itemID: UUID) async throws -> [ActivityEvent]
}

public protocol PermissionStore: Sendable {
    func save(_ record: PermissionRecord) async throws
    func remove(id: UUID) async throws
    func records(scope: PermissionScope?) async throws -> [PermissionRecord]
}

public protocol SourceStore: Sendable {
    @discardableResult
    func upsert(_ source: SourceRecord) async throws -> SourceStoreChange
    @discardableResult
    func remove(id: UUID) async throws -> SourceStoreChange
    func source(id: UUID) async throws -> SourceRecord?
    func sources() async throws -> [SourceRecord]
    func enabledSources(kind: SourceKind?) async throws -> [SourceRecord]
}

public protocol SourceWatcherReloading: Sendable {
    func reloadWatchedFolders() async throws
}

public protocol SourceLifecycleCoordinating: Sendable {
    @discardableResult
    func addWatchedFolder(_ request: SourceLifecycleRequest) async throws -> SourceLifecycleResult
    @discardableResult
    func changeWatchedFolder(id: UUID, to request: SourceLifecycleRequest) async throws -> SourceLifecycleResult
    @discardableResult
    func removeSource(id: UUID, removePermission: Bool) async throws -> SourceLifecycleResult
    @discardableResult
    func scanSource(id: UUID) async throws -> SourceLifecycleResult
    @discardableResult
    func pauseSource(id: UUID) async throws -> SourceLifecycleResult
    @discardableResult
    func resumeSource(id: UUID) async throws -> SourceLifecycleResult
    /// Observe per-item scan progress for every scan this coordinator runs
    /// (initial scans, rescans, watcher-triggered). Called with the source's
    /// display name + the scanner's progress.
    func setScanProgress(_ handler: (@Sendable (String, ColdStartScanProgress) async -> Void)?) async
}

public extension SourceLifecycleCoordinating {
    /// Default: scan progress is not observed.
    func setScanProgress(_ handler: (@Sendable (String, ColdStartScanProgress) async -> Void)?) async {}
}

public protocol AIOrchestrator: Sendable {
    func classify(_ request: AIRequest) async throws -> AIClassification
    func callTool(_ call: ToolCall, context: ExecutionContext) async throws -> ToolResult
}

public protocol AgentOrchestrator: Sendable {
    func respond(to request: AgentRequest, context: ExecutionContext) async throws -> AgentResponse
}
