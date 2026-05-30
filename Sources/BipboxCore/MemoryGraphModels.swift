import Foundation

public struct ConfidenceScore: Codable, Equatable, Comparable, Sendable {
    public var rawValue: Double

    public init(_ rawValue: Double) {
        self.rawValue = Self.clamped(rawValue)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(Double.self)
        guard rawValue.isFinite else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Confidence score must be finite."
            )
        }
        self.rawValue = Self.clamped(rawValue)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static func < (lhs: ConfidenceScore, rhs: ConfidenceScore) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    private static func clamped(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(1, max(0, value))
    }
}

public enum KnowledgeItemState: String, Codable, Equatable, CaseIterable, Sendable {
    case active
    case missing
    case permissionNeeded
    case needsReview
    case keptForLater
    case failed
    case archived
}

public struct KnowledgeItem: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var kind: ItemKind
    public var displayName: String
    public var sourceID: UUID?
    public var currentURL: URL?
    public var originalURL: URL?
    public var bookmarkID: UUID?
    public var contentFingerprint: String?
    public var filesystemIdentity: String?
    public var createdAt: Date?
    public var modifiedAt: Date?
    public var firstSeenAt: Date
    public var lastSeenAt: Date
    public var state: KnowledgeItemState

    public init(
        id: UUID = UUID(),
        kind: ItemKind,
        displayName: String,
        sourceID: UUID? = nil,
        currentURL: URL? = nil,
        originalURL: URL? = nil,
        bookmarkID: UUID? = nil,
        contentFingerprint: String? = nil,
        filesystemIdentity: String? = nil,
        createdAt: Date? = nil,
        modifiedAt: Date? = nil,
        firstSeenAt: Date,
        lastSeenAt: Date,
        state: KnowledgeItemState = .active
    ) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.sourceID = sourceID
        self.currentURL = currentURL
        self.originalURL = originalURL
        self.bookmarkID = bookmarkID
        self.contentFingerprint = contentFingerprint
        self.filesystemIdentity = filesystemIdentity
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.firstSeenAt = firstSeenAt
        self.lastSeenAt = lastSeenAt
        self.state = state
    }

    public static func draft(
        from request: OrganizationRequest,
        profile: ItemProfile,
        state: KnowledgeItemState = .active
    ) -> KnowledgeItem {
        KnowledgeItem(
            id: profile.id,
            kind: profile.kind,
            displayName: profile.displayName,
            sourceID: request.sourceID,
            currentURL: profile.url,
            originalURL: request.itemURL,
            contentFingerprint: profile.contentHash,
            createdAt: profile.createdAt,
            modifiedAt: profile.modifiedAt,
            firstSeenAt: request.receivedAt,
            lastSeenAt: request.receivedAt,
            state: state
        )
    }
}

public enum CaptureSource: String, Codable, Equatable, CaseIterable, Sendable {
    case menuBarDrop
    case watchedFolder
    case manualImport
    case existingLibraryScan
    case finderReconnect
    case agentRequest
    case automation
    case shareExtension
    case browserExtension
    case cli

    public init(intakeSource: IntakeSource) {
        switch intakeSource {
        case .dragDrop:
            self = .menuBarDrop
        case .watchedFolder:
            self = .watchedFolder
        case .manualImport:
            self = .manualImport
        case .automation:
            self = .automation
        case .ai:
            self = .agentRequest
        }
    }

    public init(sourceKind: SourceKind) {
        switch sourceKind {
        case .watchedFolder:
            self = .watchedFolder
        case .menuBarDrop:
            self = .menuBarDrop
        case .manualImport:
            self = .manualImport
        case .browserExtension:
            self = .browserExtension
        case .shareExtension:
            self = .shareExtension
        case .cli:
            self = .cli
        case .agentRequest:
            self = .agentRequest
        }
    }
}

