# App Store Release Runbook

Use this when the development Mac is on beta macOS or beta Xcode, but the App Store release must be built with the latest public GM Xcode.

## Release Rule

Regular App Store releases must be archived with the latest public GM Xcode. Do not upload archives built with Xcode beta, even when they build and run locally.

For this repo:

- App Store scheme: `Neon Vision Editor AppStore`
- Release branch: `main`, unless a release branch is explicitly created
- Release preflight: `scripts/ci/xcode_cloud_release_preflight.sh`
- Full local platform gate: `scripts/ci/build_platform_matrix.sh`
- Version source: `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `Neon Vision Editor.xcodeproj/project.pbxproj`

## Before Any App Store Release

From the repo root:

```bash
git checkout main
git pull --ff-only origin main
git status --short
scripts/ci/xcode_cloud_release_preflight.sh
scripts/ci/build_platform_matrix.sh
```

Expected result:

- Working tree is clean.
- Xcode Cloud release preflight passes.
- macOS, iOS Simulator, and iPad Simulator builds pass.

If the Mac only has beta Xcode installed, use Xcode Cloud for the actual archive. You may run the metadata-only local check with:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer scripts/ci/xcode_cloud_release_preflight.sh --allow-beta-toolchain
```

This is only a metadata check. Do not upload a beta-Xcode archive to App Store Connect.

## Manual Xcode Archive

Use this path only on a Mac that has the latest public GM Xcode installed.

1. Open the project:

   ```bash
   open "Neon Vision Editor.xcodeproj"
   ```

2. In Xcode, select:

   - Scheme: `Neon Vision Editor AppStore`
   - Destination: `Any iOS Device (arm64)` for the iOS/iPadOS archive
   - Destination: `Any Mac` or `My Mac` for the macOS archive, if submitting macOS separately

3. Confirm build settings:

   - `MARKETING_VERSION` is the App Store version, for example `0.8.0`
   - `CURRENT_PROJECT_VERSION` is the build number, and all targets use the same value
   - Signing uses the App Store Connect team
   - No beta Xcode is selected in `Xcode > Settings > Locations`

4. Create the archive:

   - `Product > Archive`

5. In Organizer:

   - Select the archive
   - Click `Distribute App`
   - Choose `App Store Connect`
   - Choose `Upload`
   - Keep automatic signing enabled unless there is a specific signing error
   - Upload

6. In App Store Connect:

   - Wait for processing
   - Open the app version
   - Select the new build
   - Add release notes, promotional text, and review notes
   - Submit for review

If App Store Connect says the build was made with beta Xcode, discard that archive and rebuild with public GM Xcode or Xcode Cloud.

## App Store Connect credentials

### What you need to provide

The Cloud counter check needs an App Store Connect API key (`.p8`). A signing
certificate export (`.p12`) cannot authenticate this API; do not convert, replace,
upload, or share your signing certificates for this setup.

1. Open App Store Connect > Users and Access > Integrations > App Store Connect API.
   If API access is unavailable, the Account Holder must request it first.
2. Reuse a suitable existing API key if available. Otherwise an Account Holder or
   Admin can create a Team Key named `Neon release counter`. Select the least
   privileged role that permits the needed Cloud reads; do not grant Admin merely
   to avoid checking permissions. Team keys apply across the team's apps.
3. Download the `.p8` once and keep it in your existing secure credential storage,
   outside this repository and its worktrees. Record its Key ID and Issuer ID.
   Individual keys do not use an Issuer ID; the built-in signer supports team
   keys only. Individual keys need an externally generated JWT instead.
4. Provide only the local key-file path, Key ID, key type, and (for a team key)
   Issuer ID to the person configuring the tooling. Do not paste the private key,
   JWT, password, or `.p12` contents into chat, Git, or logs.

