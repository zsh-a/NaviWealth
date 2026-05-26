#!/usr/bin/env bash
# Boundary lint: the cross-domain shell contracts (`core/ai/contracts/`
# + `core/sync/`) stay free of any finance / health / time / domain-
# specific terminology (`docs/lifeos-shell.md` §11 + northstar §2.5).
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

# Domain words that must not appear in shell contracts. The list is
# narrow — boundary policy is enforced by absence of these names, not
# by a generic word-blocklist.
#
# Excluded substrings (technical positives that are *not* domain
# leaks): the LifeOS `domain` field itself (D-1.3 introduced it as a
# typed namespace), and the `domain_prefix` helper module (D-1.4
# defines the namespace).
DOMAIN_WORDS='\b(Money|Account[A-Z]|JournalEntry|Posting|Holding|Liability|FirePlan|FireBucket|TradeJournal|SleepSession|HrvDaily)\b'

# Allow the namespacing helpers themselves to reference domains as
# string literals (they're the boundary, not a violation of it).
ALLOWLIST='/core/sync/domain_prefix\.dart|/core/ai/contracts/intent\.dart|/core/ai/contracts/tool_descriptor\.dart'

violations=""
for dir in "${TARGETS[@]}"; do
  hits="$(grep -rnE --include='*.dart' "$DOMAIN_WORDS" "$dir" || true)"
  if [[ -n "$hits" ]]; then
    filtered="$(echo "$hits" | grep -vE "$ALLOWLIST" || true)"
    if [[ -n "$filtered" ]]; then
      violations+="$filtered"$'\n'
    fi
  fi
done

if [[ -n "$violations" ]]; then
  echo "✖ Domain term leaked into shell contracts (D-1 boundary):" >&2
  echo "$violations" >&2
  exit 1
fi

echo "✓ Shell contracts stay domain-neutral (D-1)."
