import BipboxCore
import XCTest

final class DomainModelCodableTests: XCTestCase {
    func testOrganizationRequestRoundTripsThroughJSON() throws {
        let request = OrganizationRequest(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            source: .dragDrop,
            itemURL: URL(fileURLWithPath: "/tmp/report.pdf"),
            itemKind: .file,
            receivedAt: Date(timeIntervalSince1970: 1_800_000_000),
            mode: .organize,
            userContext: ["origin": "test"]
        )

        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(OrganizationRequest.self, from: data)

        XCTAssertEqual(decoded, request)
    }

    func testFolderCanBeRepresentedWithoutChildExpansion() throws {
        let profile = ItemProfile(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            url: URL(fileURLWithPath: "/tmp/Project"),
            kind: .folder,
            displayName: "Project",
            folderChildSummary: FolderChildSummary(
                visibleChildCount: 3,
                visibleFileCount: 2,
                visibleFolderCount: 1,
                topLevelExtensions: ["pdf": 1, "png": 1],
                recursiveInspectionRequested: false
            )
        )

        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(ItemProfile.self, from: data)

        XCTAssertEqual(decoded.kind, .folder)
        XCTAssertEqual(decoded.folderChildSummary?.visibleChildCount, 3)
        XCTAssertEqual(decoded.folderChildSummary?.recursiveInspectionRequested, false)
    }

    func testRecursiveFolderProcessingIsExplicitOnActions() {
        let action = ActionDescriptor(
            operationKind: .move,
            parameters: ["destination": "/tmp/Library/Projects"],
            recursiveFolderProcessing: false
        )

        XCTAssertFalse(action.recursiveFolderProcessing)
    }

    func testActionSafetyMetadataAndValidation() {
        let move = ActionDescriptor(operationKind: .move, parameters: ["destination": "/tmp/Library"])
        let invalidMove = ActionDescriptor(operationKind: .move)
        let open = ActionDescriptor(operationKind: .open)

        XCTAssertEqual(move.safetyMetadata.safetyLevel, .filesystemWrite)
        XCTAssertTrue(move.safetyMetadata.reversible)
        XCTAssertTrue(move.safetyMetadata.dryRunSupported)
        XCTAssertTrue(move.isValid)
        XCTAssertEqual(invalidMove.validationErrors, ["destination is required for move."])
        XCTAssertEqual(open.safetyMetadata.safetyLevel, .externalInteraction)
        XCTAssertFalse(open.safetyMetadata.reversible)
        XCTAssertTrue(open.safetyMetadata.requiresUserReview)
    }

    func testGraphActionSafetyMetadataAndContextValidation() {
        let topic = GraphActionDescriptor(kind: .addTopic, parameters: ["topic": "research"])
        let person = GraphActionDescriptor(kind: .addPerson, parameters: ["person": "Ada"])
        let project = GraphActionDescriptor(kind: .addProject, parameters: ["project": "Launch"])
        let invalidRelationship = GraphActionDescriptor(kind: .addRelationship)

        XCTAssertEqual(topic.safetyMetadata.safetyLevel, .memoryOnly)
        XCTAssertTrue(topic.safetyMetadata.reversible)
        XCTAssertTrue(topic.safetyMetadata.dryRunSupported)
        XCTAssertTrue(person.isValid)
        XCTAssertTrue(project.isValid)
        XCTAssertEqual(invalidRelationship.validationErrors, ["predicate is required for addRelationship."])
    }

    func testWorkflowRoundTripsThroughJSON() throws {
        let stop = WorkflowNode(kind: .stop, name: "Done")
        let branch = WorkflowBranch(
            name: "Folders",
            conditions: [
                ConditionDescriptor(field: .itemKind, operation: .equals, value: "folder")
            ],
            node: stop
        )
        let root = WorkflowNode(kind: .router, name: "Root", branches: [branch])
        let workflow = Workflow(name: "Default", root: root)

        let data = try JSONEncoder().encode(workflow)
        let decoded = try JSONDecoder().decode(Workflow.self, from: data)

        XCTAssertEqual(decoded, workflow)
    }

