#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

SCHEME="CalShot"
CONFIGURATION="${CALSHOT_CONFIGURATION:-Release}"
DERIVED_DATA="${CALSHOT_DERIVED_DATA:-/private/tmp/CalShotDerivedData}"
DIST_DIR="${CALSHOT_DIST_DIR:-$PWD/dist}"
DERIVED_APP_PATH="$DERIVED_DATA/Build/Products/$CONFIGURATION/CalShot.app"
DEV_DIR="${CALSHOT_DEV_DIR:-$PWD/dev}"
APP_PATH="$DEV_DIR/CalShot.app"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen is required. Install it with: brew install xcodegen" >&2
  exit 127
fi

if [[ ! -f Resources/chrono.bundle.js ]]; then
  ./script/bundle_chrono.sh
fi

xcodegen generate

xcodebuild \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA" \
  -allowProvisioningUpdates \
  build

[[ -d "$DERIVED_APP_PATH" ]] || { echo "Missing built app at $DERIVED_APP_PATH" >&2; exit 1; }
mkdir -p "$DEV_DIR"
rm -rf "$APP_PATH"
ditto "$DERIVED_APP_PATH" "$APP_PATH"

[[ -d "$APP_PATH" ]] || { echo "Missing staged app at $APP_PATH" >&2; exit 1; }
[[ -f "$APP_PATH/Contents/Resources/Assets.car" ]] || { echo "Missing compiled asset catalog in app resources" >&2; exit 1; }

ICON_NAME=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIconName" "$APP_PATH/Contents/Info.plist")
[[ "$ICON_NAME" == "AppIcon" ]] || { echo "Expected CFBundleIconName=AppIcon, got $ICON_NAME" >&2; exit 1; }

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP_PATH/Contents/Info.plist")
DMG_NAME="CalShot-${VERSION}-${BUILD}-unnotarized.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
TMP_DMG_PATH="/private/tmp/.${DMG_NAME}.$$.$RANDOM.tmp.dmg"
STAGE_ROOT="$(mktemp -d /private/tmp/CalShotDmgStage.XXXXXX)"
STAGE_DIR="$STAGE_ROOT/CalShot"

cleanup() {
  rm -rf "$STAGE_ROOT"
  rm -f "$TMP_DMG_PATH"
}
trap cleanup EXIT

mkdir -p "$DIST_DIR" "$STAGE_DIR"
ditto "$APP_PATH" "$STAGE_DIR/CalShot.app"
ln -s /Applications "$STAGE_DIR/Applications"

hdiutil create \
  -volname "CalShot" \
  -srcfolder "$STAGE_DIR" \
  -ov \
  -format UDZO \
  "$TMP_DMG_PATH" >/dev/null

hdiutil verify "$TMP_DMG_PATH" >/dev/null
mv -f "$TMP_DMG_PATH" "$DMG_PATH"
echo "$DMG_PATH"
