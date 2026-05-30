import AppKit
import BipboxCore
import SwiftUI

public struct OnboardingWorkspaceView: View {
    @StateObject private var viewModel: OnboardingWorkspaceViewModel

    public init(viewModel: OnboardingWorkspaceViewModel = OnboardingWorkspaceViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
                .padding(24)

            Divider()

            List {
                Section {
                    if viewModel.sources.isEmpty {
                        Text("No remembered folders yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.sources) { source in
                            SourceRow(
                                source: source,
                                message: viewModel.sourceMessages[source.id],
                                rescanAction: { Task { await viewModel.scanSource(id: source.id) } },
                                pauseResumeAction: {
                                    Task {
                                        if source.enabled {
                                            await viewModel.pauseSource(id: source.id)
                                        } else {
                                            await viewModel.resumeSource(id: source.id)
                                        }
                                    }
                                },
                                changeAction: { chooseReplacement(for: source) },
                                removeAction: { Task { await viewModel.removeWatchedFolder(id: source.id) } }
                            )
                        }
                    }
                } header: {
                    Text("Remembered Sources")
                } footer: {
                    Text("Each source is stored by Bipbox, indexed into Library, and monitored for future top-level arrivals when enabled.")
                }

                Section {
                    ForEach(sourceSelections) { selection in
                        OnboardingFolderRow(
                            selection: selection,
                            chooseAction: { choose(role: selection.role) },
                            skipAction: { viewModel.skip(role: selection.role) }
                        )
                    }
                } header: {
                    Text("Quick Add")
                } footer: {
                    Text("Adding a folder saves access, indexes its current top-level contents, and keeps watching it afterward.")
                }
            }
            .listStyle(.inset)

            Divider()

            footer
                .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await viewModel.load()
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Sources")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Choose the folders Bipbox should remember. A source means one durable place to index now and watch later.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(viewModel.watchedFolderCount) sources")
                    .font(.headline)
                Text(viewModel.isRunning ? "Working" : "Ready")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        HStack {
            if let errorMessage = viewModel.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .lineLimit(2)
            } else if viewModel.isCompleted {
                Label("Sources updated.", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
            } else if viewModel.isLoading {
                Label("Loading sources.", systemImage: "arrow.clockwise")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Sources keep permission state, index status, watch status, and the latest scan result together.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                chooseCustomFolder()
            } label: {
                Label("Add Folder", systemImage: "folder.badge.plus")
            }
            .disabled(viewModel.isRunning)

            Button {
                Task { await viewModel.saveAndScanSelectedFolders() }
            } label: {
                if viewModel.isRunning {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("Apply", systemImage: "checkmark.circle")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isRunning || viewModel.selectedCount == 0)
        }
    }

    private var sourceSelections: [OnboardingFolderSelection] {
        viewModel.selections.filter { $0.role.showsOnStart }
    }

    private func choose(role: OnboardingFolderRole) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Choose \(role.title) as a Bipbox source."

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        viewModel.select(role: role, url: url)
    }

    private func chooseCustomFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Add"
        panel.message = "Choose a folder for Bipbox to remember, index, and watch."

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        Task { await viewModel.addCustomWatchedFolder(url) }
    }

    private func chooseReplacement(for source: SourceRecord) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Replace"
        panel.message = "Choose a replacement source folder."
        panel.directoryURL = source.url

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        Task { await viewModel.replaceWatchedFolder(id: source.id, with: url) }
    }
}

private struct SourceRow: View {
    let source: SourceRecord
    let message: String?
    let rescanAction: () -> Void
    let pauseResumeAction: () -> Void
    let changeAction: () -> Void
    let removeAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.badge.gearshape")
                .font(.title3)
                .frame(width: 28)
                .foregroundStyle(source.healthTint)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(source.displayName)
                        .fontWeight(.medium)
                    Text(source.statusTitle)
                        .font(.caption)
                        .foregroundStyle(source.healthTint)
                }
                Text(source.url?.path ?? "No folder path")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let detail = message ?? source.detailLine {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            Button {
                rescanAction()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Scan now")

            Button {
                pauseResumeAction()
            } label: {
                Image(systemName: source.enabled ? "pause.circle" : "play.circle")
            }
            .help(source.enabled ? "Pause watching" : "Resume watching")

            Button {
                changeAction()
            } label: {
                Image(systemName: "folder")
            }
            .help("Change source folder")

            Button(role: .destructive) {
                removeAction()
            } label: {
                Image(systemName: "trash")
            }
            .help("Remove source")
        }
        .padding(.vertical, 6)
    }
}

