import Foundation

public final class PassthroughItemStabilizer: ItemStabilizer {
    public init() {}

    public func waitUntilStable(_ request: OrganizationRequest) async throws -> OrganizationRequest {
        request
    }
}

public final class DefaultOrganizationPipeline {
    private let stabilizer: ItemStabilizer
    private let inspector: ItemInspector
    private let workflowEngine: WorkflowEngine
    private let planner: OperationPlanner
    private let executor: OperationExecutor
    private let searchService: SearchService
    private let knowledgeStore: KnowledgeStore?
    private let knowledgeGraphService: KnowledgeGraphService?
    private let metadataExtractionService: MetadataExtractionService?
    private let activityLog: ActivityLog

    public init(
        stabilizer: ItemStabilizer = PassthroughItemStabilizer(),
        inspector: ItemInspector,
        workflowEngine: WorkflowEngine,
        planner: OperationPlanner,
        executor: OperationExecutor,
        searchService: SearchService,
        knowledgeStore: KnowledgeStore? = nil,
        knowledgeGraphService: KnowledgeGraphService? = nil,
        metadataExtractionService: MetadataExtractionService? = nil,
        activityLog: ActivityLog
    ) {
        self.stabilizer = stabilizer
        self.inspector = inspector
        self.workflowEngine = workflowEngine
        self.planner = planner
        self.executor = executor
        self.searchService = searchService
        self.knowledgeStore = knowledgeStore
        self.knowledgeGraphService = knowledgeGraphService
        self.metadataExtractionService = metadataExtractionService
        self.activityLog = activityLog
    }

