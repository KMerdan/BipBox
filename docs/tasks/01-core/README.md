# Batch 01: Core Services

Purpose: implement the platform-light organizer engine and storage services behind protocols.

Tasks:

- `TASK-101-item-inspector.md`
- `TASK-102-workflow-engine.md`
- `TASK-103-operation-planner.md`
- `TASK-104-tool-registry.md`
- `TASK-105-activity-log.md`
- `TASK-106-search-index.md`
- `TASK-107-organization-pipeline.md`
- `TASK-108-knowledge-sqlite-store.md`
- `TASK-109-capture-first-pipeline.md`
- `TASK-110-relationship-collection-services.md`
- `TASK-111-hybrid-relatedness-service.md`
- `TASK-112-graph-aware-rule-actions.md`

Parallelism:

- `TASK-101`, `TASK-102`, `TASK-104`, `TASK-105`, and `TASK-106` can progress independently after the domain contracts exist.
- `TASK-103` depends on workflow decisions and filesystem operation types.
- `TASK-107` integrates the earlier services and should happen later in this batch.
- `TASK-108` starts after memory graph domain models exist.
- `TASK-110` can build on `TASK-108` while `TASK-109` refactors the pipeline.
- `TASK-111` can start with Tier 0 signals after `TASK-110`; optional NLP/vector providers are not required.
- `TASK-112` should wait until relationship and collection services exist so rules can produce graph actions safely.
