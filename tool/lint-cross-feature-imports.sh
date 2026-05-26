#!/usr/bin/env bash
# Boundary lint: `features/<A>/` may not import `features/<B>/`
# (`docs/lifeos-shell.md` §4 + northstar §2.4, D-1.6 + D-1.6b).
#
# Scope today: only `features/ai_chat/` is enforced — Phase D-1.6
# targets the chat-context composition root. The rest of the
# features/ tree has plenty of historical cross-feature imports
# (settings → analytics/expense/fire/rebalance, home → cashflow/fire,
# etc.); a tree-wide enforcement is out of scope for D-1 and would
# require a snapshot-based allowlist with hundreds of entries. The
# composition pattern proven by ai_chat will be extended to other
# features in follow-up cleanup waves.
#
# `features/shared/` is the cross-feature design-system shim and is
# allowed everywhere.
#
# D-1.6b (2026-05-26) cleared all grandfathered files: the chat
# trace preparer + ai context summary + proposal applier + portfolio
# snapshot all moved to `features/finance/composition/` behind
# `core/ai/composition/` seams. `features/ai_chat/` no longer
# imports any sibling feature.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FEATURES="$ROOT/apps/mobile/lib/features/ai_chat"

# No grandfathered files remain after D-1.6b.
GRANDFATHERED_REGEX=""

violations=""
# Only an `../../<X>/` (exactly two-up, no more `..`) from a file in
# `features/<A>/<sub>/` lands in `features/<X>/`. Three-up
# (`../../../<X>/`) leaves the features/ tree entirely (core/, app/,
# design_system/, l10n/) so it's not a cross-feature import.
while IFS= read -r line; do
  # `line` is `<path>:<lineno>:<text>` from grep -n.
  path="${line%%:*}"
  rest="${line#*:}"

  # Strip the shared/ allowlist directly in the grep pattern.
  if [[ "$rest" =~ features/shared/ || "$rest" =~ \.\./shared/ ]]; then
    continue
  fi
  # Skip files in the explicit grandfather list.
  skip=0
  while IFS= read -r pat; do
    [[ -z "$pat" ]] && continue
    if [[ "$path" =~ $pat ]]; then
      skip=1
      break
    fi
  done <<< "$GRANDFATHERED_REGEX"
  if [[ $skip -eq 1 ]]; then continue; fi

  # Match an import that goes exactly two levels up (so the second
  # path segment is a sibling feature directory). Pattern:
  # `'../../<X>/...'` where `<X>` is `[a-z_]+` and the prefix is
  # NOT `'../../../` (three-up).
  if [[ "$rest" =~ \'\.\./\.\./[a-z_]+/ && ! "$rest" =~ \'\.\./\.\./\.\./ ]]; then
    src_feature="$(echo "$path" | sed -nE 's@.*features/([a-z_]+)/.*@\1@p')"
    imp_feature="$(echo "$rest" | sed -nE "s@.*'\.\./\.\./([a-z_]+)/.*@\1@p")"
    if [[ -n "$src_feature" && -n "$imp_feature" && "$src_feature" != "$imp_feature" ]]; then
      violations+="$line"$'\n'
    fi
  fi
done < <(grep -rnE --include='*.dart' "^import '\.\./\.\./" "$FEATURES" || true)

if [[ -n "$violations" ]]; then
  echo "✖ cross-feature import detected (D-1.6 boundary):" >&2
  echo "$violations" >&2
  exit 1
fi

echo "✓ features/<A>/ stays free of cross-feature imports (D-1.6)."
