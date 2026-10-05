#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/apps/mobile_flutter"
ANDROID_LOCAL_PROPERTIES="$APP_DIR/android/local.properties"
source "$ROOT_DIR/scripts/lib/flutter_release_helpers.sh"

RELEASE_TARGET="${RELEASE_TARGET:-appbundle}"
RUN_PREFLIGHT="${RUN_PREFLIGHT:-1}"
RUN_FLUTTER_BUILD="${RUN_FLUTTER_BUILD:-1}"
INTERCITY_API_BASE_URL="${INTERCITY_API_BASE_URL:-https://intercity-backend-176647550231.us-central1.run.app/api}"

resolve_flutter_bin

wait_for_aab_debug_symbols() {
  local aab_path="$1"
  local attempts="${2:-5}"
  local sleep_seconds="${3:-1}"
  local attempt=1
  local has_symbols=1

  while (( attempt <= attempts )); do
    set +e
    aab_contains_flutter_debug_symbols "$aab_path"
    has_symbols=$?
    set -e

    if [[ "$has_symbols" -eq 0 ]]; then
      return 0
    fi

    sleep "$sleep_seconds"
    ((attempt += 1))
  done

  return 1
}

show_help() {
  cat <<EOF
Builds reproducible Android release artifacts for apps/mobile_flutter.

Environment variables:
  FLUTTER_BIN         Flutter executable path. Defaults to local SDK path when
                      present, otherwise falls back to "flutter" from PATH.
  INTERCITY_ANDROID_RELEASE_KEYSTORE_BASE64
                      Optional base64-encoded keystore content. When set and
                      INTERCITY_ANDROID_RELEASE_KEYSTORE_PATH is absent, the
                      wrapper materializes a temporary keystore file for CI.
  RELEASE_TARGET      appbundle or apk. Default: appbundle
  INTERCITY_API_BASE_URL
                      API base URL compiled into the Flutter app. Defaults to
                      the production Cloud Run API.
  RUN_PREFLIGHT       1 to run release preflight first, 0 to skip. Default: 1
  RUN_FLUTTER_BUILD   1 to run flutter build after preflight, 0 to stop after
                      preflight. Default: 1

Signing environment variables (required unless ALLOW_MISSING_SIGNING=1 is set
for preflight only):
  INTERCITY_ANDROID_RELEASE_KEYSTORE_PATH
  INTERCITY_ANDROID_RELEASE_STORE_PASSWORD
  INTERCITY_ANDROID_RELEASE_KEY_ALIAS
  INTERCITY_ANDROID_RELEASE_KEY_PASSWORD

Examples:
  bash scripts/build_mobile_android_release.sh
  RELEASE_TARGET=apk bash scripts/build_mobile_android_release.sh
  RUN_FLUTTER_BUILD=0 ALLOW_MISSING_SIGNING=1 bash scripts/build_mobile_android_release.sh
EOF
}

if [[ "${1:-}" == "--help" ]]; then
  show_help
  exit 0
fi

case "$RELEASE_TARGET" in
  appbundle)
    flutter_args=(build appbundle --release "--dart-define=INTERCITY_API_BASE_URL=$INTERCITY_API_BASE_URL")
    artifact_path="$APP_DIR/build/app/outputs/bundle/release/app-release.aab"
    ;;
  apk)
    flutter_args=(build apk --release "--dart-define=INTERCITY_API_BASE_URL=$INTERCITY_API_BASE_URL")
    artifact_path="$APP_DIR/build/app/outputs/flutter-apk/app-release.apk"
    ;;
  *)
    echo "Unsupported RELEASE_TARGET: $RELEASE_TARGET" >&2
    exit 1
    ;;
esac

prepare_android_release_keystore_from_base64

if [[ "$RUN_PREFLIGHT" == "1" ]]; then
  bash "$ROOT_DIR/scripts/verify_release_readiness.sh"
fi

if [[ "$RUN_FLUTTER_BUILD" != "1" ]]; then
  exit 0
fi

echo "==> Building Android release artifact ($RELEASE_TARGET)"
rm -f "$artifact_path"

build_log="$(mktemp "${TMPDIR:-/tmp}/intercity-android-release-build.XXXXXX.log")"
trap '_intercity_cleanup_android_release_temp; rm -f "$build_log"' EXIT

set +e
(
  cd "$APP_DIR"
  "$FLUTTER_BIN" "${flutter_args[@]}" 2>&1 | tee "$build_log"
  exit "${PIPESTATUS[0]}"
)
build_exit=$?
set -e

if [[ "$build_exit" -eq 0 ]]; then
  exit 0
fi

if [[ "$RELEASE_TARGET" != "appbundle" ]]; then
  exit "$build_exit"
fi

if ! grep -q "Release app bundle failed to strip debug symbols from native libraries." "$build_log"; then
  exit "$build_exit"
fi

if ! wait_for_aab_debug_symbols "$artifact_path"; then
  exit "$build_exit"
fi

android_sdk_dir="$(resolve_android_sdk_dir "$ANDROID_LOCAL_PROPERTIES" || true)"
if [[ -n "$android_sdk_dir" ]]; then
  set +e
  android_sdk_has_apkanalyzer "$android_sdk_dir"
  has_apkanalyzer=$?
  set -e
  if [[ "$has_apkanalyzer" -eq 0 ]]; then
    exit "$build_exit"
  fi
fi

echo "WARN: Flutter reported a false-negative strip-debug-symbols failure, but the release appbundle exists and contains BUNDLE-METADATA debug symbols." >&2
if [[ -n "$android_sdk_dir" ]]; then
  echo "WARN: Android SDK cmdline-tools/apkanalyzer were not found under: $android_sdk_dir" >&2
fi
echo "WARN: Treating the appbundle build as successful. Prefer this wrapper over raw 'flutter build appbundle' on machines without apkanalyzer." >&2
echo "==> Recovered Android release artifact: $artifact_path"
