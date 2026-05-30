import Foundation

public struct RuleActionDocument: Codable, Equatable, Sendable {
    public var operation: OperationKind
    public var destinationPath: String?
    public var parameters: [String: String]
    public var requiresReview: Bool
    public var recursiveFolderProcessing: Bool

    public init(
        operation: OperationKind = .move,
        destinationPath: String? = nil,
        parameters: [String: String] = [:],
        requiresReview: Bool = false,
        recursiveFolderProcessing: Bool = false
    ) {
        self.operation = operation
        self.destinationPath = destinationPath
        self.parameters = parameters
        self.requiresReview = requiresReview
        self.recursiveFolderProcessing = recursiveFolderProcessing
    }

    public init(action: ActionDescriptor) {
        operation = action.operationKind
        destinationPath = action.parameters["destination"]
        parameters = action.parameters.filter { $0.key != "destination" }
        requiresReview = action.requiresReview
        recursiveFolderProcessing = action.recursiveFolderProcessing
    }

    public var actionDescriptor: ActionDescriptor {
        var actionParameters = parameters
        if let destinationPath, !destinationPath.isEmpty {
            actionParameters["destination"] = destinationPath
        }
        return ActionDescriptor(
            operationKind: operation,
            parameters: actionParameters,
            requiresReview: requiresReview,
            recursiveFolderProcessing: recursiveFolderProcessing
        )
    }
}

public struct GraphActionDocument: Codable, Equatable, Sendable {
    public var kind: GraphOperationKind
    public var parameters: [String: String]
    public var requiresReview: Bool

    public init(
        kind: GraphOperationKind,
        parameters: [String: String] = [:],
        requiresReview: Bool = false
    ) {
        self.kind = kind
        self.parameters = parameters
        self.requiresReview = requiresReview
    }

    public init(action: GraphActionDescriptor) {
        kind = action.kind
        parameters = action.parameters
        requiresReview = action.requiresReview
    }

    public var actionDescriptor: GraphActionDescriptor {
        GraphActionDescriptor(kind: kind, parameters: parameters, requiresReview: requiresReview)
    }
}

public struct RuleDocument: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var schemaVersion: Int
    public var name: String
    public var enabled: Bool
    public var position: Int
    public var conditions: [ConditionDescriptor]
    public var action: RuleActionDocument
    public var graphActions: [GraphActionDocument]
    public var notes: String?

    public init(
        id: UUID = UUID(),
        schemaVersion: Int = 1,
        name: String,
        enabled: Bool = true,
        position: Int = 0,
        conditions: [ConditionDescriptor],
        action: RuleActionDocument,
        graphActions: [GraphActionDocument] = [],
        notes: String? = nil
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.name = name
        self.enabled = enabled
        self.position = position
        self.conditions = conditions
        self.action = action
        self.graphActions = graphActions
        self.notes = notes
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case schemaVersion
        case name
        case enabled
        case position
        case conditions
        case action
        case graphActions
        case notes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        name = try container.decode(String.self, forKey: .name)
        enabled = try container.decode(Bool.self, forKey: .enabled)
        position = try container.decode(Int.self, forKey: .position)
        conditions = try container.decode([ConditionDescriptor].self, forKey: .conditions)
        action = try container.decode(RuleActionDocument.self, forKey: .action)
        graphActions = try container.decodeIfPresent([GraphActionDocument].self, forKey: .graphActions) ?? []
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
    }

    public init(branch: WorkflowBranch, position: Int) {
        id = branch.id
        schemaVersion = 1
        name = branch.name
        enabled = true
        self.position = position
        conditions = branch.conditions
        action = RuleActionDocument(action: branch.node.actions.first ?? ActionDescriptor(operationKind: .move))
        graphActions = (branch.node.graphActions ?? []).map(GraphActionDocument.init(action:))
        notes = nil
    }

    public var workflowBranch: WorkflowBranch {
        WorkflowBranch(
            id: id,
            name: name,
            conditions: conditions,
            node: WorkflowNode(
                kind: .action,
                name: name,
                actions: [action.actionDescriptor],
                graphActions: graphActions.map(\.actionDescriptor)
            )
        )
    }
}

public protocol RuleDocumentStore: Sendable {
    func loadRules() async throws -> [RuleDocument]
    func saveRule(_ rule: RuleDocument) async throws
    func deleteRule(id: UUID) async throws
    func fileURL(for id: UUID) async throws -> URL?
}

public extension Workflow {
    static func fromRuleDocuments(
        _ documents: [RuleDocument],
        name: String = "User Rules",
        fallback: WorkflowNode = WorkflowNode(kind: .review, name: "Inbox")
    ) -> Workflow {
        Workflow(
            name: name,
            root: WorkflowNode(
                kind: .router,
                name: "Rules Router",
                branches: documents
                    .filter(\.enabled)
                    .sortedForWorkflow()
                    .map(\.workflowBranch),
                fallback: fallback
            )
        )
    }
}

public extension Array where Element == RuleDocument {
    func sortedForWorkflow() -> [RuleDocument] {
        sorted {
            if $0.position == $1.position {
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            return $0.position < $1.position
        }
    }
}
