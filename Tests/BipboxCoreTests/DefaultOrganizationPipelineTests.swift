import BipboxCore
import XCTest

final class DefaultOrganizationPipelineTests: XCTestCase {
    func testOrganizeModeRunsAllStagesAndIndexesOrganizedItem() async throws {
        let setup = PipelineSetup(mode: .organize)

        let result = await setup.pipeline.process(setup.request, configuration: setup.configuration)

        XCTAssertEqual(result.status, .organized)
        XCTAssertEqual(setup.stabilizer.requests, [setup.request])
        XCTAssertEqual(setup.inspector.requests, [setup.request])
        XCTAssertEqual(setup.executor.executedPlans, [setup.plan])
        XCTAssertEqual(setup.search.items.first?.status, .organized)
        XCTAssertEqual(setup.search.items.first?.originalPath, setup.profile.url.path)
        XCTAssertTrue(setup.activity.events.contains { $0.kind == .executed })
        XCTAssertTrue(setup.activity.events.contains { $0.kind == .indexed })
        XCTAssertLessThan(
            try XCTUnwrap(setup.activity.events.firstIndex { $0.kind == .indexed }),
            try XCTUnwrap(setup.activity.events.firstIndex { $0.kind == .executed })
        )
        XCTAssertEqual(setup.knowledge.items[setup.profile.id]?.state, .active)
        XCTAssertEqual(setup.knowledge.captureEvents.map(\.itemID), [setup.profile.id])
    }

    func testSimulateModeDoesNotExecuteOrIndex() async throws {
        let setup = PipelineSetup(mode: .simulate)

        let result = await setup.pipeline.process(setup.request, configuration: setup.configuration)

        XCTAssertEqual(result.status, .simulated)
        XCTAssertEqual(setup.executor.executedPlans, [])
        XCTAssertEqual(setup.search.items, [])
        XCTAssertEqual(setup.knowledge.items[setup.profile.id]?.state, .active)
        XCTAssertEqual(setup.knowledge.captureEvents.count, 1)
        XCTAssertTrue(setup.activity.events.contains { $0.kind == .planned })
        XCTAssertFalse(setup.activity.events.contains { $0.kind == .executed })
    }

    func testReviewModeStagesItemWithoutMoving() async throws {
        let setup = PipelineSetup(mode: .review)

        let result = await setup.pipeline.process(setup.request, configuration: setup.configuration)

        XCTAssertEqual(result.status, .stagedForReview)
        XCTAssertEqual(setup.executor.executedPlans, [])
        XCTAssertEqual(setup.search.items.first?.status, .needsReview)
        XCTAssertEqual(setup.search.items.first?.currentPath, setup.profile.url.path)
        XCTAssertEqual(setup.knowledge.items[setup.profile.id]?.state, .needsReview)
    }

    func testRequiredReviewDecisionStagesItemWithoutMoving() async throws {
        let reviewPlan = OperationPlan(
            operations: [
                Operation(
                    kind: .markNeedsReview,
                    itemURL: URL(fileURLWithPath: "/tmp/report.pdf"),
                    value: "No route matched.",
                    reversible: true
                )
            ],
            reversible: true,
            previewText: "Mark report.pdf as needs review."
        )
        let setup = PipelineSetup(
            mode: .organize,
            decision: RouteDecision(
                confidence: 0,
                reason: "No route matched.",
                reviewRequirement: .required
            ),
            plan: reviewPlan
        )

        let result = await setup.pipeline.process(setup.request, configuration: setup.configuration)

        XCTAssertEqual(result.status, .stagedForReview)
        XCTAssertEqual(setup.executor.executedPlans, [])
        XCTAssertEqual(result.plan?.operations.map(\.kind), [.markNeedsReview])
    }

    func testFolderRequestFlowsAsOneFolderItem() async throws {
        let request = ItemFixtures.request(url: URL(fileURLWithPath: "/tmp/Project"), kind: .folder)
        let profile = ItemFixtures.folderProfile(url: request.itemURL)
        let setup = PipelineSetup(request: request, profile: profile)

        let result = await setup.pipeline.process(setup.request, configuration: setup.configuration)

        XCTAssertEqual(result.status, .organized)
        XCTAssertEqual(result.itemProfile?.kind, .folder)
        XCTAssertEqual(setup.search.items.first?.kind, .folder)
        XCTAssertEqual(setup.executor.executedPlans.first?.operations.first?.itemURL.path, "/tmp/Project")
    }

