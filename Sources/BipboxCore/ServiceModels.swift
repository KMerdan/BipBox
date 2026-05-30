import Foundation

public struct IntakeResult: Codable, Equatable, Sendable {
    public var request: OrganizationRequest
    public var accepted: Bool
    public var message: String?

    public init(request: OrganizationRequest, accepted: Bool, message: String? = nil) {
        self.request = request
        self.accepted = accepted
        self.message = message
    }
}

public struct DropIntakeFailure: Codable, Equatable, Sendable {
    public var itemURL: URL?
    public var message: String

    public init(itemURL: URL?, message: String) {
        self.itemURL = itemURL
        self.message = message
    }
}

public struct DropIntakeSummary: Codable, Equatable, Sendable {
    public var results: [IntakeResult]
    public var failures: [DropIntakeFailure]

    public init(results: [IntakeResult] = [], failures: [DropIntakeFailure] = []) {
        self.results = results
        self.failures = failures
    }

    public var acceptedCount: Int {
        results.filter(\.accepted).count
    }

    public var hasFailures: Bool {
        !failures.isEmpty
    }
}

public struct InspectionOptions: Codable, Equatable, Sendable {
    public var includeContentHash: Bool
    public var includeShallowFolderSummary: Bool
    public var allowRecursiveFolderInspection: Bool

    public init(
        includeContentHash: Bool = false,
        includeShallowFolderSummary: Bool = true,
        allowRecursiveFolderInspection: Bool = false
    ) {
        self.includeContentHash = includeContentHash
        self.includeShallowFolderSummary = includeShallowFolderSummary
        self.allowRecursiveFolderInspection = allowRecursiveFolderInspection
    }
}

public struct FolderWatchConfiguration: Codable, Equatable, Sendable {
    public var folderURL: URL
    public var sourceID: UUID?
    public var source: IntakeSource
    public var mode: OrganizationMode
    public var sourceDetail: [String: String]

    public init(
        folderURL: URL,
        sourceID: UUID? = nil,
        source: IntakeSource = .watchedFolder,
        mode: OrganizationMode = .organize,
        sourceDetail: [String: String] = [:]
    ) {
        self.folderURL = folderURL
        self.sourceID = sourceID
        self.source = source
        self.mode = mode
        self.sourceDetail = sourceDetail
    }
}

public enum FolderWatcherState: String, Codable, Equatable, Sendable {
    case stopped
    case running
    case paused
}

public struct WorkflowEvaluationContext: Codable, Equatable, Sendable {
    public var mode: OrganizationMode
    public var now: Date
    public var sourceID: UUID?
    public var sourceFacts: [String: String]
    public var collectionNames: [String]
    public var contextNames: [String]

    public init(
        mode: OrganizationMode,
        now: Date,
        sourceID: UUID? = nil,
        sourceFacts: [String: String] = [:],
        collectionNames: [String] = [],
        contextNames: [String] = []
    ) {
        self.mode = mode
        self.now = now
        self.sourceID = sourceID
        self.sourceFacts = sourceFacts
        self.collectionNames = collectionNames
        self.contextNames = contextNames
    }
}

public struct PlanningContext: Codable, Equatable, Sendable {
    public var libraryRootURL: URL?
    public var now: Date

    public init(libraryRootURL: URL? = nil, now: Date) {
        self.libraryRootURL = libraryRootURL
        self.now = now
    }
}

public struct ExecutionContext: Codable, Equatable, Sendable {
    public var dryRun: Bool
    public var actor: String

    public init(dryRun: Bool = false, actor: String = "app") {
        self.dryRun = dryRun
        self.actor = actor
    }
}

public enum OperationExecutionStatus: String, Codable, Equatable, CaseIterable, Sendable {
    case completed
    case skipped
    case failed
}

