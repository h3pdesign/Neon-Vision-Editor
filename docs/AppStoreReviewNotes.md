# App Store Review Notes

## In-App Purchase
- Product type: Non-Consumable
- Product ID: `h3p.neon-vision-editor.support.optional`
- Display name: Support Neon Vision Editor
- Price tier target: EUR 4.90
- Purpose: Optional support purchase only

## Important Behavior
- No app functionality is locked behind the purchase.
- Users can use the full app without purchasing.
- Purchase UI is in Settings -> Support.
- "Restore Purchases" is available in the same Support dialog.
- Support purchase is one-time and non-consumable (no subscription / no auto-renewal).
- Privacy policy link is shown in-app in the Support tab and documented in `PRIVACY.md`.
- AI completion is optional and off by default unless the user explicitly enables/selects a provider.
- External AI providers use bring-your-own API keys stored in Keychain.
- When external AI completion is triggered, only the active completion context, such as nearby code or the active selection, is sent to the selected provider.
- Custom OpenAI-compatible providers require HTTPS endpoints.
- The optional `nve` command-line helper is bundled as an app resource and is only linked when the user explicitly copies and runs the command shown in Settings -> Support. It uses `/usr/bin/open` / Launch Services to request file or folder opening in the app. It does not read file contents, run background services, collect telemetry, modify shell startup files, auto-install itself, or request Full Disk Access, Accessibility access, administrator permission, or elevated privileges.

## AI Data Disclosure
- The in-app Settings -> AI disclosure explains external provider behavior before users configure provider credentials.
- No external AI request is made while AI completion is disabled.
- Apple Intelligence remains the local/default fallback when no external provider credentials are configured.

## macOS Sandbox / Files
- The macOS target has App Sandbox enabled and user-selected read/write file access enabled.
- Files opened through Finder, Open panels, document handoff, or the `nve` Launch Services wrapper are handled by the app’s existing document-open path and security-scoped resource access.
- No App Store Connect privacy adjustment is required for `nve`; it does not collect data and does not directly access file contents.

## Test Notes
- Local StoreKit config file included at:
  - `Neon Vision Editor/SupportOptional.storekit`
- Use a Sandbox account or local StoreKit testing for verification.
