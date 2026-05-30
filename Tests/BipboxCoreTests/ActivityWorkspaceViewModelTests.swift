import BipboxCore
import BipboxWorkspaceUI
import XCTest

@MainActor
final class ActivityWorkspaceViewModelTests: XCTestCase {
    func testLoadsAndRendersRecentEvents() async {
        let event = activityEvent(kind: .executed, message: "Moved report.pdf.")
        let viewModel = ActivityWorkspaceViewModel(
            activityLog: TestActivityLog(events: [event]),
            undoExecutor: CapturingActivityUndoExecutor()
        )

        await viewModel.loadRecent()

        XCTAssertEqual(viewModel.events, [event])
        XCTAssertEqual(viewModel.selectedEventID, event.id)
        XCTAssertEqual(viewModel.renderedEvents.first?.title, "Executed")
        XCTAssertEqual(viewModel.renderedEvents.first?.detail, "Moved report.pdf.")
    }

    func testReversibleVsIrreversibleEvents() async {
        let reversible = activityEvent(
            kind: .executed,
            message: "Moved folder.",
            undoOperation: undoOperation(kind: .move, itemPath: "/Library/Project")
        )
        let irreversible = activityEvent(kind: .indexed, message: "Indexed report.pdf.")
        let viewModel = ActivityWorkspaceViewModel(
            activityLog: TestActivityLog(events: [reversible, irreversible]),
            undoExecutor: CapturingActivityUndoExecutor()
        )

        await viewModel.loadRecent()

        XCTAssertEqual(viewModel.renderedEvents.map(\.isReversible), [true, false])
        XCTAssertTrue(viewModel.canUndoSelectedEvent)

        viewModel.select(id: irreversible.id)
        XCTAssertFalse(viewModel.canUndoSelectedEvent)
    }

    func testUndoActionDispatchesSelectedUndoOperation() async {
        let operation = undoOperation(kind: .move, itemPath: "/Library/report.pdf")
        let event = activityEvent(kind: .executed, message: "Moved report.pdf.", undoOperation: operation)
        let undoExecutor = CapturingActivityUndoExecutor()
        let viewModel = ActivityWorkspaceViewModel(
            activityLog: TestActivityLog(events: [event]),
            undoExecutor: undoExecutor
        )

        await viewModel.loadRecent()
        await viewModel.undoSelected()

        XCTAssertEqual(undoExecutor.operations, [operation])
        XCTAssertEqual(viewModel.undoMessage, "Undo completed with 1 operation(s).")
        XCTAssertNil(viewModel.errorMessage)
    }

    func testUndoErrorIsSurfaced() async {
        let operation = undoOperation(kind: .move, itemPath: "/Library/report.pdf")
        let event = activityEvent(kind: .executed, message: "Moved report.pdf.", undoOperation: operation)
        let viewModel = ActivityWorkspaceViewModel(
            activityLog: TestActivityLog(events: [event]),
            undoExecutor: CapturingActivityUndoExecutor(error: ActivityViewModelTestError.undoFailed)
        )

        await viewModel.loadRecent()
        await viewModel.undoSelected()

        XCTAssertEqual(viewModel.errorMessage, ActivityViewModelTestError.undoFailed.localizedDescription)
        XCTAssertNil(viewModel.undoMessage)
    }

    func testFolderMoveActivityRendersFolderOperation() async {
        let operation = undoOperation(kind: .move, itemPath: "/Library/Project")
        let event = activityEvent(kind: .executed, message: "Moved Project folder.", undoOperation: operation)
        let viewModel = ActivityWorkspaceViewModel(
            activityLog: TestActivityLog(events: [event]),
            undoExecutor: CapturingActivityUndoExecutor()
        )

        await viewModel.loadRecent()

        XCTAssertEqual(viewModel.renderedEvents.first?.operationKind, .move)
        XCTAssertEqual(viewModel.renderedEvents.first?.itemPath, "/Library/Project")
        XCTAssertEqual(viewModel.renderedEvents.first?.detail, "Moved Project folder.")
    }

    func testFailedOperationsRemainVisible() async {
        let failed = activityEvent(kind: .failed, message: "Destination already exists.")
        let viewModel = ActivityWorkspaceViewModel(
            activityLog: TestActivityLog(events: [failed]),
            undoExecutor: CapturingActivityUndoExecutor()
        )

        await viewModel.loadRecent()

        XCTAssertEqual(viewModel.renderedEvents.first?.title, "Failed")
        XCTAssertEqual(viewModel.renderedEvents.first?.isFailure, true)
        XCTAssertEqual(viewModel.renderedEvents.first?.detail, "Destination already exists.")
    }

