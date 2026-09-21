#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${PROXY_PORT:-8787}"
TARGET="${PROXY_TARGET:-https://api.bldtrack.ai}"

cd "$ROOT"

node scripts/dev_api_proxy.js &
PROXY_PID=$!

cleanup() {
  kill "$PROXY_PID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

sleep 0.5
echo ""
echo "Starting Flutter (API via http://127.0.0.1:${PORT} -> ${TARGET})"
echo ""

flutter run -d chrome --dart-define=API_BASE_URL="http://127.0.0.1:${PORT}"
