# Release workflow

When asked to make a new release, start from clean `develop` aligned with
`origin/develop`. The next planned version is **1.6.2**. Do not merge the
separate macOS 27 agent branch into this release.

## Release content

Maintain reviewed user-facing changes in `CHANGELOG.md` under `Unreleased`.
Use Why Upgrade, Highlights, Fixes, Breaking changes and Migration; keep tooling
under Maintenance. Derive the draft from merged changes since the previous
release, not commit subjects alone. Never claim unverified performance gains.
Add the six localized timeline summaries in `scripts/prepare_release_docs.py`.
Generation deliberately fails on missing translations instead of shipping
English placeholders. Review generated summaries before publication.

README, architecture alignment, website timelines and welcome-screen release
notes are generated from the changelog. Do not independently hand-edit their
managed release sections. App Store versions reflect the public listing, not
the GitHub release version or a pending review submission.

## Offline rehearsal

```bash
bash scripts/release_all.sh v1.6.2 --dry-run
python3 scripts/ci/test_release_workflow.py
```

Dry run copies the current checkout's tracked files and untracked review inputs
to a disposable directory. It uses cached local tags and includes uncommitted
edits, so it is a rehearsal, not a verified remote-develop snapshot. It promotes
notes, allocates a candidate build, validates documentation/metadata, checks
repeatability, then simulates post-publication documentation. It never contacts
GitHub, signs commits, pushes, tags or dispatches workflows. Temporary files are
removed on exit. GitHub milestone closure is explicitly skipped offline.

For Xcode validation, add `--full-gate` and run with developer-service access
(Codex: elevated execution). This still does not test hosted credentials,
notarization, App Store sandbox purchases or actual public downloads. Unlike
the default offline rehearsal, Xcode may access package servers to resolve dependencies.

## Prepare and release

### Cloud build-number preflight

Real preparation now requires authenticated, read-only App Store Connect access.
It reads every page of the selected product's Cloud build runs and chooses
`max(project build, published GitHub build, highest Cloud run number) + 1`.
With project build 1028 and Cloud's last allocated run 1028, the candidate is 1029.
It records the product ID and observed counter in the release manifest, never the
credential. Active/queued builds, unknown states, missing history, malformed
responses, authentication errors and incomplete pagination stop preparation.
An older RUNNING run is nonblocking only when a newer run is COMPLETE and its
action history proves successful completed archives, successful other completed
actions, and only standard-named TestFlight distribution actions still RUNNING
after archiving. Renamed/ambiguous actions and the latest unfinished run still
block. Every run number is counted, including distribution-only runs. This does
not cancel actions or change Apple's recorded status.
The counter is checked again before committing and immediately before pushing.
Retries preserve the allocated number and reject a changed Cloud counter.

Configure these outside the repository:

For first-time setup, see [App Store Connect credentials](../docs/XCODE_CLOUD_RELEASE.md#app-store-connect-credentials).

- `ASC_CLOUD_PRODUCT_ID`: the Cloud **product** ID, not the App Store app ID or workflow ID.
- For automatic two-minute, read-scoped JWTs, supply `ASC_KEY_ID`, `ASC_ISSUER_ID`,
  and `ASC_PRIVATE_KEY_PATH` for a team key in secure storage outside Git with
  owner-only file permissions. This mode requires Python `cryptography` (tested
  with 50.0.1). The setup guide also supports local Git configuration of these
  non-secret references; no key contents are stored in Git.
- `ASC_TOKEN_KEYCHAIN_SERVICE`: a macOS Keychain generic-password service containing
  a valid App Store Connect JWT with read access to that Cloud product. Provision
  it using Keychain Access or your existing secure credential tooling; do not paste
  a token into chat or commit it.
- Alternatively, inject `ASC_API_TOKEN` through your existing secure CI secret
  provider. It takes precedence over Keychain; both external-token sources take
  precedence over `.p8` signing. Refresh external tokens through that provider;
  only `.p8` signing automatically generates fresh JWTs before each request.

Check the connection without editing files or starting builds:

```bash
python3 scripts/cloud_build_number.py
```

This prints only the product ID and highest observed run number. Dry runs remain
offline and do not require these settings, but do **not** validate Cloud alignment.
The App Store Connect API exposes
[Cloud build runs](https://developer.apple.com/documentation/appstoreconnectapi/get-v1-ciproducts-_id_-buildruns).
A read is not an atomic reservation. New builds may start after the last check,
and a manually configured **next** Cloud counter is not represented by build
history. For exact numbering across distribution channels, prevent competing
Cloud triggers during release preparation and verify Cloud's configured next
number. This tooling neither changes that setting nor starts a Cloud run.
Manual non-Cloud App Store uploads also need separate coordination.

### Release steps

1. Fetch and review `develop`, the proposed version, the diff since the previous
   tag, the closed release milestone and the release notes.
2. Run `bash scripts/release_prep.sh v1.6.2`. This creates a sibling worktree on
   `release/1.6.2`, writes `release/prepared-release.json`, generates documentation
   and makes a signed commit. The original checkout stays unchanged.
3. Review the worktree. Repeating preparation reuses its source, date and build.
   If interrupted, inspect the preserved worktree before using `--resume`.
   That explicit option regenerates release-owned files only; unrelated edits
   block it. Changed develop or a conflicting date requires manual reconciliation.
4. For the complete authorized release, run `bash scripts/release_all.sh v1.6.2
   --github-hosted`. Preparation is followed by documentation and platform/release
   gates before pushing the protected main PR. Existing prepared work is reused.
5. After the PR merges, dispatch the hosted workflow with the exact merge SHA.
   That SHA must be contained in main; newer main commits do not replace it.
   The hosted workflow retains archive, signing, notarization and asset checks.
6. Verify the public ZIP, DMG, checksums and signed Sparkle appcast. A local gate
   pass alone is not a release. Do not use retag or asset replacement for an
   ordinary new release.
7. Post-release documentation waits for actual public assets and verifies their
   checksums before advancing download references. Documentation writers share
   a queued concurrency group. App Store sync reads actual availability without
   assuming a fixed propagation delay; rerun it when the Store release appears.
8. Verify the protected main-to-develop synchronization PR has merged. Bring
   develop into the macOS 27 branch separately, preserving its independent scope.

`--next` resolves local reachable tags after fetching for real preparation.
Prefer an explicit approved version for reproducible releases. A missing or
existing release branch is never force-overwritten. `--push` only opens/updates
the protected release PR and requests auto-merge; it does not publish artifacts.

## Prepared versus published

The release manifest records source SHA, candidate version/build/date, public
version/build and status. Before publication, the app embeds candidate welcome
notes while README and website download links remain on the previous public
release. A clearly marked README candidate notice points to the changelog.

Only the verified post-release workflow uses `prepare_release_docs.py TAG
--published`. The ordinary generator and `--check` respect the manifest state.
No generator infers publication from the presence of a Git tag alone.

## Verification boundaries

Offline regression tests cover promotion, generated-file repeatability, public
versus candidate links, consistent build numbers, stable-release readiness,
checksum integrity, and rejection of destructive dry-run combinations.
Hosted workflow execution, protected PR merges, signing and notarization still
need live release verification. Pending documentation PRs can require review;
queue serialization does not bypass branch protection or guarantee their merge.
