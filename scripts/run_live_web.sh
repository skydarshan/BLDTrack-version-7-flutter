#!/usr/bin/env bash
# Run Flutter web against LIVE api.bldtrack.ai (via local CORS proxy).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PORT="${PROXY_PORT:-8787}"
TARGET="${PROXY_TARGET:-https://api.bldtrack.ai}"

if ! curl -sf "http://127.0.0.1:${PORT}/api/v1/health" >/dev/null 2>&1; then
  echo "Starting live API proxy on :${PORT} → ${TARGET}"
  PROXY_TARGET="$TARGET" PROXY_PORT="$PORT" node scripts/dev_api_proxy.js &
  PROXY_PID=$!
  trap 'kill '"$PROXY_PID"' 2>/dev/null || true' EXIT
  for i in $(seq 1 30); do
    if curl -sf "http://127.0.0.1:${PORT}/api/v1/health" >/dev/null 2>&1; then
      break
    fi
    sleep 0.3
  done
else
  echo "Proxy already up on :${PORT}"
fi

echo "Flutter → http://127.0.0.1:${PORT} → ${TARGET}"
exec flutter run -d chrome \
  --web-hostname=127.0.0.1 \
  --dart-define=API_BASE_URL="http://127.0.0.1:${PORT}"
