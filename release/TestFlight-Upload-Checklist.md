# TestFlight Upload Checklist (iOS + iPadOS)

## 1) Versioning
- In Xcode target settings (`General`): set `Version` (marketing version) for the release.
- Increase `Build` (build number) for every upload.
- Confirm bundle identifier is correct: `h3p.Neon-Vision-Editor`.

## 2) Signing & Capabilities
- Signing style: `Automatic`.
- Team selected: `CS727NF72U`.
- Confirm iPhone + iPad support remains enabled.
- Ensure an `Apple Distribution` certificate exists for your team.
- In Xcode (`Settings` -> `Accounts`), sign in with an App Store Connect user that has provider access to the app/team.

## 3) Archive (Xcode)
- Select scheme: `Neon Vision Editor`.
- Destination: `Any iOS Device (arm64)`.
- Product -> `Archive`.
- In Organizer, verify no critical warnings.

## 4) Export / Upload
- Option A (Xcode Organizer): `Distribute App` -> `App Store Connect` -> `Upload`.
- Option B (CLI export):
  - Run: `./scripts/archive_testflight.sh`
  - Uses: `release/ExportOptions-TestFlight.plist`
  - Upload resulting IPA with Apple Transporter.

## 5) App Store Connect checks
- New build appears in TestFlight (processing may take 5-30 min).
- Fill export compliance if prompted.
- Add internal testers and release notes.
- For external testing: submit Beta App Review.
- Follow release-notes structure from `release/RELEASE_NOTES_TEMPLATE.md`:
  - Hero screenshot
  - Why Upgrade (3 bullets)
  - Highlights
  - Fixes
  - Breaking changes
  - Migration

## 7) If export/upload fails
- `No provider associated with App Store Connect user`: fix Apple ID account/provider access in Xcode Accounts.
- `No profiles for 'h3p.Neon-Vision-Editor' were found`: refresh signing identities/profiles and retry with `-allowProvisioningUpdates`.
- If CLI export still fails, upload directly from Organizer (`Distribute App`) first, then return to CLI flow.

## 6) Pre-flight quality gates
- App launches on iPhone and iPad.
- Open/Save flow works (including iOS document picker).
- Run `release/iOS-File-Handler-QA-Matrix.md` on iPhone + iPad simulator.
- Validate external file open from Files app / Share sheet for `.txt`, `.md`, `.json`, `.xml`, `.plist`, `.sh`.
- Confirm reopening the same external file focuses the existing tab instead of duplicating it.
- New window behavior on macOS remains unaffected.
- No crash on startup with empty documents.
- Basic regression pass: tabs, search/replace, sidebars, translucency toggle.
