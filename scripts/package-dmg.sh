#!/bin/sh
# Packages a built Kiln.app into a compressed disk image with an Applications shortcut.
# Usage: scripts/package-dmg.sh <path/to/Kiln.app> <output.dmg>
set -eu

app="$1"
dmg="$2"

if [ ! -d "$app" ]; then
    echo "error: $app is not an app bundle" >&2
    exit 1
fi

staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT

cp -R "$app" "$staging/"
ln -s /Applications "$staging/Applications"

rm -f "$dmg"
hdiutil create -volname "Kiln" -srcfolder "$staging" -fs HFS+ -format UDZO -ov "$dmg" >/dev/null
echo "Created $dmg"
