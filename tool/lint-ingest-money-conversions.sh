#!/usr/bin/env bash
# Guardrail: Ingest persists monetary values as integer minor units. Parsing,
# editing, routing, and confirmation must use the exact minor-unit contract
# instead of binary floating point or ad-hoc scaling and rounding.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INGEST="$ROOT/apps/mobile/lib/features/finance/ingest"

double_parse_violations="$(
  grep -rnE --include='*.dart' 'double\.(tryParse|parse)\(' "$INGEST" \
    || true
)"

scaled_rounding_violations="$(
  grep -rnE --include='*.dart' \
    'Decimal\.fromInt\(100\)|\*[^;]*(100|100\.0)[^;]*\.round\(' \
    "$INGEST/data" "$INGEST/domain" \
    || true
)"

scaled_division_violations="$(
  grep -rnE --include='*.dart' \
    '[A-Za-z0-9_)][[:space:]]*/[[:space:]]*100(\.0)?([^0-9]|$)' \
    "$INGEST/data" "$INGEST/domain" \
    || true
)"

violations="$double_parse_violations$scaled_rounding_violations$scaled_division_violations"
if [[ -n "$violations" ]]; then
  echo "✖ Ingest contains a lossy or ad-hoc money conversion:" >&2
  [[ -n "$double_parse_violations" ]] && echo "$double_parse_violations" >&2
  [[ -n "$scaled_rounding_violations" ]] && echo "$scaled_rounding_violations" >&2
  [[ -n "$scaled_division_violations" ]] && echo "$scaled_division_violations" >&2
  echo >&2
  echo "Use domain/minor_unit_amount.dart for decimal ↔ minor-unit conversion." >&2
  exit 1
fi

echo "✓ Ingest monetary conversions stay on the exact minor-unit contract."
