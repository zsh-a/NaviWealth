#!/usr/bin/env bash
# Boundary lint: Finance core models belong to `features/finance/domain/models/`,
# not under the data layer. Reintroducing `features/finance/data/domain/` makes
# repository DTOs and business models look like the same ownership boundary.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for dir in \
  "$ROOT/apps/mobile/lib/features/finance/data/domain" \
  "$ROOT/apps/mobile/test/features/finance/data/domain"; do
  if [[ -d "$dir" ]]; then
    echo "✖ legacy Finance model directory exists: ${dir#$ROOT/}" >&2
    echo "Move Finance core models to apps/mobile/lib/features/finance/domain/models/." >&2
    exit 1
  fi
done

violations="$(grep -RInE --include='*.dart' \
  "features/finance/data/domain|data/domain/" \
  "$ROOT/apps/mobile/lib" \
  "$ROOT/apps/mobile/test" \
  "$ROOT/apps/mobile/integration_test" \
  || true)"

if [[ -n "$violations" ]]; then
  echo "✖ legacy Finance data/domain references found:" >&2
  echo "$violations" >&2
  echo >&2
  echo "Use package:naviwealth/features/finance/domain/models/<model>.dart instead." >&2
  exit 1
fi

echo "✓ Finance core models stay outside data/domain."
