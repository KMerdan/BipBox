// ConnectionsView.swift — the memory graph. Three zoom levels + search constellation.
import SwiftUI

struct ConnectionsView: View {
    @EnvironmentObject var model: WorkspaceModel
    var body: some View {
        switch model.selection {
        case .item(let id): EgoGraph(centerId: id)
        case .node(let id): EgoGraph(centerId: id)
        case .overview: OverviewGraph()
        default: OverviewGraph()
        }
    }
}

// MARK: - Breadcrumb

struct Crumbs: View {
    @EnvironmentObject var model: WorkspaceModel
    let centerId: String
    private var parts: [(id: String, name: String)] {
        var p: [(String, String)] = [("overview", "Overview")]
        if centerId != "overview" {
            if centerId.hasPrefix("cluster:") { p.append((centerId, model.meta(centerId)?.name ?? centerId)) }
            else if let it = Sample.itemByID[centerId] {
                if let cl = Sample.clusterOf(centerId) { p.append(("cluster:" + cl.id, cl.name)) }
                p.append((centerId, it.name))
            } else { p.append((centerId, model.meta(centerId)?.name ?? centerId)) }
        }
        return p
    }
    var body: some View {
        HStack(spacing: 5) {
            ForEach(Array(parts.enumerated()), id: \.offset) { i, part in
                if i > 0 { Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(BB.ink3) }
                if i < parts.count - 1 {
                    Button { tap(part.id) } label: {
                        Text(part.name).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(BB.ink2)
                            .padding(.horizontal, 7).padding(.vertical, 5)
                    }.buttonStyle(.plain)
                } else {
                    Text(part.name).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(BB.ink)
                        .padding(.horizontal, 7).padding(.vertical, 5).lineLimit(1)
                }
            }
        }
    }
    private func tap(_ id: String) {
        if id == "overview" { model.select(.overview) }
        else if id.hasPrefix("cluster:") || id.hasPrefix("ctx:") || id.hasPrefix("src:") || id.hasPrefix("col:") { model.select(.node(id)) }
        else { model.select(.item(id)) }
    }
}

// MARK: - Ego graph (item / cluster / context / source / collection center)

struct EgoGraph: View {
    @EnvironmentObject var model: WorkspaceModel
    let centerId: String
    @State private var hov: Int? = nil
    @State private var hidden: Set<String> = []

    private func cat(_ m: NodeMeta) -> String { m.type == .context ? m.kind : "\(m.type)" }
    private let catLabel = ["source": "Sources", "collection": "Collections", "cluster": "Groups",
                            "project": "Projects", "person": "People", "topic": "Topics", "item": "Files"]

    var body: some View {
        let cm = model.meta(centerId) ?? model.meta("overview")
        let all = model.neighbors(centerId).compactMap { n -> (Neighbor, NodeMeta)? in
            guard let m = model.meta(n.id) else { return nil }; return (n, m)
        }
        let cats = Array(Set(all.map { cat($0.1) }))
        let visible = Array(all.filter { !hidden.contains(cat($0.1)) }.prefix(8))

        GeometryReader { geo in
            let cx = geo.size.width / 2, cy = geo.size.height / 2
            let rx = geo.size.width * 0.32, ry = geo.size.height * 0.34
            let pts = visible.enumerated().map { i, _ -> CGPoint in
                let a = -.pi / 2 + Double(i) * 2 * .pi / Double(max(visible.count, 1))
                return CGPoint(x: cx + rx * cos(a), y: cy + ry * sin(a))
            }
            ZStack {
                Canvas { ctx, _ in
                    for (i, item) in visible.enumerated() {
                        var path = Path(); path.move(to: CGPoint(x: cx, y: cy)); path.addLine(to: pts[i])
                        ctx.stroke(path, with: .color(hov == i ? BB.accent : BB.edge),
                                   lineWidth: 0.6 + item.0.strength * 2.4)
                    }
                }
                ForEach(Array(visible.enumerated()), id: \.offset) { i, item in
                    Text(item.0.pred).font(.system(size: 10.5, weight: hov == i ? .semibold : .regular))
                        .foregroundStyle(hov == i ? BB.accent : BB.ink3)
                        .padding(.horizontal, 6).padding(.vertical, 1).background(BB.content, in: Capsule())
                        .position(x: (cx + pts[i].x) / 2, y: (cy + pts[i].y) / 2)
                        .opacity(hov == nil ? 0.92 : (hov == i ? 1 : 0.14))
                }
                if let cm { CenterCard(meta: cm).position(x: cx, y: cy) }
                ForEach(Array(visible.enumerated()), id: \.offset) { i, item in
                    GraphNode(meta: item.1, hub: Sample.itemByID[item.0.id] == nil ? model.itemCount(item.0.id) : 0)
                        { model.select(Sample.itemByID[item.0.id] != nil ? .item(item.0.id) : .node(item.0.id)) }
                        .opacity(hov != nil && hov != i ? 0.4 : 1)
                        .onHover { hov = $0 ? i : (hov == i ? nil : hov) }
                        .position(x: pts[i].x, y: pts[i].y)
                }
            }
        }
        .overlay(alignment: .topLeading) { Crumbs(centerId: centerId).padding(.leading, 20).padding(.top, 14) }
        .overlay(alignment: .topTrailing) {
            if cats.count >= 3 {
                FlowLayout(spacing: 6) {
                    ForEach(cats, id: \.self) { c in
                        Button { if hidden.contains(c) { hidden.remove(c) } else { hidden.insert(c) } } label: {
                            Text(catLabel[c] ?? c).font(.system(size: 11.5, weight: .semibold))
                                .strikethrough(hidden.contains(c))
                                .padding(.horizontal, 11).frame(height: 26)
                                .background(BB.field, in: Capsule())
                                .overlay(Capsule().strokeBorder(BB.hairStrong, lineWidth: 0.5))
                                .foregroundStyle(BB.ink2).opacity(hidden.contains(c) ? 0.45 : 1)
                        }.buttonStyle(.plain)
                    }
                }.frame(maxWidth: 320, alignment: .trailing).padding(.trailing, 16).padding(.top, 44)
            }
        }
        .background(BB.content)
    }
}

