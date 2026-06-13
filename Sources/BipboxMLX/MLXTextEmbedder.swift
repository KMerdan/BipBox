import Foundation
import BipboxCore
import MLX
import MLXEmbedders
import MLXLMCommon
import MLXHuggingFace
import HuggingFace
import Tokenizers

/// On-device embedder backed by MLX (Apple Silicon GPU, no server).
///
/// The model download is EXPLICIT: `embed` never triggers it — it returns nil
/// until `prepare(progress:)` has provisioned the model, so retrieval degrades to
/// lexical until the user opts into the one-time download. A marker file lets the
/// app distinguish "needs download" from "cached, just load" on first start.
public actor MLXTextEmbedder: TextEmbedder, EmbedderProvisioning {
    public let modelID: String
    private let maxTokens: Int
    private let markerURL: URL
    private let configuration: ModelConfiguration
    private var container: EmbedderModelContainer?
    private var isPreparing = false
    private var lastProgress: Double = 0

    public init(
        modelID: String = "mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ",
        maxTokens: Int = 512,
        markerURL: URL
    ) {
        self.modelID = modelID
        self.maxTokens = maxTokens
        self.markerURL = markerURL
        self.configuration = ModelConfiguration(id: modelID)
    }

    private var isCached: Bool {
        FileManager.default.fileExists(atPath: markerURL.path)
    }

    public func provisioningStatus() async -> EmbedderModelStatus {
        if container != nil { return .ready }
        if isPreparing { return .downloading(lastProgress) }
        return isCached ? .ready : .needsDownload
    }

    @discardableResult
    public func prepare(progress: @Sendable @escaping (Double) -> Void) async -> EmbedderModelStatus {
        if container != nil { progress(1); return .ready }
        isPreparing = true
        lastProgress = 0
        defer { isPreparing = false }
        do {
            let loaded = try await EmbedderModelFactory.shared.loadContainer(
                from: #hubDownloader(),
                using: #huggingFaceTokenizerLoader(),
                configuration: configuration
            ) { p in
                let f = p.fractionCompleted
                progress(f)
                Task { await self.note(f) }
            }
            container = loaded
            writeMarker()
            progress(1)
            return .ready
        } catch {
            return .failed(String(describing: error))
        }
    }

    private func note(_ fraction: Double) { lastProgress = fraction }

    private func writeMarker() {
        try? FileManager.default.createDirectory(
            at: markerURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data(modelID.utf8).write(to: markerURL)
    }

    public func embed(_ text: String) async -> [Float]? {
        guard let container else { return nil }   // not provisioned → caller falls back to lexical
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let cap = maxTokens
        return await container.perform { (ctx: EmbedderModelContext) -> [Float] in
            var tokens = ctx.tokenizer.encode(text: trimmed, addSpecialTokens: true)
            if tokens.count > cap { tokens = Array(tokens.prefix(cap)) }
            let input = MLXArray(tokens).expandedDimensions(axis: 0)
            let output = ctx.model(input, positionIds: nil, tokenTypeIds: nil, attentionMask: nil)
            let pooled = ctx.pooling(output, normalize: true)
            pooled.eval()
            return pooled.map { $0.asArray(Float.self) }[0]
        }
    }
}
