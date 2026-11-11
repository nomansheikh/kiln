# Releasing Kiln

A release is a signed, notarized disk image attached to a GitHub Release. The maintainer
cuts it on their own Mac with one command, `scripts/release.sh`. The signing key stays in
that Mac's keychain and is never uploaded anywhere.

No release has been cut yet. The script's steps were checked as far as they can be
without a Developer ID: a Release build with the hardened runtime succeeds, the engine
helper generates images when signed with the hardened runtime, and
`scripts/package-dmg.sh` produces a disk image. Signing, notarization and the upload
have not been run.

## One-time setup

You need an Apple Developer Program membership.

1. Create a **Developer ID Application** certificate in Xcode (Settings, Accounts,
   Manage Certificates, "+"). It is stored in the login keychain.
2. Create an **app-specific password** for your Apple ID at appleid.apple.com.
3. Save the notary credentials in the keychain under the name `kiln-notary`:

   ```sh
   xcrun notarytool store-credentials kiln-notary --apple-id you@example.com --team-id YOURTEAMID
   ```

   It asks for the app-specific password. To use another name, set
   `KILN_NOTARY_PROFILE` when running the release script.
4. Sign in to GitHub with `gh auth login`.

The app's bundle identifier is `codes.noman.kiln` (`PRODUCT_BUNDLE_IDENTIFIER` in
`project.yml`). A fork that publishes its own builds must change it to one it owns.

## Cutting a release

Merge everything for the release into `main`, check out `main` at the same commit as
GitHub has it, and run:

```sh
./scripts/release.sh 0.1.0
```

The script stops before building anything if the working tree is not clean, `HEAD` is
not `origin/main`, the certificate or the notary credentials are missing, or the
version already exists on GitHub. Then it:

1. Runs the KilnCore tests.
2. Builds the engine helper and the app in Release configuration for Apple Silicon.
3. Signs the helper and the app with Developer ID, the hardened runtime and a secure
   timestamp. The version is the argument; the build number is the number of commits.
4. Packages `build/release/Kiln-<version>.dmg`, signs it, submits it to Apple's notary
   service, waits for the result and staples the ticket.
5. Creates a **draft** GitHub Release with the disk image and its SHA-256 checksum.

Review the draft, edit the notes, and publish it. The `v<version>` tag is created on
GitHub when the draft is published, at the commit the release was built from. Until then
nothing is public and the draft can be deleted.

## Building without a Developer ID

```sh
./scripts/build-engine.sh
xcodegen generate
xcodebuild -project Kiln.xcodeproj -scheme Kiln -configuration Release \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath build/release build
./scripts/package-dmg.sh build/release/Build/Products/Release/Kiln.app Kiln.dmg
```

The result is ad hoc signed. It runs on the Mac that built it; on another Mac,
Gatekeeper blocks it until the user allows it in System Settings.

## Releasing from GitHub Actions instead

`.github/workflows/release.yml` does the same steps on a GitHub runner. It is not used
and has never been run. It exists for the day the project has more than one maintainer
who cuts releases. It is started by hand (Actions, Release, Run workflow) from a version
tag, and needs the certificate and the Apple credentials as repository secrets:

| Secret | Value |
| --- | --- |
| `DEVELOPER_ID_P12_BASE64` | The certificate exported from Keychain Access as `.p12`, base64 encoded |
| `DEVELOPER_ID_P12_PASSWORD` | The password chosen when exporting the `.p12` |
| `APPLE_TEAM_ID` | Your 10-character team identifier |
| `APPLE_ID` | The Apple ID email used for notarization |
| `APPLE_APP_PASSWORD` | The app-specific password |

Storing the certificate in repository secrets lets any workflow run from a branch of
this repository use it. Before enabling this, put the secrets in a GitHub environment
that requires approval.

## Not done yet

- Automatic updates. Sparkle is the intended mechanism and needs its own signing key
  and an appcast published with each release.
- An Intel build. Kiln is Apple Silicon only.
