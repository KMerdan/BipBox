import CryptoKit
import Foundation

/// Deterministic, stable IDs derived from paths — the single source of truth so
/// the scanner (which writes them) and the UI (which resolves them) agree.
public enum KnowledgeIDs {
    /// A stable UUIDv5-ish id from an input string (SHA-256 → 16 bytes).
    public static func stable(_ input: String) -> UUID {
        let digest = SHA256.hash(data: Data(input.utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    public static func knowledgeItem(forPath path: String) -> UUID {
        stable("knowledge-item:\(path)")
    }

    public static func folderContext(for url: URL) -> UUID {
        stable("folder-context:\(url.standardizedFileURL.path)")
    }
}
