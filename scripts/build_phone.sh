#!/usr/bin/env bash
# Builds the phone app against the deployed backend (https://self-infinity.vercel.app/api).
#   scripts/build_phone.sh run        # debug on the connected phone (hot reload)
#   scripts/build_phone.sh profile    # profile mode, for jank checks
#   scripts/build_phone.sh apk        # release APK, then `flutter install`
#   scripts/build_phone.sh ios        # release on a connected iPhone
# Reads app/phone.json (gitignored): API_BASE_URL, SUPABASE_URL, SUPABASE_ANON_KEY.
set -euo pipefail
cd "$(dirname "$0")/../app"
[ -f phone.json ] || { echo "app/phone.json is missing (see docs/w13-device.md)"; exit 1; }
DEFINES=(--dart-define-from-file=phone.json)
case "${1:-run}" in
  run)     flutter run "${DEFINES[@]}" ;;
  profile) flutter run --profile "${DEFINES[@]}" ;;
  apk)     flutter build apk --release "${DEFINES[@]}" && flutter install ;;
  ios)     flutter run --release "${DEFINES[@]}" ;;
  *)       echo "usage: $0 run|profile|apk|ios"; exit 2 ;;
esac
