#!/usr/bin/env bash
set -euo pipefail

# build-dmg.sh — build claudegrain.app via xcodebuild (host + widget extension),
# sign, notarize, package as DMG.
#
# Required env (optional unless noted):
#   DEVELOPER_ID       Developer ID Application identity (e.g. "Developer ID Application: Foo (TEAMID)")
#                      If unset, the app is signed ad-hoc and a warning is printed.
#   NOTARY_PROFILE     `xcrun notarytool` keychain profile name. If unset, notarization is skipped.
#   DEVELOPMENT_TEAM   Apple Developer Team ID. Required for App Group entitlement to validate.
#                      Without it, codesign succeeds ad-hoc but the widget won't read the
#                      shared container at runtime.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="claudegrain"
VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
DMG_PATH="$DIST_DIR/${APP_NAME}-${VERSION}.dmg"
DERIVED="$ROOT_DIR/.build/xcode-derived"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

echo "==> Regenerating Xcode project from project.yml"
if ! command -v xcodegen >/dev/null 2>&1; then
    echo "ERROR: xcodegen not installed. brew install xcodegen" >&2
    exit 1
fi
( cd "$ROOT_DIR" && xcodegen generate >/dev/null )

echo "==> Building release ($VERSION)"
mkdir -p "$DIST_DIR"

XCB_ARGS=(
    -project "$ROOT_DIR/Claudegrain.xcodeproj"
    -scheme Claudegrain
    -configuration Release
    -destination 'platform=macOS'
    -derivedDataPath "$DERIVED"
    MARKETING_VERSION="$VERSION"
    CURRENT_PROJECT_VERSION="$VERSION"
)

if [ -n "${DEVELOPMENT_TEAM:-}" ]; then
    XCB_ARGS+=(DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" CODE_SIGN_STYLE=Automatic)
else
    echo "WARN: DEVELOPMENT_TEAM not set — building without codesign. App Group entitlement will not validate at runtime." >&2
    XCB_ARGS+=(CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO)
fi

xcodebuild "${XCB_ARGS[@]}" build

BUILT_APP="$DERIVED/Build/Products/Release/claudegrain.app"
[ -d "$BUILT_APP" ] || { echo "missing built app: $BUILT_APP" >&2; exit 1; }

echo "==> Staging $APP_BUNDLE"
rm -rf "$APP_BUNDLE" "$DMG_PATH"
cp -R "$BUILT_APP" "$APP_BUNDLE"

# App icon (xcodebuild doesn't copy it; project still uses CFBundleIconFile=AppIcon).
if [ -f "$ROOT_DIR/assets/AppIcon.icns" ]; then
    cp "$ROOT_DIR/assets/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

if [ -n "${DEVELOPER_ID:-}" ]; then
    echo "==> Re-signing with Developer ID"
    # --deep also re-signs the embedded ClaudegrainWidget.appex with the same identity.
    codesign --force --deep --options runtime --timestamp \
        --entitlements "$ROOT_DIR/Sources/ClaudegrainApp/Claudegrain.entitlements" \
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
    STAGE="$(mktemp -d)"
    cp -R "$APP_BUNDLE" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"
    hdiutil create -volname "$APP_NAME $VERSION" -srcfolder "$STAGE" \
        -ov -format UDZO "$DMG_PATH"
    rm -rf "$STAGE"
fi

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
