import BipboxCore
import BipboxPersistence
import XCTest

final class JSONLinesActivityLogTests: XCTestCase {
    func testAppendsAndQueriesRecentEvents() async throws {
        let directory = try TemporaryDirectory(name: "activity-recent-\(UUID().uuidString)")
        let log = try JSONLinesActivityLog(directoryURL: directory.url)
        let first = activityEvent(
            kind: .requestReceived,
            message: "First",
            occurredAt: TestClock.now.addingTimeInterval(-10)
        )
        let second = activityEvent(
            kind: .executed,
            message: "Second",
            occurredAt: TestClock.now
        )

        try await log.append(first)
        try await log.append(second)

        let recent = try await log.recent(limit: 1)

        XCTAssertEqual(recent, [second])
    }

    func testQueriesEventsForOneItemInChronologicalOrder() async throws {
        let directory = try TemporaryDirectory(name: "activity-item-\(UUID().uuidString)")
        let log = try JSONLinesActivityLog(directoryURL: directory.url)
        let itemID = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
        let otherItemID = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
        let inspected = activityEvent(
            kind: .inspected,
            itemID: itemID,
            message: "Inspected",
            occurredAt: TestClock.now.addingTimeInterval(-5)
        )
        let executed = activityEvent(
            kind: .executed,
            itemID: itemID,
            message: "Executed",
            occurredAt: TestClock.now
        )
        let other = activityEvent(
            kind: .failed,
            itemID: otherItemID,
            message: "Other",
            occurredAt: TestClock.now.addingTimeInterval(5)
        )

        try await log.append(executed)
        try await log.append(other)
        try await log.append(inspected)

        let events = try await log.events(forItemID: itemID)

        XCTAssertEqual(events, [inspected, executed])
    }

    func testPreservesUndoMetadata() async throws {
        let directory = try TemporaryDirectory(name: "activity-undo-\(UUID().uuidString)")
        let log = try JSONLinesActivityLog(directoryURL: directory.url)
        let undo = Operation(
            kind: .move,
            itemURL: URL(fileURLWithPath: "/tmp/Bipbox/report.pdf"),
            destinationURL: URL(fileURLWithPath: "/tmp/report.pdf"),
            reversible: true
        )
        let event = activityEvent(
            kind: .executed,
            message: "Moved file",
            occurredAt: TestClock.now,
            undoOperation: undo
        )

        try await log.append(event)

        let recent = try await log.recent(limit: 10)

        XCTAssertEqual(recent.first?.undoOperation, undo)
    }

    func testEventsAreDurableAcrossLogReopen() async throws {
        let directory = try TemporaryDirectory(name: "activity-durable-\(UUID().uuidString)")
        let firstLog = try JSONLinesActivityLog(directoryURL: directory.url)
        let event = activityEvent(kind: .planned, message: "Planned", occurredAt: TestClock.now)

        try await firstLog.append(event)

        let reopenedLog = try JSONLinesActivityLog(directoryURL: directory.url)
        let recent = try await reopenedLog.recent(limit: 10)

        XCTAssertEqual(recent, [event])
    }

    func testInvalidRecentLimitFails() async throws {
        let directory = try TemporaryDirectory(name: "activity-limit-\(UUID().uuidString)")
        let log = try JSONLinesActivityLog(directoryURL: directory.url)

        do {
            _ = try await log.recent(limit: 0)
            XCTFail("Expected invalid limit failure.")
        } catch let error as ActivityLogError {
            XCTAssertEqual(error, .invalidLimit(0))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSchemaRepresentsFolderOperation() async throws {
        let directory = try TemporaryDirectory(name: "activity-folder-\(UUID().uuidString)")
        let log = try JSONLinesActivityLog(directoryURL: directory.url)
        let folderID = UUID(uuidString: "20000000-0000-0000-0000-000000000003")!
        let undo = Operation(
            kind: .move,
            itemURL: URL(fileURLWithPath: "/tmp/Bipbox/Project"),
            destinationURL: URL(fileURLWithPath: "/tmp/Project"),
            reversible: true
        )
        let event = activityEvent(
            kind: .executed,
            itemID: folderID,
            message: "Moved folder",
            occurredAt: TestClock.now,
            undoOperation: undo
        )

        try await log.append(event)
        let events = try await log.events(forItemID: folderID)

        XCTAssertEqual(events.first?.message, "Moved folder")
        XCTAssertEqual(events.first?.undoOperation?.itemURL.path, "/tmp/Bipbox/Project")
    }
}

private func activityEvent(
    kind: ActivityEventKind,
    itemID: UUID? = UUID(uuidString: "20000000-0000-0000-0000-000000000010")!,
    requestID: UUID? = UUID(uuidString: "20000000-0000-0000-0000-000000000011")!,
    planID: UUID? = UUID(uuidString: "20000000-0000-0000-0000-000000000012")!,
    message: String,
    occurredAt: Date,
    undoOperation: BipboxCore.Operation? = nil
) -> ActivityEvent {
    ActivityEvent(
        id: UUID(),
        kind: kind,
        itemID: itemID,
        requestID: requestID,
        planID: planID,
        message: message,
        occurredAt: occurredAt,
        undoOperation: undoOperation
    )
}
