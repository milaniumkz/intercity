#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${INTERCITY_SMOKE_API_BASE_URL:-https://intercity-backend-176647550231.us-central1.run.app/api}"
ADMIN_PHONE="${INTERCITY_SMOKE_ADMIN_PHONE:-+70000000000}"
ADMIN_PASSWORD="${INTERCITY_SMOKE_ADMIN_PASSWORD:-}"
SEARCH_TERM="${SEARCH_TERM:-QA_TEST_}"
NAME_PREFIX="${NAME_PREFIX:-QA_TEST_}"
ROLE_FILTER="${ROLE_FILTER:-}"
DRY_RUN="${DRY_RUN:-0}"

CURL_BIN="${CURL_BIN:-$(command -v curl)}"
JQ_BIN="${JQ_BIN:-$(command -v jq)}"

API_BODY=""
API_STATUS=""
ADMIN_TOKEN=""
CLEANUP_REASON=""
PROCESSED_COUNT=0
SKIPPED_COUNT=0

show_help() {
  cat <<EOF
Safely cleans legacy QA_TEST users from production by attempting admin safe-delete
and falling back to anonymization for users blocked by legacy relations.

Environment variables:
  INTERCITY_SMOKE_API_BASE_URL   API base URL. Default: $BASE_URL
  INTERCITY_SMOKE_ADMIN_PHONE    Admin phone used for cleanup.
                                 Default: $ADMIN_PHONE
  INTERCITY_SMOKE_ADMIN_PASSWORD Admin password used for cleanup.
  SEARCH_TERM                    User search term. Default: $SEARCH_TERM
  NAME_PREFIX                    Required user.name prefix. Default: $NAME_PREFIX
  ROLE_FILTER                    Optional role filter: PASSENGER or DRIVER.
  DRY_RUN                        1 to print matching users without changing them.
                                 Default: $DRY_RUN

Example:
  bash scripts/cleanup_prod_qa_users.sh
  SEARCH_TERM=QA_TEST_DRIVER_ bash scripts/cleanup_prod_qa_users.sh
  DRY_RUN=1 bash scripts/cleanup_prod_qa_users.sh
EOF
}

if [[ "${1:-}" == "--help" ]]; then
  show_help
  exit 0
fi

require_bin() {
  local bin_path="$1"
  local label="$2"
  if [[ -z "$bin_path" || ! -x "$bin_path" ]]; then
    echo "Missing required binary: $label" >&2
    exit 1
  fi
}

require_bin "$CURL_BIN" "curl"
require_bin "$JQ_BIN" "jq"

if [[ -z "$ADMIN_PASSWORD" ]]; then
  echo "Set INTERCITY_SMOKE_ADMIN_PASSWORD." >&2
  exit 1
fi

call_api() {
  local method="$1"
  local path="$2"
  local data="${3:-}"
  local token="${4:-}"
  local tmp_file
  tmp_file="$(mktemp)"

  local args=(
    -sS
    -X "$method"
    "$BASE_URL/$path"
    -H "content-type: application/json"
  )

  if [[ -n "$token" ]]; then
    args+=(-H "authorization: Bearer $token")
  fi

  if [[ -n "$data" ]]; then
    args+=(--data "$data")
  fi

  API_STATUS="$("$CURL_BIN" "${args[@]}" -o "$tmp_file" -w "%{http_code}")"
  API_BODY="$(cat "$tmp_file")"
  rm -f "$tmp_file"
}

assert_status_one_of() {
  local context="$1"
  shift
  local expected
  for expected in "$@"; do
    if [[ "$API_STATUS" == "$expected" ]]; then
      return 0
    fi
  done
  echo "Unexpected HTTP status for $context: got $API_STATUS" >&2
  echo "$API_BODY" >&2
  exit 1
}

json_build() {
  "$JQ_BIN" -cn "$@"
}

driver_profile_id_for_user() {
  local user_id="$1"
  call_api GET "admin/collections/DriverProfile?take=500" "" "$ADMIN_TOKEN"
  assert_status_one_of "list driver profiles" 200
  printf '%s' "$API_BODY" | "$JQ_BIN" -r --arg userId "$user_id" '
    map(select(.userId == $userId)) | .[0].id // empty
  '
}

driver_online_id_for_profile() {
  local driver_profile_id="$1"
  [[ -z "$driver_profile_id" ]] && return 0
  call_api GET "admin/collections/DriverOnline?take=500" "" "$ADMIN_TOKEN"
  assert_status_one_of "list driver online records" 200
  printf '%s' "$API_BODY" | "$JQ_BIN" -r --arg driverId "$driver_profile_id" '
    map(select(.driverId == $driverId)) | .[0].id // empty
  '
}

