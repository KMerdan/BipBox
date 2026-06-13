import CryptoKit
import Foundation

/// One node emitted by the descent. The unit kinds mirror the validated
/// experiment model: a PROJECT (marker folder) is one opaque unit, a COLLECTION
/// (non-project leaf folder) is one topic unit whose member files stay
/// individually indexed, and everything between root and units is a container
/// that only contributes loose files.
public struct DescentUnit: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case project
        case workspaceMember   // child project inside a workspace monorepo
        case bundle            // opaque package dir (.app, .photoslibrary, …)
        case collection        // non-project folder collapsed into one unit
        case file              // loose file, or a collection member
    }

    public let kind: Kind
    public let url: URL
    /// For collection members: the collection folder they belong to (nil = loose file).
    public let collectionURL: URL?
    /// For projects: the matched marker names (".git", "Package.swift", …).
    public let markers: [String]
    /// For files: "size:hash(head4k+tail4k)" — name-independent, so renamed copies
    /// collide. Near-dups (same meaning, different bytes) are NOT handled here.
    public let byteFingerprint: String?
    /// True when another file with the same fingerprint was chosen as primary —
    /// duplicates are indexed for search but never embedded.
    public let isDuplicate: Bool

    public init(kind: Kind, url: URL, collectionURL: URL? = nil, markers: [String] = [],
                byteFingerprint: String? = nil, isDuplicate: Bool = false) {
        self.kind = kind
        self.url = url
        self.collectionURL = collectionURL
        self.markers = markers
        self.byteFingerprint = byteFingerprint
        self.isDuplicate = isDuplicate
    }
}

/// Filesystem descent with unit classification — the Swift port of the validated
/// experiment walk. For every directory it decides: project (stop, one unit),
/// bundle (stop, opaque), collection (stop, one unit + indexed members), or
/// container (descend). That single decision is both the folder-vs-project
/// distinction and the depth decision.
public struct FilesystemDescender {

    /// Directories never entered and never emitted (build junk, caches).
    public static let pruneDirs: Set<String> = [
        "node_modules", ".build", ".git", "DerivedData", "target", "dist", "build",
        "__pycache__", ".venv", "venv", "env", "vendor", "Pods", ".next", ".nuxt",
        ".gradle", ".idea", ".cache", ".pytest_cache", ".mypy_cache", ".tox",
        "Carthage", ".terraform", "bin", "obj", ".dart_tool", ".svelte-kit"
    ]

    /// Exact-name markers that make a directory a PROJECT.
    public static let projectMarkers: Set<String> = [
        ".git", "Package.swift", "package.json", "Cargo.toml", "go.mod",
        "pyproject.toml", "pom.xml", "build.gradle", "build.gradle.kts", "Gemfile",
        "requirements.txt", "setup.py", "Makefile", "CMakeLists.txt", "composer.json",
        "pubspec.yaml", ".project", "mix.exs", "Dockerfile"
    ]
    public static let projectMarkerSuffixes = [".xcodeproj", ".xcworkspace"]

    /// Manifests that mean "this project owns child projects" (monorepo).
    public static let workspaceManifests: Set<String> = [
        "pnpm-workspace.yaml", "go.work", "lerna.json", "nx.json", "turbo.json"
    ]

    /// Package-directory suffixes treated as a single opaque unit.
    public static let bundleSuffixes = [
        ".app", ".framework", ".bundle", ".photoslibrary", ".rtfd", ".xcassets",
        ".playground", ".plugin", ".kext", ".docset"
    ]

    private let fileManager: FileManager
    private let maxDepth: Int

    public init(fileManager: FileManager = .default, maxDepth: Int = 5) {
        self.fileManager = fileManager
        self.maxDepth = maxDepth
    }

    /// Walk `root` and return every emitted unit, with exact-duplicate files
    /// (same byte fingerprint) resolved: the shortest-path copy is primary,
    /// the rest are flagged `isDuplicate`.
    public func descend(root: URL) -> [DescentUnit] {
        var units: [DescentUnit] = []
        walk(root, depth: 0, into: &units)
        return Self.resolveDuplicates(units)
    }

    // MARK: - Walk

