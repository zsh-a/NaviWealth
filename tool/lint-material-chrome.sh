#!/usr/bin/env bash
# Material chrome lint (UI refactor blueprint §10, doc 15-ui-refactor-blueprint.md).
#
# NaviWealth is a Forui app: notifications go through AppMessenger, loading
# through skeletons, dividers through AppDivider, sheets through showAppSheet.
# Raw Material chrome renders off-theme (wrong colors, wrong stacking with the
# floating dock), so it must not gain new call sites (ratchet toward zero).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$ROOT/apps/mobile/lib"

# P2 cleared SnackBar / ScaffoldMessenger / Material Divider to zero.
# P3 cleared the last CircularProgressIndicator call sites (FCircularProgress
# is the Forui replacement), so all Material chrome is now banned outright.
BASELINE=0
PATTERN='ScaffoldMessenger|SnackBar\(|CircularProgressIndicator|showModalBottomSheet|(^|[^A-Za-z_])Divider\('

count="$({ grep -RhoE --include='*.dart' "$PATTERN" "$LIB" || true; } | wc -l | tr -d ' ')"

if (( count > BASELINE )); then
  echo "✖ Material chrome usage grew: $count > baseline $BASELINE." >&2
  grep -RInE --include='*.dart' "$PATTERN" "$LIB" | tail -n 20 >&2
  echo >&2
  echo "Use AppMessenger (toasts), page skeletons (loading), AppDivider," >&2
  echo "and showAppSheet/showAppContentDialog instead." >&2
  exit 1
fi

echo "✓ material chrome ok ($count/$BASELINE)"
