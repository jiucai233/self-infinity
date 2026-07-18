#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ ! -d "$ROOT/backend/.venv" ]; then
  echo "backend/.venv not found — run: cd backend && python3 -m venv .venv && .venv/bin/pip install -r requirements.txt"
  exit 1
fi

if [ ! -d "$ROOT/frontend/node_modules" ]; then
  echo "frontend/node_modules not found — run: cd frontend && npm install"
  exit 1
fi

cleanup() {
  echo "stopping..."
  kill "$BACKEND_PID" "$FRONTEND_PID" 2>/dev/null || true
  wait "$BACKEND_PID" "$FRONTEND_PID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

(cd "$ROOT/backend" && exec .venv/bin/uvicorn app.main:app --reload) &
BACKEND_PID=$!

(cd "$ROOT/frontend" && exec npm run dev) &
FRONTEND_PID=$!

echo "backend:  http://127.0.0.1:8000/docs (pid $BACKEND_PID)"
echo "frontend: http://localhost:5173 (pid $FRONTEND_PID)"
echo "ctrl-c to stop both"

wait "$BACKEND_PID" "$FRONTEND_PID"
