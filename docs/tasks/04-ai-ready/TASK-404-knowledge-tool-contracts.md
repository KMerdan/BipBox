# TASK-404: Knowledge Tool Contracts

## Goal

Expose the memory graph and retrieval layer through safe tool contracts so future AI and MCP adapters can inspect, propose, and operate without directly mutating app state.

## Scope

- Register tool descriptors for `knowledge.search`, `knowledge.get_item`, `knowledge.related`, `knowledge.add_relationship`, `knowledge.add_collection`, `knowledge.propose_rule`, `rules.validate`, and `actions.simulate`.
- Support dry-run and permission metadata on every write-capable tool.
- Return structured outputs with IDs, match explanations, provenance, and recoverable errors.
- Primary codegraph scope: `DefaultToolRegistry.swift`, `ToolBackedAIOrchestrator.swift`, `BipboxAppServices.swift`, `RuleDocuments.swift`, relatedness and graph services.
- Change scope: tool descriptors and core handlers; no external MCP server yet.

## Non-Goals

- Do not call a real LLM.
- Do not implement MCP transport.
- Do not allow tools to bypass planner, permission, or store validation.

## Dependencies

- `TASK-110-relationship-collection-services.md`
- `TASK-111-hybrid-relatedness-service.md`
- `TASK-112-graph-aware-rule-actions.md`

## Test Requirements

- Tool registry tests for descriptor shape and permission flags.
- Dry-run tests for relationship and collection writes.
- Tests proving invalid IDs, invalid rules, and unsafe actions are rejected.
- Orchestrator tests proving tool calls are activity-logged.

## Acceptance Criteria

- AI-facing tools can inspect and propose without write permissions.
- Write tools require explicit capability and support dry-run where applicable.
- Tool outputs are structured enough for a future agent to cite and chain.

