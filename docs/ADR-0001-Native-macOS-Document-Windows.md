# ADR-0001: Native macOS document windows — CotEditor comparison and migration plan

- **Status:** Proposed
- **Date:** 2026-10-22
- **Applies to:** macOS only. iPhone, iPad and visionOS keep their existing tab UIs.
- **Starting point:** development build 1119 on `feature/native-macos-tabs` (2.1.0, PR #805)

## Context

2.1.0 makes native AppKit document tabs the only Mac tab system. Each document
has its own `EditorViewModel` and `NSWindow`; AppKit groups those windows with
window tabbing. The project sidebar and project Markdown cards are shared across
a tab group, while each document keeps its own editor, cursor and preview state.

How it is built today:

| Concern | Current implementation |
| --- | --- |
| Window creation | Two paths. The first window comes from the SwiftUI `WindowGroup(id: "primary-editor")` scene; every later tab is an `NSWindow` built by `MacDocumentWindowTabs.presentPendingWindow`. |
| Document lifecycle | Custom: `MacDocumentWindowTabs` (registration, pending owners, tab ordering, selection, metadata, close routing), `WindowCloseConfirmationDelegate`, `ContentView+SessionPersistence` (session URLs, bookmarks, drafts). No `NSDocument`. |
| Window content | A complete SwiftUI `ContentView` per window (about 264 `@State` properties plus toolbar, sidebars, cards and status), hosted in `NSHostingView`. The text view (`VirtualEditorView`) and the pane layout (`MacDocumentContentController`) are AppKit. |
| Toolbar | AppKit `NSToolbar` via `MacDocumentToolbar`, bound per document. |
| Shared state | `MacDocumentWindowTabs` shares project folder, sidebar visibility/width/mode and the project-card session across a group. |

The custom window coordination is about 1,560 lines
(`MacDocumentWindowTabs.swift`, `MacNativeEditorSurface.swift`,
`MacDocumentToolbar.swift`, `MacDocumentContentController.swift`).

### Measured position against 2.0.0

Disposable apps built once (2.0.0 with `NVE_RELEASE_BASELINE`, native control,
native candidate) and run interleaved, three runs per mode, under one recorded
display state. Median (p95). Source: `docs/Performance-Profiles.md`, build 1119.

| Workload | 2.0.0 edit / preview | Build 1119 edit / preview |
| --- | ---: | ---: |
| Retained memory growth (MiB) | 128 / 162 | 142 / 176 |
| Warm tab switch (ms) | 81 (478) / 124 (488) | 32 (37) / 30 (35) |
| Twelve-file batch open (ms) | 83 / 85 | 248 / 254 |
| Small Swift file open (ms) | 90 / 104 | 122 / 121 |
| Initial draw (ms) | 378 / 389 | 250 / 259 |

`scripts/ci/check_tab_release_parity.py` still fails: batch open, small-file
open, retained memory, close dispatch (not like-for-like: a native close closes
a window, 2.0 removed a tab from a model) and 1–3 ms scrolling medians.

### Problems traced to the current structure

1. **Two creation paths.** The SwiftUI-created first window differs from
   AppKit-created tabs: window class (`AppKitWindow` vs `NSWindow`), scene
   bridging, safe-area layout and collection behavior. This produced the
   first-tab toolbar-background bug (fixed in 2.1.0 by
   `.ignoresSafeArea(.container)`) and the earlier white/grey titlebar mismatch.
   Every window feature has to be checked on both paths.
2. **Per-tab cost.** Every tab builds and retains a full SwiftUI editor graph.
   Batch opening creates one window plus one graph per file, one per main-queue
   turn. A heap sample at the memory checkpoint showed tens of thousands of
   SwiftUI `PropertyList.Element` entries and per-window CoreAnimation and
   IOSurface backing stores. Hiding unselected tab content (build 1119) removed
   most of the backing-store cost; the remaining gaps are batch open and
   small-file open.
3. **Rebuilt document plumbing.** Session restoration, close confirmation,
   window titles and represented URLs, and draft recovery are reimplemented on
   top of a model shared with iOS rather than taken from AppKit.

## Reference: CotEditor

Read from `coteditor/CotEditor` `main` (last pushed 2026-10-20). Design
reference only; no code is copied.

| Concern | CotEditor |
| --- | --- |
| Documents | `Document`/`DataDocument` subclass `NSDocument`; `DocumentController` subclasses `NSDocumentController`, including transient-document replacement and deferred display while a file opens. |
| Window creation | One path. `Document.makeWindowControllers()` creates a `DocumentWindowController`, which builds a `DocumentWindow` (`NSWindow` subclass) around an AppKit `WindowContentViewController`. |
| Tabs | AppKit automatic window tabbing. `DocumentWindow` overrides `userTabbingPreference` (app setting, or a temporary override for "New Document as Tab/Window") and adds ⌘1…⌘9 tab selection. |
| Lifecycle | `NSDocument` provides autosave and versions, window restoration, close/save confirmation, title and proxy icon, Open Recent. |
| UI | AppKit view controllers; `NSHostingView` only for small pieces (for example the edited indicator). |
| Folders | `DirectoryDocument` is a separate folder window with a file browser. It switches one window's `fileDocument` between several documents, with back/forward history, and **disallows tabbing** for folder windows. |

CotEditor never combines native tabs with a shared project sidebar. We need
that combination, so no reference covers it: the shared-sidebar design stays
ours in every option below.

## Decision

1. Keep the model **one `NSWindow` per document, grouped by AppKit window
   tabbing**. It is the only way to get real native tabs and it matches CotEditor.
2. Ship 2.1.0 with the current implementation. Do not start a rewrite inside the
   release.
3. After 2.1.0, migrate toward CotEditor's structure in three gated stages.
   Each stage lands on its own branch and PR, must pass the measurement protocol
   below against 2.0.0 **and** against the previous stage, and must not regress
   iOS, iPadOS or visionOS.
4. Do not adopt CotEditor's folder-window model (single-window file switching
   without tabs); our product requirement is native tabs plus a shared project
   sidebar.

