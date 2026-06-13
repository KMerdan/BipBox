import Foundation
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif

public final class DefaultMetadataExtractionService: MetadataExtractionService, @unchecked Sendable {
    private let fileManager: FileManager
    private let maxTextBytes: Int
    private let maxCharacters: Int
    private let textExtractor: FileTextExtracting?
    private let textExtensions: Set<String>

    /// Files read directly as UTF-8 (plain text + source code). Richer types
    /// (PDF/doc/docx/image) go through the injected `textExtractor`.
    public static let defaultTextExtensions: Set<String> = [
        "txt", "md", "markdown", "csv", "tsv", "json", "yaml", "yml", "log", "toml", "xml", "ini",
        "swift", "js", "ts", "tsx", "jsx", "py", "java", "c", "cpp", "cc", "h", "hpp", "rb", "go",
        "rs", "kt", "m", "mm", "php", "lua", "r", "sh", "bash", "zsh", "sql", "css", "scss"
    ]

    public init(
        fileManager: FileManager = .default,
        maxTextBytes: Int = 512_000,
        maxCharacters: Int = 6000,
        textExtractor: FileTextExtracting? = nil,
        textExtensions: Set<String> = DefaultMetadataExtractionService.defaultTextExtensions
    ) {
        self.fileManager = fileManager
        self.maxTextBytes = maxTextBytes
        self.maxCharacters = maxCharacters
        self.textExtractor = textExtractor
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

        var text: String?
        if isTextCandidate(item) {
            // Plain text / source code: read UTF-8 directly (bounded).
            if let data = try? Data(contentsOf: item.url, options: [.mappedIfSafe]) {
                if data.count > maxTextBytes {
                    warnings.append("Text extraction skipped because file is larger than \(maxTextBytes) bytes.")
                } else if let utf8 = String(data: data, encoding: .utf8), !utf8.isEmpty {
                    text = utf8
                } else {
                    warnings.append("Text extraction skipped because UTF-8 text was unavailable.")
                }
            } else {
                warnings.append("Text extraction failed: could not read file.")
            }
        } else if let textExtractor {
            // Rich types — PDF / doc / docx / image OCR — via the macOS extractor.
            text = await textExtractor.extractText(
                from: item.url, uti: item.uniformTypeIdentifier, maxCharacters: maxCharacters)
            if text == nil { metadata["metadata.extraction.skipped"] = "unsupportedType" }
        } else {
            metadata["metadata.extraction.skipped"] = "unsupportedType"
        }

        if let text, !text.isEmpty {
            // Bounded slice feeds lexical search AND embeddings (not just NLP tokens).
            metadata["text.content"] = String(text.prefix(maxCharacters))
            metadata.merge(Self.naturalLanguageMetadata(from: text)) { _, new in new }
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
