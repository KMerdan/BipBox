import BipboxAI
import BipboxCore
import XCTest

final class DefaultWorkflowEngineTests: XCTestCase {
    func testActionNodeCarriesGraphActionsIntoDecision() async throws {
        let graphAction = GraphActionDescriptor(
            kind: .addToCollection,
            parameters: ["collectionName": "Research"]
        )
        let node = WorkflowNode(
            kind: .action,
            name: "Tag Research",
            graphActions: [graphAction]
        )
        let workflow = Workflow(name: "Graph", root: node)

        let decision = try await DefaultWorkflowEngine().evaluate(
            workflow: workflow,
            item: ItemFixtures.fileProfile(),
            context: WorkflowEvaluationContext(mode: .organize, now: TestClock.now)
        )

        XCTAssertEqual(decision.actions, [])
        XCTAssertEqual(decision.graphActions, [graphAction])
        XCTAssertEqual(decision.reviewRequirement, .notRequired)
    }

    func testFirstMatchingBranchRoutesToAction() async throws {
        let pdfAction = ActionDescriptor(
            operationKind: .move,
            parameters: ["destination": "/tmp/Bipbox/PDFs"]
        )
        let pdfNode = WorkflowNode(kind: .action, name: "Move PDFs", actions: [pdfAction])
        let catchAllNode = WorkflowNode(
            kind: .action,
            name: "Catch All",
            actions: [
                ActionDescriptor(
                    operationKind: .move,
                    parameters: ["destination": "/tmp/Bipbox/Other"]
                )
            ]
        )
        let pdfBranch = WorkflowBranch(
            name: "PDF",
            conditions: [
                ConditionDescriptor(field: .fileExtension, operation: .equals, value: "pdf")
            ],
            node: pdfNode
        )
        let catchAllBranch = WorkflowBranch(name: "Any File", conditions: [], node: catchAllNode)
        let root = WorkflowNode(kind: .router, name: "Root", branches: [pdfBranch, catchAllBranch])
        let workflow = Workflow(name: "Documents", root: root)

        let decision = try await DefaultWorkflowEngine().evaluate(
            workflow: workflow,
            item: ItemFixtures.fileProfile(),
            context: WorkflowEvaluationContext(mode: .organize, now: TestClock.now)
        )

        XCTAssertEqual(decision.destinationURL?.path, "/tmp/Bipbox/PDFs")
        XCTAssertEqual(decision.actions, [pdfAction])
        XCTAssertEqual(decision.reviewRequirement, .notRequired)
        XCTAssertEqual(decision.matchedRuleIDs, [root.id, pdfBranch.id, pdfNode.id])
    }

    func testFallbackRoutesWhenNoBranchMatches() async throws {
        let fallback = WorkflowNode(kind: .review, name: "Fallback Review")
        let root = WorkflowNode(
            kind: .router,
            name: "Root",
            branches: [
                WorkflowBranch(
                    name: "Images",
                    conditions: [
                        ConditionDescriptor(field: .fileExtension, operation: .equals, value: "png")
                    ],
                    node: WorkflowNode(kind: .action, name: "Move Images")
                )
            ],
            fallback: fallback
        )
        let workflow = Workflow(name: "Fallback", root: root)

        let decision = try await DefaultWorkflowEngine().evaluate(
            workflow: workflow,
            item: ItemFixtures.fileProfile(),
            context: WorkflowEvaluationContext(mode: .organize, now: TestClock.now)
        )

        XCTAssertEqual(decision.reviewRequirement, .required)
        XCTAssertEqual(decision.matchedRuleIDs, [root.id, fallback.id])
        XCTAssertTrue(decision.reason.contains("requires review"))
    }

    func testFolderSpecificRuleMatchesWithoutDeepInspection() async throws {
        let workflow = WorkflowFixtures.folderWorkflow(destination: URL(fileURLWithPath: "/tmp/Bipbox/Projects"))
        let folder = ItemFixtures.folderProfile()

        let decision = try await DefaultWorkflowEngine().evaluate(
            workflow: workflow,
            item: folder,
            context: WorkflowEvaluationContext(mode: .organize, now: TestClock.now)
        )

        XCTAssertEqual(decision.destinationURL?.path, "/tmp/Bipbox/Projects")
        XCTAssertEqual(decision.actions.first?.recursiveFolderProcessing, false)
        XCTAssertEqual(folder.folderChildSummary?.recursiveInspectionRequested, false)
        XCTAssertEqual(decision.reviewRequirement, .notRequired)
    }

