#!/usr/bin/env bash
# Build store-ready artifacts pointed at LIVE API: https://api.bldtrack.ai
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

LIVE_API="${API_BASE_URL:-https://api.bldtrack.ai}"
BUILD_NAME="${BUILD_NAME:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"

echo "==> Live API: ${LIVE_API}"
echo "==> Version: ${BUILD_NAME}+${BUILD_NUMBER}"

echo "==> flutter pub get"
flutter pub get

echo "==> Android App Bundle (Play Internal / Closed testing)"
if [[ ! -f android/key.properties ]]; then
  echo "ERROR: android/key.properties missing. Create it from android/key.properties.example"
  exit 1
fi
flutter build appbundle \
  --release \
  --build-name="$BUILD_NAME" \
  --build-number="$BUILD_NUMBER" \
  --dart-define=API_BASE_URL="$LIVE_API"

AAB="build/app/outputs/bundle/release/app-release.aab"
echo "Android AAB: $AAB"

echo "==> iOS IPA (TestFlight) — requires Apple Developer signing in Xcode"
if [[ "$(uname)" == "Darwin" ]]; then
  flutter build ipa \
    --release \
    --build-name="$BUILD_NAME" \
    --build-number="$BUILD_NUMBER" \
    --dart-define=API_BASE_URL="$LIVE_API" \
    || echo "WARN: iOS IPA build needs Team ID / certificates. Open ios/Runner.xcworkspace in Xcode → Signing & Capabilities."
  echo "If successful, IPA under: build/ios/ipa/"
else
  echo "Skipping iOS (not macOS)."
fi

echo ""
echo "Done."
echo "  Play Console → Testing → Internal testing → upload $AAB"
echo "  App Store Connect → TestFlight → upload IPA via Xcode Organizer / Transporter"
