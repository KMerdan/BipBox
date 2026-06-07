// LibraryCenterView.swift — the center column: list / gallery / connections,
// plus search results. Renders the real `[IndexedItem]` set for the active section.
import SwiftUI
import BipboxCore

struct LibraryCenterView: View {
    @EnvironmentObject var model: WorkspaceModel
    let forceList: Bool      // Inbox uses a plain decision list

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
    }

    private var items: [IndexedItem] { model.items(for: model.section) }

    @ViewBuilder
    private var content: some View {
        if forceList {
            itemList(items, showWhy: true)
        } else if model.presentation == .gallery {
            gallery(items)
        } else {
            ConnectionsView()
        }
    }

    private var header: some View {
        CenterHeader(title: title, sub: sub) {
            if case .source(let id) = model.section, let s = model.sources.first(where: { $0.id == id }) {
                HStack(spacing: 7) {
                    StatusPill(text: s.enabled ? "Watching" : "Paused", tint: s.enabled ? BB.good : BB.ink3)
                    InspIcon(symbol: "arrow.clockwise") { Task { await model.onboarding.scanSource(id: id) } }
                    InspIcon(symbol: s.enabled ? "pause" : "play") {
                        Task { s.enabled ? await model.onboarding.pauseSource(id: id) : await model.onboarding.resumeSource(id: id) }
                    }
                }
            }
        }
    }

    private var title: String {
        switch model.section {
        case .allItems: "All Items"
        case .recents: "Recents"
        case .inbox: "Inbox"
        case .source(let id): model.sources.first { $0.id == id }?.displayName ?? "Folder"
        case .collection: "Collection"
        case .sources, .rules, .activity: ""
        }
    }

    private var sub: String {
        switch model.section {
        case .allItems:
            return "\(model.library.results.count) remembered · \(model.pendingCount) need a decision"
        case .recents:
            return "Most recently captured"
        case .inbox:
            return "\(model.pendingCount) \(model.pendingCount == 1 ? "thing needs" : "things need") your decision"
        case .source(let id):
            let n = items.count
            _ = id
            return "\(n) \(n == 1 ? "item" : "items")"
        case .collection:
            return "\(items.count) items"
        case .sources, .rules, .activity:
            return ""
        }
    }

    // MARK: list
    private func itemList(_ items: [IndexedItem], showWhy: Bool) -> some View {
        Group {
            if items.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(items) { ItemRow(item: $0, showWhy: showWhy) }
                    }.padding(.horizontal, 12).padding(.bottom, 14)
                }.scrollIndicators(.hidden)
            }
        }
    }

    // MARK: gallery
    private func gallery(_ items: [IndexedItem]) -> some View {
        Group {
            if items.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 16)], spacing: 16) {
                        ForEach(items) { GalleryCard(item: $0) }
                    }.padding(20)
                }.scrollIndicators(.hidden)
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if model.section == .inbox {
            VStack(spacing: 10) {
                Image(systemName: "checkmark.circle").font(.system(size: 26)).foregroundStyle(BB.good)
                Text("Nothing needs a decision").font(.system(size: 14, weight: .semibold)).foregroundStyle(BB.ink2)
            }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(.top, 60)
        } else if model.hasNoSources {
            VStack(spacing: 14) {
                Image(systemName: "folder.badge.plus").font(.system(size: 30)).foregroundStyle(BB.accent)
                Text("Start by adding a folder").font(.system(size: 16, weight: .semibold)).foregroundStyle(BB.ink)
                Text("Add Downloads, Desktop, or any folder. Bipbox indexes what's inside\nand remembers new arrivals — nothing moves unless you ask.")
                    .font(.system(size: 12.5)).foregroundStyle(BB.ink2).multilineTextAlignment(.center)
                PillButton("Add a folder", system: "plus", kind: .primary) { model.go(.sources) }
                Text("…or drag files anywhere onto this window.").font(BB.caption).foregroundStyle(BB.ink3)
            }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(.top, 50)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "tray").font(.system(size: 26)).foregroundStyle(BB.ink3)
                Text("Nothing here yet").font(.system(size: 14, weight: .semibold)).foregroundStyle(BB.ink2)
            }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(.top, 60)
        }
    }
}

