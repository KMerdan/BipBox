# TASK-004: Test Harness

## Goal

Create reusable test utilities for filesystem sandboxes, workflow fixtures, item fixtures, and deterministic clocks.

## Scope

- Temporary directory helper.
- Fixture item builder for files and folders.
- Deterministic clock or date provider.
- Sample workflow fixtures.
- Mock tool registry.
- Mock search index.

## Non-Goals

- No production behavior.
- No snapshot test framework unless needed later.

## Dependencies

- `TASK-001-project-scaffold.md`
- `TASK-002-domain-models.md`

## Test Requirements

- Tests for the test helpers themselves where failure would hide real bugs.
- A sample test that creates a file and a folder in an isolated temp directory.

## Acceptance Criteria

- Tests never touch real user folders.
- Test fixtures support both file and folder items.
- Helpers make it easy to verify non-recursive folder behavior.
- The harness can be reused by core, persistence, and macOS adapter tests.

