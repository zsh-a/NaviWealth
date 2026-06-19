#!/usr/bin/env bash
# W-D7 removed the Rust AI contract mirror. The remaining AI wire
# contracts are mobile-local and are guarded by a generated enum manifest
# plus Dart roundtrip tests.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
"$ROOT/tool/check-ai-contract-wire-enums.sh"
cd "$ROOT/apps/mobile"

flutter test test/core/ai/contracts/contracts_roundtrip_test.dart
