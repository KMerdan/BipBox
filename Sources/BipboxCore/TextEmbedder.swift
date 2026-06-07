import Foundation
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif

/// Namespacing for vectors sharing the index: items vs context entities are
/// stored under sibling model ids so they can be queried separately.
public enum VectorModel {
    public static func entity(_ modelID: String) -> String { modelID + ".entity" }
}

/// Turns text into a point in vector space. Pluggable: the on-device Apple model
/// today, a llama.cpp / remote model later — same seam.
public protocol TextEmbedder: Sendable {
    /// Stable id of the embedding model (vectors are namespaced by this).
    var modelID: String { get }
    /// Embed text into a UNIT-NORMALIZED vector (so dot product == cosine).
    /// Returns nil when the text can't be embedded (empty / model unavailable).
    func embed(_ text: String) async -> [Float]?
}

/// On-device embedder backed by Apple's `NLEmbedding` (private, free, no network).
public final class NLEmbeddingTextEmbedder: TextEmbedder, @unchecked Sendable {
    public let modelID: String
    private let maxCharacters: Int
    #if canImport(NaturalLanguage)
    private let embedding: NLEmbedding?
    #endif

    public init(modelID: String = "apple.nl.sentence.en.v1", maxCharacters: Int = 1000) {
        self.modelID = modelID
        self.maxCharacters = maxCharacters
        #if canImport(NaturalLanguage)
        self.embedding = NLEmbedding.sentenceEmbedding(for: .english)
        #endif
    }

    /// True when the on-device model loaded (used by tests to skip when absent).
    public var isAvailable: Bool {
        #if canImport(NaturalLanguage)
        return embedding != nil
        #else
        return false
        #endif
    }

    public func embed(_ text: String) async -> [Float]? {
        #if canImport(NaturalLanguage)
        guard let embedding else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let input = String(trimmed.prefix(maxCharacters))
        guard let raw = embedding.vector(for: input) else { return nil }
        return Self.unitNormalized(raw.map { Float($0) })
        #else
        return nil
        #endif
    }

    /// L2-normalize so the vector index's dot product equals cosine similarity.
    public static func unitNormalized(_ v: [Float]) -> [Float]? {
        let norm = (v.reduce(Float(0)) { $0 + $1 * $1 }).squareRoot()
        guard norm > 0 else { return nil }
        return v.map { $0 / norm }
    }
}
