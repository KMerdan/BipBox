// ConnectionsView.swift — the memory graph: semantic zoom (Overview clusters →
// Cluster/hub → File ego) + search constellation. Native Canvas + Layout, backed
// by the model's graph adapters over real KnowledgeGraph / relatedness data.
import SwiftUI
import BipboxCore

struct ConnectionsView: View {
    @EnvironmentObject var model: WorkspaceModel
    var body: some View {
        Group {
            if model.isSearching {
                SearchGraph()
            } else {
                switch model.selection {
                case .item, .source, .cluster, .collection, .context:
                    EgoGraph(center: model.selection)
                default:
                    OverviewGraph()
                }
            }
        }
    }
}

// MARK: - Breadcrumb

struct Crumbs: View {
    @EnvironmentObject var model: WorkspaceModel
    let center: Selection

    private var parts: [(sel: Selection, name: String)] {
        var p: [(Selection, String)] = [(.overview, "Overview")]
        switch center {
        case .item(let id):
            if let cl = model.clusterOf(id) { p.append((.cluster(cl.id), cl.name)) }
            if let it = model.item(id) { p.append((.item(id), it.displayName)) }
        case .cluster, .source, .collection, .context:
            if let m = model.nodeMeta(center) { p.append((center, m.name)) }
        default:
            break
        }
        return p
    }

