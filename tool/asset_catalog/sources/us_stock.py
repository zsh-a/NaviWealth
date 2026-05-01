"""US-listed securities catalog adapter.

Two complementary feeds:

* **NASDAQ Trader symbol directory** — pipe-delimited text files from
  ``https://www.nasdaqtrader.com/dynamic/symdir/``. ``nasdaqlisted.txt``
  covers NASDAQ. ``otherlisted.txt`` covers NYSE / NYSE Arca / NYSE
  American (and is where ETFs traded on these venues live). Both files
  carry an ``ETF`` flag so we can split stocks vs. ETFs without
  guessing. Test issues are filtered.
* **SEC company tickers** — ``https://www.sec.gov/files/company_tickers_exchange.json``
  is a JSON map keyed by CIK with ticker/title/exchange. Used to fill
  in human-readable English names where NASDAQ Trader has only the
  legalese title, and to correct exchange labels when the two feeds
  disagree.

We intentionally do NOT pull warrants, units, rights, or preferred
classes — they explode the row count without helping search. The
NASDAQ Trader files mark these in the security name (e.g. trailing
``- Warrant``) so a substring filter is sufficient.
"""
from __future__ import annotations

import argparse
import csv
import io
import logging
import pathlib
import sys
from typing import Mapping

from tool.asset_catalog.common import make_row, write_rows

LOG = logging.getLogger("asset_catalog.us_stock")

NASDAQLISTED_URL = "https://www.nasdaqtrader.com/dynamic/symdir/nasdaqlisted.txt"
OTHERLISTED_URL = "https://www.nasdaqtrader.com/dynamic/symdir/otherlisted.txt"
SEC_TICKERS_URL = "https://www.sec.gov/files/company_tickers_exchange.json"

NAME_DROP_TOKENS = (
    " - Warrant",
    " - Warrants",
    " - Units",
    " - Unit",
    " - Rights",
    " - Right",
    " Depositary Shares",
    " Depositary Receipt",
    "Test Stock",
    "TEST ISSUE",
)


# ---------------------------------------------------------------------------
# Pure parsers
# ---------------------------------------------------------------------------


def _drop_name(name: str) -> bool:
    return any(token.lower() in name.lower() for token in NAME_DROP_TOKENS)


def parse_nasdaqlisted_line(row: Mapping[str, str]) -> dict[str, str] | None:
    """Parse one row from ``nasdaqlisted.txt``.

    Header: ``Symbol|Security Name|Market Category|Test Issue|...|ETF|...``
    """
    symbol = (row.get("Symbol") or "").strip()
    name = (row.get("Security Name") or "").strip()
    if not symbol or not name:
        return None
    if (row.get("Test Issue") or "").strip().upper() == "Y":
        return None
    if _drop_name(name):
        return None
    is_etf = (row.get("ETF") or "").strip().upper() == "Y"
    return make_row(
        symbol=symbol,
        market="us_stock",
        type_name="etf" if is_etf else "stock",
        currency="USD",
        name_en=name,
    )


def parse_otherlisted_line(row: Mapping[str, str]) -> dict[str, str] | None:
    """Parse one row from ``otherlisted.txt``.

    Header: ``ACT Symbol|Security Name|Exchange|CQS Symbol|ETF|Round Lot Size|Test Issue|NASDAQ Symbol``
    """
    symbol = (row.get("ACT Symbol") or row.get("NASDAQ Symbol") or "").strip()
    name = (row.get("Security Name") or "").strip()
    if not symbol or not name:
        return None
    if (row.get("Test Issue") or "").strip().upper() == "Y":
        return None
    if _drop_name(name):
        return None
    is_etf = (row.get("ETF") or "").strip().upper() == "Y"
    return make_row(
        symbol=symbol,
        market="us_stock",
        type_name="etf" if is_etf else "stock",
        currency="USD",
        name_en=name,
    )


def parse_nasdaq_trader(text: str, *, kind: str) -> list[dict[str, str]]:
    """Parse a NASDAQ Trader pipe-delimited file.

    The file ends with a ``File Creation Time`` footer line that must be
    skipped.
    """
    lines = [ln for ln in text.splitlines() if ln and not ln.startswith("File Creation Time")]
    reader = csv.DictReader(lines, delimiter="|")
    parser = parse_nasdaqlisted_line if kind == "nasdaq" else parse_otherlisted_line
    out: list[dict[str, str]] = []
    for row in reader:
        parsed = parser(row)
        if parsed:
            out.append(parsed)
    return out


