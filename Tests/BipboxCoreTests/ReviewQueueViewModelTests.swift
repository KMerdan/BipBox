import BipboxCore
import BipboxWorkspaceUI
import XCTest

@MainActor
final class ReviewQueueViewModelTests: XCTestCase {
    func testApproveExecutesSelectedPlanAndRemovesItemFromInbox() async {
        let item = reviewItem(kind: .file)
        let executor = CapturingReviewExecutor()
        let viewModel = ReviewQueueViewModel(items: [item], executor: executor)

        XCTAssertTrue(viewModel.canDecideSelectedItem)

        await viewModel.approveSelected()

        XCTAssertEqual(executor.executedPlans, [item.plan])
        XCTAssertEqual(executor.executedItems.map(\.displayName), [item.item.displayName])
        XCTAssertTrue(viewModel.items.isEmpty)
        XCTAssertNil(viewModel.selectedItem)
        XCTAssertFalse(viewModel.canDecideSelectedItem)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testRejectAndLeaveInInboxFlowsDoNotExecutePlan() async {
        let item = reviewItem(kind: .file)
        let executor = CapturingReviewExecutor()
        let viewModel = ReviewQueueViewModel(items: [item], executor: executor)

        await viewModel.rejectSelected(message: "Not this one.")

        XCTAssertEqual(viewModel.selectedItem?.status, .rejected)
        XCTAssertEqual(viewModel.selectedItem?.message, "Not this one.")
        XCTAssertFalse(viewModel.canDecideSelectedItem)
        XCTAssertEqual(executor.executedPlans, [])

        await viewModel.leaveSelectedInInbox(message: "Later.")

        XCTAssertEqual(viewModel.selectedItem?.status, .inbox)
        XCTAssertEqual(viewModel.selectedItem?.message, "Later.")
        XCTAssertTrue(viewModel.canDecideSelectedItem)
        XCTAssertEqual(executor.executedPlans, [])
    }

    func testFolderReviewPreservesFolderAsSinglePlanItem() async {
        let folder = reviewItem(kind: .folder)
        let executor = CapturingReviewExecutor()
        let viewModel = ReviewQueueViewModel(items: [folder], executor: executor)

        await viewModel.approveSelected()

        XCTAssertEqual(executor.executedItems.first?.kind, .folder)
        XCTAssertEqual(executor.executedPlans.first?.operations.count, 1)
        XCTAssertEqual(executor.executedPlans.first?.operations.first?.itemURL, folder.item.url)
    }

    func testOperationErrorIsSurfacedToUI() async {
        let item = reviewItem(kind: .file)
        let executor = CapturingReviewExecutor(error: ReviewQueueTestError.executionFailed)
        let viewModel = ReviewQueueViewModel(items: [item], executor: executor)

        await viewModel.approveSelected()

        XCTAssertEqual(viewModel.selectedItem?.status, .failed)
        XCTAssertEqual(viewModel.selectedItem?.message, ReviewQueueTestError.executionFailed.localizedDescription)
        XCTAssertEqual(viewModel.errorMessage, ReviewQueueTestError.executionFailed.localizedDescription)
    }

    func testEmptyReviewQueueState() {
        let viewModel = ReviewQueueViewModel(items: [], executor: CapturingReviewExecutor())

        XCTAssertTrue(viewModel.isEmpty)
        XCTAssertEqual(viewModel.pendingCount, 0)
        XCTAssertNil(viewModel.selectedItem)
    }

    func testChangingDestinationUpdatesMoveOperation() {
        let item = reviewItem(kind: .file)
        let viewModel = ReviewQueueViewModel(items: [item], executor: CapturingReviewExecutor())

        viewModel.updateSelectedDestination("/Library/Receipts")

        let expectedURL = URL(fileURLWithPath: "/Library/Receipts", isDirectory: true)
            .appendingPathComponent(item.item.displayName)
        XCTAssertEqual(viewModel.selectedItem?.plan.operations.first?.destinationURL, expectedURL)
        XCTAssertEqual(viewModel.selectedItem?.plan.expectedResultURL, expectedURL)
    }

    func testChangingFolderDestinationPreservesFolderAsSingleMovedItem() {
        let item = reviewItem(name: "Client Project", kind: .folder)
        let viewModel = ReviewQueueViewModel(items: [item], executor: CapturingReviewExecutor())

        viewModel.updateSelectedDestination("/Library/Projects")

        let expectedURL = URL(fileURLWithPath: "/Library/Projects", isDirectory: true)
            .appendingPathComponent(item.item.displayName, isDirectory: true)
        XCTAssertEqual(viewModel.selectedItem?.plan.operations.first?.destinationURL, expectedURL)
        XCTAssertEqual(viewModel.selectedItem?.plan.operations.first?.itemURL, item.item.url)
        XCTAssertEqual(viewModel.selectedItem?.plan.operations.count, 1)
    }

    func testLoadedReviewItemCanBecomeMovePlanWhenDestinationChanges() async throws {
        let indexedItem = IndexedItem(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000099")!,
            currentPath: "/Downloads/unknown.pdf",
            displayName: "unknown.pdf",
            kind: .file,
            uniformTypeIdentifier: "com.adobe.pdf",
            importedAt: TestClock.now,
            aiSummary: "Low confidence route.",
            status: .needsReview
        )
        let loader = SearchBackedReviewQueueLoader(searchService: ReviewQueueSearchService(items: [indexedItem]))
        let viewModel = ReviewQueueViewModel(items: [], executor: CapturingReviewExecutor(), queueLoader: loader)

        await viewModel.load()
        viewModel.updateSelectedDestination("/Library/Documents")

        let expectedURL = URL(fileURLWithPath: "/Library/Documents", isDirectory: true)
            .appendingPathComponent("unknown.pdf")
        XCTAssertEqual(viewModel.items.count, 1)
        XCTAssertEqual(viewModel.selectedItem?.reason, "Low confidence route.")
        XCTAssertEqual(viewModel.selectedItem?.plan.operations.first?.kind, .move)
        XCTAssertEqual(viewModel.selectedItem?.plan.operations.first?.destinationURL, expectedURL)
        XCTAssertEqual(viewModel.selectedItem?.plan.expectedResultURL, expectedURL)
    }

    func testReviewQueueLoaderOnlyRequestsNeedsReviewItems() async throws {
        let service = ReviewQueueSearchService(items: [])
        let loader = SearchBackedReviewQueueLoader(searchService: service, limit: 25)

        _ = try await loader.loadPendingReviewItems()

        XCTAssertEqual(service.queries.first?.statuses, [.needsReview])
        XCTAssertEqual(service.queries.first?.limit, 25)
    }

    func testInboxDoesNotOwnSourceSetupWhenNoControllerIsConfigured() async {
        let viewModel = ReviewQueueViewModel(items: [], executor: CapturingReviewExecutor())

        await viewModel.load()

        XCTAssertEqual(viewModel.watchedFolderStatuses, [])
        XCTAssertEqual(viewModel.watcherStatusSummary, "No watched folders")
    }

    func testApprovePersistsOrganizedIndexedItem() async throws {
        let indexedItem = reviewIndexedItem()
        let item = reviewItem(indexedItem: indexedItem)
        let service = ReviewQueueSearchService(items: [indexedItem])
        let persistence = SearchBackedReviewQueuePersistence(searchService: service)
        let viewModel = ReviewQueueViewModel(
            items: [item],
            executor: CapturingReviewExecutor(),
            queuePersistence: persistence,
            now: { TestClock.now.addingTimeInterval(100) }
        )

        await viewModel.approveSelected()

        XCTAssertEqual(service.updatedItems.count, 1)
        XCTAssertEqual(service.updatedItems.first?.status, .organized)
        XCTAssertEqual(service.updatedItems.first?.currentPath, item.plan.expectedResultURL?.path)
        XCTAssertEqual(service.updatedItems.first?.originalPath, indexedItem.currentPath)
        XCTAssertEqual(service.updatedItems.first?.importedAt, indexedItem.importedAt)
        XCTAssertEqual(service.updatedItems.first?.routedAt, TestClock.now.addingTimeInterval(100))
    }

    func testRejectAndLeaveInInboxPersistIndexedStatus() async throws {
        let indexedItem = reviewIndexedItem()
        let service = ReviewQueueSearchService(items: [indexedItem])
        let persistence = SearchBackedReviewQueuePersistence(searchService: service)
        let rejectedViewModel = ReviewQueueViewModel(
            items: [reviewItem(indexedItem: indexedItem)],
            executor: CapturingReviewExecutor(),
            queuePersistence: persistence,
            now: { TestClock.now }
        )

        await rejectedViewModel.rejectSelected(message: "Not this one.")

        XCTAssertEqual(service.updatedItems.last?.status, .failed)
        XCTAssertEqual(service.updatedItems.last?.currentPath, indexedItem.currentPath)
        XCTAssertEqual(service.updatedItems.last?.aiSummary, "Not this one.")

        let inboxViewModel = ReviewQueueViewModel(
            items: [reviewItem(indexedItem: indexedItem)],
            executor: CapturingReviewExecutor(),
            queuePersistence: persistence,
            now: { TestClock.now }
        )

        await inboxViewModel.leaveSelectedInInbox(message: "Later.")

        XCTAssertEqual(service.updatedItems.last?.status, .needsReview)
        XCTAssertEqual(service.updatedItems.last?.currentPath, indexedItem.currentPath)
        XCTAssertEqual(service.updatedItems.last?.aiSummary, "Later.")
    }

    func testApproveSelectsNextInboxItem() async {
        let first = reviewItem(name: "first.pdf", kind: .file)
        let second = reviewItem(name: "second.pdf", kind: .file)
        let viewModel = ReviewQueueViewModel(items: [first, second], executor: CapturingReviewExecutor())

        await viewModel.approveSelected()

        XCTAssertEqual(viewModel.items, [second])
        XCTAssertEqual(viewModel.selectedItemID, second.id)
    }

    func testMarkHandledRemovesItemAndSelectsNext() async {
        let first = reviewItem(name: "first.pdf", kind: .file)
        let second = reviewItem(name: "second.pdf", kind: .file)
        let viewModel = ReviewQueueViewModel(items: [first, second], executor: CapturingReviewExecutor())

        await viewModel.markSelectedHandled()

        XCTAssertEqual(viewModel.items, [second])
        XCTAssertEqual(viewModel.selectedItemID, second.id)
    }

    func testDecisionStateFiltersSeparateKeptFailedRejectedAndAllItems() {
        let pending = reviewItem(name: "pending.pdf", kind: .file)
        var kept = reviewItem(name: "kept.pdf", kind: .file)
        kept.status = .inbox
        var failed = reviewItem(name: "failed.pdf", kind: .file)
        failed.status = .failed
        var rejected = reviewItem(name: "rejected.pdf", kind: .file)
        rejected.status = .rejected
        let viewModel = ReviewQueueViewModel(items: [pending, kept, failed, rejected], executor: CapturingReviewExecutor())

        XCTAssertEqual(viewModel.filteredItems.map(\.item.displayName), ["pending.pdf"])

        viewModel.filter = .keptForLater
        XCTAssertEqual(viewModel.filteredItems.map(\.item.displayName), ["kept.pdf"])

        viewModel.filter = .failed
        XCTAssertEqual(viewModel.filteredItems.map(\.item.displayName), ["failed.pdf"])

        viewModel.filter = .rejected
        XCTAssertEqual(viewModel.filteredItems.map(\.item.displayName), ["rejected.pdf"])

        viewModel.filter = .all
        XCTAssertEqual(viewModel.filteredItems.count, 4)
    }

    func testRestoreAndRetryMoveItemsBackToNeedsDecision() async {
        var failed = reviewItem(name: "failed.pdf", kind: .file)
        failed.status = .failed
        let viewModel = ReviewQueueViewModel(items: [failed], executor: CapturingReviewExecutor())
        viewModel.filter = .failed

        await viewModel.retrySelected()

        XCTAssertEqual(viewModel.selectedItem?.status, .pending)
        XCTAssertEqual(viewModel.filter, .needsDecision)
        XCTAssertEqual(viewModel.selectedItem?.message, "Ready to retry.")

        await viewModel.leaveSelectedInInbox()
        await viewModel.restoreSelectedForDecision()

        XCTAssertEqual(viewModel.selectedItem?.status, .pending)
        XCTAssertEqual(viewModel.selectedItem?.message, "Restored for decision.")
    }

    func testRestoreAndDismissPersistIndexedRecoveryState() async throws {
        let indexedItem = reviewIndexedItem(status: .failed)
        let service = ReviewQueueSearchService(items: [indexedItem])
        let persistence = SearchBackedReviewQueuePersistence(searchService: service)
        var rejected = reviewItem(indexedItem: indexedItem)
        rejected.status = .rejected
        let viewModel = ReviewQueueViewModel(
            items: [rejected],
            executor: CapturingReviewExecutor(),
            queuePersistence: persistence,
            now: { TestClock.now }
        )

        await viewModel.restoreSelectedForDecision()

        XCTAssertEqual(service.updatedItems.last?.status, .needsReview)
        XCTAssertEqual(service.updatedItems.last?.aiSummary, "Restored for decision.")

        await viewModel.markSelectedHandled()

        XCTAssertEqual(service.updatedItems.last?.status, .indexedOnly)
        XCTAssertEqual(service.updatedItems.last?.aiSummary, "Dismissed from Intake.")
        XCTAssertEqual(viewModel.items, [])
    }

    func testWatcherControlsSurfaceStatusAndScanResults() async throws {
        let controller = CapturingWatchedFolderController()
        let viewModel = ReviewQueueViewModel(
            items: [],
            executor: CapturingReviewExecutor(),
            watchedFolderController: controller
        )

        await viewModel.load()
        await viewModel.scanWatchedFoldersNow()
        await viewModel.pauseWatchedFolders()
        await viewModel.resumeWatchedFolders()

        XCTAssertEqual(viewModel.watchedFolderStatuses.count, 1)
        XCTAssertEqual(viewModel.watcherStatusSummary, "1 running, 0 paused, 0 stopped")
        XCTAssertEqual(controller.scanCount, 1)
        XCTAssertEqual(controller.pauseCount, 1)
        XCTAssertEqual(controller.resumeCount, 1)
        XCTAssertEqual(viewModel.errorMessage, "2 items scanned.")
    }
}

private enum ReviewQueueTestError: Error {
    case executionFailed
}

@MainActor
private final class CapturingWatchedFolderRefresher: WatchedFolderRefreshing {
    private(set) var reloadCount = 0

