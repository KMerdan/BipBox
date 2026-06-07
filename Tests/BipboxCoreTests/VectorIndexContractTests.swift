import BipboxCore
import XCTest

final class VectorIndexContractTests: XCTestCase {
    func testVectorRecordValidationRejectsInvalidInputs() throws {
        let itemID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!

        XCTAssertThrowsError(
            try VectorRecord(itemID: itemID, modelID: " ", vector: [1]).validate()
        ) { error in
            XCTAssertEqual(error as? VectorIndexError, .emptyModelID)
        }
        XCTAssertThrowsError(
            try VectorRecord(itemID: itemID, modelID: "local", vector: []).validate()
        ) { error in
            XCTAssertEqual(error as? VectorIndexError, .emptyVector)
        }
        XCTAssertThrowsError(
            try VectorRecord(itemID: itemID, modelID: "local", vector: [1, 2]).validate(expectedDimension: 3)
        ) { error in
            XCTAssertEqual(error as? VectorIndexError, .invalidDimension(expected: 3, actual: 2))
        }
    }

    func testVectorSearchQueryValidationRejectsInvalidLimit() {
        XCTAssertThrowsError(
            try VectorSearchQuery(modelID: "local", vector: [1], limit: 0).validate()
        ) { error in
            XCTAssertEqual(error as? VectorIndexError, .invalidLimit(0))
        }
    }

    func testMockVectorIndexKeepsModelsSeparated() async throws {
        let index: VectorIndex = InMemoryVectorIndex()
        let itemA = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
        let itemB = UUID(uuidString: "00000000-0000-0000-0000-000000000103")!

        try await index.upsertVector(VectorRecord(itemID: itemA, modelID: "apple-nl", vector: [1, 0]))
        try await index.upsertVector(VectorRecord(itemID: itemB, modelID: "local-embed", vector: [1, 0]))

        let appleMatches = try await index.nearest(to: VectorSearchQuery(modelID: "apple-nl", vector: [1, 0]))
        let localMatches = try await index.nearest(to: VectorSearchQuery(modelID: "local-embed", vector: [1, 0]))

        XCTAssertEqual(appleMatches.map(\.itemID), [itemA])
        XCTAssertEqual(localMatches.map(\.itemID), [itemB])
    }

    func testMockVectorIndexAppliesItemFilters() async throws {
        let index: VectorIndex = InMemoryVectorIndex()
        let itemA = UUID(uuidString: "00000000-0000-0000-0000-000000000104")!
        let itemB = UUID(uuidString: "00000000-0000-0000-0000-000000000105")!

        try await index.upsertVector(VectorRecord(itemID: itemA, modelID: "local", vector: [1, 0]))
        try await index.upsertVector(VectorRecord(itemID: itemB, modelID: "local", vector: [0.8, 0.2]))

        let matches = try await index.nearest(
            to: VectorSearchQuery(
                modelID: "local",
                vector: [1, 0],
                filters: VectorSearchFilters(itemIDs: [itemB])
            )
        )

        XCTAssertEqual(matches.map(\.itemID), [itemB])
    }

    func testMockVectorIndexRejectsDimensionMismatchPerModel() async throws {
        let index = InMemoryVectorIndex()
        let itemA = UUID(uuidString: "00000000-0000-0000-0000-000000000106")!
        let itemB = UUID(uuidString: "00000000-0000-0000-0000-000000000107")!

        try await index.upsertVector(VectorRecord(itemID: itemA, modelID: "local", vector: [1, 0]))

        do {
            try await index.upsertVector(VectorRecord(itemID: itemB, modelID: "local", vector: [1, 0, 0]))
            XCTFail("Expected dimension mismatch.")
        } catch {
            XCTAssertEqual(error as? VectorIndexError, .invalidDimension(expected: 2, actual: 3))
        }
    }
}

private actor InMemoryVectorIndex: VectorIndex {
    private var records: [String: [UUID: VectorRecord]] = [:]
    private var dimensions: [String: Int] = [:]

    func upsertVector(_ record: VectorRecord) async throws {
        try record.validate(expectedDimension: dimensions[record.modelID])
        dimensions[record.modelID] = record.vector.count
        records[record.modelID, default: [:]][record.itemID] = record
    }

    func deleteVector(itemID: UUID, modelID: String) async throws {
        records[modelID]?[itemID] = nil
    }

    func vectors(modelID: String) async throws -> [VectorRecord] {
        Array(records[modelID, default: [:]].values)
    }

    func nearest(to query: VectorSearchQuery) async throws -> [VectorMatch] {
        guard let dimension = dimensions[query.modelID] else {
            throw VectorIndexError.unsupportedModel(query.modelID)
        }
        try query.validate(expectedDimension: dimension)

        let allowedItemIDs = Set(query.filters.itemIDs)
        let candidates = records[query.modelID, default: [:]].values
            .filter { allowedItemIDs.isEmpty || allowedItemIDs.contains($0.itemID) }
            .map { record in
                VectorMatch(
                    itemID: record.itemID,
                    modelID: record.modelID,
                    score: dot(query.vector, record.vector)
                )
            }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.itemID.uuidString < rhs.itemID.uuidString
                }
                return lhs.score > rhs.score
            }

        return Array(candidates.prefix(query.limit))
    }

    private func dot(_ lhs: [Float], _ rhs: [Float]) -> Double {
        Double(zip(lhs, rhs).map(*).reduce(0, +))
    }
}
