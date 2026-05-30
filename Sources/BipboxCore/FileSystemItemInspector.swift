import CryptoKit
import Foundation
import UniformTypeIdentifiers

public enum ItemInspectionError: Error, Equatable, LocalizedError {
    case itemMissing(URL)
    case itemInaccessible(URL, String)
    case hashUnavailable(URL, String)

    public var errorDescription: String? {
        switch self {
        case .itemMissing(let url):
            "Item does not exist: \(url.path)"
        case .itemInaccessible(let url, let reason):
            "Item is not accessible: \(url.path). \(reason)"
        case .hashUnavailable(let url, let reason):
            "Could not hash item: \(url.path). \(reason)"
        }
    }
}

public final class FileSystemItemInspector: ItemInspector {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func inspect(
        _ request: OrganizationRequest,
        options: InspectionOptions = InspectionOptions()
    ) async throws -> ItemProfile {
        guard fileManager.fileExists(atPath: request.itemURL.path) else {
            throw ItemInspectionError.itemMissing(request.itemURL)
        }

        let values: URLResourceValues
        do {
            values = try request.itemURL.resourceValues(forKeys: Self.profileResourceKeys)
        } catch {
            throw ItemInspectionError.itemInaccessible(request.itemURL, error.localizedDescription)
        }

        let kind = determineKind(url: request.itemURL, values: values)
        let folderSummary = try folderSummaryIfNeeded(
            for: request.itemURL,
            kind: kind,
            options: options,
            values: values
        )
        let contentHash = try contentHashIfNeeded(for: request.itemURL, kind: kind, options: options)
        let extensionValue = request.itemURL.pathExtension.isEmpty ? nil : request.itemURL.pathExtension

        return ItemProfile(
            url: request.itemURL,
            kind: kind,
            displayName: request.itemURL.lastPathComponent,
            fileExtension: extensionValue,
            uniformTypeIdentifier: values.contentType?.identifier,
            sizeBytes: values.fileSize.map(Int64.init),
            createdAt: values.creationDate,
            modifiedAt: values.contentModificationDate,
            source: request.source,
            finderTags: values.tagNames ?? [],
            contentHash: contentHash,
            folderChildSummary: folderSummary,
            metadata: [
                "inspection.recursiveFolderInspectionAllowed": String(options.allowRecursiveFolderInspection)
            ]
        )
    }

    private func determineKind(url: URL, values: URLResourceValues) -> ItemKind {
        if values.isSymbolicLink == true {
            return .symlink
        }

        if values.isPackage == true {
            return Self.bundleExtensions.contains(url.pathExtension.lowercased()) ? .bundle : .package
        }

        if values.isDirectory == true {
            return .folder
        }

        if values.isRegularFile == true {
            return .file
        }

        return .unknown
    }

    private func folderSummaryIfNeeded(
        for url: URL,
        kind: ItemKind,
        options: InspectionOptions,
        values: URLResourceValues
    ) throws -> FolderChildSummary? {
        guard options.includeShallowFolderSummary else {
            return nil
        }

        guard kind == .folder || kind == .package || kind == .bundle else {
            return nil
        }

        let childURLs: [URL]
        do {
            childURLs = try fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: Self.childResourceKeyList,
                options: [.skipsHiddenFiles]
            )
        } catch {
            throw ItemInspectionError.itemInaccessible(url, error.localizedDescription)
        }

        var visibleFileCount = 0
        var visibleFolderCount = 0
        var topLevelExtensions: [String: Int] = [:]
        var shallowSizeBytes: Int64 = 0

        for childURL in childURLs {
            let childValues = try? childURL.resourceValues(forKeys: Self.childResourceKeys)

            if childValues?.isDirectory == true {
                visibleFolderCount += 1
            } else {
                visibleFileCount += 1
                if let size = childValues?.fileSize {
                    shallowSizeBytes += Int64(size)
                }
            }

            let childExtension = childURL.pathExtension.lowercased()
            if !childExtension.isEmpty {
                topLevelExtensions[childExtension, default: 0] += 1
            }
        }

        return FolderChildSummary(
            visibleChildCount: childURLs.count,
            visibleFileCount: visibleFileCount,
            visibleFolderCount: visibleFolderCount,
            topLevelExtensions: topLevelExtensions,
            shallowSizeBytes: shallowSizeBytes,
            isPackageLike: values.isPackage ?? false,
            recursiveInspectionRequested: options.allowRecursiveFolderInspection
        )
    }

    private func contentHashIfNeeded(
        for url: URL,
        kind: ItemKind,
        options: InspectionOptions
    ) throws -> String? {
        guard options.includeContentHash else {
            return nil
        }

        guard kind == .file else {
            return nil
        }

        do {
            let data = try Data(contentsOf: url)
            let digest = SHA256.hash(data: data)
            return digest.map { String(format: "%02x", $0) }.joined()
        } catch {
            throw ItemInspectionError.hashUnavailable(url, error.localizedDescription)
        }
    }

    private static let profileResourceKeys: Set<URLResourceKey> = [
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

    private static let childResourceKeys: Set<URLResourceKey> = [
        .isDirectoryKey,
        .isRegularFileKey,
        .fileSizeKey
    ]

    private static let childResourceKeyList = Array(childResourceKeys)

    private static let bundleExtensions: Set<String> = [
        "app",
        "appex",
        "bundle",
        "framework",
        "plugin",
        "xpc"
    ]
}
