#!/usr/bin/env bash
# UI motion must flow through AppMotionPolicy so reduced-motion behavior stays
# consistent across features, routes, heroes, and continuous controllers.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$ROOT/apps/mobile/lib"
POLICY="$LIB/design_system/tokens/app_motion_policy.dart"
ROUTE_FACTORY="$LIB/design_system/widgets/app_page_route.dart"
HERO_FACTORY="$LIB/design_system/widgets/optional_hero.dart"

failures=()

while IFS= read -r match; do
  [[ -z "$match" ]] || failures+=("direct system motion check: $match")
done < <(
  grep -RIn --include='*.dart' 'MediaQuery\.disableAnimationsOf' "$LIB" \
    | grep -v "^$POLICY:" || true
)

while IFS= read -r match; do
  [[ -z "$match" ]] || failures+=("legacy motion helper: $match")
done < <(
  grep -RInE --include='*.dart' 'motionDuration\(|AiMotion\.duration\(' \
    "$LIB" || true
)

while IFS= read -r match; do
  [[ -z "$match" ]] || failures+=("direct PageRouteBuilder: $match")
done < <(
  grep -RIn --include='*.dart' 'PageRouteBuilder' "$LIB" \
    | grep -v "^$ROUTE_FACTORY:" || true
)

while IFS= read -r match; do
  [[ -z "$match" ]] || failures+=("direct Hero: $match")
done < <(
  grep -RInE --include='*.dart' '(^|[^A-Za-z])Hero\(' "$LIB" \
    | grep -v "^$HERO_FACTORY:" || true
)

while IFS= read -r file; do
  if ! grep -q 'AppMotionPolicy' "$file"; then
    failures+=("AnimationController without AppMotionPolicy: $file")
  fi
done < <(grep -Rl --include='*.dart' 'AnimationController' "$LIB" || true)

while IFS= read -r file; do
  if ! grep -q 'AppMotionPolicy' "$file"; then
    failures+=("repeating animation without AppMotionPolicy: $file")
  fi
done < <(grep -RlE --include='*.dart' '\.repeat\(' "$LIB" || true)

while IFS= read -r file; do
  if ! grep -q 'transitionDuration: AppMotionPolicy\.duration' "$file"; then
    failures+=("showGeneralDialog without policy duration: $file")
  fi
done < <(grep -Rl --include='*.dart' 'showGeneralDialog' "$LIB" || true)

if (( ${#failures[@]} > 0 )); then
  printf '✖ motion policy violations:\n' >&2
  printf '  - %s\n' "${failures[@]}" >&2
  exit 1
fi

echo '✓ application motion is routed through AppMotionPolicy.'