Expected effects below are hypotheses to be measured, not claims.

### Stage 1 — single AppKit window creation path

**Goal:** every editor window, including the first, is created by one AppKit
factory and owned by one `NSWindowController` subclass.

- Replace the `primary-editor` and `"New Window"` editor `WindowGroup`s with
  AppKit creation through `MacDocumentWindowTabs` (extend the existing
  `NativeDocumentWindowController`). Keep SwiftUI scenes for Settings and
  utility windows.
- Move what the scenes currently provide to AppKit: launch window and startup
  behavior, external file opens (`handlesExternalEvents`, Finder/CLI routing),
  `openWindow`/`openSettings` actions, scene-storage values (already partly
  replaced by `EditorWindowStorage`), frame autosave and restoration, menu
  command targeting, Safe Mode window.
- Remove scene-only workarounds: `NativeTabSceneBootstrapper`,
  `NativeDocumentTabAttachment` and the safe-area override in
  `NativeEditorSurface`. Re-check whether the `isForeignDocumentWindow` guards
  are still needed once one controller owns each window's content.

**Exit criteria**

- Window class, content-view type and titlebar chrome are identical for the first
  and later tabs (harness `RENDER_CHROME` dump and the titlebar-parity
  assertion).
- Startup, file open from Finder/CLI, New Window/New Tab, restore after
  relaunch, Safe Mode and close-with-unsaved-changes behave as before (existing
  `MacDocumentWindowTabsTests`, `EditorViewModelFileOpenTests`, plus new tests
  for the AppKit launch path).
- Initial draw and small-file open are not worse than build 1119 (±5% median);
  everything else not worse than build 1119.

### Stage 2 — AppKit window shell with SwiftUI panes

**Goal:** per-window structure is AppKit; SwiftUI is used only inside panes and
is created on demand. This targets the batch-open and small-file-open gaps.

- The window controller owns an `NSSplitViewController`: project sidebar,
  editor column (`MacDocumentContentController`), optional preview and project
  cards, and inspector. Status bar and find bar become AppKit or small lazily
  created hosting views.
- Split `ContentView` by responsibility: document state moves to a per-document
  controller object; pane views receive only the state they render. A
  background tab must not build sidebar, card, preview or AI views until it is
  selected.
- Shared project sidebar: choose by measurement between (a) one sidebar view
  controller moved to the selected window on tab selection, and (b) a light
  per-window sidebar bound to a shared project model. Option (a) avoids
  duplicate trees; option (b) avoids reparenting during selection.
- Keep `MacDocumentToolbar` (already AppKit).

**Exit criteria**

- Twelve-file batch open, small-file open and retained memory reach 2.0.0
  parity in the checker (median and p95), or the remaining gap is documented
  with a profile and accepted explicitly.
- Warm tab switch stays below 2.0.0 at median and p95.
- Rendered checks pass: pane heights, titlebar parity, Markdown live preview.
- VoiceOver order, keyboard navigation and focus checked for the new shell
  (AppKit view order replaces SwiftUI order).

