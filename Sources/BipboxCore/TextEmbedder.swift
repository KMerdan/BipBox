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
    /// Returns nil when the text can't be embedded (empty / model not yet provisioned).
    func embed(_ text: String) async -> [Float]?
}

/// Provisioning state of an embedder's model. The download is EXPLICIT (never
/// silent) so first run is never a surprise; until `.ready`, `embed` returns nil
/// and retrieval degrades to lexical.
public enum EmbedderModelStatus: Sendable, Equatable {
    case ready                   // model present & usable now
    case needsDownload           // a one-time model download is required
    case downloading(Double)     // fraction 0...1
    case failed(String)
}

/// An embedder whose model may require a visible, user-initiated download.
public protocol EmbedderProvisioning: Sendable {
    /// Current readiness — does NOT trigger any download.
    func provisioningStatus() async -> EmbedderModelStatus
    /// Download + load the model, reporting 0...1 progress. Idempotent; returns the final status.
    @discardableResult
    func prepare(progress: @Sendable @escaping (Double) -> Void) async -> EmbedderModelStatus
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

/// The on-device NL embedder ships with the OS — nothing to download.
extension NLEmbeddingTextEmbedder: EmbedderProvisioning {
    public func provisioningStatus() async -> EmbedderModelStatus {
        isAvailable ? .ready : .failed("on-device NL embedding model unavailable")
    }

    @discardableResult
    public func prepare(progress: @Sendable @escaping (Double) -> Void) async -> EmbedderModelStatus {
        progress(1)
        return await provisioningStatus()
    }
}
