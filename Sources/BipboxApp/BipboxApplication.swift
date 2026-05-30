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

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        commands.viewModel = viewModel
        commands.applicationModel = applicationModel
        commands.openWorkspaceAction = { [weak self] in
            self?.showWorkspaceWindow()
        }
        menuBarController = MenuBarStatusItemController(viewModel: viewModel)
        showWorkspaceWindow()
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

        let rootView = WorkspaceRootView(viewModels: applicationModel.workspaceViewModels)
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
    private let searchResultActions: BipboxSearchResultActions
    private let watchFolderRefresher: BipboxWatchFolderRefresher?
    @Published private(set) var startupError: String?

    init() {
        let searchResultActions = BipboxSearchResultActions()
        self.searchResultActions = searchResultActions

        do {
            let services = try BipboxAppServices.makeDefault()
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
            startupError = nil
            Task {
                try? await services.watchFolderAutomation.reloadWatchedFolders()
                await services.watchFolderAutomation.startScanning()
            }
        } catch {
            services = nil
            watchFolderRefresher = nil
            workspaceViewModels = WorkspaceViewModels()
            startupError = error.localizedDescription
        }
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
            EmptyView()
        }
    }
}
