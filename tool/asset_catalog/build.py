#!/usr/bin/env python3
"""FIR-76 securities catalog NDJSON builder.

Reads curated CSVs from a source directory and emits the bundled NDJSON
that ``SecuritiesCatalogLoader`` consumes at runtime. Pinyin/initials
columns are precomputed offline so the Flutter app never has to ship a
Chinese-romanisation library.

Source CSV columns (all required, blank cells allowed where noted):

    symbol            — exchange ticker
    market            — wire form (cn_a | hk_stock | us_stock | crypto | fx)
    type              — AssetType.name in Dart (stock | etf | mutualFund | bond | crypto)
    currency          — ISO-ish currency code (CNY, HKD, USD, …)
    name_en           — optional English name
    name_cn           — optional Chinese name
    aliases           — optional whitespace-separated extra search tokens

Usage:

    python3 tool/asset_catalog/build.py \
        --sources tool/asset_catalog/sources \
        --version v1.20260501 \
        --output apps/mobile/assets/catalog/securities.v1.ndjson

The output format and tokenisation rules are documented in
``apps/mobile/lib/data/securities_catalog/securities_catalog_loader.dart``.
The header line carries ``version`` + a deterministic FNV-1a checksum
over the canonicalised entry list.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import pathlib
import sys
from typing import Iterable

try:
    from pypinyin import Style, lazy_pinyin
except ImportError:  # pragma: no cover - optional dep
    lazy_pinyin = None
    Style = None


REQUIRED_COLUMNS = {"symbol", "market", "type", "currency"}
OPTIONAL_COLUMNS = {"name_en", "name_cn", "aliases"}
KNOWN_MARKETS = {"cn_a", "hk_stock", "us_stock", "crypto", "fx", "unknown"}
KNOWN_TYPES = {"stock", "etf", "mutualFund", "bond", "crypto"}


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sources", required=True, type=pathlib.Path)
    parser.add_argument("--version", required=True)
    parser.add_argument("--output", required=True, type=pathlib.Path)
    args = parser.parse_args(argv)

    rows = list(load_rows(args.sources))
    rows.sort(key=lambda r: (r["m"], r["s"]))
    rows = dedupe(rows)

    checksum = fnv1a64(rows)
    header = {
        "version": args.version,
        "checksum": f"{checksum:016x}",
        "count": len(rows),
    }

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="utf-8") as fh:
        fh.write(json.dumps(header, ensure_ascii=False, separators=(",", ":")))
        fh.write("\n")
        for row in rows:
            fh.write(json.dumps(row, ensure_ascii=False, separators=(",", ":")))
            fh.write("\n")
    print(f"wrote {len(rows)} entries → {args.output}", file=sys.stderr)
    return 0


def load_rows(src_dir: pathlib.Path) -> Iterable[dict[str, str]]:
    csv_files = sorted(src_dir.glob("*.csv"))
    if not csv_files:
        print(f"warn: no CSV files found in {src_dir}", file=sys.stderr)
    for path in csv_files:
        with path.open(encoding="utf-8") as fh:
            reader = csv.DictReader(fh)
            missing = REQUIRED_COLUMNS - set(reader.fieldnames or [])
            if missing:
                raise SystemExit(
                    f"{path}: missing required columns: {sorted(missing)}"
                )
            for raw in reader:
                yield normalise(raw, source=path.name)


def normalise(raw: dict[str, str], *, source: str) -> dict[str, str]:
    symbol = (raw.get("symbol") or "").strip()
    market = (raw.get("market") or "").strip()
    type_name = (raw.get("type") or "").strip()
    currency = (raw.get("currency") or "").strip()
    if not symbol:
        raise SystemExit(f"{source}: row with empty symbol")
    if market not in KNOWN_MARKETS:
        raise SystemExit(f"{source}: unknown market {market!r} for {symbol}")
    if type_name not in KNOWN_TYPES:
        raise SystemExit(f"{source}: unknown type {type_name!r} for {symbol}")
    if not currency:
        raise SystemExit(f"{source}: empty currency for {symbol}")
    if ":" in symbol:
        raise SystemExit(f"{source}: symbol must not contain ':' ({symbol!r})")

    name_cn = (raw.get("name_cn") or "").strip() or None
    name_en = (raw.get("name_en") or "").strip() or None
    aliases = (raw.get("aliases") or "").strip() or None

    pinyin_full, pinyin_initials = pinyin_for(name_cn)

    entry = {
        "s": symbol,
        "m": market,
        "t": type_name,
        "c": currency,
    }
    if name_en:
        entry["ne"] = name_en
    if name_cn:
        entry["nc"] = name_cn
    if pinyin_full:
        entry["p"] = pinyin_full
    if pinyin_initials:
        entry["pi"] = pinyin_initials
    if aliases:
        entry["a"] = aliases
    return entry


def pinyin_for(name_cn: str | None) -> tuple[str | None, str | None]:
    if not name_cn:
        return None, None
    if lazy_pinyin is None:
        # Allow the script to run without pypinyin installed in CI by
        # falling back to the alias slot. Build host should have pypinyin
        # available; without it, callers must supply pinyin via aliases.
        return None, None
    syllables = lazy_pinyin(name_cn, style=Style.NORMAL)
    full = "".join(s.lower() for s in syllables if s)
    initials = "".join((s[0].lower() if s else "") for s in syllables)
    return (full or None, initials or None)


def dedupe(rows: list[dict[str, str]]) -> list[dict[str, str]]:
    seen: set[tuple[str, str]] = set()
    out: list[dict[str, str]] = []
    for row in rows:
        key = (row["m"], row["s"].lower())
        if key in seen:
            continue
        seen.add(key)
        out.append(row)
    return out


def fnv1a64(rows: list[dict[str, str]]) -> int:
    """Deterministic 64-bit FNV-1a over the sorted, JSON-serialised rows.

    Independent of Python's randomised hash and stable across runs, so
    callers can compare ``securities_catalog_meta.checksum`` across
    devices to detect drift. The checksum is informational — callers
    who care about authenticity should sign the bundle separately.
    """
    blob = b"\n".join(
        json.dumps(r, ensure_ascii=False, sort_keys=True).encode("utf-8")
        for r in rows
    )
    h = 0xCBF29CE484222325
    for byte in blob:
        h ^= byte
        h = (h * 0x100000001B3) & 0xFFFFFFFFFFFFFFFF
    return h


# Used by tests (and humans) that want a SHA256 cross-check rather than
# the FNV variant the loader compares against. Kept here so the build
# script and the Dart loader agree on which bytes are canonical.
def sha256_canonical(rows: list[dict[str, str]]) -> str:
    h = hashlib.sha256()
    for row in rows:
        h.update(json.dumps(row, ensure_ascii=False, sort_keys=True).encode())
        h.update(b"\n")
    return h.hexdigest()


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
