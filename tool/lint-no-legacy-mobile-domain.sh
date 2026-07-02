#!/usr/bin/env bash
# Boundary lint: the old mobile top-level `domain/` package has been retired.
#
# Finance-owned money and FX calculation types live under
# `features/finance/domain/fx/`. New shared primitives belong in `core/` only
# when they are truly domain-neutral.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for dir in \
  "$ROOT/apps/mobile/lib/domain" \
  "$ROOT/apps/mobile/test/domain"; do
  if [[ -d "$dir" ]] && find "$dir" -type f | grep -q .; then
    echo "✖ legacy mobile domain files found under ${dir#$ROOT/}" >&2
    echo "Move Finance-specific values to apps/mobile/lib/features/finance/domain/fx/." >&2
    exit 1
  fi
done

for file in \
  "$ROOT/apps/mobile/lib/features/finance/domain/models/money.dart" \
  "$ROOT/apps/mobile/lib/features/finance/domain/models/money.freezed.dart" \
  "$ROOT/apps/mobile/lib/features/finance/domain/models/fx_rate.dart" \
  "$ROOT/apps/mobile/lib/features/finance/domain/models/fx_rate.freezed.dart"; do
  if [[ -e "$file" ]]; then
    echo "✖ duplicate Finance money/FX model found: ${file#$ROOT/}" >&2
    echo "Use apps/mobile/lib/features/finance/domain/fx/ as the single owner." >&2
    exit 1
  fi
done

violations="$(grep -RInE --include='*.dart' \
  "^[[:space:]]*import[[:space:]]+['\"][^'\"]*(package:naviwealth/domain/|(\.\./)+domain/(values/money|entities/fx_rate|services/currency_converter)\.dart|package:naviwealth/features/finance/domain/models/(money|fx_rate)\.dart)" \
  "$ROOT/apps/mobile/lib" \
  "$ROOT/apps/mobile/test" \
  "$ROOT/apps/mobile/integration_test" \
  || true)"

if [[ -n "$violations" ]]; then
  echo "✖ legacy mobile domain imports found:" >&2
  echo "$violations" >&2
  echo >&2
  echo "Use package:naviwealth/features/finance/domain/fx/<type>.dart for Finance money/FX types." >&2
  exit 1
fi

echo "✓ legacy mobile domain package stays retired."
