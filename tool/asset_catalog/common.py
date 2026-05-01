"""Shared helpers for catalog source adapters.

Adapters all produce the same CSV schema (``symbol``, ``market``, ``type``,
``currency``, ``name_en``, ``name_cn``, ``aliases``) consumed by
``build.py``. This module owns the writer + Chinese-name normaliser so
that adapters stay focused on the upstream feed they wrap.
"""
from __future__ import annotations

import csv
import io
import pathlib
import sys
from typing import Iterable, Mapping

CSV_FIELDS = (
    "symbol",
    "market",
    "type",
    "currency",
    "name_en",
    "name_cn",
    "aliases",
)


# Lazy singletons so importing this module is free even without OpenCC
# installed (test environments and the stub fast path).
_OPENCC = None
_OPENCC_TRIED = False


def _get_opencc():
    global _OPENCC, _OPENCC_TRIED
    if _OPENCC_TRIED:
        return _OPENCC
    _OPENCC_TRIED = True
    try:
        from opencc import OpenCC  # type: ignore
    except ImportError:
        return None
    _OPENCC = OpenCC("t2s")
    return _OPENCC


def to_simplified(text: str | None) -> str:
    """Convert traditional Chinese to simplified, pass-through if unavailable.

    Adapters that ingest mixed traditional/English feeds (HKEX) call this
    before writing ``name_cn`` so downstream pinyin generation produces
    canonical mainland output.
    """
    if not text:
        return ""
    cc = _get_opencc()
    if cc is None:
        return text
    return cc.convert(text)


def write_rows(
    rows: Iterable[Mapping[str, str]],
    output: pathlib.Path | str | None,
) -> int:
    """Write ``rows`` to a CSV file (or stdout when ``output`` is None).

    Returns the number of rows written. Stable column order; missing
    optional columns become empty strings.
    """
    rows = list(rows)
    if output in (None, "-"):
        _emit(rows, sys.stdout)
        return len(rows)

    output_path = pathlib.Path(output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    # Buffer to a string first so a partial write never leaves a
    # truncated CSV behind on disk.
    buf = io.StringIO()
    _emit(rows, buf)
    output_path.write_text(buf.getvalue(), encoding="utf-8")
    return len(rows)


def _emit(rows: list[Mapping[str, str]], stream) -> None:
    writer = csv.DictWriter(stream, fieldnames=list(CSV_FIELDS), lineterminator="\n")
    writer.writeheader()
    for row in rows:
        writer.writerow({key: row.get(key, "") or "" for key in CSV_FIELDS})


def make_row(
    *,
    symbol: str,
    market: str,
    type_name: str,
    currency: str,
    name_en: str = "",
    name_cn: str = "",
    aliases: str = "",
) -> dict[str, str]:
    return {
        "symbol": symbol,
        "market": market,
        "type": type_name,
        "currency": currency,
        "name_en": name_en or "",
        "name_cn": name_cn or "",
        "aliases": aliases or "",
    }
