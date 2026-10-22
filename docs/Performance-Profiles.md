# Performance Profiles and Budgets

## Inactive-tab content release — build 1119, 2026-10-22

AppKit orders out unselected tab windows but keeps their CoreAnimation backing
stores. `MacDocumentWindowTabs.updateInactiveTabContent(around:)` now hides the
content view of every registered, unselected window in a native tab group and
reveals the selected one from the existing selection observers (content host
and editor surface), before display. Unregistered windows are not touched; a
window leaving its group is revealed.

Three disposable apps were built once and run interleaved, three rounds per
mode, under one recorded display state (1800×1169 pt, 2×, EDR 16): v2.0.0 with
`NVE_RELEASE_BASELINE`, the native build with the two calls removed (control),
and the prototype. Median / p95:

| Workload | 2.0.0 edit / preview | Control edit / preview | Prototype edit / preview |
| --- | ---: | ---: | ---: |
| Retained growth (MiB) | 128 / 162 | 414 / 402 | 142 / 176 |
| Warm switch (ms) | 81 (478) / 124 (488) | 14 (25) / 13 (20) | 32 (37) / 30 (35) |
| Twelve-file loading (ms) | 83 / 85 | 259 / 272 | 248 / 254 |
| Small Swift open (ms) | 90 / 104 | 127 / 123 | 122 / 121 |
| Initial draw (ms) | 378 / 389 | 277 / 267 | 250 / 259 |

Resident growth drops by about 270 MiB and is within 14 MiB of 2.0. Warm
switching costs about 17 ms more because the revealed tab redraws, but it stays
below 2.0 at median and p95. Every warm switch still passed the harness's real
canvas-draw qualification, and the rendered pane, titlebar-parity and Markdown
live-preview checks passed with the prototype for small and large Markdown. The
strict gate still fails: twelve-file loading, small-file opening, resident
growth (+14 MiB), close dispatch (not like-for-like) and 1–3 ms scrolling
medians. Larger memory figures on this display than on the built-in one come
from EDR backing stores; the harness now logs `TAB_RELEASE_PARITY_ENV` so pairs
can be checked for matching display state. Not verified: on-screen clicking in
the tab bar and the macOS tab overview's thumbnails for hidden tabs (display
asleep during this pass).

## First-tab titlebar root cause and clean-state profile — build 1118, 2026-10-22

Root cause of the first-tab header mismatch: the scene-created primary window
laid `NativeEditorSurface` out inside SwiftUI's titlebar safe area, so its
editor backdrop started 88 pt below the window top, while AppKit-created tabs
install the editor host as `window.contentView` spanning the full-size content
area. The glass titlebar therefore showed a different backdrop only on the
first tab. Evidence: with `.ignoresSafeArea(.container)` removed from the
disposable copy, the primary backdrop frame was 1400×812 and the titlebar
band rendered transparent (alpha 0), while every child was 1400×900 with the
tinted backdrop (0.294/0.961). With it, all five tabs matched; titlebar views,
window properties and runtime chrome state were otherwise identical.
`testSceneHostedEditorSurfaceUsesTheSameFullWindowGeometryAsAppKitTabs` fails
without the line (448 vs 500 pt, inset 0 vs 52) and passes with it. The render
harness now asserts equal titlebar samples for every tab against the first.

The fixture previously stalled after aborted runs: its own defaults domain
restored stale sessions/drafts (replacing the anchor document) and persisted
window state left SwiftUI with no window. The harness now clears its disposable
domain and launches with `-ApplePersistenceIgnoreState YES`; records are written
unbuffered so watchdog exits keep evidence. Its primary scene mirrors the real
`PrimaryWindowContentView` modifiers.

Clean-state native results (three runs per mode, edit / preview median):
initial draw 260 / 252 ms, warm switch 14 / 14 ms (p95 28 / 19), small open
120 / 123 ms, large Markdown open 141 / 155 ms, twelve-file loading 263 /
267 ms, retained resident growth 414 / 402 MiB. The unchanged original harness
on the same clean state also recorded ~413 MiB, so earlier lower native memory
figures were measured on a polluted fixture domain and/or collapsed panes.
At the memory sample the footprint was 282 MB: CoreAnimation 90 MB dirty plus
169 MB reclaimable and IOSurface 34 + 36 MB — per-tab window backing stores
that a single 2.0 window never retained; the malloc heap was ~106 MB.
`testLargeMarkdownActivationKeepsMainActorResponsive` fails identically on
unmodified HEAD (359 ms gap versus a 250 ms budget).

Fresh paired gate, same machine and clean fixture state: the identical harness
compiled against v2.0.0 with `NVE_RELEASE_BASELINE` (disposable bundle
`h3p.NeonTabParity.ReleaseBaseline`), three complete runs per mode, then three
native runs per mode; `check_tab_release_parity.py` **fails** both modes.
Release → native median (edit / preview):

| Workload | 2.0.0 | Build 1118 |
| --- | ---: | ---: |
| Twelve-file loading (ms) | 81 / 73 | 223 / 270 |
| Retained resident growth (MiB) | 128 / 162 | 414 / 403 |
| Small Swift open (ms) | 103 / 103 | 124 / 124 |
| Close dispatch (ms) | 0.1 / 0.2 | 5.2 / 5.6 |
| Warm switch (ms, p95) | 87 (497) / 134 (507) | 15 (27) / 14 (19) |
| Large Swift open (ms) | 1173 / 1173 | 194 / 181 |
| Large Swift typing (ms) | 505 / 503 | 14 / 13 |
| Initial draw (ms) | 380 / 367 | 270 / 272 |

Large-file opening, typing, resizing, saving, warm switching and initial draw
are faster. Batch loading, resident growth and small-file opening are real
regressions. Close dispatch compares a native window close with 2.0's
model-only tab close, so it is not like-for-like. Scrolling and small-file
typing medians are 1–3 ms higher (13–14 ms native versus 10.5–13 ms), which
the strict gate also counts. Full 2.0 parity is not established.

## Pane-layout regression repair — build 1117, 2026-10-22

The controller migration exposed an AppKit sizing-contract defect: a horizontal
`NSStackView` supplies low-priority cross-axis alignment constraints, allowing a
SwiftUI host's 50-point intrinsic height to win over a 900-point document area.
The native layout now owns the required cross-axis edges. Saved sidebar/preview
widths, Markdown rendering, project-card design, and document ownership are not
replaced. The same helper also preserves full-width vertical editor accessories.

The regression failed four height assertions before the repair. Afterward,
195 selected tests passed with one existing opt-in benchmark skipped; the
additional WebKit split-pane geometry test passed separately. Sidebar/card
visibility toggles preserve the original native editor instance. The Level 2
matrix passed macOS, iPhone Simulator, iPad Simulator, and visionOS. Isolated
fixture windows confirmed full-height sidebar/cards, and WebKit DOM checks
confirmed initial Markdown rendering and live edits. DOM readiness alone is
not visual proof: compositor/visible-content acceptance is a separate check.

The build-1116 preview-enabled timings below predate discovery of the collapsed
panes and must **not** be treated as acceptance of preview functionality or
full design/performance parity. Full 2.0.0 parity and active-window titlebar
consistency remain open; no release-readiness claim follows from this repair.

