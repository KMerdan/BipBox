// SupportingCenterViews.swift — Rules and Activity center panes (port of the
// blueprint's SupportingViews), wired to the real rule/activity view models.
import SwiftUI
import BipboxCore

struct RulesView: View {
    @EnvironmentObject var model: WorkspaceModel
    var body: some View {
        VStack(spacing: 0) {
            CenterHeader(title: "Rules",
                         sub: "\(model.rules.ruleDocuments.count) rule(s) · automation is optional") {
                PillButton("New Rule", system: "plus", kind: .primary) {
                    Task { let id = await model.rules.addBlankRule(); model.select(.rule(id)) }
                }
                .accessibilityIdentifier("rule.new")
            }
            ScrollView {
                VStack(spacing: 0) {
                    if model.rules.ruleDocuments.isEmpty {
                        emptyState
                    } else {
                        ForEach(model.rules.ruleDocuments) { RuleRow(rule: $0) }
                    }
                    if let msg = model.rules.ruleFilesMessage {
                        Text(msg).font(BB.caption).foregroundStyle(BB.ink3).padding(.top, 8)
                    }
                }.padding(.horizontal, 12).padding(.bottom, 14)
            }.scrollIndicators(.hidden)
        }
        .task { await model.rules.loadRuleFiles() }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "point.3.connected.trianglepath.dotted").font(.system(size: 28)).foregroundStyle(BB.ink3)
            Text("No rules yet").font(.system(size: 14, weight: .semibold)).foregroundStyle(BB.ink2)
            Text("Rules are optional. Add one to auto-tag, collect, review, or move\nnew arrivals — Bipbox is useful without them.")
                .font(BB.caption).foregroundStyle(BB.ink3).multilineTextAlignment(.center)
            PillButton("New Rule", system: "plus", kind: .primary) {
                Task { let id = await model.rules.addBlankRule(); model.select(.rule(id)) }
            }
        }.frame(maxWidth: .infinity).padding(.top, 50)
    }
}

struct RuleRow: View {
    @EnvironmentObject var model: WorkspaceModel
    let rule: RuleDocument
    @State private var hover = false
    var selected: Bool { if case .rule(rule.id) = model.selection { return true }; return false }
    var body: some View {
        Button { model.select(.rule(rule.id)) } label: {
            HStack(spacing: 12) {
                Image(systemName: "point.3.connected.trianglepath.dotted").font(.system(size: 15)).foregroundStyle(BB.ink2)
                    .frame(width: 34, height: 34).background(BB.chipBg, in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 2) {
                    Text(rule.name).font(.system(size: 14, weight: .medium))
                        .foregroundStyle(rule.enabled ? BB.ink : BB.ink3)
                    Text(whenText).font(BB.mono).foregroundStyle(BB.ink2).lineLimit(1)
                }
                Spacer(minLength: 8)
                Toggle("", isOn: Binding(
                    get: { rule.enabled },
                    set: { newValue in Task { await model.rules.setRuleEnabled(id: rule.id, newValue) } }
                ))
                .labelsHidden().toggleStyle(.switch).controlSize(.small)
                .accessibilityIdentifier("rule.toggle.\(rule.id.uuidString)")
            }
            .padding(.horizontal, 12).padding(.vertical, 13)
            .background(selected ? BB.selFill : (hover ? BB.rowHover : .clear), in: RoundedRectangle(cornerRadius: BB.rCard))
            .contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { hover = $0 }
    }
    private var whenText: String {
        let op = rule.action.operation.rawValue
        if let dest = rule.action.destinationPath, !dest.isEmpty { return "\(op) → \(dest)" }
        return op
    }
}

struct ActivityView: View {
    @EnvironmentObject var model: WorkspaceModel
    var body: some View {
        VStack(spacing: 0) {
            CenterHeader(title: "Activity", sub: "Every change, explained — with undo")
            ScrollView {
                VStack(spacing: 0) { ForEach(model.activity.events) { ActivityRow(event: $0) } }
                    .padding(.horizontal, 12).padding(.bottom, 14)
            }.scrollIndicators(.hidden)
        }
        .task { await model.activity.loadRecent() }
    }
}

struct ActivityRow: View {
    @EnvironmentObject var model: WorkspaceModel
    let event: ActivityEvent
    @State private var hover = false
    var selected: Bool { if case .activity(event.id) = model.selection { return true }; return false }
    private var isGood: Bool { event.kind != .failed && event.kind != .error }
    var body: some View {
        Button { model.select(.activity(event.id)) } label: {
            HStack(alignment: .top, spacing: 12) {
                Circle().strokeBorder(isGood ? BB.good : BB.info, lineWidth: 2)
                    .frame(width: 14, height: 14).padding(.top, 3)
                VStack(alignment: .leading, spacing: 3) {
                    Text(event.message).font(.system(size: 14, weight: .medium)).foregroundStyle(BB.ink).lineLimit(1)
                    Text(event.kind.rawValue.capitalized).font(.system(size: 12)).foregroundStyle(BB.ink2).lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(WorkspaceModel.dateFormatter.string(from: event.occurredAt)).font(BB.caption).foregroundStyle(BB.ink3)
            }
            .padding(.horizontal, 12).padding(.vertical, 12)
            .background(selected ? BB.selFill : (hover ? BB.rowHover : .clear), in: RoundedRectangle(cornerRadius: BB.rCard))
            .contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { hover = $0 }
        .accessibilityIdentifier("activity.\(event.id.uuidString)")
    }
}
