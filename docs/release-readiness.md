# Bipbox Release Readiness Design

## Purpose

This document turns the current release blockers into a concrete stabilization design for a self-use alpha, private alpha, and public beta.

Bipbox already has the main product shape: menu-bar intake, Inbox review, watched-folder intake, rules, Library search, activity, persisted settings, and JSON-backed rule files. The remaining work is less about inventing the product and more about making the behavior understandable, recoverable, and safe enough to trust with real folders.

## Release Levels

### Self-Use Alpha

Goal: one developer can safely use Bipbox on a real Downloads folder.

Required:

- Clear watched-folder status and manual scan.
- Permission recovery for watched folders and library root.
- Inbox can recover from keep-later, rejected, and failed states.
- Rules can express the common routing cases needed for daily use.
- Library can find organized items and reveal missing paths clearly.
- Local logs can be exported for debugging.

Not required:

- Signed installer.
- Public onboarding polish.
- Model-backed AI.
- MCP external interoperability.

### Private Alpha

Goal: a small number of trusted testers can install, use, and report problems.

Required:

- Signed app build.
- First-run setup flow.
- More complete rule editing.
- Better Library search ranking and missing-file repair.
- Clear permission prompts and recovery.
- Diagnostic export bundle.

### Public Beta

Goal: users outside the development group can evaluate the app without hand-holding.

Required:

- Notarized app distribution.
- Crash/error reporting strategy.
- Stable onboarding.
- Strong filesystem safety audit.
- Explicit AI/MCP disabled-or-enabled product story.

## Watcher UX

Watched folders are first-class intake sources and belong in Inbox, not Settings. Inbox should show both manual/menu-bar intake and watched-folder intake because both produce the same outcome: an item either gets routed automatically or waits for a decision.

### Current Gap

The watcher pipeline can detect new top-level items and submit them to the organization pipeline, but the UI does not yet show operational health well enough.

### Design

Inbox should show an Intake panel with one row per watched folder:

```text
Downloads
Status: Watching
Last scan: 12:41 PM
Last result: 2 organized, 1 sent to Inbox
[Scan Now] [Pause] [Remove]
```

Folder states:

- `watching`: active and scanning.
- `paused`: configured but not scanning.
- `permission_needed`: bookmark missing, stale, or denied.
- `missing`: folder path no longer exists.
- `error`: last scan failed.

### Required Behavior

- Adding a watched folder starts watching immediately when automation is running.
- Removing a watched folder stops its watcher.
- Pause/resume automation controls watcher lifecycle.
- Manual `Scan Now` submits new top-level items immediately.
- Watchers should not recursively process folder contents.
- Each scan should record counts: discovered, organized, staged, failed.
- Errors should be per-folder, not only global.

### Acceptance

- User can tell whether a watched folder is active.
- User can force a scan without restarting the app.
- User can recover from a missing permission or missing path.
- A new file in a watched folder follows the same rules as a menu-bar drop.

## Permission Handling

### Current Gap

Security-scoped bookmarks exist, but the UI does not clearly explain permission state or how to repair it.

### Design

Permissions should be presented where they affect the user:

- Inbox: watched-folder permissions.
- Settings: library root and global app preferences.
- Rules: destination-folder permission issues when a rule points outside granted areas.

Each permission row should expose:

- Folder path.
- State: granted, stale, missing, denied.
- Action: `Reconnect`, `Choose Replacement`, `Remove`.
- Short reason from the permission store.

### Required Behavior

- `Reconnect` opens an `NSOpenPanel` pointing at the last known folder.
- Reconnected folders update the stored bookmark.
- Stale bookmarks are treated as recoverable warnings.
- Missing bookmarks stop automation for that watched folder until repaired.
- Permission errors must never silently fall back to moving files somewhere else.

### Acceptance

- User understands why a folder is not being watched.
- User can repair a watched folder permission from Inbox.
- User can repair library root permission from Settings.

## Rules UI

### Current Gap

The Rules UI supports simple extension-to-destination editing. That is enough for early smoke testing but not enough for the tree-like workflow/router model.

### Design

Rules should stay form-first. JSON is storage and AI/tooling surface, not the normal user editor.

Top-level UI:

```text
[New Rule] [Delete]

Rule form
  Name
  Enabled
  Match conditions
  Action
  Destination
  Review requirement
  [Apply]
```

Rule editor capabilities:

- Multiple conditions with `all` / `any` grouping.
- Conditions for kind, extension, type identifier, source, folder summary, name contains, size range, and date range.
- Actions for move, copy, rename, tag, review, and no-op/index-only.
- Review requirement toggle for risky rules.
- Rule order with drag reordering.
- Test rule against a selected item.

Router workflow capabilities:

- A root router containing ordered branches.
- Optional nested routers later, but not required for alpha.
- Fallback is always Inbox unless explicitly changed.

### AI/JSON Boundary

AI tools can read/write rule JSON through controlled tools:

- `rules.apply_files`
- future `rules.create`
- future `rules.update`
- future `rules.validate`
- future `rules.simulate`

The user should not need JSON buttons in the Rules UI.

### Acceptance

- User can create useful rules without editing JSON.
- Rule changes apply to the active workflow without restart.
- AI/tooling can still modify JSON-backed rules safely.
- Invalid AI-generated rules are rejected before becoming active.

## Inbox Polish

### Current Gap

Inbox is now the right conceptual home for intake, but item lifecycle states need better recovery and clearer empty states.

### Design

Inbox should be split conceptually into:

