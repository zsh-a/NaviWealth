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

# Feature/app typography must resolve the active visual preset. Raw display
# and numeric styles bypass refined fonts and line heights even when colors
# and surfaces have switched correctly. Token definitions and measurements
# remain design-system-owned.
raw_styles="$(rg -n 'TypographyTokens\.(display[A-Z][A-Za-z]*|numeric[A-Z][A-Za-z]*|headline[A-Z][A-Za-z]*)\b' \
  "$LIB/features" "$LIB/app" --glob '*.dart' || true)"
if [[ -n "$raw_styles" ]]; then
  echo "✖ UI typography bypasses context.appTheme.type:" >&2
  echo "$raw_styles" >&2
  exit 1
fi

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
