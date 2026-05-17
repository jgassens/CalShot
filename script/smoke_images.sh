#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

SCHEME="CalShot"
CONFIGURATION="Debug"
DERIVED_DATA="${CALSHOT_DERIVED_DATA:-/private/tmp/CalShotDerivedData}"
DERIVED_APP_PATH="$DERIVED_DATA/Build/Products/$CONFIGURATION/CalShot.app"
DEV_DIR="${CALSHOT_DEV_DIR:-$PWD/dev}"
APP_PATH="$DEV_DIR/CalShot.app"
IMAGE_DIR="${1:-build/SmokeImages}"
APP_BUNDLE_ID="${CALSHOT_BUNDLE_ID:-com.jgassens.CalShot}"
SMOKE_REFERENCE_DATE="${CALSHOT_SMOKE_REFERENCE_DATE:-2026-05-08T12:00:00Z}"
CONTAINER_TMP_DIR="$HOME/Library/Containers/$APP_BUNDLE_ID/Data/tmp"
SUMMARY_DIR="$CONTAINER_TMP_DIR/CalShotSmokeSummaries/$(date +%Y%m%d-%H%M%S)-$$"
CONTAINER_INPUT_DIR="$CONTAINER_TMP_DIR/CalShotSmokeInput"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen is required. Install it with: brew install xcodegen" >&2
  exit 127
fi

./script/generate_smoke_images.sh "$IMAGE_DIR"
IMAGE_DIR="$(cd "$IMAGE_DIR" && pwd)"

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

mkdir -p "$SUMMARY_DIR" "$CONTAINER_INPUT_DIR"

run_case() {
  local label="$1"
  local image_name="$2"
  shift 2

  local source_image="$IMAGE_DIR/$image_name"
  local staged_image="$CONTAINER_INPUT_DIR/$image_name"
  local summary_file="$SUMMARY_DIR/$label.summary"

  [[ -f "$source_image" ]] || { echo "Missing smoke image: $source_image" >&2; exit 1; }

  pkill -x "CalShot" >/dev/null 2>&1 || true
  cp "$source_image" "$staged_image"

  /usr/bin/open -n "$APP_PATH" --args \
    --calshot-open-image "$staged_image" \
    --calshot-smoke-reference-date "$SMOKE_REFERENCE_DATE" \
    --calshot-smoke-summary-file "$summary_file"

  for _ in {1..80}; do
    if [[ -f "$summary_file" ]]; then
      break
    fi
    sleep 0.25
  done

  if [[ ! -f "$summary_file" ]]; then
    echo "Smoke case '$label' did not produce a summary." >&2
    exit 1
  fi

  local summary
  summary="$(<"$summary_file")"
  echo "[$label] $summary"

  local expected
  for expected in "$@"; do
    if [[ "$summary" != *"$expected"* ]]; then
      echo "Smoke case '$label' missing expected fragment: $expected" >&2
      exit 1
    fi
  done
}

run_case "seminar" "01_university_seminar_flyer.png" \
  "title=Microglia and Memory" \
  "allDay=false" \
  "start=2026-05-09T20:00:00Z" \
  "end=2026-05-09T21:00:00Z" \
  "location=FO 2.702" \
  "url=nil" \
  "canCreate=true"

run_case "concert" "02_concert_poster.png" \
  "title=THE STATIC ARCADES" \
  "allDay=false" \
  "start=2026-05-08T23:00:00Z" \
  "end=2026-05-09T00:00:00Z" \
  "location=221B Elm Street, Dallas, TX" \
  "url=http://example.com/static" \
  "canCreate=true"

run_case "zoom" "03_zoom_invite_email.png" \
  "title=T32 Writing Workshop" \
  "allDay=false" \
  "start=2026-05-12T15:30:00Z" \
  "end=2026-05-12T16:30:00Z" \
  "location=Zoom" \
  "url=https://example.com/t32-writing-room" \
  "canCreate=true"

run_case "design-review" "04_design_review_story.png" \
  "title=DESIGN REVIEW" \
  "allDay=false" \
  "start=2026-05-09T20:00:00Z" \
  "end=2026-05-09T22:00:00Z" \
  "location=Founders Hall" \
  "url=nil" \
  "canCreate=true"

run_case "no-date" "05_bulletin_no_date.png" \
  "title=OPEN HOUSE" \
  "start=nil" \
  "end=nil" \
  "location=Building C" \
  "url=nil" \
  "canCreate=false"

echo "Smoke image summaries: $SUMMARY_DIR"
