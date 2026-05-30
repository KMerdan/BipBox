# Bipbox Memory Graph Refactor Design

## Purpose

This document captures a product and architecture refactor for Bipbox.

The current app is built around intake, rules, review, move/copy operations, and Library search. That is useful, but it still inherits the old file-organization assumption:

> The right outcome is automatic filing of one item into one destination.

That assumption is structurally weak. Files and folders belong to multiple contexts, future retrieval needs are not predictable at capture time, and any chosen hierarchy decays as projects, people, and meanings change.

The refactor direction is:

> Bipbox should become a local file memory system. It captures items, records context, builds relationships, supports retrieval, and only performs physical organization as one optional action.

This is not a rewrite request. The current pipeline, rules, permissions, search, activity, and UI surfaces remain valuable. The refactor changes the center of gravity from "where should this file go?" to "what is this item connected to, and how will the user find it again?"

## Product Principle

Bipbox should optimize for retrieval and context preservation before folder cleanup.

The explicit product stance:

> Bipbox solves retrieval first, storage second.

That means indexing in place can be a successful outcome. Adding a relationship can be a successful outcome. Creating a virtual collection can be a successful outcome. Physical move/copy/rename is useful, but it is not the default measure of whether Bipbox worked.

The new core promise:

> Bipbox remembers what a file is, where it came from, what it relates to, what happened to it, and how to get it back.

Physical folders stay useful, but they are no longer the only organization model. A file can be in one physical path while belonging to many virtual contexts:

- A project.
- A person or organization.
- A topic.
- A source app or download session.
- A time window.
- A watched folder.
- A user-created collection.
- A rule-created collection.
- A similarity cluster.
- A review or recovery state.

## Engineering Gap

The gap between the current product and the desired product is concentrated in three areas:

1. Relationship graph.
2. Capture coverage.
3. Cold start.

Rules, search, and AI should be redesigned around those three areas instead of becoming more complex versions of extension matching and folder routing.

## Target Architecture

```text
Capture Sources
  -> Identity Resolver
  -> Metadata Extractor
  -> Relationship Graph Writer
  -> Retrieval Index Writer
  -> Policy / Rule / Agent Layer
  -> Optional Action Planner
  -> Activity Log
```

The current organization pipeline maps into the lower half of this architecture. Routing and filesystem operations become optional actions after capture and graph updates.

### Current Pipeline Reframed

```text
Current:
  Intake -> Stabilize -> Inspect -> Route -> Plan -> Execute -> Index -> Log

Refactored:
  Capture -> Stabilize -> Identify -> Inspect -> Record Context -> Index -> Decide -> Act -> Log
```

The important shift is that Bipbox records the item and its context before deciding whether to move it.

## Domain Model

### Knowledge Item

`KnowledgeItem` is the durable object Bipbox knows about. It may point to a file, folder, package, alias, or future external object.

```text
KnowledgeItem
  id
  kind
  display_name
  current_url
  original_url
  bookmark_id
  content_fingerprint
  filesystem_identity
  created_at
  modified_at
  first_seen_at
  last_seen_at
  state
```

`state` examples:

- `active`
- `missing`
- `permission_needed`
- `needs_review`
- `kept_for_later`
- `failed`
- `archived`

### Capture Event

A capture event records how Bipbox learned about an item.

```text
CaptureEvent
  id
  item_id
  source
  source_detail
  received_at
  session_id
  parent_context_id
  raw_url
  requested_mode
```

Sources:

- `menu_bar_drop`
- `watched_folder`
- `manual_import`
- `existing_library_scan`
- `finder_reconnect`
- `agent_request`
- `future_share_extension`
- `future_browser_extension`

### Context

A context is a meaningful grouping or situation. Contexts are not required to map to folders.

```text
Context
  id
  kind
  name
  confidence
  source
  created_at
  updated_at
```

Context kinds:

- `project`
- `person`
- `organization`
- `topic`
- `event`
- `folder`
- `download_session`
- `application`
- `collection`
- `rule`
- `task_state`
- `time_window`

### Relationship

Relationships are typed edges between items and contexts or between two items.

```text
Relationship
  id
  subject_id
  subject_kind
  predicate
  object_id
  object_kind
  confidence
  provenance
  created_at
  updated_at
```

Predicates:

- `belongs_to`
- `came_from`
- `was_captured_in`
- `is_near`
- `is_similar_to`
- `was_moved_by`
- `was_reviewed_by`
- `was_created_by_app`
- `matches_rule`
- `has_topic`
- `mentions_person`
- `replaces`
- `duplicates`

The graph does not need a separate graph database at first. SQLite tables for nodes and edges are enough. A real graph engine can be deferred until traversal or ranking requires it.

