import BipboxCore
import SwiftUI

@MainActor
public struct WorkspaceViewModels {
    public var onboarding: OnboardingWorkspaceViewModel
    public var library: SearchWorkspaceViewModel
    public var rules: RulesWorkspaceViewModel
    public var reviewQueue: ReviewQueueViewModel
    public var activity: ActivityWorkspaceViewModel
    public var settings: SettingsWorkspaceViewModel

    public init(
        onboarding: OnboardingWorkspaceViewModel = OnboardingWorkspaceViewModel(),
        library: SearchWorkspaceViewModel = .fixture(statusFilter: .all),
        rules: RulesWorkspaceViewModel = RulesWorkspaceViewModel(),
        reviewQueue: ReviewQueueViewModel = ReviewQueueViewModel(),
        activity: ActivityWorkspaceViewModel = ActivityWorkspaceViewModel(),
        settings: SettingsWorkspaceViewModel = SettingsWorkspaceViewModel()
    ) {
        self.onboarding = onboarding
        self.library = library
        self.rules = rules
        self.reviewQueue = reviewQueue
        self.activity = activity
        self.settings = settings
    }
}

public struct WorkspaceRootView: View {
    @StateObject private var state: WorkspaceState
    private let viewModels: WorkspaceViewModels

    @MainActor
    public init(
        state: WorkspaceState = WorkspaceState(),
        viewModels: WorkspaceViewModels = WorkspaceViewModels()
    ) {
        _state = StateObject(wrappedValue: state)
        self.viewModels = viewModels
    }

    public var body: some View {
        HStack(spacing: 0) {
            WorkspaceSidebar(selectedSection: state.selectedSection) { section in
                state.select(section)
            }
            .frame(minWidth: 220, idealWidth: 220, maxWidth: 220)
            .fixedSize(horizontal: true, vertical: false)

            Divider()

            WorkspaceSectionContent(
                section: state.selectedSection,
                isLoading: state.isLoading,
                viewModels: viewModels
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay(alignment: .bottomTrailing) {
            if let dropSummary = state.dropSummary {
                Text(dropSummary)
                    .font(.callout)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding()
            }
        }
        .frame(minWidth: 980, minHeight: 560)
    }
}

private struct WorkspaceSidebar: View {
    let selectedSection: WorkspaceSection
    let select: (WorkspaceSection) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Bipbox")
                .font(.title2)
                .fontWeight(.semibold)
                .padding(.horizontal, 20)
                .padding(.top, 28)
                .padding(.bottom, 20)

            VStack(spacing: 4) {
                ForEach(WorkspaceSection.allCases) { section in
                    Button {
                        select(section)
                    } label: {
                        Label(section.title, systemImage: section.systemImage)
                            .font(.system(size: 15, weight: .medium))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(section == selectedSection ? .primary : .secondary)
                    .background {
                        if section == selectedSection {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.accentColor.opacity(0.14))
                        }
                    }
                    .contentShape(Rectangle())
                }
            }
            .padding(.horizontal, 8)

            Spacer()
        }
        .frame(width: 220, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.72))
    }
}

private struct WorkspaceSectionContent: View {
    let section: WorkspaceSection
    let isLoading: Bool
    let viewModels: WorkspaceViewModels

    var body: some View {
        switch section {
        case .onboarding:
            OnboardingWorkspaceView(viewModel: viewModels.onboarding)
        case .rules:
            RulesWorkspaceView(viewModel: viewModels.rules)
        case .activity:
            ActivityWorkspaceView(viewModel: viewModels.activity)
        case .settings:
            SettingsWorkspaceView(viewModel: viewModels.settings)
        case .inbox:
            ReviewQueueView(viewModel: viewModels.reviewQueue)
        case .library:
            LibraryWorkspaceView(viewModel: viewModels.library)
        }
    }
}
