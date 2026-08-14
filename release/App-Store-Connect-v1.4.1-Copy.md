# App Store Connect Copy — v1.4.0–v1.4.1

Copy the text in the relevant section directly into App Store Connect. Keep the App Store and TestFlight copy separate: the former is customer-facing; the latter asks testers to exercise specific paths.

## Promotional Text

**Characters:** 146 / 170

```text
Work smoothly with large files in a responsive virtualized editor, plus reachable toolbars, pinch-to-zoom project files, and reliable Watch notes.
```

## What’s New

```text
• Edit large documents more responsively with a file-backed, virtualized editor that preserves scrolling and selection.
• Every named toolbar preset action is now directly reachable on iPhone and iPad.
• Pinch to adjust project-sidebar file text size.
• Improved iPhone toolbar stability and Apple Watch note delivery.
• Refined outlines, Quick Look refresh, compact language labels, and reliable file opening.
```

## TestFlight — What to Test

```text
Neon Vision Editor 1.4.0–1.4.1 improves large-document editing, mobile controls, project navigation, and Apple Watch note delivery.

Please test:
• On iPhone and iPad, select each named toolbar preset and confirm every enabled action is available in the horizontal toolbar.
• In a project sidebar, pinch in and out over file items; confirm the text size changes smoothly and remains readable after relaunching.
• On macOS, open a large file, scroll, edit, select text, save, and reopen it. Confirm the editor remains responsive and preserves the active selection and document content.
• From the paired Apple Watch, send a note while the iPhone app is open and again while it is in the background. Confirm one note appears in Neon Inbox.md and the Watch stops retrying after acknowledgement.
• Open a document with an outline, switch documents, and reopen the first document. Confirm its outline and Quick Look preview remain current.

Please include your device, OS version, toolbar preset, and steps to reproduce with any feedback.
```

## Reusable Prompt (English)

```text
Act as an App Store Connect release-copy editor. Using only the user-facing changes in the release notes below, produce copy for version [VERSION] of [APP NAME]. Do not invent features, performance claims, compatibility claims, or fixes.

Return exactly these sections in plain text, ready to paste:

1. Promotional Text
- One sentence, maximum 170 characters including spaces.
- Lead with the strongest current benefit.
- Do not use version numbers, prices, URLs, emojis, marketing superlatives, or unsupported claims.
- State the exact character count after the text.

2. What’s New
- Three to five concise bullets for App Store customers.
- Prioritize visible improvements and meaningful reliability fixes.
- Use simple, customer-facing language; omit internal architecture and implementation details.

3. TestFlight — What to Test
- Start with one short summary sentence.
- Provide three to five concrete, reproducible checks tied to the changes.
- Include expected results and ask testers to send device, OS version, and reproduction steps with feedback.
- Clearly distinguish an intentional test from a general marketing claim.

Release notes:
[PASTE CHANGELOG SECTION HERE]
```

## Source Scope

Derived only from `CHANGELOG.md` v1.4.0–v1.4.1: file-backed virtualized large-document editing, reachable mobile toolbar actions, project-sidebar pinch sizing, WatchConnectivity reliability, compact language labels, outline navigation, Quick Look refresh, and iPhone toolbar stability.