    var body: some View {
        HStack(spacing: 5) {
            ForEach(Array(parts.enumerated()), id: \.offset) { i, part in
                if i > 0 { Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(BB.ink3) }
                if i < parts.count - 1 {
                    Button { model.select(part.sel) } label: {
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
}

// MARK: - Ego graph (item / cluster / source / collection / context center)

/// Polar layout: center point + a ring of neighbor points.
struct RadialLayout {
    let cx: CGFloat, cy: CGFloat
    let pts: [CGPoint]
    init(size: CGSize, count: Int, rxFactor: CGFloat = 0.32, ryFactor: CGFloat = 0.34) {
        let centerX = size.width / 2
        let centerY = size.height / 2
        let rx = size.width * rxFactor
        let ry = size.height * ryFactor
        let n = max(count, 1)
        var points: [CGPoint] = []
        points.reserveCapacity(max(count, 0))
        for i in 0..<max(count, 0) {
            let angle: Double = -.pi / 2 + (Double(i) * 2 * .pi / Double(n))
            let x = centerX + rx * CGFloat(cos(angle))
            let y = centerY + ry * CGFloat(sin(angle))
            points.append(CGPoint(x: x, y: y))
        }
        self.cx = centerX
        self.cy = centerY
        self.pts = points
    }
}

struct EgoGraph: View {
    @EnvironmentObject var model: WorkspaceModel
    let center: Selection
    @State private var hov: Int? = nil
    @State private var hidden: Set<String> = []
    @State private var loaded: LoadedGraph?

    var body: some View {
        content
            // Reload whenever the centered node changes — keyed loads prevent the
            // stale-neighbor bug (a node showing the previous node's connections).
            .task(id: center) {
                loaded = nil
                loaded = await model.loadGraph(center: center)
            }
            .overlay(alignment: .topLeading) { Crumbs(center: center).padding(.leading, 20).padding(.top, 14) }
            .background(BB.content)
    }

    @ViewBuilder
    private var content: some View {
        if let loaded {
            graphBody(loaded)
        } else {
            VStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Loading connections…").font(BB.caption).foregroundStyle(BB.ink3)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func graphBody(_ loaded: LoadedGraph) -> some View {
        let cm = loaded.center
        let all = loaded.neighbors
        let cats = Array(Set(all.map(\.category))).sorted()
        let visible = Array(all.filter { !hidden.contains($0.category) }.prefix(8))

        return GeometryReader { geo in
            let layout = RadialLayout(size: geo.size, count: visible.count)
            ZStack {
                edges(layout, visible)
                ForEach(Array(visible.enumerated()), id: \.offset) { i, n in
                    label(n, at: midpoint(layout, i), active: hov == i)
                }
                if let cm { CenterCard(center: cm).position(x: layout.cx, y: layout.cy) }
                ForEach(Array(visible.enumerated()), id: \.offset) { i, n in
                    node(n, index: i, at: layout.pts[i])
                }
                if visible.isEmpty {
                    VStack(spacing: 6) {
                        Text(cm == nil ? "Nothing to show here" : "No connections yet")
                            .font(.system(size: 13.5, weight: .semibold)).foregroundStyle(BB.ink2)
                        Text(cm == nil ? "This node is no longer in your library." : "This item isn't linked to anything else yet.")
                            .font(BB.caption).foregroundStyle(BB.ink3)
                    }.position(x: layout.cx, y: layout.cy + (cm == nil ? 0 : 96))
                }
            }
        }
        .overlay(alignment: .topTrailing) { filterChips(cats) }
    }

    private func edges(_ layout: RadialLayout, _ visible: [GraphNeighbor]) -> some View {
        Canvas { ctx, _ in
            for i in visible.indices {
                var path = Path()
                path.move(to: CGPoint(x: layout.cx, y: layout.cy))
                path.addLine(to: layout.pts[i])
                ctx.stroke(path, with: .color(hov == i ? BB.accent : BB.edge),
                           lineWidth: 0.6 + visible[i].strength * 2.4)
            }
        }
    }

    private func midpoint(_ layout: RadialLayout, _ i: Int) -> CGPoint {
        CGPoint(x: (layout.cx + layout.pts[i].x) / 2, y: (layout.cy + layout.pts[i].y) / 2)
    }

    private func label(_ n: GraphNeighbor, at p: CGPoint, active: Bool) -> some View {
        Text(n.pred).font(.system(size: 10.5, weight: active ? .semibold : .regular))
            .foregroundStyle(active ? BB.accent : BB.ink3)
            .padding(.horizontal, 6).padding(.vertical, 1).background(BB.content, in: Capsule())
            .position(x: p.x, y: p.y)
            .opacity(hov == nil ? 0.92 : (active ? 1 : 0.14))
    }

    private func node(_ n: GraphNeighbor, index i: Int, at p: CGPoint) -> some View {
        GraphNode(neighbor: n) { model.select(n.selection) }
            .opacity(hov != nil && hov != i ? 0.4 : 1)
            .onHover { hov = $0 ? i : (hov == i ? nil : hov) }
            .position(x: p.x, y: p.y)
    }

    @ViewBuilder
    private func filterChips(_ cats: [String]) -> some View {
        if cats.count >= 3 {
            FlowLayout(spacing: 6) {
                ForEach(cats, id: \.self) { c in
                    Button { toggle(c) } label: {
                        Text(c).font(.system(size: 11.5, weight: .semibold))
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

    private func toggle(_ c: String) {
        if hidden.contains(c) { hidden.remove(c) } else { hidden.insert(c) }
    }
}

// MARK: - Overview (similarity clusters)

struct OverviewGraph: View {
    @EnvironmentObject var model: WorkspaceModel
    @State private var hov: Int? = nil
    var body: some View {
        let cl = model.clusters
        let links = model.clusterLinks()
        GeometryReader { geo in
            let layout = RadialLayout(size: geo.size, count: cl.count, rxFactor: 0.30, ryFactor: 0.30)
            ZStack {
                clusterEdges(layout, links)
                ForEach(Array(cl.enumerated()), id: \.offset) { i, c in
                    clusterNode(c, index: i, at: layout.pts[i], links: links)
                }
                if cl.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "point.3.connected.trianglepath.dotted").font(.system(size: 28)).foregroundStyle(BB.ink3)
                        Text("No clusters yet").font(.system(size: 14, weight: .semibold)).foregroundStyle(BB.ink2)
                    }.position(x: layout.cx, y: layout.cy)
                }
            }
        }
        .overlay(alignment: .topLeading) { Crumbs(center: .overview).padding(.leading, 20).padding(.top, 14) }
        .background(BB.content)
    }

    private func clusterEdges(_ layout: RadialLayout, _ links: [(Int, Int, Int)]) -> some View {
        Canvas { ctx, _ in
            for (a, b, shared) in links {
                let on = hov == a || hov == b
                var p = Path(); p.move(to: layout.pts[a]); p.addLine(to: layout.pts[b])
                ctx.stroke(p, with: .color(on ? BB.accent : BB.edge), lineWidth: 0.8 + Double(shared) * 1.2)
            }
        }
    }

    private func clusterNode(_ c: LibraryCluster, index i: Int, at p: CGPoint, links: [(Int, Int, Int)]) -> some View {
        let size = 50 + CGFloat(c.itemIDs.count) * 8
        let dimmed = hov != nil && hov != i && !links.contains { ($0.0 == hov && $0.1 == i) || ($0.1 == hov && $0.0 == i) }
        return Button { model.select(.cluster(c.id)) } label: {
            VStack(spacing: 9) {
                ZStack {
                    Circle().fill(c.color.opacity(0.13))
                    Circle().strokeBorder(c.color.opacity(0.4), lineWidth: 1.5)
                    Image(systemName: "square.stack.3d.up").font(.system(size: size * 0.34)).foregroundStyle(c.color)
                }.frame(width: size, height: size).shadow(color: .black.opacity(0.07), radius: 8, y: 3)
                VStack(spacing: 1) {
                    Text(c.name).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(BB.ink)
                    Text("\(c.itemIDs.count) files").font(.system(size: 11)).foregroundStyle(BB.ink3)
                }
            }
        }.buttonStyle(.plain)
            .opacity(dimmed ? 0.32 : 1)
            .onHover { hov = $0 ? i : (hov == i ? nil : hov) }
            .position(x: p.x, y: p.y)
    }
}

// MARK: - Search constellation

struct SearchGraph: View {
    @EnvironmentObject var model: WorkspaceModel
    @State private var hov: Int? = nil
    var body: some View {
        let files = Array(model.library.results.prefix(10))
        GeometryReader { geo in
            let layout = RadialLayout(size: geo.size, count: files.count)
            ZStack {
                searchEdges(layout, count: files.count)
                centerCard.position(x: layout.cx, y: layout.cy)
                ForEach(Array(files.enumerated()), id: \.offset) { i, it in
                    resultNode(it, index: i, at: layout.pts[i])
                }
            }
        }
        .overlay(alignment: .topLeading) {
            Text("Results for “\(model.query.trimmingCharacters(in: .whitespaces))” · \(model.library.results.count)")
                .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(BB.ink).padding(.leading, 20).padding(.top, 14)
        }
        .background(BB.content)
    }

    private func searchEdges(_ layout: RadialLayout, count: Int) -> some View {
        Canvas { ctx, _ in
            for i in 0..<count {
                var p = Path(); p.move(to: CGPoint(x: layout.cx, y: layout.cy)); p.addLine(to: layout.pts[i])
                ctx.stroke(p, with: .color(hov == i ? BB.accent : BB.edge), lineWidth: 0.6)
            }
        }
    }

    private var centerCard: some View {
        HStack(spacing: 11) {
            Image(systemName: "magnifyingglass").font(.system(size: 20)).foregroundStyle(BB.accent)
                .frame(width: 40, height: 40).background(BB.info.opacity(0.13), in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 1) {
                Text("“\(model.query.trimmingCharacters(in: .whitespaces))”").font(.system(size: 14, weight: .bold)).foregroundStyle(BB.ink)
                Text("\(model.library.results.count) matches").font(.system(size: 11)).foregroundStyle(BB.ink3)
            }
        }.padding(12).background(BB.nodeBg, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(BB.hair, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }

    private func resultNode(_ it: IndexedItem, index i: Int, at p: CGPoint) -> some View {
        let cl = model.clusterOf(it.id)
        let n = GraphNeighbor(id: "item:\(it.id)", selection: .item(it.id), name: it.displayName,
                              kind: "\(cl?.name ?? "ungrouped") group", color: cl?.color ?? BB.ink2,
                              symbol: model.symbol(for: it), pred: "", strength: 0.6,
                              category: "Files", hubCount: 0)
        return GraphNode(neighbor: n) { model.select(.item(it.id)) }
            .opacity(hov != nil && hov != i ? 0.4 : 1)
            .onHover { hov = $0 ? i : (hov == i ? nil : hov) }
            .position(x: p.x, y: p.y)
    }
}

// MARK: - Graph node + center card

struct GraphNode: View {
    let neighbor: GraphNeighbor
    let tap: () -> Void
    var body: some View {
        Button(action: tap) {
            HStack(spacing: 9) {
                Image(systemName: neighbor.symbol).font(.system(size: 14)).foregroundStyle(neighbor.color)
                    .frame(width: 24, height: 24).background(neighbor.color.opacity(0.13), in: RoundedRectangle(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 0) {
                    Text(neighbor.name).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(BB.ink).lineLimit(1)
                    Text(neighbor.hubCount > 1 ? "\(neighbor.kind) · \(neighbor.hubCount) files" : neighbor.kind)
                        .font(.system(size: 10.5)).foregroundStyle(BB.ink3).lineLimit(1)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 9).frame(maxWidth: 190)
            .background(BB.nodeBg, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(BB.hair, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
            .overlay(alignment: .topTrailing) {
                if neighbor.hubCount > 1 {
                    Image(systemName: "point.3.connected.trianglepath.dotted").font(.system(size: 9)).foregroundStyle(.white)
                        .frame(width: 18, height: 18).background(BB.accent, in: Circle()).offset(x: 6, y: -6)
                }
            }
        }.buttonStyle(.plain).fixedSize()
    }
}

struct CenterCard: View {
    let center: GraphCenter
    var body: some View {
        if center.isItem {
            VStack(spacing: 0) {
                FileThumb(symbol: center.symbol, w: 132, h: 80, radius: 14)
                Text(center.name).font(.system(size: 12.5, weight: .bold)).foregroundStyle(BB.ink)
                    .lineLimit(2).multilineTextAlignment(.center).padding(.horizontal, 11).padding(.vertical, 9).frame(width: 132)
            }
            .background(BB.nodeBg, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(BB.hair, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.18), radius: 12, y: 4).fixedSize()
        } else {
            HStack(spacing: 11) {
                Image(systemName: center.symbol).font(.system(size: 22)).foregroundStyle(center.color)
                    .frame(width: 40, height: 40).background(center.color.opacity(0.13), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 1) {
                    Text(center.name).font(.system(size: 14, weight: .bold)).foregroundStyle(BB.ink)
                    Text(center.kind.capitalized).font(.system(size: 11)).foregroundStyle(BB.ink3)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(BB.nodeBg, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(BB.hair, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.12), radius: 10, y: 3).fixedSize()
        }
    }
}
