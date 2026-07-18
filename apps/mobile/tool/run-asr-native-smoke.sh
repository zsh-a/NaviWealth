#!/usr/bin/env bash

set -euo pipefail

CACHE_DIR="${1:-}"
if [[ -z "$CACHE_DIR" ]]; then
  echo "Usage: tool/run-asr-native-smoke.sh <cache-dir>" >&2
  exit 64
fi

MODEL_DIR="$CACHE_DIR/model"
WAV_PATH="$CACHE_DIR/0.wav"
BASE_URL="https://huggingface.co/csukuangfj/sherpa-onnx-streaming-zipformer-zh-14M-2023-02-23/resolve/main"
EXPECTED_TRANSCRIPT="对我做了介绍那么我想说的是大家如果对我的研究感兴趣呢"

mkdir -p "$MODEL_DIR"

download_verified() {
  local url="$1"
  local destination="$2"
  local expected_sha="$3"
  local partial="${destination}.partial"
  local actual_sha

  if [[ -f "$destination" ]]; then
    actual_sha="$(shasum -a 256 "$destination" | awk '{print $1}')"
    if [[ "$actual_sha" == "$expected_sha" ]]; then
      return
    fi
  fi

  curl --fail --location --silent --show-error "$url" --output "$partial"
  actual_sha="$(shasum -a 256 "$partial" | awk '{print $1}')"
  if [[ "$actual_sha" != "$expected_sha" ]]; then
    echo "SHA-256 mismatch for $url" >&2
    echo "expected=$expected_sha actual=$actual_sha" >&2
    rm -f "$partial"
    exit 65
  fi
  mv "$partial" "$destination"
}

download_verified \
  "$BASE_URL/encoder-epoch-99-avg-1.int8.onnx" \
  "$MODEL_DIR/encoder-epoch-99-avg-1.int8.onnx" \
  "1c556ea57cec304e55ec4b72e52c1cc098bb01476ed7d90f3de939fe126487b1"
download_verified \
  "$BASE_URL/decoder-epoch-99-avg-1.int8.onnx" \
  "$MODEL_DIR/decoder-epoch-99-avg-1.int8.onnx" \
  "22f123bb8cba9b38974b3df18a3f45e7081f4985ebb2e075d9f21f618c468bbf"
download_verified \
  "$BASE_URL/joiner-epoch-99-avg-1.int8.onnx" \
  "$MODEL_DIR/joiner-epoch-99-avg-1.int8.onnx" \
  "a7cf9d82757bdcf786059454495a9ca95e4bd7347f72473fc08d794475c36169"
download_verified \
  "$BASE_URL/tokens.txt" \
  "$MODEL_DIR/tokens.txt" \
  "8b294db9045d6e5f94647f4c1eec1af4da143a75053c399611444b378ff966ac"
download_verified \
  "$BASE_URL/test_wavs/0.wav" \
  "$WAV_PATH" \
  "668bf8df51a10027b84d5d8816a1ce11ae93545538dc05cfe2aa6811d399c250"

dart run tool/asr_native_smoke.dart \
  auto \
  "$MODEL_DIR" \
  "$WAV_PATH" \
  "$EXPECTED_TRANSCRIPT"
