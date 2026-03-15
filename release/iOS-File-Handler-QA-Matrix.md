# iOS File Handler QA Matrix

Last updated: 2026-03-15

Goal: verify that iPhone and iPad file-opening behavior stays reliable across Files app, Share sheet, and default-app selection before each release.

## Coverage matrix

| File type | Example extension | Files app open | Share sheet open | Default-app picker | In-app result |
| --- | --- | --- | --- | --- | --- |
| Plain text | `.txt` | Required | Required | Required | Opens editable in a tab |
| Markdown | `.md` | Required | Required | Required | Opens editable with markdown language |
| JSON | `.json` | Required | Required | Required | Opens editable with JSON language |
| XML | `.xml` | Required | Required | Optional | Opens editable with XML language |
| Property list | `.plist` | Required | Required | Optional | Opens editable with plist/XML language |
| Shell script | `.sh` | Required | Required | Optional | Opens editable with shell language |

## Devices

- iPhone Simulator
- iPad Simulator
- At least one physical iPhone or iPad before release candidate sign-off

## Test steps

### Files app / default app

1. Put one sample file of each covered type into Files/iCloud Drive.
2. Open the file from Files.
3. If the system shows an app picker, choose Neon Vision Editor.
4. If Neon Vision Editor is already the default suggestion, use that direct path once and the picker path once.
5. Confirm:
   - file opens without unsupported-file alert
   - correct filename appears in the selected tab
   - file content is visible and editable
   - reopening the same file focuses the existing tab instead of creating duplicates

### Share sheet

1. In Files, long-press the same sample file.
2. Use `Share` -> `Open in Neon Vision Editor` (or equivalent app target).
3. Confirm the same expectations as above.

### Regression checks

1. Open a supported file externally, edit it, and confirm tab state becomes dirty.
2. Open another supported file externally and confirm tab switching remains correct.
3. Attempt to open one unsupported binary file (for example `.png`) and confirm the app rejects it gracefully.
4. Repeat one supported-file open while the file is already open and confirm no duplicate tab is created.

## Release sign-off

Mark release-ready only when:

- all required matrix rows pass on iPhone and iPad simulator
- one physical iOS/iPadOS device confirms at least `.txt`, `.md`, `.json`
- no regression is found in existing in-app open/import flows
