#!/usr/bin/env bash
# Guards the LifeOS page-shell boundary. Feature pages should use the
# canonical shells (ShellTabScaffold, AppPageScaffold, ObjectDetailScaffold,
# or a form/detail-specific wrapper) instead of growing new direct FScaffold
# compositions.
#
# Remaining direct FScaffold files are catalogued in
# page-scaffold-allowlist.txt and should shrink over time.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FEATURES="$ROOT/apps/mobile/lib/features"
ALLOWLIST="$ROOT/tool/page-scaffold-allowlist.txt"

matches="$(
  grep -rl --include='*.dart' 'FScaffold(' "$FEATURES" \
    | sed -E "s#^$ROOT/##" \
    | sort \
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
  echo "✖ Direct FScaffold usage found outside the page-shell allowlist." >&2
  echo "  Prefer ShellTabScaffold, AppPageScaffold, ObjectDetailScaffold, or a dedicated form/detail shell." >&2
  echo >&2
  echo "$violations" >&2
  exit 1
fi

echo "✓ Direct feature FScaffold usage is limited to the page-shell allowlist."
