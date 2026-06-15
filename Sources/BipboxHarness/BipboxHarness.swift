// BipboxHarness — in-process programmatic driver for the Bipbox workspace.
//
// Builds the REAL service stack (the same `makeDefault()` the app uses) against an
// isolated data directory, wires the production view models, and exposes the
// `WorkspaceCommand` / `WorkspaceSnapshot` control surface. Use it from tests, a
// CLI, or any scripted scenario — every action drives real services and returns
// real state.
import BipboxAppSupport
import BipboxCore
import BipboxWorkspaceUI
import Foundation

@MainActor
public final class BipboxHarness {
    public let model: WorkspaceModel
    public let services: BipboxAppServices
    private let baseDirectory: URL
    private let ownsDirectory: Bool

    /// Build a harness over a fresh, isolated data directory (auto-created under a
    /// temp path unless `baseDirectory` is given).
    public init(baseDirectory: URL? = nil) throws {
        let fm = FileManager.default
        if let baseDirectory {
            self.baseDirectory = baseDirectory
            self.ownsDirectory = false
        } else {
            self.baseDirectory = fm.temporaryDirectory.appendingPathComponent("bipbox-harness-\(UUID().uuidString)", isDirectory: true)
            self.ownsDirectory = true
        }
        try fm.createDirectory(at: self.baseDirectory, withIntermediateDirectories: true)

        let services = try BipboxAppServices.makeDefault(paths: BipboxRuntimePaths(baseDirectoryURL: self.baseDirectory))
        self.services = services

        let viewModels = BipboxHarness.makeViewModels(services: services)
        let model = WorkspaceModel(
            viewModels,
            graphServices: WorkspaceGraphServices(
                graph: services.knowledgeGraphService,
                relatedness: services.relatednessService,
                store: services.knowledgeStore,
                vectorIndex: services.vectorIndex,
                embedder: services.embedder
            )
        )
        let search = services.searchService
        let base = self.baseDirectory
        model.pendingSeeder = { count in
            await seedPendingReviewItems(count: count, into: search, baseDirectory: base)
        }
        let store = services.knowledgeStore
        model.missingSeeder = { count in
            await seedMissingItems(count: count, into: search, knowledgeStore: store, baseDirectory: base)
        }
        self.model = model
    }

    deinit {
        if ownsDirectory {
            try? FileManager.default.removeItem(at: baseDirectory)
        }
    }

    /// Load initial state (library, sources, queue). Call once after init.
    public func start() async {
        await model.loadInitial()
    }

    // MARK: control surface

    @discardableResult
    public func apply(_ command: WorkspaceCommand) async -> WorkspaceSnapshot {
        await model.apply(command)
    }

    public func snapshot() async -> WorkspaceSnapshot {
        await model.snapshot()
    }

