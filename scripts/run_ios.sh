#!/usr/bin/env bash
# Run BldTrack on iOS Simulator or a connected iPhone.
# Must be executed on macOS with Xcode + CocoaPods + Flutter.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "iOS build only works on a Mac (Xcode). This PC is not macOS."
  exit 1
fi

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter is not on PATH. Install Flutter, then retry."
  exit 1
fi

if ! command -v pod >/dev/null 2>&1; then
  echo "CocoaPods missing. Run: sudo gem install cocoapods"
  exit 1
fi

flutter pub get
(
  cd ios
  pod install
)

API_BASE_URL="${API_BASE_URL:-https://api.bldtrack.ai}"

if [[ "${1:-}" == "--iphone" ]]; then
  DEVICE="$(flutter devices | awk '/ios/{print $5; exit}')"
  if [[ -z "${DEVICE}" ]]; then
    echo "No physical iPhone found. Unlock it, trust this Mac, then retry."
    exit 1
  fi
  flutter run -d "$DEVICE" --dart-define="API_BASE_URL=${API_BASE_URL}"
else
  flutter run -d ios --dart-define="API_BASE_URL=${API_BASE_URL}"
fi
