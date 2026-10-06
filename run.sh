#!/usr/bin/env bash
# Dev workflow: backend on :8000 + Flutter web client on :8090.
# LLM_PROVIDER defaults to mock so a real key in backend/.env is never used by
# accident; run `LLM_PROVIDER=deepseek ./run.sh` to use the real provider.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROVIDER="${LLM_PROVIDER:-mock}"

if [ ! -d "$ROOT/backend/.venv" ]; then
  echo "backend/.venv not found — run: cd backend && python3 -m venv .venv && .venv/bin/pip install -r requirements.txt"
  exit 1
fi

if ! command -v flutter >/dev/null; then
  echo "flutter not found on PATH"
  exit 1
fi

for port in 8000 8090; do
  if lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "port $port is already in use — stop that process first: lsof -nP -iTCP:$port -sTCP:LISTEN"
    exit 1
  fi
done

cleanup() {
  echo "stopping..."
  kill "$BACKEND_PID" "$APP_PID" 2>/dev/null || true
  wait "$BACKEND_PID" "$APP_PID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

(cd "$ROOT/backend" && LLM_PROVIDER="$PROVIDER" exec .venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8000) &
BACKEND_PID=$!

(cd "$ROOT/app" && exec flutter run -d web-server --release --web-hostname 127.0.0.1 --web-port 8090 \
  --dart-define=API_BASE_URL=http://127.0.0.1:8000/api) &
APP_PID=$!

echo "backend: http://127.0.0.1:8000/docs (LLM_PROVIDER=$PROVIDER, pid $BACKEND_PID)"
echo "app:     http://127.0.0.1:8090 (first build takes ~1 min, pid $APP_PID)"
echo "ctrl-c to stop both"

wait "$BACKEND_PID" "$APP_PID"
