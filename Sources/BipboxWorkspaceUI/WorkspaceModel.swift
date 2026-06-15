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

    /// How the Connections graph groups items (the quiet "Group by" switch).
    @Published public var lens: LibraryLens = .smart
    /// Cached clusters for the current lens (recomputed async; semantic clustering
    /// is async, so this is a stored cache rather than a live computed value).
    @Published public private(set) var clusters: [LibraryCluster] = []
    /// Topic<->topic edges (semantic centroid similarity) backing the current `clusters`.
    private var topicEdges: [(a: Int, b: Int, weight: Double)] = []

    // MARK: semantic index (the one source of truth for the 4 clean relations)
    // Built once from the embeddings, reused for topic discovery AND item-level
    // cosine neighbors so weights are consistent across the graph and inspector.
    private var semVectors: [UUID: [Float]] = [:]        // mean-centered + unit-normalized
    private var semGraph: TopicGraph = .empty            // topics + soft membership + edges
    private var semCentroids: [Int: [Float]] = [:]       // topic centroids in semVectors space
    private var semLoaded = false
    /// Long-running indexing work (first scan / embedding backfill) rendered as
    /// the sidebar status line with "n of m" + ETA. Nil when idle.
    @Published public private(set) var indexingActivity: IndexingActivity?

    /// The selected item's relations (the 4 clean edges), resolved once per
    /// selection and published so the inspector reads them without recomputing
    /// cosine on every redraw.
    @Published public private(set) var inspectorSimilar: [(item: IndexedItem, score: Double)] = []
    @Published public private(set) var inspectorTopics: [(cluster: LibraryCluster, weight: Double)] = []
    @Published public private(set) var inspectorContainer: IndexedItem?
    @Published public private(set) var inspectorContents: [IndexedItem] = []
    @Published public private(set) var inspectorDuplicates: [IndexedItem] = []

    /// Report (or clear) indexing progress. Throttled by callers; preserves the
    /// original start time while the same kind of work continues so the ETA is
    /// computed over the whole run, not the latest slice.
    public func reportIndexing(kind: IndexingActivity.Kind?, completed: Int = 0, total: Int = 0) {
        guard let kind, total > 0, completed < total else {
            indexingActivity = nil
            return
        }
        let startedAt = (indexingActivity?.kind == kind) ? indexingActivity!.startedAt : Date()
        indexingActivity = IndexingActivity(kind: kind, completed: completed, total: total, startedAt: startedAt)
    }

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
        // Resolve from the current library page first, then fall back to the
        // related/overview caches so selecting a Related row whose item isn't on
        // the current page still opens a real inspector (not the empty state).
        library.results.first { $0.id == id }
            ?? library.relatedItems.first { $0.item.id == id }?.item
    }

    // MARK: inspector target (open / reveal / copy for the current selection)

    /// The on-disk URL the inspector header acts on for the current selection:
    /// an item's path, or a watched source's folder. Nil when there's nothing
    /// file-backed to act on (overview, rules, activity, …).
    public var inspectorTargetURL: URL? {
        switch selection {
        case .item(let id):
            return item(id).map { URL(fileURLWithPath: $0.currentPath) }
        case .source(let id):
            return sources.first { $0.id == id }?.url
        default:
            return nil
        }
    }

    func openSelectionExternally() {
        guard let url = inspectorTargetURL else { return }
        NSWorkspace.shared.open(url)
    }

    func revealSelectionInFinder() {
        guard let url = inspectorTargetURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func copySelectionPath() {
        guard let url = inspectorTargetURL else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path, forType: .string)
        flash("Copied path")
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
        guard s != selection else { return }
        backStack.append(selection)
        if backStack.count > 50 { backStack.removeFirst() }
        forwardStack.removeAll()
        selection = s
    }

    // MARK: back / forward history + sidebar toggle (toolbar chrome)

    @Published public var sidebarVisible = true
    private var backStack: [Selection] = []
    private var forwardStack: [Selection] = []
    public var canGoBack: Bool { !backStack.isEmpty }
    public var canGoForward: Bool { !forwardStack.isEmpty }

    public func goBack() {
        guard let previous = backStack.popLast() else { return }
        forwardStack.append(selection)
        selection = previous
    }

    public func goForward() {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(selection)
        selection = next
    }

    public func toggleSidebar() {
        sidebarVisible.toggle()
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
        await recomputeClusters()
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
        invalidateSemanticIndex()   // library/embeddings may have changed
        await recomputeClusters()
        await onboarding.load()
        await reviewQueue.load()
    }

    /// True until the user has configured at least one watched source — drives
    /// the first-run guidance.
    public var hasNoSources: Bool { onboarding.sources.isEmpty }

    /// Open a folder picker, classify what it is, and capture it with a smart
    /// default (no "top level vs deep" interrogation — we detect and just do it).
    public func addWatchedFolderViaPanel() {
        guard let url = WorkspaceModel.chooseFolder() else { return }
        let classification = DefaultTargetClassifier().classify(url: url)
        flash("Adding \(url.lastPathComponent) as \(classification.nature.displayName)…")
        Task {
            await onboarding.addCustomWatchedFolder(url, recursivePolicy: classification.recommendedPolicy)
            await refresh()
        }
    }

    /// Classify a folder's nature (for the smart-capture default + UI labels).
    public static func classify(_ url: URL) -> TargetClassification {
        DefaultTargetClassifier().classify(url: url)
    }

    static func chooseFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Watch Folder"
        return panel.runModal() == .OK ? panel.url : nil
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

    // MARK: inspector data — the 4 clean relations for the selected item

    var selectedOverview: RelatedContextOverview? { library.relatedContextOverview }
    var selectedRelated: [RelatedItem] { library.relatedItems }

    /// Resolve the inspector relations for the selected item (semantic index +
    /// the four resolvers). Called from the inspector's `.task(id:)`.
    public func prepareInspector(for id: UUID) async {
        await ensureSemanticIndex()
        guard case .item(id) = selection else { return }   // selection moved on
        inspectorSimilar = similarItems(to: id, limit: 6).compactMap { s in
            item(s.id).map { (item: $0, score: s.score) }
        }
        inspectorTopics = topicMemberships(for: id)
        inspectorContainer = containingUnit(of: id)
        let it = item(id)
        inspectorContents = (it?.tags.contains("unit:collection") == true || it?.tags.contains("unit:project") == true)
            ? containedItems(of: id) : []
        inspectorDuplicates = duplicates(of: id)
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

    /// Tier-0 clusters: group by type category (used by the Type lens + as the
    /// fallback when no embeddings are available).
    func typeClusters() -> [LibraryCluster] {
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

    /// The clean item neighborhood: only the four meaningful relations —
    /// `similar` (cosine), `hasTopic`, `contains` (parent project/collection),
    /// `duplicate`. Provenance (source/folder/path) is NOT here; it lives in the
    /// inspector's Details.
    private func itemNeighbors(_ id: UUID) -> [GraphNeighbor] {
        guard item(id) != nil else { return [] }
        var out: [GraphNeighbor] = []

        // Topic(s) it belongs to — the anchor(s), weighted by closeness to centroid.
        for (cl, weight) in topicMemberships(for: id) {
            out.append(GraphNeighbor(id: "cluster:\(cl.id)", selection: .cluster(cl.id), name: cl.name,
                                     kind: "topic", color: cl.color, symbol: "square.stack.3d.up",
                                     pred: "topic", strength: weight, category: "Topics",
                                     hubCount: cl.itemIDs.count))
        }

        // Most similar files (vector cosine), distance/thickness = strength.
        for sim in similarItems(to: id, limit: 8) {
            guard let other = item(sim.id) else { continue }
            out.append(GraphNeighbor(id: "item:\(sim.id)", selection: .item(sim.id),
                                     name: other.displayName, kind: "file",
                                     color: clusterOf(sim.id)?.color ?? BB.ink2,
                                     symbol: symbol(for: other), pred: "similar",
                                     strength: sim.score, category: "Similar", hubCount: 0))
        }

        // Containing project / collection (structural drill-up).
        if let unit = containingUnit(of: id) {
            out.append(GraphNeighbor(id: "item:\(unit.id)", selection: .item(unit.id), name: unit.displayName,
                                     kind: unit.tags.contains("unit:project") ? "project" : "collection",
                                     color: BB.grape, symbol: "folder.fill", pred: "in", strength: 0.85,
                                     category: "Container", hubCount: 0))
        }

        // If THIS item is itself a project/collection, list its members (drill-down).
        if let it = item(id), it.tags.contains("unit:collection") || it.tags.contains("unit:project") {
            for member in containedItems(of: id).prefix(12) {
                out.append(GraphNeighbor(id: "item:\(member.id)", selection: .item(member.id),
                                         name: member.displayName, kind: "file",
                                         color: clusterOf(member.id)?.color ?? BB.ink2,
                                         symbol: symbol(for: member), pred: "contains", strength: 0.6,
                                         category: "Contents", hubCount: 0))
            }
        }

        // Exact duplicates (same byte fingerprint).
        for dup in duplicates(of: id) {
            out.append(GraphNeighbor(id: "item:\(dup.id)", selection: .item(dup.id), name: dup.displayName,
                                     kind: "file", color: BB.ink2, symbol: "doc.on.doc",
                                     pred: "duplicate", strength: 1.0, category: "Duplicates", hubCount: 0))
        }
        return out
    }

    // MARK: - the four clean relations (resolved from the semantic index)

    /// Top-`limit` files by cosine over the mean-centered embeddings.
    public func similarItems(to id: UUID, limit: Int) -> [(id: UUID, score: Double)] {
        guard let v = semVectors[id], !v.isEmpty else { return [] }
        var scored: [(UUID, Double)] = []
        scored.reserveCapacity(semVectors.count)
        for (oid, ov) in semVectors where oid != id && ov.count == v.count {
            var s: Float = 0
            for d in 0..<v.count { s += v[d] * ov[d] }
            if s > 0 { scored.append((oid, Double(s))) }
        }
        return scored.sorted { $0.1 > $1.1 }.prefix(limit).map { (id: $0.0, score: $0.1) }
    }

    /// Topics the item belongs to (soft membership), weighted by cosine-to-centroid.
    public func topicMemberships(for id: UUID) -> [(cluster: LibraryCluster, weight: Double)] {
        guard let topicIdxs = semGraph.membership[id], let v = semVectors[id] else { return [] }
        var out: [(LibraryCluster, Double)] = []
        for ti in topicIdxs {
            guard let cl = clusters.first(where: { $0.id == "topic:\(ti)" }) else { continue }
            var w = 0.7
            if let c = semCentroids[ti], c.count == v.count {
                var s: Float = 0; for d in 0..<v.count { s += v[d] * c[d] }; w = Double(max(0, s))
            }
            out.append((cl, w))
        }
        return out.sorted { $0.1 > $1.1 }
    }

    /// The project/collection that contains this file (via its `collection:<id>` tag).
    public func containingUnit(of id: UUID) -> IndexedItem? {
        guard let it = item(id),
              let tag = it.tags.first(where: { $0.hasPrefix("collection:") }),
              let uid = UUID(uuidString: String(tag.dropFirst("collection:".count)))
        else { return nil }
        return item(uid)
    }

    /// Exact-duplicate files (same content fingerprint), excluding self.
    public func duplicates(of id: UUID) -> [IndexedItem] {
        guard let it = item(id), let fp = it.contentFingerprint else { return [] }
        return library.results.filter { $0.id != id && $0.contentFingerprint == fp }
    }

    /// Files that belong to this project/collection (tagged `collection:<id>`).
    public func containedItems(of id: UUID) -> [IndexedItem] {
        let tag = "collection:\(id.uuidString)"
        return library.results.filter { $0.tags.contains(tag) }
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

    /// Topic<->topic edges from semantic centroid similarity (TopicDiscovery),
    /// as (clusterIndexA, clusterIndexB, lineWeight). Replaces the old "two clusters
    /// share a parent folder" hairball.
    public func clusterLinks() -> [(Int, Int, Int)] {
        topicEdges.map { ($0.a, $0.b, max(1, Int(($0.weight * 10).rounded()))) }
    }
}

// MARK: - Group-by lens + cluster recomputation

/// How the Connections graph groups items. "Smart" = semantic topic discovery
/// (mean-center -> kNN -> Louvain -> soft membership). Type/Source/Time are
/// deterministic groupings.
public enum LibraryLens: String, CaseIterable, Sendable, Identifiable {
    case smart, type, source, time
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .smart: "Smart"
        case .type: "Type"
        case .source: "Source"
        case .time: "Time"
        }
    }
}

