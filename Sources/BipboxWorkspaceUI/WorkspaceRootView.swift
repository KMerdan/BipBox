import BipboxCore
import SwiftUI

@MainActor
public struct WorkspaceViewModels {
    public var onboarding: OnboardingWorkspaceViewModel
    public var library: SearchWorkspaceViewModel
    public var rules: RulesWorkspaceViewModel
    public var reviewQueue: ReviewQueueViewModel
    public var activity: ActivityWorkspaceViewModel
    public var settings: SettingsWorkspaceViewModel

    public init(
        onboarding: OnboardingWorkspaceViewModel = OnboardingWorkspaceViewModel(),
        library: SearchWorkspaceViewModel = .fixture(statusFilter: .all),
        rules: RulesWorkspaceViewModel = RulesWorkspaceViewModel(),
        reviewQueue: ReviewQueueViewModel = ReviewQueueViewModel(),
        activity: ActivityWorkspaceViewModel = ActivityWorkspaceViewModel(),
        settings: SettingsWorkspaceViewModel = SettingsWorkspaceViewModel()
    ) {
        self.onboarding = onboarding
        self.library = library
        self.rules = rules
        self.reviewQueue = reviewQueue
        self.activity = activity
        self.settings = settings
    }
}

/// Fixed 3-column shell (sidebar 252 · center flex · inspector 344). Only the
/// CENTER + INSPECTOR *content* swap on navigation; column widths never change.
public struct WorkspaceRootView: View {
    @StateObject private var model: WorkspaceModel
    @State private var appearance: ColorScheme? = nil
    @State private var isDropTargeted = false
    /// Opens the macOS Settings scene (wired by the app; Cmd+, also works).
    private let openSettings: () -> Void

    @MainActor
    public init(
        viewModels: WorkspaceViewModels = WorkspaceViewModels(),
        graphServices: WorkspaceGraphServices? = nil,
        openSettings: @escaping () -> Void = { NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) },
        onDropURLs: @escaping ([URL]) -> Void = { _ in }
    ) {
        let model = WorkspaceModel(viewModels, graphServices: graphServices)
        model.onDropURLs = onDropURLs
        _model = StateObject(wrappedValue: model)
        self.openSettings = openSettings
    }

    /// Use a pre-built model (so the app can share one instance with the control
    /// API / automation harness).
    @MainActor
    public init(
        model: WorkspaceModel,
        openSettings: @escaping () -> Void = { NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) }
    ) {
        _model = StateObject(wrappedValue: model)
        self.openSettings = openSettings
    }

    public var body: some View {
        HStack(spacing: 0) {
            SidebarView(onOpenSettings: openSettings)
                .frame(width: 252)

            VStack(spacing: 0) {
                WorkspaceToolbar(appearance: $appearance)
                Divider().overlay(BB.hair)
                HStack(spacing: 0) {
                    CenterColumn()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Divider().overlay(BB.hair)
                    InspectorView()
                        .frame(width: 344)
                        .background(BB.panel)
                }
            }
            .background(BB.content)
        }
        .frame(minWidth: 1040, minHeight: 680)
        .environmentObject(model)
        .preferredColorScheme(appearance)
        .task { await model.loadInitial() }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            loadDroppedURLs(providers)
            return true
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(BB.accent, style: StrokeStyle(lineWidth: 2, dash: [8]))
                    .background(BB.accent.opacity(0.06))
                    .overlay(Label("Drop to capture", systemImage: "tray.and.arrow.down")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(BB.accent))
                    .allowsHitTesting(false)
                    .padding(8)
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                Label(toast, systemImage: "checkmark")
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 18).padding(.vertical, 11)
                    .background(BB.ink, in: RoundedRectangle(cornerRadius: 11))
                    .foregroundStyle(BB.content)
                    .padding(.bottom, 22)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.toast)
    }

    private func loadDroppedURLs(_ providers: [NSItemProvider]) {
        let group = DispatchGroup()
        var urls: [URL] = []
        let lock = NSLock()
        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { lock.lock(); urls.append(url); lock.unlock() }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            model.receiveDroppedURLs(urls)
        }
    }
}

