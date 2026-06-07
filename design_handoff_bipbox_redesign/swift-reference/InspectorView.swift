// InspectorView.swift — ONE inspector for every selection.
// Item · hub (context/source/collection/cluster) · overview · rule · activity.
import SwiftUI

struct InspectorView: View {
    @EnvironmentObject var model: WorkspaceModel
    var body: some View {
        VStack(spacing: 0) {
            switch model.selection {
            case .item(let id): if let it = Sample.itemByID[id] { ItemInspector(item: it) } else { EmptyInspector() }
            case .node(let id): NodeInspector(id: id)
            case .overview: OverviewInspector()
            case .rule(let id): if let r = Sample.rules.first(where: { $0.id == id }) { RuleInspector(rule: r) }
            case .activity(let id): if let e = Sample.activity.first(where: { $0.id == id }) { ActivityInspector(event: e) }
            default: EmptyInspector()
            }
        }
    }
}

// MARK: shared pieces

private func inspHead(_ trailingOnly: Bool = false) -> some View {
    HStack(spacing: 6) {
        if !trailingOnly {
            ForEach(["arrow.up.forward.square", "folder", "link"], id: \.self) { InspIcon(symbol: $0) }
        }
        Spacer()
        InspIcon(symbol: "ellipsis")
    }
    .padding(.horizontal, 14).padding(.vertical, 10)
    .overlay(alignment: .bottom) { Divider().overlay(BB.hair) }
}

struct InspIcon: View {
    let symbol: String; @State private var hover = false
    var body: some View {
        Image(systemName: symbol).font(.system(size: 14)).foregroundStyle(hover ? BB.ink : BB.ink2)
            .frame(width: 30, height: 30)
            .background(hover ? BB.rowHover : .clear, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(BB.hairStrong, lineWidth: 0.5))
            .onHover { hover = $0 }
    }
}

struct InspSection<C: View>: View {
    let title: String; @ViewBuilder let content: C
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title.uppercased()).font(BB.groupHead).tracking(0.4).foregroundStyle(BB.ink3)
            content
        }.padding(.bottom, 18)
    }
}

struct KV: View {
    let k: String; let v: String; var mono = false
    var body: some View {
        HStack { Text(k).font(.system(size: 12.5)).foregroundStyle(BB.ink2)
            Spacer(); Text(v).font(mono ? BB.mono : .system(size: 12.5, weight: .medium)).foregroundStyle(BB.ink)
                .multilineTextAlignment(.trailing).lineLimit(2) }
        .padding(.vertical, 5).overlay(alignment: .bottom) { Divider().overlay(BB.hair) }
    }
}

struct WhyBox: View {
    let lead: String; let symbol: String; let text: String; var tint = BB.accent; var bg = BB.info.opacity(0.13)
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(lead, systemImage: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(tint)
            Text(text).font(.system(size: 12.5)).foregroundStyle(BB.ink).fixedSize(horizontal: false, vertical: true)
        }.padding(13).frame(maxWidth: .infinity, alignment: .leading)
            .background(bg, in: RoundedRectangle(cornerRadius: 10))
    }
}

struct RelatedRow: View {
    let symbol: String; let title: String; let sub: String; let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 14)).foregroundStyle(BB.ink3)
                    .frame(width: 28, height: 28).background(BB.chipBg, in: RoundedRectangle(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(BB.ink).lineLimit(1)
                    Text(sub).font(.system(size: 11)).foregroundStyle(BB.ink3).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.vertical, 7)
            .background(hover ? BB.rowHover : .clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { hover = $0 }
    }
}

// MARK: item