### Stage 3 — evaluate `NSDocument`

**Goal:** decide, with a prototype, whether macOS document lifecycle should move
to `NSDocument`/`NSDocumentController`.

- Prototype a macOS-only `NSDocument` subclass that owns one `EditorViewModel`
  tab and delegates reading/writing to the existing loaders, keeping
  `EditorViewModel` shared with iOS.
- Compare against current behavior for: file coordination and security-scoped
  bookmarks (App Sandbox), encoding detection and large-file loading,
  remote documents, external refresh with pending edits, unsaved-draft recovery
  versus autosave/versions semantics, Open Recent, restoration, and duplicate
  opens of the same URL.
- Adopt only if it removes custom lifecycle code without user-visible
  regressions and passes the measurement protocol. Otherwise record the
  rejection and keep the custom coordinator.

**Exit criteria:** a written go/no-go with prototype measurements, test results
and a list of behaviors that would change for users.

## Measurement protocol for every stage

1. **Builds.** Three disposable apps, built once: v2.0.0 with
   `NVE_RELEASE_BASELINE` (bundle `h3p.NeonTabParity.ReleaseBaseline`), the
   previous stage as control, and the candidate. Same harness
   (`scripts/tab_release_parity.swift`), same compiler flags
   (`scripts/ci/profile_native_document_tabs.sh`).
2. **Clean state.** The harness clears its disposable defaults domain and
   launches with `-ApplePersistenceIgnoreState YES`, so aborted runs cannot
   restore stale sessions or windows.
3. **Same display.** Every run logs `TAB_RELEASE_PARITY_ENV` (screen size,
   scale, EDR headroom, window size). Pair only runs with identical lines;
   backing-store memory depends on the display.
4. **Interleaving.** Three rounds × edit and preview modes × three apps,
   alternating apps within each round. Nothing else heavy runs meanwhile.
5. **Gate.** `python3 scripts/ci/check_tab_release_parity.py <release logs>
   --native <candidate logs>` per mode, plus the same comparison against the
   control to show the stage's own effect.
6. **Rendered checks.** Render mode with `NVE_PARITY_RENDER_DIR` for small and
   large Markdown: pane heights, first-tab titlebar parity, Markdown initial
   render and live edit.
7. **Correctness.** Full macOS unit suite, `scripts/ci/build_platform_matrix.sh`
   (macOS, iPhone, iPad, visionOS), and manual on-screen checks the harness
   cannot automate: tab-bar clicking, drag reordering, the tab overview,
   VoiceOver.
8. **Record.** Add a dated section to `docs/Performance-Profiles.md` with the
   table, the `TAB_RELEASE_PARITY_ENV` line, and failures stated as failures.

Metrics of primary interest per stage:

| Stage | Primary metrics | Must not regress |
| --- | --- | --- |
| 1 | initial draw, small-file open, first-tab chrome parity | warm switch, memory, batch open |
| 2 | twelve-file batch open, small-file open, retained memory | warm switch, typing, scrolling, preview render |
| 3 | open/save/close latency, restoration correctness | everything above |

## Consequences

- **Positive:** one window path removes a whole class of first-window bugs;
  AppKit shells make per-tab cost explicit and lazy; each stage is independently
  shippable and measurable.
- **Negative:** large changes to `ContentView` and scene wiring; SwiftUI
  conveniences (scene storage, `openWindow`, scene-based restoration) must be
  replaced on macOS; temporary duplication while both shells exist; accessibility
  order must be re-verified.
- **Risks:** App Sandbox file access and bookmarks during Stage 3; restoration
  and Safe Mode during Stage 1; the shared-sidebar design in Stage 2 has no
  reference implementation.

## Non-goals

- Changing iPhone, iPad or visionOS tab UIs.
- Reintroducing an in-window Mac tab strip.
- Adopting CotEditor's folder-window behavior or copying its code.

## References

- `docs/Performance-Profiles.md` — build 1118/1119 sections and the 2.0.0 paired gate.
- `docs/ARCHITECTURE.md` — application entry, macOS window and session restoration.
- CotEditor (`coteditor/CotEditor`, `main`): `CotEditor/Sources/Document/Document.swift`,
  `DocumentController.swift`, `DirectoryDocument.swift`,
  `CotEditor/Sources/Document Window/DocumentWindowController.swift`, `DocumentWindow.swift`.
- Apple: `NSDocument`, `NSDocumentController`, `NSWindowController`,
  `NSWindow.tabbingMode`, `NSWindow.userTabbingPreference`, `NSWindowTabGroup`.