    func testIndexOnlyModeIndexesInPlaceWithoutRoutingOrExecution() async throws {
        let setup = PipelineSetup(mode: .indexOnly)

        let result = await setup.pipeline.process(setup.request, configuration: setup.configuration)

        XCTAssertEqual(result.status, .indexedOnly)
        XCTAssertEqual(setup.executor.executedPlans, [])
        XCTAssertEqual(setup.search.items.first?.status, .indexedOnly)
        XCTAssertEqual(setup.search.items.first?.currentPath, setup.profile.url.path)
        XCTAssertEqual(setup.knowledge.items[setup.profile.id]?.state, .active)
        XCTAssertFalse(setup.activity.events.contains { $0.kind == .routed })
    }

    func testExecutionFailureIsLogged() async throws {
        let setup = PipelineSetup(mode: .organize)
        setup.executor.errorToThrow = PipelineTestError.executionFailed

        let result = await setup.pipeline.process(setup.request, configuration: setup.configuration)

        XCTAssertEqual(result.status, .failed)
        XCTAssertTrue(setup.activity.events.contains { $0.kind == .failed })
        XCTAssertEqual(setup.search.items.first?.status, .failed)
        XCTAssertEqual(setup.search.items.first?.currentPath, setup.profile.url.path)
        XCTAssertEqual(setup.knowledge.items[setup.profile.id]?.state, .failed)
        XCTAssertEqual(setup.knowledge.captureEvents.count, 1)
    }

    func testGraphOnlyRuleAddsCollectionWithoutMovingFile() async throws {
        let collectionID = UUID(uuidString: "50000000-0000-0000-0000-000000000002")!
        let graphOperation = GraphOperation(
            kind: .addToCollection,
            itemID: ItemFixtures.fileProfile().id,
            parameters: [
                "collectionID": collectionID.uuidString,
                "collectionName": "Research"
            ]
        )
        let plan = OperationPlan(
            operations: [],
            graphOperations: [graphOperation],
            reversible: true,
            previewText: "Add report.pdf to collection Research."
        )
        let setup = PipelineSetup(
            mode: .organize,
            decision: RouteDecision(
                confidence: 1,
                graphActions: [
                    GraphActionDescriptor(
                        kind: .addToCollection,
                        parameters: [
                            "collectionID": collectionID.uuidString,
                            "collectionName": "Research"
                        ]
                    )
                ],
                reason: "Add to collection.",
                reviewRequirement: .notRequired
            ),
            plan: plan
        )

        let result = await setup.pipeline.process(setup.request, configuration: setup.configuration)

        XCTAssertEqual(result.status, .organized)
        XCTAssertEqual(setup.executor.executedPlans.first?.operations, [])
        XCTAssertEqual(setup.knowledge.collections[collectionID]?.name, "Research")
        XCTAssertEqual(setup.knowledge.collectionMemberships[collectionID], [setup.profile.id])
        XCTAssertTrue(setup.activity.events.contains { $0.kind == .relationshipRecorded })
    }

    func testReviewRequiredFilesystemPlanStillAppliesSafeGraphOperation() async throws {
        let contextID = UUID(uuidString: "50000000-0000-0000-0000-000000000003")!
        let moveOperation = Operation(
            kind: .move,
            itemURL: URL(fileURLWithPath: "/tmp/report.pdf"),
            destinationURL: URL(fileURLWithPath: "/tmp/Bipbox/PDFs/report.pdf"),
            reversible: true
        )
        let graphOperation = GraphOperation(
            kind: .addTopic,
            itemID: ItemFixtures.fileProfile().id,
            parameters: [
                "contextID": contextID.uuidString,
                "topic": "finance"
            ]
        )
        let plan = OperationPlan(
            operations: [moveOperation],
            graphOperations: [graphOperation],
            expectedResultURL: moveOperation.destinationURL,
            reversible: true,
            previewText: "Move report.pdf. Add topic finance."
        )
        let setup = PipelineSetup(
            mode: .organize,
            decision: RouteDecision(
                confidence: 0.4,
                actions: [
                    ActionDescriptor(
                        operationKind: .move,
                        parameters: ["destination": "/tmp/Bipbox/PDFs/"],
                        requiresReview: true
                    )
                ],
                graphActions: [
                    GraphActionDescriptor(
                        kind: .addTopic,
                        parameters: [
                            "contextID": contextID.uuidString,
                            "topic": "finance"
                        ]
                    )
                ],
                reason: "Move needs review.",
                reviewRequirement: .required
            ),
            plan: plan
        )

        let result = await setup.pipeline.process(setup.request, configuration: setup.configuration)

        XCTAssertEqual(result.status, .stagedForReview)
        XCTAssertEqual(setup.executor.executedPlans, [])
        XCTAssertEqual(setup.knowledge.contexts[contextID]?.name, "finance")
        XCTAssertEqual(
            setup.knowledge.relationshipsByID.values.map(\.predicate),
            [.hasTopic]
        )
        XCTAssertTrue(setup.activity.events.contains { $0.kind == .relationshipRecorded })
    }

