// InspectorView.swift — ONE inspector for every selection (port of the blueprint).
// Item · hub (source/collection/cluster/context) · overview · rule · activity · empty.
import SwiftUI
import BipboxCore

struct InspectorView: View {
    @EnvironmentObject var model: WorkspaceModel
    var body: some View {
        VStack(spacing: 0) {
            switch model.selection {
            case .item(let id):
                if let it = model.item(id) { ItemInspector(item: it) } else { EmptyInspector() }
            case .source, .collection, .cluster, .context:
                NodeInspector(selection: model.selection)
            case .overview:
                OverviewInspector()
            case .rule(let id):
                if let r = model.rules.ruleDocuments.first(where: { $0.id == id }) { RuleInspector(rule: r) } else { EmptyInspector() }
            case .activity(let id):
                if let e = model.activity.events.first(where: { $0.id == id }) { ActivityInspector(event: e) } else { EmptyInspector() }
            case .none:
                EmptyInspector()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

// MARK: item

struct ItemInspector: View {
    @EnvironmentObject var model: WorkspaceModel
    let item: IndexedItem
    var body: some View {
        VStack(spacing: 0) {
            inspHead()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(spacing: 12) {
                        FileThumb(symbol: model.symbol(for: item), w: 92, h: 110)
                        VStack(spacing: 2) {
                            Text(item.displayName).font(BB.head()).foregroundStyle(BB.ink).multilineTextAlignment(.center)
                            Text("\(item.kind.rawValue.uppercased()) · from \(model.sourceName(for: item))")
                                .font(BB.caption).foregroundStyle(BB.ink2)
                        }
                        StatusPill(text: item.status.displayLabel, tint: item.status.tint)
                            .accessibilityIdentifier("item.status")
                    }.frame(maxWidth: .infinity).padding(.bottom, 18)

                    if model.isPending(item) { DecisionBlock(item: item).padding(.bottom, 18) }

                    if item.status == .missing || item.status == .failed {
                        RecoveryBlock(item: item).padding(.bottom, 18)
                    }

                    WhyBox(lead: "Why you’re seeing this", symbol: "sparkles", text: model.why(for: item))
                        .accessibilityIdentifier("item.why")
                        .padding(.bottom, 18)

                    InspSection(title: "Details") {
                        VStack(spacing: 0) {
                            KV(k: "Kind", v: item.kind.rawValue.capitalized).accessibilityIdentifier("detail.kind")
                            KV(k: "Where", v: item.currentPath, mono: true).accessibilityIdentifier("detail.where")
                            if let origin = item.originalPath, !origin.isEmpty {
                                KV(k: "Came from", v: origin, mono: true).accessibilityIdentifier("detail.cameFrom")
                            }
                            KV(k: "Source", v: model.sourceName(for: item)).accessibilityIdentifier("detail.source")
                            KV(k: "Added", v: model.dateString(for: item)).accessibilityIdentifier("detail.added")
                        }
                    }

                    if isSelected, let overview = model.selectedOverview, !overview.contexts.isEmpty {
                        InspSection(title: "In context") {
                            FlowChips(overview.contexts.map {
                                ChipData(id: $0.context.id.uuidString, text: $0.context.name, color: BB.grape)
                            })
                            .accessibilityIdentifier("item.contexts")
                        }
                    }

                    if isSelected, !model.selectedRelated.isEmpty {
                        InspSection(title: "Related") {
                            VStack(spacing: 4) {
                                ForEach(model.selectedRelated.prefix(6).map(\.item)) { rel in
                                    RelatedRow(symbol: model.symbol(for: rel), title: rel.displayName,
                                               sub: "related content · \(model.sourceName(for: rel))") {
                                        model.select(.item(rel.id))
                                    }
                                    .accessibilityIdentifier("related.\(rel.id.uuidString)")
                                }
                            }
                        }
                    }
                }.padding(20)
            }.scrollIndicators(.hidden)
        }
        .task(id: item.id) { await model.loadInspectorData() }
    }

    private var isSelected: Bool {
        if case .item(item.id) = model.selection { return true }
        return false
    }
}

struct DecisionBlock: View {
    @EnvironmentObject var model: WorkspaceModel
    let item: IndexedItem
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Assistant suggests", systemImage: "sparkles").font(.system(size: 12.5, weight: .bold)).foregroundStyle(BB.warn)
            Text(suggestionText)
                .font(.system(size: 12.5)).foregroundStyle(BB.ink).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("decision.suggestion")
            HStack(spacing: 8) {
                PillButton("Approve", system: "checkmark", kind: .primary) { model.decide(item, .approve) }
                    .accessibilityIdentifier("decision.approve")
                PillButton("Keep, don’t move") { model.decide(item, .keep) }
                    .accessibilityIdentifier("decision.keep")
                PillButton("Reject", system: "xmark", kind: .danger) { model.decide(item, .reject) }
                    .accessibilityIdentifier("decision.reject")
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(BB.warn.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(BB.warn.opacity(0.3), lineWidth: 0.5))
    }

    private var suggestionText: String {
        if let queued = model.reviewQueue.items.first(where: { $0.indexedItem?.id == item.id }) {
            let preview = queued.plan.previewText
            return preview.isEmpty ? queued.reason : preview
        }
        return "Nothing moves until you approve — it stays findable either way."
    }
}

// MARK: recovery (missing / failed items — safety: recoverable, not forgotten)

struct RecoveryBlock: View {
    @EnvironmentObject var model: WorkspaceModel
    let item: IndexedItem
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("This file can't be found", systemImage: "exclamationmark.triangle")
                .font(.system(size: 12.5, weight: .bold)).foregroundStyle(BB.bad)
            Text("Bipbox still remembers it. Point it at the file's new location, or re-check.")
                .font(.system(size: 12.5)).foregroundStyle(BB.ink).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                PillButton("Locate…", system: "folder", kind: .primary) { locate() }
                    .accessibilityIdentifier("recover.locate")
                PillButton("Reindex", system: "arrow.clockwise") { model.recoverItem(item, mode: .reindex) }
                    .accessibilityIdentifier("recover.reindex")
                PillButton("Refresh") { model.recoverItem(item, mode: .refresh) }
                    .accessibilityIdentifier("recover.refresh")
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(BB.bad.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(BB.bad.opacity(0.3), lineWidth: 0.5))
    }

    private func locate() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Locate"
        if panel.runModal() == .OK, let url = panel.url {
            model.recoverItem(item, mode: .locate, at: url)
        }
    }
}

