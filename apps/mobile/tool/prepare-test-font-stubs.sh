#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

mkdir -p assets/fonts
touch \
  assets/fonts/app-cn-base.woff2 \
  assets/fonts/app-cn-ext.woff2 \
  assets/fonts/inter-regular.woff2 \
  assets/fonts/inter-medium.woff2 \
  assets/fonts/inter-semibold.woff2 \
  assets/fonts/inter-bold.woff2 \
  assets/fonts/outfit-bold.woff2
