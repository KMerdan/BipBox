# Semantic Filesystem RAG Design

## Purpose

This document describes a more semantic AI direction for Bipbox: a local-first RAG system for the user's filesystem.

The goal is not to build a smarter extension router. The goal is to let Bipbox understand, retrieve, relate, and optionally act on files by meaning.

The product stance:

> Bipbox treats files and folders as evidence for a memory system. Physical filing is one optional action after memory is captured.

## Problem

Traditional file organization assumes that each item should be filed into one correct folder at capture time. That breaks down because:

- A file can belong to several contexts at once.
- Future retrieval needs are not knowable when the file arrives.
- Folder hierarchy decays as projects, clients, tasks, and mental models change.
- Rules such as extension, regex, or watched-folder routing only describe storage behavior, not meaning.
- AI auto-sorters that only choose folders inherit the same lossy model.

The deeper problem is retrieval and context, not filing.

## Target Product Model

Bipbox should answer:

> What is this item, what is it related to, how can the user find it later, and should any safe action happen now?

The default successful outcome is not "moved to a folder." Successful outcomes include:

- Indexed in place.
- Summarized.
- Linked to a project, person, organization, topic, event, source, or collection.
- Connected to related files.
- Made retrievable by natural language.
- Staged for a user decision.
- Moved, copied, or renamed only when policy says that is useful and safe.

## Core Pipeline

```text
Capture
  -> Identity
  -> Extraction
  -> Semantic Understanding
  -> Memory Graph
  -> Retrieval Index
  -> Policy / Agent Decision
  -> Optional Action
  -> Audit
```

This replaces the old mental model:

```text
File appears -> choose destination folder
```

with:

```text
File appears -> understand meaning -> connect to memory -> make retrievable -> optionally act
```

## Capture

Capture records that Bipbox saw an item.

Sources include:

- Watched folders.
- Menu-bar drops.
- Manual imports.
- Existing source scans.
- Future share/browser/CLI/agent captures.

Folders are captured as items by default. Bipbox must not recursively process child files unless a workflow explicitly requests recursive handling.

Capture writes:

```text
FileRecord / KnowledgeItem
CaptureEvent
SourceRecord
ActivityEvent
```

## Identity

Identity prevents duplicated memory when the same file is seen again or moved.

Signals:

- Current path.
- Original path.
- File system identity where available.
- Content fingerprint where practical.
- Bookmark or permission reference.
- Source ID and capture session.
- File size, dates, and basic metadata.

The identity layer decides whether an arrival is:

- A new item.
- A moved known item.
- A duplicate.
- A replacement.
- A missing/recovered item.

## Extraction

Extraction creates raw material for understanding and retrieval.

Extractor examples:

- Text/PDF/DOC: text, title, headings, author, dates.
- Image: OCR, dimensions, visual description, EXIF.
- Audio/video: metadata, transcript where available.
- Folder/package: shallow summary, top-level names, project indicators.
- Code/repo: language, package metadata, README, dependency hints.
- Web/email/archive: title, sender/source, URL, date, body summary.

Extraction should be modular. Each extractor returns:

```text
ExtractedDocument
  itemID
  chunks
  metadata
  warnings
  confidence
  extractorVersion
```

Unsupported files still become indexed items with metadata-only understanding.

## Semantic Understanding

Semantic understanding converts extracted evidence into meaning facts.

Outputs:

- Summary.
- Document type.
- Topics.
- People.
- Organizations.
- Projects.
- Dates and time windows.
- Candidate collections.
- Related item candidates.
- Embeddings.
- Confidence scores.

Example:

```text
contract-final.pdf
  documentType: contract
  project: Client A migration
  organization: Client A
  topic: legal
  date: 2026 Q2
  relatedTo: proposal.docx, invoice.pdf, kickoff-notes.md
  confidence: 0.86
```

This layer should distinguish hard facts from inferred facts:

```text
Hard fact:
  fileExtension = pdf
  sourceName = Downloads

Inferred fact:
  documentType = invoice
  project = Tax 2026
  topic = accounting
```

Every inferred fact needs provenance and confidence.

## Memory Graph

The memory graph is the real organization layer.

Nodes:

