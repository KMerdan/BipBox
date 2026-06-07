import BipboxCore
import Foundation

public struct WorkflowSimulationResult: Equatable, Sendable {
    public var itemName: String
    public var matchedPath: [String]
    public var decision: RouteDecision

    public init(itemName: String, matchedPath: [String], decision: RouteDecision) {
        self.itemName = itemName
        self.matchedPath = matchedPath
        self.decision = decision
    }
}

public enum RuleDropRoutingState: Equatable, Sendable {
    case matched(ruleName: String, destinationPath: String?)
    case needsRule(itemName: String, reason: String)
}

public struct NewRuleDraft: Equatable, Sendable {
    public var itemName: String
    public var itemKind: ItemKind
    public var fileExtension: String
    public var ruleName: String
    public var destinationPath: String

    public init(
        itemName: String,
        itemKind: ItemKind,
        fileExtension: String,
        ruleName: String,
        destinationPath: String
    ) {
        self.itemName = itemName
        self.itemKind = itemKind
        self.fileExtension = fileExtension
        self.ruleName = ruleName
        self.destinationPath = destinationPath
    }
}

public enum RuleOutcomeKind: String, CaseIterable, Identifiable, Sendable {
    case move
    case copy
    case indexOnly
    case review
    case addTags
    case addToCollection
    case addTopic
    case addPerson
    case addProject

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .move: "Move"
        case .copy: "Copy"
        case .indexOnly: "Index Only"
        case .review: "Needs Review"
        case .addTags: "Add Tags"
        case .addToCollection: "Collection"
        case .addTopic: "Topic"
        case .addPerson: "Person"
        case .addProject: "Project"
        }
    }
}

@MainActor
public protocol RulesWorkflowSimulating: AnyObject {
    func evaluate(
        workflow: Workflow,
        item: ItemProfile,
        context: WorkflowEvaluationContext
    ) async throws -> RouteDecision
}

@MainActor
public final class RulesWorkspaceViewModel: ObservableObject {
    @Published public var workflow: Workflow
    @Published public private(set) var selectedBranchID: UUID?
    @Published public private(set) var simulationResult: WorkflowSimulationResult?
    @Published public private(set) var dropRoutingState: RuleDropRoutingState?
    @Published public var newRuleDraft: NewRuleDraft?
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var ruleDocuments: [RuleDocument]
    @Published public private(set) var isLoadingRuleFiles: Bool
    @Published public private(set) var isSavingRuleFiles: Bool
    @Published public private(set) var ruleFilesMessage: String?

    private let workflowSimulator: RulesWorkflowSimulating
    private let ruleStore: RuleDocumentStore?
    private let jsonEncoder: JSONEncoder
    private let jsonDecoder: JSONDecoder
    private let onWorkflowChanged: (@MainActor (Workflow) -> Void)?

    public init(
        workflow: Workflow = .fixtureRulesWorkflow(),
        workflowSimulator: RulesWorkflowSimulating = DefaultRulesWorkflowSimulator(),
        ruleStore: RuleDocumentStore? = nil,
        onWorkflowChanged: (@MainActor (Workflow) -> Void)? = nil
    ) {
        self.workflow = workflow
        self.workflowSimulator = workflowSimulator
        self.ruleStore = ruleStore
        self.onWorkflowChanged = onWorkflowChanged
        jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        jsonDecoder = JSONDecoder()
        selectedBranchID = workflow.root.branches.first?.id
        simulationResult = nil
        dropRoutingState = nil
        newRuleDraft = nil
        errorMessage = nil
        ruleDocuments = Self.documents(from: workflow)
        isLoadingRuleFiles = false
        isSavingRuleFiles = false
        ruleFilesMessage = nil
    }

    public var branches: [WorkflowBranch] {
        workflow.root.branches
    }

    public var selectedBranch: WorkflowBranch? {
        guard let selectedBranchID else {
            return nil
        }
        return workflow.root.branches.first { $0.id == selectedBranchID }
    }

    public var fallbackTitle: String {
        workflow.root.fallback?.name ?? "None"
    }

    public var selectedRuleDocument: RuleDocument? {
        guard let selectedBranchID else {
            return nil
        }
        return ruleDocuments.first { $0.id == selectedBranchID }
    }

