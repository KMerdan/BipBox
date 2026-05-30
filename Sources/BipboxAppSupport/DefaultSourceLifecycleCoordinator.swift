import BipboxCore
import Foundation

public actor DefaultSourceLifecycleCoordinator: SourceLifecycleCoordinating {
    private let permissionStore: PermissionStore
    private let sourceStore: SourceStore
    private let scanner: ColdStartScanner?
    private let watcherReloader: SourceWatcherReloading?
    private let now: @Sendable () -> Date

    public init(
        permissionStore: PermissionStore,
        sourceStore: SourceStore,
        scanner: ColdStartScanner? = nil,
        watcherReloader: SourceWatcherReloading? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.permissionStore = permissionStore
        self.sourceStore = sourceStore
        self.scanner = scanner
        self.watcherReloader = watcherReloader
        self.now = now
    }

    @discardableResult
    public func addWatchedFolder(_ request: SourceLifecycleRequest) async throws -> SourceLifecycleResult {
        try await saveAndActivateWatchedFolder(request, existingSource: nil)
    }

    @discardableResult
    public func changeWatchedFolder(id: UUID, to request: SourceLifecycleRequest) async throws -> SourceLifecycleResult {
        guard let existingSource = try await sourceStore.source(id: id) else {
            throw SourceStoreError.missingSource(id)
        }
        guard existingSource.kind == .watchedFolder else {
            throw SourceLifecycleError.watchedFolderRequired(id)
        }
        return try await saveAndActivateWatchedFolder(request, existingSource: existingSource)
    }

    @discardableResult
    public func removeSource(id: UUID, removePermission: Bool = true) async throws -> SourceLifecycleResult {
        guard let existingSource = try await sourceStore.source(id: id) else {
            throw SourceStoreError.missingSource(id)
        }
        let permissionRecord = try await permissionRecord(id: existingSource.permissionRecordID)
        try await sourceStore.remove(id: id)
        if removePermission, let permissionRecordID = existingSource.permissionRecordID {
            try await permissionStore.remove(id: permissionRecordID)
        }
        try await reloadWatchers()
        var removedSource = existingSource
        removedSource.enabled = false
        removedSource.watchState = .stopped
        removedSource.updatedAt = now()
        return SourceLifecycleResult(
            source: removedSource,
            permissionRecord: permissionRecord,
            watcherReloaded: watcherReloader != nil,
            message: "Source removed."
        )
    }

    @discardableResult
    public func scanSource(id: UUID) async throws -> SourceLifecycleResult {
        guard var source = try await sourceStore.source(id: id) else {
            throw SourceStoreError.missingSource(id)
        }
        guard source.kind == .watchedFolder else {
            throw SourceLifecycleError.watchedFolderRequired(id)
        }
        let permissionRecord = try await permissionRecord(id: source.permissionRecordID)
        let scanResult = try await runInitialScan(source: &source, permissionRecordID: try permissionID(for: source))
        return SourceLifecycleResult(
            source: source,
            permissionRecord: permissionRecord,
            scanResult: scanResult,
            watcherReloaded: false,
            message: "Source scanned."
        )
    }

    @discardableResult
    public func pauseSource(id: UUID) async throws -> SourceLifecycleResult {
        guard var source = try await sourceStore.source(id: id) else {
            throw SourceStoreError.missingSource(id)
        }
        source.enabled = false
        source.watchState = .paused
        source.updatedAt = now()
        try await sourceStore.upsert(source)
        try await reloadWatchers()
        return SourceLifecycleResult(
            source: source,
            permissionRecord: try await permissionRecord(id: source.permissionRecordID),
            watcherReloaded: watcherReloader != nil,
            message: "Source paused."
        )
    }

    @discardableResult
    public func resumeSource(id: UUID) async throws -> SourceLifecycleResult {
        guard var source = try await sourceStore.source(id: id) else {
            throw SourceStoreError.missingSource(id)
        }
        source.enabled = true
        source.watchState = watcherReloader == nil ? .stopped : .running
        source.updatedAt = now()
        try await sourceStore.upsert(source)
        try await reloadWatchers()
        return SourceLifecycleResult(
            source: source,
            permissionRecord: try await permissionRecord(id: source.permissionRecordID),
            watcherReloaded: watcherReloader != nil,
            message: "Source resumed."
        )
    }

    private func saveAndActivateWatchedFolder(
        _ request: SourceLifecycleRequest,
        existingSource: SourceRecord?
    ) async throws -> SourceLifecycleResult {
        let timestamp = now()
        let savedPermissionRecord = PermissionRecord(
            id: UUID(),
            scope: .watchedFolder,
            url: request.url,
            state: .missing,
            metadata: sourceMetadata(request: request)
        )
        try await permissionStore.save(savedPermissionRecord)

        var source = SourceRecord.watchedFolder(
            id: existingSource?.id ?? request.sourceID ?? UUID(),
            url: request.url,
            displayName: request.displayName,
            permissionRecordID: savedPermissionRecord.id,
            enabled: request.enabled,
            createdAt: existingSource?.createdAt ?? timestamp,
            updatedAt: timestamp,
            metadata: sourceMetadata(request: request)
        )
        source.recursivePolicy = request.recursivePolicy
        source.indexState = scanner == nil ? .completed : .running
        source.watchState = .stopped
        try await sourceStore.upsert(source)

        let scanResult: ColdStartScanResult?
        do {
            scanResult = try await runInitialScan(source: &source, permissionRecordID: savedPermissionRecord.id)
        } catch {
            source.indexState = .failed
            source.watchState = .error
            source.lastScanAt = timestamp
            source.lastScanSummary = SourceScanSummary(
                failedCount: 1,
                message: error.localizedDescription
            )
            _ = try? await sourceStore.upsert(source)
            throw error
        }

        do {
            try await reloadWatchers()
            source.watchState = watcherReloader == nil ? .stopped : .running
            source.updatedAt = now()
            try await sourceStore.upsert(source)
        } catch {
            source.watchState = .error
            source.updatedAt = now()
            _ = try? await sourceStore.upsert(source)
            throw error
        }

        return SourceLifecycleResult(
            source: source,
            permissionRecord: try await permissionRecord(id: savedPermissionRecord.id) ?? savedPermissionRecord,
            scanResult: scanResult,
            watcherReloaded: watcherReloader != nil,
            message: "Source indexed and watching for new arrivals."
        )
    }

    private func runInitialScan(source: inout SourceRecord, permissionRecordID: UUID) async throws -> ColdStartScanResult? {
        guard let scanner else {
            source.indexState = .completed
            source.lastScanAt = now()
            source.lastScanSummary = SourceScanSummary(message: "No scanner configured.")
            try await sourceStore.upsert(source)
            return nil
        }

        let result = try await scanner.scan(
            ColdStartScanRequest(
                permissionRecordID: permissionRecordID,
                sourceID: source.id,
                recursive: source.recursivePolicy == .always,
                receivedAt: now(),
                sourceDetail: source.captureDetail
            ),
            progress: nil
        )
        source.indexState = result.failures.isEmpty ? .completed : .failed
        source.lastScanAt = now()
        source.lastScanSummary = SourceScanSummary(
            discoveredCount: result.scannedItemCount + result.failures.count,
            indexedCount: result.scannedItemCount,
            failedCount: result.failures.count,
            message: result.failures.isEmpty ? "Initial scan completed." : "Initial scan completed with failures."
        )
        source.updatedAt = now()
        try await sourceStore.upsert(source)
        return result
    }

    private func permissionID(for source: SourceRecord) throws -> UUID {
        guard let permissionRecordID = source.permissionRecordID else {
            throw SourceLifecycleError.sourceMissingPermission(source.id)
        }
        return permissionRecordID
    }

    private func permissionRecord(id: UUID?) async throws -> PermissionRecord? {
        guard let id else {
            return nil
        }
        return try await permissionStore.records(scope: nil).first { $0.id == id }
    }

    private func reloadWatchers() async throws {
        try await watcherReloader?.reloadWatchedFolders()
    }

    private func sourceMetadata(request: SourceLifecycleRequest) -> [String: String] {
        var metadata = request.metadata
        metadata["sourceKind"] = SourceKind.watchedFolder.rawValue
        metadata["watchEnabled"] = request.enabled ? "true" : "false"
        metadata["watchFolderPath"] = request.url.path
        metadata["watchFolderName"] = request.displayName ?? request.url.lastPathComponent.nonEmpty ?? request.url.path
        metadata["startPurpose"] = "watchAndIndex"
        return metadata
    }
}

extension WatchFolderAutomationService: SourceWatcherReloading {}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
