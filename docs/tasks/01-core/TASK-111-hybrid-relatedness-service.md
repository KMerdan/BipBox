# TASK-111: Hybrid Relatedness Service

## Goal

Implement a production relatedness service that starts with Tier 0 metadata/graph signals and can optionally incorporate Tier 1 Apple NLP or future vector results behind contracts.

## Scope

- Add a `RelatednessService` protocol and default implementation.
- Rank candidates using filename/path tokens, UTType, source, time proximity, capture session, existing relationships, collections, and activity.
- Include explanation strings for why each result matched.
- Optionally consume `VectorIndex` or Apple NLP features only when the spike proves them usable.
- Primary codegraph scope: `SQLiteSearchIndex.swift`, knowledge store from `TASK-108`, `ServiceProtocols.swift`, `SearchWorkspaceViewModel.swift`.
- Change scope: core retrieval service and tests; UI integration is separate.

## Non-Goals

- Do not require embeddings to ship.
- Do not call remote AI providers.
- Do not add Library UI panels in this task.

## Dependencies

- `TASK-110-relationship-collection-services.md`
- `TASK-007-vector-index-contract.md`

## Test Requirements

- Ranking tests for filename, folder, source, time, and collection signals.
- Tests for deterministic tie-breaking.
- Tests that explanations correspond to actual scoring signals.
- Tests proving the service still returns useful results when no vector backend exists.

## Acceptance Criteria

- Relatedness can run locally with Tier 0 signals only.
- Results include machine-readable scores and user-facing explanations.
- Bad or missing optional NLP/vector providers do not break Library search.