// MARK: - Toolbar

private struct WorkspaceToolbar: View {
    @EnvironmentObject var model: WorkspaceModel
    @Binding var appearance: ColorScheme?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 10) {
            ForEach(["sidebar.left", "chevron.left", "chevron.right"], id: \.self) { s in
                ToolbarButton(symbol: s) {}
            }
            searchField
            Spacer(minLength: 8)
            if model.presentation == .connections && !model.isSearching && model.section.isLibraryLike { groupByMenu }
            if model.section.isLibraryLike || model.isSearching { viewToggle }
            ToolbarButton(symbol: (appearance ?? scheme) == .dark ? "sun.max" : "moon") {
                appearance = (appearance ?? scheme) == .dark ? .light : .dark
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .background(BB.sidebar)
    }

    /// The quiet "Group by" switch — unobtrusive, defaults to Smart.
    private var groupByMenu: some View {
        Menu {
            ForEach(LibraryLens.allCases) { lens in
                Button { model.setLens(lens) } label: {
                    if model.lens == lens { Label(lens.title, systemImage: "checkmark") } else { Text(lens.title) }
                }
            }
        } label: {
            Label("Group: \(model.lens.title)", systemImage: "circle.grid.2x2")
                .font(.system(size: 12, weight: .medium)).foregroundStyle(BB.ink2)
                .padding(.horizontal, 9).frame(height: 26)
                .background(BB.chipBg, in: RoundedRectangle(cornerRadius: 7))
        }
        .menuStyle(.borderlessButton).fixedSize()
        .accessibilityIdentifier("toolbar.groupby")
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: model.isSearching ? "magnifyingglass" : "sparkles")
                .font(.system(size: 13)).foregroundStyle(model.isSearching ? BB.ink2 : BB.accent)
            TextField("Ask or search your files…", text: $model.query)
                .textFieldStyle(.plain).font(.system(size: 13)).foregroundStyle(BB.ink)
                .onSubmit { Task { await model.runSearch() } }
                .accessibilityIdentifier("toolbar.search")
            if model.isSearching {
                Button { model.clearSearch() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(BB.ink3)
                }.buttonStyle(.plain)
            } else {
                Text("⌘K").font(.system(size: 11)).foregroundStyle(BB.ink3)
            }
        }
        .padding(.horizontal, 10).frame(height: 30).frame(maxWidth: 460)
        .background(BB.field, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(model.isSearching ? BB.accent : BB.hairStrong, lineWidth: 0.5))
    }

    private var viewToggle: some View {
        HStack(spacing: 2) {
            seg(.gallery, model.isSearching ? "Results" : "Gallery", model.isSearching ? "list.bullet" : "square.grid.2x2")
            seg(.connections, model.isSearching ? "Map" : "Connections", "point.3.connected.trianglepath.dotted")
        }
        .padding(2).background(BB.chipBg, in: RoundedRectangle(cornerRadius: 8))
    }

    private func seg(_ m: LibraryPresentation, _ label: String, _ symbol: String) -> some View {
        Button { model.setPresentation(m) } label: {
            Label(label, systemImage: symbol).font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 11).frame(height: 26)
                .background(model.presentation == m ? BB.content : .clear, in: RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(model.presentation == m ? BB.ink : BB.ink2)
        }.buttonStyle(.plain)
        .accessibilityIdentifier("toolbar.toggle.\(m.rawValue)")
    }
}

struct ToolbarButton: View {
    let symbol: String
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 15)).foregroundStyle(hover ? BB.ink : BB.ink2)
                .frame(width: 28, height: 28)
                .background(hover ? BB.rowHover : .clear, in: RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(.plain).onHover { hover = $0 }
    }
}

// MARK: - Center column (swaps content by section / search)

private struct CenterColumn: View {
    @EnvironmentObject var model: WorkspaceModel
    var body: some View {
        Group {
            if model.isSearching {
                SearchView()
            } else {
                switch model.section {
                case .sources: SourcesView(vm: model.onboarding)
                case .rules: RulesView()
                case .activity: ActivityView()
                case .inbox: LibraryCenterView(forceList: true)
                default: LibraryCenterView(forceList: false)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
