import Foundation

public struct LibraryRecoveryResult: Equatable, Sendable {
    public var item: KnowledgeItem
    public var indexedItem: IndexedItem?
    public var message: String

    public init(item: KnowledgeItem, indexedItem: IndexedItem? = nil, message: String) {
        self.item = item
        self.indexedItem = indexedItem
        self.message = message
    }
}

public enum LibraryRecoveryError: Error, Equatable, LocalizedError {
    case itemNotFound(UUID)
    case currentURLMissing(UUID)
    case locatedURLMissing(URL)
    case searchRemovalUnavailable

    public var errorDescription: String? {
        switch self {
        case .itemNotFound(let id):
            "Library item was not found: \(id.uuidString)"
        case .currentURLMissing(let id):
            "Library item has no current URL: \(id.uuidString)"
        case .locatedURLMissing(let url):
            "Selected file does not exist: \(url.path)"
        case .searchRemovalUnavailable:
            "Search index removal is unavailable."
        }
    }
}

public final class DefaultMissingFileRecoveryService: MissingFileRecoveryService, @unchecked Sendable {
    private let knowledgeStore: KnowledgeStore
    private let searchService: SearchService
    private let searchRemover: SearchIndexRemoving?
    private let fileManager: FileManager
    private let now: @Sendable () -> Date

    public init(
        knowledgeStore: KnowledgeStore,
        searchService: SearchService,
        searchRemover: SearchIndexRemoving? = nil,
        fileManager: FileManager = .default,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.knowledgeStore = knowledgeStore
        self.searchService = searchService
        self.searchRemover = searchRemover
        self.fileManager = fileManager
        self.now = now
    }

    public func refreshStatus(itemID: UUID) async throws -> LibraryRecoveryResult {
        var item = try await requiredItem(id: itemID)
        guard let currentURL = item.currentURL else {
            throw LibraryRecoveryError.currentURLMissing(itemID)
        }
        item.state = state(for: currentURL)
        item.lastSeenAt = now()
        try await knowledgeStore.upsertKnowledgeItem(item)

        let indexedItem = try await updateIndexedItem(id: itemID) {
            $0.status = indexedStatus(for: item.state)
        }
        return LibraryRecoveryResult(item: item, indexedItem: indexedItem, message: "Library item status refreshed.")
    }

    public func locate(itemID: UUID, at url: URL) async throws -> LibraryRecoveryResult {
        guard fileManager.fileExists(atPath: url.path) else {
            throw LibraryRecoveryError.locatedURLMissing(url)
        }
        var item = try await requiredItem(id: itemID)
        item.currentURL = url
        item.state = state(for: url)
        item.lastSeenAt = now()
        try await knowledgeStore.upsertKnowledgeItem(item)

        let indexedItem = try await updateIndexedItem(id: itemID) {
            $0.currentPath = url.path
            $0.displayName = url.lastPathComponent
            $0.status = indexedStatus(for: item.state)
        }
        return LibraryRecoveryResult(item: item, indexedItem: indexedItem, message: "Library item location updated.")
    }

    public func removeFromLibrary(itemID: UUID) async throws {
        guard var item = try await knowledgeStore.knowledgeItem(id: itemID) else {
            throw LibraryRecoveryError.itemNotFound(itemID)
        }
        item.state = .archived
        item.lastSeenAt = now()
        try await knowledgeStore.upsertKnowledgeItem(item)
        guard let searchRemover else {
            throw LibraryRecoveryError.searchRemovalUnavailable
        }
        try await searchRemover.remove(id: itemID)
    }

    public func reindex(itemID: UUID) async throws -> LibraryRecoveryResult {
        var item = try await requiredItem(id: itemID)
        guard let currentURL = item.currentURL else {
            throw LibraryRecoveryError.currentURLMissing(itemID)
        }
        item.state = state(for: currentURL)
        item.lastSeenAt = now()
        try await knowledgeStore.upsertKnowledgeItem(item)

        let indexedItem = try await updateIndexedItem(id: itemID) {
            $0.currentPath = currentURL.path
            $0.displayName = currentURL.lastPathComponent
            $0.status = indexedStatus(for: item.state)
            $0.importedAt = now()
        }
        return LibraryRecoveryResult(item: item, indexedItem: indexedItem, message: "Library item reindexed.")
    }

    private func requiredItem(id: UUID) async throws -> KnowledgeItem {
        guard let item = try await knowledgeStore.knowledgeItem(id: id) else {
            throw LibraryRecoveryError.itemNotFound(id)
        }
        return item
    }

    private func updateIndexedItem(id: UUID, mutate: (inout IndexedItem) -> Void) async throws -> IndexedItem? {
        let results = try await searchService.search(SearchQuery(text: "", limit: 1_000))
        guard var indexedItem = results.items.first(where: { $0.id == id }) else {
            return nil
        }
        mutate(&indexedItem)
        try await searchService.update(indexedItem)
        return indexedItem
    }

    private func state(for url: URL) -> KnowledgeItemState {
        guard fileManager.fileExists(atPath: url.path) else {
            return .missing
        }
        guard fileManager.isReadableFile(atPath: url.path) else {
            return .permissionNeeded
        }
        return .active
    }

    private func indexedStatus(for state: KnowledgeItemState) -> IndexedItemStatus {
        switch state {
        case .missing, .permissionNeeded:
            .missing
        case .failed:
            .failed
        case .needsReview, .keptForLater:
            .needsReview
        case .active, .archived:
            .indexedOnly
        }
    }
}
