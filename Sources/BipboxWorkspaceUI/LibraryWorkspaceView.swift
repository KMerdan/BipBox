import AppKit
import BipboxCore
import SwiftUI

public struct LibraryWorkspaceView: View {
    @StateObject private var viewModel: SearchWorkspaceViewModel
    @State private var pendingSearchTask: Task<Void, Never>?

    public init(viewModel: SearchWorkspaceViewModel = .fixture(statusFilter: .all)) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        VStack(spacing: 0) {
            libraryControls
                .padding()

            Divider()

            HSplitView {
                resultsPane
                    .frame(minWidth: 360)

                detailPane
                    .frame(minWidth: 360)
            }
        }
        .task {
            await viewModel.search()
        }
        .onChange(of: viewModel.searchText) {
            scheduleSearch()
        }
        .onChange(of: viewModel.kindFilter) {
            scheduleSearch(delay: 0)
        }
        .onChange(of: viewModel.statusFilter) {
            scheduleSearch(delay: 0)
        }
        .onChange(of: viewModel.mode) {
            scheduleSearch(delay: 0)
        }
        .onChange(of: viewModel.typeFilterText) {
            scheduleSearch()
        }
        .onChange(of: viewModel.tagFilterText) {
            scheduleSearch()
        }
        .onChange(of: viewModel.collectionFilterText) {
            scheduleSearch()
        }
        .onChange(of: viewModel.sourceFilterText) {
            scheduleSearch()
        }
        .onDisappear {
            pendingSearchTask?.cancel()
            pendingSearchTask = nil
        }
    }

    private var libraryControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Library")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("\(viewModel.totalCount) item(s)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if viewModel.isSearching {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            HStack(spacing: 8) {
                TextField("Search library", text: $viewModel.searchText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        runSearchNow()
                    }

                Button {
                    runSearchNow()
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .keyboardShortcut(.return, modifiers: .command)
            }

            HStack(spacing: 8) {
                Picker("Mode", selection: $viewModel.mode) {
                    ForEach(LibraryMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 420)
            }

            HStack(spacing: 8) {
                Picker("Kind", selection: $viewModel.kindFilter) {
                    ForEach(SearchKindFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 320)

                Picker("Status", selection: $viewModel.statusFilter) {
                    ForEach(SearchStatusFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 180)

                TextField("Type identifiers", text: $viewModel.typeFilterText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                    .onSubmit {
                        runSearchNow()
                    }

                TextField("Tags", text: $viewModel.tagFilterText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                    .onSubmit {
                        runSearchNow()
                    }

                TextField("Collection", text: $viewModel.collectionFilterText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 150)
                    .onSubmit {
                        runSearchNow()
                    }

                TextField("Source", text: $viewModel.sourceFilterText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 130)
                    .onSubmit {
                        runSearchNow()
                    }
            }
        }
    }

    private var resultsPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let errorMessage = viewModel.errorMessage {
                WorkspaceEmptyState(
                    title: "Library failed",
                    message: errorMessage,
                    systemImage: "exclamationmark.triangle"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !viewModel.hasResults {
                WorkspaceEmptyState(
                    title: "No items",
                    message: "Try a different search or filter.",
                    systemImage: "folder"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(viewModel.results) { item in
                    Button {
                        viewModel.select(item)
                        if viewModel.mode == .related {
                            Task { await viewModel.loadRelatedForSelected() }
                        } else if viewModel.mode == .contexts {
                            Task { await viewModel.loadContextForSelected() }
                        }
                    } label: {
                        LibraryResultRow(
                            item: item,
                            explanation: viewModel.matchExplanation(for: item),
                            isSelected: viewModel.selectedItem?.id == item.id
                        )
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.inset)
            }
        }
    }

    private var detailPane: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let item = viewModel.selectedItem {
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: item.kind.systemImageName)
                    Text(item.displayName)
                        .font(.title3)
                        .fontWeight(.semibold)
                    Spacer()
                }

                metadataRow("Kind", item.kind.rawValue.capitalized)
                metadataRow("Status", item.status.title)
                metadataRow("Path", item.currentPath)
                if let originalPath = item.originalPath {
                    metadataRow("Original", originalPath)
                }
                if let uniformTypeIdentifier = item.uniformTypeIdentifier {
                    metadataRow("Type", uniformTypeIdentifier)
                }
                if !item.tags.isEmpty {
                    metadataRow("Tags", item.tags.joined(separator: ", "))
                }
                metadataRow("Why", viewModel.matchExplanation(for: item))

                if viewModel.mode == .related {
                    relatedItemsSection
                }
                if viewModel.mode == .contexts {
                    contextSection
                }

                HStack {
                    Button("Open") {
                        viewModel.openSelectedItem()
                    }
                    Button("Reveal") {
                        viewModel.revealSelectedItem()
                    }
                    Button("Copy Path") {
                        viewModel.copySelectedPath()
                    }
                    Button("Related") {
                        Task { await viewModel.showRelatedForSelected() }
                    }
                }
                .padding(.top, 4)

                HStack {
                    Button("Reindex") {
                        Task { await viewModel.reindexSelectedItem() }
                    }
                    Button("Refresh Status") {
                        Task { await viewModel.refreshSelectedItemStatus() }
                    }
                    Button("Locate") {
                        locateSelectedItem()
                    }
                    Button("Remove") {
                        Task { await viewModel.removeSelectedItemFromLibrary() }
                    }
                }
            } else {
                WorkspaceEmptyState(
                    title: "Select an item",
                    message: "File and folder details appear here.",
                    systemImage: "sidebar.right"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Spacer()
        }
        .padding()
    }

    @ViewBuilder
    private var relatedItemsSection: some View {
        if viewModel.relatedItems.isEmpty {
            metadataRow("Related", "No related items loaded.")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Related")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(viewModel.relatedItems, id: \.item.id) { related in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(related.item.displayName)
                            .font(.callout)
                        Text(related.explanations.joined(separator: " | "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var contextSection: some View {
        if let overview = viewModel.relatedContextOverview {
            VStack(alignment: .leading, spacing: 8) {
                metadataRow("Context", overview.explanations.joined(separator: " "))

                if !overview.contexts.isEmpty {
                    Text("Contexts")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(overview.contexts, id: \.relationship.id) { context in
                        Text("\(context.context.kind.rawValue): \(context.context.name)")
                            .font(.callout)
                    }
                }

                if !overview.collections.isEmpty {
                    Text("Collections")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(overview.collections, id: \.id) { collection in
                        Text(collection.name)
                            .font(.callout)
                    }
                }
            }
        } else {
            metadataRow("Context", "No related context loaded.")
        }
    }

    private func metadataRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
                .lineLimit(3)
        }
    }

    private func runSearchNow() {
        pendingSearchTask?.cancel()
        pendingSearchTask = nil
        Task { await viewModel.search() }
    }

    private func scheduleSearch(delay: UInt64 = 300_000_000) {
        pendingSearchTask?.cancel()
        pendingSearchTask = Task {
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
            }
            guard !Task.isCancelled else {
                return
            }
            await viewModel.search()
        }
    }

    private func locateSelectedItem() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Locate"
        panel.message = "Choose the current file or folder location."

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        Task { await viewModel.locateSelectedItem(at: url) }
    }
}

private struct LibraryResultRow: View {
    let item: IndexedItem
    let explanation: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.kind.systemImageName)
                .frame(width: 20)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayName)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .lineLimit(1)
                Text(item.currentPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(item.status.title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

private extension ItemKind {
    var systemImageName: String {
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

private extension IndexedItemStatus {
    var title: String {
        switch self {
        case .organized: "Organized"
        case .needsReview: "Needs Review"
        case .indexedOnly: "Indexed Only"
        case .missing: "Missing"
        case .failed: "Failed"
        }
    }
}
