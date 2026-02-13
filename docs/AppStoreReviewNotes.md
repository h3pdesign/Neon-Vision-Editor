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

## Test Notes
- Local StoreKit config file included at:
  - `Neon Vision Editor/SupportOptional.storekit`
- Use a Sandbox account or local StoreKit testing for verification.
