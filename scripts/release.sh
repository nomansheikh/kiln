#!/bin/sh
# Builds, signs, notarizes and uploads a release from this Mac.
# Usage: scripts/release.sh <version>      for example: scripts/release.sh 0.1.0
#
# Needs, once (see docs/releasing.md):
#   - a "Developer ID Application" certificate in the login keychain
#   - notary credentials saved with: xcrun notarytool store-credentials kiln-notary
#   - gh, signed in to GitHub
# The result is a draft GitHub Release. Nothing is public until the draft is published.
set -eu

profile="${KILN_NOTARY_PROFILE:-kiln-notary}"
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

fail() {
    echo "error: $1" >&2
    exit 1
}

# --- Checks, before anything slow -------------------------------------------

version="${1:-}"
echo "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || fail "give a version such as 0.1.0"
tag="v$version"

[ -z "$(git status --porcelain)" ] || fail "the working tree has uncommitted changes"
git fetch --quiet origin main
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || fail "HEAD is not origin/main. Releases are cut from main as it is on GitHub."
commit="$(git rev-parse HEAD)"

identity="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: .*\)"$/\1/p' | head -n 1)"
[ -n "$identity" ] || fail "no Developer ID Application certificate in the keychain. See docs/releasing.md."
team="$(echo "$identity" | sed -n 's/.*(\([A-Z0-9]*\))$/\1/p')"
[ -n "$team" ] || fail "could not read the team id from \"$identity\""

xcrun notarytool history --keychain-profile "$profile" >/dev/null 2>&1 \
    || fail "notary credentials \"$profile\" are missing or rejected. Run: xcrun notarytool store-credentials $profile"
gh auth status >/dev/null 2>&1 || fail "gh is not signed in. Run: gh auth login"
if gh release view "$tag" >/dev/null 2>&1 || git ls-remote --exit-code --tags origin "$tag" >/dev/null 2>&1; then
    fail "$tag already exists on GitHub"
fi

echo "Releasing Kiln $version from $(git rev-parse --short HEAD), signed as $identity"

# --- Build --------------------------------------------------------------------

swift test
./scripts/build-engine.sh
xcodegen generate
rm -rf build/release
xcodebuild -project Kiln.xcodeproj -scheme Kiln -configuration Release \
    -destination 'platform=macOS,arch=arm64' -derivedDataPath build/release \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="Developer ID Application" \
    DEVELOPMENT_TEAM="$team" \
    OTHER_CODE_SIGN_FLAGS="--timestamp" \
    MARKETING_VERSION="$version" \
    CURRENT_PROJECT_VERSION="$(git rev-list --count HEAD)" \
    build
app="build/release/Build/Products/Release/Kiln.app"
codesign --verify --deep --strict --verbose=2 "$app"

# --- Package and notarize -----------------------------------------------------

dmg="build/release/Kiln-$version.dmg"
./scripts/package-dmg.sh "$app" "$dmg"
codesign --force --sign "$identity" --timestamp "$dmg"
xcrun notarytool submit "$dmg" --keychain-profile "$profile" --wait
xcrun stapler staple "$dmg"
spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"

# --- Draft release ------------------------------------------------------------

(cd build/release && shasum -a 256 "Kiln-$version.dmg" > "Kiln-$version.dmg.sha256")
# The tag is created on GitHub, at this commit, when the draft is published.
gh release create "$tag" "$dmg" "$dmg.sha256" --target "$commit" \
    --title "Kiln $version" --generate-notes --draft

echo "Draft release created. Review and publish it: gh release view $tag --web"
