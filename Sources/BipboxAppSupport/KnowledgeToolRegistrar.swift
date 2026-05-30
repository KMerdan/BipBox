import BipboxCore
import BipboxPersistence
import Foundation

enum KnowledgeToolRegistrar {
    static func register(
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
        try registerRulesApplyFiles(
            toolRegistry: toolRegistry,
            ruleStore: ruleStore,
            workflowConfiguration: workflowConfiguration,
            activityLog: activityLog
        )
        try registerSourcesList(toolRegistry: toolRegistry, sourceStore: sourceStore)
        try registerSourceAddWatchedFolder(
            toolRegistry: toolRegistry,
            sourceLifecycleCoordinator: sourceLifecycleCoordinator,
            activityLog: activityLog
        )
        try registerSourceRescan(
            toolRegistry: toolRegistry,
            sourceLifecycleCoordinator: sourceLifecycleCoordinator,
            activityLog: activityLog
        )
        try registerSourcePauseResume(
            toolRegistry: toolRegistry,
            sourceLifecycleCoordinator: sourceLifecycleCoordinator,
            activityLog: activityLog
        )
        try registerKnowledgeSearch(toolRegistry: toolRegistry, searchService: searchService)
        try registerKnowledgeRetrieve(toolRegistry: toolRegistry, retrievalService: retrievalService)
        try registerKnowledgeGetItem(toolRegistry: toolRegistry, knowledgeStore: knowledgeStore)
        try registerKnowledgeRelated(toolRegistry: toolRegistry, relatednessService: relatednessService)
        try registerKnowledgeAddRelationship(
            toolRegistry: toolRegistry,
            knowledgeGraphService: knowledgeGraphService,
            activityLog: activityLog
        )
        try registerKnowledgeAddCollection(
            toolRegistry: toolRegistry,
            knowledgeGraphService: knowledgeGraphService,
            activityLog: activityLog
        )
        try registerKnowledgeProposeRule(toolRegistry: toolRegistry)
        try registerRulesValidate(toolRegistry: toolRegistry)
        try registerActionsSimulate(toolRegistry: toolRegistry)
    }

    private static func registerRulesApplyFiles(
        toolRegistry: DefaultToolRegistry,
        ruleStore: JSONRuleDocumentStore,
        workflowConfiguration: RuntimeWorkflowConfiguration,
        activityLog: ActivityLog
    ) throws {
        try toolRegistry.registerSync(
            ToolDescriptor(
                name: "rules.apply_files",
                description: "Load rule JSON files from disk and apply them to the active workflow cache.",
                inputSchema: "{}",
                outputSchema: #"{"ruleCount":"String","applied":"String"}"#,
                permissions: [.read, .ruleWrite],
                dryRunSupported: true,
                reversible: false
            )
        ) { call, context in
            let documents = try await ruleStore.loadRules()
            if !call.dryRun {
                workflowConfiguration.workflow = Workflow.fromRuleDocuments(documents)
                try await auditToolMutation(
                    activityLog: activityLog,
                    call: call,
                    actor: context.actor,
                    message: "Applied \(documents.count) rule file(s) to the active workflow."
                )
            }
            return ToolResult(
                toolName: call.toolName,
                output: [
                    "ruleCount": "\(documents.count)",
                    "applied": call.dryRun ? "false" : "true"
                ],
                message: call.dryRun
                    ? "\(documents.count) rule file(s) are valid and ready to apply."
                    : "Applied \(documents.count) rule file(s) to the active workflow."
            )
        }
    }

    private static func registerSourcesList(
        toolRegistry: DefaultToolRegistry,
        sourceStore: SourceStore
    ) throws {
        try toolRegistry.registerSync(
            descriptor(
                name: "source.list",
                description: "List configured Bipbox capture sources and watcher/index status.",
                inputSchema: #"{"kind":"String?"}"#,
                outputSchema: #"{"count":"String","source.N.id":"String","source.N.state":"String"}"#,
                permissions: [.read],
                dryRunSupported: true
            )
        ) { call, _ in
            let kind = try optionalEnum(SourceKind.self, rawValue: call.input["kind"])
            let sources = try await sourceStore.enabledSources(kind: kind)
            var output: [String: String] = ["count": "\(sources.count)"]
            for (index, source) in sources.enumerated() {
                output["source.\(index).id"] = source.id.uuidString
                output["source.\(index).kind"] = source.kind.rawValue
                output["source.\(index).name"] = source.displayName
                output["source.\(index).path"] = source.url?.path ?? ""
                output["source.\(index).enabled"] = String(source.enabled)
                output["source.\(index).indexState"] = source.indexState.rawValue
                output["source.\(index).watchState"] = source.watchState.rawValue
            }
            return ToolResult(toolName: call.toolName, output: output)
        }
    }

