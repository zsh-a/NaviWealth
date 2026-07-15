#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

update=false
if [[ "${1:-}" == "--update" ]]; then
  update=true
elif [[ $# -gt 0 ]]; then
  echo "usage: $0 [--update]" >&2
  exit 64
fi

CHECK_CN_FONT_SIZE=false tool/build-cn-fonts.sh
tool/build-latin-fonts.sh
flutter pub get

args=(
  flutter test
  test/readme_screenshots/readme_screenshot_test.dart
  --tags=readme-screenshot
  --reporter=expanded
)
if [[ "$update" == true ]]; then
  args+=(--update-goldens)
fi
"${args[@]}"

dart run tool/validate_readme_screenshots.dart

if [[ "$update" == true ]]; then
  echo "README screenshots refreshed under docs/assets/readme/generated/."
else
  echo "README screenshots match the current production UI."
fi
