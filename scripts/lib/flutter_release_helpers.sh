#!/usr/bin/env bash

resolve_flutter_bin() {
  local default_flutter_bin="${1:-/Volumes/PD1000/job/flutter/bin/flutter}"

  if [[ -n "${FLUTTER_BIN:-}" ]]; then
    export FLUTTER_BIN
    return 0
  fi

  if [[ -x "$default_flutter_bin" ]]; then
    FLUTTER_BIN="$default_flutter_bin"
  else
    FLUTTER_BIN="flutter"
  fi

  export FLUTTER_BIN
}

_intercity_cleanup_android_release_temp() {
  if [[ -n "${_INTERCITY_ANDROID_RELEASE_TEMP_DIR:-}" &&
        -d "${_INTERCITY_ANDROID_RELEASE_TEMP_DIR:-}" ]]; then
    rm -rf "$_INTERCITY_ANDROID_RELEASE_TEMP_DIR"
  fi
}

_intercity_decode_base64_to_file() {
  local output_path="$1"

  if base64 --help 2>&1 | grep -q -- '--decode'; then
    printf '%s' "$INTERCITY_ANDROID_RELEASE_KEYSTORE_BASE64" |
      base64 --decode > "$output_path"
  else
    printf '%s' "$INTERCITY_ANDROID_RELEASE_KEYSTORE_BASE64" |
      base64 -D > "$output_path"
  fi
}

prepare_android_release_keystore_from_base64() {
  if [[ -n "${INTERCITY_ANDROID_RELEASE_KEYSTORE_PATH:-}" ||
        -z "${INTERCITY_ANDROID_RELEASE_KEYSTORE_BASE64:-}" ]]; then
    return 0
  fi

  if [[ -n "${_INTERCITY_ANDROID_RELEASE_TEMP_DIR:-}" ]]; then
    return 0
  fi

  _INTERCITY_ANDROID_RELEASE_TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/intercity-android-release.XXXXXX")"
  export _INTERCITY_ANDROID_RELEASE_TEMP_DIR

  local keystore_path="$_INTERCITY_ANDROID_RELEASE_TEMP_DIR/release.keystore"
  _intercity_decode_base64_to_file "$keystore_path"
  chmod 600 "$keystore_path"
  export INTERCITY_ANDROID_RELEASE_KEYSTORE_PATH="$keystore_path"

  trap _intercity_cleanup_android_release_temp EXIT
}

resolve_android_sdk_dir() {
  local local_properties_path="${1:-}"
  local sdk_dir=""

  if [[ -n "${ANDROID_SDK_ROOT:-}" && -d "${ANDROID_SDK_ROOT:-}" ]]; then
    sdk_dir="$ANDROID_SDK_ROOT"
  elif [[ -n "${ANDROID_HOME:-}" && -d "${ANDROID_HOME:-}" ]]; then
    sdk_dir="$ANDROID_HOME"
  elif [[ -n "$local_properties_path" && -f "$local_properties_path" ]]; then
    sdk_dir="$(sed -n 's/^sdk.dir=//p' "$local_properties_path" | tail -n 1)"
  fi

  if [[ -z "$sdk_dir" ]]; then
    return 1
  fi

  printf '%s\n' "$sdk_dir"
}

android_sdk_has_apkanalyzer() {
  local sdk_dir="${1:-}"

  if [[ -z "$sdk_dir" || ! -d "$sdk_dir" ]]; then
    return 1
  fi

  find "$sdk_dir/cmdline-tools" -type f \
    \( -name apkanalyzer -o -name apkanalyzer.bat \) \
    -print -quit 2>/dev/null | grep -q .
}

aab_contains_flutter_debug_symbols() {
  local aab_path="${1:-}"
  local archive_entries=""

  if [[ -z "$aab_path" || ! -f "$aab_path" ]]; then
    return 1
  fi

  if ! command -v unzip >/dev/null 2>&1; then
    return 1
  fi

  archive_entries="$(unzip -Z1 "$aab_path")" || return 1
  grep -Eq '^BUNDLE-METADATA/.*/libflutter\.so\.(sym|dbg)$' <<<"$archive_entries"
}
