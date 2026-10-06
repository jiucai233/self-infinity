#!/usr/bin/env bash
# Deploys Self-Infinity to Vercel (docs/deploy.md): builds the Flutter web app
# into backend/public/ here, then uploads backend/ — the FastAPI app and the
# built web app — as one Vercel project.
#
#   SUPABASE_URL=https://xyz.supabase.co SUPABASE_ANON_KEY=sb_publishable_... scripts/deploy.sh [--prod]
#
# The first time, `npx vercel login` and `npx vercel link` (in backend/) set up the project.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
: "${SUPABASE_URL:?set SUPABASE_URL (Supabase → Project Settings → API)}"
: "${SUPABASE_ANON_KEY:?set SUPABASE_ANON_KEY (the publishable / anon key, not the secret one)}"

rm -rf "$ROOT/backend/public"
(
  cd "$ROOT/app"
  flutter build web --release \
    --dart-define=API_BASE_URL=/api \
    --dart-define=SUPABASE_URL="$SUPABASE_URL" \
    --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY" \
    --output "$ROOT/backend/public"
)
cd "$ROOT/backend"
npx --yes vercel@latest deploy "$@"
