import BipboxCore
import Foundation

public actor JSONSourceStore: SourceStore {
    private let fileURL: URL
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(directoryURL: URL, fileManager: FileManager = .default) throws {
        self.fileURL = directoryURL.appendingPathComponent("sources.json", isDirectory: false)
        self.fileManager = fileManager
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        } catch {
            throw SourceStoreError.storageUnavailable(directoryURL, error.localizedDescription)
        }
    }

    @discardableResult
    public func upsert(_ source: SourceRecord) async throws -> SourceStoreChange {
        try validate(source)
        var records = try loadRecords()
        if let url = source.url {
            let standardizedPath = url.standardizedFileURL.path
            if records.contains(where: { $0.id != source.id && $0.url?.standardizedFileURL.path == standardizedPath }) {
                throw SourceStoreError.duplicatePath(url)
            }
        }

        if let index = records.firstIndex(where: { $0.id == source.id }) {
            records[index] = source
            try persist(records)
            return .updated(source)
        }

        records.append(source)
        try persist(records)
        return .inserted(source)
    }

    @discardableResult
    public func remove(id: UUID) async throws -> SourceStoreChange {
        var records = try loadRecords()
        guard let index = records.firstIndex(where: { $0.id == id }) else {
            throw SourceStoreError.missingSource(id)
        }

        let removed = records.remove(at: index)
        try persist(records)
        return .removed(removed)
    }

    public func source(id: UUID) async throws -> SourceRecord? {
        try loadRecords().first { $0.id == id }
    }

    public func sources() async throws -> [SourceRecord] {
        sort(try loadRecords())
    }

    public func enabledSources(kind: SourceKind?) async throws -> [SourceRecord] {
        try await sources().filter { source in
            source.enabled && (kind == nil || source.kind == kind)
        }
    }

    private func loadRecords() throws -> [SourceRecord] {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }

        do {
            let data = try Data(contentsOf: fileURL)
            guard !data.isEmpty else {
                return []
            }
            return try decoder.decode([SourceRecord].self, from: data)
        } catch let error as DecodingError {
            throw SourceStoreError.invalidStorage(fileURL, error.localizedDescription)
        } catch {
            throw SourceStoreError.storageUnavailable(fileURL, error.localizedDescription)
        }
    }

    private func persist(_ records: [SourceRecord]) throws {
        do {
            try encoder.encode(sort(records)).write(to: fileURL, options: [.atomic])
        } catch {
            throw SourceStoreError.storageUnavailable(fileURL, error.localizedDescription)
        }
    }

    private func validate(_ source: SourceRecord) throws {
        guard let url = source.url else {
            return
        }
        guard url.isFileURL else {
            throw SourceStoreError.invalidURL(url)
        }
    }

    private func sort(_ records: [SourceRecord]) -> [SourceRecord] {
        records.sorted { lhs, rhs in
            let displayOrder = lhs.displayName.localizedStandardCompare(rhs.displayName)
            if displayOrder != .orderedSame {
                return displayOrder == .orderedAscending
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}
