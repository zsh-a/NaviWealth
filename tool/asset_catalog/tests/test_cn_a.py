import inspect

import pytest

from tool.asset_catalog.sources.cn_a import (
    FetchError,
    fetch_mootdx_market,
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


class _FakeMootdxTransport:
    def __init__(self, pages):
        self.pages = pages
        self.calls = []

    def get_security_list(self, *, market, start):
        self.calls.append((market, start))
        page = self.pages.get(start)
        if isinstance(page, Exception):
            raise page
        return page


class _FakeMootdxClient:
    def __init__(self, *, count, pages):
        self.count = count
        self.client = _FakeMootdxTransport(pages)
        self.closed = False

    def stock_count(self, *, market):
        return self.count

    def close(self):
        self.closed = True


class TestFetchMootdxMarket:
    @pytest.mark.parametrize(
        ("market", "symbol"),
        [
            (0, "000001"),
            (1, "600519"),
            (2, "830799"),
        ],
    )
    def test_uses_low_level_pagination_for_every_market(self, market, symbol):
        fake = _FakeMootdxClient(
            count=2001,
            pages={
                0: [{"code": symbol, "name": "测试证券"}],
                1000: [{"code": "399001", "name": "过滤指数"}],
                2000: [],
            },
        )

        rows = fetch_mootdx_market(market, _client_factory=lambda: fake)

        assert [row["symbol"] for row in rows] == [symbol]
        assert fake.client.calls == [(market, 0), (market, 1000), (market, 2000)]
        assert fake.closed is True

    def test_wraps_transport_failure_and_closes_client(self):
        fake = _FakeMootdxClient(
            count=1,
            pages={0: RuntimeError("connection reset")},
        )

        with pytest.raises(FetchError, match="get_security_list.*connection reset"):
            fetch_mootdx_market(0, _client_factory=lambda: fake)

        assert fake.closed is True

    def test_pinned_tdxpy_exposes_paginated_transport_contract(self):
        hq = pytest.importorskip("tdxpy.hq")
        parameters = inspect.signature(hq.TdxHq_API.get_security_list).parameters

        assert {"market", "start"}.issubset(parameters)