public struct OperationExecutionResult: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var operationID: UUID
    public var status: OperationExecutionStatus
    public var resultingURL: URL?
    public var message: String?
    public var undoOperation: Operation?

    public init(
        id: UUID = UUID(),
        operationID: UUID,
        status: OperationExecutionStatus,
        resultingURL: URL? = nil,
        message: String? = nil,
        undoOperation: Operation? = nil
    ) {
        self.id = id
        self.operationID = operationID
        self.status = status
        self.resultingURL = resultingURL
        self.message = message
        self.undoOperation = undoOperation
    }
}

public struct ExecutionResult: Codable, Equatable, Sendable {
    public var planID: UUID
    public var operationResults: [OperationExecutionResult]

    public init(planID: UUID, operationResults: [OperationExecutionResult]) {
        self.planID = planID
        self.operationResults = operationResults
    }
}

public enum ToolPermission: String, Codable, Equatable, CaseIterable, Sendable {
    case read
    case plan
    case write
    case ruleWrite
    case external
}

public struct ToolDescriptor: Codable, Equatable, Identifiable, Sendable {
    public var id: String { name }
    public var name: String
    public var description: String
    public var inputSchema: String
    public var outputSchema: String
    public var permissions: [ToolPermission]
    public var dryRunSupported: Bool
    public var reversible: Bool

    public init(
        name: String,
        description: String,
        inputSchema: String,
        outputSchema: String,
        permissions: [ToolPermission],
        dryRunSupported: Bool,
        reversible: Bool
    ) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
        self.outputSchema = outputSchema
        self.permissions = permissions
        self.dryRunSupported = dryRunSupported
        self.reversible = reversible
    }
}

public struct ToolCall: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var toolName: String
    public var input: [String: String]
    public var requestedPermissions: [ToolPermission]
    public var dryRun: Bool

    public init(
        id: UUID = UUID(),
        toolName: String,
        input: [String: String],
        requestedPermissions: [ToolPermission],
        dryRun: Bool = false
    ) {
        self.id = id
        self.toolName = toolName
        self.input = input
        self.requestedPermissions = requestedPermissions
        self.dryRun = dryRun
    }
}

public struct ToolResult: Codable, Equatable, Sendable {
    public var toolName: String
    public var output: [String: String]
    public var message: String?

    public init(toolName: String, output: [String: String] = [:], message: String? = nil) {
        self.toolName = toolName
        self.output = output
        self.message = message
    }
}

public enum AgentMode: String, Codable, Equatable, CaseIterable, Sendable {
    case explain
    case propose
    case simulate
    case requestApproval
}

public enum AgentPlanStepStatus: String, Codable, Equatable, CaseIterable, Sendable {
    case proposed
    case simulated
    case requiresApproval
    case executed
    case failed
}

public struct AgentRequest: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var intent: String
    public var mode: AgentMode
    public var proposedToolCalls: [ToolCall]
    public var approvedToolCallIDs: [UUID]
    public var context: [String: String]

    public init(
        id: UUID = UUID(),
        intent: String,
        mode: AgentMode,
        proposedToolCalls: [ToolCall] = [],
        approvedToolCallIDs: [UUID] = [],
        context: [String: String] = [:]
    ) {
        self.id = id
        self.intent = intent
        self.mode = mode
        self.proposedToolCalls = proposedToolCalls
        self.approvedToolCallIDs = approvedToolCallIDs
        self.context = context
    }
}

public struct AgentPlanStep: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var toolCall: ToolCall
    public var status: AgentPlanStepStatus
    public var requiresApproval: Bool
    public var result: ToolResult?
    public var message: String?

    public init(
        id: UUID = UUID(),
        toolCall: ToolCall,
        status: AgentPlanStepStatus,
        requiresApproval: Bool,
        result: ToolResult? = nil,
        message: String? = nil
    ) {
        self.id = id
        self.toolCall = toolCall
        self.status = status
        self.requiresApproval = requiresApproval
        self.result = result
        self.message = message
    }
}

public struct AgentPlan: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var intent: String
    public var steps: [AgentPlanStep]

    public init(id: UUID = UUID(), intent: String, steps: [AgentPlanStep] = []) {
        self.id = id
        self.intent = intent
        self.steps = steps
    }
}

