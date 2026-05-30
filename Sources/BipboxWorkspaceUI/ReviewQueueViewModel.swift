import BipboxCore
import Foundation

public enum ReviewQueueItemStatus: String, Equatable, Sendable {
    case pending
    case approved
    case rejected
    case inbox
    case failed
}

public enum ReviewQueueFilter: String, CaseIterable, Identifiable, Sendable {
    case needsDecision
    case keptForLater
    case failed
    case permissionNeeded
    case rejected
    case all

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .needsDecision: "Needs Decision"
        case .keptForLater: "Kept"
        case .failed: "Failed"
        case .permissionNeeded: "Permission"
        case .rejected: "Rejected"
        case .all: "All"
        }
    }
}

public struct ReviewQueueItem: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var item: ItemProfile
    public var plan: OperationPlan
    public var reason: String
    public var status: ReviewQueueItemStatus
    public var message: String?
    public var indexedItem: IndexedItem?

    public init(
        id: UUID = UUID(),
        item: ItemProfile,
        plan: OperationPlan,
        reason: String,
        status: ReviewQueueItemStatus = .pending,
        message: String? = nil,
        indexedItem: IndexedItem? = nil
    ) {
        self.id = id
        self.item = item
        self.plan = plan
        self.reason = reason
        self.status = status
        self.message = message
        self.indexedItem = indexedItem
    }
}

@MainActor
public protocol ReviewPlanExecuting: AnyObject {
    func execute(_ plan: OperationPlan, item: ItemProfile) async throws -> ExecutionResult
}

public protocol ReviewQueueLoading: Sendable {
    func loadPendingReviewItems() async throws -> [ReviewQueueItem]
}

public protocol ReviewQueuePersisting: Sendable {
    func markApproved(_ item: ReviewQueueItem, result: ExecutionResult, now: Date) async throws
    func markRejected(_ item: ReviewQueueItem, message: String, now: Date) async throws
    func markLeftInInbox(_ item: ReviewQueueItem, message: String, now: Date) async throws
    func markRestored(_ item: ReviewQueueItem, message: String, now: Date) async throws
    func markDismissed(_ item: ReviewQueueItem, message: String, now: Date) async throws
}

@MainActor
public protocol WatchedFolderRefreshing: AnyObject {
    func reloadWatchedFolders() async
}

@MainActor
public protocol WatchedFolderControlling: AnyObject {
    func reloadWatchedFolders() async
    func scanNow() async throws -> Int
    func pauseAll() async
    func resumeAll() async throws
    func statusSnapshot() async throws -> [WatchedFolderStatus]
}

@MainActor
public final class ReviewQueueViewModel: ObservableObject {
    @Published public private(set) var items: [ReviewQueueItem]
    @Published public private(set) var watchedFolderStatuses: [WatchedFolderStatus]
    @Published public var filter: ReviewQueueFilter
    @Published public private(set) var selectedItemID: UUID?
    @Published public private(set) var isExecuting: Bool
    @Published public private(set) var isLoading: Bool
    @Published public private(set) var errorMessage: String?

    private let executor: ReviewPlanExecuting
    private let queueLoader: ReviewQueueLoading?
    private let queuePersistence: ReviewQueuePersisting?
    private weak var watchedFolderController: WatchedFolderControlling?
    private let now: () -> Date

    public init(
        items: [ReviewQueueItem] = .fixtureReviewItems(),
        executor: ReviewPlanExecuting = FixtureReviewPlanExecutor(),
        queueLoader: ReviewQueueLoading? = nil,
        queuePersistence: ReviewQueuePersisting? = nil,
        watchedFolderController: WatchedFolderControlling? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.items = items
        self.executor = executor
        self.queueLoader = queueLoader
        self.queuePersistence = queuePersistence
        self.watchedFolderController = watchedFolderController
        self.now = now
        watchedFolderStatuses = []
        filter = .needsDecision
        selectedItemID = items.first?.id
        isExecuting = false
        isLoading = false
        errorMessage = nil
    }

    public var selectedItem: ReviewQueueItem? {
        guard let selectedItemID else {
            return nil
        }
        return items.first { $0.id == selectedItemID }
    }

    public var pendingCount: Int {
        items.filter { $0.status == .pending }.count
    }

    public var filteredItems: [ReviewQueueItem] {
        items.filter { item in
            switch filter {
            case .needsDecision:
                item.status == .pending
            case .keptForLater:
                item.status == .inbox
            case .failed:
                item.status == .failed
            case .permissionNeeded:
                item.indexedItem?.status == .missing
            case .rejected:
                item.status == .rejected
            case .all:
                true
            }
        }
    }

    public var canDecideSelectedItem: Bool {
        guard let status = selectedItem?.status else {
            return false
        }
        return status == .pending || status == .inbox
    }

