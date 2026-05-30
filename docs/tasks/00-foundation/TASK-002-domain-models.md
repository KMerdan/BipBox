# TASK-002: Domain Models

## Goal

Define platform-light domain models for items, organization requests, item profiles, route decisions, operation plans, workflow nodes, tools, and indexed records.

## Scope

- Define `ItemKind`: file, folder, package, bundle, symlink, unknown.
- Define `OrganizationRequest`.
- Define `ItemProfile`.
- Define `FolderChildSummary`.
- Define `RouteDecision`.
- Define `OperationPlan`.
- Define `Workflow`, `WorkflowNode`, `Branch`, and condition/action descriptors.
- Define `IndexedItem`.
- Make models serializable where needed.

## Non-Goals

- No rule evaluation.
- No filesystem access.
- No database access.
- No UI models unless they are plain projections.

## Dependencies

- `TASK-001-project-scaffold.md`

## Test Requirements

- Unit tests for JSON encoding and decoding of public persisted models.
- Unit tests that verify a folder can be represented as an item without child expansion.
- Unit tests for stable IDs or identity behavior if implemented.

## Acceptance Criteria

- Core domain models compile without importing SwiftUI or AppKit.
- Folder-as-item behavior is explicit in the model.
- Recursive folder processing is represented only as an explicit workflow/action option.
- Persisted models have versioning or a documented migration placeholder.

