// Selection.swift — the single typed selection that drives the shared inspector,
// plus the Library center presentation toggle. Ports the blueprint's `Selection`
// and `LibraryMode` (renamed `LibraryPresentation` to avoid clashing with the
// existing search `LibraryMode`).
import Foundation
import SwiftUI
import BipboxCore

/// One selection type the whole workspace shares. Every list sets it; the shared
/// `InspectorView` reads it. IDs are real `UUID`s (clusters have no backing id yet).
public enum Selection: Hashable, Sendable {
    case none
    case overview                  // graph overview level (no item selected)
    case item(UUID)                // IndexedItem / KnowledgeItem
    case source(UUID)              // SourceRecord (watched folder hub)
    case context(UUID)             // ContextNode (person / project / topic)
    case collection(UUID)          // KnowledgeCollection
    case cluster(String)           // similarity group (Tier-0: tag/topic key)
    case rule(UUID)                // RuleDocument / WorkflowBranch
    case activity(UUID)            // ActivityEvent
}

/// Center presentation when a Library-like section is active.
public enum LibraryPresentation: String, CaseIterable, Identifiable, Sendable {
    case gallery
    case connections

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .gallery: "Gallery"
        case .connections: "Connections"
        }
    }
}

// MARK: - Status display (user-facing redesign naming + tokens)

public extension IndexedItemStatus {
    /// User-facing label per the redesign naming guide.
    var displayLabel: String {
        switch self {
        case .organized: "Filed"
        case .needsReview: "Needs a decision"
        case .indexedOnly: "Remembered"
        case .missing: "Missing"
        case .failed: "Failed"
        }
    }

    /// Status tint from the BB palette.
    var tint: Color {
        switch self {
        case .organized: BB.good
        case .needsReview: BB.warn
        case .indexedOnly: BB.info
        case .missing: BB.ink3
        case .failed: BB.bad
        }
    }
}
