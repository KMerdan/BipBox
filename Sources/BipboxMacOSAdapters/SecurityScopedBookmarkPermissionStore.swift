import BipboxCore
import Foundation

public enum PermissionStoreError: Error, Equatable, LocalizedError {
    case storageUnavailable(URL, String)
    case bookmarkCreationFailed(URL, String)
    case bookmarkResolutionFailed(URL, String)

    public var errorDescription: String? {
        switch self {
        case .storageUnavailable(let url, let reason):
            "Permission storage is unavailable at \(url.path): \(reason)"
        case .bookmarkCreationFailed(let url, let reason):
            "Could not create bookmark for \(url.path): \(reason)"
        case .bookmarkResolutionFailed(let url, let reason):
            "Could not resolve bookmark for \(url.path): \(reason)"
        }
    }
}

public protocol BookmarkResolving: Sendable {
    func makeBookmarkData(for url: URL) throws -> Data
    func resolveBookmarkData(_ data: Data) throws -> BookmarkResolution
}

public struct BookmarkResolution: Equatable, Sendable {
    public var url: URL
    public var isStale: Bool

    public init(url: URL, isStale: Bool) {
        self.url = url
        self.isStale = isStale
    }
}

public struct SecurityScopedBookmarkResolver: BookmarkResolving {
    public init() {}

    public func makeBookmarkData(for url: URL) throws -> Data {
        do {
            return try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            throw PermissionStoreError.bookmarkCreationFailed(url, error.localizedDescription)
        }
    }

    public func resolveBookmarkData(_ data: Data) throws -> BookmarkResolution {
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            return BookmarkResolution(url: url, isStale: isStale)
        } catch {
            throw PermissionStoreError.bookmarkResolutionFailed(URL(fileURLWithPath: ""), error.localizedDescription)
        }
    }
}

public actor SecurityScopedBookmarkPermissionStore: PermissionStore {
    private let fileURL: URL
    private let fileManager: FileManager
    private let resolver: BookmarkResolving
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(
        directoryURL: URL,
        fileManager: FileManager = .default,
        resolver: BookmarkResolving = SecurityScopedBookmarkResolver()
    ) throws {
        self.fileURL = directoryURL.appendingPathComponent("permissions.json", isDirectory: false)
        self.fileManager = fileManager
        self.resolver = resolver

        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            if !fileManager.fileExists(atPath: fileURL.path) {
                try encoder.encode([PermissionRecord]()).write(to: fileURL)
            }
        } catch {
            throw PermissionStoreError.storageUnavailable(directoryURL, error.localizedDescription)
        }
    }

    public func save(_ record: PermissionRecord) async throws {
        var records = try loadStoredRecords()
        let bookmarkData = try record.bookmarkData ?? resolver.makeBookmarkData(for: record.url)
        let stored = PermissionRecord(
            id: record.id,
            scope: record.scope,
            url: record.url,
            state: .granted,
            bookmarkData: bookmarkData,
            message: nil,
            metadata: record.metadata
        )

        records.removeAll { $0.id == stored.id }
        records.append(stored)
        try persist(records)
    }

    public func remove(id: UUID) async throws {
        var records = try loadStoredRecords()
        records.removeAll { $0.id == id }
        try persist(records)
    }

    public func records(scope: PermissionScope?) async throws -> [PermissionRecord] {
        let records = try loadStoredRecords()
        let resolved = records.map(resolveState(for:))

        if let scope {
            return resolved.filter { $0.scope == scope }
        }

        return resolved
    }

    private func resolveState(for record: PermissionRecord) -> PermissionRecord {
        guard let bookmarkData = record.bookmarkData else {
            return PermissionRecord(
                id: record.id,
                scope: record.scope,
                url: record.url,
                state: .missing,
                bookmarkData: nil,
                message: "No bookmark data stored.",
                metadata: record.metadata
            )
        }

        do {
            let resolution = try resolver.resolveBookmarkData(bookmarkData)
            return PermissionRecord(
                id: record.id,
                scope: record.scope,
                url: resolution.url,
                state: resolution.isStale ? .stale : .granted,
                bookmarkData: bookmarkData,
                message: resolution.isStale ? "Bookmark is stale and should be refreshed." : nil,
                metadata: record.metadata
            )
        } catch {
            return PermissionRecord(
                id: record.id,
                scope: record.scope,
                url: record.url,
                state: .missing,
                bookmarkData: bookmarkData,
                message: error.localizedDescription,
                metadata: record.metadata
            )
        }
    }

    private func loadStoredRecords() throws -> [PermissionRecord] {
        do {
            let data = try Data(contentsOf: fileURL)
            guard !data.isEmpty else {
                return []
            }
            return try decoder.decode([PermissionRecord].self, from: data)
        } catch {
            throw PermissionStoreError.storageUnavailable(fileURL, error.localizedDescription)
        }
    }

    private func persist(_ records: [PermissionRecord]) throws {
        do {
            try encoder.encode(records).write(to: fileURL, options: [.atomic])
        } catch {
            throw PermissionStoreError.storageUnavailable(fileURL, error.localizedDescription)
        }
    }
}