// MARK: - Overview (similarity clusters)

struct OverviewGraph: View {
    @EnvironmentObject var model: WorkspaceModel
    @State private var hov: Int? = nil
    var body: some View {
        let cl = Sample.clusters
        GeometryReader { geo in
            let cx = geo.size.width / 2, cy = geo.size.height / 2
            let rx = geo.size.width * 0.30, ry = geo.size.height * 0.30
            let pts = cl.enumerated().map { i, _ -> CGPoint in
                let a = -.pi / 2 + Double(i) * 2 * .pi / Double(cl.count)
                return CGPoint(x: cx + rx * cos(a), y: cy + ry * sin(a))
            }
            let links: [(Int, Int, Int)] = {
                var out: [(Int, Int, Int)] = []
                for i in 0..<cl.count { for j in (i+1)..<cl.count {
                    let shared = cl[i].items.filter { cl[j].items.contains($0) }.count
                    if shared > 0 { out.append((i, j, shared)) }
                } }
                return out
            }()
            ZStack {
                Canvas { ctx, _ in
                    for (a, b, shared) in links {
                        let on = hov == a || hov == b
                        var p = Path(); p.move(to: pts[a]); p.addLine(to: pts[b])
                        ctx.stroke(p, with: .color(on ? BB.accent : BB.edge), lineWidth: 0.8 + Double(shared) * 1.2)
                    }
                }
                ForEach(Array(cl.enumerated()), id: \.offset) { i, c in
                    let size = 50 + CGFloat(c.items.count) * 8
                    Button { model.select(.node("cluster:" + c.id)) } label: {
                        VStack(spacing: 9) {
                            ZStack {
                                Circle().fill(c.color.opacity(0.13))
                                Circle().strokeBorder(c.color.opacity(0.4), lineWidth: 1.5)
                                Image(systemName: "square.stack.3d.up").font(.system(size: size * 0.34)).foregroundStyle(c.color)
                            }.frame(width: size, height: size).shadow(color: .black.opacity(0.07), radius: 8, y: 3)
                            VStack(spacing: 1) {
                                Text(c.name).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(BB.ink)
                                Text("\(c.items.count) files").font(.system(size: 11)).foregroundStyle(BB.ink3)
                            }
                        }
                    }.buttonStyle(.plain)
                        .opacity(hov != nil && hov != i && !links.contains { ($0.0 == hov && $0.1 == i) || ($0.1 == hov && $0.0 == i) } ? 0.32 : 1)
                        .onHover { hov = $0 ? i : (hov == i ? nil : hov) }
                        .position(x: pts[i].x, y: pts[i].y)
                }
            }
        }
        .overlay(alignment: .topLeading) { Crumbs(centerId: "overview").padding(.leading, 20).padding(.top, 14) }
        .background(BB.content)
    }
}

// MARK: - Search constellation

