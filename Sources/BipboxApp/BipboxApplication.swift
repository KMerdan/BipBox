import AppKit
import BipboxAppSupport
import BipboxCore
import BipboxMenuBarUI
import BipboxMLX
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
        applicationModel.provisioning.start()   // load cached model, or surface the one-time download
        applicationModel.rescanSourcesOnLaunch() // reconcile offline changes (cheap: fingerprint-skipping)
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

        let rootView = RootContainerView(
            coordinator: applicationModel.provisioning,
            model: applicationModel.workspaceModel,
            startupError: applicationModel.startupError
        )
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
    let provisioning: ModelProvisioningCoordinator
    private let searchResultActions: BipboxSearchResultActions
    private let watchFolderRefresher: BipboxWatchFolderRefresher?
    @Published private(set) var startupError: String?

    init() {
        let searchResultActions = BipboxSearchResultActions()
        self.searchResultActions = searchResultActions

        do {
            try Self.forceStartupErrorIfRequested()
            let services = try BipboxAppServices.makeDefault(
                paths: Self.overrideRuntimePaths(),
                embedderFactory: Self.makeEmbedderFactory()
            )
            self.services = services
            self.provisioning = ModelProvisioningCoordinator(embedder: services.embedder)
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
                    statusFilter: .all,
                    // Load the whole library, not a 50-row sample — otherwise the
                    // gallery, source views, and clustering only ever see 50 items.
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
                    appSettingsStore: services.appSettingsStore,
                    dataDirectoryURL: services.paths.dataDirectoryURL
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
            // Once the model is provisioned, backfill embeddings + recompute topics.
            provisioning.onBecameReady = { [weak self] in await self?.backfillAndRecompute() }
            Task {
                try? await services.watchFolderAutomation.reloadWatchedFolders()
                await services.watchFolderAutomation.startScanning()
            }
            // Long-running scans -> sidebar status line ("Indexing <source> · n of m · ETA").
            // Throttled: a per-item MainActor publish for a 7k-file scan is wasted churn.
            Task { [weak self] in
                await services.sourceLifecycleCoordinator.setScanProgress { sourceName, progress in
                    let shouldPublish = progress.phase != .scanning || progress.scannedCount % 20 == 0
                    guard shouldPublish else { return }
                    await MainActor.run {
                        guard let self else { return }
                        switch progress.phase {
                        case .completed:
                            self.workspaceModel.reportIndexing(kind: nil)
                        default:
                            guard let total = progress.totalCount, total > 0 else { return }
                            self.workspaceModel.reportIndexing(
                                kind: .scanning(sourceName: sourceName),
                                completed: progress.scannedCount, total: total)
                        }
                    }
                }
            }
        } catch {
            services = nil
            watchFolderRefresher = nil
            provisioning = ModelProvisioningCoordinator(embedder: nil)
            let fixtures = WorkspaceViewModels()
            workspaceViewModels = fixtures
            workspaceModel = WorkspaceModel(fixtures)
            startupError = error.localizedDescription
        }
    }

    /// The app injects the MLX (Qwen3) embedder. DEBUG UI tests can substitute a
    /// scripted provisioner via `BIPBOX_FAKE_PROVISIONING=needsDownload|ready` so the
    /// banner flow is testable without a real ~600 MB download.
    private static func makeEmbedderFactory() -> (@Sendable (BipboxRuntimePaths) -> TextEmbedder) {
        #if DEBUG
        if let mode = ProcessInfo.processInfo.environment["BIPBOX_FAKE_PROVISIONING"], !mode.isEmpty {
            return { _ in ScriptedProvisioningEmbedder(mode: mode) }
        }
        #endif
        return { paths in MLXTextEmbedder(markerURL: paths.embedderMarkerURL) }
    }

    /// DEBUG: force the startup-error path so the error banner is testable.
    private static func forceStartupErrorIfRequested() throws {
        #if DEBUG
        if ProcessInfo.processInfo.environment["BIPBOX_FORCE_STARTUP_ERROR"] == "1" {
            throw NSError(domain: "Bipbox", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "forced startup error (debug)"])
        }
        #endif
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

    /// Once the embedding model is provisioned: embed any indexed items that lack a
    /// vector for it, then recompute the topic graph so it actually populates.
    func backfillAndRecompute() async {
        guard let services else { return }
        _ = await services.embeddingBackfill.backfill(limit: 10_000) { [weak self] processed, total in
            // Embedding is slow (local model), so every 10th update is plenty.
            guard processed % 10 == 0 || processed == total else { return }
            await MainActor.run {
                self?.workspaceModel.reportIndexing(kind: .embedding, completed: processed, total: total)
            }
        }
        workspaceModel.reportIndexing(kind: nil)
        workspaceModel.invalidateSemanticIndex()   // embeddings changed
        await workspaceModel.recomputeClusters()
    }

    /// Every launch: incremental rescan of all completed sources. Unchanged items
    /// are fingerprint-skipped, so this only pays for files that changed while the
    /// app was closed — and it upgrades pre-unit-model libraries in place
    /// (services.needsMigrationRescan). Backfill afterwards embeds anything new.
    func rescanSourcesOnLaunch() {
        guard let services else { return }
        // Plain Task: the awaits suspend rather than block the main thread; the
        // heavy work happens inside the scanner/store actors.
        Task(priority: .utility) { [weak self] in
            await services.rescanAllSources()
            await self?.backfillAndRecompute()
        }
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

/// Drives the one-time embedding-model download and exposes its state to the UI.
/// On launch: if the model is already cached it loads silently; otherwise it
/// surfaces `.needsDownload` so the user opts in — never a silent download.
@MainActor
final class ModelProvisioningCoordinator: ObservableObject {
    @Published private(set) var status: EmbedderModelStatus = .ready
    private let provisioner: EmbedderProvisioning?
    /// Runs once the model reaches `.ready` (e.g. backfill embeddings + recompute topics).
    var onBecameReady: (() async -> Void)?

    init(embedder: TextEmbedder?) {
        self.provisioner = embedder as? EmbedderProvisioning
    }

    func start() {
        guard let provisioner else { status = .ready; return }
        Task {
            let current = await provisioner.provisioningStatus()
            if case .ready = current {
                await load(provisioner)        // cached → load into memory, no download
            } else {
                status = current               // .needsDownload → banner waits for the user
            }
        }
    }

    func download() {
        guard let provisioner else { return }
        Task { await load(provisioner) }
    }

    private func load(_ provisioner: EmbedderProvisioning) async {
        status = .downloading(0)
        let final = await provisioner.prepare { [weak self] fraction in
            Task { @MainActor in self?.status = .downloading(fraction) }
        }
        status = final
        if case .ready = final { await onBecameReady?() }
    }
}

/// First-run banner above the workspace. Hidden once the model is ready.
private struct ModelProvisioningBanner: View {
    @ObservedObject var coordinator: ModelProvisioningCoordinator

    var body: some View {
        switch coordinator.status {
        case .ready:
            EmptyView()
        case .needsDownload:
            banner(color: .yellow, icon: "sparkles") {
                Text("Semantic search uses a one-time on-device model (~600 MB). It runs locally — nothing leaves your Mac.")
                Spacer(minLength: 12)
                Button("Download") { coordinator.download() }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("provisioning.download")
            }
        case .downloading(let fraction):
            banner(color: .blue, icon: "arrow.down.circle") {
                Text("Preparing semantic search…")
                    .accessibilityIdentifier("provisioning.downloading")
                ProgressView(value: fraction).frame(width: 160)
                Text("\(Int(fraction * 100))%").monospacedDigit().foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        case .failed(let message):
            banner(color: .red, icon: "exclamationmark.triangle") {
                Text("Model download failed. Search is using keywords only.")
                    .help(message)
                Spacer(minLength: 12)
                Button("Retry") { coordinator.download() }
                    .accessibilityIdentifier("provisioning.retry")
            }
        }
    }

    // NB: no accessibilityIdentifier on this container — identifying a container
    // collapses its a11y subtree and hides the child Button from XCUITest. Leaf
    // elements (the Download/Retry buttons, the "Preparing…" text) carry the IDs.
    @ViewBuilder
    private func banner(color: Color, icon: String, @ViewBuilder _ content: () -> some View) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(color)
            content()
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.12))
        .overlay(Rectangle().frame(height: 1).foregroundStyle(color.opacity(0.25)), alignment: .bottom)
    }
}

