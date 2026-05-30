# Bipbox Product North Star

## Purpose

This document resets Bipbox around one consistent goal.

The project has drifted between three ideas:

- Auto-file downloads into folders.
- Manage an Inbox of uncertain file decisions.
- Build a retrieval-first memory graph.

Those are not equal product centers. If they compete, the app becomes confusing. The coherent product is:

> Bipbox is a local file memory and retrieval system for macOS. It watches user-chosen sources, remembers files and folders in context, makes them searchable and relatable, and only performs physical filing as an optional, safe action.

The goal is not to make a smarter folder sorter. The goal is to make the user stop depending on fragile folder hierarchy as the only way to remember where things are.

## Product Promise

The user should be able to trust this statement:

> Add folders and drops to Bipbox. Bipbox remembers what it saw, where it came from, what it relates to, what happened to it, and how to get it back.

Physical organization still matters, but it is not the primary success condition. A file can stay where it is and still be successfully organized if Bipbox can retrieve it, explain it, and connect it to useful contexts.

## Non-Goals

Bipbox should not be:

- A magical auto-filer that silently moves everything into one hierarchy.
- A rule editor that requires setup before the product proves value.
- A duplicate Finder with prettier search.
- An AI chatbot that directly mutates files or internal state.
- A recursive folder processor that explodes project folders into unrelated child items by default.

## Core Principles

### 1. Retrieval First, Storage Second

Every captured item should become findable before any move/copy/rename decision is made.

Valid successful outcomes:

- Index in place.
- Add relationships.
- Add to a collection.
- Tag.
- Stage for decision.
- Move/copy/rename when explicitly safe.

Physical filing is one action type, not the product center.

### 2. Sources Are First-Class

A source is a folder or capture surface Bipbox watches or imports from.

Examples:

- Downloads.
- Desktop.
- Documents.
- Project folders.
- Menu-bar drops.
- Manual imports.
- Future browser/share/CLI captures.

A watched folder means:

1. Bipbox has persistent permission to access it.
2. Bipbox indexes existing top-level items when the source is added.
3. Bipbox watches future top-level arrivals.
4. Bipbox records capture events for items from that source.

There should be no separate user-facing concept of "index existing folder" versus "watched folder" for normal setup. A watched source is indexed and watched.

### 3. Folders Are Items

Files, folders, packages, and bundles are all items.

Dropping or watching a folder captures the folder itself as one item. Bipbox must not walk into it and process children unless a workflow explicitly requests recursive handling.

### 4. The Memory Graph Is The Organization Layer

Folders are one organization signal. They are not the only structure.

Bipbox should remember:

- Source folder.
- Original path.
- Current path.
- Capture session.
- Parent folder context.
- File type and metadata.
- Extracted text or summaries where available.
- Similar items.
- Related projects, topics, people, organizations, and collections.
- Rule and action history.

The user should be able to retrieve by any of those signals.

### 5. Automation Is Policy Over Memory

Rules should operate on item profiles and graph facts. They should not be limited to extension-to-folder routing.

Rule outcomes can include:

- Add to collection.
- Add topic/person/project relationship.
- Tag.
- Index only.
- Ask for review.
- Move/copy/rename.

The default fallback is Inbox, not an arbitrary folder.

### 6. AI Is An Orchestrator, Not A Secret Mutator

AI is part of the architecture, but it must operate through the same tool contracts as the UI and rules.

AI can:

- Search the Library.
- Inspect item metadata.
- Suggest relationships.
- Propose rules.
- Simulate actions.
- Request approved tool calls.

AI cannot:

- Directly edit the database.
- Directly move files.
- Bypass dry-run and permission checks.
- Send file content to a provider without explicit user-visible privacy settings.

MCP is an adapter boundary for tools, not the internal source of truth.

## Product Surfaces

### Start: Source Management

Start is not a marketing/onboarding page after first launch. It is the home for source setup.

It should show:

- Current watched sources.
- Permission state per source.
- Index/watch state per source.
- Last scan time and result.
- Actions: Add Folder, Change, Remove, Rescan, Pause/Resume.

Adding a folder should:

