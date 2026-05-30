import Foundation
import SwiftUI

public enum WorkspaceSection: String, CaseIterable, Identifiable, Hashable, Sendable {
    case onboarding
    case inbox
    case library
    case rules
    case activity
    case settings

    public var id: String {
        rawValue
    }

    public var title: String {
        switch self {
        case .onboarding: "Start"
        case .inbox: "Intake"
        case .library: "Library"
        case .rules: "Rules"
        case .activity: "Activity"
        case .settings: "Settings"
        }
    }

    public var systemImage: String {
        switch self {
        case .onboarding: "sparkles.rectangle.stack"
        case .inbox: "tray.and.arrow.down"
        case .library: "folder"
        case .rules: "point.3.connected.trianglepath.dotted"
        case .activity: "clock"
        case .settings: "gearshape"
        }
    }

    public var placeholderDescription: String {
        switch self {
        case .onboarding:
            "Choose starter folders and index existing files in place."
        case .inbox:
            "Monitor watched folders and resolve incoming items that need a decision."
        case .library:
            "Browse and search files organized or indexed by Bipbox."
        case .rules:
            "Build tree-like routing workflows."
        case .activity:
            "Inspect recent organization events."
        case .settings:
            "Configure folders, permissions, and app behavior."
        }
    }
}

@MainActor
public final class WorkspaceState: ObservableObject {
    @Published public var selectedSection: WorkspaceSection
    @Published public private(set) var isLoading: Bool
    @Published public private(set) var dropSummary: String?

    public init(
        selectedSection: WorkspaceSection = .onboarding,
        isLoading: Bool = false,
        dropSummary: String? = nil
    ) {
        self.selectedSection = selectedSection
        self.isLoading = isLoading
        self.dropSummary = dropSummary
    }

    public func select(_ section: WorkspaceSection) {
        selectedSection = section
    }

    public func setLoading(_ loading: Bool) {
        isLoading = loading
    }

    public func recordDropAccepted(itemCount: Int) {
        dropSummary = itemCount == 1 ? "1 item received." : "\(itemCount) items received."
    }

    public func recordDropFailure(_ message: String) {
        dropSummary = message
    }

    public func clearDropSummary() {
        dropSummary = nil
    }
}
