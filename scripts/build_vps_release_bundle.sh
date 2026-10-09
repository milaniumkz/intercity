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

# The GitHub event's parent may have never been published (CI-only commits,
# cancelled/failed builds). Read the last published marker; the SSH deployment
# still verifies this exact marker and every changed source hash before writes.
BASE_COMMIT_SHA="${BASE_COMMIT_SHA:-$(python3 - <<'PYBASE'
import json, os, re, urllib.request
web_url = os.environ.get('PRODUCTION_WEB_URL', 'https://intercity.89-207-255-27.sslip.io').rstrip('/')
with urllib.request.urlopen(web_url + '/version.json', timeout=15) as response:
    base = json.load(response).get('commit', '')
if not re.fullmatch(r'[0-9a-f]{40}', base):
    raise SystemExit('Invalid production release marker')
print(base)
PYBASE
)}"
git cat-file -e "$BASE_COMMIT_SHA^{commit}" 2>/dev/null || git fetch --depth=1 origin "$BASE_COMMIT_SHA"
if [[ "$(git rev-parse --is-shallow-repository)" == "true" ]]; then
  git fetch --unshallow origin
fi
git merge-base --is-ancestor "$BASE_COMMIT_SHA" HEAD || {
  echo 'Published production commit is not an ancestor of this release' >&2
  exit 1
}

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

# Package committed source, not lockfiles/registrants rewritten by build tools.
# Compiled outputs remain alongside the exact source snapshot.
python3 - "$ROOT_DIR" "$STAGE_DIR/intercity" <<'PYSOURCE'
from pathlib import Path
import subprocess, sys
root, stage = map(Path, sys.argv[1:])
changed = subprocess.check_output(['git', '-C', str(root), 'diff', '--name-only', '-z', 'HEAD']).split(b'\0')
for raw in changed:
    if not raw:
        continue
    name = raw.decode()
    target = stage / name
    if target.is_file() and not name.startswith('.github/'):
        original = subprocess.run(['git', '-C', str(root), 'show', 'HEAD:' + name], capture_output=True)
        if original.returncode == 0:
            target.write_bytes(original.stdout)
PYSOURCE

python3 "$ROOT_DIR/scripts/vps_release_manifest.py" create \
  "$BASE_COMMIT_SHA" "$STAGE_DIR/intercity/.release-manifest.json"

tar -C "$STAGE_DIR" -czf "$BUNDLE" intercity
shasum -a 256 "$BUNDLE" > "$BUNDLE.sha256"
echo "$BUNDLE"
