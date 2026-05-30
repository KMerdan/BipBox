import BipboxCore
import BipboxMacOSAdapters
import XCTest

final class FileSystemOperationExecutorTests: XCTestCase {
    func testMovesFileAndReturnsUndoOperation() async throws {
        let directory = try TemporaryDirectory(name: "executor-move-file-\(UUID().uuidString)")
        let sourceURL = try directory.createFile(named: "report.txt", contents: "report")
        let destinationURL = directory.url.appendingPathComponent("Organized/report.txt")
        let operation = Operation(kind: .move, itemURL: sourceURL, destinationURL: destinationURL, reversible: true)
        let plan = OperationPlan(
            operations: [operation],
            expectedResultURL: destinationURL,
            reversible: true,
            previewText: "Move file"
        )

        let result = try await FileSystemOperationExecutor(allowOpenAndReveal: false).execute(
            plan,
            context: ExecutionContext(actor: "test")
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationURL.path))
        XCTAssertEqual(result.operationResults.first?.status, .completed)
        XCTAssertEqual(result.operationResults.first?.undoOperation?.itemURL, destinationURL)
        XCTAssertEqual(result.operationResults.first?.undoOperation?.destinationURL, sourceURL)
    }

    func testMovesFolderAsOneObjectAndPreservesChildren() async throws {
        let directory = try TemporaryDirectory(name: "executor-move-folder-\(UUID().uuidString)")
        let folderURL = try directory.createFolder(named: "Project")
        let childURL = folderURL.appendingPathComponent("inside.txt")
        try "child".data(using: .utf8)?.write(to: childURL)
        let destinationURL = directory.url.appendingPathComponent("Organized/Project")
        let operation = Operation(kind: .move, itemURL: folderURL, destinationURL: destinationURL, reversible: true)
        let plan = OperationPlan(
            operations: [operation],
            expectedResultURL: destinationURL,
            reversible: true,
            previewText: "Move folder"
        )

        let result = try await FileSystemOperationExecutor(allowOpenAndReveal: false).execute(
            plan,
            context: ExecutionContext(actor: "test")
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: folderURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationURL.appendingPathComponent("inside.txt").path))
        XCTAssertEqual(result.operationResults.count, 1)
        XCTAssertEqual(result.operationResults.first?.resultingURL, destinationURL)
    }

    func testCopyFileLeavesSourceInPlace() async throws {
        let directory = try TemporaryDirectory(name: "executor-copy-file-\(UUID().uuidString)")
        let sourceURL = try directory.createFile(named: "report.txt", contents: "report")
        let destinationURL = directory.url.appendingPathComponent("Copies/report.txt")
        let operation = Operation(kind: .copy, itemURL: sourceURL, destinationURL: destinationURL, reversible: true)
        let plan = OperationPlan(
            operations: [operation],
            expectedResultURL: destinationURL,
            reversible: true,
            previewText: "Copy file"
        )

        let result = try await FileSystemOperationExecutor(allowOpenAndReveal: false).execute(
            plan,
            context: ExecutionContext(actor: "test")
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationURL.path))
        XCTAssertEqual(result.operationResults.first?.status, .completed)
    }

    func testRenameItemUsesMoveOperation() async throws {
        let directory = try TemporaryDirectory(name: "executor-rename-\(UUID().uuidString)")
        let sourceURL = try directory.createFile(named: "draft.txt", contents: "draft")
        let destinationURL = directory.url.appendingPathComponent("final.txt")
        let operation = Operation(kind: .rename, itemURL: sourceURL, destinationURL: destinationURL, value: "final.txt", reversible: true)
        let plan = OperationPlan(
            operations: [operation],
            expectedResultURL: destinationURL,
            reversible: true,
            previewText: "Rename file"
        )

        let result = try await FileSystemOperationExecutor(allowOpenAndReveal: false).execute(
            plan,
            context: ExecutionContext(actor: "test")
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationURL.path))
        XCTAssertEqual(result.operationResults.first?.undoOperation?.destinationURL, sourceURL)
    }

    func testConflictFailureDoesNotMutateFilesystem() async throws {
        let directory = try TemporaryDirectory(name: "executor-conflict-\(UUID().uuidString)")
        let sourceURL = try directory.createFile(named: "report.txt", contents: "source")
        let destinationURL = try directory.createFile(named: "existing.txt", contents: "existing")
        let operation = Operation(kind: .move, itemURL: sourceURL, destinationURL: destinationURL, reversible: true)
        let plan = OperationPlan(
            operations: [operation],
            expectedResultURL: destinationURL,
            reversible: true,
            previewText: "Move file"
        )

        do {
            _ = try await FileSystemOperationExecutor(allowOpenAndReveal: false).execute(
                plan,
                context: ExecutionContext(actor: "test")
            )
            XCTFail("Expected destination conflict failure.")
        } catch let error as FileSystemOperationError {
            XCTAssertEqual(error, .destinationExists(destinationURL))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertEqual(try String(contentsOf: destinationURL), "existing")
    }

    func testPlanConflictsFailBeforeExecutingOperations() async throws {
        let directory = try TemporaryDirectory(name: "executor-plan-conflict-\(UUID().uuidString)")
        let sourceURL = try directory.createFile(named: "report.txt")
        let destinationURL = directory.url.appendingPathComponent("report-moved.txt")
        let operation = Operation(kind: .move, itemURL: sourceURL, destinationURL: destinationURL, reversible: true)
        let plan = OperationPlan(
            operations: [operation],
            expectedResultURL: destinationURL,
            conflicts: ["Destination already exists"],
            reversible: true,
            previewText: "Move file"
        )

        do {
            _ = try await FileSystemOperationExecutor(allowOpenAndReveal: false).execute(
                plan,
                context: ExecutionContext(actor: "test")
            )
            XCTFail("Expected plan conflict failure.")
        } catch let error as FileSystemOperationError {
            XCTAssertEqual(error, .planHasConflicts(["Destination already exists"]))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destinationURL.path))
    }

    func testDryRunSkipsMutation() async throws {
        let directory = try TemporaryDirectory(name: "executor-dry-run-\(UUID().uuidString)")
        let sourceURL = try directory.createFile(named: "report.txt", contents: "report")
        let destinationURL = directory.url.appendingPathComponent("Organized/report.txt")
        let operation = Operation(kind: .move, itemURL: sourceURL, destinationURL: destinationURL, reversible: true)
        let plan = OperationPlan(
            operations: [operation],
            expectedResultURL: destinationURL,
            reversible: true,
            previewText: "Move file"
        )

        let result = try await FileSystemOperationExecutor(allowOpenAndReveal: false).execute(
            plan,
            context: ExecutionContext(dryRun: true, actor: "test")
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destinationURL.path))
        XCTAssertEqual(result.operationResults.first?.status, .skipped)
    }

    func testOpenAndRevealCanBeDisabledForTests() async throws {
        let directory = try TemporaryDirectory(name: "executor-open-reveal-\(UUID().uuidString)")
        let sourceURL = try directory.createFile(named: "report.txt")
        let plan = OperationPlan(
            operations: [
                Operation(kind: .open, itemURL: sourceURL, reversible: false),
                Operation(kind: .revealInFinder, itemURL: sourceURL, reversible: false)
            ],
            reversible: false,
            previewText: "Open and reveal"
        )

        let result = try await FileSystemOperationExecutor(allowOpenAndReveal: false).execute(
            plan,
            context: ExecutionContext(actor: "test")
        )

        XCTAssertEqual(result.operationResults.map(\.status), [.skipped, .skipped])
    }
}