    private static func registerSourceAddWatchedFolder(
        toolRegistry: DefaultToolRegistry,
        sourceLifecycleCoordinator: SourceLifecycleCoordinating,
        activityLog: ActivityLog
    ) throws {
        try toolRegistry.registerSync(
            descriptor(
                name: "source.add_watched_folder",
                description: "Add a watched folder source through the source lifecycle coordinator.",
                inputSchema: #"{"path":"String","displayName":"String?","scanNow":"String?"}"#,
                outputSchema: #"{"sourceID":"String","dryRun":"String","watchState":"String"}"#,
                permissions: [.read, .write],
                dryRunSupported: true,
                reversible: true
            )
        ) { call, context in
            let path = try requiredString(call.input["path"], name: "path")
            let url = URL(fileURLWithPath: path, isDirectory: true)
            if call.dryRun || context.dryRun {
                return ToolResult(toolName: call.toolName, output: ["dryRun": "true", "path": url.path])
            }
            let result = try await sourceLifecycleCoordinator.addWatchedFolder(
                SourceLifecycleRequest(url: url, displayName: call.input["displayName"])
            )
            if call.input["scanNow"] == "true" {
                _ = try await sourceLifecycleCoordinator.scanSource(id: result.source.id)
            }
            try await auditToolMutation(
                activityLog: activityLog,
                call: call,
                actor: context.actor,
                message: "Added watched folder source \(result.source.displayName).",
                metadata: ["sourceID": result.source.id.uuidString]
            )
            return ToolResult(
                toolName: call.toolName,
                output: [
                    "dryRun": "false",
                    "sourceID": result.source.id.uuidString,
                    "watchState": result.source.watchState.rawValue
                ],
                message: result.message
            )
        }
    }

    private static func registerSourceRescan(
        toolRegistry: DefaultToolRegistry,
        sourceLifecycleCoordinator: SourceLifecycleCoordinating,
        activityLog: ActivityLog
    ) throws {
        try toolRegistry.registerSync(
            descriptor(
                name: "source.rescan",
                description: "Run a manual scan for a configured source.",
                inputSchema: #"{"sourceID":"String"}"#,
                outputSchema: #"{"sourceID":"String","indexedCount":"String","failedCount":"String"}"#,
                permissions: [.read, .write],
                dryRunSupported: true,
                reversible: false
            )
        ) { call, context in
            let sourceID = try requiredUUID(call.input["sourceID"], name: "sourceID")
            if call.dryRun || context.dryRun {
                return ToolResult(toolName: call.toolName, output: ["dryRun": "true", "sourceID": sourceID.uuidString])
            }
            let result = try await sourceLifecycleCoordinator.scanSource(id: sourceID)
            try await auditToolMutation(
                activityLog: activityLog,
                call: call,
                actor: context.actor,
                message: "Rescanned source \(sourceID.uuidString).",
                metadata: ["sourceID": sourceID.uuidString]
            )
            return ToolResult(
                toolName: call.toolName,
                output: [
                    "dryRun": "false",
                    "sourceID": sourceID.uuidString,
                    "indexedCount": "\(result.scanResult?.scannedItemCount ?? 0)",
                    "failedCount": "\(result.scanResult?.failures.count ?? 0)"
                ],
                message: result.message
            )
        }
    }

