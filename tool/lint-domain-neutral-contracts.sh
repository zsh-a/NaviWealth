#!/usr/bin/env bash
# Boundary lint: the cross-domain shell contracts (`core/ai/contracts/`
# + `core/sync/`) stay free of any finance / health / time / domain-
# specific terminology (`docs/architecture/lifeos-shell.md` §11 + northstar §2.5).
#
# The contracts ship the *shape* every domain uses; a domain word
# leaking into them creates an asymmetry that the next domain has to
# justify around. Catch this at lint time so a hurried PR doesn't add
# `Money` or `Account` or `SleepSession` to a shell type.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGETS=(
  "$ROOT/apps/mobile/lib/core/ai/contracts"
  "$ROOT/apps/mobile/lib/core/sync"
)

# Match complete business type families. A suffix must consume the full
# identifier: `Account[A-Z]` only matches a one-letter suffix and misses
# real contracts such as `AccountSummary`.
# Namespacing helpers need no file exemptions: lowercase domain identifiers
# do not match these business types, and must not hide future type leaks.
DOMAIN_WORDS='\b(Money|Account([A-Z][[:alnum:]_]*)?|Cashflow[A-Z][[:alnum:]_]*|JournalEntry([A-Z][[:alnum:]_]*)?|Posting([A-Z][[:alnum:]_]*)?|Holding([A-Z][[:alnum:]_]*)?|Liability([A-Z][[:alnum:]_]*)?|Fire(Plan|Bucket|Goal)([A-Z][[:alnum:]_]*)?|TradeJournal([A-Z][[:alnum:]_]*)?|SleepSession([A-Z][[:alnum:]_]*)?|HrvDaily([A-Z][[:alnum:]_]*)?)\b'

violations=""
for dir in "${TARGETS[@]}"; do
  hits="$(grep -rnE --include='*.dart' "$DOMAIN_WORDS" "$dir" || true)"
  if [[ -n "$hits" ]]; then
    violations+="$hits"$'\n'
  fi
done

if [[ -n "$violations" ]]; then
  echo "✖ Domain term leaked into shell contracts (D-1 boundary):" >&2
  echo "$violations" >&2
  exit 1
fi

echo "✓ Shell contracts stay domain-neutral (D-1)."
