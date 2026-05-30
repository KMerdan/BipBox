import BipboxAppSupport
import BipboxCore
import BipboxPersistence
import XCTest

final class BipboxAppServicesTests: XCTestCase {
    func testRuntimePathsCreateStorageDirectories() throws {
        let temporaryDirectory = try TemporaryDirectory()
        let paths = BipboxRuntimePaths(baseDirectoryURL: temporaryDirectory.url)

        try paths.createRequiredDirectories()

        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.searchIndexDirectoryURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.knowledgeStoreDirectoryURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.rulesDirectoryURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.activityLogDirectoryURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.permissionsDirectoryURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.settingsDirectoryURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.defaultLibraryRootURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.defaultInboxURL.path))
    }

    func testDefaultServicesCanIndexDroppedFileInPlace() async throws {
        let temporaryDirectory = try TemporaryDirectory()
        let paths = BipboxRuntimePaths(baseDirectoryURL: temporaryDirectory.url.appendingPathComponent("Runtime", isDirectory: true))
        let fileURL = try temporaryDirectory.createFile(named: "receipt.txt", contents: "coffee")
        let services = try BipboxAppServices.makeDefault(paths: paths)

        let summary = await services.dropIntakeHandler.submit(
            fileURLs: [fileURL],
            source: .dragDrop,
            mode: .indexOnly,
            receivedAt: TestClock.now
        )

        XCTAssertEqual(summary.acceptedCount, 1)
        XCTAssertFalse(summary.hasFailures)

        let searchResults = try await services.searchService.search(SearchQuery(text: "receipt"))
        XCTAssertEqual(searchResults.items.count, 1)
        XCTAssertEqual(searchResults.items.first?.currentPath, fileURL.path)
        XCTAssertEqual(searchResults.items.first?.status, .indexedOnly)
    }

    func testDefaultWorkflowStagesDroppedFolderAsSingleReviewItem() async throws {
        let temporaryDirectory = try TemporaryDirectory()
        let paths = BipboxRuntimePaths(baseDirectoryURL: temporaryDirectory.url.appendingPathComponent("Runtime", isDirectory: true))
        let folderURL = try temporaryDirectory.createFolder(named: "Client Package")
        _ = try "proposal".data(using: .utf8)?.write(to: folderURL.appendingPathComponent("proposal.txt"))
        let services = try BipboxAppServices.makeDefault(paths: paths)

        let summary = await services.dropIntakeHandler.submit(
            fileURLs: [folderURL],
            source: .dragDrop,
            mode: .organize,
            receivedAt: TestClock.now
        )

        XCTAssertEqual(summary.acceptedCount, 1)
        XCTAssertFalse(summary.hasFailures)

        let searchResults = try await services.searchService.search(
            SearchQuery(text: "Client", kinds: [.folder], statuses: [.needsReview])
        )
        XCTAssertEqual(searchResults.items.count, 1)
        XCTAssertEqual(searchResults.items.first?.kind, .folder)
        XCTAssertEqual(searchResults.items.first?.currentPath, folderURL.path)
    }

    func testExtensionRouterCanBeInjectedForAutomaticOrganization() async throws {
        let temporaryDirectory = try TemporaryDirectory()
        let paths = BipboxRuntimePaths(baseDirectoryURL: temporaryDirectory.url.appendingPathComponent("Runtime", isDirectory: true))
        let fileURL = try temporaryDirectory.createFile(named: "invoice.pdf", contents: "invoice")
        let workflow = DefaultWorkflowFactory.extensionRouter(libraryRootURL: paths.defaultLibraryRootURL)
        let services = try BipboxAppServices.makeDefault(paths: paths, workflow: workflow)

        let result = try await services.intakeService.submit(
            OrganizationRequest(
                source: .dragDrop,
                itemURL: fileURL,
                itemKind: .file,
                receivedAt: TestClock.now,
                mode: .organize
            )
        )

        XCTAssertTrue(result.accepted)
        let organizedURL = paths.defaultLibraryRootURL
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("invoice.pdf")
        XCTAssertTrue(FileManager.default.fileExists(atPath: organizedURL.path))

        let searchResults = try await services.searchService.search(SearchQuery(text: "invoice", statuses: [.organized]))
        XCTAssertEqual(searchResults.items.first?.currentPath, organizedURL.path)
    }

    func testDefaultServicesLoadWorkflowFromRuleFiles() async throws {
        let temporaryDirectory = try TemporaryDirectory()
        let paths = BipboxRuntimePaths(baseDirectoryURL: temporaryDirectory.url.appendingPathComponent("Runtime", isDirectory: true))
        try paths.createRequiredDirectories()
        let rule = RuleDocument(
            name: "Markdown Notes",
            conditions: [
                ConditionDescriptor(field: .fileExtension, operation: .equals, value: "md")
            ],
            action: RuleActionDocument(operation: .move, destinationPath: paths.defaultLibraryRootURL.path)
        )
        let store = try JSONRuleDocumentStore(directoryURL: paths.rulesDirectoryURL)
        try await store.saveRule(rule)

        let services = try BipboxAppServices.makeDefault(paths: paths)

        XCTAssertEqual(services.workflow.root.branches.first?.name, "Markdown Notes")
        XCTAssertEqual(services.workflowConfiguration.workflow.root.branches.first?.name, "Markdown Notes")
    }

    func testRulesApplyFilesToolReloadsRuntimeWorkflow() async throws {
        let temporaryDirectory = try TemporaryDirectory()
        let paths = BipboxRuntimePaths(baseDirectoryURL: temporaryDirectory.url.appendingPathComponent("Runtime", isDirectory: true))
        let services = try BipboxAppServices.makeDefault(paths: paths, workflow: Workflow(name: "Empty", root: WorkflowNode(kind: .router, name: "Root")))
        let rule = RuleDocument(
            name: "Markdown Notes",
            conditions: [
                ConditionDescriptor(field: .fileExtension, operation: .equals, value: "md")
            ],
            action: RuleActionDocument(operation: .move, destinationPath: paths.defaultLibraryRootURL.path)
        )
        try await services.ruleStore.saveRule(rule)

        let result = try await services.aiOrchestrator.callTool(
            ToolCall(
                toolName: "rules.apply_files",
                input: [:],
                requestedPermissions: [.read, .ruleWrite]
            ),
            context: ExecutionContext(actor: "test")
        )

        XCTAssertEqual(result.output["ruleCount"], "1")
        XCTAssertEqual(result.output["applied"], "true")
        XCTAssertEqual(services.workflowConfiguration.workflow.root.branches.first?.name, "Markdown Notes")
    }

    func testKnowledgeToolDescriptorsAreRegisteredWithPermissionMetadata() async throws {
        let temporaryDirectory = try TemporaryDirectory()
        let services = try BipboxAppServices.makeDefault(
            paths: BipboxRuntimePaths(baseDirectoryURL: temporaryDirectory.url.appendingPathComponent("Runtime", isDirectory: true))
        )
        let expectedToolNames = [
            "source.list",
            "source.add_watched_folder",
            "source.rescan",
            "source.pause",
            "source.resume",
            "knowledge.search",
            "knowledge.retrieve",
            "knowledge.get_item",
            "knowledge.related",
            "knowledge.add_relationship",
            "knowledge.add_collection",
            "knowledge.propose_rule",
            "rules.validate",
            "actions.simulate"
        ]

        for toolName in expectedToolNames {
            let descriptor = await services.toolRegistry.descriptor(named: toolName)
            XCTAssertNotNil(descriptor, toolName)
        }
        let writeDescriptor = await services.toolRegistry.descriptor(named: "knowledge.add_relationship")
        XCTAssertEqual(writeDescriptor?.permissions, [.read, .write])
        XCTAssertEqual(writeDescriptor?.dryRunSupported, true)
        XCTAssertEqual(writeDescriptor?.reversible, true)
    }

    func testSourceToolsUseLifecycleCoordinatorAndSupportDryRun() async throws {
        let temporaryDirectory = try TemporaryDirectory()
        let watchedFolder = try temporaryDirectory.createFolder(named: "Downloads")
        let services = try BipboxAppServices.makeDefault(
            paths: BipboxRuntimePaths(baseDirectoryURL: temporaryDirectory.url.appendingPathComponent("Runtime", isDirectory: true))
        )

        let dryRun = try await services.toolRegistry.execute(
            ToolCall(
                toolName: "source.add_watched_folder",
                input: ["path": watchedFolder.path],
                requestedPermissions: [.read, .write],
                dryRun: true
            ),
            context: ExecutionContext(dryRun: true, actor: "test")
        )
        XCTAssertEqual(dryRun.output["dryRun"], "true")
        let sourcesAfterDryRun = try await services.sourceStore.sources()
        XCTAssertTrue(sourcesAfterDryRun.isEmpty)

        let added = try await services.toolRegistry.execute(
            ToolCall(
                toolName: "source.add_watched_folder",
                input: ["path": watchedFolder.path, "displayName": "Downloads"],
                requestedPermissions: [.read, .write]
            ),
            context: ExecutionContext(actor: "test")
        )
        let sourceID = try XCTUnwrap(UUID(uuidString: try XCTUnwrap(added.output["sourceID"])))
        let listed = try await services.toolRegistry.execute(
            ToolCall(toolName: "source.list", input: ["kind": "watchedFolder"], requestedPermissions: [.read]),
            context: ExecutionContext(actor: "test")
        )

        XCTAssertEqual(listed.output["count"], "1")
        XCTAssertEqual(listed.output["source.0.id"], sourceID.uuidString)
    }

    func testKnowledgeRetrieveToolUsesRetrievalServiceExplanations() async throws {
        let temporaryDirectory = try TemporaryDirectory()
        let services = try BipboxAppServices.makeDefault(
            paths: BipboxRuntimePaths(baseDirectoryURL: temporaryDirectory.url.appendingPathComponent("Runtime", isDirectory: true))
        )
        let itemID = UUID(uuidString: "70000000-0000-0000-0000-000000000021")!
        try await services.searchService.index(
            IndexedItem(
                id: itemID,
                currentPath: "/tmp/research-note.md",
                displayName: "research-note.md",
                kind: .file,
                importedAt: TestClock.now,
                status: .indexedOnly
            )
        )

        let result = try await services.toolRegistry.execute(
            ToolCall(
                toolName: "knowledge.retrieve",
                input: ["query": "research", "kind": "file", "status": "indexedOnly"],
                requestedPermissions: [.read]
            ),
            context: ExecutionContext(actor: "test")
        )

        XCTAssertEqual(result.output["totalCount"], "1")
        XCTAssertEqual(result.output["item.0.id"], itemID.uuidString)
        XCTAssertNotNil(result.output["item.0.explanation"])
    }

    func testMCPPlaceholderAdapterIsDisabledByDefaultAndDoesNotAffectStartup() throws {
        let temporaryDirectory = try TemporaryDirectory()
        let services = try BipboxAppServices.makeDefault(
            paths: BipboxRuntimePaths(baseDirectoryURL: temporaryDirectory.url.appendingPathComponent("Runtime", isDirectory: true))
        )

        XCTAssertFalse(services.mcpToolAdapter.isEnabled)
        XCTAssertEqual(services.mcpToolAdapter.metadata(for: []), [])
    }

    func testKnowledgeSearchAndGetItemToolsReturnStructuredOutput() async throws {
        let temporaryDirectory = try TemporaryDirectory()
        let services = try BipboxAppServices.makeDefault(
            paths: BipboxRuntimePaths(baseDirectoryURL: temporaryDirectory.url.appendingPathComponent("Runtime", isDirectory: true))
        )
        let itemID = UUID(uuidString: "70000000-0000-0000-0000-000000000001")!
        try await services.searchService.index(
            IndexedItem(
                id: itemID,
                currentPath: "/tmp/invoice.pdf",
                displayName: "invoice.pdf",
                kind: .file,
                importedAt: TestClock.now,
                status: .organized
            )
        )
        try await services.knowledgeStore.upsertKnowledgeItem(
            KnowledgeItem(
                id: itemID,
                kind: .file,
                displayName: "invoice.pdf",
                currentURL: URL(fileURLWithPath: "/tmp/invoice.pdf"),
                firstSeenAt: TestClock.now,
                lastSeenAt: TestClock.now,
                state: .active
            )
        )

        let search = try await services.toolRegistry.execute(
            ToolCall(toolName: "knowledge.search", input: ["query": "invoice"], requestedPermissions: [.read]),
            context: ExecutionContext(actor: "test")
        )
        let getItem = try await services.toolRegistry.execute(
            ToolCall(toolName: "knowledge.get_item", input: ["itemID": itemID.uuidString], requestedPermissions: [.read]),
            context: ExecutionContext(actor: "test")
        )

        XCTAssertEqual(search.output["totalCount"], "1")
        XCTAssertEqual(search.output["item.0.id"], itemID.uuidString)
        XCTAssertEqual(search.output["item.0.reason"], "Matched indexed filename or searchable content.")
        XCTAssertEqual(getItem.output["found"], "true")
        XCTAssertEqual(getItem.output["state"], "active")
    }

    func testKnowledgeWriteToolsSupportDryRunBeforeMutation() async throws {
        let temporaryDirectory = try TemporaryDirectory()
        let services = try BipboxAppServices.makeDefault(
            paths: BipboxRuntimePaths(baseDirectoryURL: temporaryDirectory.url.appendingPathComponent("Runtime", isDirectory: true))
        )
        let collectionID = UUID(uuidString: "70000000-0000-0000-0000-000000000002")!

        let dryRun = try await services.toolRegistry.execute(
            ToolCall(
                toolName: "knowledge.add_collection",
                input: ["collectionID": collectionID.uuidString, "name": "Research"],
                requestedPermissions: [.read, .write],
                dryRun: true
            ),
            context: ExecutionContext(dryRun: true, actor: "test")
        )
        XCTAssertEqual(dryRun.output["dryRun"], "true")
        let dryRunCollection = try await services.knowledgeGraphService.collection(id: collectionID)
        XCTAssertNil(dryRunCollection)

        let applied = try await services.toolRegistry.execute(
            ToolCall(
                toolName: "knowledge.add_collection",
                input: ["collectionID": collectionID.uuidString, "name": "Research"],
                requestedPermissions: [.read, .write]
            ),
            context: ExecutionContext(actor: "test")
        )

        XCTAssertEqual(applied.output["dryRun"], "false")
        let appliedCollection = try await services.knowledgeGraphService.collection(id: collectionID)
        XCTAssertEqual(appliedCollection?.name, "Research")
        let activity = try await services.activityLog.recent(limit: 10)
        XCTAssertEqual(activity.last?.kind, .toolCall)
        XCTAssertEqual(activity.last?.metadata["toolName"], "knowledge.add_collection")
    }

    func testKnowledgeRelationshipToolRejectsInvalidIDsAndWritesValidatedEdge() async throws {
        let temporaryDirectory = try TemporaryDirectory()
        let services = try BipboxAppServices.makeDefault(
            paths: BipboxRuntimePaths(baseDirectoryURL: temporaryDirectory.url.appendingPathComponent("Runtime", isDirectory: true))
        )
        let itemID = UUID(uuidString: "70000000-0000-0000-0000-000000000003")!
        let contextID = UUID(uuidString: "70000000-0000-0000-0000-000000000004")!

        do {
            _ = try await services.toolRegistry.execute(
                ToolCall(
                    toolName: "knowledge.add_relationship",
                    input: ["subjectID": "not-a-uuid", "objectID": contextID.uuidString, "predicate": "belongsTo"],
                    requestedPermissions: [.read, .write]
                ),
                context: ExecutionContext(actor: "test")
            )
            XCTFail("Expected invalid input failure.")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("subjectID"))
        }

        let result = try await services.toolRegistry.execute(
            ToolCall(
                toolName: "knowledge.add_relationship",
                input: [
                    "subjectID": itemID.uuidString,
                    "objectID": contextID.uuidString,
                    "predicate": "belongsTo",
                    "objectKind": "context"
                ],
                requestedPermissions: [.read, .write]
            ),
            context: ExecutionContext(actor: "test")
        )

        XCTAssertEqual(result.output["dryRun"], "false")
        XCTAssertEqual(result.output["provenance"], "aiSuggestion")
        let relationships = try await services.knowledgeGraphService.relationships(subjectID: itemID)
        XCTAssertEqual(relationships.first?.objectID, contextID)
    }

    func testRuleProposalValidationAndActionSimulationToolsDoNotMutateState() async throws {
        let temporaryDirectory = try TemporaryDirectory()
        let services = try BipboxAppServices.makeDefault(
            paths: BipboxRuntimePaths(baseDirectoryURL: temporaryDirectory.url.appendingPathComponent("Runtime", isDirectory: true))
        )

        let proposal = try await services.toolRegistry.execute(
            ToolCall(
                toolName: "knowledge.propose_rule",
                input: ["name": "PDF", "extension": "pdf", "destination": "/tmp/PDFs"],
                requestedPermissions: [.plan],
                dryRun: true
            ),
            context: ExecutionContext(dryRun: true, actor: "test")
        )
        let validation = try await services.toolRegistry.execute(
            ToolCall(
                toolName: "rules.validate",
                input: ["json": try XCTUnwrap(proposal.output["ruleJSON"])],
                requestedPermissions: [.read, .plan],
                dryRun: true
            ),
            context: ExecutionContext(dryRun: true, actor: "test")
        )
        let simulation = try await services.toolRegistry.execute(
            ToolCall(
                toolName: "actions.simulate",
                input: ["path": "/tmp/report.pdf", "operation": "move"],
                requestedPermissions: [.plan],
                dryRun: true
            ),
            context: ExecutionContext(dryRun: true, actor: "test")
        )

        XCTAssertEqual(proposal.output["valid"], "true")
        XCTAssertEqual(validation.output["valid"], "true")
        XCTAssertEqual(simulation.output["simulated"], "true")
        XCTAssertEqual(simulation.message, "Simulation only; no filesystem operation was executed.")
    }

    func testWatchFolderAutomationSubmitsNewItemsToPipeline() async throws {
        let temporaryDirectory = try TemporaryDirectory()
        let paths = BipboxRuntimePaths(baseDirectoryURL: temporaryDirectory.url.appendingPathComponent("Runtime", isDirectory: true))
        let watchedFolderURL = try temporaryDirectory.createFolder(named: "Downloads")
        let services = try BipboxAppServices.makeDefault(paths: paths)
        _ = try await services.sourceLifecycleCoordinator.addWatchedFolder(
            SourceLifecycleRequest(
                url: watchedFolderURL,
                displayName: "Downloads",
                metadata: ["watchEnabled": "true"]
            )
        )

        let fileURL = try temporaryDirectory.createFile(named: "Downloads/report.pdf", contents: "report")
        let emittedCount = try await services.watchFolderAutomation.scanOnce(receivedAt: TestClock.now)

        XCTAssertEqual(emittedCount, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        let organizedURL = paths.defaultLibraryRootURL
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("report.pdf")
        XCTAssertTrue(FileManager.default.fileExists(atPath: organizedURL.path))
        let results = try await services.searchService.search(SearchQuery(text: "report", statuses: [.organized]))
        XCTAssertEqual(results.items.first?.currentPath, organizedURL.path)
    }

    func testWatchFolderAutomationRunsFromEnabledSources() async throws {
        let directory = try TemporaryDirectory(name: "source-backed-watch-\(UUID().uuidString)")
        let downloadsURL = try directory.createFolder(named: "Downloads")
        let disabledURL = try directory.createFolder(named: "Disabled")
        let permissionStore = MockPermissionStore()
        let sourceStore = MockSourceStore()
        let intake = MockIntakeService()
        let downloadsPermission = SourceFixtures.permissionRecord(
            id: UUID(uuidString: "66000000-0000-0000-0000-000000000001")!,
            url: downloadsURL
        )
        let disabledPermission = SourceFixtures.permissionRecord(
            id: UUID(uuidString: "66000000-0000-0000-0000-000000000002")!,
            url: disabledURL
        )
        let source = SourceFixtures.watchedFolder(
            id: UUID(uuidString: "66000000-0000-0000-0000-000000000003")!,
            url: downloadsURL,
            displayName: "Downloads",
            permissionRecordID: downloadsPermission.id,
            watchState: .stopped
        )
        let disabledSource = SourceFixtures.watchedFolder(
            id: UUID(uuidString: "66000000-0000-0000-0000-000000000004")!,
            url: disabledURL,
            displayName: "Disabled",
            permissionRecordID: disabledPermission.id,
            enabled: false,
            watchState: .stopped
        )
        try await permissionStore.save(downloadsPermission)
        try await permissionStore.save(disabledPermission)
        try await sourceStore.upsert(source)
        try await sourceStore.upsert(disabledSource)
        let automation = WatchFolderAutomationService(
            permissionStore: permissionStore,
            sourceStore: sourceStore,
            intakeService: intake,
            appSettingsStore: MockAppSettingsStore()
        )

        try await automation.reloadWatchedFolders()
        let enabledFileURL = try directory.createFile(named: "Downloads/report.pdf")
        _ = try directory.createFile(named: "Disabled/ignored.pdf")
        let emittedCount = try await automation.scanOnce(receivedAt: TestClock.now)

        let statuses = try await automation.statusSnapshot()
        let submitted = try XCTUnwrap(intake.submitted.first)
        XCTAssertEqual(emittedCount, 1)
        XCTAssertEqual(submitted.itemURL, enabledFileURL)
        XCTAssertEqual(submitted.sourceID, source.id)
        XCTAssertEqual(submitted.userContext["sourceID"], source.id.uuidString)
        XCTAssertEqual(statuses.first { $0.id == source.id }?.state, .running)
        XCTAssertEqual(statuses.first { $0.id == disabledSource.id }?.state, .stopped)
    }

    func testWatchFolderAutomationMarksSourcePermissionNeeded() async throws {
        let directory = try TemporaryDirectory(name: "source-backed-permission-\(UUID().uuidString)")
        let downloadsURL = try directory.createFolder(named: "Downloads")
        let permissionStore = MockPermissionStore()
        let sourceStore = MockSourceStore()
        let permission = SourceFixtures.permissionRecord(
            id: UUID(uuidString: "66000000-0000-0000-0000-000000000005")!,
            url: downloadsURL,
            state: .stale
        )
        let source = SourceFixtures.watchedFolder(
            id: UUID(uuidString: "66000000-0000-0000-0000-000000000006")!,
            url: downloadsURL,
            displayName: "Downloads",
            permissionRecordID: permission.id,
            watchState: .stopped
        )
        try await permissionStore.save(permission)
        try await sourceStore.upsert(source)
        let automation = WatchFolderAutomationService(
            permissionStore: permissionStore,
            sourceStore: sourceStore,
            intakeService: MockIntakeService(),
            appSettingsStore: MockAppSettingsStore()
        )

        try await automation.reloadWatchedFolders()

        let updated = try await sourceStore.source(id: source.id)
        let emittedCount = try await automation.scanOnce(receivedAt: TestClock.now)
        XCTAssertEqual(updated?.watchState, .permissionNeeded)
        XCTAssertEqual(emittedCount, 0)
    }

    func testWatchFolderAutomationConfiguresDownloadsAndDesktopCaptureSources() async throws {
        let directory = try TemporaryDirectory(name: "common-capture-\(UUID().uuidString)")
        let downloadsURL = try directory.createFolder(named: "Downloads")
        let desktopURL = try directory.createFolder(named: "Desktop")
        let permissionStore = MockPermissionStore()
        let intake = MockIntakeService()
        let automation = WatchFolderAutomationService(
            permissionStore: permissionStore,
            intakeService: intake,
            appSettingsStore: MockAppSettingsStore(),
            commonLocationURLs: [
                .downloads: downloadsURL,
                .desktop: desktopURL
            ]
        )

        try await automation.configureCommonCaptureLocation(.downloads)
        try await automation.configureCommonCaptureLocation(.desktop)
        try await automation.reloadWatchedFolders()

        let statuses = try await automation.statusSnapshot()
        XCTAssertEqual(Set(statuses.map(\.captureLocation)), [.downloads, .desktop])
        XCTAssertEqual(Set(statuses.map(\.state)), [.running])

        let fileURL = try directory.createFile(named: "Downloads/report.pdf")
        let folderURL = try directory.createFolder(named: "Desktop/Project")
        let emittedCount = try await automation.scanOnce(receivedAt: TestClock.now)

        XCTAssertEqual(emittedCount, 2)
        let submittedByPath = Dictionary(uniqueKeysWithValues: intake.submitted.map { ($0.itemURL.path, $0) })
        XCTAssertEqual(submittedByPath[fileURL.path]?.userContext["captureLocation"], "downloads")
        XCTAssertEqual(submittedByPath[fileURL.path]?.itemKind, .file)
        XCTAssertEqual(submittedByPath[folderURL.path]?.userContext["captureLocation"], "desktop")
        XCTAssertEqual(submittedByPath[folderURL.path]?.itemKind, .folder)
    }

    func testWatchFolderAutomationPauseResumeAndRemoveCommonCaptureWatchers() async throws {
        let directory = try TemporaryDirectory(name: "common-capture-control-\(UUID().uuidString)")
        let downloadsURL = try directory.createFolder(named: "Downloads")
        let permissionStore = MockPermissionStore()
        let intake = MockIntakeService()
        let automation = WatchFolderAutomationService(
            permissionStore: permissionStore,
            intakeService: intake,
            appSettingsStore: MockAppSettingsStore(),
            commonLocationURLs: [.downloads: downloadsURL]
        )

        let record = try await automation.configureCommonCaptureLocation(.downloads)
        try await automation.reloadWatchedFolders()
        await automation.pauseAll()
        _ = try directory.createFile(named: "Downloads/paused.pdf")

        let pausedCount = try await automation.scanOnce(receivedAt: TestClock.now)
        let pausedStatuses = try await automation.statusSnapshot()

        try await automation.resumeAll()
        let resumedCount = try await automation.scanOnce(receivedAt: TestClock.now)
        try await permissionStore.remove(id: record.id)
        try await automation.reloadWatchedFolders()
        _ = try directory.createFile(named: "Downloads/removed.pdf")
        let removedCount = try await automation.scanOnce(receivedAt: TestClock.now)
        let removedStatuses = try await automation.statusSnapshot()

        XCTAssertEqual(pausedCount, 0)
        XCTAssertEqual(pausedStatuses.first?.state, .paused)
        XCTAssertEqual(resumedCount, 1)
        XCTAssertEqual(removedCount, 0)
        XCTAssertEqual(removedStatuses, [])
    }
}
