import Foundation

public protocol PathConflictChecking {
    func itemExists(at url: URL) -> Bool
}

public struct FileManagerPathConflictChecker: PathConflictChecking {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func itemExists(at url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }
}

public final class DefaultOperationPlanner: OperationPlanner {
    private let conflictChecker: PathConflictChecking

    public init(conflictChecker: PathConflictChecking = FileManagerPathConflictChecker()) {
        self.conflictChecker = conflictChecker
    }

    public func plan(
        decision: RouteDecision,
        item: ItemProfile,
        context: PlanningContext
    ) async throws -> OperationPlan {
        var operations: [Operation] = []
        let graphOperations = decision.graphActions.map { action in
            GraphOperation(
                kind: action.kind,
                itemID: item.id,
                parameters: action.parameters,
                requiresReview: action.requiresReview
            )
        }
        var conflicts: [String] = []

        let actions = decision.actions.isEmpty && decision.reviewRequirement != .notRequired
            ? [ActionDescriptor(operationKind: .markNeedsReview, requiresReview: true)]
            : decision.actions

        for action in actions {
            let operation = operationForAction(action, decision: decision, item: item, context: context)
            conflicts.append(contentsOf: action.validationErrors)
            if action.safetyMetadata.requiresUserReview && decision.reviewRequirement == .notRequired {
                conflicts.append("Review required for \(action.operationKind.rawValue).")
            }
            if action.safetyMetadata.safetyLevel == .filesystemWrite && !operation.reversible && !action.requiresReview {
                conflicts.append("Filesystem write action \(action.operationKind.rawValue) must be reversible or require review.")
            }
            if let conflict = conflictForOperation(operation) {
                conflicts.append(conflict)
            }
            operations.append(operation)
        }

        if operations.isEmpty && graphOperations.isEmpty {
            let reviewOperation = Operation(
                kind: .markNeedsReview,
                itemURL: item.url,
                value: "No executable action was produced.",
                reversible: true
            )
            operations.append(reviewOperation)
        }

        if decision.reviewRequirement == .required && !operations.contains(where: { $0.kind == .markNeedsReview }) {
            operations.append(
                Operation(
                    kind: .markNeedsReview,
                    itemURL: item.url,
                    value: decision.reason,
                    reversible: true
                )
            )
        }

        if !conflicts.isEmpty && !operations.contains(where: { $0.kind == .markNeedsReview }) {
            operations.append(
                Operation(
                    kind: .markNeedsReview,
                    itemURL: item.url,
                    value: conflicts.joined(separator: "; "),
                    reversible: true
                )
            )
        }

        let reversible = operations.allSatisfy(\.reversible) && graphOperations.allSatisfy(\.reversible)
        let expectedResultURL = operations.last(where: { $0.destinationURL != nil })?.destinationURL

        return OperationPlan(
            operations: operations,
            graphOperations: graphOperations,
            expectedResultURL: expectedResultURL,
            conflicts: conflicts,
            reversible: reversible,
            previewText: previewText(
                for: operations,
                graphOperations: graphOperations,
                item: item,
                conflicts: conflicts,
                decision: decision
            )
        )
    }

    private func operationForAction(
        _ action: ActionDescriptor,
        decision: RouteDecision,
        item: ItemProfile,
        context: PlanningContext
    ) -> Operation {
        switch action.operationKind {
        case .move, .copy:
            return Operation(
                kind: action.operationKind,
                itemURL: item.url,
                destinationURL: destinationURL(for: action, decision: decision, item: item, context: context),
                reversible: true
            )
        case .rename:
            let newName = action.parameters["name"] ?? action.parameters["newName"] ?? item.displayName
            return Operation(
                kind: .rename,
                itemURL: item.url,
                destinationURL: item.url.deletingLastPathComponent().appendingPathComponent(newName),
                value: newName,
                reversible: true
            )
        case .addTags, .removeTags:
            return Operation(
                kind: action.operationKind,
                itemURL: item.url,
                value: action.parameters["tags"],
                reversible: true
            )
        case .createFolder:
            let destination = action.parameters["destination"]
                .map { URL(fileURLWithPath: $0) }
                ?? decision.destinationURL
                ?? context.libraryRootURL
            return Operation(
                kind: .createFolder,
                itemURL: item.url,
                destinationURL: destination,
                reversible: true
            )
        case .markNeedsReview:
            return Operation(
                kind: .markNeedsReview,
                itemURL: item.url,
                value: action.parameters["reason"] ?? decision.reason,
                reversible: true
            )
        case .indexInPlace:
            return Operation(kind: .indexInPlace, itemURL: item.url, reversible: true)
        case .open, .revealInFinder:
            return Operation(kind: action.operationKind, itemURL: item.url, reversible: false)
        }
    }

