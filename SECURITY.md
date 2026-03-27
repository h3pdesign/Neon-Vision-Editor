# Security Policy

Thank you for helping keep Neon Vision Editor and its users secure.

Neon Vision Editor is a lightweight, native editor focused on speed, readability, privacy, and minimalism. This document explains which versions currently receive security attention and how to report a potential vulnerability responsibly.

## Supported Versions

As an actively developed pre-1.0 project, security fixes are generally applied to the latest public release and to the current `main` branch.

| Version | Supported |
| --- | --- |
| Latest release | ✅ Yes |
| Previous release (best effort, if fix is low-risk) | ⚠️ Limited |
| Older releases | ❌ No |
| Unreleased local forks / modified builds | ❌ No |

Notes:
- If a vulnerability affects an older release but the fix is straightforward, it may still be patched at maintainer discretion.
- Users should upgrade to the latest release as soon as practical.

## Reporting a Vulnerability

Please **do not** report security vulnerabilities through public GitHub issues, discussions, pull requests, Reddit, social posts, or App Store reviews.

### Preferred reporting method

Use GitHub’s **private vulnerability reporting** for this repository, if available:

- Open the repository on GitHub
- Go to **Security**
- Click **Report a vulnerability**

This is the preferred channel because it keeps details private until the issue is reviewed and, if needed, fixed.

### Fallback reporting method

If private reporting is not available for any reason, contact the maintainer privately by opening a GitHub issue **only** asking for a private contact method, without disclosing technical details publicly.

## What to include

Please include as much of the following as possible:

- A short description of the issue
- Affected version, branch, commit, or build
- Platform details:
  - macOS / iOS / iPadOS version
  - device model if relevant
- Reproduction steps
- Proof of concept, sample file, or screenshots if safe to share
- Impact assessment:
  - code execution
  - arbitrary file access
  - privilege escalation
  - token exposure
  - sandbox bypass
  - data leakage
  - denial of service / crash
- Any known mitigations or workarounds

Please avoid including secrets in reports unless absolutely necessary. If a secret must be shared to reproduce the issue, clearly label it as sensitive.

## Response Targets

Best effort targets:

- Initial acknowledgement: **within 7 days**
- Triage / severity assessment: **within 14 days**
- Status update after triage: **as available, usually within 30 days**

These are targets, not guarantees. As this is an individually maintained project, response times may vary.

## Disclosure Policy

Please follow responsible disclosure:

- Do not publish exploit details before the issue has been reviewed
- Do not publicly disclose proof-of-concept code before a fix or mitigation is available
- Do not access, modify, exfiltrate, or destroy data that does not belong to you
- Do not attempt social engineering, phishing, spam, or attacks against infrastructure outside what is strictly necessary to demonstrate the issue
- Do not perform denial-of-service, destructive testing, or mass automated exploitation

Good-faith researchers acting responsibly and within these limits are appreciated.

## Security Scope Notes

Security-relevant areas in this project may include, among others:

- File access and sandbox handling
- Security-scoped bookmarks
- Coordinated file writes
- API token storage
- AI/completion network requests
- Cross-window state isolation
- Large-file handling paths
- Import/export and document opening flows

Project principles relevant to security and privacy:

- No telemetry
- No sensitive logging
- Network calls only when explicitly user-triggered
- API tokens must remain in Keychain
- HTTPS for external requests
- No weakening of sandbox or file-security behavior

## Out of Scope

The following are generally not considered security vulnerabilities unless they create a concrete security impact:

- Basic crashes without security impact
- UI glitches
- Feature requests
- Performance-only issues
- Problems only affecting unsupported or heavily modified local builds
- Missing best-practice hardening with no demonstrable exploit path

Please report those through normal GitHub issues instead.

## Fix and Release Process

When a report is confirmed:

1. The issue will be validated privately
2. A fix will be prepared in the smallest reasonable change set
3. The fix will be released in the latest supported version
4. Public release notes may mention the security fix after a patch is available

## Thanks

Responsible reports are appreciated and help improve Neon Vision Editor for everyone.