import CryptoKit
import Foundation

public enum ColdStartScannerError: Error, Equatable, LocalizedError {
    case permissionRecordNotFound(UUID)
    case permissionRequired(UUID, PermissionState)
    case rootMissing(URL)
    case rootIsNotFolder(URL)
    case scanFailed(URL, String)
    case cancelled(scannedCount: Int)

    public var errorDescription: String? {
        switch self {
        case .permissionRecordNotFound(let id):
            "Permission record was not found for cold-start scan: \(id.uuidString)"
        case .permissionRequired(let id, let state):
            "Permission \(id.uuidString) is not ready for cold-start scan: \(state.rawValue)"
        case .rootMissing(let url):
            "Cold-start scan root does not exist: \(url.path)"
        case .rootIsNotFolder(let url):
            "Cold-start scan root is not a folder: \(url.path)"
        case .scanFailed(let url, let reason):
            "Could not scan \(url.path): \(reason)"
        case .cancelled(let scannedCount):
            "Cold-start scan was cancelled after \(scannedCount) item(s)."
        }
    }
}

public final class DefaultColdStartScanner: ColdStartScanner, @unchecked Sendable {
    private let permissionStore: PermissionStore
    private let inspector: ItemInspector
    private let knowledgeStore: KnowledgeStore
    private let searchService: SearchService?
    private let metadataExtractionService: MetadataExtractionService?
    private let activityLog: ActivityLog?
    private let vectorIndex: VectorIndex?
    private let embedder: TextEmbedder?
    private let fileManager: FileManager

    public init(
        permissionStore: PermissionStore,
        inspector: ItemInspector,
        knowledgeStore: KnowledgeStore,
        searchService: SearchService? = nil,
        metadataExtractionService: MetadataExtractionService? = nil,
        activityLog: ActivityLog? = nil,
        vectorIndex: VectorIndex? = nil,
        embedder: TextEmbedder? = nil,
        fileManager: FileManager = .default
    ) {
        self.permissionStore = permissionStore
        self.inspector = inspector
        self.knowledgeStore = knowledgeStore
        self.searchService = searchService
        self.metadataExtractionService = metadataExtractionService
        self.activityLog = activityLog
        self.vectorIndex = vectorIndex
        self.embedder = embedder
        self.fileManager = fileManager
    }

