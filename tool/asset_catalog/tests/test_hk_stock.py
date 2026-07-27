import pytest

import tool.asset_catalog.sources.hk_stock as hk_stock
from tool.asset_catalog.validate_release import DEFAULT_MIN_MARKET_COUNTS
from tool.asset_catalog.sources.hk_stock import (
    CATEGORY_TYPE_MAP,
    DROPPED_CATEGORIES,
    FetchError,
    MIN_HK_STOCK_ROWS,
    _fetch_yfinance_screen,
    fetch_hk_stock,
    parse_hkex_row,
    parse_yfinance_quote,
)


class TestParseHkexRow:
    def test_equity(self):
        row = parse_hkex_row(700, "TENCENT", "Equity")
        assert row is not None
        assert row["symbol"] == "0700.HK"
        assert row["market"] == "hk_stock"
        assert row["type"] == "stock"
        assert row["currency"] == "HKD"
        assert row["name_en"] == "TENCENT"

    def test_traditional_chinese_name(self):
        row = parse_hkex_row(9988, "阿里巴巴-SW", "Equity")
        assert row is not None
        # name_cn should be populated; name_en empty (looks-Latin heuristic).
        assert row["name_cn"]
        assert row["name_en"] == ""

    def test_etf(self):
        row = parse_hkex_row(2800, "TRACKER FUND OF HONG KONG", "ETF")
        assert row is not None
        assert row["type"] == "etf"
        assert row["symbol"] == "2800.HK"

    def test_reit_treated_as_stock(self):
        row = parse_hkex_row(823, "LINK REIT", "REIT")
        assert row is not None
        assert row["type"] == "stock"

    def test_dropped_category(self):
        for cat in DROPPED_CATEGORIES:
            assert parse_hkex_row(99999, "FOOBAR CBBC", cat) is None

    def test_unknown_category_dropped(self):
        assert parse_hkex_row(700, "TENCENT", "Mystery Box") is None

    def test_string_code_padded(self):
        row = parse_hkex_row("388", "HKEX", "Equity")
        assert row is not None
        assert row["symbol"] == "0388.HK"

    def test_official_five_character_code_normalised(self):
        row = parse_hkex_row("00700", "TENCENT", "Equity")
        assert row is not None
        assert row["symbol"] == "0700.HK"

    def test_long_code_preserved(self):
        # 5-digit codes (mostly DWs) shouldn't be truncated.
        row = parse_hkex_row("12345", "DERIVATIVE WARRANT", "DW")
        assert row is not None
        assert row["symbol"] == "12345.HK"

    def test_non_numeric_code_dropped(self):
        assert parse_hkex_row("ABC", "JUNK", "Equity") is None

    def test_empty_inputs(self):
        assert parse_hkex_row("", "x", "Equity") is None
        assert parse_hkex_row(700, "", "Equity") is None
        assert parse_hkex_row(None, None, None) is None


def test_category_map_has_no_duplicates():
    """Drop-categories and type-map must not overlap, otherwise classifications collide."""
    overlap = set(CATEGORY_TYPE_MAP) & DROPPED_CATEGORIES
    assert not overlap, f"category collision: {overlap}"


def test_fallback_floor_matches_release_policy():
    assert MIN_HK_STOCK_ROWS == dict(DEFAULT_MIN_MARKET_COUNTS)["hk_stock"]


