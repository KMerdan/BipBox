import BipboxCore
import BipboxMacOSAdapters
import Foundation

public enum WatchFolderAutomationError: Error, Equatable, LocalizedError {
    case commonCaptureLocationUnavailable(CommonCaptureLocation)

    public var errorDescription: String? {
        switch self {
        case .commonCaptureLocationUnavailable(let location):
            "Could not resolve \(location.displayName) as a capture location."
        }
    }
}

public actor WatchFolderAutomationService {
    private let permissionStore: PermissionStore
    private let sourceStore: SourceStore?
    private let intakeService: IntakeService
    private let appSettingsStore: AppSettingsStore
    private let scanIntervalNanoseconds: UInt64
    private let fileManager: FileManager
    private let commonLocationURLs: [CommonCaptureLocation: URL]
    private var watchers: [UUID: PollingFolderWatcher] = [:]
    private var scanTask: Task<Void, Never>?

    public init(
        permissionStore: PermissionStore,
        sourceStore: SourceStore? = nil,
        intakeService: IntakeService,
        appSettingsStore: AppSettingsStore,
        scanIntervalNanoseconds: UInt64 = 2_000_000_000,
        fileManager: FileManager = .default,
        commonLocationURLs: [CommonCaptureLocation: URL] = [:]
    ) {
        self.permissionStore = permissionStore
        self.sourceStore = sourceStore
        self.intakeService = intakeService
        self.appSettingsStore = appSettingsStore
        self.scanIntervalNanoseconds = scanIntervalNanoseconds
        self.fileManager = fileManager
        self.commonLocationURLs = commonLocationURLs
    }

    @discardableResult
    public func configureCommonCaptureLocation(
        _ location: CommonCaptureLocation,
        url providedURL: URL? = nil,
        state: PermissionState = .missing
    ) async throws -> PermissionRecord {
        let url = try providedURL ?? commonLocationURL(for: location)
        let record = PermissionRecord(
            scope: .watchedFolder,
            url: url,
            state: state,
            metadata: metadata(for: location, url: url)
        )
        try await permissionStore.save(record)
        if let sourceStore {
            let source = SourceRecord.watchedFolder(
                url: url,
                displayName: location.displayName,
                permissionRecordID: record.id,
                createdAt: Date(),
                metadata: metadata(for: location, url: url)
            )
            try await sourceStore.upsert(source)
        }
        return record
    }

    public func reloadWatchedFolders() async throws {
        for watcher in watchers.values {
            await watcher.stop()
        }
        watchers = [:]

        let settings = try await appSettingsStore.load()
        guard settings.automationState == .running else {
            return
        }

        if let sourceStore {
            try await reloadSourceBackedWatchers(sourceStore: sourceStore)
            return
        }

        let records = try await permissionStore.records(scope: .watchedFolder)
        for record in records where record.state == .granted || record.state == .missing {
            let watcher = PollingFolderWatcher(
                configuration: FolderWatchConfiguration(
                    folderURL: record.url,
                    mode: .organize,
                    sourceDetail: sourceDetail(for: record)
                ),
                intakeService: intakeService
            )
            try await watcher.start()
            watchers[record.id] = watcher
        }
    }

    @discardableResult
    public func scanOnce(receivedAt: Date = Date()) async throws -> Int {
        var emittedCount = 0
        for (id, watcher) in watchers {
            let count = try await watcher.scanNow(receivedAt: receivedAt).count
            emittedCount += count
            try await updateSourceAfterScan(id: id, emittedCount: count)
        }
        return emittedCount
    }

    public func pauseAll() async {
        for (id, watcher) in watchers {
            await watcher.pause()
            try? await updateSourceWatchState(id: id, state: .paused, enabled: false)
        }
    }

    public func resumeAll() async throws {
        for (id, watcher) in watchers {
            try await watcher.resume()
            try await updateSourceWatchState(id: id, state: .running, enabled: true)
        }
    }

    public func statusSnapshot() async throws -> [WatchedFolderStatus] {
        if let sourceStore {
            let sources = try await sourceStore.sources().filter { $0.kind == .watchedFolder }
            let permissions = try await permissionStore.records(scope: .watchedFolder)
            return sources.map { source in
                let permission = source.permissionRecordID.flatMap { id in permissions.first { $0.id == id } }
                return WatchedFolderStatus(
                    id: source.id,
                    url: source.url ?? permission?.url ?? URL(fileURLWithPath: ""),
                    state: folderWatcherState(from: source.watchState),
                    permissionState: permission?.state ?? .missing,
                    captureLocation: captureLocation(from: source),
                    message: source.lastScanSummary?.message ?? permission?.message
                )
            }
        }

        let records = try await permissionStore.records(scope: .watchedFolder)
        var statuses: [WatchedFolderStatus] = []
        for record in records.sorted(by: { $0.url.path < $1.url.path }) {
            let state = if let watcher = watchers[record.id] {
                await watcher.state
            } else {
                FolderWatcherState.stopped
            }
            statuses.append(
                WatchedFolderStatus(
                    id: record.id,
                    url: record.url,
                    state: state,
                    permissionState: record.state,
                    captureLocation: captureLocation(from: record),
                    message: record.message
                )
            )
        }
        return statuses
    }

    public func startScanning() {
        guard scanTask == nil else {
            return
        }

        scanTask = Task { [scanIntervalNanoseconds] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: scanIntervalNanoseconds)
                guard !Task.isCancelled else {
                    return
                }
                _ = try? await self.scanOnce()
            }
        }
    }

    public func stopScanning() async {
        scanTask?.cancel()
        scanTask = nil
        for watcher in watchers.values {
            await watcher.stop()
        }
        watchers = [:]
    }

    private func commonLocationURL(for location: CommonCaptureLocation) throws -> URL {
        if let url = commonLocationURLs[location] {
            return url
        }
        guard let url = fileManager.urls(for: location.searchPathDirectory, in: .userDomainMask).first else {
            throw WatchFolderAutomationError.commonCaptureLocationUnavailable(location)
        }
        return url
    }

    private func metadata(for location: CommonCaptureLocation, url: URL) -> [String: String] {
        [
            "captureLocation": location.rawValue,
            "captureLocationName": location.displayName,
            "watchFolderPath": url.path,
            "watchEnabled": "true"
        ]
    }

    private func captureLocation(from record: PermissionRecord) -> CommonCaptureLocation? {
        record.metadata["captureLocation"].flatMap(CommonCaptureLocation.init(rawValue:))
    }

    private func sourceDetail(for record: PermissionRecord) -> [String: String] {
        var detail = record.metadata
        detail["watchFolderID"] = record.id.uuidString
        detail["watchFolderPath"] = record.url.path
        if detail["captureLocation"] == nil {
            detail["captureLocation"] = "custom"
            detail["captureLocationName"] = "Watched Folder"
        }
        return detail
    }

    private func reloadSourceBackedWatchers(sourceStore: SourceStore) async throws {
        let sources = try await sourceStore.enabledSources(kind: .watchedFolder)
        let permissions = try await permissionStore.records(scope: .watchedFolder)
        for source in sources {
            guard let permissionRecordID = source.permissionRecordID,
                  let permission = permissions.first(where: { $0.id == permissionRecordID }) else {
                try await update(source: source, watchState: .permissionNeeded, message: "Permission record is missing.")
                continue
            }
            guard permission.state == .granted else {
                try await update(source: source, watchState: .permissionNeeded, message: permission.message ?? "Permission is \(permission.state.rawValue).")
                continue
            }
            guard let sourceURL = source.url else {
                try await update(source: source, watchState: .missing, message: "Source path is missing.")
                continue
            }

            let watcher = PollingFolderWatcher(
                configuration: FolderWatchConfiguration(
                    folderURL: sourceURL,
                    sourceID: source.id,
                    mode: .organize,
                    sourceDetail: sourceDetail(for: source, permission: permission)
                ),
                intakeService: intakeService
            )
            do {
                try await watcher.start()
                watchers[source.id] = watcher
                try await update(source: source, watchState: .running, message: "Watching for new arrivals.")
            } catch {
                let state: SourceWatchState = if case FolderWatcherError.watchedFolderMissing = error {
                    .missing
                } else {
                    .error
                }
                try await update(source: source, watchState: state, message: error.localizedDescription)
            }
        }
    }

    private func updateSourceAfterScan(id: UUID, emittedCount: Int) async throws {
        guard let sourceStore,
              var source = try await sourceStore.source(id: id) else {
            return
        }
        source.lastScanAt = Date()
        source.lastScanSummary = SourceScanSummary(
            discoveredCount: emittedCount,
            indexedCount: emittedCount,
            message: emittedCount == 1 ? "1 new item received." : "\(emittedCount) new items received."
        )
        source.updatedAt = Date()
        try await sourceStore.upsert(source)
    }

    private func updateSourceWatchState(id: UUID, state: SourceWatchState, enabled: Bool) async throws {
        guard let sourceStore,
              var source = try await sourceStore.source(id: id) else {
            return
        }
        source.enabled = enabled
        source.watchState = state
        source.updatedAt = Date()
        try await sourceStore.upsert(source)
    }

    private func update(source: SourceRecord, watchState: SourceWatchState, message: String?) async throws {
        guard let sourceStore else { return }
        var updated = source
        updated.watchState = watchState
        updated.lastScanSummary = SourceScanSummary(message: message)
        updated.updatedAt = Date()
        try await sourceStore.upsert(updated)
    }

    private func sourceDetail(for source: SourceRecord, permission: PermissionRecord) -> [String: String] {
        var detail = permission.metadata
        detail.merge(source.captureDetail) { _, new in new }
        detail["permissionRecordID"] = permission.id.uuidString
        detail["watchFolderPath"] = source.url?.path ?? permission.url.path
        if detail["captureLocation"] == nil {
            detail["captureLocation"] = "custom"
            detail["captureLocationName"] = source.displayName
        }
        return detail
    }

    private func captureLocation(from source: SourceRecord) -> CommonCaptureLocation? {
        source.metadata["captureLocation"].flatMap(CommonCaptureLocation.init(rawValue:))
    }

    private func folderWatcherState(from sourceWatchState: SourceWatchState) -> FolderWatcherState {
        switch sourceWatchState {
        case .running:
            .running
        case .paused:
            .paused
        case .stopped, .permissionNeeded, .missing, .error:
            .stopped
        }
    }
}
