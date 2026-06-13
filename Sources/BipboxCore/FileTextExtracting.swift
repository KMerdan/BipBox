import Foundation

/// Extracts plain text from a file whose bytes aren't directly UTF-8 readable —
/// PDFs, Word/RTF/HTML documents, images (OCR). Implemented in BipboxMacOSAdapters
/// with PDFKit / NSAttributedString / Vision, so BipboxCore stays framework-free.
public protocol FileTextExtracting: Sendable {
    /// Up to `maxCharacters` of extracted text, or nil if unsupported / empty.
    func extractText(from url: URL, uti: String?, maxCharacters: Int) async -> String?
}
