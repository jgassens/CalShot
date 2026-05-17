#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

SCHEME="CalShot"
CONFIGURATION="${CALSHOT_CONFIGURATION:-Release}"
DERIVED_DATA="${CALSHOT_DERIVED_DATA:-/private/tmp/CalShotReleaseDerivedData}"
DIST_DIR="${CALSHOT_DIST_DIR:-$PWD/dist}"
ARCHIVE_PATH="${CALSHOT_ARCHIVE_PATH:-/private/tmp/CalShot.xcarchive}"
TEAM_ID="${CALSHOT_TEAM_ID:-C2N7W5247T}"
APP_BUNDLE_ID="${CALSHOT_BUNDLE_ID:-com.jgassens.CalShot}"
SIGNING_IDENTITY="${CALSHOT_SIGNING_IDENTITY:-Developer ID Application: JEREMIAH JOSEPH GASSENSMITH (C2N7W5247T)}"
NOTARY_PROFILE="${CALSHOT_NOTARY_PROFILE:-}"
TEST_DESTINATION="${CALSHOT_TEST_DESTINATION:-platform=macOS,arch=$(uname -m)}"

RUN_TESTS=1
NOTARIZE=0
UNSIGNED=0

usage() {
  cat <<'USAGE'
Usage: script/build_dmg.sh [--notarize] [--notary-profile NAME] [--identity NAME] [--unsigned] [--skip-tests]

Build a CalShot Release archive, package CalShot.app into a DMG, and verify the artifact.

Environment:
  CALSHOT_SIGNING_IDENTITY   Developer ID identity for distribution signing.
  CALSHOT_NOTARY_PROFILE     notarytool keychain profile used with --notarize.
  CALSHOT_TEAM_ID            Apple Developer Team ID.
  CALSHOT_BUNDLE_ID          Bundle ID to build and verify.
  CALSHOT_DIST_DIR           Output directory, defaults to ./dist.
  CALSHOT_TEST_DESTINATION   xcodebuild test destination, defaults to this Mac's architecture.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --notarize)
      NOTARIZE=1
      shift
      ;;
    --notary-profile)
      NOTARY_PROFILE="${2:-}"
      [[ -n "$NOTARY_PROFILE" ]] || { echo "--notary-profile requires a value" >&2; exit 2; }
      shift 2
      ;;
    --identity)
      SIGNING_IDENTITY="${2:-}"
      [[ -n "$SIGNING_IDENTITY" ]] || { echo "--identity requires a value" >&2; exit 2; }
      shift 2
      ;;
    --unsigned)
      UNSIGNED=1
      shift
      ;;
    --skip-tests)
      RUN_TESTS=0
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen is required. Install it with: brew install xcodegen" >&2
  exit 127
fi

if [[ "$NOTARIZE" -eq 1 && "$UNSIGNED" -eq 1 ]]; then
  echo "--notarize cannot be used with --unsigned" >&2
  exit 2
fi

if [[ "$NOTARIZE" -eq 1 && -z "$NOTARY_PROFILE" ]]; then
  echo "Set CALSHOT_NOTARY_PROFILE or pass --notary-profile before using --notarize." >&2
  exit 2
fi

if [[ ! -f Resources/chrono.bundle.js ]]; then
  ./script/bundle_chrono.sh
fi

xcodegen generate

if [[ "$RUN_TESTS" -eq 1 ]]; then
  xcodebuild \
    -scheme "$SCHEME" \
    -configuration Debug \
    -destination "$TEST_DESTINATION" \
    -derivedDataPath "$DERIVED_DATA" \
    -allowProvisioningUpdates \
    test
fi

rm -rf "$ARCHIVE_PATH"

BUILD_SETTINGS=(
  PRODUCT_BUNDLE_IDENTIFIER="$APP_BUNDLE_ID"
  DEVELOPMENT_TEAM="$TEAM_ID"
)

if [[ "$UNSIGNED" -eq 1 ]]; then
  BUILD_SETTINGS+=(
    CODE_SIGNING_ALLOWED=NO
    CODE_SIGNING_REQUIRED=NO
  )
else
  if ! security find-identity -p codesigning -v | grep -Fq "$SIGNING_IDENTITY"; then
    echo "Signing identity not found: $SIGNING_IDENTITY" >&2
    echo "Install a Developer ID Application certificate, pass --identity, or use --unsigned for local-only packaging." >&2
    exit 1
  fi

  BUILD_SETTINGS+=(
    CODE_SIGN_STYLE=Manual
    CODE_SIGN_IDENTITY="$SIGNING_IDENTITY"
    OTHER_CODE_SIGN_FLAGS="--timestamp"
  )
fi

xcodebuild \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE_PATH" \
  -derivedDataPath "$DERIVED_DATA" \
  -allowProvisioningUpdates \
  archive \
  "${BUILD_SETTINGS[@]}"

