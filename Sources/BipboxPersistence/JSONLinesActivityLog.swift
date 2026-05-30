import BipboxCore
import Foundation

public enum ActivityLogError: Error, Equatable, LocalizedError {
    case invalidLimit(Int)
    case storageUnavailable(URL, String)

    public var errorDescription: String? {
        switch self {
        case .invalidLimit(let limit):
            "Activity log limit must be positive: \(limit)"
        case .storageUnavailable(let url, let reason):
            "Activity log storage is unavailable at \(url.path): \(reason)"
        }
    }
}

public actor JSONLinesActivityLog: ActivityLog {
    private let fileURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(directoryURL: URL, fileManager: FileManager = .default) throws {
        self.fileURL = directoryURL.appendingPathComponent("activity.jsonl", isDirectory: false)
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()

        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601

        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            if !fileManager.fileExists(atPath: fileURL.path) {
                try Data().write(to: fileURL)
            }
        } catch {
            throw ActivityLogError.storageUnavailable(directoryURL, error.localizedDescription)
        }
    }

    public func append(_ event: ActivityEvent) async throws {
        do {
            var data = try encoder.encode(event)
            data.append(0x0A)

            let handle = try FileHandle(forWritingTo: fileURL)
            defer {
                try? handle.close()
            }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            throw ActivityLogError.storageUnavailable(fileURL, error.localizedDescription)
        }
    }

    public func recent(limit: Int) async throws -> [ActivityEvent] {
        guard limit > 0 else {
            throw ActivityLogError.invalidLimit(limit)
        }

        let events = try readAllEvents()
        return Array(events.sorted { $0.occurredAt > $1.occurredAt }.prefix(limit))
    }

    public func events(forItemID itemID: UUID) async throws -> [ActivityEvent] {
        try readAllEvents()
            .filter { $0.itemID == itemID }
            .sorted { $0.occurredAt < $1.occurredAt }
    }

    private func readAllEvents() throws -> [ActivityEvent] {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw ActivityLogError.storageUnavailable(fileURL, error.localizedDescription)
        }

        guard !data.isEmpty else {
            return []
        }

        let lines = String(decoding: data, as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: true)

        do {
            return try lines.map { line in
                try decoder.decode(ActivityEvent.self, from: Data(line.utf8))
            }
        } catch {
            throw ActivityLogError.storageUnavailable(fileURL, error.localizedDescription)
        }
    }
}

