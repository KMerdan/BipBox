import BipboxCore
import Foundation

public enum SearchKindFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case files
    case folders
    case packages

    public var id: String {
        rawValue
    }

    public var title: String {
        switch self {
        case .all: "All"
        case .files: "Files"
        case .folders: "Folders"
        case .packages: "Packages"
        }
    }

    var itemKinds: [ItemKind] {
        switch self {
        case .all: []
        case .files: [.file]
        case .folders: [.folder]
        case .packages: [.package, .bundle]
        }
    }
}

public enum SearchStatusFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case organized
    case needsReview
    case indexedOnly
    case missing
    case failed

    public var id: String {
        rawValue
    }

    public var title: String {
        switch self {
        case .all: "All"
        case .organized: "Organized"
        case .needsReview: "Needs Review"
        case .indexedOnly: "Indexed Only"
        case .missing: "Missing"
        case .failed: "Failed"
        }
    }

    var statuses: [IndexedItemStatus] {
        switch self {
        case .all: []
        case .organized: [.organized]
        case .needsReview: [.needsReview]
        case .indexedOnly: [.indexedOnly]
        case .missing: [.missing]
        case .failed: [.failed]
        }
    }
}

public enum LibraryMode: String, CaseIterable, Identifiable, Sendable {
    case search
    case recent
    case collections
    case sources
    case contexts
    case missing
    case related

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .search: "Search"
        case .recent: "Recent"
        case .collections: "Collections"
        case .sources: "Sources"
        case .contexts: "Contexts"
        case .missing: "Missing"
        case .related: "Related"
        }
    }
}

@MainActor
public protocol SearchResultActionHandling: AnyObject {
    func open(_ item: IndexedItem)
    func revealInFinder(_ item: IndexedItem)
    func copyPath(_ item: IndexedItem)
}

@MainActor
public final class SearchWorkspaceViewModel: ObservableObject {
    @Published public var searchText: String
    @Published public var kindFilter: SearchKindFilter
    @Published public var typeFilterText: String
    @Published public var tagFilterText: String
    @Published public var statusFilter: SearchStatusFilter
    @Published public var importedFrom: Date?
    @Published public var importedThrough: Date?
    @Published public var mode: LibraryMode
    @Published public var collectionFilterText: String
    @Published public var sourceFilterText: String
    @Published public private(set) var results: [IndexedItem]
    @Published public private(set) var retrievalResults: [RetrievalResult]
    @Published public private(set) var relatedItems: [RelatedItem]
    @Published public private(set) var relatedContextOverview: RelatedContextOverview?
    @Published public private(set) var totalCount: Int
    @Published public private(set) var selectedItem: IndexedItem?
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var isSearching: Bool

    public weak var actionHandler: SearchResultActionHandling?

    private let searchService: SearchService
    private let retrievalService: RetrievalService?
    private let missingFileRecoveryService: MissingFileRecoveryService?
    private let relatednessService: RelatednessService?
    private let relatedContextService: RelatedContextService?
    private let limit: Int

    public init(
        searchService: SearchService,
        retrievalService: RetrievalService? = nil,
        missingFileRecoveryService: MissingFileRecoveryService? = nil,
        relatednessService: RelatednessService? = nil,
        relatedContextService: RelatedContextService? = nil,
        actionHandler: SearchResultActionHandling? = nil,
        searchText: String = "",
        kindFilter: SearchKindFilter = .all,
        typeFilterText: String = "",
        tagFilterText: String = "",
        statusFilter: SearchStatusFilter = .all,
        importedFrom: Date? = nil,
        importedThrough: Date? = nil,
        mode: LibraryMode = .search,
        collectionFilterText: String = "",
        sourceFilterText: String = "",
        limit: Int = 50
    ) {
        self.searchService = searchService
        self.retrievalService = retrievalService
        self.missingFileRecoveryService = missingFileRecoveryService
        self.relatednessService = relatednessService
        self.relatedContextService = relatedContextService
        self.actionHandler = actionHandler
        self.searchText = searchText
        self.kindFilter = kindFilter
        self.typeFilterText = typeFilterText
        self.tagFilterText = tagFilterText
        self.statusFilter = statusFilter
        self.importedFrom = importedFrom
        self.importedThrough = importedThrough
        self.mode = mode
        self.collectionFilterText = collectionFilterText
        self.sourceFilterText = sourceFilterText
        self.limit = limit
        results = []
        retrievalResults = []
        relatedItems = []
        relatedContextOverview = nil
        totalCount = 0
        selectedItem = nil
        errorMessage = nil
        isSearching = false
    }

