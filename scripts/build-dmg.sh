#!/usr/bin/env bash
set -euo pipefail

# build-dmg.sh — build claudegrain.app, sign, notarize, package as DMG.
#
# Required env (optional unless noted):
#   DEVELOPER_ID       Developer ID Application identity (e.g. "Developer ID Application: Foo (TEAMID)")
#                      If unset, the app is signed ad-hoc and a warning is printed.
#   NOTARY_PROFILE     `xcrun notarytool` keychain profile name. If unset, notarization is skipped.
#   BUNDLE_ID          Override default bundle id (default: dev.claudegrain.menubar).

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="claudegrain"
EXEC_NAME="claudegrain"
BUNDLE_ID="${BUNDLE_ID:-dev.claudegrain.menubar}"
VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
DMG_PATH="$DIST_DIR/${APP_NAME}-${VERSION}.dmg"

# Use full Xcode toolchain — CommandLineTools toolchain is broken on the dev box.
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

echo "==> Building release ($VERSION)"
cd "$ROOT_DIR"
swift build -c release --product "$EXEC_NAME"

BIN_PATH="$(swift build -c release --product "$EXEC_NAME" --show-bin-path)/$EXEC_NAME"
[ -f "$BIN_PATH" ] || { echo "missing binary: $BIN_PATH" >&2; exit 1; }

echo "==> Assembling $APP_BUNDLE"
rm -rf "$APP_BUNDLE" "$DMG_PATH"
mkdir -p "$DIST_DIR" "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/$EXEC_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$EXEC_NAME"

# Copy SwiftPM-processed resource bundle if present so the runtime can locate it.
RES_BUNDLE="$(dirname "$BIN_PATH")/${APP_NAME}_ClaudegrainApp.bundle"
[ -d "$RES_BUNDLE" ] && cp -R "$RES_BUNDLE" "$APP_BUNDLE/Contents/Resources/"

# App icon
if [ -f "$ROOT_DIR/assets/AppIcon.icns" ]; then
  cp "$ROOT_DIR/assets/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleDisplayName</key><string>Claudegrain</string>
    <key>CFBundleExecutable</key><string>${EXEC_NAME}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>Copyright © Claudegrain contributors.</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>ATSApplicationFontsPath</key><string>claudegrain_ClaudegrainApp.bundle</string>
</dict>
</plist>
PLIST

# Minimal hardened-runtime entitlements — extend if app needs network/files.
ENT_PATH="$DIST_DIR/claudegrain.entitlements"
cat > "$ENT_PATH" <<'ENT'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.cs.allow-jit</key><false/>
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key><false/>
</dict>
</plist>
ENT

echo "==> Codesigning"
if [ -n "${DEVELOPER_ID:-}" ]; then
    codesign --force --deep --options runtime --timestamp \
        --entitlements "$ENT_PATH" \
        --sign "$DEVELOPER_ID" \
        "$APP_BUNDLE"
    codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
else
    echo "WARN: DEVELOPER_ID not set — signing ad-hoc (DMG will not pass Gatekeeper)" >&2
    codesign --force --deep --sign - "$APP_BUNDLE"
fi

echo "==> Building DMG: $DMG_PATH"
if command -v create-dmg >/dev/null 2>&1; then
    create-dmg \
        --volname "$APP_NAME $VERSION" \
        --window-size 540 360 \
        --icon-size 96 \
        --icon "$APP_NAME.app" 140 180 \
        --app-drop-link 400 180 \
        --no-internet-enable \
        "$DMG_PATH" "$APP_BUNDLE" || true
fi

if [ ! -f "$DMG_PATH" ]; then
    # Fallback: hdiutil. Stage the .app alone so the DMG only contains it + Applications symlink.
    STAGE="$(mktemp -d)"
    cp -R "$APP_BUNDLE" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"
    hdiutil create -volname "$APP_NAME $VERSION" -srcfolder "$STAGE" \
        -ov -format UDZO "$DMG_PATH"
    rm -rf "$STAGE"
fi

# Sign the DMG itself so notarization stapling can attach to it.
if [ -n "${DEVELOPER_ID:-}" ]; then
    codesign --force --sign "$DEVELOPER_ID" --timestamp "$DMG_PATH"
fi

if [ -n "${NOTARY_PROFILE:-}" ]; then
    echo "==> Submitting to Apple notary service (profile=$NOTARY_PROFILE)"
    xcrun notarytool submit "$DMG_PATH" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait
    echo "==> Stapling ticket"
    xcrun stapler staple "$DMG_PATH"
    xcrun stapler validate "$DMG_PATH"
else
    echo "WARN: NOTARY_PROFILE not set — skipping notarization & stapling" >&2
fi

echo "==> Done: $DMG_PATH"