    public func process(
        _ request: OrganizationRequest,
        configuration: OrganizationPipelineConfiguration
    ) async -> OrganizationPipelineResult {
        var capturedItemProfile: ItemProfile?
        do {
            try await log(.requestReceived, request: request, message: "Organization request received.", now: configuration.now)

            let stableRequest = try await stabilizer.waitUntilStable(request)
            let inspectedProfile = try await inspector.inspect(stableRequest, options: configuration.inspectionOptions)
            let itemProfile = await enrichWithExtractedMetadata(inspectedProfile)
                .mergingRequestContext(stableRequest)
            capturedItemProfile = itemProfile
            try await recordCapture(request: stableRequest, item: itemProfile, state: .active)
            try await log(
                .inspected,
                request: stableRequest,
                item: itemProfile,
                message: "Inspected \(itemProfile.displayName).",
                now: configuration.now
            )

            if stableRequest.mode == .indexOnly {
                try await updateKnowledgeState(request: stableRequest, item: itemProfile, state: .active)
                let indexedItem = makeIndexedItem(
                    item: itemProfile,
                    request: stableRequest,
                    status: .indexedOnly,
                    currentPath: itemProfile.url.path,
                    originalPath: nil,
                    now: configuration.now
                )
                try await searchService.index(indexedItem)
                try await log(
                    .indexed,
                    request: stableRequest,
                    item: itemProfile,
                    message: "Indexed \(itemProfile.displayName) in place.",
                    now: configuration.now
                )
                return OrganizationPipelineResult(
                    status: .indexedOnly,
                    request: stableRequest,
                    itemProfile: itemProfile,
                    indexedItem: indexedItem,
                    message: "Indexed item in place."
                )
            }

            let decision = try await workflowEngine.evaluate(
                workflow: configuration.workflow,
                item: itemProfile,
                context: WorkflowEvaluationContext(
                    mode: stableRequest.mode,
                    now: configuration.now,
                    sourceID: stableRequest.sourceID,
                    sourceFacts: stableRequest.userContext
                )
            )
            try await log(
                .routed,
                request: stableRequest,
                item: itemProfile,
                message: decision.reason,
                now: configuration.now
            )

            let plan = try await planner.plan(
                decision: decision,
                item: itemProfile,
                context: configuration.planningContext
            )
            try await log(
                .planned,
                request: stableRequest,
                item: itemProfile,
                plan: plan,
                message: plan.previewText,
                now: configuration.now
            )

            if stableRequest.mode == .simulate {
                return OrganizationPipelineResult(
                    status: .simulated,
                    request: stableRequest,
                    itemProfile: itemProfile,
                    decision: decision,
                    plan: plan,
                    message: "Simulated organization plan."
                )
            }

            if stableRequest.mode == .review ||
                decision.reviewRequirement == .required ||
                !plan.conflicts.isEmpty ||
                plan.operations.contains(where: { $0.kind == .markNeedsReview }) {
                try await applySafeGraphOperations(
                    plan.graphOperations,
                    request: stableRequest,
                    item: itemProfile,
                    now: configuration.now
                )
                try await updateKnowledgeState(request: stableRequest, item: itemProfile, state: .needsReview)
                let indexedItem = makeIndexedItem(
                    item: itemProfile,
                    request: stableRequest,
                    status: .needsReview,
                    currentPath: itemProfile.url.path,
                    originalPath: nil,
                    now: configuration.now
                )
                try await searchService.index(indexedItem)
                try await log(
                    .indexed,
                    request: stableRequest,
                    item: itemProfile,
                    plan: plan,
                    message: "Staged \(itemProfile.displayName) for review.",
                    now: configuration.now
                )
                return OrganizationPipelineResult(
                    status: .stagedForReview,
                    request: stableRequest,
                    itemProfile: itemProfile,
                    decision: decision,
                    plan: plan,
                    indexedItem: indexedItem,
                    message: "Item staged for review."
                )
            }

            let preActionIndexedItem = makeIndexedItem(
                item: itemProfile,
                request: stableRequest,
                status: .indexedOnly,
                currentPath: itemProfile.url.path,
                originalPath: nil,
                now: configuration.now
            )
            try await searchService.index(preActionIndexedItem)
            try await log(
                .indexed,
                request: stableRequest,
                item: itemProfile,
                plan: plan,
                message: "Indexed \(itemProfile.displayName) before applying actions.",
                now: configuration.now
            )

            let executionResult = try await executor.execute(plan, context: configuration.executionContext)
            try await applySafeGraphOperations(
                plan.graphOperations,
                request: stableRequest,
                item: itemProfile,
                now: configuration.now
            )
            try await updateKnowledgeState(request: stableRequest, item: itemProfile, state: .active)
            try await log(
                .executed,
                request: stableRequest,
                item: itemProfile,
                plan: plan,
                message: "Executed organization plan.",
                now: configuration.now,
                undoOperation: firstUndoOperation(from: executionResult)
            )

            let indexedItem = makeIndexedItem(
                item: itemProfile,
                request: stableRequest,
                status: .organized,
                currentPath: executionResult.operationResults.first(where: { $0.resultingURL != nil })?.resultingURL?.path
                    ?? plan.expectedResultURL?.path
                    ?? itemProfile.url.path,
                originalPath: itemProfile.url.path,
                now: configuration.now
            )
            try await searchService.update(indexedItem)
            try await log(
                .indexed,
                request: stableRequest,
                item: itemProfile,
                plan: plan,
                message: "Indexed organized item.",
                now: configuration.now
            )

            return OrganizationPipelineResult(
                status: .organized,
                request: stableRequest,
                itemProfile: itemProfile,
                decision: decision,
                plan: plan,
                executionResult: executionResult,
                indexedItem: indexedItem,
                message: "Item organized."
            )
        } catch {
            if let capturedItemProfile {
                try? await updateKnowledgeState(request: request, item: capturedItemProfile, state: .failed)
                let failedItem = makeIndexedItem(
                    item: capturedItemProfile,
                    request: request,
                    status: .failed,
                    currentPath: capturedItemProfile.url.path,
                    originalPath: nil,
                    now: configuration.now
                )
                try? await searchService.update(failedItem)
            }
            try? await log(
                .failed,
                request: request,
                message: "Organization failed: \(error.localizedDescription)",
                now: configuration.now
            )
            return OrganizationPipelineResult(
                status: .failed,
                request: request,
                message: error.localizedDescription
            )
        }
    }

    private func recordCapture(
        request: OrganizationRequest,
        item: ItemProfile,
        state: KnowledgeItemState
    ) async throws {
        guard let knowledgeStore else { return }
        let knowledgeItem = KnowledgeItem.draft(from: request, profile: item, state: state)
        let captureEvent = CaptureEvent.draft(
            from: request,
            itemID: knowledgeItem.id,
            sessionID: captureSessionID(from: request)
        )
        try await knowledgeStore.upsertKnowledgeItem(knowledgeItem)
        try await knowledgeStore.appendCaptureEvent(captureEvent)
        if !item.metadata.isEmpty {
            try await knowledgeStore.upsertMetadataSnapshot(
                itemID: item.id,
                metadata: item.metadata,
                capturedAt: request.receivedAt
            )
        }
    }

