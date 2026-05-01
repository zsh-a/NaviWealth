#!/usr/bin/env bash
# FIR-76 / FIR-79 — securities seed catalog builder.
#
# Modes:
#   default          stub fast-path. Reads the curated CSVs already on
#                    disk under tool/asset_catalog/sources/ and bakes
#                    them into apps/mobile/assets/catalog/securities.v1.ndjson.
#                    No network. Useful in CI dry-runs and for editing
#                    the stub set during development.
#
#   --full           full ingest. Runs every source adapter (BaoStock +
#                    mootdx for A-share, HKEX xlsx, NASDAQ Trader +
#                    SEC for US, CoinGecko for crypto), regenerates
#                    each source CSV, then bakes the NDJSON. Requires
#                    network access to the upstream feeds — currently
#                    only reliable from a runner inside mainland China
#                    because BaoStock and mootdx geo-restrict.
#
#   --allow-degraded  with --full, do not fail if a single source is
#                     unreachable (the previous CSV for that source is
#                     left in place). Off by default — CI never enables
#                     this; only on-call humans should pass it when
#                     debugging an outage.
#
#   --skip-bake      with --full, only rebuild the source CSVs and
#                    skip the NDJSON bake step. Helpful when iterating
#                    on a single adapter.
#
# Output budget:
#   the gzip-compressed bundle must stay under 800KB; the script
#   measures it after the bake and aborts otherwise.
#
# Why a Bash + Python combo:
#   - Bash for argument parsing, venv plumbing, and path glue.
#   - Python for fetchers, pinyin generation, and the bake step.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_PATH="${ROOT_DIR}/apps/mobile/assets/catalog/securities.v1.ndjson"
SRC_DIR="${ROOT_DIR}/tool/asset_catalog/sources"
VENV_DIR="${ROOT_DIR}/tool/asset_catalog/.venv"
REQUIREMENTS="${ROOT_DIR}/tool/asset_catalog/requirements.txt"
VERSION="${CATALOG_VERSION:-v1.$(date -u +%Y%m%d)}"
GZIP_BUDGET_BYTES=$((800 * 1024))
DIFF_THRESHOLD="${CATALOG_DIFF_THRESHOLD:-0.05}"

FULL=0
ALLOW_DEGRADED=0
SKIP_BAKE=0
SOURCES_ARG=""

usage() {
  sed -n '2,30p' "$0"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --full) FULL=1 ;;
    --allow-degraded) ALLOW_DEGRADED=1 ;;
    --skip-bake) SKIP_BAKE=1 ;;
    --sources)
      shift
      SOURCES_ARG="$1"
      ;;
    -h|--help) usage; exit 0 ;;
    *) echo "fatal: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

if [[ ! -d "${SRC_DIR}" ]]; then
  echo "fatal: missing source dir ${SRC_DIR}" >&2
  exit 1
fi

if ! command -v python3 >/dev/null; then
  echo "fatal: python3 is required" >&2
  exit 1
fi

run_python() {
  if [[ $FULL -eq 1 && -x "${VENV_DIR}/bin/python" ]]; then
    "${VENV_DIR}/bin/python" "$@"
  else
    python3 "$@"
  fi
}

setup_venv() {
  if [[ ! -d "${VENV_DIR}" ]]; then
    echo "==> creating venv ${VENV_DIR}"
    python3 -m venv "${VENV_DIR}"
  fi
  echo "==> installing dependencies from ${REQUIREMENTS}"
  "${VENV_DIR}/bin/pip" install --quiet --upgrade pip
  "${VENV_DIR}/bin/pip" install --quiet -r "${REQUIREMENTS}"
}

run_source() {
  local name="$1"
  local module="tool.asset_catalog.sources.${name}"
  local out="${SRC_DIR}/${name}.csv"
  local tmp="${out}.new"
  echo "==> source: ${name}"
  if (cd "${ROOT_DIR}" && run_python -m "${module}" --output "${tmp}"); then
    mv "${tmp}" "${out}"
    echo "    wrote $(wc -l < "${out}") rows to ${out}"
    return 0
  fi
  rm -f "${tmp}"
  if [[ $ALLOW_DEGRADED -eq 1 ]]; then
    echo "    warn: ${name} failed; keeping previous ${out}" >&2
    return 0
  fi
  echo "fatal: source ${name} failed (rerun with --allow-degraded to keep going)" >&2
  return 1
}