The stronger rendered acceptance check was not green: the large-Markdown run
exceeded its 80-second watchdog before compositor acceptance, and a subsequent
run failed the qualified first-canvas-draw assertion. Neither run is valid
performance evidence. A blank screenshot despite a populated DOM is still an
open visible-preview failure, not a successful render. The checker continues to
reject failed/incomplete/diagnostic runs; these failures must not be hidden by
relaxing its gates. The screenshot runner captures only owned fixture windows,
and the geometry test also covers the real clipped/padded WebKit pane hierarchy.

## Controller-owned rendering — build 1116, 2026-10-22

The macOS source layout now uses AppKit content controllers, direct native
scroll views, native toolbar buttons, and separate lazy accessory/preview hosts.
The window layout attaches the source controller directly, without an additional
full-size SwiftUI wrapper. Document state, sheets, recovery, and command routing
remain in the retained compatibility coordinator; the whole scene layer has not
been rewritten. Native tabs remain the default.

Six complete optimized native-only runs (three per mode) exercised all 25
workload metrics. No old-tab application was run. Complete sample arrays and
aggregates are retained in [`native-controller-1116-profile.json`](native-controller-1116-profile.json).
The final correctness pass executed 167 tests: 166 passed and the existing
opt-in in-process benchmark was skipped (the separate disposable workload ran
six times). Level 2 builds passed for macOS, iPhone Simulator, iPad Simulator,
and visionOS. Keyboard/text-input and accessibility contracts were automated;
manual VoiceOver/focus-order acceptance and rendered inspection of every
optional-pane combination remain pending. Generated apps, source snapshots,
and DerivedData were removed after verification; the sample archive is durable.

| Workload | Editor-only median / p95 | Preview-enabled median / p95 |
| --- | ---: | ---: |
| Initial draw (ms) | 277 / 529 | 289 / 296 |
| Warm switch (ms) | 15 / 22 | 16 / 24 |
| Small Swift open (ms) | 137 / 181 | 146 / 159 |
| Large Markdown open (ms) | 151 / 161 | 155 / 175 |
| Twelve-file loading (ms) | 274 / 284 | 320 / 344 |
| Retained resident growth (MiB) | 126.2 / 128.1 | 163.2 / 163.3 |
| Native close dispatch (ms) | 7.6 / 13.5 | 6.7 / 14.3 |

Compared with the recorded build-1115 editor-only reference, small-file opening
improved from 165 to 137 ms and resident growth from approximately 161 to 126 MiB.
Warm-switch results remain fast, but 15/22 ms is not zero latency or a guarantee
of meeting every display's frame budget. Against the recorded 2.0 reference,
twelve-file loading (274 versus 109 ms) and retained growth (126 versus 42 MiB)
still fail parity. No full-parity or release-readiness claim follows from this
rewrite. RSS is pressure-dependent and does not account for all WebKit child
processes; native close dispatch still includes AppKit window closure, unlike
the recorded old model-only close endpoint.

## New-tab-only follow-up — 2026-10-22

Three complete editor-only control pairs for build 1115 still failed the
unchanged release gate: warm switching 13/19 ms median/p95 versus 82/564 ms in
2.0.0; small Swift opening 165 versus 142 ms; twelve-file loading 278 versus
109 ms; retained resident growth approximately 161 versus 42 MiB. The user
then requested that old-tab runs stop; the remaining baseline loop was stopped.
Those baseline values are reference evidence, not a reason to rerun old tabs.

Only disposable native snapshots were changed in the subsequent diagnostics.
Coalescing queued window construction did not materially improve batch loading
(274 ms median across three runs) and was rejected. Hiding inactive editor
hosts failed the real draw check and was rejected. Pooling toolbar hosts did
not establish parity: its run stalled before initial drawing, then completed
after UI inspection with an invalid 1,261,274 ms startup sample. Its timing
and memory results are not acceptance evidence. None of these three snapshot
changes was applied to production sources.

The native heap diagnostic retained 76,381 SwiftUI PropertyList elements and
29,147 Core Text runs; window-owned graphs and render surfaces remain relevant
costs. Existing snapshots below already document the additional native-window
surface retention. No renderer redesign or successful full-parity result is
claimed. Temporary snapshots, apps and diagnostics from this follow-up were
removed; only this concise record remains. The harness now writes an explicit
error before its optimized-build assertion traps, avoiding silent failed draws.

## Toolbar transaction follow-up — development build 1115, 2026-10-22

The remaining cold-open trace identified native toolbar construction/layout.
`ToolbarCoordinator.bind` previously assigned empty identifiers before assigning
the complete toolbar. This discarded AppKit's existing-item diffing and forced
an unnecessary intermediate layout. The coordinator now publishes identifiers
once at initial construction, skips that publication when group identifiers are
unchanged, and updates actions in existing group/hosting views. Group removal,
reintroduction and overflow actions continue to use the owning coordinator.
Apple documents `NSToolbar.itemIdentifiers` as key-value observable and as
diffing against existing toolbar items; the change uses that existing behavior.

The primary-scene-only SwiftUI window/toolbar background modifiers were also
removed. All editor windows use `MacDocumentTabPolicy.configureWindowChrome`,
including translucency preference updates. The native surface integration
fixture and parity harness no longer refer to those deleted modifiers.

The new tests assert no explicit empty identifier publication on initial bind,
no further identifier publication for an unchanged update, retained group/host
identity when actions change, and correct removal/reintroduction. These are
operation-count and lifetime regressions, not full-app latency measurements.
No new paired 2.0/native acceptance run is claimed by this change. Cold-open,
batch-loading and resident-memory parity remain unproven, and 2.1 remains
blocked on the full release-parity gate. Earlier `/private/tmp` evidence paths
below are historical: those temporary artifacts were deleted at the user's request.

Focused macOS verification executed 72 window/toolbar tests: 71 passed, one
opt-in benchmark skipped, zero failures. The parity-checker unit tests also
passed (4 tests). The first test build exposed a missing explicit MainActor
annotation in the new recorder; the next run exposed an overstrict KVO-count
assertion. Both test defects were corrected before the final passing run.
The generated verification products were then removed. No new paired latency
or memory comparison, rendered titlebar acceptance, or spoken VoiceOver check
was performed; these results do not establish release readiness.

## Ownership follow-up — development build 1113, 2026-10-22

The retained-host design no longer swaps a document environment into a shared
`ContentView`. Its 262 local state properties now use normal `@State` again,
rather than each carrying the shared-host wrapper's environment lookup,
fallback, initial value, key and observable box. The host asserts permanent
document ownership. iOS/visionOS previously aliased that wrapper to `State`, so
their storage behavior is unchanged. Captured document models still use the
installed-model wrapper; file coordination and security scopes are unchanged.

Exploratory optimized runs reduced resident growth substantially versus build
1112, but still failed release parity. The completed editor-only exploratory
report recorded approximately 173 MiB growth versus 89 MiB in 2.0, small-file
opening 242 versus 152 ms, and warm switching 13/25 ms median/p95 versus
120/1212 ms. These runs overlapped separate UI work and are **not final acceptance**;
the later paired control experiment independently retained the lower-memory
direction. An additional modal-callback reference snapshot was rejected: three
paired runs did not improve overall results (control/variant small-file medians
196/202 ms, batch medians 411/434 ms, resident-growth medians 156/172 MiB).
That snapshot change is not in the source checkout.

