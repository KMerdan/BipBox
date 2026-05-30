# TASK-002: Source Store Contract

## Goal

Define the storage protocol for durable source records so Start and capture services no longer depend on in-memory onboarding selections.

## Scope

- Add `SourceStore` protocol with upsert, remove, fetch by ID, list, and list enabled methods.
- Add explicit error cases for missing source, duplicate path, invalid URL, and storage unavailable.
- Add an event or return shape for source changes if needed by watcher reload flows.
- Add mock and fixture source stores for tests.

## Non-Goals

- No JSON or SQLite implementation.
- No UI migration from `OnboardingWorkspaceViewModel`.
- No security-scoped bookmark implementation.

## Dependencies

- `TASK-001-source-models.md`

## Test Requirements

- Protocol fixture tests for add/update/remove/list behavior.
- Tests for duplicate path behavior using standardized file URLs.
- Tests proving disabled sources are not returned by enabled-source queries.

## Acceptance Criteria

- Source lifecycle can be tested without macOS adapters.
- View models and services can depend on `SourceStore` without importing persistence.
- The contract does not expose bookmark data directly.

