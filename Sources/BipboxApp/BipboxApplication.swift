import AppKit
import BipboxAppSupport
import BipboxCore
import BipboxMenuBarUI
import BipboxWorkspaceUI
import SwiftUI

@MainActor
private final class BipboxAppCommands: MenuBarCommandHandling {
    weak var viewModel: MenuBarStatusViewModel?
    weak var applicationModel: BipboxApplicationModel?
    var openWorkspaceAction: (() -> Void)?

    func openWorkspace() {
        NSApp.activate(ignoringOtherApps: true)
        if let openWorkspaceAction {
            openWorkspaceAction()
        } else {
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
    }

    func pauseOrganizer() {
        viewModel?.update(status: .paused)
    }

    func resumeOrganizer() {
        viewModel?.update(status: .running)
    }

    func showRecentActivity() {
        openWorkspace()
    }

    func focusQuickSearch() {
        openWorkspace()
    }

    func submitDroppedFileURLs(_ urls: [URL]) {
        applicationModel?.submitDroppedURLs(urls)
    }

    func quit() {
        NSApp.terminate(nil)
    }
}

@MainActor
private final class BipboxApplicationDelegate: NSObject, NSApplicationDelegate {
    private let commands = BipboxAppCommands()
    private let applicationModel = BipboxApplicationModel()
    private lazy var viewModel = MenuBarStatusViewModel(commandHandler: commands)
    private var menuBarController: MenuBarStatusItemController?
    private var workspaceWindow: NSWindow?
    private var controlServer: WorkspaceControlServer?

    /// The shared Settings view model surfaced in the `Settings { }` scene (Cmd+,).
    var settingsViewModel: SettingsWorkspaceViewModel { applicationModel.workspaceViewModels.settings }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        commands.viewModel = viewModel
        commands.applicationModel = applicationModel
        commands.openWorkspaceAction = { [weak self] in
            self?.showWorkspaceWindow()
        }
        menuBarController = MenuBarStatusItemController(viewModel: viewModel)
        showWorkspaceWindow()
        startControlAPIIfRequested()
        seedFolderIfRequested()
    }

    private func seedFolderIfRequested() {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        if let seed = env["BIPBOX_SEED_FOLDER"], !seed.isEmpty {
            let url = URL(fileURLWithPath: seed, isDirectory: true)
            Task { await applicationModel.seedWatchedFolder(url) }
        }
        if let n = env["BIPBOX_SEED_PENDING"].flatMap(Int.init), n > 0 {
            Task { await applicationModel.workspaceModel.apply(WorkspaceCommand(action: WorkspaceAction.seedPending, target: String(n))) }
        }
        if let n = env["BIPBOX_SEED_MISSING"].flatMap(Int.init), n > 0 {
            Task { await applicationModel.workspaceModel.apply(WorkspaceCommand(action: WorkspaceAction.seedMissing, target: String(n))) }
        }
        #endif
    }

    /// Debug-only localhost control API for automation. Opt in with
    /// `BIPBOX_CONTROL_API=1` (optionally `BIPBOX_CONTROL_TOKEN`, `BIPBOX_CONTROL_PORT`).
    private func startControlAPIIfRequested() {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        guard env["BIPBOX_CONTROL_API"] == "1" else { return }
        let port = env["BIPBOX_CONTROL_PORT"].flatMap(UInt16.init) ?? 7777
        let server = WorkspaceControlServer(
            model: applicationModel.workspaceModel,
            port: port,
            token: env["BIPBOX_CONTROL_TOKEN"]
        )
        server.start()
        controlServer = server
        #endif
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWorkspaceWindow()
        return true
    }

