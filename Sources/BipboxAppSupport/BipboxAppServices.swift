import BipboxAI
import BipboxCore
import BipboxMacOSAdapters
import BipboxPersistence
import Foundation

public final class BipboxAppServices {
    public let paths: BipboxRuntimePaths
    public let workflow: Workflow
    public let workflowConfiguration: RuntimeWorkflowConfiguration
    public let inspector: ItemInspector
    public let aiOrchestrator: AIOrchestrator
    public let workflowEngine: WorkflowEngine
    public let planner: OperationPlanner
    public let executor: OperationExecutor
    public let searchService: SearchService
    public let knowledgeStore: KnowledgeStore
    public let knowledgeGraphService: KnowledgeGraphService
    public let relatednessService: RelatednessService
    public let retrievalService: RetrievalService
    public let missingFileRecoveryService: MissingFileRecoveryService
    public let relatedContextService: RelatedContextService
    public let coldStartScanner: ColdStartScanner
    public let metadataExtractionService: MetadataExtractionService
    public let ruleStore: JSONRuleDocumentStore
    public let activityLog: ActivityLog
    public let permissionStore: PermissionStore
    public let sourceStore: SourceStore
    public let sourceLifecycleCoordinator: SourceLifecycleCoordinating
    public let appSettingsStore: AppSettingsStore
    public let toolRegistry: DefaultToolRegistry
    public let mcpToolAdapter: MCPToolMetadataAdapter
    public let watchFolderAutomation: WatchFolderAutomationService
    public let pipeline: DefaultOrganizationPipeline
    public let intakeService: IntakeService
    public let dropIntakeHandler: DropIntakeHandling
    public let vectorIndex: VectorIndex
    public let embedder: TextEmbedder

    public init(
        paths: BipboxRuntimePaths,
        workflow: Workflow,
        workflowConfiguration: RuntimeWorkflowConfiguration,
        inspector: ItemInspector,
        aiOrchestrator: AIOrchestrator,
        workflowEngine: WorkflowEngine,
        planner: OperationPlanner,
        executor: OperationExecutor,
        searchService: SearchService,
        knowledgeStore: KnowledgeStore,
        knowledgeGraphService: KnowledgeGraphService,
        relatednessService: RelatednessService,
        retrievalService: RetrievalService,
        missingFileRecoveryService: MissingFileRecoveryService,
        relatedContextService: RelatedContextService,
        coldStartScanner: ColdStartScanner,
        metadataExtractionService: MetadataExtractionService,
        ruleStore: JSONRuleDocumentStore,
        activityLog: ActivityLog,
        permissionStore: PermissionStore,
        sourceStore: SourceStore,
        sourceLifecycleCoordinator: SourceLifecycleCoordinating,
        appSettingsStore: AppSettingsStore,
        toolRegistry: DefaultToolRegistry,
        mcpToolAdapter: MCPToolMetadataAdapter,
        watchFolderAutomation: WatchFolderAutomationService,
        pipeline: DefaultOrganizationPipeline,
        intakeService: IntakeService,
        dropIntakeHandler: DropIntakeHandling,
        vectorIndex: VectorIndex,
        embedder: TextEmbedder
    ) {
        self.paths = paths
        self.workflow = workflow
        self.workflowConfiguration = workflowConfiguration
        self.inspector = inspector
        self.aiOrchestrator = aiOrchestrator
        self.workflowEngine = workflowEngine
        self.planner = planner
        self.executor = executor
        self.searchService = searchService
        self.knowledgeStore = knowledgeStore
        self.knowledgeGraphService = knowledgeGraphService
        self.relatednessService = relatednessService
        self.retrievalService = retrievalService
        self.missingFileRecoveryService = missingFileRecoveryService
        self.relatedContextService = relatedContextService
        self.coldStartScanner = coldStartScanner
        self.metadataExtractionService = metadataExtractionService
        self.ruleStore = ruleStore
        self.activityLog = activityLog
        self.permissionStore = permissionStore
        self.sourceStore = sourceStore
        self.sourceLifecycleCoordinator = sourceLifecycleCoordinator
        self.appSettingsStore = appSettingsStore
        self.toolRegistry = toolRegistry
        self.mcpToolAdapter = mcpToolAdapter
        self.watchFolderAutomation = watchFolderAutomation
        self.pipeline = pipeline
        self.intakeService = intakeService
        self.dropIntakeHandler = dropIntakeHandler
        self.vectorIndex = vectorIndex
        self.embedder = embedder
    }

