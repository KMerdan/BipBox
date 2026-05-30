# AI Role Design Draft

## Purpose

This draft defines where AI belongs in the semantic Bipbox architecture.

AI should not be a hidden mutator. It should not directly move files, edit SQLite, or rewrite rule files. AI should sit behind explicit service/tool boundaries and produce either semantic facts or proposed actions.

## Primary AI Roles

### 1. Understanding AI

Understanding AI turns file evidence into semantic facts.

Input:

```text
file content
metadata
source facts
folder context
existing graph context
extracted chunks
```

Output:

```text
summary
documentType
project
people
organizations
topics
dates
candidate collections
related item candidates
confidence scores
provenance
```

It answers:

> What is this item?

Example:

```text
invoice-openai-may.pdf
  documentType: invoice
  organization: OpenAI
  topic: AI tools
  timeWindow: May 2026
  confidence: 0.87
```

Understanding AI may suggest facts, but native services decide how facts are validated, stored, corrected, or staged for review.

### 2. Planning AI

Planning AI consumes facts, graph context, rules, policies, and user intent to propose memory or filesystem actions.

Input:

```text
semantic facts
source facts
retrieval results
relationship graph
rules / policies
user preferences
activity history
current file state
```

Output:

```text
proposed relationships
proposed collections
proposed tags
proposed rule changes
proposed rename/move/copy actions
review requests
dry-run tool calls
approval requests
```

It answers:

> What should Bipbox do with this understanding?

Example:

```text
Because documentType = invoice and organization = OpenAI:
  - add to Finance collection
  - link to OpenAI organization context
  - suggest move to Finance/Invoices
  - request review because confidence is below auto-move threshold
```

Planning AI must operate through native tools. It may propose actions and run dry-runs, but approved execution still goes through Bipbox services, safety checks, permissions, and audit logging.

## Secondary AI Roles

These roles are useful, but they should remain subordinate to understanding and planning.

### Retrieval AI

Improves Library search and context discovery.

Responsibilities:

- Natural-language query interpretation.
- Query expansion.
- Result reranking.
- Related item discovery.
- Why-this-matched explanations.

Retrieval AI should not mutate state unless it explicitly proposes a separate memory action.

### Rule Authoring AI

Helps users create or refine semantic policies.

Responsibilities:

- Convert user intent into rule JSON proposals.
- Suggest rules from repeated Inbox decisions.
- Validate rule conflicts.
- Explain what a rule will do.

Rule Authoring AI produces proposals. Rule files are saved and applied only through native rule tools.

### Inbox Explanation AI

Explains uncertain decisions.

Responsibilities:

- Summarize why an item needs review.
- Explain competing interpretations.
- Show confidence and evidence.
- Suggest next actions in user language.

Inbox Explanation AI should make review easier, not bypass review.

### Recovery AI

Helps reconnect missing or moved files.

Responsibilities:

- Match missing records to likely current files.
- Compare names, metadata, fingerprints, semantic facts, and graph context.
- Suggest recovery actions.

Recovery AI proposes candidates; native recovery services perform any accepted update.

### Agent Orchestration AI

Coordinates tools for larger workflows.

Responsibilities:

- Break a user intent into tool calls.
- Retrieve evidence.
- Simulate actions.
- Request approval.
- Execute approved tools.
- Summarize results.

Agent Orchestration AI must use the same native tool registry as UI and MCP paths.

## Boundary Rule

AI can infer and propose. Native services persist and execute.

```text
AI:
  infer facts
  explain evidence
  propose memory updates
  propose filesystem actions
  request approval

Native Bipbox services:
  validate facts
  write memory graph
  save rules
  execute filesystem operations
  enforce permissions
  enforce dry-run and review gates
  audit mutations
```

## Architecture Placement

```text
Capture
  -> Extraction
  -> Understanding AI
  -> Semantic Facts
  -> Memory Graph / Retrieval Index
  -> Planning AI
  -> Proposed Actions
  -> Native Safety Planner
  -> Inbox or Execution
  -> Activity Audit
```

The same item may go through both AI seats:

1. Understanding AI says what the item appears to be.
2. Planning AI decides what to propose based on that understanding.

## Confidence And Review

AI outputs must carry confidence and provenance.

Low-confidence facts should be stored as tentative or staged for review. Low-confidence actions should go to Inbox. Filesystem changes need higher confidence than memory graph updates.

Suggested default posture:

```text
High confidence memory relationship:
  may auto-add with audit

Low confidence memory relationship:
  stage for review

Any destructive or hard-to-reverse filesystem action:
  require review

Semantic-only move/copy:
  require explicit trust threshold or user approval
```

## Product Summary

AI in Bipbox has two main jobs:

```text
Interpreter:
  evidence -> semantic facts

Planner:
  semantic facts + graph + policy -> proposed actions
```

Everything else, including retrieval help, rule authoring, Inbox explanation, recovery, and agent orchestration, supports those two jobs.
