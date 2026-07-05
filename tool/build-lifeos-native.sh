#!/usr/bin/env bash
# OPTIONAL out-of-Flutter build for the lifeos_native Rust crate.
#
# **The primary build path is `flutter run` / `flutter build`** — the
# `rust_builder/` Flutter plugin invokes cargokit which calls cargo
# for the right target automatically. You only need this script when:
#
#   - Running `flutter test` on desktop and the test imports the lib
#     via `--dart-define=RUST_EMBEDDER_LIBRARY_PATH=...`
#   - Producing standalone artefacts (e.g. xcframework for sharing
#     between repos)
#   - Reproducing a Rust-only build outside the Flutter toolchain
#     (CI smoke check, container build, etc.)
#
# Usage:
#   tool/build-lifeos-native.sh macos              # host arch only
#   tool/build-lifeos-native.sh macos universal     # arm64 + x86_64 lipo'd dylib
#   tool/build-lifeos-native.sh ios                # device (arm64) + sim (arm64+x86_64) xcframework
#   tool/build-lifeos-native.sh android            # arm64-v8a + armeabi-v7a + x86_64
#
# Outputs (in apps/mobile/native/lifeos_native/dist/):
#   macos/liblifeos_native.dylib
#   ios/LifeosNative.xcframework
#   android/<abi>/liblifeos_native.so
#
# Prerequisites checked at run time; missing tools print install hints.
#
# Docs: docs/architecture/lifeos-shell.md §6.6 (D-1.7c).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CRATE_DIR="$REPO_ROOT/apps/mobile/native/lifeos_native"
DIST_DIR="$CRATE_DIR/dist"
LIB_BASENAME="liblifeos_native"
FRB_CONFIG="$REPO_ROOT/apps/mobile/flutter_rust_bridge.yaml"

# Regenerate the flutter_rust_bridge bindings whenever the Rust API
# signature might have changed. Cheap when nothing changed (frb checks
# rust-content-hash) and required when src/api/*.rs is edited.
run_frb_codegen() {
  if ! command -v flutter_rust_bridge_codegen >/dev/null 2>&1; then
    echo "==> Installing flutter_rust_bridge_codegen (one-time)"
    cargo install flutter_rust_bridge_codegen --version "^2.12" --locked
  fi
  echo "==> Regenerating FRB bindings"
  (cd "$REPO_ROOT/apps/mobile" && flutter_rust_bridge_codegen generate) \
    || { echo "ERROR: flutter_rust_bridge_codegen generate failed" >&2; exit 1; }
}

ensure_target() {
  local target="$1"
  if ! rustup target list --installed | grep -qx "$target"; then
    echo "==> Installing Rust target: $target"
    rustup target add "$target"
  fi
}

build_macos() {
  local mode="${1:-host}"
  mkdir -p "$DIST_DIR/macos"
  if [[ "$mode" == "universal" ]]; then
    ensure_target aarch64-apple-darwin
    ensure_target x86_64-apple-darwin
    echo "==> cargo build --release --target aarch64-apple-darwin"
    (cd "$CRATE_DIR" && cargo build --release --target aarch64-apple-darwin )
    echo "==> cargo build --release --target x86_64-apple-darwin"
    (cd "$CRATE_DIR" && cargo build --release --target x86_64-apple-darwin )
    echo "==> lipo arm64 + x86_64 → $DIST_DIR/macos/${LIB_BASENAME}.dylib"
    lipo -create \
      "$CRATE_DIR/target/aarch64-apple-darwin/release/${LIB_BASENAME}.dylib" \
      "$CRATE_DIR/target/x86_64-apple-darwin/release/${LIB_BASENAME}.dylib" \
      -output "$DIST_DIR/macos/${LIB_BASENAME}.dylib"
  else
    echo "==> cargo build --release (host arch)"
    (cd "$CRATE_DIR" && cargo build --release )
    cp "$CRATE_DIR/target/release/${LIB_BASENAME}.dylib" \
      "$DIST_DIR/macos/${LIB_BASENAME}.dylib"
  fi

  fix_macos_linkedit_alignment "$DIST_DIR/macos/${LIB_BASENAME}.dylib"

  # Fetch the matching ORT dylib alongside (ort 2.0.0-rc.12 → ORT 1.24.2;
  # `ort-load-dynamic` discovers via ORT_DYLIB_PATH at runtime).
  local host_arch
  host_arch="$(uname -m)"
  case "$host_arch" in
    arm64)  "$REPO_ROOT/tool/fetch-onnxruntime.sh" aarch64-apple-darwin "$DIST_DIR/macos" ;;
    x86_64) "$REPO_ROOT/tool/fetch-onnxruntime.sh" x86_64-apple-darwin "$DIST_DIR/macos" ;;
    *) echo "WARNING: unknown host arch $host_arch; skipping ORT fetch" >&2 ;;
  esac

  echo
  echo "macOS dylib: $DIST_DIR/macos/${LIB_BASENAME}.dylib"
  ls -lh "$DIST_DIR/macos/${LIB_BASENAME}.dylib" \
        "$DIST_DIR/macos/libonnxruntime.dylib"
}

