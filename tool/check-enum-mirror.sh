#!/usr/bin/env bash
# W-D7 removed the Rust AI contract mirror. The remaining AI wire
# contracts are mobile-local and are guarded by Dart roundtrip tests.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT/apps/mobile"

flutter test test/core/ai/contracts/contracts_roundtrip_test.dart
