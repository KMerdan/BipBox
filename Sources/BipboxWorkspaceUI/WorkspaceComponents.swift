// WorkspaceComponents.swift — small reusable UI pieces (port of the blueprint's
// Components.swift + the inspector's shared pieces), adapted to real data.
import SwiftUI
import BipboxCore

// MARK: Pill button

struct PillButton: View {
    enum Kind { case normal, primary, danger }
    let title: String
    var system: String? = nil
    var kind: Kind = .normal
    let action: () -> Void
    @State private var hover = false
    init(_ title: String, system: String? = nil, kind: Kind = .normal, action: @escaping () -> Void) {
        self.title = title; self.system = system; self.kind = kind; self.action = action
    }
    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let system { Image(systemName: system).font(.system(size: 12, weight: .semibold)) }
                Text(title).font(.system(size: 12.5, weight: .medium))
            }
            .padding(.horizontal, 14).frame(height: 30)
            .background(bg, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(kind == .primary ? .clear : BB.hairStrong, lineWidth: 0.5))
            .foregroundStyle(fg)
        }.buttonStyle(.plain).onHover { hover = $0 }
    }
    private var bg: Color {
        switch kind {
        case .primary: hover ? BB.accentPress : BB.accent
        default: hover ? BB.rowHover : BB.field
        }
    }
    private var fg: Color { kind == .primary ? .white : (kind == .danger ? BB.bad : BB.ink) }
}

// MARK: Striped file thumbnail placeholder

struct FileThumb: View {
    let symbol: String
    var w: CGFloat = 40
    var h: CGFloat = 40
    var radius: CGFloat = 9
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius).fill(BB.chipBg)
            Image(systemName: symbol).font(.system(size: max(14, w * 0.32))).foregroundStyle(BB.ink3)
        }
        .frame(width: w, height: h)
        .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(BB.hair, lineWidth: 0.5))
    }
}

// MARK: Context chips (wrapping)

struct ChipData: Identifiable {
    let id: String
    let text: String
    let color: Color
    init(id: String = UUID().uuidString, text: String, color: Color) {
        self.id = id; self.text = text; self.color = color
    }
}

struct FlowChips: View {
    let chips: [ChipData]
    init(_ chips: [ChipData]) { self.chips = chips }
    var body: some View {
        FlowLayout(spacing: 7) {
            ForEach(chips) { c in
                HStack(spacing: 6) {
                    Circle().fill(c.color).frame(width: 7, height: 7)
                    Text(c.text).font(.system(size: 12, weight: .medium))
                }
                .padding(.horizontal, 11).frame(height: 26)
                .background(BB.chipBg, in: Capsule())
                .foregroundStyle(BB.ink2)
            }
        }
    }
}

// MARK: Simple flow layout (macOS 13+)

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > maxW { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing; rowH = max(rowH, s.height)
        }
        return CGSize(width: maxW == .infinity ? x : maxW, height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing; rowH = max(rowH, s.height)
        }
    }
}

// MARK: Result-list header (title + sub + optional accessory)

struct CenterHeader<Accessory: View>: View {
    let title: String
    let sub: String
    @ViewBuilder var accessory: Accessory
    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(BB.title()).foregroundStyle(BB.ink)
                Text(sub).font(.system(size: 12.5)).foregroundStyle(BB.ink2)
            }
            Spacer()
            accessory
        }
        .padding(.horizontal, 22).padding(.top, 18).padding(.bottom, 12)
    }
}
extension CenterHeader where Accessory == EmptyView {
    init(title: String, sub: String) { self.init(title: title, sub: sub) { EmptyView() } }
}

// MARK: Inspector shared pieces

/// The inspector header. Leading icons (open / reveal / copy path) act on the
/// current selection's on-disk target; the trailing ⋯ menu mirrors them. Icons
/// that have nothing to act on are disabled rather than dead-on-click.
struct InspectorHeader: View {
    @EnvironmentObject var model: WorkspaceModel
    var trailingOnly: Bool = false

