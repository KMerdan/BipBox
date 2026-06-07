# Bipbox programmatic test & control harness

Three layers, one shared command vocabulary. Drive the app by API, read back real
state. All three speak the same `WorkspaceCommand` → `WorkspaceSnapshot` engine
(`Sources/BipboxWorkspaceUI/WorkspaceControl.swift`).

## Principle acceptance suite (start here)

The product north star (`docs/product-north-star.md`) is the acceptance contract. Each
principle maps to a named, passing test — fast in-process **and** confirmed through the
rendered UI:

- `Tests/BipboxCoreTests/PrincipleAcceptanceTests.swift` — the exhaustive matrix over the
  real services (in-process via `BipboxHarness`, runs in < 1s). `swift test --filter PrincipleAcceptanceTests`
- `UITests/PrincipleUITests.swift` — the headline flows confirmed through the rendered
  window (XCUITest). `scripts/ui-test.sh`

### Principle → test traceability

| North-star principle | In-process test | UI confirmation |
|---|---|---|
| Promise (saw / came-from / relates / happened / get-back) | `test_Promise_remembersSaw_…` | `testAlphaLoop_AddSourceLibraryAndItemMemory`, `testRetrieval_SearchFindsItem` |
| P1 Retrieval first, storage second | `test_P1_itemsAreFindableAndRememberedWithoutMoving` | `testAlphaLoop_…` (status "Remembered") |
| P2 Sources are first-class | `test_P2_sourcePersistsWithStateAndLifecycle` | `testSourceFirstClass_PauseReflectsInUI` |
| P3 Folders are items (no recursion by default) | `test_P3_topLevelCapturesFoldersAsItems_recursiveWalksIn` | `testFoldersAreItems_SubfolderShownChildHidden` |
| P4 Memory graph is the org layer | `test_P4_itemConnectsToContextAndContextListsMembers` | `testMemoryGraph_OverviewReachable` |
| P4 Memory graph — full zoom journey & navigation | `ConnectionsGraphWorkflowTests` (9 workflows) | `ConnectionsGraphUITests` (zoom journey + re-center) |
| P5 Automation is policy (Inbox fallback) | `test_P5_rulesAreOptionalAndFallbackIsInbox` | `testInboxFallbackAndExplicitDecision` |
| P6 AI/automation orchestrates, never silently mutates | `test_P6_decisionsRequireUserActionAndPreviewThePlan` | `testInboxFallbackAndExplicitDecision` (plan preview) |
| Safety: index before action; activity records mutations | `test_Safety_indexBeforeAction_nothingMovedOnCapture` | `testActivity_RecordsMutations` |
| Safety: missing files marked + recoverable | `test_Safety_missingFilesAreMarkedAndRecoverable` | `testMissingFilesAreMarkedAndRecoverable` |
| Naming (Needs a decision / Remembered / Filed) | `test_Naming_usesFriendlyStatusLabels` | (labels visible in `testAlphaLoop_…`) |

### Deferred (not yet confirmable — by design, not gaps)

Real AI provider (currently `NoModelAIGateway`), collections create/browse, tag display
on items, AI rule proposal, embeddings-based similarity. These are Tier-1/Tier-2 in the
north star; no acceptance test asserts them yet.

## The command vocabulary

`WorkspaceCommand` is a flat, JSON-friendly struct. `action` plus optional fields:

| action | fields | effect |
|---|---|---|
| `snapshot` | — | return current state |
| `refresh` | — | reload library/sources/queue |
| `navigate` | `target` (`allItems`,`recents`,`inbox`,`sources`,`rules`,`activity`,`source:<uuid>`) | switch section |
| `search` | `query` | run a search |
| `clearSearch` | — | clear search |
| `select` | `target` (`item:<uuid>`,`source:<uuid>`,`context:<uuid>`,`cluster:<key>`,`overview`,`none`) | set selection (also drives the graph) |
| `setPresentation` | `target` (`gallery`/`connections`) | center presentation |
| `decide` | `id` (item uuid), `decision` (`approve`/`keep`/`reject`) | resolve a pending item |
| `addFolder` | `path`, `depth` (`top`/`all`) | add a watched source + index |
| `scanSource`/`pauseSource`/`resumeSource` | `id` | source lifecycle |
| `addRule`/`deleteRule`/`toggleRule` | `id` | rule CRUD |
| `recover` | `id`, `mode` (`locate`/`reindex`/`refresh`), `path` (for locate) | recover a missing item |
| `seedPending`/`seedMissing` | `target` (count) | test/automation: create pending / missing items |

`WorkspaceSnapshot` returns: section, presentation, selection, query, item/pending/
rule counts, the item list (each with `status` + `originalPath`), sources, rules, the
recent `activity` (kind/message/reversible), and the resolved `graph` (center +
neighbors) for the current selection.

## 1. In-process driver (`BipboxHarness`)

Builds the real `makeDefault()` stack against an isolated temp dir. Use it from
Swift tests or any in-process scenario.

```swift
let harness = try BipboxHarness()           // fresh temp data dir
await harness.start()
let snap = await harness.addFolder(url, depth: .never)
let after = await harness.search("report")  // -> WorkspaceSnapshot
let graph = (await harness.select("item:\(id)")).graph
```

