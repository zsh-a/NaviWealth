#!/usr/bin/env bash
# Download + extract the ONNX Runtime dynamic library for a given
# Rust target triple, placing the resulting `libonnxruntime.{dylib,so}`
# into the requested destination directory.
#
# This is a standalone developer helper for native embedder tests. Production
# Android and Apple builds reuse the runtime bundled by sherpa_onnx.
#
# Why a separate script: `ort 2.0.0-rc.12` (the version `fastembed`
# pulls in) uses the ONNX Runtime C API. Keep this aligned with the sherpa-onnx
# native packages so the app ships one runtime per process. The CocoaPods
# `onnxruntime-c` pod only publishes up to 1.21.0, which is ABI-
# incompatible. We side-step that by fetching the matching dylib
# directly from Microsoft's GitHub release.
#
# The dylib version (e.g. `libonnxruntime.1.27.0.dylib`) is renamed
# to the unversioned `libonnxruntime.dylib` so our embedder loader
# can use a stable filename across ORT bumps.
#
# Usage:
#   tool/fetch-onnxruntime.sh <target> <dest_dir>
#
# Targets:
#   aarch64-apple-darwin    x86_64-apple-darwin
#   aarch64-linux-android   armv7-linux-androideabi
#   x86_64-linux-android    i686-linux-android
#
# Cached in $REPO_ROOT/.cache/onnxruntime/ so repeat runs are free.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ORT_VERSION="1.27.0"
ORT_CACHE="$REPO_ROOT/.cache/onnxruntime/$ORT_VERSION"

TARGET="${1:-}"
DEST_DIR="${2:-}"

if [[ -z "$TARGET" || -z "$DEST_DIR" ]]; then
  sed -n '2,20p' "$0"
  exit 1
fi

mkdir -p "$ORT_CACHE" "$DEST_DIR"

# Microsoft's GitHub asset names + the relative path inside the
# extracted archive that holds the dylib we want.
case "$TARGET" in
  aarch64-apple-darwin)
    ARCHIVE="onnxruntime-osx-arm64-${ORT_VERSION}.tgz"
    INNER_LIB="onnxruntime-osx-arm64-${ORT_VERSION}/lib/libonnxruntime.${ORT_VERSION}.dylib"
    OUT_NAME="libonnxruntime.dylib"
    ;;
  x86_64-apple-darwin)
    ARCHIVE="onnxruntime-osx-x86_64-${ORT_VERSION}.tgz"
    INNER_LIB="onnxruntime-osx-x86_64-${ORT_VERSION}/lib/libonnxruntime.${ORT_VERSION}.dylib"
    OUT_NAME="libonnxruntime.dylib"
    ;;
  aarch64-apple-ios)
    # Microsoft's iOS distribution is the `onnxruntime-c` pod normally,
    # but for our `ort-load-dynamic` flow we want a single .dylib. The
    # mobile-c.framework archive contains it; this is best-effort and
    # may need adjustment when iOS shipping is real (cf. lifeos-shell §6.6).
    echo "ERROR: iOS dylib fetch not implemented; iOS shipping requires the" >&2
    echo "       onnxruntime-c CocoaPod or a custom xcframework. Keep the" >&2
    echo "       stub embedder on iOS until that packaging work lands." >&2
    exit 2
    ;;
  aarch64-linux-android)
    ARCHIVE="onnxruntime-android-${ORT_VERSION}.aar"
    INNER_LIB="jni/arm64-v8a/libonnxruntime.so"
    OUT_NAME="libonnxruntime.so"
    MAVEN_ARTIFACT="onnxruntime-android"
    ;;
  armv7-linux-androideabi)
    ARCHIVE="onnxruntime-android-${ORT_VERSION}.aar"
    INNER_LIB="jni/armeabi-v7a/libonnxruntime.so"
    OUT_NAME="libonnxruntime.so"
    MAVEN_ARTIFACT="onnxruntime-android"
    ;;
  x86_64-linux-android)
    ARCHIVE="onnxruntime-android-${ORT_VERSION}.aar"
    INNER_LIB="jni/x86_64/libonnxruntime.so"
    OUT_NAME="libonnxruntime.so"
    MAVEN_ARTIFACT="onnxruntime-android"
    ;;
  i686-linux-android)
    ARCHIVE="onnxruntime-android-${ORT_VERSION}.aar"
    INNER_LIB="jni/x86/libonnxruntime.so"
    OUT_NAME="libonnxruntime.so"
    MAVEN_ARTIFACT="onnxruntime-android"
    ;;
  *)
    echo "ERROR: unsupported target: $TARGET" >&2
    exit 1
    ;;
esac

CACHED_ARCHIVE="$ORT_CACHE/$ARCHIVE"
if [[ "${MAVEN_ARTIFACT:-}" == "onnxruntime-android" ]]; then
  URL="https://repo.maven.apache.org/maven2/com/microsoft/onnxruntime/${MAVEN_ARTIFACT}/${ORT_VERSION}/${ARCHIVE}"
else
  URL="https://github.com/microsoft/onnxruntime/releases/download/v${ORT_VERSION}/${ARCHIVE}"
fi

if [[ ! -f "$CACHED_ARCHIVE" ]]; then
  echo "==> Downloading $URL"
  curl -fsSL -o "$CACHED_ARCHIVE.partial" "$URL"
  mv "$CACHED_ARCHIVE.partial" "$CACHED_ARCHIVE"
fi

EXTRACT_DIR="$ORT_CACHE/extracted-$TARGET"
if [[ ! -f "$EXTRACT_DIR/$INNER_LIB" ]]; then
  echo "==> Extracting $ARCHIVE"
  rm -rf "$EXTRACT_DIR"
  mkdir -p "$EXTRACT_DIR"
  case "$ARCHIVE" in
    *.tgz) tar xzf "$CACHED_ARCHIVE" -C "$EXTRACT_DIR" ;;
    *.aar) unzip -q "$CACHED_ARCHIVE" "$INNER_LIB" -d "$EXTRACT_DIR" ;;
    *) echo "ERROR: unsupported archive type: $ARCHIVE" >&2; exit 1 ;;
  esac
fi

cp -f "$EXTRACT_DIR/$INNER_LIB" "$DEST_DIR/$OUT_NAME"

# macOS: the dylib's `LC_ID_DYLIB` typically points at the upstream
# install path (e.g. `@rpath/libonnxruntime.1.27.0.dylib`). When ort
# dlopens it under our chosen filename, dyld can complain that the
# loaded library's id doesn't match. Patch the id to the simpler
# unversioned name so `dlopen("libonnxruntime.dylib")` is consistent.
case "$TARGET" in
  *-apple-darwin)
    install_name_tool -id "@rpath/$OUT_NAME" "$DEST_DIR/$OUT_NAME" 2>/dev/null || true
    ;;
esac

ls -lh "$DEST_DIR/$OUT_NAME"
