# TASK-401: Memory Action Contracts

## Goal

Define rule/action outputs that enrich memory without requiring physical file movement.

## Scope

- Add or refine action models for add relationship, add to collection, add topic/person/project context, tag, index-only, review, move, copy, and rename.
- Mark action safety, reversibility, and dry-run support.
- Expose memory actions through the existing tool registry where appropriate.

## Non-Goals

- No visual rule editor changes.
- No AI provider.
- No filesystem executor changes unless action contracts require type updates.

## Dependencies

- `../02-memory-retrieval/TASK-204-related-context-service.md`

## Test Requirements

- Codable/action validation tests.
- Dry-run tests for memory actions.
- Tests proving graph-only actions are valid successful outcomes.

## Acceptance Criteria

- A rule can succeed by adding context or collection membership without moving a file.
- Action contracts expose safety metadata for UI and AI tools.
- Existing move/copy/rename actions still work.

