import BipboxCore
import BipboxWorkspaceUI
import XCTest

@MainActor
final class OnboardingWorkspaceViewModelTests: XCTestCase {
    func testSelectSkipAndCompleteWithoutScanning() {
        let viewModel = OnboardingWorkspaceViewModel(selections: [
            OnboardingFolderSelection(role: .downloads),
            OnboardingFolderSelection(role: .desktop)
        ])
        let downloadsURL = URL(fileURLWithPath: "/Downloads", isDirectory: true)

        viewModel.select(role: .downloads, url: downloadsURL)
        viewModel.skip(role: .desktop)
        viewModel.completeWithoutScanning()

        XCTAssertEqual(viewModel.selectedCount, 1)
        XCTAssertEqual(viewModel.completedCount, 1)
        XCTAssertEqual(viewModel.selections.first?.url, downloadsURL)
        XCTAssertEqual(viewModel.selections.last?.state, .skipped)
        XCTAssertTrue(viewModel.isCompleted)
    }

    func testWatchedSourceSetupPersistsSourceIndexesAndWatches() async throws {
        let sourceStore = MockSourceStore()
        let coordinator = CapturingSourceLifecycleCoordinator(sourceStore: sourceStore)
        let viewModel = OnboardingWorkspaceViewModel(
            sourceStore: sourceStore,
            lifecycleCoordinator: coordinator,
            selections: [OnboardingFolderSelection(role: .downloads)]
        )
        let downloadsURL = URL(fileURLWithPath: "/Downloads", isDirectory: true)

        viewModel.select(role: .downloads, url: downloadsURL)
        await viewModel.saveAndScanSelectedFolders()

        let sources = try await sourceStore.sources()
        XCTAssertEqual(sources.count, 1)
        XCTAssertEqual(sources.first?.metadata["captureLocation"], "downloads")
        XCTAssertEqual(sources.first?.metadata["watchEnabled"], "true")
        XCTAssertEqual(sources.first?.metadata["startPurpose"], "watchAndIndex")
        XCTAssertEqual(coordinator.addRequests.first?.url, downloadsURL)
        XCTAssertEqual(viewModel.selections.first?.state, .completed)
        XCTAssertEqual(viewModel.selections.first?.scannedCount, 3)
        XCTAssertEqual(viewModel.selections.first?.message, "Initial scan completed.")
        XCTAssertEqual(viewModel.sources.map(\.url), [downloadsURL])
        XCTAssertTrue(viewModel.isCompleted)
    }

    func testLoadRendersPersistedSourcesAndSyncsPresetSelections() async throws {
        let downloadsURL = URL(fileURLWithPath: "/Downloads", isDirectory: true)
        let source = SourceFixtures.watchedFolder(
            url: downloadsURL,
            metadata: OnboardingFolderRole.downloads.metadata
        )
        let sourceStore = MockSourceStore(sourceRecords: [source])
        let viewModel = OnboardingWorkspaceViewModel(sourceStore: sourceStore)

        await viewModel.load()

        XCTAssertEqual(viewModel.sources.map(\.url), [downloadsURL])
        XCTAssertEqual(viewModel.watchedFolderCount, 1)
        XCTAssertEqual(viewModel.selections.first(where: { $0.role == .downloads })?.state, .completed)
        XCTAssertEqual(viewModel.selections.first(where: { $0.role == .downloads })?.sourceID, source.id)
    }

    func testSourceActionsCallLifecycleAndRefreshRows() async throws {
        let source = SourceFixtures.watchedFolder(metadata: OnboardingFolderRole.downloads.metadata)
        let sourceStore = MockSourceStore(sourceRecords: [source])
        let coordinator = CapturingSourceLifecycleCoordinator(sourceStore: sourceStore)
        let viewModel = OnboardingWorkspaceViewModel(
            sourceStore: sourceStore,
            lifecycleCoordinator: coordinator
        )
        await viewModel.load()

        await viewModel.scanSource(id: source.id)
        await viewModel.pauseSource(id: source.id)
        await viewModel.resumeSource(id: source.id)

        XCTAssertEqual(coordinator.scannedIDs, [source.id])
        XCTAssertEqual(coordinator.pausedIDs, [source.id])
        XCTAssertEqual(coordinator.resumedIDs, [source.id])
        XCTAssertEqual(viewModel.sources.first?.enabled, true)
        XCTAssertEqual(viewModel.sources.first?.watchState, .running)
    }

    func testChangingWatchedSourceUpdatesDurablePath() async throws {
        let source = SourceFixtures.watchedFolder(metadata: OnboardingFolderRole.downloads.metadata)
        let sourceStore = MockSourceStore(sourceRecords: [source])
        let coordinator = CapturingSourceLifecycleCoordinator(sourceStore: sourceStore)
        let viewModel = OnboardingWorkspaceViewModel(
            sourceStore: sourceStore,
            lifecycleCoordinator: coordinator
        )
        let replacementURL = URL(fileURLWithPath: "/NewDownloads", isDirectory: true)
        await viewModel.load()

        await viewModel.replaceWatchedFolder(id: source.id, with: replacementURL)

        XCTAssertEqual(coordinator.changedIDs, [source.id])
        XCTAssertEqual(viewModel.sources.first?.url, replacementURL)
    }

