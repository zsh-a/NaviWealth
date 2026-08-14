#!/usr/bin/env bash
# Interaction primitives lint (P2 interaction convergence).
#
# Standard taps go through AppTappable (focus ring, hover, uniform
# AppInteraction feedback); plain-tap raw GestureDetector sites bypass that
# contract and must not grow. Remaining raw GestureDetector uses are
# non-tap gestures or inline text links (e.g. knowledge markdown links).
#
# Icon-only buttons use FButton.icon; icon+label buttons use Forui's
# documented FButton(prefix:/suffix:) layout — hand-rolled Row(Icon, Text)
# button content is the ad-hoc pattern this guards against. The FButton
# prefix count is ratcheted so new icon+label call sites get an explicit
# design-system review instead of spreading unchecked.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$ROOT/apps/mobile/lib"

# P2 baseline: 5 in features/ai_chat (owned separately) + 1 inline markdown
# link in features/knowledge (MouseRegion + link semantics, not a row tap).
GD_BASELINE=6
gd_count="$({ grep -RhoE --include='*.dart' 'GestureDetector\(' \
  "$LIB/features" "$LIB/app" || true; } | wc -l | tr -d ' ')"

if (( gd_count > GD_BASELINE )); then
  echo "✖ Raw GestureDetector usage grew: $gd_count > baseline $GD_BASELINE." >&2
  grep -RInE --include='*.dart' 'GestureDetector\(' \
    "$LIB/features" "$LIB/app" | tail -n 20 >&2
  echo >&2
  echo "Use AppTappable for plain tap targets (rows, tiles, cells)." >&2
  exit 1
fi

# Count plain FButton( calls whose argument list passes `prefix:` (paren-depth
# tracked so multi-line argument lists are covered).
PREFIX_BASELINE=71
prefix_count="$(
  grep -rlE --include='*.dart' '(^|[^A-Za-z_])FButton\(' "$LIB/features" |
    while read -r f; do
      awk '
        /(^|[^A-Za-z_])FButton\(/ { if (!inb) { inb=1; depth=0 } }
        inb {
          line=$0
          opens=gsub(/\(/,"(",line)
          closes=gsub(/\)/,")",line)
          if ($0 ~ /^[[:space:]]*prefix:/) c++
          depth+=opens-closes
          if (depth<=0) inb=0
        }
        END { print c+0 }
      ' "$f"
    done | awk '{s+=$1} END {print s+0}'
)"

if (( prefix_count > PREFIX_BASELINE )); then
  echo "✖ FButton icon+label usage grew: $prefix_count > baseline $PREFIX_BASELINE." >&2
  echo >&2
  echo "Icon-only buttons must use FButton.icon; icon+label uses Forui's" >&2
  echo "FButton(prefix:) layout — never a hand-rolled Row(Icon, Text) child." >&2
  echo "Bump the baseline only with design-system sign-off." >&2
  exit 1
fi

echo "✓ interaction primitives ok (GestureDetector $gd_count/$GD_BASELINE, FButton prefix $prefix_count/$PREFIX_BASELINE)"
