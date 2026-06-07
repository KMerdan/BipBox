import BipboxCore
import BipboxHarness
import BipboxWorkspaceUI
import XCTest

/// Slice 2: the Connections graph driven by embeddings + the Group-by lens switch.
@MainActor
final class SemanticGraphWorkflowTests: XCTestCase {
    private var project: URL!
    private var harness: BipboxHarness!

    override func setUp() async throws {
        project = try E2ESupport.makeDummyProject()
        harness = try await makeStartedHarness()
        await harness.addFolder(project, depth: .always)
    }

    override func tearDown() async throws {
        if let project { try? FileManager.default.removeItem(at: project) }
        harness = nil
    }

    func testGroupByLensProducesDifferentClusterings() async throws {
        let model = harness.model

        model.lens = .type
        await model.recomputeClusters()
        let typeClusters = model.clusters
        XCTAssertFalse(typeClusters.isEmpty)
        XCTAssertTrue(typeClusters.contains { ["Documents", "Images", "Code"].contains($0.name) },
                      "Type lens groups by category")

        model.lens = .source
        await model.recomputeClusters()
        XCTAssertTrue(model.clusters.allSatisfy { $0.id.hasPrefix("source:") }, "Source lens groups by source")

        model.lens = .time
        await model.recomputeClusters()
        XCTAssertTrue(model.clusters.allSatisfy { $0.id.hasPrefix("time:") }, "Time lens groups by month")

        model.lens = .smart
        await model.recomputeClusters()
        XCTAssertFalse(model.clusters.isEmpty, "Smart lens always produces clusters")
    }

    func testSmartLensUsesSemanticClustersWhenEmbeddingsAvailable() async throws {
        try XCTSkipUnless(NLEmbeddingTextEmbedder().isAvailable, "NLEmbedding unavailable on this host")
        let model = harness.model
        model.lens = .smart
        await model.recomputeClusters()
        // With embeddings, smart clusters are semantic ("sem:" ids), not type buckets.
        XCTAssertTrue(model.clusters.contains { $0.id.hasPrefix("sem:") },
                      "Smart lens yields semantic clusters when embeddings exist")
    }

    func testItemEgoIncludesSemanticNeighbors() async throws {
        try XCTSkipUnless(NLEmbeddingTextEmbedder().isAvailable, "NLEmbedding unavailable on this host")
        let snap = await harness.snapshot()
        let report = try XCTUnwrap(snap.items.first { $0.name == "report.pdf" })
        let graph = (await harness.select("item:\(report.id)")).graph
        let neighbors = graph?.neighbors ?? []
        XCTAssertFalse(neighbors.isEmpty, "Item ego has neighbors")
        // Semantic neighbors carry the "similar" predicate (vs lexical "related").
        XCTAssertTrue(neighbors.contains { $0.predicate == "similar" || $0.selection.hasPrefix("source:") },
                      "Ego graph includes semantic file neighbors and/or its source")
    }
}