struct ItemInspector: View {
    @EnvironmentObject var model: WorkspaceModel
    let item: KItem
    var body: some View {
        let st = model.status(of: item)
        VStack(spacing: 0) {
            inspHead()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(spacing: 12) {
                        FileThumb(symbol: item.symbol, w: 92, h: 110)
                        VStack(spacing: 2) {
                            Text(item.name).font(BB.head()).foregroundStyle(BB.ink).multilineTextAlignment(.center)
                            Text("\(item.kind.rawValue.uppercased()) · from \(Sample.sourceByID[item.sourceID]?.name ?? "")")
                                .font(BB.caption).foregroundStyle(BB.ink2)
                        }
                        StatusPill(text: st.label, tint: st.tint)
                    }.frame(maxWidth: .infinity).padding(.bottom, 18)

                    if model.isPending(item) { DecisionBlock(item: item).padding(.bottom, 18) }

                    WhyBox(lead: "Why you’re seeing this", symbol: "sparkles", text: item.why).padding(.bottom, 18)

                    InspSection(title: "Details") {
                        VStack(spacing: 0) {
                            KV(k: "Kind", v: item.kind.rawValue.capitalized)
                            KV(k: "Where", v: item.path, mono: true)
                            KV(k: "Source", v: Sample.sourceByID[item.sourceID]?.name ?? "")
                            KV(k: "Added", v: item.date)
                        }
                    }
                    InspSection(title: "In context") {
                        FlowChips(item.contexts.compactMap { Sample.contexts[$0] })
                    }
                    InspSection(title: "Related") {
                        VStack(spacing: 4) {
                            if let sim = item.similar, let s = Sample.itemByID[sim] {
                                RelatedRow(symbol: s.symbol, title: s.name, sub: "similar content · same source") { model.select(.item(sim)) }
                            }
                            if let coll = item.collection {
                                RelatedRow(symbol: "bookmark", title: coll, sub: "collection it belongs to") { model.select(.node("col:" + coll)) }
                            }
                        }
                    }
                }.padding(20)
            }.scrollIndicators(.hidden)
        }
    }
}

struct DecisionBlock: View {
    @EnvironmentObject var model: WorkspaceModel
    let item: KItem
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Assistant suggests", systemImage: "sparkles").font(.system(size: 12.5, weight: .bold)).foregroundStyle(BB.warn)
            (Text("Move to ")
             + Text(item.planMove ?? "destination").bold()
             + Text(item.planColl != nil ? " and add to " : ". ")
             + Text(item.planColl ?? "").bold()
             + Text(". Nothing moves until you approve — it stays findable either way."))
                .font(.system(size: 12.5)).foregroundStyle(BB.ink).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                PillButton("Approve", system: "checkmark", kind: .primary) { model.decide(item, "approve") }
                PillButton("Keep, don’t move") { model.decide(item, "keep") }
                PillButton("Reject", system: "xmark", kind: .danger) { model.decide(item, "reject") }
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(BB.warn.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(BB.warn.opacity(0.3), lineWidth: 0.5))
    }
}

// MARK: hub (context / source / collection / cluster)

struct NodeInspector: View {
    @EnvironmentObject var model: WorkspaceModel
    let id: String
    var body: some View {
        let m = model.meta(id)
        let members = model.neighbors(id).filter { Sample.itemByID[$0.id] != nil }
        VStack(spacing: 0) {
            inspHead(true)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let m {
                        HStack(spacing: 14) {
                            Image(systemName: m.symbol).font(.system(size: 34)).foregroundStyle(m.color)
                                .frame(width: 84, height: 84).background(m.color.opacity(0.16), in: RoundedRectangle(cornerRadius: 18))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(m.name).font(BB.head()).foregroundStyle(BB.ink)
                                Text("\(m.kind.capitalized) · \(members.count) connected items").font(BB.caption).foregroundStyle(BB.ink2)
                            }
                            Spacer()
                        }.padding(.bottom, 18)
                        WhyBox(lead: "This is a hub", symbol: "point.3.connected.trianglepath.dotted",
                               text: "\(members.count) of your items connect through \(m.name). Open one, or click another node in the graph to keep following the thread.")
                            .padding(.bottom, 18)
                        InspSection(title: "Connected items") {
                            VStack(spacing: 4) {
                                ForEach(members) { n in
                                    if let it = Sample.itemByID[n.id] {
                                        RelatedRow(symbol: it.symbol, title: it.name, sub: "\(n.pred) · \(Sample.sourceByID[it.sourceID]?.name ?? "")") { model.select(.item(n.id)) }
                                    }
                                }
                            }
                        }
                        if m.type == .source {
                            HStack(spacing: 8) {
                                PillButton("Rescan", system: "arrow.clockwise") { model.flash("Rescanning \(m.name)…") }
                                PillButton("Pause", system: "pause") { model.flash("Paused watching") }
                            }
                        }
                    }
                }.padding(20)
            }.scrollIndicators(.hidden)
        }
    }
}

