import BipboxCore
import Foundation

/// Seam for a chat/completion LLM. The on-device default is "unavailable" until a
/// real local model (e.g. a GGUF via llama.cpp) is configured; a remote provider
/// can plug in here too — both behind the app's AI privacy settings.
public protocol LLMProvider: Sendable {
    var isAvailable: Bool { get }
    var modelID: String { get }
    func complete(_ request: LLMRequest) async throws -> LLMResponse
}

public struct LLMMessage: Sendable, Equatable {
    public enum Role: String, Sendable { case system, user, assistant }
    public var role: Role
    public var content: String
    public init(role: Role, content: String) { self.role = role; self.content = content }
}

public struct LLMRequest: Sendable, Equatable {
    public var messages: [LLMMessage]
    public var maxTokens: Int
    public var temperature: Double
    public init(messages: [LLMMessage], maxTokens: Int = 512, temperature: Double = 0.2) {
        self.messages = messages
        self.maxTokens = maxTokens
        self.temperature = temperature
    }
}

public struct LLMResponse: Sendable, Equatable {
    public var text: String
    public var modelID: String
    public init(text: String, modelID: String) { self.text = text; self.modelID = modelID }
}

public enum LLMError: Error, Equatable, LocalizedError {
    case notConfigured
    case generationFailed(String)
    public var errorDescription: String? {
        switch self {
        case .notConfigured: "No local language model is configured."
        case .generationFailed(let r): "Language model failed: \(r)"
        }
    }
}

/// Default provider when no model is installed. Keeps the app fully functional
/// (semantic search + graph work without any LLM); language features simply
/// degrade to "no answer".
public struct UnavailableLLMProvider: LLMProvider {
    public init() {}
    public var isAvailable: Bool { false }
    public var modelID: String { "none" }
    public func complete(_ request: LLMRequest) async throws -> LLMResponse {
        throw LLMError.notConfigured
    }
}
