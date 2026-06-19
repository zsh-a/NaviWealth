#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

# These generated font assets are only needed so Flutter can resolve the test
# asset bundle. The baseline tests below do not rasterize real glyphs.
mkdir -p assets/fonts
touch assets/fonts/app-cn-base.woff2 assets/fonts/app-cn-ext.woff2
touch assets/fonts/inter-regular.woff2 assets/fonts/inter-medium.woff2 \
  assets/fonts/inter-semibold.woff2 assets/fonts/inter-bold.woff2 \
  assets/fonts/outfit-bold.woff2

flutter test \
  test/design_system/delta_text_test.dart \
  test/design_system/skeleton_test.dart \
  test/core/ai/visual/ai_markdown_test.dart \
  test/core/perf/frame_timing_collector_test.dart \
  test/core/perf/perf_trace_recorder_test.dart \
  test/design_system/charts/downsample_test.dart \
  test/features/investment/domain/returns/xirr_engine_test.dart \
  --reporter=expanded
