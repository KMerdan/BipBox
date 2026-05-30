import BipboxCore
import XCTest

final class DefaultOperationPlannerTests: XCTestCase {
    func testCreatesMovePlanForFile() async throws {
        let item = ItemFixtures.fileProfile(url: URL(fileURLWithPath: "/tmp/report.pdf"))
        let action = ActionDescriptor(
            operationKind: .move,
            parameters: ["destination": "/tmp/Bipbox/PDFs/"]
        )
        let decision = RouteDecision(
            confidence: 1,
            destinationURL: URL(fileURLWithPath: "/tmp/Bipbox/PDFs"),
            actions: [action],
            reason: "Matched PDF rule.",
            reviewRequirement: .notRequired
        )

        let plan = try await DefaultOperationPlanner(conflictChecker: StubConflictChecker()).plan(
            decision: decision,
            item: item,
            context: PlanningContext(now: TestClock.now)
        )

        XCTAssertEqual(plan.operations.count, 1)
        XCTAssertEqual(plan.operations.first?.kind, .move)
        XCTAssertEqual(plan.operations.first?.itemURL, item.url)
        XCTAssertEqual(plan.operations.first?.destinationURL?.path, "/tmp/Bipbox/PDFs/report.pdf")
        XCTAssertEqual(plan.expectedResultURL?.path, "/tmp/Bipbox/PDFs/report.pdf")
        XCTAssertTrue(plan.reversible)
        XCTAssertTrue(plan.conflicts.isEmpty)
    }

    func testCreatesFolderMovePlanAsSingleItem() async throws {
        let item = ItemFixtures.folderProfile(url: URL(fileURLWithPath: "/tmp/Project"))
        let action = ActionDescriptor(
            operationKind: .move,
            parameters: ["destination": "/tmp/Bipbox/Projects/"],
            recursiveFolderProcessing: false
        )
        let decision = RouteDecision(
            confidence: 1,
            actions: [action],
            reason: "Matched folder rule.",
            reviewRequirement: .notRequired
        )

        let plan = try await DefaultOperationPlanner(conflictChecker: StubConflictChecker()).plan(
            decision: decision,
            item: item,
            context: PlanningContext(now: TestClock.now)
        )

        XCTAssertEqual(plan.operations.count, 1)
        XCTAssertEqual(plan.operations.first?.kind, .move)
        XCTAssertEqual(plan.operations.first?.itemURL.path, "/tmp/Project")
        XCTAssertEqual(plan.operations.first?.destinationURL?.path, "/tmp/Bipbox/Projects/Project")
        XCTAssertEqual(item.folderChildSummary?.recursiveInspectionRequested, false)
    }

    func testDetectsDestinationConflict() async throws {
        let item = ItemFixtures.fileProfile(url: URL(fileURLWithPath: "/tmp/report.pdf"))
        let action = ActionDescriptor(
            operationKind: .copy,
            parameters: ["destination": "/tmp/Bipbox/PDFs/"]
        )
        let conflictPath = "/tmp/Bipbox/PDFs/report.pdf"
        let planner = DefaultOperationPlanner(
            conflictChecker: StubConflictChecker(existingPaths: [conflictPath])
        )
        let decision = RouteDecision(
            confidence: 1,
            actions: [action],
            reason: "Copy PDF.",
            reviewRequirement: .notRequired
        )

        let plan = try await planner.plan(
            decision: decision,
            item: item,
            context: PlanningContext(now: TestClock.now)
        )

        XCTAssertEqual(plan.conflicts, ["Destination already exists: \(conflictPath)"])
        XCTAssertEqual(plan.operations.map(\.kind), [.copy, .markNeedsReview])
        XCTAssertTrue(plan.previewText.contains("Review required"))
    }

    func testMarksPlanIrreversibleWhenOperationIsIrreversible() async throws {
        let item = ItemFixtures.fileProfile()
        let action = ActionDescriptor(operationKind: .open)
        let decision = RouteDecision(
            confidence: 1,
            actions: [action],
            reason: "Open item.",
            reviewRequirement: .notRequired
        )

        let plan = try await DefaultOperationPlanner(conflictChecker: StubConflictChecker()).plan(
            decision: decision,
            item: item,
            context: PlanningContext(now: TestClock.now)
        )

        XCTAssertEqual(plan.operations.first?.kind, .open)
        XCTAssertFalse(plan.operations.first?.reversible ?? true)
        XCTAssertEqual(plan.operations.map(\.kind), [.open, .markNeedsReview])
        XCTAssertEqual(plan.conflicts, ["Review required for open."])
        XCTAssertFalse(plan.reversible)
    }

    func testMissingFilesystemDestinationIsStagedForReview() async throws {
        let item = ItemFixtures.fileProfile()
        let action = ActionDescriptor(operationKind: .move)
        let decision = RouteDecision(
            confidence: 1,
            actions: [action],
            reason: "Bad rule.",
            reviewRequirement: .notRequired
        )

        let plan = try await DefaultOperationPlanner(conflictChecker: StubConflictChecker()).plan(
            decision: decision,
            item: item,
            context: PlanningContext(now: TestClock.now)
        )

        XCTAssertEqual(plan.operations.map(\.kind), [.move, .markNeedsReview])
        XCTAssertEqual(plan.conflicts, ["destination is required for move."])
        XCTAssertTrue(plan.previewText.contains("Review required"))
    }

