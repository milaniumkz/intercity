#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${INTERCITY_SMOKE_API_BASE_URL:-https://intercity-backend-176647550231.us-central1.run.app/api}"
ADMIN_PHONE="${INTERCITY_SMOKE_ADMIN_PHONE:-+70000000000}"
ADMIN_PASSWORD="${INTERCITY_SMOKE_ADMIN_PASSWORD:-}"
QA_PASSWORD="${INTERCITY_SMOKE_QA_PASSWORD:-}"
RUN_CLEANUP="${RUN_CLEANUP:-1}"
CLEANUP_USERS="${CLEANUP_USERS:-0}"

CURL_BIN="${CURL_BIN:-$(command -v curl)}"
JQ_BIN="${JQ_BIN:-$(command -v jq)}"

API_BODY=""
API_STATUS=""
QA_TIMESTAMP=""
PASSENGER_PHONE=""
DRIVER_PHONE=""
PASSENGER_USER_ID=""
DRIVER_USER_ID=""
PASSENGER_TOKEN=""
DRIVER_TOKEN=""
ADMIN_TOKEN=""
DRIVER_CITY_ID=""
DRIVER_PROFILE_ID=""
CITY_ORDER_ID=""
CITY_AUCTION_REQUEST_ID=""
CITY_AUCTION_OFFER_ID=""
DELIVERY_REQUEST_ID=""
DELIVERY_OFFER_ID=""
INTERCITY_REQUEST_ID=""

