#!/usr/bin/env bash

set -euo pipefail

CACHE_DIR="${1:-}"
if [[ -z "$CACHE_DIR" ]]; then
  echo "Usage: tool/run-asr-native-smoke.sh <cache-dir>" >&2
  exit 64
fi

MODEL_DIR="$CACHE_DIR/model"
WAV_PATH="$CACHE_DIR/0.wav"
BASE_URL="https://huggingface.co/csukuangfj/sherpa-onnx-streaming-zipformer-ctc-zh-int8-2025-06-30/resolve/main"
EXPECTED_TRANSCRIPT="对我做了介绍啊那么我想说的是呢大家如果对我的研究感兴趣呢"

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

  curl \
    --fail \
    --location \
    --silent \
    --show-error \
    --continue-at - \
    "$url" \
    --output "$partial"
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
  "$BASE_URL/model.int8.onnx" \
  "$MODEL_DIR/model.int8.onnx" \
  "24ffdc19ba9aaed5a6a9beaede1e087745217d82425cf4041bca0c696661801e"
download_verified \
  "$BASE_URL/tokens.txt" \
  "$MODEL_DIR/tokens.txt" \
  "6193c7ea1c96d0d9a1e9652789b40d13a8a913b434a5451e93158f5a09fd6652"
download_verified \
  "$BASE_URL/test_wavs/0.wav" \
  "$WAV_PATH" \
  "668bf8df51a10027b84d5d8816a1ce11ae93545538dc05cfe2aa6811d399c250"

dart run tool/asr_native_smoke.dart \
  auto \
  "$MODEL_DIR" \
  "$WAV_PATH" \
  "$EXPECTED_TRANSCRIPT"
