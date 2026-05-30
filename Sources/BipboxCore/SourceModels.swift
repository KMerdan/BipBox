import Foundation

public enum SourceKind: String, Codable, Equatable, CaseIterable, Sendable {
    case watchedFolder
    case menuBarDrop
    case manualImport
    case browserExtension
    case shareExtension
    case cli
    case agentRequest
}

public enum SourceRecursivePolicy: String, Codable, Equatable, CaseIterable, Sendable {
    case never
    case explicit
    case always
}

public enum SourceIndexState: String, Codable, Equatable, CaseIterable, Sendable {
    case pending
    case running
    case completed
    case failed
}

public enum SourceWatchState: String, Codable, Equatable, CaseIterable, Sendable {
    case stopped
    case running
    case paused
    case permissionNeeded
    case missing
    case error
}

public struct SourceScanSummary: Codable, Equatable, Sendable {
    public var discoveredCount: Int
    public var indexedCount: Int
    public var stagedCount: Int
    public var organizedCount: Int
    public var failedCount: Int
    public var message: String?

    public init(
        discoveredCount: Int = 0,
        indexedCount: Int = 0,
        stagedCount: Int = 0,
        organizedCount: Int = 0,
        failedCount: Int = 0,
        message: String? = nil
    ) {
        self.discoveredCount = discoveredCount
        self.indexedCount = indexedCount
        self.stagedCount = stagedCount
        self.organizedCount = organizedCount
        self.failedCount = failedCount
        self.message = message
    }
}

public struct SourceRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var kind: SourceKind
    public var displayName: String
    public var url: URL?
    public var permissionRecordID: UUID?
    public var enabled: Bool
    public var recursivePolicy: SourceRecursivePolicy
    public var indexState: SourceIndexState
    public var watchState: SourceWatchState
    public var lastScanAt: Date?
    public var lastScanSummary: SourceScanSummary?
    public var createdAt: Date
    public var updatedAt: Date
    public var metadata: [String: String]

    public init(
        id: UUID = UUID(),
        kind: SourceKind,
        displayName: String,
        url: URL? = nil,
        permissionRecordID: UUID? = nil,
        enabled: Bool = true,
        recursivePolicy: SourceRecursivePolicy = .never,
        indexState: SourceIndexState = .pending,
        watchState: SourceWatchState = .stopped,
        lastScanAt: Date? = nil,
        lastScanSummary: SourceScanSummary? = nil,
        createdAt: Date,
        updatedAt: Date,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.url = url
        self.permissionRecordID = permissionRecordID
        self.enabled = enabled
        self.recursivePolicy = recursivePolicy
        self.indexState = indexState
        self.watchState = watchState
        self.lastScanAt = lastScanAt
        self.lastScanSummary = lastScanSummary
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.metadata = metadata
    }

    public static func watchedFolder(
        id: UUID = UUID(),
        url: URL,
        displayName: String? = nil,
        permissionRecordID: UUID? = nil,
        enabled: Bool = true,
        createdAt: Date,
        updatedAt: Date? = nil,
        metadata: [String: String] = [:]
    ) -> SourceRecord {
        SourceRecord(
            id: id,
            kind: .watchedFolder,
            displayName: displayName ?? url.lastPathComponent.nonEmpty ?? url.path,
            url: url,
            permissionRecordID: permissionRecordID,
            enabled: enabled,
            recursivePolicy: .never,
            indexState: .pending,
            watchState: .stopped,
            createdAt: createdAt,
            updatedAt: updatedAt ?? createdAt,
            metadata: metadata
        )
    }

    public static func menuBarDrop(
        id: UUID = UUID(),
        displayName: String = "Menu Bar Drop",
        enabled: Bool = true,
        createdAt: Date,
        updatedAt: Date? = nil,
        metadata: [String: String] = [:]
    ) -> SourceRecord {
        ephemeralCaptureSurface(
            id: id,
            kind: .menuBarDrop,
            displayName: displayName,
            enabled: enabled,
            createdAt: createdAt,
            updatedAt: updatedAt,
            metadata: metadata
        )
    }

    public static func manualImport(
        id: UUID = UUID(),
        displayName: String = "Manual Import",
        url: URL? = nil,
        enabled: Bool = true,
        createdAt: Date,
        updatedAt: Date? = nil,
        metadata: [String: String] = [:]
    ) -> SourceRecord {
        SourceRecord(
            id: id,
            kind: .manualImport,
            displayName: displayName,
            url: url,
            enabled: enabled,
            recursivePolicy: .never,
            indexState: .completed,
            watchState: .stopped,
            createdAt: createdAt,
            updatedAt: updatedAt ?? createdAt,
            metadata: metadata
        )
    }

    private static func ephemeralCaptureSurface(
        id: UUID,
        kind: SourceKind,
        displayName: String,
        enabled: Bool,
        createdAt: Date,
        updatedAt: Date?,
        metadata: [String: String]
    ) -> SourceRecord {
        SourceRecord(
            id: id,
            kind: kind,
            displayName: displayName,
            enabled: enabled,
            recursivePolicy: .never,
            indexState: .completed,
            watchState: .stopped,
            createdAt: createdAt,
            updatedAt: updatedAt ?? createdAt,
            metadata: metadata
        )
    }
}

