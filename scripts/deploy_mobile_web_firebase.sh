#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIREBASE_CONFIG_PATH="${FIREBASE_CONFIG_PATH:-$ROOT_DIR/firebase.mobile_web.json}"
FIREBASE_PROJECT_ID="${FIREBASE_PROJECT_ID:-inter-city-pkzpps}"
FIREBASE_HOSTING_SITE="${FIREBASE_HOSTING_SITE:-inter-city-pkzpps}"
PRODUCTION_API_BASE_URL="${PRODUCTION_API_BASE_URL:-https://intercity-backend-176647550231.us-central1.run.app/api}"

show_help() {
  cat <<EOF
Builds and deploys the mobile Flutter web bundle to Firebase Hosting.

Environment variables:
  FIREBASE_PROJECT_ID     Firebase project ID. Default: $FIREBASE_PROJECT_ID
  FIREBASE_HOSTING_SITE   Firebase Hosting site ID. Default: $FIREBASE_HOSTING_SITE
  FIREBASE_CONFIG_PATH    Firebase config file. Default: $FIREBASE_CONFIG_PATH
  INTERCITY_API_BASE_URL  Optional compile-time API base URL passed to the
                          Flutter web build via --dart-define.
  PRODUCTION_API_BASE_URL Default API base URL used when INTERCITY_API_BASE_URL
                          is not set. Default: $PRODUCTION_API_BASE_URL

Examples:
  bash scripts/deploy_mobile_web_firebase.sh
  INTERCITY_API_BASE_URL="https://api.example.com/api" bash scripts/deploy_mobile_web_firebase.sh
EOF
}

if [[ "${1:-}" == "--help" ]]; then
  show_help
  exit 0
fi

if [[ ! -f "$FIREBASE_CONFIG_PATH" ]]; then
  echo "Firebase config not found: $FIREBASE_CONFIG_PATH" >&2
  exit 1
fi

if [[ -z "${INTERCITY_API_BASE_URL:-}" ]]; then
  export INTERCITY_API_BASE_URL="$PRODUCTION_API_BASE_URL"
  echo "INFO: INTERCITY_API_BASE_URL is not set. Falling back to production API: $INTERCITY_API_BASE_URL" >&2
fi

echo "==> Building mobile web deploy bundle"
bash "$ROOT_DIR/scripts/build_mobile_web_deploy.sh"

echo "==> Deploying Firebase Hosting site $FIREBASE_HOSTING_SITE in project $FIREBASE_PROJECT_ID"
firebase deploy \
  --project "$FIREBASE_PROJECT_ID" \
  --config "$FIREBASE_CONFIG_PATH" \
  --only hosting
