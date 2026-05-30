# Batch 04: AI-Ready Architecture

Purpose: reserve the correct boundaries for AI without requiring model-backed classification in the first implementation.

Tasks:

- `TASK-401-ai-gateway-placeholder.md`
- `TASK-402-ai-tool-orchestration.md`
- `TASK-403-ai-classification-node.md`
- `TASK-404-knowledge-tool-contracts.md`
- `TASK-405-mcp-knowledge-adapter-placeholder.md`

Parallelism:

- `TASK-401` can start after service protocols exist.
- `TASK-402` depends on the tool registry contract.
- `TASK-403` depends on the workflow engine and AI gateway protocol.
- `TASK-404` depends on graph, relatedness, and graph-aware rule services.
- `TASK-405` should stay a placeholder until native knowledge tools exist; MCP must remain an adapter, not the internal source of truth.
