#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib/flutter_release_helpers.sh"
resolve_flutter_bin

INTERCITY_API_BASE_URL="${INTERCITY_API_BASE_URL:-https://api.intercity.89-207-255-27.sslip.io/api}"
if [[ "$INTERCITY_API_BASE_URL" != https://* || "$INTERCITY_API_BASE_URL" == *'.invalid'* ]]; then
  echo "Release requires a real HTTPS API URL" >&2
  exit 1
fi
# Probe the backend itself, rather than Caddy's static /health response.
curl --fail --silent --show-error --max-time 30 \
  "${INTERCITY_API_BASE_URL%/}/geo/cities" > /dev/null

cd "$ROOT_DIR/apps/mobile_flutter"
# Native asset hooks can retain simulator frameworks between iOS targets.
# A release must regenerate them for physical devices before archiving.
"$FLUTTER_BIN" clean
"$FLUTTER_BIN" pub get
"$FLUTTER_BIN" build ipa --release \
  "--dart-define=INTERCITY_API_BASE_URL=$INTERCITY_API_BASE_URL" "$@"
