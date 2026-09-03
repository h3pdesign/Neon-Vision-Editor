# App Store Review Notes

## In-App Purchase
- Product type: Consumable
- Product ID: `002420160`
- Display name: Support Tip for Neon Vision Editor
- Price tier target: EUR 4.99 (the app always displays StoreKit's localized price)
- Purpose: Optional support tip only; it can be purchased multiple times.

## Important Behavior
- No app functionality is locked behind the purchase.
- Users can use the full app without purchasing.
- Purchase UI is in Settings -> Support.
- No restore action is required because this is consumable and grants no entitlement.
- Support purchase has no subscription and no auto-renewal.
- The purchase unlocks no features; all editor functionality remains available without payment.
- The support screen handles loading, missing-product, StoreKit-unavailable, cancelled, and failed-purchase states.
- The purchase price is loaded from StoreKit and localized for the user's storefront.
- Privacy policy link is shown in-app in the Support tab and documented in `PRIVACY.md`.
- AI completion is optional and off by default unless the user explicitly enables/selects a provider.
- External AI providers use bring-your-own API keys stored in Keychain.
- When external AI completion is triggered, only the active completion context, such as nearby code or the active selection, is sent to the selected provider.
- Custom OpenAI-compatible providers require HTTPS endpoints.

## AI Data Disclosure
- The in-app Settings -> AI disclosure explains external provider behavior before users configure provider credentials.
- No external AI request is made while AI completion is disabled.
- Apple Intelligence remains the local/default fallback when no external provider credentials are configured.

## macOS Sandbox / Files
- The macOS target has App Sandbox enabled and user-selected read/write file access enabled.
- Files opened through Finder, Open panels, or document handoff are handled by the app’s existing document-open path and security-scoped resource access.
- Neon Vision Editor does not collect data or include tracking; optional external AI requests occur only after the user enables and configures a provider.

## Test Notes
- Local StoreKit config file included at:
  - `Neon Vision Editor/SupportOptional.storekit`
- Local StoreKit tests verify loading and purchase state transitions, but do not verify App Store Connect or App Review sandbox availability.
- Before resubmitting, use a TestFlight build on iPhone and Apple Vision Pro to open Settings -> Support, confirm the localized price loads, and complete a sandbox support tip. Also check the welcome/support prompt purchase entry points.
- For an Xcode-launched sandbox check, set the Run action's StoreKit Configuration to None; the shared schemes use the local configuration by default. TestFlight always uses Apple's sandbox.
- A failed or interrupted lookup must recover when revisiting Support or selecting Retry App Store. Successful prices may be cached for five minutes.
- visionOS purchases use the presenting SwiftUI view's StoreKit purchase action so the system can anchor purchase confirmation to the correct window.
