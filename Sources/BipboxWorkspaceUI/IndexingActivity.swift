import Foundation

/// The one long-running-work indicator: a first scan of a big folder, or the
/// post-provisioning embedding backfill. Total is always known up front (the
/// descender enumerates before capturing; backfill counts missing vectors), so
/// the status line can show "n of m" plus a rate-based ETA.
public struct IndexingActivity: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case scanning(sourceName: String)
        case embedding
    }

    public var kind: Kind
    public var completed: Int
    public var total: Int
    public var startedAt: Date

    public init(kind: Kind, completed: Int, total: Int, startedAt: Date) {
        self.kind = kind
        self.completed = completed
        self.total = total
        self.startedAt = startedAt
    }

    /// "Indexing Downloads · 1,240 of 7,600 · ~4 min left"
    public func statusLine(now: Date = Date()) -> String {
        let verb: String
        switch kind {
        case .scanning(let sourceName): verb = "Indexing \(sourceName)"
        case .embedding: verb = "Embedding for semantic search"
        }
        var parts = [verb, "\(completed.formatted()) of \(total.formatted())"]
        if let eta = etaDescription(now: now) {
            parts.append(eta)
        }
        return parts.joined(separator: " · ")
    }

    /// Rate-based remaining time. Nil until there is enough signal to be honest
    /// (a few items done and a couple of seconds elapsed).
    public func etaDescription(now: Date = Date()) -> String? {
        let elapsed = now.timeIntervalSince(startedAt)
        guard completed >= 5, elapsed >= 2, completed < total else { return nil }
        let rate = Double(completed) / elapsed
        guard rate > 0 else { return nil }
        let remaining = Double(total - completed) / rate
        switch remaining {
        case ..<60: return "less than a minute left"
        case ..<5400: return "~\(Int((remaining / 60).rounded())) min left"
        default:
            let hours = Int(remaining / 3600)
            let minutes = Int((remaining.truncatingRemainder(dividingBy: 3600)) / 60)
            return minutes > 0 ? "~\(hours) hr \(minutes) min left" : "~\(hours) hr left"
        }
    }
}