    public static func fixture(statusFilter: SearchStatusFilter = .all) -> SearchWorkspaceViewModel {
        SearchWorkspaceViewModel(searchService: FixtureSearchService(), statusFilter: statusFilter)
    }

    public var query: SearchQuery {
        let effectiveStatusFilter: SearchStatusFilter = mode == .missing ? .missing : statusFilter
        let tagFilters = splitFilterText(tagFilterText) + splitFilterText(collectionFilterText) + splitFilterText(sourceFilterText)
        return SearchQuery(
            text: searchText.trimmingCharacters(in: .whitespacesAndNewlines),
            kinds: kindFilter.itemKinds,
            uniformTypeIdentifiers: splitFilterText(typeFilterText),
            tags: tagFilters,
            statuses: effectiveStatusFilter.statuses,
            importedFrom: importedFrom,
            importedThrough: importedThrough,
            limit: limit
        )
    }

    public var retrievalQuery: RetrievalQuery {
        let effectiveStatusFilter: SearchStatusFilter = mode == .missing ? .missing : statusFilter
        let sourceTokens = splitFilterText(sourceFilterText)
        let sourceIDs = sourceTokens.compactMap(UUID.init(uuidString:))
        let sourceTags = sourceTokens.filter { UUID(uuidString: $0) == nil }
        return RetrievalQuery(
            text: searchText.trimmingCharacters(in: .whitespacesAndNewlines),
            sourceIDs: sourceIDs,
            kinds: kindFilter.itemKinds,
            statuses: effectiveStatusFilter.statuses,
            tags: splitFilterText(tagFilterText) + splitFilterText(collectionFilterText) + sourceTags,
            importedFrom: importedFrom,
            importedThrough: importedThrough,
            contextIDs: splitFilterText(collectionFilterText).compactMap(UUID.init(uuidString:)),
            limit: limit
        )
    }

    public var hasResults: Bool {
        !results.isEmpty
    }

    public func search() async {
        isSearching = true
        errorMessage = nil

        do {
            if let retrievalService {
                let retrieved = try await retrievalService.retrieve(retrievalQuery)
                retrievalResults = retrieved.items
                results = retrieved.items.map(\.item)
                totalCount = retrieved.totalCount
            } else {
                let searchResults = try await searchService.search(query)
                retrievalResults = []
                results = searchResults.items
                totalCount = searchResults.totalCount
            }
            selectedItem = results.first
            if mode == .related {
                await loadRelatedForSelected()
            } else if mode == .contexts {
                await loadContextForSelected()
            }
        } catch {
            results = []
            retrievalResults = []
            relatedItems = []
            relatedContextOverview = nil
            totalCount = 0
            selectedItem = nil
            errorMessage = error.localizedDescription
        }

        isSearching = false
    }

    public func select(_ item: IndexedItem?) {
        selectedItem = item
    }

    public func loadRelatedForSelected() async {
        guard let selectedItem, let relatednessService else {
            relatedItems = []
            return
        }

        do {
            relatedItems = try await relatednessService.relatedItems(to: selectedItem.id, limit: 8)
            errorMessage = nil
        } catch {
            relatedItems = []
            errorMessage = error.localizedDescription
        }
    }

    public func loadContextForSelected() async {
        guard let selectedItem, let relatedContextService else {
            relatedContextOverview = nil
            return
        }

        do {
            relatedContextOverview = try await relatedContextService.overview(for: selectedItem.id, relatedLimit: 8)
            relatedItems = relatedContextOverview?.relatedItems ?? []
            errorMessage = nil
        } catch {
            relatedContextOverview = nil
            relatedItems = []
            errorMessage = error.localizedDescription
        }
    }

