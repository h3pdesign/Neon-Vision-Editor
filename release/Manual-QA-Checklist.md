# Manual QA Checklist

Use this checklist for release candidates after automated preflight passes.

## App Store Review Smoke

- Run `scripts/ci/app_store_review_preflight.sh`.
- On a fresh iPad or visionOS simulator install, open the app and immediately tap Settings.
- Confirm Settings opens once, stays stable, and is not interrupted by Welcome, Support, Help, or Markdown Preview sheets.
- Open `samples/markdown-fixtures/compact-preview-clipping-regression.md`, enable Markdown Preview, and confirm preview body text matches the editor font size.
- Confirm Line Wrap is enabled for a fresh install before changing editor settings.
- Check device logs for crashes or SwiftUI sheet warnings during the first Settings open.

## macOS Settings Resize

- Open Settings on macOS.
- Resize the window down to its minimum height and confirm content remains scrollable.
- Switch through General, Editor, Templates, Themes, Support, AI, Remote, Updates, and Diagnostics.
- Confirm the selected tab remains visible and keyboard focus moves through controls in order.
- Confirm Escape or Command-W closes Settings without trapping focus.

## Markdown Preview Compact Themes

- Open `samples/markdown-fixtures/compact-preview-clipping-regression.md`.
- On iPhone, open Markdown Preview and switch through every template.
- Confirm long headings and URLs wrap instead of clipping off the left or right edge.
- Confirm wide tables scroll inside the table block and do not create page-level horizontal scrolling.
- Confirm code blocks remain readable in Default, Changelog, Focus Writing, Presentation, and Neon Paper.

## macOS Editor Flicker

- Open a generated Swift sample from `scripts/benchmark_large_file.sh 100000`.
- Disable Line Wrap.
- Enable Bold Keywords.
- Test fast vertical scrolling with Highlight Current Line enabled.
- Test fast vertical scrolling with Highlight Matching Brackets enabled.
- Test fast vertical scrolling with both overlays enabled.
- Confirm text remains visible and keywords do not flicker or disappear.