### Collection

A collection is a user-visible virtual grouping.

```text
Collection
  id
  name
  kind
  query
  manual_membership_allowed
  created_by
```

Kinds:

- `manual`
- `saved_search`
- `rule_backed`
- `agent_suggested`
- `system`

Collections should behave more like playlists than folders. They can overlap freely.

## Capture Coverage

The capture layer should preserve situation, not just path.

Capture priority should follow daily leverage, not visual prominence:

1. Downloads watcher.
2. Desktop watcher.
3. Manual import and cold-start scan.
4. Menu-bar drop.
5. Finder extension or share extension.
6. Browser extension.

The menu-bar drop is still valuable because it gives the user an explicit capture action and keeps Bipbox visible. But Downloads and Desktop watching are probably higher-leverage because they catch files at the point of ordinary mess creation, without requiring the user to remember a new habit.

### Required Capture Sources

Menu-bar drop:

- Captures explicit user intent.
- Creates one capture session for all items dropped together.
- Does not recursively process folders by default.

Watched folders:

- Captures new top-level items in selected folders.
- Records watched folder identity and scan event.
- Does not recursively process folder contents by default.

Manual import:

- Lets the user add existing files or folders into the memory layer.
- Can be `index_only`, `review`, or `organize`.

Cold-start scan:

- Builds first useful memory from existing folders.
- Should be explicit and permission-based.
- Starts shallow, then deepens only when the user asks.

### Future Capture Sources

Browser extension:

- Adds source URL, page title, referrer, and download context.

Share extension:

- Captures from apps that support macOS sharing.

Finder extension:

- Adds contextual actions from Finder selection.

CLI:

- Lets scripts and power users import/index/search items.

AI/MCP tools:

- Let an agent inspect, relate, and propose actions through controlled tools.

## Cold Start

Cold start decides whether the product feels empty or immediately useful.

The app should not ask the user to configure rules before proving value. The first-run flow should build a useful local memory layer from existing user-selected areas.

### First-Run Flow

1. Choose Library root.
2. Choose starter capture locations:
   - Downloads.
   - Desktop.
   - Documents.
   - Optional project folders.
3. Run shallow scan.
4. Show immediate findings:
   - Recent downloads.
   - Large groups by type.
   - Existing folder-derived contexts.
   - Candidate projects.
   - Items needing attention.
5. Ask only high-value questions:
   - "Should this folder be treated as a project?"
   - "Should this group become a collection?"
   - "Should new PDFs from Downloads be reviewed or auto-tagged?"

### Cold-Start Rules

The system should infer suggestions from existing organization, but not treat existing folders as perfect truth.

Existing folder structure becomes evidence:

```text
Folder path: ~/Documents/Clients/Acme/Invoices

Possible facts:
  item belongs_to organization: Acme
  item has_topic: invoices
  item belongs_to collection: Clients
  confidence: medium
  provenance: existing_folder_scan
```

The user should be able to accept, ignore, or refine these suggestions.

## Retrieval Model

Library becomes the primary product surface.

Retrieval should combine:

- Keyword search.
- Filename/path matching.
- Metadata filters.
- Relationship traversal.
- Recency.
- Collections.
- Activity history.
- Similarity.
- Future semantic search.

Search results should explain why they matched:

```text
invoice-may.pdf
Matched:
  filename contains "invoice"
  belongs to Acme collection
  captured from Downloads last week
  similar to 4 accepted invoice files
```

### Library Views

Recommended Library views:

- Search.
- Recent.
- Collections.
- Projects.
- Sources.
- Missing / Needs Permission.
- Related Files.

Search and Library should not be separate top-level products. Search is a mode inside Library.

### Relatedness Tiers

Related files should be implemented in tiers so the product does not depend on one unproven semantic-search bet.

Tier 0: local metadata and graph retrieval.

- FTS over filename, path, tags, metadata, and extracted text when available.
- Type, folder, source, time, capture session, rule, and activity relationships.
- Works without embeddings.
- Must always ship.

Tier 1: Apple-native lightweight NLP.

- `NLTagger` for language, lexical classes, names, nouns, lemmas, and candidate entities.
- `NLEmbedding` for word-level or token-level similarity where useful.
- Hybrid scoring with metadata and graph signals.
- Must be validated by spike before becoming a product promise.

Tier 2: real embedding provider.

- Local embedding model, remote provider, or pluggable embedding service.
- Used when Tier 1 does not produce ship-quality related results.
- Must stay behind a provider abstraction.

Tier 3: agentic reasoning.

- AI uses search, relatedness, graph, rules, and action tools to explain, propose, and operate.
- It is not the core retrieval substrate.

