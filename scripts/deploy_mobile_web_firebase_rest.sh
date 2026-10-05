#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PUBLIC_DIR="${PUBLIC_DIR:-$ROOT_DIR/apps/mobile_flutter/web_deploy}"
SITE_ID="${FIREBASE_HOSTING_SITE:-inter-city-pkzpps}"
GCLOUD_ACCOUNT="${GCLOUD_ACCOUNT:-itmilanium@gmail.com}"
BUILD_BEFORE_DEPLOY="${BUILD_BEFORE_DEPLOY:-1}"
PRODUCTION_API_BASE_URL="${PRODUCTION_API_BASE_URL:-https://intercity-backend-176647550231.us-central1.run.app/api}"

show_help() {
  cat <<EOF
Builds and deploys the mobile Flutter web bundle to Firebase Hosting using the
Hosting REST API and an existing gcloud-authenticated account.

Environment variables:
  FIREBASE_HOSTING_SITE   Hosting site ID. Default: $SITE_ID
  GCLOUD_ACCOUNT          gcloud account used to mint the OAuth token.
                          Default: $GCLOUD_ACCOUNT
  PUBLIC_DIR              Directory to deploy. Default: $PUBLIC_DIR
  BUILD_BEFORE_DEPLOY     When "1", rebuilds the web bundle before deploy.
                          Default: $BUILD_BEFORE_DEPLOY
  INTERCITY_API_BASE_URL  Optional compile-time API base URL passed through to
                          the Flutter web build via scripts/build_mobile_web_deploy.sh
  PRODUCTION_API_BASE_URL Default API base URL used when INTERCITY_API_BASE_URL
                          is not set. Default: $PRODUCTION_API_BASE_URL

Example:
  INTERCITY_API_BASE_URL="https://api.example.com/api" \\
  bash scripts/deploy_mobile_web_firebase_rest.sh
EOF
}

if [[ "${1:-}" == "--help" ]]; then
  show_help
  exit 0
fi

if [[ -z "${INTERCITY_API_BASE_URL:-}" ]]; then
  export INTERCITY_API_BASE_URL="$PRODUCTION_API_BASE_URL"
  echo "INFO: INTERCITY_API_BASE_URL is not set. Falling back to production API: $INTERCITY_API_BASE_URL" >&2
fi

if [[ "$BUILD_BEFORE_DEPLOY" == "1" ]]; then
  bash "$ROOT_DIR/scripts/build_mobile_web_deploy.sh"
fi

if [[ ! -d "$PUBLIC_DIR" ]]; then
  echo "Web deploy directory not found: $PUBLIC_DIR" >&2
  exit 1
fi

ACCESS_TOKEN="$(
  CLOUDSDK_CORE_ACCOUNT="$GCLOUD_ACCOUNT" \
    gcloud auth print-access-token
)"
GOOGLE_QUOTA_PROJECT_HEADER="X-Goog-User-Project: $SITE_ID"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

HASH_MAP_FILE="$TMP_DIR/hash_map.tsv"
FILE_HASHES_FILE="$TMP_DIR/file_hashes.tsv"
touch "$HASH_MAP_FILE" "$FILE_HASHES_FILE"

while IFS= read -r -d '' file_path; do
  relative_path="${file_path#$PUBLIC_DIR/}"
  hosting_path="/$relative_path"
  gzip_path="$TMP_DIR/${relative_path//\//__}.gz"
  gzip -n -c "$file_path" > "$gzip_path"
  file_hash="$(shasum -a 256 "$gzip_path" | awk '{print $1}')"
  printf '%s\t%s\n' "$file_hash" "$gzip_path" >> "$HASH_MAP_FILE"
  printf '%s\t%s\n' "$hosting_path" "$file_hash" >> "$FILE_HASHES_FILE"
done < <(find "$PUBLIC_DIR" -type f ! -name '.last_build_id' -print0 | sort -z)

FILES_JSON="$(
  cat "$FILE_HASHES_FILE" | jq -Rn '
    [inputs | select(length > 0) | split("\t")]
    | reduce .[] as $entry ({}; . + {($entry[0]): $entry[1]})
  '
)"

VERSION_PAYLOAD='{
  "config": {
    "headers": [
      {
        "glob": "**",
        "headers": {
          "Cache-Control": "no-cache, no-store, max-age=0, must-revalidate"
        }
      }
    ],
    "rewrites": [
      {
        "glob": "**",
        "path": "/index.html"
      }
    ]
  }
}'

VERSION_RESPONSE="$(
  curl -sf \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "$GOOGLE_QUOTA_PROJECT_HEADER" \
    -H 'Content-Type: application/json' \
    -X POST \
    -d "$VERSION_PAYLOAD" \
    "https://firebasehosting.googleapis.com/v1beta1/sites/$SITE_ID/versions"
)"

VERSION_NAME="$(echo "$VERSION_RESPONSE" | jq -r '.name')"
if [[ -z "$VERSION_NAME" || "$VERSION_NAME" == "null" ]]; then
  echo "Failed to create Firebase Hosting version." >&2
  echo "$VERSION_RESPONSE" >&2
  exit 1
fi

POPULATE_PAYLOAD="$(jq -n --argjson files "$FILES_JSON" '{files: $files}')"
POPULATE_RESPONSE="$(
  curl -sf \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "$GOOGLE_QUOTA_PROJECT_HEADER" \
    -H 'Content-Type: application/json' \
    -X POST \
    -d "$POPULATE_PAYLOAD" \
    "https://firebasehosting.googleapis.com/v1beta1/$VERSION_NAME:populateFiles"
)"

while IFS= read -r required_hash; do
  [[ -z "$required_hash" ]] && continue
  gzip_file="$(
    awk -F '\t' -v required_hash="$required_hash" '
      $1 == required_hash { print $2; exit }
    ' "$HASH_MAP_FILE"
  )"
  if [[ -z "$gzip_file" || ! -f "$gzip_file" ]]; then
    echo "Missing prepared upload for hash $required_hash" >&2
    exit 1
  fi

  curl -sf \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "$GOOGLE_QUOTA_PROJECT_HEADER" \
    -H 'Content-Type: application/octet-stream' \
    -X POST \
    --data-binary @"$gzip_file" \
    "https://upload-firebasehosting.googleapis.com/upload/$VERSION_NAME/files/$required_hash" \
    >/dev/null
done < <(echo "$POPULATE_RESPONSE" | jq -r '.uploadRequiredHashes[]?')

curl -sf \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "$GOOGLE_QUOTA_PROJECT_HEADER" \
  -H 'Content-Type: application/json' \
  -X PATCH \
  -d '{"status":"FINALIZED"}' \
  "https://firebasehosting.googleapis.com/v1beta1/$VERSION_NAME?update_mask=status" \
  >/dev/null

ENCODED_VERSION_NAME="${VERSION_NAME//\//%2F}"
RELEASE_RESPONSE="$(
  curl -sf \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "$GOOGLE_QUOTA_PROJECT_HEADER" \
    -X POST \
    "https://firebasehosting.googleapis.com/v1beta1/sites/$SITE_ID/releases?versionName=$ENCODED_VERSION_NAME"
)"

echo "$RELEASE_RESPONSE" | jq .
echo "Hosting URL: https://$SITE_ID.web.app"