    /// Run a JSON command (object with `action` etc.) and return JSON snapshot.
    public func applyJSON(_ json: Data) async -> Data {
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let command = try decoder.decode(WorkspaceCommand.self, from: json)
            let snapshot = await apply(command)
            return (try? encoder.encode(snapshot)) ?? Data()
        } catch {
            let snapshot = await model.snapshot(error: "Bad command JSON: \(error.localizedDescription)")
            return (try? encoder.encode(snapshot)) ?? Data()
        }
    }

    // MARK: convenience (typed scenario helpers)

    @discardableResult
    public func addFolder(_ url: URL, depth: SourceRecursivePolicy = .never) async -> WorkspaceSnapshot {
        await model.onboarding.addCustomWatchedFolder(url, recursivePolicy: depth)
        await model.refresh()
        return await snapshot()
    }

    @discardableResult
    public func search(_ text: String) async -> WorkspaceSnapshot {
        await apply(WorkspaceCommand(action: WorkspaceAction.search, query: text))
    }

    @discardableResult
    public func navigate(_ nav: String) async -> WorkspaceSnapshot {
        await apply(WorkspaceCommand(action: WorkspaceAction.navigate, target: nav))
    }

    @discardableResult
    public func select(_ ref: String) async -> WorkspaceSnapshot {
        await apply(WorkspaceCommand(action: WorkspaceAction.select, target: ref))
    }

    /// Seed N pending (`needsReview`) items and refresh.
    @discardableResult
    public func seedPending(_ count: Int) async -> WorkspaceSnapshot {
        await apply(WorkspaceCommand(action: WorkspaceAction.seedPending, target: String(count)))
    }

    /// Seed N `.missing` items (backed by real files) and refresh.
    @discardableResult
    public func seedMissing(_ count: Int) async -> WorkspaceSnapshot {
        await apply(WorkspaceCommand(action: WorkspaceAction.seedMissing, target: String(count)))
    }

    /// Recover a missing item (locate/reindex/refresh).
    @discardableResult
    public func recover(_ id: String, mode: String, path: String? = nil) async -> WorkspaceSnapshot {
        await apply(WorkspaceCommand(action: WorkspaceAction.recover, path: path, id: id, mode: mode))
    }

    /// Route file URLs through the REAL drop-intake pipeline (organize mode), then refresh.
    @discardableResult
    public func submitDrop(_ urls: [URL]) async -> WorkspaceSnapshot {
        let handler = services.dropIntakeHandler
        _ = await handler.submit(
            fileURLs: urls, source: .dragDrop, mode: .organize, receivedAt: Date()
        )
        await model.refresh()
        return await snapshot()
    }

    // MARK: view-model wiring (mirrors BipboxApplication)

    private static func makeViewModels(services: BipboxAppServices) -> WorkspaceViewModels {
        WorkspaceViewModels(
            onboarding: OnboardingWorkspaceViewModel(
                sourceStore: services.sourceStore,
                lifecycleCoordinator: services.sourceLifecycleCoordinator
            ),
            library: SearchWorkspaceViewModel(
                searchService: services.searchService,
                retrievalService: services.retrievalService,
                missingFileRecoveryService: services.missingFileRecoveryService,
                relatednessService: services.relatednessService,
                relatedContextService: services.relatedContextService,
                actionHandler: HarnessSearchActions(),
                statusFilter: .all,
                limit: 50_000
            ),
            rules: RulesWorkspaceViewModel(
                workflow: services.workflowConfiguration.workflow,
                ruleStore: services.ruleStore,
                onWorkflowChanged: { [workflowConfiguration = services.workflowConfiguration] workflow in
                    workflowConfiguration.workflow = workflow
                }
            ),
            reviewQueue: ReviewQueueViewModel(
                items: [],
                executor: HarnessReviewExecutor(executor: services.executor),
                queueLoader: SearchBackedReviewQueueLoader(searchService: services.searchService),
                queuePersistence: SearchBackedReviewQueuePersistence(searchService: services.searchService)
            ),
            activity: ActivityWorkspaceViewModel(
                activityLog: services.activityLog,
                undoExecutor: HarnessUndoExecutor(executor: services.executor)
            ),
            settings: SettingsWorkspaceViewModel(
                appSettingsStore: services.appSettingsStore,
                dataDirectoryURL: services.paths.dataDirectoryURL
            )
        )
    }
}

// MARK: - Minimal action wrappers (headless: open/reveal are no-ops)

@MainActor
private final class HarnessSearchActions: SearchResultActionHandling {
    func open(_ item: IndexedItem) {}
    func revealInFinder(_ item: IndexedItem) {}
    func copyPath(_ item: IndexedItem) {}
}

@MainActor
private final class HarnessReviewExecutor: ReviewPlanExecuting {
    nonisolated(unsafe) private let executor: OperationExecutor
    init(executor: OperationExecutor) { self.executor = executor }
    func execute(_ plan: OperationPlan, item: ItemProfile) async throws -> ExecutionResult {
        try await executor.execute(plan, context: ExecutionContext(actor: "harness"))
    }
}

@MainActor
private final class HarnessUndoExecutor: ActivityUndoExecuting {
    nonisolated(unsafe) private let executor: OperationExecutor
    init(executor: OperationExecutor) { self.executor = executor }
    func executeUndo(_ operation: BipboxCore.Operation) async throws -> ExecutionResult {
        let plan = OperationPlan(
            operations: [operation],
            expectedResultURL: operation.destinationURL,
            reversible: operation.reversible,
            previewText: "Undo \(operation.kind.rawValue)"
        )
        return try await executor.execute(plan, context: ExecutionContext(actor: "harness"))
    }
}
