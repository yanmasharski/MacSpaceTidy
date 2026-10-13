#!/bin/zsh
# Builds the app and packs it into dist/MacSpaceTidy.zip (plus a .sha256 file) for a GitHub release.
# The file name has no version on purpose: install.sh downloads releases/latest/download/MacSpaceTidy.zip.
set -euo pipefail

cd "$(dirname "$0")/.."
./scripts/build-app.sh
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' build/MacSpaceTidy.app/Contents/Info.plist)"
mkdir -p dist
rm -f dist/MacSpaceTidy.zip dist/MacSpaceTidy.zip.sha256
# ditto keeps the code signature and extended attributes; plain zip can break them.
ditto -c -k --keepParent build/MacSpaceTidy.app dist/MacSpaceTidy.zip
(cd dist && shasum -a 256 MacSpaceTidy.zip > MacSpaceTidy.zip.sha256)
printf 'Packed version %s: dist/MacSpaceTidy.zip (%s)\n' "$VERSION" "$(du -h dist/MacSpaceTidy.zip | cut -f1)"