1. Open a path selector.
2. Save a security-scoped bookmark.
3. Upsert a durable source record.
4. Run an initial shallow index.
5. Start watching future top-level arrivals.
6. Show progress and errors inline.

The user-facing model is:

> These are the places Bipbox remembers from.

### Library: Primary Retrieval Surface

Library is the main product surface. Search is part of Library, not a separate top-level product.

Library should answer:

- Where is this thing?
- Why did this match?
- What is related to it?
- What project/topic/person/source does it belong to?
- What happened to it?
- Is it missing or permission-blocked?

Library views:

- Search.
- Recent captures.
- Sources.
- Collections.
- Contexts.
- Related items.
- Missing or permission-needed items.

Result cards should show:

- Name.
- Current path.
- Source.
- Last seen date.
- Match reason.
- Status.
- Actions: Open, Reveal, Related, Add to Collection, Reindex, Locate if missing.

### Inbox: Decisions And Recovery

Inbox is not source setup and not general search.

Inbox contains only things that need user attention:

- Ambiguous rule or AI decision.
- Risky filesystem action.
- Permission problem.
- Failed action.
- Kept-for-later decision.
- Rejected item that can be restored or dismissed.

Inbox should answer:

- What needs my decision?
- What will happen if I approve?
- What failed and how do I recover?

Actions:

- Approve.
- Change plan.
- Keep for later.
- Retry.
- Reject.
- Restore.
- Dismiss.

Inbox may show a compact source health summary, but source management belongs in Start.

### Rules: Automation Recipes

Rules are optional acceleration. The app must be useful before rules exist.

Rules should be form-first for users and JSON-backed for storage/tooling.

Rule editor model:

- Name.
- Enabled.
- Conditions.
- Outcome.
- Review requirement.
- Apply.

Rules can produce graph outcomes, not only filesystem outcomes.

JSON is:

- The durable rule storage format.
- The AI/tooling surface.
- Not the normal user editing surface.

### Activity: Audit And Undo

Activity is the operational ledger.

It should show:

- Captures.
- Indexes.
- Relationship changes.
- Rule matches.
- Filesystem operations.
- Review decisions.
- AI/tool calls later.
- Errors.

Every mutation should be explainable from Activity. Reversible filesystem actions should expose undo.

### Settings: Preferences And Privacy

Settings should not be where source folders are managed.

Settings owns:

- Library storage location.
- Automation global pause.
- Privacy and AI provider settings.
- Diagnostic export.
- Logs.
- App startup behavior.

## Durable Data Model

The app should stop treating source state as view-model memory.

### SourceRecord

Source records describe places Bipbox captures from.

```text
SourceRecord
  id
  kind                 watched_folder | menu_bar_drop | manual_import | future_browser | future_share | future_cli
  display_name
  url
  permission_record_id
  enabled
  recursive_policy     never | explicit | always
  initial_index_state  pending | running | completed | failed
  watch_state          stopped | running | paused | permission_needed | missing | error
  last_scan_at
  last_scan_summary
  created_at
  updated_at
  metadata
```

Initial storage can be `sources.json` or a SQLite table. Long term, source records should live beside the knowledge store in SQLite. Security-scoped bookmark data can remain in `permissions.json` or move behind the same store later.

Important boundary:

- `PermissionRecord` answers: can Bipbox access this path?
- `SourceRecord` answers: should Bipbox capture from this path and what is its operational state?

The current implementation partially conflates those concepts. That is acceptable as a temporary bridge, but the product design should not.

### KnowledgeItem

```text
KnowledgeItem
  id
  kind
  display_name
  current_url
  original_url
  source_id
  content_fingerprint
  filesystem_identity
  created_at
  modified_at
  first_seen_at
  last_seen_at
  state
```

States:

- active
- missing
- permission_needed
- needs_review
- kept_for_later
- failed
- archived

### CaptureEvent

```text
CaptureEvent
  id
  item_id
  source_id
  source_kind
  raw_url
  received_at
  session_id
  requested_mode
  source_detail
```

### ContextNode