    private static func registerSourcePauseResume(
        toolRegistry: DefaultToolRegistry,
        sourceLifecycleCoordinator: SourceLifecycleCoordinating,
        activityLog: ActivityLog
    ) throws {
        try registerSourceToggle(
            toolRegistry: toolRegistry,
            name: "source.pause",
            description: "Pause a watched folder source.",
            activityLog: activityLog
        ) { id in
            try await sourceLifecycleCoordinator.pauseSource(id: id)
        }
        try registerSourceToggle(
            toolRegistry: toolRegistry,
            name: "source.resume",
            description: "Resume a watched folder source.",
            activityLog: activityLog
        ) { id in
            try await sourceLifecycleCoordinator.resumeSource(id: id)
        }
    }

    private static func registerSourceToggle(
        toolRegistry: DefaultToolRegistry,
        name: String,
        description: String,
        activityLog: ActivityLog,
        action: @escaping @Sendable (UUID) async throws -> SourceLifecycleResult
    ) throws {
        try toolRegistry.registerSync(
            descriptor(
                name: name,
                description: description,
                inputSchema: #"{"sourceID":"String"}"#,
                outputSchema: #"{"sourceID":"String","watchState":"String"}"#,
                permissions: [.read, .write],
                dryRunSupported: true,
                reversible: true
            )
        ) { call, context in
            let sourceID = try requiredUUID(call.input["sourceID"], name: "sourceID")
            if call.dryRun || context.dryRun {
                return ToolResult(toolName: call.toolName, output: ["dryRun": "true", "sourceID": sourceID.uuidString])
            }
            let result = try await action(sourceID)
            try await auditToolMutation(
                activityLog: activityLog,
                call: call,
                actor: context.actor,
                message: "Changed source \(sourceID.uuidString) watcher state.",
                metadata: ["sourceID": sourceID.uuidString]
            )
            return ToolResult(
                toolName: call.toolName,
                output: [
                    "dryRun": "false",
                    "sourceID": sourceID.uuidString,
                    "watchState": result.source.watchState.rawValue
                ],
                message: result.message
            )
        }
    }

    private static func registerKnowledgeSearch(
        toolRegistry: DefaultToolRegistry,
        searchService: SearchService
    ) throws {
        try toolRegistry.registerSync(
            descriptor(
                name: "knowledge.search",
                description: "Search indexed Bipbox items by text.",
                inputSchema: #"{"query":"String","limit":"String?"}"#,
                outputSchema: #"{"totalCount":"String","item.N.id":"String","item.N.reason":"String"}"#,
                permissions: [.read],
                dryRunSupported: true
            )
        ) { call, _ in
            let limit = parseLimit(call.input["limit"], defaultValue: 10)
            let results = try await searchService.search(SearchQuery(text: call.input["query"] ?? "", limit: limit))
            var output: [String: String] = ["totalCount": "\(results.totalCount)"]
            for (index, item) in results.items.enumerated() {
                output["item.\(index).id"] = item.id.uuidString
                output["item.\(index).name"] = item.displayName
                output["item.\(index).path"] = item.currentPath
                output["item.\(index).kind"] = item.kind.rawValue
                output["item.\(index).status"] = item.status.rawValue
                output["item.\(index).reason"] = "Matched indexed filename or searchable content."
            }
            return ToolResult(toolName: call.toolName, output: output)
        }
    }

    private static func registerKnowledgeRetrieve(
        toolRegistry: DefaultToolRegistry,
        retrievalService: RetrievalService
    ) throws {
        try toolRegistry.registerSync(
            descriptor(
                name: "knowledge.retrieve",
                description: "Run Library retrieval with text, kind, status, and limit filters.",
                inputSchema: #"{"query":"String","kind":"String?","status":"String?","limit":"String?"}"#,
                outputSchema: #"{"totalCount":"String","item.N.id":"String","item.N.explanation":"String"}"#,
                permissions: [.read],
                dryRunSupported: true
            )
        ) { call, _ in
            let kind = try optionalEnum(ItemKind.self, rawValue: call.input["kind"])
            let status = try optionalEnum(IndexedItemStatus.self, rawValue: call.input["status"])
            let retrievalQuery = RetrievalQuery(
                text: call.input["query"] ?? "",
                kinds: kind.map { [$0] } ?? [],
                statuses: status.map { [$0] } ?? [],
                limit: parseLimit(call.input["limit"], defaultValue: 10)
            )
            let results = try await retrievalService.retrieve(retrievalQuery)
            var output: [String: String] = ["totalCount": "\(results.totalCount)"]
            for (index, item) in results.items.enumerated() {
                output["item.\(index).id"] = item.item.id.uuidString
                output["item.\(index).name"] = item.item.displayName
                output["item.\(index).path"] = item.item.currentPath
                output["item.\(index).score"] = String(format: "%.3f", item.score)
                output["item.\(index).explanation"] = item.explanations.joined(separator: " | ")
            }
            return ToolResult(toolName: call.toolName, output: output)
        }
    }

