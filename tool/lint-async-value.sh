#!/usr/bin/env bash
# AsyncValue consumption lint.
#
# Feature UI consumes AsyncValue through the whenOrLoading/whenOrError
# extensions (apps/mobile/lib/design_system/widgets/app_async_helpers.dart)
# so loading, error and retry chrome stay consistent. Hand-rolled
# .when(loading:/error:) blocks fork that chrome per screen and must ratchet
# toward zero. The remaining call sites are intentional exceptions (custom
# skeletons, custom error UI, non-Widget or data-layer transforms) and are
# capped by the baseline below.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$ROOT/apps/mobile/lib"

BASELINE=96
PATTERN='\.when\([[:space:]]*$|\.when\(loading:'

count="$({ grep -RhoE --include='*.dart' "$PATTERN" \
  "$LIB/app" "$LIB/core" "$LIB/features" || true; } | wc -l | tr -d ' ')"

if (( count > BASELINE )); then
  echo "✖ Manual AsyncValue .when( grew: $count > baseline $BASELINE." >&2
  grep -RInE --include='*.dart' "$PATTERN" \
    "$LIB/app" "$LIB/core" "$LIB/features" | tail -n 20 >&2
  echo "Use .whenOrLoading(context: ...) from" >&2
  echo "design_system/widgets/app_async_helpers.dart for default" >&2
  echo "loading/error UI instead." >&2
  exit 1
fi

echo "✓ async-value ok ($count/$BASELINE)"