    private func walk(_ dir: URL, depth: Int, into units: inout [DescentUnit]) {
        let (dirs, files) = entries(of: dir)

        // Classify THIS directory (the root itself is always a container).
        if depth > 0 {
            if Self.bundleSuffixes.contains(where: { dir.lastPathComponent.hasSuffix($0) }) {
                units.append(DescentUnit(kind: .bundle, url: dir, byteFingerprint: bundleFingerprint(dir)))
                return // opaque unit — never descend
            }

            let markers = projectMarkers(dirURLs: dirs, fileURLs: files)
            if !markers.isEmpty {
                units.append(DescentUnit(kind: .project, url: dir, markers: markers,
                                         byteFingerprint: projectFingerprint(dir, markers: markers)))
                // A workspace monorepo additionally surfaces its member projects.
                if hasWorkspaceManifest(dir: dir, fileURLs: files) {
                    for sub in dirs where !isPruned(sub) {
                        let (subDirs, subFiles) = entries(of: sub)
                        let subMarkers = projectMarkers(dirURLs: subDirs, fileURLs: subFiles)
                        if !subMarkers.isEmpty {
                            units.append(DescentUnit(kind: .workspaceMember, url: sub, markers: subMarkers,
                                                     byteFingerprint: projectFingerprint(sub, markers: subMarkers)))
                        }
                    }
                }
                return // STOP — a project is one unit; its files are not indexed
            }

            // Non-project folder: container (holds projects -> descend) or
            // collection (the folder IS the topic -> collapse the subtree).
            if !dirHasProjectChild(dirs) {
                emitCollection(dir, into: &units)
                return // STOP — collections collapse their subtree (no depth cap)
            }
        }

        // Container (or root): loose files here, then descend.
        for file in files {
            units.append(fileUnit(file, collectionURL: nil))
        }
        guard depth < maxDepth else { return }
        for sub in dirs where !isPruned(sub) {
            walk(sub, depth: depth + 1, into: &units)
        }
    }

    /// A collection = one unit + every member file (so search hits exact files).
    /// Nested projects are split out as their own units and pruned from the
    /// member walk — a collection never swallows a project.
    private func emitCollection(_ dir: URL, into units: inout [DescentUnit]) {
        var members: [URL] = []
        var queue = [dir]
        while let cur = queue.popLast() {
            let (dirs, files) = entries(of: cur)
            for sub in dirs where !isPruned(sub) {
                let (subDirs, subFiles) = entries(of: sub)
                let markers = projectMarkers(dirURLs: subDirs, fileURLs: subFiles)
                if !markers.isEmpty {
                    units.append(DescentUnit(kind: .project, url: sub, markers: markers))
                } else {
                    queue.append(sub)
                }
            }
            members.append(contentsOf: files)
        }
        // The collection's fingerprint is composite over its members' names and
        // fingerprints — its unit text derives from exactly those, so any member
        // add/remove/rename/edit changes it and triggers re-embedding.
        let memberUnits = members.map { fileUnit($0, collectionURL: dir) }
        let prefixLength = dir.path.count
        let fingerprint = Self.combinedFingerprint(memberUnits.map {
            String($0.url.path.dropFirst(prefixLength)) + ":" + ($0.byteFingerprint ?? "")
        }.sorted())
        units.append(DescentUnit(kind: .collection, url: dir, byteFingerprint: fingerprint))
        units.append(contentsOf: memberUnits)
    }

    private func fileUnit(_ url: URL, collectionURL: URL?) -> DescentUnit {
        DescentUnit(kind: .file, url: url, collectionURL: collectionURL,
                    byteFingerprint: Self.byteFingerprint(of: url))
    }

    // MARK: - Classification helpers

    private func projectMarkers(dirURLs: [URL], fileURLs: [URL]) -> [String] {
        var matched: [String] = []
        for url in dirURLs + fileURLs {
            let name = url.lastPathComponent
            if Self.projectMarkers.contains(name) { matched.append(name) }
            else if Self.projectMarkerSuffixes.contains(where: { name.hasSuffix($0) }) { matched.append(name) }
        }
        return matched.sorted()
    }

    private func hasWorkspaceManifest(dir: URL, fileURLs: [URL]) -> Bool {
        let names = Set(fileURLs.map(\.lastPathComponent))
        if !names.isDisjoint(with: Self.workspaceManifests) { return true }
        // Cargo workspaces live inside Cargo.toml — cheap text peek.
        if names.contains("Cargo.toml"),
           let text = try? String(contentsOf: dir.appendingPathComponent("Cargo.toml"), encoding: .utf8),
           text.contains("[workspace]") {
            return true
        }
        return false
    }

