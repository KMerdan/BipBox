# TASK-109: Capture-First Pipeline

## Goal

Refactor the organization pipeline so every accepted item is recorded in the memory graph before routing, planning, or filesystem operations happen.

## Scope

- Inject the knowledge store into `DefaultOrganizationPipeline`.
- After stabilization and inspection, upsert a `KnowledgeItem` and append a `CaptureEvent`.
- Preserve current `indexOnly`, review, simulate, organized, and failed outcomes.
- Ensure failed routing or execution still leaves a searchable/captured record with failure state.
- Primary codegraph scope: `DefaultOrganizationPipeline.swift`, `PipelineIntakeService.swift`, `DefaultDropIntakeHandler.swift`, `WatchFolderAutomationService.swift`, `SQLiteSearchIndex.swift`.
- Change scope: pipeline orchestration and tests; no new UI.

## Non-Goals

- Do not redesign workflow routing.
- Do not add recursive folder processing.
- Do not change operation execution safety rules.
- Do not implement Library relatedness UI.

## Dependencies

- `TASK-108-knowledge-sqlite-store.md`

## Test Requirements

- Pipeline tests proving capture records are written before route/plan/execute.
- Failure tests proving an inspection success followed by route/execute failure still leaves a `KnowledgeItem`.
- Tests for `indexOnly` producing memory graph records without filesystem operations.
- Tests preserving the invariant that dropped folders create one item, not child items.

## Acceptance Criteria

- New menu-bar, drag/drop, watched-folder, and manual-import requests can be found in the knowledge store after processing.
- Existing pipeline result statuses remain compatible with current UI view models.
- Activity log and search index behavior are not regressed.

