// WorkspaceModel.swift — the single observable model that drives the redesigned
// workspace (port of the blueprint's `WorkspaceModel`). It owns the cross-cutting
// UI state (section · presentation · selection · query · toast) and wraps the real
// per-feature view models, which remain the data + action layer.
import Combine
import Foundation
import SwiftUI
import BipboxCore

/// Grouped sidebar navigation target (port of the blueprint's `NavSection`).
public enum WorkspaceNav: Hashable, Sendable {
    case allItems
    case recents
    case inbox
    case sources          // source management surface ("Start" in the north star)
    case source(UUID)
    case collection(UUID)
    case rules
    case activity

    /// Library-like sections present the Gallery/Connections toggle.
    public var isLibraryLike: Bool {
        switch self {
        case .allItems, .recents, .source, .collection: true
        case .inbox, .sources, .rules, .activity: false
        }
    }
}

@MainActor
public final class WorkspaceModel: ObservableObject {
    // Cross-cutting UI state (the blueprint's published surface).
    @Published public var section: WorkspaceNav = .allItems
    // Default to Gallery so real files are the first thing the user sees; the
    // Connections graph is one toggle away (north star: Library is primary).
    @Published public var presentation: LibraryPresentation = .gallery
    @Published public var selection: Selection = .overview
    @Published public var query: String = ""
    @Published public var toast: String?

    /// Injected capture hook (drag-drop → real drop intake handler).
    public var onDropURLs: ([URL]) -> Void = { _ in }

    /// Test/automation hook: index N pending (`needsReview`) items so the Inbox
    /// decision flow can be exercised deterministically. Wired by the app/harness.
    public var pendingSeeder: ((Int) async -> Void)?

    /// Test/automation hook: index N `.missing` items (backed by real temp files)
    /// so missing-file recovery can be exercised deterministically.
    public var missingSeeder: ((Int) async -> Void)?

    // Real data + action layer.
    public let library: SearchWorkspaceViewModel
    public let reviewQueue: ReviewQueueViewModel
    public let rules: RulesWorkspaceViewModel
    public let activity: ActivityWorkspaceViewModel
    public let onboarding: OnboardingWorkspaceViewModel
    public let settings: SettingsWorkspaceViewModel

    /// Real graph services that back the Connections view (nil in fixtures/tests,
    /// where the graph falls back to library-results-only neighbors).
    let graphServices: WorkspaceGraphServices?

    private var cancellables: Set<AnyCancellable> = []

