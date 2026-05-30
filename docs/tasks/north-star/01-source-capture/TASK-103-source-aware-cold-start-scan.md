# TASK-103: Source-Aware Cold-Start Scan

## Goal

Make initial source scans write source-aware memory, capture events, relationships, search records, and activity entries.

## Scope

- Extend the cold-start scanner request to include source ID or source detail.
- Upsert `KnowledgeItem` records before any policy action.
- Write `CaptureEvent` records for each top-level item scanned.
- Add source/folder context relationships where current graph services support them.
- Update Library search records with source fields and missing/permission state.

## Non-Goals

- No deep recursive scan.
- No AI classification.
- No UI progress redesign beyond existing progress callbacks.

## Dependencies

- `TASK-102-source-lifecycle-coordinator.md`
- `../02-memory-retrieval/TASK-201-knowledge-schema-source-fields.md`

## Test Requirements

- Integration test scanning a watched source with files and folders.
- Test that folder children are not emitted as separate items.
- Test that search and knowledge stores both contain scanned items.
- Test scan failure preserves source record with failed index state.

## Acceptance Criteria

- Library can show items immediately after adding a source.
- Capture events identify which source produced each item.
- Initial scan can be retried without duplicating knowledge items.

