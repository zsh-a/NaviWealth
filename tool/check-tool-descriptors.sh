#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# W-D7 removed the backend AI registry and its `tool_descriptor_dump`
# binary. The active contract is now mobile-local: every descriptor in
# `tool_descriptor.dart` must correspond to a registered device tool,
# and every registered device tool must have descriptor metadata.
cd "$ROOT/apps/mobile"
flutter test \
  test/core/ai/contracts/contracts_roundtrip_test.dart \
  test/core/ai/runtime/device/device_degradation_test.dart
