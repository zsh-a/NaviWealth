#!/usr/bin/env bash
# Report gzip-9 sizes of the first-paint critical-path web assets and fail
# the build if `main.dart.js` exceeds the regression budget.
#
# Run after `flutter build web --release`. The numbers reported here are what
# a CDN with gzip/brotli will actually serve — see docs/web-bundle.md for the
# baseline and rationale.
#
# Usage:
#   apps/mobile/tool/check-web-bundle-size.sh [--budget-bytes N]
#
# Env / flag:
#   --budget-bytes N    Override the regression cap (default: 921600 = 900 KB).
#                       The aspirational target from FIR-39 / FIR-62 is
#                       ≤ 800 KB; the cap sits ~10 % above the current
#                       baseline (~821 KB) so we catch obvious regressions
#                       while the long-tail wins land.
set -euo pipefail

cd "$(dirname "$0")/.."

BUILD_DIR="build/web"
BUDGET_BYTES=${WEB_BUNDLE_BUDGET_BYTES:-921600}

while [ $# -gt 0 ]; do
  case "$1" in
    --budget-bytes)
      BUDGET_BYTES="$2"
      shift 2
      ;;
    *)
      echo "unknown arg: $1" >&2
      exit 64
      ;;
  esac
done

if [ ! -d "$BUILD_DIR" ]; then
  echo "error: $BUILD_DIR not found — run 'flutter build web --release' first" >&2
  exit 1
fi

stat_size() {
  if stat -f '%z' "$1" >/dev/null 2>&1; then
    stat -f '%z' "$1"
  else
    stat -c '%s' "$1"
  fi
}

human_kb() {
  awk -v b="$1" 'BEGIN { printf "%.1f KB", b / 1024 }'
}

main_js="$BUILD_DIR/main.dart.js"
if [ ! -f "$main_js" ]; then
  echo "error: $main_js not found in build output" >&2
  exit 1
fi

echo "First-paint critical-path bundle (gzip-9):"
printf '  %-32s %12s %12s\n' "file" "raw" "gzip"
total_gz=0
fail=0
for f in \
  "$BUILD_DIR/main.dart.js" \
  "$BUILD_DIR/flutter.js" \
  "$BUILD_DIR/flutter_bootstrap.js"; do
  if [ ! -f "$f" ]; then continue; fi
  raw=$(stat_size "$f")
  gz=$(gzip -c -9 "$f" | wc -c | tr -d ' ')
  printf '  %-32s %12s %12s\n' "$(basename "$f")" "$(human_kb "$raw")" "$(human_kb "$gz")"
  total_gz=$((total_gz + gz))
done
echo "  ----"
printf '  %-32s %12s %12s\n' "first-paint total" "" "$(human_kb "$total_gz")"

main_gz=$(gzip -c -9 "$main_js" | wc -c | tr -d ' ')
echo
echo "main.dart.js gzip-9:  $(human_kb "$main_gz") (raw $(human_kb "$(stat_size "$main_js")"))"
echo "regression cap:       $(human_kb "$BUDGET_BYTES")"

if [ "$main_gz" -gt "$BUDGET_BYTES" ]; then
  echo "::error::main.dart.js gzip-9 ($(human_kb "$main_gz")) exceeds the regression cap ($(human_kb "$BUDGET_BYTES"))." >&2
  echo "See apps/mobile/docs/web-bundle.md — either shrink the bundle (defer a heavy import) or update the baseline doc and the cap, with justification." >&2
  fail=1
fi

exit $fail
