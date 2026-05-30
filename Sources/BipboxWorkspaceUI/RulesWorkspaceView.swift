import AppKit
import BipboxCore
import SwiftUI

public struct RulesWorkspaceView: View {
    @StateObject private var viewModel: RulesWorkspaceViewModel
    @State private var ruleName = "New PDF Rule"
    @State private var fileExtension = "pdf"
    @State private var destinationPath = RulesWorkspaceView.defaultDestinationPath
    @State private var conditionField: ConditionField = .fileExtension
    @State private var conditionOperation: ConditionOperator = .equals
    @State private var conditionValue = "pdf"
    @State private var outcomeKind: RuleOutcomeKind = .move
    @State private var outcomeValue = RulesWorkspaceView.defaultDestinationPath
    @State private var requiresReview = false
    @State private var ruleEnabled = true

    public init(viewModel: RulesWorkspaceViewModel = RulesWorkspaceViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        HSplitView {
            ruleList
                .frame(minWidth: 280, idealWidth: 320)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    editorPane
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(minWidth: 520)
        }
        .task {
            await viewModel.loadRuleFiles()
            syncEditorFields()
        }
        .onChange(of: viewModel.selectedBranchID) {
            syncEditorFields()
        }
    }

    private var ruleList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.workflow.name)
                        .font(.headline)
                    Text("\(viewModel.branches.count) routes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if viewModel.isLoadingRuleFiles || viewModel.isSavingRuleFiles {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding()

            List(viewModel.branches, selection: Binding(
                get: { viewModel.selectedBranchID },
                set: { viewModel.selectBranch(id: $0) }
            )) { branch in
                VStack(alignment: .leading, spacing: 5) {
                    Text(branch.name)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Text(branch.conditions.map(\.summary).joined(separator: " and "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .padding(.vertical, 3)
                .tag(branch.id)
            }
            .listStyle(.sidebar)
        }
    }

    private var editorPane: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Rule")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                if viewModel.isLoadingRuleFiles || viewModel.isSavingRuleFiles {
                    ProgressView()
                        .controlSize(.small)
                }
                Button {
                    createNewRule()
                } label: {
                    Label("New Rule", systemImage: "plus")
                }

                Button(role: .destructive) {
                    deleteSelectedRule()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(viewModel.selectedBranch == nil)
            }

            HStack(spacing: 8) {
                if let message = viewModel.ruleFilesMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            HStack {
                TextField("Rule name", text: $ruleName)
                    .textFieldStyle(.roundedBorder)
                Toggle("Enabled", isOn: $ruleEnabled)
            }

            HStack {
                Picker("Field", selection: $conditionField) {
                    ForEach(ConditionField.allCases, id: \.rawValue) { field in
                        Text(field.rawValue).tag(field)
                    }
                }
                Picker("Operator", selection: $conditionOperation) {
                    ForEach(ConditionOperator.allCases, id: \.rawValue) { operation in
                        Text(operation.rawValue).tag(operation)
                    }
                }
                TextField("Value", text: $conditionValue)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Picker("Outcome", selection: $outcomeKind) {
                    ForEach(RuleOutcomeKind.allCases) { outcome in
                        Text(outcome.title).tag(outcome)
                    }
                }
                TextField(outcomePlaceholder, text: $outcomeValue)
                    .textFieldStyle(.roundedBorder)

                Button {
                    chooseDestinationFolder()
                } label: {
                    Label("Choose Folder", systemImage: "folder")
                }
                .disabled(!(outcomeKind == .move || outcomeKind == .copy))
            }

            Toggle("Requires review", isOn: $requiresReview)

            HStack {
                Button {
                    viewModel.updateSelectedRuleForm(
                        name: ruleName,
                        enabled: ruleEnabled,
                        conditionField: conditionField,
                        conditionOperation: conditionOperation,
                        conditionValue: conditionValue,
                        outcomeKind: outcomeKind,
                        outcomeValue: outcomeValue,
                        requiresReview: requiresReview
                    )
                    Task { await viewModel.saveRuleFiles() }
                } label: {
                    Label("Apply", systemImage: "checkmark")
                }
                .disabled(viewModel.selectedBranch == nil)
            }

            Divider()

            if let branch = viewModel.selectedBranch {
                VStack(alignment: .leading, spacing: 10) {
                    Label(branch.name, systemImage: "arrow.triangle.branch")
                        .font(.headline)

                    ForEach(branch.conditions) { condition in
                        Label(condition.summary, systemImage: "line.3.horizontal.decrease.circle")
                    }

                    ForEach(branch.node.actions) { action in
                        Label(action.summary, systemImage: "arrow.turn.down.right")
                    }

                    Text("Fallback: \(viewModel.fallbackTitle)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else {
                WorkspaceEmptyState(
                    title: "No route selected",
                    message: "Create or select a route.",
                    systemImage: "point.3.connected.trianglepath.dotted"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private static var defaultDestinationPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Bipbox", isDirectory: true)
            .path
    }

    private func createNewRule() {
        viewModel.addFileRule(
            name: "New Rule",
            fileExtension: "pdf",
            destinationPath: destinationPath
        )
        syncEditorFields()
        Task { await viewModel.saveRuleFiles() }
    }

    private func deleteSelectedRule() {
        viewModel.removeSelectedBranch()
        syncEditorFields()
        Task { await viewModel.saveRuleFiles() }
    }

    private func chooseDestinationFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Choose the rule destination folder."
        panel.directoryURL = URL(fileURLWithPath: destinationPath, isDirectory: true)

        if panel.runModal() == .OK, let url = panel.url {
            outcomeValue = url.path
            destinationPath = url.path
        }
    }

    private func syncEditorFields() {
        guard let branch = viewModel.selectedBranch else {
            return
        }

        ruleName = branch.name
        ruleEnabled = viewModel.selectedRuleDocument?.enabled ?? true
        if let condition = branch.conditions.first {
            conditionField = condition.field
            conditionOperation = condition.operation
            conditionValue = condition.value
            if condition.field == .fileExtension {
                fileExtension = condition.value
            }
        }
        if let action = branch.node.actions.first {
            outcomeKind = RuleOutcomeKind(operationKind: action.operationKind, graphAction: branch.node.graphActions?.first)
            requiresReview = action.requiresReview || (branch.node.graphActions ?? []).contains(where: \.requiresReview)
        }
        if let graphAction = branch.node.graphActions?.first {
            outcomeValue = graphAction.formValue
        } else if let destination = branch.node.actions.first?.parameters["destination"] {
            destinationPath = destination
            outcomeValue = destination
        } else if let tags = branch.node.actions.first?.parameters["tags"] {
            outcomeValue = tags
        } else if let reason = branch.node.actions.first?.parameters["reason"] {
            outcomeValue = reason
        }
    }

    private var outcomePlaceholder: String {
        switch outcomeKind {
        case .move, .copy: "Destination folder"
        case .indexOnly: "Optional note"
        case .review: "Review reason"
        case .addTags: "Tags"
        case .addToCollection: "Collection name"
        case .addTopic: "Topic"
        case .addPerson: "Person"
        case .addProject: "Project"
        }
    }
}

private extension ConditionDescriptor {
    var summary: String {
        "\(field.rawValue) \(operation.rawValue) \(value)"
    }
}

private extension ActionDescriptor {
    var summary: String {
        let destination = parameters["destination"].map { " -> \($0)" } ?? ""
        return "\(operationKind.rawValue)\(destination)"
    }
}

private extension RuleOutcomeKind {
    init(operationKind: OperationKind, graphAction: GraphActionDescriptor?) {
        if let graphAction {
            switch graphAction.kind {
            case .addToCollection:
                self = .addToCollection
            case .addTopic:
                self = .addTopic
            case .addPerson:
                self = .addPerson
            case .addProject:
                self = .addProject
            case .addRelationship:
                self = .indexOnly
            }
            return
        }

        switch operationKind {
        case .move: self = .move
        case .copy: self = .copy
        case .indexInPlace: self = .indexOnly
        case .markNeedsReview: self = .review
        case .addTags: self = .addTags
        case .rename, .removeTags, .createFolder, .open, .revealInFinder:
            self = .indexOnly
        }
    }
}

private extension GraphActionDescriptor {
    var formValue: String {
        switch kind {
        case .addToCollection:
            parameters["collectionName"] ?? parameters["collectionID"] ?? ""
        case .addTopic:
            parameters["topic"] ?? ""
        case .addPerson:
            parameters["person"] ?? ""
        case .addProject:
            parameters["project"] ?? ""
        case .addRelationship:
            parameters["predicate"] ?? ""
        }
    }
}

public extension ItemProfile {
    static func rulesFixturePDF() -> ItemProfile {
        ItemProfile(
            url: URL(fileURLWithPath: "/Users/example/Downloads/report.pdf"),
            kind: .file,
            displayName: "report.pdf",
            fileExtension: "pdf",
            uniformTypeIdentifier: "com.adobe.pdf",
            source: .dragDrop
        )
    }

    static func rulesFixtureFolder() -> ItemProfile {
        ItemProfile(
            url: URL(fileURLWithPath: "/Users/example/Downloads/Client Project", isDirectory: true),
            kind: .folder,
            displayName: "Client Project",
            source: .dragDrop,
            folderChildSummary: FolderChildSummary(
                visibleChildCount: 1,
                visibleFileCount: 1,
                visibleFolderCount: 0,
                topLevelExtensions: ["pdf": 1],
                recursiveInspectionRequested: false
            )
        )
    }
}
