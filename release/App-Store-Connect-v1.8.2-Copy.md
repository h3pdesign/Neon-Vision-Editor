# App Store Connect Copy — v1.8.2

Copy the relevant text into App Store Connect after the release build is available. Keep customer-facing release notes separate from TestFlight instructions. Do not mark the version available before App Store Connect confirms distribution.

## Promotional Text

**Characters:** 129 / 170

```text
Read large Markdown documents in full preview, open files from Finder reliably, and keep long documents readable while scrolling.
```

## What’s New

```text
• Large Markdown documents now render as formatted previews instead of stopping at a truncated source view.
• Files and project folders sent from Finder open an editor window even when none is currently open.
• Long-document scrolling redraws the visible editor rows more consistently.
```

## TestFlight — What to Test

```text
Neon Vision Editor 1.8.2 focuses on large Markdown previews, Finder opening, and long-document scrolling.

Please test:
• Open a Markdown file of about 600 KB or 12,000 lines. Show Markdown preview and scroll to the final heading. The content should remain formatted, complete, and free of the “truncated preview” message.
• Open a Markdown file larger than 2 MB. Show the preview, check content near the end, edit and save the document, then reopen it. The preview and saved file should include the final changes.
• On macOS, close every editor window without quitting the app, then open a file and a project folder from Finder. Each should bring back an editor window with the requested content.
• Scroll a long Swift or Markdown file with preview open. Text should remain readable without missing or overlapping rows.

Please include device, OS version, file size, approximate line count, and reproduction steps with feedback.
```

## App Review Notes

```text
This update fixes large Markdown preview rendering and Finder file opening when no editor window is open. No new account, permission, purchase, or external service is needed to test these changes. To verify, open a large local Markdown file, enable Markdown preview, and scroll to its last heading; the preview should remain formatted rather than show a truncated-source warning.
```
