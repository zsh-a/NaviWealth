from tool.asset_catalog.sources.hk_stock import (
    CATEGORY_TYPE_MAP,
    DROPPED_CATEGORIES,
    parse_hkex_row,
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
