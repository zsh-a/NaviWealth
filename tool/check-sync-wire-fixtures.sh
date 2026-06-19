#!/usr/bin/env bash
# Verifies checked-in sync-v2 wire fixtures against the Rust serializer.
#
# The Dart client consumes docs/fixtures/*.json directly. This gate keeps the
# server-owned outbound fixture generated from the actual Rust RowChange
# serializer instead of relying on a hand-maintained JSON copy.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND="${ROOT}/apps/backend"
FIXTURES="${ROOT}/docs/fixtures"

actual="$(mktemp)"
trap 'rm -f "${actual}"' EXIT

cargo run --quiet \
  --manifest-path "${BACKEND}/Cargo.toml" \
  --bin dump-sync-wire-fixture \
  -- sync_v2_server_tombstone_row_change >"${actual}"

diff -u "${FIXTURES}/sync_v2_server_tombstone_row_change.json" "${actual}"
echo "✓ sync-v2 wire fixtures match the Rust serializer."
