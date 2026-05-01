"""Crypto catalog adapter (CoinGecko).

CoinGecko ``/coins/list?include_platform=false`` returns ~14k entries,
the long tail of which is dust. We rank by market cap via
``/coins/markets`` (paginated, ``per_page=250``, ``order=market_cap_desc``)
and keep only the top ``--top-n`` (default 500). The free public API is
rate-limited to ~10–30 requests/min which is plenty: top-500 fits in
two pages.

Symbols are uppercased and suffixed with ``-USD`` so they match the
already-shipped stub catalog and the format other parts of NaviWealth
use for crypto pricing pairs.

Optional ``COINGECKO_API_KEY`` env var switches to the demo/Pro API
host when set, lifting the rate ceiling for CI runs.
"""
from __future__ import annotations

import argparse
import logging
import os
import pathlib
import sys
import time
from typing import Iterable

from tool.asset_catalog.common import make_row, write_rows

LOG = logging.getLogger("asset_catalog.crypto")

DEFAULT_TOP_N = 500
PAGE_SIZE = 250  # CoinGecko's max
PUBLIC_API = "https://api.coingecko.com/api/v3"
DEMO_API = "https://api.coingecko.com/api/v3"  # Pro hosts use a different domain
PRO_API = "https://pro-api.coingecko.com/api/v3"


# Common Chinese names for the very top coins. CoinGecko has a
# ``localization=true`` endpoint per coin, but that's one request per
# coin which blows the rate limit for the top-500. We seed the most
# searched names here; everything else falls back to the English name.
ZH_OVERRIDES: dict[str, str] = {
    "BTC": "比特币",
    "ETH": "以太坊",
    "USDT": "泰达币",
    "USDC": "USD Coin",
    "BNB": "币安币",
    "SOL": "索拉纳",
    "XRP": "瑞波币",
    "ADA": "卡尔达诺",
    "DOGE": "狗狗币",
    "TRX": "波场",
    "TON": "Toncoin",
    "DOT": "波卡",
    "MATIC": "Polygon",
    "LTC": "莱特币",
    "BCH": "比特币现金",
    "AVAX": "雪崩",
    "LINK": "Chainlink",
    "ATOM": "宇宙",
    "SHIB": "柴犬币",
    "UNI": "Uniswap",
    "FIL": "Filecoin",
    "ETC": "以太经典",
    "XLM": "恒星币",
    "NEAR": "NEAR",
    "APT": "Aptos",
    "ARB": "Arbitrum",
    "OP": "Optimism",
}


# ---------------------------------------------------------------------------
# Pure parser
# ---------------------------------------------------------------------------


def parse_market_entry(entry: dict) -> dict[str, str] | None:
    """Translate one ``/coins/markets`` row to a CSV row."""
    raw_symbol = (entry.get("symbol") or "").strip().upper()
    name_en = (entry.get("name") or "").strip()
    if not raw_symbol or not name_en:
        return None
    symbol = f"{raw_symbol}-USD"
    name_cn = ZH_OVERRIDES.get(raw_symbol, "")
    aliases = entry.get("id") or ""  # CoinGecko id, e.g. "bitcoin"
    return make_row(
        symbol=symbol,
        market="crypto",
        type_name="crypto",
        currency="USD",
        name_en=name_en,
        name_cn=name_cn,
        aliases=aliases.lower() if aliases else "",
    )


def parse_market_pages(pages: Iterable[Iterable[dict]]) -> list[dict[str, str]]:
    """Flatten CoinGecko market pages into deduplicated catalog rows."""
    seen: set[str] = set()
    out: list[dict[str, str]] = []
    for page in pages:
        for entry in page:
            row = parse_market_entry(entry)
            if not row:
                continue
            if row["symbol"] in seen:
                continue
            seen.add(row["symbol"])
            out.append(row)
    return out


# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------


class FetchError(RuntimeError):
    pass


def _resolve_host() -> tuple[str, dict[str, str]]:
    api_key = os.environ.get("COINGECKO_API_KEY") or os.environ.get("CG_API_KEY")
    if api_key:
        return PRO_API, {"x-cg-pro-api-key": api_key}
    return PUBLIC_API, {}


def fetch_top_n(top_n: int = DEFAULT_TOP_N, *, sleep: float = 6.0) -> list[dict[str, str]]:
    """Fetch the top ``top_n`` coins ranked by market cap.

    ``sleep`` is the inter-page delay (seconds) — keeps the public API
    happy at 10 req/min.
    """
    try:
        import requests  # type: ignore
    except ImportError as exc:
        raise FetchError("requests not installed; run pip install -r requirements.txt") from exc

    base, headers = _resolve_host()
    headers = {"User-Agent": "NaviWealth-CatalogBuilder/1.0", **headers}
    pages: list[list[dict]] = []
    pages_needed = (top_n + PAGE_SIZE - 1) // PAGE_SIZE

    for page in range(1, pages_needed + 1):
        params = {
            "vs_currency": "usd",
            "order": "market_cap_desc",
            "per_page": str(PAGE_SIZE),
            "page": str(page),
            "sparkline": "false",
        }
        resp = requests.get(
            f"{base}/coins/markets",
            params=params,
            headers=headers,
            timeout=30,
        )
        if resp.status_code != 200:
            raise FetchError(
                f"coingecko HTTP {resp.status_code} on page {page}: {resp.text[:200]}"
            )
        data = resp.json()
        if not isinstance(data, list):
            raise FetchError(f"coingecko unexpected payload type: {type(data)!r}")
        pages.append(data)
        LOG.info("coingecko page %d/%d: %d coins", page, pages_needed, len(data))
        if page < pages_needed:
            time.sleep(sleep)

    rows = parse_market_pages(pages)
    return rows[:top_n]


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output",
        type=pathlib.Path,
        default=pathlib.Path("tool/asset_catalog/sources/crypto.csv"),
        help="output CSV path (use '-' for stdout)",
    )
    parser.add_argument("--top-n", type=int, default=DEFAULT_TOP_N)
    parser.add_argument("--sleep", type=float, default=6.0)
    parser.add_argument("-v", "--verbose", action="store_true")
    args = parser.parse_args(argv)
    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )
    rows = fetch_top_n(top_n=args.top_n, sleep=args.sleep)
    written = write_rows(rows, args.output)
    LOG.info("wrote %d rows to %s", written, args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