    func reloadWatchedFolders() async {
        reloadCount += 1
    }
}

@MainActor
private final class CapturingWatchedFolderController: WatchedFolderControlling {
    private(set) var reloadCount = 0
    private(set) var scanCount = 0
    private(set) var pauseCount = 0
    private(set) var resumeCount = 0
    private let statusID = UUID(uuidString: "80000000-0000-0000-0000-000000000001")!

    func reloadWatchedFolders() async {
        reloadCount += 1
    }

    func scanNow() async throws -> Int {
        scanCount += 1
        return 2
    }

    func pauseAll() async {
        pauseCount += 1
    }

    func resumeAll() async throws {
        resumeCount += 1
    }

    func statusSnapshot() async throws -> [WatchedFolderStatus] {
        [
            WatchedFolderStatus(
                id: statusID,
                url: URL(fileURLWithPath: "/Downloads", isDirectory: true),
                state: .running,
                permissionState: .granted,
                captureLocation: .downloads
            )
        ]
    }
}

private final class ReviewQueueSearchService: SearchService, @unchecked Sendable {
    private let items: [IndexedItem]
    private(set) var queries: [SearchQuery] = []
    private(set) var updatedItems: [IndexedItem] = []

    init(items: [IndexedItem]) {
        self.items = items
    }