fix_macos_linkedit_alignment() {
  local dylib="$1"
  if ! command -v python3 >/dev/null 2>&1; then
    echo "WARNING: python3 not found; skipping Mach-O LINKEDIT alignment fix" >&2
    return 0
  fi
  if ! command -v codesign >/dev/null 2>&1; then
    echo "WARNING: codesign not found; skipping Mach-O re-sign" >&2
    return 0
  fi

  python3 - "$dylib" <<'PY'
import struct
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = bytearray(path.read_bytes())


def u32(offset, endian="<"):
    return struct.unpack_from(f"{endian}I", data, offset)[0]


def write_u32(offset, value, endian="<"):
    struct.pack_into(f"{endian}I", data, offset, value)


def slices():
    magic_be = u32(0, ">")
    if magic_be == 0xCAFEBABE:
        nfat = u32(4, ">")
        offset = 8
        for _ in range(nfat):
            arch_offset = u32(offset + 8, ">")
            arch_size = u32(offset + 12, ">")
            yield arch_offset, arch_size
            offset += 20
        return
    if magic_be == 0xCAFEBABF:
        nfat = u32(4, ">")
        offset = 8
        for _ in range(nfat):
            arch_offset = struct.unpack_from(">Q", data, offset + 8)[0]
            arch_size = struct.unpack_from(">Q", data, offset + 16)[0]
            yield arch_offset, arch_size
            offset += 32
        return
    yield 0, len(data)


def patch_slice(base, size):
    if u32(base) != 0xFEEDFACF:
        return False

    ncmds = u32(base + 16)
    command = base + 32
    symtab_command = None
    stroff = None
    strsize = None
    code_signature_dataoff = None

    for _ in range(ncmds):
        cmd = u32(command)
        cmdsize = u32(command + 4)
        if cmd == 0x2:  # LC_SYMTAB
            symtab_command = command
            stroff = u32(command + 16)
            strsize = u32(command + 20)
        elif cmd == 0x1D:  # LC_CODE_SIGNATURE
            code_signature_dataoff = u32(command + 8)
        command += cmdsize

    if stroff is None or strsize is None or code_signature_dataoff is None:
        return False

    pad = (-stroff) % 8
    if pad == 0:
        return False
    if stroff + strsize + pad > code_signature_dataoff:
        raise SystemExit(
            f"{path}: cannot align LINKEDIT string pool; "
            f"stroff={stroff} strsize={strsize} code_signature={code_signature_dataoff}"
        )

    start = base + stroff
    code_signature = base + code_signature_dataoff
    data[start + pad : code_signature] = data[start : code_signature - pad]
    data[start : start + pad] = b"\0" * pad
    write_u32(symtab_command + 16, stroff + pad)
    return True


patched = False
for base, size in slices():
    patched = patch_slice(base, size) or patched

if patched:
    path.write_bytes(data)
    print(f"==> Aligned Mach-O LINKEDIT string pool: {path}")
PY

  codesign --force --sign - "$dylib" >/dev/null 2>&1
}

