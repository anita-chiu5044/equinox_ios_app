#!/usr/bin/env bash
set -euo pipefail

API_URL="${1:-}"
CONFIGURATION="${CONFIGURATION:-Release}"
DESTINATION="${DESTINATION:-platform=macOS}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-/private/tmp/EquinoxDerivedData-${CONFIGURATION}}"

if [[ -z "${API_URL}" ]]; then
  echo "Usage: scripts/build_with_api_url.sh https://your-cloud-run-url" >&2
  exit 1
fi

if [[ "${CONFIGURATION}" == "Release" && ! "${API_URL}" =~ ^https:// ]]; then
  echo "Release API URL must start with https:// for TestFlight/App Store builds." >&2
  exit 1
fi

xcodebuild \
  -project Equinox.xcodeproj \
  -scheme Equinox \
  -configuration "${CONFIGURATION}" \
  -destination "${DESTINATION}" \
  -derivedDataPath "${DERIVED_DATA_PATH}" \
  CODE_SIGNING_ALLOWED="${CODE_SIGNING_ALLOWED:-NO}" \
  EQUINOX_API_BASE_URL="${API_URL}" \
  build

APP_INFO_PLIST="${DERIVED_DATA_PATH}/Build/Products/${CONFIGURATION}/Equinox.app/Contents/Info.plist"
if [[ -f "${APP_INFO_PLIST}" ]]; then
  echo "Built API URL:"
  /usr/libexec/PlistBuddy -c 'Print :EQUINOX_API_BASE_URL' "${APP_INFO_PLIST}"
fi
