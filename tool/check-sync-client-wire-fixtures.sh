#!/usr/bin/env bash
# Verifies checked-in sync-v2 client-push fixtures against the Dart serializer.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOBILE="${ROOT}/apps/mobile"
FIXTURES="${ROOT}/docs/fixtures"

actual="$(mktemp)"
trap 'rm -f "${actual}"' EXIT

check_fixture() {
  local fixture="$1"
  (
    cd "${MOBILE}"
    dart run tool/dump_sync_wire_fixture.dart "${fixture}"
  ) >"${actual}"
  diff -u "${FIXTURES}/${fixture}.json" "${actual}"
}

check_fixture sync_v2_client_push_row_change
check_fixture sync_v2_client_sync_request

echo "sync-v2 client fixtures match the Dart serializer."
