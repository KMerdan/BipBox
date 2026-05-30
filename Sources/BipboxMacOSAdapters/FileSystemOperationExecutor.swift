import AppKit
import BipboxCore
import Foundation

public enum FileSystemOperationError: Error, Equatable, LocalizedError {
    case planHasConflicts([String])
    case missingDestination(OperationKind)
    case itemMissing(URL)
    case destinationExists(URL)
    case unsupportedTags
    case operationFailed(OperationKind, String)

    public var errorDescription: String? {
        switch self {
        case .planHasConflicts(let conflicts):
            "Plan has unresolved conflicts: \(conflicts.joined(separator: "; "))"
        case .missingDestination(let kind):
            "Operation requires a destination: \(kind.rawValue)"
        case .itemMissing(let url):
            "Item does not exist: \(url.path)"
        case .destinationExists(let url):
            "Destination already exists: \(url.path)"
        case .unsupportedTags:
            "Finder tag operations are not supported in this build."
        case .operationFailed(let kind, let reason):
            "Operation failed: \(kind.rawValue). \(reason)"
        }
    }
}

public final class FileSystemOperationExecutor: OperationExecutor {
    private let fileManager: FileManager
    private let workspace: NSWorkspace
    private let allowOpenAndReveal: Bool

    public init(
        fileManager: FileManager = .default,
        workspace: NSWorkspace = .shared,
        allowOpenAndReveal: Bool = true
    ) {
        self.fileManager = fileManager
        self.workspace = workspace
        self.allowOpenAndReveal = allowOpenAndReveal
    }

    public func execute(_ plan: OperationPlan, context: ExecutionContext) async throws -> ExecutionResult {
        guard plan.conflicts.isEmpty else {
            throw FileSystemOperationError.planHasConflicts(plan.conflicts)
        }

        var results: [OperationExecutionResult] = []
        for operation in plan.operations {
            let result = try execute(operation, context: context)
            results.append(result)
        }

        return ExecutionResult(planID: plan.id, operationResults: results)
    }

    private func execute(_ operation: BipboxCore.Operation, context: ExecutionContext) throws -> OperationExecutionResult {
        if context.dryRun {
            return OperationExecutionResult(
                operationID: operation.id,
                status: .skipped,
                resultingURL: operation.destinationURL,
                message: "Dry run skipped \(operation.kind.rawValue).",
                undoOperation: nil
            )
        }

        switch operation.kind {
        case .move:
            return try move(operation)
        case .copy:
            return try copy(operation)
        case .rename:
            return try move(operation)
        case .createFolder:
            return try createFolder(operation)
        case .addTags:
            return try updateTags(operation, adding: true)
        case .removeTags:
            return try updateTags(operation, adding: false)
        case .markNeedsReview, .indexInPlace:
            return OperationExecutionResult(
                operationID: operation.id,
                status: .skipped,
                resultingURL: operation.itemURL,
                message: "\(operation.kind.rawValue) has no filesystem mutation.",
                undoOperation: nil
            )
        case .open:
            return try open(operation)
        case .revealInFinder:
            return try reveal(operation)
        }
    }

    private func move(_ operation: BipboxCore.Operation) throws -> OperationExecutionResult {
        let destinationURL = try requiredDestination(for: operation)
        try validateSourceExists(operation.itemURL)
        try validateDestinationAvailable(destinationURL)
        try createParentDirectory(for: destinationURL)

        do {
            try fileManager.moveItem(at: operation.itemURL, to: destinationURL)
            return OperationExecutionResult(
                operationID: operation.id,
                status: .completed,
                resultingURL: destinationURL,
                undoOperation: BipboxCore.Operation(
                    kind: .move,
                    itemURL: destinationURL,
                    destinationURL: operation.itemURL,
                    reversible: true
                )
            )
        } catch {
            throw FileSystemOperationError.operationFailed(operation.kind, error.localizedDescription)
        }
    }

