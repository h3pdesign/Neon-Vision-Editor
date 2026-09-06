# File Provider safety verification

Automated tests cover local file admission, failed reads, coordinated access,
missing-file conflicts, queued saves, encoding preservation, and file-backed
documents. They do not establish that Nextcloud uploaded a saved file.

## Required device acceptance test

Use disposable files only. Record the exact iPhone/iPad model, iOS/iPadOS version,
Nextcloud app and server versions, and Neon build. “Current version” is not a
reproducible version identifier.
Use a development/TestFlight build containing this patch; the existing App Store
build cannot validate changes that have not been published.

1. Create text files named `notes.txt`, `notes.custom-extension`, `NOTES`, and
   `.custom-settings`; include Unicode, empty text, and a larger text file.
2. In Files, select Nextcloud and open each in Neon. Edit, save, close, reopen,
   and compare the complete contents both in Files and on the server.
3. Repeat with an initially undownloaded file, offline, after backgrounding,
   and after terminating/relaunching Neon. Check that errors never replace the
   document with an empty buffer or silently discard dirty edits.
4. While Neon has unsaved edits, modify or delete the disposable source from
   another client. Saving must preserve the local edits and present a conflict
   or error instead of silently recreating or overwriting the source.
5. Make rapid edits and repeated saves, including immediately before
   backgrounding. The final saved contents must be the newest requested revision.
6. For an external document saved on iOS/visionOS, check Files → On My
   iPhone/iPad → Neon Vision Editor → Neon Recovery. The latest full save payload
   is retained there, with a path-derived prefix, even after a provider accepts
   the save. Compare it with the intended edits when testing upload failures.
7. Try binary data with an unknown suffix. A rejected read must leave the source
   unchanged and the failed placeholder non-editable.
8. Use Save and Close, Close All, and Close Project during a slow/offline save.
   Tabs must remain available until saving succeeds; failed/conflicted documents
   must remain open. Include an ANSI-colored terminal log and consecutive saves
   that change the file size or encoding.

Recovery copies are local, contain document text, and are not server-sync
receipts. They retain the latest attempted save per source path, not version
history or edits never submitted for saving. Delete disposable recovery copies
after testing; do not uninstall the app before retrieving a needed copy.

## Acceptance boundary

Device/provider verification remains pending until the above cases pass on the
affected Nextcloud setup. Local builds and synthetic tests cannot attribute the
original loss to Nextcloud or prove that a remote upload completed.

## Local verification — 2026-09-05

- Verification Level 2: macOS, iOS Simulator, iPad Simulator, and visionOS builds passed with Xcode 27 beta.
- Final serial macOS regression run: 89 tests passed across
  file opening and file-backed documents, including UTF-16 split surrogates, queued
  encoding changes, stale metadata, ANSI preservation, recovery contents, snapshot
  isolation, a deliberately blocked coordinated writer, and save-before-close/conflict retention.
- Final large-Markdown activation: 662 ms total, 213 ms longest main-thread gap
  (below the 250 ms test limit). The preceding 87-test run measured 524 ms / 11 ms.
  The preceding parallel run exceeded the 250 ms responsiveness limit at 389 ms;
  concurrent test-host load remains a timing sensitivity, not proof of a provider defect.
- Existing unrelated test-concurrency and App Intents metadata-extraction warnings remain.
- Temporary matrix build products were removed by the matrix script.
- Actual Nextcloud upload/recovery, physical-device UI/accessibility behavior, and
  provider-dependent total save latency have not been verified. File-backed saves now
  use an exclusively owned snapshot on a background worker; the held-lock test verifies
  that initiating Save does not wait on the main actor and later edits survive.

## Reviewed changes

- `EditorViewModel.enqueueSave`: queue-aware normalization and fresh post-replacement
  metadata, so a previous save cannot invalidate an equivalent queued encoding request.
- `FileBackedTextDocument.SaveSnapshot`: background Save/Save As without sharing the
  live mutable document or seekable handle; subsequent edits retain their recovery log.
- `CoordinatedDocumentAccess.isText` and file-load normalization: permit ANSI/control
  text without stripping it, while keeping NUL-based binary rejection.
- `EditorViewModel.saveAndCloseTabs` and close actions: await writes before discarding
  buffers, and retain failed/conflicted tabs and their project access.
- Recovery storage tests use an injected temporary directory, exercising full-copy,
  replacement, source separation, and error preservation without accessing real files.