    private func enrichWithExtractedMetadata(_ item: ItemProfile) async -> ItemProfile {
        guard let metadataExtractionService else {
            return item
        }

        do {
            let result = try await metadataExtractionService.extractMetadata(for: item)
            var enriched = item
            enriched.metadata.merge(result.metadata) { _, new in new }
            if !result.warnings.isEmpty {
                enriched.metadata["metadata.extraction.warnings"] = result.warnings.joined(separator: " | ")
            }
            return enriched
        } catch {
            var enriched = item
            enriched.metadata["metadata.extraction.error"] = error.localizedDescription
            return enriched
        }
    }

    private func updateKnowledgeState(
        request: OrganizationRequest,
        item: ItemProfile,
        state: KnowledgeItemState
    ) async throws {
        guard let knowledgeStore else { return }
        var knowledgeItem = KnowledgeItem.draft(from: request, profile: item, state: state)
        if let existing = try await knowledgeStore.knowledgeItem(id: item.id) {
            knowledgeItem.firstSeenAt = existing.firstSeenAt
            knowledgeItem.bookmarkID = existing.bookmarkID
            knowledgeItem.filesystemIdentity = existing.filesystemIdentity
        }
        try await knowledgeStore.upsertKnowledgeItem(knowledgeItem)
    }

    private func captureSessionID(from request: OrganizationRequest) -> UUID {
        request.userContext["captureSessionID"].flatMap(UUID.init(uuidString:)) ?? request.id
    }

    private func applySafeGraphOperations(
        _ operations: [GraphOperation],
        request: OrganizationRequest,
        item: ItemProfile,
        now: Date
    ) async throws {
        guard let knowledgeGraphService else { return }
        for operation in operations where !operation.requiresReview {
            try await applyGraphOperation(operation, graphService: knowledgeGraphService, now: now)
            try await log(
                .relationshipRecorded,
                request: request,
                item: item,
                message: "Applied memory action \(operation.kind.rawValue).",
                now: now
            )
        }
    }

    private func applyGraphOperation(
        _ operation: GraphOperation,
        graphService: KnowledgeGraphService,
        now: Date
    ) async throws {
        switch operation.kind {
        case .addToCollection:
            let collectionID = operation.parameters["collectionID"].flatMap(UUID.init(uuidString:)) ?? UUID()
            let collectionName = operation.parameters["collectionName"] ?? "Rule Collection"
            let collection = KnowledgeCollection(
                id: collectionID,
                name: collectionName,
                kind: .ruleBacked,
                manualMembershipAllowed: true,
                createdBy: .rule,
                createdAt: now,
                updatedAt: now
            )
            try await graphService.upsertCollection(collection)
            try await graphService.addItem(operation.itemID, toCollection: collectionID, createdAt: now)
        case .addTopic, .addPerson, .addProject:
            let contextID = operation.parameters["contextID"].flatMap(UUID.init(uuidString:)) ?? UUID()
            let contextKind: ContextKind
            let contextName: String
            let predicate: RelationshipPredicate
            switch operation.kind {
            case .addTopic:
                contextKind = .topic
                contextName = operation.parameters["topic"] ?? operation.parameters["name"] ?? "untitled"
                predicate = .hasTopic
            case .addPerson:
                contextKind = .person
                contextName = operation.parameters["person"] ?? operation.parameters["name"] ?? "untitled"
                predicate = .mentionsPerson
            case .addProject:
                contextKind = .project
                contextName = operation.parameters["project"] ?? operation.parameters["name"] ?? "untitled"
                predicate = .belongsTo
            default:
                contextKind = .topic
                contextName = "untitled"
                predicate = .hasTopic
            }
            let context = ContextNode(
                id: contextID,
                kind: contextKind,
                name: contextName,
                confidence: ConfidenceScore(1),
                provenance: .rule,
                createdAt: now,
                updatedAt: now
            )
            try await graphService.upsertContext(context)
            _ = try await graphService.relate(
                subjectID: operation.itemID,
                subjectKind: .knowledgeItem,
                predicate: predicate,
                objectID: contextID,
                objectKind: .context,
                confidence: ConfidenceScore(1),
                provenance: .rule,
                now: now
            )
        case .addRelationship:
            guard
                let objectID = operation.parameters["objectID"].flatMap(UUID.init(uuidString:)),
                let objectKind = operation.parameters["objectKind"].flatMap(GraphNodeKind.init(rawValue:)),
                let predicate = operation.parameters["predicate"].flatMap(RelationshipPredicate.init(rawValue:))
            else {
                throw GraphOperationExecutionError.invalidRelationshipParameters
            }
            _ = try await graphService.relate(
                subjectID: operation.itemID,
                subjectKind: .knowledgeItem,
                predicate: predicate,
                objectID: objectID,
                objectKind: objectKind,
                confidence: ConfidenceScore(Double(operation.parameters["confidence"] ?? "") ?? 1),
                provenance: .rule,
                now: now
            )
        }
    }