// MARK: hub (source / collection / cluster / context)

struct NodeInspector: View {
    @EnvironmentObject var model: WorkspaceModel
    let selection: Selection
    var body: some View {
        let meta = model.nodeMeta(selection)
        let members = model.nodeMembers(selection)
        VStack(spacing: 0) {
            inspHead(true)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let meta {
                        HStack(spacing: 14) {
                            Image(systemName: meta.symbol).font(.system(size: 34)).foregroundStyle(meta.color)
                                .frame(width: 84, height: 84).background(meta.color.opacity(0.16), in: RoundedRectangle(cornerRadius: 18))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(meta.name).font(BB.head()).foregroundStyle(BB.ink)
                                Text("\(meta.kind.capitalized) · \(members.count) connected items").font(BB.caption).foregroundStyle(BB.ink2)
                            }
                            Spacer()
                        }.padding(.bottom, 18)

                        WhyBox(lead: "This is a hub", symbol: "point.3.connected.trianglepath.dotted",
                               text: "\(members.count) of your items connect through \(meta.name). Open one, or click another node in the graph to keep following the thread.")
                            .padding(.bottom, 18)

                        InspSection(title: "Connected items") {
                            VStack(spacing: 4) {
                                ForEach(members) { it in
                                    RelatedRow(symbol: model.symbol(for: it), title: it.displayName,
                                               sub: model.sourceName(for: it)) {
                                        model.select(.item(it.id))
                                    }
                                }
                            }
                        }

                        if meta.type == .source, case .source(let id) = selection {
                            HStack(spacing: 8) {
                                PillButton("Rescan", system: "arrow.clockwise") {
                                    model.flash("Rescanning \(meta.name)…")
                                    Task { await model.onboarding.scanSource(id: id); await model.refresh() }
                                }
                                .accessibilityIdentifier("hub.rescan")
                                PillButton("Pause", system: "pause") {
                                    model.flash("Paused watching \(meta.name)")
                                    Task { await model.onboarding.pauseSource(id: id); await model.refresh() }
                                }
                                .accessibilityIdentifier("hub.pause")
                            }
                        }
                    } else {
                        EmptyInspector()
                    }
                }.padding(20)
            }.scrollIndicators(.hidden)
        }
    }
}

// MARK: overview

