import BipboxCore
import Foundation

public enum AIGatewayDefaults {
    public static let remoteContentSharingAllowed = false
}

public enum AIGatewayError: Error, Equatable, LocalizedError {
    case toolUseUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case .toolUseUnavailable(let toolName):
            "AI tool use is not available without a configured model: \(toolName)"
        }
    }
}

public struct AIPrivacySnapshot: Codable, Equatable, Sendable {
    public var remoteContentSharingAllowed: Bool
    public var itemKind: ItemKind
    public var includesExtractedTextSummary: Bool
    public var allowedToolCount: Int

    public init(
        remoteContentSharingAllowed: Bool,
        itemKind: ItemKind,
        includesExtractedTextSummary: Bool,
        allowedToolCount: Int
    ) {
        self.remoteContentSharingAllowed = remoteContentSharingAllowed
        self.itemKind = itemKind
        self.includesExtractedTextSummary = includesExtractedTextSummary
        self.allowedToolCount = allowedToolCount
    }

    public init(request: AIRequest) {
        remoteContentSharingAllowed = request.remoteContentSharingAllowed
        itemKind = request.itemProfile.kind
        includesExtractedTextSummary = request.itemProfile.extractedTextSummary != nil
        allowedToolCount = request.allowedTools.count
    }
}

public final class NoModelAIGateway: AIOrchestrator, @unchecked Sendable {
    public private(set) var classifications: [AIPrivacySnapshot] = []

    public init() {}

    public func classify(_ request: AIRequest) async throws -> AIClassification {
        classifications.append(AIPrivacySnapshot(request: request))

        return AIClassification(
            category: nil,
            suggestedDestinationURL: nil,
            confidence: 0,
            reason: "No AI model is configured. The item must be handled by rules or manual review.",
            requiredTools: request.allowedTools,
            reviewRequirement: .required
        )
    }

    public func callTool(_ call: ToolCall, context: ExecutionContext) async throws -> ToolResult {
        throw AIGatewayError.toolUseUnavailable(call.toolName)
    }
}
