#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

SCHEME="CalShot"
CONFIGURATION="Debug"
DERIVED_DATA="${CALSHOT_DERIVED_DATA:-/private/tmp/CalShotDerivedData}"
DERIVED_APP_PATH="$DERIVED_DATA/Build/Products/$CONFIGURATION/CalShot.app"
DEV_DIR="${CALSHOT_DEV_DIR:-$PWD/dev}"
APP_PATH="$DEV_DIR/CalShot.app"

VERIFY=0
CLEAN=0
IMAGE_PATH=""
EMAIL_PATH=""
SMOKE_SUMMARY_PATH=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --verify)
      VERIFY=1
      shift
      ;;
    --clean)
      CLEAN=1
      shift
      ;;
    --image)
      IMAGE_PATH="${2:-}"
      if [[ -z "$IMAGE_PATH" ]]; then
        echo "--image requires a path" >&2
        exit 2
      fi
      shift 2
      ;;
    --email)
      EMAIL_PATH="${2:-}"
      if [[ -z "$EMAIL_PATH" ]]; then
        echo "--email requires a path" >&2
        exit 2
      fi
      shift 2
      ;;
    --smoke-summary-file)
      SMOKE_SUMMARY_PATH="${2:-}"
      if [[ -z "$SMOKE_SUMMARY_PATH" ]]; then
        echo "--smoke-summary-file requires a path" >&2
        exit 2
      fi
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen is required. Install it with: brew install xcodegen" >&2
  exit 127
fi

if [[ "$CLEAN" -eq 1 ]]; then
  rm -rf "$DERIVED_DATA" CalShot.xcodeproj "$APP_PATH"
fi

if [[ ! -f Resources/chrono.bundle.js ]]; then
  ./script/bundle_chrono.sh
fi

if [[ -n "$IMAGE_PATH" ]]; then
  CONTAINER_INPUT_DIR="$HOME/Library/Containers/com.local.CalShot/Data/tmp/CalShotSmokeInput"
  mkdir -p "$CONTAINER_INPUT_DIR"
  STAGED_IMAGE_PATH="$CONTAINER_INPUT_DIR/$(basename "$IMAGE_PATH")"
  cp "$IMAGE_PATH" "$STAGED_IMAGE_PATH"
  IMAGE_PATH="$STAGED_IMAGE_PATH"
fi

if [[ -n "$EMAIL_PATH" ]]; then
  CONTAINER_INPUT_DIR="$HOME/Library/Containers/com.local.CalShot/Data/tmp/CalShotEmailInput"
  mkdir -p "$CONTAINER_INPUT_DIR"
  STAGED_EMAIL_PATH="$CONTAINER_INPUT_DIR/$(basename "$EMAIL_PATH")"
  cp "$EMAIL_PATH" "$STAGED_EMAIL_PATH"
  EMAIL_PATH="$STAGED_EMAIL_PATH"
fi

xcodegen generate

if pgrep -x "CalShot" >/dev/null 2>&1; then
  pkill -x "CalShot"
fi

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

PBS="/System/Library/CoreServices/pbs"
if [[ -x "$PBS" ]]; then
  "$PBS" -read_bundle "$APP_PATH" >/dev/null 2>&1 || true
fi

if [[ "$VERIFY" -eq 1 ]]; then
  xcodebuild \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA" \
    -destination 'platform=macOS,arch=arm64' \
    -allowProvisioningUpdates \
    test

  [[ -d "$APP_PATH" ]] || { echo "Missing built app at $APP_PATH" >&2; exit 1; }
  [[ -f "$APP_PATH/Contents/Resources/chrono.bundle.js" ]] || { echo "Missing chrono.bundle.js in app resources" >&2; exit 1; }

  LSUI_ELEMENT=$(/usr/libexec/PlistBuddy -c "Print :LSUIElement" "$APP_PATH/Contents/Info.plist")
  [[ "$LSUI_ELEMENT" == "true" ]] || { echo "Expected LSUIElement=true, got $LSUI_ELEMENT" >&2; exit 1; }

  /usr/libexec/PlistBuddy -c "Print :NSCalendarsWriteOnlyAccessUsageDescription" "$APP_PATH/Contents/Info.plist" >/dev/null
  /usr/libexec/PlistBuddy -c "Print :NSCalendarsFullAccessUsageDescription" "$APP_PATH/Contents/Info.plist" >/dev/null
  SERVICE_TITLE=$(/usr/libexec/PlistBuddy -c "Print :NSServices:0:NSMenuItem:default" "$APP_PATH/Contents/Info.plist")
  [[ "$SERVICE_TITLE" == "Send to CalShot" ]] || { echo "Expected Services menu item, got $SERVICE_TITLE" >&2; exit 1; }
  codesign -d --entitlements - "$APP_PATH" 2>/dev/null | grep -q "com.apple.security.personal-information.calendars"
  codesign -d --entitlements - "$APP_PATH" 2>/dev/null | grep -q "com.apple.security.network.client"
fi

OPEN_ARGS=(-n "$APP_PATH")
if [[ -n "$IMAGE_PATH" ]]; then
  OPEN_ARGS+=(--args --calshot-open-image "$IMAGE_PATH")
  if [[ -n "$SMOKE_SUMMARY_PATH" ]]; then
    OPEN_ARGS+=(--calshot-smoke-summary-file "$SMOKE_SUMMARY_PATH")
  fi
fi
if [[ -n "$EMAIL_PATH" ]]; then
  if [[ "${#OPEN_ARGS[@]}" -eq 2 ]]; then
    OPEN_ARGS+=(--args)
  fi
  OPEN_ARGS+=(--calshot-open-email "$EMAIL_PATH")
fi

/usr/bin/open "${OPEN_ARGS[@]}"

if [[ "$VERIFY" -eq 1 ]]; then
  for _ in {1..30}; do
    if pgrep -x "CalShot" >/dev/null 2>&1; then
      echo "CalShot launched: $APP_PATH"
      exit 0
    fi
    sleep 0.5
  done
  echo "CalShot did not appear to launch." >&2
  exit 1
fi