    private func makeIndexedItem(
        item: ItemProfile,
        request: OrganizationRequest,
        status: IndexedItemStatus,
        currentPath: String,
        originalPath: String?,
        now: Date
    ) -> IndexedItem {
        var tags = item.finderTags
        if let sourceID = request.sourceID {
            tags.append("source:\(sourceID.uuidString)")
        }
        if let sourceKind = request.userContext["sourceKind"] {
            tags.append(sourceKind)
        }
        if let captureSource = request.userContext["captureSource"] {
            tags.append(captureSource)
        }
        return IndexedItem(
            id: item.id,
            currentPath: currentPath,
            originalPath: originalPath,
            displayName: item.displayName,
            kind: item.kind,
            uniformTypeIdentifier: item.uniformTypeIdentifier,
            sizeBytes: item.sizeBytes,
            createdAt: item.createdAt,
            modifiedAt: item.modifiedAt,
            importedAt: request.receivedAt,
            routedAt: now,
            ruleID: nil,
            tags: Array(Set(tags)).sorted(),
            extractedText: item.extractedTextSummary,
            status: status
        )
    }

    private func firstUndoOperation(from result: ExecutionResult) -> Operation? {
        result.operationResults.lazy.compactMap(\.undoOperation).first
    }

    private func log(
        _ kind: ActivityEventKind,
        request: OrganizationRequest,
        item: ItemProfile? = nil,
        plan: OperationPlan? = nil,
        message: String,
        now: Date,
        undoOperation: Operation? = nil
    ) async throws {
        try await activityLog.append(
            ActivityEvent(
                kind: kind,
                itemID: item?.id,
                requestID: request.id,
                planID: plan?.id,
                sourceID: request.sourceID,
                message: message,
                occurredAt: now,
                undoOperation: undoOperation,
                metadata: item?.metadata ?? request.userContext
            )
        )
    }
}

private extension ItemProfile {
    func mergingRequestContext(_ request: OrganizationRequest) -> ItemProfile {
        var metadata = self.metadata
        metadata.merge(request.userContext) { existing, _ in existing }
        if let sourceID = request.sourceID {
            metadata["sourceID"] = sourceID.uuidString
        }
        if metadata["sourceKind"] == nil {
            metadata["sourceKind"] = request.source.rawValue
        }
        return ItemProfile(
            id: id,
            url: url,
            kind: kind,
            displayName: displayName,
            fileExtension: fileExtension,
            uniformTypeIdentifier: uniformTypeIdentifier,
            sizeBytes: sizeBytes,
            createdAt: createdAt,
            modifiedAt: modifiedAt,
            source: source ?? request.source,
            finderTags: finderTags,
            contentHash: contentHash,
            folderChildSummary: folderChildSummary,
            extractedTextSummary: extractedTextSummary,
            metadata: metadata
        )
    }
}

public enum GraphOperationExecutionError: Error, Equatable, LocalizedError {
    case invalidRelationshipParameters

    public var errorDescription: String? {
        switch self {
        case .invalidRelationshipParameters:
            "Graph relationship operation requires objectID, objectKind, and predicate parameters."
        }
    }
}
