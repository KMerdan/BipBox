import BipboxCore
import BipboxHarness
import BipboxWorkspaceUI
import XCTest

/// Acceptance suite organized by the product north star (docs/product-north-star.md).
/// Each test is named for the principle it proves and runs in-process over the REAL
/// service stack via BipboxHarness. The headline flows are also confirmed through the
/// rendered UI in `UITests/PrincipleUITests.swift`.
@MainActor
final class PrincipleAcceptanceTests: XCTestCase {
    private var project: URL!
    private var harness: BipboxHarness!

    override func setUp() async throws {
        project = try E2ESupport.makeDummyProject()
        harness = try await makeStartedHarness()
    }

    override func tearDown() async throws {
        if let project { try? FileManager.default.removeItem(at: project) }
        harness = nil
    }

    // MARK: - Product Promise
    // "Bipbox remembers what it saw, where it came from, what it relates to,
    //  what happened to it, and how to get it back."

    func test_Promise_remembersSaw_cameFrom_relates_happened_getBack() async throws {
        var snap = await harness.addFolder(project, depth: .always)

        // SAW: captured items are visible in the library.
        XCTAssertTrue(snap.items.contains { $0.name == "report.pdf" }, "What it saw")

        // CAME FROM: the source is recorded (where it came from for watched items).
        XCTAssertEqual(snap.sources.count, 1)
        XCTAssertGreaterThan(snap.sources.first?.indexedCount ?? 0, 0, "Where it came from (source)")

        // HAPPENED: indexing mutations are recorded in Activity.
        XCTAssertTrue(snap.activity.contains { $0.kind == ActivityEventKind.indexed.rawValue },
                      "What happened to it (activity)")

        // RELATES: selecting an item resolves graph neighbors (context/related/cluster).
        let report = try XCTUnwrap(snap.items.first { $0.name == "report.pdf" })
        snap = await harness.select("item:\(report.id)")
        XCTAssertFalse(snap.graph?.neighbors.isEmpty ?? true, "What it relates to")

        // GET IT BACK: search finds it.
        snap = await harness.search("report")
        XCTAssertTrue(snap.items.contains { $0.name == "report.pdf" }, "How to get it back")
    }

    // MARK: - Principle 1: Retrieval First, Storage Second

    func test_P1_itemsAreFindableAndRememberedWithoutMoving() async throws {
        let snap = await harness.addFolder(project, depth: .always)
        XCTAssertGreaterThan(snap.itemCount, 0, "Captured items are findable")
        // Default outcome is "Remembered" (indexedOnly) — nothing is moved/filed.
        XCTAssertTrue(snap.items.allSatisfy { $0.status == IndexedItemStatus.indexedOnly.rawValue },
                      "Items are remembered in place, not organized/moved")
    }

    // MARK: - Principle 2: Sources Are First-Class

    func test_P2_sourcePersistsWithStateAndLifecycle() async throws {
        var snap = await harness.addFolder(project, depth: .never)
        let source = try XCTUnwrap(snap.sources.first)
        XCTAssertTrue(source.enabled)
        XCTAssertGreaterThan(source.indexedCount, 0, "Existing top-level items indexed on add")

        snap = await harness.apply(WorkspaceCommand(action: WorkspaceAction.pauseSource, id: source.id))
        XCTAssertEqual(snap.sources.first { $0.id == source.id }?.enabled, false)

        snap = await harness.apply(WorkspaceCommand(action: WorkspaceAction.resumeSource, id: source.id))
        XCTAssertEqual(snap.sources.first { $0.id == source.id }?.enabled, true)
    }

    // MARK: - Principle 3: Folders Are Items (no recursion by default)

    func test_P3_topLevelCapturesFoldersAsItems_recursiveWalksIn() async throws {
        var snap = await harness.addFolder(project, depth: .never)
        var names = Set(snap.items.map(\.name))
        XCTAssertTrue(names.contains("src"), "Subfolder captured as a single item")
        XCTAssertFalse(names.contains("main.swift"), "Default does NOT walk into folders")

        // Opting in to recursion captures the contents.
        let project2 = try E2ESupport.makeDummyProject()
        defer { try? FileManager.default.removeItem(at: project2) }
        snap = await harness.addFolder(project2, depth: .always)
        names = Set(snap.items.map(\.name))
        XCTAssertTrue(names.contains("main.swift"), "Recursive add walks into folders")
    }

    // MARK: - Principle 4: The Memory Graph Is The Organization Layer