cross_check_cn_a() {
  # Optional dual-source diff: re-run cn_a in mootdx-only mode and
  # compare its row count against the BaoStock-primary CSV. Anything
  # over a 1% delta on the SH+SZ universe means one feed has drifted.
  local primary="${SRC_DIR}/cn_a.csv"
  local fallback="${SRC_DIR}/cn_a.fallback.csv"
  echo "==> cross-check: cn_a (mootdx-only second pass)"
  if (cd "${ROOT_DIR}" && run_python -m tool.asset_catalog.sources.cn_a \
        --use-mootdx-only --output "${fallback}"); then
    run_python - <<PY
import csv, pathlib, sys

primary_rows = list(csv.DictReader(open("${primary}", encoding="utf-8")))
fallback_rows = list(csv.DictReader(open("${fallback}", encoding="utf-8")))

# Compare SH+SZ universes only — mootdx covers BJ via market=2 always,
# but BaoStock doesn't, so a BJ-inclusive check would always trip.
def sh_sz_only(rows):
    return {(r["symbol"]) for r in rows if r["symbol"][:2] not in ("83", "87", "92")}

p, f = sh_sz_only(primary_rows), sh_sz_only(fallback_rows)
union = p | f
delta = len(p ^ f) / max(len(union), 1)
print(f"    cn_a SH+SZ universe — BaoStock={len(p)} mootdx={len(f)} symmetric_diff={delta:.2%}")
if delta > 0.01:
    sys.stderr.write(f"warning: cn_a dual-source diff {delta:.2%} > 1% baseline\n")
    sys.exit(0)  # advisory only
PY
  else
    echo "    warn: mootdx-only pass failed; skipping cross-check" >&2
  fi
  rm -f "${fallback}"
}

bake_ndjson() {
  echo "==> bake: ${OUT_PATH}"
  mkdir -p "$(dirname "${OUT_PATH}")"

  local prev="${OUT_PATH}"
  local tmp="${OUT_PATH}.new"

  (cd "${ROOT_DIR}" && run_python -m tool.asset_catalog.build \
      --sources "${SRC_DIR}" \
      --version "${VERSION}" \
      --output "${tmp}")

  echo "==> diff against previous bundle"
  set +e
  (cd "${ROOT_DIR}" && run_python -m tool.asset_catalog.diff_report \
      --previous "${prev}" \
      --current "${tmp}" \
      --threshold "${DIFF_THRESHOLD}")
  local diff_rc=$?
  set -e
  if [[ $diff_rc -ne 0 && $diff_rc -ne 2 ]]; then
    echo "fatal: diff_report failed with code ${diff_rc}" >&2
    rm -f "${tmp}"
    exit 1
  fi
  if [[ $diff_rc -eq 2 ]]; then
    echo "warn: diff threshold tripped — review the report above" >&2
  fi

  mv "${tmp}" "${OUT_PATH}"

  local raw_size
  raw_size=$(wc -c < "${OUT_PATH}")
  local gzip_size
  gzip_size=$(gzip -c "${OUT_PATH}" | wc -c | tr -d ' ')
  echo "    raw:  ${raw_size} bytes"
  echo "    gzip: ${gzip_size} bytes (budget ${GZIP_BUDGET_BYTES})"
  if (( gzip_size > GZIP_BUDGET_BYTES )); then
    echo "fatal: gzip-compressed catalog exceeds ${GZIP_BUDGET_BYTES} byte budget" >&2
    exit 1
  fi
  echo "catalog written: ${OUT_PATH}"
}

if [[ $FULL -eq 1 ]]; then
  setup_venv
  default_sources=(cn_a hk_stock us_stock crypto)
  if [[ -n "${SOURCES_ARG}" ]]; then
    IFS=',' read -r -a sources <<< "${SOURCES_ARG}"
  else
    sources=("${default_sources[@]}")
  fi
  for source in "${sources[@]}"; do
    run_source "${source}"
  done
  if printf '%s\n' "${sources[@]}" | grep -qx "cn_a"; then
    cross_check_cn_a || true
  fi
fi

if [[ $SKIP_BAKE -eq 0 ]]; then
  bake_ndjson
fi
