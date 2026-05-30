# TASK-007: Vector Index Contract

## Goal

Define a provider-neutral vector index boundary so embeddings can be stored and queried later without hard-coding `sqlite-vec`, SQLite `vec1`, a local model, or a remote provider into core domain logic.

## Scope

- Add a `VectorIndex` protocol and request/result models in `BipboxCore`.
- Include `modelID`, vector dimension, item ID, score/distance, limit, and optional filters.
- Define explicit errors for dimension mismatch, unsupported model, unavailable backend, and invalid query limits.
- Primary codegraph scope: `ServiceProtocols.swift`, `DomainModels.swift`, `SQLiteSearchIndex.swift`, `ToolBackedAIOrchestrator.swift`.
- Change scope: protocol and tests only; no concrete vector backend.

## Non-Goals

- Do not add `sqlite-vec` or any native extension.
- Do not implement embedding generation.
- Do not expose vector search in the UI.

## Dependencies

- `TASK-005-memory-graph-domain-models.md`

## Test Requirements

- Unit tests for vector request validation.
- Mock vector index tests proving nearest-neighbor results can be consumed without knowing the backend.
- Tests for model ID separation so two embedding models cannot silently mix results.

## Acceptance Criteria

- Core services can depend on `VectorIndex` without importing platform or persistence modules.
- The contract can represent brute-force, `sqlite-vec`, SQLite `vec1`, local model, or remote provider backends.
- No production code assumes embeddings exist.

