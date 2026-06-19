#!/usr/bin/env bash
# Verifies the checked-in AI contract enum wire manifest against Dart code.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOBILE="${ROOT}/apps/mobile"
FIXTURE="${ROOT}/docs/fixtures/ai_contract_wire_enums.json"

actual="$(mktemp)"
trap 'rm -f "${actual}"' EXIT

(
  cd "${MOBILE}"
  dart run tool/dump_ai_contract_wire_enums.dart
) >"${actual}"

diff -u "${FIXTURE}" "${actual}"
echo "AI contract wire enum manifest matches Dart code."
