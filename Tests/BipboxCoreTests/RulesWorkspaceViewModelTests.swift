import BipboxCore
import BipboxPersistence
import BipboxWorkspaceUI
import XCTest

@MainActor
final class RulesWorkspaceViewModelTests: XCTestCase {
    func testAddsAndRemovesFileRule() {
        let viewModel = RulesWorkspaceViewModel(workflow: emptyWorkflow())

        let branch = viewModel.addFileRule(
            name: "PDFs",
            fileExtension: ".pdf",
            destinationPath: "/Library/Documents"
        )

        XCTAssertEqual(viewModel.branches.count, 1)
        XCTAssertEqual(viewModel.selectedBranchID, branch.id)
        XCTAssertEqual(viewModel.selectedBranch?.conditions.first?.field, .fileExtension)
        XCTAssertEqual(viewModel.selectedBranch?.conditions.first?.operation, .equals)
        XCTAssertEqual(viewModel.selectedBranch?.conditions.first?.value, "pdf")
        XCTAssertEqual(viewModel.selectedBranch?.node.actions.first?.parameters["destination"], "/Library/Documents")

        viewModel.removeSelectedBranch()

        XCTAssertEqual(viewModel.branches, [])
        XCTAssertNil(viewModel.selectedBranchID)
    }

    func testAddsFolderRuleWithoutRecursiveFolderProcessing() {
        let viewModel = RulesWorkspaceViewModel(workflow: emptyWorkflow())

        viewModel.addFolderRule(name: "Folders", destinationPath: "/Library/Projects")

        XCTAssertEqual(viewModel.selectedBranch?.conditions.first?.field, .itemKind)
        XCTAssertEqual(viewModel.selectedBranch?.conditions.first?.operation, .equals)
        XCTAssertEqual(viewModel.selectedBranch?.conditions.first?.value, ItemKind.folder.rawValue)
        XCTAssertEqual(viewModel.selectedBranch?.node.actions.first?.operationKind, .move)
        XCTAssertEqual(viewModel.selectedBranch?.node.actions.first?.recursiveFolderProcessing, false)
    }

    func testFallbackCanBeConfiguredToInbox() {
        let viewModel = RulesWorkspaceViewModel(workflow: emptyWorkflow())

        XCTAssertEqual(viewModel.fallbackTitle, "None")

        viewModel.setFallbackToInbox()

        XCTAssertEqual(viewModel.fallbackTitle, "Inbox")
        XCTAssertEqual(viewModel.workflow.root.fallback?.kind, .review)
    }

    func testWorkflowSerializesAfterEditing() throws {
        let viewModel = RulesWorkspaceViewModel(workflow: emptyWorkflow())
        viewModel.addFileRule(name: "Images", fileExtension: "png", destinationPath: "/Library/Images")
        viewModel.setFallbackToInbox()

        let data = try viewModel.encodedWorkflow()
        let decoded = try JSONDecoder().decode(Workflow.self, from: data)

        XCTAssertEqual(decoded.root.branches.count, 1)
        XCTAssertEqual(decoded.root.branches.first?.name, "Images")
        XCTAssertEqual(decoded.root.fallback?.name, "Inbox")
    }

    func testUpdatingSelectedBranchPersistsExtensionFromForm() {
        let viewModel = RulesWorkspaceViewModel(workflow: emptyWorkflow())
        viewModel.addFileRule(name: "Documents", fileExtension: "pdf", destinationPath: "/Library/Documents")

        viewModel.updateSelectedBranch(
            name: "Markdown",
            destinationPath: "/Library/Notes",
            fileExtension: ".md"
        )

        XCTAssertEqual(viewModel.selectedBranch?.name, "Markdown")
        XCTAssertEqual(viewModel.selectedBranch?.conditions.first?.field, .fileExtension)
        XCTAssertEqual(viewModel.selectedBranch?.conditions.first?.value, "md")
        XCTAssertEqual(viewModel.selectedBranch?.node.actions.first?.parameters["destination"], "/Library/Notes")
        XCTAssertEqual(viewModel.ruleDocuments.first?.conditions.first?.value, "md")
    }