    public init(_ viewModels: WorkspaceViewModels, graphServices: WorkspaceGraphServices? = nil) {
        self.library = viewModels.library
        self.reviewQueue = viewModels.reviewQueue
        self.rules = viewModels.rules
        self.activity = viewModels.activity
        self.onboarding = viewModels.onboarding
        self.settings = viewModels.settings
        self.graphServices = graphServices

        // Re-publish nested view-model changes so views that observe only this
        // model (sidebar source rows, Inbox badge, rules count) stay in sync.
        for publisher in [
            library.objectWillChange, reviewQueue.objectWillChange, rules.objectWillChange,
            activity.objectWillChange, onboarding.objectWillChange
        ] {
            publisher
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.objectWillChange.send() }
                .store(in: &cancellables)
        }
    }

    // MARK: search

    public var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: items for a section

    /// The library item set backing a section's center presentation.
    public func items(for section: WorkspaceNav) -> [IndexedItem] {
        switch section {
        case .allItems:
            return library.results
        case .recents:
            return library.results
                .sorted { $0.importedAt > $1.importedAt }
        case .inbox:
            return library.results.filter { $0.status == .needsReview }
        case .source(let id):
            return library.results.filter { sourceID(of: $0) == id }
        case .collection:
            // Collection membership comes from the graph; Tier-0 shows all items.
            return library.results
        case .sources, .rules, .activity:
            return []
        }
    }

    /// Resolve an item's originating source id from its metadata, if available.
    func sourceID(of item: IndexedItem) -> UUID? {
        retrieval(for: item.id)?.knowledgeItem?.sourceID
    }

    func retrieval(for id: UUID) -> RetrievalResult? {
        library.retrievalResults.first { $0.item.id == id }
    }

    func item(_ id: UUID) -> IndexedItem? {
        library.results.first { $0.id == id }
    }

    // MARK: navigation

    public func go(_ section: WorkspaceNav) {
        self.section = section
        switch section {
        case .rules:
            selection = rules.ruleDocuments.first.map { .rule($0.id) } ?? .none
        case .activity:
            selection = activity.events.first.map { .activity($0.id) } ?? .none
        case .inbox:
            selection = items(for: .inbox).first.map { .item($0.id) } ?? .none
        case .sources:
            selection = .none
        case .source(let id):
            selection = .source(id)
        case .collection(let id):
            selection = .collection(id)
        case .allItems, .recents:
            selection = (presentation == .gallery)
                ? (items(for: section).first.map { .item($0.id) } ?? .none)
                : .overview
        }
    }

    public func setPresentation(_ p: LibraryPresentation) {
        presentation = p
        if p == .gallery, case .overview = selection {
            selection = items(for: section).first.map { .item($0.id) } ?? .none
        }
    }

    public func select(_ s: Selection) {
        selection = s
    }

    // MARK: decisions (route through the real review queue)

    /// Approve / keep / reject a pending item. Routes to `ReviewQueueViewModel`
    /// when the item exists in the queue; otherwise records a local toast.
    public func decide(_ item: IndexedItem, _ kind: DecisionKind) {
        Task { await performDecision(item, kind) }
    }

    /// Awaitable decision used by the programmatic control surface.
    func performDecisionForControl(_ item: IndexedItem, _ kind: DecisionKind) async {
        await performDecision(item, kind)
    }

    private func performDecision(_ item: IndexedItem, _ kind: DecisionKind) async {
        // Best-effort match against the live review queue by underlying item id.
        if let queued = reviewQueue.items.first(where: { $0.indexedItem?.id == item.id }) {
            reviewQueue.select(id: queued.id)
            switch kind {
            case .approve: await reviewQueue.approveSelected()
            case .keep: await reviewQueue.leaveSelectedInInbox(message: "Kept for later.")
            case .reject: await reviewQueue.rejectSelected(message: "Rejected.")
            }
        }
        // Re-pull the library so the decided item leaves the Inbox list and its
        // new status is reflected everywhere (the queue and search index diverge
        // otherwise — the inbox reads library.results, not the queue).
        await library.search()
        flash(kind.toast(for: item.displayName))
        // Advance to the next pending item when triaging the inbox.
        if section == .inbox {
            selection = items(for: .inbox).first { $0.id != item.id }.map { .item($0.id) } ?? .none
        }
    }

    // MARK: search wiring (toolbar query drives the real search VM)

    /// Populate the library, sources, and review queue on first appearance.
    public func loadInitial() async {
        await library.search()
        await onboarding.load()
        await reviewQueue.load()
    }

    public func runSearch() async {
        library.searchText = query
        await library.search()
        selection = library.results.first.map { .item($0.id) } ?? .none
    }

    public func clearSearch() {
        query = ""
        library.searchText = ""
        selection = .overview
        Task { await library.search() }
    }

    // MARK: capture

    /// Capture dropped file URLs through the real drop-intake handler, then
    /// refresh the library so the new items appear.
    public func receiveDroppedURLs(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        onDropURLs(urls)
        flash(urls.count == 1 ? "Capturing 1 item…" : "Capturing \(urls.count) items…")
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            await refresh()
        }
    }

    // MARK: missing-file recovery (safety: missing items stay recoverable)

    public enum RecoveryMode: String, Sendable { case locate, reindex, refresh }

    /// Recover a missing/failed item, then refresh so its new status shows.
    public func recoverItem(_ item: IndexedItem, mode: RecoveryMode, at url: URL? = nil) {
        Task { await performRecovery(item, mode: mode, at: url) }
    }

    func performRecovery(_ item: IndexedItem, mode: RecoveryMode, at url: URL?) async {
        library.select(item)
        switch mode {
        case .locate:
            if let url { await library.locateSelectedItem(at: url) }
        case .reindex:
            await library.reindexSelectedItem()
        case .refresh:
            await library.refreshSelectedItemStatus()
        }
        await refresh()
    }

    /// Re-pull library + sources + queue (after a capture/scan).
    public func refresh() async {
        await library.search()
        await onboarding.load()
        await reviewQueue.load()
    }

    /// True until the user has configured at least one watched source — drives
    /// the first-run guidance.
    public var hasNoSources: Bool { onboarding.sources.isEmpty }

    /// Open a folder picker, ask how deep to index, then add it as a watched source.
    public func addWatchedFolderViaPanel() {
        guard let url = WorkspaceModel.chooseFolder() else { return }
        guard let policy = WorkspaceModel.askIndexDepth(for: url) else { return }
        flash("Adding \(url.lastPathComponent)…")
        Task {
            await onboarding.addCustomWatchedFolder(url, recursivePolicy: policy)
            await refresh()
        }
    }

    static func chooseFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Watch Folder"
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// Ask the user how deep to index a folder. Returns nil if cancelled.
    /// Top level → `.never` (subfolders captured as single items, not walked);
    /// Everything inside → `.always` (recurse into every subfolder).
    static func askIndexDepth(for url: URL) -> SourceRecursivePolicy? {
        let alert = NSAlert()
        alert.messageText = "How deep should Bipbox index “\(url.lastPathComponent)”?"
        alert.informativeText = """
        Top level only: index the files and folders directly inside, capturing each subfolder as one item.
        Everything inside: recurse into every subfolder and index all files (slower for large trees).
        """
        alert.addButton(withTitle: "Top level only")   // .alertFirstButtonReturn
        alert.addButton(withTitle: "Everything inside") // .alertSecondButtonReturn
        alert.addButton(withTitle: "Cancel")            // .alertThirdButtonReturn
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .never
        case .alertSecondButtonReturn: return .always
        default: return nil
        }
    }

    public func flash(_ message: String) {
        toast = message
        Task {
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            if toast == message { toast = nil }
        }
    }
}