public struct AgentResponse: Codable, Equatable, Sendable {
    public var mode: AgentMode
    public var explanation: String
    public var availableTools: [ToolDescriptor]
    public var proposedPlan: AgentPlan
    public var dryRunResults: [ToolResult]
    public var requiredApprovals: [ToolCall]
    public var executionSummary: String?

    public init(
        mode: AgentMode,
        explanation: String,
        availableTools: [ToolDescriptor],
        proposedPlan: AgentPlan,
        dryRunResults: [ToolResult] = [],
        requiredApprovals: [ToolCall] = [],
        executionSummary: String? = nil
    ) {
        self.mode = mode
        self.explanation = explanation
        self.availableTools = availableTools
        self.proposedPlan = proposedPlan
        self.dryRunResults = dryRunResults
        self.requiredApprovals = requiredApprovals
        self.executionSummary = executionSummary
    }
}

public struct SearchQuery: Codable, Equatable, Sendable {
    public var text: String
    public var kinds: [ItemKind]
    public var uniformTypeIdentifiers: [String]
    public var tags: [String]
    public var statuses: [IndexedItemStatus]
    public var importedFrom: Date?
    public var importedThrough: Date?
    public var limit: Int

    public init(
        text: String,
        kinds: [ItemKind] = [],
        uniformTypeIdentifiers: [String] = [],
        tags: [String] = [],
        statuses: [IndexedItemStatus] = [],
        importedFrom: Date? = nil,
        importedThrough: Date? = nil,
        limit: Int = 50
    ) {
        self.text = text
        self.kinds = kinds
        self.uniformTypeIdentifiers = uniformTypeIdentifiers
        self.tags = tags
        self.statuses = statuses
        self.importedFrom = importedFrom
        self.importedThrough = importedThrough
        self.limit = limit
    }
}

public struct SearchResults: Codable, Equatable, Sendable {
    public var items: [IndexedItem]
    public var totalCount: Int

    public init(items: [IndexedItem], totalCount: Int) {
        self.items = items
        self.totalCount = totalCount
    }
}

public enum ActivityEventKind: String, Codable, Equatable, CaseIterable, Sendable {
    case requestReceived
    case inspected
    case routed
    case planned
    case executed
    case indexed
    case failed
    case undoExecuted
    case captured
    case relationshipRecorded
    case ruleMatched
    case reviewDecision
    case filesystemOperation
    case error
    case toolCall
}

public struct ActivityEvent: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var kind: ActivityEventKind
    public var itemID: UUID?
    public var requestID: UUID?
    public var planID: UUID?
    public var sourceID: UUID?
    public var message: String
    public var occurredAt: Date
    public var undoOperation: Operation?
    public var metadata: [String: String]

    public init(
        id: UUID = UUID(),
        kind: ActivityEventKind,
        itemID: UUID? = nil,
        requestID: UUID? = nil,
        planID: UUID? = nil,
        sourceID: UUID? = nil,
        message: String,
        occurredAt: Date,
        undoOperation: Operation? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.kind = kind
        self.itemID = itemID
        self.requestID = requestID
        self.planID = planID
        self.sourceID = sourceID
        self.message = message
        self.occurredAt = occurredAt
        self.undoOperation = undoOperation
        self.metadata = metadata
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case itemID
        case requestID
        case planID
        case sourceID
        case message
        case occurredAt
        case undoOperation
        case metadata
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(ActivityEventKind.self, forKey: .kind)
        itemID = try container.decodeIfPresent(UUID.self, forKey: .itemID)
        requestID = try container.decodeIfPresent(UUID.self, forKey: .requestID)
        planID = try container.decodeIfPresent(UUID.self, forKey: .planID)
        sourceID = try container.decodeIfPresent(UUID.self, forKey: .sourceID)
        message = try container.decode(String.self, forKey: .message)
        occurredAt = try container.decode(Date.self, forKey: .occurredAt)
        undoOperation = try container.decodeIfPresent(Operation.self, forKey: .undoOperation)
        metadata = try container.decodeIfPresent([String: String].self, forKey: .metadata) ?? [:]
    }
}

