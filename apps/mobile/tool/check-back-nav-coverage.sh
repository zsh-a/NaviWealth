#!/usr/bin/env bash
# Back-nav coverage guard.
#
# IA contract §1 (apps/mobile/docs/design/00-information-architecture.md):
# only the four primary tab pages (Today / Activity / Wealth / Plan) may
# render an FHeader.nested without a back arrow. Every other page that
# owns its scaffold must surface a back arrow — otherwise a user who
# pushed into it via deep link or sibling navigation has no way out
# besides the system gesture, which doesn't exist on web.
#
# This script greps every lib/features/**/*.dart file that uses
# `FHeader.nested(` and fails if the file does not also reference
# `backHeaderAction` or `appSubPageHeader` — i.e. the back action is
# either inlined or injected by the shared sub-page wrapper.
#
# Exceptions are listed explicitly below in two allowlists:
#   TAB_PAGES        — top-level tab pages (no back arrow by design)
#   EMBEDDED_HEADERS — widgets whose FHeader.nested is only rendered
#                      inside another scaffold (master-detail empty
#                      states, etc.) — they're never the back-target.
#
# Exit codes:
#   0 — every non-allowlisted page has a back action wired
#   1 — at least one page is missing back-nav coverage
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

# Top-level tab pages — these intentionally have NO back arrow because
# they are the back target of every other page.
TAB_PAGES=(
  "lib/features/home/home_page.dart"
  "lib/features/activity/activity_page.dart"
  "lib/features/finance/ui/wealth/wealth_hub_page.dart"
  "lib/features/finance/ui/plan_hub_page.dart"
)

# Files whose FHeader.nested is NOT a stranded pushed page:
#   * detail-pane empty states in master-detail layouts (back lives on
#     the master pane);
#   * fullscreen modals that surface their own × close icon instead of
#     the arrow.
EMBEDDED_HEADERS=(
  "lib/features/assets/ui/assets_list_body.dart"
  # Fullscreen chart modal — wires Navigator.pop directly on Icons.close.
  "lib/features/home/ui/dashboard_chart_fullscreen.dart"
  # accounts_master.dart hosts both a sub-page scaffold (with back) and
  # the master-detail empty pane (no back); the file passes the grep
  # because the sub-page scaffold imports the back primitive.
)

is_allowlisted() {
  local file="$1"
  local entry
  for entry in "${TAB_PAGES[@]}" "${EMBEDDED_HEADERS[@]}"; do
    [[ "${file}" == "${entry}" ]] && return 0
  done
  return 1
}

missing=()
while IFS= read -r file; do
  is_allowlisted "${file}" && continue
  if ! grep -qE 'backHeaderAction|appSubPageHeader' "${file}"; then
    missing+=("${file}")
  fi
done < <(grep -rl 'FHeader\.nested(' lib/features lib/app 2>/dev/null | sort)

# Also: any page wired into the router as a top-level (off-shell) push
# target — Settings is the canonical example — MUST have back coverage.
# Same check, just makes the intent obvious in the failure message.
SETTINGS_PAGE="lib/features/settings/settings_page.dart"
if [[ -f "${SETTINGS_PAGE}" ]] && \
   ! grep -qE 'backHeaderAction|appSubPageHeader|AppPageScaffold' "${SETTINGS_PAGE}"; then
  missing+=("${SETTINGS_PAGE} (off-shell root — back is critical)")
fi

if (( ${#missing[@]} > 0 )); then
  printf '::error::back-nav coverage: pages with FHeader.nested but no back action wired\n'
  for f in "${missing[@]}"; do
    printf '  - %s\n' "${f}"
  done
  printf '\nFix by switching to `appSubPageHeader(...)` from\n'
  printf '`lib/design_system/widgets/back_header_action.dart`,\n'
  printf 'or — if the page is intentionally a back-target — add it to\n'
  printf 'TAB_PAGES / EMBEDDED_HEADERS in tool/check-back-nav-coverage.sh.\n'
  exit 1
fi

printf 'back-nav coverage: ok (every non-tab FHeader.nested page wires a back action)\n'
