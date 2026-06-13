import Foundation

/// Data-directory-wide versioning, above the per-store SQLite `user_version`s.
/// Covers cross-cutting transitions that no single store can see — e.g. "items
/// indexed before the unit model carry no unit tags". The remedy for derived
/// data is always the same: a (cheap, fingerprint-skipping) full rescan.
public struct DataDirectoryMeta: Codable, Equatable, Sendable {
    public var appDataVersion: Int

    public init(appDataVersion: Int) {
        self.appDataVersion = appDataVersion
    }
}

public enum DataDirectoryMetaStore {
    /// 1 = pre-unit-model scans (no unit:* tags, no content fingerprints)
    /// 2 = descent/collection unit model + incremental-rescan fingerprints
    public static let currentVersion = 2

    public static func metaURL(dataDirectoryURL: URL) -> URL {
        dataDirectoryURL.appendingPathComponent("meta.json", isDirectory: false)
    }

    /// Read (or infer) the data dir's version, stamp it to current, and report
    /// whether a full rescan is needed to bring derived data up to date.
    ///
    /// A data dir with existing stores but no meta.json predates versioning ->
    /// version 1. A fresh dir starts at current. A NEWER version than this app
    /// understands is left untouched and reported (the caller should surface
    /// "update Bipbox" instead of scanning).
    public static func reconcile(
        dataDirectoryURL: URL,
        fileManager: FileManager = .default
    ) -> (meta: DataDirectoryMeta, needsFullRescan: Bool) {
        let url = metaURL(dataDirectoryURL: dataDirectoryURL)

        let onDisk: DataDirectoryMeta
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(DataDirectoryMeta.self, from: data) {
            onDisk = decoded
        } else {
            // No meta: legacy dir if any store already exists, fresh otherwise.
            let searchStore = dataDirectoryURL
                .appendingPathComponent("Search", isDirectory: true)
                .appendingPathComponent("search.sqlite", isDirectory: false)
            let isLegacy = fileManager.fileExists(atPath: searchStore.path)
            onDisk = DataDirectoryMeta(appDataVersion: isLegacy ? 1 : currentVersion)
        }

        guard onDisk.appDataVersion <= currentVersion else {
            return (onDisk, false) // newer app wrote this — don't touch it
        }

        let stamped = DataDirectoryMeta(appDataVersion: currentVersion)
        try? fileManager.createDirectory(at: dataDirectoryURL, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(stamped) {
            try? data.write(to: url, options: [.atomic])
        }
        return (stamped, onDisk.appDataVersion < currentVersion)
    }
}
