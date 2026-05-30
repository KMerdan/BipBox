# TASK-307: Onboarding And Cold-Start UI

## Goal

Add a first-run and manual cold-start flow that proves retrieval value before asking the user to configure detailed rules.

## Scope

- Add UI for choosing Library root and starter capture locations such as Downloads, Desktop, Documents, and optional project folders.
- Show shallow scan progress, recoverable permission states, and immediate findings.
- Let users accept, ignore, or defer suggested contexts and collections.
- Use mock scanner data first if the real scanner is not ready.
- Primary codegraph scope: `WorkspaceRootView.swift`, `SettingsWorkspaceView.swift`, `ReviewQueueView.swift`, `LibraryWorkspaceView.swift`, `BipboxApplication.swift`.
- Change scope: SwiftUI onboarding and view models; scanner integration can be mocked initially.

## Non-Goals

- Do not build a marketing landing page.
- Do not expose raw graph terminology.
- Do not require AI.

## Dependencies

- `TASK-005-memory-graph-domain-models.md`
- Real integration later: `TASK-207-cold-start-scanner.md`

## Test Requirements

- View model tests for first-run state, selected folders, skipped folders, and completion.
- UI smoke tests for onboarding navigation.
- Manual verification for permission picker flows.

## Acceptance Criteria

- A new user can start with indexing/capturing rather than writing rules.
- The flow communicates that Bipbox solves retrieval first and storage second.
- Users can leave onboarding and continue using the app without data loss.

