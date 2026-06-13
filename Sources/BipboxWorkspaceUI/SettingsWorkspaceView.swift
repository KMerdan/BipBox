import AppKit
import BipboxCore
import SwiftUI

public struct SettingsWorkspaceView: View {
    @StateObject private var viewModel: SettingsWorkspaceViewModel
    @State private var selectedLibraryRootURL: URL?

    public init(viewModel: SettingsWorkspaceViewModel = SettingsWorkspaceViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        Form {
            Section("Library") {
                folderSelectionRow(
                    placeholder: "No library folder selected",
                    selectedURL: selectedLibraryRootURL ?? viewModel.libraryRoot?.url,
                    chooseTitle: "Choose Library",
                    applyTitle: "Set Library",
                    canApply: selectedLibraryRootURL != nil
                ) {
                    selectedLibraryRootURL = chooseFolder(initialURL: selectedLibraryRootURL ?? viewModel.libraryRoot?.url)
                } apply: {
                    guard let selectedLibraryRootURL else {
                        return
                    }
                    Task {
                        await viewModel.setLibraryRoot(selectedLibraryRootURL)
                        self.selectedLibraryRootURL = nil
                    }
                }

                if let libraryRoot = viewModel.libraryRoot {
                    permissionRow(libraryRoot)
                }
            }

            Section("Automation") {
                HStack {
                    Text("Organizer")
                    Spacer()
                    Text(viewModel.automationState.rawValue.capitalized)
                        .foregroundStyle(.secondary)
                    Button(viewModel.automationState == .running ? "Pause" : "Resume") {
                        if viewModel.automationState == .running {
                            Task { await viewModel.pauseAutomation() }
                        } else {
                            Task { await viewModel.resumeAutomation() }
                        }
                    }
                }

                Toggle("Launch at login", isOn: Binding(
                    get: { viewModel.launchAtLoginEnabled },
                    set: { enabled in
                        Task { await viewModel.setLaunchAtLoginEnabled(enabled) }
                    }
                ))
            }

            Section("Privacy") {
                Toggle("Enable AI agent", isOn: Binding(
                    get: { viewModel.aiEnabled },
                    set: { enabled in
                        Task { await viewModel.setAIEnabled(enabled) }
                    }
                ))
                .accessibilityIdentifier("settings.aiEnabled")

                Picker("Provider", selection: Binding(
                    get: { viewModel.aiProvider },
                    set: { provider in
                        Task { await viewModel.setAIProvider(provider) }
                    }
                )) {
                    ForEach(AIProviderKind.allCases, id: \.self) { provider in
                        Text(provider.rawValue).tag(provider)
                    }
                }

                Toggle("Local-only mode", isOn: Binding(
                    get: { viewModel.aiLocalOnlyModeEnabled },
                    set: { enabled in
                        Task { await viewModel.setAILocalOnlyModeEnabled(enabled) }
                    }
                ))

                Toggle("Metadata-only mode", isOn: Binding(
                    get: { viewModel.aiMetadataOnlyModeEnabled },
                    set: { enabled in
                        Task { await viewModel.setAIMetadataOnlyModeEnabled(enabled) }
                    }
                ))

                Toggle("Allow AI content sharing", isOn: Binding(
                    get: { viewModel.aiContentSharingEnabled },
                    set: { enabled in
                        Task { await viewModel.setAIContentSharingEnabled(enabled) }
                    }
                ))

                Toggle("Audit AI tool calls", isOn: Binding(
                    get: { viewModel.aiAuditLoggingEnabled },
                    set: { enabled in
                        Task { await viewModel.setAIAuditLoggingEnabled(enabled) }
                    }
                ))

                Text(viewModel.aiPrivacySummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Permission Health") {
                Text(viewModel.permissionHealthSummary)
                Text(viewModel.permissionHealthActionHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }

            Section("Diagnostics") {
                Text(viewModel.diagnosticsSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .task {
            await viewModel.load()
        }
    }

    private func folderSelectionRow(
        placeholder: String,
        selectedURL: URL?,
        chooseTitle: String,
        applyTitle: String,
        canApply: Bool,
        choose: @escaping () -> Void,
        apply: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Text(selectedURL?.path ?? placeholder)
                .foregroundStyle(selectedURL == nil ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            Button {
                choose()
            } label: {
                Label(chooseTitle, systemImage: "folder")
            }

            Button {
                apply()
            } label: {
                Label(applyTitle, systemImage: "checkmark")
            }
            .disabled(!canApply)
        }
    }

    private func chooseFolder(initialURL: URL?) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Choose a folder for Bipbox."
        panel.directoryURL = initialURL

        guard panel.runModal() == .OK else {
            return nil
        }
        return panel.url
    }

    private func permissionRow(_ record: PermissionRecord) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(record.url.path)
                    .lineLimit(1)
                Text(record.state.rawValue.capitalized)
                    .font(.caption)
                    .foregroundStyle(record.state == .granted ? Color.secondary : Color.red)
            }
        } icon: {
            Image(systemName: record.state == .granted ? "checkmark.circle" : "exclamationmark.triangle")
        }
    }
}
