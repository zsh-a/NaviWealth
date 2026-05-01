from tool.asset_catalog.sources.us_stock import (
    merge_with_sec,
    parse_nasdaq_trader,
    parse_nasdaqlisted_line,
    parse_otherlisted_line,
)


NASDAQ_FIXTURE = """\
Symbol|Security Name|Market Category|Test Issue|Financial Status|Round Lot Size|ETF|NextShares
AAPL|Apple Inc. - Common Stock|Q|N|N|100|N|N
QQQ|Invesco QQQ Trust|Q|N|N|100|Y|N
ZTEST|Nasdaq Test Stock|Q|Y|N|100|N|N
ZWRT|Foobar Corp - Warrant|Q|N|N|100|N|N
File Creation Time: 2026050100:00|||||||
"""

OTHERLISTED_FIXTURE = """\
ACT Symbol|Security Name|Exchange|CQS Symbol|ETF|Round Lot Size|Test Issue|NASDAQ Symbol
SPY|SPDR S&P 500 ETF Trust|P|SPY|Y|100|N|SPY
JPM|JPMorgan Chase & Co. Common Stock|N|JPM|N|100|N|JPM
ZTST|TEST ISSUE|N|ZTST|N|100|Y|ZTST
File Creation Time: 2026050100:00|||||||
"""


class TestParseNasdaqlisted:
    def test_stock(self):
        row = parse_nasdaqlisted_line({
            "Symbol": "AAPL",
            "Security Name": "Apple Inc. - Common Stock",
            "Test Issue": "N",
            "ETF": "N",
        })
        assert row is not None
        assert row["symbol"] == "AAPL"
        assert row["type"] == "stock"
        assert row["currency"] == "USD"
        assert row["market"] == "us_stock"

    def test_etf(self):
        row = parse_nasdaqlisted_line({
            "Symbol": "QQQ",
            "Security Name": "Invesco QQQ Trust",
            "Test Issue": "N",
            "ETF": "Y",
        })
        assert row is not None
        assert row["type"] == "etf"

    def test_test_issue_dropped(self):
        row = parse_nasdaqlisted_line({
            "Symbol": "ZTEST",
            "Security Name": "Nasdaq Test Stock",
            "Test Issue": "Y",
            "ETF": "N",
        })
        assert row is None

    def test_warrant_dropped(self):
        row = parse_nasdaqlisted_line({
            "Symbol": "ZWRT",
            "Security Name": "Foobar Corp - Warrant",
            "Test Issue": "N",
            "ETF": "N",
        })
        assert row is None


class TestParseOtherlisted:
    def test_etf(self):
        row = parse_otherlisted_line({
            "ACT Symbol": "SPY",
            "Security Name": "SPDR S&P 500 ETF Trust",
            "ETF": "Y",
            "Test Issue": "N",
        })
        assert row is not None
        assert row["symbol"] == "SPY"
        assert row["type"] == "etf"

    def test_stock(self):
        row = parse_otherlisted_line({
            "ACT Symbol": "JPM",
            "Security Name": "JPMorgan Chase & Co. Common Stock",
            "ETF": "N",
            "Test Issue": "N",
        })
        assert row is not None
        assert row["type"] == "stock"


class TestParseNasdaqTrader:
    def test_full_nasdaq_file(self):
        rows = parse_nasdaq_trader(NASDAQ_FIXTURE, kind="nasdaq")
        symbols = {r["symbol"] for r in rows}
        assert "AAPL" in symbols
        assert "QQQ" in symbols
        assert "ZTEST" not in symbols
        assert "ZWRT" not in symbols
        assert len(rows) == 2

    def test_full_other_file(self):
        rows = parse_nasdaq_trader(OTHERLISTED_FIXTURE, kind="other")
        symbols = {r["symbol"] for r in rows}
        assert symbols == {"SPY", "JPM"}


class TestMergeWithSec:
    def test_overrides_legalese_name(self):
        rows = [
            {
                "symbol": "AAPL",
                "market": "us_stock",
                "type": "stock",
                "currency": "USD",
                "name_en": "Apple Inc. - Common Stock",
                "name_cn": "",
                "aliases": "",
            }
        ]
        sec = {
            "fields": ["cik", "name", "ticker", "exchange"],
            "data": [[320193, "Apple Inc.", "AAPL", "Nasdaq"]],
        }
        merged = merge_with_sec(rows, sec)
        assert merged[0]["name_en"] == "Apple Inc."

    def test_keeps_clean_name(self):
        rows = [
            {
                "symbol": "AAPL",
                "market": "us_stock",
                "type": "stock",
                "currency": "USD",
                "name_en": "Apple Inc.",
                "name_cn": "",
                "aliases": "",
            }
        ]
        sec = {
            "fields": ["cik", "name", "ticker", "exchange"],
            "data": [[320193, "Apple Computer, Inc.", "AAPL", "Nasdaq"]],
        }
        merged = merge_with_sec(rows, sec)
        # Already clean, so SEC payload doesn't override.
        assert merged[0]["name_en"] == "Apple Inc."

    def test_no_match_passes_through(self):
        rows = [
            {
                "symbol": "ZZZZ",
                "market": "us_stock",
                "type": "stock",
                "currency": "USD",
                "name_en": "Zzz Co",
                "name_cn": "",
                "aliases": "",
            }
        ]
        sec = {
            "fields": ["cik", "name", "ticker", "exchange"],
            "data": [[1, "Other", "AAPL", "Nasdaq"]],
        }
        merged = merge_with_sec(rows, sec)
        assert merged == rows

    def test_handles_missing_fields(self):
        rows = [{"symbol": "AAPL", "market": "us_stock", "type": "stock", "currency": "USD", "name_en": "x", "name_cn": "", "aliases": ""}]
        merged = merge_with_sec(rows, {"fields": [], "data": []})
        assert merged == rows
