// WorkspaceControl.swift — the programmatic control surface for the workspace.
//
// One Codable command vocabulary + one Codable state snapshot, interpreted by
// `WorkspaceModel`. This is the shared engine behind every harness: the in-process
// driver, the JSON CLI, and the live HTTP control API all speak these types.
import Foundation
import BipboxCore

/// Index N synthetic `needsReview` items into the search index so the Inbox
/// decision flow can be exercised deterministically. Shared by the app + harness.
public func seedPendingReviewItems(count: Int, into searchService: SearchService, baseDirectory: URL) async {
    guard count > 0 else { return }
    for i in 1...count {
        let name = "Pending \(i).pdf"
        let item = IndexedItem(
            currentPath: baseDirectory.appendingPathComponent(name).path,
            displayName: name,
            kind: .file,
            uniformTypeIdentifier: "com.adobe.pdf",
            importedAt: Date(timeIntervalSince1970: 1_800_000_000 + Double(i)),
            tags: ["pending"],
            aiSummary: "Needs a decision (seeded for testing).",
            status: .needsReview
        )
        try? await searchService.index(item)
    }
}

/// Index N `.missing` items, each backed by a REAL temp file (so reindex/refresh
/// can legitimately transition them back). The recorded path is the real file;
/// `originalPath` records where it "came from". Writes to BOTH the search index
/// and the knowledge store so the recovery service (which reads the knowledge
/// store) can act on them.
public func seedMissingItems(count: Int, into searchService: SearchService, knowledgeStore: KnowledgeStore, baseDirectory: URL) async {
    guard count > 0 else { return }
    for i in 1...count {
        let id = UUID()
        let name = "Missing \(i).txt"
        let fileURL = baseDirectory.appendingPathComponent(name)
        try? "recovered contents \(i)".write(to: fileURL, atomically: true, encoding: .utf8)
        let when = Date(timeIntervalSince1970: 1_800_000_500 + Double(i))
        let item = IndexedItem(
            id: id,
            currentPath: fileURL.path,
            originalPath: baseDirectory.appendingPathComponent("Downloads/\(name)").path,
            displayName: name,
            kind: .file,
            uniformTypeIdentifier: "public.plain-text",
            importedAt: when,
            tags: ["missing"],
            aiSummary: "Recently moved or renamed (seeded for testing).",
            status: .missing
        )
        let knowledgeItem = KnowledgeItem(
            id: id,
            kind: .file,
            displayName: name,
            currentURL: fileURL,
            originalURL: baseDirectory.appendingPathComponent("Downloads/\(name)"),
            firstSeenAt: when,
            lastSeenAt: when,
            state: .missing
        )
        try? await knowledgeStore.upsertKnowledgeItem(knowledgeItem)
        try? await searchService.index(item)
    }
}

// MARK: - Command

/// A single instruction for the workspace. Flat + JSON-friendly so it is trivial
/// to send from curl / Python / a Swift test.
public struct WorkspaceCommand: Codable, Sendable, Equatable {
    public var action: String       // see WorkspaceAction
    public var target: String?      // section or selection ref ("allItems", "item:<uuid>", "source:<uuid>")
    public var query: String?       // for search
    public var decision: String?    // approve | keep | reject
    public var path: String?        // for addFolder / recover(locate)
    public var depth: String?       // top | all  (addFolder)
    public var id: String?          // uuid string (decide/scanSource/rules/recover)
    public var name: String?        // rename
    public var mode: String?        // recover: locate | reindex | refresh

    public init(action: String, target: String? = nil, query: String? = nil,
                decision: String? = nil, path: String? = nil, depth: String? = nil,
                id: String? = nil, name: String? = nil, mode: String? = nil) {
        self.action = action
        self.target = target
        self.query = query
        self.decision = decision
        self.path = path
        self.depth = depth
        self.id = id
        self.name = name
        self.mode = mode
    }
}

public enum WorkspaceAction {
    public static let snapshot = "snapshot"
    public static let refresh = "refresh"
    public static let navigate = "navigate"
    public static let search = "search"
    public static let clearSearch = "clearSearch"
    public static let select = "select"
    public static let setPresentation = "setPresentation"
    public static let decide = "decide"
    public static let addFolder = "addFolder"
    public static let scanSource = "scanSource"
    public static let pauseSource = "pauseSource"
    public static let resumeSource = "resumeSource"
    public static let addRule = "addRule"
    public static let deleteRule = "deleteRule"
    public static let toggleRule = "toggleRule"
    public static let seedPending = "seedPending"   // test/automation: create pending items
    public static let seedMissing = "seedMissing"   // test/automation: create missing items
    public static let recover = "recover"           // locate | reindex | refresh a missing item
}

