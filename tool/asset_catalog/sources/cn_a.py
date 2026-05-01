"""A-share (Shanghai + Shenzhen + Beijing) catalog adapter.

Layout
------
* **Primary**: BaoStock for Shanghai + Shenzhen. ``query_all_stock`` gives
  the universe; ``query_stock_basic(code=...)`` returns a ``type`` field
  (1=stock, 2=index, 3=other, 4=bond, 5=etf) that lets us classify the
  row authoritatively without code-prefix heuristics.
* **Beijing**: mootdx ``Quotes.factory`` against the BSE market
  (``market=2``). BaoStock does not cover the BSE so this is mandatory,
  not just a fallback.
* **Fallback**: when BaoStock is unreachable, we drop down to mootdx for
  all three markets (``market=0/1/2``) and use ``classify.classify_a_share``
  to recover the asset type from the bare code.

The script can be invoked as a module so the Bash orchestrator can call
it uniformly:

    python3 -m tool.asset_catalog.sources.cn_a \\
        --output tool/asset_catalog/sources/cn_a.csv

Optional flags:

    --no-fallback      do not attempt mootdx when BaoStock fails
    --use-mootdx-only  skip BaoStock entirely (smoke testing the fallback)
    --date YYYY-MM-DD  override the BaoStock universe trading date
"""
from __future__ import annotations

import argparse
import logging
import pathlib
import sys

from tool.asset_catalog.classify import (
    MARKET_BJ,
    MARKET_SH,
    MARKET_SZ,
    classify_a_share,
)
from tool.asset_catalog.common import make_row, write_rows

LOG = logging.getLogger("asset_catalog.cn_a")

# BaoStock numeric type codes.
BAOSTOCK_TYPE_MAP = {
    "1": "stock",
    "4": "bond",
    "5": "etf",
    # 2 (index) and 3 (other) are dropped — they are not tradable assets
    # and would inflate the catalog without helping search.
}

MOOTDX_MARKET_LABEL = {0: MARKET_SZ, 1: MARKET_SH, 2: MARKET_BJ}


# ---------------------------------------------------------------------------
# Pure parsers (covered by tests; no network)
# ---------------------------------------------------------------------------


def parse_baostock_basic(
    code: str,
    code_name: str,
    type_code: str | int,
    *,
    status: str | int | None = None,
) -> dict[str, str] | None:
    """Translate one BaoStock ``query_stock_basic`` row to a CSV row.

    Returns ``None`` when the row should be dropped (delisted, untyped,
    or an instrument we explicitly exclude such as indices).
    """
    if not code or not code_name:
        return None
    if status is not None and str(status) not in ("1", ""):
        # status=0 means delisted in BaoStock. Empty is treated as live to
        # keep tests forgiving when fixtures omit the field.
        return None
    asset_type = BAOSTOCK_TYPE_MAP.get(str(type_code))
    if not asset_type:
        return None
    if "." in code:
        _market, raw_code = code.split(".", 1)
    else:
        raw_code = code
    raw_code = raw_code.strip()
    if not raw_code:
        return None
    return make_row(
        symbol=raw_code,
        market="cn_a",
        type_name=asset_type,
        currency="CNY",
        name_cn=code_name.strip(),
    )


def parse_mootdx_row(
    market_id: int,
    raw: dict,
) -> dict[str, str] | None:
    """Translate one mootdx ``get_security_list`` row to a CSV row."""
    market_label = MOOTDX_MARKET_LABEL.get(int(market_id))
    if market_label is None:
        return None
    code = str(raw.get("code") or raw.get("Code") or "").strip()
    name = str(raw.get("name") or raw.get("Name") or "").strip()
    if not code or not name:
        return None
    asset_type = classify_a_share(market_label, code)
    if not asset_type:
        return None
    return make_row(
        symbol=code,
        market="cn_a",
        type_name=asset_type,
        currency="CNY",
        name_cn=name,
    )


# ---------------------------------------------------------------------------
# Network paths (BaoStock + mootdx)
# ---------------------------------------------------------------------------


class FetchError(RuntimeError):
    """Raised when an upstream source fails after exhausting retries."""


