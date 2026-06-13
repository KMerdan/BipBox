import Foundation

public enum ItemKind: String, Codable, Equatable, CaseIterable, Sendable {
    case file
    case folder
    case package
    case bundle
    case symlink
    case unknown
}

public enum IntakeSource: String, Codable, Equatable, CaseIterable, Sendable {
    case dragDrop
    case watchedFolder
    case manualImport
    case automation
    case ai
}

public enum OrganizationMode: String, Codable, Equatable, CaseIterable, Sendable {
    case organize
    case review
    case indexOnly
    case simulate
}

public struct OrganizationRequest: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var source: IntakeSource
    public var sourceID: UUID?
    public var itemURL: URL
    public var itemKind: ItemKind
    public var receivedAt: Date
    public var mode: OrganizationMode
    public var userContext: [String: String]

    public init(
        id: UUID = UUID(),
        source: IntakeSource,
        sourceID: UUID? = nil,
        itemURL: URL,
        itemKind: ItemKind,
        receivedAt: Date,
        mode: OrganizationMode,
        userContext: [String: String] = [:]
    ) {
        self.id = id
        self.source = source
        self.sourceID = sourceID
        self.itemURL = itemURL
        self.itemKind = itemKind
        self.receivedAt = receivedAt
        self.mode = mode
        self.userContext = userContext
    }

    public func associated(with sourceRecord: SourceRecord) -> OrganizationRequest {
        var context = userContext
        context.merge(sourceRecord.captureDetail) { existing, _ in existing }
        return OrganizationRequest(
            id: id,
            source: IntakeSource(sourceKind: sourceRecord.kind) ?? source,
            sourceID: sourceRecord.id,
            itemURL: itemURL,
            itemKind: itemKind,
            receivedAt: receivedAt,
            mode: mode,
            userContext: context
        )
    }
}

public extension IntakeSource {
    init?(sourceKind: SourceKind) {
        switch sourceKind {
        case .watchedFolder:
            self = .watchedFolder
        case .menuBarDrop:
            self = .dragDrop
        case .manualImport:
            self = .manualImport
        case .browserExtension, .shareExtension, .cli:
            self = .automation
        case .agentRequest:
            self = .ai
        }
    }
}

public struct FolderChildSummary: Codable, Equatable, Sendable {
    public var visibleChildCount: Int
    public var visibleFileCount: Int
    public var visibleFolderCount: Int
    public var topLevelExtensions: [String: Int]
    public var shallowSizeBytes: Int64?
    public var isPackageLike: Bool
    public var recursiveInspectionRequested: Bool

    public init(
        visibleChildCount: Int,
        visibleFileCount: Int,
        visibleFolderCount: Int,
        topLevelExtensions: [String: Int] = [:],
        shallowSizeBytes: Int64? = nil,
        isPackageLike: Bool = false,
        recursiveInspectionRequested: Bool = false
    ) {
        self.visibleChildCount = visibleChildCount
        self.visibleFileCount = visibleFileCount
        self.visibleFolderCount = visibleFolderCount
        self.topLevelExtensions = topLevelExtensions
        self.shallowSizeBytes = shallowSizeBytes
        self.isPackageLike = isPackageLike
        self.recursiveInspectionRequested = recursiveInspectionRequested
    }
}

public struct ItemProfile: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var url: URL
    public var kind: ItemKind
    public var displayName: String
    public var fileExtension: String?
    public var uniformTypeIdentifier: String?
    public var sizeBytes: Int64?
    public var createdAt: Date?
    public var modifiedAt: Date?
    public var source: IntakeSource?
    public var finderTags: [String]
    public var contentHash: String?
    public var folderChildSummary: FolderChildSummary?
    public var extractedTextSummary: String?
    public var metadata: [String: String]

    public init(
        id: UUID = UUID(),
        url: URL,
        kind: ItemKind,
        displayName: String,
        fileExtension: String? = nil,
        uniformTypeIdentifier: String? = nil,
        sizeBytes: Int64? = nil,
        createdAt: Date? = nil,
        modifiedAt: Date? = nil,
        source: IntakeSource? = nil,
        finderTags: [String] = [],
        contentHash: String? = nil,
        folderChildSummary: FolderChildSummary? = nil,
        extractedTextSummary: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.url = url
        self.kind = kind
        self.displayName = displayName
        self.fileExtension = fileExtension
        self.uniformTypeIdentifier = uniformTypeIdentifier
        self.sizeBytes = sizeBytes
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.source = source
        self.finderTags = finderTags
        self.contentHash = contentHash
        self.folderChildSummary = folderChildSummary
        self.extractedTextSummary = extractedTextSummary
        self.metadata = metadata
    }
}

