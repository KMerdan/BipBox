import Foundation

/// Assembles the text that REPRESENTS an aggregate unit for embedding — the
/// validated recipe: a project is its name + languages + manifest description +
/// top-level listing + README; a collection is its name + a sample of member
/// titles + a few text snippets. This is what makes one repo or one document
/// dump land in the right topic as a single node.
public enum UnitTextComposer {
    static let maxCharacters = 6000
    static let collectionTitleSample = 40
    static let collectionSnippets = 4

    private static let codeExtensions: Set<String> = [
        "swift", "js", "ts", "tsx", "jsx", "py", "java", "c", "cpp", "h",
        "hpp", "rb", "go", "rs", "kt", "m", "mm", "php", "lua", "r", "sh", "sql"
    ]

    // MARK: - Project

    public static func projectText(url: URL, fileManager: FileManager = .default) -> String {
        let name = url.lastPathComponent
        let langs = languages(in: url, fileManager: fileManager).joined(separator: ", ")
        let manifest = manifestDescription(in: url, fileManager: fileManager)
        let listing = ((try? fileManager.contentsOfDirectory(atPath: url.path)) ?? [])
            .filter { !$0.hasPrefix(".") }
            .sorted()
            .prefix(25)
            .joined(separator: ", ")
        let readme = readmeText(in: url, fileManager: fileManager)
        return clip("project: \(name). languages: \(langs). \(manifest). contents: \(listing). \(readme)")
    }

    /// Top source-file extensions inside the project (bounded walk).
    private static func languages(in url: URL, fileManager: FileManager, dirLimit: Int = 200) -> [String] {
        var counts: [String: Int] = [:]
        var queue = [url]
        var seen = 0
        while let dir = queue.popLast(), seen < dirLimit {
            seen += 1
            for entry in (try? fileManager.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [])) ?? [] {
                let name = entry.lastPathComponent
                if (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    if !FilesystemDescender.pruneDirs.contains(name), !name.hasPrefix(".") {
                        queue.append(entry)
                    }
                } else {
                    let ext = entry.pathExtension.lowercased()
                    if codeExtensions.contains(ext) { counts[ext, default: 0] += 1 }
                }
            }
        }
        return counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(4).map(\.key)
    }

    /// name/description/keywords from package.json, pyproject.toml, Cargo.toml.
    private static func manifestDescription(in url: URL, fileManager: FileManager) -> String {
        var parts: [String] = []
        let packageJSON = url.appendingPathComponent("package.json")
        if let data = try? Data(contentsOf: packageJSON),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            parts.append(obj["name"] as? String ?? "")
            parts.append(obj["description"] as? String ?? "")
            parts.append(((obj["keywords"] as? [String]) ?? []).joined(separator: " "))
            parts.append(((obj["dependencies"] as? [String: Any])?.keys.sorted().prefix(20))
                .map { $0.joined(separator: " ") } ?? "")
        }
        for manifest in ["pyproject.toml", "Cargo.toml"] {
            guard let text = try? String(contentsOf: url.appendingPathComponent(manifest), encoding: .utf8)
            else { continue }
            for line in text.split(separator: "\n").prefix(60) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("name") || trimmed.hasPrefix("description"),
                   let value = trimmed.split(separator: "=", maxSplits: 1).last {
                    parts.append(value.trimmingCharacters(in: CharacterSet(charactersIn: " \"'")))
                }
            }
        }
        return parts.filter { !$0.isEmpty }.joined(separator: " ")
    }

    private static func readmeText(in url: URL, fileManager: FileManager) -> String {
        let entries = (try? fileManager.contentsOfDirectory(atPath: url.path)) ?? []
        guard let readme = entries.first(where: { $0.lowercased().hasPrefix("readme") }),
              let text = try? String(contentsOf: url.appendingPathComponent(readme), encoding: .utf8)
        else { return "" }
        return String(text.prefix(4000))
    }

    // MARK: - Collection

    public static func collectionText(url: URL, memberURLs: [URL]) -> String {
        let name = url.lastPathComponent
        let titles = memberURLs
            .map { $0.deletingPathExtension().lastPathComponent }
            .filter { !$0.hasPrefix(".") }
            .prefix(collectionTitleSample)
            .joined(separator: ", ")
        var snippets: [String] = []
        for member in memberURLs where snippets.count < collectionSnippets {
            guard ["md", "txt"].contains(member.pathExtension.lowercased()),
                  let text = try? String(contentsOf: member, encoding: .utf8),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { continue }
            snippets.append(String(text.prefix(400)))
        }
        return clip("collection: \(name). items: \(titles). " + snippets.joined(separator: " "))
    }

    private static func clip(_ text: String) -> String {
        String(text.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(maxCharacters))
    }
}
