# Release workflow

When asked to make a new release, start from clean `develop` aligned with
`origin/develop`. Choose and review the next release tag before running any
commands below; set `TAG` to that approved version.

## Fast release path

Aim to start the hosted release promptly after the protected preparation PR
merges. Do read-only status checks together, prepare once, review the generated
diff, and run the release gate once for that exact source. Do not repeat the
offline rehearsal, platform matrix, or runtime tests unless the release source
changes or the failed check needs a targeted rerun. Reuse an existing prepared
release with the documented resume path; do not create another preparation PR
or dispatch a second hosted run while an equivalent run is active. The matrix
reuses its macOS build products for the runtime gate and retries only its
identified transient build-system errors.

If a required check, protected merge, Apple service, or hosted runner prevents
progress, report the specific blocker and elapsed time immediately. The goal is
under two hours end-to-end, with a roughly ten-minute hosted workflow, but
external queues, notarization, and protected-branch approval cannot be
guaranteed by automation.

### Publication latency and recovery

The v1.9.3 hosted run archived and notarized in about nine minutes, then spent
23 minutes publishing the appcast PR. Feed-only and publication-manifest-only
PRs now retain required check contexts but avoid the Xcode matrix; the Linux
preflight validates the feed mirrors and manifest. Swift, project, script,
workflow and renamed files still require full Swift validation.

Appcast, publication-documentation and App Store metadata PRs use the existing
`METRIC_TOKEN` automation identity for PR creation as well as branch pushes.
GitHub holds `GITHUB_TOKEN`-authored PR checks for workflow approval; using the
existing PAT avoids that hold without changing protection or signature rules.
Keep this credential limited to the repository automation it already serves.

Documentation and appcast merges wait for all required checks on the exact
signed PR head (including registration), reject failures or changed heads, and
leave the PR open with an actionable error on timeout. Publication docs are
dispatched before the other documentation writers and before Pages polling.
Same-tag primary/fallback notarized runs share one non-cancelling lock. Do not
start a duplicate run: GitHub's lock serializes rather than deduplicates it.

After uploaded assets pass verification and become public, an appcast, Pages,
or documentation failure must not delete those assets. Repair the failed
publication step/PR and rerun the failed job only after inspecting its source
and completed steps; do not overwrite a healthy release to repair documentation.
Reruns re-verify and reuse the published ZIP/DMG without replacing them, but
still reconcile the appcast and documentation. Appcast signing uses the exact
downloaded, checksum-verified ZIP and its version/build, not a fresh same-tag
archive. ZIP and DMG metadata must agree. A Pages failure or a malformed/stale
live feed fails the run visibly while preserving published assets. Feed
readiness requires version, build, URL and a well-formed Ed25519 signature on
the same XML item; it is not an independent cryptographic verification.
Manually dispatched Pages runs identify their requested source in `run-name`,
so a later main commit does not make the pinned deployment undiscoverable.
The next hosted release must verify these changes end to end; offline checks
do not establish token validity, runner timing or protected-merge behavior.

OS 27 features are part of `develop`; App Store builds must use Xcode 27 or later so their
SDK-qualified sources are included, while older SDK builds retain compatibility.

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
TAG=vX.Y.Z # replace with the approved release tag
bash scripts/release_all.sh "$TAG" --dry-run
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
The values are resolved live for every release; documentation must not carry a
stale example as an implied build reservation.
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
   tag and the release notes. Move every issue that remains open in the release
   milestone to the next planned version milestone without closing the issue,
   then close the emptied release milestone before running the release gate.
2. Run `bash scripts/release_prep.sh "$TAG"`. This creates a sibling worktree on
   `release/<version>`, writes `release/prepared-release.json`, generates documentation
   and makes a signed commit. The original checkout stays unchanged.
3. Review the worktree. Repeating preparation reuses its source, date and build.
   If interrupted, inspect the preserved worktree before using `--resume`.
   That explicit option regenerates release-owned files only; unrelated edits
   block it. Changed develop or a conflicting date requires manual reconciliation.
4. For the complete authorized release, run `bash scripts/release_all.sh "$TAG"
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
8. Verify the protected main-to-develop synchronization PR has merged.

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
