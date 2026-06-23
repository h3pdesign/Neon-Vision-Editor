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

   - `MARKETING_VERSION` is the App Store version, for example `0.7.9`
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

## Xcode Cloud Archive

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
prepare v0.7.9 for App Store release, run preflight, commit signed, and push main
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
draft App Store Connect change message, promotional text, and review notes for v0.7.9
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