    var body: some View {
        let url = model.inspectorTargetURL
        HStack(spacing: 6) {
            if !trailingOnly {
                InspIcon(symbol: "arrow.up.forward.square", help: "Open", enabled: url != nil) {
                    model.openSelectionExternally()
                }.accessibilityIdentifier("inspector.open")
                InspIcon(symbol: "folder", help: "Reveal in Finder", enabled: url != nil) {
                    model.revealSelectionInFinder()
                }.accessibilityIdentifier("inspector.reveal")
                InspIcon(symbol: "link", help: "Copy path", enabled: url != nil) {
                    model.copySelectionPath()
                }.accessibilityIdentifier("inspector.copyPath")
            }
            Spacer()
            Menu {
                Button("Open") { model.openSelectionExternally() }.disabled(url == nil)
                Button("Reveal in Finder") { model.revealSelectionInFinder() }.disabled(url == nil)
                Button("Copy Path") { model.copySelectionPath() }.disabled(url == nil)
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 14)).foregroundStyle(BB.ink2)
                    .frame(width: 30, height: 30)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(BB.hairStrong, lineWidth: 0.5))
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .accessibilityIdentifier("inspector.more")
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .overlay(alignment: .bottom) { Divider().overlay(BB.hair) }
    }
}

struct InspIcon: View {
    let symbol: String
    var help: String = ""
    var enabled: Bool = true
    var action: (() -> Void)? = nil
    @State private var hover = false
    var body: some View {
        Button { action?() } label: {
            Image(systemName: symbol).font(.system(size: 14))
                .foregroundStyle(enabled ? (hover ? BB.ink : BB.ink2) : BB.ink3)
                .frame(width: 30, height: 30)
                .background(hover && enabled ? BB.rowHover : .clear, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(BB.hairStrong, lineWidth: 0.5))
        }
        .buttonStyle(.plain).disabled(!enabled).onHover { hover = $0 }
        .help(help)
    }
}

struct InspSection<C: View>: View {
    let title: String
    @ViewBuilder let content: C
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if !title.isEmpty {
                Text(title.uppercased()).font(BB.groupHead).tracking(0.4).foregroundStyle(BB.ink3)
            }
            content
        }.padding(.bottom, 18)
    }
}

struct KV: View {
    let k: String
    let v: String
    var mono = false
    var body: some View {
        HStack {
            Text(k).font(.system(size: 12.5)).foregroundStyle(BB.ink2)
            Spacer()
            Text(v).font(mono ? BB.mono : .system(size: 12.5, weight: .medium)).foregroundStyle(BB.ink)
                .multilineTextAlignment(.trailing).lineLimit(2)
        }
        .padding(.vertical, 5).overlay(alignment: .bottom) { Divider().overlay(BB.hair) }
    }
}

struct WhyBox: View {
    let lead: String
    let symbol: String
    let text: String
    var tint = BB.accent
    var bg = BB.info.opacity(0.13)
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(lead, systemImage: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(tint)
            Text(text).font(.system(size: 12.5)).foregroundStyle(BB.ink).fixedSize(horizontal: false, vertical: true)
        }.padding(13).frame(maxWidth: .infinity, alignment: .leading)
            .background(bg, in: RoundedRectangle(cornerRadius: 10))
    }
}

/// A related-file row with a similarity strength bar (0…1) — the inspector twin
/// of the graph's distance/thickness weighting.
struct SimilarityRow: View {
    let symbol: String
    let title: String
    let score: Double          // 0…1 cosine
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 13)).foregroundStyle(BB.ink3)
                    .frame(width: 26, height: 26).background(BB.chipBg, in: RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(BB.ink).lineLimit(1)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(BB.hair).frame(height: 3)
                            Capsule().fill(BB.accent.opacity(0.85))
                                .frame(width: max(3, geo.size.width * CGFloat(min(1, max(0, score)))), height: 3)
                        }
                    }.frame(height: 3)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.vertical, 7)
            .background(hover ? BB.rowHover : .clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { hover = $0 }
    }
}

struct RelatedRow: View {
    let symbol: String
    let title: String
    let sub: String
    let action: () -> Void
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

// MARK: - Display helpers for real models

extension ItemKind {
    var symbolName: String {
        switch self {
        case .file: "doc.text"
        case .folder: "folder"
        case .package, .bundle: "shippingbox"
        case .symlink: "link"
        case .unknown: "doc"
        }
    }
}

/// A small, stable color palette used to tint sources/clusters by index.
enum BBPalette {
    static let colors: [Color] = [BB.accent, BB.grape, BB.good, BB.warn, BB.bad, BB.info]
    static func color(for index: Int) -> Color { colors[((index % colors.count) + colors.count) % colors.count] }
    /// Deterministic color from a UUID so the same source always gets the same hue.
    static func color(for id: UUID) -> Color { color(for: abs(id.hashValue)) }
}