New cold-profile mode repeats small-file opens after app startup and labels its
output `TAB_RELEASE_PARITY_DIAGNOSTIC_PAUSE`; the unchanged acceptance checker
rejects it. Sampling after the startup marker identifies synchronous toolbar
construction/layout in `MacDocumentToolbar.ToolbarCoordinator.bind`, including
the `itemIdentifiers` assignment, as a remaining contributor. This is not proof
that a speculative toolbar rewrite improves the application. Traces:
`/private/tmp/neon-cold-after-startup.sample.txt` and its diagnostic log.

All four required platform builds passed for the state change. Final macOS
window/loading/appearance tests executed 129 tests with 128 passing, one opt-in
benchmark skipped, zero failures. The enhanced integration test preserves two
different native caret positions, host identities and toolbar identities across
repeated tab selection. The first ten-test StoreKit pass in the newly named host
had five empty-fixture failures; re-registering that now-launched disposable
host resolved routing and the ten-test recheck passed. Results:
`/private/tmp/neon-owner-final-regressions.xcresult` and
`/private/tmp/neon-owner-storekit-recheck.xcresult`. Do not label the initial
combined test run a pass.

The full editor still reproduced the white/gray titlebar mismatch with a
background preference installed in both hosting contexts. The latest unverified
candidate removes scene bridging from the inner document host and keeps an
explicit, availability-guarded toolbar background at the primary scene boundary
only. Native toolbar identities are preserved by the integration tests. The Mac
locked before a rendered comparison of that final ownership change; no unlock,
normal-editor restart or user-document mutation was attempted. Final titlebar,
accessibility and repeated interactive performance acceptance remain blocked on
an unlocked desktop. Version 2.1 is **not release-ready**.

## Follow-up verification — development build 1112, 2026-10-22

The file-open path now submits its detached coordinated read before queuing
main-actor result installation, allowing I/O to overlap native-window setup.
The installer acquires its strong document owner only after the read completes.
A regression holds a coordinated writer open and verifies that closing the
pending document releases its owner before the provider becomes available.

AppKit-created tabs now install their editor hosting view at the window content
root, rather than below the temporary loading surface. Window presentation
bridges `.title`, but not SwiftUI toolbars; the physical native toolbar remains
unchanged across selection. A retained window controller owns the loading
surface's close protection and notifications after root replacement. Tests
cover close/unregister behavior and rejection of a foreign document/window pair.
This corrects a presentation-ownership difference found between the primary
SwiftUI scene and AppKit-created tabs, but it does not resolve their rendered
appearance mismatch. After explicit authorization, selecting the first and then
the second tab in the disposable build-1112 app still showed a white primary
titlebar versus a light-gray child titlebar under the same inactive-window
conditions. Appearance acceptance therefore fails; passing lifecycle tests is
not visual proof. No documents were edited, saved or closed during this comparison.

The final focused macOS pass executed 139 tests: 138 passed, one opt-in benchmark
was skipped, zero failed (`/private/tmp/neon-root-final-regressions.xcresult`).
This includes 59 file-open, 46 native-window, 10 StoreKit and 24 translucency tests.
The shared loader change passed the required macOS, iPhone, iPad and visionOS
build matrix with Xcode 27.1 (27A9275); the later macOS-only root/lifetime changes
passed their targeted macOS build/tests. No new Swift compiler, view-publication
or SceneStorage lifecycle warning was observed. Xcode's informational AppIntents
metadata-extraction warning remains unrelated.

Local StoreKit verification is now passing. The isolated, renamed test app had
not been registered with LaunchServices: storekitagent reported application-not-
found (-10814), so its Xcode test-session context could not route to that host.
Registering only the disposable app resolved the lookup. All ten support tests,
including actual local `displayPrice` and simulated consumable purchase, passed.
The tests use a bundled configuration, validate the fixture before suspending a
shared lookup, and test alert behavior instead of reading inaccessible source
files. This is local StoreKit Test evidence, not App Store pricing or purchase
acceptance; no production product IDs, pricing fallbacks or security settings changed.

Three complete alternating optimized release/candidate runs per preview mode
used the unchanged, correct-revision first-draw gate:

| Workload (median) | 2.0 editor / preview | Build 1112 editor / preview |
| --- | ---: | ---: |
| Warm switch, ms | 85 / 157 | 11 / 11 |
| Warm switch p95, ms | 586 / 1173 | 20 / 24 |
| Small Swift open, ms | 119 / 127 | 166 / 149 |
| Twelve-file loading, ms | 133 / 104 | 291 / 327 |
| Resident growth, MiB | 142 / 162 | 477 / 381 |

Both overall acceptance reports **fail**. Full retained per-document SwiftUI
graphs/rendering surfaces still carry a substantial memory cost, and cold/batch
opening is slower. Do not describe this candidate as release-ready or universally
instant. A single diagnostic root-host run is not substituted for these repeated
results. Logs: `/private/tmp/neon-root-final-{release,native}-{edit,preview}-{1,2,3}.log`;
reports: `/private/tmp/neon-root-final-{edit,preview}-parity.json`. Results from the
earlier inner-host build 1111 also failed and are retained under
`/private/tmp/neon-followup-{edit,preview}-parity.json`. These are disposable-host
optimized measurements, not signed distribution archives or physical-device proof.

## Current development status: window-owned native editor surfaces

Build 1110 removes the measured warm-switch graph handoff. A fresh sample of
build 1109 (`/private/tmp/neon-instant-current.sample.txt`) attributed 856 main
thread samples to `NativeEditorSurfaceGroup.install` attaching the hosting view;
673 descended through `NSHostingView.viewDidMoveToWindow` into SwiftUI focus
traversal. This synchronously requested the changed document's view graph.
Changing attachment order alone did not improve the result (48–67 ms warm
draws in `/private/tmp/neon-instant-order-edit.log`), so that experiment was
discarded rather than shipped.

Each visited document now retains its editor attached to its own native window.
Unvisited restored windows still mount no editor until selected. Switching a
visited tab no longer reparents the full graph, substitutes its document
environment, or rereads its initial viewport. Native tabs remain the default;
the shared project-card session, file presenters, document bindings and
dirty-close validation retain their existing ownership. Closing a document
removes its rendering entry through the existing unregister path.

The macOS regression pass executed 286 tests: 285 passed, one opt-in benchmark
was skipped, none failed (`/private/tmp/neon-instant-regressions.xcresult`). The
updated regression asserts distinct document hosts/canvases, attachment stability
across repeated selection, filenames, independent content and inactive close
protection. No new SwiftUI publication or SceneStorage lifecycle warning was
observed in that pass. This change is macOS-only; the preceding shared-code
platform matrix remains separately documented below.

Three complete alternating release/candidate runs per mode then measured:

| Warm switching | Published 2.0 median / p95, ms | Build 1110 median / p95, ms |
| --- | ---: | ---: |
| Editor only | 99 / 496 | 10 / 23 |
| Markdown preview enabled | 124 / 581 | 9 / 18 |

Logs: `/private/tmp/neon-instant-{release,native}-{edit,preview}-{1,2,3}.log`.
These are optimized disposable-host measurements, not signed release archives or
an absolute zero-latency guarantee. The renderer must still draw the correct
loaded revision with a populated toolbar; no snapshot-only or placeholder draw
qualifies. Diagnostic warm-profile runs are explicitly rejected by the checker.

Both overall parity reports still fail:
`/private/tmp/neon-instant-edit-parity.json` and
`/private/tmp/neon-instant-preview-parity.json`. Small-file opening medians were
159/157 ms (editor/preview) versus 124/118 ms in 2.0, and twelve-file loading
314/375 ms versus 69/89 ms. Resident-growth medians were 209/246 MiB versus
92/123 MiB. The initial editor-only experiment's approximately 7 MiB growth did
not reproduce in the repeated runs and is not an accepted memory improvement.
Fast warm selection does not clear these remaining release blockers.

