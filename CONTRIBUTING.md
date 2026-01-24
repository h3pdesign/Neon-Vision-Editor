# Contributing to Neon Vision Editor

Thanks for taking the time to contribute.

## Scope & goals

Neon Vision Editor is intentionally a lightweight native macOS editor.
Please keep PRs focused and aligned with the project goals:
- fast file opening
- readable UI
- reliable syntax highlighting
- stability/performance

Non-goals (for now):
- plugin system
- full IDE features (LSP/refactors/project indexing)

## Reporting bugs

Please open a GitHub issue and include:
- macOS version
- Xcode version (if building from source)
- Neon Vision Editor version/tag
- steps to reproduce
- expected vs actual behavior
- screenshots or a short screen recording if applicable
- sample file (if the bug is file-content dependent)

## Proposing features

Open a feature request issue first, especially for anything large.
Describe:
- the user problem
- the proposed solution
- alternatives considered
- why it fits the scope

## Pull requests

- Keep PRs small and focused.
- Prefer one logical change per PR.
- Include a short summary and any relevant screenshots.
- If behavior changes, mention it in the PR description and update the changelog if appropriate.

## Development notes

- The project is built with Swift and AppKit.
- Ensure the app builds and runs locally before opening a PR.
- Avoid committing Xcode user state or DerivedData artifacts (see `.gitignore`).