    public var selectedRuleJSON: String {
        guard let selectedRuleDocument,
              let data = try? jsonEncoder.encode(selectedRuleDocument),
              let json = String(data: data, encoding: .utf8) else {
            return ""
        }
        return json
    }

    public var selectedRuleAIContext: String {
        guard let selectedRuleDocument else {
            return "No rule is selected."
        }

        return """
        You are editing one Bipbox rule document. Return only valid JSON matching this shape.

        Supported condition fields: \(ConditionField.allCases.map(\.rawValue).joined(separator: ", "))
        Supported condition operators: \(ConditionOperator.allCases.map(\.rawValue).joined(separator: ", "))
        Supported operations: \(OperationKind.allCases.map(\.rawValue).joined(separator: ", "))

        Keep these fields unless the user asks to change them:
        - id: \(selectedRuleDocument.id.uuidString)
        - schemaVersion: \(selectedRuleDocument.schemaVersion)
        - position: \(selectedRuleDocument.position)

        Current rule JSON:
        \(selectedRuleJSON)
        """
    }

    public func selectBranch(id: UUID?) {
        selectedBranchID = id
    }

    public func selectedRuleFileURL() async -> URL? {
        guard let selectedBranchID, let ruleStore else {
            return nil
        }

        return try? await ruleStore.fileURL(for: selectedBranchID)
    }

    public func loadRuleFiles() async {
        guard let ruleStore else {
            return
        }

        isLoadingRuleFiles = true
        errorMessage = nil

        do {
            let documents = try await ruleStore.loadRules()
            if documents.isEmpty {
                syncRuleDocumentsFromWorkflow()
                try await saveRuleDocuments(ruleDocuments)
                ruleFilesMessage = "Created \(ruleDocuments.count) rule file(s)."
            } else {
                applyRuleDocuments(documents)
                ruleFilesMessage = "Loaded \(documents.count) rule file(s)."
            }
        } catch {
            errorMessage = error.localizedDescription
            ruleFilesMessage = nil
        }

        isLoadingRuleFiles = false
    }

    public func applyRuleFiles() async {
        guard let ruleStore else {
            ruleFilesMessage = "Rule file storage is not connected."
            return
        }

        isLoadingRuleFiles = true
        errorMessage = nil

        do {
            let documents = try await ruleStore.loadRules()
            applyRuleDocuments(documents)
            ruleFilesMessage = "Applied \(documents.count) rule file(s) to the active workflow."
        } catch {
            errorMessage = error.localizedDescription
            ruleFilesMessage = nil
        }

        isLoadingRuleFiles = false
    }

    public func saveRuleFiles() async {
        guard ruleStore != nil else {
            syncRuleDocumentsFromWorkflow()
            ruleFilesMessage = "Rule file storage is not connected."
            return
        }

        isSavingRuleFiles = true
        errorMessage = nil

        do {
            syncRuleDocumentsFromWorkflow()
            try await saveRuleDocuments(ruleDocuments)
            ruleFilesMessage = "Saved \(ruleDocuments.count) rule file(s)."
            onWorkflowChanged?(workflow)
        } catch {
            errorMessage = error.localizedDescription
            ruleFilesMessage = nil
        }

        isSavingRuleFiles = false
    }

    public func applyRuleDocumentJSON(_ json: String) throws {
        let data = Data(json.utf8)
        var document = try jsonDecoder.decode(RuleDocument.self, from: data)
        if let existingIndex = ruleDocuments.firstIndex(where: { $0.id == document.id }) {
            document.position = ruleDocuments[existingIndex].position
            ruleDocuments[existingIndex] = document
        } else {
            document.position = ruleDocuments.count
            ruleDocuments.append(document)
        }
        applyRuleDocuments(ruleDocuments)
        ruleFilesMessage = "Applied \(document.name). Save rule files to persist it."
    }

    @discardableResult
    public func addFileRule(
        name: String,
        fileExtension: String,
        destinationPath: String
    ) -> WorkflowBranch {
        let trimmedExtension = fileExtension.trimmingCharacters(in: .whitespacesAndNewlines).trimmingPrefix(".")
        let branch = makeMoveBranch(
            name: name,
            conditions: [
                ConditionDescriptor(field: .fileExtension, operation: .equals, value: trimmedExtension)
            ],
            destinationPath: destinationPath,
            recursiveFolderProcessing: false
        )
        workflow.root.branches.append(branch)
        selectedBranchID = branch.id
        syncRuleDocumentsFromWorkflow()
        onWorkflowChanged?(workflow)
        return branch
    }

