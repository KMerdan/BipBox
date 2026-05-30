import Foundation

public final class DefaultWorkflowEngine: WorkflowEngine {
    private let aiOrchestrator: AIOrchestrator?
    private let highConfidenceThreshold: Double

    public init(aiOrchestrator: AIOrchestrator? = nil, highConfidenceThreshold: Double = 0.85) {
        self.aiOrchestrator = aiOrchestrator
        self.highConfidenceThreshold = highConfidenceThreshold
    }

    public func evaluate(
        workflow: Workflow,
        item: ItemProfile,
        context: WorkflowEvaluationContext
    ) async throws -> RouteDecision {
        try await evaluateNode(workflow.root, item: item, context: context, matchedIDs: [workflow.root.id])
    }

    private func evaluateNode(
        _ node: WorkflowNode,
        item: ItemProfile,
        context: WorkflowEvaluationContext,
        matchedIDs: [UUID]
    ) async throws -> RouteDecision {
        switch node.kind {
        case .router:
            return try await evaluateRouter(node, item: item, context: context, matchedIDs: matchedIDs)
        case .action:
            return actionDecision(node, matchedIDs: matchedIDs)
        case .review:
            return reviewDecision(node, matchedIDs: matchedIDs, reason: "Workflow requires review at \(node.name).")
        case .stop:
            return RouteDecision(
                confidence: 1,
                matchedRuleIDs: matchedIDs,
                reason: "Workflow stopped at \(node.name).",
                reviewRequirement: .notRequired
            )
        case .aiClassify:
            return try await aiClassificationDecision(node, item: item, matchedIDs: matchedIDs)
        case .transform, .toolCall:
            return reviewDecision(
                node,
                matchedIDs: matchedIDs,
                reason: "\(node.kind.rawValue) node \(node.name) is not executable by this engine yet."
            )
        }
    }

    private func evaluateRouter(
        _ node: WorkflowNode,
        item: ItemProfile,
        context: WorkflowEvaluationContext,
        matchedIDs: [UUID]
    ) async throws -> RouteDecision {
        for branch in node.branches where branchMatches(branch, item: item, context: context) {
            return try await evaluateNode(
                branch.node,
                item: item,
                context: context,
                matchedIDs: matchedIDs + [branch.id, branch.node.id]
            )
        }

        if let fallback = node.fallback {
            return try await evaluateNode(fallback, item: item, context: context, matchedIDs: matchedIDs + [fallback.id])
        }

        return reviewDecision(
            node,
            matchedIDs: matchedIDs,
            reason: "No workflow branch matched and no fallback was configured."
        )
    }

    private func aiClassificationDecision(
        _ node: WorkflowNode,
        item: ItemProfile,
        matchedIDs: [UUID]
    ) async throws -> RouteDecision {
        guard let aiOrchestrator else {
            return reviewDecision(
                node,
                matchedIDs: matchedIDs,
                reason: "AI classification node \(node.name) has no configured AI gateway."
            )
        }

        let classification = try await aiOrchestrator.classify(
            AIRequest(
                itemProfile: item,
                allowedTools: [],
                remoteContentSharingAllowed: false
            )
        )
        let reason = "AI classification at \(node.name): \(classification.reason)"
        let requiresReview = classification.reviewRequirement == .required ||
            classification.confidence < highConfidenceThreshold ||
            node.actions.isEmpty ||
            node.actions.contains(where: \.requiresReview) ||
            (node.graphActions ?? []).contains(where: \.requiresReview)

        guard !requiresReview else {
            return RouteDecision(
                confidence: classification.confidence,
                matchedRuleIDs: matchedIDs,
                destinationURL: classification.suggestedDestinationURL,
                actions: node.actions,
                graphActions: node.graphActions ?? [],
                reason: reason,
                reviewRequirement: .required
            )
        }

        let actions = actionsForAIClassification(node.actions, classification: classification)
        let destination = classification.suggestedDestinationURL ??
            actions.lazy.compactMap { $0.parameters["destination"].map(URL.init(fileURLWithPath:)) }.first

        return RouteDecision(
            confidence: classification.confidence,
            matchedRuleIDs: matchedIDs,
            destinationURL: destination,
            actions: actions,
            graphActions: node.graphActions ?? [],
            reason: reason,
            reviewRequirement: .notRequired
        )
    }

    private func actionsForAIClassification(
        _ actions: [ActionDescriptor],
        classification: AIClassification
    ) -> [ActionDescriptor] {
        actions.map { action in
            guard let suggestedDestinationURL = classification.suggestedDestinationURL,
                  action.parameters["destination"] == nil,
                  action.operationKind == .move || action.operationKind == .copy else {
                return action
            }

            var parameters = action.parameters
            parameters["destination"] = suggestedDestinationURL.path
            return ActionDescriptor(
                id: action.id,
                operationKind: action.operationKind,
                parameters: parameters,
                requiresReview: action.requiresReview,
                recursiveFolderProcessing: action.recursiveFolderProcessing
            )
        }
    }

    private func branchMatches(_ branch: WorkflowBranch, item: ItemProfile, context: WorkflowEvaluationContext) -> Bool {
        branch.conditions.allSatisfy { conditionMatches($0, item: item, context: context) }
    }

