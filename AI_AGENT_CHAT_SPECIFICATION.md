# AI Agent and Chat — Specification and Requirements

Reviewed: 2026-09-05. Development branch: `codex/macos-27-agentic-editor`.

This document defines the intended product contract and release requirements. A requirement is not proof of implementation or App Review approval. See the review record and verification evidence below for remaining work.

## Product purpose

Help people understand and improve the document or project already open in Neon without turning a lightweight editor into an autonomous IDE. Keep ordinary chat useful without a project. Agent Mode adds narrowly scoped project discovery and proposals; the editor owns permissions, document mutations, and execution.

### Supported experiences

| Experience | Inputs | Model capabilities | User-controlled outcome |
| --- | --- | --- | --- |
| Chat | User prompt and explicitly selected context | Existing configured provider; no project tools | Copy, review, insert, or confirm replacement |
| Explore | User prompt and indexed project | Search and bounded text reads | Evidence-based explanation with uncertainty |
| Edit | User prompt, exact captured editable selection, optional project context | Same read tools; structured replacement | Compare original/proposal, then explicitly apply |
| Verify | User prompt and project evidence | Suggest a predefined verification category | Inspect the resolved command and approve execution where supported |

Agent Mode requires macOS 27, a usable Apple Intelligence model, and an open project. Ordinary chat remains available across supported platforms. Store and sandboxed builds do not run verification subprocesses. Direct macOS builds may run approved verification plans. No new entitlement or sandbox exception is implied by this specification.

## Architecture and ownership

`AIChatConversation` is scene-local and owns request identity, messages, cancellation, retry, and saved sessions. `ContentView+AIChat` captures editor state and routes proposals to existing diff, replacement, and undo paths. `AppleEditorAgentAIClient` owns Foundation Models generation and structured results. `EditorAgentWorkspace` enforces project read policy. `EditorAgentVerificationResolver` and `EditorAgentVerificationRunner` resolve and execute approved commands.