- Item.
- Source.
- Project.
- Person.
- Organization.
- Topic.
- Event.
- Collection.
- Folder context.
- Rule.
- Decision.

Edges:

- cameFrom.
- belongsTo.
- mentions.
- similarTo.
- duplicateOf.
- replaces.
- capturedIn.
- matchedRule.
- movedBy.
- reviewedBy.
- addedToCollection.

A file can have many relationships while staying in one physical path.

Example:

```text
invoice.pdf
  cameFrom -> Downloads
  belongsTo -> Finance
  mentions -> OpenAI
  relatedTo -> subscription-email.eml
  capturedIn -> May 2026 downloads session
```

## Retrieval Index

Retrieval is hybrid:

```text
keyword search
+ structured filters
+ vector similarity
+ graph relationships
+ recency/source/status signals
+ user decision history
```

The user should be able to ask:

- "that invoice from the AI tools vendor"
- "files related to Bipbox memory graph design"
- "the deck after the client kickoff"
- "tax documents from last quarter"
- "everything from Downloads that Bipbox was unsure about"

Retrieval results should explain why they matched:

```text
Matched because:
- semantic similarity to "AI tools vendor invoice"
- documentType = invoice
- organization = OpenAI
- cameFrom = Downloads
- imported in May 2026
```

## Rules As Semantic Policy

Rules should not be separate from indexing. Rules consume memory facts.

Current deterministic rule:

```text
IF fileExtension == pdf
THEN move to Documents
```

Semantic policy:

```text
IF documentType == invoice
AND organization is known
AND confidence >= 0.8
THEN add to Finance collection
AND link organization
AND suggest move to Finance/Invoices
```

Rules should support two classes of conditions:

```text
Structured facts:
  extension, kind, source, path, date, status

Meaning facts:
  documentType, project, person, organization, topic, collection, similarity cluster
```

Rules should support confidence:

```text
IF inferred.documentType == invoice
AND confidence(documentType) >= 0.8
THEN auto-apply
ELSE stage for Inbox
```

Rules should produce action proposals, not direct mutation:

```text
Rule Match -> Proposed Memory Actions -> Proposed Filesystem Actions -> Safety Planner
```

Valid rule outcomes:

- Index only.
- Add topic/person/project/org relationship.
- Add to collection.
- Tag.
- Rename.
- Move/copy.
- Ask for review.
- Request AI plan.

## AI Agent

The AI agent is an orchestrator over native tools.

It must not:

- Directly write SQLite.
- Directly edit rule files.
- Directly move/delete files.
- Bypass permission, dry-run, review, or audit checks.

It can:

- Retrieve items.
- Inspect extracted metadata.
- Propose semantic facts.
- Propose relationships.
- Propose or update rules.
- Simulate actions.
- Request approval.
- Execute approved native tools.

Agent loop:

```text
User intent or captured item
  -> retrieve evidence
  -> propose understanding
  -> propose memory/action plan
  -> dry-run native tools
  -> request approval if needed
  -> execute approved native tools
  -> audit everything
```

MCP remains a transport adapter over native tools, not an internal architecture.

## UX Model

### Start / Sources

The user chooses what Bipbox should remember:

- Downloads.
- Desktop.
- Documents.
- Project folders.
- Manual import folders.

A watched source means both:

- index existing top-level items,
- watch future arrivals.

### Library

Library is the main retrieval surface.

It should support:

- Natural language search.
- Filters for kind/source/status/date/context.
- Related items.
- Collections.
- Missing file recovery.
- Why-this-result explanations.

### Contexts

Contexts are the user-visible graph.

Examples:

- Projects.
- People.
- Organizations.
- Topics.
- Events.
- Collections.

Opening a context shows related files without requiring those files to live in the same folder.

### Inbox

Inbox is for uncertain or risky decisions.

Examples:

- "I think this is an invoice for OpenAI. Add to Finance?"
- "This looks related to Project X, but confidence is low."
- "Move proposal conflicts with an existing file."
- "This rule would rename a folder. Approve?"

Inbox should show:

- The evidence.
- The proposed memory updates.
- The proposed filesystem action if any.
- Confidence.
- Safety warnings.
- Approve, edit, keep for later, reject.

### Rules