    func testNorthStarAuditKindsRenderWithoutUndo() async {
        let sourceID = UUID(uuidString: "90000000-0000-0000-0000-000000000001")!
        let itemID = UUID(uuidString: "90000000-0000-0000-0000-000000000002")!
        let events = [
            activityEvent(kind: .captured, message: "Captured from Downloads.", itemID: itemID, sourceID: sourceID),
            activityEvent(kind: .indexed, message: "Indexed report.pdf.", itemID: itemID, sourceID: sourceID),
            activityEvent(kind: .relationshipRecorded, message: "Linked report to Launch.", itemID: itemID),
            activityEvent(kind: .ruleMatched, message: "Matched PDF rule.", itemID: itemID),
            activityEvent(kind: .reviewDecision, message: "Kept for later.", itemID: itemID),
            activityEvent(kind: .toolCall, message: "AI tool searched library.", itemID: itemID),
            activityEvent(kind: .error, message: "Permission denied.", itemID: itemID)
        ]
        let viewModel = ActivityWorkspaceViewModel(
            activityLog: TestActivityLog(events: events),
            undoExecutor: CapturingActivityUndoExecutor()
        )

        await viewModel.loadRecent()

        XCTAssertEqual(
            viewModel.renderedEvents.map(\.auditKind),
            [.capture, .index, .relationship, .rule, .decision, .tool, .error]
        )
        XCTAssertEqual(viewModel.renderedEvents.map(\.isReversible), Array(repeating: false, count: events.count))
        XCTAssertEqual(viewModel.renderedEvents.first?.contextRows.first { $0.label == "Source" }?.value, sourceID.uuidString)
    }

    func testFiltersActivityByKindItemAndSource() async {
        let sourceID = UUID(uuidString: "90000000-0000-0000-0000-000000000010")!
        let matchingItemID = UUID(uuidString: "90000000-0000-0000-0000-000000000011")!
        let matching = activityEvent(
            kind: .captured,
            message: "Captured contract.pdf.",
            itemID: matchingItemID,
            sourceID: sourceID,
            metadata: ["sourceName": "Downloads", "itemName": "contract.pdf"]
        )
        let other = activityEvent(kind: .ruleMatched, message: "Matched screenshots.", metadata: ["sourceName": "Desktop"])
        let viewModel = ActivityWorkspaceViewModel(
            activityLog: TestActivityLog(events: [matching, other]),
            undoExecutor: CapturingActivityUndoExecutor()
        )

        await viewModel.loadRecent()
        viewModel.filter = .capture
        viewModel.itemFilterText = "contract"
        viewModel.sourceFilterText = "Downloads"

        XCTAssertEqual(viewModel.renderedEvents.map(\.id), [matching.id])
    }
}

private enum ActivityViewModelTestError: Error {
    case undoFailed
}

private actor TestActivityLog: ActivityLog {
    let events: [ActivityEvent]

    init(events: [ActivityEvent]) {
        self.events = events
    }

    func append(_ event: ActivityEvent) async throws {}

    func recent(limit: Int) async throws -> [ActivityEvent] {
        Array(events.prefix(limit))
    }

    func events(forItemID itemID: UUID) async throws -> [ActivityEvent] {
        events.filter { $0.itemID == itemID }
    }
}

@MainActor
private final class CapturingActivityUndoExecutor: ActivityUndoExecuting {
    private let error: Error?
    private(set) var operations: [BipboxCore.Operation] = []

    init(error: Error? = nil) {
        self.error = error
    }

    func executeUndo(_ operation: BipboxCore.Operation) async throws -> ExecutionResult {
        if let error {
            throw error
        }
        operations.append(operation)
        return ExecutionResult(
            planID: UUID(),
            operationResults: [
                OperationExecutionResult(operationID: operation.id, status: .completed, resultingURL: operation.destinationURL)
            ]
        )
    }
}

private func activityEvent(
    kind: ActivityEventKind,
    message: String,
    itemID: UUID? = nil,
    sourceID: UUID? = nil,
    metadata: [String: String] = [:],
    undoOperation: BipboxCore.Operation? = nil
) -> ActivityEvent {
    ActivityEvent(
        kind: kind,
        itemID: itemID,
        sourceID: sourceID,
        message: message,
        occurredAt: TestClock.now,
        undoOperation: undoOperation,
        metadata: metadata
    )
}

private func undoOperation(kind: OperationKind, itemPath: String) -> BipboxCore.Operation {
    BipboxCore.Operation(
        kind: kind,
        itemURL: URL(fileURLWithPath: itemPath),
        destinationURL: URL(fileURLWithPath: "/Downloads/\(URL(fileURLWithPath: itemPath).lastPathComponent)"),
        reversible: true
    )
}
