import Foundation

public struct BipboxRuntimePaths: Equatable {
    public var baseDirectoryURL: URL

    public init(baseDirectoryURL: URL) {
        self.baseDirectoryURL = baseDirectoryURL
    }

    public static func defaultBaseDirectory(
        appFolderName: String = "Bipbox",
        fileManager: FileManager = .default
    ) throws -> URL {
        if let applicationSupportURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first {
            return applicationSupportURL.appendingPathComponent(appFolderName, isDirectory: true)
        }

        return fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent(appFolderName, isDirectory: true)
    }

    public var dataDirectoryURL: URL {
        baseDirectoryURL.appendingPathComponent("Data", isDirectory: true)
    }

    public var searchIndexDirectoryURL: URL {
        dataDirectoryURL.appendingPathComponent("Search", isDirectory: true)
    }

    public var knowledgeStoreDirectoryURL: URL {
        dataDirectoryURL.appendingPathComponent("Knowledge", isDirectory: true)
    }

    public var rulesDirectoryURL: URL {
        dataDirectoryURL.appendingPathComponent("Rules", isDirectory: true)
    }

    public var activityLogDirectoryURL: URL {
        dataDirectoryURL.appendingPathComponent("Activity", isDirectory: true)
    }

    public var permissionsDirectoryURL: URL {
        dataDirectoryURL.appendingPathComponent("Permissions", isDirectory: true)
    }

    public var settingsDirectoryURL: URL {
        dataDirectoryURL.appendingPathComponent("Settings", isDirectory: true)
    }

    public var sourcesDirectoryURL: URL {
        dataDirectoryURL.appendingPathComponent("Sources", isDirectory: true)
    }

    public var vectorIndexDirectoryURL: URL {
        dataDirectoryURL.appendingPathComponent("Vectors", isDirectory: true)
    }

    public var modelsDirectoryURL: URL {
        dataDirectoryURL.appendingPathComponent("Models", isDirectory: true)
    }

    /// Marker written once the embedding model has finished downloading, so the app
    /// can show a one-time download prompt on first start (no silent surprise).
    public var embedderMarkerURL: URL {
        modelsDirectoryURL.appendingPathComponent("embedder.downloaded", isDirectory: false)
    }

    public var defaultLibraryRootURL: URL {
        baseDirectoryURL.appendingPathComponent("Library", isDirectory: true)
    }

    public var defaultInboxURL: URL {
        baseDirectoryURL.appendingPathComponent("Inbox", isDirectory: true)
    }

    public func createRequiredDirectories(fileManager: FileManager = .default) throws {
        for directoryURL in [
            dataDirectoryURL,
            searchIndexDirectoryURL,
            knowledgeStoreDirectoryURL,
            rulesDirectoryURL,
            activityLogDirectoryURL,
            permissionsDirectoryURL,
            settingsDirectoryURL,
            sourcesDirectoryURL,
            vectorIndexDirectoryURL,
            modelsDirectoryURL,
            defaultLibraryRootURL,
            defaultInboxURL
        ] {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
    }
}
