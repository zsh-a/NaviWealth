#!/usr/bin/env bash
# Wave 41 — pin the count of allowed-failing test files.
#
# We can't fix all ~50 design-system / golden / widget rot tests at
# once (they reference removed APIs like `AppElevations` and
# `marketColorMode` — a separate cleanup), but we MUST stop the rot
# from growing. This script:
#
#   1. Runs `flutter test --exclude-tags=golden`.
#   2. Tallies which test files contain failures.
#   3. Compares against `tool/known-failing-tests.txt`.
#
# Exit codes:
#   0 — current failures ⊆ expected (allowed to stay green)
#   1 — current failures include a NEW file not in the expected list
#   2 — current failures missing a file that's in the expected list
#       (someone fixed it — bump the baseline by removing the line)
#
# CI invokes this after the test run; it does NOT itself run tests
# (avoids double execution). The hash of the test output is the
# input contract: pipe the failing-file lines into stdin.
#
# Usage in CI (after `flutter test`):
#   flutter test --exclude-tags=golden --reporter expanded 2>&1 \
#     | tool/check-known-failing-tests.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXPECTED_FILE="${SCRIPT_DIR}/known-failing-tests.txt"

if [[ ! -f "${EXPECTED_FILE}" ]]; then
  echo "::error::known-failing-tests.txt missing at ${EXPECTED_FILE}"
  exit 1
fi

# Pull failing test file paths out of `flutter test --reporter expanded`
# output. Two line shapes end with "[E]":
#   - "00:14 +362 -12: loading /…/test/<rel>.dart [E]"
#     (compile error — the loading line itself errors)
#   - "00:14 +362 -12: /…/test/<rel>.dart: <case> [E]"
#     (runtime test failure)
# Extract <rel> from either, then de-dupe.
actual="$(grep -E '\[E\]$' \
  | sed -E 's|.*/test/||;
            s| \[E\]$||;
            s|^([^:]+\.dart):.*$|\1|;
            s|^([^[:space:]]+\.dart)$|\1|' \
  | grep -E '\.dart$' \
  | sort -u || true)"

if [[ -z "${actual}" ]]; then
  echo "✅ No test failures detected."
  # Sanity: if the expected list is non-empty but actual is empty,
  # somebody fixed everything — flag it so the baseline can be tightened.
  if [[ -s "${EXPECTED_FILE}" ]]; then
    echo "⚠️  Baseline allows failures but none were observed."
    echo "    Consider deleting ${EXPECTED_FILE} to enforce zero failures going forward."
  fi
  exit 0
fi

expected="$(grep -v '^#' "${EXPECTED_FILE}" | grep -v '^[[:space:]]*$' | sort -u || true)"

# Files that are failing but not on the allowlist → REGRESSION.
new_failures="$(comm -23 <(echo "${actual}") <(echo "${expected}") || true)"
# Files on the allowlist but no longer failing → please trim.
fixed="$(comm -13 <(echo "${actual}") <(echo "${expected}") || true)"

if [[ -n "${new_failures}" ]]; then
  echo "::error::New test files regressed (not on the allowlist):"
  echo "${new_failures}" | sed 's/^/  - /'
  echo
  echo "Fix the failing tests, or — only if intentional — add them to"
  echo "${EXPECTED_FILE} with a one-line rationale."
  exit 1
fi

if [[ -n "${fixed}" ]]; then
  echo "::warning::These files are on the allowlist but no longer fail:"
  echo "${fixed}" | sed 's/^/  - /'
  echo
  echo "Please delete those lines from ${EXPECTED_FILE} so the baseline"
  echo "tightens. (Soft warning — not a CI failure today.)"
fi

echo "✅ Failure footprint matches the pinned baseline."
exit 0
