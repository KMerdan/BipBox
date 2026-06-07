// Models.swift — UI-facing domain models, the Selection type, and sample data.
//
// These mirror the prototype. In the real app, replace the sample arrays with
// data from your services (KnowledgeGraphService, SourceStore, RetrievalService)
// and keep the same shapes — the views only depend on these structs.
import SwiftUI

// MARK: - Domain

enum ItemKind: String { case file, folder, image, pdf, sketch }

enum ItemStatus {
    case needsDecision, needsCare, filed, indexed, kept
    var label: String {
        switch self {
        case .needsDecision: return "Needs decision"
        case .needsCare: return "Needs care"
        case .filed: return "Filed"
        case .indexed: return "Indexed"
        case .kept: return "Kept"
        }
    }
    var tint: Color {
        switch self {
        case .needsDecision: return BB.warn
        case .needsCare: return BB.bad
        case .filed: return BB.good
        case .indexed: return BB.info
        case .kept: return BB.ink3
        }
    }
}

struct Source: Identifiable, Hashable {
    let id: String
    let name: String
    let color: Color
    let symbol: String
    let path: String
    let status: String
    let pill: (String, Color)
    var watching: Bool = true
    static func == (a: Source, b: Source) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

struct ContextNode: Identifiable {
    let id: String          // "ctx:maya", "src:downloads", "col:Q3 Close", "cluster:finance"
    let name: String
    let color: Color
    let symbol: String
    let kind: String        // person / project / topic / source / collection / similarity group
}

struct KItem: Identifiable {
    let id: String
    let name: String
    let path: String
    let sourceID: String
    let kind: ItemKind
    let date: String
    var status: ItemStatus
    let why: String
    let pending: Bool
    let contexts: [String]  // ctx ids
    let similar: String?
    let collection: String?
    let planMove: String?
    let planColl: String?
    var symbol: String {
        switch kind {
        case .folder: return "folder"
        case .image, .sketch: return "photo"
        default: return "doc"
        }
    }
}

struct Cluster: Identifiable {
    let id: String
    let name: String
    let color: Color
    let items: [String]
}

struct Rule: Identifiable {
    let id: String
    var name: String
    var enabled: Bool
    let when: String
    let then: String
    let review: Bool
}

struct ActivityEvent: Identifiable {
    let id: String
    let title: String
    let kind: String
    let detail: String
    let when: String
    let reversible: Bool
    let good: Bool
}

// MARK: - Selection (the single source of truth for the inspector)

enum Selection: Hashable {
    case none, overview
    case item(String)
    case node(String)       // ctx: / src: / col: / cluster:
    case rule(String)
    case activity(String)
    case search             // search-results focus uses item() for the chosen result
}

// MARK: - Navigation

enum NavSection: Hashable {
    case allItems, recents, inbox
    case source(String)
    case collection(String)
    case rules, activity
    var isLibraryLike: Bool {
        switch self {
        case .allItems, .recents, .source, .collection: return true
        default: return false
        }
    }
}

enum LibraryMode: String, CaseIterable { case gallery, connections }

// MARK: - Sample data (swap for real services)

enum Sample {
    static let sources: [Source] = [
        .init(id: "downloads", name: "Downloads", color: BB.accent, symbol: "arrow.down.circle",
              path: "~/Downloads", status: "218 items · watching for new arrivals", pill: ("Watching", BB.good)),
        .init(id: "desktop", name: "Desktop", color: BB.grape, symbol: "menubar.dock.rectangle",
              path: "~/Desktop", status: "64 items · watching", pill: ("Watching", BB.good)),
        .init(id: "documents", name: "Documents", color: BB.good, symbol: "doc.text",
              path: "~/Documents", status: "Indexing… 1,204 of 1,580 items", pill: ("Indexing", BB.info)),
        .init(id: "aurora", name: "Aurora", color: BB.warn, symbol: "folder",
              path: "~/Projects/Aurora", status: "Paused · last scanned 2 days ago", pill: ("Paused", BB.ink3), watching: false),
    ]
    static let sourceByID = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0) })

    static let contexts: [String: ContextNode] = [
        "ctx:q3close": .init(id: "ctx:q3close", name: "Q3 Earnings", color: BB.accent, symbol: "shippingbox", kind: "project"),
        "ctx:maya": .init(id: "ctx:maya", name: "Maya Chen", color: BB.grape, symbol: "person", kind: "person"),
        "ctx:finance": .init(id: "ctx:finance", name: "Finance", color: BB.good, symbol: "number", kind: "topic"),
        "ctx:aurora": .init(id: "ctx:aurora", name: "Aurora", color: BB.warn, symbol: "shippingbox", kind: "project"),
        "ctx:design": .init(id: "ctx:design", name: "Design", color: BB.good, symbol: "number", kind: "topic"),
    ]

    static let items: [KItem] = [
        .init(id: "q3", name: "Q3 Financial Report.pdf", path: "~/Downloads/Q3 Financial Report.pdf", sourceID: "downloads",
              kind: .pdf, date: "Today, 9:14 AM", status: .needsDecision, why: "Matches “Q3” and “financial”; arrived in a watched source today.",
              pending: true, contexts: ["ctx:q3close", "ctx:maya", "ctx:finance"], similar: "invoice", collection: "Q3 Close",
              planMove: "~/Documents/Finance/Q3/", planColl: "Q3 Close"),
        .init(id: "screenshot", name: "screenshot 2025-03-14.png", path: "~/Desktop/screenshot 2025-03-14.png", sourceID: "desktop",
              kind: .image, date: "Today, 8:02 AM", status: .needsDecision, why: "Ambiguous — could belong to two projects.",
              pending: true, contexts: ["ctx:aurora", "ctx:design"], similar: "roadmap", collection: "Design Inspiration",
              planMove: "~/Projects/Aurora/Shots/", planColl: "Design Inspiration"),
        .init(id: "untitled", name: "Untitled folder", path: "~/Downloads/Untitled folder", sourceID: "downloads",
              kind: .folder, date: "Yesterday", status: .needsCare, why: "Risky move — destination already has a folder with this name.",
              pending: true, contexts: ["ctx:q3close"], similar: "mockups", collection: "Q3 Close",
              planMove: "~/Documents/Inbox/", planColl: nil),
        .init(id: "contract", name: "Maya Chen — Contract.pdf", path: "~/Documents/Clients/Maya Chen/Contract.pdf", sourceID: "documents",
              kind: .pdf, date: "Mar 14", status: .filed, why: "Mentions “Maya Chen”; related to Project Q3 Earnings.",
              pending: false, contexts: ["ctx:maya", "ctx:q3close", "ctx:finance"], similar: "q3", collection: "Q3 Close", planMove: nil, planColl: nil),
        .init(id: "brand", name: "Brand Guidelines 2025.pdf", path: "~/Desktop/Brand Guidelines 2025.pdf", sourceID: "desktop",
              kind: .pdf, date: "Mar 11", status: .indexed, why: "Filename token “brand”; similar to 4 design files.",
              pending: false, contexts: ["ctx:design", "ctx:aurora"], similar: "mockups", collection: "Design Inspiration", planMove: nil, planColl: nil),
        .init(id: "mockups", name: "Aurora — Mockups", path: "~/Projects/Aurora/Mockups", sourceID: "aurora",
              kind: .folder, date: "Mar 9", status: .filed, why: "Folder kept whole; belongs to Project Aurora.",
              pending: false, contexts: ["ctx:aurora", "ctx:design"], similar: "roadmap", collection: "Design Inspiration", planMove: nil, planColl: nil),
        .init(id: "invoice", name: "invoice-1042.pdf", path: "~/Downloads/invoice-1042.pdf", sourceID: "downloads",
              kind: .pdf, date: "Mar 8", status: .indexed, why: "Similar to Q3 Financial Report; same source.",
              pending: false, contexts: ["ctx:finance", "ctx:q3close"], similar: "q3", collection: "Invoices", planMove: nil, planColl: nil),
        .init(id: "offsite", name: "team-offsite.heic", path: "~/Desktop/team-offsite.heic", sourceID: "desktop",
              kind: .image, date: "Mar 6", status: .indexed, why: "Captured 6 days ago from Desktop.",
              pending: false, contexts: ["ctx:design"], similar: "screenshot", collection: "Design Inspiration", planMove: nil, planColl: nil),
        .init(id: "roadmap", name: "roadmap.sketch", path: "~/Projects/Aurora/roadmap.sketch", sourceID: "aurora",
              kind: .sketch, date: "Mar 3", status: .filed, why: "Belongs to Project Aurora; edited recently.",
              pending: false, contexts: ["ctx:aurora", "ctx:design"], similar: "mockups", collection: "Design Inspiration", planMove: nil, planColl: nil),
    ]
    static let itemByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })

    static let clusters: [Cluster] = [
        .init(id: "finance", name: "Finance", color: BB.accent, items: ["q3", "invoice", "contract", "untitled"]),
        .init(id: "q3", name: "Q3 Earnings", color: BB.warn, items: ["q3", "invoice", "contract"]),
        .init(id: "clients", name: "Clients", color: BB.grape, items: ["contract", "q3"]),
        .init(id: "design", name: "Design", color: BB.good, items: ["brand", "mockups", "roadmap", "offsite", "screenshot"]),
    ]
    static func clusterOf(_ id: String) -> Cluster? { clusters.first { $0.items.contains(id) } }