    func test_P4_itemConnectsToContextAndContextListsMembers() async throws {
        var snap = await harness.addFolder(project, depth: .always)
        // A collection member connects to its container, and the container lists
        // its members — the clean replacement for the old folder-"context" edge.
        let main = try XCTUnwrap(snap.items.first { $0.name == "main.swift" })
        snap = await harness.select("item:\(main.id)")
        let graph = try XCTUnwrap(snap.graph)
        let container = try XCTUnwrap(graph.neighbors.first { $0.predicate == "in" },
                                      "Item should connect to its containing collection")

        snap = await harness.select(container.selection)
        XCTAssertNotNil(snap.graph?.center, "Container resolves a real name")
        XCTAssertTrue(snap.graph?.neighbors.contains { $0.predicate == "contains" } ?? false,
                      "Container lists its member items")
    }

    // MARK: - Principle 5: Automation Is Policy Over Memory (Inbox is the fallback)

    func test_P5_rulesAreOptionalAndFallbackIsInbox() async throws {
        // The library works before any rule is authored.
        let base = await harness.addFolder(project, depth: .never)
        XCTAssertGreaterThan(base.itemCount, 0)

        // Ambiguous items land in the Inbox (a visible fallback, not a hidden folder).
        var snap = await harness.seedPending(2)
        XCTAssertEqual(snap.pendingCount, 2)
        snap = await harness.navigate("inbox")
        XCTAssertTrue(snap.items.contains { $0.status == IndexedItemStatus.needsReview.rawValue })

        // Rules are editable policy.
        snap = await harness.apply(WorkspaceCommand(action: WorkspaceAction.addRule))
        let ruleID = try XCTUnwrap(snap.rules.last?.id)
        snap = await harness.apply(WorkspaceCommand(action: WorkspaceAction.toggleRule, id: ruleID))
        XCTAssertTrue(snap.rules.contains { $0.id == ruleID && !$0.enabled })
        snap = await harness.apply(WorkspaceCommand(action: WorkspaceAction.deleteRule, id: ruleID))
        XCTAssertFalse(snap.rules.contains { $0.id == ruleID })
    }

    // MARK: - Principle 6: AI/Automation Is An Orchestrator, Not A Secret Mutator

    func test_P6_decisionsRequireUserActionAndPreviewThePlan() async throws {
        _ = await harness.seedPending(1)
        await harness.navigate("inbox")

        // The proposed action is previewed before anything happens (no silent destination).
        let queued = try XCTUnwrap(harness.model.reviewQueue.items.first)
        XCTAssertFalse(queued.plan.previewText.isEmpty, "Plan is previewed, not silently applied")

        // Nothing changes until the user decides.
        var snap = await harness.snapshot()
        XCTAssertEqual(snap.pendingCount, 1, "Item stays staged until the user acts")

        let itemID = try XCTUnwrap(snap.items.first { $0.status == IndexedItemStatus.needsReview.rawValue }?.id)
        snap = await harness.apply(WorkspaceCommand(action: WorkspaceAction.decide, decision: "approve", id: itemID))
        XCTAssertEqual(snap.pendingCount, 0, "Resolves only when the user approves")
    }

    // MARK: - Safety Rules

    func test_Safety_indexBeforeAction_nothingMovedOnCapture() async throws {
        let snap = await harness.addFolder(project, depth: .always)
        // Index-before-action: every captured item is findable, none filed/moved yet.
        XCTAssertTrue(snap.items.allSatisfy { $0.status != IndexedItemStatus.organized.rawValue })
        XCTAssertTrue(snap.activity.contains { $0.kind == ActivityEventKind.indexed.rawValue },
                      "Every mutation (index) is recorded in Activity")
    }

    func test_Safety_missingFilesAreMarkedAndRecoverable() async throws {
        var snap = await harness.seedMissing(1)
        let missing = try XCTUnwrap(snap.items.first { $0.status == IndexedItemStatus.missing.rawValue })
        XCTAssertNotNil(missing.originalPath, "Missing item still remembers where it came from")

        // Recovery transitions it back to a remembered/active state (file exists).
        snap = await harness.recover(missing.id, mode: "reindex")
        let recovered = snap.items.first { $0.id == missing.id }
        XCTAssertNotEqual(recovered?.status, IndexedItemStatus.missing.rawValue,
                          "Reindex recovers a missing item")
    }

    // MARK: - User-facing naming (north-star "Naming" section)

    func test_Naming_usesFriendlyStatusLabels() {
        XCTAssertEqual(IndexedItemStatus.needsReview.displayLabel, "Needs a decision")
        XCTAssertEqual(IndexedItemStatus.indexedOnly.displayLabel, "Remembered")
        XCTAssertEqual(IndexedItemStatus.organized.displayLabel, "Filed")
    }
}
