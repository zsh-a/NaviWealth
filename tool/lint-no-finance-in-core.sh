#!/usr/bin/env bash
# Boundary lint: `core/ai/runtime/` is the shell-only AI runtime
# (`docs/architecture/lifeos-shell.md` §7.1, D-1.2). It must not import from
# `features/<domain>/`.
#
# Phase D-1.2 ships the DomainPack composition root + `deviceToolsProvider`
# so each domain registers its own tools. The old Finance tool cluster has
# moved out of `core/ai/runtime/device/tools/`; this script protects against
# regressions by linting new shell runtime imports.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME="$ROOT/apps/mobile/lib/core/ai/runtime"

# Search `core/ai/runtime/` for any feature-domain import. Only `import`
# statements count — doc-comment mentions are explicitly excluded so
# contextual references don't trigger the lint.
violations="$(grep -rnE --include='*.dart' "^import\s+['\"][^'\"]*features/[a-z_]+/" "$RUNTIME" \
  || true)"

if [[ -n "$violations" ]]; then
  echo "✖ core/ai/runtime/ imports features/ (boundary violation, D-1.2):" >&2
  echo "$violations" >&2
  echo >&2
  echo "Tools must live under features/<domain>/ai_tools/ and be" >&2
  echo "registered through the domain's DomainPack/deviceTools list." >&2
  exit 1
fi

echo "✓ core/ai/runtime/ stays domain-neutral (D-1.2 boundary holds)."