// MARK: - Display helpers over real models

extension WorkspaceModel {
    /// Sidebar Inbox badge — pending decisions from the live review queue.
    var pendingCount: Int { reviewQueue.pendingCount }

    /// Watched folders (the only place sources live now).
    var sources: [SourceRecord] { onboarding.sources }

    func isPending(_ item: IndexedItem) -> Bool { item.status == .needsReview }

    func symbol(for item: IndexedItem) -> String { item.kind.symbolName }

    func source(for item: IndexedItem) -> SourceRecord? {
        guard let sid = sourceID(of: item) else { return nil }
        return onboarding.sources.first { $0.id == sid }
    }

    func sourceName(for item: IndexedItem) -> String {
        source(for: item)?.displayName ?? "Library"
    }

    func sourceColor(for item: IndexedItem) -> Color {
        if let sid = sourceID(of: item) { return BBPalette.color(for: sid) }
        return BB.ink3
    }

    func why(for item: IndexedItem) -> String { library.matchExplanation(for: item) }

    func dateString(for item: IndexedItem) -> String {
        Self.dateFormatter.string(from: item.importedAt)
    }

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    // MARK: inspector data (contexts / related for the selected item)

    var selectedOverview: RelatedContextOverview? { library.relatedContextOverview }
    var selectedRelated: [RelatedItem] { library.relatedItems }

    /// Load the context/related graph for whatever item is currently selected.
    func loadInspectorData() async {
        guard case .item(let id) = selection, let it = item(id) else { return }
        library.select(it)
        await library.loadContextForSelected()
    }

    // MARK: Tier-0 clusters
    //
    // There is no embedding/semantic model yet (that is Tier-1 per the north
    // star). Grouping by `tags.first` was degenerate: real scanned files rarely
    // carry Finder tags, so everything collapsed into one "untagged" orb and the
    // overview drew no edges. Tier-0 instead groups by **type category** (always
    // populated, discriminating) and links categories that **co-occur in the same
    // folder** (a real structural signal). Honest label: "by type & location".

    private static let categoryOrder = [
        "Folders", "Documents", "Spreadsheets", "Presentations", "Images",
        "Video", "Audio", "Code", "Archives", "Packages", "Other"
    ]

