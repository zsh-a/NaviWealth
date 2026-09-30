#!/usr/bin/env bash
# Boundary lint: shared mobile layers must not import or export feature code.
#
# `core/` and `design_system/` are reusable infrastructure and widget layers.
# Domain/product code flows inward from `features/` to
# these layers, never the other way around. App composition is the place where
# feature modules are assembled.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export LINT_ROOT="$ROOT"

violations="$(python3 -B <<'PY'
import os
from pathlib import Path
import sys

root = Path(os.environ["LINT_ROOT"]).resolve()
sys.path.insert(0, str(root / "tool"))
from dart_dependencies import feature_for_path, iter_dart_dependencies

lib_root = root / "apps/mobile/lib"
features_root = lib_root / "features"
for layer in ("core", "design_system"):
    for path in sorted((lib_root / layer).rglob("*.dart")):
        for edge in iter_dart_dependencies(path, lib_root):
            if feature_for_path(edge.target, features_root) is not None:
                print(
                    f"{path.relative_to(root)}:{edge.line}: "
                    f"{edge.directive} {edge.uri}"
                )
PY
)"

if [[ -n "$violations" ]]; then
  echo "✖ shared layer depends on features/ (boundary violation):" >&2
  echo "$violations" >&2
  echo >&2
  echo "Move domain-specific code under features/<domain>/, or expose a" >&2
  echo "domain-neutral contract from core/design_system and wire it" >&2
  echo "from apps/mobile/lib/app/." >&2
  exit 1
fi

echo "✓ shared layers stay free of feature imports and exports."
