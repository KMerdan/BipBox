// LibraryView.swift — list / gallery / connections, and the search results.
import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var model: WorkspaceModel
    let forceList: Bool      // Inbox uses a plain list

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(BB.hair).opacity(0)   // spacing only
            content
        }
    }

    private var content: some View {
        Group {
            if forceList { itemList(model.items(for: model.section), showWhy: true) }
            else if model.mode == .gallery { gallery(model.items(for: model.section)) }
            else { ConnectionsView() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        CenterHeader(title: title, sub: sub) {
            if case .source(let id) = model.section, let s = Sample.sourceByID[id] {
                HStack(spacing: 7) {
                    StatusPill(text: s.pill.0, tint: s.pill.1)
                    InspIcon(symbol: "arrow.clockwise")
                    InspIcon(symbol: s.watching ? "pause" : "play")
                }
            }
        }
    }
    private var title: String {
        switch model.section {
        case .allItems: return "All Items"
        case .recents: return "Recents"
        case .inbox: return "Inbox"
        case .source(let id): return Sample.sourceByID[id]?.name ?? "Folder"
        case .collection(let cid): return Sample.collections.first { $0.id == cid }?.name ?? "Collection"
        default: return ""
        }
    }
    private var sub: String {
        switch model.section {
        case .allItems: return "428 remembered · 3 need a decision"
        case .recents: return "Captured in the last 14 days"
        case .inbox: return "\(model.pendingCount) \(model.pendingCount == 1 ? "thing needs" : "things need") your decision"
        case .source(let id): return Sample.sourceByID[id]?.status ?? ""
        case .collection: return "\(model.items(for: model.section).count) items"
        default: return ""
        }
    }

    // MARK: list
    private func itemList(_ items: [KItem], showWhy: Bool) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(items) { it in ItemRow(item: it, showWhy: showWhy) }
            }.padding(.horizontal, 12).padding(.bottom, 14)
        }.scrollIndicators(.hidden)
    }

    // MARK: gallery
    private func gallery(_ items: [KItem]) -> some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 16)], spacing: 16) {
                ForEach(items) { it in GalleryCard(item: it) }
            }.padding(20)
        }.scrollIndicators(.hidden)
    }
}

struct ItemRow: View {
    @EnvironmentObject var model: WorkspaceModel
    let item: KItem; var showWhy = false
    @State private var hover = false
    var selected: Bool { if case .item(item.id) = model.selection { return true }; return false }
    var body: some View {
        Button { model.select(.item(item.id)) } label: {
            HStack(alignment: showWhy ? .top : .center, spacing: 13) {
                FileThumb(symbol: item.symbol, w: 40, h: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name).font(.system(size: 14, weight: .medium)).foregroundStyle(BB.ink).lineLimit(1)
                    Text(item.path).font(BB.mono).foregroundStyle(BB.ink3).lineLimit(1)
                    if showWhy {
                        Label(item.why, systemImage: "sparkles").font(.system(size: 12)).foregroundStyle(BB.ink2).lineLimit(2)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 6) {
                    Text(item.date).font(BB.caption).foregroundStyle(BB.ink3)
                    if showWhy { StatusPill(text: model.status(of: item).label, tint: model.status(of: item).tint) }
                    else { DotChip(text: Sample.sourceByID[item.sourceID]?.name ?? "", dot: Sample.sourceByID[item.sourceID]?.color ?? .gray) }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 11)
            .background(selected ? BB.selFill : (hover ? BB.rowHover : .clear), in: RoundedRectangle(cornerRadius: BB.rCard))
            .contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { hover = $0 }
    }
}

struct GalleryCard: View {
    @EnvironmentObject var model: WorkspaceModel
    let item: KItem
    @State private var hover = false
    var selected: Bool { if case .item(item.id) = model.selection { return true }; return false }
    var body: some View {
        Button { model.select(.item(item.id)) } label: {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    Rectangle().fill(BB.chipBg).frame(height: 120)
                        .overlay(Image(systemName: item.symbol).font(.system(size: 34)).foregroundStyle(BB.ink3))
                    StatusPill(text: model.status(of: item).label, tint: model.status(of: item).tint).padding(9)
                }
                VStack(alignment: .leading, spacing: 7) {
                    Text(item.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(BB.ink).lineLimit(1)
                    HStack {
                        DotChip(text: Sample.sourceByID[item.sourceID]?.name ?? "", dot: Sample.sourceByID[item.sourceID]?.color ?? .gray)
                        Spacer()
                        Text(item.date).font(BB.caption).foregroundStyle(BB.ink3)
                    }
                }.padding(.horizontal, 13).padding(.vertical, 11)
            }
            .background(BB.content, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? BB.accent : BB.hair, lineWidth: selected ? 2 : 0.5))
            .shadow(color: .black.opacity(hover ? 0.1 : 0.04), radius: hover ? 10 : 2, y: hover ? 4 : 1)
        }.buttonStyle(.plain).onHover { hover = $0 }
    }
}