    /// Broad, always-available type bucket for an item.
    func typeCategory(for item: IndexedItem) -> String {
        switch item.kind {
        case .folder: return "Folders"
        case .package, .bundle: return "Packages"
        default: break
        }
        let ext = (item.currentPath as NSString).pathExtension.lowercased()
        let uti = item.uniformTypeIdentifier?.lowercased() ?? ""
        func has(_ set: Set<String>) -> Bool { set.contains(ext) }
        if uti.contains("pdf") || has(["pdf", "doc", "docx", "pages", "txt", "md", "rtf", "odt"]) { return "Documents" }
        if has(["csv", "xls", "xlsx", "numbers", "tsv"]) { return "Spreadsheets" }
        if has(["key", "ppt", "pptx"]) { return "Presentations" }
        if uti.contains("image") || has(["png", "jpg", "jpeg", "gif", "heic", "webp", "svg", "tiff", "bmp"]) { return "Images" }
        if uti.contains("movie") || uti.contains("video") || has(["mp4", "mov", "m4v", "avi", "mkv", "webm"]) { return "Video" }
        if uti.contains("audio") || has(["mp3", "wav", "aac", "m4a", "flac", "aiff"]) { return "Audio" }
        if has(["swift", "js", "ts", "tsx", "py", "java", "c", "cpp", "h", "hpp", "rb", "go", "rs", "json", "yaml", "yml", "html", "css", "sh", "kt"]) { return "Code" }
        if has(["zip", "dmg", "tar", "gz", "tgz", "rar", "7z", "bz2"]) { return "Archives" }
        return "Other"
    }

    private func categoryColor(_ name: String) -> Color {
        BBPalette.color(for: Self.categoryOrder.firstIndex(of: name) ?? 0)
    }

    public var clusters: [LibraryCluster] {
        var buckets: [String: [UUID]] = [:]
        for it in library.results {
            buckets[typeCategory(for: it), default: []].append(it.id)
        }
        return buckets.keys
            .sorted { (Self.categoryOrder.firstIndex(of: $0) ?? 99) < (Self.categoryOrder.firstIndex(of: $1) ?? 99) }
            .map { key in LibraryCluster(id: key, name: key, color: categoryColor(key), itemIDs: buckets[key] ?? []) }
    }

    func cluster(_ id: String) -> LibraryCluster? { clusters.first { $0.id == id } }
    public func clusterOf(_ itemID: UUID) -> LibraryCluster? { clusters.first { $0.itemIDs.contains(itemID) } }

    // MARK: hub (source / collection / cluster / context) metadata + members

    func nodeMeta(_ sel: Selection) -> NodeMeta? {
        switch sel {
        case .source(let id):
            let s = sources.first { $0.id == id }
            return NodeMeta(name: s?.displayName ?? "Folder", kind: "watched folder",
                            color: BBPalette.color(for: id), symbol: "folder.fill", type: .source)
        case .cluster(let key):
            let c = cluster(key)
            return NodeMeta(name: c?.name ?? "Cluster", kind: "similarity group",
                            color: c?.color ?? BB.grape, symbol: "square.stack.3d.up", type: .cluster)
        case .collection:
            return NodeMeta(name: "Collection", kind: "collection", color: BB.warn, symbol: "bookmark.fill", type: .collection)
        case .context:
            return NodeMeta(name: "Context", kind: "context", color: BB.grape, symbol: "number", type: .context)
        default:
            return nil
        }
    }

    func nodeMembers(_ sel: Selection) -> [IndexedItem] {
        switch sel {
        case .source(let id):
            return library.results.filter { sourceID(of: $0) == id }
        case .cluster(let key):
            return (cluster(key)?.itemIDs ?? []).compactMap { item($0) }
        case .collection, .context:
            return []
        default:
            return []
        }
    }
}

/// A Tier-0 similarity cluster (tag-based grouping until embeddings land).
public struct LibraryCluster: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let color: Color
    public let itemIDs: [UUID]
}

// MARK: - Graph adapters (drive ConnectionsView from real, already-loaded data)

/// One edge from the centered node to a neighbor, with display + nav info.
public struct GraphNeighbor: Identifiable, Sendable {
    public let id: String
    public let selection: Selection
    public let name: String
    public let kind: String
    public let color: Color
    public let symbol: String
    public let pred: String      // edge label
    public let strength: Double  // 0…1, line width
    public let category: String  // filter-chip bucket
    public let hubCount: Int     // >1 → hub badge
}

/// The card at the center of an ego graph.
public struct GraphCenter: Sendable {
    public let name: String
    public let symbol: String
    public let color: Color
    public let kind: String
    public let isItem: Bool
}

