#!/usr/bin/env bash
# Builds the Flutter web app into backend/public/ for Vercel (docs/deploy.md).
#
# scripts/deploy.sh builds it locally first, so on Vercel this usually finds
# public/index.html and does nothing. Deploying from Git instead (no public/), it
# installs Flutter in the build machine and builds the app from ../app, with
# SUPABASE_URL and SUPABASE_ANON_KEY from the Vercel project's environment.
set -euo pipefail
cd "$(dirname "$0")"

if [ -f public/index.html ]; then
  echo "public/ is already built; skipping the Flutter build."
  exit 0
fi
if [ ! -d ../app ]; then
  echo "No public/ and no ../app to build it from. Run scripts/deploy.sh, or enable" >&2
  echo "'Include files outside the root directory' in the Vercel project settings." >&2
  exit 1
fi
if ! command -v flutter >/dev/null; then
  git clone --depth 1 --branch stable https://github.com/flutter/flutter.git /tmp/flutter
  export PATH="/tmp/flutter/bin:$PATH"
fi
(
  cd ../app
  flutter build web --release \
    --dart-define=API_BASE_URL=/api \
    --dart-define=SUPABASE_URL="${SUPABASE_URL:?set SUPABASE_URL}" \
    --dart-define=SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY:?set SUPABASE_ANON_KEY}" \
    --output ../backend/public
)