### One-Day Relatedness Spike

Before building UI around semantic related files, run a one-day spike against a few hundred real personal files.

The gating question:

> Can Apple-native NLP plus graph/metadata signals produce related-file results good enough to show in the product?

The spike should compare three methods:

1. Metadata, FTS, and graph only.
2. Apple NLP only.
3. Hybrid scoring.

Extracted signals:

- Filename tokens.
- Parent folder tokens.
- Extension and Uniform Type Identifier.
- Created, modified, first-seen, and capture-session time.
- Finder tags.
- Spotlight metadata when available.
- Shallow extracted text when cheap.
- `NLTagger` tokens, lemmas, lexical classes, and candidate names.
- `NLEmbedding` vectors or token-neighbor scores where available.

Evaluation should be manual and strict:

- Are the top 3 related items believable?
- Does the top 10 include at least one useful item?
- Are bad matches embarrassing?
- Can the UI explain why each result matched?
- Does the method work across PDFs, Markdown, screenshots, folders, archives, and items with no extracted content?

Pass condition:

> Hybrid relatedness is useful enough to display as "Related" without damaging trust.

If this fails, Tier 1 collapses into Tier 0 for the first release, and real semantic relatedness moves to Tier 2.

## Inbox Model

Inbox is not a generic drop page. It is the uncertainty and decision queue.

Inbox should contain:

- Items needing context decisions.
- Items whose proposed action requires approval.
- Failed operations.
- Permission-needed items.
- Kept-for-later items.
- Watched-folder status.

Inbox should not duplicate Library search. It answers:

> What needs my decision now?

Library answers:

> What do I know, and how do I find it?

## Rules Model

Rules become automation recipes over graph facts and item profiles.

Rules should be able to:

- Add relationships.
- Add items to collections.
- Add Finder tags.
- Suggest destination.
- Move/copy/rename when safe.
- Request review.
- Trigger extraction.
- Trigger agent review later.

A rule should not be limited to one match and one destination.

Example future rule:

```json
{
  "name": "Research PDFs",
  "enabled": true,
  "when": {
    "all": [
      { "typeConformsTo": "com.adobe.pdf" },
      { "textOrNameContainsAny": ["paper", "abstract", "doi", "arxiv"] }
    ]
  },
  "then": [
    { "addCollection": "Research" },
    { "addTopic": "research" },
    { "suggestDestination": "~/Documents/Research" },
    { "requireReviewForMove": true }
  ],
  "fallback": "inbox"
}
```

The UI should remain form-first. JSON remains storage and AI/tooling surface.

## AI And MCP Position

AI should not be designed as a smarter auto-filer. It should be designed as an orchestrator over the memory layer.

AI roles:

- Extract candidate topics, people, projects, and dates.
- Suggest relationships.
- Suggest collections.
- Explain search results.
- Generate or update rules.
- Propose safe cleanup plans.
- Use tools to inspect, search, simulate, and request confirmation.

AI should not directly mutate the database or filesystem. It should use the same tools as user-facing automation.

MCP position:

- Bipbox can expose its tools through a built-in MCP server later.
- Bipbox can consume external MCP servers later.
- The internal source of truth remains the native tool registry.
- MCP is an adapter boundary, not the core architecture.

## macOS Primitives

The refactor should continue to lean on native macOS capabilities:

- Security-scoped bookmarks for durable access.
- FSEvents or polling fallback for watched folders.
- Uniform Type Identifiers for type classification.
- Finder tags for optional native interoperability.
- Spotlight metadata as a metadata source and possible search complement.
- Core Spotlight later if Bipbox records should appear in system search.
- File Provider later only if a Finder-visible virtual Bipbox Library becomes necessary.

File Provider should not be an early dependency. It is too heavy for the current product stage.

## Persistence Direction

SQLite should become the shared durable store for:

- Knowledge items.
- Capture events.
- Metadata snapshots.
- Relationships.
- Collections.
- Search index.
- Review states.
- Activity references.

Recommended initial tables:

```text
file_records
capture_events
context_nodes
relationship_edges
collections
collection_memberships
metadata_snapshots
search_fts
embedding_vectors
activity_events
```

Do not introduce a separate graph database initially. SQLite is local-first, transactional, inspectable, backup-friendly, and already aligned with the current app. Relationship traversal can start with indexed edge tables. If graph traversal becomes a bottleneck later, the storage boundary can be revisited with real workload data.

Vector storage should also start behind an abstraction:

```text
VectorIndex
  upsert_vector(item_id, model_id, vector)
  delete_vector(item_id, model_id)
  nearest(model_id, vector, limit, filters)
```

