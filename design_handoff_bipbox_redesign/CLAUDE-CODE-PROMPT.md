# Paste this into Claude Code (run it from your bipbox repo root)

> Read `design_handoff_bipbox_redesign/README.md` first — it is the spec. The
> Swift blueprint is in `design_handoff_bipbox_redesign/swift-reference/` and the
> interactive reference is `design_handoff_bipbox_redesign/prototype/Bipbox.html`.

---

You are refactoring the Bipbox macOS workspace UI in `Sources/BipboxWorkspaceUI`.
Implement the redesign described in `design_handoff_bipbox_redesign/README.md`,
using the SwiftUI blueprint in `design_handoff_bipbox_redesign/swift-reference/`
as the structural reference. Reuse our existing services and models — do NOT copy
the blueprint's `Sample` data; wire the views to real data.

Hard requirements:
- One grouped sidebar (Library / Watched Folders / Collections / Organize);
  Settings moves to a `Settings { }` scene (Cmd+,), off the main nav.
- A single `Selection` type drives ONE shared `InspectorView`. Move the detail
  panes out of `LibraryWorkspaceView`, `ReviewQueueView`, `RulesWorkspaceView`,
  `ActivityWorkspaceView` into it; delete the now-duplicated per-view actions.
- Fixed 3-column shell (sidebar 252 / center / inspector 344). NEVER add/remove a
  whole column on navigation — only swap content. (Our old UI shifted layout; this
  must not.)
- Inbox = decisions only (remove the watched-source panel from `ReviewQueueView`);
  the decision renders in the inspector.
- New `ConnectionsView`: semantic-zoom graph (Overview clusters -> Cluster ->
  File) backed by `KnowledgeGraphService` relationships; `meta(_:)`/`neighbors(_:)`
  in the blueprint's `WorkspaceModel` are the adapter points.

Work in this PR order, keeping the app building & running after each step. After
each step, build the package and run the app to confirm before moving on:
1. `Selection` + empty `InspectorView` hosted in `WorkspaceRootView`, wired to the
   Library list selection.
2. Regroup the sidebar.
3. Inspector `.item` content incl. the decision block; delete scattered per-view
   action buttons.
4. Inbox panel removal + Sources surface.
5. `Settings { }` scene; drop `.settings` from nav.
6. Library Gallery renderer; then `ConnectionsView` (file-ego first, Overview next).

Before you start: read `WorkspaceRootView.swift`, `WorkspaceState.swift`, the four
workspace view models, `BipboxApplication.swift`, and the Core model files
(`DomainModels.swift`, `MemoryGraphModels.swift`, `SourceModels.swift`,
`RuleDocuments.swift`) so the adapters match real types. Match the exact tokens in
`swift-reference/Theme.swift`. Start with step 1 and show me the diff before
applying.
