#!/usr/bin/env bash
# Check that the device AI tool registry, the descriptor catalog, the
# intent policy, and the regression corpus stay in sync.
#
# `CLAUDE.md` references this command as the canonical "did I keep the
# tool surface honest" gate. Adding a new device tool requires:
#
#   1. A `DeviceTool` implementation registered in `kDeviceTools`
#      (`lib/core/ai/runtime/device/tools/device_tool_registry.dart`).
#   2. A matching `ToolDescriptor` entry in `allToolDescriptors`
#      (`lib/core/ai/contracts/tool_descriptor.dart`).
#   3. The expected name appearing in
#      `test/core/ai/runtime/device/device_degradation_test.dart`'s
#      "canonical set" expectation (sorted).
#   4. For tools used by intents, an entry in the regression corpus
#      (`lib/core/ai/regression/regression_corpus.dart`) and the
#      intent's `preferredReadModels`.
#
# This script just runs the existing CI tests that already cover each
# of those bullets — it's a developer shortcut, not new validation.
#
# Exit code: 0 if every check passes, non-zero if anything trips.

set -euo pipefail

cd "$(dirname "$0")/.."

# `flutter test` returns 1 if any test fails; the `set -e` above lets
# that propagate. Each file targets one of the contract surfaces:
#
#   contracts_roundtrip_test  — descriptor catalog length + JSON shape.
#   device_degradation_test   — registry membership = expected set,
#                               sorted. Also: every descriptor name
#                               resolves to a registered tool.
#   fire_tools_contract_test  — Phase-5 specific: the 8 FIRE OS tools +
#                               5 intents are present and consistent.
#   regression_corpus_test    — every intent has ≥1 corpus prompt, and
#                               every expected tool is reachable from
#                               the intent's preferredReadModels.
exec flutter test \
  test/core/ai/contracts/contracts_roundtrip_test.dart \
  test/core/ai/runtime/device/device_degradation_test.dart \
  test/core/ai/fire_tools_contract_test.dart \
  test/core/ai/regression/regression_corpus_test.dart \
  "$@"
