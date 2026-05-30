import BipboxCore
import Foundation

public enum RuleDocumentStoreError: Error, Equatable, LocalizedError {
    case storageUnavailable(URL, String)
    case invalidRuleFile(URL, String)

    public var errorDescription: String? {
        switch self {
        case .storageUnavailable(let url, let reason):
            "Rule storage is unavailable at \(url.path): \(reason)"
        case .invalidRuleFile(let url, let reason):
            "Rule file is invalid at \(url.path): \(reason)"
        }
    }
}

public final class JSONRuleDocumentStore: RuleDocumentStore, @unchecked Sendable {
    public let directoryURL: URL

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(directoryURL: URL, fileManager: FileManager = .default) throws {
        self.directoryURL = directoryURL
        self.fileManager = fileManager
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder = JSONDecoder()

        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        } catch {
            throw RuleDocumentStoreError.storageUnavailable(directoryURL, error.localizedDescription)
        }
    }

    public func loadRules() async throws -> [RuleDocument] {
        try loadRulesSync()
    }

    public func saveRule(_ rule: RuleDocument) async throws {
        try saveRuleSync(rule)
    }

    public func deleteRule(id: UUID) async throws {
        try deleteRuleSync(id: id)
    }

    public func fileURL(for id: UUID) async throws -> URL? {
        try ruleFileURLIfPresent(id: id)
    }

    public func loadRulesSync() throws -> [RuleDocument] {
        let fileURLs: [URL]
        do {
            fileURLs = try fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: nil
            )
        } catch {
            throw RuleDocumentStoreError.storageUnavailable(directoryURL, error.localizedDescription)
        }

        let rules = try fileURLs
            .filter { $0.pathExtension.lowercased() == "json" }
            .map(loadRule)

        return rules.sortedForWorkflow()
    }

    public func saveRuleSync(_ rule: RuleDocument) throws {
        try deleteRuleFileIfPresent(id: rule.id)
        let data = try encoder.encode(rule)
        let targetURL = directoryURL.appendingPathComponent(fileName(for: rule), isDirectory: false)

        do {
            try data.write(to: targetURL, options: .atomic)
        } catch {
            throw RuleDocumentStoreError.storageUnavailable(targetURL, error.localizedDescription)
        }
    }

    public func deleteRuleSync(id: UUID) throws {
        try deleteRuleFileIfPresent(id: id)
    }

    private func loadRule(from url: URL) throws -> RuleDocument {
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(RuleDocument.self, from: data)
        } catch {
            throw RuleDocumentStoreError.invalidRuleFile(url, error.localizedDescription)
        }
    }

    private func deleteRuleFileIfPresent(id: UUID) throws {
        guard let url = try ruleFileURLIfPresent(id: id) else {
            return
        }

        do {
            try fileManager.removeItem(at: url)
        } catch {
            throw RuleDocumentStoreError.storageUnavailable(url, error.localizedDescription)
        }
    }

    private func ruleFileURLIfPresent(id: UUID) throws -> URL? {
        let fileURLs: [URL]
        do {
            fileURLs = try fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)
        } catch {
            throw RuleDocumentStoreError.storageUnavailable(directoryURL, error.localizedDescription)
        }

        for url in fileURLs where url.lastPathComponent.contains(id.uuidString.lowercased()) ||
            url.lastPathComponent.contains(id.uuidString.uppercased()) {
            return url
        }

        return nil
    }

    private func fileName(for rule: RuleDocument) -> String {
        let position = String(format: "%03d", rule.position)
        return "\(position)-\(slug(rule.name))-\(rule.id.uuidString.lowercased()).json"
    }

    private func slug(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = value
            .lowercased()
            .unicodeScalars
            .map { allowed.contains($0) ? Character($0) : "-" }
        let collapsed = String(scalars)
            .split(separator: "-")
            .joined(separator: "-")
        return collapsed.isEmpty ? "rule" : collapsed
    }
}
