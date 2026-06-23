# Xcode Cloud Release

Use Xcode Cloud for App Store releases when the local machine is on a beta macOS or beta Xcode.

## Required Cloud Setup

- Product: `Neon Vision Editor`
- Scheme: `Neon Vision Editor AppStore`
- Xcode version: latest public GM release only
- Signing: automatic signing with the App Store Connect team
- Start condition: manual on `main` or the release branch
- Distribution: archive to TestFlight/App Store Connect first, then submit from App Store Connect

Do not use an Xcode beta workflow for a regular App Store release. App Store Connect rejects archives built with beta Xcode, even when the project builds locally.

## Before Starting the Cloud Build

Run this locally on a public Xcode runner, or in CI before tagging:

```bash
scripts/ci/xcode_cloud_release_preflight.sh
```

On a beta-only development Mac, this command may be used only to check project metadata and shared schemes:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer scripts/ci/xcode_cloud_release_preflight.sh --allow-beta-toolchain
```

If the strict command fails because only beta Xcode is installed locally, start the archive from Xcode Cloud with the latest public GM Xcode selected. If it fails with future project metadata, open and save the project once with the latest public GM Xcode and commit that project-file change.