    func testFormRuleCanCreateMemoryOutcomeWithoutRawJSON() {
        let viewModel = RulesWorkspaceViewModel(workflow: emptyWorkflow())
        viewModel.addFileRule(name: "Draft", fileExtension: "pdf", destinationPath: "/Library/Documents")

        viewModel.updateSelectedRuleForm(
            name: "Launch Contracts",
            enabled: true,
            conditionField: .extractedText,
            conditionOperation: .contains,
            conditionValue: "statement of work",
            outcomeKind: .addToCollection,
            outcomeValue: "Contracts",
            requiresReview: false
        )

        XCTAssertEqual(viewModel.selectedBranch?.name, "Launch Contracts")
        XCTAssertEqual(viewModel.selectedBranch?.conditions.first?.field, .extractedText)
        XCTAssertEqual(viewModel.selectedBranch?.conditions.first?.value, "statement of work")
        XCTAssertEqual(viewModel.selectedBranch?.node.actions.first?.operationKind, .indexInPlace)
        XCTAssertEqual(viewModel.selectedBranch?.node.graphActions?.first?.kind, .addToCollection)
        XCTAssertEqual(viewModel.selectedBranch?.node.graphActions?.first?.parameters["collectionName"], "Contracts")
        XCTAssertEqual(viewModel.ruleDocuments.first?.graphActions.first?.kind, .addToCollection)
    }

    func testDisabledRuleFormEditRemovesRuleFromActiveWorkflowButKeepsDocument() {
        let viewModel = RulesWorkspaceViewModel(workflow: emptyWorkflow())
        let branch = viewModel.addFileRule(name: "PDF", fileExtension: "pdf", destinationPath: "/Library/Documents")

        viewModel.updateSelectedRuleForm(
            name: "PDF",
            enabled: false,
            conditionField: .fileExtension,
            conditionOperation: .equals,
            conditionValue: "pdf",
            outcomeKind: .move,
            outcomeValue: "/Library/Documents",
            requiresReview: false
        )

        XCTAssertEqual(viewModel.branches, [])
        XCTAssertEqual(viewModel.ruleDocuments.first?.id, branch.id)
        XCTAssertEqual(viewModel.ruleDocuments.first?.enabled, false)
    }

    func testRuleDocumentsMirrorWorkflowBranches() {
        let viewModel = RulesWorkspaceViewModel(workflow: emptyWorkflow())
        viewModel.addFileRule(name: "Images", fileExtension: "png", destinationPath: "/Library/Images")

        XCTAssertEqual(viewModel.ruleDocuments.count, 1)
        XCTAssertEqual(viewModel.ruleDocuments.first?.name, "Images")
        XCTAssertEqual(viewModel.ruleDocuments.first?.conditions.first?.value, "png")
        XCTAssertEqual(viewModel.ruleDocuments.first?.action.destinationPath, "/Library/Images")
        XCTAssertTrue(viewModel.selectedRuleJSON.contains("\"name\" : \"Images\""))
        XCTAssertTrue(viewModel.selectedRuleAIContext.contains("Current rule JSON"))
        XCTAssertTrue(viewModel.selectedRuleAIContext.contains("Images"))
    }

    func testRuleFilesCanBeSavedAndLoaded() async throws {
        let directory = try TemporaryDirectory()
        let store = try JSONRuleDocumentStore(directoryURL: directory.url)
        let original = RulesWorkspaceViewModel(workflow: emptyWorkflow(), ruleStore: store)
        original.addFileRule(name: "Images", fileExtension: "png", destinationPath: "/Library/Images")

        await original.saveRuleFiles()

        let loaded = RulesWorkspaceViewModel(workflow: emptyWorkflow(), ruleStore: store)
        await loaded.loadRuleFiles()

        XCTAssertEqual(loaded.branches.count, 1)
        XCTAssertEqual(loaded.selectedBranch?.name, "Images")
        XCTAssertEqual(loaded.selectedBranch?.conditions.first?.value, "png")
        XCTAssertEqual(loaded.selectedBranch?.node.actions.first?.parameters["destination"], "/Library/Images")
    }

    func testApplyRuleFilesReloadsExternalJSONEditsIntoActiveWorkflow() async throws {
        let directory = try TemporaryDirectory()
        let store = try JSONRuleDocumentStore(directoryURL: directory.url)
        let viewModel = RulesWorkspaceViewModel(workflow: emptyWorkflow(), ruleStore: store)
        let document = RuleDocument(
            name: "External JSON Rule",
            conditions: [
                ConditionDescriptor(field: .fileExtension, operation: .equals, value: "json")
            ],
            action: RuleActionDocument(operation: .move, destinationPath: "/Library/JSON")
        )
        try await store.saveRule(document)

        await viewModel.applyRuleFiles()

        XCTAssertEqual(viewModel.selectedBranch?.name, "External JSON Rule")
        XCTAssertEqual(viewModel.selectedBranch?.conditions.first?.value, "json")
        XCTAssertEqual(viewModel.selectedBranch?.node.actions.first?.parameters["destination"], "/Library/JSON")
        XCTAssertEqual(viewModel.ruleFilesMessage, "Applied 1 rule file(s) to the active workflow.")
    }

