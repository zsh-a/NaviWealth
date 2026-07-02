#!/usr/bin/env bash
# Boundary lint: `features/<A>/` may not import `features/<B>/`
# (`docs/architecture/lifeos-shell.md` §4 + northstar §2.4, D-1.6 + D-1.6b).
#
# Scope today: enforce clean cross-domain/product surfaces:
# `ai_chat/`, `auth/`, `settings/`, HealthOS, KnowledgeOS, and ExecutionOS. The rest of
# the features/ tree still has historical FinanceOS sibling imports
# (home → cashflow/fire, finance → legacy finance slices, etc.); a tree-wide
# enforcement remains out of scope until those slices are moved behind
# domain-local seams or a snapshot allowlist.
#
# D-1.6b (2026-05-26) cleared all grandfathered files for `ai_chat/`.
# Later shell cleanups also removed app/agent-runtime reverse dependencies
# from HealthOS, KnowledgeOS, and ExecutionOS; `auth/` and `settings/` are also
# sibling-free, so these surfaces are protected from sibling-feature imports too.
# The former `features/shared/` bucket has been split into `core/forms/` and
# `features/finance/shared/`; keep it empty so cross-feature "shared" code does
# not grow back. `features/plan/` and `features/wealth/` were also folded
# back into FinanceOS UI; keep those top-level pseudo-features empty too.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export LINT_ROOT="$ROOT"

violations="$(python3 <<'PY'
import os
import re
from pathlib import Path

root = Path(os.environ["LINT_ROOT"]).resolve()
features_root = root / "apps/mobile/lib/features"
protected = {"ai_chat", "auth", "settings", "health", "knowledge", "execution"}
import_re = re.compile(r"^\s*import\s+['\"]([^'\"]+)['\"]")

def feature_for_path(path):
    try:
        rel = path.resolve().relative_to(features_root.resolve())
    except ValueError:
        return None
    return rel.parts[0] if rel.parts else None

hits = []
retired_features = {
    "shared": (
        "features/shared is retired; move domain-neutral code to core/ "
        "or Finance-specific code to features/finance/shared/"
    ),
    "plan": (
        "features/plan is retired; move Plan tab code to features/finance/ui/"
    ),
    "wealth": (
        "features/wealth is retired; move Wealth tab code to "
        "features/finance/ui/wealth/"
    ),
}
for retired, message in retired_features.items():
    retired_root = features_root / retired
    for path in sorted(retired_root.rglob("*.dart")) if retired_root.exists() else []:
        rel = path.relative_to(root)
        hits.append(f"{rel}: {message}")

for feature in sorted(protected):
    for path in sorted((features_root / feature).rglob("*.dart")):
        src_feature = feature_for_path(path)
        if src_feature is None:
            continue
        for lineno, line in enumerate(path.read_text().splitlines(), start=1):
            match = import_re.match(line)
            if not match:
                continue
            uri = match.group(1)
            target_feature = None
            if uri.startswith("package:naviwealth/features/"):
                parts = uri.split("/")
                if len(parts) >= 3:
                    target_feature = parts[2]
            elif uri.startswith("."):
                target_feature = feature_for_path((path.parent / uri).resolve())
            if target_feature is None:
                continue
            if target_feature == src_feature:
                continue
            rel = path.relative_to(root)
            hits.append(
                f"{rel}:{lineno}: {src_feature} imports features/{target_feature}: {line.strip()}"
            )

print("\n".join(hits))
PY
)"

if [[ -n "$violations" ]]; then
  echo "✖ cross-feature import detected (D-1.6 boundary):" >&2
  echo "$violations" >&2
  exit 1
fi

echo "✓ protected features stay free of cross-feature imports (D-1.6)."