def fetch_baostock_universe(date: str | None = None) -> list[dict[str, str]]:
    """Fetch the SH+SZ universe from BaoStock.

    Side effects: opens a BaoStock session for the duration of the call.
    Yields rows already mapped to the catalog CSV schema (i.e. indices /
    delisted / unknown-type entries are filtered out).
    """
    try:
        import baostock as bs  # type: ignore
    except ImportError as exc:
        raise FetchError("baostock not installed; run pip install -r requirements.txt") from exc

    login = bs.login()
    if str(getattr(login, "error_code", "0")) != "0":
        raise FetchError(
            f"baostock login failed: code={login.error_code} msg={login.error_msg}"
        )
    try:
        universe = bs.query_all_stock(day=date or "") if date else bs.query_all_stock()
        if str(getattr(universe, "error_code", "0")) != "0":
            raise FetchError(
                f"baostock query_all_stock failed: code={universe.error_code} "
                f"msg={universe.error_msg}"
            )
        codes: list[str] = []
        while universe.error_code == "0" and universe.next():
            row = universe.get_row_data()
            if row:
                codes.append(row[0])
        LOG.info("baostock universe: %d codes (date=%s)", len(codes), date or "latest")

        rows: list[dict[str, str]] = []
        for code in codes:
            basic = bs.query_stock_basic(code=code)
            if str(getattr(basic, "error_code", "0")) != "0":
                LOG.warning(
                    "baostock query_stock_basic %s failed: %s",
                    code,
                    basic.error_msg,
                )
                continue
            while basic.next():
                fields = basic.get_row_data()
                # Field order per BaoStock docs:
                # code, code_name, ipoDate, outDate, type, status
                if len(fields) < 6:
                    continue
                parsed = parse_baostock_basic(
                    code=fields[0],
                    code_name=fields[1],
                    type_code=fields[4],
                    status=fields[5],
                )
                if parsed:
                    rows.append(parsed)
        return rows
    finally:
        bs.logout()


def fetch_mootdx_market(market_id: int) -> list[dict[str, str]]:
    """Fetch one market from mootdx (TCP fan-out under the hood).

    ``market_id``: 0=Shenzhen, 1=Shanghai, 2=Beijing.
    """
    try:
        from mootdx.quotes import Quotes  # type: ignore
    except ImportError as exc:
        raise FetchError("mootdx not installed; run pip install -r requirements.txt") from exc

    client = Quotes.factory(market="std")
    try:
        count = client.stock_count(market=market_id)
    except Exception as exc:  # pragma: no cover - upstream API surface
        raise FetchError(f"mootdx stock_count(market={market_id}) failed: {exc}") from exc

    rows: list[dict[str, str]] = []
    page = 1000
    for offset in range(0, int(count), page):
        try:
            chunk = client.stocks(market=market_id, start=offset)
        except Exception as exc:  # pragma: no cover - upstream API surface
            raise FetchError(
                f"mootdx stocks(market={market_id}, start={offset}) failed: {exc}"
            ) from exc
        if chunk is None:
            continue
        # mootdx may return a pandas DataFrame or list[dict] depending on
        # version. Normalise to dict iteration.
        records = chunk.to_dict("records") if hasattr(chunk, "to_dict") else list(chunk)
        for raw in records:
            parsed = parse_mootdx_row(market_id, dict(raw))
            if parsed:
                rows.append(parsed)
    LOG.info("mootdx market=%d: %d catalog rows", market_id, len(rows))
    return rows


def fetch_cn_a(
    *,
    date: str | None = None,
    allow_fallback: bool = True,
    use_mootdx_only: bool = False,
) -> list[dict[str, str]]:
    """Fetch the full SH+SZ+BJ catalog using BaoStock + mootdx.

    Network strategy:
      - SH+SZ from BaoStock (typed, authoritative).
      - BJ from mootdx (BaoStock has no BSE coverage).
      - On BaoStock failure, fall back to mootdx for SH+SZ as well,
        unless ``allow_fallback=False``.
    """
    if use_mootdx_only:
        out: list[dict[str, str]] = []
        for market in (0, 1, 2):
            out.extend(fetch_mootdx_market(market))
        return out

    try:
        sh_sz = fetch_baostock_universe(date=date)
    except FetchError as exc:
        if not allow_fallback:
            raise
        LOG.warning("baostock unreachable (%s); falling back to mootdx", exc)
        out = []
        for market in (0, 1, 2):
            out.extend(fetch_mootdx_market(market))
        return out

    bj = fetch_mootdx_market(2)
    return sh_sz + bj


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def _parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output",
        type=pathlib.Path,
        default=pathlib.Path("tool/asset_catalog/sources/cn_a.csv"),
        help="output CSV path (use '-' for stdout)",
    )
    parser.add_argument("--date", default=None, help="BaoStock universe trading date (YYYY-MM-DD)")
    parser.add_argument("--no-fallback", action="store_true")
    parser.add_argument("--use-mootdx-only", action="store_true")
    parser.add_argument("-v", "--verbose", action="store_true")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = _parse_args(argv)
    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )
    rows = fetch_cn_a(
        date=args.date,
        allow_fallback=not args.no_fallback,
        use_mootdx_only=args.use_mootdx_only,
    )
    written = write_rows(rows, args.output)
    LOG.info("wrote %d rows to %s", written, args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
