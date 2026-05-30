import BipboxCore
import Foundation

public enum AppSettingsStoreError: Error, Equatable, LocalizedError {
    case storageUnavailable(URL, String)
    case invalidSettings(String)

    public var errorDescription: String? {
        switch self {
        case .storageUnavailable(let url, let reason):
            "App settings storage is unavailable at \(url.path): \(reason)"
        case .invalidSettings(let reason):
            "App settings file is invalid: \(reason)"
        }
    }
}

public actor JSONAppSettingsStore: AppSettingsStore {
    private let directoryURL: URL
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let fileManager: FileManager

    public init(directoryURL: URL, fileManager: FileManager = .default) throws {
        self.directoryURL = directoryURL
        self.fileURL = directoryURL.appendingPathComponent("settings.json", isDirectory: false)
        self.fileManager = fileManager
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder = JSONDecoder()

        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        } catch {
            throw AppSettingsStoreError.storageUnavailable(directoryURL, error.localizedDescription)
        }
    }

    public func load() async throws -> AppSettings {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return .defaults
        }

        do {
            let data = try Data(contentsOf: fileURL)
            return try decoder.decode(AppSettings.self, from: data)
        } catch let error as DecodingError {
            throw AppSettingsStoreError.invalidSettings(error.localizedDescription)
        } catch {
            throw AppSettingsStoreError.storageUnavailable(fileURL, error.localizedDescription)
        }
    }

    public func save(_ settings: AppSettings) async throws {
        do {
            let data = try encoder.encode(settings)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            throw AppSettingsStoreError.storageUnavailable(fileURL, error.localizedDescription)
        }
    }
}
