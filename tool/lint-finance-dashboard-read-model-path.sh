#!/usr/bin/env bash
# Boundary lint: Finance dashboard read models live in
# `features/finance/application/read_models/`, not under the Home UI slice.
#
# The old `features/finance/home/data/dashboard_providers.dart` path remains
# as a compatibility export only. New imports must target the application
# read-model package path directly.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export LINT_ROOT="$ROOT"

violations="$(python3 <<'PY'
import os
import re
from pathlib import Path

root = Path(os.environ["LINT_ROOT"]).resolve()
mobile_lib = root / "apps/mobile/lib"
shim = mobile_lib / "features/finance/home/data/dashboard_providers.dart"
target = "features/finance/home/data/dashboard_providers.dart"
directive_re = re.compile(r"^\s*(import|export)\s+['\"]([^'\"]+)['\"]")

hits = []
for base in (root / "apps/mobile/lib", root / "apps/mobile/test"):
    for path in sorted(base.rglob("*.dart")):
        if path.resolve() == shim.resolve():
            continue
        for lineno, line in enumerate(path.read_text().splitlines(), start=1):
            match = directive_re.match(line)
            if not match:
                continue
            uri = match.group(2)
            resolves_to_old_path = False
            if uri == f"package:naviwealth/{target}":
                resolves_to_old_path = True
            elif uri.startswith("."):
                try:
                    resolved = (path.parent / uri).resolve()
                    resolves_to_old_path = resolved == shim.resolve()
                except OSError:
                    resolves_to_old_path = False
            elif uri.endswith("/dashboard_providers.dart"):
                # Catch common relative imports without a leading `./`, e.g.
                # `import 'data/dashboard_providers.dart';`.
                try:
                    resolved = (path.parent / uri).resolve()
                    resolves_to_old_path = resolved == shim.resolve()
                except OSError:
                    resolves_to_old_path = False
            if resolves_to_old_path:
                rel = path.relative_to(root)
                hits.append(f"{rel}:{lineno}: import application/read_models/dashboard_providers.dart instead")

print("\n".join(hits))
PY
)"

if [[ -n "$violations" ]]; then
  echo "✖ Finance dashboard read-model imports use the retired Home path:" >&2
  echo "$violations" >&2
  exit 1
fi

echo "✓ Finance dashboard read-model imports target the application layer."