    @discardableResult
    public func addFolderRule(name: String, destinationPath: String) -> WorkflowBranch {
        let branch = makeMoveBranch(
            name: name,
            conditions: [
                ConditionDescriptor(field: .itemKind, operation: .equals, value: ItemKind.folder.rawValue)
            ],
            destinationPath: destinationPath,
            recursiveFolderProcessing: false
        )
        workflow.root.branches.append(branch)
        selectedBranchID = branch.id
        syncRuleDocumentsFromWorkflow()
        onWorkflowChanged?(workflow)
        return branch
    }

    public func removeSelectedBranch() {
        guard let selectedBranchID else {
            return
        }

        workflow.root.branches.removeAll { $0.id == selectedBranchID }
        ruleDocuments.removeAll { $0.id == selectedBranchID }
        self.selectedBranchID = workflow.root.branches.first?.id
        onWorkflowChanged?(workflow)
    }

    /// Delete a rule by id and persist the change.
    public func deleteRule(id: UUID) async {
        ruleDocuments.removeAll { $0.id == id }
        workflow.root.branches.removeAll { $0.id == id }
        if selectedBranchID == id { selectedBranchID = workflow.root.branches.first?.id }
        onWorkflowChanged?(workflow)
        await persistRuleDocuments()
    }

    /// Toggle a rule's enabled flag and persist. Disabled rules stay in the list
    /// (and on disk) but are dropped from the active workflow.
    public func setRuleEnabled(id: UUID, _ enabled: Bool) async {
        // Make sure every branch has a backing document before toggling.
        syncRuleDocumentsFromWorkflowPreservingState()
        if let index = ruleDocuments.firstIndex(where: { $0.id == id }) {
            ruleDocuments[index].enabled = enabled
        }
        ruleDocuments = ruleDocuments.sortedForWorkflow()
        workflow = Workflow.fromRuleDocuments(ruleDocuments)
        onWorkflowChanged?(workflow)
        await persistRuleDocuments()
    }

    /// Create a starter rule the user can then edit, and persist it.
    @discardableResult
    public func addBlankRule() async -> UUID {
        syncRuleDocumentsFromWorkflowPreservingState()
        let id = UUID()
        let document = RuleDocument(
            id: id,
            name: "New Rule",
            enabled: true,
            position: ruleDocuments.count,
            conditions: [ConditionDescriptor(field: .fileExtension, operation: .equals, value: "pdf")],
            action: RuleActionDocument(operation: .markNeedsReview, requiresReview: true)
        )
        ruleDocuments.append(document)
        ruleDocuments = ruleDocuments.sortedForWorkflow()
        workflow = Workflow.fromRuleDocuments(ruleDocuments)
        selectedBranchID = id
        onWorkflowChanged?(workflow)
        await persistRuleDocuments()
        return id
    }

    /// Rename a rule and persist.
    public func renameRule(id: UUID, to name: String) async {
        syncRuleDocumentsFromWorkflowPreservingState()
        if let index = ruleDocuments.firstIndex(where: { $0.id == id }) {
            ruleDocuments[index].name = name
        }
        if let bIndex = workflow.root.branches.firstIndex(where: { $0.id == id }) {
            workflow.root.branches[bIndex].name = name
            workflow.root.branches[bIndex].node.name = name
        }
        onWorkflowChanged?(workflow)
        await persistRuleDocuments()
    }

    /// Persist the current `ruleDocuments` (including disabled ones) to the store.
    private func persistRuleDocuments() async {
        guard ruleStore != nil else {
            ruleFilesMessage = "Rule file storage is not connected."
            return
        }
        isSavingRuleFiles = true
        errorMessage = nil
        do {
            try await saveRuleDocuments(ruleDocuments)
            ruleFilesMessage = "Saved \(ruleDocuments.count) rule file(s)."
        } catch {
            errorMessage = error.localizedDescription
        }
        isSavingRuleFiles = false
    }

    /// Refresh documents from the workflow without losing disabled documents
    /// (which the workflow does not contain).
    private func syncRuleDocumentsFromWorkflowPreservingState() {
        let derived = Self.documents(from: workflow)
        let disabled = ruleDocuments.filter { doc in !derived.contains { $0.id == doc.id } }
        ruleDocuments = (derived + disabled).sortedForWorkflow()
    }

