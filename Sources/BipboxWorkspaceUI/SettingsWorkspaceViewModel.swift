import BipboxCore
import Foundation
#if canImport(ServiceManagement)
import ServiceManagement
#endif

/// Controls the macOS "launch at login" item. Abstracted behind a protocol so the
/// view model stays testable — the real implementation needs a signed app bundle.
public protocol LoginItemControlling: Sendable {
    func isEnabled() -> Bool
    func setEnabled(_ enabled: Bool) throws
}

/// Real login-item control via ServiceManagement (`SMAppService.mainApp`).
public struct SMAppServiceLoginItem: LoginItemControlling {
    public init() {}
    public func isEnabled() -> Bool {
        #if canImport(ServiceManagement)
        return SMAppService.mainApp.status == .enabled
        #else
        return false
        #endif
    }
    public func setEnabled(_ enabled: Bool) throws {
        #if canImport(ServiceManagement)
        if enabled { try SMAppService.mainApp.register() }
        else { try SMAppService.mainApp.unregister() }
        #endif
    }
}

/// Settings is a GLOBAL-CONFIG surface only — no runtime status or actions.
/// (Model provisioning lives in the startup banner; re-indexing lives in Sources.)
@MainActor
public final class SettingsWorkspaceViewModel: ObservableObject {
    @Published public private(set) var watchFoldersEnabled: Bool
    @Published public private(set) var launchAtLoginEnabled: Bool
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var isLoading: Bool

    /// Where Bipbox keeps its on-device index (shown read-only).
    public let dataDirectoryURL: URL?

    private let appSettingsStore: AppSettingsStore
    private let loginItem: LoginItemControlling

    public init(
        appSettingsStore: AppSettingsStore = FixtureAppSettingsStore(),
        dataDirectoryURL: URL? = nil,
        loginItem: LoginItemControlling = SMAppServiceLoginItem()
    ) {
        self.appSettingsStore = appSettingsStore
        self.dataDirectoryURL = dataDirectoryURL
        self.loginItem = loginItem
        watchFoldersEnabled = true
        launchAtLoginEnabled = false
        errorMessage = nil
        isLoading = false
    }

    public func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let settings = try await appSettingsStore.load()
            watchFoldersEnabled = settings.automationState == .running
        } catch {
            errorMessage = error.localizedDescription
        }
        launchAtLoginEnabled = loginItem.isEnabled()
        isLoading = false
    }

    public func setWatchFoldersEnabled(_ enabled: Bool) async {
        errorMessage = nil
        watchFoldersEnabled = enabled
        await saveCurrentSettings()
    }

    public func setLaunchAtLoginEnabled(_ enabled: Bool) async {
        errorMessage = nil
        do {
            try loginItem.setEnabled(enabled)
        } catch {
            errorMessage = "Couldn’t update launch at login: \(error.localizedDescription)"
        }
        // Reflect the OS's actual state, not the requested one.
        launchAtLoginEnabled = loginItem.isEnabled()
        await saveCurrentSettings()
    }

    /// Read-modify-write so settings this surface doesn't manage (e.g. the
    /// not-yet-shipped AI configuration) are preserved untouched. Sets an error
    /// only on failure — it never clears one a caller just set.
    private func saveCurrentSettings() async {
        do {
            var settings = (try? await appSettingsStore.load()) ?? .defaults
            settings.automationState = watchFoldersEnabled ? .running : .paused
            settings.launchAtLoginEnabled = launchAtLoginEnabled
            try await appSettingsStore.save(settings)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

public actor FixtureAppSettingsStore: AppSettingsStore {
    private var settings: AppSettings

    public init(settings: AppSettings = .defaults) {
        self.settings = settings
    }

    public func load() async throws -> AppSettings {
        settings
    }

    public func save(_ settings: AppSettings) async throws {
        self.settings = settings
    }
}