    public static func makeDefault(
        paths: BipboxRuntimePaths? = nil,
        workflow: Workflow? = nil,
        fileManager: FileManager = .default
    ) throws -> BipboxAppServices {
        let runtimePaths = try paths ?? BipboxRuntimePaths(
            baseDirectoryURL: BipboxRuntimePaths.defaultBaseDirectory(fileManager: fileManager)
        )
        try runtimePaths.createRequiredDirectories(fileManager: fileManager)

        let inspector = FileSystemItemInspector(fileManager: fileManager)
        let activityLog = try JSONLinesActivityLog(directoryURL: runtimePaths.activityLogDirectoryURL)
        let searchService = try SQLiteSearchIndex(directoryURL: runtimePaths.searchIndexDirectoryURL)
        let knowledgeStore = try SQLiteKnowledgeStore(directoryURL: runtimePaths.knowledgeStoreDirectoryURL)
        let knowledgeGraphService = DefaultKnowledgeGraphService(store: knowledgeStore)
        let relatednessService = DefaultHybridRelatednessService(
            knowledgeStore: knowledgeStore,
            searchService: searchService,
            graphService: knowledgeGraphService
        )
        // Semantic layer: on-device embeddings + SQLite vector index. Gated by
        // BIPBOX_SEMANTIC (default on); set to "0" to A/B against lexical-only.
        let vectorIndex = try SQLiteVectorIndex(directoryURL: runtimePaths.vectorIndexDirectoryURL)
        let embedder = NLEmbeddingTextEmbedder()
        let semanticEnabled = ProcessInfo.processInfo.environment["BIPBOX_SEMANTIC"] != "0"
        let semanticWeight = semanticEnabled ? 0.6 : 0
        let retrievalService = DefaultRetrievalService(
            searchService: searchService,
            knowledgeStore: knowledgeStore,
            graphService: knowledgeGraphService,
            vectorIndex: vectorIndex,
            embedder: embedder,
            semanticWeight: semanticWeight
        )
        let missingFileRecoveryService = DefaultMissingFileRecoveryService(
            knowledgeStore: knowledgeStore,
            searchService: searchService,
            searchRemover: searchService
        )
        let relatedContextService = DefaultRelatedContextService(
            graphService: knowledgeGraphService,
            relatednessService: relatednessService
        )
        let metadataExtractionService = DefaultMetadataExtractionService(fileManager: fileManager)
        let ruleStore = try JSONRuleDocumentStore(directoryURL: runtimePaths.rulesDirectoryURL)
        let permissionStore = try SecurityScopedBookmarkPermissionStore(
            directoryURL: runtimePaths.permissionsDirectoryURL
        )
        let sourceStore = try JSONSourceStore(directoryURL: runtimePaths.sourcesDirectoryURL)
        let coldStartScanner = DefaultColdStartScanner(
            permissionStore: permissionStore,
            inspector: inspector,
            knowledgeStore: knowledgeStore,
            searchService: searchService,
            metadataExtractionService: metadataExtractionService,
            activityLog: activityLog,
            vectorIndex: semanticEnabled ? vectorIndex : nil,
            embedder: semanticEnabled ? embedder : nil,
            fileManager: fileManager
        )
        let appSettingsStore = try JSONAppSettingsStore(directoryURL: runtimePaths.settingsDirectoryURL)
        let toolRegistry = DefaultToolRegistry()
        let mcpToolAdapter = PlaceholderMCPToolMetadataAdapter()
        let selectedWorkflow = workflow ?? Self.initialWorkflow(ruleStore: ruleStore, runtimePaths: runtimePaths)
        let workflowConfiguration = RuntimeWorkflowConfiguration(workflow: selectedWorkflow)
        let aiOrchestrator = ToolBackedAIOrchestrator(
            classifier: NoModelAIGateway(),
            toolRegistry: toolRegistry,
            activityLog: activityLog
        )
        let workflowEngine = DefaultWorkflowEngine(aiOrchestrator: aiOrchestrator)
        let planner = DefaultOperationPlanner(conflictChecker: FileManagerPathConflictChecker(fileManager: fileManager))
        let executor = FileSystemOperationExecutor(fileManager: fileManager)

        let pipeline = DefaultOrganizationPipeline(
            inspector: inspector,
            workflowEngine: workflowEngine,
            planner: planner,
            executor: executor,
            searchService: searchService,
            knowledgeStore: knowledgeStore,
            knowledgeGraphService: knowledgeGraphService,
            metadataExtractionService: metadataExtractionService,
            activityLog: activityLog
        )
        let intakeService = PipelineIntakeService(pipeline: pipeline) {
            OrganizationPipelineConfiguration(
                workflow: workflowConfiguration.workflow,
                planningContext: PlanningContext(libraryRootURL: runtimePaths.defaultLibraryRootURL, now: Date()),
                executionContext: ExecutionContext(dryRun: false, actor: "app"),
                now: Date()
            )
        }
        let dropIntakeHandler = DefaultDropIntakeHandler(
            intakeService: intakeService,
            itemInspector: inspector,
            sourceStore: sourceStore
        )
        let watchFolderAutomation = WatchFolderAutomationService(
            permissionStore: permissionStore,
            sourceStore: sourceStore,
            intakeService: intakeService,
            appSettingsStore: appSettingsStore
        )
        let sourceLifecycleCoordinator = DefaultSourceLifecycleCoordinator(
            permissionStore: permissionStore,
            sourceStore: sourceStore,
            scanner: coldStartScanner,
            watcherReloader: watchFolderAutomation
        )
        try Self.registerBuiltInTools(
            toolRegistry: toolRegistry,
            ruleStore: ruleStore,
            workflowConfiguration: workflowConfiguration,
            searchService: searchService,
            knowledgeStore: knowledgeStore,
            knowledgeGraphService: knowledgeGraphService,
            relatednessService: relatednessService,
            retrievalService: retrievalService,
            sourceStore: sourceStore,
            sourceLifecycleCoordinator: sourceLifecycleCoordinator,
            activityLog: activityLog
        )

        return BipboxAppServices(
            paths: runtimePaths,
            workflow: selectedWorkflow,
            workflowConfiguration: workflowConfiguration,
            inspector: inspector,
            aiOrchestrator: aiOrchestrator,
            workflowEngine: workflowEngine,
            planner: planner,
            executor: executor,
            searchService: searchService,
            knowledgeStore: knowledgeStore,
            knowledgeGraphService: knowledgeGraphService,
            relatednessService: relatednessService,
            retrievalService: retrievalService,
            missingFileRecoveryService: missingFileRecoveryService,
            relatedContextService: relatedContextService,
            coldStartScanner: coldStartScanner,
            metadataExtractionService: metadataExtractionService,
            ruleStore: ruleStore,
            activityLog: activityLog,
            permissionStore: permissionStore,
            sourceStore: sourceStore,
            sourceLifecycleCoordinator: sourceLifecycleCoordinator,
            appSettingsStore: appSettingsStore,
            toolRegistry: toolRegistry,
            mcpToolAdapter: mcpToolAdapter,
            watchFolderAutomation: watchFolderAutomation,
            pipeline: pipeline,
            intakeService: intakeService,
            dropIntakeHandler: dropIntakeHandler,
            vectorIndex: vectorIndex,
            embedder: embedder
        )
    }

