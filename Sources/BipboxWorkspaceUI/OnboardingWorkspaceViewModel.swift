import BipboxCore
import Foundation

public enum OnboardingFolderRole: String, CaseIterable, Identifiable, Sendable {
    case libraryRoot
    case downloads
    case desktop
    case documents
    case projectFolder

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .libraryRoot: "Library"
        case .downloads: "Downloads"
        case .desktop: "Desktop"
        case .documents: "Documents"
        case .projectFolder: "Project Folder"
        }
    }

    public var metadata: [String: String] {
        switch self {
        case .libraryRoot:
            ["sourceRole": rawValue, "startPurpose": "storage", "watchEnabled": "false"]
        case .downloads:
            [
                "sourceRole": rawValue,
                "captureLocation": CommonCaptureLocation.downloads.rawValue,
                "sourceKind": SourceKind.watchedFolder.rawValue,
                "startPurpose": "watchAndIndex",
                "watchEnabled": "true"
            ]
        case .desktop:
            [
                "sourceRole": rawValue,
                "captureLocation": CommonCaptureLocation.desktop.rawValue,
                "sourceKind": SourceKind.watchedFolder.rawValue,
                "startPurpose": "watchAndIndex",
                "watchEnabled": "true"
            ]
        case .documents, .projectFolder:
            [
                "sourceRole": rawValue,
                "sourceKind": SourceKind.watchedFolder.rawValue,
                "startPurpose": "watchAndIndex",
                "watchEnabled": "true"
            ]
        }
    }
}

public enum OnboardingFolderState: String, Codable, Equatable, Sendable {
    case pending
    case selected
    case skipped
    case saved
    case scanning
    case completed
    case failed
}

public struct OnboardingFolderSelection: Identifiable, Equatable, Sendable {
    public var id: OnboardingFolderRole { role }
    public var role: OnboardingFolderRole
    public var url: URL?
    public var state: OnboardingFolderState
    public var scannedCount: Int
    public var message: String?
    public var sourceID: UUID?

    public init(
        role: OnboardingFolderRole,
        url: URL? = nil,
        state: OnboardingFolderState = .pending,
        scannedCount: Int = 0,
        message: String? = nil,
        sourceID: UUID? = nil
    ) {
        self.role = role
        self.url = url
        self.state = state
        self.scannedCount = scannedCount
        self.message = message
        self.sourceID = sourceID
    }
}

@MainActor
public final class OnboardingWorkspaceViewModel: ObservableObject {
    @Published public private(set) var selections: [OnboardingFolderSelection]
    @Published public private(set) var sources: [SourceRecord]
    @Published public private(set) var isRunning: Bool
    @Published public private(set) var isLoading: Bool
    @Published public private(set) var isCompleted: Bool
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var sourceMessages: [UUID: String]

    private let sourceStore: SourceStore?
    private let lifecycleCoordinator: SourceLifecycleCoordinating?

    public init(
        sourceStore: SourceStore? = nil,
        lifecycleCoordinator: SourceLifecycleCoordinating? = nil,
        selections: [OnboardingFolderSelection] = OnboardingFolderRole.allCases.map { OnboardingFolderSelection(role: $0) }
    ) {
        self.sourceStore = sourceStore
        self.lifecycleCoordinator = lifecycleCoordinator
        self.selections = selections
        sources = []
        isRunning = false
        isLoading = false
        isCompleted = false
        errorMessage = nil
        sourceMessages = [:]
    }

    public var selectedCount: Int {
        selections.filter { $0.state == .selected || $0.state == .saved || $0.state == .completed }.count
    }

    public var completedCount: Int {
        selections.filter { $0.state == .completed || $0.state == .skipped }.count
    }

    public var watchedFolderCount: Int {
        sources.filter { $0.kind == .watchedFolder }.count
    }

    public func load() async {
        guard sourceStore != nil else {
            sources = []
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await loadSources()
            syncSelectionsWithSources()
        } catch {
            sources = []
            errorMessage = error.localizedDescription
        }
    }