    func testCaptureSessionIDCanComeFromRequestContext() async throws {
        let sessionID = UUID(uuidString: "50000000-0000-0000-0000-000000000001")!
        let request = OrganizationRequest(
            source: .dragDrop,
            itemURL: URL(fileURLWithPath: "/tmp/report.pdf"),
            itemKind: .file,
            receivedAt: TestClock.now,
            mode: .organize,
            userContext: ["captureSessionID": sessionID.uuidString]
        )
        let setup = PipelineSetup(mode: .indexOnly, request: request)

        _ = await setup.pipeline.process(setup.request, configuration: setup.configuration)

        XCTAssertEqual(setup.knowledge.captureEvents.first?.sessionID, sessionID)
    }

    func testSourceAwareRequestTagsLibraryItemAndCaptureEvent() async throws {
        let sourceID = UUID(uuidString: "50000000-0000-0000-0000-000000000004")!
        let request = OrganizationRequest(
            source: .manualImport,
            sourceID: sourceID,
            itemURL: URL(fileURLWithPath: "/tmp/report.pdf"),
            itemKind: .file,
            receivedAt: TestClock.now,
            mode: .indexOnly,
            userContext: [
                "sourceKind": SourceKind.manualImport.rawValue,
                "captureSource": CaptureSource.manualImport.rawValue
            ]
        )
        let setup = PipelineSetup(mode: .indexOnly, request: request)

        let result = await setup.pipeline.process(setup.request, configuration: setup.configuration)

        XCTAssertEqual(result.status, .indexedOnly)
        XCTAssertEqual(setup.knowledge.items[setup.profile.id]?.sourceID, sourceID)
        XCTAssertEqual(setup.knowledge.captureEvents.first?.sourceID, sourceID)
        XCTAssertTrue(setup.search.items.first?.tags.contains("source:\(sourceID.uuidString)") == true)
        XCTAssertTrue(setup.search.items.first?.tags.contains(SourceKind.manualImport.rawValue) == true)
        XCTAssertTrue(setup.search.items.first?.tags.contains(CaptureSource.manualImport.rawValue) == true)
    }

    func testPipelinePassesSourceFactsIntoRuleEvaluation() async throws {
        let sourceID = UUID(uuidString: "50000000-0000-0000-0000-000000000005")!
        let request = OrganizationRequest(
            source: .watchedFolder,
            sourceID: sourceID,
            itemURL: URL(fileURLWithPath: "/tmp/report.pdf"),
            itemKind: .file,
            receivedAt: TestClock.now,
            mode: .organize,
            userContext: [
                "sourceKind": SourceKind.watchedFolder.rawValue,
                "sourceName": "Downloads"
            ]
        )
        let setup = PipelineSetup(mode: .organize, request: request)

        _ = await setup.pipeline.process(setup.request, configuration: setup.configuration)

        XCTAssertEqual(setup.engine.lastContext?.sourceID, sourceID)
        XCTAssertEqual(setup.engine.lastContext?.sourceFacts["sourceName"], "Downloads")
        XCTAssertEqual(setup.engine.lastItem?.metadata["sourceID"], sourceID.uuidString)
        XCTAssertEqual(setup.engine.lastItem?.metadata["sourceKind"], SourceKind.watchedFolder.rawValue)
    }

