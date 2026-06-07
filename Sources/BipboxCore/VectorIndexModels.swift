import Foundation

public enum VectorIndexError: Error, Equatable, LocalizedError, Sendable {
    case emptyModelID
    case emptyVector
    case invalidDimension(expected: Int, actual: Int)
    case invalidLimit(Int)
    case unsupportedModel(String)
    case backendUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case .emptyModelID:
            "Vector model ID must not be empty."
        case .emptyVector:
            "Vector must contain at least one value."
        case .invalidDimension(let expected, let actual):
            "Vector dimension mismatch. Expected \(expected), got \(actual)."
        case .invalidLimit(let limit):
            "Vector search limit must be positive: \(limit)."
        case .unsupportedModel(let modelID):
            "Vector model is not supported: \(modelID)."
        case .backendUnavailable(let reason):
            "Vector index backend is unavailable: \(reason)."
        }
    }
}

public struct VectorRecord: Codable, Equatable, Sendable {
    public var itemID: UUID
    public var modelID: String
    public var vector: [Float]

    public init(itemID: UUID, modelID: String, vector: [Float]) {
        self.itemID = itemID
        self.modelID = modelID
        self.vector = vector
    }

    public func validate(expectedDimension: Int? = nil) throws {
        try VectorValidation.validate(modelID: modelID, vector: vector, expectedDimension: expectedDimension)
    }
}

public struct VectorSearchFilters: Codable, Equatable, Sendable {
    public var itemIDs: [UUID]
    public var kinds: [ItemKind]
    public var contextIDs: [UUID]
    public var collectionIDs: [UUID]

    public init(
        itemIDs: [UUID] = [],
        kinds: [ItemKind] = [],
        contextIDs: [UUID] = [],
        collectionIDs: [UUID] = []
    ) {
        self.itemIDs = itemIDs
        self.kinds = kinds
        self.contextIDs = contextIDs
        self.collectionIDs = collectionIDs
    }
}

public struct VectorSearchQuery: Codable, Equatable, Sendable {
    public var modelID: String
    public var vector: [Float]
    public var limit: Int
    public var filters: VectorSearchFilters

    public init(
        modelID: String,
        vector: [Float],
        limit: Int = 10,
        filters: VectorSearchFilters = VectorSearchFilters()
    ) {
        self.modelID = modelID
        self.vector = vector
        self.limit = limit
        self.filters = filters
    }

    public func validate(expectedDimension: Int? = nil) throws {
        guard limit > 0 else {
            throw VectorIndexError.invalidLimit(limit)
        }
        try VectorValidation.validate(modelID: modelID, vector: vector, expectedDimension: expectedDimension)
    }
}

public struct VectorMatch: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID { itemID }
    public var itemID: UUID
    public var modelID: String
    public var score: Double
    public var distance: Double?

    public init(itemID: UUID, modelID: String, score: Double, distance: Double? = nil) {
        self.itemID = itemID
        self.modelID = modelID
        self.score = score
        self.distance = distance
    }
}

public protocol VectorIndex: Sendable {
    func upsertVector(_ record: VectorRecord) async throws
    func deleteVector(itemID: UUID, modelID: String) async throws
    func nearest(to query: VectorSearchQuery) async throws -> [VectorMatch]
    /// All stored vectors for a model (for clustering / centroid work).
    func vectors(modelID: String) async throws -> [VectorRecord]
}

enum VectorValidation {
    static func validate(modelID: String, vector: [Float], expectedDimension: Int?) throws {
        guard !modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw VectorIndexError.emptyModelID
        }
        guard !vector.isEmpty else {
            throw VectorIndexError.emptyVector
        }
        if let expectedDimension, vector.count != expectedDimension {
            throw VectorIndexError.invalidDimension(expected: expectedDimension, actual: vector.count)
        }
    }
}