// MARK: - Snapshot

public struct WorkspaceSnapshot: Codable, Sendable, Equatable {
    public var section: String
    public var presentation: String
    public var selection: String
    public var query: String
    public var isSearching: Bool
    public var itemCount: Int
    public var pendingCount: Int
    public var ruleCount: Int
    public var toast: String?
    public var items: [ItemSummary]
    public var sources: [SourceSummary]
    public var rules: [RuleSummary]
    public var activity: [ActivitySummary]
    public var graph: GraphSnapshot?
    public var lastError: String?

    public struct ItemSummary: Codable, Sendable, Equatable {
        public var id: String
        public var name: String
        public var status: String
        public var path: String
        public var originalPath: String?
    }
    public struct ActivitySummary: Codable, Sendable, Equatable {
        public var id: String
        public var kind: String
        public var message: String
        public var reversible: Bool
    }
    public struct SourceSummary: Codable, Sendable, Equatable {
        public var id: String
        public var name: String
        public var enabled: Bool
        public var path: String
        public var indexedCount: Int
    }
    public struct RuleSummary: Codable, Sendable, Equatable {
        public var id: String
        public var name: String
        public var enabled: Bool
    }
    public struct GraphSnapshot: Codable, Sendable, Equatable {
        public var center: String?
        public var neighbors: [NeighborSummary]
    }
    public struct NeighborSummary: Codable, Sendable, Equatable {
        public var name: String
        public var kind: String
        public var predicate: String
        public var selection: String
    }
}

// MARK: - Interpreter

@MainActor
extension WorkspaceModel {
    /// Apply a command and return the resulting snapshot.
    public func apply(_ command: WorkspaceCommand) async -> WorkspaceSnapshot {
        switch command.action {
        case WorkspaceAction.snapshot:
            break
        case WorkspaceAction.refresh:
            await refresh()
        case WorkspaceAction.navigate:
            if let nav = Self.parseNav(command.target) { go(nav) }
        case WorkspaceAction.search:
            query = command.query ?? ""
            await runSearch()
        case WorkspaceAction.clearSearch:
            clearSearch()
        case WorkspaceAction.select:
            if let sel = Self.parseSelection(command.target) { select(sel) }
        case WorkspaceAction.setPresentation:
            if let p = LibraryPresentation(rawValue: command.target ?? "") { setPresentation(p) }
        case WorkspaceAction.decide:
            await applyDecide(command)
        case WorkspaceAction.addFolder:
            await applyAddFolder(command)
        case WorkspaceAction.scanSource:
            if let id = command.id.flatMap(UUID.init(uuidString:)) { await onboarding.scanSource(id: id); await refresh() }
        case WorkspaceAction.pauseSource:
            if let id = command.id.flatMap(UUID.init(uuidString:)) { await onboarding.pauseSource(id: id); await refresh() }
        case WorkspaceAction.resumeSource:
            if let id = command.id.flatMap(UUID.init(uuidString:)) { await onboarding.resumeSource(id: id); await refresh() }
        case WorkspaceAction.addRule:
            _ = await rules.addBlankRule()
        case WorkspaceAction.deleteRule:
            if let id = command.id.flatMap(UUID.init(uuidString:)) { await rules.deleteRule(id: id) }
        case WorkspaceAction.toggleRule:
            if let id = command.id.flatMap(UUID.init(uuidString:)),
               let doc = rules.ruleDocuments.first(where: { $0.id == id }) {
                await rules.setRuleEnabled(id: id, !doc.enabled)
            }
        case WorkspaceAction.seedPending:
            let count = Int(command.target ?? "") ?? 1
            await pendingSeeder?(count)
            await refresh()
        case WorkspaceAction.seedMissing:
            let count = Int(command.target ?? "") ?? 1
            await missingSeeder?(count)
            await refresh()
        case WorkspaceAction.recover:
            await applyRecover(command)
        default:
            return await snapshot(error: "Unknown action: \(command.action)")
        }
        return await snapshot()
    }

    private func applyDecide(_ command: WorkspaceCommand) async {
        guard let id = command.id.flatMap(UUID.init(uuidString:)), let it = item(id) else { return }
        let kind: DecisionKind
        switch command.decision {
        case "approve": kind = .approve
        case "reject": kind = .reject
        default: kind = .keep
        }
        await performDecisionForControl(it, kind)
    }

    private func applyRecover(_ command: WorkspaceCommand) async {
        guard let id = command.id.flatMap(UUID.init(uuidString:)), let it = item(id) else { return }
        let mode: RecoveryMode
        switch command.mode {
        case "locate": mode = .locate
        case "refresh": mode = .refresh
        default: mode = .reindex
        }
        let url = command.path.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
        await performRecovery(it, mode: mode, at: url)
    }