    public func matchExplanation(for item: IndexedItem) -> String {
        if let retrieval = retrievalResults.first(where: { $0.item.id == item.id }) {
            return retrieval.explanations.joined(separator: " ")
        }
        if let related = relatedItems.first(where: { $0.item.id == item.id }) {
            return related.explanations.first ?? "Related by metadata and context."
        }
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Matched name, path, or indexed text."
        }
        if !collectionFilterText.isEmpty {
            return "Matched collection tag."
        }
        if !sourceFilterText.isEmpty {
            return "Matched capture source tag."
        }
        if item.status == .missing {
            return "Missing or permission-needed item."
        }
        return "Recently indexed by Bipbox."
    }

    public func showRelatedForSelected() async {
        guard selectedItem != nil else {
            return
        }
        mode = .related
        await loadRelatedForSelected()
    }

    public func refreshSelectedItemStatus() async {
        guard let selectedItem else {
            return
        }
        await runRecoveryAction {
            try await missingFileRecoveryService?.refreshStatus(itemID: selectedItem.id)
        }
    }

    public func reindexSelectedItem() async {
        guard let selectedItem else {
            return
        }
        await runRecoveryAction {
            try await missingFileRecoveryService?.reindex(itemID: selectedItem.id)
        }
    }

    public func locateSelectedItem(at url: URL) async {
        guard let selectedItem else {
            return
        }
        await runRecoveryAction {
            try await missingFileRecoveryService?.locate(itemID: selectedItem.id, at: url)
        }
    }

    public func removeSelectedItemFromLibrary() async {
        guard let selectedItem else {
            return
        }
        guard let missingFileRecoveryService else {
            errorMessage = "Library recovery is unavailable."
            return
        }

        do {
            try await missingFileRecoveryService.removeFromLibrary(itemID: selectedItem.id)
            results.removeAll { $0.id == selectedItem.id }
            retrievalResults.removeAll { $0.item.id == selectedItem.id }
            totalCount = max(0, totalCount - 1)
            self.selectedItem = results.first
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func openSelectedItem() {
        guard let selectedItem else {
            return
        }
        actionHandler?.open(selectedItem)
    }

    public func revealSelectedItem() {
        guard let selectedItem else {
            return
        }
        actionHandler?.revealInFinder(selectedItem)
    }

    public func copySelectedPath() {
        guard let selectedItem else {
            return
        }
        actionHandler?.copyPath(selectedItem)
    }

    private func runRecoveryAction(_ action: () async throws -> LibraryRecoveryResult?) async {
        guard missingFileRecoveryService != nil else {
            errorMessage = "Library recovery is unavailable."
            return
        }

        do {
            if let result = try await action(), let indexedItem = result.indexedItem {
                replaceItem(indexedItem)
                selectedItem = indexedItem
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func replaceItem(_ item: IndexedItem) {
        if let index = results.firstIndex(where: { $0.id == item.id }) {
            results[index] = item
        }
        if let index = retrievalResults.firstIndex(where: { $0.item.id == item.id }) {
            retrievalResults[index].item = item
        }
    }

    private func splitFilterText(_ text: String) -> [String] {
        text
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

private final class FixtureSearchService: SearchService, @unchecked Sendable {
    private let items: [IndexedItem]

    init(items: [IndexedItem] = FixtureSearchService.defaultItems) {
        self.items = items
    }

    func index(_ item: IndexedItem) async throws {}

    func update(_ item: IndexedItem) async throws {}

    func search(_ query: SearchQuery) async throws -> SearchResults {
        let filtered = items.filter { item in
            let textMatches = query.text.isEmpty
                || item.displayName.localizedCaseInsensitiveContains(query.text)
                || item.currentPath.localizedCaseInsensitiveContains(query.text)
            let kindMatches = query.kinds.isEmpty || query.kinds.contains(item.kind)
            let typeMatches = query.uniformTypeIdentifiers.isEmpty
                || query.uniformTypeIdentifiers.contains(item.uniformTypeIdentifier ?? "")
            let tagMatches = query.tags.isEmpty || !Set(query.tags).isDisjoint(with: Set(item.tags))
            let statusMatches = query.statuses.isEmpty || query.statuses.contains(item.status)
            return textMatches && kindMatches && typeMatches && tagMatches && statusMatches
        }
        return SearchResults(items: Array(filtered.prefix(query.limit)), totalCount: filtered.count)
    }

    private static let defaultItems: [IndexedItem] = [
        IndexedItem(
            currentPath: "/Users/example/Bipbox/Documents/Tax 2025.pdf",
            originalPath: "/Users/example/Downloads/Tax 2025.pdf",
            displayName: "Tax 2025.pdf",
            kind: .file,
            uniformTypeIdentifier: "com.adobe.pdf",
            importedAt: Date(timeIntervalSince1970: 1_800_000_000),
            tags: ["finance"],
            status: .organized
        ),
        IndexedItem(
            currentPath: "/Users/example/Bipbox/Projects/Client Package",
            originalPath: "/Users/example/Downloads/Client Package",
            displayName: "Client Package",
            kind: .folder,
            importedAt: Date(timeIntervalSince1970: 1_800_000_100),
            tags: ["client"],
            status: .needsReview
        )
    ]
}
