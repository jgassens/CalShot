#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

DERIVED_DATA="${CALSHOT_DERIVED_DATA:-/private/tmp/CalShotReleaseDerivedData}"
UPDATES_DIR="${CALSHOT_SPARKLE_UPDATES_DIR:-$PWD/dist/sparkle-updates}"
SPARKLE_ACCOUNT="${CALSHOT_SPARKLE_ACCOUNT:-com.jgassens.CalShot}"
PRODUCT_URL="${CALSHOT_PRODUCT_URL:-https://github.com/jgassens/CalShot}"
ARTIFACT_PATH=""
RELEASE_NOTES_PATH=""
RELEASE_TAG="${CALSHOT_RELEASE_TAG:-}"
DOWNLOAD_URL_PREFIX="${CALSHOT_SPARKLE_DOWNLOAD_URL_PREFIX:-}"

usage() {
  cat <<'USAGE'
Usage: script/generate_appcast.sh --artifact PATH [--release-tag TAG] [--release-notes PATH] [--updates-dir DIR]

Generate or update Sparkle's appcast.xml for a CalShot GitHub Release.

Typical release flow:
  CALSHOT_NOTARY_PROFILE=calshot-notary ./script/build_dmg.sh --notarize
  ./script/generate_appcast.sh \
    --artifact dist/CalShot-1.0-1-notarized.dmg \
    --release-tag v1.0

Upload the DMG and the generated appcast.xml to the GitHub release. CalShot's
SUFeedURL points at:
  https://github.com/jgassens/CalShot/releases/latest/download/appcast.xml

Environment:
  CALSHOT_RELEASE_TAG                  GitHub release tag, defaults to v<CFBundleShortVersionString>.
  CALSHOT_SPARKLE_DOWNLOAD_URL_PREFIX  Override update asset URL prefix.
  CALSHOT_SPARKLE_UPDATES_DIR          Working appcast/archive directory, defaults to dist/sparkle-updates.
  CALSHOT_SPARKLE_ACCOUNT              Keychain account for Sparkle signing, defaults to com.jgassens.CalShot.
  CALSHOT_SPARKLE_PRIVATE_KEY          CI secret; when set, passed to generate_appcast via stdin.
  CALSHOT_SPARKLE_TOOLS_DIR            Directory containing Sparkle's generate_appcast tool.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --artifact)
      ARTIFACT_PATH="${2:-}"
      [[ -n "$ARTIFACT_PATH" ]] || { echo "--artifact requires a path" >&2; exit 2; }
      shift 2
      ;;
    --release-notes)
      RELEASE_NOTES_PATH="${2:-}"
      [[ -n "$RELEASE_NOTES_PATH" ]] || { echo "--release-notes requires a path" >&2; exit 2; }
      shift 2
      ;;
    --release-tag)
      RELEASE_TAG="${2:-}"
      [[ -n "$RELEASE_TAG" ]] || { echo "--release-tag requires a value" >&2; exit 2; }
      shift 2
      ;;
    --updates-dir)
      UPDATES_DIR="${2:-}"
      [[ -n "$UPDATES_DIR" ]] || { echo "--updates-dir requires a path" >&2; exit 2; }
      shift 2
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

[[ -n "$ARTIFACT_PATH" ]] || { echo "--artifact is required" >&2; usage >&2; exit 2; }
[[ -f "$ARTIFACT_PATH" ]] || { echo "Missing update artifact: $ARTIFACT_PATH" >&2; exit 1; }

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen is required. Install it with: brew install xcodegen" >&2
  exit 127
fi

xcodegen generate >/dev/null

if [[ -z "$RELEASE_TAG" ]]; then
  VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
  RELEASE_TAG="v$VERSION"
fi

if [[ -z "$DOWNLOAD_URL_PREFIX" ]]; then
  DOWNLOAD_URL_PREFIX="https://github.com/jgassens/CalShot/releases/download/$RELEASE_TAG"
fi
DOWNLOAD_URL_PREFIX="${DOWNLOAD_URL_PREFIX%/}/"

if [[ -n "${CALSHOT_SPARKLE_TOOLS_DIR:-}" ]]; then
  GENERATE_APPCAST="$CALSHOT_SPARKLE_TOOLS_DIR/generate_appcast"
else
  xcodebuild \
    -resolvePackageDependencies \
    -project CalShot.xcodeproj \
    -scheme CalShot \
    -derivedDataPath "$DERIVED_DATA" >/dev/null
  GENERATE_APPCAST="$(find "$DERIVED_DATA/SourcePackages/artifacts" -path '*/Sparkle/bin/generate_appcast' -type f | head -n 1)"
fi

[[ -x "$GENERATE_APPCAST" ]] || { echo "Could not find Sparkle generate_appcast. Set CALSHOT_SPARKLE_TOOLS_DIR." >&2; exit 1; }

mkdir -p "$UPDATES_DIR"
ARTIFACT_BASENAME="$(basename "$ARTIFACT_PATH")"
UPDATE_ARTIFACT="$UPDATES_DIR/$ARTIFACT_BASENAME"
ditto "$ARTIFACT_PATH" "$UPDATE_ARTIFACT"

if [[ -n "$RELEASE_NOTES_PATH" ]]; then
  [[ -f "$RELEASE_NOTES_PATH" ]] || { echo "Missing release notes: $RELEASE_NOTES_PATH" >&2; exit 1; }
  NOTES_EXT="${RELEASE_NOTES_PATH##*.}"
  NOTES_TARGET="$UPDATES_DIR/${ARTIFACT_BASENAME%.*}.$NOTES_EXT"
  cp "$RELEASE_NOTES_PATH" "$NOTES_TARGET"
fi

APPCAST_ARGS=(
  --download-url-prefix "$DOWNLOAD_URL_PREFIX"
  --link "$PRODUCT_URL"
  -o "$UPDATES_DIR/appcast.xml"
)

if [[ -n "${CALSHOT_SPARKLE_PRIVATE_KEY:-}" ]]; then
  printf "%s" "$CALSHOT_SPARKLE_PRIVATE_KEY" | "$GENERATE_APPCAST" "${APPCAST_ARGS[@]}" --ed-key-file - "$UPDATES_DIR"
else
  "$GENERATE_APPCAST" "${APPCAST_ARGS[@]}" --account "$SPARKLE_ACCOUNT" "$UPDATES_DIR"
fi

echo "Sparkle archive: $UPDATE_ARTIFACT"
echo "Sparkle appcast: $UPDATES_DIR/appcast.xml"
echo "Download URL prefix: $DOWNLOAD_URL_PREFIX"
