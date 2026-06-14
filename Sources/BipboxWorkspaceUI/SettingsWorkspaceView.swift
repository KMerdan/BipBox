import AppKit
import BipboxCore
import SwiftUI

/// Bipbox settings — a global-config surface only. No runtime status or actions
/// live here: model provisioning is in the startup banner, re-indexing is in
/// Sources, and watched folders are managed from the sidebar.
public struct SettingsWorkspaceView: View {
    @StateObject private var viewModel: SettingsWorkspaceViewModel
    @AppStorage(AppAppearance.storageKey) private var appearanceRaw = AppAppearance.system.rawValue

    public init(viewModel: SettingsWorkspaceViewModel = SettingsWorkspaceViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        Form {
            Section("General") {
                Toggle(isOn: Binding(
                    get: { viewModel.watchFoldersEnabled },
                    set: { enabled in Task { await viewModel.setWatchFoldersEnabled(enabled) } }
                )) {
                    Text("Watch folders for new files")
                    Text("Automatically index new files as they appear in your sources.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("settings.watchFolders")

                Toggle("Launch Bipbox at login", isOn: Binding(
                    get: { viewModel.launchAtLoginEnabled },
                    set: { enabled in Task { await viewModel.setLaunchAtLoginEnabled(enabled) } }
                ))
                .accessibilityIdentifier("settings.launchAtLogin")

                Picker("Appearance", selection: $appearanceRaw) {
                    ForEach(AppAppearance.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
                .accessibilityIdentifier("settings.appearance")
            }

            Section("Intelligence") {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AI agent").foregroundStyle(.secondary)
                        Text("Ask questions and let Bipbox act on your files — coming soon.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("Coming soon")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.15), in: Capsule())
                        .foregroundStyle(.secondary)
                }
            }

            Section("Data") {
                LabeledContent("On-device index") {
                    HStack(spacing: 8) {
                        Text(viewModel.dataDirectoryURL?.path ?? "Default location")
                            .lineLimit(1).truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        if let url = viewModel.dataDirectoryURL {
                            Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                                .accessibilityIdentifier("settings.revealData")
                        }
                    }
                }
                Text("Your files are never moved or uploaded — everything runs on this Mac.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("About") {
                LabeledContent("Version", value: Self.appVersion)
            }

            if let errorMessage = viewModel.errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .accessibilityIdentifier("settings.root")
        .task { await viewModel.load() }
    }

    private static var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        switch (short, build) {
        case let (v?, b?): return "\(v) (\(b))"
        case let (v?, nil): return v
        default: return "—"
        }
    }
}
