#!/usr/bin/env bash
# Boundary lint: every `RowChange` emitted by the sync engine must
# carry a LifeOS domain prefix (`docs/lifeos-shell.md` §8, D-1.4).
#
# The shape today: `core/sync/sync_engine.dart::_toRowChange` calls
# `prefixFinanceTable(table)` so all outbound rows start with `fin:`.
# This script protects against a future regression where someone
# constructs a bare `RowChange(table: '<localname>', ...)` outside the
# domain-prefix helpers.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SYNC="$ROOT/apps/mobile/lib/core/sync"

# Allowlist — files that *receive* RowChange (from the wire / fakes /
# tests) are exempt from the producer-side guarantee. Producer files
# must funnel through the prefix helpers in `domain_prefix.dart`.
ALLOWLISTED='/sync_api_client\.dart|/dio_sync_api_client\.dart|/row_applier\.dart|/domain_prefix\.dart|/test/|/sync_engine_test'

# Match any `RowChange(... table: '<literal>'` invocation. The
# literal is then checked: must start with `fin:` / `health:` / it
# may also be a known prefix-helper call.
hits="$(grep -rnE --include='*.dart' "RowChange\(" "$SYNC" \
  | grep -E "table:[[:space:]]*'[^']+'" \
  | grep -vE "$ALLOWLISTED" \
  || true)"

bad=""
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  # Extract the literal between single quotes following `table:`.
  literal="$(echo "$line" | sed -nE "s@.*table:[[:space:]]*'([^']+)'.*@\1@p")"
  [[ -z "$literal" ]] && continue
  if [[ ! "$literal" =~ ^(fin|health): ]]; then
    bad+="$line"$'\n'
  fi
done <<< "$hits"

if [[ -n "$bad" ]]; then
  echo "✖ RowChange emitted without a recognised domain prefix (D-1.4):" >&2
  echo "$bad" >&2
  echo "Use prefixFinanceTable() / prefixHealthTable() from" >&2
  echo "lib/core/sync/domain_prefix.dart." >&2
  exit 1
fi

echo "✓ Every sync RowChange producer carries a domain prefix (D-1.4)."