extension WorkspaceModel {
    public func setLens(_ lens: LibraryLens) {
        guard lens != self.lens else { return }
        self.lens = lens
        Task { await recomputeClusters() }
    }

    /// Recompute the cached `clusters` for the active lens. Smart = semantic topic
    /// discovery (async, reads the vector index); the others are deterministic.
    public func recomputeClusters() async {
        switch lens {
        case .type:
            topicEdges = []
            clusters = typeClusters()
        case .source:
            topicEdges = []
            clusters = sourceClusters()
        case .time:
            topicEdges = []
            clusters = timeClusters()
        case .smart:
            await ensureSemanticIndex()
            topicEdges = semGraph.edges
            clusters = semGraph.topics.enumerated().map { idx, topic in
                LibraryCluster(id: "topic:\(topic.id)", name: topic.label,
                               color: BBPalette.color(for: idx), itemIDs: topic.memberIDs)
            }
        }
    }

    /// Invalidate the semantic index after the library or embeddings change
    /// (rescan, backfill, capture) so the next access rebuilds it.
    public func invalidateSemanticIndex() { semLoaded = false }

    /// Build the semantic index from stored embeddings: mean-center + normalize
    /// every item vector (consistent space for both topic discovery and item
    /// cosine neighbors), run topic discovery, and recompute topic centroids in
    /// that same space so membership weights are comparable. Empty when there are
    /// no embeddings yet — no fallback. Cached until `invalidateSemanticIndex()`.
    ///
    /// Discovery SEEDS are aggregate units (projects/collections), content-bearing
    /// loose items, and a capped sample of each collection's members; everything
    /// else is soft-ASSIGNED — the anti-flooding rule that keeps big dumps from
    /// shattering the topic structure.
    private func ensureSemanticIndex() async {
        guard !semLoaded else { return }
        guard let services = graphServices,
              let vectorIndex = services.vectorIndex,
              let embedder = services.embedder,
              let records = try? await vectorIndex.vectors(modelID: embedder.modelID),
              !records.isEmpty
        else { semVectors = [:]; semGraph = .empty; semCentroids = [:]; semLoaded = true; return }

        let ids = Set(library.results.map(\.id))
        let recs = records.filter { ids.contains($0.itemID) }
        guard let dim = recs.first?.vector.count, dim > 0, recs.count >= 3 else {
            semVectors = [:]; semGraph = .empty; semCentroids = [:]; semLoaded = true; return
        }

        // Seeds vs assign split (drives discovery without flooding).
        let samplePerCollection = 15
        var seedIDs: Set<UUID> = []
        var membersByCollection: [String: [IndexedItem]] = [:]
        for item in library.results {
            if item.tags.contains("unit:member"),
               let collection = item.tags.first(where: { $0.hasPrefix("collection:") }) {
                membersByCollection[collection, default: []].append(item)
            } else if item.tags.contains("unit:project") || item.tags.contains("unit:collection") {
                seedIDs.insert(item.id)
            } else if item.tags.contains("unit:bundle") {
                continue
            } else {
                switch typeCategory(for: item) {
                case "Documents", "Spreadsheets", "Presentations", "Code", "Folders":
                    seedIDs.insert(item.id)
                default: break
                }
            }
        }
        for members in membersByCollection.values {
            for (index, member) in members.sorted(by: { $0.displayName < $1.displayName }).enumerated()
            where index < samplePerCollection { seedIDs.insert(member.id) }
        }
        var names: [UUID: String] = [:]
        for it in library.results { names[it.id] = it.displayName }

        // Heavy work (centering + O(n^2) kNN) off the main actor.
        let result = await Task.detached(priority: .userInitiated) {
            Self.buildSemanticIndex(records: recs, dim: dim, seedIDs: seedIDs, names: names)
        }.value
        semVectors = result.vectors
        semGraph = result.graph
        semCentroids = result.centroids
        semLoaded = true
    }

