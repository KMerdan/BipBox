# TASK-003: Memory Capture Contracts

## Goal

Align existing knowledge and capture models with source-aware retrieval-first capture.

## Scope

- Add source linkage to capture requests, capture events, and knowledge item creation paths where missing.
- Ensure `KnowledgeItem` can retain original URL, current URL, first/last seen dates, source ID, and missing/permission-needed states.
- Add helper mappers from `OrganizationRequest` and `SourceRecord` to `CaptureEvent`.
- Preserve existing SQLite knowledge store APIs where possible.

## Non-Goals

- No storage migration implementation unless required for compilation.
- No UI behavior changes.
- No AI or embedding work.

## Dependencies

- `TASK-001-source-models.md`

## Test Requirements

- Domain tests for source-aware capture events.
- Tests proving a folder capture creates one knowledge item, not child items.
- Tests for missing and permission-needed states as explicit knowledge states.

## Acceptance Criteria

- Capture contracts can represent Start scans, watched-folder arrivals, menu-bar drops, and manual imports.
- Existing capture tests still pass.
- Index-before-action remains representable in the pipeline.

