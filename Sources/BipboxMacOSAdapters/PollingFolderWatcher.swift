import BipboxCore
import Foundation

public enum FolderWatcherError: Error, Equatable, LocalizedError {
    case watchedFolderMissing(URL)
    case watchedURLIsNotFolder(URL)
    case scanFailed(URL, String)

    public var errorDescription: String? {
        switch self {
        case .watchedFolderMissing(let url):
            "Watched folder does not exist: \(url.path)"
        case .watchedURLIsNotFolder(let url):
            "Watched URL is not a folder: \(url.path)"
        case .scanFailed(let url, let reason):
            "Could not scan watched folder \(url.path): \(reason)"
        }
    }
}

public actor PollingFolderWatcher: FolderWatcher {
    private let configuration: FolderWatchConfiguration
    private let intakeService: IntakeService
    private let fileManager: FileManager
    private var knownTopLevelPaths: Set<String> = []
    private var watcherState: FolderWatcherState = .stopped

    public var state: FolderWatcherState {
        watcherState
    }

    public init(
        configuration: FolderWatchConfiguration,
        intakeService: IntakeService,
        fileManager: FileManager = .default
    ) {
        self.configuration = configuration
        self.intakeService = intakeService
        self.fileManager = fileManager
    }

    public func start() async throws {
        try validateWatchedFolder()
        knownTopLevelPaths = try topLevelItemURLs().map(\.path).asSet()
        watcherState = .running
    }

    public func pause() async {
        guard watcherState == .running else {
            return
        }
        watcherState = .paused
    }

    public func resume() async throws {
        guard watcherState == .paused else {
            return
        }
        try validateWatchedFolder()
        watcherState = .running
    }

    public func stop() async {
        watcherState = .stopped
        knownTopLevelPaths = []
    }

    @discardableResult
    public func scanNow(receivedAt: Date = Date()) async throws -> [OrganizationRequest] {
        guard watcherState == .running else {
            return []
        }

        let topLevelURLs = try topLevelItemURLs()
        let currentPaths = Set(topLevelURLs.map(\.path))
        let newURLs = topLevelURLs.filter { !knownTopLevelPaths.contains($0.path) }
        knownTopLevelPaths = currentPaths

        var requests: [OrganizationRequest] = []
        var emittedPaths: Set<String> = []

        for url in newURLs.sorted(by: { $0.path < $1.path }) {
            guard emittedPaths.insert(url.path).inserted else {
                continue
            }

            let request = OrganizationRequest(
                source: configuration.source,
                sourceID: configuration.sourceID,
                itemURL: url,
                itemKind: try itemKind(for: url),
                receivedAt: receivedAt,
                mode: configuration.mode,
                userContext: configuration.sourceDetail
            )
            _ = try await intakeService.submit(request)
            requests.append(request)
        }

        return requests
    }

    private func validateWatchedFolder() throws {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: configuration.folderURL.path, isDirectory: &isDirectory) else {
            throw FolderWatcherError.watchedFolderMissing(configuration.folderURL)
        }

        guard isDirectory.boolValue else {
            throw FolderWatcherError.watchedURLIsNotFolder(configuration.folderURL)
        }
    }

    private func topLevelItemURLs() throws -> [URL] {
        do {
            let discoveredURLs = try fileManager.contentsOfDirectory(
                at: configuration.folderURL,
                includingPropertiesForKeys: [
                    .isRegularFileKey,
                    .isDirectoryKey,
                    .isPackageKey,
                    .isSymbolicLinkKey
                ],
                options: [.skipsHiddenFiles]
            )
            return discoveredURLs.map(normalizedTopLevelURL)
        } catch {
            throw FolderWatcherError.scanFailed(configuration.folderURL, error.localizedDescription)
        }
    }

    private func normalizedTopLevelURL(_ discoveredURL: URL) -> URL {
        let isDirectory = (try? discoveredURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? discoveredURL.hasDirectoryPath
        return configuration.folderURL.appendingPathComponent(discoveredURL.lastPathComponent, isDirectory: isDirectory)
    }

    private func itemKind(for url: URL) throws -> ItemKind {
        let values = try url.resourceValues(forKeys: [
            .isRegularFileKey,
            .isDirectoryKey,
            .isPackageKey,
            .isSymbolicLinkKey
        ])

        if values.isSymbolicLink == true {
            return .symlink
        }

        if values.isPackage == true {
            return ["app", "appex", "bundle", "framework", "plugin", "xpc"].contains(url.pathExtension.lowercased())
                ? .bundle
                : .package
        }

        if values.isDirectory == true {
            return .folder
        }

        if values.isRegularFile == true {
            return .file
        }

        return .unknown
    }
}

private extension Array where Element: Hashable {
    func asSet() -> Set<Element> {
        Set(self)
    }
}