public enum ReviewRequirement: String, Codable, Equatable, CaseIterable, Sendable {
    case notRequired
    case recommended
    case required
}

public struct RouteDecision: Codable, Equatable, Sendable {
    public var confidence: Double
    public var matchedRuleIDs: [UUID]
    public var destinationURL: URL?
    public var actions: [ActionDescriptor]
    public var graphActions: [GraphActionDescriptor]
    public var reason: String
    public var reviewRequirement: ReviewRequirement

    public init(
        confidence: Double,
        matchedRuleIDs: [UUID] = [],
        destinationURL: URL? = nil,
        actions: [ActionDescriptor] = [],
        graphActions: [GraphActionDescriptor] = [],
        reason: String,
        reviewRequirement: ReviewRequirement
    ) {
        self.confidence = confidence
        self.matchedRuleIDs = matchedRuleIDs
        self.destinationURL = destinationURL
        self.actions = actions
        self.graphActions = graphActions
        self.reason = reason
        self.reviewRequirement = reviewRequirement
    }
}

public enum OperationKind: String, Codable, Equatable, CaseIterable, Sendable {
    case move
    case copy
    case rename
    case addTags
    case removeTags
    case createFolder
    case markNeedsReview
    case indexInPlace
    case open
    case revealInFinder
}

public struct Operation: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var kind: OperationKind
    public var itemURL: URL
    public var destinationURL: URL?
    public var value: String?
    public var reversible: Bool

    public init(
        id: UUID = UUID(),
        kind: OperationKind,
        itemURL: URL,
        destinationURL: URL? = nil,
        value: String? = nil,
        reversible: Bool
    ) {
        self.id = id
        self.kind = kind
        self.itemURL = itemURL
        self.destinationURL = destinationURL
        self.value = value
        self.reversible = reversible
    }
}

public struct OperationPlan: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var operations: [Operation]
    public var graphOperations: [GraphOperation]
    public var expectedResultURL: URL?
    public var conflicts: [String]
    public var reversible: Bool
    public var previewText: String

    public init(
        id: UUID = UUID(),
        operations: [Operation],
        graphOperations: [GraphOperation] = [],
        expectedResultURL: URL? = nil,
        conflicts: [String] = [],
        reversible: Bool,
        previewText: String
    ) {
        self.id = id
        self.operations = operations
        self.graphOperations = graphOperations
        self.expectedResultURL = expectedResultURL
        self.conflicts = conflicts
        self.reversible = reversible
        self.previewText = previewText
    }
}

public enum WorkflowNodeKind: String, Codable, Equatable, CaseIterable, Sendable {
    case router
    case action
    case transform
    case review
    case aiClassify
    case toolCall
    case stop
}

public struct Workflow: Codable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var version: Int
    public var root: WorkflowNode

    public init(id: UUID = UUID(), name: String, version: Int = 1, root: WorkflowNode) {
        self.id = id
        self.name = name
        self.version = version
        self.root = root
    }
}

public final class WorkflowNode: Codable, Equatable, Identifiable {
    public var id: UUID
    public var kind: WorkflowNodeKind
    public var name: String
    public var branches: [WorkflowBranch]
    public var fallback: WorkflowNode?
    public var actions: [ActionDescriptor]
    public var graphActions: [GraphActionDescriptor]?
    public var toolName: String?

    public init(
        id: UUID = UUID(),
        kind: WorkflowNodeKind,
        name: String,
        branches: [WorkflowBranch] = [],
        fallback: WorkflowNode? = nil,
        actions: [ActionDescriptor] = [],
        graphActions: [GraphActionDescriptor] = [],
        toolName: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.branches = branches
        self.fallback = fallback
        self.actions = actions
        self.graphActions = graphActions
        self.toolName = toolName
    }

    public static func == (lhs: WorkflowNode, rhs: WorkflowNode) -> Bool {
        lhs.id == rhs.id &&
            lhs.kind == rhs.kind &&
            lhs.name == rhs.name &&
            lhs.branches == rhs.branches &&
            lhs.fallback == rhs.fallback &&
            lhs.actions == rhs.actions &&
            (lhs.graphActions ?? []) == (rhs.graphActions ?? []) &&
            lhs.toolName == rhs.toolName
    }
}