private struct OnboardingFolderRow: View {
    let selection: OnboardingFolderSelection
    let chooseAction: () -> Void
    let skipAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: selection.role.systemImage)
                .font(.title3)
                .frame(width: 28)
                .foregroundStyle(selection.state.tint)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(selection.role.title)
                        .fontWeight(.medium)
                    Text(selection.state.title)
                        .font(.caption)
                        .foregroundStyle(selection.state.tint)
                }
                Text(selection.url?.path ?? selection.role.placeholder)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let message = selection.message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if selection.state == .scanning {
                ProgressView()
                    .controlSize(.small)
            }

            Button {
                chooseAction()
            } label: {
                Image(systemName: "folder")
            }
            .help("Choose folder")

            Button {
                skipAction()
            } label: {
                Image(systemName: "minus.circle")
            }
            .help("Skip")
        }
        .padding(.vertical, 6)
    }
}

private extension SourceRecord {
    var statusTitle: String {
        if !enabled {
            return "Paused"
        }
        switch (indexState, watchState) {
        case (.failed, _), (_, .error):
            return "Needs Attention"
        case (_, .permissionNeeded):
            return "Permission Needed"
        case (_, .missing):
            return "Missing"
        case (.running, _):
            return "Indexing"
        case (.completed, .running):
            return "Watching"
        case (.completed, _):
            return "Indexed"
        case (.pending, _):
            return "Pending"
        }
    }

    var detailLine: String? {
        if let summary = lastScanSummary {
            let count = summary.indexedCount
            let base = count == 1 ? "1 item indexed" : "\(count) items indexed"
            if let message = summary.message {
                return "\(base). \(message)"
            }
            return base
        }
        return "Policy: top-level items only."
    }

    var healthTint: Color {
        if !enabled {
            return .secondary
        }
        switch (indexState, watchState) {
        case (.failed, _), (_, .error), (_, .missing):
            return .red
        case (_, .permissionNeeded):
            return .orange
        case (.running, _), (.pending, _):
            return .blue
        case (.completed, .running), (.completed, .stopped):
            return .green
        case (.completed, .paused):
            return .secondary
        }
    }
}

private extension OnboardingFolderRole {
    var showsOnStart: Bool {
        switch self {
        case .downloads, .desktop, .documents, .projectFolder:
            true
        case .libraryRoot:
            false
        }
    }

    var systemImage: String {
        switch self {
        case .libraryRoot: "books.vertical"
        case .downloads: "arrow.down.circle"
        case .desktop: "macwindow"
        case .documents: "doc.text"
        case .projectFolder: "folder.badge.gearshape"
        }
    }

    var placeholder: String {
        switch self {
        case .libraryRoot: "Choose where Bipbox keeps its library index."
        case .downloads: "Choose Downloads to capture new files."
        case .desktop: "Choose Desktop to capture loose work."
        case .documents: "Choose Documents for shallow indexing."
        case .projectFolder: "Choose one active project folder."
        }
    }
}

private extension OnboardingFolderState {
    var title: String {
        switch self {
        case .pending: "Pending"
        case .selected: "Selected"
        case .skipped: "Skipped"
        case .saved: "Saved"
        case .scanning: "Scanning"
        case .completed: "Added"
        case .failed: "Failed"
        }
    }

    var tint: Color {
        switch self {
        case .pending: .secondary
        case .selected, .saved, .scanning: .blue
        case .skipped: .secondary
        case .completed: .green
        case .failed: .red
        }
    }
}