    func testRuleDocumentGraphActionsRoundTripAndBuildWorkflowBranch() throws {
        let graphAction = GraphActionDocument(
            kind: .addTopic,
            parameters: ["topic": "research"]
        )
        let rule = RuleDocument(
            name: "Research Notes",
            conditions: [
                ConditionDescriptor(field: .filename, operation: .contains, value: "research")
            ],
            action: RuleActionDocument(operation: .indexInPlace),
            graphActions: [graphAction]
        )

        let data = try JSONEncoder().encode(rule)
        let decoded = try JSONDecoder().decode(RuleDocument.self, from: data)
        let branch = decoded.workflowBranch

        XCTAssertEqual(decoded, rule)
        XCTAssertEqual(branch.node.actions.map(\.operationKind), [.indexInPlace])
        XCTAssertEqual(branch.node.graphActions?.map(\.kind), [.addTopic])
    }

    func testRuleDocumentDecodesLegacyJSONWithoutGraphActions() throws {
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000030",
          "schemaVersion": 1,
          "name": "Legacy PDF",
          "enabled": true,
          "position": 0,
          "conditions": [],
          "action": {
            "operation": "move",
            "destinationPath": "/tmp/PDFs",
            "parameters": {},
            "requiresReview": false,
            "recursiveFolderProcessing": false
          }
        }
        """

        let decoded = try JSONDecoder().decode(RuleDocument.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.name, "Legacy PDF")
        XCTAssertEqual(decoded.graphActions, [])
    }

    func testKnowledgeItemRoundTripsThroughJSON() throws {
        let item = KnowledgeItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
            kind: .file,
            displayName: "invoice.pdf",
            sourceID: UUID(uuidString: "00000000-0000-0000-0000-000000000099")!,
            currentURL: URL(fileURLWithPath: "/tmp/invoice.pdf"),
            originalURL: URL(fileURLWithPath: "/Users/example/Downloads/invoice.pdf"),
            bookmarkID: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
            contentFingerprint: "abc123",
            filesystemIdentity: "dev:1-inode:2",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_100),
            firstSeenAt: Date(timeIntervalSince1970: 1_800_000_000),
            lastSeenAt: Date(timeIntervalSince1970: 1_800_000_100),
            state: .active
        )

        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(KnowledgeItem.self, from: data)

        XCTAssertEqual(decoded, item)
    }

    func testCaptureEventDraftPreservesRequestContext() {
        let request = OrganizationRequest(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000012")!,
            source: .watchedFolder,
            itemURL: URL(fileURLWithPath: "/Users/example/Downloads/report.pdf"),
            itemKind: .file,
            receivedAt: TestClock.now,
            mode: .review,
            userContext: ["watchFolder": "Downloads"]
        )
        let itemID = UUID(uuidString: "00000000-0000-0000-0000-000000000013")!
        let sessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000014")!

        let event = CaptureEvent.draft(
            from: request,
            itemID: itemID,
            sessionID: sessionID,
            sourceDetail: request.userContext
        )

        XCTAssertEqual(event.itemID, itemID)
        XCTAssertEqual(event.source, .watchedFolder)
        XCTAssertEqual(event.sourceDetail, ["watchFolder": "Downloads"])
        XCTAssertEqual(event.receivedAt, TestClock.now)
        XCTAssertEqual(event.sessionID, sessionID)
        XCTAssertEqual(event.rawURL, request.itemURL)
        XCTAssertEqual(event.requestedMode, .review)
    }

    func testKnowledgeItemDraftUsesProfileIdentityAndRequestTiming() {
        let request = ItemFixtures.request(
            url: URL(fileURLWithPath: "/Users/example/Downloads/report.pdf"),
            kind: .file
        )
        let profile = ItemProfile(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000015")!,
            url: URL(fileURLWithPath: "/Users/example/Downloads/report.pdf"),
            kind: .file,
            displayName: "report.pdf",
            fileExtension: "pdf",
            uniformTypeIdentifier: "com.adobe.pdf",
            sizeBytes: 42,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_001),
            source: .dragDrop,
            contentHash: "hash"
        )

        let item = KnowledgeItem.draft(from: request, profile: profile, state: .needsReview)

        XCTAssertEqual(item.id, profile.id)
        XCTAssertEqual(item.kind, .file)
        XCTAssertEqual(item.displayName, "report.pdf")
        XCTAssertEqual(item.currentURL, profile.url)
        XCTAssertEqual(item.originalURL, request.itemURL)
        XCTAssertEqual(item.contentFingerprint, "hash")
        XCTAssertEqual(item.firstSeenAt, request.receivedAt)
        XCTAssertEqual(item.lastSeenAt, request.receivedAt)
        XCTAssertEqual(item.state, .needsReview)
    }

    func testSourceAwareCaptureEventDraftLinksSourceRecord() {
        let sourceID = UUID(uuidString: "00000000-0000-0000-0000-000000000040")!
        let permissionID = UUID(uuidString: "00000000-0000-0000-0000-000000000041")!
        let source = SourceRecord.watchedFolder(
            id: sourceID,
            url: URL(fileURLWithPath: "/Users/example/Downloads", isDirectory: true),
            permissionRecordID: permissionID,
            createdAt: TestClock.now,
            metadata: ["captureLocation": "downloads"]
        )
        let request = OrganizationRequest(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000042")!,
            source: .automation,
            itemURL: URL(fileURLWithPath: "/Users/example/Downloads/report.pdf"),
            itemKind: .file,
            receivedAt: TestClock.now,
            mode: .indexOnly,
            userContext: ["session": "initial-scan"]
        ).associated(with: source)
        let itemID = UUID(uuidString: "00000000-0000-0000-0000-000000000043")!
        let event = CaptureEvent.draft(
            from: request,
            sourceRecord: source,
            itemID: itemID,
            sourceDetail: ["scan": "manual"]
        )

        XCTAssertEqual(request.source, .watchedFolder)
        XCTAssertEqual(request.sourceID, sourceID)
        XCTAssertEqual(request.userContext["sourceID"], sourceID.uuidString)
        XCTAssertEqual(event.itemID, itemID)
        XCTAssertEqual(event.source, .watchedFolder)
        XCTAssertEqual(event.sourceID, sourceID)
        XCTAssertEqual(event.sourceDetail["permissionRecordID"], permissionID.uuidString)
        XCTAssertEqual(event.sourceDetail["captureLocation"], "downloads")
        XCTAssertEqual(event.sourceDetail["session"], "initial-scan")
        XCTAssertEqual(event.sourceDetail["scan"], "manual")
    }

    func testKnowledgeItemDraftPreservesSourceIDAndRecoveryStates() {
        let sourceID = UUID(uuidString: "00000000-0000-0000-0000-000000000044")!
        let request = OrganizationRequest(
            source: .watchedFolder,
            sourceID: sourceID,
            itemURL: URL(fileURLWithPath: "/Users/example/Downloads/missing.pdf"),
            itemKind: .file,
            receivedAt: TestClock.now,
            mode: .indexOnly
        )
        let profile = ItemProfile(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000045")!,
            url: request.itemURL,
            kind: .file,
            displayName: "missing.pdf"
        )

        let missing = KnowledgeItem.draft(from: request, profile: profile, state: .missing)
        let permissionNeeded = KnowledgeItem.draft(from: request, profile: profile, state: .permissionNeeded)

        XCTAssertEqual(missing.sourceID, sourceID)
        XCTAssertEqual(missing.state, .missing)
        XCTAssertEqual(permissionNeeded.sourceID, sourceID)
        XCTAssertEqual(permissionNeeded.state, .permissionNeeded)
    }

    func testFolderKnowledgeItemDraftDoesNotExpandChildren() {
        let folderURL = URL(fileURLWithPath: "/Users/example/Downloads/Project")
        let request = ItemFixtures.request(url: folderURL, kind: .folder)
        let profile = ItemFixtures.folderProfile(url: folderURL)

        let item = KnowledgeItem.draft(from: request, profile: profile)
        let event = CaptureEvent.draft(from: request, itemID: item.id)

        XCTAssertEqual(item.kind, .folder)
        XCTAssertEqual(item.displayName, "Project")
        XCTAssertEqual(event.rawURL, folderURL)
        XCTAssertEqual(event.itemID, profile.id)
    }

    func testGraphRecordsRoundTripThroughJSON() throws {
        let itemID = UUID(uuidString: "00000000-0000-0000-0000-000000000016")!
        let contextID = UUID(uuidString: "00000000-0000-0000-0000-000000000017")!
        let now = TestClock.now
        let context = ContextNode(
            id: contextID,
            kind: .project,
            name: "Bipbox",
            confidence: ConfidenceScore(0.75),
            provenance: .existingFolderScan,
            createdAt: now,
            updatedAt: now
        )
        let relationship = RelationshipEdge(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000018")!,
            subjectID: itemID,
            subjectKind: .knowledgeItem,
            predicate: .belongsTo,
            objectID: contextID,
            objectKind: .context,
            confidence: ConfidenceScore(0.8),
            provenance: .captureSession,
            createdAt: now,
            updatedAt: now
        )
        let collection = KnowledgeCollection(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000019")!,
            name: "Research",
            kind: .manual,
            query: nil,
            manualMembershipAllowed: true,
            createdBy: .user,
            createdAt: now,
            updatedAt: now
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        XCTAssertEqual(try decoder.decode(ContextNode.self, from: encoder.encode(context)), context)
        XCTAssertEqual(
            try decoder.decode(RelationshipEdge.self, from: encoder.encode(relationship)),
            relationship
        )
        XCTAssertEqual(
            try decoder.decode(KnowledgeCollection.self, from: encoder.encode(collection)),
            collection
        )
    }

    func testConfidenceScoreClampsToStorageRange() {
        XCTAssertEqual(ConfidenceScore(-1).rawValue, 0)
        XCTAssertEqual(ConfidenceScore(0.4).rawValue, 0.4)
        XCTAssertEqual(ConfidenceScore(2).rawValue, 1)
    }

    func testOneKnowledgeItemCanBelongToMultipleContexts() {
        let itemID = UUID(uuidString: "00000000-0000-0000-0000-000000000020")!
        let projectID = UUID(uuidString: "00000000-0000-0000-0000-000000000021")!
        let topicID = UUID(uuidString: "00000000-0000-0000-0000-000000000022")!
        let now = TestClock.now

        let projectEdge = RelationshipEdge(
            subjectID: itemID,
            subjectKind: .knowledgeItem,
            predicate: .belongsTo,
            objectID: projectID,
            objectKind: .context,
            provenance: .user,
            createdAt: now,
            updatedAt: now
        )
        let topicEdge = RelationshipEdge(
            subjectID: itemID,
            subjectKind: .knowledgeItem,
            predicate: .hasTopic,
            objectID: topicID,
            objectKind: .context,
            confidence: ConfidenceScore(0.6),
            provenance: .metadataExtraction,
            createdAt: now,
            updatedAt: now
        )

        XCTAssertEqual(projectEdge.subjectID, topicEdge.subjectID)
        XCTAssertNotEqual(projectEdge.objectID, topicEdge.objectID)
        XCTAssertEqual(projectEdge.predicate, .belongsTo)
        XCTAssertEqual(topicEdge.predicate, .hasTopic)
    }
}
