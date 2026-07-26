#!/usr/bin/env bash
# Number/label formatting lint (UI refactor blueprint §5/§10).
#
# Money and percent rendering has exactly one path: MoneyText / DeltaText /
# AppFormatters. Hand-rolled '${currency} ${amount}' interpolation and
# toStringAsFixed(..)% drift per screen and must ratchet toward zero.
# Wire enum values (`.wire`) are sync identifiers, never user-visible text.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FEATURES="$ROOT/apps/mobile/lib/features"

# ── Rule 1: hand-formatted percent (ratchet) ───────────────────────────────
# P2 migrated every hand-formatted percent to AppFormatters — keep at zero.
PCT_BASELINE=0
pct_count="$({ grep -RhoE --include='*.dart' \
  'toStringAsFixed\([0-9]\)[^;]{0,20}%' \
  "$FEATURES" || true; } | wc -l | tr -d ' ')"

if (( pct_count > PCT_BASELINE )); then
  echo "✖ Hand-formatted percent grew: $pct_count > baseline $PCT_BASELINE." >&2
  echo "Use AppFormatters.percent / signedPercent." >&2
  exit 1
fi

# ── Rule 2: wire enums rendered in UI (ratchet) ────────────────────────────
WIRE_BASELINE=66
wire_count="$({ find "$FEATURES" -type d -name ui -prune -print0 \
  | xargs -0 grep -RhoE --include='*.dart' '\.wire\b' 2>/dev/null \
  || true; } | wc -l | tr -d ' ')"

if (( wire_count > WIRE_BASELINE )); then
  echo "✖ .wire usage in ui/ grew: $wire_count > baseline $WIRE_BASELINE." >&2
  echo "Render localized labels (e.g. decisionStatusLabel), never wire values." >&2
  exit 1
fi

echo "✓ format path ok (percent: $pct_count/$PCT_BASELINE, wire-in-ui: $wire_count/$WIRE_BASELINE)"
