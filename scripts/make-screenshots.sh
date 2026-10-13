#!/bin/zsh
# Draws the README screenshots with made-up demo data (nothing from your Mac). See SnapshotJob.swift.
set -euo pipefail

cd "$(dirname "$0")/.."
swift build --product MacSpaceTidyApp
APP="$(swift build --product MacSpaceTidyApp --show-bin-path)/MacSpaceTidyApp"
OUT="docs/images"
mkdir -p "$OUT"
"$APP" --snapshot "$OUT/screenshot-light.png" --demo
"$APP" --snapshot "$OUT/screenshot-dark.png" --demo --dark
"$APP" --snapshot "$OUT/screenshot-confirm.png" --demo --sheet confirm --width 560