    public func select(role: OnboardingFolderRole, url: URL) {
        update(role: role) {
            $0.url = url
            $0.state = .selected
            $0.message = nil
        }
    }

    public func skip(role: OnboardingFolderRole) {
        update(role: role) {
            $0.state = .skipped
            $0.message = "Skipped."
        }
    }

    public func completeWithoutScanning() {
        isCompleted = true
        errorMessage = nil
    }

    public func saveAndScanSelectedFolders() async {
        let selected = selections.filter { $0.state == .selected && $0.url != nil }
        guard !selected.isEmpty else { return }

        for selection in selected {
            guard let url = selection.url else { continue }
            await addPresetWatchedFolder(role: selection.role, url: url)
        }
        isCompleted = errorMessage == nil
    }

    public func addPresetWatchedFolder(role: OnboardingFolderRole, url: URL, recursivePolicy: SourceRecursivePolicy = .never) async {
        await addWatchedFolder(url, role: role, displayName: role.title, recursivePolicy: recursivePolicy)
    }

    public func addCustomWatchedFolder(_ url: URL, recursivePolicy: SourceRecursivePolicy = .never) async {
        await addWatchedFolder(url, role: nil, displayName: url.lastPathComponent.nilIfEmpty ?? url.path, recursivePolicy: recursivePolicy)
    }

    public func replaceWatchedFolder(id: UUID, with url: URL) async {
        guard let lifecycleCoordinator else {
            errorMessage = "Source management is unavailable."
            return
        }
        guard let source = sources.first(where: { $0.id == id }) else {
            errorMessage = "Source is no longer available."
            return
        }

        isRunning = true
        errorMessage = nil
        sourceMessages[id] = "Changing source."
        defer { isRunning = false }

        do {
            let result = try await lifecycleCoordinator.changeWatchedFolder(
                id: id,
                to: SourceLifecycleRequest(
                    sourceID: id,
                    url: url,
                    displayName: source.displayName,
                    metadata: replacementMetadata(source: source, url: url),
                    enabled: source.enabled,
                    recursivePolicy: source.recursivePolicy
                )
            )
            sourceMessages[id] = result.message ?? "Source changed."
            try await loadSources()
            syncSelectionsWithSources()
        } catch {
            sourceMessages[id] = error.localizedDescription
            errorMessage = error.localizedDescription
        }
    }

    public func removeWatchedFolder(id: UUID) async {
        guard let lifecycleCoordinator else {
            errorMessage = "Source management is unavailable."
            return
        }

        isRunning = true
        errorMessage = nil
        sourceMessages[id] = "Removing source."
        defer { isRunning = false }

        do {
            _ = try await lifecycleCoordinator.removeSource(id: id, removePermission: true)
            sourceMessages[id] = nil
            try await loadSources()
            syncSelectionsWithSources()
        } catch {
            sourceMessages[id] = error.localizedDescription
            errorMessage = error.localizedDescription
        }
    }

    public func scanSource(id: UUID) async {
        guard let lifecycleCoordinator else {
            errorMessage = "Source management is unavailable."
            return
        }

        isRunning = true
        errorMessage = nil
        sourceMessages[id] = "Scanning source."
        defer { isRunning = false }

        do {
            let result = try await lifecycleCoordinator.scanSource(id: id)
            sourceMessages[id] = result.message ?? "Source scanned."
            try await loadSources()
        } catch {
            sourceMessages[id] = error.localizedDescription
            errorMessage = error.localizedDescription
        }
    }

    public func pauseSource(id: UUID) async {
        await setSourcePaused(true, id: id)
    }

    public func resumeSource(id: UUID) async {
        await setSourcePaused(false, id: id)
    }

