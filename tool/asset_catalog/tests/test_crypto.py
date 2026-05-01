from tool.asset_catalog.sources.crypto import (
    parse_market_entry,
    parse_market_pages,
)


class TestParseMarketEntry:
    def test_btc(self):
        row = parse_market_entry({
            "id": "bitcoin",
            "symbol": "btc",
            "name": "Bitcoin",
            "current_price": 60000.0,
        })
        assert row is not None
        assert row["symbol"] == "BTC-USD"
        assert row["market"] == "crypto"
        assert row["type"] == "crypto"
        assert row["currency"] == "USD"
        assert row["name_en"] == "Bitcoin"
        assert row["name_cn"] == "比特币"
        assert row["aliases"] == "bitcoin"

    def test_no_zh_override_falls_back(self):
        row = parse_market_entry({
            "id": "obscure-coin",
            "symbol": "obs",
            "name": "Obscure Coin",
        })
        assert row is not None
        assert row["symbol"] == "OBS-USD"
        # No zh override available.
        assert row["name_cn"] == ""
        assert row["aliases"] == "obscure-coin"

    def test_empty_inputs(self):
        assert parse_market_entry({}) is None
        assert parse_market_entry({"symbol": "", "name": "x"}) is None
        assert parse_market_entry({"symbol": "btc", "name": ""}) is None


class TestParseMarketPages:
    def test_dedupes_across_pages(self):
        page1 = [{"id": "bitcoin", "symbol": "btc", "name": "Bitcoin"}]
        page2 = [
            {"id": "bitcoin", "symbol": "btc", "name": "Bitcoin"},  # duplicate
            {"id": "ethereum", "symbol": "eth", "name": "Ethereum"},
        ]
        rows = parse_market_pages([page1, page2])
        symbols = [r["symbol"] for r in rows]
        assert symbols == ["BTC-USD", "ETH-USD"]

    def test_handles_skipped_rows(self):
        rows = parse_market_pages([
            [
                {"id": "x", "symbol": "btc", "name": "Bitcoin"},
                {"symbol": "", "name": "broken"},  # dropped
                {"id": "y", "symbol": "eth", "name": "Ethereum"},
            ],
        ])
        assert [r["symbol"] for r in rows] == ["BTC-USD", "ETH-USD"]