public struct WorkflowBranch: Codable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var conditions: [ConditionDescriptor]
    public var node: WorkflowNode

    public init(
        id: UUID = UUID(),
        name: String,
        conditions: [ConditionDescriptor],
        node: WorkflowNode
    ) {
        self.id = id
        self.name = name
        self.conditions = conditions
        self.node = node
    }
}

public enum ConditionField: String, Codable, Equatable, CaseIterable, Sendable {
    case itemKind
    case filename
    case fileExtension
    case uniformTypeIdentifier
    case source
    case sourceID
    case sourceKind
    case sourceName
    case sourcePath
    case collection
    case context
    case extractedText
    case sizeBytes
    case createdAt
    case modifiedAt
    case finderTags
    case folderChildSummary
}

public enum ConditionOperator: String, Codable, Equatable, CaseIterable, Sendable {
    case equals
    case contains
    case startsWith
    case endsWith
    case matchesRegex
    case greaterThan
    case lessThan
}

public struct ConditionDescriptor: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var field: ConditionField
    public var operation: ConditionOperator
    public var value: String

    public init(
        id: UUID = UUID(),
        field: ConditionField,
        operation: ConditionOperator,
        value: String
    ) {
        self.id = id
        self.field = field
        self.operation = operation
        self.value = value
    }
}

public struct ActionDescriptor: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var operationKind: OperationKind
    public var parameters: [String: String]
    public var requiresReview: Bool
    public var recursiveFolderProcessing: Bool

    public init(
        id: UUID = UUID(),
        operationKind: OperationKind,
        parameters: [String: String] = [:],
        requiresReview: Bool = false,
        recursiveFolderProcessing: Bool = false
    ) {
        self.id = id
        self.operationKind = operationKind
        self.parameters = parameters
        self.requiresReview = requiresReview
        self.recursiveFolderProcessing = recursiveFolderProcessing
    }
}

public enum ActionSafetyLevel: String, Codable, Equatable, CaseIterable, Sendable {
    case readOnly
    case memoryOnly
    case filesystemWrite
    case externalInteraction
}

public struct ActionSafetyMetadata: Codable, Equatable, Sendable {
    public var safetyLevel: ActionSafetyLevel
    public var reversible: Bool
    public var dryRunSupported: Bool
    public var requiresUserReview: Bool

    public init(
        safetyLevel: ActionSafetyLevel,
        reversible: Bool,
        dryRunSupported: Bool,
        requiresUserReview: Bool
    ) {
        self.safetyLevel = safetyLevel
        self.reversible = reversible
        self.dryRunSupported = dryRunSupported
        self.requiresUserReview = requiresUserReview
    }
}

public enum GraphOperationKind: String, Codable, Equatable, CaseIterable, Sendable {
    case addToCollection
    case addTopic
    case addPerson
    case addProject
    case addRelationship
}

public struct GraphActionDescriptor: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var kind: GraphOperationKind
    public var parameters: [String: String]
    public var requiresReview: Bool

    public init(
        id: UUID = UUID(),
        kind: GraphOperationKind,
        parameters: [String: String] = [:],
        requiresReview: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.parameters = parameters
        self.requiresReview = requiresReview
    }
}

public extension OperationKind {
    var safetyMetadata: ActionSafetyMetadata {
        switch self {
        case .move, .copy, .rename, .addTags, .removeTags, .createFolder:
            ActionSafetyMetadata(
                safetyLevel: .filesystemWrite,
                reversible: true,
                dryRunSupported: true,
                requiresUserReview: false
            )
        case .markNeedsReview, .indexInPlace:
            ActionSafetyMetadata(
                safetyLevel: .memoryOnly,
                reversible: true,
                dryRunSupported: true,
                requiresUserReview: self == .markNeedsReview
            )
        case .open, .revealInFinder:
            ActionSafetyMetadata(
                safetyLevel: .externalInteraction,
                reversible: false,
                dryRunSupported: true,
                requiresUserReview: true
            )
        }
    }
}

public extension ActionDescriptor {
    var safetyMetadata: ActionSafetyMetadata {
        var metadata = operationKind.safetyMetadata
        metadata.requiresUserReview = metadata.requiresUserReview || requiresReview
        return metadata
    }

