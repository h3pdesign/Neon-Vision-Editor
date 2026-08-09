# Homebrew Cask workflow

Homebrew Cask updates run independently from the macOS release workflow through
`.github/workflows/homebrew-cask.yml`. Dispatch it with a published release tag,
or let the `release: published` trigger start it automatically.

The workflow requires the `HOMEBREW_CASK_PR_TOKEN` repository secret. The token
must be able to push the `h3pdesign/homebrew-cask` fork and create or edit pull
requests against `Homebrew/homebrew-cask`. The release workflow's GitHub App
token is intentionally not reused: it can push the branch but cannot create the
upstream pull request.

Before creating or updating a PR, the workflow:

- verifies the published stable release asset and SHA-256 checksum;
- updates the fork branch from `Homebrew/homebrew-cask/main`;
- runs `brew audit --cask --online`, `brew style --fix`, and `brew audit --cask --new`;
- installs and uninstalls the local cask with `HOMEBREW_NO_INSTALL_FROM_API=1`;
- fills the current Homebrew PR template, including the AI-assistance disclosure;
- reuses an existing PR for the same release branch instead of opening duplicates.

Use `prepare_only=true` to validate and publish the fork branch without opening
or editing a PR. This is useful for maintainer review or when Homebrew's bot has
closed a PR pending template completion.

If a PR is closed by BrewTestBot for an incomplete template, edit that existing
PR with the generated body; do not open a second PR for the same branch.