See Apple's [API access and key setup](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api/)
and [private-key storage guidance](https://developer.apple.com/documentation/appstoreconnectapi/creating-api-keys-for-app-store-connect-api).

### Configuration handoff and read-only test

`scripts/cloud_build_number.py` can generate a fresh two-minute JWT in memory for
each counter request, using a team `.p8` key. Each token is scoped to that exact
GET request. No JWT or private-key contents are saved in Git or printed. The
signer requires Python's `cryptography` library (tested with 50.0.1); external-JWT
and offline dry-run paths do not require it. To use an isolated Python environment:

```bash
nve_auth_env="$(mktemp -d "${TMPDIR:-/tmp}/nve-cloud-auth.XXXXXX")"
python3 -m venv "$nve_auth_env"
"$nve_auth_env/bin/python" -m pip install 'cryptography==50.0.1'
export PATH="$nve_auth_env/bin:$PATH"
```

Use that Python environment for the preflight and release scripts. The API key
must remain in secure storage outside any Git checkout, with owner-only access
(`chmod 600` on the specific key file). A downloaded iCloud file still follows
your iCloud synchronization policy; file permissions do not remove cloud copies.
The script rejects keys stored inside Git and does not import or relocate keys.
See Apple's [JWT requirements](https://developer.apple.com/documentation/appstoreconnectapi/generating-tokens-for-api-requests).

With authentication configured, resolve Neon's Cloud product using Apple's
[`GET /v1/ciProducts`](https://developer.apple.com/documentation/appstoreconnectapi/get-v1-ciproducts)
and confirm its associated app. This product ID is distinct from the App Store
app ID and the Cloud workflow ID.

Configure these non-secret references once from the repository root. Do not
commit a shell script containing your machine's settings:

```bash
git config --local nve.asc.productId "REPLACE_WITH_CONFIRMED_CLOUD_PRODUCT_ID"
git config --local nve.asc.keyId "REPLACE_WITH_KEY_ID"
git config --local nve.asc.issuerId "REPLACE_WITH_ISSUER_ID"
git config --local nve.asc.privateKeyPath "/absolute/secure/path/AuthKey_KEY_ID.p8"
python3 scripts/cloud_build_number.py
```

These references are local to the Git repository (normally shared by linked
worktrees); other clones need their own setup. Environment variables
`ASC_CLOUD_PRODUCT_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, and `ASC_PRIVATE_KEY_PATH`
override the respective local settings.

An existing `ASC_API_TOKEN` takes precedence over a token from the Keychain
generic-password service named by `ASC_TOKEN_KEYCHAIN_SERVICE`; either token
source takes precedence over `.p8` signing. Externally supplied tokens are not
refreshed by this script, so remove stale token overrides when using `.p8` signing.
Most Apple API requests reject token lifetimes above 20 minutes.
The successful output
contains only `product_id` and `max_number`. Missing credentials, denied/expired
authentication, or active/queued builds must be resolved before release prep.
This check starts no builds, allocates no number, and publishes nothing.

Finally, verify the configured next Cloud build number in App Store Connect and
coordinate automatic triggers before release prep. A history read cannot reserve
a number or detect a manually configured next counter. Do not assume 1029 remains
available if Cloud has since allocated another build.

## Xcode Cloud Archive

For shared local/GitHub/Cloud build numbering, use the authenticated counter
preflight in [the release workflow](../release/RELEASE-WORKFLOW.md#cloud-build-number-preflight).
It stops on active Cloud runs or stale allocations; changing the project build
number alone does not change Xcode Cloud's configured next build number.

Use this path when the local Mac is on beta macOS or beta Xcode.

1. Push the release-ready branch:

   ```bash
   git checkout main
   git pull --ff-only origin main
   git status --short
   git push origin main
   ```

2. In App Store Connect:

   - Open `Neon Vision Editor`
   - Go to `Xcode Cloud`
   - Create or edit a workflow

3. Workflow settings:

   - Repository: `h3pdesign/Neon-Vision-Editor`
   - Branch: `main`
   - Scheme: `Neon Vision Editor AppStore`
   - Xcode: latest public GM release, not beta
   - Clean build: enabled
   - Archive action: enabled
   - Distribution: TestFlight or App Store Connect

4. If Xcode Cloud offers separate platform actions, configure:

   - iOS/iPadOS archive with `Neon Vision Editor AppStore`
   - macOS archive with `Neon Vision Editor AppStore`

5. Start the workflow manually.

6. After the workflow finishes:

   - Confirm archive upload succeeded
   - Wait for build processing in App Store Connect
   - Select the processed build on the app version
   - Submit for review

If Xcode Cloud fails with future project metadata, open the project once with the latest public GM Xcode, save it, commit that project-file change, push, and rerun the workflow.

## How To Use Codex For This Release

Ask Codex to do repo-safe preparation work:

```text
prepare v0.8.0 for App Store release, run preflight, commit signed, and push main
```

Codex can do:

- Update release docs and changelog.
- Align `MARKETING_VERSION`.
- Verify `CURRENT_PROJECT_VERSION` is consistent.
- Run `scripts/ci/xcode_cloud_release_preflight.sh`.
- Run `scripts/ci/build_platform_matrix.sh`.
- Commit signed changes.
- Push `main`.
- Draft App Store release notes, promotional text, and review notes.

Codex cannot directly click through App Store Connect review submission unless a configured connector/browser session is explicitly available and authenticated. Keep final App Store submission manual unless you explicitly ask Codex to operate an authenticated browser session.

Useful Codex prompts:

```text
check whether main is ready for Xcode Cloud App Store release
```

```text
run the Xcode Cloud release preflight and platform matrix
```

```text
draft App Store Connect change message, promotional text, and review notes for v0.8.0
```

```text
commit and push all release documentation changes with signed commits
```

## Troubleshooting

Beta Xcode rejection:

- Cause: archive was built with Xcode beta.
- Fix: rebuild with latest public GM Xcode or Xcode Cloud configured to latest public GM Xcode.

Closed pre-release train:

- Cause: `CFBundleShortVersionString` matches an already closed App Store version.
- Fix: bump `MARKETING_VERSION` to a higher version, then rebuild.

Build number mismatch:

- Cause: `CURRENT_PROJECT_VERSION` differs across targets.
- Fix: normalize all target build numbers, then rerun preflight.

App Clip minimum OS error:

- Cause: App Clip deployment target is below App Store Connect's current requirement.
- Fix: update the App Clip deployment target and rerun preflight.

Icon alpha rejection:

- Cause: App Store large app icon contains transparency.
- Fix: regenerate icon assets without alpha, then rerun release preflight.

Future project metadata:

- Cause: project was saved by newer beta Xcode than the release builder supports.
- Fix: save the project with latest public GM Xcode, commit the project-file metadata, and rerun Xcode Cloud.
