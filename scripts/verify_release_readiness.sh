#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/apps/mobile_flutter"
GRADLE_FILE="$APP_DIR/android/app/build.gradle.kts"
ANDROID_LOCAL_PROPERTIES="$APP_DIR/android/local.properties"
source "$ROOT_DIR/scripts/lib/flutter_release_helpers.sh"

RUN_APPBUNDLE_BUILD="${RUN_APPBUNDLE_BUILD:-0}"
ALLOW_MISSING_SIGNING="${ALLOW_MISSING_SIGNING:-0}"

required_env_vars=(
  INTERCITY_ANDROID_RELEASE_KEYSTORE_PATH
  INTERCITY_ANDROID_RELEASE_STORE_PASSWORD
  INTERCITY_ANDROID_RELEASE_KEY_ALIAS
  INTERCITY_ANDROID_RELEASE_KEY_PASSWORD
)

show_help() {
  cat <<EOF
Verifies Android release readiness for apps/mobile_flutter.

Checks:
  - production-safe namespace/applicationId
  - release minify/shrinkResources enabled
  - release build is not wired to debug signing
  - env-based signing variables are configured
  - keystore path exists and is readable

Environment variables:
  INTERCITY_ANDROID_RELEASE_KEYSTORE_BASE64
                        Optional base64-encoded keystore content. When set and
                        INTERCITY_ANDROID_RELEASE_KEYSTORE_PATH is absent, the
                        script materializes a temporary keystore file for CI.
  ALLOW_MISSING_SIGNING  1 to downgrade missing signing env vars to a warning.
                         Default: 0
  RUN_APPBUNDLE_BUILD    1 to run 'flutter build appbundle --release' after
                         preflight checks pass through the release wrapper.
                         Default: 0
  FLUTTER_BIN            Optional Flutter executable path for build step.

Examples:
  bash scripts/verify_release_readiness.sh
  ALLOW_MISSING_SIGNING=1 bash scripts/verify_release_readiness.sh
  RUN_APPBUNDLE_BUILD=1 bash scripts/verify_release_readiness.sh
EOF
}

if [[ "${1:-}" == "--help" ]]; then
  show_help
  exit 0
fi

if [[ ! -f "$GRADLE_FILE" ]]; then
  echo "Release readiness check failed: missing $GRADLE_FILE" >&2
  exit 1
fi

resolve_flutter_bin
prepare_android_release_keystore_from_base64

warn() {
  echo "WARN: $*" >&2
}

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

require_pattern() {
  local pattern="$1"
  local file="$2"
  local message="$3"
  if ! rg -q "$pattern" "$file"; then
    fail "$message"
  fi
}

reject_pattern() {
  local pattern="$1"
  local file="$2"
  local message="$3"
  if rg -q "$pattern" "$file"; then
    fail "$message"
  fi
}

echo "==> Checking Android release config"
reject_pattern 'namespace\s*=\s*"com\.example\.' "$GRADLE_FILE" \
  "android namespace still uses com.example placeholder"
reject_pattern 'applicationId\s*=\s*"com\.example\.' "$GRADLE_FILE" \
  "android applicationId still uses com.example placeholder"
require_pattern 'namespace\s*=\s*"com\.milanium\.intercity"' "$GRADLE_FILE" \
  "expected production-safe namespace com.milanium.intercity"
require_pattern 'applicationId\s*=\s*"com\.milanium\.intercity"' "$GRADLE_FILE" \
  "expected production-safe applicationId com.milanium.intercity"
require_pattern 'isMinifyEnabled\s*=\s*true' "$GRADLE_FILE" \
  "release minify is not enabled"
require_pattern 'isShrinkResources\s*=\s*true' "$GRADLE_FILE" \
  "release shrinkResources is not enabled"
reject_pattern 'signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)' "$GRADLE_FILE" \
  "release build still uses debug signing"
require_pattern 'INTERCITY_ANDROID_RELEASE_KEYSTORE_PATH' "$GRADLE_FILE" \
  "release signing env vars are not wired into Gradle config"

echo "==> Checking signing environment"
missing_env=()
for env_name in "${required_env_vars[@]}"; do
  if [[ -z "${!env_name:-}" ]]; then
    missing_env+=("$env_name")
  fi
done

if (( ${#missing_env[@]} > 0 )); then
  if [[ "$ALLOW_MISSING_SIGNING" == "1" ]]; then
    warn "missing release signing env vars: ${missing_env[*]}"
  else
    fail "missing release signing env vars: ${missing_env[*]}"
  fi
fi

keystore_path="${INTERCITY_ANDROID_RELEASE_KEYSTORE_PATH:-}"
if [[ -n "$keystore_path" ]]; then
  if [[ ! -f "$keystore_path" ]]; then
    fail "release keystore file does not exist: $keystore_path"
  fi
  if [[ ! -r "$keystore_path" ]]; then
    fail "release keystore file is not readable: $keystore_path"
  fi
fi

google_services_paths=(
  "$APP_DIR/android/app/google-services.json"
  "$APP_DIR/android/app/src/debug/google-services.json"
  "$APP_DIR/android/app/src/release/google-services.json"
)

has_google_services=0
for candidate in "${google_services_paths[@]}"; do
  if [[ -f "$candidate" ]]; then
    has_google_services=1
    break
  fi
done

if [[ "$has_google_services" == "0" ]]; then
  warn "google-services.json not found; release build will skip Google Services plugin"
fi

android_sdk_dir="$(resolve_android_sdk_dir "$ANDROID_LOCAL_PROPERTIES" || true)"
if [[ -z "$android_sdk_dir" ]]; then
  warn "Android SDK path was not resolved; direct 'flutter build appbundle' may fail toolchain post-checks on this machine"
elif ! android_sdk_has_apkanalyzer "$android_sdk_dir"; then
  warn "Android SDK cmdline-tools/apkanalyzer not found under $android_sdk_dir; raw 'flutter build appbundle' may false-fail after producing a valid .aab. Use scripts/build_mobile_android_release.sh instead."
fi

echo "==> Android release preflight passed"

if [[ "$RUN_APPBUNDLE_BUILD" != "1" ]]; then
  exit 0
fi

echo "==> Building release appbundle"
RUN_PREFLIGHT=0 RELEASE_TARGET=appbundle bash "$ROOT_DIR/scripts/build_mobile_android_release.sh"