public enum PermissionScope: String, Codable, Equatable, CaseIterable, Sendable {
    case libraryRoot
    case watchedFolder
}

public enum PermissionState: String, Codable, Equatable, CaseIterable, Sendable {
    case granted
    case missing
    case stale
}

public enum CommonCaptureLocation: String, Codable, Equatable, CaseIterable, Sendable {
    case downloads
    case desktop

    public var displayName: String {
        switch self {
        case .downloads:
            "Downloads"
        case .desktop:
            "Desktop"
        }
    }

    public var searchPathDirectory: FileManager.SearchPathDirectory {
        switch self {
        case .downloads:
            .downloadsDirectory
        case .desktop:
            .desktopDirectory
        }
    }
}

public struct PermissionRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var scope: PermissionScope
    public var url: URL
    public var state: PermissionState
    public var bookmarkData: Data?
    public var message: String?
    public var metadata: [String: String]

    public init(
        id: UUID = UUID(),
        scope: PermissionScope,
        url: URL,
        state: PermissionState,
        bookmarkData: Data? = nil,
        message: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.scope = scope
        self.url = url
        self.state = state
        self.bookmarkData = bookmarkData
        self.message = message
        self.metadata = metadata
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case scope
        case url
        case state
        case bookmarkData
        case message
        case metadata
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        scope = try container.decode(PermissionScope.self, forKey: .scope)
        url = try container.decode(URL.self, forKey: .url)
        state = try container.decode(PermissionState.self, forKey: .state)
        bookmarkData = try container.decodeIfPresent(Data.self, forKey: .bookmarkData)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        metadata = try container.decodeIfPresent([String: String].self, forKey: .metadata) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(scope, forKey: .scope)
        try container.encode(url, forKey: .url)
        try container.encode(state, forKey: .state)
        try container.encodeIfPresent(bookmarkData, forKey: .bookmarkData)
        try container.encodeIfPresent(message, forKey: .message)
        try container.encode(metadata, forKey: .metadata)
    }
}

public struct WatchedFolderStatus: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var url: URL
    public var state: FolderWatcherState
    public var permissionState: PermissionState
    public var captureLocation: CommonCaptureLocation?
    public var message: String?

    public init(
        id: UUID,
        url: URL,
        state: FolderWatcherState,
        permissionState: PermissionState,
        captureLocation: CommonCaptureLocation? = nil,
        message: String? = nil
    ) {
        self.id = id
        self.url = url
        self.state = state
        self.permissionState = permissionState
        self.captureLocation = captureLocation
        self.message = message
    }
}

public enum ColdStartScanPhase: String, Codable, Equatable, Sendable {
    case preparing
    case scanning
    case completed
}

public struct ColdStartScanRequest: Codable, Equatable, Sendable {
    public var permissionRecordID: UUID
    public var sourceID: UUID?
    public var recursive: Bool
    public var receivedAt: Date
    public var sessionID: UUID
    public var sourceDetail: [String: String]

    public init(
        permissionRecordID: UUID,
        sourceID: UUID? = nil,
        recursive: Bool = false,
        receivedAt: Date = Date(),
        sessionID: UUID = UUID(),
        sourceDetail: [String: String] = [:]
    ) {
        self.permissionRecordID = permissionRecordID
        self.sourceID = sourceID
        self.recursive = recursive
        self.receivedAt = receivedAt
        self.sessionID = sessionID
        self.sourceDetail = sourceDetail
    }
}

public struct ColdStartScanProgress: Codable, Equatable, Sendable {
    public var phase: ColdStartScanPhase
    public var scannedCount: Int
    public var totalCount: Int?
    public var currentURL: URL?
    public var message: String?

    public init(
        phase: ColdStartScanPhase,
        scannedCount: Int,
        totalCount: Int? = nil,
        currentURL: URL? = nil,
        message: String? = nil
    ) {
        self.phase = phase
        self.scannedCount = scannedCount
        self.totalCount = totalCount
        self.currentURL = currentURL
        self.message = message
    }
}