    func testMetadataExtractionFailureDoesNotFailCapture() async throws {
        let setup = PipelineSetup(
            mode: .indexOnly,
            metadataExtractionService: ThrowingMetadataExtractionService()
        )

        let result = await setup.pipeline.process(setup.request, configuration: setup.configuration)

        XCTAssertEqual(result.status, .indexedOnly)
        XCTAssertEqual(
            setup.knowledge.metadataSnapshots[setup.profile.id]?["metadata.extraction.error"],
            "metadata unavailable"
        )
    }
}

private enum PipelineTestError: Error, LocalizedError {
    case executionFailed

    var errorDescription: String? {
        "Execution failed"
    }
}

private final class PipelineSetup {
    let request: OrganizationRequest
    let profile: ItemProfile
    let plan: OperationPlan
    let stabilizer: MockItemStabilizer
    let inspector: MockItemInspector
    let engine: MockWorkflowEngine
    let executor: MockOperationExecutor
    let search: MockSearchService
    let knowledge: MockKnowledgeStore
    let activity: MockActivityLog
    let pipeline: DefaultOrganizationPipeline
    let configuration: OrganizationPipelineConfiguration

    init(
        mode: OrganizationMode = .organize,
        request: OrganizationRequest? = nil,
        profile: ItemProfile? = nil,
        decision: RouteDecision? = nil,
        plan providedPlan: OperationPlan? = nil,
        metadataExtractionService: MetadataExtractionService? = nil
    ) {
        let baseRequest = request ?? ItemFixtures.request(mode: mode)
        self.request = OrganizationRequest(
            id: baseRequest.id,
            source: baseRequest.source,
            sourceID: baseRequest.sourceID,
            itemURL: baseRequest.itemURL,
            itemKind: baseRequest.itemKind,
            receivedAt: baseRequest.receivedAt,
            mode: mode,
            userContext: baseRequest.userContext
        )
        self.profile = profile ?? ItemFixtures.fileProfile(url: self.request.itemURL)
        let operation = Operation(
            kind: .move,
            itemURL: self.profile.url,
            destinationURL: URL(fileURLWithPath: "/tmp/Bipbox/\(self.profile.displayName)"),
            reversible: true
        )
        self.plan = providedPlan ?? OperationPlan(
            operations: [operation],
            expectedResultURL: operation.destinationURL,
            reversible: true,
            previewText: "Move \(self.profile.displayName)."
        )

        stabilizer = MockItemStabilizer()
        inspector = MockItemInspector(profile: self.profile)
        executor = MockOperationExecutor()
        search = MockSearchService()
        knowledge = MockKnowledgeStore()
        activity = MockActivityLog()
        let workflow = WorkflowFixtures.folderWorkflow()
        engine = MockWorkflowEngine(
            decision: decision ?? RouteDecision(
                confidence: 1,
                destinationURL: operation.destinationURL,
                actions: [
                    ActionDescriptor(
                        operationKind: .move,
                        parameters: ["destination": "/tmp/Bipbox/"]
                    )
                ],
                reason: "Matched test rule.",
                reviewRequirement: .notRequired
            )
        )
        let planner = MockOperationPlanner(plan: self.plan)
        pipeline = DefaultOrganizationPipeline(
            stabilizer: stabilizer,
            inspector: inspector,
            workflowEngine: engine,
            planner: planner,
            executor: executor,
            searchService: search,
            knowledgeStore: knowledge,
            knowledgeGraphService: DefaultKnowledgeGraphService(store: knowledge),
            metadataExtractionService: metadataExtractionService,
            activityLog: activity
        )
        configuration = OrganizationPipelineConfiguration(
            workflow: workflow,
            planningContext: PlanningContext(now: TestClock.now),
            executionContext: ExecutionContext(actor: "test"),
            now: TestClock.now
        )
    }
}

private struct ThrowingMetadataExtractionService: MetadataExtractionService {
    func extractMetadata(for item: ItemProfile) async throws -> MetadataExtractionResult {
        throw MetadataExtractionFixtureError.unavailable
    }
}

private enum MetadataExtractionFixtureError: Error, LocalizedError {
    case unavailable

    var errorDescription: String? {
        "metadata unavailable"
    }
}
