# App Store Readiness (Checked: 2026-02-07)

## Completed in codebase
- API tokens moved from `UserDefaults` to Keychain (`SecureTokenStore`).
- Added privacy manifest: `Neon Vision Editor/PrivacyInfo.xcprivacy`.
- Disabled unnecessary incoming-network sandbox entitlement.
- Disabled app-group registration entitlement (not used by app).
- Added `ITSAppUsesNonExemptEncryption = NO` in generated Info.plist settings.
- Moved Gemini API key transport from URL query parameters to request headers.
- Reduced production log verbosity for network failures (debug-only logs).

## Still required in App Store Connect / release process
- Add/update Privacy Policy URL and support URL in app metadata.
- Complete App Privacy questionnaire to match real behavior (AI prompts/source code sent to providers).
- Verify age rating and regional availability.
- Provide reviewer notes that explain AI provider setup (bring-your-own API key flow).
- Upload final screenshots for all device classes enabled by target (`iPhone` + `iPad` and macOS listing if shipping macOS on App Store).
- Ensure valid Apple signing certificates/profiles exist on the build machine for both iOS and macOS distribution.
- No App Store Connect privacy metadata adjustment is required for the optional bundled `nve` command-line helper. It is user-linked from Settings, opens files/folders through Launch Services, does not collect data, does not run background services, and does not access file contents directly.

## High-risk rejection pitfalls to avoid
- Hidden paywalls or paid features without In-App Purchase.
- Missing disclosure for data sent to third-party AI endpoints.
- Non-functional “Sign in with Apple” parity if any third-party login is added later.
- Broken document open/save flows, especially around permission prompts and sandboxed file access.
- Shipping a helper that auto-installs itself, modifies shell startup files, requests elevated privileges, or weakens sandbox posture.
- Misleading marketing text (claims not supported by in-app functionality).

## Pre-submit validation
- `xcodebuild` simulator build passes.
- Archive with Release config and upload through Organizer or `scripts/archive_testflight.sh`.
- Run through first-launch flow with no API key configured.
- Verify all AI providers fail gracefully and show user-facing errors.
- Run the iOS/iPadOS external-document regression matrix in `release/iOS-File-Handler-QA-Matrix.md`.
- Confirm Files app and Share sheet both open supported text/source files into Neon Vision Editor without duplicate-tab regressions.