// MARK: - Search

struct SearchView: View {
    @EnvironmentObject var model: WorkspaceModel
    var body: some View {
        let hits = model.search()
        VStack(spacing: 0) {
            CenterHeader(title: "Search", sub: "\(hits.count) \(hits.count == 1 ? "match" : "matches") for “\(model.query.trimmingCharacters(in: .whitespaces))”")
            if model.mode == .connections { SearchGraph(hits: hits) }
            else { results(hits) }
        }
    }
    private func results(_ hits: [SearchHit]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                let strong = hits.filter { $0.score >= 70 }, rest = hits.filter { $0.score < 70 }
                if !strong.isEmpty { groupLabel("Best matches"); ForEach(strong) { hit in SearchRow(hit: hit, q: model.query) } }
                if !rest.isEmpty { groupLabel("Also related"); ForEach(rest) { hit in SearchRow(hit: hit, q: model.query) } }
                if hits.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").font(.system(size: 22)).foregroundStyle(BB.ink3)
                        Text("No matches").font(.system(size: 14, weight: .semibold)).foregroundStyle(BB.ink2)
                    }.frame(maxWidth: .infinity).padding(.top, 60)
                }
            }.padding(.horizontal, 12).padding(.bottom, 14)
        }.scrollIndicators(.hidden)
    }
    private func groupLabel(_ t: String) -> some View {
        Text(t.uppercased()).font(BB.groupHead).tracking(0.4).foregroundStyle(BB.ink3).padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 6)
    }
}

struct SearchRow: View {
    @EnvironmentObject var model: WorkspaceModel
    let hit: SearchHit; let q: String
    @State private var hover = false
    var selected: Bool { if case .item(hit.id) = model.selection { return true }; return false }
    var body: some View {
        let it = hit.item; let cl = Sample.clusterOf(it.id)
        Button { model.select(.item(it.id)) } label: {
            HStack(spacing: 13) {
                FileThumb(symbol: it.symbol, w: 40, h: 40)
                VStack(alignment: .leading, spacing: 3) {
                    highlighted(it.name, q).font(.system(size: 14, weight: .medium)).foregroundStyle(BB.ink).lineLimit(1)
                    Text(it.path).font(BB.mono).foregroundStyle(BB.ink3).lineLimit(1)
                    Label("matched in \(hit.why.joined(separator: " · "))\(cl != nil ? " · \(cl!.name) group" : "")", systemImage: "sparkles")
                        .font(.system(size: 12)).foregroundStyle(BB.ink2).lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 6) {
                    Text(it.date).font(BB.caption).foregroundStyle(BB.ink3)
                    DotChip(text: Sample.sourceByID[it.sourceID]?.name ?? "", dot: Sample.sourceByID[it.sourceID]?.color ?? .gray)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 11)
            .background(selected ? BB.selFill : (hover ? BB.rowHover : .clear), in: RoundedRectangle(cornerRadius: BB.rCard))
            .contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { hover = $0 }
    }
    private func highlighted(_ text: String, _ q: String) -> Text {
        guard let r = text.range(of: q, options: .caseInsensitive) else { return Text(text) }
        return Text(String(text[text.startIndex..<r.lowerBound]))
            + Text(String(text[r])).foregroundColor(BB.accent).bold()
            + Text(String(text[r.upperBound...]))
    }
}