struct OverviewInspector: View {
    @EnvironmentObject var model: WorkspaceModel
    var body: some View {
        let clusters = model.clusters
        VStack(spacing: 0) {
            inspHead(true)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    InspSection(title: "Overview") {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Your library, grouped by \(model.lens.title.lowercased())").font(BB.head()).foregroundStyle(BB.ink)
                            Text("\(model.library.results.count) files in \(clusters.count) groups. Pick a group to zoom in, then a file — you never see every file at once. Switch the grouping with “Group” in the toolbar.")
                                .font(BB.caption).foregroundStyle(BB.ink2)
                        }
                    }
                    WhyBox(lead: "A map, not a hairball", symbol: "point.3.connected.trianglepath.dotted",
                           text: "Smart grouping clusters files by meaning (on-device embeddings); Type, Source and Time are alternate lenses.").padding(.bottom, 18)
                    InspSection(title: "Clusters") {
                        VStack(spacing: 4) {
                            ForEach(clusters) { cl in
                                RelatedRow(symbol: "square.stack.3d.up", title: cl.name, sub: "\(cl.itemIDs.count) files") {
                                    model.select(.cluster(cl.id))
                                }
                            }
                        }
                    }
                }.padding(20)
            }.scrollIndicators(.hidden)
        }
    }
}

// MARK: rule

struct RuleInspector: View {
    @EnvironmentObject var model: WorkspaceModel
    let rule: RuleDocument
    @State private var draftName: String = ""
    @State private var didLoad = false

    var body: some View {
        VStack(spacing: 0) {
            inspHead(true)
            ScrollView { VStack(alignment: .leading, spacing: 0) {
                InspSection(title: "Rule") {
                    TextField("Rule name", text: $draftName)
                        .textFieldStyle(.plain).font(BB.head()).foregroundStyle(BB.ink)
                        .onSubmit { rename() }
                }
                InspSection(title: "Status") {
                    Toggle(isOn: Binding(
                        get: { rule.enabled },
                        set: { v in Task { await model.rules.setRuleEnabled(id: rule.id, v) } }
                    )) {
                        Text(rule.enabled ? "Enabled" : "Paused").font(.system(size: 13)).foregroundStyle(BB.ink)
                    }.toggleStyle(.switch).controlSize(.small)
                }
                InspSection(title: "When") { Text(whenText).font(BB.mono).foregroundStyle(BB.ink2) }
                InspSection(title: "Then") { Text(thenText).font(.system(size: 12.5)).foregroundStyle(BB.ink) }
                InspSection(title: "") {
                    KV(k: "Ask before doing it", v: rule.action.requiresReview ? "Yes" : "No")
                }
                HStack(spacing: 8) {
                    PillButton("Save name", kind: .primary) { rename() }
                    PillButton("Delete", system: "trash", kind: .danger) {
                        Task { await model.rules.deleteRule(id: rule.id); model.select(.none) }
                    }
                }
                Text("Condition/destination editing is JSON-backed for now (see the rule files on disk).")
                    .font(.system(size: 11)).foregroundStyle(BB.ink3).padding(.top, 10)
            }.padding(20) }.scrollIndicators(.hidden)
        }
        .onAppear { if !didLoad { draftName = rule.name; didLoad = true } }
        .onChange(of: rule.id) { draftName = rule.name }
    }

    private func rename() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != rule.name else { return }
        Task { await model.rules.renameRule(id: rule.id, to: trimmed) }
    }

    private var whenText: String {
        rule.conditions.isEmpty ? "any captured item" : rule.conditions
            .map { "\($0.field.rawValue) \($0.operation.rawValue) “\($0.value)”" }
            .joined(separator: "\nand ")
    }
    private var thenText: String {
        let op = rule.action.operation.rawValue.capitalized
        if let dest = rule.action.destinationPath, !dest.isEmpty { return "\(op) → \(dest)" }
        return op
    }
}

// MARK: activity

struct ActivityInspector: View {
    @EnvironmentObject var model: WorkspaceModel
    let event: ActivityEvent
    var body: some View {
        VStack(spacing: 0) {
            inspHead(true)
            ScrollView { VStack(alignment: .leading, spacing: 0) {
                InspSection(title: event.kind.rawValue) { Text(event.message).font(BB.head()).foregroundStyle(BB.ink) }
                InspSection(title: "") { VStack(spacing: 0) {
                    KV(k: "When", v: WorkspaceModel.dateFormatter.string(from: event.occurredAt))
                    KV(k: "Reversible", v: event.undoOperation != nil ? "Yes" : "No")
                } }
                if event.undoOperation != nil {
                    PillButton("Undo this", system: "arrow.uturn.backward") {
                        model.activity.select(id: event.id)
                        Task { await model.activity.undoSelected() }
                        model.flash("Reverted — back to previous state")
                    }
                    .accessibilityIdentifier("activity.undo")
                }
            }.padding(20) }.scrollIndicators(.hidden)
        }
    }
}

// MARK: empty

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
