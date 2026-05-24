#!/usr/bin/env bash
# Populate Android jniLibs with ONNX Runtime .so files.
#
# Called by the rust_builder Android Gradle plugin before native libs
# are merged. Sources come from Microsoft's onnxruntime-android AAR
# on Maven Central, pinned by tool/fetch-onnxruntime.sh.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST_ROOT="${1:-}"
TARGETS_CSV="${2:-}"

if [[ -z "$DEST_ROOT" ]]; then
  echo "Usage: tool/embed-onnxruntime-android.sh <dest_jni_libs_dir> [target1,target2,...]" >&2
  exit 1
fi

if [[ -z "$TARGETS_CSV" ]]; then
  TARGETS_CSV="aarch64-linux-android,armv7-linux-androideabi,x86_64-linux-android,i686-linux-android"
fi

IFS=',' read -r -a TARGETS <<< "$TARGETS_CSV"
mkdir -p "$DEST_ROOT"

for TARGET in "${TARGETS[@]}"; do
  case "$TARGET" in
    aarch64-linux-android) ABI="arm64-v8a" ;;
    armv7-linux-androideabi) ABI="armeabi-v7a" ;;
    x86_64-linux-android) ABI="x86_64" ;;
    i686-linux-android) ABI="x86" ;;
    *)
      echo "warning: unsupported Android ORT target $TARGET; skipping" >&2
      continue
      ;;
  esac
  ABI_DIR="$DEST_ROOT/$ABI"
  mkdir -p "$ABI_DIR"
  "$REPO_ROOT/tool/fetch-onnxruntime.sh" "$TARGET" "$ABI_DIR"
done

find "$DEST_ROOT" -name libonnxruntime.so -exec ls -lh {} \;