public struct CaptureEvent: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var itemID: UUID
    public var source: CaptureSource
    public var sourceID: UUID?
    public var sourceDetail: [String: String]
    public var receivedAt: Date
    public var sessionID: UUID
    public var parentContextID: UUID?
    public var rawURL: URL
    public var requestedMode: OrganizationMode

    public init(
        id: UUID = UUID(),
        itemID: UUID,
        source: CaptureSource,
        sourceID: UUID? = nil,
        sourceDetail: [String: String] = [:],
        receivedAt: Date,
        sessionID: UUID = UUID(),
        parentContextID: UUID? = nil,
        rawURL: URL,
        requestedMode: OrganizationMode
    ) {
        self.id = id
        self.itemID = itemID
        self.source = source
        self.sourceID = sourceID
        self.sourceDetail = sourceDetail
        self.receivedAt = receivedAt
        self.sessionID = sessionID
        self.parentContextID = parentContextID
        self.rawURL = rawURL
        self.requestedMode = requestedMode
    }

    public static func draft(
        from request: OrganizationRequest,
        itemID: UUID,
        sessionID: UUID = UUID(),
        parentContextID: UUID? = nil,
        sourceDetail: [String: String] = [:]
    ) -> CaptureEvent {
        CaptureEvent(
            itemID: itemID,
            source: CaptureSource(intakeSource: request.source),
            sourceID: request.sourceID,
            sourceDetail: sourceDetail,
            receivedAt: request.receivedAt,
            sessionID: sessionID,
            parentContextID: parentContextID,
            rawURL: request.itemURL,
            requestedMode: request.mode
        )
    }

    public static func draft(
        from request: OrganizationRequest,
        sourceRecord: SourceRecord,
        itemID: UUID,
        sessionID: UUID = UUID(),
        parentContextID: UUID? = nil,
        sourceDetail: [String: String] = [:]
    ) -> CaptureEvent {
        var detail = sourceRecord.captureDetail
        detail.merge(request.userContext) { _, new in new }
        detail.merge(sourceDetail) { _, new in new }
        return CaptureEvent(
            itemID: itemID,
            source: CaptureSource(sourceKind: sourceRecord.kind),
            sourceID: sourceRecord.id,
            sourceDetail: detail,
            receivedAt: request.receivedAt,
            sessionID: sessionID,
            parentContextID: parentContextID,
            rawURL: request.itemURL,
            requestedMode: request.mode
        )
    }
}

public enum ContextKind: String, Codable, Equatable, CaseIterable, Sendable {
    case project
    case person
    case organization
    case topic
    case event
    case folder
    case downloadSession
    case application
    case collection
    case rule
    case taskState
    case timeWindow
}

public enum GraphProvenance: String, Codable, Equatable, CaseIterable, Sendable {
    case user
    case rule
    case existingFolderScan
    case captureSession
    case metadataExtraction
    case aiSuggestion
    case system
}

public struct ContextNode: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var kind: ContextKind
    public var name: String
    public var confidence: ConfidenceScore
    public var provenance: GraphProvenance
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        kind: ContextKind,
        name: String,
        confidence: ConfidenceScore = ConfidenceScore(1),
        provenance: GraphProvenance,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.confidence = confidence
        self.provenance = provenance
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum GraphNodeKind: String, Codable, Equatable, CaseIterable, Sendable {
    case knowledgeItem
    case context
    case collection
}

public enum RelationshipPredicate: String, Codable, Equatable, CaseIterable, Sendable {
    case belongsTo
    case cameFrom
    case wasCapturedIn
    case isNear
    case isSimilarTo
    case wasMovedBy
    case wasReviewedBy
    case wasCreatedByApp
    case matchesRule
    case hasTopic
    case mentionsPerson
    case replaces
    case duplicates
}

public struct RelationshipEdge: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var subjectID: UUID
    public var subjectKind: GraphNodeKind
    public var predicate: RelationshipPredicate
    public var objectID: UUID
    public var objectKind: GraphNodeKind
    public var confidence: ConfidenceScore
    public var provenance: GraphProvenance
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        subjectID: UUID,
        subjectKind: GraphNodeKind,
        predicate: RelationshipPredicate,
        objectID: UUID,
        objectKind: GraphNodeKind,
        confidence: ConfidenceScore = ConfidenceScore(1),
        provenance: GraphProvenance,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.subjectID = subjectID
        self.subjectKind = subjectKind
        self.predicate = predicate
        self.objectID = objectID
        self.objectKind = objectKind
        self.confidence = confidence
        self.provenance = provenance
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum KnowledgeCollectionKind: String, Codable, Equatable, CaseIterable, Sendable {
    case manual
    case savedSearch
    case ruleBacked
    case agentSuggested
    case system
}

public struct KnowledgeCollection: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: KnowledgeCollectionKind
    public var query: String?
    public var manualMembershipAllowed: Bool
    public var createdBy: GraphProvenance
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        kind: KnowledgeCollectionKind,
        query: String? = nil,
        manualMembershipAllowed: Bool = true,
        createdBy: GraphProvenance,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.query = query
        self.manualMembershipAllowed = manualMembershipAllowed
        self.createdBy = createdBy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
