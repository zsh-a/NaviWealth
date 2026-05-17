#!/usr/bin/env bash
# Guards the unified modal system: every sheet/dialog in feature code
# must go through the design-system helpers (showAppSheet /
# showAppFormSheet / showConfirmDialog / showInfoDialog) so the drag
# handle, header, surface, keyboard avoidance and footer stay identical.
#
# Raw Material modal APIs bypass all of that, so they are banned in
# `apps/mobile/lib/features/**`. (Forui's showFSheet / showFDialog /
# showGeneralDialog remain allowed — they are the primitives the
# design-system helpers and the responsive desktop presenters build on.)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FEATURES="$ROOT/apps/mobile/lib/features"

# Material modal entry points that must not appear in feature code.
PATTERN='showDialog\(|showModalBottomSheet\(|AlertDialog\(|showCupertinoModalPopup\(|showAdaptiveDialog\('

if matches="$(grep -rnE --include='*.dart' "$PATTERN" "$FEATURES" || true)"; then
  if [[ -n "$matches" ]]; then
    echo "✖ Raw Material modal API used in feature code." >&2
    echo "  Route it through the design-system helpers in" >&2
    echo "  lib/design_system/widgets/app_sheet.dart instead:" >&2
    echo "    showAppSheet / showAppFormSheet / showConfirmDialog / showInfoDialog" >&2
    echo >&2
    echo "$matches" >&2
    exit 1
  fi
fi

echo "✓ No raw Material modals in feature code."
