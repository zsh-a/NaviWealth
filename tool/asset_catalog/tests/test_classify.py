from tool.asset_catalog.classify import (
    classify_a_share,
    detect_market_from_code,
)


class TestClassifyAShare:
    def test_shanghai_main_board_stock(self):
        assert classify_a_share("sh", "600519") == "stock"
        assert classify_a_share("sh", "601398") == "stock"

    def test_shanghai_star_board_stock(self):
        assert classify_a_share("sh", "688981") == "stock"

    def test_shanghai_etf(self):
        assert classify_a_share("sh", "510300") == "etf"
        assert classify_a_share("sh", "588000") == "etf"

    def test_shanghai_convertible_bond(self):
        assert classify_a_share("sh", "110001") == "bond"
        assert classify_a_share("sh", "113537") == "bond"

    def test_shanghai_index_dropped(self):
        assert classify_a_share("sh", "000001") is None  # SSE Composite
        assert classify_a_share("sh", "880001") is None

    def test_shenzhen_main_board_stock(self):
        assert classify_a_share("sz", "000001") == "stock"  # Ping An Bank
        assert classify_a_share("sz", "000858") == "stock"

    def test_shenzhen_chinext_stock(self):
        assert classify_a_share("sz", "300750") == "stock"

    def test_shenzhen_etf(self):
        assert classify_a_share("sz", "159919") == "etf"
        assert classify_a_share("sz", "160001") == "etf"

    def test_shenzhen_convertible_bond(self):
        assert classify_a_share("sz", "128136") == "bond"

    def test_shenzhen_index_dropped(self):
        assert classify_a_share("sz", "399001") is None

    def test_beijing_stock(self):
        assert classify_a_share("bj", "830799") == "stock"
        assert classify_a_share("bj", "873223") == "stock"
        assert classify_a_share("bj", "920001") == "stock"

    def test_beijing_unknown_dropped(self):
        assert classify_a_share("bj", "600519") is None

    def test_invalid_inputs(self):
        assert classify_a_share("xx", "600519") is None
        assert classify_a_share("sh", "60051") is None  # too short
        assert classify_a_share("sh", "abc123") is None
        assert classify_a_share("sh", "") is None


class TestDetectMarketFromCode:
    def test_shanghai_codes(self):
        assert detect_market_from_code("600519") == "sh"
        assert detect_market_from_code("688981") == "sh"
        assert detect_market_from_code("510300") == "sh"
        assert detect_market_from_code("110001") == "sh"

    def test_shenzhen_codes(self):
        assert detect_market_from_code("000858") == "sz"
        assert detect_market_from_code("300750") == "sz"
        assert detect_market_from_code("159919") == "sz"
        assert detect_market_from_code("128136") == "sz"

    def test_beijing_codes(self):
        assert detect_market_from_code("830799") == "bj"
        assert detect_market_from_code("873223") == "bj"
        assert detect_market_from_code("920001") == "bj"

    def test_unknown(self):
        assert detect_market_from_code("999999") is None
        assert detect_market_from_code("") is None
        assert detect_market_from_code("AAPL") is None