    public var isEmpty: Bool {
        filteredItems.isEmpty
    }

    public var watcherStatusSummary: String {
        guard !watchedFolderStatuses.isEmpty else {
            return "No watched folders"
        }
        let running = watchedFolderStatuses.filter { $0.state == .running }.count
        let paused = watchedFolderStatuses.filter { $0.state == .paused }.count
        let stopped = watchedFolderStatuses.filter { $0.state == .stopped }.count
        return "\(running) running, \(paused) paused, \(stopped) stopped"
    }

    public func select(id: UUID?) {
        selectedItemID = id
    }

    public func load() async {
        isLoading = true
        errorMessage = nil

        do {
            if let queueLoader {
                items = try await queueLoader.loadPendingReviewItems()
                selectedItemID = filteredItems.first?.id ?? items.first?.id
            }
            try await loadWatchedFolderStatuses()
        } catch {
            items = []
            selectedItemID = nil
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    public func approveSelected() async {
        guard let index = selectedIndex else {
            return
        }

        isExecuting = true
        errorMessage = nil

        do {
            let result = try await executor.execute(items[index].plan, item: items[index].item)
            var approvedItem = items[index]
            approvedItem.status = .approved
            approvedItem.message = "Approved \(result.operationResults.count) operation(s)."
            try await queuePersistence?.markApproved(approvedItem, result: result, now: now())
            removeItem(at: index)
        } catch {
            items[index].status = .failed
            items[index].message = error.localizedDescription
            errorMessage = error.localizedDescription
        }

        isExecuting = false
    }

    public func rejectSelected(message: String = "Rejected by user.") async {
        guard let index = selectedIndex else {
            return
        }

        do {
            var rejectedItem = items[index]
            rejectedItem.status = .rejected
            rejectedItem.message = message
            try await queuePersistence?.markRejected(rejectedItem, message: message, now: now())
            items[index] = rejectedItem
            errorMessage = nil
        } catch {
            items[index].status = .failed
            items[index].message = error.localizedDescription
            errorMessage = error.localizedDescription
        }
    }

    public func leaveSelectedInInbox(message: String = "Left in inbox for later.") async {
        guard let index = selectedIndex else {
            return
        }

        do {
            var inboxItem = items[index]
            inboxItem.status = .inbox
            inboxItem.message = message
            try await queuePersistence?.markLeftInInbox(inboxItem, message: message, now: now())
            items[index] = inboxItem
            errorMessage = nil
        } catch {
            items[index].status = .failed
            items[index].message = error.localizedDescription
            errorMessage = error.localizedDescription
        }
    }

    public func markSelectedHandled(message: String = "Dismissed from Intake.") async {
        guard let selectedItemID,
              let index = selectedIndex else {
            return
        }
        do {
            try await queuePersistence?.markDismissed(items[index], message: message, now: now())
            errorMessage = nil
        } catch {
            items[index].status = .failed
            items[index].message = error.localizedDescription
            errorMessage = error.localizedDescription
            return
        }
        items.removeAll { $0.id == selectedItemID }
        self.selectedItemID = items.first(where: { $0.status == .pending })?.id ?? items.first?.id
    }

    public func restoreSelectedForDecision(message: String = "Restored for decision.") async {
        guard let index = selectedIndex else {
            return
        }
        do {
            var restored = items[index]
            restored.status = .pending
            restored.message = message
            try await queuePersistence?.markRestored(restored, message: message, now: now())
            items[index] = restored
            filter = .needsDecision
            selectedItemID = restored.id
            errorMessage = nil
        } catch {
            items[index].status = .failed
            items[index].message = error.localizedDescription
            errorMessage = error.localizedDescription
        }
    }

    public func retrySelected() async {
        guard selectedIndex != nil else {
            return
        }
        await restoreSelectedForDecision(message: "Ready to retry.")
    }

    public func scanWatchedFoldersNow() async {
        guard let watchedFolderController else {
            errorMessage = "Watcher controls are unavailable."
            return
        }
        do {
            let count = try await watchedFolderController.scanNow()
            try await loadWatchedFolderStatuses()
            errorMessage = count == 1 ? "1 item scanned." : "\(count) items scanned."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func pauseWatchedFolders() async {
        guard let watchedFolderController else {
            errorMessage = "Watcher controls are unavailable."
            return
        }
        await watchedFolderController.pauseAll()
        try? await loadWatchedFolderStatuses()
    }

    public func resumeWatchedFolders() async {
        guard let watchedFolderController else {
            errorMessage = "Watcher controls are unavailable."
            return
        }
        do {
            try await watchedFolderController.resumeAll()
            try await loadWatchedFolderStatuses()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func updateSelectedDestination(_ destinationPath: String) {
        guard let index = selectedIndex else {
            return
        }

        let destinationFolderURL = URL(fileURLWithPath: destinationPath, isDirectory: true)
        let destinationURL = destinationFolderURL.appendingPathComponent(
            items[index].item.displayName,
            isDirectory: items[index].item.kind == .folder
        )
        var updatedMoveOrCopy = false
        var updatedOperations = items[index].plan.operations.map { operation in
            if operation.kind == .move || operation.kind == .copy {
                updatedMoveOrCopy = true
                return Operation(
                    id: operation.id,
                    kind: operation.kind,
                    itemURL: operation.itemURL,
                    destinationURL: destinationURL,
                    value: operation.value,
                    reversible: operation.reversible
                )
            }
            return operation
        }

        if !updatedMoveOrCopy {
            updatedOperations = [
                Operation(
                    kind: .move,
                    itemURL: items[index].item.url,
                    destinationURL: destinationURL,
                    reversible: true
                )
            ]
        }

        items[index].plan = OperationPlan(
            id: items[index].plan.id,
            operations: updatedOperations,
            expectedResultURL: destinationURL,
            conflicts: items[index].plan.conflicts,
            reversible: items[index].plan.reversible,
            previewText: "Move \(items[index].item.displayName) to \(destinationPath)"
        )
    }

    private var selectedIndex: Int? {
        guard let selectedItemID else {
            return nil
        }
        return items.firstIndex { $0.id == selectedItemID }
    }

    private func loadWatchedFolderStatuses() async throws {
        if let watchedFolderController {
            watchedFolderStatuses = try await watchedFolderController.statusSnapshot()
        } else {
            watchedFolderStatuses = []
        }
    }

    private func removeItem(at index: Int) {
        items.remove(at: index)
        selectedItemID = items.first(where: { $0.status == .pending || $0.status == .inbox })?.id ?? items.first?.id
    }
}

public final class SearchBackedReviewQueueLoader: ReviewQueueLoading {
    private let searchService: SearchService
    private let limit: Int

    public init(searchService: SearchService, limit: Int = 100) {
        self.searchService = searchService
        self.limit = limit
    }

    public func loadPendingReviewItems() async throws -> [ReviewQueueItem] {
        let results = try await searchService.search(
            SearchQuery(text: "", statuses: [.needsReview], limit: limit)
        )
        return results.items.map(Self.reviewQueueItem)
    }

    private static func reviewQueueItem(from indexedItem: IndexedItem) -> ReviewQueueItem {
        let itemURL = URL(fileURLWithPath: indexedItem.currentPath, isDirectory: indexedItem.kind.isDirectoryLike)
        let itemProfile = ItemProfile(
            id: indexedItem.id,
            url: itemURL,
            kind: indexedItem.kind,
            displayName: indexedItem.displayName,
            fileExtension: indexedItem.kind == .file ? itemURL.pathExtension.nilIfEmpty : nil,
            uniformTypeIdentifier: indexedItem.uniformTypeIdentifier,
            sizeBytes: indexedItem.sizeBytes,
            createdAt: indexedItem.createdAt,
            modifiedAt: indexedItem.modifiedAt,
            finderTags: indexedItem.tags,
            extractedTextSummary: indexedItem.extractedText
        )
        let reviewOperation = Operation(
            kind: .markNeedsReview,
            itemURL: itemURL,
            value: "Loaded from the search index inbox queue.",
            reversible: true
        )
        let plan = OperationPlan(
            operations: [reviewOperation],
            reversible: true,
            previewText: "Review \(indexedItem.displayName)"
        )
        return ReviewQueueItem(
            id: indexedItem.id,
            item: itemProfile,
            plan: plan,
            reason: indexedItem.aiSummary ?? "Needs review from a previous organization decision.",
            indexedItem: indexedItem
        )
    }
}

public final class SearchBackedReviewQueuePersistence: ReviewQueuePersisting {
    private let searchService: SearchService

    public init(searchService: SearchService) {
        self.searchService = searchService
    }

    public func markApproved(_ item: ReviewQueueItem, result: ExecutionResult, now: Date) async throws {
        try await searchService.update(
            indexedItem(
                from: item,
                status: .organized,
                currentPath: approvedPath(for: item, result: result),
                originalPath: item.indexedItem?.originalPath ?? item.item.url.path,
                message: item.message,
                now: now
            )
        )
    }

    public func markRejected(_ item: ReviewQueueItem, message: String, now: Date) async throws {
        try await searchService.update(
            indexedItem(
                from: item,
                status: .failed,
                currentPath: item.item.url.path,
                originalPath: item.indexedItem?.originalPath,
                message: message,
                now: now
            )
        )
    }

    public func markLeftInInbox(_ item: ReviewQueueItem, message: String, now: Date) async throws {
        try await searchService.update(
            indexedItem(
                from: item,
                status: .needsReview,
                currentPath: item.item.url.path,
                originalPath: item.indexedItem?.originalPath,
                message: message,
                now: now
            )
        )
    }

    public func markRestored(_ item: ReviewQueueItem, message: String, now: Date) async throws {
        try await searchService.update(
            indexedItem(
                from: item,
                status: .needsReview,
                currentPath: item.item.url.path,
                originalPath: item.indexedItem?.originalPath,
                message: message,
                now: now
            )
        )
    }

    public func markDismissed(_ item: ReviewQueueItem, message: String, now: Date) async throws {
        try await searchService.update(
            indexedItem(
                from: item,
                status: .indexedOnly,
                currentPath: item.item.url.path,
                originalPath: item.indexedItem?.originalPath,
                message: message,
                now: now
            )
        )
    }

    private func approvedPath(for item: ReviewQueueItem, result: ExecutionResult) -> String {
        result.operationResults.first(where: { $0.resultingURL != nil })?.resultingURL?.path
            ?? item.plan.expectedResultURL?.path
            ?? item.item.url.path
    }

    private func indexedItem(
        from item: ReviewQueueItem,
        status: IndexedItemStatus,
        currentPath: String,
        originalPath: String?,
        message: String?,
        now: Date
    ) -> IndexedItem {
        let existing = item.indexedItem
        return IndexedItem(
            id: item.item.id,
            currentPath: currentPath,
            originalPath: originalPath,
            displayName: item.item.displayName,
            kind: item.item.kind,
            uniformTypeIdentifier: existing?.uniformTypeIdentifier ?? item.item.uniformTypeIdentifier,
            sizeBytes: existing?.sizeBytes ?? item.item.sizeBytes,
            createdAt: existing?.createdAt ?? item.item.createdAt,
            modifiedAt: existing?.modifiedAt ?? item.item.modifiedAt,
            importedAt: existing?.importedAt ?? now,
            routedAt: now,
            ruleID: existing?.ruleID,
            tags: existing?.tags ?? item.item.finderTags,
            extractedText: existing?.extractedText ?? item.item.extractedTextSummary,
            aiSummary: message ?? existing?.aiSummary ?? item.reason,
            status: status
        )
    }
}

@MainActor
public final class FixtureReviewPlanExecutor: ReviewPlanExecuting {
    public init() {}

    public func execute(_ plan: OperationPlan, item: ItemProfile) async throws -> ExecutionResult {
        let results = plan.operations.map { operation in
            OperationExecutionResult(
                operationID: operation.id,
                status: .completed,
                resultingURL: operation.destinationURL
            )
        }
        return ExecutionResult(planID: plan.id, operationResults: results)
    }
}

private extension ItemKind {
    var isDirectoryLike: Bool {
        switch self {
        case .folder, .package, .bundle:
            true
        case .file, .symlink, .unknown:
            false
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

public extension Array where Element == ReviewQueueItem {
    static func fixtureReviewItems() -> [ReviewQueueItem] {
        [
            ReviewQueueItem(
                item: ItemProfile(
                    url: URL(fileURLWithPath: "/Users/example/Downloads/unknown.pdf"),
                    kind: .file,
                    displayName: "unknown.pdf",
                    fileExtension: "pdf",
                    uniformTypeIdentifier: "com.adobe.pdf",
                    source: .dragDrop
                ),
                plan: OperationPlan.reviewFixture(
                    itemURL: URL(fileURLWithPath: "/Users/example/Downloads/unknown.pdf"),
                    destinationURL: URL(fileURLWithPath: "/Users/example/Bipbox/Documents/unknown.pdf")
                ),
                reason: "Low confidence route between Documents and Finance."
            ),
            ReviewQueueItem(
                item: ItemProfile.rulesFixtureFolder(),
                plan: OperationPlan.reviewFixture(
                    itemURL: URL(fileURLWithPath: "/Users/example/Downloads/Client Project", isDirectory: true),
                    destinationURL: URL(fileURLWithPath: "/Users/example/Bipbox/Projects/Client Project")
                ),
                reason: "Folder matched project rule but needs confirmation."
            )
        ]
    }
}

private extension OperationPlan {
    static func reviewFixture(itemURL: URL, destinationURL: URL) -> OperationPlan {
        let operation = Operation(
            kind: .move,
            itemURL: itemURL,
            destinationURL: destinationURL,
            reversible: true
        )
        return OperationPlan(
            operations: [operation],
            expectedResultURL: destinationURL,
            reversible: true,
            previewText: "Move \(itemURL.lastPathComponent) to \(destinationURL.deletingLastPathComponent().path)"
        )
    }
}