public struct ColdStartScanFailure: Codable, Equatable, Sendable {
    public var url: URL
    public var message: String

    public init(url: URL, message: String) {
        self.url = url
        self.message = message
    }
}

public struct ColdStartScanResult: Codable, Equatable, Sendable {
    public var sessionID: UUID
    public var rootURL: URL
    public var scannedItemCount: Int
    public var contextCount: Int
    public var failures: [ColdStartScanFailure]

    public init(
        sessionID: UUID,
        rootURL: URL,
        scannedItemCount: Int,
        contextCount: Int,
        failures: [ColdStartScanFailure] = []
    ) {
        self.sessionID = sessionID
        self.rootURL = rootURL
        self.scannedItemCount = scannedItemCount
        self.contextCount = contextCount
        self.failures = failures
    }
}

public struct MetadataExtractionResult: Codable, Equatable, Sendable {
    public var metadata: [String: String]
    public var warnings: [String]

    public init(metadata: [String: String] = [:], warnings: [String] = []) {
        self.metadata = metadata
        self.warnings = warnings
    }
}

public struct AIRequest: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var itemProfile: ItemProfile
    public var allowedTools: [String]
    public var remoteContentSharingAllowed: Bool

    public init(
        id: UUID = UUID(),
        itemProfile: ItemProfile,
        allowedTools: [String] = [],
        remoteContentSharingAllowed: Bool = false
    ) {
        self.id = id
        self.itemProfile = itemProfile
        self.allowedTools = allowedTools
        self.remoteContentSharingAllowed = remoteContentSharingAllowed
    }
}

public struct AIClassification: Codable, Equatable, Sendable {
    public var category: String?
    public var suggestedDestinationURL: URL?
    public var confidence: Double
    public var reason: String
    public var requiredTools: [String]
    public var reviewRequirement: ReviewRequirement

    public init(
        category: String? = nil,
        suggestedDestinationURL: URL? = nil,
        confidence: Double,
        reason: String,
        requiredTools: [String] = [],
        reviewRequirement: ReviewRequirement
    ) {
        self.category = category
        self.suggestedDestinationURL = suggestedDestinationURL
        self.confidence = confidence
        self.reason = reason
        self.requiredTools = requiredTools
        self.reviewRequirement = reviewRequirement
    }
}

public enum OrganizationPipelineStatus: String, Codable, Equatable, Sendable {
    case organized
    case simulated
    case stagedForReview
    case indexedOnly
    case failed
}

public struct OrganizationPipelineResult: Codable, Equatable, Sendable {
    public var status: OrganizationPipelineStatus
    public var request: OrganizationRequest
    public var itemProfile: ItemProfile?
    public var decision: RouteDecision?
    public var plan: OperationPlan?
    public var executionResult: ExecutionResult?
    public var indexedItem: IndexedItem?
    public var message: String

    public init(
        status: OrganizationPipelineStatus,
        request: OrganizationRequest,
        itemProfile: ItemProfile? = nil,
        decision: RouteDecision? = nil,
        plan: OperationPlan? = nil,
        executionResult: ExecutionResult? = nil,
        indexedItem: IndexedItem? = nil,
        message: String
    ) {
        self.status = status
        self.request = request
        self.itemProfile = itemProfile
        self.decision = decision
        self.plan = plan
        self.executionResult = executionResult
        self.indexedItem = indexedItem
        self.message = message
    }
}

public struct OrganizationPipelineConfiguration: Codable, Equatable {
    public var workflow: Workflow
    public var inspectionOptions: InspectionOptions
    public var planningContext: PlanningContext
    public var executionContext: ExecutionContext
    public var now: Date

    public init(
        workflow: Workflow,
        inspectionOptions: InspectionOptions = InspectionOptions(),
        planningContext: PlanningContext,
        executionContext: ExecutionContext = ExecutionContext(),
        now: Date
    ) {
        self.workflow = workflow
        self.inspectionOptions = inspectionOptions
        self.planningContext = planningContext
        self.executionContext = executionContext
        self.now = now
    }
}
