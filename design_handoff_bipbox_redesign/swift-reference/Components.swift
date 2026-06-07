// Components.swift — small reusable UI pieces.
import SwiftUI

// MARK: Pill button

struct PillButton: View {
    enum Kind { case normal, primary, danger }
    let title: String; var system: String? = nil; var kind: Kind = .normal; let action: () -> Void
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
    let symbol: String; var w: CGFloat = 40; var h: CGFloat = 40; var radius: CGFloat = 9
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

struct FlowChips: View {
    let contexts: [ContextNode]
    init(_ contexts: [ContextNode]) { self.contexts = contexts }
    var body: some View {
        FlowLayout(spacing: 7) {
            ForEach(contexts) { c in
                HStack(spacing: 6) {
                    Circle().fill(c.color).frame(width: 7, height: 7)
                    Text(c.name).font(.system(size: 12, weight: .medium))
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
    let title: String; let sub: String; @ViewBuilder var accessory: Accessory
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