    private func applyAddFolder(_ command: WorkspaceCommand) async {
        guard let path = command.path else { return }
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        let policy: SourceRecursivePolicy = (command.depth == "all") ? .always : .never
        await onboarding.addCustomWatchedFolder(url, recursivePolicy: policy)
        await refresh()
    }

    /// Build the current state snapshot (resolving the graph for the selection).
    public func snapshot(error: String? = nil) async -> WorkspaceSnapshot {
        let graph = await currentGraphSnapshot()
        await activity.loadRecent()
        return WorkspaceSnapshot(
            section: Self.navString(section),
            presentation: presentation.rawValue,
            selection: Self.selectionString(selection),
            query: query,
            isSearching: isSearching,
            itemCount: library.results.count,
            pendingCount: pendingCount,
            ruleCount: rules.ruleDocuments.count,
            toast: toast,
            items: library.results.prefix(100).map {
                .init(id: $0.id.uuidString, name: $0.displayName, status: $0.status.rawValue,
                      path: $0.currentPath, originalPath: $0.originalPath)
            },
            sources: sources.map {
                .init(id: $0.id.uuidString, name: $0.displayName, enabled: $0.enabled,
                      path: $0.url?.path ?? "", indexedCount: $0.lastScanSummary?.indexedCount ?? 0)
            },
            rules: rules.ruleDocuments.map { .init(id: $0.id.uuidString, name: $0.name, enabled: $0.enabled) },
            activity: activity.events.prefix(50).map {
                .init(id: $0.id.uuidString, kind: $0.kind.rawValue, message: $0.message, reversible: $0.undoOperation != nil)
            },
            graph: graph,
            lastError: error
        )
    }

    private func currentGraphSnapshot() async -> WorkspaceSnapshot.GraphSnapshot? {
        switch selection {
        case .item, .source, .cluster, .collection, .context, .overview:
            let loaded = await loadGraph(center: selection)
            return WorkspaceSnapshot.GraphSnapshot(
                center: loaded.center?.name,
                neighbors: loaded.neighbors.map {
                    .init(name: $0.name, kind: $0.kind, predicate: $0.pred, selection: Self.selectionString($0.selection))
                }
            )
        default:
            return nil
        }
    }

    // MARK: string <-> nav/selection

    static func navString(_ nav: WorkspaceNav) -> String {
        switch nav {
        case .allItems: "allItems"
        case .recents: "recents"
        case .inbox: "inbox"
        case .sources: "sources"
        case .rules: "rules"
        case .activity: "activity"
        case .source(let id): "source:\(id.uuidString)"
        case .collection(let id): "collection:\(id.uuidString)"
        }
    }

    static func parseNav(_ s: String?) -> WorkspaceNav? {
        guard let s else { return nil }
        switch s {
        case "allItems": return .allItems
        case "recents": return .recents
        case "inbox": return .inbox
        case "sources": return .sources
        case "rules": return .rules
        case "activity": return .activity
        default:
            if s.hasPrefix("source:"), let id = UUID(uuidString: String(s.dropFirst(7))) { return .source(id) }
            if s.hasPrefix("collection:"), let id = UUID(uuidString: String(s.dropFirst(11))) { return .collection(id) }
            return nil
        }
    }

    static func selectionString(_ sel: Selection) -> String {
        switch sel {
        case .none: "none"
        case .overview: "overview"
        case .item(let id): "item:\(id.uuidString)"
        case .source(let id): "source:\(id.uuidString)"
        case .context(let id): "context:\(id.uuidString)"
        case .collection(let id): "collection:\(id.uuidString)"
        case .cluster(let key): "cluster:\(key)"
        case .rule(let id): "rule:\(id.uuidString)"
        case .activity(let id): "activity:\(id.uuidString)"
        }
    }

    static func parseSelection(_ s: String?) -> Selection? {
        guard let s else { return nil }
        switch s {
        case "none": return Selection.none
        case "overview": return .overview
        default: break
        }
        let parts = s.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        let value = parts[1]
        switch parts[0] {
        case "item": return UUID(uuidString: value).map(Selection.item)
        case "source": return UUID(uuidString: value).map(Selection.source)
        case "context": return UUID(uuidString: value).map(Selection.context)
        case "collection": return UUID(uuidString: value).map(Selection.collection)
        case "cluster": return .cluster(value)
        case "rule": return UUID(uuidString: value).map(Selection.rule)
        case "activity": return UUID(uuidString: value).map(Selection.activity)
        default: return nil
        }
    }
}
