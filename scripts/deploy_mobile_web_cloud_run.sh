#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/apps/mobile_flutter"
OUTPUT_DIR="${OUTPUT_DIR:-$APP_DIR/web_deploy}"
SERVICE_NAME="${SERVICE_NAME:-intercity-mobile-web}"
REGION="${REGION:-us-central1}"
PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || true)}"

show_help() {
  cat <<EOF
Builds and deploys the mobile Flutter web bundle to Google Cloud Run.

Environment variables:
  PROJECT_ID              Google Cloud project ID. Defaults to the active
                          gcloud project.
  SERVICE_NAME            Cloud Run service name. Default: $SERVICE_NAME
  REGION                  Cloud Run region. Default: $REGION
  OUTPUT_DIR              Web build output directory. Default: $OUTPUT_DIR
  INTERCITY_API_BASE_URL  Optional compile-time API base URL passed to the
                          Flutter web build via --dart-define.

Examples:
  bash scripts/deploy_mobile_web_cloud_run.sh
  INTERCITY_API_BASE_URL="https://api.example.com/api" bash scripts/deploy_mobile_web_cloud_run.sh
  PROJECT_ID=my-project SERVICE_NAME=intercity-mobile-web-staging bash scripts/deploy_mobile_web_cloud_run.sh
EOF
}

if [[ "${1:-}" == "--help" ]]; then
  show_help
  exit 0
fi

if [[ -z "$PROJECT_ID" ]]; then
  echo "PROJECT_ID is not set and no active gcloud project was found." >&2
  exit 1
fi

if [[ "$PROJECT_ID" == "(unset)" ]]; then
  echo "PROJECT_ID is not set and gcloud returned '(unset)'." >&2
  exit 1
fi

if [[ -z "${INTERCITY_API_BASE_URL:-}" ]]; then
  echo "WARN: INTERCITY_API_BASE_URL is not set. The deployed web build will use the safe placeholder backend and only the UI shell will be testable." >&2
fi

echo "==> Building mobile web deploy bundle"
bash "$ROOT_DIR/scripts/build_mobile_web_deploy.sh"

echo "==> Deploying Cloud Run service $SERVICE_NAME to project $PROJECT_ID ($REGION)"
gcloud run deploy "$SERVICE_NAME" \
  --project "$PROJECT_ID" \
  --source "$OUTPUT_DIR" \
  --region "$REGION" \
  --platform managed \
  --allow-unauthenticated \
  --port 8080 \
  --quiet

echo "==> Cloud Run URL"
gcloud run services describe "$SERVICE_NAME" \
  --project "$PROJECT_ID" \
  --platform managed \
  --region "$REGION" \
  --format='value(status.url)'