The separately identified build-1110 UI app verified Swift/Markdown filename
tabs, independent document/preview contents, restoring an already-focused
editor and its caret after returning to its tab, typing into that document,
and unsaved-close Cancel/Don't Save behavior using disposable fixtures. Native
tab and editor accessibility labels were present. Spoken VoiceOver and complete
keyboard focus-order acceptance were not performed. Further keyboard-navigation
automation stopped when the tool reported concurrent user interaction with the
test app. No normal editor or user documents were modified.

## Earlier shared-surface prototype (builds 1104–1109)

Development builds 1104–1109 investigate sharing one editor hosting graph per
native tab group while retaining document-owned state, bindings, file presenters,
close validation and per-window toolbars. These are uncommitted development
changes, not a released performance improvement.

The first optimized editor-only run recorded 81 ms median warm activation,
243 ms small-Swift opening, 261 ms large-Markdown opening, 882 ms twelve-file
loading and 111.4 MiB resident growth. Evidence:
`/private/tmp/neon-shared-final-native-edit-1.log`. This is one run, not three
paired acceptance runs; it does **not** establish parity. In particular, batch
loading remains slower and must not be represented as fixed. The appearance-only
backing-layer correction in build 1106 was not part of that timing sample.

Build 1109 removes a measured contributor: repeated crash-report prefix
classification during the shared graph's view evaluation. Each document now
caches only the classification result, keyed by document identity, content
revision and external revision; the cache does not retain closed documents or
cache read failures. The status bar reuses the document's maintained line index
instead of scheduling a complete-text scan on the main actor. Its no-document
fallback counts an immutable snapshot in a detached utility task and rejects
cancelled results.

One optimized editor-only run before this change recorded 88–240 ms warm
activation (median 118 ms); the first run after it recorded 68–86 ms (median
81 ms). Logs: `/private/tmp/neon-ready-native-edit-1.log` and
`/private/tmp/neon-ready-cache-native-edit-1.log`. These are individual runs, not
repeated paired acceptance or a universal speedup claim. The sample trace
`/private/tmp/neon-ready-warm.sample.txt` identifies classification in
`ContentView.isAppleCrashReportDocument` and a line-count task on the main
thread. Native hosting/focus/layout work remains, so this does **not** establish
instant switching or release parity.

The final build-1109 regression pass executed 262 tests across document tabs,
file opening, toolbar selection, language detection and editor layout: 261
passed, one separately opt-in benchmark was skipped, and none failed. The five
new regressions cover positive/negative cache reuse, edits/external refreshes,
document replacement/revision reset, bounded reads/read failures and weak
document ownership. Results: `/private/tmp/neon-classification-regressions.xcresult`
and `/private/tmp/neon-classification-integration.xcresult`. The required build
matrix passed macOS, iPhone/iPad simulator and visionOS. No new cross-platform
build issue was found; this is not physical-device acceptance.

Three complete alternating release/candidate runs per preview setting were then
captured without simultaneous builds or UI automation. Warm-switch median/p95:

| Setting | Published 2.0, ms | Candidate, ms |
| --- | ---: | ---: |
| Editor only | 89 / 505 | 50 / 62 |
| Markdown preview enabled | 125 / 984 | 73 / 105 |

Raw logs: `/private/tmp/neon-classification-{release,native}-{edit,preview}-{1,2,3}.log`.
Both unchanged acceptance checks still **failed overall**. Editor-only small-file
opening was 186 ms versus 124 ms, twelve-file loading 701 ms versus 94 ms, and
resident growth 167.5 MiB versus 88.7 MiB (medians). With preview enabled,
small-file opening was 165 ms versus 119 ms, batch loading 659 ms versus 93 ms,
and resident growth 203.0 MiB versus 66.8 MiB. Reports:
`/private/tmp/neon-classification-edit-parity.json` and
`/private/tmp/neon-classification-preview-parity.json`. This removes measured
contributors but does not make switching instant or clear the release gate.

Release-workflow tests (64), the offline 2.1.0 preparation rehearsal and the
Xcode Cloud metadata/toolchain preflight passed. Missing localized timeline
entries and required Unreleased headings were supplied; published metadata was
not changed. These checks did not publish, sign, notarize or verify StoreKit
pricing, and do not override the failed performance/visual acceptance.

The focused candidate regression suite executed 239 tests: 238 passed and one
opt-in benchmark was skipped. Result:
`/private/tmp/neon-shared-surface-final-regressions.xcresult`. This covers state
and binding ownership, inactive dirty-close validation, filename metadata,
file loading, native layout and toolbar selection; it is not release timing,
full accessibility acceptance or physical-device proof.

The startup chrome regression initially exposed transparent titlebar drawing
and a clear window backing. AppKit toolbars use in-window blending;
the editor's behind-window visual effect cannot supply a missing native backing
above its content bounds. Native document windows now retain the system window
background before presentation and during appearance updates, while editor
content keeps its existing behind-window material. That was insufficient:
paired screenshots still showed a white SwiftUI primary-window header versus a
gray AppKit child-window header. The shared editor also emitted unconditional
SwiftUI toolbar background/visibility preferences, despite AppKit owning the
native toolbar. Build 1108 restricts those preferences to the legacy toolbar,
keeps native focus visibility on its physical NSToolbar, declares the SwiftUI
scene's native container background, and removes the competing per-activation
background assignment. Primary action hosts explicitly use 17-point symbols to
restore the released toolbar scale. The 24 appearance/toolbar tests passed;
the subsequent rendered dark-mode comparison still showed a darker first-tab
titlebar than the child tab. That visual regression remains open. Neither this
appearance change nor its performance impact has completed acceptance.

StoreKit verification remains separate and unresolved. The debug Run scheme
selects the correct configuration and product ID. Tests now load the bundled
configuration instead of an inaccessible source-checkout path. The isolated
local StoreKit lookup still returned no product; the full purchase suite did
not pass. One source-inspection test additionally cannot read checkout files
from the sandboxed test host. Do not represent this as successful price or
purchase verification.

## Native tab activation regression harness

`VirtualEditorPerformanceTests.testTabSwitchActivationBenchmarkRecordsRealSwiftUIViewportAndDraw` attaches the actual SwiftUI representable to a disposable macOS window, switches between Markdown, Swift and single-line Unicode JSON, and waits for the renderer's real first-draw stage. It reports cold samples and warm median/tail samples. It does not manually mark viewport/draw events and does not open user documents.

Run the focused suite in **Release** with elevated Xcode access:

```bash
xcodebuild -project 'Neon Vision Editor.xcodeproj' -scheme 'Neon Vision Editor' \
  -configuration Release-GitHub ENABLE_TESTABILITY=YES DEAD_CODE_STRIPPING=NO \
  COPY_PHASE_STRIP=NO STRIP_INSTALLED_PRODUCT=NO CODE_SIGNING_ALLOWED=NO \
  -destination 'platform=macOS' \
  -only-testing:'Neon Vision EditorTests/VirtualEditorPerformanceTests' test
```