    func testFolderSummaryConditionCanMatchTopLevelExtension() async throws {
        let action = ActionDescriptor(operationKind: .move, parameters: ["destination": "/tmp/Bipbox/FolderPDFs"])
        let actionNode = WorkflowNode(kind: .action, name: "Folder With PDF", actions: [action])
        let branch = WorkflowBranch(
            name: "Contains Top-Level PDF",
            conditions: [
                ConditionDescriptor(field: .folderChildSummary, operation: .contains, value: "extension:pdf")
            ],
            node: actionNode
        )
        let root = WorkflowNode(kind: .router, name: "Root", branches: [branch])
        let workflow = Workflow(name: "Folder Summary", root: root)

        let decision = try await DefaultWorkflowEngine().evaluate(
            workflow: workflow,
            item: ItemFixtures.folderProfile(),
            context: WorkflowEvaluationContext(mode: .organize, now: TestClock.now)
        )

        XCTAssertEqual(decision.destinationURL?.path, "/tmp/Bipbox/FolderPDFs")
    }

    func testSourceAndContextAwareConditionsCanMatchMemoryFacts() async throws {
        let action = ActionDescriptor(operationKind: .indexInPlace)
        let actionNode = WorkflowNode(kind: .action, name: "Memory Policy", actions: [action])
        let sourceID = UUID(uuidString: "60000000-0000-0000-0000-000000000001")!
        let branch = WorkflowBranch(
            name: "Downloads Launch Contracts",
            conditions: [
                ConditionDescriptor(field: .sourceID, operation: .equals, value: sourceID.uuidString),
                ConditionDescriptor(field: .sourceKind, operation: .equals, value: SourceKind.watchedFolder.rawValue),
                ConditionDescriptor(field: .collection, operation: .equals, value: "Contracts"),
                ConditionDescriptor(field: .context, operation: .contains, value: "Launch"),
                ConditionDescriptor(field: .extractedText, operation: .contains, value: "statement of work")
            ],
            node: actionNode
        )
        let workflow = Workflow(name: "Memory", root: WorkflowNode(kind: .router, name: "Root", branches: [branch]))
        let item = ItemProfile(
            url: URL(fileURLWithPath: "/Downloads/sow.pdf"),
            kind: .file,
            displayName: "sow.pdf",
            fileExtension: "pdf",
            extractedTextSummary: "Draft statement of work",
            metadata: ["collections": "Contracts", "contexts": "Launch Project"]
        )

        let decision = try await DefaultWorkflowEngine().evaluate(
            workflow: workflow,
            item: item,
            context: WorkflowEvaluationContext(
                mode: .organize,
                now: TestClock.now,
                sourceID: sourceID,
                sourceFacts: ["sourceKind": SourceKind.watchedFolder.rawValue]
            )
        )

        XCTAssertEqual(decision.actions, [action])
        XCTAssertEqual(decision.reviewRequirement, .notRequired)
    }

    func testReviewNodeRequiresReview() async throws {
        let review = WorkflowNode(kind: .review, name: "Manual Review")
        let workflow = Workflow(name: "Review", root: review)

        let decision = try await DefaultWorkflowEngine().evaluate(
            workflow: workflow,
            item: ItemFixtures.fileProfile(),
            context: WorkflowEvaluationContext(mode: .organize, now: TestClock.now)
        )

        XCTAssertEqual(decision.confidence, 0)
        XCTAssertEqual(decision.reviewRequirement, .required)
        XCTAssertEqual(decision.matchedRuleIDs, [review.id])
    }

    func testSimulationProducesSameDecisionAsOrganizeMode() async throws {
        let workflow = WorkflowFixtures.folderWorkflow()
        let item = ItemFixtures.folderProfile()
        let engine = DefaultWorkflowEngine()

        let organizeDecision = try await engine.evaluate(
            workflow: workflow,
            item: item,
            context: WorkflowEvaluationContext(mode: .organize, now: TestClock.now)
        )
        let simulateDecision = try await engine.evaluate(
            workflow: workflow,
            item: item,
            context: WorkflowEvaluationContext(mode: .simulate, now: TestClock.now)
        )

        XCTAssertEqual(simulateDecision, organizeDecision)
    }

    func testUnsupportedNodeFailsSafelyIntoReview() async throws {
        let aiNode = WorkflowNode(kind: .aiClassify, name: "AI Later")
        let workflow = Workflow(name: "Future", root: aiNode)

        let decision = try await DefaultWorkflowEngine().evaluate(
            workflow: workflow,
            item: ItemFixtures.fileProfile(),
            context: WorkflowEvaluationContext(mode: .organize, now: TestClock.now)
        )

        XCTAssertEqual(decision.reviewRequirement, .required)
        XCTAssertTrue(decision.reason.contains("no configured AI gateway"))
    }

    func testAIPlaceholderResponseRequiresReview() async throws {
        let aiNode = WorkflowNode(kind: .aiClassify, name: "AI Placeholder")
        let workflow = Workflow(name: "Future", root: aiNode)
        let engine = DefaultWorkflowEngine(aiOrchestrator: NoModelAIGateway())

        let decision = try await engine.evaluate(
            workflow: workflow,
            item: ItemFixtures.fileProfile(),
            context: WorkflowEvaluationContext(mode: .organize, now: TestClock.now)
        )

        XCTAssertEqual(decision.confidence, 0)
        XCTAssertEqual(decision.reviewRequirement, .required)
        XCTAssertTrue(decision.reason.contains("No AI model"))
    }

