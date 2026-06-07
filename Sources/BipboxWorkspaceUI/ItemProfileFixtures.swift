// ItemProfileFixtures.swift — sample `ItemProfile`s used by view-model fixtures
// and previews. (Recovered from the old RulesWorkspaceView during the redesign.)
import BipboxCore
import Foundation

public extension ItemProfile {
    static func rulesFixturePDF() -> ItemProfile {
        ItemProfile(
            url: URL(fileURLWithPath: "/Users/example/Downloads/report.pdf"),
            kind: .file,
            displayName: "report.pdf",
            fileExtension: "pdf",
            uniformTypeIdentifier: "com.adobe.pdf",
            source: .dragDrop
        )
    }

    static func rulesFixtureFolder() -> ItemProfile {
        ItemProfile(
            url: URL(fileURLWithPath: "/Users/example/Downloads/Client Project", isDirectory: true),
            kind: .folder,
            displayName: "Client Project",
            source: .dragDrop,
            folderChildSummary: FolderChildSummary(
                visibleChildCount: 1,
                visibleFileCount: 1,
                visibleFolderCount: 0,
                topLevelExtensions: ["pdf": 1],
                recursiveInspectionRequested: false
            )
        )
    }
}
