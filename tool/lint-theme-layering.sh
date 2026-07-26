#!/usr/bin/env bash
# Theme layering lint (UI refactor blueprint §10, doc 15-ui-refactor-blueprint.md).
#
# Enforces the one-way theme layering:
#   primitives (ColorPalette) -> roles (AppTheme) -> component specs -> UI.
#
# Rule 1 (hard): only design_system/ may import tokens/color_palette.dart.
# Rule 2 (ratchet): legacy theme entry points (SemanticColors.of, MarketColors.of,
#   AccentColors.*) must not gain new call sites; migrate to context.appTheme.
# Rule 3 (ratchet): feature/component code must not branch on Brightness —
#   brightness is resolved once by resolveAppTheme().
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$ROOT/apps/mobile/lib"

# ── Rule 1: primitives stay private to design_system ──────────────────────
violations="$(grep -RInE --include='*.dart' \
  "^[[:space:]]*import[[:space:]]+['\"][^'\"]*color_palette\.dart" \
  "$LIB/app" "$LIB/core" "$LIB/features" "$LIB/l10n" 2>/dev/null || true)"

if [[ -n "$violations" ]]; then
  echo "✖ ColorPalette (theme primitives) imported outside design_system/:" >&2
  echo "$violations" >&2
  echo "Consume colors through context.appTheme roles instead." >&2
  exit 1
fi

# ── Rule 2: legacy theme entry points are frozen (ratchet) ─────────────────
# design_system/theme/ is exempt: resolveAppTheme() is the facade that
# legitimately folds the legacy tables into AppThemeData during migration.
# Remaining 8 = 6 MarketColors.of (preference-critical delta widgets, to be
# retired together with MarketColorsScope) + 2 AccentColors.series chart
# constants. Everything else reads context.appTheme.
LEGACY_BASELINE=8
legacy_count="$({ grep -RhoE --include='*.dart' \
  --exclude-dir=theme \
  "SemanticColors\.of\(|MarketColors\.of\(|AccentColors\." \
  "$LIB" || true; } | wc -l | tr -d ' ')"

if (( legacy_count > LEGACY_BASELINE )); then
  echo "✖ Legacy theme entry points grew: $legacy_count > baseline $LEGACY_BASELINE." >&2
  echo "New code must read context.appTheme; do not add SemanticColors.of /" >&2
  echo "MarketColors.of / AccentColors.* call sites." >&2
  exit 1
fi

# ── Rule 3: no Brightness branching in features/ (ratchet) ────────────────
BRIGHTNESS_BASELINE=3
brightness_count="$({ grep -RhoE --include='*.dart' \
  "== Brightness\.|Brightness\.(dark|light) ==" \
  "$LIB/features" || true; } | wc -l | tr -d ' ')"

if (( brightness_count > BRIGHTNESS_BASELINE )); then
  echo "✖ Brightness branching in features/ grew: $brightness_count > baseline $BRIGHTNESS_BASELINE." >&2
  echo "Brightness is resolved once in resolveAppTheme(); consume roles/specs." >&2
  exit 1
fi

echo "✓ theme layering ok (legacy entry points: $legacy_count/$LEGACY_BASELINE, brightness branches: $brightness_count/$BRIGHTNESS_BASELINE)"