struct ItemRow: View {
    @EnvironmentObject var model: WorkspaceModel
    let item: IndexedItem
    var showWhy = false
    @State private var hover = false
    var selected: Bool { if case .item(item.id) = model.selection { return true }; return false }
    var body: some View {
        Button { model.select(.item(item.id)) } label: {
            HStack(alignment: showWhy ? .top : .center, spacing: 13) {
                FileThumb(symbol: model.symbol(for: item), w: 40, h: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.displayName).font(.system(size: 14, weight: .medium)).foregroundStyle(BB.ink).lineLimit(1)
                    Text(item.currentPath).font(BB.mono).foregroundStyle(BB.ink3).lineLimit(1)
                    if showWhy {
                        Label(model.why(for: item), systemImage: "sparkles").font(.system(size: 12)).foregroundStyle(BB.ink2).lineLimit(2)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 6) {
                    Text(model.dateString(for: item)).font(BB.caption).foregroundStyle(BB.ink3)
                    if showWhy { StatusPill(text: item.status.displayLabel, tint: item.status.tint) }
                    else { DotChip(text: model.sourceName(for: item), dot: model.sourceColor(for: item)) }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 11)
            .background(selected ? BB.selFill : (hover ? BB.rowHover : .clear), in: RoundedRectangle(cornerRadius: BB.rCard))
            .contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { hover = $0 }
        .accessibilityIdentifier("item.\(item.id.uuidString)")
    }
}

struct GalleryCard: View {
    @EnvironmentObject var model: WorkspaceModel
    let item: IndexedItem
    @State private var hover = false
    var selected: Bool { if case .item(item.id) = model.selection { return true }; return false }
    var body: some View {
        Button { model.select(.item(item.id)) } label: {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    Rectangle().fill(BB.chipBg).frame(height: 120)
                        .overlay(Image(systemName: model.symbol(for: item)).font(.system(size: 34)).foregroundStyle(BB.ink3))
                    StatusPill(text: item.status.displayLabel, tint: item.status.tint).padding(9)
                }
                VStack(alignment: .leading, spacing: 7) {
                    Text(item.displayName).font(.system(size: 13, weight: .semibold)).foregroundStyle(BB.ink).lineLimit(1)
                    HStack {
                        DotChip(text: model.sourceName(for: item), dot: model.sourceColor(for: item))
                        Spacer()
                        Text(model.dateString(for: item)).font(BB.caption).foregroundStyle(BB.ink3)
                    }
                }.padding(.horizontal, 13).padding(.vertical, 11)
            }
            .background(BB.content, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? BB.accent : BB.hair, lineWidth: selected ? 2 : 0.5))
            .shadow(color: .black.opacity(hover ? 0.1 : 0.04), radius: hover ? 10 : 2, y: hover ? 4 : 1)
        }.buttonStyle(.plain).onHover { hover = $0 }
        .accessibilityIdentifier("item.\(item.id.uuidString)")
    }
}

// MARK: - Search results

struct SearchView: View {
    @EnvironmentObject var model: WorkspaceModel
    var body: some View {
        let hits = model.library.results
        VStack(spacing: 0) {
            CenterHeader(title: "Search", sub: "\(hits.count) \(hits.count == 1 ? "match" : "matches") for “\(model.query.trimmingCharacters(in: .whitespaces))”")
            if model.presentation == .connections {
                ConnectionsView()
            } else {
                results(hits)
            }
        }
    }

    private func results(_ hits: [IndexedItem]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if hits.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").font(.system(size: 22)).foregroundStyle(BB.ink3)
                        Text("No matches").font(.system(size: 14, weight: .semibold)).foregroundStyle(BB.ink2)
                    }.frame(maxWidth: .infinity).padding(.top, 60)
                } else {
                    ForEach(hits) { SearchRow(item: $0, q: model.query) }
                }
            }.padding(.horizontal, 12).padding(.bottom, 14)
        }.scrollIndicators(.hidden)
    }
}

struct SearchRow: View {
    @EnvironmentObject var model: WorkspaceModel
    let item: IndexedItem
    let q: String
    @State private var hover = false
    var selected: Bool { if case .item(item.id) = model.selection { return true }; return false }
    var body: some View {
        Button { model.select(.item(item.id)) } label: {
            HStack(spacing: 13) {
                FileThumb(symbol: model.symbol(for: item), w: 40, h: 40)
                VStack(alignment: .leading, spacing: 3) {
                    highlighted(item.displayName, q).font(.system(size: 14, weight: .medium)).foregroundStyle(BB.ink).lineLimit(1)
                    Text(item.currentPath).font(BB.mono).foregroundStyle(BB.ink3).lineLimit(1)
                    Label("matched in \(model.why(for: item))", systemImage: "sparkles")
                        .font(.system(size: 12)).foregroundStyle(BB.ink2).lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 6) {
                    Text(model.dateString(for: item)).font(BB.caption).foregroundStyle(BB.ink3)
                    DotChip(text: model.sourceName(for: item), dot: model.sourceColor(for: item))
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 11)
            .background(selected ? BB.selFill : (hover ? BB.rowHover : .clear), in: RoundedRectangle(cornerRadius: BB.rCard))
            .contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { hover = $0 }
    }
    private func highlighted(_ text: String, _ q: String) -> Text {
        let query = q.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty, let r = text.range(of: query, options: .caseInsensitive) else { return Text(text) }
        return Text(String(text[text.startIndex..<r.lowerBound]))
            + Text(String(text[r])).foregroundColor(BB.accent).bold()
            + Text(String(text[r.upperBound...]))
    }
}
