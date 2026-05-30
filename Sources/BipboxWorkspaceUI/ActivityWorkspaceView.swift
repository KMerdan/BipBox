import BipboxCore
import SwiftUI

public struct ActivityWorkspaceView: View {
    @StateObject private var viewModel: ActivityWorkspaceViewModel

    public init(viewModel: ActivityWorkspaceViewModel = ActivityWorkspaceViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        HSplitView {
            listPane
                .frame(minWidth: 360)

            detailPane
                .frame(minWidth: 480)
        }
        .task {
            await viewModel.loadRecent()
        }
    }

    private var listPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Activity")
                    .font(.headline)
                Spacer()
                if viewModel.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding()

            VStack(spacing: 8) {
                Picker("Kind", selection: $viewModel.filter) {
                    ForEach(ActivityAuditKind.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.menu)

                HStack {
                    TextField("Item", text: $viewModel.itemFilterText)
                        .textFieldStyle(.roundedBorder)
                    TextField("Source", text: $viewModel.sourceFilterText)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)

            if viewModel.renderedEvents.isEmpty {
                WorkspaceEmptyState(
                    title: "No activity",
                    message: "Organization events will appear here.",
                    systemImage: "clock"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(viewModel.renderedEvents, selection: Binding(
                    get: { viewModel.selectedEventID },
                    set: { viewModel.select(id: $0) }
                )) { event in
                    VStack(alignment: .leading, spacing: 4) {
                        Label(event.title, systemImage: event.isFailure ? "xmark.octagon" : "checkmark.circle")
                            .fontWeight(.medium)
                        Text(event.auditKind.title)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(event.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        if event.isReversible {
                            Text("Undo available")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(event.id)
                }
                .listStyle(.sidebar)
            }
        }
    }

    private var detailPane: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let event = viewModel.selectedEventViewData {
                Text(event.title)
                    .font(.title3)
                    .fontWeight(.semibold)

                metadataRow("Message", event.detail)
                metadataRow("Occurred", event.occurredAt.formatted(date: .abbreviated, time: .standard))
                if let operationKind = event.operationKind {
                    metadataRow("Undo Operation", operationKind.rawValue)
                }
                if let itemPath = event.itemPath {
                    metadataRow("Item", itemPath)
                }
                ForEach(event.contextRows, id: \.label) { row in
                    metadataRow(row.label, row.value)
                }
                if let errorMessage = viewModel.errorMessage {
                    metadataRow("Error", errorMessage)
                }
                if let undoMessage = viewModel.undoMessage {
                    metadataRow("Undo", undoMessage)
                }

                Button("Undo") {
                    Task { await viewModel.undoSelected() }
                }
                .disabled(!viewModel.canUndoSelectedEvent)
            } else {
                WorkspaceEmptyState(
                    title: "Select an event",
                    message: "Activity details and undo actions appear here.",
                    systemImage: "clock"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Spacer()
        }
        .padding()
    }

    private func metadataRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
                .lineLimit(4)
        }
    }
}