    func testRequiredReviewAddsReviewOperation() async throws {
        let item = ItemFixtures.fileProfile()
        let action = ActionDescriptor(
            operationKind: .move,
            parameters: ["destination": "/tmp/Bipbox/PDFs/"],
            requiresReview: true
        )
        let decision = RouteDecision(
            confidence: 0.4,
            actions: [action],
            reason: "Low confidence.",
            reviewRequirement: .required
        )

        let plan = try await DefaultOperationPlanner(conflictChecker: StubConflictChecker()).plan(
            decision: decision,
            item: item,
            context: PlanningContext(now: TestClock.now)
        )

        XCTAssertEqual(plan.operations.map(\.kind), [.move, .markNeedsReview])
        XCTAssertTrue(plan.reversible)
        XCTAssertTrue(plan.previewText.contains("Mark report.pdf as needs review"))
    }

    func testReviewDecisionWithoutActionsCreatesReviewPlan() async throws {
        let item = ItemFixtures.fileProfile()
        let decision = RouteDecision(
            confidence: 0,
            reason: "No route matched.",
            reviewRequirement: .required
        )

        let plan = try await DefaultOperationPlanner(conflictChecker: StubConflictChecker()).plan(
            decision: decision,
            item: item,
            context: PlanningContext(now: TestClock.now)
        )

        XCTAssertEqual(plan.operations.map(\.kind), [.markNeedsReview])
        XCTAssertEqual(plan.operations.first?.value, "No route matched.")
    }

    func testGraphOnlyActionCreatesGraphOperationWithoutReviewFallback() async throws {
        let item = ItemFixtures.fileProfile()
        let decision = RouteDecision(
            confidence: 1,
            graphActions: [
                GraphActionDescriptor(
                    kind: .addToCollection,
                    parameters: ["collectionName": "Research"]
                )
            ],
            reason: "Add to collection.",
            reviewRequirement: .notRequired
        )

        let plan = try await DefaultOperationPlanner(conflictChecker: StubConflictChecker()).plan(
            decision: decision,
            item: item,
            context: PlanningContext(now: TestClock.now)
        )

        XCTAssertEqual(plan.operations, [])
        XCTAssertEqual(plan.graphOperations.map(\.kind), [.addToCollection])
        XCTAssertEqual(plan.graphOperations.first?.parameters["collectionName"], "Research")
        XCTAssertNil(plan.expectedResultURL)
        XCTAssertTrue(plan.previewText.contains("Add report.pdf to collection Research"))
    }

    func testGraphOnlyContextActionsAreValidSuccessfulOutcomes() async throws {
        let item = ItemFixtures.fileProfile()
        let decision = RouteDecision(
            confidence: 1,
            graphActions: [
                GraphActionDescriptor(kind: .addPerson, parameters: ["person": "Ada"]),
                GraphActionDescriptor(kind: .addProject, parameters: ["project": "Launch"])
            ],
            reason: "Enrich memory graph.",
            reviewRequirement: .notRequired
        )

        let plan = try await DefaultOperationPlanner(conflictChecker: StubConflictChecker()).plan(
            decision: decision,
            item: item,
            context: PlanningContext(now: TestClock.now)
        )

        XCTAssertEqual(plan.operations, [])
        XCTAssertEqual(plan.graphOperations.map(\.kind), [.addPerson, .addProject])
        XCTAssertTrue(plan.previewText.contains("Add person Ada"))
        XCTAssertTrue(plan.previewText.contains("Add project Launch"))
        XCTAssertTrue(plan.reversible)
    }

    func testRequiredReviewCanApplyToFilesystemWhileGraphOperationIsPreviewedSeparately() async throws {
        let item = ItemFixtures.fileProfile()
        let decision = RouteDecision(
            confidence: 0.5,
            actions: [
                ActionDescriptor(
                    operationKind: .move,
                    parameters: ["destination": "/tmp/Bipbox/PDFs/"],
                    requiresReview: true
                )
            ],
            graphActions: [
                GraphActionDescriptor(kind: .addTopic, parameters: ["topic": "finance"])
            ],
            reason: "Risky move.",
            reviewRequirement: .required
        )

        let plan = try await DefaultOperationPlanner(conflictChecker: StubConflictChecker()).plan(
            decision: decision,
            item: item,
            context: PlanningContext(now: TestClock.now)
        )

        XCTAssertEqual(plan.operations.map(\.kind), [.move, .markNeedsReview])
        XCTAssertEqual(plan.graphOperations.map(\.kind), [.addTopic])
        XCTAssertTrue(plan.previewText.contains("Add topic finance"))
    }

    func testPlanRoundTripsThroughJSON() async throws {
        let item = ItemFixtures.fileProfile()
        let decision = RouteDecision(
            confidence: 1,
            actions: [
                ActionDescriptor(operationKind: .indexInPlace)
            ],
            reason: "Index only.",
            reviewRequirement: .notRequired
        )
        let plan = try await DefaultOperationPlanner(conflictChecker: StubConflictChecker()).plan(
            decision: decision,
            item: item,
            context: PlanningContext(now: TestClock.now)
        )

        let data = try JSONEncoder().encode(plan)
        let decoded = try JSONDecoder().decode(OperationPlan.self, from: data)

        XCTAssertEqual(decoded, plan)
    }
}

private struct StubConflictChecker: PathConflictChecking {
    var existingPaths: Set<String> = []

    func itemExists(at url: URL) -> Bool {
        existingPaths.contains(url.path)
    }
}
