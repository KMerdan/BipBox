import Foundation

/// Re-embeds already-indexed items that don't yet have a vector for the active
/// embedding model. Needed after the model is first provisioned (or swapped):
/// items indexed before the model was ready embedded to nil — or under a different
/// model id — so topic discovery / semantic retrieval can't see them until they're
/// backfilled. Idempotent: only items missing a vector are embedded.
public protocol EmbeddingBackfilling: Sendable {
    /// `progress` is called with (processed, total) — total is known up front
    /// (the missing-vector count), so callers can render a percentage + ETA.
    @discardableResult
    func backfill(limit: Int, progress: (@Sendable (_ processed: Int, _ total: Int) async -> Void)?) async -> Int
}

public extension EmbeddingBackfilling {
    @discardableResult
    func backfill(limit: Int = 10_000) async -> Int {
        await backfill(limit: limit, progress: nil)
    }
}

public actor DefaultEmbeddingBackfillService: EmbeddingBackfilling {
    private let searchService: SearchService
    private let embedder: TextEmbedder
    private let vectorIndex: VectorIndex

    public init(searchService: SearchService, embedder: TextEmbedder, vectorIndex: VectorIndex) {
        self.searchService = searchService
        self.embedder = embedder
        self.vectorIndex = vectorIndex
    }

    /// Embed every indexed item lacking a vector for `embedder.modelID`. Returns the
    /// number newly embedded. No-op (returns 0) when the embedder isn't ready —
    /// `embed` returns nil and nothing is written.
    @discardableResult
    public func backfill(
        limit: Int = 10_000,
        progress: (@Sendable (_ processed: Int, _ total: Int) async -> Void)? = nil
    ) async -> Int {
        guard let results = try? await searchService.search(SearchQuery(text: "", limit: limit)) else { return 0 }
        let existing = (try? await vectorIndex.vectors(modelID: embedder.modelID)) ?? []
        let have = Set(existing.map(\.itemID))

        // "dup" = exact byte-fingerprint duplicate; indexed for search but never
        // embedded (the primary copy carries the vector).
        let pending = results.items.filter { !have.contains($0.id) && !$0.tags.contains("dup") }
        await progress?(0, pending.count)

        var embedded = 0
        for (index, item) in pending.enumerated() {
            let text = Self.embedText(for: item)
            if !text.isEmpty, let vector = await embedder.embed(text) {
                try? await vectorIndex.upsertVector(
                    VectorRecord(itemID: item.id, modelID: embedder.modelID, vector: vector))
                embedded += 1
            }
            await progress?(index + 1, pending.count)
        }
        return embedded
    }

    /// What represents an item for embedding: its name + extracted content.
    static func embedText(for item: IndexedItem) -> String {
        [item.displayName, item.extractedText]
            .compactMap { $0 }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
