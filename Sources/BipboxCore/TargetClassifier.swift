import Foundation

/// The "nature" of a thing pointed at Bipbox — used to pick a smart capture
/// strategy (instead of asking the user "top level or deep?") and to seed a
/// meaningful entity/cluster.
public enum TargetNature: String, Sendable, Equatable, CaseIterable {
    case project        // a repo / codebase (.git, Package.swift, Cargo.toml, …)
    case workspace      // a folder full of projects (e.g. ~/Code)
    case media          // mostly images / video / audio
    case documents      // mostly docs / spreadsheets / pdfs
    case mixed          // a heterogeneous dump (Downloads, Desktop)
    case bundle         // a package/bundle (.app, .framework)
    case file           // a single file, not a folder

    public var displayName: String {
        switch self {
        case .project: "project"
        case .workspace: "workspace"
        case .media: "media library"
        case .documents: "documents"
        case .mixed: "folder"
        case .bundle: "package"
        case .file: "file"
        }
    }

    /// Context kind to attach for this nature (nil = generic folder context).
    public var contextKind: ContextKind {
        switch self {
        case .project, .workspace: .project
        default: .folder
        }
    }

    /// Whether offering a "index everything inside" depth option makes sense.
    public var supportsDeepIndex: Bool {
        self == .project || self == .workspace
    }
}

public struct TargetClassification: Sendable, Equatable {
    public var nature: TargetNature
    public var recommendedPolicy: SourceRecursivePolicy
    public var rationale: String

    public init(nature: TargetNature, recommendedPolicy: SourceRecursivePolicy, rationale: String) {
        self.nature = nature
        self.recommendedPolicy = recommendedPolicy
        self.rationale = rationale
    }
}

public protocol TargetClassifier: Sendable {
    func classify(url: URL) -> TargetClassification
}

/// Cheap, top-level-only classifier (one directory listing + a marker peek).
/// Default capture is always top-level (`.never`) — recursion is opt-in — so the
/// user is never interrogated; we just label what we found.
public struct DefaultTargetClassifier: TargetClassifier {
    public init() {}

    private var fileManager: FileManager { .default }

    private static let projectMarkers: Set<String> = [
        ".git", "Package.swift", "package.json", "Cargo.toml", "go.mod",
        "pyproject.toml", "pom.xml", "build.gradle", "Gemfile",
        "requirements.txt", "Makefile", "CMakeLists.txt"
    ]
    private static let projectMarkerSuffixes = [".xcodeproj", ".xcworkspace"]
    private static let mediaExts: Set<String> = [
        "png", "jpg", "jpeg", "gif", "heic", "webp", "svg", "tiff", "bmp",
        "mp4", "mov", "m4v", "avi", "mkv", "mp3", "wav", "aac", "m4a", "flac"
    ]
    private static let docExts: Set<String> = [
        "pdf", "doc", "docx", "pages", "txt", "md", "rtf",
        "csv", "xls", "xlsx", "key", "ppt", "pptx"
    ]

    public func classify(url: URL) -> TargetClassification {
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir) else {
            return .init(nature: .file, recommendedPolicy: .never, rationale: "Not found.")
        }
        if !isDir.boolValue {
            return .init(nature: .file, recommendedPolicy: .never, rationale: "A single file.")
        }
        if (try? url.resourceValues(forKeys: [.isPackageKey]))?.isPackage == true {
            return .init(nature: .bundle, recommendedPolicy: .never, rationale: "A package/bundle.")
        }

        let entries = (try? fileManager.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey], options: []
        )) ?? []
        let names = entries.map { $0.lastPathComponent }

        if hasProjectMarker(names) {
            return .init(nature: .project, recommendedPolicy: .never,
                         rationale: "Contains a project marker (\(matchedMarker(names) ?? "repo")).")
        }

        let childDirs = entries.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
        if childDirs.count >= 2 {
            let projectChildren = childDirs.prefix(24).filter { isProjectFolder($0) }.count
            if projectChildren >= 2 && projectChildren * 2 >= min(childDirs.count, 24) {
                return .init(nature: .workspace, recommendedPolicy: .never,
                             rationale: "\(projectChildren) of its subfolders look like projects.")
            }
        }

        // Classify by the dominant file type at the top level.
        let exts = names.compactMap { name -> String? in
            let e = (name as NSString).pathExtension.lowercased()
            return e.isEmpty ? nil : e
        }
        if !exts.isEmpty {
            let media = exts.filter { Self.mediaExts.contains($0) }.count
            let docs = exts.filter { Self.docExts.contains($0) }.count
            if media * 10 >= exts.count * 6 {
                return .init(nature: .media, recommendedPolicy: .never, rationale: "Mostly media files.")
            }
            if docs * 10 >= exts.count * 6 {
                return .init(nature: .documents, recommendedPolicy: .never, rationale: "Mostly documents.")
            }
        }
        return .init(nature: .mixed, recommendedPolicy: .never, rationale: "A mix of files and folders.")
    }

    private func hasProjectMarker(_ names: [String]) -> Bool {
        matchedMarker(names) != nil
    }

    private func matchedMarker(_ names: [String]) -> String? {
        if let exact = names.first(where: { Self.projectMarkers.contains($0) }) { return exact }
        return names.first { name in Self.projectMarkerSuffixes.contains { name.hasSuffix($0) } }
    }

    private func isProjectFolder(_ url: URL) -> Bool {
        let names = ((try? fileManager.contentsOfDirectory(atPath: url.path)) ?? [])
        return hasProjectMarker(names)
    }
}
