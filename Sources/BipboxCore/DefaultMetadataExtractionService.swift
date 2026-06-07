import Foundation
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif

public final class DefaultMetadataExtractionService: MetadataExtractionService, @unchecked Sendable {
    private let fileManager: FileManager
    private let maxTextBytes: Int
    private let textExtensions: Set<String>

    public init(
        fileManager: FileManager = .default,
        maxTextBytes: Int = 128_000,
        textExtensions: Set<String> = ["txt", "md", "markdown", "csv", "json", "yaml", "yml", "log"]
    ) {
        self.fileManager = fileManager
        self.maxTextBytes = maxTextBytes
        self.textExtensions = textExtensions
    }

    public func extractMetadata(for item: ItemProfile) async throws -> MetadataExtractionResult {
        var metadata: [String: String] = [:]
        var warnings: [String] = []

        metadata.merge(resourceMetadata(for: item)) { _, new in new }

        guard item.kind == .file else {
            metadata["metadata.extraction.skipped"] = "nonFile"
            return MetadataExtractionResult(metadata: metadata, warnings: warnings)
        }

        guard isTextCandidate(item) else {
            metadata["metadata.extraction.skipped"] = "unsupportedType"
            return MetadataExtractionResult(metadata: metadata, warnings: warnings)
        }

        do {
            let data = try Data(contentsOf: item.url, options: [.mappedIfSafe])
            guard data.count <= maxTextBytes else {
                warnings.append("Text extraction skipped because file is larger than \(maxTextBytes) bytes.")
                metadata["metadata.extraction.warningCount"] = String(warnings.count)
                return MetadataExtractionResult(metadata: metadata, warnings: warnings)
            }
            guard let text = String(data: data, encoding: .utf8), !text.isEmpty else {
                warnings.append("Text extraction skipped because UTF-8 text was unavailable.")
                metadata["metadata.extraction.warningCount"] = String(warnings.count)
                return MetadataExtractionResult(metadata: metadata, warnings: warnings)
            }

            // Keep a bounded slice of the raw text so it can feed lexical search
            // and embeddings (not just NLP-derived tokens).
            metadata["text.content"] = String(text.prefix(4000))
            metadata.merge(Self.naturalLanguageMetadata(from: text)) { _, new in new }
        } catch {
            warnings.append("Text extraction failed: \(error.localizedDescription)")
        }

        if !warnings.isEmpty {
            metadata["metadata.extraction.warningCount"] = String(warnings.count)
        }
        return MetadataExtractionResult(metadata: metadata, warnings: warnings)
    }

    private func resourceMetadata(for item: ItemProfile) -> [String: String] {
        var metadata: [String: String] = [
            "resource.displayName": item.displayName,
            "resource.kind": item.kind.rawValue
        ]
        if let uniformTypeIdentifier = item.uniformTypeIdentifier {
            metadata["resource.uniformTypeIdentifier"] = uniformTypeIdentifier
        }
        if let sizeBytes = item.sizeBytes {
            metadata["resource.sizeBytes"] = String(sizeBytes)
        }
        if !item.finderTags.isEmpty {
            metadata["resource.finderTags"] = item.finderTags.sorted().joined(separator: ",")
        }
        metadata["metadata.extractor"] = "local"
        return metadata
    }

    private func isTextCandidate(_ item: ItemProfile) -> Bool {
        if let fileExtension = item.fileExtension?.lowercased(), textExtensions.contains(fileExtension) {
            return true
        }
        if let uniformTypeIdentifier = item.uniformTypeIdentifier?.lowercased() {
            return uniformTypeIdentifier.contains("text") ||
                uniformTypeIdentifier.contains("json") ||
                uniformTypeIdentifier.contains("yaml")
        }
        return false
    }

    private static func naturalLanguageMetadata(from text: String) -> [String: String] {
        var metadata: [String: String] = [:]
        let fallbackTokens = fallbackTokenize(text)

        #if canImport(NaturalLanguage)
        let tagger = NLTagger(tagSchemes: [.lexicalClass, .lemma, .nameType])
        tagger.string = text

        var tokens: [String] = []
        var lemmas: [String] = []
        var names: [String] = []
        let range = text.startIndex..<text.endIndex
        tagger.enumerateTags(
            in: range,
            unit: .word,
            scheme: .lexicalClass,
            options: [.omitWhitespace, .omitPunctuation]
        ) { tag, tokenRange in
            let token = String(text[tokenRange]).lowercased()
            guard !token.isEmpty else { return true }
            tokens.append(token)
            if tag == .personalName || tag == .placeName || tag == .organizationName {
                names.append(String(text[tokenRange]))
            }
            if let lemma = tagger.tag(at: tokenRange.lowerBound, unit: .word, scheme: .lemma).0?.rawValue {
                lemmas.append(lemma.lowercased())
            }
            if let nameType = tagger.tag(at: tokenRange.lowerBound, unit: .word, scheme: .nameType).0,
               nameType == .personalName || nameType == .placeName || nameType == .organizationName {
                names.append(String(text[tokenRange]))
            }
            return true
        }

        metadata["nl.backend"] = "NLTagger"
        metadata["nl.tokens"] = limitedUnique(tokens.isEmpty ? fallbackTokens : tokens).joined(separator: ",")
        let uniqueLemmas = limitedUnique(lemmas.filter { !$0.isEmpty })
        if !uniqueLemmas.isEmpty {
            metadata["nl.lemmas"] = uniqueLemmas.joined(separator: ",")
        }
        let uniqueNames = limitedUnique(names)
        if !uniqueNames.isEmpty {
            metadata["nl.names"] = uniqueNames.joined(separator: ",")
        }
        #else
        metadata["nl.backend"] = "fallback"
        metadata["nl.tokens"] = limitedUnique(fallbackTokens).joined(separator: ",")
        #endif

        return metadata
    }

    private static func fallbackTokenize(_ text: String) -> [String] {
        text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 }
    }

    private static func limitedUnique(_ values: [String], limit: Int = 40) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values {
            guard seen.insert(value).inserted else { continue }
            result.append(value)
            if result.count == limit {
                break
            }
        }
        return result
    }
}
