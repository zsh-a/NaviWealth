#!/usr/bin/env bash
# Boundary lint: shared mobile layers must not import feature code.
#
# `core/`, `domain/`, and `design_system/` are reusable infrastructure and
# value/widget layers. Domain/product code flows inward from `features/` to
# these layers, never the other way around. App composition is the place where
# feature modules are assembled.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

violations="$(grep -RInE --include='*.dart' \
  "^[[:space:]]*import[[:space:]]+['\"][^'\"]*features/" \
  "$ROOT/apps/mobile/lib/core" \
  "$ROOT/apps/mobile/lib/domain" \
  "$ROOT/apps/mobile/lib/design_system" \
  || true)"

if [[ -n "$violations" ]]; then
  echo "✖ shared layer imports features/ (boundary violation):" >&2
  echo "$violations" >&2
  echo >&2
  echo "Move domain-specific code under features/<domain>/, or expose a" >&2
  echo "domain-neutral contract from core/domain/design_system and wire it" >&2
  echo "from apps/mobile/lib/app/." >&2
  exit 1
fi

echo "✓ shared layers stay free of feature imports."
