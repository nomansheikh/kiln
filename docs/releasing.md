# Releasing Kiln

A release is a signed, notarized disk image attached to a GitHub Release. Pushing a
version tag builds it. The workflow is `.github/workflows/release.yml`.

The workflow has not been run yet. The steps it automates were checked locally as far
as they can be without a Developer ID: a Release build with the hardened runtime
succeeds, the engine helper generates images when signed with the hardened runtime,
and `scripts/package-dmg.sh` produces a disk image.

## One-time setup

You need an Apple Developer Program membership.

1. Create a **Developer ID Application** certificate in Xcode (Settings, Accounts,
   Manage Certificates) or on developer.apple.com.
2. Export it from Keychain Access as a `.p12` file with a password.
3. Create an **app-specific password** for your Apple ID at appleid.apple.com.
4. Add these repository secrets (Settings, Secrets and variables, Actions):

| Secret | Value |
| --- | --- |
| `DEVELOPER_ID_P12_BASE64` | The `.p12` file, base64 encoded: `base64 -i certificate.p12 \| pbcopy` |
| `DEVELOPER_ID_P12_PASSWORD` | The password chosen when exporting the `.p12` |
| `APPLE_TEAM_ID` | Your 10-character team identifier |
| `APPLE_ID` | The Apple ID email used for notarization |
| `APPLE_APP_PASSWORD` | The app-specific password |

5. Set the app's bundle identifier in `project.yml` (`PRODUCT_BUNDLE_IDENTIFIER`) to one
   you own. It is `app.kiln.Kiln` until then.

## Cutting a release

```sh
git tag v0.1.0
git push origin v0.1.0
```

The workflow then:

1. Runs the KilnCore tests.
2. Builds the engine helper and the app in Release configuration for Apple Silicon.
3. Signs the helper and the app with Developer ID, the hardened runtime and a secure
   timestamp. The version comes from the tag; the build number is the workflow run number.
4. Packages `Kiln-<version>.dmg`, signs it, submits it to Apple's notary service and
   staples the ticket.
5. Creates a **draft** GitHub Release with the disk image and its SHA-256 checksum.

Review the draft, edit the notes, and publish it.

## Building a release by hand

```sh
./scripts/build-engine.sh
xcodegen generate
xcodebuild -project Kiln.xcodeproj -scheme Kiln -configuration Release \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath build/release build
./scripts/package-dmg.sh build/release/Build/Products/Release/Kiln.app Kiln.dmg
```

Without a Developer ID the result is ad hoc signed. It runs on the Mac that built it;
on another Mac, Gatekeeper blocks it until the user allows it in System Settings.

## Not done yet

- Automatic updates. Sparkle is the intended mechanism and needs its own signing key
  and an appcast published by the release workflow.
- An Intel build. Kiln is Apple Silicon only.