    private func showWorkspaceWindow() {
        if let workspaceWindow {
            placeWindowOnVisibleScreen(workspaceWindow)
            activateWorkspaceWindow(workspaceWindow)
            return
        }

        let rootView = WorkspaceRootView(model: applicationModel.workspaceModel)
        let hostingView = NSHostingView(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Bipbox"
        window.contentView = hostingView
        window.isReleasedWhenClosed = false
        placeWindowOnVisibleScreen(window)

        workspaceWindow = window
        activateWorkspaceWindow(window)

        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window else {
                return
            }
            placeWindowOnVisibleScreen(window)
            activateWorkspaceWindow(window)
        }
    }

    private func activateWorkspaceWindow(_ window: NSWindow) {
        NSApp.setActivationPolicy(.regular)
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func placeWindowOnVisibleScreen(_ window: NSWindow) {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let visibleFrame = screen?.visibleFrame else {
            window.center()
            return
        }

        let topLeft = NSPoint(
            x: visibleFrame.minX + 80,
            y: visibleFrame.maxY - 80
        )
        window.setFrameTopLeftPoint(topLeft)
    }
}

@MainActor
private final class BipboxActivityUndoExecutor: ActivityUndoExecuting {
    nonisolated(unsafe) private let executor: OperationExecutor

    init(executor: OperationExecutor) {
        self.executor = executor
    }

    func executeUndo(_ operation: BipboxCore.Operation) async throws -> ExecutionResult {
        let plan = OperationPlan(
            operations: [operation],
            expectedResultURL: operation.destinationURL,
            reversible: operation.reversible,
            previewText: "Undo \(operation.kind.rawValue)"
        )
        return try await executor.execute(plan, context: ExecutionContext(actor: "user"))
    }
}

@MainActor
private final class BipboxReviewPlanExecutor: ReviewPlanExecuting {
    nonisolated(unsafe) private let executor: OperationExecutor

    init(executor: OperationExecutor) {
        self.executor = executor
    }

    func execute(_ plan: OperationPlan, item: ItemProfile) async throws -> ExecutionResult {
        try await executor.execute(plan, context: ExecutionContext(actor: "user"))
    }
}

@MainActor
private final class BipboxSearchResultActions: SearchResultActionHandling {
    func open(_ item: IndexedItem) {
        NSWorkspace.shared.open(URL(fileURLWithPath: item.currentPath, isDirectory: item.kind.isDirectoryLikeForApp))
    }

    func revealInFinder(_ item: IndexedItem) {
        NSWorkspace.shared.activateFileViewerSelecting([
            URL(fileURLWithPath: item.currentPath, isDirectory: item.kind.isDirectoryLikeForApp)
        ])
    }

    func copyPath(_ item: IndexedItem) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.currentPath, forType: .string)
    }
}

@MainActor
private final class BipboxWatchFolderRefresher: WatchedFolderRefreshing, WatchedFolderControlling {
    private let automation: WatchFolderAutomationService

    init(automation: WatchFolderAutomationService) {
        self.automation = automation
    }

    func reloadWatchedFolders() async {
        try? await automation.reloadWatchedFolders()
    }

    func scanNow() async throws -> Int {
        try await automation.scanOnce(receivedAt: Date())
    }

    func pauseAll() async {
        await automation.pauseAll()
    }

    func resumeAll() async throws {
        try await automation.resumeAll()
    }

    func statusSnapshot() async throws -> [WatchedFolderStatus] {
        try await automation.statusSnapshot()
    }
}

@MainActor
private final class BipboxApplicationModel: ObservableObject {
    let services: BipboxAppServices?
    let workspaceViewModels: WorkspaceViewModels
    let workspaceModel: WorkspaceModel
    private let searchResultActions: BipboxSearchResultActions
    private let watchFolderRefresher: BipboxWatchFolderRefresher?
    @Published private(set) var startupError: String?