    private static func initialWorkflow(ruleStore: JSONRuleDocumentStore, runtimePaths: BipboxRuntimePaths) -> Workflow {
        do {
            let documents = try ruleStore.loadRulesSync()
            if !documents.isEmpty {
                return Workflow.fromRuleDocuments(documents)
            }
        } catch {
            return DefaultWorkflowFactory.extensionRouter(libraryRootURL: runtimePaths.defaultLibraryRootURL)
        }

        return DefaultWorkflowFactory.extensionRouter(libraryRootURL: runtimePaths.defaultLibraryRootURL)
    }

    private static func registerBuiltInTools(
        toolRegistry: DefaultToolRegistry,
        ruleStore: JSONRuleDocumentStore,
        workflowConfiguration: RuntimeWorkflowConfiguration,
        searchService: SearchService,
        knowledgeStore: KnowledgeStore,
        knowledgeGraphService: KnowledgeGraphService,
        relatednessService: RelatednessService,
        retrievalService: RetrievalService,
        sourceStore: SourceStore,
        sourceLifecycleCoordinator: SourceLifecycleCoordinating,
        activityLog: ActivityLog
    ) throws {
        try KnowledgeToolRegistrar.register(
            toolRegistry: toolRegistry,
            ruleStore: ruleStore,
            workflowConfiguration: workflowConfiguration,
            searchService: searchService,
            knowledgeStore: knowledgeStore,
            knowledgeGraphService: knowledgeGraphService,
            relatednessService: relatednessService,
            retrievalService: retrievalService,
            sourceStore: sourceStore,
            sourceLifecycleCoordinator: sourceLifecycleCoordinator,
            activityLog: activityLog
        )
    }
}

public final class RuntimeWorkflowConfiguration: @unchecked Sendable {
    private let lock = NSLock()
    private var currentWorkflow: Workflow

    public init(workflow: Workflow) {
        currentWorkflow = workflow
    }

    public var workflow: Workflow {
        get {
            lock.lock()
            defer { lock.unlock() }
            return currentWorkflow
        }
        set {
            lock.lock()
            currentWorkflow = newValue
            lock.unlock()
        }
    }
}