The test-only overrides enable `@testable` linking without changing shipping settings; Swift still uses Release optimization. The 100 ms warm median / 250 ms warm tail limits are regression ceilings, not an instant-switch claim. This harness isolates native editor activation; separately profile the complete application with preview on/off, cold file-provider reads, multiple windows, and iPhone/iPad hardware. Keep raw traces, median/p95, OS/toolchain, fixture sizes and build configuration with results. Do not equate fixture generation, simulator builds or the native harness with end-to-end device proof.

Initial macOS reads use immutable document snapshots and independent coordinated file handles. Captured indexes are validated against file identity and data generation, not size/mtime alone. Providers without supported version identifiers use a cancellable 256 KiB-chunk fingerprint check of the indexed source bytes; prepared indexes require a complete-source scan on that fallback path, so network/provider cold activation can remain slower. Fingerprints are accumulated during existing index passes without retaining the whole file. Completed reads install only for matching resource/document/activation/revisions. Warm render states are bounded to eight entries with a 16 MiB conservative retention-cost budget, keyed by revisions, caret, theme/font/wrapping and viewport width. This budget estimates retained text/attributed-line cost; use Allocations to measure actual Core Text heap residency. Markdown HTML has a separate six-entry / 8 MiB UTF-8 cache; local-image renders continue bypassing HTML reuse.

### Local optimized harness evidence — 2026-10-14

Xcode 27.0 (27A266a), macOS destination, development 1.9.4/build 1086. All runs used a disposable SwiftUI-hosted native editor window and the same Markdown/Swift/single-line Unicode JSON fixtures, with preview excluded from this native activation benchmark. Test-only linking overrides above were enabled; these are not bit-identical shipping binaries.

| Fresh test-host process | Cold first-draw samples, ms (Swift / JSON / Markdown) | Warm median, ms | Warm p95, ms |
| --- | --- | --- | --- |
| Full regression pass | 9 / 93 / 31 | 2 | 5 |
| Repeat 2 | 100 / 431 / 186 | 3 | 32 |
| Repeat 3 | 358 / 101 / 154 | 5 | 32 |

The full optimized regression pass ran 183 tests with zero failures, including actual WebKit in-place updates/fallback and focus retention, native keyboard/accessibility contracts, lazy snapshot ownership, same-resource document replacement and cancellation. Raw local results/logs are `/private/tmp/NeonOptimization20261014-complete.xcresult`, `/private/tmp/NeonOptimization20261014-perf2.xcresult`, `/private/tmp/NeonOptimization20261014-perf3.xcresult` and their `neon-optimization-*` logs. Temporary result locations are not durable CI artifacts; hosted CI uploads its own runtime results.

PR #772 follow-up (development build 1087): the same-size/preserved-timestamp snapshot regression failed all four rewrite cases before the fix. The final optimized document/layout/activation pass ran 142 tests with zero failures. Fresh-host warm medians were 7 ms (p95 38 ms), 4 ms (p95 32 ms), and 3 ms (p95 7 ms in the complete targeted pass). Two earlier combined passes exceeded the unchanged 100 ms warm ceiling at 113 and 122 ms; those timing failures are retained, not erased or treated as a proven source-validation regression. This benchmark uses in-memory documents, outside the file-validation path. It now logs per-activation UI/viewport/draw stages and window activation/visibility to diagnose scheduling variability. Results are `/private/tmp/nve-pr772-red-exact-20261014.xcresult`, `/private/tmp/nve-pr772-green-20261014.xcresult`, `/private/tmp/nve-pr772-final-20261014.xcresult`, `/private/tmp/nve-pr772-perf-repeat1-20261014.xcresult`, `/private/tmp/nve-pr772-stages-20261014.xcresult`, and `/private/tmp/nve-pr772-final-stages-20261014.xcresult`, with matching log files.

Recorded passing warm runs meet the regression budget, but timings vary across test processes. Cold activation varies considerably and is **not guaranteed instant**. This is not a before/after comparison against v1.9.3, nor proof of complete-app startup, preview-enabled switching, file-provider latency, hardware memory behavior or physical-device accessibility. Those remain separate profiling/sign-off tasks.

Compatible inert Markdown pages update only `main.content`, preserving equal nodes and relative scroll position. Document, base URL, script policy or HTML-shell changes, ambiguous markers, unsafe elements and JavaScript failures fall back to a full navigation. Content scripts remain disabled; no telemetry or new network requests are introduced.

Run `scripts/benchmark_large_file.sh` on a quiet machine before changing debounces, caches, or rendering paths. It creates deterministic Swift, TypeScript, JSON, NDJSON, CSV, and Markdown files plus separate 500-card Markdown and PDF project fixtures (override with `NVE_BENCHMARK_CARD_COUNT` and `NVE_BENCHMARK_PDF_CARD_COUNT`).

`docs/performance-baselines.json` is the versioned contract for fixture sizes and stable retained-data limits. `scripts/ci/check_performance_budget.py` verifies that the JSON contract still matches the runtime Git and draft-recovery bounds; it deliberately does not gate raw timings, which vary across hardware and simulator runtimes.

## Capture matrix

### Controller-owned native editor (development build 1116)

The current macOS source layout is owned by `MacDocumentContentController`,
with direct native canvas creation/update and separate lazy status, find,
minimap, structured-mode, sidebar, and preview hosts. Ordinary toolbar actions
use native buttons. The existing scene/document-state coordinator remains;
this architectural change alone is not a claim of full 2.0 performance parity.
The final controller/toolbar/native-window/native-layout regression pass executes
167 tests (166 passed, one existing skip), including direct-canvas identity, independent document ownership,
split-pane release, source/reading/source transitions, absent optional factories,
accessory layout, deferred geometry publication, and per-window action routing.

`bash scripts/ci/profile_native_document_tabs.sh OUTPUT_DIRECTORY edit` builds
only the current native implementation in a disposable source snapshot and runs
three optimized foreground workloads. Use `preview` for the preview-enabled
workload or `both` to compile once and run all six. Its generated app/source copy is removed automatically, and each run
has a 90-second process timeout. It never runs the old tab implementation. Logs
are evidence only when all workload metrics and a completion marker are present;
compare them with previously recorded matching release logs. Explicit foreground
activation and a process activity prevent background App Nap from being mistaken
for document activation latency. The normal app and shipping sources are not
modified by these harness adaptations.

### Native tabs versus the published release

Performance parity is a separate acceptance requirement from a passing build or
a fast warm-tab median. Do not publish 2.1 on the strength of a synthetic canvas
benchmark alone.

`scripts/tab_release_parity.swift` is an opt-in, disposable macOS app harness. It
uses the real `ContentView`, file loading, editor canvas, saves and native tab
coordinator. Compile identical harness copies in isolated source snapshots of
the latest published tag and development checkout, using the same Xcode, `-O`,
preferences and machine. `NVE_TAB_PARITY_APP` selects its app entry point;
`NVE_RELEASE_BASELINE` selects the released in-window tab model. Only the
disposable snapshots replace the normal app entry point and gate the canvas's
first-draw measurement through `canRecordDraw(tabID:contentRevision:)`. That
gate rejects loading placeholders and stale revisions. Never make those harness
adaptations in the shipping app. The bundle ID must start with
`h3p.NeonTabParity.` and execution requires `NVE_RUN_TAB_PARITY=1`.

