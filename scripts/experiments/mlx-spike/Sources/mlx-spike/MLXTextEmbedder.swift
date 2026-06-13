import Foundation
import MLX
import MLXEmbedders
import MLXLMCommon
import MLXHuggingFace
import HuggingFace
import Tokenizers

/// In Bipbox this conforms to `BipboxCore.TextEmbedder`; mirrored here so the spike
/// compiles standalone and the body ports verbatim.
public protocol TextEmbedder: Sendable {
    var modelID: String { get }
    func embed(_ text: String) async -> [Float]?
}

/// On-device embedder backed by MLX (Apple Silicon GPU, no server). Loads a
/// Qwen3-Embedding model lazily on first use and caches the container.
public actor MLXTextEmbedder: TextEmbedder {
    public let modelID: String
    private let maxTokens: Int
    private let configuration: ModelConfiguration
    private var container: EmbedderModelContainer?

    public init(
        modelID: String = "mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ",
        maxTokens: Int = 512
    ) {
        self.modelID = modelID
        self.maxTokens = maxTokens
        self.configuration = ModelConfiguration(id: modelID)
    }

    private func loaded() async throws -> EmbedderModelContainer {
        if let container { return container }
        let c = try await EmbedderModelFactory.shared.loadContainer(
            from: #hubDownloader(),
            using: #huggingFaceTokenizerLoader(),
            configuration: configuration
        ) { progress in
            FileHandle.standardError.write(
                Data("  download \(Int(progress.fractionCompleted * 100))%\r".utf8))
        }
        container = c
        return c
    }

    /// Embed into a UNIT-NORMALIZED vector (dot product == cosine). nil on failure.
    public func embed(_ text: String) async -> [Float]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let cap = maxTokens
        do {
            let container = try await loaded()
            return await container.perform { (context: EmbedderModelContext) -> [Float] in
                var tokens = context.tokenizer.encode(text: trimmed, addSpecialTokens: true)
                if tokens.count > cap { tokens = Array(tokens.prefix(cap)) }
                let input = MLXArray(tokens).expandedDimensions(axis: 0)
                let output = context.model(
                    input, positionIds: nil, tokenTypeIds: nil, attentionMask: nil)
                let pooled = context.pooling(output, normalize: true)
                pooled.eval()
                return pooled.map { $0.asArray(Float.self) }[0]
            }
        } catch {
            FileHandle.standardError.write(Data("embed error: \(error)\n".utf8))
            return nil
        }
    }
}
