#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib/flutter_release_helpers.sh"

STAMP="${GITHUB_SHA:-$(date +%Y%m%d%H%M%S)}"
OUT_DIR="${OUT_DIR:-$ROOT_DIR/output}"
STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/intercity-vps-bundle.XXXXXX")"
BUNDLE="$OUT_DIR/intercity-vps-$STAMP.tar.gz"

cleanup() {
  rm -rf "$STAGE_DIR"
}
trap cleanup EXIT

mkdir -p "$OUT_DIR"
resolve_flutter_bin

echo "==> Backend build"
(cd "$ROOT_DIR/backend" && npm ci && npm run build)

echo "==> Mobile web build"
OUTPUT_DIR="$ROOT_DIR/infra/vps/web/mobile" \
  INTERCITY_API_BASE_URL="${INTERCITY_API_BASE_URL:?INTERCITY_API_BASE_URL is required}" \
  bash "$ROOT_DIR/scripts/build_mobile_web_deploy.sh"

echo "==> Admin web build"
(
  cd "$ROOT_DIR/apps/admin_web"
  "$FLUTTER_BIN" pub get
  "$FLUTTER_BIN" build web --release \
    --no-wasm-dry-run \
    --pwa-strategy=none \
    --dart-define=INTERCITY_API_BASE_URL="${INTERCITY_API_BASE_URL}"
)
rm -rf "$ROOT_DIR/infra/vps/web/admin"
mkdir -p "$ROOT_DIR/infra/vps/web/admin"
cp -R "$ROOT_DIR/apps/admin_web/build/web/." "$ROOT_DIR/infra/vps/web/admin/"

cat > "$ROOT_DIR/infra/vps/web/mobile/version.json" <<JSON
{"commit":"$STAMP","builtAt":"$(date -u +%Y-%m-%dT%H:%M:%SZ)"}
JSON
cp "$ROOT_DIR/infra/vps/web/mobile/version.json" "$ROOT_DIR/infra/vps/web/admin/version.json"

echo "==> Package release bundle"
rsync -a --delete \
  --exclude='.git' \
  --exclude='.github' \
  --exclude='.DS_Store' \
  --exclude='**/node_modules' \
  --exclude='**/.dart_tool' \
  --exclude='**/build' \
  --exclude='output' \
  --exclude='releases' \
  --exclude='uploads' \
  --exclude='.playwright-cli' \
  --exclude='.playwright-mcp' \
  --exclude='*.jks' \
  --exclude='*.keystore' \
  --exclude='*.p8' \
  --exclude='*.ipa' \
  --exclude='*.apk' \
  --exclude='*.aab' \
  --exclude='infra/vps/.env' \
  --exclude='infra/vps/.env.tmp' \
  "$ROOT_DIR/" "$STAGE_DIR/intercity/"

tar -C "$STAGE_DIR" -czf "$BUNDLE" intercity
shasum -a 256 "$BUNDLE" > "$BUNDLE.sha256"
echo "$BUNDLE"
