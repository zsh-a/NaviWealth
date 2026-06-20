#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

required_fonts=(
  assets/fonts/app-cn-base.woff2
  assets/fonts/app-cn-ext.woff2
  assets/fonts/inter-regular.woff2
  assets/fonts/inter-medium.woff2
  assets/fonts/inter-semibold.woff2
  assets/fonts/inter-bold.woff2
  assets/fonts/outfit-bold.woff2
)

for font in "${required_fonts[@]}"; do
  if [[ ! -s "$font" ]]; then
    echo "Missing generated font asset: $font" >&2
    echo "Run apps/mobile/tool/build-latin-fonts.sh and apps/mobile/tool/build-cn-fonts.sh before UI baseline checks." >&2
    exit 1
  fi
done

flutter test \
  test/design_system/delta_text_test.dart \
  test/design_system/skeleton_test.dart \
  test/core/ai/visual/ai_markdown_test.dart \
  test/core/perf/frame_timing_collector_test.dart \
  test/core/perf/perf_trace_recorder_test.dart \
  test/design_system/charts/downsample_test.dart \
  test/features/investment/domain/returns/xirr_engine_test.dart \
  --reporter=expanded