- Intake: watched folders and drop status.
- Decisions: items that need user action.

Decision filters:

- Needs decision.
- Kept for later.
- Failed.
- Rejected.
- All.

Item actions:

- `Approve`: execute the current plan and remove from Inbox.
- `Change Destination`: update plan before approval.
- `Keep for Later`: keep visible under a dedicated filter.
- `Retry`: rerun routing/planning for failed or kept items.
- `Reject`: mark rejected, with option to restore.
- `Dismiss`: hide from Inbox after user accepts the state.

### Required Behavior

- Keep for later must be recoverable and visible.
- Rejected items can be restored or dismissed.
- Failed items show the exact failure and provide retry.
- Empty states distinguish between no watched folders, no pending items, and automation paused.

### Acceptance

- User never loses track of an item because of an unclear state.
- Failed automation does not require database inspection to recover.
- Inbox makes it obvious what will happen before approving.

## Library Search

### Current Gap

Library search works through the local index, but result quality and missing-file behavior are basic.

### Design

Library should be the retrieval surface for everything Bipbox has touched.

Search improvements:

- Rank filename/path matches above metadata-only matches.
- Tokenize filenames, extensions, and folder names.
- Support quoted exact search.
- Support filters for kind, status, date, rule, and tags.
- Show recent organized items when search is empty.

Missing path handling:

- If an indexed path no longer exists, mark result as missing.
- Offer `Locate`, `Remove from Library`, and `Reindex`.
- Reindex should update metadata without duplicating records.

### Acceptance

- User can find where Bipbox put an item.
- Missing files are clearly identified.
- Revealing a missing result does not fail silently.
- Reindexing repairs stale metadata.

## Packaging, Signing, And Notarization

### Current Gap

The app can be built locally, but there is no release-grade macOS distribution path.

### Design

Release pipeline:

```text
swift test
build app bundle
codesign
notarize
staple
package dmg or zip
verify fresh install
```

Required artifacts:

- Signed `.app`.
- Notarized `.dmg` or `.zip`.
- Versioned release notes.
- Reproducible build script.

### Acceptance

- App launches on a clean machine without Gatekeeper warnings.
- Release artifact includes version/build metadata.
- CI or a documented local release command can produce the artifact.

## Onboarding And First Run

### Current Gap

The app assumes the user already knows what to configure.

### Design

First-run setup should be short and operational:

1. Choose Library root.
2. Add first watched folder, usually Downloads.
3. Create starter rules or accept defaults.
4. Explain Inbox: auto-routed items disappear into Library; uncertain items wait for approval.
5. Confirm privacy defaults: AI content sharing off.

### Acceptance

- A new user can set up Bipbox without reading docs.
- The first watched folder starts working after setup.
- Defaults are conservative and reversible.

## Crash, Error Reporting, And Log Export

### Current Gap

Activity logs exist, but there is no user-facing diagnostic export.

### Design

Add `Export Diagnostics`:

```text
diagnostics.zip
  app-settings.json
  permissions-redacted.json
  rules/
  activity.log
  recent-errors.log
  search-index-summary.json
  system-info.txt
```

Privacy rules:

- File paths are included by default because this is a file organization app, but the export UI must say so.
- Optional redaction mode should hash or truncate home-relative paths.
- No file contents are included unless explicitly requested.

Crash/error strategy:

- Self-use alpha: local logs only.
- Private alpha: export diagnostics.
- Public beta: consider opt-in crash reporting.

### Acceptance

- User can produce one diagnostic bundle for bug reports.
- Errors from watcher, permissions, rules, search, and filesystem execution are included.
- Export does not include file contents by default.

## AI And MCP Product Readiness

### Current Gap

AI/MCP is architecture-ready but not product-ready. The app has tools and a no-model gateway, but no real agent loop, provider setup, or MCP interoperability UI.

### Design

AI should remain tool-bound:

```text
AgentRuntime
  -> ToolBroker
      -> Native Bipbox tools
      -> MCP client tools
```

MCP should be added as interoperability:

- Built-in MCP server exposes Bipbox tools to external MCP clients.
- Built-in MCP client lets Bipbox use external tools.
- Native tool registry remains source of truth.

Provider setup:

- No model by default.
- Remote model use is opt-in.
- Apple Foundation Models can be added as a local provider when target OS allows.
- OpenAI/Anthropic should be providers behind internal protocols, not UI dependencies.

Minimum AI/MCP release bar:

- Provider configuration UI.
- Tool permission review UI.
- Audit log of every AI/MCP tool call.
- Dry-run preview for rule and filesystem mutations.
- User confirmation for write/destructive actions.

### Acceptance

- AI cannot mutate files or rules outside registered tools.
- User can see what tool calls were made.
- Remote content sharing is explicit and disabled by default.
- MCP servers are allowlisted and permission-scoped.

## Recommended Implementation Order

1. Watcher UX and pause/resume lifecycle.
2. Permission recovery UI.
3. Inbox recovery states and manual scan.
4. Rules editor expansion.
5. Library missing-file and reindex flow.
6. Onboarding.
7. Diagnostics export.
8. Packaging/signing/notarization.
9. AI/MCP product UI and permission controls.

## Self-Use Alpha Exit Checklist

- A watched Downloads folder can organize known file types automatically.
- Unknown or risky files appear in Inbox.
- Keep-later, rejected, and failed items can be recovered.
- Rule edits apply without app restart.
- Library can find organized files.
- Missing permission states are visible and repairable.
- Diagnostics can be exported locally.
- Full test suite is green before every build.