    private static func registerKnowledgeGetItem(
        toolRegistry: DefaultToolRegistry,
        knowledgeStore: KnowledgeStore
    ) throws {
        try toolRegistry.registerSync(
            descriptor(
                name: "knowledge.get_item",
                description: "Load one memory-graph item by ID.",
                inputSchema: #"{"itemID":"String"}"#,
                outputSchema: #"{"id":"String","name":"String","state":"String"}"#,
                permissions: [.read],
                dryRunSupported: true
            )
        ) { call, _ in
            let itemID = try requiredUUID(call.input["itemID"], name: "itemID")
            guard let item = try await knowledgeStore.knowledgeItem(id: itemID) else {
                return ToolResult(toolName: call.toolName, output: ["found": "false"], message: "Item was not found.")
            }
            return ToolResult(
                toolName: call.toolName,
                output: [
                    "found": "true",
                    "id": item.id.uuidString,
                    "name": item.displayName,
                    "kind": item.kind.rawValue,
                    "state": item.state.rawValue,
                    "currentPath": item.currentURL?.path ?? ""
                ]
            )
        }
    }

    private static func registerKnowledgeRelated(
        toolRegistry: DefaultToolRegistry,
        relatednessService: RelatednessService
    ) throws {
        try toolRegistry.registerSync(
            descriptor(
                name: "knowledge.related",
                description: "Find related Bipbox items with explanation strings.",
                inputSchema: #"{"itemID":"String","limit":"String?"}"#,
                outputSchema: #"{"item.N.id":"String","item.N.score":"String","item.N.explanations":"String"}"#,
                permissions: [.read],
                dryRunSupported: true
            )
        ) { call, _ in
            let itemID = try requiredUUID(call.input["itemID"], name: "itemID")
            let related = try await relatednessService.relatedItems(to: itemID, limit: parseLimit(call.input["limit"], defaultValue: 5))
            var output: [String: String] = ["count": "\(related.count)"]
            for (index, relatedItem) in related.enumerated() {
                output["item.\(index).id"] = relatedItem.item.id.uuidString
                output["item.\(index).name"] = relatedItem.item.displayName
                output["item.\(index).score"] = String(format: "%.3f", relatedItem.score)
                output["item.\(index).explanations"] = relatedItem.explanations.joined(separator: " | ")
            }
            return ToolResult(toolName: call.toolName, output: output)
        }
    }

    private static func registerKnowledgeAddRelationship(
        toolRegistry: DefaultToolRegistry,
        knowledgeGraphService: KnowledgeGraphService,
        activityLog: ActivityLog
    ) throws {
        try toolRegistry.registerSync(
            descriptor(
                name: "knowledge.add_relationship",
                description: "Add a validated relationship from a knowledge item to another graph node.",
                inputSchema: #"{"subjectID":"String","predicate":"String","objectID":"String","objectKind":"String?","confidence":"String?"}"#,
                outputSchema: #"{"relationshipID":"String","dryRun":"String"}"#,
                permissions: [.read, .write],
                dryRunSupported: true,
                reversible: true
            )
        ) { call, context in
            let subjectID = try requiredUUID(call.input["subjectID"], name: "subjectID")
            let objectID = try requiredUUID(call.input["objectID"], name: "objectID")
            let predicate = try requiredEnum(RelationshipPredicate.self, rawValue: call.input["predicate"], name: "predicate")
            let objectKind = try optionalEnum(GraphNodeKind.self, rawValue: call.input["objectKind"]) ?? .context
            let confidence = ConfidenceScore(Double(call.input["confidence"] ?? "") ?? 1)
            if call.dryRun {
                return ToolResult(toolName: call.toolName, output: ["dryRun": "true", "valid": "true"])
            }
            let edge = try await knowledgeGraphService.relate(
                subjectID: subjectID,
                subjectKind: .knowledgeItem,
                predicate: predicate,
                objectID: objectID,
                objectKind: objectKind,
                confidence: confidence,
                provenance: .aiSuggestion,
                now: Date()
            )
            try await auditToolMutation(
                activityLog: activityLog,
                call: call,
                actor: context.actor,
                message: "Added knowledge relationship \(edge.id.uuidString).",
                metadata: ["relationshipID": edge.id.uuidString, "subjectID": subjectID.uuidString]
            )
            return ToolResult(
                toolName: call.toolName,
                output: ["dryRun": "false", "relationshipID": edge.id.uuidString, "provenance": edge.provenance.rawValue]
            )
        }
    }

