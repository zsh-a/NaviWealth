#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$repo_root/apps/mobile/tool/check-l10n-parity.sh"
"$repo_root/apps/mobile/tool/check-back-nav-coverage.sh"
"$repo_root/tool/check-ai-contract-wire-enums.sh"
"$repo_root/tool/check-sync-client-wire-fixtures.sh"
"$repo_root/tool/lint-motion-policy.sh"
"$repo_root/tool/lint-no-feature-in-shared.sh"
"$repo_root/tool/lint-cross-feature-imports.sh"
"$repo_root/tool/lint-finance-domain-data-imports.sh"
"$repo_root/tool/lint-domain-neutral-contracts.sh"
"$repo_root/tool/lint-frb-llm-entrypoints.sh"
"$repo_root/tool/lint-theme-layering.sh"
"$repo_root/tool/lint-material-chrome.sh"
"$repo_root/tool/lint-format-path.sh"
"$repo_root/tool/lint-typography.sh"
