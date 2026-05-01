import json
import pathlib

from tool.asset_catalog.diff_report import diff, format_report, load_entries


def _write_ndjson(path: pathlib.Path, entries: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = [json.dumps({"version": "v1.test", "checksum": "0", "count": len(entries)})]
    for entry in entries:
        lines.append(json.dumps(entry, ensure_ascii=False))
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


class TestDiffReport:
    def test_added_removed_renamed(self):
        prev = {("us_stock", "aapl"): {"s": "AAPL", "m": "us_stock", "ne": "Apple Inc.", "t": "stock"}}
        curr = {
            ("us_stock", "aapl"): {"s": "AAPL", "m": "us_stock", "ne": "Apple, Inc.", "t": "stock"},
            ("us_stock", "msft"): {"s": "MSFT", "m": "us_stock", "ne": "Microsoft Corp", "t": "stock"},
        }
        stats = diff(prev, curr)
        assert stats["added"] == 1
        assert stats["removed"] == 0
        assert stats["renamed"] == 1
        assert stats["previous"] == 1
        assert stats["current"] == 2

    def test_no_change(self):
        e = {"s": "AAPL", "m": "us_stock", "ne": "Apple Inc.", "t": "stock"}
        stats = diff({("us_stock", "aapl"): e}, {("us_stock", "aapl"): e})
        assert stats["added"] == 0
        assert stats["removed"] == 0
        assert stats["renamed"] == 0

    def test_format_report_smoke(self):
        report = format_report({
            "previous": 100,
            "current": 110,
            "added": 12,
            "removed": 2,
            "renamed": 5,
        })
        assert "added:" in report
        assert "removed:" in report
        assert "renamed:" in report

    def test_load_entries_roundtrip(self, tmp_path):
        entries = [
            {"s": "AAPL", "m": "us_stock", "t": "stock"},
            {"s": "600519", "m": "cn_a", "t": "stock"},
        ]
        path = tmp_path / "catalog.ndjson"
        _write_ndjson(path, entries)
        loaded = load_entries(path)
        assert set(loaded.keys()) == {("us_stock", "aapl"), ("cn_a", "600519")}

    def test_load_missing_file_returns_empty(self, tmp_path):
        assert load_entries(tmp_path / "missing.ndjson") == {}