Alternate release/native runs sequentially, without concurrent builds or UI
inspection. Record at least three complete runs for each preview setting via
`NVE_PARITY_PREVIEW_MODE=preview` and `edit`. Workloads cover initial editor
presentation, new small/source/Unicode JSON/large Markdown files, returning to
tabs, typing, resizing, scrolling, saving, closing, retained resident-memory
growth and loading twelve files. The batch case is **not** full bookmark,
provider, conflict-dialog or recovered-draft startup verification. Resident
growth excludes WebKit child processes and does not certify peak memory or
absence of leaks. Simulator/device, external sync, project-card scrolling and
spoken accessibility acceptance remain separate.

Compare each setting with:

```bash
python3 scripts/ci/check_tab_release_parity.py release-1.log release-2.log release-3.log \
  --native native-1.log native-2.log native-3.log
python3 scripts/ci/test_tab_release_parity.py
```

The checker rejects incomplete, mismatched or invalid evidence and reports a
regression if either median or p95 exceeds the release. It intentionally grants
no performance allowance: investigate noise with more paired runs rather than
raising the limits to accept a slowdown. This is an explicit local acceptance
check, not an automatically executed hosted-release gate or a universal speed
guarantee. Preserve failing results; a partial improvement is not parity.

#### 2026-10-21 acceptance result: NOT PASSED

Baseline: published `v2.0.0` (`08f70c6163d440deac80146e944e37f93fde80a9`).
Candidate: the native-tab working changes based on `7fd70c72`, including
document-event ownership filtering and hidden detached-preview work elimination.
Both use Xcode 27.1, macOS 27.0.1, arm64 and Debug with `-O`, not signed
distribution archives. Each setting has three complete alternating release/native
runs. The same loaded-revision draw guard is applied only to both harness copies.

Medians below describe the captured workloads, not a claim of parity; the checker
also tests p95. Units are milliseconds except resident growth.

| Workload | Release, preview | Native, preview | Release, editor only | Native, editor only |
| --- | ---: | ---: | ---: | ---: |
| Return to an open tab | 130 | 15 | 91 | 15 |
| Open small Swift | 101 | 277 | 99 | 275 |
| Open Unicode JSON | 170 | 306 | 189 | 285 |
| Open large Markdown | 243 | 312 | 159 | 283 |
| Open 100,000-line Swift | 1,131 | 333 | 1,127 | 347 |
| Load twelve small files | 97 | 370 | 88 | 340 |
| Retained-editor resident growth, MiB | 163 | 423 | 129 | 430 |

Both parity comparisons return exit status 1. Raw logs are
`/private/tmp/neon-parity-{release,native}-{preview,edit}-{1,2,3}.log`;
the complete median/p95 reports are
`/private/tmp/neon-tab-release-parity-{preview,edit}.json`.

Root causes fixed during this comparison:

- Global caret/selection notifications fell back to each other window's selected
  document. Every keystroke invalidated hidden editors and changed their cursor
  status. A repeated pre-fix native run measured small-file typing at about
  560–590 ms; ownership filtering restored it to about 12–15 ms.
- The installed-but-hidden detached-preview presenter projected and sanitized
  full document source on editor updates. A main-thread sample reached
  `detachedPreviewHTML → webPreviewHTML → webPreviewSourceWithCSP` for non-preview
  documents. The getter now exits before reading the document while hidden.

Remaining acceptance work: cold opening, batch loading, retained memory and
several tail-latency cases still regress. Investigate the per-document
`NSWindow`/`NSHostingView` construction and retained graphs with allocation/hitch
profiles before selecting a reuse architecture. Do not mask those costs with a
placeholder, accept higher limits, or call the native implementation release-ready.
Full recovered-session, external-provider, device and accessibility acceptance
is not covered by this harness. No 2.1 release was published by this check.

#### Build 1102 follow-up: native tabs remain default, parity NOT PASSED

The requested product direction is unchanged: native tabs stay the default.
The follow-up removes repeated native title/URL/dirty-state setter calls, uses
existing tab-group insertion for background windows without selecting them, and
populates the complete AppKit language menu only when it opens. Regression tests
assert unchanged metadata causes no setter writes, background insertion preserves
selection, and menu construction/sizing does not enumerate unopened language rows.

Three fresh paired runs per mode alternate baseline/candidate order. These runs
occurred with higher unrelated desktop activity; compare within each paired set,
not absolute times or RSS against the earlier quieter set. The checker still
compares both median and p95 without relaxing thresholds.

| Workload | Release, preview | Native, preview | Release, editor only | Native, editor only |
| --- | ---: | ---: | ---: | ---: |
| Startup editor draw, ms | 724 | 632 | 616 | 474 |
| Return to an open tab, ms | 190 | 17 | 129 | 14 |
| Open small Swift, ms | 164 | 317 | 151 | 338 |
| Open Unicode JSON, ms | 201 | 361 | 210 | 315 |
| Open large Markdown, ms | 337 | 421 | 238 | 295 |
| Open 100,000-line Swift, ms | 1,567 | 547 | 1,365 | 477 |
| Load twelve small files, ms | 135 | 484 | 135 | 453 |
| Retained-editor resident growth, MiB | 60.8 | 112.2 | 27.0 | 117.4 |

Both comparisons fail. Logs are
`/private/tmp/neon-tab-creation-{Release,Native}-{preview,edit}-{1,2,3}.log`;
reports are `/private/tmp/neon-tab-creation-{preview,edit}.json`.
RSS depends on system pressure and excludes WebKit child processes; it is not
peak memory or a complete accounting of memory cost.

Matched allocation snapshots also show a structural cost: about 49,545 versus
237,758 AttributeGraph nodes, 83 versus 140 MB of heap allocations, and 33.7 versus
119.2 MB of resident IOSurface backing in the captured baseline/native processes.
Each visited native window retains a full editor SwiftUI graph and backing
surfaces. A disposable shared-host prototype reduced retained growth but raised
warm activation from roughly 15 ms to 149 ms, so it was rejected. A separate
diagnostic omitting unopened dialog presenters did not establish a cold-opening
improvement and was not promoted to app code. Neither experiment is release
evidence or a supported app configuration.

Verification: 212 tests passed, one opt-in benchmark skipped, no failures or
xcresult runtime warnings; macOS, iPhone/iPad simulator and visionOS builds passed.
The four parity-checker tests and static performance-budget check passed. The
rendered language control exposed the complete menu and updated the owning
document's language without changing its contents. Concurrent desktop interaction
prevented reliable keyboard-menu acceptance; spoken VoiceOver remains pending.
Cold opening, batch loading, memory, and several tail-latency cases remain open.
Passing correctness tests does not certify 2.0 performance parity or authorize a
2.1 release.

#### Build 1103 research: native toolbar prototypes rejected