public extension SourceRecord {
    var captureDetail: [String: String] {
        var detail = metadata
        detail["sourceID"] = id.uuidString
        detail["sourceKind"] = kind.rawValue
        detail["sourceName"] = displayName
        if let url {
            detail["sourcePath"] = url.path
        }
        if let permissionRecordID {
            detail["permissionRecordID"] = permissionRecordID.uuidString
        }
        return detail
    }
}

public enum SourceStoreError: Error, Equatable, LocalizedError, Sendable {
    case missingSource(UUID)
    case duplicatePath(URL)
    case invalidURL(URL)
    case invalidStorage(URL, String)
    case storageUnavailable(URL, String)

    public var errorDescription: String? {
        switch self {
        case .missingSource(let id):
            "Source is missing: \(id.uuidString)"
        case .duplicatePath(let url):
            "A source already exists for \(url.path)."
        case .invalidURL(let url):
            "Source URL is invalid: \(url.path)"
        case .invalidStorage(let url, let reason):
            "Source storage is invalid at \(url.path): \(reason)"
        case .storageUnavailable(let url, let reason):
            "Source storage is unavailable at \(url.path): \(reason)"
        }
    }
}

public enum SourceStoreChange: Equatable, Sendable {
    case inserted(SourceRecord)
    case updated(SourceRecord)
    case removed(SourceRecord)
}

public struct SourceLifecycleRequest: Equatable, Sendable {
    public var sourceID: UUID?
    public var url: URL
    public var displayName: String?
    public var metadata: [String: String]
    public var enabled: Bool
    public var recursivePolicy: SourceRecursivePolicy

    public init(
        sourceID: UUID? = nil,
        url: URL,
        displayName: String? = nil,
        metadata: [String: String] = [:],
        enabled: Bool = true,
        recursivePolicy: SourceRecursivePolicy = .never
    ) {
        self.sourceID = sourceID
        self.url = url
        self.displayName = displayName
        self.metadata = metadata
        self.enabled = enabled
        self.recursivePolicy = recursivePolicy
    }
}

public struct SourceLifecycleResult: Equatable, Sendable {
    public var source: SourceRecord
    public var permissionRecord: PermissionRecord?
    public var scanResult: ColdStartScanResult?
    public var watcherReloaded: Bool
    public var message: String?

    public init(
        source: SourceRecord,
        permissionRecord: PermissionRecord? = nil,
        scanResult: ColdStartScanResult? = nil,
        watcherReloaded: Bool = false,
        message: String? = nil
    ) {
        self.source = source
        self.permissionRecord = permissionRecord
        self.scanResult = scanResult
        self.watcherReloaded = watcherReloaded
        self.message = message
    }
}

public enum SourceLifecycleError: Error, Equatable, LocalizedError, Sendable {
    case sourceMissingPermission(UUID)
    case watchedFolderRequired(UUID)

    public var errorDescription: String? {
        switch self {
        case .sourceMissingPermission(let id):
            "Source \(id.uuidString) does not have a permission record."
        case .watchedFolderRequired(let id):
            "Source \(id.uuidString) is not a watched folder."
        }
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
