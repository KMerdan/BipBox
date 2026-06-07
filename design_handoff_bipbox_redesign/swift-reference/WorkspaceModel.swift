// WorkspaceModel.swift — single observable state + graph/search helpers.
import SwiftUI

enum NodeType { case item, source, context, collection, cluster }

struct NodeMeta {
    let id: String
    let name: String
    let kind: String
    let color: Color
    let symbol: String
    let type: NodeType
}

struct Neighbor: Identifiable { let id: String; let pred: String; let strength: Double }

struct SearchHit: Identifiable { let id: String; let item: KItem; let score: Int; let why: [String] }

@MainActor
final class WorkspaceModel: ObservableObject {
    @Published var section: NavSection = .allItems
    @Published var mode: LibraryMode = .connections          // Connections is the default
    @Published var selection: Selection = .overview
    @Published var query: String = ""
    @Published var resolved: [String: String] = [:]          // itemID -> approve/keep/reject
    @Published var toast: String?

    private let collByName = Dictionary(uniqueKeysWithValues:
        Sample.collections.map { ($0.name, $0.items) })

    // MARK: status / pending
    func status(of item: KItem) -> ItemStatus {
        if item.pending, let r = resolved[item.id] { return r == "approve" ? .filed : .kept }
        return item.status
    }
    func isPending(_ item: KItem) -> Bool { item.pending && resolved[item.id] == nil }
    var pendingItems: [KItem] { Sample.items.filter(isPending) }
    var pendingCount: Int { pendingItems.count }

    // MARK: items for a section
    func items(for s: NavSection) -> [KItem] {
        switch s {
        case .inbox: return pendingItems
        case .source(let id): return Sample.items.filter { $0.sourceID == id }
        case .collection(let cid):
            let ids = Sample.collections.first { $0.id == cid }?.items ?? []
            return ids.compactMap { Sample.itemByID[$0] }
        case .recents: return Array(Sample.items.prefix(6))
        default: return Sample.items
        }
    }
    var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    // MARK: navigation
    func go(_ s: NavSection) {
        section = s
        switch s {
        case .rules: selection = .rule(Sample.rules[0].id)
        case .activity: selection = .activity(Sample.activity[0].id)
        case .inbox: selection = pendingItems.first.map { .item($0.id) } ?? .none
        case .source(let id): selection = mode == .gallery
            ? (items(for: s).first.map { .item($0.id) } ?? .none) : .node("src:" + id)
        case .collection(let cid):
            let name = Sample.collections.first { $0.id == cid }?.name ?? ""
            selection = mode == .gallery ? (items(for: s).first.map { .item($0.id) } ?? .none) : .node("col:" + name)
        default:
            selection = mode == .gallery ? (items(for: s).first.map { .item($0.id) } ?? .none) : .overview
        }
    }
    func setMode(_ m: LibraryMode) {
        mode = m
        if m == .gallery, case .node = selection { selection = items(for: section).first.map { .item($0.id) } ?? .none }
        if m == .gallery, case .overview = selection { selection = items(for: section).first.map { .item($0.id) } ?? .none }
    }
    func select(_ s: Selection) { selection = s }

    func decide(_ item: KItem, _ kind: String) {
        resolved[item.id] = kind
        switch kind {
        case "approve": flash("Filed to \(item.planMove ?? "destination") · Undo")
        case "keep": flash("Kept in place — still findable")
        default: flash("Rejected — left where it was")
        }
        if case .inbox = section {
            selection = Sample.items.first { $0.pending && resolved[$0.id] == nil }.map { .item($0.id) } ?? .none
        }
    }
    func flash(_ msg: String) {
        toast = msg
        Task { try? await Task.sleep(nanoseconds: 2_600_000_000); if toast == msg { toast = nil } }
    }