    private struct SemanticIndex: Sendable {
        let vectors: [UUID: [Float]]
        let graph: TopicGraph
        let centroids: [Int: [Float]]
    }

    private nonisolated static func buildSemanticIndex(
        records: [VectorRecord], dim: Int, seedIDs: Set<UUID>, names: [UUID: String]
    ) -> SemanticIndex {
        // 1. Mean-center + unit-normalize (anisotropy fix; gives cosines real spread).
        var mu = [Float](repeating: 0, count: dim)
        for r in records where r.vector.count == dim { for d in 0..<dim { mu[d] += r.vector[d] } }
        for d in 0..<dim { mu[d] /= Float(records.count) }
        var centered: [UUID: [Float]] = [:]
        centered.reserveCapacity(records.count)
        for r in records where r.vector.count == dim {
            var v = r.vector
            for d in 0..<dim { v[d] -= mu[d] }
            var norm: Float = 0; for x in v { norm += x * x }; norm = norm.squareRoot()
            if norm > 0 { for d in 0..<dim { v[d] /= norm } }
            centered[r.itemID] = v
        }

        // 2. Topic discovery over the centered space (pre-centered → skip its own).
        let seeds = records.filter { seedIDs.contains($0.itemID) }.compactMap { r in
            centered[r.itemID].map { (id: r.itemID, vector: $0) }
        }
        let assign = records.filter { !seedIDs.contains($0.itemID) }.compactMap { r in
            centered[r.itemID].map { (id: r.itemID, vector: $0) }
        }
        guard seeds.count >= 3 else {
            return SemanticIndex(vectors: centered, graph: .empty, centroids: [:])
        }
        let graph = TopicDiscovery.discover(
            vectors: seeds, assign: assign, names: names, preCentered: true)

        // 3. Topic centroids in the SAME centered space (so item↔topic weights are
        //    comparable to item↔item cosines).
        var centroids: [Int: [Float]] = [:]
        for topic in graph.topics {
            var c = [Float](repeating: 0, count: dim)
            var n = 0
            for mid in topic.memberIDs { if let v = centered[mid] { for d in 0..<dim { c[d] += v[d] }; n += 1 } }
            guard n > 0 else { continue }
            var norm: Float = 0; for x in c { norm += x * x }; norm = norm.squareRoot()
            if norm > 0 { for d in 0..<dim { c[d] /= norm } }
            centroids[topic.id] = c
        }
        return SemanticIndex(vectors: centered, graph: graph, centroids: centroids)
    }

