# TASK-112: Graph-Aware Rule Actions

## Goal

Extend rule actions so workflows can enrich the memory graph without moving files, making "add collection", "add topic", and "add relationship" valid successful automation outcomes.

## Scope

- Extend action descriptors and workflow execution planning for graph-only actions.
- Add planner output that separates graph mutations from filesystem operations.
- Update rule JSON validation and conversion so AI/tooling can create graph-aware rules safely.
- Keep existing simple extension-to-destination rules working.
- Primary codegraph scope: `RuleDocuments.swift`, `DefaultWorkflowEngine.swift`, `DefaultOperationPlanner.swift`, `DefaultOrganizationPipeline.swift`, `RulesWorkspaceViewModel.swift`.
- Change scope: core rules/planning and tests; visual rule editor expansion is separate.

## Non-Goals

- Do not add a full nested-router visual editor.
- Do not make graph actions perform filesystem writes.
- Do not expose raw JSON buttons in user-facing Rules UI.

## Dependencies

- `TASK-110-relationship-collection-services.md`

## Test Requirements

- Rule document tests for graph action encoding/decoding.
- Workflow tests for rules that only add collection/topic relationships.
- Planner tests proving graph-only actions do not require destination paths.
- Pipeline tests proving review can apply to filesystem actions while graph enrichment remains safe.

## Acceptance Criteria

- A rule can add a file to a collection without moving it.
- Rule simulation previews graph changes separately from filesystem changes.
- Existing rules load and behave as before.