    func index(_ item: IndexedItem) async throws {}

    func update(_ item: IndexedItem) async throws {
        updatedItems.append(item)
    }

    func search(_ query: SearchQuery) async throws -> SearchResults {
        queries.append(query)
        let filtered = items.filter { item in
            query.statuses.isEmpty || query.statuses.contains(item.status)
        }
        return SearchResults(items: Array(filtered.prefix(query.limit)), totalCount: filtered.count)
    }
}

@MainActor
private final class CapturingReviewExecutor: ReviewPlanExecuting {
    private let error: Error?
    private(set) var executedPlans: [OperationPlan] = []
    private(set) var executedItems: [ItemProfile] = []

    init(error: Error? = nil) {
        self.error = error
    }

    func execute(_ plan: OperationPlan, item: ItemProfile) async throws -> ExecutionResult {
        if let error {
            throw error
        }
        executedPlans.append(plan)
        executedItems.append(item)
        return ExecutionResult(
            planID: plan.id,
            operationResults: plan.operations.map {
                OperationExecutionResult(operationID: $0.id, status: .completed, resultingURL: $0.destinationURL)
            }
        )
    }
}

private func reviewIndexedItem(
    id: UUID = UUID(uuidString: "10000000-0000-0000-0000-000000000055")!,
    name: String = "review.pdf",
    kind: ItemKind = .file,
    status: IndexedItemStatus = .needsReview
) -> IndexedItem {
    IndexedItem(
        id: id,
        currentPath: "/Downloads/\(name)",
        displayName: name,
        kind: kind,
        uniformTypeIdentifier: kind == .file ? "com.adobe.pdf" : nil,
        importedAt: TestClock.now,
        tags: ["review"],
        aiSummary: "Needs confirmation.",
        status: status
    )
}

private func reviewItem(name: String = "review.pdf", kind: ItemKind) -> ReviewQueueItem {
    let itemURL = URL(fileURLWithPath: "/Downloads/\(name)", isDirectory: kind == .folder)
    let destinationURL = URL(fileURLWithPath: "/Library/Target/\(name)", isDirectory: kind == .folder)
    let profile = ItemProfile(
        url: itemURL,
        kind: kind,
        displayName: name,
        fileExtension: kind == .file ? "pdf" : nil,
        source: .dragDrop
    )
    let operation = Operation(
        kind: .move,
        itemURL: itemURL,
        destinationURL: destinationURL,
        reversible: true
    )
    let plan = OperationPlan(
        operations: [operation],
        expectedResultURL: destinationURL,
        reversible: true,
        previewText: "Move \(name)"
    )
    return ReviewQueueItem(item: profile, plan: plan, reason: "Needs confirmation.")
}

private func reviewItem(indexedItem: IndexedItem) -> ReviewQueueItem {
    let itemURL = URL(fileURLWithPath: indexedItem.currentPath, isDirectory: indexedItem.kind == .folder)
    let destinationURL = URL(
        fileURLWithPath: "/Library/Target/\(indexedItem.displayName)",
        isDirectory: indexedItem.kind == .folder
    )
    let profile = ItemProfile(
        id: indexedItem.id,
        url: itemURL,
        kind: indexedItem.kind,
        displayName: indexedItem.displayName,
        fileExtension: indexedItem.kind == .file ? itemURL.pathExtension : nil,
        uniformTypeIdentifier: indexedItem.uniformTypeIdentifier,
        source: .dragDrop,
        finderTags: indexedItem.tags,
        extractedTextSummary: indexedItem.extractedText
    )
    let operation = Operation(
        kind: .move,
        itemURL: itemURL,
        destinationURL: destinationURL,
        reversible: true
    )
    let plan = OperationPlan(
        operations: [operation],
        expectedResultURL: destinationURL,
        reversible: true,
        previewText: "Move \(indexedItem.displayName)"
    )
    return ReviewQueueItem(
        id: indexedItem.id,
        item: profile,
        plan: plan,
        reason: indexedItem.aiSummary ?? "Needs confirmation.",
        indexedItem: indexedItem
    )
}
