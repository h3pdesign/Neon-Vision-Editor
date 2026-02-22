# Notarized GitHub Runner Workflow (macOS)

This guide documents the full release flow used to build, sign, notarize, staple, and publish `Neon Vision Editor.app` from GitHub Actions.

## 1) Prerequisites

- Apple Developer account with access to your app team.
- A valid **Developer ID Application** certificate in Keychain.
- GitHub repo admin access for Actions secrets.
- `gh` CLI authenticated (`gh auth status`).

## 2) Keep Team IDs Consistent

Use one team ID everywhere:

- Xcode project signing team (`DEVELOPMENT_TEAM`)
- `APPLE_TEAM_ID` GitHub secret
- Developer ID Application certificate team

Current verified team in this project:

- `CS727NF72U`

## 3) Export the Correct Certificate as `.p12`

From **Keychain Access**:

1. Open **My Certificates**.
2. Select: `Developer ID Application: Hilthart Pedersen (CS727NF72U)`.
3. Right-click -> **Export** -> save as `DeveloperIDApplication-final.p12`.
4. Set an export password (this becomes `MACOS_CERT_PASSWORD`).

## 4) Validate the `.p12` Locally (Important)

```bash
KEYCHAIN=/tmp/nve-ci-test.keychain-db
security create-keychain -p 'tmpKeychainPass123!' "$KEYCHAIN"
security unlock-keychain -p 'tmpKeychainPass123!' "$KEYCHAIN"
security import ~/Downloads/DeveloperIDApplication-final.p12 -k "$KEYCHAIN" -P 'YOUR_REAL_P12_PASSWORD' -T /usr/bin/codesign
security find-identity -p codesigning -v "$KEYCHAIN"
security delete-keychain "$KEYCHAIN"
```

Expected: at least `1 valid identities found`.

## 5) Configure GitHub Repository Secrets

Repo -> **Settings** -> **Secrets and variables** -> **Actions** -> **Repository secrets**

Set these exact names:

- `MACOS_CERT_P12` (base64 single-line of `.p12`)
- `MACOS_CERT_PASSWORD` (the `.p12` export password)
- `KEYCHAIN_PASSWORD` (random password for runner temp keychain)
- `APPLE_ID` (Apple ID email used for notarization)
- `APPLE_TEAM_ID` (`CS727NF72U`)
- `APPLE_APP_SPECIFIC_PASSWORD` (Apple app-specific password)

Set `MACOS_CERT_P12` from terminal:

```bash
base64 -i ~/Downloads/DeveloperIDApplication-final.p12 | tr -d '\n' | gh secret set MACOS_CERT_P12
printf %s 'YOUR_REAL_P12_PASSWORD' | gh secret set MACOS_CERT_PASSWORD
printf %s 'CS727NF72U' | gh secret set APPLE_TEAM_ID
```

## 6) Workflow Used

- File: `.github/workflows/release-notarized.yml`
- Run manually with:

```bash
gh workflow run release-notarized.yml -f tag=v0.4.5
```

The workflow performs:

1. Import cert into temporary keychain
2. Archive macOS app (Developer ID signing)
3. Export app (`method=developer-id`)
4. Submit to notarization (`notarytool`)
5. Staple ticket
6. Zip app and upload to GitHub release asset (`--clobber`)

## 6b) Self-Hosted Runner Setup (Required when hosted runner lacks Xcode 17+)

Use this when GitHub-hosted runners only provide Xcode 16.x and release icon requirements need Xcode 17+.

Where to run:

- Run on the physical Mac that will be your runner, in Terminal.
- Use a dedicated directory (recommended): `~/actions-runner`.
- Do not run the runner from the app repository folder.

Get the correct token:

- Open: `https://github.com/h3pdesign/Neon-Vision-Editor/settings/actions/runners/new`
- Use the short-lived **runner registration token** shown on that page.
- Do not use a Personal Access Token for `./config.sh --token`.

Install and configure:

```bash
mkdir -p ~/actions-runner
cd ~/actions-runner
curl -o actions-runner-osx-arm64.tar.gz -L <github-runner-download-url-from-page>
tar xzf actions-runner-osx-arm64.tar.gz
./config.sh --url https://github.com/h3pdesign/Neon-Vision-Editor --token <runner-token-from-page> --labels self-hosted,macOS
```

Start as a service:

```bash
sudo ./svc.sh install
sudo ./svc.sh start
```

Verify prerequisites on runner:

```bash
xcodebuild -version
xcode-select -p
```

Expected:

- Xcode major version `17` or higher.
- Runner appears online in repo settings with labels: `self-hosted`, `macOS`.

Trigger self-hosted notarized release:

```bash
gh workflow run release-notarized-selfhosted.yml -f tag=v0.4.12 -f use_self_hosted=true
gh run list --workflow release-notarized-selfhosted.yml --limit 5
gh run watch <RUN_ID> --exit-status
```

## 7) Monitor and Inspect

```bash
gh run list --workflow release-notarized.yml --limit 5
gh run watch <RUN_ID> --exit-status
gh run view <RUN_ID> --log-failed
```

## 8) Verify Resulting Release Asset

```bash
gh release download v0.4.5 -p Neon.Vision.Editor.app.zip -D /tmp/nve_verify --clobber
ditto -xk /tmp/nve_verify/Neon.Vision.Editor.app.zip /tmp/nve_verify
APP="/tmp/nve_verify/Neon Vision Editor.app"

codesign -dv --verbose=4 "$APP"
spctl -a -vv "$APP"
xcrun stapler validate "$APP"
```

Expected:

- `Authority=Developer ID Application: ... (CS727NF72U)`
- `Notarization Ticket=stapled`
- `source=Notarized Developer ID`

## 9) Verify Icon Is Present (Not Blank)

Check release bundle contents:

```bash
find "/tmp/nve_verify/Neon Vision Editor.app/Contents/Resources" -maxdepth 3 -type f | rg -i 'AppIcon|foreground\.png|assets\.car'
```

Expected files include:

- `AppIcon.icon/icon.json`
- `AppIcon.icon/Assets/foreground.png`
- `Assets.car`

## 10) Common Failures and Fixes

- `SecKeychainItemImport: Unknown format in import`
  - `MACOS_CERT_P12` is not a valid `.p12` identity export.
  - Re-export from Keychain **My Certificates** entry.

- `MAC verification failed during PKCS12 import (wrong password?)`
  - `MACOS_CERT_PASSWORD` does not match the `.p12`.
  - Re-export `.p12`, verify locally, then re-upload secret values.

- `No signing certificate "Mac Development" found`
  - CI archive attempted wrong signing identity.
  - Use Developer ID signing settings in workflow archive step.

## 11) Security Notes

- Never commit `.p12` files.
- Rotate exposed passwords immediately.
- Delete temporary `.p12` from disk after validation/upload.
