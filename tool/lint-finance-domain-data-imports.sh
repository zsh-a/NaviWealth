#!/usr/bin/env bash
# Boundary lint: Finance domain code must not depend on data/repository or
# Drift row ownership. Data/application layers adapt persistence rows into
# domain inputs.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

violations="$(
  find \
    "$ROOT/apps/mobile/lib/features/finance" \
    "$ROOT/apps/mobile/test/features/finance" \
    -path '*/domain/*.dart' \
    -type f \
    -print0 |
    xargs -0 grep -nE \
      "import ['\"]package:naviwealth/features/finance/.*/data/|import ['\"](\.\./)+data/|import ['\"]package:naviwealth/core/persistence/app_database.dart" \
      || true
)"

if [[ -n "$violations" ]]; then
  echo "✖ Finance domain imports data-layer or Drift row code:" >&2
  echo "$violations" >&2
  echo >&2
  echo "Move row/repository adapters to data or application read-model layers." >&2
  exit 1
fi

echo "✓ Finance domain stays free of data-layer imports."
