# Codex Project Instructions - Neon Vision Editor

This file is the single source of truth for how Codex must work in this repository.
Primary goal: ship small, safe changes that preserve existing behavior and architecture.

Neon Vision Editor is a native SwiftUI/AppKit editor focused on speed, stability, and minimalism.
Avoid "helpful refactors." Fix or implement exactly what is requested.

---

## 0) Global Non-Negotiables (Always)

### A. Preserve working code
- Do NOT touch working code unless strictly required.
- No opportunistic refactors.
- No renaming/moving for aesthetics.

### B. No deprecated APIs
- Do not introduce deprecated Apple APIs.
- Modern Swift patterns only if required for the task.

### C. Security & Privacy
- No telemetry.
- No sensitive logging (documents, prompts, tokens).
- Network calls only when explicitly user-triggered.
- API tokens must remain in Keychain.
- No weakening sandbox or file security.

### D. Small, reviewable diffs
- Minimal patches only.
- If change is large, split into phases.
- If diff exceeds reasonable review scope, stop and split.

### E. Multi-window correctness
- No accidental shared state across windows/scenes.
- Window state must remain isolated unless explicitly designed otherwise.

### F. Main thread discipline
- UI mutations must be on main thread / `@MainActor`.
- No blocking IO, parsing, or network on main thread.

---

## 1) Hard Cross-Platform Rule (Blocking)

Neon Vision Editor ships on:
- macOS
- iOS
- iPadOS

ANY change targeting one platform MUST prove it does not break the others.

### Mandatory compile safety
- No AppKit types in shared code without `#if os(macOS)` guards.
- No UIKit-only APIs leaking into macOS builds.
- Shared models must remain platform-agnostic.

### Mandatory verification requirement (STRICT)

A patch is NOT acceptable without explicit iOS and iPadOS verification steps.

Your response MUST include either:

A) Exact build commands executed for:
- macOS
- iOS simulator
- iPad simulator

OR

B) A detailed manual verification checklist for:
- macOS
- iOS
- iPadOS

If this section is missing, the answer is incomplete.

### Standard build verification command

Prefer the repo matrix script when Xcode and simulator services are available:

```bash
scripts/ci/build_platform_matrix.sh
```

It runs macOS, iOS Simulator, and iPad Simulator builds sequentially with `CODE_SIGNING_ALLOWED=NO`. By default it writes to `.DerivedDataMatrix` and removes it on exit. Use `--keep-derived-data` only when actively debugging build artifacts, then remove the derived data directory before finishing.

Equivalent individual commands, when the matrix script is not suitable:

```bash
xcodebuild -project "Neon Vision Editor.xcodeproj" -scheme "Neon Vision Editor" -configuration Debug -destination "generic/platform=macOS" -derivedDataPath .DerivedData-macOS CODE_SIGNING_ALLOWED=NO build
xcodebuild -project "Neon Vision Editor.xcodeproj" -scheme "Neon Vision Editor" -configuration Debug -sdk iphonesimulator -destination "generic/platform=iOS Simulator" -derivedDataPath .DerivedData-iOS CODE_SIGNING_ALLOWED=NO build
xcodebuild -project "Neon Vision Editor.xcodeproj" -scheme "Neon Vision Editor" -configuration Debug -sdk iphonesimulator -destination "generic/platform=iOS Simulator" -derivedDataPath .DerivedData-iPad TARGETED_DEVICE_FAMILY=2 CODE_SIGNING_ALLOWED=NO build
```

Remove any `.DerivedData*` folders created during verification before returning.

---

## 2) Accessibility Rule (Non-Optional)

Every UI-affecting change must consider:

- VoiceOver (macOS + iOS/iPadOS)
- Keyboard navigation (macOS + iPad with keyboard)
- Focus management

You must explicitly state:

- What accessibility elements were affected
- How labels/traits remain correct
- That focus order is preserved
- That no UI state traps accessibility focus

If accessibility validation is missing, the patch is incomplete.

---

## 3) Mode Selection (Declare One)

At the top of every implementation response, state:

- `MODE: BUGFIX/DEBUG`
or
- `MODE: NEW FEATURE`

If unclear, default to `BUGFIX/DEBUG`.

---

# MODE: BUGFIX / DEBUG

## Scope
Crashes, regressions, incorrect behavior, UI glitches, build failures, performance issues.

## Rules
- Do not change expected behavior unless clearly wrong.
- Fix smallest surface possible.
- Prefer guards and state corrections over redesign.
- Debug logs must be `#if DEBUG` gated.

## Required Output Structure

1. Repro steps
2. Root cause hypothesis
3. Minimal patch plan
4. Patch
5. Verification
   - macOS
   - iOS
   - iPadOS
   - Accessibility checks (if UI touched)
6. Risk assessment

If any section is missing, the response is invalid.

---

# MODE: NEW FEATURE

## Scope
New UI, new settings, new editor capability, new integration.

## Rules
- Must fit lightweight editor philosophy.
- No IDE bloat.
- Integrate into existing infrastructure.
- No hidden default behavior changes.

## Platform Requirements
- Must define macOS interaction model.
- Must define iOS touch interaction.
- Must define iPad keyboard/multitasking behavior.
- If platform-limited, explicitly guard and document.

## Required Output Structure

1. User problem
2. Proposed solution
3. Why this fits scope
4. Alternatives considered
5. Minimal phased plan
6. Patch
7. Acceptance criteria
8. Verification checklist
   - macOS
   - iOS
   - iPadOS
   - Accessibility validation
9. Security/privacy impact
10. Performance impact

If cross-platform verification is missing, the patch is invalid.

---

## 4) Repo Workflows and Commands

### Local git hooks

Install the repo hooks before routine development:

```bash
scripts/install_git_hooks.sh
```

The pre-commit hook auto-bumps `CURRENT_PROJECT_VERSION` for non-doc-only commits. Set `NVE_SKIP_BUILD_NUMBER_BUMP=1` only for intentional release/doc automation commits that should not bump the build number.

### Release validation

Use dry-run validation before creating or pushing release tags:

```bash
scripts/release_dry_run.sh v0.6.2
```

Use the full release orchestrator only from a clean, authenticated repo with `gh` available:

```bash
scripts/release_all.sh v0.6.2 --dry-run
scripts/release_all.sh v0.6.2 notarized
```

If an existing tag must be repointed as part of a notarized release, the supported command shape is:

```bash
scripts/release_all.sh v0.6.2 notarized --retag
```

Use `--resume-auto` to continue an interrupted release flow after checking whether local and remote tags already exist.

### Release preflight

For release-specific local checks, run:

```bash
scripts/ci/release_preflight.sh v0.6.2
```

This validates release docs, README metrics freshness when applicable, critical runtime tests, and icon payloads.

---

## 5) Code Style Expectations

- Explicit naming over comments.
- Comments explain WHY, not WHAT.
- No clever hidden logic.
- No dead code.
- No temporary hacks.

---

## 6) Absolute Stop Conditions

Stop and ask for clarification if:

- Feature requires architectural rewrite.
- Expected behavior is ambiguous.
- Security posture would change.
- Cross-platform behavior cannot be guaranteed.

Do NOT guess.

Remove `.DerivedData*` folders after use so they are not accumulated.
