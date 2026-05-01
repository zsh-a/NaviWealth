#!/usr/bin/env bash
# FIR-76 — securities seed catalog builder.
#
# Reads a curated source list at `tool/asset_catalog/sources/` and emits a
# bundled NDJSON file at the path the loader expects:
#
#   apps/mobile/assets/catalog/securities.v1.ndjson
#
# The output format is documented in
# `apps/mobile/lib/data/securities_catalog/securities_catalog_loader.dart`:
# a single JSON header line followed by one JSON entry per line.
#
# Why a Bash + Python combo:
#   - Bash for invocation / path glue / git status checks (matches the rest
#     of `tool/`).
#   - Python for pinyin generation: the canonical mainland-China pinyin
#     romanisation needs `pypinyin` (or equivalent), which has no Dart
#     port worth pulling in. We pre-compute pinyin offline so the runtime
#     never has to.
#
# The script is idempotent: re-running with the same source list and the
# same version tag is a no-op (the bundle's checksum is computed from the
# canonical entry order, so trivial reorderings don't bust caches).

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_PATH="${ROOT_DIR}/apps/mobile/assets/catalog/securities.v1.ndjson"
SRC_DIR="${ROOT_DIR}/tool/asset_catalog/sources"
VERSION="${CATALOG_VERSION:-v1.$(date -u +%Y%m%d)}"

if [[ ! -d "${SRC_DIR}" ]]; then
  echo "fatal: missing source dir ${SRC_DIR}" >&2
  echo "       drop CSV / TSV / JSON files describing each market in there" >&2
  exit 1
fi

if ! command -v python3 >/dev/null; then
  echo "fatal: python3 is required to compute pinyin tags" >&2
  exit 1
fi

mkdir -p "$(dirname "${OUT_PATH}")"

python3 "${ROOT_DIR}/tool/asset_catalog/build.py" \
  --sources "${SRC_DIR}" \
  --version "${VERSION}" \
  --output "${OUT_PATH}"

echo "catalog written: ${OUT_PATH}"
echo "  size: $(wc -c < "${OUT_PATH}") bytes"
echo "  rows: $(grep -c -v '^#' "${OUT_PATH}" || true) (incl. header)"
