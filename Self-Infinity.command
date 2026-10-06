#!/usr/bin/env bash
# Double-click launcher for daily use: builds the Flutter web app once into
# app/build/web, then runs a single backend process that serves both the API
# and the built app (see backend/app/main.py's StaticFiles mount) on one port.
# Opens the browser automatically. Close this window (or Ctrl+C) to stop.
#
# This is deliberately NOT run.sh: run.sh is the dev workflow (backend on :8000
# plus `flutter run` on :8090, Mock LLM by default). This script uses the
# provider configured in backend/.env. It only builds when app/build/web does
# not exist yet; delete that folder to pick up code changes.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PORT=8000
URL="http://127.0.0.1:$PORT"

if [ ! -d "$ROOT/backend/.venv" ]; then
  echo "backend/.venv not found — run: cd backend && python3 -m venv .venv && .venv/bin/pip install -r requirements.txt"
  read -n 1 -s -r -p "Press any key to close..."
  exit 1
fi

if [ ! -d "$ROOT/app/build/web" ]; then
  echo "First run — building the app (only happens once; delete app/build/web to force a rebuild later)..."
  (cd "$ROOT/app" && flutter build web --release --dart-define=API_BASE_URL="$URL/api")
fi

cleanup() {
  echo "stopping..."
  kill "$SERVER_PID" 2>/dev/null || true
  wait "$SERVER_PID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

(cd "$ROOT/backend" && exec .venv/bin/uvicorn app.main:app --host 127.0.0.1 --port "$PORT") &
SERVER_PID=$!

echo "Starting Self-Infinity..."
for _ in $(seq 1 30); do
  if curl -s -o /dev/null "$URL/api/health"; then
    break
  fi
  sleep 0.3
done

open "$URL"
echo "Self-Infinity is running at $URL — close this window (or Ctrl+C) to stop it."

wait "$SERVER_PID"
