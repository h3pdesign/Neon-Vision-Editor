# Neon Vision Editor Documentation

Start with the root [`README.md`](../README.md) for installation, features, and shortcuts, and with [`CHANGELOG.md`](../CHANGELOG.md) for release history. This folder holds the deeper references.

## Architecture and decisions

| Document | What it covers |
|---|---|
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | Current cross-platform architecture, ownership boundaries, distribution boundaries, performance rules, and verification. Its "Current Release Alignment" section is regenerated during release preparation. |
| [`ADR-0001-Native-macOS-Document-Windows.md`](ADR-0001-Native-macOS-Document-Windows.md) | Proposed staged migration of Mac document windows toward a single AppKit creation path (not started). |
| [`AI_AGENT_CHAT_SPECIFICATION.md`](AI_AGENT_CHAT_SPECIFICATION.md) | Product contract and release requirements for AI chat and macOS 27 Agent Mode. |

## Features

| Document | What it covers |
|---|---|
| [`CommandLineHelper.md`](CommandLineHelper.md) | The optional `nve` helper in the direct GitHub macOS build. Linked from the website. |
| [`Side-by-Side-Editor.md`](Side-by-Side-Editor.md) | Showing two editable documents next to each other. |
| [`Markdown-Project-Preview-Feature.md`](Markdown-Project-Preview-Feature.md) | Project-level Markdown and PDF preview cards. |
| [`JSON-Preview.md`](JSON-Preview.md) | Structured JSON tree preview, limits, and its original verification record. |
| [`YAML-Preview.md`](YAML-Preview.md) | Syntax-colored, paged YAML preview. |

## Release and operations

| Document | What it covers |
|---|---|
| [`../release/RELEASE-WORKFLOW.md`](../release/RELEASE-WORKFLOW.md) | The release process: reviewed Unreleased notes, isolated preparation, dry runs, and publication checks. |
| [`XCODE_CLOUD_RELEASE.md`](XCODE_CLOUD_RELEASE.md) | App Store archives with public Xcode, App Store Connect API credentials, API upload, and Xcode Cloud. |
| [`notarized-github-runner-workflow.md`](notarized-github-runner-workflow.md) | Signing, notarizing, and publishing the direct macOS build from GitHub Actions or a self-hosted runner. |
| [`AppStoreReviewNotes.md`](AppStoreReviewNotes.md) | App Review notes for the support tip, AI disclosure, and sandbox. Checked by `scripts/ci/review_metadata_audit.py`. |
| [`branch-cleanup.md`](branch-cleanup.md) | Local and remote branch cleanup rules. |

## Verification and performance

| Document | What it covers |
|---|---|
| [`End-to-End-UI-Test-Plan.md`](End-to-End-UI-Test-Plan.md) | Planned XCUITest coverage (no UI-test target exists yet). |
| [`FILE_PROVIDER_VERIFICATION.md`](FILE_PROVIDER_VERIFICATION.md) | Device acceptance test for File Provider locations such as Nextcloud. |
| [`Editor-Opening-Responsiveness.md`](Editor-Opening-Responsiveness.md) | Opening-responsiveness test contract and the investigation behind the v1.8.6 single-line fix. |
| [`Performance-Profiles.md`](Performance-Profiles.md) | Dated profiling log, recording protocol, and guardrails. |
| [`performance-baselines.json`](performance-baselines.json) | Versioned fixture sizes and budgets, read by `scripts/ci/check_performance_budget.py` and the performance tests. |
| [`native-controller-1116-profile.json`](native-controller-1116-profile.json) | Raw aggregates for the build 1116 profile in `Performance-Profiles.md`. |

## Media

- [`images/README.md`](images/README.md) indexes the README screenshots, generated charts, and historical images.
- `media/` holds website image sources and local App Store screenshot copies (`media/app-store`).