anonymize_qa_user() {
  local user_id="$1"
  local role="$2"
  local driver_profile_id="$3"
  local driver_online_id="$4"

  local short_id="${user_id%%-*}"
  local deleted_phone="deleted_${short_id}_$(date +%Y%m%d%H%M%S)"
  local deleted_name="DELETED_QA_${role}_${short_id}"
  local deleted_ref_code="DEL${short_id}$(date +%m%d%H%M%S)"

  if [[ -n "$driver_online_id" ]]; then
    local online_payload
    online_payload="$(json_build '{isOnline:false}')"
    call_api PATCH "admin/collections/DriverOnline/$driver_online_id" "$online_payload" "$ADMIN_TOKEN"
    assert_status_one_of "set driver offline before anonymization" 200 201
  fi

  if [[ -n "$driver_profile_id" ]]; then
    local driver_payload
    driver_payload="$(json_build \
      --arg carNumber "DELETED-${short_id}" \
      '{status:"DELETED",carModel:null,carNumber:$carNumber}')"
    call_api PATCH "admin/collections/DriverProfile/$driver_profile_id" "$driver_payload" "$ADMIN_TOKEN"
    assert_status_one_of "anonymize driver profile" 200 201
  fi

  local user_payload
  user_payload="$(json_build \
    --arg phone "$deleted_phone" \
    --arg name "$deleted_name" \
    --arg refCode "$deleted_ref_code" \
    --arg refLink "deleted://$user_id" \
    '{
      phone: $phone,
      name: $name,
      refCode: $refCode,
      refLink: $refLink,
      pushToken: null,
      pushPlatform: null,
      pushTokenUpdatedAt: null,
      cityId: null,
      referredBy: null
    }')"
  call_api PATCH "admin/collections/User/$user_id" "$user_payload" "$ADMIN_TOKEN"
  assert_status_one_of "anonymize user" 200 201
}

cleanup_user() {
  local user_id="$1"
  local role="$2"
  local name="$3"
  local driver_profile_id=""
  local driver_online_id=""

  if [[ "$name" != "$NAME_PREFIX"* ]]; then
    printf '==> %s (%s)\n' "$name" "$role"
    echo "    skipped: name does not match required prefix $NAME_PREFIX"
    SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
    return 0
  fi

  if [[ -n "$ROLE_FILTER" && "$role" != "$ROLE_FILTER" ]]; then
    printf '==> %s (%s)\n' "$name" "$role"
    echo "    skipped: role filter is $ROLE_FILTER"
    SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
    return 0
  fi

  PROCESSED_COUNT=$((PROCESSED_COUNT + 1))

  if [[ "$DRY_RUN" == "1" ]]; then
    printf '==> %s (%s)\n' "$name" "$role"
    echo "    dry-run: would cleanup"
    return 0
  fi

  if [[ "$role" == "DRIVER" ]]; then
    driver_profile_id="$(driver_profile_id_for_user "$user_id")"
    driver_online_id="$(driver_online_id_for_profile "$driver_profile_id")"
  fi

  printf '==> %s (%s)\n' "$name" "$role"
  call_api DELETE "admin/users/$user_id?reason=$CLEANUP_REASON" "" "$ADMIN_TOKEN"
  if [[ "$API_STATUS" == "200" || "$API_STATUS" == "201" ]]; then
    echo "    deleted"
    return 0
  fi

  anonymize_qa_user "$user_id" "$role" "$driver_profile_id" "$driver_online_id"
  echo "    anonymized"
}

main() {
  CLEANUP_REASON="QA_TEST_batch_cleanup_$(date +%Y%m%d%H%M%S)"

  call_api POST "auth/login" "$(json_build \
    --arg phone "$ADMIN_PHONE" \
    --arg password "$ADMIN_PASSWORD" \
    '{phone:$phone,password:$password}')" ""
  assert_status_one_of "admin login" 200 201
  ADMIN_TOKEN="$(printf '%s' "$API_BODY" | "$JQ_BIN" -r '.accessToken // empty')"

  call_api GET "admin/users?search=$SEARCH_TERM" "" "$ADMIN_TOKEN"
  assert_status_one_of "search QA users" 200

  local total
  total="$(printf '%s' "$API_BODY" | "$JQ_BIN" -r '.total // 0')"
  if [[ "$total" == "0" ]]; then
    echo "No users matched $SEARCH_TERM"
    exit 0
  fi

  while IFS=$'\t' read -r user_id role name; do
    cleanup_user "$user_id" "$role" "$name"
  done < <(printf '%s' "$API_BODY" | "$JQ_BIN" -r '.items[] | [.id, .role, .name] | @tsv')

  echo "--"
  echo "processed: $PROCESSED_COUNT"
  echo "skipped: $SKIPPED_COUNT"
}

main "$@"