```text
ContextNode
  id
  kind                 project | person | organization | topic | event | folder | source | collection | rule | time_window
  name
  confidence
  source
  created_at
  updated_at
```

### RelationshipEdge

```text
RelationshipEdge
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

Useful predicates:

- belongs_to
- came_from
- was_captured_in
- is_near
- is_similar_to
- mentions
- matches_rule
- was_moved_by
- duplicates
- replaces

### Collection

Collections are virtual groupings. They behave like playlists, not folders.

Kinds:

- manual
- saved_search
- rule_backed
- agent_suggested
- system

One item can belong to many collections.

## Core Runtime Flow

### Add Watched Source

```text
Choose folder
  -> save permission bookmark
  -> upsert SourceRecord
  -> shallow scan current top-level items
  -> upsert KnowledgeItems
  -> write CaptureEvents
  -> infer folder/source contexts
  -> update Library index
  -> start watcher
  -> log activity
```

No file moves are required in this flow.

### New Watched-Folder Arrival

```text
Watcher detects top-level item
  -> stabilize
  -> identify or create KnowledgeItem
  -> inspect metadata
  -> record source/capture relationships
  -> index for retrieval
  -> evaluate policy/rules
  -> either apply safe actions or stage Inbox decision
  -> log activity
```

The item should be findable in Library even if policy/rule evaluation fails.

### Menu-Bar Drop

```text
Drop item(s)
  -> create capture session
  -> process each item as file/folder/package
  -> record explicit user capture context
  -> index first
  -> optional policy/action
```

Folder drops remain one folder item.

### Inbox Decision

```text
User opens decision
  -> sees item context and proposed plan
  -> approves, modifies, keeps, rejects, retries, or dismisses
  -> state updates in knowledge store and search index
  -> activity records the decision
```

### Library Retrieval

```text
Query or browse
  -> search lexical index
  -> blend graph signals
  -> show explainable results
  -> allow open/reveal/related/reindex/locate actions
```

## Matching And Ranking

Tier 0 retrieval should be local and deterministic:

- Filename tokens.
- Path and parent folder tokens.
- Extension and UTType.
- Source.
- Capture date and modified date.
- Tags.
- Extracted text where cheap.
- Activity history.
- Graph relationships.

Tier 1 can add local embeddings if the quality is proven by a real-file spike.

Tier 2 can add model-backed AI, but only as an optional provider behind privacy controls.

AI should improve explanation, suggestion, and recovery. It should not be the only retrieval substrate.

## Safety Rules

Always true:

- Index before action.
- No recursive folder processing by default.
- No silent fallback destination.
- No destructive action without a reversible plan or explicit review.
- Permissions are explicit and recoverable.
- Missing files are marked missing, not forgotten.
- Activity records every mutation.
- AI/tool calls are audited.

## First Useful Alpha

The alpha should prove one coherent loop:

1. User adds Downloads or another folder as a watched source.
2. Bipbox indexes current top-level items.
3. Library immediately shows those items.
4. New top-level arrivals appear in Library automatically.
5. Ambiguous/risky items appear in Inbox.
6. User can approve or recover decisions.
7. User can search by name, source, type, date, and related context.
8. Optional simple rules can tag, collect, review, or move.

This is releasable for self-use before advanced AI, complete rule editing, notarization, or polished onboarding.

## Immediate Refactor Direction

The next implementation wave should align code to this design:

1. Add a real `SourceStore` and `SourceRecord`.
2. Move Start from onboarding selections to source management backed by `SourceStore`.
3. Keep `PermissionStore` focused on bookmarks and permission state.
4. Make cold-start scan write capture events and relationships for each source.
5. Ensure watched-folder arrivals are indexed before rules/actions.
6. Keep Inbox as decision/recovery only.
7. Keep Library as the primary search and relationship surface.
8. Move Rules toward graph-aware outcomes.

## Decision Filter

When deciding whether to add or change a feature, ask:

1. Does this improve capture coverage?
2. Does this preserve context?
3. Does this improve retrieval?
4. Does this make decisions safer or more recoverable?
5. Does this keep physical filing optional?

If the answer is no to all five, it is probably not core Bipbox.
