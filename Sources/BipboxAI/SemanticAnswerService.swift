import BipboxCore
import Foundation

public struct AnswerCitation: Sendable, Equatable {
    public var itemID: UUID
    public var name: String
    public var path: String
}

public struct SemanticAnswer: Sendable, Equatable {
    public var text: String
    public var citations: [AnswerCitation]
}

/// The optional language layer on top of hybrid retrieval (RAG). Everything here
/// degrades gracefully: with no LLM configured, query expansion is a passthrough
/// and answer synthesis returns nil — semantic search/graph keep working.
///
/// Privacy: this only does anything when a provider is available AND the caller
/// has opted in (the app gates construction on its AI privacy settings).
public final class SemanticAnswerService: Sendable {
    private let provider: LLMProvider

    public init(provider: LLMProvider = UnavailableLLMProvider()) {
        self.provider = provider
    }

    public var isAvailable: Bool { provider.isAvailable }

    /// S3.2 — turn a fuzzy natural-language query into retrieval-friendly terms.
    /// Returns the original text unchanged when no LLM is available.
    public func expandQuery(_ text: String) async -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard provider.isAvailable, !trimmed.isEmpty else { return trimmed }
        let request = LLMRequest(messages: [
            LLMMessage(role: .system, content: "Extract concise search keywords from the user's request. Reply with only the keywords, space-separated."),
            LLMMessage(role: .user, content: trimmed)
        ], maxTokens: 32)
        guard let response = try? await provider.complete(request) else { return trimmed }
        let expanded = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return expanded.isEmpty ? trimmed : expanded
    }

    /// S3.3 — synthesize a short, cited answer from retrieved items. Returns nil
    /// when no LLM is available (the UI then just shows the ranked results).
    public func answer(to query: String, using results: [RetrievalResult], limit: Int = 5) async -> SemanticAnswer? {
        guard provider.isAvailable, !results.isEmpty else { return nil }
        let top = Array(results.prefix(limit))
        let context = top.enumerated().map { idx, r in
            let snippet = (r.item.extractedText ?? "").prefix(400)
            return "[\(idx + 1)] \(r.item.displayName) — \(r.item.currentPath)\n\(snippet)"
        }.joined(separator: "\n\n")

        let request = LLMRequest(messages: [
            LLMMessage(role: .system, content: "Answer the user's question using only the provided files. Cite sources as [n]. Be concise. If the files don't answer it, say so."),
            LLMMessage(role: .user, content: "Question: \(query)\n\nFiles:\n\(context)")
        ], maxTokens: 400)

        guard let response = try? await provider.complete(request) else { return nil }
        let citations = top.map { AnswerCitation(itemID: $0.item.id, name: $0.item.displayName, path: $0.item.currentPath) }
        return SemanticAnswer(text: response.text.trimmingCharacters(in: .whitespacesAndNewlines), citations: citations)
    }
}