class TestParseYfinanceQuote:
    def test_equity(self):
        row = parse_yfinance_quote(
            {
                "symbol": "0700.HK",
                "shortName": "TENCENT",
                "quoteType": "EQUITY",
                "exchange": "HKG",
                "currency": "HKD",
            },
            type_name="stock",
        )
        assert row is not None
        assert row["symbol"] == "0700.HK"
        assert row["type"] == "stock"
        assert row["name_en"] == "TENCENT"

    def test_etf(self):
        row = parse_yfinance_quote(
            {
                "symbol": "2800.HK",
                "longName": "Tracker Fund of Hong Kong",
                "quoteType": "ETF",
                "exchange": "HKG",
                "currency": "HKD",
            },
            type_name="etf",
        )
        assert row is not None
        assert row["type"] == "etf"

    @pytest.mark.parametrize(
        ("quote", "type_name"),
        [
            (
                {
                    "symbol": "14741.HK",
                    "shortName": "DERIVATIVE WARRANT",
                    "quoteType": "EQUITY",
                    "exchange": "HKG",
                    "currency": "HKD",
                },
                "stock",
            ),
            (
                {
                    "symbol": "0700.HK",
                    "shortName": "TENCENT",
                    "quoteType": "EQUITY",
                    "exchange": "NYQ",
                    "currency": "HKD",
                },
                "stock",
            ),
            (
                {
                    "symbol": "0700.HK",
                    "shortName": "TENCENT",
                    "quoteType": "EQUITY",
                    "exchange": "HKG",
                    "currency": "CNY",
                },
                "stock",
            ),
            (
                {
                    "symbol": "0700.HK",
                    "shortName": "",
                    "quoteType": "EQUITY",
                    "exchange": "HKG",
                    "currency": "HKD",
                },
                "stock",
            ),
        ],
    )
    def test_rejects_non_catalog_quote(self, quote, type_name):
        assert parse_yfinance_quote(quote, type_name=type_name) is None


def test_yfinance_screen_paginates():
    calls = []

    def fake_screen(query, *, offset, size, sortField, sortAsc):
        calls.append((query, offset, size, sortField, sortAsc))
        remaining = 501 - offset
        count = min(size, max(remaining, 0))
        return {
            "total": 501,
            "quotes": [{"symbol": f"{offset + i:04d}.HK"} for i in range(count)],
        }

    rows = _fetch_yfinance_screen(fake_screen, "query")

    assert len(rows) == 501
    assert [call[1] for call in calls] == [0, 250, 500]


def test_yfinance_screen_rejects_truncated_page():
    def fake_screen(query, *, offset, size, sortField, sortAsc):
        return {
            "total": 500,
            "quotes": [{"symbol": "0001.HK"}] if offset == 0 else [],
        }

    with pytest.raises(FetchError, match="stopped at offset 250"):
        _fetch_yfinance_screen(fake_screen, "query")


def test_yfinance_screen_rejects_duplicate_pages():
    def fake_screen(query, *, offset, size, sortField, sortAsc):
        return {
            "total": 500,
            "quotes": [{"symbol": f"{i:04d}.HK"} for i in range(250)],
        }

    with pytest.raises(FetchError, match="duplicate symbols"):
        _fetch_yfinance_screen(fake_screen, "query")


def test_fetch_hk_stock_prefers_healthy_hkex(monkeypatch):
    expected = [{"symbol": f"{i:04d}.HK"} for i in range(MIN_HK_STOCK_ROWS)]
    monkeypatch.setattr(hk_stock, "fetch_hkex", lambda: b"workbook")
    monkeypatch.setattr(hk_stock, "parse_workbook", lambda blob: expected)
    monkeypatch.setattr(
        hk_stock,
        "fetch_yfinance",
        lambda: pytest.fail("fallback should not run"),
    )

    assert fetch_hk_stock() is expected


def test_fetch_hk_stock_falls_back_for_truncated_hkex(monkeypatch):
    expected = [{"symbol": f"{i:04d}.HK"} for i in range(MIN_HK_STOCK_ROWS)]
    monkeypatch.setattr(hk_stock, "fetch_hkex", lambda: b"workbook")
    monkeypatch.setattr(hk_stock, "parse_workbook", lambda blob: expected[:5])
    monkeypatch.setattr(hk_stock, "fetch_yfinance", lambda: expected)

    assert fetch_hk_stock() is expected


def test_fetch_hk_stock_fails_when_fallback_is_too_small(monkeypatch):
    monkeypatch.setattr(
        hk_stock,
        "fetch_hkex",
        lambda: (_ for _ in ()).throw(FetchError("upstream unavailable")),
    )
    monkeypatch.setattr(
        hk_stock,
        "fetch_yfinance",
        lambda: [{"symbol": "0001.HK"}],
    )

    with pytest.raises(FetchError, match="yfinance returned only 1 HK rows"):
        fetch_hk_stock()
