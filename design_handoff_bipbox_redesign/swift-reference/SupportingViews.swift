// SupportingViews.swift — Rules and Activity center panes.
import SwiftUI

struct RulesView: View {
    @EnvironmentObject var model: WorkspaceModel
    var body: some View {
        VStack(spacing: 0) {
            CenterHeader(title: "Rules", sub: "3 routes · automation is optional")
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Sample.rules) { r in RuleRow(rule: r) }
                    HStack(spacing: 10) {
                        Image(systemName: "plus"); Text("New rule — match files, then choose what happens")
                    }
                    .font(.system(size: 13.5, weight: .medium)).foregroundStyle(BB.ink2)
                    .frame(maxWidth: .infinity).padding(22)
                    .background(RoundedRectangle(cornerRadius: 12).strokeBorder(BB.hairStrong, style: StrokeStyle(lineWidth: 1.5, dash: [5])))
                    .padding(.top, 6)
                }.padding(.horizontal, 12).padding(.bottom, 14)
            }.scrollIndicators(.hidden)
        }
    }
}

struct RuleRow: View {
    @EnvironmentObject var model: WorkspaceModel
    let rule: Rule
    @State private var hover = false
    var selected: Bool { if case .rule(rule.id) = model.selection { return true }; return false }
    var body: some View {
        Button { model.select(.rule(rule.id)) } label: {
            HStack(spacing: 12) {
                Image(systemName: "point.3.connected.trianglepath.dotted").font(.system(size: 15)).foregroundStyle(BB.ink2)
                    .frame(width: 34, height: 34).background(BB.chipBg, in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 2) {
                    Text(rule.name).font(.system(size: 14, weight: .medium)).foregroundStyle(BB.ink)
                    Text(rule.when).font(BB.mono).foregroundStyle(BB.ink2).lineLimit(1)
                }
                Spacer(minLength: 8)
                Toggle("", isOn: .constant(rule.enabled)).labelsHidden().toggleStyle(.switch).controlSize(.small)
                    .onTapGesture { model.flash(rule.enabled ? "Paused “\(rule.name)”" : "Enabled “\(rule.name)”") }
            }
            .padding(.horizontal, 12).padding(.vertical, 13)
            .background(selected ? BB.selFill : (hover ? BB.rowHover : .clear), in: RoundedRectangle(cornerRadius: BB.rCard))
            .contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { hover = $0 }
    }
}

struct ActivityView: View {
    @EnvironmentObject var model: WorkspaceModel
    var body: some View {
        VStack(spacing: 0) {
            CenterHeader(title: "Activity", sub: "Every change, explained — with undo")
            ScrollView {
                VStack(spacing: 0) { ForEach(Sample.activity) { e in ActivityRow(event: e) } }
                    .padding(.horizontal, 12).padding(.bottom, 14)
            }.scrollIndicators(.hidden)
        }
    }
}

struct ActivityRow: View {
    @EnvironmentObject var model: WorkspaceModel
    let event: ActivityEvent
    @State private var hover = false
    var selected: Bool { if case .activity(event.id) = model.selection { return true }; return false }
    var body: some View {
        Button { model.select(.activity(event.id)) } label: {
            HStack(alignment: .top, spacing: 12) {
                Circle().strokeBorder(event.good ? BB.good : BB.info, lineWidth: 2)
                    .frame(width: 14, height: 14).padding(.top, 3)
                VStack(alignment: .leading, spacing: 3) {
                    Text(event.title).font(.system(size: 14, weight: .medium)).foregroundStyle(BB.ink)
                    Text(event.detail).font(.system(size: 12)).foregroundStyle(BB.ink2).lineLimit(2)
                }
                Spacer(minLength: 8)
                Text(event.when.components(separatedBy: ",").first ?? "").font(BB.caption).foregroundStyle(BB.ink3)
            }
            .padding(.horizontal, 12).padding(.vertical, 12)
            .background(selected ? BB.selFill : (hover ? BB.rowHover : .clear), in: RoundedRectangle(cornerRadius: BB.rCard))
            .contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { hover = $0 }
    }
}
