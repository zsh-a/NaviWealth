#!/usr/bin/env bash
# Copy the build-pinned ONNX Runtime dylib into the macOS .app bundle.
#
# Called by the Runner Xcode target after CocoaPods embeds frameworks.
# The app is sandboxed, so ORT must live inside Contents/Frameworks;
# dlopening a workspace/cache path is blocked at runtime.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

FRAMEWORKS_DIR="${TARGET_BUILD_DIR:-}/${FRAMEWORKS_FOLDER_PATH:-}"
if [[ -z "${TARGET_BUILD_DIR:-}" || -z "${FRAMEWORKS_FOLDER_PATH:-}" ]]; then
  echo "warning: TARGET_BUILD_DIR/FRAMEWORKS_FOLDER_PATH not set; skipping ORT embed" >&2
  exit 0
fi

ARCH="${CURRENT_ARCH:-}"
if [[ -z "$ARCH" || "$ARCH" == "undefined_arch" ]]; then
  ARCH="${ARCHS%% *}"
fi
if [[ -z "$ARCH" ]]; then
  ARCH="$(uname -m)"
fi

case "$ARCH" in
  arm64) TARGET_TRIPLE="aarch64-apple-darwin" ;;
  x86_64) TARGET_TRIPLE="x86_64-apple-darwin" ;;
  *)
    echo "warning: unsupported macOS arch $ARCH; skipping ORT embed" >&2
    exit 0
    ;;
esac

mkdir -p "$FRAMEWORKS_DIR"
"$REPO_ROOT/tool/fetch-onnxruntime.sh" "$TARGET_TRIPLE" "$FRAMEWORKS_DIR"

ORT_DYLIB="$FRAMEWORKS_DIR/libonnxruntime.dylib"
if [[ "${CODE_SIGNING_ALLOWED:-NO}" == "YES" ]] && command -v codesign >/dev/null 2>&1; then
  SIGN_IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:--}"
  codesign --force --sign "$SIGN_IDENTITY" "$ORT_DYLIB"
fi

echo "Embedded ONNX Runtime: $ORT_DYLIB"
