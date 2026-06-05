#!/usr/bin/env bash
# Guards the shared UI primitives introduced for the LifeOS surface
# unification pass. Feature code should prefer AppBadge, AppStatusBanner
# and AppSection over growing new local Badge/Pill/Banner widgets.
#
# Existing business-specific wrappers are catalogued in
# ui-unified-components-allowlist.txt and can be migrated down over time.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FEATURES="$ROOT/apps/mobile/lib/features"
ALLOWLIST="$ROOT/tool/ui-unified-components-allowlist.txt"
PATTERN='^class _?[A-Za-z0-9]*(Badge|Pill|Banner)\b'

matches="$(
  grep -rnE --include='*.dart' "$PATTERN" "$FEATURES" \
    | sed -E "s#^$ROOT/##; s#^(.+):[0-9]+:class +([^ ]+).*\$#\1:\2#" \
    || true
)"

violations="$(
  while IFS= read -r match; do
    [[ -z "$match" ]] && continue
    if ! grep -Fxq "$match" "$ALLOWLIST"; then
      echo "$match"
    fi
  done <<< "$matches"
)"

if [[ -n "$violations" ]]; then
  echo "✖ Local Badge/Pill/Banner widgets found outside the UI unification allowlist." >&2
  echo "  Prefer design_system AppBadge/AppStatusBanner/AppSection, or add a documented exception." >&2
  echo >&2
  echo "$violations" >&2
  exit 1
fi

echo "✓ Feature Badge/Pill/Banner wrappers are limited to the UI unification allowlist."
