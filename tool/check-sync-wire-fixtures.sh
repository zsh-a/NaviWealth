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

check_fixture() {
  local fixture="$1"
  cargo run --quiet \
    --manifest-path "${BACKEND}/Cargo.toml" \
    --bin dump-sync-wire-fixture \
    -- "${fixture}" >"${actual}"
  diff -u "${FIXTURES}/${fixture}.json" "${actual}"
}

check_fixture sync_v2_server_tombstone_row_change
check_fixture sync_v2_server_sync_response
check_fixture sync_v2_server_empty_response
check_fixture sync_v2_server_more_response
check_fixture sync_v2_server_no_accepted_response

echo "sync-v2 server fixtures match the Rust serializer."
