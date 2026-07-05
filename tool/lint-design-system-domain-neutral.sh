#!/usr/bin/env bash
# Boundary lint: design-system code must not import domain value/business code.
#
# Design-system widgets should accept primitives or UI-only display DTOs so they
# remain reusable across LifeOS domains.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

violations="$(grep -RInE --include='*.dart' \
  "^[[:space:]]*import[[:space:]]+['\"][^'\"]*(package:naviwealth/domain/|(\.\./)+domain/)" \
  "$ROOT/apps/mobile/lib/design_system" \
  "$ROOT/apps/mobile/test/design_system" \
  || true)"

if [[ -n "$violations" ]]; then
  echo "✖ design_system imports domain/ (boundary violation):" >&2
  echo "$violations" >&2
  echo >&2
  echo "Keep business value objects outside design_system. Pass primitives" >&2
  echo "or UI-only display DTOs at the widget boundary instead." >&2
  exit 1
fi

echo "✓ design_system stays domain-neutral."