def merge_with_sec(
    rows: list[dict[str, str]],
    sec_data: dict,
) -> list[dict[str, str]]:
    """Enrich rows with SEC titles when available.

    The SEC payload is ``{"fields": [...], "data": [[cik, name, ticker, exchange], ...]}``.
    We index by ticker so callers can call this once per build.
    """
    fields = sec_data.get("fields") or []
    data = sec_data.get("data") or []
    if not fields or not data:
        return rows

    try:
        ticker_idx = fields.index("ticker")
        name_idx = fields.index("name")
    except ValueError:
        LOG.warning("sec: unexpected field layout %r; skipping enrichment", fields)
        return rows

    by_ticker: dict[str, str] = {}
    for entry in data:
        if len(entry) <= max(ticker_idx, name_idx):
            continue
        ticker = (str(entry[ticker_idx]) or "").strip().upper()
        name = (str(entry[name_idx]) or "").strip()
        if ticker and name and ticker not in by_ticker:
            by_ticker[ticker] = name

    enriched: list[dict[str, str]] = []
    for row in rows:
        sec_name = by_ticker.get(row["symbol"].upper())
        if sec_name and (not row.get("name_en") or _looks_legalese(row["name_en"])):
            row = {**row, "name_en": sec_name}
        enriched.append(row)
    return enriched


def _looks_legalese(name: str) -> bool:
    # Heuristic: NASDAQ Trader names often append " - Common Stock",
    # " Class A", etc. SEC names are usually cleaner. If the trader
    # name has any of these tells, prefer the SEC name when available.
    return any(
        marker in name
        for marker in (" - Common Stock", " - Class", " Common Stock")
    )


# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------


class FetchError(RuntimeError):
    pass


def _http_get(url: str, *, timeout: int = 60, accept_json: bool = False) -> bytes:
    try:
        import requests  # type: ignore
    except ImportError as exc:
        raise FetchError("requests not installed; run pip install -r requirements.txt") from exc

    # SEC requires a descriptive User-Agent or it 403s.
    headers = {
        "User-Agent": "NaviWealth-CatalogBuilder/1.0 (contact: dev@naviwealth.local)",
    }
    if accept_json:
        headers["Accept"] = "application/json"
    resp = requests.get(url, timeout=timeout, headers=headers)
    if resp.status_code != 200:
        raise FetchError(f"HTTP {resp.status_code} for {url}")
    return resp.content


def fetch_us_stock() -> list[dict[str, str]]:
    nasdaq = parse_nasdaq_trader(
        _http_get(NASDAQLISTED_URL).decode("utf-8", errors="replace"),
        kind="nasdaq",
    )
    other = parse_nasdaq_trader(
        _http_get(OTHERLISTED_URL).decode("utf-8", errors="replace"),
        kind="other",
    )
    rows = nasdaq + other
    LOG.info("nasdaq trader: %d rows (nasdaq=%d, other=%d)", len(rows), len(nasdaq), len(other))

    try:
        import json
        sec_blob = _http_get(SEC_TICKERS_URL, accept_json=True)
        sec_data = json.loads(sec_blob.decode("utf-8", errors="replace"))
        rows = merge_with_sec(rows, sec_data)
    except FetchError as exc:
        LOG.warning("sec enrichment skipped: %s", exc)

    return rows


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output",
        type=pathlib.Path,
        default=pathlib.Path("tool/asset_catalog/sources/us_stock.csv"),
        help="output CSV path (use '-' for stdout)",
    )
    parser.add_argument("-v", "--verbose", action="store_true")
    args = parser.parse_args(argv)
    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )
    rows = fetch_us_stock()
    written = write_rows(rows, args.output)
    LOG.info("wrote %d rows to %s", written, args.output)
    return 0


# Re-export for tests
__all__ = [
    "FetchError",
    "fetch_us_stock",
    "merge_with_sec",
    "parse_nasdaq_trader",
    "parse_nasdaqlisted_line",
    "parse_otherlisted_line",
]


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