    /// One-level lookahead: a non-project folder is a container (descend) iff
    /// any immediate subdir is itself a project; otherwise it's a collection.
    private func dirHasProjectChild(_ dirs: [URL]) -> Bool {
        for sub in dirs where !isPruned(sub) {
            let (subDirs, subFiles) = entries(of: sub)
            if !projectMarkers(dirURLs: subDirs, fileURLs: subFiles).isEmpty { return true }
        }
        return false
    }

    private func isPruned(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        return Self.pruneDirs.contains(name) || name.hasPrefix(".")
    }

    /// Directory listing split into (dirs, files), symlinks skipped. Hidden
    /// entries are KEPT here (markers like ".git" must be visible to the
    /// classifier); descent itself skips them via `isPruned`.
    private func entries(of dir: URL) -> (dirs: [URL], files: [URL]) {
        guard let all = try? fileManager.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        ) else { return ([], []) }
        var dirs: [URL] = []
        var files: [URL] = []
        for url in all.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isSymbolicLink != true else { continue }
            if values.isDirectory == true { dirs.append(url) } else { files.append(url) }
        }
        return (dirs, files)
    }

    // MARK: - Fingerprints

    /// A project's fingerprint covers what its unit text derives from: the
    /// matched markers, the top-level listing, and the bytes of README/manifest
    /// files. Deep source edits inside the repo do NOT change it by design —
    /// the project node represents the project, not its diff history.
    private func projectFingerprint(_ dir: URL, markers: [String]) -> String {
        var parts = markers
        let names = ((try? fileManager.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
        parts.append(names.joined(separator: ","))
        for name in names {
            let lowered = name.lowercased()
            if lowered.hasPrefix("readme") || ["package.json", "cargo.toml", "pyproject.toml"].contains(lowered) {
                parts.append(Self.byteFingerprint(of: dir.appendingPathComponent(name)) ?? "")
            }
        }
        return Self.combinedFingerprint(parts)
    }

    /// Bundles are opaque; their dir mtime changes when direct contents do.
    private func bundleFingerprint(_ dir: URL) -> String? {
        guard let mtime = (try? dir.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        else { return nil }
        return Self.combinedFingerprint([dir.lastPathComponent, String(mtime.timeIntervalSince1970)])
    }

    static func combinedFingerprint(_ parts: [String]) -> String {
        var hasher = SHA256()
        hasher.update(data: Data(parts.joined(separator: "\u{1f}").utf8))
        return hasher.finalize().prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Dedup

    /// "size:hash(head4k+tail4k)" — cheap structural fingerprint, no full read.
    /// Name-independent, so renamed copies collide.
    public static func byteFingerprint(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize else { return nil }
        let head = (try? handle.read(upToCount: 4096)) ?? Data()
        var tail = Data()
        if size > 8192 {
            try? handle.seek(toOffset: UInt64(size - 4096))
            tail = (try? handle.read(upToCount: 4096)) ?? Data()
        }
        var hasher = SHA256()
        hasher.update(data: head)
        hasher.update(data: tail)
        let digest = hasher.finalize().prefix(8).map { String(format: "%02x", $0) }.joined()
        return "\(size):\(digest)"
    }

    /// Group files by fingerprint; the shortest path (then lexicographic) is the
    /// primary, the rest are flagged duplicates.
    static func resolveDuplicates(_ units: [DescentUnit]) -> [DescentUnit] {
        var groups: [String: [Int]] = [:]
        for (i, unit) in units.enumerated() {
            if unit.kind == .file, let fp = unit.byteFingerprint {
                groups[fp, default: []].append(i)
            }
        }
        var result = units
        for indices in groups.values where indices.count > 1 {
            let primary = indices.min { a, b in
                let (pa, pb) = (units[a].url.path, units[b].url.path)
                return pa.count != pb.count ? pa.count < pb.count : pa < pb
            }
            for i in indices where i != primary {
                let u = units[i]
                result[i] = DescentUnit(kind: u.kind, url: u.url, collectionURL: u.collectionURL,
                                        markers: u.markers, byteFingerprint: u.byteFingerprint,
                                        isDuplicate: true)
            }
        }
        return result
    }
}
