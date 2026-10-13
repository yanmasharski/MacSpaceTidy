#!/bin/bash
# Installs the latest MacSpaceTidy release into /Applications (or ~/Applications).
# Safe to run again: it replaces the old copy.
#
# Why this script exists: a file downloaded with a browser gets a "quarantine" mark, and macOS then says
# the app is damaged or from an unidentified developer. A file downloaded with curl has no such mark.
# The script also checks the file against its published checksum and checks the app's code signature.
#
#   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/yanmasharski/MacSpaceTidy/main/install.sh)"
set -euo pipefail

REPO="yanmasharski/MacSpaceTidy"
BASE_URL="https://github.com/$REPO/releases/latest/download"
ZIP_NAME="MacSpaceTidy.zip"
APP_NAME="MacSpaceTidy.app"
MIN_MACOS_MAJOR=14
# Overrides, used for tests: MST_INSTALL_DIR=<folder> and MST_NO_OPEN=1.
INSTALL_DIR="${MST_INSTALL_DIR:-/Applications}"

say() { printf '\n==> %s\n' "$1"; }
fail() { printf '\nSomething went wrong: %s\n' "$1" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || fail "MacSpaceTidy works only on macOS."
MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
[ "$MAJOR" -ge "$MIN_MACOS_MAJOR" ] || fail "MacSpaceTidy needs macOS $MIN_MACOS_MAJOR or newer. You have $(sw_vers -productVersion)."

if [ ! -w "$INSTALL_DIR" ]; then
  INSTALL_DIR="$HOME/Applications"
  mkdir -p "$INSTALL_DIR"
  say "/Applications is not writable for you. Installing into $INSTALL_DIR instead."
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

say "Downloading MacSpaceTidy"
curl -fL --progress-bar -o "$WORK/$ZIP_NAME" "$BASE_URL/$ZIP_NAME" || fail "Could not download the app. Check your internet connection."
curl -fsSL -o "$WORK/$ZIP_NAME.sha256" "$BASE_URL/$ZIP_NAME.sha256" || fail "Could not download the checksum file."

say "Checking the download"
(cd "$WORK" && shasum -a 256 -c "$ZIP_NAME.sha256" >/dev/null) || fail "The checksum does not match. The file is damaged. Do not use it."
ditto -x -k "$WORK/$ZIP_NAME" "$WORK/unpacked"
codesign --verify --deep --strict "$WORK/unpacked/$APP_NAME" || fail "The app's code signature is not valid."

if pgrep -x MacSpaceTidy >/dev/null; then
  say "Closing the running MacSpaceTidy"
  osascript -e 'tell application "MacSpaceTidy" to quit' >/dev/null 2>&1 || true
  sleep 2
fi

say "Installing into $INSTALL_DIR"
rm -rf "${INSTALL_DIR:?}/$APP_NAME"
ditto "$WORK/unpacked/$APP_NAME" "$INSTALL_DIR/$APP_NAME"
# Removes the "downloaded from the internet" mark, if there is one. Harmless when there is none.
xattr -dr com.apple.quarantine "$INSTALL_DIR/$APP_NAME" 2>/dev/null || true

say "Done. MacSpaceTidy is in $INSTALL_DIR"
if [ -z "${MST_NO_OPEN:-}" ]; then
  open "$INSTALL_DIR/$APP_NAME"
fi
