# Releasing Kiln

A release is a signed, notarized disk image attached to a GitHub Release. The signing
key stays in the maintainer's keychain and is never uploaded anywhere.

Version 0.1.0 was made with Xcode, as described below. The release script has not been
run from start to finish.

Before either way, go through [release-checklist.md](release-checklist.md): what to
run, and what to click through by hand, since the app has no automated tests.

## With Xcode

This is the way the maintainer intends to release. Xcode signs with the Developer ID
certificate and notarizes through the Apple account it is signed in to, so no notary
credentials need to be stored.

1. Check out `main` at the commit GitHub has, with a clean working tree.
2. Set the version: `MARKETING_VERSION` in `project.yml` (for example `0.1.0`), and
   raise `CURRENT_PROJECT_VERSION`. The project file is generated, so a setting changed
   in Xcode's own interface is lost the next time it is regenerated; change
   `project.yml`. Commit that through a pull request first.
3. Build the helpers and the project:

   ```sh
   ./scripts/build-engine.sh
   xcodegen generate
   ```

4. Open `Kiln.xcodeproj` and set the signing for the release. The project signs ad hoc
   by default, so that anyone can build it, and an archive made that way stops at
   "No Team Found in Archive", whatever team is picked in the menu. In the Kiln target's
   Signing & Capabilities tab, for the Release configuration, turn off automatic
   signing, choose your team and the "Developer ID Application" certificate. This is
   not kept in the repository, and `xcodegen generate` resets it, so it is done again
   for each release.
5. Choose Product, Archive, then Distribute App, Direct Distribution. Xcode uploads the
   archive for notarization and gives back a notarized `Kiln.app` to export. For 0.1.0
   this took seconds.
6. Check the three helpers inside it. They are copied in and signed by a build script
   with the identity the build uses, so with the signing above they come out signed like
   the app. Each must show the Developer ID authority, the `runtime` flag and a timestamp:

   ```sh
   for helper in kiln-engine kiln-whisper kiln-audio; do
     codesign -dvv "Kiln.app/Contents/MacOS/$helper" 2>&1 | grep -E "Authority=Developer ID|flags=|Timestamp="
   done
   spctl --assess --type execute --verbose Kiln.app
   xcrun stapler validate Kiln.app
   ```

   If a helper is signed with anything else, notarization fails or the helper does not
   start on another Mac. Fix the signing in `project.yml` ("Bundle the helpers") before
   going on.
7. Package the app and work out its checksum:

   ```sh
   ./scripts/package-dmg.sh Kiln.app Kiln-0.1.0.dmg
   shasum -a 256 Kiln-0.1.0.dmg
   ```

   The disk image itself is not notarized this way; the app inside it is, and that is
   what Gatekeeper checks when the app is opened. Notarizing the image as well needs
   the notary credentials described below.
8. Try it as a user would, on an account that has never run Kiln: open the disk image,
   drag the app to Applications, open it, download one model and generate with it. This
   is the only step that shows Gatekeeper, the sandboxed helpers and a first launch
   working together.
9. Create a draft release and publish it once it has been read through:

   ```sh
   gh release create v0.1.0 Kiln-0.1.0.dmg --draft --title "Kiln 0.1.0" --notes "..."
   ```

   Publishing creates the `v0.1.0` tag. The app's notice of a new version reads the
   latest published release, so a draft or a prerelease is not announced to users.

## With the release script

`scripts/release.sh` does the same without Xcode's interface, and also signs and
notarizes the disk image. It is kept as the alternative and has not been run past its
first checks.

### One-time setup

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

### Running it

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

- Automatic updates. The app says when a newer version has been published and links
  to it; it does not download or install one. Sparkle would be the way to do that and
  needs its own signing key and an appcast published with each release.
- A Homebrew cask. It needs the disk image's address and SHA-256 from a published
  release.
- An Intel build. Kiln is Apple Silicon only.