    var validationErrors: [String] {
        switch operationKind {
        case .move, .copy, .createFolder:
            parameters["destination"].isNilOrEmpty ? ["destination is required for \(operationKind.rawValue)."] : []
        case .rename:
            (parameters["name"] ?? parameters["newName"]).isNilOrEmpty ? ["name or newName is required for rename."] : []
        case .addTags, .removeTags:
            parameters["tags"].isNilOrEmpty ? ["tags is required for \(operationKind.rawValue)."] : []
        case .markNeedsReview, .indexInPlace, .open, .revealInFinder:
            []
        }
    }

    var isValid: Bool {
        validationErrors.isEmpty
    }
}

public extension GraphOperationKind {
    var safetyMetadata: ActionSafetyMetadata {
        ActionSafetyMetadata(
            safetyLevel: .memoryOnly,
            reversible: true,
            dryRunSupported: true,
            requiresUserReview: false
        )
    }
}

public extension GraphActionDescriptor {
    var safetyMetadata: ActionSafetyMetadata {
        var metadata = kind.safetyMetadata
        metadata.requiresUserReview = metadata.requiresUserReview || requiresReview
        return metadata
    }

    var validationErrors: [String] {
        switch kind {
        case .addToCollection:
            return (parameters["collectionID"].isNilOrEmpty && parameters["collectionName"].isNilOrEmpty)
                ? ["collectionID or collectionName is required for addToCollection."]
                : []
        case .addTopic:
            return parameters["topic"].isNilOrEmpty ? ["topic is required for addTopic."] : []
        case .addPerson:
            return parameters["person"].isNilOrEmpty ? ["person is required for addPerson."] : []
        case .addProject:
            return parameters["project"].isNilOrEmpty ? ["project is required for addProject."] : []
        case .addRelationship:
            return parameters["predicate"].isNilOrEmpty ? ["predicate is required for addRelationship."] : []
        }
    }

    var isValid: Bool {
        validationErrors.isEmpty
    }
}

public struct GraphOperation: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var kind: GraphOperationKind
    public var itemID: UUID
    public var parameters: [String: String]
    public var requiresReview: Bool
    public var reversible: Bool

    public init(
        id: UUID = UUID(),
        kind: GraphOperationKind,
        itemID: UUID,
        parameters: [String: String] = [:],
        requiresReview: Bool = false,
        reversible: Bool = true
    ) {
        self.id = id
        self.kind = kind
        self.itemID = itemID
        self.parameters = parameters
        self.requiresReview = requiresReview
        self.reversible = reversible
    }
}

public enum IndexedItemStatus: String, Codable, Equatable, CaseIterable, Sendable {
    case organized
    case needsReview
    case indexedOnly
    case missing
    case failed
}

public struct IndexedItem: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var currentPath: String
    public var originalPath: String?
    public var displayName: String
    public var kind: ItemKind
    public var uniformTypeIdentifier: String?
    public var sizeBytes: Int64?
    public var createdAt: Date?
    public var modifiedAt: Date?
    public var importedAt: Date
    public var routedAt: Date?
    public var ruleID: UUID?
    public var tags: [String]
    public var extractedText: String?
    public var aiSummary: String?
    public var status: IndexedItemStatus
    /// Fingerprint of the content this item was last indexed/embedded from
    /// (files: size + head/tail hash; aggregates: composite over members).
    /// Rescans skip items whose fingerprint is unchanged.
    public var contentFingerprint: String?

    public init(
        id: UUID = UUID(),
        currentPath: String,
        originalPath: String? = nil,
        displayName: String,
        kind: ItemKind,
        uniformTypeIdentifier: String? = nil,
        sizeBytes: Int64? = nil,
        createdAt: Date? = nil,
        modifiedAt: Date? = nil,
        importedAt: Date,
        routedAt: Date? = nil,
        ruleID: UUID? = nil,
        tags: [String] = [],
        extractedText: String? = nil,
        aiSummary: String? = nil,
        status: IndexedItemStatus,
        contentFingerprint: String? = nil
    ) {
        self.id = id
        self.currentPath = currentPath
        self.originalPath = originalPath
        self.displayName = displayName
        self.kind = kind
        self.uniformTypeIdentifier = uniformTypeIdentifier
        self.sizeBytes = sizeBytes
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.importedAt = importedAt
        self.routedAt = routedAt
        self.ruleID = ruleID
        self.tags = tags
        self.extractedText = extractedText
        self.aiSummary = aiSummary
        self.status = status
        self.contentFingerprint = contentFingerprint
    }
}

private extension Optional where Wrapped == String {
    var isNilOrEmpty: Bool {
        switch self {
        case .none:
            true
        case .some(let value):
            value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}
