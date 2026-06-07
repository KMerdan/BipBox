// SourcesView.swift — the source-management surface (the north star's "Start").
// "These are the places Bipbox remembers from." Reuses OnboardingWorkspaceViewModel,
// which is fully wired to the real SourceLifecycleCoordinator.
import SwiftUI
import BipboxCore

struct SourcesView: View {
    @EnvironmentObject var model: WorkspaceModel
    @ObservedObject var vm: OnboardingWorkspaceViewModel

    var body: some View {
        VStack(spacing: 0) {
            CenterHeader(title: "Watched Folders",
                         sub: "These are the places Bipbox remembers from.") {
                PillButton("Add Folder", system: "plus", kind: .primary) { model.addWatchedFolderViaPanel() }
                    .accessibilityIdentifier("sources.addFolder")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if vm.sources.isEmpty { firstRunBanner }

                    if !vm.sources.isEmpty {
                        sectionLabel("Remembered sources")
                        VStack(spacing: 8) {
                            ForEach(vm.sources) { SourceManagerRow(source: $0, vm: vm) }
                        }
                    }

                    sectionLabel("Quick add")
                    VStack(spacing: 8) {
                        ForEach(quickRoles) { role in QuickAddRow(role: role, vm: vm) }
                    }
                }
                .padding(.horizontal, 22).padding(.bottom, 20)
            }.scrollIndicators(.hidden)
        }
        .task { await vm.load() }
    }

    private var quickRoles: [OnboardingFolderRole] {
        [.downloads, .desktop, .documents, .projectFolder]
    }

    private var firstRunBanner: some View {
        WhyBox(lead: "Start by adding a folder",
               symbol: "folder.badge.plus",
               text: "Pick Downloads, Desktop, or any folder. Bipbox indexes what's already inside, then remembers new arrivals — nothing moves unless you ask.",
               tint: BB.accent, bg: BB.info.opacity(0.13))
    }

    private func sectionLabel(_ t: String) -> some View {
        Text(t.uppercased()).font(BB.groupHead).tracking(0.4).foregroundStyle(BB.ink3)
    }
}

private struct SourceManagerRow: View {
    @EnvironmentObject var model: WorkspaceModel
    let source: SourceRecord
    @ObservedObject var vm: OnboardingWorkspaceViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 11) {
                Image(systemName: "folder.fill").font(.system(size: 16)).foregroundStyle(BBPalette.color(for: source.id))
                    .frame(width: 34, height: 34).background(BB.chipBg, in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 2) {
                    Button { model.go(.source(source.id)) } label: {
                        Text(source.displayName).font(.system(size: 14, weight: .semibold)).foregroundStyle(BB.ink)
                    }.buttonStyle(.plain)
                    Text(source.url?.path ?? "—").font(BB.mono).foregroundStyle(BB.ink3).lineLimit(1)
                }
                Spacer()
                StatusPill(text: statusText, tint: statusTint).accessibilityIdentifier("source.status")
            }
            HStack(spacing: 12) {
                Text(scanSummary).font(.system(size: 11.5)).foregroundStyle(BB.ink2)
                Spacer()
                actionButton("Rescan", "arrow.clockwise") { Task { await vm.scanSource(id: source.id); await model.refresh() } }
                    .accessibilityIdentifier("source.rescan")
                actionButton(source.enabled ? "Pause" : "Resume", source.enabled ? "pause" : "play") {
                    Task { source.enabled ? await vm.pauseSource(id: source.id) : await vm.resumeSource(id: source.id); await model.refresh() }
                }
                .accessibilityIdentifier("source.pauseResume")
                actionButton("Remove", "trash") { Task { await vm.removeWatchedFolder(id: source.id); await model.refresh() } }
                    .accessibilityIdentifier("source.remove")
            }
            if let msg = vm.sourceMessages[source.id] {
                Text(msg).font(.system(size: 11)).foregroundStyle(BB.ink3)
            }
        }
        .padding(13)
        .background(BB.panel, in: RoundedRectangle(cornerRadius: BB.rCard))
        .overlay(RoundedRectangle(cornerRadius: BB.rCard).strokeBorder(BB.hair, lineWidth: 0.5))
    }

    private func actionButton(_ title: String, _ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(title == "Remove" ? BB.bad : BB.ink2)
        }.buttonStyle(.plain)
    }

    private var statusText: String {
        if !source.enabled { return "Paused" }
        switch source.watchState {
        case .running: return "Watching"
        case .paused: return "Paused"
        case .permissionNeeded: return "Permission"
        case .missing: return "Missing"
        case .error: return "Error"
        case .stopped: return "Stopped"
        }
    }
    private var statusTint: Color {
        switch source.watchState {
        case .running where source.enabled: return BB.good
        case .permissionNeeded, .missing, .error: return BB.bad
        default: return BB.ink3
        }
    }
    private var scanSummary: String {
        if let s = source.lastScanSummary {
            return s.message ?? "\(s.indexedCount) indexed"
        }
        return "Not scanned yet"
    }
}

private struct QuickAddRow: View {
    @EnvironmentObject var model: WorkspaceModel
    let role: OnboardingFolderRole
    @ObservedObject var vm: OnboardingWorkspaceViewModel

    private var selection: OnboardingFolderSelection? {
        vm.selections.first { $0.role == role }
    }
    private var alreadyAdded: Bool {
        selection?.state == .completed
    }

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: symbol).font(.system(size: 15)).foregroundStyle(BB.ink2)
                .frame(width: 34, height: 34).background(BB.chipBg, in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 2) {
                Text(role.title).font(.system(size: 14, weight: .medium)).foregroundStyle(BB.ink)
                if let msg = selection?.message {
                    Text(msg).font(.system(size: 11)).foregroundStyle(BB.ink3).lineLimit(1)
                }
            }
            Spacer()
            if alreadyAdded {
                Label("Added", systemImage: "checkmark").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(BB.good)
            } else {
                PillButton("Add") { add() }
            }
        }
        .padding(.horizontal, 13).padding(.vertical, 10)
        .background(BB.panel, in: RoundedRectangle(cornerRadius: BB.rCard))
        .overlay(RoundedRectangle(cornerRadius: BB.rCard).strokeBorder(BB.hair, lineWidth: 0.5))
    }

    private var symbol: String {
        switch role {
        case .downloads: "arrow.down.circle"
        case .desktop: "menubar.dock.rectangle"
        case .documents: "doc.on.doc"
        case .projectFolder, .libraryRoot: "folder"
        }
    }

    private func add() {
        // Prefer the well-known URL for common roles; fall back to a picker.
        let url = Self.defaultURL(for: role) ?? WorkspaceModel.chooseFolder()
        guard let url else { return }
        guard let policy = WorkspaceModel.askIndexDepth(for: url) else { return }
        Task { await vm.addPresetWatchedFolder(role: role, url: url, recursivePolicy: policy); await model.refresh() }
    }

    static func defaultURL(for role: OnboardingFolderRole) -> URL? {
        let fm = FileManager.default
        switch role {
        case .downloads: return fm.urls(for: .downloadsDirectory, in: .userDomainMask).first
        case .desktop: return fm.urls(for: .desktopDirectory, in: .userDomainMask).first
        case .documents: return fm.urls(for: .documentDirectory, in: .userDomainMask).first
        case .projectFolder, .libraryRoot: return nil
        }
    }
}
