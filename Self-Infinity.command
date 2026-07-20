#!/usr/bin/env bash
# Double-click launcher for personal daily use — builds the frontend once,
# then runs a single backend process that serves both the API and the
# built frontend (see backend/app/main.py's StaticFiles mount) on one port.
# Opens the browser automatically. Close this window (or Ctrl+C) to stop.
#
# This is deliberately NOT run.sh: run.sh is the dev workflow (two
# processes, Vite hot-reload on :5173, proxying to the backend on :8000).
# This script is the "just use the app" path — no hot reload, one process,
# one URL. If you've changed frontend code, delete frontend/dist (or just
# re-run `npm run build` inside frontend/) before launching again to pick
# up the changes — this script only builds when dist doesn't exist yet, to
# keep normal daily launches fast.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PORT=8000
URL="http://127.0.0.1:$PORT"

if [ ! -d "$ROOT/backend/.venv" ]; then
  echo "backend/.venv not found — run: cd backend && python3 -m venv .venv && .venv/bin/pip install -r requirements.txt"
  read -n 1 -s -r -p "Press any key to close..."
  exit 1
fi

if [ ! -d "$ROOT/frontend/dist" ]; then
  echo "First run — building the frontend (only happens once; delete frontend/dist to force a rebuild later)..."
  if [ ! -d "$ROOT/frontend/node_modules" ]; then
    (cd "$ROOT/frontend" && npm install)
  fi
  (cd "$ROOT/frontend" && npm run build)
fi

cleanup() {
  echo "stopping..."
  kill "$SERVER_PID" 2>/dev/null || true
  wait "$SERVER_PID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

(cd "$ROOT/backend" && exec .venv/bin/uvicorn app.main:app --port "$PORT") &
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
