#!/usr/bin/env bash
# Wave 42 — verify every translation key exists in both en and zh ARB
# files (and only in both). One side adding a key without the other
# is a deployment hazard: the UI silently falls back to en at runtime
# for missing zh keys, and 中文 users see the English string.
#
# Uses Python's stdlib `json` for accurate top-level key extraction
# (regex parsing trips on nested `@metadata` blocks).
#
# Exit codes:
#   0 — top-level translation key sets identical
#   1 — at least one key is on one side only
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EN="${REPO_ROOT}/lib/l10n/app_en.arb"
ZH="${REPO_ROOT}/lib/l10n/app_zh.arb"

if [[ ! -f "${EN}" || ! -f "${ZH}" ]]; then
  echo "::error::ARB files missing — looked in ${EN} and ${ZH}"
  exit 1
fi

python3 - "${EN}" "${ZH}" <<'PY'
import json
import sys
from pathlib import Path

en_path, zh_path = (Path(p) for p in sys.argv[1:3])

def keys(path):
    raw = json.loads(path.read_text(encoding="utf-8"))
    # Top-level translation keys are everything except `@`-prefixed
    # metadata and ARB-control directives (e.g. `@@locale`).
    return {k for k in raw.keys() if not k.startswith("@")}

en_keys = keys(en_path)
zh_keys = keys(zh_path)

only_en = en_keys - zh_keys
only_zh = zh_keys - en_keys

if not only_en and not only_zh:
    print(f"✅ ARB key parity: {len(en_keys)} shared keys.")
    sys.exit(0)

print("::error::ARB key parity broken between app_en.arb and app_zh.arb:")
if only_en:
    print("  Keys present in en but missing from zh:")
    for k in sorted(only_en):
        print(f"    - {k}")
if only_zh:
    print("  Keys present in zh but missing from en:")
    for k in sorted(only_zh):
        print(f"    - {k}")
sys.exit(1)
PY
