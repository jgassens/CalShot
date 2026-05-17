#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

SCHEME="CalShot"
CONFIGURATION="Debug"
DERIVED_DATA="${CALSHOT_DERIVED_DATA:-/private/tmp/CalShotDerivedData}"
DERIVED_APP_PATH="$DERIVED_DATA/Build/Products/$CONFIGURATION/CalShot.app"
DEV_DIR="${CALSHOT_DEV_DIR:-$PWD/dev}"
APP_PATH="$DEV_DIR/CalShot.app"
APP_BUNDLE_ID="${CALSHOT_BUNDLE_ID:-com.jgassens.CalShot}"
SMOKE_REFERENCE_DATE="${CALSHOT_SMOKE_REFERENCE_DATE:-2026-05-08T12:00:00Z}"
CONTAINER_TMP_DIR="$HOME/Library/Containers/$APP_BUNDLE_ID/Data/tmp"
SUMMARY_DIR="$CONTAINER_TMP_DIR/CalShotEmailSmokeSummaries/$(date +%Y%m%d-%H%M%S)-$$"
CONTAINER_INPUT_DIR="$CONTAINER_TMP_DIR/CalShotEmailSmokeInput"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen is required. Install it with: brew install xcodegen" >&2
  exit 127
fi

xcodegen generate
xcodebuild \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA" \
  -allowProvisioningUpdates \
  build

[[ -d "$DERIVED_APP_PATH" ]] || { echo "Missing built app at $DERIVED_APP_PATH" >&2; exit 1; }
mkdir -p "$DEV_DIR" "$SUMMARY_DIR" "$CONTAINER_INPUT_DIR"
rm -rf "$APP_PATH"
ditto "$DERIVED_APP_PATH" "$APP_PATH"

write_fixture() {
  local name="$1"
  local path="$CONTAINER_INPUT_DIR/$name.eml"

  case "$name" in
    plain)
      cat > "$path" <<'EOF'
From: Research Office <research@example.edu>
Subject: Stress Seminar
Date: Wed, 13 May 2026 09:00:00 -0500
Content-Type: text/plain; charset=utf-8

Stress Seminar
May 20, 2026 at 3 PM
Where: FO 2.702
Join: https://example.edu/stress
EOF
      ;;
    broken-multipart)
      cat > "$path" <<'EOF'
Subject: Broken Multipart Invite
Content-Type: multipart/mixed

Broken Multipart Invite
Meet May 21, 2026 at 4 PM.
Details: https://example.edu/broken-multipart
EOF
      ;;
    nested-html)
      cat > "$path" <<'EOF'
Subject: Forwarded Nested Invite
Content-Type: message/rfc822

Subject: Nested Invite
Content-Type: text/html; charset=utf-8

<html><body><p>Nested Invite</p><p>May 22, 2026 at 11 AM</p><p>Where: Zoom</p><a href="https://teams.example.edu/nested">Join nested meeting</a></body></html>
EOF
      ;;
    *)
      echo "Unknown fixture: $name" >&2
      exit 2
      ;;
  esac

  echo "$path"
}

run_case() {
  local label="$1"
  shift
  local email_file
  email_file="$(write_fixture "$label")"
  local summary_file="$SUMMARY_DIR/$label.summary"

  pkill -x "CalShot" >/dev/null 2>&1 || true
  /usr/bin/open -n "$APP_PATH" --args \
    --calshot-open-email "$email_file" \
    --calshot-smoke-reference-date "$SMOKE_REFERENCE_DATE" \
    --calshot-smoke-summary-file "$summary_file"

  for _ in {1..80}; do
    if [[ -f "$summary_file" ]]; then
      break
    fi
    sleep 0.25
  done

  if [[ ! -f "$summary_file" ]]; then
    echo "Email smoke case '$label' did not produce a summary." >&2
    exit 1
  fi

  local summary
  summary="$(<"$summary_file")"
  echo "[$label] $summary"

  local expected
  for expected in "$@"; do
    if [[ "$summary" != *"$expected"* ]]; then
      echo "Email smoke case '$label' missing expected fragment: $expected" >&2
      exit 1
    fi
  done
}

run_case "plain" \
  "title=Stress Seminar" \
  "start=2026-05-20T20:00:00Z" \
  "location=FO 2.702" \
  "url=https://example.edu/stress" \
  "canCreate=true"

run_case "broken-multipart" \
  "title=Broken Multipart Invite" \
  "start=2026-05-21T21:00:00Z" \
  "url=https://example.edu/broken-multipart" \
  "canCreate=true"

run_case "nested-html" \
  "title=Forwarded Nested Invite" \
  "start=2026-05-22T16:00:00Z" \
  "location=Zoom" \
  "url=https://teams.example.edu/nested" \
  "canCreate=true"

echo "Email smoke summaries: $SUMMARY_DIR"
