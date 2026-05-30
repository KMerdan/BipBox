# Bipbox Design

> Current product direction is now anchored by [Product North Star](product-north-star.md). This older design remains useful implementation background, but where it conflicts with the north-star document, the north-star document wins.

See also:

- [Product North Star](product-north-star.md) for the coherent product goal and user-facing architecture.
- [Memory Graph Refactor Design](memory-graph-refactor.md) for the deeper product/architecture shift from automatic filing to retrieval-first file memory.
- [Release Readiness Design](release-readiness.md) for the stabilization work needed before alpha, beta, and public release.

## Product Goal

Bipbox is a macOS file organization app that gives the user one trusted place to drop, route, search, and recover files or folders. The app should reduce the need to manually browse complex folder structures.

The core promise is:

> Put files or folders into Bipbox. Bipbox decides where they belong, records what happened, and lets you find them later.

## Product Surfaces

### Workspace App

The main macOS GUI. It is used to configure rules, search organized items, review uncertain items, inspect activity, undo operations, and manage permissions.

### Menu-Bar App

The always-available capture surface. It accepts drag/drop items, shows recent activity, exposes quick search, and lets the user pause or resume organization.

### Organizer Service

The background organizer. It watches configured intake folders, stabilizes incoming items, runs workflows, executes filesystem operations, updates the index, and records activity.

For the first implementation, these can live in one app process. The architecture should still keep them separated as modules so the menu-bar surface, workspace, background service, and future AI layer interact through stable interfaces.

## Core Principle: Items, Not Just Files

Bipbox organizes filesystem items.

An item can be:

- A regular file.
- A folder.
- A package or bundle.
- A symbolic link or alias, if supported later.

Folders are first-class organization targets. When the user drops a folder, Bipbox must treat the folder itself as the item to classify, route, move, rename, tag, index, or review.

Bipbox must not automatically walk into a dropped folder and organize its children unless a workflow explicitly says to do so.

This avoids surprising destructive behavior and preserves intentional folder groupings such as project folders, exported archives, design asset sets, and document bundles.

## Intake Sources

Initial intake sources:

- Drag/drop onto the menu-bar item or popover.
- Drag/drop into the workspace app.
- Watched folders such as Downloads or Desktop.
- Manual import from a file picker.

Future intake sources:

- Share extension.
- Browser extension.
- CLI command.
- Automation shortcut.
- AI-created import requests.

Every intake source creates an `OrganizationRequest`.

```text
OrganizationRequest
  id
  source
  item_url
  item_kind
  received_at
  requested_mode
  user_context
```

`requested_mode` can be:

- `organize`: classify and execute automatically if safe.
- `review`: classify and stage for confirmation.
- `index_only`: leave in place but make searchable.
- `simulate`: run rules without modifying anything.

## Organization Pipeline

```text
Intake
  -> Stabilize
  -> Inspect
  -> Route
  -> Plan
  -> Execute
  -> Index
  -> Log
```

### Stabilize

Wait until the item is safe to process.

For files, this means size and modification time are stable. For folders, this means the folder entry itself is stable. Bipbox should not recursively wait for all child files unless the workflow explicitly requests recursive processing.

### Inspect

Build an `ItemProfile`.

```text
ItemProfile
  id
  url
  kind
  display_name
  extension
  uniform_type
  size
  created_at
  modified_at
  source
  finder_tags
  content_hash
  folder_child_summary
  extracted_text_summary
  metadata
```

For folders, `folder_child_summary` should be shallow by default, for example child count, visible file count, top-level extensions, total shallow size if cheap, and whether the folder looks like a package or bundle. Deep recursive inspection is opt-in.

### Route

Run the item through a workflow tree. The router returns a `RouteDecision`.

```text
RouteDecision
  confidence
  matched_rule_ids
  destination
  actions
  reason
  requires_review
```

### Plan

Convert the route decision into a safe executable `OperationPlan`.

```text
OperationPlan
  operations
  expected_result
  conflicts
  reversible
  preview_text
```

### Execute

Run approved operations through the filesystem tool layer. Execution must be logged and reversible when possible.

### Index

Update the Bipbox search index with the final item location, metadata, tags, route history, and searchable text or summaries.

### Log

Record every decision and operation in an append-only activity log.

## Workflow Model

Workflows are tree-like routers.

```text
Workflow
  Root Router
    Branch
      Condition
      Node
    Fallback Node
```

Node types:

- `router`: chooses among branches.
- `condition`: evaluates item metadata.
- `action`: emits filesystem or metadata operations.
- `transform`: prepares values such as destination paths or names.
- `review`: stops and asks for confirmation.
- `ai_classify`: asks the AI layer for a decision.
- `tool_call`: calls a registered app tool.
- `stop`: finalizes the route.

The workflow engine must operate on abstract item profiles and tool interfaces, not directly on UI objects or platform-specific implementation details.

## Match Conditions

