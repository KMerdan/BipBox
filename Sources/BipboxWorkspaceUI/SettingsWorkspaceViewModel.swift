import BipboxCore
import Foundation

@MainActor
public final class SettingsWorkspaceViewModel: ObservableObject {
    @Published public private(set) var libraryRoot: PermissionRecord?
    @Published public private(set) var automationState: AutomationState
    @Published public private(set) var launchAtLoginEnabled: Bool
    @Published public private(set) var aiEnabled: Bool
    @Published public private(set) var aiProvider: AIProviderKind
    @Published public private(set) var aiLocalOnlyModeEnabled: Bool
    @Published public private(set) var aiContentSharingEnabled: Bool
    @Published public private(set) var aiMetadataOnlyModeEnabled: Bool
    @Published public private(set) var aiAuditLoggingEnabled: Bool
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var isLoading: Bool

    private let permissionStore: PermissionStore
    private let appSettingsStore: AppSettingsStore

    public init(
        permissionStore: PermissionStore = FixturePermissionStore(),
        appSettingsStore: AppSettingsStore = FixtureAppSettingsStore()
    ) {
        self.permissionStore = permissionStore
        self.appSettingsStore = appSettingsStore
        libraryRoot = nil
        automationState = .running
        launchAtLoginEnabled = false
        aiEnabled = false
        aiProvider = .none
        aiLocalOnlyModeEnabled = true
        aiContentSharingEnabled = false
        aiMetadataOnlyModeEnabled = true
        aiAuditLoggingEnabled = true
        errorMessage = nil
        isLoading = false
    }

    public var permissionHealthSummary: String {
        let records = [libraryRoot].compactMap { $0 }
        guard !records.isEmpty else {
            return "No library storage folder configured."
        }

        let unhealthy = records.filter { $0.state != .granted }
        return unhealthy.isEmpty ? "All permissions healthy." : "\(unhealthy.count) permission issue(s)."
    }

    public var permissionHealthActionHint: String {
        if libraryRoot == nil {
            return "Use Library to choose storage; use Start to add remembered source folders."
        }
        if libraryRoot?.state != .granted {
            return "Refresh storage permission here. Source permissions are managed from Start; missing files are recovered from Library."
        }
        return "Source permissions are managed from Start. Missing files are recovered from Library."
    }

    public var aiPrivacySummary: String {
        if !aiEnabled {
            return "AI is off. Tools remain available locally for future agent planning."
        }
        if aiLocalOnlyModeEnabled {
            return "AI is local-only. Remote providers cannot receive file content."
        }
        if aiMetadataOnlyModeEnabled {
            return "AI may use \(aiProvider.rawValue), but only metadata can leave the device."
        }
        return aiContentSharingEnabled
            ? "AI may use \(aiProvider.rawValue) with explicit content sharing enabled."
            : "AI provider access is enabled, but content sharing is off."
    }

    public var diagnosticsSummary: String {
        "Activity contains the audit trail for capture, indexing, decisions, filesystem operations, and tool calls."
    }

    public func load() async {
        isLoading = true
        errorMessage = nil

        do {
            libraryRoot = try await permissionStore.records(scope: .libraryRoot).first
            applySettings(try await appSettingsStore.load())
        } catch {
            libraryRoot = nil
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    public func setLibraryRoot(_ url: URL, state: PermissionState = .missing) async {
        let record = PermissionRecord(scope: .libraryRoot, url: url, state: state)
        await save(record)
        libraryRoot = record
    }

    public func pauseAutomation() async {
        await setAutomationState(.paused)
    }

    public func resumeAutomation() async {
        await setAutomationState(.running)
    }

    public func setAutomationState(_ state: AutomationState) async {
        automationState = state
        await saveCurrentSettings()
    }

    public func setLaunchAtLoginEnabled(_ enabled: Bool) async {
        launchAtLoginEnabled = enabled
        await saveCurrentSettings()
    }

    public func setAIEnabled(_ enabled: Bool) async {
        aiEnabled = enabled
        if !enabled {
            aiProvider = .none
            aiLocalOnlyModeEnabled = true
            aiContentSharingEnabled = false
            aiMetadataOnlyModeEnabled = true
        }
        await saveCurrentSettings()
    }

    public func setAIProvider(_ provider: AIProviderKind) async {
        aiProvider = provider
        aiEnabled = provider != .none
        if provider == .none {
            aiLocalOnlyModeEnabled = true
            aiContentSharingEnabled = false
            aiMetadataOnlyModeEnabled = true
        }
        await saveCurrentSettings()
    }

    public func setAILocalOnlyModeEnabled(_ enabled: Bool) async {
        aiLocalOnlyModeEnabled = enabled
        if enabled {
            aiContentSharingEnabled = false
            aiMetadataOnlyModeEnabled = true
        }
        await saveCurrentSettings()
    }

    public func setAIContentSharingEnabled(_ enabled: Bool) async {
        aiContentSharingEnabled = enabled
        if enabled {
            aiLocalOnlyModeEnabled = false
            aiMetadataOnlyModeEnabled = false
        }
        await saveCurrentSettings()
    }

    public func setAIMetadataOnlyModeEnabled(_ enabled: Bool) async {
        aiMetadataOnlyModeEnabled = enabled
        if enabled {
            aiContentSharingEnabled = false
        }
        await saveCurrentSettings()
    }

    public func setAIAuditLoggingEnabled(_ enabled: Bool) async {
        aiAuditLoggingEnabled = enabled
        await saveCurrentSettings()
    }

    private func save(_ record: PermissionRecord) async {
        errorMessage = nil
        do {
            try await permissionStore.save(record)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applySettings(_ settings: AppSettings) {
        automationState = settings.automationState
        launchAtLoginEnabled = settings.launchAtLoginEnabled
        aiEnabled = settings.aiEnabled
        aiProvider = settings.aiProvider
        aiLocalOnlyModeEnabled = settings.aiLocalOnlyModeEnabled
        aiContentSharingEnabled = settings.aiContentSharingEnabled
        aiMetadataOnlyModeEnabled = settings.aiMetadataOnlyModeEnabled
        aiAuditLoggingEnabled = settings.aiAuditLoggingEnabled
    }

    private func saveCurrentSettings() async {
        errorMessage = nil
        do {
            try await appSettingsStore.save(
                AppSettings(
                    automationState: automationState,
                    launchAtLoginEnabled: launchAtLoginEnabled,
                    aiEnabled: aiEnabled,
                    aiProvider: aiProvider,
                    aiLocalOnlyModeEnabled: aiLocalOnlyModeEnabled,
                    aiContentSharingEnabled: aiContentSharingEnabled,
                    aiMetadataOnlyModeEnabled: aiMetadataOnlyModeEnabled,
                    aiAuditLoggingEnabled: aiAuditLoggingEnabled
                )
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

public actor FixturePermissionStore: PermissionStore {
    private var records: [PermissionRecord]

    public init(records: [PermissionRecord] = []) {
        self.records = records
    }

    public func save(_ record: PermissionRecord) async throws {
        records.removeAll { $0.id == record.id || $0.scope == .libraryRoot && record.scope == .libraryRoot }
        records.append(record)
    }

    public func remove(id: UUID) async throws {
        records.removeAll { $0.id == id }
    }

    public func records(scope: PermissionScope?) async throws -> [PermissionRecord] {
        guard let scope else {
            return records
        }
        return records.filter { $0.scope == scope }
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
