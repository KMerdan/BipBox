# TASK-101: Item Inspector

## Goal

Implement item inspection that produces an `ItemProfile` for files and folders without mutating the filesystem.

## Scope

- Determine item kind.
- Collect display name, extension, size, dates, and basic type information.
- Produce shallow folder summaries.
- Avoid recursive folder traversal by default.
- Add hooks for future text extraction and metadata enrichment.

## Non-Goals

- No routing decisions.
- No AI classification.
- No deep content extraction.

## Dependencies

- `TASK-002-domain-models.md`
- `TASK-003-service-protocols.md`
- `TASK-004-test-harness.md`

## Test Requirements

- Unit test for regular file profile.
- Unit test for folder profile.
- Unit test that dropped folder children are not turned into separate organization requests.
- Unit test for shallow folder summary.
- Unit test for missing or inaccessible item error.

## Acceptance Criteria

- Inspector treats folders as first-class items.
- Recursive inspection happens only when explicitly requested by an option.
- Output is deterministic enough for workflow tests.
- No filesystem writes occur during inspection.

