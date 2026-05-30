# TASK-105: Menu-Bar And Manual Source Events

## Goal

Represent menu-bar drops and manual imports as source-aware capture events without pretending they are watched folders.

## Scope

- Add source detail for menu-bar drop sessions and manual imports.
- Create capture sessions for multi-item drops.
- Ensure dropped folders remain one item.
- Index captured items before optional rule/action evaluation.
- Preserve existing menu-bar UI behavior while adding memory context.

## Non-Goals

- No new drag/drop visual design.
- No browser/share extension.
- No AI decision making.

## Dependencies

- `../00-contracts/TASK-003-memory-capture-contracts.md`
- `../02-memory-retrieval/TASK-201-knowledge-schema-source-fields.md`

## Test Requirements

- Tests for multi-item menu-bar drop sharing a capture session.
- Tests for manual import source kind.
- Tests that dropped folders are not recursively processed.
- Tests that captured items are searchable even when rules fail.

## Acceptance Criteria

- All capture paths share the same source-aware memory contract.
- Menu-bar drops and manual imports are visible in Library as captured items.

