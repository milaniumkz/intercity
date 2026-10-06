#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib/flutter_release_helpers.sh"

# Use checkout identity, including manual inputs.ref; GITHUB_SHA identifies the event.
STAMP="$(git -C "$ROOT_DIR" rev-parse HEAD)"
OUT_DIR="${OUT_DIR:-$ROOT_DIR/output}"
STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/intercity-vps-bundle.XXXXXX")"
BUNDLE="$OUT_DIR/intercity-vps-$STAMP.tar.gz"

cleanup() {
  rm -rf "$STAGE_DIR"
}
trap cleanup EXIT

mkdir -p "$OUT_DIR"
resolve_flutter_bin

BASE_COMMIT_SHA="${BASE_COMMIT_SHA:-$(python3 - <<'PY'
import json, os, subprocess
event_path = os.environ.get('GITHUB_EVENT_PATH')
event = json.load(open(event_path)) if event_path else {}
base = event.get('before', '')
if not base or set(base) == {'0'}:
    commit = subprocess.check_output(['git', 'cat-file', '-p', 'HEAD']).decode()
    base = next(line.split()[1] for line in commit.splitlines() if line.startswith('parent '))
print(base)
PY
)}"
git cat-file -e "$BASE_COMMIT_SHA^{commit}" 2>/dev/null || git fetch --depth=1 origin "$BASE_COMMIT_SHA"

echo "==> Backend build"
(cd "$ROOT_DIR/backend" && npm ci && npm run build)
(cd "$ROOT_DIR/backend" && node --test test/*.test.js)

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

# Both web clients must retire older Flutter service workers on release.
python3 - "$ROOT_DIR/infra/vps/web" <<'PYWEB'
from pathlib import Path
import re, sys
web = Path(sys.argv[1])
mobile = (web / 'mobile/index.html').read_text()
reset = re.search(r'<script id="intercity-cache-reset">.*?</script>', mobile, re.S).group()
index = web / 'admin/index.html'
text = re.sub(r'\s*<script id="intercity-cache-reset">.*?</script>', '', index.read_text(), flags=re.S)
text = re.sub(r'\s*<script src="flutter_bootstrap\.js(?:\?v=[^"]*)?" async=""></script>', '', text)
index.write_text(text.replace('</head>', reset + '\n</head>'))
(web / 'admin/flutter_service_worker.js').write_bytes((web / 'mobile/flutter_service_worker.js').read_bytes())
PYWEB

cat > "$ROOT_DIR/infra/vps/web/mobile/version.json" <<JSON
{"commit":"$STAMP","builtAt":"$(date -u +%Y-%m-%dT%H:%M:%SZ)"}
JSON
cp "$ROOT_DIR/infra/vps/web/mobile/version.json" "$ROOT_DIR/infra/vps/web/admin/version.json"

echo "==> Package release bundle"
rsync -a --delete \
  --exclude='.git' \
  --include='**/.env.example' \
  --exclude='**/.env*' \
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

python3 "$ROOT_DIR/scripts/vps_release_manifest.py" create \
  "$BASE_COMMIT_SHA" "$STAGE_DIR/intercity/.release-manifest.json"

tar -C "$STAGE_DIR" -czf "$BUNDLE" intercity
shasum -a 256 "$BUNDLE" > "$BUNDLE.sha256"
echo "$BUNDLE"