    func testAIHighConfidenceFixtureCanReturnWorkflowAllowedAction() async throws {
        let action = ActionDescriptor(operationKind: .move, parameters: ["destination": "/tmp/Bipbox/AI"])
        let aiNode = WorkflowNode(kind: .aiClassify, name: "AI Classify", actions: [action])
        let workflow = Workflow(name: "AI", root: aiNode)
        let engine = DefaultWorkflowEngine(
            aiOrchestrator: FixtureAIOrchestrator(
                classification: AIClassification(
                    category: "documents",
                    confidence: 0.96,
                    reason: "Looks like a document.",
                    reviewRequirement: .notRequired
                )
            )
        )

        let decision = try await engine.evaluate(
            workflow: workflow,
            item: ItemFixtures.fileProfile(),
            context: WorkflowEvaluationContext(mode: .organize, now: TestClock.now)
        )

        XCTAssertEqual(decision.confidence, 0.96)
        XCTAssertEqual(decision.destinationURL?.path, "/tmp/Bipbox/AI")
        XCTAssertEqual(decision.actions, [action])
        XCTAssertEqual(decision.reviewRequirement, .notRequired)
        XCTAssertTrue(decision.reason.contains("Looks like a document"))
    }

    func testAIMediumConfidenceFallsBackToReview() async throws {
        let action = ActionDescriptor(operationKind: .move, parameters: ["destination": "/tmp/Bipbox/AI"])
        let aiNode = WorkflowNode(kind: .aiClassify, name: "AI Classify", actions: [action])
        let workflow = Workflow(name: "AI", root: aiNode)
        let engine = DefaultWorkflowEngine(
            aiOrchestrator: FixtureAIOrchestrator(
                classification: AIClassification(
                    category: "documents",
                    confidence: 0.6,
                    reason: "Could be a document.",
                    reviewRequirement: .recommended
                )
            )
        )

        let decision = try await engine.evaluate(
            workflow: workflow,
            item: ItemFixtures.fileProfile(),
            context: WorkflowEvaluationContext(mode: .organize, now: TestClock.now)
        )

        XCTAssertEqual(decision.confidence, 0.6)
        XCTAssertEqual(decision.actions, [action])
        XCTAssertEqual(decision.reviewRequirement, .required)
        XCTAssertTrue(decision.reason.contains("Could be a document"))
    }

    func testAIFolderProfileClassificationUsesSameNode() async throws {
        let action = ActionDescriptor(operationKind: .move, parameters: ["destination": "/tmp/Bipbox/Projects"])
        let ai = FixtureAIOrchestrator(
            classification: AIClassification(
                category: "project",
                confidence: 0.95,
                reason: "Looks like a project folder.",
                reviewRequirement: .notRequired
            )
        )
        let aiNode = WorkflowNode(kind: .aiClassify, name: "AI Folder", actions: [action])
        let workflow = Workflow(name: "AI", root: aiNode)

        let decision = try await DefaultWorkflowEngine(aiOrchestrator: ai).evaluate(
            workflow: workflow,
            item: ItemFixtures.folderProfile(),
            context: WorkflowEvaluationContext(mode: .organize, now: TestClock.now)
        )

        XCTAssertEqual(ai.requests.map(\.itemProfile.kind), [.folder])
        XCTAssertEqual(decision.destinationURL?.path, "/tmp/Bipbox/Projects")
        XCTAssertEqual(decision.reviewRequirement, .notRequired)
    }

    func testAIDestructiveActionsCanStillRequireReview() async throws {
        let action = ActionDescriptor(
            operationKind: .move,
            parameters: ["destination": "/tmp/Bipbox/AI"],
            requiresReview: true
        )
        let aiNode = WorkflowNode(kind: .aiClassify, name: "AI Move", actions: [action])
        let workflow = Workflow(name: "AI", root: aiNode)
        let engine = DefaultWorkflowEngine(
            aiOrchestrator: FixtureAIOrchestrator(
                classification: AIClassification(
                    category: "documents",
                    confidence: 0.99,
                    reason: "High confidence, but workflow requires review.",
                    reviewRequirement: .notRequired
                )
            )
        )

        let decision = try await engine.evaluate(
            workflow: workflow,
            item: ItemFixtures.fileProfile(),
            context: WorkflowEvaluationContext(mode: .organize, now: TestClock.now)
        )

        XCTAssertEqual(decision.actions, [action])
        XCTAssertEqual(decision.reviewRequirement, .required)
    }
}

private final class FixtureAIOrchestrator: AIOrchestrator, @unchecked Sendable {
    let classification: AIClassification
    private(set) var requests: [AIRequest] = []

    init(classification: AIClassification) {
        self.classification = classification
    }

    func classify(_ request: AIRequest) async throws -> AIClassification {
        requests.append(request)
        return classification
    }

    func callTool(_ call: ToolCall, context: ExecutionContext) async throws -> ToolResult {
        ToolResult(toolName: call.toolName)
    }
}
