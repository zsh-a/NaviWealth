from tool.asset_catalog.sources.cn_a import (
    parse_baostock_basic,
    parse_mootdx_row,
)


class TestParseBaostockBasic:
    def test_stock(self):
        row = parse_baostock_basic("sh.600519", "贵州茅台", "1", status="1")
        assert row == {
            "symbol": "600519",
            "market": "cn_a",
            "type": "stock",
            "currency": "CNY",
            "name_en": "",
            "name_cn": "贵州茅台",
            "aliases": "",
        }

    def test_etf(self):
        row = parse_baostock_basic("sh.510300", "300ETF", "5", status="1")
        assert row is not None
        assert row["type"] == "etf"
        assert row["symbol"] == "510300"

    def test_convertible_bond(self):
        row = parse_baostock_basic("sh.113001", "中行转债", "4", status="1")
        assert row is not None
        assert row["type"] == "bond"

    def test_index_dropped(self):
        # type=2 is index — not in the catalog.
        assert parse_baostock_basic("sh.000001", "上证综指", "2", status="1") is None

    def test_other_dropped(self):
        assert parse_baostock_basic("sh.999999", "Mystery", "3", status="1") is None

    def test_delisted_dropped(self):
        assert parse_baostock_basic("sh.600001", "已退市", "1", status="0") is None

    def test_empty_inputs(self):
        assert parse_baostock_basic("", "x", "1") is None
        assert parse_baostock_basic("sh.600519", "", "1") is None

    def test_int_type_code(self):
        # BaoStock sometimes returns integers, sometimes strings.
        row = parse_baostock_basic("sz.000001", "平安银行", 1, status=1)
        assert row is not None
        assert row["type"] == "stock"

    def test_status_blank_assumed_live(self):
        row = parse_baostock_basic("sh.600519", "茅台", "1", status="")
        assert row is not None


class TestParseMootdxRow:
    def test_shanghai_stock(self):
        row = parse_mootdx_row(1, {"code": "600519", "name": "贵州茅台"})
        assert row is not None
        assert row["symbol"] == "600519"
        assert row["type"] == "stock"
        assert row["market"] == "cn_a"
        assert row["currency"] == "CNY"

    def test_shenzhen_stock(self):
        row = parse_mootdx_row(0, {"code": "000001", "name": "平安银行"})
        assert row is not None
        assert row["type"] == "stock"

    def test_beijing_stock(self):
        row = parse_mootdx_row(2, {"code": "830799", "name": "贝特瑞"})
        assert row is not None
        assert row["type"] == "stock"

    def test_drops_index(self):
        # 39xxxx on Shenzhen are indices — not catalog rows.
        assert parse_mootdx_row(0, {"code": "399001", "name": "深证成指"}) is None

    def test_etf(self):
        row = parse_mootdx_row(1, {"code": "510300", "name": "300ETF"})
        assert row is not None
        assert row["type"] == "etf"

    def test_convertible_bond(self):
        row = parse_mootdx_row(0, {"code": "128136", "name": "金博转债"})
        assert row is not None
        assert row["type"] == "bond"

    def test_unknown_market(self):
        assert parse_mootdx_row(7, {"code": "600519", "name": "x"}) is None

    def test_capitalised_keys(self):
        # mootdx version drift — some payloads use capitalised keys.
        row = parse_mootdx_row(1, {"Code": "600519", "Name": "贵州茅台"})
        assert row is not None
        assert row["symbol"] == "600519"

    def test_empty_inputs(self):
        assert parse_mootdx_row(1, {}) is None
        assert parse_mootdx_row(1, {"code": "", "name": "x"}) is None
        assert parse_mootdx_row(1, {"code": "600519", "name": ""}) is None
