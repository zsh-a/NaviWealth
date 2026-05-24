#!/usr/bin/env bash
# Download + extract the ONNX Runtime dynamic library for a given
# Rust target triple, placing the resulting `libonnxruntime.{dylib,so}`
# into the requested destination directory.
#
# Called by:
#   - tool/build-lifeos-native.sh (standalone dev build)
#   - rust_builder/{macos,ios}/lifeos_native.podspec (cargokit-driven
#     `flutter run` / `flutter build`)
#
# Why a separate script: `ort 2.0.0-rc.12` (the version `fastembed`
# pulls in) is built against ONNX Runtime 1.24.2. The CocoaPods
# `onnxruntime-c` pod only publishes up to 1.21.0, which is ABI-
# incompatible. We side-step that by fetching the matching dylib
# directly from Microsoft's GitHub release.
#
# The dylib version (e.g. `libonnxruntime.1.24.2.dylib`) is renamed
# to the unversioned `libonnxruntime.dylib` so our embedder loader
# can use a stable filename across ORT bumps.
#
# Usage:
#   tool/fetch-onnxruntime.sh <target> <dest_dir>
#
# Targets:
#   aarch64-apple-darwin    aarch64-apple-ios    aarch64-apple-ios-sim
#   x86_64-apple-darwin     x86_64-apple-ios     aarch64-linux-android
#
# Cached in $REPO_ROOT/.cache/onnxruntime/ so repeat runs are free.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ORT_VERSION="1.24.2"
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
    echo "       onnxruntime-c CocoaPod or a custom xcframework. Punted to" >&2
    echo "       D-2.x when HealthOS lands." >&2
    exit 2
    ;;
  aarch64-linux-android | armv7-linux-androideabi | x86_64-linux-android)
    echo "ERROR: Android .so fetch not implemented; use Microsoft's" >&2
    echo "       onnxruntime-android Maven artifact when wiring Android." >&2
    exit 2
    ;;
  *)
    echo "ERROR: unsupported target: $TARGET" >&2
    exit 1
    ;;
esac

CACHED_TGZ="$ORT_CACHE/$ARCHIVE"
URL="https://github.com/microsoft/onnxruntime/releases/download/v${ORT_VERSION}/${ARCHIVE}"

if [[ ! -f "$CACHED_TGZ" ]]; then
  echo "==> Downloading $URL"
  curl -fsSL -o "$CACHED_TGZ.partial" "$URL"
  mv "$CACHED_TGZ.partial" "$CACHED_TGZ"
fi

EXTRACT_DIR="$ORT_CACHE/extracted-$TARGET"
if [[ ! -f "$EXTRACT_DIR/$INNER_LIB" ]]; then
  echo "==> Extracting $ARCHIVE"
  rm -rf "$EXTRACT_DIR"
  mkdir -p "$EXTRACT_DIR"
  tar xzf "$CACHED_TGZ" -C "$EXTRACT_DIR"
fi

cp -f "$EXTRACT_DIR/$INNER_LIB" "$DEST_DIR/$OUT_NAME"

# macOS: the dylib's `LC_ID_DYLIB` typically points at the upstream
# install path (e.g. `@rpath/libonnxruntime.1.24.2.dylib`). When ort
# dlopens it under our chosen filename, dyld can complain that the
# loaded library's id doesn't match. Patch the id to the simpler
# unversioned name so `dlopen("libonnxruntime.dylib")` is consistent.
case "$TARGET" in
  *-apple-darwin)
    install_name_tool -id "@rpath/$OUT_NAME" "$DEST_DIR/$OUT_NAME" 2>/dev/null || true
    ;;
esac

ls -lh "$DEST_DIR/$OUT_NAME"