    init() {
        let searchResultActions = BipboxSearchResultActions()
        self.searchResultActions = searchResultActions

        do {
            let services = try BipboxAppServices.makeDefault(paths: Self.overrideRuntimePaths())
            self.services = services
            let watchFolderRefresher = BipboxWatchFolderRefresher(automation: services.watchFolderAutomation)
            self.watchFolderRefresher = watchFolderRefresher
            workspaceViewModels = WorkspaceViewModels(
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
                    actionHandler: searchResultActions,
                    statusFilter: .all
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
                    executor: BipboxReviewPlanExecutor(executor: services.executor),
                    queueLoader: SearchBackedReviewQueueLoader(searchService: services.searchService),
                    queuePersistence: SearchBackedReviewQueuePersistence(searchService: services.searchService),
                    watchedFolderController: watchFolderRefresher
                ),
                activity: ActivityWorkspaceViewModel(
                    activityLog: services.activityLog,
                    undoExecutor: BipboxActivityUndoExecutor(executor: services.executor)
                ),
                settings: SettingsWorkspaceViewModel(
                    permissionStore: services.permissionStore,
                    appSettingsStore: services.appSettingsStore
                )
            )
            let model = WorkspaceModel(
                workspaceViewModels,
                graphServices: WorkspaceGraphServices(
                    graph: services.knowledgeGraphService,
                    relatedness: services.relatednessService,
                    store: services.knowledgeStore,
                    vectorIndex: services.vectorIndex,
                    embedder: services.embedder
                )
            )
            let dropHandler = services.dropIntakeHandler
            model.onDropURLs = { urls in
                Task {
                    _ = await dropHandler.submit(fileURLs: urls, source: .dragDrop, mode: .organize, receivedAt: Date())
                }
            }
            let search = services.searchService
            let base = services.paths.baseDirectoryURL
            model.pendingSeeder = { count in
                await seedPendingReviewItems(count: count, into: search, baseDirectory: base)
            }
            let store = services.knowledgeStore
            model.missingSeeder = { count in
                await seedMissingItems(count: count, into: search, knowledgeStore: store, baseDirectory: base)
            }
            workspaceModel = model
            startupError = nil
            Task {
                try? await services.watchFolderAutomation.reloadWatchedFolders()
                await services.watchFolderAutomation.startScanning()
            }
        } catch {
            services = nil
            watchFolderRefresher = nil
            let fixtures = WorkspaceViewModels()
            workspaceViewModels = fixtures
            workspaceModel = WorkspaceModel(fixtures)
            startupError = error.localizedDescription
        }
    }

    /// DEBUG: route the data store to an isolated directory for UI/automation tests.
    private static func overrideRuntimePaths() -> BipboxRuntimePaths? {
        #if DEBUG
        if let dir = ProcessInfo.processInfo.environment["BIPBOX_DATA_DIR"], !dir.isEmpty {
            return BipboxRuntimePaths(baseDirectoryURL: URL(fileURLWithPath: dir, isDirectory: true))
        }
        #endif
        return nil
    }

    /// DEBUG: seed a watched folder on launch so UI tests have deterministic data.
    func seedWatchedFolder(_ url: URL) async {
        await workspaceModel.onboarding.addCustomWatchedFolder(url, recursivePolicy: .never)
        await workspaceModel.refresh()
    }

    func submitDroppedURLs(_ urls: [URL]) {
        guard let dropIntakeHandler = services?.dropIntakeHandler else {
            startupError = "Bipbox services are unavailable."
            return
        }

        Task {
            _ = await dropIntakeHandler.submit(
                fileURLs: urls,
                source: .dragDrop,
                mode: .organize,
                receivedAt: Date()
            )
        }
    }
}

private extension ItemKind {
    var isDirectoryLikeForApp: Bool {
        switch self {
        case .folder, .package, .bundle:
            true
        case .file, .symlink, .unknown:
            false
        }
    }
}

@main
struct BipboxApplication: App {
    @NSApplicationDelegateAdaptor(BipboxApplicationDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsWorkspaceView(viewModel: appDelegate.settingsViewModel)
                .frame(minWidth: 460, minHeight: 420)
        }
    }
}