    private func destinationURL(
        for action: ActionDescriptor,
        decision: RouteDecision,
        item: ItemProfile,
        context: PlanningContext
    ) -> URL? {
        if let rawDestination = action.parameters["destination"] {
            return destinationURL(rawDestination, item: item)
        }

        if let decisionDestination = decision.destinationURL {
            return decisionDestination.hasDirectoryPath
                ? decisionDestination.appendingPathComponent(item.displayName)
                : decisionDestination
        }

        if let libraryRootURL = context.libraryRootURL {
            return libraryRootURL.appendingPathComponent(item.displayName)
        }

        return nil
    }

    private func destinationURL(_ rawDestination: String, item: ItemProfile) -> URL {
        let url = URL(fileURLWithPath: rawDestination)
        if rawDestination.hasSuffix("/") || url.hasDirectoryPath {
            return url.appendingPathComponent(item.displayName)
        }
        return url
    }

    private func conflictForOperation(_ operation: Operation) -> String? {
        guard let destinationURL = operation.destinationURL else {
            return nil
        }

        guard operation.kind == .move ||
            operation.kind == .copy ||
            operation.kind == .rename ||
            operation.kind == .createFolder
        else {
            return nil
        }

        guard conflictChecker.itemExists(at: destinationURL) else {
            return nil
        }

        return "Destination already exists: \(destinationURL.path)"
    }

    private func previewText(
        for operations: [Operation],
        graphOperations: [GraphOperation],
        item: ItemProfile,
        conflicts: [String],
        decision: RouteDecision
    ) -> String {
        if !conflicts.isEmpty {
            return "Review required for \(item.displayName): \(conflicts.joined(separator: "; "))"
        }

        let operationSummaries = operations.map { operation in
            switch operation.kind {
            case .move:
                "Move \(item.displayName) to \(operation.destinationURL?.path ?? "unknown destination")"
            case .copy:
                "Copy \(item.displayName) to \(operation.destinationURL?.path ?? "unknown destination")"
            case .rename:
                "Rename \(item.displayName) to \(operation.value ?? operation.destinationURL?.lastPathComponent ?? "new name")"
            case .addTags:
                "Add tags to \(item.displayName)"
            case .removeTags:
                "Remove tags from \(item.displayName)"
            case .createFolder:
                "Create folder \(operation.destinationURL?.path ?? "unknown destination")"
            case .markNeedsReview:
                "Mark \(item.displayName) as needs review"
            case .indexInPlace:
                "Index \(item.displayName) in place"
            case .open:
                "Open \(item.displayName)"
            case .revealInFinder:
                "Reveal \(item.displayName) in Finder"
            }
        }
        let graphSummaries = graphOperations.map { operation in
            switch operation.kind {
            case .addToCollection:
                "Add \(item.displayName) to collection \(operation.parameters["collectionName"] ?? operation.parameters["collectionID"] ?? "unknown")"
            case .addTopic:
                "Add topic \(operation.parameters["topic"] ?? "unknown") to \(item.displayName)"
            case .addPerson:
                "Add person \(operation.parameters["person"] ?? "unknown") to \(item.displayName)"
            case .addProject:
                "Add project \(operation.parameters["project"] ?? "unknown") to \(item.displayName)"
            case .addRelationship:
                "Add relationship \(operation.parameters["predicate"] ?? "related") for \(item.displayName)"
            }
        }
        let summaries = operationSummaries + graphSummaries

        if decision.reviewRequirement == .recommended {
            return "Review recommended: \(summaries.joined(separator: "; "))"
        }

        return summaries.joined(separator: "; ")
    }
}