    public func addConditionToSelectedBranch(
        field: ConditionField,
        operation: ConditionOperator,
        value: String
    ) {
        guard let index = selectedBranchIndex else {
            return
        }
        workflow.root.branches[index].conditions.append(
            ConditionDescriptor(field: field, operation: operation, value: value)
        )
        syncRuleDocumentsFromWorkflow()
        onWorkflowChanged?(workflow)
    }

    public func updateSelectedBranch(
        name: String,
        destinationPath: String,
        fileExtension: String? = nil
    ) {
        guard let index = selectedBranchIndex else {
            return
        }

        workflow.root.branches[index].name = name
        workflow.root.branches[index].node.name = name
        if let fileExtension {
            updateFileExtensionCondition(at: index, fileExtension: fileExtension)
        }
        workflow.root.branches[index].node.actions = [
            ActionDescriptor(
                operationKind: .move,
                parameters: ["destination": destinationPath],
                recursiveFolderProcessing: false
            )
        ]
        syncRuleDocumentsFromWorkflow()
        onWorkflowChanged?(workflow)
    }

    public func updateSelectedRuleForm(
        name: String,
        enabled: Bool,
        conditionField: ConditionField,
        conditionOperation: ConditionOperator,
        conditionValue: String,
        outcomeKind: RuleOutcomeKind,
        outcomeValue: String,
        requiresReview: Bool
    ) {
        guard let selectedBranchID else {
            return
        }

        let condition = ConditionDescriptor(
            field: conditionField,
            operation: conditionOperation,
            value: conditionValue.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        let document = RuleDocument(
            id: selectedBranchID,
            name: name,
            enabled: enabled,
            position: ruleDocuments.first(where: { $0.id == selectedBranchID })?.position ?? 0,
            conditions: [condition],
            action: ruleActionDocument(outcomeKind: outcomeKind, outcomeValue: outcomeValue, requiresReview: requiresReview),
            graphActions: graphActionDocuments(outcomeKind: outcomeKind, outcomeValue: outcomeValue, requiresReview: requiresReview)
        )

        if let index = ruleDocuments.firstIndex(where: { $0.id == selectedBranchID }) {
            ruleDocuments[index] = document
        } else {
            ruleDocuments.append(document)
        }
        applyRuleDocuments(ruleDocuments)
        self.selectedBranchID = enabled ? selectedBranchID : workflow.root.branches.first?.id
    }

    public func setFallbackToInbox() {
        workflow.root.fallback = WorkflowNode(kind: .review, name: "Inbox")
        onWorkflowChanged?(workflow)
    }

    public func setFallbackToNeedsReview() {
        setFallbackToInbox()
    }

    public func routeDroppedItem(_ item: ItemProfile, defaultDestinationPath: String, now: Date = Date()) async {
        await simulate(item: item, now: now)

        if let matchedBranch = matchedActionBranch(for: simulationResult?.decision) {
            selectedBranchID = matchedBranch.id
            newRuleDraft = nil
            dropRoutingState = .matched(
                ruleName: matchedBranch.name,
                destinationPath: matchedBranch.node.actions.first?.parameters["destination"]
            )
            return
        }

        let draft = makeNewRuleDraft(for: item, defaultDestinationPath: defaultDestinationPath)
        newRuleDraft = draft
        dropRoutingState = .needsRule(
            itemName: item.displayName,
            reason: "No automatic rule matched \(item.displayName)."
        )
    }

    @discardableResult
    public func createRuleFromDraft() -> WorkflowBranch? {
        guard let draft = newRuleDraft else {
            return nil
        }

        let branch: WorkflowBranch
        switch draft.itemKind {
        case .folder:
            branch = addFolderRule(name: draft.ruleName, destinationPath: draft.destinationPath)
        default:
            branch = addFileRule(
                name: draft.ruleName,
                fileExtension: draft.fileExtension,
                destinationPath: draft.destinationPath
            )
        }

        newRuleDraft = nil
        dropRoutingState = .matched(
            ruleName: branch.name,
            destinationPath: branch.node.actions.first?.parameters["destination"]
        )
        return branch
    }

    public func dismissNewRuleDraft() {
        newRuleDraft = nil
    }

    public func simulate(item: ItemProfile, now: Date = Date()) async {
        errorMessage = nil

        do {
            let decision = try await workflowSimulator.evaluate(
                workflow: workflow,
                item: item,
                context: WorkflowEvaluationContext(mode: .simulate, now: now)
            )
            simulationResult = WorkflowSimulationResult(
                itemName: item.displayName,
                matchedPath: matchedPath(for: decision),
                decision: decision
            )
        } catch {
            simulationResult = nil
            errorMessage = error.localizedDescription
        }
    }

    public func encodedWorkflow() throws -> Data {
        try JSONEncoder().encode(workflow)
    }

    private func saveRuleDocuments(_ documents: [RuleDocument]) async throws {
        guard let ruleStore else {
            return
        }

        let existing = try await ruleStore.loadRules()
        let currentIDs = Set(documents.map(\.id))
        for oldDocument in existing where !currentIDs.contains(oldDocument.id) {
            try await ruleStore.deleteRule(id: oldDocument.id)
        }

        for document in documents.sortedForWorkflow() {
            try await ruleStore.saveRule(document)
        }
    }

    private func applyRuleDocuments(_ documents: [RuleDocument]) {
        ruleDocuments = documents.sortedForWorkflow()
        workflow = Workflow.fromRuleDocuments(ruleDocuments)
        selectedBranchID = workflow.root.branches.first?.id
        onWorkflowChanged?(workflow)
    }

    private func syncRuleDocumentsFromWorkflow() {
        ruleDocuments = Self.documents(from: workflow)
    }

    private static func documents(from workflow: Workflow) -> [RuleDocument] {
        workflow.root.branches.enumerated().map { position, branch in
            RuleDocument(branch: branch, position: position)
        }
    }

    private var selectedBranchIndex: Int? {
        guard let selectedBranchID else {
            return nil
        }
        return workflow.root.branches.firstIndex { $0.id == selectedBranchID }
    }

    private func updateFileExtensionCondition(at branchIndex: Int, fileExtension: String) {
        let trimmedExtension = fileExtension.trimmingCharacters(in: .whitespacesAndNewlines).trimmingPrefix(".")
        let extensionIndex = workflow.root.branches[branchIndex].conditions.firstIndex { $0.field == .fileExtension }
        if let extensionIndex {
            workflow.root.branches[branchIndex].conditions[extensionIndex].value = trimmedExtension
            return
        }

        guard !trimmedExtension.isEmpty,
              !workflow.root.branches[branchIndex].conditions.contains(where: {
                  $0.field == .itemKind && $0.value == ItemKind.folder.rawValue
              }) else {
            return
        }

        workflow.root.branches[branchIndex].conditions.append(
            ConditionDescriptor(field: .fileExtension, operation: .equals, value: trimmedExtension)
        )
    }

    private func makeMoveBranch(
        name: String,
        conditions: [ConditionDescriptor],
        destinationPath: String,
        recursiveFolderProcessing: Bool
    ) -> WorkflowBranch {
        let action = ActionDescriptor(
            operationKind: .move,
            parameters: ["destination": destinationPath],
            recursiveFolderProcessing: recursiveFolderProcessing
        )
        return WorkflowBranch(
            name: name,
            conditions: conditions,
            node: WorkflowNode(kind: .action, name: name, actions: [action])
        )
    }

    private func ruleActionDocument(
        outcomeKind: RuleOutcomeKind,
        outcomeValue: String,
        requiresReview: Bool
    ) -> RuleActionDocument {
        switch outcomeKind {
        case .move:
            RuleActionDocument(operation: .move, destinationPath: outcomeValue, requiresReview: requiresReview)
        case .copy:
            RuleActionDocument(operation: .copy, destinationPath: outcomeValue, requiresReview: requiresReview)
        case .indexOnly, .addToCollection, .addTopic, .addPerson, .addProject:
            RuleActionDocument(operation: .indexInPlace, requiresReview: requiresReview)
        case .review:
            RuleActionDocument(operation: .markNeedsReview, parameters: ["reason": outcomeValue], requiresReview: true)
        case .addTags:
            RuleActionDocument(operation: .addTags, parameters: ["tags": outcomeValue], requiresReview: requiresReview)
        }
    }

    private func graphActionDocuments(
        outcomeKind: RuleOutcomeKind,
        outcomeValue: String,
        requiresReview: Bool
    ) -> [GraphActionDocument] {
        switch outcomeKind {
        case .addToCollection:
            [GraphActionDocument(kind: .addToCollection, parameters: ["collectionName": outcomeValue], requiresReview: requiresReview)]
        case .addTopic:
            [GraphActionDocument(kind: .addTopic, parameters: ["topic": outcomeValue], requiresReview: requiresReview)]
        case .addPerson:
            [GraphActionDocument(kind: .addPerson, parameters: ["person": outcomeValue], requiresReview: requiresReview)]
        case .addProject:
            [GraphActionDocument(kind: .addProject, parameters: ["project": outcomeValue], requiresReview: requiresReview)]
        case .move, .copy, .indexOnly, .review, .addTags:
            []
        }
    }

    private func matchedPath(for decision: RouteDecision) -> [String] {
        let matchedNames = workflow.root.branches
            .filter { decision.matchedRuleIDs.contains($0.id) }
            .map(\.name)

        if !matchedNames.isEmpty {
            return [workflow.root.name] + matchedNames
        }

        if decision.reviewRequirement == .required, let fallback = workflow.root.fallback {
            return [workflow.root.name, fallback.name]
        }

        return [workflow.root.name]
    }

    private func matchedActionBranch(for decision: RouteDecision?) -> WorkflowBranch? {
        guard let decision else {
            return nil
        }

        return workflow.root.branches.first { branch in
            decision.matchedRuleIDs.contains(branch.id) && !branch.node.actions.isEmpty
        }
    }

    private func makeNewRuleDraft(for item: ItemProfile, defaultDestinationPath: String) -> NewRuleDraft {
        let extensionText = (item.fileExtension ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let ruleName: String

        if item.kind == .folder {
            ruleName = "\(item.displayName) Folders"
        } else if extensionText.isEmpty {
            ruleName = "\(item.displayName) Files"
        } else {
            ruleName = "\(extensionText.uppercased()) Files"
        }

        return NewRuleDraft(
            itemName: item.displayName,
            itemKind: item.kind,
            fileExtension: extensionText,
            ruleName: ruleName,
            destinationPath: defaultDestinationPath
        )
    }
}

@MainActor
public final class DefaultRulesWorkflowSimulator: RulesWorkflowSimulating {
    public init() {}

    public func evaluate(
        workflow: Workflow,
        item: ItemProfile,
        context: WorkflowEvaluationContext
    ) async throws -> RouteDecision {
        evaluateNode(workflow.root, item: item, matchedIDs: [workflow.root.id])
    }

    private func evaluateNode(_ node: WorkflowNode, item: ItemProfile, matchedIDs: [UUID]) -> RouteDecision {
        switch node.kind {
        case .router:
            for branch in node.branches where branchMatches(branch, item: item) {
                return evaluateNode(branch.node, item: item, matchedIDs: matchedIDs + [branch.id, branch.node.id])
            }

            if let fallback = node.fallback {
                return evaluateNode(fallback, item: item, matchedIDs: matchedIDs + [fallback.id])
            }

            return RouteDecision(
                confidence: 0,
                matchedRuleIDs: matchedIDs,
                reason: "No workflow branch matched and no fallback was configured.",
                reviewRequirement: .required
            )
        case .action:
            return RouteDecision(
                confidence: 1,
                matchedRuleIDs: matchedIDs,
                destinationURL: node.actions.first?.parameters["destination"].map(URL.init(fileURLWithPath:)),
                actions: node.actions,
                reason: "Matched action node \(node.name).",
                reviewRequirement: node.actions.contains(where: \.requiresReview) ? .required : .notRequired
            )
        case .review:
            return RouteDecision(
                confidence: 1,
                matchedRuleIDs: matchedIDs,
                reason: "Workflow requires review at \(node.name).",
                reviewRequirement: .required
            )
        case .stop:
            return RouteDecision(
                confidence: 1,
                matchedRuleIDs: matchedIDs,
                reason: "Workflow stopped at \(node.name).",
                reviewRequirement: .notRequired
            )
        case .transform, .aiClassify, .toolCall:
            return RouteDecision(
                confidence: 0.5,
                matchedRuleIDs: matchedIDs,
                reason: "\(node.kind.rawValue) node \(node.name) is not executable by the rules UI simulator yet.",
                reviewRequirement: .required
            )
        }
    }

    private func branchMatches(_ branch: WorkflowBranch, item: ItemProfile) -> Bool {
        branch.conditions.allSatisfy { conditionMatches($0, item: item) }
    }

    private func conditionMatches(_ condition: ConditionDescriptor, item: ItemProfile) -> Bool {
        let actualValue: String
        switch condition.field {
        case .itemKind:
            actualValue = item.kind.rawValue
        case .filename:
            actualValue = item.displayName
        case .fileExtension:
            actualValue = item.fileExtension ?? ""
        case .uniformTypeIdentifier:
            actualValue = item.uniformTypeIdentifier ?? ""
        case .source:
            actualValue = item.source?.rawValue ?? ""
        case .sourceID:
            actualValue = item.metadata["sourceID"] ?? ""
        case .sourceKind:
            actualValue = item.metadata["sourceKind"] ?? item.source?.rawValue ?? ""
        case .sourceName:
            actualValue = item.metadata["sourceName"] ?? ""
        case .sourcePath:
            actualValue = item.metadata["sourcePath"] ?? ""
        case .collection:
            actualValue = item.metadata["collections"] ?? ""
        case .context:
            actualValue = item.metadata["contexts"] ?? ""
        case .extractedText:
            actualValue = item.extractedTextSummary ?? item.metadata["extractedText"] ?? ""
        case .finderTags:
            actualValue = item.finderTags.joined(separator: ",")
        case .folderChildSummary:
            actualValue = folderSummaryValue(item.folderChildSummary)
        case .sizeBytes:
            actualValue = item.sizeBytes.map(String.init) ?? ""
        case .createdAt:
            actualValue = item.createdAt.map { String($0.timeIntervalSince1970) } ?? ""
        case .modifiedAt:
            actualValue = item.modifiedAt.map { String($0.timeIntervalSince1970) } ?? ""
        }

        switch condition.operation {
        case .equals:
            return actualValue.localizedCaseInsensitiveCompare(condition.value) == .orderedSame
        case .contains:
            return actualValue.localizedCaseInsensitiveContains(condition.value)
        case .startsWith:
            return actualValue.lowercased().hasPrefix(condition.value.lowercased())
        case .endsWith:
            return actualValue.lowercased().hasSuffix(condition.value.lowercased())
        case .matchesRegex:
            return actualValue.range(of: condition.value, options: [.regularExpression, .caseInsensitive]) != nil
        case .greaterThan:
            return (Double(actualValue) ?? 0) > (Double(condition.value) ?? 0)
        case .lessThan:
            return (Double(actualValue) ?? 0) < (Double(condition.value) ?? 0)
        }
    }

    private func folderSummaryValue(_ summary: FolderChildSummary?) -> String {
        guard let summary else {
            return ""
        }
        let extensions = summary.topLevelExtensions.keys.map { "extension:\($0)" }.joined(separator: ",")
        return "\(summary.visibleChildCount),\(summary.visibleFileCount),\(summary.visibleFolderCount),\(extensions)"
    }
}

public extension Workflow {
    static func fixtureRulesWorkflow() -> Workflow {
        let root = WorkflowNode(
            kind: .router,
            name: "Downloads Router",
            branches: [
                WorkflowBranch(
                    name: "PDF Documents",
                    conditions: [
                        ConditionDescriptor(field: .fileExtension, operation: .equals, value: "pdf")
                    ],
                    node: WorkflowNode(
                        kind: .action,
                        name: "PDF Documents",
                        actions: [
                            ActionDescriptor(
                                operationKind: .move,
                                parameters: ["destination": "/Users/example/Bipbox/Documents"]
                            )
                        ]
                    )
                ),
                WorkflowBranch(
                    name: "Project Folders",
                    conditions: [
                        ConditionDescriptor(field: .itemKind, operation: .equals, value: ItemKind.folder.rawValue)
                    ],
                    node: WorkflowNode(
                        kind: .action,
                        name: "Project Folders",
                        actions: [
                            ActionDescriptor(
                                operationKind: .move,
                                parameters: ["destination": "/Users/example/Bipbox/Projects"],
                                recursiveFolderProcessing: false
                            )
                        ]
                    )
                )
            ],
            fallback: WorkflowNode(kind: .review, name: "Inbox")
        )
        return Workflow(name: "Default Rules", root: root)
    }
}

private extension String {
    func trimmingPrefix(_ prefix: String) -> String {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : self
    }
}
