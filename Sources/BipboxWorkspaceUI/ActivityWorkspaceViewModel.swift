import BipboxCore
import Foundation

public enum ActivityAuditKind: String, CaseIterable, Identifiable, Sendable {
    case all
    case capture
    case index
    case relationship
    case rule
    case decision
    case filesystem
    case error
    case tool

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: "All"
        case .capture: "Capture"
        case .index: "Index"
        case .relationship: "Relations"
        case .rule: "Rules"
        case .decision: "Decisions"
        case .filesystem: "Files"
        case .error: "Errors"
        case .tool: "Tools"
        }
    }
}

public struct ActivityContextRow: Equatable, Sendable {
    public var label: String
    public var value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

public struct ActivityEventViewData: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var detail: String
    public var occurredAt: Date
    public var auditKind: ActivityAuditKind
    public var isReversible: Bool
    public var isFailure: Bool
    public var operationKind: OperationKind?
    public var itemPath: String?
    public var contextRows: [ActivityContextRow]

    public init(event: ActivityEvent) {
        id = event.id
        title = event.kind.title
        detail = event.message
        occurredAt = event.occurredAt
        auditKind = event.kind.auditKind
        isReversible = event.undoOperation != nil
        isFailure = event.kind.auditKind == .error
        operationKind = event.undoOperation?.kind
        itemPath = event.undoOperation?.itemURL.path
        contextRows = event.contextRows
    }
}

@MainActor
public protocol ActivityUndoExecuting: AnyObject {
    func executeUndo(_ operation: BipboxCore.Operation) async throws -> ExecutionResult
}

@MainActor
public final class ActivityWorkspaceViewModel: ObservableObject {
    @Published public private(set) var events: [ActivityEvent]
    @Published public private(set) var selectedEventID: UUID?
    @Published public private(set) var isLoading: Bool
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var undoMessage: String?
    @Published public var filter: ActivityAuditKind
    @Published public var itemFilterText: String
    @Published public var sourceFilterText: String

    private let activityLog: ActivityLog
    private let undoExecutor: ActivityUndoExecuting
    private let limit: Int

    public init(
        activityLog: ActivityLog = FixtureActivityLog(),
        undoExecutor: ActivityUndoExecuting = FixtureActivityUndoExecutor(),
        limit: Int = 50
    ) {
        self.activityLog = activityLog
        self.undoExecutor = undoExecutor
        self.limit = limit
        events = []
        selectedEventID = nil
        isLoading = false
        errorMessage = nil
        undoMessage = nil
        filter = .all
        itemFilterText = ""
        sourceFilterText = ""
    }

    public var renderedEvents: [ActivityEventViewData] {
        filteredEvents.map(ActivityEventViewData.init(event:))
    }

    public var filteredEvents: [ActivityEvent] {
        events.filter { event in
            let kindMatches = filter == .all || event.kind.auditKind == filter
            let itemMatches = filterText(itemFilterText, matches: event.itemFilterCandidates)
            let sourceMatches = filterText(sourceFilterText, matches: event.sourceFilterCandidates)
            return kindMatches && itemMatches && sourceMatches
        }
    }

    public var selectedEvent: ActivityEvent? {
        guard let selectedEventID else {
            return nil
        }
        return events.first { $0.id == selectedEventID }
    }

    public var selectedEventViewData: ActivityEventViewData? {
        selectedEvent.map(ActivityEventViewData.init(event:))
    }

    public var canUndoSelectedEvent: Bool {
        selectedEvent?.undoOperation != nil
    }

