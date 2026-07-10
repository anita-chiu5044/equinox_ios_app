#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IOS_BUILD_DERIVED_DATA="${IOS_BUILD_DERIVED_DATA:-/private/tmp/EquinoxDerivedData-iOSSim}"
MAC_BUILD_DERIVED_DATA="${MAC_BUILD_DERIVED_DATA:-/private/tmp/EquinoxDerivedData-mac}"
IOS_TEST_DERIVED_DATA="${IOS_TEST_DERIVED_DATA:-/private/tmp/EquinoxDerivedData-iOSTest}"
IOS_TEST_DESTINATION="${IOS_TEST_DESTINATION:-platform=iOS Simulator,name=iPhone 17}"

cd "$ROOT"

echo "== Xcode release preflight =="
if python3 scripts/preflight_release.py; then
  echo "Release settings are complete."
else
  echo "Release settings are incomplete; continuing with local build/test verification."
fi

echo
echo "== iOS Simulator generic build =="
xcodebuild -quiet \
  -project Equinox.xcodeproj \
  -scheme Equinox \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$IOS_BUILD_DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  build

echo
echo "== macOS generic build =="
xcodebuild -quiet \
  -project Equinox.xcodeproj \
  -scheme Equinox \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$MAC_BUILD_DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  build

echo
echo "== iOS Simulator tests =="
xcodebuild -quiet \
  -project Equinox.xcodeproj \
  -scheme Equinox \
  -destination "$IOS_TEST_DESTINATION" \
  -derivedDataPath "$IOS_TEST_DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  test

echo
echo "Local app verification passed."
