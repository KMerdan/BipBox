import BipboxCore
import Foundation
#if canImport(PDFKit)
import PDFKit
#endif
#if canImport(AppKit)
import AppKit
#endif
#if canImport(Vision)
import Vision
#endif

/// macOS-backed text extraction for rich file types: PDFs (PDFKit), Word/RTF/HTML
/// documents (the system text importers via NSAttributedString), and images (Vision
/// OCR). Plain text / source code is handled directly by the metadata service.
public struct MacContentExtractor: FileTextExtracting {
    public init() {}

    public func extractText(from url: URL, uti: String?, maxCharacters: Int) async -> String? {
        let ext = url.pathExtension.lowercased()

        if ext == "pdf" || (uti?.contains("pdf") ?? false) {
            return Self.clip(pdfText(url, max: maxCharacters), maxCharacters)
        }
        if ["doc", "docx", "rtf", "rtfd", "html", "htm", "odt", "wordml"].contains(ext) {
            return Self.clip(attributedText(url), maxCharacters)
        }
        if ["png", "jpg", "jpeg", "heic", "heif", "tiff", "tif", "bmp", "gif", "webp"].contains(ext) {
            return Self.clip(await ocrText(url), maxCharacters)
        }
        return nil
    }

    // MARK: - PDF

    private func pdfText(_ url: URL, max: Int) -> String? {
        #if canImport(PDFKit)
        guard let document = PDFDocument(url: url) else { return nil }
        var out = ""
        for index in 0..<document.pageCount {
            if let page = document.page(at: index)?.string { out += page + "\n" }
            if out.count >= max { break }
        }
        return out
        #else
        return nil
        #endif
    }

    // MARK: - Word / RTF / HTML / ODT via the system text importers

    private func attributedText(_ url: URL) -> String? {
        #if canImport(AppKit)
        guard let attributed = try? NSAttributedString(url: url, options: [:], documentAttributes: nil) else {
            return nil
        }
        return attributed.string
        #else
        return nil
        #endif
    }

    // MARK: - Image OCR

    private func ocrText(_ url: URL) async -> String? {
        #if canImport(Vision) && canImport(AppKit)
        guard let image = NSImage(contentsOf: url),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let text = (request.results as? [VNRecognizedTextObservation])?
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n") ?? ""
                continuation.resume(returning: text.isEmpty ? nil : text)
            }
            request.recognitionLevel = .fast
            request.usesLanguageCorrection = false
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do { try handler.perform([request]) } catch { continuation.resume(returning: nil) }
        }
        #else
        return nil
        #endif
    }

    private static func clip(_ text: String?, _ max: Int) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return String(trimmed.prefix(max))
    }
}