    private func addWatchedFolder(_ url: URL, role: OnboardingFolderRole?, displayName: String, recursivePolicy: SourceRecursivePolicy = .never) async {
        guard let lifecycleCoordinator else {
            errorMessage = "Source management is unavailable."
            return
        }

        isRunning = true
        errorMessage = nil
        if let role {
            update(role: role) {
                $0.url = url
                $0.state = .scanning
                $0.message = "Saving access and indexing."
            }
        }
        defer { isRunning = false }

        do {
            let result = try await lifecycleCoordinator.addWatchedFolder(
                SourceLifecycleRequest(
                    url: url,
                    displayName: displayName,
                    metadata: sourceMetadata(role: role, url: url),
                    enabled: true,
                    recursivePolicy: recursivePolicy
                )
            )
            if let role {
                update(role: role) {
                    $0.sourceID = result.source.id
                    $0.state = .completed
                    $0.scannedCount = result.scanResult?.scannedItemCount ?? result.source.lastScanSummary?.indexedCount ?? 0
                    $0.message = result.message ?? "Source indexed and watching for new arrivals."
                }
            }
            try await loadSources()
            syncSelectionsWithSources()
            isCompleted = true
        } catch {
            if let role {
                update(role: role) {
                    $0.state = .failed
                    $0.message = error.localizedDescription
                }
            }
            errorMessage = error.localizedDescription
        }
    }

    private func setSourcePaused(_ paused: Bool, id: UUID) async {
        guard let lifecycleCoordinator else {
            errorMessage = "Source management is unavailable."
            return
        }

        isRunning = true
        errorMessage = nil
        sourceMessages[id] = paused ? "Pausing source." : "Resuming source."
        defer { isRunning = false }

        do {
            let result = paused
                ? try await lifecycleCoordinator.pauseSource(id: id)
                : try await lifecycleCoordinator.resumeSource(id: id)
            sourceMessages[id] = result.message
            try await loadSources()
            syncSelectionsWithSources()
        } catch {
            sourceMessages[id] = error.localizedDescription
            errorMessage = error.localizedDescription
        }
    }

    private func loadSources() async throws {
        guard let sourceStore else {
            sources = []
            return
        }
        sources = try await sourceStore.sources()
            .filter { $0.kind == .watchedFolder }
            .sorted { left, right in
                (left.url?.path ?? left.displayName)
                    .localizedStandardCompare(right.url?.path ?? right.displayName) == .orderedAscending
            }
    }

    private func syncSelectionsWithSources() {
        for source in sources {
            guard let role = sourceRole(from: source) else {
                continue
            }
            update(role: role) {
                $0.url = source.url
                $0.state = .completed
                $0.message = source.lastScanSummary?.message ?? "Persisted watched source."
                $0.sourceID = source.id
                $0.scannedCount = source.lastScanSummary?.indexedCount ?? 0
            }
        }
    }

    private func update(role: OnboardingFolderRole, _ transform: (inout OnboardingFolderSelection) -> Void) {
        guard let index = selections.firstIndex(where: { $0.role == role }) else { return }
        transform(&selections[index])
    }

    private func sourceMetadata(role: OnboardingFolderRole?, url: URL) -> [String: String] {
        var metadata = role?.metadata ?? [:]
        metadata["sourceKind"] = SourceKind.watchedFolder.rawValue
        metadata["startPurpose"] = "watchAndIndex"
        metadata["watchEnabled"] = "true"
        metadata["watchFolderPath"] = url.path
        metadata["watchFolderName"] = role?.title ?? url.lastPathComponent.nilIfEmpty ?? url.path
        return metadata
    }

    private func replacementMetadata(source: SourceRecord, url: URL) -> [String: String] {
        var metadata = source.metadata
        metadata["sourceKind"] = SourceKind.watchedFolder.rawValue
        metadata["watchEnabled"] = source.enabled ? "true" : "false"
        metadata["watchFolderPath"] = url.path
        metadata["watchFolderName"] = source.displayName
        metadata["startPurpose"] = "watchAndIndex"
        return metadata
    }
}

private func sourceRole(from source: SourceRecord) -> OnboardingFolderRole? {
    source.metadata["sourceRole"].flatMap(OnboardingFolderRole.init(rawValue:))
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
