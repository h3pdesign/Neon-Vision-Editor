# Apple Store Distribution Checklist (iOS + macOS)

Checked on: 2026-02-07

## Required app-side files/settings
- `PrivacyInfo.xcprivacy` included in app bundle.
- App icon assets present and generated for target platforms.
- `ITSAppUsesNonExemptEncryption` set (currently `NO`).
- App Sandbox enabled for macOS target.
- Only required entitlements enabled (incoming network disabled, app groups disabled).
- macOS user-selected read/write file access remains enabled for document open/save flows.
- `nve` is bundled as an optional app resource and only linked by an explicit user-run command shown in Settings.

## Required App Store Connect metadata
- Privacy Policy URL
- Support URL
- App description, keywords, and category
- Age rating questionnaire
- App Privacy data collection answers
- Export compliance answers (encryption)
- Reviewer notes (include AI provider behavior and user-supplied API key flow)
- No extra App Privacy questionnaire entry is needed for `nve`; it does not collect data, does not run background services, and does not access file contents directly. Mention in reviewer notes if marketing/review text calls out terminal opening.

## Required media/assets in App Store Connect
- iPhone screenshots
- iPad screenshots
- macOS screenshots (if distributing the macOS build via App Store)
- Promotional text / What’s New

## Security checks before submit
- No hardcoded secrets or API tokens in source.
- API tokens stored in Keychain, not `UserDefaults`.
- No tokens embedded in URL query strings.
- Production logs do not include provider tokens or sensitive payloads.
- Network traffic uses HTTPS only.
- Command-line helper does not auto-install, modify shell startup files, request Full Disk Access, Accessibility, administrator privileges, background execution, telemetry, or direct file-content access.

## Signing/distribution prerequisites
- Valid team provisioning access in Xcode (`CS727NF72U`).
- Valid iOS distribution signing assets on the release machine.
- Valid macOS distribution signing assets on the release machine.
- Archive from `Release` configuration and upload via Organizer/TestFlight flow.
