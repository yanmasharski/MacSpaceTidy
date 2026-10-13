#!/bin/zsh
# Builds the app and packs it into dist/MacSpaceTidy-<version>.zip for a GitHub release.
set -euo pipefail

cd "$(dirname "$0")/.."
./scripts/build-app.sh
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' build/MacSpaceTidy.app/Contents/Info.plist)"
mkdir -p dist
ZIP="dist/MacSpaceTidy-$VERSION.zip"
rm -f "$ZIP"
# ditto keeps the code signature and extended attributes; plain zip can break them.
ditto -c -k --keepParent build/MacSpaceTidy.app "$ZIP"
printf 'Packed %s (%s)\n' "$ZIP" "$(du -h "$ZIP" | cut -f1)"