Rules become policy management, not raw JSON editing.

The UI should render forms:

- Trigger facts.
- Meaning conditions.
- Confidence thresholds.
- Outcomes.
- Safety behavior.

JSON remains the synced storage and AI-editable surface, but not the primary user interface.

### Activity

Activity is the trust layer.

It records:

- Capture.
- Extraction.
- Semantic inference.
- Retrieval/index updates.
- Rule matches.
- Agent tool calls.
- User decisions.
- Filesystem operations.
- Graph mutations.

## Storage Architecture

Recommended first implementation:

```text
SQLite
  items
  sources
  capture_events
  extracted_documents
  chunks
  semantic_facts
  graph_nodes
  graph_edges
  collections
  activity_events
  vector_records
```

A separate graph database is not required initially. SQLite plus graph tables and vector search is enough until traversal/ranking needs prove otherwise.

Vector storage options:

- SQLite table with custom vector extension if available.
- SQLite + sqlite-vec if practical.
- Local file-backed vector index behind `VectorIndex` protocol.

The important boundary is the protocol, not the first backend.

## Privacy Model

Default posture:

- AI off.
- Local-only on.
- Content sharing off.
- Metadata-only on.
- Audit logging on.

Remote providers must be explicit opt-in.

Content sent to any remote model must be controlled by settings and visible in activity/audit logs.

The app should support local-only extraction and embedding first where practical.

## Safety Invariants

- Capture and index before any move/copy/rename/delete.
- Folder-as-item by default.
- No silent fallback destination.
- Risky or low-confidence actions go to Inbox.
- Every mutation goes through native services/tools.
- Every mutation is audited.
- Rules and AI produce proposals; planners enforce safety.
- Dry-run must be available for write-capable tools.

## Relationship To Current Bipbox

Current Bipbox already has useful foundation:

- Sources.
- Source-aware capture.
- Index-before-action pipeline.
- Library retrieval.
- Rule JSON storage.
- Form-first rules.
- Activity audit trail.
- Native AI/MCP tool boundary.
- Privacy settings.

The missing semantic layer is:

- Rich extracted document/chunk model.
- Embeddings.
- Semantic facts with confidence/provenance.
- Stronger graph retrieval/ranking.
- Meaning-based rules.
- Agent planning over semantic evidence.

## Implementation Phases

### Phase 1: Semantic Evidence Store

- Add extracted document and chunk models.
- Store extraction metadata and warnings.
- Keep extraction local.
- Index chunks for keyword retrieval.

### Phase 2: Local Embedding Spike

- Run local embedding on a real personal file sample.
- Measure whether related results are useful enough.
- Decide whether local vectors are product-grade or only a fallback tier.

### Phase 3: Semantic Facts

- Add semantic fact schema:

```text
itemID
factType
value
confidence
provenance
evidenceChunkIDs
createdAt
modelOrExtractorVersion
```

- Render facts in Library details.
- Use facts in retrieval explanations.

### Phase 4: Graph-Ranked Retrieval

- Combine keyword, vector, graph, source, status, and recency scores.
- Explain result ranking.
- Add context pages.

### Phase 5: Meaning-Based Rules

- Extend rule conditions to semantic facts and confidence thresholds.
- Add policy actions for graph updates and collections.
- Stage low-confidence semantic matches for Inbox.

### Phase 6: Agent Planning

- Let the agent propose facts, relationships, collections, and policies.
- Require dry-run and approval for mutations.
- Keep MCP as a transport adapter over the same native tools.

## Open Questions

- Are local embeddings good enough on the user's real files?
- Which file types are highest leverage for first-class extraction?
- Should semantic facts be user-editable directly, or only correctable through decisions?
- How much hierarchy should Library expose before it starts feeling like Finder again?
- What confidence threshold is safe for automatic graph updates?
- What confidence threshold is safe for filesystem moves?
- Should physical move ever be automatic for semantic-only matches, or should it require explicit user trust over time?

## Success Criteria

Bipbox succeeds when the user can stop thinking:

> Where did I file that?

and start relying on:

> Bipbox remembers the source, meaning, relationships, and history well enough that I can find it again.

The long-term product is not a folder sorter. It is a local memory layer for the filesystem.