    private func copy(_ operation: BipboxCore.Operation) throws -> OperationExecutionResult {
        let destinationURL = try requiredDestination(for: operation)
        try validateSourceExists(operation.itemURL)
        try validateDestinationAvailable(destinationURL)
        try createParentDirectory(for: destinationURL)

        do {
            try fileManager.copyItem(at: operation.itemURL, to: destinationURL)
            return OperationExecutionResult(
                operationID: operation.id,
                status: .completed,
                resultingURL: destinationURL,
                undoOperation: BipboxCore.Operation(
                    kind: .move,
                    itemURL: destinationURL,
                    destinationURL: operation.itemURL,
                    reversible: true
                )
            )
        } catch {
            throw FileSystemOperationError.operationFailed(.copy, error.localizedDescription)
        }
    }

    private func createFolder(_ operation: BipboxCore.Operation) throws -> OperationExecutionResult {
        let destinationURL = try requiredDestination(for: operation)
        try validateDestinationAvailable(destinationURL)

        do {
            try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
            return OperationExecutionResult(
                operationID: operation.id,
                status: .completed,
                resultingURL: destinationURL,
                undoOperation: BipboxCore.Operation(
                    kind: .move,
                    itemURL: destinationURL,
                    destinationURL: operation.itemURL,
                    reversible: true
                )
            )
        } catch {
            throw FileSystemOperationError.operationFailed(.createFolder, error.localizedDescription)
        }
    }

    private func updateTags(_ operation: BipboxCore.Operation, adding: Bool) throws -> OperationExecutionResult {
        guard #available(macOS 26.0, *) else {
            throw FileSystemOperationError.unsupportedTags
        }

        try validateSourceExists(operation.itemURL)
        let existingTags = try resourceTags(for: operation.itemURL)
        let requestedTags = parseTags(operation.value)
        let updatedTags = adding
            ? Array(Set(existingTags).union(requestedTags)).sorted()
            : existingTags.filter { !requestedTags.contains($0) }

        do {
            var resourceValues = URLResourceValues()
            resourceValues.tagNames = updatedTags
            var url = operation.itemURL
            try url.setResourceValues(resourceValues)

            return OperationExecutionResult(
                operationID: operation.id,
                status: .completed,
                resultingURL: operation.itemURL,
                undoOperation: BipboxCore.Operation(
                    kind: adding ? .removeTags : .addTags,
                    itemURL: operation.itemURL,
                    value: requestedTags.joined(separator: ","),
                    reversible: true
                )
            )
        } catch {
            throw FileSystemOperationError.operationFailed(operation.kind, error.localizedDescription)
        }
    }

    private func open(_ operation: BipboxCore.Operation) throws -> OperationExecutionResult {
        try validateSourceExists(operation.itemURL)
        guard allowOpenAndReveal else {
            return OperationExecutionResult(
                operationID: operation.id,
                status: .skipped,
                resultingURL: operation.itemURL,
                message: "Open disabled for this executor."
            )
        }

        workspace.open(operation.itemURL)
        return OperationExecutionResult(operationID: operation.id, status: .completed, resultingURL: operation.itemURL)
    }

    private func reveal(_ operation: BipboxCore.Operation) throws -> OperationExecutionResult {
        try validateSourceExists(operation.itemURL)
        guard allowOpenAndReveal else {
            return OperationExecutionResult(
                operationID: operation.id,
                status: .skipped,
                resultingURL: operation.itemURL,
                message: "Reveal disabled for this executor."
            )
        }

        workspace.activateFileViewerSelecting([operation.itemURL])
        return OperationExecutionResult(operationID: operation.id, status: .completed, resultingURL: operation.itemURL)
    }

    private func requiredDestination(for operation: BipboxCore.Operation) throws -> URL {
        guard let destinationURL = operation.destinationURL else {
            throw FileSystemOperationError.missingDestination(operation.kind)
        }
        return destinationURL
    }

    private func validateSourceExists(_ url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            throw FileSystemOperationError.itemMissing(url)
        }
    }

    private func validateDestinationAvailable(_ url: URL) throws {
        guard !fileManager.fileExists(atPath: url.path) else {
            throw FileSystemOperationError.destinationExists(url)
        }
    }

    private func createParentDirectory(for url: URL) throws {
        let parentURL = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true)
    }

    private func resourceTags(for url: URL) throws -> [String] {
        do {
            return try url.resourceValues(forKeys: [.tagNamesKey]).tagNames ?? []
        } catch {
            throw FileSystemOperationError.unsupportedTags
        }
    }

    private func parseTags(_ value: String?) -> [String] {
        (value ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