extension WorkspaceModel {
    /// Metadata for the node currently centered in the ego graph.
    func graphCenter(for sel: Selection) -> GraphCenter? {
        switch sel {
        case .item(let id):
            guard let it = item(id) else { return nil }
            return GraphCenter(name: it.displayName, symbol: symbol(for: it),
                               color: BB.accent, kind: it.kind.rawValue, isItem: true)
        case .source, .cluster, .collection, .context:
            guard let m = nodeMeta(sel) else { return nil }
            return GraphCenter(name: m.name, symbol: m.symbol, color: m.color, kind: m.kind, isItem: false)
        default:
            return nil
        }
    }

    /// Neighbors of the centered node, built from data already loaded into the
    /// view models (graph overview for items, member lists for hubs).
    func graphNeighbors(for sel: Selection) -> [GraphNeighbor] {
        switch sel {
        case .item(let id):
            return itemNeighbors(id)
        case .source, .cluster, .collection, .context:
            return nodeMembers(sel).map { memberNeighbor($0) }
        default:
            return []
        }
    }

    private func itemNeighbors(_ id: UUID) -> [GraphNeighbor] {
        guard let it = item(id) else { return [] }
        var out: [GraphNeighbor] = []

        // Source it came from.
        if let sid = sourceID(of: it), let src = sources.first(where: { $0.id == sid }) {
            out.append(GraphNeighbor(id: "src:\(sid)", selection: .source(sid), name: src.displayName,
                                     kind: "watched folder", color: BBPalette.color(for: sid),
                                     symbol: "folder.fill", pred: "came from", strength: 0.55,
                                     category: "Sources", hubCount: nodeMembers(.source(sid)).count))
        }

        // Contexts (only when the loaded overview is for this item).
        if let overview = selectedOverview, overview.itemID == id {
            for rel in overview.contexts {
                let c = rel.context
                out.append(GraphNeighbor(id: "ctx:\(c.id)", selection: .context(c.id), name: c.name,
                                         kind: c.kind.rawValue, color: BB.grape, symbol: contextSymbol(c.kind),
                                         pred: contextPredicate(c.kind), strength: 0.9,
                                         category: contextCategory(c.kind), hubCount: 0))
            }
        }

        // Similar / related files.
        for rel in selectedRelated.prefix(5) where rel.item.id != id {
            out.append(GraphNeighbor(id: "item:\(rel.item.id)", selection: .item(rel.item.id),
                                     name: rel.item.displayName, kind: "file",
                                     color: clusterOf(rel.item.id)?.color ?? BB.ink2,
                                     symbol: symbol(for: rel.item), pred: "related",
                                     strength: min(1, max(0.3, rel.score)), category: "Files", hubCount: 0))
        }

        // Cluster it belongs to.
        if let cl = clusterOf(id) {
            out.append(GraphNeighbor(id: "cluster:\(cl.id)", selection: .cluster(cl.id), name: cl.name,
                                     kind: "similarity group", color: cl.color, symbol: "square.stack.3d.up",
                                     pred: "in group", strength: 0.7, category: "Groups", hubCount: cl.itemIDs.count))
        }
        return out
    }

    private func memberNeighbor(_ it: IndexedItem) -> GraphNeighbor {
        GraphNeighbor(id: "item:\(it.id)", selection: .item(it.id), name: it.displayName, kind: "file",
                      color: clusterOf(it.id)?.color ?? BB.ink2, symbol: symbol(for: it),
                      pred: "member", strength: 0.6, category: "Files", hubCount: 0)
    }

    private func contextSymbol(_ k: ContextKind) -> String {
        switch k {
        case .person: "person"
        case .project: "folder.badge.gearshape"
        case .topic: "number"
        case .organization: "building.2"
        default: "tag"
        }
    }
    private func contextPredicate(_ k: ContextKind) -> String {
        switch k {
        case .person: "mentions"
        case .topic: "about"
        default: "belongs to"
        }
    }
    private func contextCategory(_ k: ContextKind) -> String {
        switch k {
        case .person: "People"
        case .project: "Projects"
        case .topic: "Topics"
        default: "Topics"
        }
    }

