#!/usr/bin/env bash
# Flags naked `.toStringAsFixed(...)` money display so UI code uses
# MoneyText/SignedMoneyText/DualMoneyText or AppFormatters.currency instead.
#
# Legitimate non-money uses of toStringAsFixed (percentages, timing, compact
# chart labels, Decimal rounding) must be registered in
# tool/money-display-to-string-allowlist.txt. Any new unregistered call is
# treated as suspicious money display and fails strict mode.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:---strict}"

if [[ "$MODE" != "--strict" && "$MODE" != "--advisory" ]]; then
  echo "usage: tool/lint-money-display.sh [--strict|--advisory]" >&2
  exit 2
fi

SEARCH_ROOTS=(
  "$ROOT/apps/mobile/lib"
)
ALLOWLIST="$ROOT/tool/money-display-to-string-allowlist.txt"

is_allowlisted() {
  local rel_path="$1"
  local text="$2"

  [[ -f "$ALLOWLIST" ]] || return 1
  awk -F '\t' -v path="$rel_path" -v line="$text" '
    /^#/ || NF < 2 { next }
    $1 == path && $2 == line { found = 1; exit }
    END { exit found ? 0 : 1 }
  ' "$ALLOWLIST"
}

matches="$(
  grep -RIn --include='*.dart' '\.toStringAsFixed(' "${SEARCH_ROOTS[@]}" \
    | grep -Ev '\.(g|freezed)\.dart:' \
    || true
)"

findings=""
while IFS= read -r line; do
  [[ -z "$line" ]] && continue

  path="${line%%:*}"
  text="${line#*:}"
  text="${text#*:}"
  rel_path="${path#$ROOT/}"
  text="$(printf '%s' "$text" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"

  if ! is_allowlisted "$rel_path" "$text"; then
    findings+="$rel_path: $text"$'\n'
  fi
done <<< "$matches"

if [[ -n "$findings" ]]; then
  echo "✖ Unallowlisted .toStringAsFixed display found." >&2
  echo "  Use MoneyText/SignedMoneyText/DualMoneyText for money widgets or AppFormatters.currency for money strings." >&2
  echo "  If this is a non-money percentage, duration, compact label, AI diagnostic cost, or Decimal rounding path, add it to:" >&2
  echo "  $ALLOWLIST" >&2
  echo >&2
  printf "%s" "$findings" >&2
  if [[ "$MODE" == "--strict" ]]; then
    exit 1
  fi
  echo "advisory mode: not failing, but strict CI will reject these lines." >&2
  exit 0
fi

echo "✓ No unallowlisted .toStringAsFixed display found."
