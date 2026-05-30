# TASK-005: Memory Graph Domain Models

## Goal

Add the shared domain types for the retrieval-first memory graph so capture, storage, Library, rules, and AI tools can all talk about the same durable item, context, relationship, and collection concepts.

## Scope

- Extend `Sources/BipboxCore/DomainModels.swift` or add a focused core model file for `KnowledgeItem`, `CaptureEvent`, `ContextNode`, `RelationshipEdge`, `Collection`, and related enums.
- Define stable IDs, provenance fields, confidence fields, item state, context kinds, relationship predicates, and collection kinds.
- Add conversion helpers from existing `OrganizationRequest`, `ItemProfile`, and `IndexedItem` where they are pure domain logic.
- Primary codegraph scope: `DomainModels.swift`, `ServiceModels.swift`, `DefaultOrganizationPipeline.swift`, `SQLiteSearchIndex.swift`.
- Change scope: contracts and codable/equality behavior only; no SQLite implementation.

## Non-Goals

- Do not implement persistence.
- Do not change the organization pipeline behavior.
- Do not add UI.
- Do not add semantic embeddings or relatedness ranking.

## Dependencies

- `TASK-002-domain-models.md`

## Test Requirements

- Unit tests for `Codable`, `Equatable`, default values, confidence bounds, and stable ID behavior.
- Tests proving folders remain first-class `KnowledgeItem` values and are not expanded into child records by model helpers.
- Tests for conversion from `OrganizationRequest` plus `ItemProfile` into a draft `KnowledgeItem` and `CaptureEvent`.

## Acceptance Criteria

- Core memory graph models compile in `BipboxCore`.
- Existing tests still pass without requiring persistence changes.
- Models can represent one file in multiple collections/contexts without duplicating the file item.
- Model docs or inline comments clarify that physical move/copy/rename is optional, not the definition of success.