    public func scan(
        _ request: ColdStartScanRequest,
        progress: (@Sendable (ColdStartScanProgress) async -> Void)? = nil
    ) async throws -> ColdStartScanResult {
        let permissionRecord = try await permissionRecord(id: request.permissionRecordID)
        guard permissionRecord.state == .granted else {
            throw ColdStartScannerError.permissionRequired(permissionRecord.id, permissionRecord.state)
        }
        try validateRoot(permissionRecord.url)

        await progress?(
            ColdStartScanProgress(
                phase: .preparing,
                scannedCount: 0,
                currentURL: permissionRecord.url,
                message: "Preparing cold-start scan."
            )
        )

        let candidates = try scanCandidates(rootURL: permissionRecord.url, recursive: request.recursive)
        let rootContext = ContextNode(
            id: KnowledgeIDs.folderContext(for: permissionRecord.url),
            kind: .folder,
            name: permissionRecord.url.lastPathComponent.isEmpty ? permissionRecord.url.path : permissionRecord.url.lastPathComponent,
            confidence: ConfidenceScore(1),
            provenance: .existingFolderScan,
            createdAt: request.receivedAt,
            updatedAt: request.receivedAt
        )
        try await knowledgeStore.upsertContext(rootContext)
        await embedEntity(rootContext)

        // Incremental rescan: load what is already indexed ONCE; candidates whose
        // content fingerprint is unchanged are skipped entirely (no extraction,
        // no FTS write, no embedding, no capture event).
        var existingByID: [UUID: IndexedItem] = [:]
        if let searchService,
           let indexed = try? await searchService.search(SearchQuery(text: "", limit: 1_000_000)) {
            for item in indexed.items { existingByID[item.id] = item }
        }

        var scannedCount = 0
        var failures: [ColdStartScanFailure] = []
        for candidate in candidates {
            if Task.isCancelled {
                throw ColdStartScannerError.cancelled(scannedCount: scannedCount)
            }

            await progress?(
                ColdStartScanProgress(
                    phase: .scanning,
                    scannedCount: scannedCount,
                    totalCount: candidates.count,
                    currentURL: candidate.url
                )
            )

            let existing = existingByID[Self.itemID(for: candidate.url)]
            if let fingerprint = candidate.fingerprint,
               let existing,
               existing.contentFingerprint == fingerprint,
               existing.status != .missing {
                scannedCount += 1
                continue
            }

            do {
                try await capture(candidate, rootContextID: rootContext.id, permissionRecord: permissionRecord,
                                  request: request, replacesExisting: existing != nil)
                scannedCount += 1
            } catch {
                let message = error.localizedDescription
                failures.append(ColdStartScanFailure(url: candidate.url, message: message))
                try await activityLog?.append(
                    ActivityEvent(
                        kind: .failed,
                        message: "Cold-start scan failed for \(candidate.url.lastPathComponent): \(message)",
                        occurredAt: request.receivedAt
                    )
                )
            }
        }

        if request.recursive {
            await reconcileVanishedItems(
                under: permissionRecord.url, candidates: candidates, existingByID: existingByID)
        }

        await progress?(
            ColdStartScanProgress(
                phase: .completed,
                scannedCount: scannedCount,
                totalCount: candidates.count,
                currentURL: permissionRecord.url,
                message: "Cold-start scan completed."
            )
        )

        return ColdStartScanResult(
            sessionID: request.sessionID,
            rootURL: permissionRecord.url,
            scannedItemCount: scannedCount,
            contextCount: 1,
            failures: failures
        )
    }

    private func permissionRecord(id: UUID) async throws -> PermissionRecord {
        let records = try await permissionStore.records(scope: nil)
        guard let record = records.first(where: { $0.id == id }) else {
            throw ColdStartScannerError.permissionRecordNotFound(id)
        }
        return record
    }

