#!/usr/bin/env bash
# Native macOS checks only: no Docker/Linux services, deployment, or signing.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
[[ "$(uname -s)" == Darwin && "$(uname -m)" == arm64 ]] || {
  echo 'Native verification requires macOS ARM64.' >&2
  exit 1
}
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
for tool in node npm python3 pod xcodebuild; do
  command -v "$tool" >/dev/null || { echo "Missing tool: $tool" >&2; exit 1; }
done
node -e 'if (process.versions.node.split(".")[0] !== "20") process.exit(1)'
"$FLUTTER_BIN" --version --machine | python3 -c '
import json, sys
version = json.load(sys.stdin)["frameworkVersion"]
if version != "3.41.1":
    sys.exit("Expected Flutter 3.41.1; found " + version)
'
# Desktop support is already enabled on this Mac; do not modify shared SDK settings.
unset CURRENCY_TEST_DATABASE_URL
export DATABASE_URL= REDIS_URL=
"$FLUTTER_BIN" doctor -v
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts/tests -p 'test_ci_flutter_paths.py' -v
(
  cd backend
  npm ci
  npx prisma generate
  npm run build
  node --test test/*.test.js
)
FLUTTER_BIN="$FLUTTER_BIN" VERIFY_MOBILE=1 VERIFY_ADMIN=1 \
  RUN_UNIT_TESTS=1 RUN_WEB_BUILDS=1 RUN_MACOS_SMOKE=1 \
  bash scripts/verify_flutter_apps.sh