    /// Cluster edges weighted by how many **folders** two type-categories share.
    /// (Type clusters are disjoint by item, so item-overlap is always zero; folder
    /// co-occurrence is the real structural signal — e.g. a project folder holding
    /// code + docs + images links those three clusters.)
    public func clusterLinks() -> [(Int, Int, Int)] {
        let cls = clusters
        guard cls.count > 1 else { return [] }
        var indexByName: [String: Int] = [:]
        for (i, c) in cls.enumerated() { indexByName[c.id] = i }

        var categoriesByFolder: [String: Set<Int>] = [:]
        for it in library.results {
            let folder = (it.currentPath as NSString).deletingLastPathComponent
            if let ci = indexByName[typeCategory(for: it)] {
                categoriesByFolder[folder, default: []].insert(ci)
            }
        }

        var pairCounts: [Int: Int] = [:]   // (i * cls.count + j) -> shared folder count
        for (_, cats) in categoriesByFolder {
            let arr = cats.sorted()
            guard arr.count > 1 else { continue }
            for a in 0..<arr.count {
                for b in (a + 1)..<arr.count {
                    pairCounts[arr[a] * cls.count + arr[b], default: 0] += 1
                }
            }
        }
        return pairCounts.map { key, count in (key / cls.count, key % cls.count, count) }
    }
}

// MARK: - Real graph services + async graph loading

/// The services the Connections view needs to load real neighbors per node.
public struct WorkspaceGraphServices {
    public let graph: KnowledgeGraphService
    public let relatedness: RelatednessService
    public let store: KnowledgeStore
    public init(graph: KnowledgeGraphService, relatedness: RelatednessService, store: KnowledgeStore) {
        self.graph = graph
        self.relatedness = relatedness
        self.store = store
    }
}

/// A fully-resolved graph for one centered node — what the view renders.
public struct LoadedGraph: Sendable {
    public var center: GraphCenter?
    public var neighbors: [GraphNeighbor]
    public init(center: GraphCenter?, neighbors: [GraphNeighbor]) {
        self.center = center
        self.neighbors = neighbors
    }
}

extension WorkspaceModel {
    /// Load the graph centered on `sel`, fetching real neighbors from the graph /
    /// relatedness services. Source and cluster hubs resolve synchronously from the
    /// loaded library; item / context / collection nodes query the live graph.
    public func loadGraph(center sel: Selection) async -> LoadedGraph {
        switch sel {
        case .item(let id):
            return await loadItemGraph(id)
        case .context(let id):
            return await loadContextGraph(id)
        case .collection(let id):
            return await loadCollectionGraph(id)
        case .source, .cluster:
            return LoadedGraph(center: graphCenter(for: sel), neighbors: graphNeighbors(for: sel))
        default:
            return LoadedGraph(center: nil, neighbors: [])
        }
    }

    private func loadItemGraph(_ id: UUID) async -> LoadedGraph {
        // Center from the library item, else the knowledge store.
        var center = graphCenter(for: .item(id))
        if center == nil, let ki = try? await graphServices?.store.knowledgeItem(id: id) {
            center = GraphCenter(name: ki.displayName, symbol: ki.kind.symbolName, color: BB.accent, kind: ki.kind.rawValue, isItem: true)
        }
        guard let services = graphServices else {
            // Fixture/test fallback: synchronous, library-only neighbors.
            return LoadedGraph(center: center, neighbors: graphNeighbors(for: .item(id)))
        }

        var neighbors: [GraphNeighbor] = []

        // Source it came from.
        if let ki = try? await services.store.knowledgeItem(id: id), let sid = ki.sourceID,
           let src = sources.first(where: { $0.id == sid }) {
            neighbors.append(GraphNeighbor(id: "src:\(sid)", selection: .source(sid), name: src.displayName,
                                           kind: "watched folder", color: BBPalette.color(for: sid),
                                           symbol: "folder.fill", pred: "came from", strength: 0.55,
                                           category: "Sources", hubCount: nodeMembers(.source(sid)).count))
        }

        // Contexts (folder / topic / person / project) from the live graph.
        if let contexts = try? await services.graph.contexts(relatedTo: id) {
            for rel in contexts {
                let c = rel.context
                neighbors.append(GraphNeighbor(id: "ctx:\(c.id)", selection: .context(c.id), name: c.name,
                                               kind: c.kind.rawValue, color: BB.grape, symbol: contextSymbol(c.kind),
                                               pred: contextPredicate(c.kind), strength: 0.9,
                                               category: contextCategory(c.kind), hubCount: 0))
            }
        }

        // Related files from the relatedness service.
        if let related = try? await services.relatedness.relatedItems(to: id, limit: 6) {
            for r in related where r.item.id != id {
                neighbors.append(GraphNeighbor(id: "item:\(r.item.id)", selection: .item(r.item.id),
                                               name: r.item.displayName, kind: "file",
                                               color: clusterOf(r.item.id)?.color ?? BB.ink2,
                                               symbol: symbol(for: r.item), pred: "related",
                                               strength: min(1, max(0.3, r.score)), category: "Files", hubCount: 0))
            }
        }

        // Tier-0 type cluster it belongs to.
        if let cl = clusterOf(id) {
            neighbors.append(GraphNeighbor(id: "cluster:\(cl.id)", selection: .cluster(cl.id), name: cl.name,
                                           kind: "type group", color: cl.color, symbol: "square.stack.3d.up",
                                           pred: "in group", strength: 0.7, category: "Groups", hubCount: cl.itemIDs.count))
        }

        return LoadedGraph(center: center, neighbors: neighbors)
    }