Foundation Models dynamic profiles select instructions, tools, and model configuration. A profile is a configuration, not an authorization boundary. File and execution policies must hold even if the generated response or a tool argument is malicious. Do not introduce additional agents, MCP servers, embeddings, dependencies, or broad refactoring without a concrete task that needs them. Apple describes profiles as flexible building blocks for context and model orchestration; this implementation deliberately uses a small set of phases. [Apple: agentic app experiences](https://developer.apple.com/videos/play/wwdc2026/242/)

## Functional requirements

| ID | Requirement | Acceptance evidence |
| --- | --- | --- |
| CHAT-01 | A cancelled or superseded request cannot update messages, errors, structured proposals, or retry state after an asynchronous suspension. | Delayed provider-result regression; clear/new request while final metadata is pending. |
| CHAT-02 | Restoring saved text does not restore executable approval or silently attach fresh editor contents. | Restore/clear regression; inspect persistence payload. |
| CTX-01 | Preserve the complete current user request. Never trim arbitrary prefixes/suffixes to fit a model. | Oversized request rejected with actionable message. |
| CTX-02 | Exact edit source must reach the model unchanged. Reject an oversized selection instead of replacing a larger range using a partial excerpt. | Whitespace, Unicode, and oversized-selection tests. |
| CTX-03 | Account for model context capacity, instructions, tool schemas/results, and generated response. Optional excerpts must disclose truncation. | Token budget tests plus live model evaluation. |
| TOOL-01 | Reads and search stay inside the captured root and file allowlist, including changed symlinks. Reject directories, FIFOs, and other special files. | Read/search symlink replacement and special-file tests. |
| TOOL-02 | Bound bytes, matches, total tool calls, and elapsed work; observe cancellation between operations. | Budget exhaustion and cancellation tests. |
| TOOL-03 | Tool results and source files are untrusted reference material. Text in them cannot grant permission or select an executable. | Prompt-injection fixtures and host policy tests. |
| EDIT-01 | Preserve replacement indentation, trailing spaces, line endings, and newlines. | Exact-byte/string proposal tests. |
| EDIT-02 | Revalidate tab identity, original source, range, and editability before applying. Use the editor's existing mutation/undo path. | Change selection/tab/source while generation or review is pending. |
| RUN-01 | Only predefined executable/argument shapes may run, after a visible command and directory approval. | Argument injection and sandbox boundary tests. |
| RUN-02 | Stop, timeout, output limits, and pre-launch cancellation apply to the subprocess lifecycle. Do not report success for cancelled or incomplete execution. | Direct-build process fixtures, including SIGTERM resistance. |
| RUN-03 | Build/test/run can execute project scripts, write files, resolve dependencies, and contact services. The approval must disclose this; an executable allowlist is not a sandbox. | Approval copy review and direct-build integration test. |
| RUN-04 | Verification targets must be tied to the relevant project/file. A later tab switch cannot silently retarget an earlier result. | Project-switch regression and explicit target review. |
| PRIV-01 | On-device is the default. PCC is opt-in; the composer and result must not describe a cloud-enabled run as exclusively local. | Local/PCC UI states and settings tests. |
| PRIV-02 | External provider transmission requires clear disclosure and permission for the actual context being sent. Tokens stay in Keychain. | Provider switch, sensitive current-file context, and retry review. |
| PRIV-03 | Project reads may contain confidential material. Avoid credentials, secret files, raw query/content telemetry, and persistent tool-output logs. | Secret fixtures and persistence/log audit. |

Project paths are captured, but file contents read from disk are not an immutable project snapshot. Results can become stale. Open unsaved buffers and disk content must be distinguished in explanations; no result should claim a successful compiler run on unsaved text unless that exact text was tested.

## Interaction design

Use one assistant sidebar with a compact provider/status header, message history, optional result card, and composer. Chat is the default. Enabling Agent Mode explains its indexed-project read access. Place the Explore/Edit/Verify selector on its own row so labels remain readable at the narrowest sidebar width.

Show a concise scope label before sending: selected document/selection and project access. For Edit, clearly explain a missing or oversized selection. Preserve the typed prompt on validation failure. Never hide an error solely inside the activity disclosure.

Distinguish “proposal prepared,” “applied,” “verification running,” “passed,” “failed,” “cancelled,” and “timed out.” Do not show a success icon merely because the model generated text. Keep Stop reachable during work even if project eligibility changes. Disabling Stop must wait for termination, not merely cancellation being requested.

The result card should show the actual processing location, a short evidence summary, optional activity disclosure, and relevant review actions. Review opens the existing diff. Apply requires confirmation and stale-source validation. A result must not regain unsafe generic Apply behavior after starting a new chat turn or restoring history.

Use native buttons, segmented controls, text selection, semantic labels, and keyboard focus. Verify Command-Return, Tab/Shift-Tab, Escape, VoiceOver labels/order, narrow width, appearance changes, and reduced motion. Status cannot depend on color alone. Apple’s Generative AI HIG is a design reference; its dynamically rendered page was not fully extractable during this review, so no detailed HIG compliance claim is made. [Apple HIG](https://developer.apple.com/design/human-interface-guidelines/generative-ai)

## Apple platform and review requirements

- Guideline 2.1: no claims of finished model quality, purchases, entitlement access, or runtime behavior based solely on compilation. Provide a working review path with availability/error states.
- Guideline 2.5.2: retain the existing Store execution boundary and self-contained app behavior. Direct distribution does not establish Store eligibility.
- Guideline 5.1.2: explain data sharing and obtain permission where required, including external AI providers. Review the privacy policy and App Store privacy answers before release.

These are engineering acceptance criteria based on the current guidelines, not legal advice or an App Review decision. [Apple App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)

PCC depends on Apple approval/entitlement, model availability, connectivity, and user quota. Check actual availability and quota before offering the feature. If a quota is exhausted, show persistent actionable status or an explicit local alternative; do not repeatedly retry or silently route to an unrelated provider. Availability fallback is distinct from fallback after a request fails. Apple recommends evaluating local/server quality and exposing usage-limit states in the existing UI. [Apple PCC integration](https://developer.apple.com/videos/play/wwdc2026/319/)

## Evaluation and release gate

Deterministic tests validate host invariants. They cannot establish model accuracy, instruction-following, tool selection, or usable latency. Maintain a separate repeatable model evaluation set with Swift, Python, Markdown, Unicode, empty/malformed files, missing symbols, large context, stale edits, secret-like text, and prompt injection in comments/tool results.

For each evaluation record OS/SDK/model, prompt, permitted scope, expected observable outcome, tool trajectory, run status, duration, number of calls, and human review. Keep fixtures synthetic and exclude real credentials. Run multiple trials; score task outcome and policy violations separately. Model-as-judge scores alone cannot approve edits or release. Apple’s Evaluations guidance covers datasets and tool evaluations; Anthropic likewise separates task outcomes from agent trajectories and recommends repeatable harnesses. [Apple evaluations](https://developer.apple.com/videos/play/wwdc2026/299/), [Anthropic agent evals](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents)

Prefer targeted retrieval and a small relevant context over repeatedly sending the whole project. Record bounded output and uncertainty when evidence is incomplete; summarization must preserve the active request and relevant facts. This follows the context-engineering principle of selecting high-signal information rather than equating larger context with better answers. [Anthropic context engineering](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)

Release requires: focused regressions, Level 2 builds for macOS/iOS/iPadOS/visionOS, Store execution-boundary audit, runtime UI/accessibility checks, direct-build cancellation/output tests, live local-model task evaluations, and PCC entitlement/quota testing if PCC is offered. Any unverified item remains an explicit release blocker, even if source review is finalized.

## Review record

Initial review of `ccc1b1ca` found request loss through suffix truncation, incomplete edit-source delivery, replacement whitespace loss, stale metadata publication after awaits, search paths bypassing fresh containment validation, unlimited aggregate tool work, and subprocess termination/output bounds that did not match the UI promise. The review also found insufficient distinction between local and PCC-enabled processing and a crowded horizontal mode selector.

An independent reviewer identified six additional issues: generic edit actions returning on older/restored agent messages, missing PCC quota checks, discarded cancellation status, ordinary child processes surviving termination, missing secret-read exclusions, and undisclosed excerpt truncation. A second independent source pass confirmed all six corrections and found no additional P1/P2 issue within the reviewed scope. This is source-review clearance, not runtime or compliance approval.

Focused macOS tests: 21 passed, zero failed, four execution tests skipped by the sandboxed test host. A standalone direct-execution harness separately passed all four process scenarios: SIGTERM-resistant timeout, a bounded 128 KiB tail from 2 MiB output, cancellation before launch, and termination of ordinary child processes. The Store execution-boundary audit passed.

Level 2 verification with Xcode 27 beta: macOS, iOS Simulator, iPad Simulator, and visionOS builds all passed. No cross-platform build issue was found. Generated matrix DerivedData was removed by the verification script. These are compile checks, not device/UI tests.

Still required before release: runtime UI/VoiceOver/keyboard checks, representative live-model evaluations including prompt injection and accumulated tool context, and PCC entitlement/quota/device validation. Credential filtering is defense in depth, not a guarantee that arbitrary confidential text is detected. Deliberately detached subprocesses can escape the owned process group; verification remains restricted to explicitly approved trusted projects.

Out of scope for this release: autonomous multi-file writes, shell generation, package installation as an agent tool, Git publication, multi-agent orchestration in the shipped app, image attachments, and App Intents that act on an uncaptured selection. Reconsider these only with a concrete user flow and independent evaluation.
