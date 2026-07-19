# Command-Line Helper (`nve`)

`nve` is a lightweight macOS shell helper for opening files in the direct GitHub release of Neon Vision Editor from Terminal. It is not included in Mac App Store builds.

## Distribution model

- Direct GitHub app builds bundle the helper as `Neon Vision Editor.app/Contents/Resources/nve`.
- The app does not auto-install the helper, modify shell startup files, or write links into `/usr/local/bin`.
- The Settings support section shows a user-local link command that the user can copy and run explicitly.
- It calls `/usr/bin/open -a "Neon Vision Editor"` and passes user-supplied file paths to macOS Launch Services.
- It does not read file contents, write files, request Full Disk Access, request Accessibility access, install privileged components, or run with elevated permissions.
- It validates that each path exists before forwarding it to Launch Services.

## macOS permission behavior

The helper itself does not show permission prompts because it does not access file contents. macOS grants the sandboxed app access through the document-open flow when Launch Services delivers the file-open request to Neon Vision Editor.

Inside the app, file loading uses security-scoped access before reading the URL. This matches the sandbox model for user-selected/opened documents.

If a file is in a protected location and macOS requires additional user approval, the prompt belongs to the app/system file-access flow, not to the helper script. The helper must not request Full Disk Access or Accessibility permission.

## App Store compliance notes

For the bundled, user-linked helper:

- No App Store Connect privacy metadata change is required.
- No additional entitlement is required beyond the existing macOS App Sandbox and user-selected read/write file access.
- The helper should be described as optional, user-initiated, and limited to opening files/folders through Launch Services.
- Reviewer notes should state that it does not run background services, collect telemetry, request privileged permissions, or access file contents directly.

If a future release replaces the shell wrapper with a compiled helper tool, Apple’s sandbox guidance applies: the helper must inherit the containing app’s sandbox configuration, and the release must be rechecked for signing, sandbox inheritance, and App Store review notes.

## Usage

```bash
nve README.md
nve --wait --new-window "Neon Vision Editor/UI/ContentView.swift"
nve --line 42 "Neon Vision Editor/UI/ContentView.swift"
```

## User-local link

The app shows this command in Settings > Support on macOS:

```bash
mkdir -p "$HOME/bin"
ln -sf "/Applications/Neon Vision Editor.app/Contents/Resources/nve" "$HOME/bin/nve"
```

If the app is installed somewhere else, use the path shown in Settings.

`--line` is accepted for compatibility with editor-style CLI workflows. Current builds open the file without cursor placement.