    private func loadContextGraph(_ id: UUID) async -> LoadedGraph {
        guard let services = graphServices else { return LoadedGraph(center: nil, neighbors: []) }
        let context = try? await services.graph.context(id: id)
        let center = context.map {
            GraphCenter(name: $0.name, symbol: contextSymbol($0.kind), color: BB.grape, kind: $0.kind.rawValue, isItem: false)
        }
        var neighbors: [GraphNeighbor] = []
        if let edges = try? await services.graph.relationships(objectID: id) {
            let itemIDs = edges.filter { $0.subjectKind == .knowledgeItem }.map(\.subjectID)
            for itemID in Array(Set(itemIDs)).prefix(40) {
                if let n = await resolveItemNeighbor(itemID, pred: "in", strength: 0.7) {
                    neighbors.append(n)
                }
            }
        }
        return LoadedGraph(center: center, neighbors: neighbors)
    }

    private func loadCollectionGraph(_ id: UUID) async -> LoadedGraph {
        guard let services = graphServices else { return LoadedGraph(center: nil, neighbors: []) }
        let collection = try? await services.graph.collection(id: id)
        let center = collection.map {
            GraphCenter(name: $0.name, symbol: "bookmark.fill", color: BB.warn, kind: "collection", isItem: false)
        }
        var neighbors: [GraphNeighbor] = []
        if let itemIDs = try? await services.graph.itemIDs(inCollection: id) {
            for itemID in itemIDs.prefix(40) {
                if let n = await resolveItemNeighbor(itemID, pred: "in collection", strength: 0.6) {
                    neighbors.append(n)
                }
            }
        }
        return LoadedGraph(center: center, neighbors: neighbors)
    }

    /// Resolve an item id into a graph neighbor, preferring the loaded library
    /// item and falling back to the knowledge store.
    private func resolveItemNeighbor(_ id: UUID, pred: String, strength: Double) async -> GraphNeighbor? {
        if let it = item(id) {
            return GraphNeighbor(id: "item:\(id)", selection: .item(id), name: it.displayName, kind: "file",
                                 color: clusterOf(id)?.color ?? BB.ink2, symbol: symbol(for: it),
                                 pred: pred, strength: strength, category: "Files", hubCount: 0)
        }
        if let ki = try? await graphServices?.store.knowledgeItem(id: id) {
            return GraphNeighbor(id: "item:\(id)", selection: .item(id), name: ki.displayName, kind: "file",
                                 color: BB.ink2, symbol: ki.kind.symbolName,
                                 pred: pred, strength: strength, category: "Files", hubCount: 0)
        }
        return nil
    }
}

public enum NodeType: Sendable { case item, source, context, collection, cluster }

public struct NodeMeta: Sendable {
    public let name: String
    public let kind: String
    public let color: Color
    public let symbol: String
    public let type: NodeType
}

public enum DecisionKind: Sendable {
    case approve, keep, reject

    func toast(for name: String) -> String {
        switch self {
        case .approve: "Approved — \(name) filed."
        case .keep: "Kept \(name) where it is."
        case .reject: "Rejected suggestion for \(name)."
        }
    }
}
