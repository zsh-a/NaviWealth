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

mkdir -p "$FRAMEWORKS_DIR"
ORT_DYLIB="$FRAMEWORKS_DIR/libonnxruntime.dylib"

ARCH_LIST=()
if [[ -n "${CURRENT_ARCH:-}" && "${CURRENT_ARCH:-}" != "undefined_arch" ]]; then
  ARCH_LIST=("$CURRENT_ARCH")
elif [[ -n "${ARCHS:-}" ]]; then
  # shellcheck disable=SC2206
  ARCH_LIST=($ARCHS)
else
  ARCH_LIST=("$(uname -m)")
fi

TMP_DIR="${TARGET_TEMP_DIR:-$FRAMEWORKS_DIR/.onnxruntime-tmp}"
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

LIBS=()
for ARCH in "${ARCH_LIST[@]}"; do
  case "$ARCH" in
    arm64) TARGET_TRIPLE="aarch64-apple-darwin" ;;
    x86_64) TARGET_TRIPLE="x86_64-apple-darwin" ;;
    *)
      echo "warning: unsupported macOS arch $ARCH; skipping" >&2
      continue
      ;;
  esac
  ARCH_DIR="$TMP_DIR/$ARCH"
  mkdir -p "$ARCH_DIR"
  "$REPO_ROOT/tool/fetch-onnxruntime.sh" "$TARGET_TRIPLE" "$ARCH_DIR"
  LIBS+=("$ARCH_DIR/libonnxruntime.dylib")
done

if [[ "${#LIBS[@]}" -eq 0 ]]; then
  echo "warning: no supported macOS ORT archs in: ${ARCH_LIST[*]}" >&2
  exit 0
elif [[ "${#LIBS[@]}" -eq 1 ]]; then
  cp -f "${LIBS[0]}" "$ORT_DYLIB"
else
  lipo -create "${LIBS[@]}" -output "$ORT_DYLIB"
fi

install_name_tool -id "@rpath/libonnxruntime.dylib" "$ORT_DYLIB" 2>/dev/null || true

if [[ "${CODE_SIGNING_ALLOWED:-NO}" == "YES" ]] && command -v codesign >/dev/null 2>&1; then
  SIGN_IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:--}"
  codesign --force --sign "$SIGN_IDENTITY" "$ORT_DYLIB"
fi

echo "Embedded ONNX Runtime: $ORT_DYLIB"