APP_PATH="$ARCHIVE_PATH/Products/Applications/CalShot.app"
[[ -d "$APP_PATH" ]] || { echo "Missing archived app at $APP_PATH" >&2; exit 1; }

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP_PATH/Contents/Info.plist")
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP_PATH/Contents/Info.plist")
ICON_NAME=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIconName" "$APP_PATH/Contents/Info.plist")
LSUI_ELEMENT=$(/usr/libexec/PlistBuddy -c "Print :LSUIElement" "$APP_PATH/Contents/Info.plist")
FEED_URL=$(/usr/libexec/PlistBuddy -c "Print :SUFeedURL" "$APP_PATH/Contents/Info.plist")
PUBLIC_KEY=$(/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" "$APP_PATH/Contents/Info.plist")
AUTO_CHECKS=$(/usr/libexec/PlistBuddy -c "Print :SUEnableAutomaticChecks" "$APP_PATH/Contents/Info.plist")
INSTALLER_SERVICE=$(/usr/libexec/PlistBuddy -c "Print :SUEnableInstallerLauncherService" "$APP_PATH/Contents/Info.plist")

[[ "$BUNDLE_ID" == "$APP_BUNDLE_ID" ]] || { echo "Expected bundle id $APP_BUNDLE_ID, got $BUNDLE_ID" >&2; exit 1; }
[[ "$ICON_NAME" == "AppIcon" ]] || { echo "Expected CFBundleIconName=AppIcon, got $ICON_NAME" >&2; exit 1; }
[[ "$LSUI_ELEMENT" == "true" ]] || { echo "Expected LSUIElement=true, got $LSUI_ELEMENT" >&2; exit 1; }
[[ "$FEED_URL" == "https://github.com/jgassens/CalShot/releases/latest/download/appcast.xml" ]] || { echo "Unexpected Sparkle feed URL: $FEED_URL" >&2; exit 1; }
[[ "$PUBLIC_KEY" != *PENDING* && ${#PUBLIC_KEY} -gt 30 ]] || { echo "Missing valid Sparkle public key" >&2; exit 1; }
[[ "$AUTO_CHECKS" == "true" ]] || { echo "Expected Sparkle automatic checks to be enabled" >&2; exit 1; }
[[ "$INSTALLER_SERVICE" == "true" ]] || { echo "Expected Sparkle installer launcher service to be enabled" >&2; exit 1; }
[[ -f "$APP_PATH/Contents/Resources/Assets.car" ]] || { echo "Missing compiled asset catalog in app resources" >&2; exit 1; }
[[ -f "$APP_PATH/Contents/Resources/chrono.bundle.js" ]] || { echo "Missing chrono.bundle.js in app resources" >&2; exit 1; }
[[ -f "$APP_PATH/Contents/Resources/chrono-node-MIT.txt" ]] || { echo "Missing chrono license in app resources" >&2; exit 1; }
[[ -d "$APP_PATH/Contents/Frameworks/Sparkle.framework" ]] || { echo "Missing Sparkle.framework" >&2; exit 1; }
[[ -d "$APP_PATH/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc" ]] || { echo "Missing Sparkle Installer.xpc" >&2; exit 1; }

if [[ "$UNSIGNED" -eq 0 ]]; then
  codesign --verify --deep --strict --verbose=2 "$APP_PATH"
  codesign -d --entitlements - "$APP_PATH" 2>/dev/null | grep -q "com.apple.security.app-sandbox"
  codesign -d --entitlements - "$APP_PATH" 2>/dev/null | grep -q "com.apple.security.personal-information.calendars"
  codesign -d --entitlements - "$APP_PATH" 2>/dev/null | grep -q "com.apple.security.network.client"
  codesign -d --entitlements - "$APP_PATH" 2>/dev/null | grep -q "$(printf '%s' "$APP_BUNDLE_ID-spks")"
  codesign -d --entitlements - "$APP_PATH" 2>/dev/null | grep -q "$(printf '%s' "$APP_BUNDLE_ID-spki")"
fi

ARTIFACT_SUFFIX="unnotarized"
if [[ "$UNSIGNED" -eq 1 ]]; then
  ARTIFACT_SUFFIX="unsigned"
elif [[ "$NOTARIZE" -eq 1 ]]; then
  ARTIFACT_SUFFIX="notarized"
fi

DMG_NAME="CalShot-${VERSION}-${BUILD}-${ARTIFACT_SUFFIX}.dmg"
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

if [[ "$UNSIGNED" -eq 0 ]]; then
  codesign --force --sign "$SIGNING_IDENTITY" --timestamp "$TMP_DMG_PATH"
  codesign --verify --verbose=2 "$TMP_DMG_PATH"
fi

mv -f "$TMP_DMG_PATH" "$DMG_PATH"

if [[ "$NOTARIZE" -eq 1 ]]; then
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
  spctl -a -t open --context context:primary-signature -vv "$DMG_PATH"
fi

shasum -a 256 "$DMG_PATH" > "$DMG_PATH.sha256"

echo "App: $APP_PATH"
echo "DMG: $DMG_PATH"
echo "SHA-256: $DMG_PATH.sha256"