    func testGeneratedRuleJSONCanBeApplied() throws {
        let viewModel = RulesWorkspaceViewModel(workflow: emptyWorkflow())
        let document = RuleDocument(
            id: UUID(uuidString: "20000000-0000-0000-0000-000000000123")!,
            name: "LLM Rule",
            conditions: [
                ConditionDescriptor(field: .fileExtension, operation: .equals, value: "md")
            ],
            action: RuleActionDocument(operation: .move, destinationPath: "/Library/Notes")
        )
        let json = String(data: try JSONEncoder().encode(document), encoding: .utf8)!

        try viewModel.applyRuleDocumentJSON(json)

        XCTAssertEqual(viewModel.selectedBranch?.name, "LLM Rule")
        XCTAssertEqual(viewModel.selectedBranch?.conditions.first?.value, "md")
        XCTAssertEqual(viewModel.selectedBranch?.node.actions.first?.parameters["destination"], "/Library/Notes")
    }

    func testSimulationReportsMatchedWorkflowPath() async {
        let viewModel = RulesWorkspaceViewModel(workflow: .fixtureRulesWorkflow())

        await viewModel.simulate(item: .rulesFixtureFolder(), now: TestClock.now)

        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.simulationResult?.itemName, "Client Project")
        XCTAssertEqual(viewModel.simulationResult?.matchedPath, ["Downloads Router", "Project Folders"])
        XCTAssertEqual(viewModel.simulationResult?.decision.reviewRequirement, .notRequired)
    }

    func testSimulationCanUseMockWorkflowEngine() async {
        let branchID = UUID(uuidString: "30000000-0000-0000-0000-000000000001")!
        let decision = RouteDecision(
            confidence: 0.75,
            matchedRuleIDs: [branchID],
            reason: "Mock matched.",
            reviewRequirement: .recommended
        )
        let engine = RulesMockWorkflowEngine(decision: decision)
        let branch = WorkflowBranch(
            id: branchID,
            name: "Mock Rule",
            conditions: [],
            node: WorkflowNode(kind: .action, name: "Mock Rule")
        )
        let workflow = Workflow(
            name: "Mock Workflow",
            root: WorkflowNode(kind: .router, name: "Root", branches: [branch])
        )
        let viewModel = RulesWorkspaceViewModel(workflow: workflow, workflowSimulator: engine)

        await viewModel.simulate(item: .rulesFixturePDF(), now: TestClock.now)

        XCTAssertEqual(engine.evaluatedItems.map(\.displayName), ["report.pdf"])
        XCTAssertEqual(viewModel.simulationResult?.matchedPath, ["Root", "Mock Rule"])
        XCTAssertEqual(viewModel.simulationResult?.decision.reason, "Mock matched.")
    }

    func testDroppedItemSelectsMatchingRuleWithoutDraft() async {
        let viewModel = RulesWorkspaceViewModel(workflow: .fixtureRulesWorkflow())

        await viewModel.routeDroppedItem(.rulesFixturePDF(), defaultDestinationPath: "/Library/Bipbox", now: TestClock.now)

        XCTAssertEqual(viewModel.selectedBranch?.name, "PDF Documents")
        XCTAssertNil(viewModel.newRuleDraft)
        XCTAssertEqual(
            viewModel.dropRoutingState,
            .matched(ruleName: "PDF Documents", destinationPath: "/Users/example/Bipbox/Documents")
        )
    }

    func testDroppedUnknownItemCreatesNewRuleDraft() async {
        let viewModel = RulesWorkspaceViewModel(workflow: .fixtureRulesWorkflow())
        let item = ItemProfile(
            url: URL(fileURLWithPath: "/Users/example/Downloads/photo.heic"),
            kind: .file,
            displayName: "photo.heic",
            fileExtension: "heic",
            source: .dragDrop
        )

        await viewModel.routeDroppedItem(item, defaultDestinationPath: "/Library/Bipbox", now: TestClock.now)

        XCTAssertEqual(viewModel.newRuleDraft?.ruleName, "HEIC Files")
        XCTAssertEqual(viewModel.newRuleDraft?.fileExtension, "heic")
        XCTAssertEqual(viewModel.newRuleDraft?.destinationPath, "/Library/Bipbox")
        XCTAssertEqual(
            viewModel.dropRoutingState,
            .needsRule(itemName: "photo.heic", reason: "No automatic rule matched photo.heic.")
        )
    }

    func testCreateRuleFromDroppedDraftAddsAndSelectsRoute() async {
        let viewModel = RulesWorkspaceViewModel(workflow: emptyWorkflow())
        let item = ItemProfile(
            url: URL(fileURLWithPath: "/Users/example/Downloads/photo.heic"),
            kind: .file,
            displayName: "photo.heic",
            fileExtension: "heic",
            source: .dragDrop
        )

        await viewModel.routeDroppedItem(item, defaultDestinationPath: "/Library/Photos", now: TestClock.now)
        viewModel.newRuleDraft?.ruleName = "Camera Imports"
        let branch = viewModel.createRuleFromDraft()

        XCTAssertEqual(branch?.name, "Camera Imports")
        XCTAssertEqual(viewModel.selectedBranch?.name, "Camera Imports")
        XCTAssertEqual(viewModel.selectedBranch?.conditions.first?.value, "heic")
        XCTAssertEqual(viewModel.selectedBranch?.node.actions.first?.parameters["destination"], "/Library/Photos")
        XCTAssertNil(viewModel.newRuleDraft)
    }
    // MARK: redesign rules CRUD/toggle

    func testAddBlankRulePersistsAndSelects() async throws {
        let directory = try TemporaryDirectory()
        let store = try JSONRuleDocumentStore(directoryURL: directory.url)
        let vm = RulesWorkspaceViewModel(workflow: emptyWorkflow(), ruleStore: store)

        let id = await vm.addBlankRule()

        XCTAssertEqual(vm.selectedBranchID, id)
        XCTAssertEqual(vm.ruleDocuments.count, 1)

        let reloaded = RulesWorkspaceViewModel(workflow: emptyWorkflow(), ruleStore: store)
        await reloaded.loadRuleFiles()
        XCTAssertEqual(reloaded.ruleDocuments.count, 1)
    }

    func testDisablingRuleKeepsItOnDiskButOutOfWorkflow() async throws {
        let directory = try TemporaryDirectory()
        let store = try JSONRuleDocumentStore(directoryURL: directory.url)
        let vm = RulesWorkspaceViewModel(workflow: emptyWorkflow(), ruleStore: store)
        let branch = vm.addFileRule(name: "PNGs", fileExtension: "png", destinationPath: "/x")
        await vm.saveRuleFiles()

        await vm.setRuleEnabled(id: branch.id, false)

        // Disabled rule is dropped from the active workflow…
        XCTAssertTrue(vm.workflow.root.branches.isEmpty)
        // …but kept in the document list (and on disk).
        XCTAssertEqual(vm.ruleDocuments.count, 1)
        XCTAssertEqual(vm.ruleDocuments.first?.enabled, false)

        let reloaded = RulesWorkspaceViewModel(workflow: emptyWorkflow(), ruleStore: store)
        await reloaded.loadRuleFiles()
        XCTAssertEqual(reloaded.ruleDocuments.count, 1, "Disabled rule must survive a reload, not be deleted")
        XCTAssertEqual(reloaded.ruleDocuments.first?.enabled, false)
    }

    func testDeleteRuleRemovesItFromDisk() async throws {
        let directory = try TemporaryDirectory()
        let store = try JSONRuleDocumentStore(directoryURL: directory.url)
        let vm = RulesWorkspaceViewModel(workflow: emptyWorkflow(), ruleStore: store)
        let branch = vm.addFileRule(name: "PNGs", fileExtension: "png", destinationPath: "/x")
        await vm.saveRuleFiles()

        await vm.deleteRule(id: branch.id)
        XCTAssertTrue(vm.ruleDocuments.isEmpty)

        let reloaded = RulesWorkspaceViewModel(workflow: emptyWorkflow(), ruleStore: store)
        await reloaded.loadRuleFiles()
        XCTAssertTrue(reloaded.ruleDocuments.isEmpty)
    }

    func testRenameRulePersists() async throws {
        let directory = try TemporaryDirectory()
        let store = try JSONRuleDocumentStore(directoryURL: directory.url)
        let vm = RulesWorkspaceViewModel(workflow: emptyWorkflow(), ruleStore: store)
        let branch = vm.addFileRule(name: "Old", fileExtension: "png", destinationPath: "/x")
        await vm.saveRuleFiles()

        await vm.renameRule(id: branch.id, to: "New Name")

        let reloaded = RulesWorkspaceViewModel(workflow: emptyWorkflow(), ruleStore: store)
        await reloaded.loadRuleFiles()
        XCTAssertEqual(reloaded.ruleDocuments.first?.name, "New Name")
    }
}

private func emptyWorkflow() -> Workflow {
    Workflow(name: "Empty", root: WorkflowNode(kind: .router, name: "Root"))
}

@MainActor
private final class RulesMockWorkflowEngine: RulesWorkflowSimulating {
    let decision: RouteDecision
    private(set) var evaluatedItems: [ItemProfile] = []

    init(decision: RouteDecision) {
        self.decision = decision
    }

    func evaluate(
        workflow: Workflow,
        item: ItemProfile,
        context: WorkflowEvaluationContext
    ) async throws -> RouteDecision {
        evaluatedItems.append(item)
        return decision
    }
}