Candidate implementations:

- Plain SQLite table with brute-force scan for tiny local spikes.
- `sqlite-vec` if it is stable enough for bundled local vector search.
- SQLite `vec1` if it becomes stable enough for app embedding.
- External or local model provider storage later.

The app should not hard-code `sqlite-vec` or any specific embedding provider into the domain layer.

Existing JSON files remain useful for:

- Rule documents.
- Human/AI-editable configuration.
- Diagnostic export.
- Portable workflow definitions.

JSON should not become the main memory store.

## Refactoring Plan

### Phase 0: Relatedness Spike

Run the one-day Apple-native relatedness spike before committing to Tier 1 related-file UX.

Acceptance:

- A local script or throwaway tool can scan a few hundred real files.
- The tool outputs top related candidates by metadata-only, Apple NLP-only, and hybrid ranking.
- Results are manually reviewed and classified as ship-quality, useful-but-secondary, or not trustworthy.
- The decision is recorded in this design doc or a follow-up spike report.

### Phase 1: Core Model

Add durable core types:

- `KnowledgeItem`
- `CaptureEvent`
- `ContextNode`
- `RelationshipEdge`
- `Collection`

Add repository protocols:

- `KnowledgeItemStore`
- `CaptureEventStore`
- `RelationshipStore`
- `CollectionStore`

Acceptance:

- Existing intake can create or update a `KnowledgeItem`.
- Existing index entries can reference `KnowledgeItem.id`.
- Unit tests cover identity updates and relationship writes.

### Phase 2: Capture-First Pipeline

Move graph recording before routing.

Acceptance:

- Dropped and watched items are recorded even when no rule matches.
- Folder items are still treated as first-class items.
- Capture sessions preserve grouped drops.

### Phase 3: Library Graph Retrieval

Extend Library to show:

- Related files.
- Collections.
- Source contexts.
- Missing/permission-needed states.
- "Why this matched" explanations.

Acceptance:

- A user can find an item by name, source, collection, recent capture, or related item.
- Search results can explain at least one match reason.

### Phase 4: Inbox As Decision Queue

Refine Inbox around decision state:

- Needs decision.
- Kept for later.
- Failed.
- Permission needed.
- Rejected.

Acceptance:

- No item disappears without being searchable in Library.
- Kept and failed items are recoverable.
- Watcher status is visible and actionable.

### Phase 5: Rule Actions Over Graph

Extend rules from route-only actions to graph-aware actions.

Acceptance:

- A rule can add a collection relationship without moving the file.
- A rule can require review only for the filesystem action.
- Rule simulation previews graph changes and filesystem changes separately.

### Phase 6: Cold-Start Import

Add first-run or manual cold-start scan.

Acceptance:

- User can scan selected folders into Bipbox without moving anything.
- Existing folders produce suggested contexts and collections.
- User can accept or ignore suggestions.

### Phase 7: AI/Tool Expansion

Expose graph and retrieval operations as tools.

Required tools:

- `knowledge.search`
- `knowledge.get_item`
- `knowledge.related`
- `knowledge.add_relationship`
- `knowledge.add_collection`
- `knowledge.propose_rule`
- `rules.validate`
- `rules.apply_files`
- `actions.simulate`

Acceptance:

- Agent can inspect and propose without write permissions.
- Write tools require explicit capability and can be dry-run.
- Invalid rules or unsafe actions are rejected before activation.

## Non-Goals

This refactor does not require:

- Replacing the current UI immediately.
- Shipping model-backed AI.
- Moving to a graph database.
- Requiring File Provider.
- Recursive watched-folder processing.
- Deleting or hiding normal Finder folders.
- Forcing every item into a collection.

## Product Risks

### Too Abstract

If the UI exposes graph concepts directly, it will feel technical. Users should see Library, collections, related files, sources, and decisions. They should not need to understand graph edges.

### Too Passive

If Bipbox only indexes and never acts, it may feel like a worse Spotlight. Physical actions still matter, but they should be safe, previewable, and optional.

### Too AI-Centered

If the product depends on AI to feel useful, cold start and privacy become fragile. The graph and search layer must work locally first.

### Too Much Capture

If capture feels invasive, users will not trust it. Every source should be permission-based and visible, with pause/resume and clear status.

## Success Criteria

Bipbox is moving in the right direction when:

- A file can belong to multiple contexts without duplication.
- New items are useful in Library even before they are moved.
- Inbox contains unresolved decisions, not all captured files.
- Rules can create metadata and relationships, not just destinations.
- AI can explain and operate through tools, but the product remains useful without AI.
- The user can recover an item by memory, not by remembered folder path.
