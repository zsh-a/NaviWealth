#!/usr/bin/env bash
# Verifies apps/mobile/design_tokens/tokens.json matches the Dart
# design-system tokens.
#
# Dart (apps/mobile/lib/design_system) is the source of truth; tokens.json
# is a generated export for design tools. The exporter imports Flutter
# types, so it runs through a flutter-test wrapper instead of `dart run` —
# see apps/mobile/design_tokens/README.md.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOBILE="${ROOT}/apps/mobile"
COMMITTED="${MOBILE}/design_tokens/tokens.json"

actual="$(mktemp)"
log="$(mktemp)"
trap 'rm -f "${actual}" "${log}"' EXIT

if (
  cd "${MOBILE}"
  DESIGN_TOKENS_OUT="${actual}" flutter test \
    test/tools/export_design_tokens_test.dart
) >"${log}" 2>&1; then
  echo "design_tokens/tokens.json matches the Dart design-system tokens."
  exit 0
fi

if [[ -s "${actual}" ]] && ! diff -u "${COMMITTED}" "${actual}"; then
  echo >&2
  echo "error: apps/mobile/design_tokens/tokens.json is stale — the Dart" >&2
  echo "design-system tokens have changed (Dart is the source of truth)." >&2
  echo "Regenerate it with:" >&2
  echo "  cd apps/mobile && UPDATE_DESIGN_TOKENS=1 flutter test test/tools/export_design_tokens_test.dart" >&2
else
  # The exporter itself failed (compile error, missing file, ...).
  cat "${log}" >&2
fi
exit 1