    private func sourceClusters() -> [LibraryCluster] {
        var buckets: [UUID?: [UUID]] = [:]
        for it in library.results { buckets[sourceID(of: it), default: []].append(it.id) }
        return buckets.sorted { ($0.value.count) > ($1.value.count) }.enumerated().map { idx, entry in
            let name = entry.key.flatMap { sid in sources.first { $0.id == sid }?.displayName } ?? "Loose files"
            return LibraryCluster(id: "source:\(entry.key?.uuidString ?? "none")", name: name,
                                  color: BBPalette.color(for: idx), itemIDs: entry.value)
        }
    }

    private func timeClusters() -> [LibraryCluster] {
        let fmt = DateFormatter(); fmt.dateFormat = "LLLL yyyy"
        var buckets: [String: [UUID]] = [:]
        for it in library.results { buckets[fmt.string(from: it.importedAt), default: []].append(it.id) }
        return buckets.keys.sorted(by: >).enumerated().map { idx, key in
            LibraryCluster(id: "time:\(key)", name: key, color: BBPalette.color(for: idx), itemIDs: buckets[key] ?? [])
        }
    }

}

// MARK: - Real graph services + async graph loading

/// The services the Connections view needs to load real neighbors per node.
public struct WorkspaceGraphServices {
    public let graph: KnowledgeGraphService
    public let relatedness: RelatednessService
    public let store: KnowledgeStore
    public var vectorIndex: VectorIndex?
    public var embedder: TextEmbedder?

    public init(
        graph: KnowledgeGraphService,
        relatedness: RelatednessService,
        store: KnowledgeStore,
        vectorIndex: VectorIndex? = nil,
        embedder: TextEmbedder? = nil
    ) {
        self.graph = graph
        self.relatedness = relatedness
        self.store = store
        self.vectorIndex = vectorIndex
        self.embedder = embedder
    }

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
        // The clean 4-edge neighborhood (similar / topic / contains / duplicate),
        // resolved from the shared semantic index. Provenance stays in the
        // inspector, not the graph.
        await ensureSemanticIndex()
        return LoadedGraph(center: center, neighbors: itemNeighbors(id))
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
