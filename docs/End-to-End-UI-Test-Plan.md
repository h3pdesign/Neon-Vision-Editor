# End-to-End UI Test Plan

This plan defines the UI-test contract for Neon Vision Editor. It is intentionally separate from in-process unit tests: each UI case launches the built app and drives it only through accessibility identifiers.

## Test contract

- Use `XCUIApplication` with a fresh temporary project directory per test.
- Use stable `accessibilityIdentifier` values; never address controls by localized text.
- Use `waitForExistence` and predicate expectations. Fixed sleeps are prohibited.
- Capture a screenshot and the accessibility hierarchy on failure.
- Each destructive action must cover both confirm and cancel paths.

## macOS suite

| Flow | Success proof | Safe path |
| --- | --- | --- |
| Open, edit, save, restore | Saved document reopens with edited content | Cancel unsaved-close keeps the tab open |
| External conflict | Compare/reload decision is reachable | Cancel retains in-memory edits |
| Git | Stage, unstage, commit, and diff can be reached for filenames containing spaces and quotes | Cancel commit leaves the index unchanged |
| Terminal | A command produces output and stops cleanly | Stop terminates a spawned child process |
| Markdown/PDF | Markdown navigation reaches the selected heading and PDF export completes | Cancel export writes no destination file |

## iPhone and iPad suite

| Flow | Success proof | Safe path |
| --- | --- | --- |
| Toolbar presets | Every enabled preset action is reachable directly or in More | Switching presets preserves the active document |
| Accessibility | VoiceOver labels and focus order expose each toolbar action exactly once | Dynamic Type keeps More and language controls reachable |
| Keyboard | External keyboard shortcuts invoke their declared actions | No shortcut changes the inactive window/document |
| External import | Imported content opens in a new tab | Cancel leaves the existing tab unchanged |

## CI execution

Run the suite as separate macOS, iPhone Simulator, and iPad Simulator jobs. The jobs must select the relevant test plan, retain `.xcresult` bundles on failure, and run the suite without network dependencies. The platform build matrix remains the compile gate; these are runtime gates.

## Rollout order

1. Add the dedicated XCUITest target and shared launch/temporary-project helpers.
2. Land the macOS open/edit/save/restore and terminal-child cases.
3. Land iPhone/iPad toolbar, More-menu, Dynamic Type, and import cases.
4. Add Git, conflict, Markdown navigation, and PDF-export coverage as the corresponding UI surfaces gain identifiers.
