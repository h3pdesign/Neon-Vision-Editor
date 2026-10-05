# Privacy Policy

Neon Vision Editor does not collect, sell, or share personal data for analytics or advertising.

## Data Handling

- Local editor content stays on-device unless you explicitly open/save/export files or send context through an optional AI feature.
- API tokens for optional AI providers are stored in Apple Keychain.
- No telemetry is sent by default.

## Network Use

- Network requests occur only when you explicitly use optional AI/completion providers.
- Requests are sent over HTTPS to the selected provider endpoint.
- External AI completion requests send only the active completion context, such as the code around the cursor or the active selection, to the provider you selected.
- External AI chat sends your prompt and selected editor context to the configured provider after the in-app context disclosure and confirmation.
- Experimental Jev context ranking is disabled by default. When enabled and confirmed, it sends your prompt and bounded Current File and Project Structure excerpts to TypeSafe before external AI chat. Selection and chat history are excluded from the TypeSafe request. Apple Intelligence, Agent Mode, code completion, and follow-up messages skip ranking. TypeSafe credentials stay in Keychain; ranking uses HTTPS and does not run in the background.
- Custom OpenAI-compatible providers must use HTTPS endpoints.

## In-App Purchase

- The support purchase is an optional consumable tip that can be purchased repeatedly and grants no entitlement.
- No auto-renewing subscription is used.
- Core app functionality is not locked behind the support purchase.

## Contact

For privacy questions, use the security contact in `SECURITY.md`.