    private static func registerKnowledgeAddCollection(
        toolRegistry: DefaultToolRegistry,
        knowledgeGraphService: KnowledgeGraphService,
        activityLog: ActivityLog
    ) throws {
        try toolRegistry.registerSync(
            descriptor(
                name: "knowledge.add_collection",
                description: "Create a collection and optionally add one item.",
                inputSchema: #"{"name":"String","collectionID":"String?","itemID":"String?"}"#,
                outputSchema: #"{"collectionID":"String","dryRun":"String"}"#,
                permissions: [.read, .write],
                dryRunSupported: true,
                reversible: true
            )
        ) { call, context in
            let name = try requiredString(call.input["name"], name: "name")
            let collectionID = call.input["collectionID"].flatMap(UUID.init(uuidString:)) ?? UUID()
            let itemID = call.input["itemID"].flatMap(UUID.init(uuidString:))
            if call.input["itemID"] != nil && itemID == nil {
                throw KnowledgeToolError.invalidInput("itemID must be a valid UUID.")
            }
            if call.dryRun {
                return ToolResult(toolName: call.toolName, output: ["dryRun": "true", "collectionID": collectionID.uuidString, "name": name])
            }
            let now = Date()
            try await knowledgeGraphService.upsertCollection(
                KnowledgeCollection(
                    id: collectionID,
                    name: name,
                    kind: .manual,
                    manualMembershipAllowed: true,
                    createdBy: .user,
                    createdAt: now,
                    updatedAt: now
                )
            )
            if let itemID {
                try await knowledgeGraphService.addItem(itemID, toCollection: collectionID, createdAt: now)
            }
            try await auditToolMutation(
                activityLog: activityLog,
                call: call,
                actor: context.actor,
                message: "Created or updated collection \(name).",
                metadata: ["collectionID": collectionID.uuidString]
            )
            return ToolResult(toolName: call.toolName, output: ["dryRun": "false", "collectionID": collectionID.uuidString, "name": name])
        }
    }