    private func validateRoot(_ url: URL) throws {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw ColdStartScannerError.rootMissing(url)
        }
        guard isDirectory.boolValue else {
            throw ColdStartScannerError.rootIsNotFolder(url)
        }
    }

    /// One item to index: the URL plus its unit classification (tags), how to
    /// compose its unit text (aggregates only — composed LAZILY so skipped
    /// candidates cost nothing), whether to skip embedding (exact duplicates
    /// are indexed for search but never embedded), and the content fingerprint
    /// that makes rescans incremental.
    struct ScanCandidate {
        enum UnitTextSource {
            case project
            case collection(members: [URL])
        }

        let url: URL
        var tags: [String] = []
        var unitTextSource: UnitTextSource? = nil
        var skipEmbed: Bool = false
        var fingerprint: String? = nil
    }

    /// Recursive scans use the FilesystemDescender: projects/collections become
    /// single aggregate units, collection members stay individually indexed, and
    /// exact byte-fingerprint duplicates are flagged. Non-recursive scans keep
    /// the flat top-level listing.
    private func scanCandidates(rootURL: URL, recursive: Bool) throws -> [ScanCandidate] {
        guard recursive else {
            do {
                return try fileManager.contentsOfDirectory(
                    at: rootURL,
                    includingPropertiesForKeys: Self.resourceKeys,
                    options: [.skipsHiddenFiles]
                )
                .sorted { $0.path < $1.path }
                .map { ScanCandidate(url: $0) }
            } catch {
                throw ColdStartScannerError.scanFailed(rootURL, error.localizedDescription)
            }
        }

        let units = FilesystemDescender(fileManager: fileManager).descend(root: rootURL)
        var membersByCollection: [URL: [URL]] = [:]
        for unit in units where unit.kind == .file {
            if let collection = unit.collectionURL {
                membersByCollection[collection, default: []].append(unit.url)
            }
        }

        return units.map { unit in
            switch unit.kind {
            case .project, .workspaceMember:
                return ScanCandidate(
                    url: unit.url,
                    tags: ["unit:project"],
                    unitTextSource: .project,
                    fingerprint: unit.byteFingerprint
                )
            case .bundle:
                return ScanCandidate(url: unit.url, tags: ["unit:bundle"], fingerprint: unit.byteFingerprint)
            case .collection:
                return ScanCandidate(
                    url: unit.url,
                    tags: ["unit:collection"],
                    unitTextSource: .collection(members: membersByCollection[unit.url] ?? []),
                    fingerprint: unit.byteFingerprint
                )
            case .file:
                var tags: [String]
                if let collection = unit.collectionURL {
                    tags = ["unit:member", "collection:\(Self.itemID(for: collection).uuidString)"]
                } else {
                    tags = ["unit:loose"]
                }
                if unit.isDuplicate { tags.append("dup") }
                return ScanCandidate(url: unit.url, tags: tags, skipEmbed: unit.isDuplicate,
                                     fingerprint: unit.byteFingerprint)
            }
        }
    }

    /// Remove or mark items that a completed recursive scan no longer accounts
    /// for: file gone from disk -> status .missing (recoverable); file present
    /// but no longer a unit (now inside a project, pruned dir, ...) -> dropped
    /// from the search index (the knowledge store keeps its history).
    private func reconcileVanishedItems(
        under root: URL, candidates: [ScanCandidate], existingByID: [UUID: IndexedItem]
    ) async {
        guard let searchService else { return }
        let seen = Set(candidates.map { Self.itemID(for: $0.url) })
        // Stored paths are symlink-resolved (/private/var/...). Foundation's
        // resolvingSymlinksInPath() deliberately does NOT resolve /var -> /private/var,
        // so use realpath(3) for the real on-disk form and match both.
        let standardized = root.standardizedFileURL
        var forms = Set([standardized.path])
        if let real = standardized.path.withCString({ realpath($0, nil) }) {
            forms.insert(String(cString: real))
            free(real)
        }
        let prefixes = forms.map { $0 + "/" }
        for (id, item) in existingByID
        where !seen.contains(id) && prefixes.contains(where: { item.currentPath.hasPrefix($0) }) {
            if fileManager.fileExists(atPath: item.currentPath) {
                try? await (searchService as? SearchIndexRemoving)?.remove(id: id)
                if let embedder, let vectorIndex {
                    try? await vectorIndex.deleteVector(itemID: id, modelID: embedder.modelID)
                }
            } else if item.status != .missing {
                var updated = item
                updated.status = .missing
                try? await searchService.update(updated)
            }
        }
    }

    private func capture(
        _ candidate: ScanCandidate,
        rootContextID: UUID,
        permissionRecord: PermissionRecord,
        request scanRequest: ColdStartScanRequest,
        replacesExisting: Bool = false
    ) async throws {
        let url = candidate.url
        let organizationRequest = OrganizationRequest(
            source: intakeSource(for: scanRequest),
            sourceID: scanRequest.sourceID,
            itemURL: url,
            itemKind: .unknown,
            receivedAt: scanRequest.receivedAt,
            mode: .indexOnly,
            userContext: sourceDetail(for: permissionRecord, scanRequest: scanRequest)
        )
        var profile = try await inspector.inspect(
            organizationRequest,
            options: InspectionOptions(includeContentHash: false, includeShallowFolderSummary: true, allowRecursiveFolderInspection: false)
        )
        profile.id = Self.itemID(for: url)
        profile = await enrichWithExtractedMetadata(profile)
        switch candidate.unitTextSource {
        case .project:
            // Aggregate units (projects/collections) are REPRESENTED by their
            // composed unit text — it feeds lexical search and the embedding.
            // Composed here, not at candidate time, so skipped items cost nothing.
            let unitText = UnitTextComposer.projectText(url: url, fileManager: fileManager)
            profile.metadata["text.content"] = unitText
            profile.extractedTextSummary = unitText
        case .collection(let members):
            let unitText = UnitTextComposer.collectionText(url: url, memberURLs: members)
            profile.metadata["text.content"] = unitText
            profile.extractedTextSummary = unitText
        case nil:
            break
        }

        let knowledgeItem = KnowledgeItem.draft(from: organizationRequest, profile: profile, state: .active)
        let captureEvent = CaptureEvent(
            id: Self.stableUUID("capture-event:\(profile.id.uuidString):\(scanRequest.sourceID?.uuidString ?? permissionRecord.id.uuidString)"),
            itemID: profile.id,
            source: captureSource(for: scanRequest),
            sourceID: scanRequest.sourceID,
            sourceDetail: organizationRequest.userContext,
            receivedAt: scanRequest.receivedAt,
            sessionID: scanRequest.sessionID,
            parentContextID: rootContextID,
            rawURL: url,
            requestedMode: .indexOnly
        )
        let relationship = RelationshipEdge(
            id: Self.stableUUID("relationship:\(profile.id.uuidString):belongsTo:\(rootContextID.uuidString)"),
            subjectID: profile.id,
            subjectKind: .knowledgeItem,
            predicate: .belongsTo,
            objectID: rootContextID,
            objectKind: .context,
            confidence: ConfidenceScore(1),
            provenance: .existingFolderScan,
            createdAt: scanRequest.receivedAt,
            updatedAt: scanRequest.receivedAt
        )

        try await knowledgeStore.upsertKnowledgeItem(knowledgeItem)
        try await knowledgeStore.appendCaptureEvent(captureEvent)
        try await knowledgeStore.upsertRelationship(relationship)
        try await searchService?.index(
            makeIndexedItem(from: profile, request: organizationRequest,
                            permissionRecord: permissionRecord, unitTags: candidate.tags,
                            contentFingerprint: candidate.fingerprint))
        if !candidate.skipEmbed {
            if replacesExisting, let embedder, let vectorIndex {
                // Content changed: drop the stale vector so backfill re-embeds
                // even if the embedder isn't ready right now.
                try? await vectorIndex.deleteVector(itemID: profile.id, modelID: embedder.modelID)
            }
            await embedItem(profile)
        }
        if !profile.metadata.isEmpty {
            try await knowledgeStore.upsertMetadataSnapshot(
                itemID: profile.id,
                metadata: profile.metadata,
                capturedAt: scanRequest.receivedAt
            )
        }
        try await activityLog?.append(
            ActivityEvent(
                kind: .indexed,
                itemID: profile.id,
                requestID: organizationRequest.id,
                message: "Cold-start indexed \(profile.displayName).",
                occurredAt: scanRequest.receivedAt
            )
        )
    }

    /// Embed an item's name + extracted text into the vector index for semantic
    /// retrieval. Best-effort: a failure here never blocks indexing.
    private func embedItem(_ profile: ItemProfile) async {
        guard let embedder, let vectorIndex else { return }
        guard let vector = await embedder.embed(Self.embedText(for: profile)) else { return }
        try? await vectorIndex.upsertVector(
            VectorRecord(itemID: profile.id, modelID: embedder.modelID, vector: vector)
        )
    }

    /// The text that represents an item for indexing/embedding: name + extracted
    /// content (falling back to NLP tokens).
    private static func embedText(for profile: ItemProfile) -> String {
        let content = profile.extractedTextSummary
            ?? profile.metadata["text.content"]
            ?? profile.metadata["nl.tokens"]?.replacingOccurrences(of: ",", with: " ")
        return [profile.displayName, content].compactMap { $0 }.joined(separator: " ")
    }

    /// Embed a context entity (folder / project) under a separate model namespace
    /// so it can label semantic clusters without polluting item clustering.
    /// Idempotent: rescans skip entities that already carry a vector.
    private func embedEntity(_ context: ContextNode) async {
        guard let embedder, let vectorIndex else { return }
        let entityModel = VectorModel.entity(embedder.modelID)
        if let existing = try? await vectorIndex.vectors(modelID: entityModel),
           existing.contains(where: { $0.itemID == context.id }) {
            return
        }
        guard let vector = await embedder.embed(context.name) else { return }
        try? await vectorIndex.upsertVector(
            VectorRecord(itemID: context.id, modelID: VectorModel.entity(embedder.modelID), vector: vector)
        )
    }

    private func makeIndexedItem(
        from item: ItemProfile,
        request: OrganizationRequest,
        permissionRecord: PermissionRecord,
        unitTags: [String] = [],
        contentFingerprint: String? = nil
    ) -> IndexedItem {
        var tags = item.finderTags + unitTags
        if let captureLocation = permissionRecord.metadata["captureLocation"] {
            tags.append(captureLocation)
        }
        if let onboardingRole = permissionRecord.metadata["onboardingRole"] {
            tags.append(onboardingRole)
        }
        let captureTag = request.userContext["captureSource"]
            .flatMap(CaptureSource.init(rawValue:)) ?? CaptureSource(intakeSource: request.source)
        tags.append(captureTag.rawValue)
        if let sourceID = request.sourceID {
            tags.append("source:\(sourceID.uuidString)")
        }
        if let sourceKind = request.userContext["sourceKind"] {
            tags.append(sourceKind)
        }

        return IndexedItem(
            id: item.id,
            currentPath: item.url.path,
            originalPath: nil,
            displayName: item.displayName,
            kind: item.kind,
            uniformTypeIdentifier: item.uniformTypeIdentifier,
            sizeBytes: item.sizeBytes,
            createdAt: item.createdAt,
            modifiedAt: item.modifiedAt,
            importedAt: request.receivedAt,
            routedAt: nil,
            ruleID: nil,
            tags: Array(Set(tags)).sorted(),
            extractedText: item.extractedTextSummary ?? item.metadata["text.content"],
            aiSummary: "Indexed in place from \(permissionRecord.url.lastPathComponent).",
            status: .indexedOnly,
            contentFingerprint: contentFingerprint
        )
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

    private func sourceDetail(
        for permissionRecord: PermissionRecord,
        scanRequest: ColdStartScanRequest
    ) -> [String: String] {
        var detail = permissionRecord.metadata
        detail.merge(scanRequest.sourceDetail) { _, new in new }
        if let sourceID = scanRequest.sourceID {
            detail["sourceID"] = sourceID.uuidString
        }
        detail["permissionRecordID"] = permissionRecord.id.uuidString
        detail["scanRootPath"] = permissionRecord.url.path
        detail["scanRecursive"] = String(scanRequest.recursive)
        detail["captureSource"] = captureSource(for: scanRequest).rawValue
        return detail
    }

    private func intakeSource(for scanRequest: ColdStartScanRequest) -> IntakeSource {
        if scanRequest.sourceID != nil || scanRequest.sourceDetail["sourceKind"] == SourceKind.watchedFolder.rawValue {
            return .watchedFolder
        }
        return .manualImport
    }

    private func captureSource(for scanRequest: ColdStartScanRequest) -> CaptureSource {
        if scanRequest.sourceID != nil || scanRequest.sourceDetail["sourceKind"] == SourceKind.watchedFolder.rawValue {
            return .watchedFolder
        }
        return .existingLibraryScan
    }

    /// The stable, path-derived item id — also used by scanCandidates to tag
    /// collection members with their collection's item id.
    static func itemID(for url: URL) -> UUID {
        stableUUID("knowledge-item:\(url.standardizedFileURL.path)")
    }

    private static func stableUUID(_ input: String) -> UUID {
        let digest = SHA256.hash(data: Data(input.utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    private static let resourceKeys: [URLResourceKey] = [
        .isRegularFileKey,
        .isDirectoryKey,
        .isPackageKey,
        .isSymbolicLinkKey,
        .fileSizeKey,
        .creationDateKey,
        .contentModificationDateKey,
        .contentTypeKey,
        .tagNamesKey
    ]
}
