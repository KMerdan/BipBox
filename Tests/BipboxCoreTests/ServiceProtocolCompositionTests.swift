import BipboxCore
import XCTest

final class ServiceProtocolCompositionTests: XCTestCase {
    func testMockOrganizationPipelineCanBeComposedFromProtocols() async throws {
        let request = ItemFixtures.request(
            url: URL(fileURLWithPath: "/tmp/Project"),
            kind: .folder
        )
        let profile = ItemFixtures.folderProfile(url: request.itemURL)
        let workflow = WorkflowFixtures.folderWorkflow()
        let operation = Operation(
            kind: .move,
            itemURL: profile.url,
            destinationURL: URL(fileURLWithPath: "/tmp/Bipbox/Projects/Project"),
            reversible: true
        )
        let plan = OperationPlan(
            operations: [operation],
            expectedResultURL: operation.destinationURL,
            reversible: true,
            previewText: "Move Project to Projects."
        )

        let intake: IntakeService = MockIntakeService()
        let inspector: ItemInspector = MockItemInspector(profile: profile)
        let engine: WorkflowEngine = MockWorkflowEngine(
            decision: RouteDecision(
                confidence: 1,
                destinationURL: operation.destinationURL,
                actions: workflow.root.branches.first?.node.actions ?? [],
                reason: "Matched folder workflow.",
                reviewRequirement: .notRequired
            )
        )
        let planner: OperationPlanner = MockOperationPlanner(plan: plan)
        let executor = MockOperationExecutor()
        let search = MockSearchService()
        let activity = MockActivityLog()

        let intakeResult = try await intake.submit(request)
        let inspected = try await inspector.inspect(
            intakeResult.request,
            options: InspectionOptions()
        )
        let decision = try await engine.evaluate(
            workflow: workflow,
            item: inspected,
            context: WorkflowEvaluationContext(mode: request.mode, now: TestClock.now)
        )
        let operationPlan = try await planner.plan(
            decision: decision,
            item: inspected,
            context: PlanningContext(now: TestClock.now)
        )
        let execution = try await executor.execute(
            operationPlan,
            context: ExecutionContext(dryRun: true, actor: "test")
        )
        let indexed = IndexedItem(
            id: inspected.id,
            currentPath: execution.operationResults.first?.resultingURL?.path ?? inspected.url.path,
            originalPath: inspected.url.path,
            displayName: inspected.displayName,
            kind: inspected.kind,
            importedAt: TestClock.now,
            status: .organized
        )
        try await search.index(indexed)
        try await activity.append(
            ActivityEvent(
                kind: .executed,
                itemID: inspected.id,
                requestID: request.id,
                planID: operationPlan.id,
                message: "Executed mock plan.",
                occurredAt: TestClock.now,
                undoOperation: operation
            )
        )

        let searchResults = try await search.search(SearchQuery(text: "Project", kinds: [.folder]))
        let activityEvents = try await activity.events(forItemID: inspected.id)

        XCTAssertEqual(intakeResult.accepted, true)
        XCTAssertEqual(inspected.kind, .folder)
        XCTAssertEqual(decision.reviewRequirement, .notRequired)
        XCTAssertEqual(operationPlan.operations.first?.kind, .move)
        XCTAssertEqual(execution.operationResults.first?.status, .completed)
        XCTAssertEqual(searchResults.items.first?.kind, .folder)
        XCTAssertEqual(activityEvents.count, 1)
    }

    func testAIBoundaryUsesToolProtocolShape() async throws {
        let registry = MockToolRegistry()
        let descriptor = ToolDescriptor(
            name: "inspect_item",
            description: "Inspect an item.",
            inputSchema: #"{"path":"string"}"#,
            outputSchema: #"{"kind":"string"}"#,
            permissions: [.read],
            dryRunSupported: true,
            reversible: false
        )

        try await registry.register(descriptor)
        let found = await registry.descriptor(named: "inspect_item")
        let result = try await registry.execute(
            ToolCall(
                toolName: "inspect_item",
                input: ["path": "/tmp/Project"],
                requestedPermissions: [.read],
                dryRun: true
            ),
            context: ExecutionContext(dryRun: true, actor: "ai")
        )

        XCTAssertEqual(found, descriptor)
        XCTAssertEqual(result.output["path"], "/tmp/Project")
        XCTAssertEqual(result.message, "dry-run")
    }
}

