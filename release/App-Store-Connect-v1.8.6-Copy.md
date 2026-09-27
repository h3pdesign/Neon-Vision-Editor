# App Store Connect Copy — v1.8.6

Paste the platform-appropriate text after the release build is available. GitHub publication does not establish App Store approval or availability.

## Promotional Text

```text
Edit unusually long lines on iPhone and iPad, return to editing-first Markdown with side-by-side preview on larger screens, and rearrange macOS tabs.
```

## What’s New — iPhone and iPad

```text
• Edit unusually long, single-line generated documents without changing their saved text or copied selections.
• Open Markdown for editing by default, with source and rendered preview side by side where screen width allows.
• Choose full-window Markdown reading in Settings when you want a wider reading view; formatting controls stay with the editor.
```

## What’s New — macOS

```text
• Work with Markdown source and its rendered preview side by side by default, or choose full-window reading in Settings.
• Keep Markdown formatting controls with the editor instead of over the full-window preview.
• Drag a document tab without activating its editor first, and drop it between tabs or at a strip edge.
```

## TestFlight — What to Test

```text
Neon Vision Editor 1.8.6 focuses on long-line editing, Markdown layout, and macOS tab dragging.

Please test:
• On iPhone and iPad, open a JSON or text document with a very long single line containing mixed Unicode. Insert and delete near the beginning, middle, and end; select and copy text; undo and redo; save and reopen. Confirm the original characters and offsets remain correct.
• On iPad, repeat with No Wrap selected, then background and foreground the app. Check editing responsiveness, caret position, and VoiceOver navigation.
• Open Markdown and confirm editing is the default. On a regular-width iPad or macOS window, check the side-by-side preview; on iPhone, check its compact presentation. Switch to full-window reading in Settings, then return to editing; confirm the formatting controls appear only with the editor.
• On macOS, drag an inactive document tab across another tab, into a gap, and to a strip edge. Confirm the drag begins before the document switches, the order changes, and a normal click, double-click close, keyboard selection, and VoiceOver activation still work.

Include the device, OS version, document size and line length, and exact steps with feedback.
```

## App Review Notes

```text
This update improves editing of unusually long single-line documents on iPhone and iPad, restores Markdown editing as the default with side-by-side preview where space allows, and adjusts macOS document-tab dragging. The long-line presentation is display-only; saved document text and copied selections remain unchanged. Full-window Markdown reading is available in Settings. No new account, permission, purchase, or external service is required to test these changes. The optional support tip remains unchanged and does not unlock features.
```