    private func actionDecision(_ node: WorkflowNode, matchedIDs: [UUID]) -> RouteDecision {
        let destination = node.actions
            .lazy
            .compactMap { $0.parameters["destination"] }
            .first
            .map { URL(fileURLWithPath: $0) }
        let requiresReview = node.actions.contains { $0.requiresReview } ||
            (node.graphActions ?? []).contains { $0.requiresReview }

        return RouteDecision(
            confidence: 1,
            matchedRuleIDs: matchedIDs,
            destinationURL: destination,
            actions: node.actions,
            graphActions: node.graphActions ?? [],
            reason: "Matched action node \(node.name).",
            reviewRequirement: requiresReview ? .required : .notRequired
        )
    }

    private func reviewDecision(
        _ node: WorkflowNode,
        matchedIDs: [UUID],
        reason: String
    ) -> RouteDecision {
        RouteDecision(
            confidence: 0,
            matchedRuleIDs: matchedIDs,
            reason: reason,
            reviewRequirement: .required
        )
    }

    private func conditionMatches(_ condition: ConditionDescriptor, item: ItemProfile, context: WorkflowEvaluationContext) -> Bool {
        switch condition.field {
        case .sizeBytes:
            return compareNumeric(item.sizeBytes.map(Double.init), condition: condition)
        case .createdAt:
            return compareDate(item.createdAt, condition: condition)
        case .modifiedAt:
            return compareDate(item.modifiedAt, condition: condition)
        case .finderTags:
            return compareStrings(item.finderTags, condition: condition)
        case .folderChildSummary:
            return compareFolderSummary(item.folderChildSummary, condition: condition)
        default:
            return compareStrings(stringValues(for: condition.field, item: item, context: context), condition: condition)
        }
    }

    private func stringValues(for field: ConditionField, item: ItemProfile, context: WorkflowEvaluationContext) -> [String] {
        switch field {
        case .itemKind:
            [item.kind.rawValue]
        case .filename:
            [item.displayName]
        case .fileExtension:
            item.fileExtension.map { [$0] } ?? []
        case .uniformTypeIdentifier:
            item.uniformTypeIdentifier.map { [$0] } ?? []
        case .source:
            item.source.map { [$0.rawValue] } ?? []
        case .sourceID:
            [context.sourceID?.uuidString, item.metadata["sourceID"]].compactMap { $0 }
        case .sourceKind:
            [context.sourceFacts["sourceKind"], item.metadata["sourceKind"], item.source?.rawValue].compactMap { $0 }
        case .sourceName:
            [context.sourceFacts["sourceName"], item.metadata["sourceName"]].compactMap { $0 }
        case .sourcePath:
            [context.sourceFacts["sourcePath"], item.metadata["sourcePath"]].compactMap { $0 }
        case .collection:
            context.collectionNames + commaSeparatedMetadata("collections", item: item)
        case .context:
            context.contextNames + commaSeparatedMetadata("contexts", item: item)
        case .extractedText:
            [item.extractedTextSummary, item.metadata["extractedText"]].compactMap { $0 }
        case .finderTags, .folderChildSummary, .sizeBytes, .createdAt, .modifiedAt:
            []
        }
    }

    private func commaSeparatedMetadata(_ key: String, item: ItemProfile) -> [String] {
        item.metadata[key]?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
    }

    private func compareStrings(_ values: [String], condition: ConditionDescriptor) -> Bool {
        switch condition.operation {
        case .equals:
            values.contains { $0.caseInsensitiveCompare(condition.value) == .orderedSame }
        case .contains:
            values.contains { $0.localizedCaseInsensitiveContains(condition.value) }
        case .startsWith:
            values.contains { $0.lowercased().hasPrefix(condition.value.lowercased()) }
        case .endsWith:
            values.contains { $0.lowercased().hasSuffix(condition.value.lowercased()) }
        case .matchesRegex:
            values.contains { value in
                value.range(of: condition.value, options: [.regularExpression, .caseInsensitive]) != nil
            }
        case .greaterThan, .lessThan:
            compareNumeric(values.first.flatMap(Double.init), condition: condition)
        }
    }

    private func compareNumeric(_ value: Double?, condition: ConditionDescriptor) -> Bool {
        guard let value, let expected = Double(condition.value) else {
            return false
        }

        switch condition.operation {
        case .equals:
            return value == expected
        case .greaterThan:
            return value > expected
        case .lessThan:
            return value < expected
        case .contains, .startsWith, .endsWith, .matchesRegex:
            return compareStrings([String(value)], condition: condition)
        }
    }

    private func compareDate(_ date: Date?, condition: ConditionDescriptor) -> Bool {
        guard let date else {
            return false
        }

        let value = date.timeIntervalSince1970
        if Double(condition.value) != nil {
            return compareNumeric(value, condition: condition)
        }

        return compareStrings([ISO8601DateFormatter().string(from: date)], condition: condition)
    }

    private func compareFolderSummary(
        _ summary: FolderChildSummary?,
        condition: ConditionDescriptor
    ) -> Bool {
        guard let summary else {
            return false
        }

        let values = [
            "visibleChildCount:\(summary.visibleChildCount)",
            "visibleFileCount:\(summary.visibleFileCount)",
            "visibleFolderCount:\(summary.visibleFolderCount)",
            "isPackageLike:\(summary.isPackageLike)",
            "recursiveInspectionRequested:\(summary.recursiveInspectionRequested)"
        ] + summary.topLevelExtensions.map { "extension:\($0.key):\($0.value)" }

        return compareStrings(values, condition: condition)
    }
}