See `Tests/BipboxCoreTests/BipboxHarnessScenarioTests.swift` for full scenarios.

## 2. JSON CLI (`bipbox-harness`)

One JSON command per stdin line → one JSON snapshot per stdout line. Great for
shell/Python scripting and CI without launching the GUI.

```sh
swift build --product bipbox-harness
printf '%s\n' \
  '{"action":"addFolder","path":"/tmp/demo","depth":"top"}' \
  '{"action":"search","query":"pdf"}' \
  | .build/debug/bipbox-harness --pretty
# flags: --base <dir> (persist to a chosen dir), --pretty
```

## 3. Live control API (running app)

A localhost HTTP/JSON server embedded in the **running** app (DEBUG only, opt-in).
Drives the same `WorkspaceModel` the UI uses, so changes reflect live in the window.

```sh
# launch with the API on
BIPBOX_CONTROL_API=1 BIPBOX_CONTROL_PORT=7777 \
  .build/Bipbox.app/Contents/MacOS/BipboxApp

curl -s localhost:7777/health
curl -s localhost:7777/state | jq
curl -s -XPOST localhost:7777/command \
  -d '{"action":"addFolder","path":"~/Downloads","depth":"all"}' | jq
```

- Binds to 127.0.0.1 (loopback) only.
- Optional auth: set `BIPBOX_CONTROL_TOKEN`; clients send `Authorization: Bearer <token>`.
- Helper: `scripts/automation/bipbox_control.py` (`state`/`add`/`search`/`navigate`/`select`/`raw`).

## 4. UI automation (rendered window) — XCUITest

Full XCUITest drives the real rendered window. SwiftPM can't host UI tests, so the
project is generated from `project.yml` with XcodeGen.

```sh
brew install xcodegen      # one-time
scripts/ui-test.sh         # generate Bipbox.xcodeproj + run BipboxUITests
# or just regenerate:  scripts/ui-test.sh generate
```

- Tests live in `UITests/BipboxUITests.swift`; the project is generated (gitignored).
- Each test launches against an **isolated** store (`BIPBOX_DATA_DIR`) with the
  control API on, **seeds deterministically over the API**, then asserts the UI.
  (Env-based background seeding is racy; API setup + UI assertions is reliable.)
- Key controls carry accessibility identifiers: `sidebar.<section>` (incl.
  `sidebar.source:<uuid>`), `toolbar.search`, `toolbar.toggle.gallery|connections`,
  `item.<uuid>`, `decision.approve|keep|reject`, `rule.new`, `rule.toggle.<uuid>`,
  `sources.addFolder`.
- Project quirks handled in `project.yml`: `EXECUTABLE_NAME=BipboxApp` (must match
  the shared Info.plist's `CFBundleExecutable` or codesign fails); `ENABLE_DEBUG_DYLIB`
  / `ENABLE_PREVIEWS` off (Xcode 16+/26 side dylibs break ad-hoc bundle signing);
  `GENERATE_INFOPLIST_FILE` on for the UI test bundle.

Lightweight alternative (no Xcode project) — click by identifier via the
Accessibility API: `osascript scripts/automation/ui_click.applescript sidebar.inbox`
(needs Accessibility permission for the controlling terminal).

> The UI suite already caught a real bug: the sidebar source rows / Inbox badge
> read nested view models (`onboarding`, `reviewQueue`) but only observed
> `WorkspaceModel`, so they didn't refresh on change. `WorkspaceModel` now
> re-publishes nested `objectWillChange`.

## Coverage map (what's tested where)

- **E2E over a realistic dummy project** (`Tests/BipboxCoreTests/BipboxE2EDummyProjectTests.swift`,
  in-process harness): recursive vs top-level indexing, type clustering + folder-overlap
  edges, search→select→graph navigation (item → folder context → members), Inbox
  decision flow (approve/keep/reject), rules add/toggle/delete, source pause/resume/
  scan, and real drop-intake capture.
- **Rendered UI** (`UITests/BipboxUITests.swift`, XCUITest): sidebar + seeded library,
  rules create, toolbar search, **Inbox approve flow**, Gallery↔Connections toggle,
  navigate all sections.
- **Scenario** (`BipboxHarnessScenarioTests.swift`) and unit suites round it out.

To create pending decisions deterministically (no flaky drop routing): the
`seedPending` control action / `harness.seedPending(n)` indexes `needsReview` items
via the real search index.

> Two real bugs these e2e tests caught and fixed: (1) the sidebar/badge didn't react
> to nested view-model changes (WorkspaceModel now forwards `objectWillChange`);
> (2) after a decision the Inbox list didn't refresh because it reads `library.results`,
> not the queue (`performDecision` now re-pulls the library).

## Which to use

- **CI / fast logic tests** → in-process harness (`BipboxHarness`) or the CLI.
- **Live experimentation / external agents / any language** → the control API.
- **Real rendered-UI regression** → accessibility IDs + XCUITest/AppleScript.

Note: the live API persists to the real `~/Library/Application Support/Bipbox`.
To reset, move that folder aside (the app recreates it empty).