show_help() {
  cat <<EOF
Runs a production API smoke flow for INTERCITY with fresh QA_TEST accounts.

Environment variables:
  INTERCITY_SMOKE_API_BASE_URL   API base URL. Default: $BASE_URL
  INTERCITY_SMOKE_ADMIN_PHONE    Admin phone used for driver approval.
                                 Default: $ADMIN_PHONE
  INTERCITY_SMOKE_ADMIN_PASSWORD Admin password used for driver approval.
  INTERCITY_SMOKE_QA_PASSWORD    Password for fresh QA accounts.
                                 Default: $QA_PASSWORD
  RUN_CLEANUP                    1 to cancel open QA requests and set the
                                 QA driver offline after the smoke run.
                                 Default: $RUN_CLEANUP
  CLEANUP_USERS                  1 to delete the fresh QA passenger and driver
                                 through admin safe-delete after the smoke run.
                                 Default: $CLEANUP_USERS

Examples:
  bash scripts/smoke_prod_core.sh
  RUN_CLEANUP=0 bash scripts/smoke_prod_core.sh
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

if [[ -z "$ADMIN_PASSWORD" || -z "$QA_PASSWORD" ]]; then
  echo "Set INTERCITY_SMOKE_ADMIN_PASSWORD and INTERCITY_SMOKE_QA_PASSWORD." >&2
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

assert_status() {
  local expected="$1"
  local context="$2"
  if [[ "$API_STATUS" != "$expected" ]]; then
    echo "Unexpected HTTP status for $context: expected $expected, got $API_STATUS" >&2
    echo "$API_BODY" >&2
    exit 1
  fi
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

json_read() {
  local expr="$1"
  printf '%s' "$API_BODY" | "$JQ_BIN" -r "$expr"
}

json_build() {
  "$JQ_BIN" -cn "$@"
}

log_step() {
  printf '==> %s\n' "$1"
}

generate_phone() {
  local offset="$1"
  local seed
  seed="$(( (10#$(date +%s) + RANDOM + $$ + offset) % 1000000000 ))"
  printf '+77%08d\n' "$seed"
}

cleanup_open_request() {
  local request_id="$1"
  [[ -z "$request_id" ]] && return 0

  call_api POST "intercity/requests/$request_id/cancel" "" "$PASSENGER_TOKEN"
  assert_status_one_of "cancel request $request_id" 200 201
}

cleanup_driver_offline() {
  [[ -z "$DRIVER_TOKEN" || -z "$DRIVER_CITY_ID" ]] && return 0

  local payload
  payload="$(json_build \
    --arg cityId "$DRIVER_CITY_ID" \
    '{isOnline:false, cityId:$cityId}')"
  call_api POST "driver/online" "$payload" "$DRIVER_TOKEN"
  assert_status_one_of "set driver offline" 200 201
}

anonymize_qa_user() {
  local user_id="$1"
  local role_label="$2"
  local driver_profile_id="${3:-}"
  [[ -z "$user_id" ]] && return 0

  local short_id="${user_id%%-*}"
  local deleted_phone="deleted_${short_id}_${QA_TIMESTAMP}"
  local deleted_name="DELETED_QA_${role_label}_${short_id}"
  local deleted_ref_code="DEL${short_id}${QA_TIMESTAMP}"

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
  assert_status_one_of "anonymize QA $role_label user" 200 201

  if [[ -n "$driver_profile_id" ]]; then
    local driver_payload
    driver_payload="$(json_build \
      --arg carNumber "DELETED-${short_id}" \
      '{status:"DELETED",carModel:null,carNumber:$carNumber}')"
    call_api PATCH "admin/collections/DriverProfile/$driver_profile_id" "$driver_payload" "$ADMIN_TOKEN"
    assert_status_one_of "anonymize QA driver profile" 200 201
  fi
}

delete_or_anonymize_qa_user() {
  local user_id="$1"
  local role_label="$2"
  local driver_profile_id="${3:-}"
  [[ -z "$user_id" ]] && return 0

  call_api DELETE "admin/users/$user_id?reason=$encoded_reason" "" "$ADMIN_TOKEN"
  if [[ "$API_STATUS" == "200" || "$API_STATUS" == "201" ]]; then
    return 0
  fi

  anonymize_qa_user "$user_id" "$role_label" "$driver_profile_id"
}

cleanup_users() {
  [[ -z "$ADMIN_TOKEN" ]] && return 0

  encoded_reason="QA_TEST_smoke_cleanup_${QA_TIMESTAMP}"

  delete_collection_item_if_present() {
    local collection="$1"
    local item_id="$2"
    [[ -z "$item_id" ]] && return 0

    call_api DELETE "admin/collections/$collection/$item_id" "" "$ADMIN_TOKEN"
    assert_status_one_of "delete $collection:$item_id" 200 201
  }

  delete_collection_item_if_present "IntercityOffer" "$CITY_AUCTION_OFFER_ID"
  delete_collection_item_if_present "IntercityOffer" "$DELIVERY_OFFER_ID"
  delete_collection_item_if_present "IntercityRequest" "$CITY_AUCTION_REQUEST_ID"
  delete_collection_item_if_present "IntercityRequest" "$DELIVERY_REQUEST_ID"
  delete_collection_item_if_present "IntercityRequest" "$INTERCITY_REQUEST_ID"

  delete_or_anonymize_qa_user "$PASSENGER_USER_ID" "PASSENGER"
  delete_or_anonymize_qa_user "$DRIVER_USER_ID" "DRIVER" "$DRIVER_PROFILE_ID"
}

main() {
  QA_TIMESTAMP="$(date +%Y%m%d%H%M%S)"
  PASSENGER_PHONE="$(generate_phone 1)"
  DRIVER_PHONE="$(generate_phone 2)"

  local passenger_name="QA_TEST_PASSENGER_${QA_TIMESTAMP}"
  local driver_name="QA_TEST_DRIVER_${QA_TIMESTAMP}"

  log_step "Admin login"
  call_api POST "auth/login" "$(json_build \
    --arg phone "$ADMIN_PHONE" \
    --arg password "$ADMIN_PASSWORD" \
    '{phone:$phone,password:$password}')" ""
  assert_status "201" "admin login"
  ADMIN_TOKEN="$(json_read '.accessToken // empty')"

  log_step "Register passenger"
  call_api POST "auth/register" "$(json_build \
    --arg phone "$PASSENGER_PHONE" \
    --arg password "$QA_PASSWORD" \
    --arg name "$passenger_name" \
    '{phone:$phone,password:$password,name:$name}')" ""
  assert_status_one_of "passenger register" 200 201
  PASSENGER_USER_ID="$(json_read '.user.id // empty')"
  PASSENGER_TOKEN="$(json_read '.accessToken // empty')"

  log_step "Register driver"
  call_api POST "auth/register" "$(json_build \
    --arg phone "$DRIVER_PHONE" \
    --arg password "$QA_PASSWORD" \
    --arg name "$driver_name" \
    '{phone:$phone,password:$password,name:$name}')" ""
  assert_status_one_of "driver register" 200 201
  DRIVER_USER_ID="$(json_read '.user.id // empty')"
  DRIVER_TOKEN="$(json_read '.accessToken // empty')"

  log_step "Create driver profile"
  call_api POST "driver/profile" "$(json_build \
    --arg carModel "QA_TEST Toyota Camry" \
    --arg carNumber "777QA02" \
    '{carModel:$carModel,carNumber:$carNumber}')" "$DRIVER_TOKEN"
  assert_status_one_of "driver profile create" 200 201
  DRIVER_PROFILE_ID="$(json_read '.id // empty')"

  log_step "Approve driver"
  call_api POST "admin/drivers/$DRIVER_PROFILE_ID/approve" "$(json_build \
    --arg reason "QA_TEST production smoke" \
    '{reason:$reason}')" "$ADMIN_TOKEN"
  assert_status_one_of "driver approve" 200 201

  log_step "Set driver location and online"
  call_api POST "driver/location" "$(json_build \
    '{lat:49.9489,lng:82.6275}')" "$DRIVER_TOKEN"
  assert_status_one_of "driver location" 200 201
  DRIVER_CITY_ID="$(json_read '.cityId // empty')"
  call_api POST "driver/online" "$(json_build \
    --arg cityId "$DRIVER_CITY_ID" \
    '{isOnline:true, cityId:$cityId}')" "$DRIVER_TOKEN"
  assert_status_one_of "driver online" 200 201

  log_step "City fixed preview"
  call_api POST "orders/preview" "$(json_build \
    '{requestType:"CITY_FIXED",fromLat:49.9489,fromLng:82.6275,fromAddress:"QA_TEST Усть-Каменогорск, вокзал",toLat:49.9690,toLng:82.6140,toAddress:"QA_TEST Усть-Каменогорск, центр",vehicleClass:"COMFORT",paymentMethod:"BONUSES"}')" ""
  assert_status "201" "city fixed preview"
  local city_preview_price
  city_preview_price="$(json_read '.price')"

  log_step "City fixed create / accept / complete"
  call_api POST "orders" "$(json_build \
    '{requestType:"CITY_FIXED",fromLat:49.9489,fromLng:82.6275,fromAddress:"QA_TEST Усть-Каменогорск, вокзал",toLat:49.9690,toLng:82.6140,toAddress:"QA_TEST Усть-Каменогорск, центр",vehicleClass:"COMFORT",paymentMethod:"BONUSES",comment:"QA_TEST city fixed order"}')" "$PASSENGER_TOKEN"
  assert_status_one_of "city fixed create" 200 201
  CITY_ORDER_ID="$(json_read '.id // empty')"

  call_api GET "driver/orders/nearby" "" "$DRIVER_TOKEN"
  assert_status "200" "driver nearby orders"
  local nearby_count
  nearby_count="$(printf '%s' "$API_BODY" | "$JQ_BIN" 'length')"

  call_api POST "driver/orders/$CITY_ORDER_ID/accept" "" "$DRIVER_TOKEN"
  assert_status_one_of "accept city fixed order" 200 201

  local status_payload
  for next_status in DRIVER_ARRIVED IN_PROGRESS COMPLETED; do
    status_payload="$(json_build --arg status "$next_status" '{status:$status}')"
    call_api POST "orders/$CITY_ORDER_ID/status" "$status_payload" "$DRIVER_TOKEN"
    assert_status_one_of "set order status $next_status" 200 201
  done

  call_api POST "orders/$CITY_ORDER_ID/rate" "$(json_build '{rating:5}')" "$PASSENGER_TOKEN"
  assert_status_one_of "rate completed city order" 200 201
  local final_city_status
  final_city_status="$(json_read '.order.status // empty')"
  if [[ -z "$final_city_status" || "$final_city_status" == "null" ]]; then
    final_city_status="COMPLETED"
  fi

  log_step "City auction create / offer / accept"
  call_api POST "intercity/requests" "$(json_build \
    '{requestType:"CITY_AUCTION",fromManualAddress:"QA_TEST Усть-Каменогорск, вокзал",toManualAddress:"QA_TEST Рынок Заречный",fromAddressSource:"MANUAL",toAddressSource:"MANUAL",paymentMethod:"CARD_TRANSFER",comment:"QA_TEST city auction",date:"2026-05-16T12:00:00Z"}')" "$PASSENGER_TOKEN"
  assert_status_one_of "city auction create" 200 201
  CITY_AUCTION_REQUEST_ID="$(json_read '.id // empty')"

  call_api POST "intercity/requests/$CITY_AUCTION_REQUEST_ID/offers" "$(json_build \
    '{price:1800,comment:"QA_TEST city offer"}')" "$DRIVER_TOKEN"
  assert_status_one_of "city auction offer" 200 201
  CITY_AUCTION_OFFER_ID="$(json_read '.id // empty')"

  call_api POST "intercity/offers/$CITY_AUCTION_OFFER_ID/accept" "" "$PASSENGER_TOKEN"
  assert_status_one_of "city auction accept" 200 201

  call_api GET "intercity/requests/$CITY_AUCTION_REQUEST_ID" "" "$PASSENGER_TOKEN"
  assert_status "200" "city auction details"
  local city_auction_status
  city_auction_status="$(json_read '.status // empty')"

  log_step "Delivery validation and offer"
  call_api POST "intercity/requests" "$(json_build \
    '{requestType:"DELIVERY_CITY",fromManualAddress:"QA_TEST склад А",toManualAddress:"QA_TEST склад Б",fromAddressSource:"MANUAL",toAddressSource:"MANUAL",paymentMethod:"BONUSES",itemDescription:"QA_TEST коробка",date:"2026-05-16T13:00:00Z"}')" "$PASSENGER_TOKEN"
  assert_status "400" "delivery bonuses validation"
  local delivery_bonus_error
  delivery_bonus_error="$(json_read '.message // empty')"

  call_api POST "intercity/requests" "$(json_build \
    '{requestType:"DELIVERY_CITY",fromManualAddress:"QA_TEST склад А",toManualAddress:"QA_TEST склад Б",fromAddressSource:"MANUAL",toAddressSource:"MANUAL",paymentMethod:"CARD_TRANSFER",itemDescription:"QA_TEST коробка",recipientContact:"QA_TEST +77019990000",date:"2026-05-16T13:00:00Z"}')" "$PASSENGER_TOKEN"
  assert_status_one_of "delivery create" 200 201
  DELIVERY_REQUEST_ID="$(json_read '.id // empty')"

  call_api POST "intercity/requests/$DELIVERY_REQUEST_ID/offers" "$(json_build \
    '{price:2500,comment:"QA_TEST delivery offer"}')" "$DRIVER_TOKEN"
  assert_status_one_of "delivery offer" 200 201
  DELIVERY_OFFER_ID="$(json_read '.id // empty')"
  local delivery_offer_status
  delivery_offer_status="$(json_read '.status // empty')"

  log_step "Intercity create and balance guard"
  call_api POST "intercity/requests" "$(json_build \
    '{requestType:"INTERCITY",fromManualAddress:"QA_TEST Усть-Каменогорск, вокзал",toManualAddress:"QA_TEST Риддер, автовокзал",fromAddressSource:"MANUAL",toAddressSource:"MANUAL",paymentMethod:"BONUSES",seats:2,date:"2026-05-17T09:00:00Z"}')" "$PASSENGER_TOKEN"
  assert_status_one_of "intercity create" 200 201
  INTERCITY_REQUEST_ID="$(json_read '.id // empty')"
  local intercity_payment
  intercity_payment="$(json_read '.paymentMethod // empty')"

  call_api POST "intercity/requests/$INTERCITY_REQUEST_ID/offers" "$(json_build \
    '{price:6000,seats:2,comment:"QA_TEST intercity offer"}')" "$DRIVER_TOKEN"
  assert_status "400" "intercity insufficient balance guard"
  local intercity_offer_error
  intercity_offer_error="$(json_read '.message // empty')"

  log_step "Access control checks"
  call_api GET "admin/drivers/pending" "" "$PASSENGER_TOKEN"
  assert_status "403" "passenger admin access"
  local admin_access_error
  admin_access_error="$(json_read '.message // empty')"

  call_api GET "intercity/requests/$CITY_AUCTION_REQUEST_ID" "" "$DRIVER_TOKEN"
  assert_status "404" "driver reading foreign passenger request"
  local foreign_request_error
  foreign_request_error="$(json_read '.message // empty')"

  if [[ "$RUN_CLEANUP" == "1" ]]; then
    cleanup_open_request "$DELIVERY_REQUEST_ID"
    cleanup_open_request "$INTERCITY_REQUEST_ID"
    cleanup_driver_offline
  fi

  if [[ "$CLEANUP_USERS" == "1" ]]; then
    cleanup_users
  fi

  "$JQ_BIN" -n \
    --arg timestamp "$QA_TIMESTAMP" \
    --arg passengerPhone "$PASSENGER_PHONE" \
    --arg driverPhone "$DRIVER_PHONE" \
    --arg cityPreviewPrice "$city_preview_price" \
    --arg cityOrderId "$CITY_ORDER_ID" \
    --arg cityNearbyCount "$nearby_count" \
    --arg cityFinalStatus "$final_city_status" \
    --arg cityAuctionRequestId "$CITY_AUCTION_REQUEST_ID" \
    --arg cityAuctionStatus "$city_auction_status" \
    --arg deliveryError "$delivery_bonus_error" \
    --arg deliveryRequestId "$DELIVERY_REQUEST_ID" \
    --arg deliveryOfferStatus "$delivery_offer_status" \
    --arg intercityRequestId "$INTERCITY_REQUEST_ID" \
    --arg intercityPayment "$intercity_payment" \
    --arg intercityOfferError "$intercity_offer_error" \
    --arg adminAccessError "$admin_access_error" \
    --arg foreignRequestError "$foreign_request_error" \
    --arg cleanup "$RUN_CLEANUP" \
    --arg cleanupUsers "$CLEANUP_USERS" \
    '{
      timestamp: $timestamp,
      accounts: {
        passengerPhone: $passengerPhone,
        driverPhone: $driverPhone
      },
      cityFixed: {
        previewPrice: ($cityPreviewPrice | tonumber),
        orderId: $cityOrderId,
        nearbyCount: ($cityNearbyCount | tonumber),
        finalStatus: $cityFinalStatus
      },
      cityAuction: {
        requestId: $cityAuctionRequestId,
        finalStatus: $cityAuctionStatus
      },
      delivery: {
        bonusesValidation: $deliveryError,
        requestId: $deliveryRequestId,
        offerStatus: $deliveryOfferStatus
      },
      intercity: {
        requestId: $intercityRequestId,
        paymentMethod: $intercityPayment,
        driverGuard: $intercityOfferError
      },
      accessControl: {
        adminEndpoint: $adminAccessError,
        foreignRequest: $foreignRequestError
      },
      cleanupAttempted: ($cleanup == "1"),
      cleanupUsersAttempted: ($cleanupUsers == "1")
    }'
}

main "$@"