    func testRemovingWatchedSourceDeletesDurableRecord() async throws {
        let source = SourceFixtures.watchedFolder(metadata: OnboardingFolderRole.downloads.metadata)
        let sourceStore = MockSourceStore(sourceRecords: [source])
        let coordinator = CapturingSourceLifecycleCoordinator(sourceStore: sourceStore)
        let viewModel = OnboardingWorkspaceViewModel(
            sourceStore: sourceStore,
            lifecycleCoordinator: coordinator
        )
        await viewModel.load()

        await viewModel.removeWatchedFolder(id: source.id)

        let sources = try await sourceStore.sources()
        XCTAssertEqual(sources, [])
        XCTAssertEqual(viewModel.sources, [])
        XCTAssertEqual(coordinator.removedIDs, [source.id])
    }
}

private final class CapturingSourceLifecycleCoordinator: SourceLifecycleCoordinating, @unchecked Sendable {
    private let sourceStore: SourceStore
    private(set) var addRequests: [SourceLifecycleRequest] = []
    private(set) var changedIDs: [UUID] = []
    private(set) var removedIDs: [UUID] = []
    private(set) var scannedIDs: [UUID] = []
    private(set) var pausedIDs: [UUID] = []
    private(set) var resumedIDs: [UUID] = []

    init(sourceStore: SourceStore) {
        self.sourceStore = sourceStore
    }

    func addWatchedFolder(_ request: SourceLifecycleRequest) async throws -> SourceLifecycleResult {
        addRequests.append(request)
        var source = SourceRecord.watchedFolder(
            url: request.url,
            displayName: request.displayName,
            permissionRecordID: UUID(),
            enabled: request.enabled,
            createdAt: TestClock.now,
            metadata: request.metadata
        )
        source.recursivePolicy = request.recursivePolicy
        source.indexState = .completed
        source.watchState = .running
        source.lastScanAt = TestClock.now
        source.lastScanSummary = SourceScanSummary(discoveredCount: 3, indexedCount: 3, message: "Initial scan completed.")
        try await sourceStore.upsert(source)
        return SourceLifecycleResult(
            source: source,
            scanResult: ColdStartScanResult(
                sessionID: UUID(),
                rootURL: request.url,
                scannedItemCount: 3,
                contextCount: 0
            ),
            watcherReloaded: true,
            message: "Source indexed and watching for new arrivals."
        )
    }

    func changeWatchedFolder(id: UUID, to request: SourceLifecycleRequest) async throws -> SourceLifecycleResult {
        changedIDs.append(id)
        guard var source = try await sourceStore.source(id: id) else {
            throw SourceStoreError.missingSource(id)
        }
        source.url = request.url
        source.displayName = request.displayName ?? source.displayName
        source.metadata = request.metadata
        source.updatedAt = TestClock.now
        try await sourceStore.upsert(source)
        return SourceLifecycleResult(source: source, watcherReloaded: true, message: "Source changed.")
    }

    func removeSource(id: UUID, removePermission: Bool) async throws -> SourceLifecycleResult {
        removedIDs.append(id)
        let change = try await sourceStore.remove(id: id)
        guard case .removed(let source) = change else {
            throw SourceStoreError.missingSource(id)
        }
        return SourceLifecycleResult(source: source, watcherReloaded: true, message: "Source removed.")
    }

    func scanSource(id: UUID) async throws -> SourceLifecycleResult {
        scannedIDs.append(id)
        guard var source = try await sourceStore.source(id: id) else {
            throw SourceStoreError.missingSource(id)
        }
        source.indexState = .completed
        source.lastScanSummary = SourceScanSummary(discoveredCount: 4, indexedCount: 4, message: "Source scanned.")
        try await sourceStore.upsert(source)
        return SourceLifecycleResult(source: source, message: "Source scanned.")
    }

    func pauseSource(id: UUID) async throws -> SourceLifecycleResult {
        pausedIDs.append(id)
        guard var source = try await sourceStore.source(id: id) else {
            throw SourceStoreError.missingSource(id)
        }
        source.enabled = false
        source.watchState = .paused
        try await sourceStore.upsert(source)
        return SourceLifecycleResult(source: source, watcherReloaded: true, message: "Source paused.")
    }

    func resumeSource(id: UUID) async throws -> SourceLifecycleResult {
        resumedIDs.append(id)
        guard var source = try await sourceStore.source(id: id) else {
            throw SourceStoreError.missingSource(id)
        }
        source.enabled = true
        source.watchState = .running
        try await sourceStore.upsert(source)
        return SourceLifecycleResult(source: source, watcherReloaded: true, message: "Source resumed.")
    }
}
