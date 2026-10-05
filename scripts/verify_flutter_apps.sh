#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib/flutter_release_helpers.sh"

RUN_WEB_BUILDS="${RUN_WEB_BUILDS:-1}"
RUN_MACOS_SMOKE="${RUN_MACOS_SMOKE:-auto}"
VERIFY_MOBILE="${VERIFY_MOBILE:-1}"
VERIFY_ADMIN="${VERIFY_ADMIN:-1}"

resolve_flutter_bin

show_help() {
  cat <<EOF
Verifies INTERCITY Flutter targets with a reproducible command sequence.

Environment variables:
  FLUTTER_BIN      Flutter executable path. Defaults to local SDK path when
                   present, otherwise falls back to "flutter" from PATH.
  RUN_WEB_BUILDS   1 to run web builds, 0 to skip them. Default: 1
  RUN_MACOS_SMOKE  auto, 1, or 0. Default: auto
  VERIFY_MOBILE    1 to verify apps/mobile_flutter, 0 to skip. Default: 1
  VERIFY_ADMIN     1 to verify apps/admin_web, 0 to skip. Default: 1

Examples:
  bash scripts/verify_flutter_apps.sh
  RUN_MACOS_SMOKE=0 bash scripts/verify_flutter_apps.sh
  VERIFY_ADMIN=0 bash scripts/verify_flutter_apps.sh
EOF
}

if [[ "${1:-}" == "--help" ]]; then
  show_help
  exit 0
fi

run_in_dir() {
  local dir="$1"
  shift
  (
    cd "$dir"
    "$@"
  )
}

should_run_macos_smoke() {
  case "$RUN_MACOS_SMOKE" in
    1) return 0 ;;
    0) return 1 ;;
    auto)
      [[ "$(uname -s)" == "Darwin" ]]
      ;;
    *)
      echo "Unsupported RUN_MACOS_SMOKE value: $RUN_MACOS_SMOKE" >&2
      exit 1
      ;;
  esac
}

verify_mobile() {
  local dir="$ROOT_DIR/apps/mobile_flutter"
  echo "==> Verifying apps/mobile_flutter"
  run_in_dir "$dir" "$FLUTTER_BIN" pub get
  run_in_dir "$dir" "$FLUTTER_BIN" analyze
  run_in_dir "$dir" "$FLUTTER_BIN" test
  if should_run_macos_smoke; then
    run_in_dir "$dir" "$FLUTTER_BIN" test integration_test/app_smoke_test.dart -d macos
  fi
  if [[ "$RUN_WEB_BUILDS" == "1" ]]; then
    run_in_dir "$dir" "$FLUTTER_BIN" build web
  fi
}

verify_admin() {
  local dir="$ROOT_DIR/apps/admin_web"
  echo "==> Verifying apps/admin_web"
  run_in_dir "$dir" "$FLUTTER_BIN" pub get
  run_in_dir "$dir" "$FLUTTER_BIN" analyze
  run_in_dir "$dir" "$FLUTTER_BIN" test
  if [[ "$RUN_WEB_BUILDS" == "1" ]]; then
    run_in_dir "$dir" "$FLUTTER_BIN" build web
  fi
}

if [[ "$VERIFY_MOBILE" == "1" ]]; then
  verify_mobile
fi

if [[ "$VERIFY_ADMIN" == "1" ]]; then
  verify_admin
fi
