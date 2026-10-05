#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLUTTER_BIN="${FLUTTER_BIN:-/Volumes/PD1000/job/flutter/bin/flutter}"
CONFIG_PATH="$ROOT_DIR/firebase.mobile_web.json"
APP_DIR="$ROOT_DIR/apps/mobile_flutter"
SITE_ID="inter-city-pkzpps"
INTERCITY_API_BASE_URL="${INTERCITY_API_BASE_URL:-https://intercity-backend-176647550231.us-central1.run.app/api}"

echo "== InterCity mobile web deploy =="
echo "Root: $ROOT_DIR"
echo "Site: $SITE_ID"
echo "API: $INTERCITY_API_BASE_URL"

if ! command -v firebase >/dev/null 2>&1; then
  echo "Firebase CLI not found. Install it first: npm i -g firebase-tools" >&2
  exit 1
fi

if [[ ! -x "$FLUTTER_BIN" ]]; then
  echo "Flutter binary not found or not executable: $FLUTTER_BIN" >&2
  exit 1
fi

echo "== Checking Firebase access =="
if ! firebase hosting:sites:list --project "$SITE_ID" >/dev/null; then
  echo "Firebase access check failed." >&2
  echo "Login with an account that has Hosting Admin or Owner on project/site: $SITE_ID" >&2
  echo "Run: firebase login --reauth" >&2
  exit 1
fi

echo "== Running tests =="
(
  cd "$APP_DIR"
  "$FLUTTER_BIN" test
  "$FLUTTER_BIN" analyze
  "$FLUTTER_BIN" build web --release --no-wasm-dry-run \
    --dart-define=INTERCITY_API_BASE_URL="$INTERCITY_API_BASE_URL"
  rsync -a --delete build/web/ web_deploy/
)

echo "== Deploying to Firebase Hosting =="
firebase deploy --config "$CONFIG_PATH" --project "$SITE_ID" --only hosting

echo "== Done =="
echo "URL: https://$SITE_ID.web.app/"