struct SearchGraph: View {
    @EnvironmentObject var model: WorkspaceModel
    let hits: [SearchHit]
    @State private var hov: Int? = nil
    var body: some View {
        let files = Array(hits.prefix(10))
        GeometryReader { geo in
            let cx = geo.size.width / 2, cy = geo.size.height / 2
            let rx = geo.size.width * 0.32, ry = geo.size.height * 0.34
            let pts = files.enumerated().map { i, _ -> CGPoint in
                let a = -.pi / 2 + Double(i) * 2 * .pi / Double(max(files.count, 1))
                return CGPoint(x: cx + rx * cos(a), y: cy + ry * sin(a))
            }
            ZStack {
                Canvas { ctx, _ in
                    for i in files.indices {
                        var p = Path(); p.move(to: CGPoint(x: cx, y: cy)); p.addLine(to: pts[i])
                        ctx.stroke(p, with: .color(hov == i ? BB.accent : BB.edge), lineWidth: 0.6)
                    }
                }
                VStack(spacing: 2) {
                    HStack(spacing: 11) {
                        Image(systemName: "magnifyingglass").font(.system(size: 20)).foregroundStyle(BB.accent)
                            .frame(width: 40, height: 40).background(BB.info.opacity(0.13), in: RoundedRectangle(cornerRadius: 11))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("“\(model.query.trimmingCharacters(in: .whitespaces))”").font(.system(size: 14, weight: .bold)).foregroundStyle(BB.ink)
                            Text("\(hits.count) matches").font(.system(size: 11)).foregroundStyle(BB.ink3)
                        }
                    }.padding(12).background(BB.nodeBg, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(BB.hair, lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
                }.position(x: cx, y: cy)
                ForEach(Array(files.enumerated()), id: \.offset) { i, hit in
                    let cl = Sample.clusterOf(hit.id)
                    GraphNode(meta: NodeMeta(id: hit.id, name: hit.item.name, kind: "\(cl?.name ?? "ungrouped") group",
                                            color: cl?.color ?? BB.ink2, symbol: hit.item.symbol, type: .item), hub: 0)
                        { model.select(.item(hit.id)) }
                        .opacity(hov != nil && hov != i ? 0.4 : 1)
                        .onHover { hov = $0 ? i : (hov == i ? nil : hov) }
                        .position(x: pts[i].x, y: pts[i].y)
                }
            }
        }
        .overlay(alignment: .topLeading) {
            Text("Results for “\(model.query.trimmingCharacters(in: .whitespaces))” · \(hits.count)")
                .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(BB.ink).padding(.leading, 20).padding(.top, 14)
        }
        .background(BB.content)
    }
}

// MARK: - Graph node + center card

struct GraphNode: View {
    let meta: NodeMeta; let hub: Int; let tap: () -> Void
    var body: some View {
        Button(action: tap) {
            HStack(spacing: 9) {
                Image(systemName: meta.symbol).font(.system(size: 14)).foregroundStyle(meta.color)
                    .frame(width: 24, height: 24).background(meta.color.opacity(0.13), in: RoundedRectangle(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 0) {
                    Text(meta.name).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(BB.ink).lineLimit(1)
                    Text(hub > 1 ? "\(meta.kind) · \(hub) files" : (meta.type == .item ? "file" : meta.kind))
                        .font(.system(size: 10.5)).foregroundStyle(BB.ink3).lineLimit(1)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 9).frame(maxWidth: 190)
            .background(BB.nodeBg, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(BB.hair, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
            .overlay(alignment: .topTrailing) {
                if hub > 1 {
                    Image(systemName: "point.3.connected.trianglepath.dotted").font(.system(size: 9)).foregroundStyle(.white)
                        .frame(width: 18, height: 18).background(BB.accent, in: Circle()).offset(x: 6, y: -6)
                }
            }
        }.buttonStyle(.plain).fixedSize()
    }
}

struct CenterCard: View {
    let meta: NodeMeta
    var body: some View {
        if meta.type == .item {
            VStack(spacing: 0) {
                FileThumb(symbol: meta.symbol, w: 132, h: 80, radius: 14)
                Text(meta.name).font(.system(size: 12.5, weight: .bold)).foregroundStyle(BB.ink)
                    .lineLimit(2).multilineTextAlignment(.center).padding(.horizontal, 11).padding(.vertical, 9).frame(width: 132)
            }
            .background(BB.nodeBg, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(BB.hair, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.18), radius: 12, y: 4).fixedSize()
        } else {
            HStack(spacing: 11) {
                Image(systemName: meta.symbol).font(.system(size: 22)).foregroundStyle(meta.color)
                    .frame(width: 40, height: 40).background(meta.color.opacity(0.13), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 1) {
                    Text(meta.name).font(.system(size: 14, weight: .bold)).foregroundStyle(BB.ink)
                    Text(meta.kind.capitalized).font(.system(size: 11)).foregroundStyle(BB.ink3)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(BB.nodeBg, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(BB.hair, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.12), radius: 10, y: 3).fixedSize()
        }
    }
}