struct CollectionDef: Identifiable { let id: String; let name: String; let items: [String] }

    static let collections: [CollectionDef] = [
        .init(id: "colQ3", name: "Q3 Close", items: ["q3", "contract", "invoice", "untitled"]),
        .init(id: "colDesign", name: "Design Inspiration", items: ["brand", "mockups", "roadmap", "offsite", "screenshot"]),
        .init(id: "colInvoices", name: "Invoices · smart", items: ["invoice", "q3"]),
    ]

    static let rules: [Rule] = [
        .init(id: "r1", name: "Financial documents", enabled: true, when: "name contains “invoice” or “financial”", then: "Move → ~/Documents/Finance, add to Q3 Close", review: true),
        .init(id: "r2", name: "Design assets stay whole", enabled: true, when: "kind is Folder and source is Aurora", then: "Remember in place, tag “design”", review: false),
        .init(id: "r3", name: "Screenshots", enabled: false, when: "name starts with “screenshot”", then: "Add to collection “Design Inspiration”", review: false),
    ]

    static let activity: [ActivityEvent] = [
        .init(id: "a1", title: "Filed Maya Chen — Contract.pdf", kind: "Move", detail: "Moved to ~/Documents/Clients/Maya Chen/ by rule “Financial documents”.", when: "Mar 14, 2:31 PM", reversible: true, good: true),
        .init(id: "a2", title: "Remembered 64 items from Desktop", kind: "Index", detail: "Initial scan of Desktop indexed 64 top-level items for search.", when: "Mar 11, 9:00 AM", reversible: false, good: false),
        .init(id: "a3", title: "Added roadmap.sketch to Aurora", kind: "Relationship", detail: "Linked roadmap.sketch to Project Aurora.", when: "Mar 9, 4:12 PM", reversible: true, good: false),
        .init(id: "a4", title: "Paused watching Aurora", kind: "Source", detail: "Watching paused for ~/Projects/Aurora.", when: "Mar 7, 10:20 AM", reversible: true, good: false),
    ]
}
