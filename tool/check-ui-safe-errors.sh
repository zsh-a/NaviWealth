#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UI_ROOTS=(
  "$ROOT/apps/mobile/lib/features"
  "$ROOT/apps/mobile/lib/core/ai/agents/ui"
)

patterns=(
  "message: ['\"]?\\\$\\{?[^,;)]*error"
  "Text\\([^\\n]*(error\\.toString\\(\\)|\\\$\\{?[^)]*error)"
  "commonLoadError\\([^)]*(error|Error|\\.error)"
  "[A-Za-z0-9_]*(Error|Failed)\\(['\"]?\\\$\\{?[^,;)]*error"
)

findings=""
for pattern in "${patterns[@]}"; do
  matches="$(grep -RInE --include='*.dart' "$pattern" "${UI_ROOTS[@]}" || true)"
  if [[ -n "$matches" ]]; then
    findings+="$matches"$'\n'
  fi
done

if [[ -n "$findings" ]]; then
  echo "✖ Raw technical errors are rendered in UI code." >&2
  echo "  Use userSafeErrorMessage(context, error) and preserve retry actions." >&2
  printf '%s' "$findings" >&2
  exit 1
fi

echo "✓ UI error states use safe localized messages."