    public func loadRecent() async {
        isLoading = true
        errorMessage = nil

        do {
            events = try await activityLog.recent(limit: limit)
            selectedEventID = filteredEvents.first?.id ?? events.first?.id
        } catch {
            events = []
            selectedEventID = nil
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    public func select(id: UUID?) {
        selectedEventID = id
    }

    public func undoSelected() async {
        guard let operation = selectedEvent?.undoOperation else {
            return
        }

        errorMessage = nil
        undoMessage = nil

        do {
            let result = try await undoExecutor.executeUndo(operation)
            undoMessage = "Undo completed with \(result.operationResults.count) operation(s)."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

public actor FixtureActivityLog: ActivityLog {
    public init() {}

    public func append(_ event: ActivityEvent) async throws {}

    public func recent(limit: Int) async throws -> [ActivityEvent] {
        Array(Self.events.prefix(limit))
    }

    public func events(forItemID itemID: UUID) async throws -> [ActivityEvent] {
        Self.events.filter { $0.itemID == itemID }
    }

    private static let events: [ActivityEvent] = [
        ActivityEvent(
            kind: .executed,
            message: "Moved Project Folder to /Users/example/Bipbox/Projects.",
            occurredAt: Date(timeIntervalSince1970: 1_800_000_300),
            undoOperation: BipboxCore.Operation(
                kind: .move,
                itemURL: URL(fileURLWithPath: "/Users/example/Bipbox/Projects/Project Folder", isDirectory: true),
                destinationURL: URL(fileURLWithPath: "/Users/example/Downloads/Project Folder", isDirectory: true),
                reversible: true
            )
        ),
        ActivityEvent(
            kind: .failed,
            message: "Could not move report.pdf because the destination already exists.",
            occurredAt: Date(timeIntervalSince1970: 1_800_000_200)
        )
    ]
}

@MainActor
public final class FixtureActivityUndoExecutor: ActivityUndoExecuting {
    public init() {}

    public func executeUndo(_ operation: BipboxCore.Operation) async throws -> ExecutionResult {
        ExecutionResult(
            planID: UUID(),
            operationResults: [
                OperationExecutionResult(operationID: operation.id, status: .completed, resultingURL: operation.destinationURL)
            ]
        )
    }
}

private extension ActivityEventKind {
    var title: String {
        switch self {
        case .requestReceived: "Request Received"
        case .inspected: "Inspected"
        case .routed: "Routed"
        case .planned: "Planned"
        case .executed: "Executed"
        case .indexed: "Indexed"
        case .failed: "Failed"
        case .undoExecuted: "Undo Executed"
        case .captured: "Captured"
        case .relationshipRecorded: "Relationship Recorded"
        case .ruleMatched: "Rule Matched"
        case .reviewDecision: "Review Decision"
        case .filesystemOperation: "Filesystem Operation"
        case .error: "Error"
        case .toolCall: "Tool Call"
        }
    }

    var auditKind: ActivityAuditKind {
        switch self {
        case .requestReceived, .inspected, .captured:
            .capture
        case .indexed:
            .index
        case .relationshipRecorded:
            .relationship
        case .routed, .planned, .ruleMatched:
            .rule
        case .reviewDecision:
            .decision
        case .executed, .undoExecuted, .filesystemOperation:
            .filesystem
        case .failed, .error:
            .error
        case .toolCall:
            .tool
        }
    }
}

private extension ActivityEvent {
    var contextRows: [ActivityContextRow] {
        var rows: [ActivityContextRow] = []
        if let itemID {
            rows.append(ActivityContextRow(label: "Item", value: itemID.uuidString))
        }
        if let sourceID {
            rows.append(ActivityContextRow(label: "Source", value: sourceID.uuidString))
        }
        if let requestID {
            rows.append(ActivityContextRow(label: "Request", value: requestID.uuidString))
        }
        if let planID {
            rows.append(ActivityContextRow(label: "Plan", value: planID.uuidString))
        }
        rows.append(contentsOf: metadata.sorted { $0.key < $1.key }.map {
            ActivityContextRow(label: $0.key, value: $0.value)
        })
        return rows
    }

    var itemFilterCandidates: [String] {
        [itemID?.uuidString, undoOperation?.itemURL.path, message, metadata["itemPath"], metadata["itemName"]].compactMap { $0 }
    }

    var sourceFilterCandidates: [String] {
        [sourceID?.uuidString, metadata["sourceID"], metadata["sourceName"], metadata["sourcePath"], message].compactMap { $0 }
    }
}

private func filterText(_ text: String, matches candidates: [String]) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return true
    }
    return candidates.contains { $0.localizedCaseInsensitiveContains(trimmed) }
}