/// Workspace with the provisioning + startup-error banners stacked on top.
private struct RootContainerView: View {
    @ObservedObject var coordinator: ModelProvisioningCoordinator
    let model: WorkspaceModel
    let startupError: String?

    var body: some View {
        VStack(spacing: 0) {
            if let startupError {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.octagon").foregroundStyle(.red)
                    Text("Bipbox couldn't start its services: \(startupError)")
                    Spacer(minLength: 0)
                }
                .font(.callout)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.12))
                .overlay(Rectangle().frame(height: 1).foregroundStyle(.red.opacity(0.25)), alignment: .bottom)
                .accessibilityIdentifier("startup.error")
            }
            ModelProvisioningBanner(coordinator: coordinator)
            WorkspaceRootView(model: model)
        }
    }
}

#if DEBUG
/// DEBUG-only scripted embedder for UI tests of the provisioning banner — no real
/// download. `mode == "ready"` starts provisioned; `"needsDownload"` shows the banner
/// and `download()` plays a brief visible progress sequence before becoming ready.
actor ScriptedProvisioningEmbedder: TextEmbedder, EmbedderProvisioning {
    let modelID = "debug-scripted-embed"
    private var ready: Bool

    init(mode: String) { self.ready = (mode == "ready") }

    func provisioningStatus() async -> EmbedderModelStatus { ready ? .ready : .needsDownload }

    @discardableResult
    func prepare(progress: @Sendable @escaping (Double) -> Void) async -> EmbedderModelStatus {
        if ready { progress(1); return .ready }
        for step in stride(from: 0.0, through: 1.0, by: 0.2) {
            progress(step)
            try? await Task.sleep(nanoseconds: 250_000_000)   // visible "downloading" for the UI test
        }
        ready = true
        return .ready
    }

    func embed(_ text: String) async -> [Float]? {
        guard ready else { return nil }
        var hash = 5381
        for byte in text.utf8 { hash = ((hash << 5) &+ hash) &+ Int(byte) }
        let x = Float(abs(hash % 1000)) / 1000
        return NLEmbeddingTextEmbedder.unitNormalized([x, 1 - x, Float((hash >> 3) % 7) / 7])
    }
}
#endif

@main
struct BipboxApplication: App {
    @NSApplicationDelegateAdaptor(BipboxApplicationDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsWorkspaceView(viewModel: appDelegate.settingsViewModel)
                .frame(width: 480, height: 560)
        }
    }
}
