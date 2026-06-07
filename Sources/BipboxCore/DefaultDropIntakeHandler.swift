import Foundation

public final class DefaultDropIntakeHandler: DropIntakeHandling, @unchecked Sendable {
    private let intakeService: IntakeService
    private let itemInspector: ItemInspector
    private let sourceStore: SourceStore?

    public init(intakeService: IntakeService, itemInspector: ItemInspector, sourceStore: SourceStore? = nil) {
        self.intakeService = intakeService
        self.itemInspector = itemInspector
        self.sourceStore = sourceStore
    }

    public func submit(
        fileURLs: [URL],
        source: IntakeSource = .dragDrop,
        mode: OrganizationMode = .organize,
        receivedAt: Date = Date()
    ) async -> DropIntakeSummary {
        guard !fileURLs.isEmpty else {
            return DropIntakeSummary(
                failures: [
                    DropIntakeFailure(itemURL: nil, message: "No file URLs were provided.")
                ]
            )
        }

        var results: [IntakeResult] = []
        var failures: [DropIntakeFailure] = []
        let captureSessionID = UUID()
        let sourceRecord = await captureSourceRecord(for: source, receivedAt: receivedAt)

        for url in fileURLs {
            guard url.isFileURL else {
                failures.append(DropIntakeFailure(itemURL: url, message: "Only file URLs can be dropped."))
                continue
            }

            let initialRequest = OrganizationRequest(
                source: source,
                sourceID: sourceRecord?.id,
                itemURL: url,
                itemKind: .unknown,
                receivedAt: receivedAt,
                mode: mode,
                userContext: sourceDetail(
                    sourceRecord: sourceRecord,
                    captureSessionID: captureSessionID,
                    itemCount: fileURLs.count
                )
            )

            do {
                let profile = try await itemInspector.inspect(
                    initialRequest,
                    options: InspectionOptions(
                        includeContentHash: false,
                        includeShallowFolderSummary: true,
                        allowRecursiveFolderInspection: false
                    )
                )
                let request = OrganizationRequest(
                    source: source,
                    sourceID: sourceRecord?.id,
                    itemURL: url,
                    itemKind: profile.kind,
                    receivedAt: receivedAt,
                    mode: mode,
                    userContext: sourceDetail(
                        sourceRecord: sourceRecord,
                        captureSessionID: captureSessionID,
                        itemCount: fileURLs.count
                    )
                )
                let result = try await intakeService.submit(request)
                results.append(result)

                if !result.accepted {
                    failures.append(
                        DropIntakeFailure(
                            itemURL: url,
                            message: result.message ?? "Dropped item was not accepted."
                        )
                    )
                }
            } catch {
                failures.append(DropIntakeFailure(itemURL: url, message: error.localizedDescription))
            }
        }

        return DropIntakeSummary(results: results, failures: failures)
    }

    private func captureSourceRecord(for source: IntakeSource, receivedAt: Date) async -> SourceRecord? {
        guard let sourceStore else {
            return nil
        }
        guard let sourceKind = sourceKind(for: source) else {
            return nil
        }

        if let existing = (try? await sourceStore.enabledSources(kind: sourceKind))?.first {
            return existing
        }

        let record: SourceRecord
        switch sourceKind {
        case .menuBarDrop:
            record = SourceRecord.menuBarDrop(createdAt: receivedAt, metadata: ["captureSource": CaptureSource.menuBarDrop.rawValue])
        case .manualImport:
            record = SourceRecord.manualImport(createdAt: receivedAt, metadata: ["captureSource": CaptureSource.manualImport.rawValue])
        case .agentRequest:
            record = SourceRecord(
                kind: .agentRequest,
                displayName: "Agent Request",
                recursivePolicy: .never,
                indexState: .completed,
                watchState: .stopped,
                createdAt: receivedAt,
                updatedAt: receivedAt,
                metadata: ["captureSource": CaptureSource.agentRequest.rawValue]
            )
        case .cli:
            record = SourceRecord(
                kind: .cli,
                displayName: "CLI",
                recursivePolicy: .never,
                indexState: .completed,
                watchState: .stopped,
                createdAt: receivedAt,
                updatedAt: receivedAt,
                metadata: ["captureSource": CaptureSource.cli.rawValue]
            )
        case .watchedFolder, .browserExtension, .shareExtension:
            return nil
        }

        _ = try? await sourceStore.upsert(record)
        return record
    }

    private func sourceKind(for source: IntakeSource) -> SourceKind? {
        switch source {
        case .dragDrop:
            .menuBarDrop
        case .manualImport:
            .manualImport
        case .automation:
            .cli
        case .ai:
            .agentRequest
        case .watchedFolder:
            nil
        }
    }

    private func sourceDetail(sourceRecord: SourceRecord?, captureSessionID: UUID, itemCount: Int) -> [String: String] {
        var detail = sourceRecord?.captureDetail ?? [:]
        detail["captureSessionID"] = captureSessionID.uuidString
        detail["captureItemCount"] = String(itemCount)
        if detail["captureSource"] == nil, let sourceRecord {
            detail["captureSource"] = CaptureSource(sourceKind: sourceRecord.kind).rawValue
        }
        return detail
    }
}
