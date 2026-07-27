import datetime as dt
import json
import pathlib
import zipfile

import pytest

from tool.asset_catalog.build import fnv1a64
from tool.asset_catalog.validate_release import (
    CATALOG_ASSET_PATH,
    CatalogValidationError,
    ReleasePolicy,
    validate_archives,
    validate_catalog,
    validate_pubspec,
    validate_web_root,
)


def _entries() -> list[dict[str, str]]:
    return [
        {"s": "BTC-USD", "m": "crypto", "t": "crypto", "c": "USD"},
        {"s": "0700.HK", "m": "hk_stock", "t": "stock", "c": "HKD"},
        {"s": "AAPL", "m": "us_stock", "t": "stock", "c": "USD"},
    ]


def _write_catalog(
    path: pathlib.Path,
    *,
    entries: list[dict[str, str]] | None = None,
    version: str = "v1.20260720",
    count: int | None = None,
    checksum: str | None = None,
) -> bytes:
    rows = entries or _entries()
    header = {
        "version": version,
        "checksum": checksum or f"{fnv1a64(rows):016x}",
        "count": len(rows) if count is None else count,
    }
    lines = [json.dumps(header, separators=(",", ":"))]
    lines.extend(json.dumps(row, separators=(",", ":")) for row in rows)
    raw = ("\n".join(lines) + "\n").encode()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(raw)
    return raw


def _fixture_policy() -> ReleasePolicy:
    return ReleasePolicy(
        max_age_days=45,
        min_market_counts=(
            ("crypto", 1),
            ("hk_stock", 1),
            ("us_stock", 1),
        ),
    )


def test_valid_catalog_reports_market_counts(tmp_path):
    path = tmp_path / "catalog.ndjson"
    raw = _write_catalog(path)

    report = validate_catalog(
        path,
        policy=_fixture_policy(),
        today=dt.date(2026, 7, 27),
    )

    assert report.row_count == 3
    assert report.market_counts == {
        "crypto": 1,
        "hk_stock": 1,
        "us_stock": 1,
    }
    assert report.raw_bytes == raw


@pytest.mark.parametrize(
    ("overrides", "message"),
    [
        ({"count": 99}, "header.count=99"),
        ({"checksum": "0000000000000000"}, "does not match calculated"),
        ({"version": "v1.20260101"}, "207 days old"),
    ],
)
def test_rejects_invalid_header_or_stale_catalog(tmp_path, overrides, message):
    path = tmp_path / "catalog.ndjson"
    _write_catalog(path, **overrides)

    with pytest.raises(CatalogValidationError, match=message):
        validate_catalog(
            path,
            policy=_fixture_policy(),
            today=dt.date(2026, 7, 27),
        )


def test_rejects_duplicate_unsorted_and_too_small_markets(tmp_path):
    path = tmp_path / "catalog.ndjson"
    rows = [
        {"s": "MSFT", "m": "us_stock", "t": "stock", "c": "USD"},
        {"s": "AAPL", "m": "us_stock", "t": "stock", "c": "USD"},
        {"s": "aapl", "m": "us_stock", "t": "stock", "c": "USD"},
    ]
    _write_catalog(path, entries=rows)
    policy = ReleasePolicy(
        max_age_days=45,
        min_market_counts=(("us_stock", 4),),
    )

    with pytest.raises(CatalogValidationError) as error:
        validate_catalog(path, policy=policy, today=dt.date(2026, 7, 27))

    message = str(error.value)
    assert "duplicate market/symbol" in message
    assert "not in canonical market/symbol order" in message
    assert "release minimum is 4" in message


def test_validates_pubspec_declaration(tmp_path):
    pubspec = tmp_path / "pubspec.yaml"
    pubspec.write_text(
        f"flutter:\n  assets:\n    - {CATALOG_ASSET_PATH}\n",
        encoding="utf-8",
    )
    validate_pubspec(pubspec)

    pubspec.write_text("flutter:\n  assets: []\n", encoding="utf-8")
    with pytest.raises(CatalogValidationError, match="missing Flutter asset"):
        validate_pubspec(pubspec)


@pytest.mark.parametrize(
    "entry",
    [
        f"assets/flutter_assets/{CATALOG_ASSET_PATH}",
        f"base/assets/flutter_assets/{CATALOG_ASSET_PATH}",
    ],
)
def test_validates_apk_and_aab_catalog_bytes(tmp_path, entry):
    catalog = tmp_path / "catalog.ndjson"
    raw = _write_catalog(catalog)
    report = validate_catalog(
        catalog,
        policy=_fixture_policy(),
        today=dt.date(2026, 7, 27),
    )
    archive = tmp_path / ("app.aab" if entry.startswith("base/") else "app.apk")
    with zipfile.ZipFile(archive, "w") as bundle:
        bundle.writestr(entry, raw)

    validate_archives([archive], expected=report)


def test_rejects_changed_archive_catalog(tmp_path):
    catalog = tmp_path / "catalog.ndjson"
    _write_catalog(catalog)
    report = validate_catalog(
        catalog,
        policy=_fixture_policy(),
        today=dt.date(2026, 7, 27),
    )
    archive = tmp_path / "app.apk"
    with zipfile.ZipFile(archive, "w") as bundle:
        bundle.writestr(
            f"assets/flutter_assets/{CATALOG_ASSET_PATH}",
            b"different",
        )

    with pytest.raises(CatalogValidationError, match="differs from committed"):
        validate_archives([archive], expected=report)


def test_validates_web_catalog_bytes(tmp_path):
    catalog = tmp_path / "catalog.ndjson"
    raw = _write_catalog(catalog)
    report = validate_catalog(
        catalog,
        policy=_fixture_policy(),
        today=dt.date(2026, 7, 27),
    )
    web_root = tmp_path / "web"
    web_catalog = web_root / "assets" / CATALOG_ASSET_PATH
    web_catalog.parent.mkdir(parents=True)
    web_catalog.write_bytes(raw)

    validate_web_root(web_root, expected=report)
