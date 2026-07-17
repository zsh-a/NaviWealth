#!/usr/bin/env bash
# Validate the arm64 native payload shipped in an Android APK or AAB.
#
# The Play Store requires 16 KiB page-size compatibility. This checks the
# ELF LOAD segment alignment for every arm64 shared library, verifies the
# runtime's required libraries are present, and (for APKs) verifies that
# uncompressed .so entries are 16 KiB zip-aligned.

set -euo pipefail

ARCHIVE="${1:-}"
MIN_PAGE_SIZE=$((16 * 1024))
REQUIRED_LIBS=(liblifeos_native.so libonnxruntime.so)
LIFEOS_INIT_SYMBOL="Java_com_naviwealth_naviwealth_NaviWealthApplication_initLifeosNativeAndroid"

if [[ -z "$ARCHIVE" || ! -f "$ARCHIVE" ]]; then
  echo "Usage: tool/check-android-native-libs.sh <app.apk|app.aab>" >&2
  exit 2
fi

case "$ARCHIVE" in
  *.apk) ARCHIVE_KIND="apk" ;;
  *.aab) ARCHIVE_KIND="aab" ;;
  *)
    echo "ERROR: expected an .apk or .aab archive: $ARCHIVE" >&2
    exit 2
    ;;
esac

if ! command -v unzip >/dev/null 2>&1; then
  echo "ERROR: unzip is required" >&2
  exit 2
fi

find_sdk_tool() {
  local tool="$1"
  local candidate

  if command -v "$tool" >/dev/null 2>&1; then
    command -v "$tool"
    return 0
  fi

  for candidate in \
    "${ANDROID_NDK_HOME:-}/toolchains/llvm/prebuilt"/*/bin/"$tool" \
    "${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}/ndk"/*/toolchains/llvm/prebuilt/*/bin/"$tool"; do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

READELF="${LLVM_READELF:-}"
if [[ -z "$READELF" ]]; then
  READELF="$(find_sdk_tool llvm-readelf || true)"
fi
if [[ -z "$READELF" ]] && command -v readelf >/dev/null 2>&1; then
  READELF="$(command -v readelf)"
fi
if [[ -z "$READELF" || ! -x "$READELF" ]]; then
  echo "ERROR: llvm-readelf/readelf not found; set LLVM_READELF or ANDROID_NDK_HOME" >&2
  exit 2
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

ENTRY_LIST="$TMP_DIR/entries.txt"
unzip -Z1 "$ARCHIVE" \
  | grep -E '(^|/)lib/arm64-v8a/[^/]+\.so$' \
  | LC_ALL=C sort > "$ENTRY_LIST" || true

if [[ ! -s "$ENTRY_LIST" ]]; then
  echo "ERROR: $ARCHIVE contains no arm64-v8a shared libraries" >&2
  exit 1
fi

for required in "${REQUIRED_LIBS[@]}"; do
  if ! grep -Eq "/arm64-v8a/${required}$" "$ENTRY_LIST"; then
    echo "ERROR: missing arm64-v8a/$required in $ARCHIVE" >&2
    exit 1
  fi
done

checked=0
while IFS= read -r entry; do
  lib="$TMP_DIR/$(basename "$entry")"
  unzip -p "$ARCHIVE" "$entry" > "$lib"

  file_header="$("$READELF" --file-header "$lib")"
  if ! grep -q 'Machine:.*AArch64' <<< "$file_header"; then
    echo "ERROR: $entry is not an AArch64 ELF shared library" >&2
    exit 1
  fi

  alignments="$("$READELF" --program-headers --wide "$lib" \
    | awk '$1 == "LOAD" { print $NF }')"
  if [[ -z "$alignments" ]]; then
    echo "ERROR: $entry has no ELF LOAD segments" >&2
    exit 1
  fi

  while IFS= read -r alignment; do
    if (( alignment < MIN_PAGE_SIZE )); then
      echo "ERROR: $entry has LOAD alignment $alignment; expected at least 0x4000" >&2
      exit 1
    fi
  done <<< "$alignments"

  if [[ "$(basename "$entry")" == "liblifeos_native.so" ]]; then
    dynamic_symbols="$("$READELF" --dyn-symbols --wide "$lib")"
    if ! grep -Fq "$LIFEOS_INIT_SYMBOL" <<< "$dynamic_symbols"; then
      echo "ERROR: $entry does not export $LIFEOS_INIT_SYMBOL" >&2
      exit 1
    fi
    echo "OK: $entry exports the process initializer JNI symbol"
  fi

  printf 'OK: %-56s ELF LOAD alignment >= 0x4000\n' "$entry"
  checked=$((checked + 1))
done < "$ENTRY_LIST"

if [[ "$ARCHIVE_KIND" == "apk" ]]; then
  ZIPALIGN="${ZIPALIGN:-}"
  if [[ -z "$ZIPALIGN" ]]; then
    if command -v zipalign >/dev/null 2>&1; then
      ZIPALIGN="$(command -v zipalign)"
    else
      for candidate in \
        "${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}/build-tools"/*/zipalign; do
        if [[ -x "$candidate" ]]; then
          ZIPALIGN="$candidate"
        fi
      done
    fi
  fi
  if [[ -z "$ZIPALIGN" || ! -x "$ZIPALIGN" ]]; then
    echo "ERROR: zipalign not found; set ZIPALIGN or ANDROID_SDK_ROOT" >&2
    exit 2
  fi
  "$ZIPALIGN" -c -P 16 4 "$ARCHIVE" >/dev/null
  echo "OK: APK uncompressed native libraries are 16 KiB zip-aligned"
fi

echo "Validated $checked arm64 shared libraries in $ARCHIVE"