This investigation follows Apple's [SwiftUI performance guidance](https://developer.apple.com/documentation/Xcode/understanding-and-improving-swiftui-performance),
[Instruments session](https://developer.apple.com/videos/play/wwdc2025/306/),
[hosting-view sizing contract](https://developer.apple.com/documentation/swiftui/nshostingview/sizingoptions),
and [toolbar design guidance](https://developer.apple.com/design/human-interface-guidelines/toolbars).
These are architectural constraints, not proof that a particular change is faster.

The inspected applications are not interchangeable benchmarks:

- [CotEditor](https://github.com/coteditor/CotEditor/blob/3893947d296b1a8f578e23a9e81d0d28bc1d39d9/CotEditor/Sources/Document%20Window/DocumentWindowController.swift)
  owns its AppKit toolbar in the document window controller and uses narrowly
  scoped SwiftUI hosts rather than a SwiftUI-owned window toolbar bridge.
- [CodeEdit](https://github.com/CodeEditApp/CodeEdit/blob/fa2aebd86373211c78626074b53ab75010767575/CodeEdit/Features/Documents/Controllers/CodeEditWindowController%2BToolbar.swift)
  also owns its toolbar and hosts individual SwiftUI controls, with a unique
  toolbar identifier per window. Its workspace tabs are not native window tabs.
- [TextMate](https://github.com/textmate/textmate/blob/346b52b108b387462d4b3def481fb74983ae89f3/Frameworks/DocumentWindow/src/DocumentWindowController.mm)
  uses a custom workspace tab bar and document view. Its architecture does not
  demonstrate equal costs for one native window per document.

A cold-opening main-thread sample reached
`NativeDocumentContentHost.installIfSelected → NSHostingView.viewDidMoveToWindow
→ updateToolbarBridge → NSWindow.setToolbar → windowDidGainToolbar → layout`.
Approximately 700 samples followed the late toolbar insertion path in
`/private/tmp/neon-cold-baseline.sample.txt`. This identifies avoidable toolbar
attachment work; it does not explain all retained per-window editor graphs.

An isolated candidate created the physical toolbar before adding a document window to
its native group. Existing SwiftUI actions remain hosted leaf controls; the
editor host bridged its title, not the toolbar. Controls retained their hosts
when their item list was unchanged. Overflow menus were constructed on request
from the current owning document. Apple's [identifier contract](https://developer.apple.com/documentation/appkit/nstoolbar/identifier-swift.property)
requires distinct identifiers here: equal identifiers synchronize item lists
across windows even with configuration autosaving disabled.

An earlier isolated owned-toolbar prototype omitted required toolbar delegate
methods and rendered no controls. Its apparent timing improvement is invalid
and must not be used. Isolated correctness regressions asserted actual item inventory,
stable toolbar/control identity, independent window ownership, lazy overflow,
and disabled actions. Benchmark evidence version 2 records first draw only
when both the document revision and a visible, nonempty toolbar are installed. Older
logs remain historical evidence, not inputs for this stricter acceptance run.

The completed, control-qualified candidate passed 215 correctness tests, with
one opt-in benchmark skipped. Rendered checks confirmed controls, collapse/
expand, document-specific language/preview state, and the complete language
menu. These results apply to the rejected prototype, not a shipped feature.
Three paired runs per preview mode still failed performance acceptance:

| Median workload | 2.0 edit | Candidate edit | 2.0 preview | Candidate preview |
| --- | ---: | ---: | ---: | ---: |
| Warm switch (ms) | 90 | 11 | 159 | 13 |
| Small Swift open (ms) | 142 | 239 | 146 | 230 |
| Large Markdown open (ms) | 183 | 283 | 292 | 309 |
| Twelve-file load (ms) | 118 | 351 | 97 | 416 |
| Retained editor RSS growth (MiB) | 90.4 | 183.1 | 82.8 | 146.0 |

Raw logs: `/private/tmp/neon-qualified-{release,native}-{edit,preview}-{1,2,3}.log`.
Reports: `/private/tmp/neon-qualified-{edit,preview}.json`. A subsequent isolated
two-host toolbar variant improved some cold-open timings, but retained growth
rose to approximately 429–430 MiB in two repeated edit-mode runs
(`/private/tmp/neon-grouped-native-edit-{1,2,3}.log`). It was also rejected.
RSS is system-pressure dependent and does not include all WebKit child processes.

Neither toolbar replacement is retained in app source. No production toolbar,
file ownership, preview, or session behavior was changed by this research pass;
the pre-existing native-tab work remains intact. The stricter benchmark gate,
its tests, research record, and development build 1103 are retained. Full editor
graph duplication remains unresolved. A future reuse design must separate
per-document presentation/command state from the physical editor host and
prove dirty-close, conflict-dialog, preview, detached-group, keyboard/focus, and
accessibility behavior before replacing the current ownership boundary.
Native tabs remain default, performance parity remains NOT PASSED, and the 2.1
release remains on hold. Do not convert these rejected prototypes into release
notes or claim an instant-opening fix.

Final retained-source verification: all four platform-matrix builds passed;
212 focused tests passed, one opt-in benchmark skipped, and the result bundle
recorded no runtime warnings. The four parity-evidence tests and static
performance-budget check passed. An earlier concurrent-compilation run failed
the unchanged large-Markdown external-refresh test's ten-second deadline
(`/private/tmp/neon-research-final-regressions.xcresult`). The unchanged suite
then passed without compilation (`neon-research-final-regressions-quiet.xcresult`),
and that exact refresh test passed three additional iterations in 2.22, 2.13,
and 2.04 seconds (`neon-research-refresh-repeat.xcresult`). Preserve the failed
run: these quiet passes do not certify refresh responsiveness under load.

### Open issue acceptance — 2026-10-14

- #770: the SwiftUI/UIKit stale-caret regression rewound native position 12 to persisted position 5 before the fix. Persistence is now an observation, not a same-resource navigation command; resource activation/loading completion still restores bookmarks, while Find and explicit range/line navigation keep their separate command route. The iPhone simulator reproducer and mobile/layout suites passed; physical iOS 26.0.1 confirmation remains distinct.
- Second-pass #770 regressions exposed two loading-state defects: finishing a deferred, chunked load lost bookmark 150000 and left the caret at 0; the empty loading placeholder also emitted a persistable caret notification. The installer now owns bookmark restoration until the complete buffer exists, and loading/partial-buffer caret telemetry is suppressed. Red bundles are `nve-issues-recheck-red-20261014.xcresult` and `nve-issues-recheck-placeholder-red-20261014.xcresult` in `/private/tmp`.
- Second-pass verification: macOS 93 executions (one opt-in UI fixture skipped), iPhone 83, iPad 83 (four phone-only cases skipped), and six native activation/Markdown preview regressions passed with no failures. The existing wrap-transition fixture previously changed an unobserved reference captured by a binding; it now supplies explicit changed configuration and awaits SwiftUI's update. Native first-draw benchmark: cold 18/92/98 ms, warm median 5 ms, warm tail 8 ms in this run; this is a synthetic hosted-editor measurement, not an instant-switch guarantee for the full app or physical hardware. All four platform builds and localization checks passed. The expected red test assertions/logs were preserved; their stalled diagnostic collectors were terminated after the failures, so those bundles are not completed verification runs.
- #766: the AppKit regression reset a manually browsed tab-strip offset from 1936 to 0 during an unchanged-selection update. Only a changed selection now reveals its tab. Native overflow buttons provide pointer/assistive navigation without changing the document-tab architecture requested separately in excluded issue #621.
- The overflow controls were visually inspected in their actual on-screen window and exposed correct accessible button names/enabled states. Initial optional external tab-interaction runs could not reliably target the QA window while another editor instance had restored documents; their failed fixture bundles (`nve-issues-mac-tabs-live*`) are retained. After the user saved and quit the editor, live pointer navigation successfully moved right to hidden tabs and left back to the first page; `/private/tmp/nve-release-tabs-uiqa-20261014.xcresult` passed. Native key/focus regressions also passed; spoken VoiceOver remains a separate acceptance step.
- #738: the existing Settings → Editor → Basics checkbox was located through the actual external accessibility tree, turned off and on, and verified against isolated persisted preferences with unchanged synthetic document contents. Run the fixture with `TEST_RUNNER_NVE_SETTINGS_INTERACTIVE_QA=1` and `-only-testing:'Neon Vision EditorTests/EditorSettingsDefaultsTests/testCSVSettingIsAccessibleAndPersistsWithoutChangingDocuments'`; it deliberately skips without an external UI driver. The successful acceptance bundle is `/private/tmp/nve-issues-mac-uiqa-active-20261014.xcresult`. Spoken VoiceOver and system keyboard-navigation preferences were not changed or certified by this run.
- #498: compact phone toolbar selection now follows the actual horizontal layout class, rather than assuming every phone is compact; existing iPad presentation is retained. Follow Apple's [iPhone Duo preparation guidance](https://developer.apple.com/iphone-duo/prepare/). Full-screen opt-in and device poses require a build using Xcode/iOS 27.1, which is not installed here. Before closing: verify outer/inner displays, open/closed/partially folded poses, portrait/landscape, both Split View sides, asymmetric safe areas, software/hardware keyboards, project/preview splits, Settings, and accessibility text sizes. Existing SDK 27.0 tests are not Duo certification.

| Workload | Measure | Baseline and threshold |
| --- | --- | --- |
| Large Markdown typing and preview | Time to first stable preview, typing hitch count, peak resident memory | Record a baseline per supported OS; investigate a regression of more than 20% or any sustained input hitch |
| 500 project cards | Index completion time, visible-card count, peak resident memory | All cards appear; investigate repeated indexing or a retained-card count above the fixture size |
| Large Git diff | Diff preparation time and retained output bytes | Output remains bounded by the existing Git-service cap; investigate truncation bypasses |
| Sidebar/card toggling | Peak resident memory after 20 toggles and whether it returns near baseline | Investigate monotonic growth across toggles |
| Crash recovery | Serialized payload size and restoration duration | Payload stays within the existing recovery budget and restoration remains interactive |

## Recording protocol

1. Use `scripts/capture_performance_profile.sh macos|iphone|ipad` to create the fixture log, raw Allocations trace, and capture record. Provide `NVE_PERFORMANCE_APP_PATH` for macOS or the booted simulator UDID in `NVE_PERFORMANCE_DEVICE_ID` for iPhone/iPad.
2. Start from a fresh launch, keep the same theme and preview layout, and record device/OS/Xcode versions.
3. Repeat each case three times; use the median for time and the largest observed resident memory.
4. Attach the raw `.trace`, `capture.json`, and fixture log to the change that alters a budget. The capture runner deliberately retains raw traces instead of invoking Xcode 27 beta's unreliable command-line XML exporter; inspect those traces in Instruments rather than treating `Document Missing Template Error` as a missing capture.

## Guardrails

- Do not turn a profile result into a universal hard limit until it is stable on macOS, iPhone, and iPad.
- Keep bounded file reads, card excerpts, Git output, and recovery payloads as correctness limits, not only performance optimizations.
- Treat an increase over 20% from the recorded median as a regression requiring either remediation or an explicit documented trade-off.
- Run `python3 scripts/ci/check_performance_budget.py` in CI or release preflight whenever a retained-data limit changes.

## Large-document editing contract

The v1.4.0 large-file path is file-backed rather than a full-document compatibility copy on every edit:

- `FileBackedTextDocument` keeps the source representation on disk, records UTF-16 edits, preserves the detected encoding and line endings, and streams an atomic replacement on save.
- `FileBackedTextViewportAdapter` supplies bounded text windows to the native editor. Viewport generations reject edits against stale windows, while caret and selection state are translated when a window is replaced.
- The macOS virtual text renderer draws visible lines with Core Text in `VirtualEditorCanvas`, an `NSView` implementing `NSTextInputClient`. It requests bounded viewport replacements around the scroll anchor and limits syntax highlighting/minimap work to the visible range. Measure viewport installation and replacement as rendering operations, not as full-document open operations.
- Large editable documents remain editable below the 100 MB partial-open boundary. The 100 MB-and-above path is intentionally read-only and exposes only the first 4 MB for safe inspection.
- Performance investigations must measure viewport replacement, scrolling, typing, save, and external-change handling separately; a full-document allocation in the per-edit path is a regression.

## Swift 6.4 and OS 27 audit (2026-09-14)

The v1.8.0 performance pass keeps optimizations evidence-driven:

- Terminal ANSI parsing and display sanitization run outside the main actor. The UI receives coalesced incremental attributed chunks every 33 ms and appends them to a native `NSTextView`; it does not rebuild the complete 240,000 UTF-16-unit scrollback value on every publication.
- Git diff presentations precompute changed, inline, and side-by-side display rows once. SwiftUI renders those rows with stable identities instead of filtering and rebuilding arrays during body evaluation.
- The Data iteration benchmark in issue #507 measured `withUnsafeBytes` at 0.32 seconds, RawSpan at 0.59 seconds, and `Data.enumerated()` at 2.12 seconds for the benchmark workload. Keep `withUnsafeBytes`; RawSpan is both OS-27-only and slower for this path.
- Foundation's OS 27 implementations of `Data`, `NSData`, `URL`, `NSURL`, and `CFURL` are runtime replacements, so they require no source-level availability branch. Release and platform-matrix builds require Xcode 27 and the OS 27 SDK family; the project index stays on native `URL` and cached `URLResourceValues`, normalizes its root once per scan, and receives the newer runtime automatically on OS 27 while retaining older deployment targets.
- Keep Swift 6 default main-actor isolation for UI ownership, but explicitly move measured parsing and formatting work off the main actor. Do not enable approachable concurrency as a performance switch.
- Do not add yielding accessors, blanket `@inline(always)`, or `@specialized` attributes until an Instruments trace identifies a remaining copy or dispatch hotspot. These features can increase exclusivity complexity or binary size without improving the current workloads.

The optimized Release-GitHub build was exercised on a MacBook Pro M5 Pro with macOS 27.0 (26A428) and Xcode 27.0 (27A266a). A 16,000-line PTY workload reached its completion marker, retained bounded scrollback, and produced no Instruments hang over 250 ms in a 30-second Time Profiler capture. ANSI work appeared on the processing worker; the incremental text bridge appeared only sparsely in CPU samples.

Automated tab switching covered HTML, CSV, Markdown, Swift, and Ada documents. Full accessibility-tree capture itself produced main-thread stalls while serializing very large editor and WebKit accessibility values, so those stalls are automation overhead and are not accepted as tab-switch latency measurements. Use the deterministic tab-switch and virtual-editor XCTest benchmarks plus the existing `TabSwitch` signposts for regression decisions.

No OS 26 runtime is installed on this machine, so an OS 26 versus OS 27 timing comparison remains unmeasured. Record that comparison on identical hardware before attributing a performance change to OS 27 Foundation or Swift runtime behavior.

## Primary-screen terminal follow-up

The development terminal now incrementally decodes UTF-8 bytes and parses cursor/erase controls on its output worker. The native text bridge applies immutable changed-suffix patches at the existing 33 ms cadence; retained screen text remains capped at 240,000 UTF-16 units. Alternate-screen applications remain unsupported. The high-volume PTY regression checks completion and bounded output, but is not a substitute for Instruments timing or memory evidence. Re-capture the terminal profile after this screen-rendering change; the v1.8.0 trace above describes the previous append-only implementation.

The full three-run macOS/iPhone/iPad workload matrix remains required before issue #318 is complete. Build success and unit-test results do not supply those profiling measurements.