    private static func registerKnowledgeProposeRule(toolRegistry: DefaultToolRegistry) throws {
        try toolRegistry.registerSync(
            descriptor(
                name: "knowledge.propose_rule",
                description: "Create a JSON rule proposal without applying it.",
                inputSchema: #"{"name":"String","extension":"String","destination":"String"}"#,
                outputSchema: #"{"ruleJSON":"String","valid":"String"}"#,
                permissions: [.plan],
                dryRunSupported: true
            )
        ) { call, _ in
            let name = try requiredString(call.input["name"], name: "name")
            let fileExtension = try requiredString(call.input["extension"], name: "extension").lowercased()
            let destination = try requiredString(call.input["destination"], name: "destination")
            guard !destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw KnowledgeToolError.invalidInput("destination cannot be empty.")
            }
            let rule = RuleDocument(
                name: name,
                conditions: [ConditionDescriptor(field: .fileExtension, operation: .equals, value: fileExtension)],
                action: RuleActionDocument(operation: .move, destinationPath: destination)
            )
            return ToolResult(
                toolName: call.toolName,
                output: ["valid": "true", "ruleJSON": try encodeRule(rule)]
            )
        }
    }

    private static func registerRulesValidate(toolRegistry: DefaultToolRegistry) throws {
        try toolRegistry.registerSync(
            descriptor(
                name: "rules.validate",
                description: "Validate one rule JSON document without saving or applying it.",
                inputSchema: #"{"json":"String"}"#,
                outputSchema: #"{"valid":"String","ruleID":"String"}"#,
                permissions: [.read, .plan],
                dryRunSupported: true
            )
        ) { call, _ in
            let json = try requiredString(call.input["json"], name: "json")
            let rule = try JSONDecoder().decode(RuleDocument.self, from: Data(json.utf8))
            return ToolResult(toolName: call.toolName, output: ["valid": "true", "ruleID": rule.id.uuidString, "name": rule.name])
        }
    }

    private static func registerActionsSimulate(toolRegistry: DefaultToolRegistry) throws {
        try toolRegistry.registerSync(
            descriptor(
                name: "actions.simulate",
                description: "Validate that an action request can only be simulated through the planner boundary.",
                inputSchema: #"{"path":"String","operation":"String?"}"#,
                outputSchema: #"{"simulated":"String","safe":"String"}"#,
                permissions: [.plan],
                dryRunSupported: true
            )
        ) { call, _ in
            let path = try requiredString(call.input["path"], name: "path")
            let operation = call.input["operation"] ?? OperationKind.move.rawValue
            _ = try requiredEnum(OperationKind.self, rawValue: operation, name: "operation")
            return ToolResult(
                toolName: call.toolName,
                output: ["simulated": "true", "safe": "true", "path": path, "operation": operation],
                message: "Simulation only; no filesystem operation was executed."
            )
        }
    }

    private static func descriptor(
        name: String,
        description: String,
        inputSchema: String,
        outputSchema: String,
        permissions: [ToolPermission],
        dryRunSupported: Bool,
        reversible: Bool = false
    ) -> ToolDescriptor {
        ToolDescriptor(
            name: name,
            description: description,
            inputSchema: inputSchema,
            outputSchema: outputSchema,
            permissions: permissions,
            dryRunSupported: dryRunSupported,
            reversible: reversible
        )
    }

    private static func auditToolMutation(
        activityLog: ActivityLog,
        call: ToolCall,
        actor: String,
        message: String,
        metadata: [String: String] = [:]
    ) async throws {
        var eventMetadata = metadata
        eventMetadata["toolName"] = call.toolName
        eventMetadata["actor"] = actor
        eventMetadata["dryRun"] = String(call.dryRun)
        try await activityLog.append(
            ActivityEvent(
                kind: .toolCall,
                message: message,
                occurredAt: Date(),
                metadata: eventMetadata
            )
        )
    }

    private static func parseLimit(_ rawValue: String?, defaultValue: Int) -> Int {
        max(1, min(50, Int(rawValue ?? "") ?? defaultValue))
    }

    private static func requiredString(_ value: String?, name: String) throws -> String {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw KnowledgeToolError.invalidInput("\(name) is required.")
        }
        return value
    }

    private static func requiredUUID(_ value: String?, name: String) throws -> UUID {
        guard let value, let uuid = UUID(uuidString: value) else {
            throw KnowledgeToolError.invalidInput("\(name) must be a valid UUID.")
        }
        return uuid
    }

    private static func requiredEnum<T: RawRepresentable>(_ type: T.Type, rawValue: String?, name: String) throws -> T where T.RawValue == String {
        guard let rawValue, let value = T(rawValue: rawValue) else {
            throw KnowledgeToolError.invalidInput("\(name) is invalid.")
        }
        return value
    }

    private static func optionalEnum<T: RawRepresentable>(_ type: T.Type, rawValue: String?) throws -> T? where T.RawValue == String {
        guard let rawValue, !rawValue.isEmpty else { return nil }
        guard let value = T(rawValue: rawValue) else {
            throw KnowledgeToolError.invalidInput("\(rawValue) is invalid.")
        }
        return value
    }

    private static func encodeRule(_ rule: RuleDocument) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(data: try encoder.encode(rule), encoding: .utf8) ?? "{}"
    }
}

enum KnowledgeToolError: Error, Equatable, LocalizedError {
    case invalidInput(String)

    var errorDescription: String? {
        switch self {
        case .invalidInput(let message):
            message
        }
    }
}
