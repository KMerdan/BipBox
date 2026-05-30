import AppKit
import BipboxCore
import SwiftUI

public struct ReviewQueueView: View {
    @StateObject private var viewModel: ReviewQueueViewModel
    @State private var destinationPath = ""
    @State private var committedDestinationPath = ""
    @State private var destinationUpdateMessage: String?

    public init(viewModel: ReviewQueueViewModel = ReviewQueueViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        HSplitView {
            queuePane
                .frame(minWidth: 320, idealWidth: 380)

            detailPane
                .frame(minWidth: 560)
        }
        .task {
            await viewModel.load()
            syncDestinationWithSelection()
        }
        .onChange(of: viewModel.selectedItemID) {
            syncDestinationWithSelection()
        }
    }

    private var queuePane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Intake")
                        .font(.headline)
                    Text("\(viewModel.pendingCount) waiting for decision")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if viewModel.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding()

            intakePane
                .padding(.horizontal)
                .padding(.bottom, 12)

            Picker("Decision Filter", selection: $viewModel.filter) {
                ForEach(ReviewQueueFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)

            if let errorMessage = viewModel.errorMessage {
                WorkspaceEmptyState(
                    title: "Intake failed",
                    message: errorMessage,
                    systemImage: "exclamationmark.triangle"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.isEmpty {
                WorkspaceEmptyState(
                    title: "Intake empty",
                    message: "New menu bar drops and watched-folder arrivals that need a decision will appear here.",
                    systemImage: "tray.and.arrow.down"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(viewModel.filteredItems, selection: Binding(
                    get: { viewModel.selectedItemID },
                    set: { viewModel.select(id: $0) }
                )) { item in
                    ReviewQueueRow(item: item)
                        .tag(item.id)
                }
                .listStyle(.sidebar)
            }
        }
    }

    private var intakePane: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Watched Sources", systemImage: "arrow.down.doc")
                .font(.headline)

            Text("Start registers sources. Intake watches them afterward and keeps only new arrivals that need a decision.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if viewModel.watchedFolderStatuses.isEmpty {
                Text("No watched sources. Add Downloads or Desktop from Start.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                HStack {
                    Text(viewModel.watcherStatusSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        Task { await viewModel.scanWatchedFoldersNow() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Scan now")
                    Button {
                        Task { await viewModel.pauseWatchedFolders() }
                    } label: {
                        Image(systemName: "pause")
                    }
                    .help("Pause watchers")
                    Button {
                        Task { await viewModel.resumeWatchedFolders() }
                    } label: {
                        Image(systemName: "play")
                    }
                    .help("Resume watchers")
                }

                ForEach(viewModel.watchedFolderStatuses) { status in
                    HStack(spacing: 8) {
                        Image(systemName: status.statusImage)
                            .foregroundStyle(status.tint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(status.captureLocation?.displayName ?? "Watched Folder")
                                .font(.caption)
                                .fontWeight(.medium)
                            Text(status.url.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Text(status.state.rawValue.capitalized)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var detailPane: some View {
        ScrollView {
            if let item = viewModel.selectedItem {
                VStack(alignment: .leading, spacing: 18) {
                    reviewHeader(item)
                    proposalPanel(item)
                    statusPanel(item)
                    decisionPanel(item)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            } else {
                WorkspaceEmptyState(
                    title: "No item selected",
                    message: "Select an intake item to inspect its proposed action.",
                    systemImage: "tray.and.arrow.down"
                )
                .frame(maxWidth: .infinity, minHeight: 420)
            }
        }
    }

    private func reviewHeader(_ item: ReviewQueueItem) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: item.item.kind.reviewSystemImageName)
                .font(.system(size: 24))
                .foregroundStyle(Color.accentColor)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.item.displayName)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                Text(item.reason)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            Spacer()

            ReviewStatusBadge(status: item.status)
        }
    }

    private func proposalPanel(_ item: ReviewQueueItem) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Proposed action", systemImage: "arrow.triangle.branch")
                .font(.headline)

            ReviewDetailRow(label: "Current location", value: item.item.url.path)
            ReviewDetailRow(label: "Action", value: item.plan.previewText)
            if let expectedResultURL = item.plan.expectedResultURL {
                ReviewDetailRow(label: "Result", value: expectedResultURL.path)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Destination folder for approval")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    TextField("Destination folder", text: $destinationPath)
                        .textFieldStyle(.roundedBorder)
                        .disabled(true)

                    Button {
                        chooseDestinationFolder()
                    } label: {
                        Label("Choose Folder", systemImage: "folder")
                    }
                    .disabled(!viewModel.canDecideSelectedItem || viewModel.isExecuting)

                    Button {
                        viewModel.updateSelectedDestination(destinationPath)
                        committedDestinationPath = destinationPath
                        destinationUpdateMessage = "Proposal updated. The file is not moved until you approve it."
                    } label: {
                        Label("Update Proposal", systemImage: "arrow.triangle.branch")
                    }
                    .disabled(!canUpdateDestinationProposal)
                }

                Text(destinationUpdateMessage ?? "Choose a folder, then update the proposal. The file is not moved until approval.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func statusPanel(_ item: ReviewQueueItem) -> some View {
        if item.message != nil || viewModel.errorMessage != nil || item.status != .pending {
            VStack(alignment: .leading, spacing: 10) {
                Label("Status", systemImage: item.status.statusSystemImage)
                    .font(.headline)
                if let message = item.message {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func decisionPanel(_ item: ReviewQueueItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Decision")
                    .font(.headline)
                Spacer()
                if viewModel.isExecuting {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            HStack(spacing: 10) {
                Button {
                    Task { await viewModel.approveSelected() }
                } label: {
                    Label("Approve", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canDecideSelectedItem || viewModel.isExecuting)

                Button {
                    Task { await viewModel.leaveSelectedInInbox() }
                } label: {
                    Label("Keep for Later", systemImage: "tray")
                }
                .disabled(!viewModel.canDecideSelectedItem || viewModel.isExecuting)

                Button(role: .destructive) {
                    Task { await viewModel.rejectSelected() }
                } label: {
                    Label("Reject", systemImage: "xmark")
                }
                .disabled(!viewModel.canDecideSelectedItem || viewModel.isExecuting)

                Spacer()

                if item.status == .failed {
                    Button {
                        Task { await viewModel.retrySelected() }
                    } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                    }
                    .disabled(viewModel.isExecuting)
                }

                if item.status == .inbox || item.status == .rejected {
                    Button {
                        Task { await viewModel.restoreSelectedForDecision() }
                    } label: {
                        Label("Restore", systemImage: "arrow.uturn.left")
                    }
                    .disabled(viewModel.isExecuting)
                }

                Button {
                    Task { await viewModel.markSelectedHandled() }
                } label: {
                    Label(item.status == .pending ? "Dismiss" : "Remove", systemImage: "archivebox")
                }
                .disabled(viewModel.isExecuting)
            }

            if !viewModel.canDecideSelectedItem {
                Text("This item has already been \(item.status.displayName.lowercased()). Remove it when you no longer need it in Intake.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func syncDestinationWithSelection() {
        guard let item = viewModel.selectedItem else {
            destinationPath = ""
            committedDestinationPath = ""
            destinationUpdateMessage = nil
            return
        }
        destinationPath = destinationFolderPath(for: item)
        committedDestinationPath = destinationPath
        destinationUpdateMessage = nil
    }

    private var canUpdateDestinationProposal: Bool {
        viewModel.canDecideSelectedItem
            && !viewModel.isExecuting
            && !destinationPath.isEmpty
            && destinationPath != committedDestinationPath
    }

    private func chooseDestinationFolder() {
        if let url = chooseFolder(message: "Choose the destination folder for this approval.", initialURL: nil) {
            destinationPath = url.path
            destinationUpdateMessage = destinationPath == committedDestinationPath
                ? "Selected folder matches the current proposal."
                : "Folder selected. Update the proposal to use it."
        }
    }

    private func chooseFolder(message: String, initialURL: URL?) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = message

        if let initialURL {
            panel.directoryURL = initialURL
        } else if !destinationPath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: destinationPath, isDirectory: true)
        }

        guard panel.runModal() == .OK else {
            return nil
        }
        return panel.url
    }

    private func destinationFolderPath(for item: ReviewQueueItem) -> String {
        if let expectedResultURL = item.plan.expectedResultURL {
            return expectedResultURL.deletingLastPathComponent().path
        }

        if let destinationURL = item.plan.operations.first(where: { $0.kind == .move || $0.kind == .copy })?.destinationURL {
            return destinationURL.deletingLastPathComponent().path
        }

        return item.item.url.deletingLastPathComponent().path
    }
}

private struct ReviewQueueRow: View {
    let item: ReviewQueueItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: item.item.kind.reviewSystemImageName)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 18)
                Text(item.item.displayName)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Spacer()
                ReviewStatusBadge(status: item.status)
            }

            Text(item.reason)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 5)
    }
}

private struct ReviewStatusBadge: View {
    let status: ReviewQueueItemStatus

    var body: some View {
        Text(status.displayName)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(status.tint.opacity(0.16))
            .foregroundStyle(status.tint)
            .clipShape(Capsule())
    }
}

private struct ReviewDetailRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout)
                .textSelection(.enabled)
                .lineLimit(3)
        }
    }
}

private extension ReviewQueueItemStatus {
    var displayName: String {
        switch self {
        case .pending: "Pending"
        case .approved: "Approved"
        case .rejected: "Rejected"
        case .inbox: "In Inbox"
        case .failed: "Failed"
        }
    }

    var tint: Color {
        switch self {
        case .pending: .orange
        case .approved: .green
        case .rejected: .red
        case .inbox: .blue
        case .failed: .red
        }
    }

    var statusSystemImage: String {
        switch self {
        case .pending: "hourglass"
        case .approved: "checkmark.circle"
        case .rejected: "xmark.circle"
        case .inbox: "tray"
        case .failed: "exclamationmark.triangle"
        }
    }
}

private extension ItemKind {
    var reviewSystemImageName: String {
        switch self {
        case .file: "doc"
        case .folder: "folder"
        case .package: "shippingbox"
        case .bundle: "app"
        case .symlink: "arrow.triangle.branch"
        case .unknown: "questionmark.square"
        }
    }
}

private extension WatchedFolderStatus {
    var statusImage: String {
        switch state {
        case .running:
            permissionState == .granted ? "checkmark.circle" : "exclamationmark.triangle"
        case .paused:
            "pause.circle"
        case .stopped:
            "stop.circle"
        }
    }

    var tint: Color {
        switch state {
        case .running:
            permissionState == .granted ? .green : .orange
        case .paused:
            .blue
        case .stopped:
            .secondary
        }
    }
}