    // MARK: graph model
    func meta(_ id: String) -> NodeMeta? {
        if id.hasPrefix("ctx:"), let c = Sample.contexts[id] {
            return .init(id: id, name: c.name, kind: c.kind, color: c.color, symbol: c.symbol, type: .context)
        }
        if id.hasPrefix("src:"), let s = Sample.sourceByID[String(id.dropFirst(4))] {
            return .init(id: id, name: s.name, kind: "source", color: s.color, symbol: s.symbol, type: .source)
        }
        if id.hasPrefix("col:") {
            return .init(id: id, name: String(id.dropFirst(4)), kind: "collection", color: BB.warn, symbol: "bookmark", type: .collection)
        }
        if id.hasPrefix("cluster:"), let cl = Sample.clusters.first(where: { $0.id == String(id.dropFirst(8)) }) {
            return .init(id: id, name: cl.name, kind: "similarity group", color: cl.color, symbol: "square.stack.3d.up", type: .cluster)
        }
        if let it = Sample.itemByID[id] {
            return .init(id: id, name: it.name, kind: it.kind.rawValue, color: BB.ink2, symbol: it.symbol, type: .item)
        }
        return nil
    }

    func neighbors(_ id: String) -> [Neighbor] {
        var out: [Neighbor] = []
        if let it = Sample.itemByID[id] {
            out.append(.init(id: "src:" + it.sourceID, pred: "came from", strength: 0.55))
            for c in it.contexts { if let ctx = Sample.contexts[c] { out.append(.init(id: c, pred: pred(for: ctx.kind), strength: 0.9)) } }
            if let sim = it.similar, Sample.itemByID[sim] != nil { out.append(.init(id: sim, pred: "similar to", strength: 0.45)) }
            if let coll = it.collection { out.append(.init(id: "col:" + coll, pred: "in collection", strength: 0.6)) }
        } else if id.hasPrefix("ctx:") {
            for it in Sample.items where it.contexts.contains(id) {
                out.append(.init(id: it.id, pred: pred(for: Sample.contexts[id]?.kind ?? ""), strength: 0.85))
            }
        } else if id.hasPrefix("src:") {
            let k = String(id.dropFirst(4))
            for it in Sample.items where it.sourceID == k { out.append(.init(id: it.id, pred: "captured here", strength: 0.55)) }
        } else if id.hasPrefix("col:") {
            let name = String(id.dropFirst(4))
            let ids = collByName[name] ?? Sample.items.filter { $0.collection == name }.map(\.id)
            for iid in ids where Sample.itemByID[iid] != nil { out.append(.init(id: iid, pred: "in collection", strength: 0.6)) }
        } else if id.hasPrefix("cluster:") {
            let cl = Sample.clusters.first { $0.id == String(id.dropFirst(8)) }
            for iid in cl?.items ?? [] where Sample.itemByID[iid] != nil { out.append(.init(id: iid, pred: "similar group", strength: 0.7)) }
        }
        var seen = Set<String>()
        return out.filter { seen.insert($0.id).inserted && meta($0.id) != nil }
    }
    func itemCount(_ id: String) -> Int { neighbors(id).filter { Sample.itemByID[$0.id] != nil }.count }
    private func pred(for kind: String) -> String {
        switch kind {
        case "person": return "mentions"
        case "topic": return "about"
        default: return "belongs to"
        }
    }

    // MARK: search
    func search() -> [SearchHit] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        var hits: [SearchHit] = []
        for it in Sample.items {
            let name = it.name.lowercased(), path = it.path.lowercased()
            var score = 0; var why: [String] = []
            if name.hasPrefix(q) { score += 100; why.append("name") }
            else if name.contains(q) { score += 70; why.append("name") }
            if path.contains(q) && !name.contains(q) { score += 30; why.append("path") }
            if (Sample.sourceByID[it.sourceID]?.name.lowercased().contains(q) ?? false) { score += 22; why.append("source") }
            for c in it.contexts { if let ctx = Sample.contexts[c], ctx.name.lowercased().contains(q) { score += 26; why.append(ctx.kind) } }
            if let cl = Sample.clusterOf(it.id), cl.name.lowercased().contains(q) { score += 16 }
            if it.kind.rawValue.contains(q) { score += 12; why.append("type") }
            if score > 0 {
                var seenWhy = Set<String>()
                let uniqueWhy = why.filter { seenWhy.insert($0).inserted }
                hits.append(.init(id: it.id, item: it, score: score, why: uniqueWhy))
            }
        }
        return hits.sorted { $0.score > $1.score }
    }
}