// MARK: overview / rule / activity / empty

struct OverviewInspector: View {
    @EnvironmentObject var model: WorkspaceModel
    var body: some View {
        VStack(spacing: 0) {
            inspHead(true)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    InspSection(title: "Overview") {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Your library, by similarity").font(BB.head()).foregroundStyle(BB.ink)
                            Text("\(Sample.items.count) files grouped into \(Sample.clusters.count) clusters. Pick a cluster to zoom in, then a file — you never see every file at once.")
                                .font(BB.caption).foregroundStyle(BB.ink2)
                        }
                    }
                    WhyBox(lead: "A map, not a hairball", symbol: "point.3.connected.trianglepath.dotted",
                           text: "At scale Bipbox groups files by what they’re about. Searching or choosing a folder/collection zooms the map straight to that neighborhood.").padding(.bottom, 18)
                    InspSection(title: "Clusters") {
                        VStack(spacing: 4) {
                            ForEach(Sample.clusters) { cl in
                                RelatedRow(symbol: "square.stack.3d.up", title: cl.name, sub: "\(cl.items.count) files") { model.select(.node("cluster:" + cl.id)) }
                            }
                        }
                    }
                }.padding(20)
            }.scrollIndicators(.hidden)
        }
    }
}

struct RuleInspector: View {
    @EnvironmentObject var model: WorkspaceModel
    let rule: Rule
    var body: some View {
        VStack(spacing: 0) {
            inspHead(true)
            ScrollView { VStack(alignment: .leading, spacing: 0) {
                InspSection(title: "Rule") { Text(rule.name).font(BB.head()).foregroundStyle(BB.ink) }
                InspSection(title: "When") { Text(rule.when).font(BB.mono).foregroundStyle(BB.ink2) }
                InspSection(title: "Then") { Text(rule.then).font(.system(size: 12.5)).foregroundStyle(BB.ink) }
                InspSection(title: "") {
                    VStack(spacing: 0) {
                        KV(k: "Ask before doing it", v: rule.review ? "Yes" : "No")
                        KV(k: "Status", v: rule.enabled ? "Enabled" : "Paused")
                    }
                }
                HStack(spacing: 8) {
                    PillButton("Test on Library", kind: .primary) { model.flash("Simulated — 6 items would match") }
                    PillButton("Edit") {}
                }
            }.padding(20) }.scrollIndicators(.hidden)
        }
    }
}

struct ActivityInspector: View {
    @EnvironmentObject var model: WorkspaceModel
    let event: ActivityEvent
    var body: some View {
        VStack(spacing: 0) {
            inspHead(true)
            ScrollView { VStack(alignment: .leading, spacing: 0) {
                InspSection(title: event.kind) { Text(event.title).font(BB.head()).foregroundStyle(BB.ink) }
                InspSection(title: "") { Text(event.detail).font(.system(size: 12.5)).foregroundStyle(BB.ink2).fixedSize(horizontal: false, vertical: true) }
                InspSection(title: "") { VStack(spacing: 0) {
                    KV(k: "When", v: event.when)
                    KV(k: "Reversible", v: event.reversible ? "Yes" : "No")
                } }
                if event.reversible { PillButton("Undo this", system: "arrow.uturn.backward") { model.flash("Reverted — back to previous state") } }
            }.padding(20) }.scrollIndicators(.hidden)
        }
    }
}

struct EmptyInspector: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.stack.3d.up").font(.system(size: 22)).foregroundStyle(BB.ink3)
                .frame(width: 54, height: 54).overlay(Circle().strokeBorder(BB.hairStrong, style: StrokeStyle(lineWidth: 1.5, dash: [4])))
            Text("Select an item").font(.system(size: 13.5, weight: .semibold)).foregroundStyle(BB.ink2)
            Text("Its details, connections and history show here.").font(BB.caption).foregroundStyle(BB.ink3)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(30)
    }
}
