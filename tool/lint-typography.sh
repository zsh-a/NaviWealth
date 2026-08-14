#!/usr/bin/env bash
# Typography lint (UI refactor blueprint §4/§10).
#
# The type scale carries size, weight and line height. Ad-hoc
# copyWith(fontSize:/fontWeight:/height:) outside design_system/ forks the
# scale per screen and must ratchet toward zero — use the semantic presets
# and their .muted/.emphasized variants instead.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$ROOT/apps/mobile/lib"

BASELINE=31
count="$({ grep -RhoE --include='*.dart' \
  'copyWith\([^)]*(fontSize:|fontWeight:|height:)' \
  "$LIB/app" "$LIB/core" "$LIB/features" || true; } | wc -l | tr -d ' ')"

if (( count > BASELINE )); then
  echo "✖ Ad-hoc typography copyWith grew: $count > baseline $BASELINE." >&2
  grep -RInE --include='*.dart' 'copyWith\([^)]*(fontSize:|fontWeight:|height:)' \
    "$LIB/app" "$LIB/core" "$LIB/features" | tail -n 20 >&2
  echo "Use the semantic type scale (context.appTheme.type) instead." >&2
  exit 1
fi

echo "✓ typography ok ($count/$BASELINE)"
