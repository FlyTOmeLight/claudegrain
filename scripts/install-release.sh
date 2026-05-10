#!/usr/bin/env bash
# install-release.sh — fetch the published DMG for a tag, mount it, copy
# claudegrain.app over /Applications, unmount, relaunch.
#
# Usage:
#   scripts/install-release.sh                # latest release
#   scripts/install-release.sh v0.3.0         # specific tag
#
# Idempotent: kills any running claudegrain first, replaces /Applications/claudegrain.app,
# detaches the mount even on partial failure.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="claudegrain"
DEST_APP="/Applications/$APP_NAME.app"
TAG="${1:-}"

if [ -z "$TAG" ]; then
    TAG="$(gh release view --json tagName --jq .tagName)"
    echo "==> Latest release: $TAG"
fi

WORK_DIR="$(mktemp -d -t claudegrain-install.XXXXXX)"
MOUNT_POINT=""

cleanup() {
    if [ -n "$MOUNT_POINT" ] && [ -d "$MOUNT_POINT" ]; then
        hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null || true
    fi
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

echo "==> Downloading $TAG DMG → $WORK_DIR"
gh release download "$TAG" --pattern '*.dmg' --dir "$WORK_DIR"

DMG_PATH="$(ls "$WORK_DIR"/*.dmg | head -1)"
[ -f "$DMG_PATH" ] || { echo "ERROR: no DMG in $WORK_DIR" >&2; exit 1; }
echo "==> DMG: $DMG_PATH"

echo "==> Killing running $APP_NAME"
pkill -f "$APP_NAME.app/Contents/MacOS/$APP_NAME" 2>/dev/null || true
sleep 1

echo "==> Mounting"
MOUNT_POINT="$(hdiutil attach "$DMG_PATH" -nobrowse -readonly | tail -1 | awk '{ for (i=3;i<=NF;i++) printf "%s%s", $i, (i==NF?"":" ") }')"
[ -d "$MOUNT_POINT" ] || { echo "ERROR: mount failed" >&2; exit 1; }
echo "    mounted at $MOUNT_POINT"

SRC_APP="$MOUNT_POINT/$APP_NAME.app"
[ -d "$SRC_APP" ] || { echo "ERROR: $APP_NAME.app missing on DMG" >&2; exit 1; }

echo "==> Replacing $DEST_APP"
rm -rf "$DEST_APP"
cp -R "$SRC_APP" "$DEST_APP"

# Strip quarantine so Gatekeeper doesn't prompt for ad-hoc-signed builds.
xattr -dr com.apple.quarantine "$DEST_APP" 2>/dev/null || true

echo "==> Launching"
open "$DEST_APP"

echo "==> $TAG installed."
