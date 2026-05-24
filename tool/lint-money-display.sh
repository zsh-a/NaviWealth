#!/usr/bin/env bash
# Flags naked `.toStringAsFixed(...)` money display so UI code uses
# MoneyText/SignedMoneyText/DualMoneyText or AppFormatters.currency instead.
#
# During MT-2.3.M1.2 this runs in advisory mode from CI because the codebase
# still has legitimate non-money uses of toStringAsFixed (percentages, timing,
# compact chart labels, Decimal rounding). Once the money display migration is
# complete, run without --advisory to make findings blocking.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:---strict}"

if [[ "$MODE" != "--strict" && "$MODE" != "--advisory" ]]; then
  echo "usage: tool/lint-money-display.sh [--strict|--advisory]" >&2
  exit 2
fi

SEARCH_ROOTS=(
  "$ROOT/apps/mobile/lib/features"
  "$ROOT/apps/mobile/lib/design_system"
  "$ROOT/apps/mobile/lib/core"
)

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

  # AI trace cost is a micro-cost diagnostic pill, not an end-user money
  # amount; it intentionally keeps more than fiat fraction digits.
  if [[ "$path" == *"/features/settings/ui/ai_"* ]]; then
    continue
  fi

  # Pure numeric rounding/parsing paths are not display.
  if [[ "$text" =~ Decimal\.parse|double\.parse ]]; then
    continue
  fi

  # Common non-money display classes: percentages, durations, chart compact
  # labels, and FIRE month/year copy.
  if [[ "$text" =~ %|pct|Pct|percent|Percent|rate|Rate|ratio|Ratio|weight|Weight|drift|Drift|seconds|ms|months|Months|year|Year|DTE|万|[KMT]\' ]]; then
    continue
  fi

  if [[ "$text" =~ \.amount\.toStringAsFixed|currency|Currency|_fmtMoney|Money|cash|Cash|price|Price|cost|Cost|fee|Fee|tax|Tax|balance|Balance|premium|Premium|strike|Strike|breakeven|Breakeven|¥ ]]; then
    findings+="$line"$'\n'
  fi
done <<< "$matches"

if [[ -n "$findings" ]]; then
  echo "✖ Naked money formatting found." >&2
  echo "  Use MoneyText/SignedMoneyText/DualMoneyText for widgets or AppFormatters.currency for strings." >&2
  echo >&2
  printf "%s" "$findings" >&2
  if [[ "$MODE" == "--strict" ]]; then
    exit 1
  fi
  echo "advisory mode: not failing while MT-2.3.M1.2 migration is in progress." >&2
  exit 0
fi

echo "✓ No suspicious naked money .toStringAsFixed display found."
