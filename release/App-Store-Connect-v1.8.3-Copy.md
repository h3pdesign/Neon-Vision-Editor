# App Store Connect Copy — v1.8.3

Paste the platform-appropriate text after the release build is available. GitHub publication does not imply App Store approval or availability.

## Promotional Text

```text
Edit complete large text files, enjoy clearer mobile toolbars, and keep long lines, syntax colors, and formatting consistent across your documents.
```

## What’s New — iPhone and iPad

```text
• Open supported text files below 100 MB as complete editable documents.
• Read and scroll long lines without clipped text when line wrap is turned off.
• Keep line-wrap settings consistent when showing or hiding the keyboard.
• Get more consistent syntax highlighting while scrolling large code and HTML files.
• Enjoy refined toolbars with system-adaptive Liquid Glass, one-line labels, colored presets, and optional larger symbols.
• Apply the selected custom toolbar action count correctly while keeping Settings and Help accessible.
```

## What’s New — macOS

```text
• Open supported text files below 100 MB as complete editable documents.
• Apply theme changes immediately without switching document tabs.
• Get more consistent syntax highlighting, bold keywords, Markdown headings, italic comments, and underlined links.
• Use native Settings panes with corrected sizing and titlebar appearance, without repeated window repositioning.
• Reduce duplicate editor refresh work when changing settings and repeated session updates during startup.
• This version supports Apple Silicon Macs only. No document migration is required.
```

## TestFlight — What to Test

```text
Neon Vision Editor 1.8.3 focuses on complete text-file editing, long-line rendering, Settings, and syntax formatting.

Please test:
• Open, edit, save, and reopen HTML, Markdown, JSON, CSV, and source files between 10 and 99 MB. Verify content near the end remains accessible and saved changes persist.
• On iPhone and iPad, disable line wrap, scroll long lines horizontally in both directions, and move the cursor to the end. Check for blank strips, clipped characters, and unexpected jumps.
• Toggle line wrap with the keyboard visible, dismiss the keyboard, switch documents, and rotate the device. The chosen setting should remain consistent.
• Change themes and toggle bold keywords, bold Markdown headings, italic comments, and underlined links. Check the active document without switching tabs.
• On macOS, open and reopen Settings, switch every pane, and check sizing, position, header appearance, and responsiveness.
• On mobile, select a Custom toolbar, change the visible action count, and check Settings, Help, presets, labels, and optional larger symbols. Check the keyboard toolbar against system glass and accessibility settings.

Include device, OS version, file format and size, approximate line count, and reproduction steps with feedback. Mac builds require Apple Silicon.
```

## App Review Notes

```text
This update fixes text rendering with line wrap disabled on iPhone and iPad, improves complete editing of supported text files below 100 MB, and corrects Settings, syntax formatting, and mobile toolbar behavior. No new account, permission, purchase, or external service is required to test these changes. Open a local text file with long lines, disable line wrap, and scroll horizontally; re-enable line wrap with and without the keyboard visible. On macOS, also open Settings and switch panes, then change a theme or formatting option while a document is open. Mac builds now require Apple Silicon.
```
