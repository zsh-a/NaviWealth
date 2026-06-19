#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

# These web font files are generated artifacts in normal builds. The semantic
# surrogate tests do not rasterize real glyphs, but Flutter's asset bundle still
# needs readable files for the registered paths.
mkdir -p assets/fonts
touch assets/fonts/app-cn-base.woff2 assets/fonts/app-cn-ext.woff2
touch assets/fonts/inter-regular.woff2 assets/fonts/inter-medium.woff2 \
  assets/fonts/inter-semibold.woff2 assets/fonts/inter-bold.woff2 \
  assets/fonts/outfit-bold.woff2

if grep -R "ContextPack\\.analytical_uploads" lib test; then
  echo "ContextPack.analytical_uploads has been removed; use device analytical signal/tool output wording." >&2
  exit 1
fi

flutter test \
  test/features/ai_chat/tool_invocation_renderers_test.dart \
  test/core/ai/regression/regression_corpus_test.dart \
  --reporter=expanded