Initial match conditions:

- Item kind: file, folder, package, bundle.
- Filename contains, starts with, ends with, or regex.
- Extension.
- Uniform Type Identifier.
- Source folder.
- Size.
- Date created, modified, or received.
- Finder tags.
- Folder shallow summary.

Future match conditions:

- Extracted PDF or document text.
- Image metadata.
- Archive contents summary.
- Duplicate content.
- AI classification.
- Similarity to existing organized items.

## Actions

Initial actions:

- Move item.
- Copy item.
- Rename item.
- Add Finder tags.
- Remove Finder tags.
- Create destination folder.
- Mark as needs review.
- Index in place.
- Open in Finder.

Future actions:

- Extract archive.
- OCR.
- Summarize content.
- Run Shortcut.
- Run script.
- Ask AI to choose between destinations.
- Ask AI to create a new rule suggestion.

All actions are exposed as tools through a registry.

## Tool Abstraction

Bipbox should be built around explicit tools so the future AI layer can operate the app safely.

```text
Tool
  name
  description
  input_schema
  output_schema
  permissions
  dry_run_supported
  reversible
  execute(input, context)
```

Examples:

- `inspect_item`
- `simulate_workflow`
- `create_operation_plan`
- `move_item`
- `rename_item`
- `tag_item`
- `index_item`
- `search_index`
- `open_item`
- `reveal_in_finder`
- `undo_operation`
- `create_rule`
- `update_rule`
- `request_user_review`

Tools must support permission boundaries:

- `read`: inspect metadata or index.
- `plan`: produce a proposal without changing files.
- `write`: modify files or metadata.
- `rule_write`: change workflows.
- `external`: call network, script, Shortcut, or external service.

The AI layer should never bypass tools and mutate app state directly.

## AI Architecture

AI is a planned core capability, not an optional side feature. The first implementation can ship without model-backed decisions, but the architecture must include the AI boundary from the start.

The AI layer has two roles:

1. Classifier: classify an item and suggest route decisions.
2. Operator: use Bipbox tools to inspect, simulate, search, plan, and request confirmation.

AI output must be structured.

```text
AIClassification
  category
  suggested_destination
  confidence
  reason
  required_tools
  requires_review
```

AI can suggest actions, but the operation planner decides whether they are valid and safe.

Automation policy:

- High confidence plus low-risk action: execute if workflow allows it.
- Medium confidence: stage in Needs Review.
- Low confidence: leave in Inbox or Needs Review.
- Any destructive or irreversible operation: require explicit user confirmation.

Privacy policy:

- Local-only metadata classification should be supported first.
- Content sent to any remote model must be opt-in.
- The UI must make it clear which files or summaries are sent to AI.

## Library And Search

Bipbox owns a local search index. Finder remains usable, but Library is the primary retrieval interface for files and folders that Bipbox has organized or indexed.

Initial implementation:

- SQLite database.
- FTS5 text index.
- Metadata filters.
- Activity history.

Searchable records:

```text
IndexedItem
  id
  current_path
  original_path
  display_name
  kind
  uniform_type
  size
  created_at
  modified_at
  imported_at
  routed_at
  rule_id
  tags
  extracted_text
  ai_summary
  status
```

Library search must answer:

- Where did Bipbox put this?
- What files/folders were organized recently?
- What items need review?
- What rule moved this item?
- Can I undo this operation?

## Safety Model

Bipbox must be conservative with user data.

Required guarantees:

- Dry-run simulation for workflows.
- Reversible operation log for move, copy, rename, and tag operations.
- No permanent deletion by default.
- Conflict detection before moving or renaming.
- Duplicate detection by path and optional content hash.
- Folders are not recursively processed by default.
- Needs Review fallback when no confident route exists.
- Pause/resume automation.
- Clear activity log for every operation.

## macOS Implementation Notes

Likely platform choices:

- SwiftUI for the workspace UI.
- AppKit `NSStatusItem` for the menu-bar item.
- FSEvents for watched folders.
- `UniformTypeIdentifiers.UTType` for file and folder type classification.
- Security-scoped bookmarks for persistent access to user-selected folders in a sandboxed build.
- Service Management login item for background startup.
- SQLite plus FTS5 for local search.
- Core Spotlight integration later if exposing Bipbox records to system search is useful.

## MVP Scope

The first useful version should include:

- Native workspace window.
- Menu-bar capture item.
- User-selected library root.
- User-selected watched folders.
- Folder-as-item intake behavior.
- Rule workflow engine.
- Workflow simulation.
- Move, copy, rename, tag, review, and index actions.
- Tool registry abstraction.
- Placeholder AI tool interface with no model requirement yet.
- SQLite search index.
- Activity log.
- Undo for reversible operations.

Deferred:

- Model-backed AI classification.
- OCR.
- Deep content extraction.
- Browser extension.
- Cloud sync.
- Scripting/plugin marketplace.
- Spotlight export.
