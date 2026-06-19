#!/usr/bin/env bash
# Verifies checked-in sync-v2 client-push fixtures against the Dart serializer.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOBILE="${ROOT}/apps/mobile"
FIXTURES="${ROOT}/docs/fixtures"

actual="$(mktemp)"
trap 'rm -f "${actual}"' EXIT

(
  cd "${MOBILE}"
  dart run tool/dump_sync_wire_fixture.dart sync_v2_client_push_row_change
) >"${actual}"

diff -u "${FIXTURES}/sync_v2_client_push_row_change.json" "${actual}"
echo "sync-v2 client-push fixture matches the Dart serializer."