build_ios() {
  if ! command -v xcodebuild >/dev/null 2>&1; then
    echo "ERROR: xcodebuild not found. Install Xcode + 'sudo xcode-select -s /Applications/Xcode.app'"
    exit 1
  fi
  ensure_target aarch64-apple-ios
  ensure_target aarch64-apple-ios-sim
  ensure_target x86_64-apple-ios

  mkdir -p "$DIST_DIR/ios"

  echo "==> cargo build --release --target aarch64-apple-ios (device)"
  (cd "$CRATE_DIR" && cargo build --release --target aarch64-apple-ios )

  echo "==> cargo build --release --target aarch64-apple-ios-sim (sim arm64)"
  (cd "$CRATE_DIR" && cargo build --release --target aarch64-apple-ios-sim )

  echo "==> cargo build --release --target x86_64-apple-ios (sim x86_64)"
  (cd "$CRATE_DIR" && cargo build --release --target x86_64-apple-ios )

  # Fat sim static lib (arm64 + x86_64).
  local sim_dir="$CRATE_DIR/target/ios-sim-universal/release"
  mkdir -p "$sim_dir"
  lipo -create \
    "$CRATE_DIR/target/aarch64-apple-ios-sim/release/${LIB_BASENAME}.a" \
    "$CRATE_DIR/target/x86_64-apple-ios/release/${LIB_BASENAME}.a" \
    -output "$sim_dir/${LIB_BASENAME}.a"

  local xcfwk="$DIST_DIR/ios/LifeosNative.xcframework"
  rm -rf "$xcfwk"
  echo "==> Assembling $xcfwk"
  xcodebuild -create-xcframework \
    -library "$CRATE_DIR/target/aarch64-apple-ios/release/${LIB_BASENAME}.a" \
    -library "$sim_dir/${LIB_BASENAME}.a" \
    -output "$xcfwk"

  echo
  echo "iOS xcframework: $xcfwk"
}

build_android() {
  if [[ -z "${ANDROID_NDK_HOME:-}" ]]; then
    echo "ERROR: ANDROID_NDK_HOME is not set. Install Android NDK (r25c+) and:"
    echo "  export ANDROID_NDK_HOME=\$HOME/Library/Android/sdk/ndk/<version>"
    exit 1
  fi
  if ! command -v cargo-ndk >/dev/null 2>&1; then
    echo "==> Installing cargo-ndk (one-time)"
    cargo install cargo-ndk
  fi
  ensure_target aarch64-linux-android
  ensure_target armv7-linux-androideabi
  ensure_target x86_64-linux-android

  mkdir -p "$DIST_DIR/android"
  echo "==> cargo ndk → arm64-v8a / armeabi-v7a / x86_64"
  (cd "$CRATE_DIR" && cargo ndk \
    -t arm64-v8a -t armeabi-v7a -t x86_64 \
    -o "../../../../$DIST_DIR/android" \
    build --release)

  echo
  echo "Android .so per ABI in: $DIST_DIR/android/"
  find "$DIST_DIR/android" -name "${LIB_BASENAME}.so" -exec ls -lh {} \;

  "$REPO_ROOT/tool/embed-onnxruntime-android.sh" "$DIST_DIR/android" \
    "aarch64-linux-android,armv7-linux-androideabi,x86_64-linux-android"
}

case "${1:-}" in
  macos|ios|android)
    run_frb_codegen
    ;;
esac

case "${1:-}" in
  macos)
    build_macos "${2:-host}"
    ;;
  ios)
    build_ios
    ;;
  android)
    build_android
    ;;
  ""|--help|-h)
    sed -n '2,12p' "$0"
    exit 0
    ;;
  *)
    echo "Unknown platform: $1"
    sed -n '2,12p' "$0"
    exit 1
    ;;
esac
