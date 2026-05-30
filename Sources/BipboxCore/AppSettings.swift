import Foundation

public enum AutomationState: String, Codable, Equatable, Sendable {
    case running
    case paused
}

public enum AIProviderKind: String, Codable, Equatable, CaseIterable, Sendable {
    case none
    case local
    case openAI
    case anthropic
    case custom
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var automationState: AutomationState
    public var launchAtLoginEnabled: Bool
    public var aiEnabled: Bool
    public var aiProvider: AIProviderKind
    public var aiLocalOnlyModeEnabled: Bool
    public var aiContentSharingEnabled: Bool
    public var aiMetadataOnlyModeEnabled: Bool
    public var aiAuditLoggingEnabled: Bool

    public init(
        automationState: AutomationState = .running,
        launchAtLoginEnabled: Bool = false,
        aiEnabled: Bool = false,
        aiProvider: AIProviderKind = .none,
        aiLocalOnlyModeEnabled: Bool = true,
        aiContentSharingEnabled: Bool = false,
        aiMetadataOnlyModeEnabled: Bool = true,
        aiAuditLoggingEnabled: Bool = true
    ) {
        self.automationState = automationState
        self.launchAtLoginEnabled = launchAtLoginEnabled
        self.aiEnabled = aiEnabled
        self.aiProvider = aiProvider
        self.aiLocalOnlyModeEnabled = aiLocalOnlyModeEnabled
        self.aiContentSharingEnabled = aiContentSharingEnabled
        self.aiMetadataOnlyModeEnabled = aiMetadataOnlyModeEnabled
        self.aiAuditLoggingEnabled = aiAuditLoggingEnabled
    }

    public static let defaults = AppSettings()

    private enum CodingKeys: String, CodingKey {
        case automationState
        case launchAtLoginEnabled
        case aiEnabled
        case aiProvider
        case aiLocalOnlyModeEnabled
        case aiContentSharingEnabled
        case aiMetadataOnlyModeEnabled
        case aiAuditLoggingEnabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        automationState = try container.decodeIfPresent(AutomationState.self, forKey: .automationState) ?? .running
        launchAtLoginEnabled = try container.decodeIfPresent(Bool.self, forKey: .launchAtLoginEnabled) ?? false
        aiEnabled = try container.decodeIfPresent(Bool.self, forKey: .aiEnabled) ?? false
        aiProvider = try container.decodeIfPresent(AIProviderKind.self, forKey: .aiProvider) ?? .none
        aiLocalOnlyModeEnabled = try container.decodeIfPresent(Bool.self, forKey: .aiLocalOnlyModeEnabled) ?? true
        aiContentSharingEnabled = try container.decodeIfPresent(Bool.self, forKey: .aiContentSharingEnabled) ?? false
        aiMetadataOnlyModeEnabled = try container.decodeIfPresent(Bool.self, forKey: .aiMetadataOnlyModeEnabled) ?? true
        aiAuditLoggingEnabled = try container.decodeIfPresent(Bool.self, forKey: .aiAuditLoggingEnabled) ?? true
    }
}

public protocol AppSettingsStore: Sendable {
    func load() async throws -> AppSettings
    func save(_ settings: AppSettings) async throws
}
