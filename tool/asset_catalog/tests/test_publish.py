import gzip
import hashlib
import json
import pathlib

import pytest

from tool.asset_catalog.build import fnv1a64
from tool.asset_catalog.publish import MANIFEST_NAME, package_catalog
from tool.asset_catalog.validate_release import CatalogValidationError, ReleasePolicy

ROWS = [
    {"s": "BTC-USD", "m": "crypto", "t": "crypto", "c": "USD"},
    {"s": "AAPL", "m": "us_stock", "t": "stock", "c": "USD"},
]
POLICY = ReleasePolicy(min_market_counts=(("crypto", 1),))


def _write(path: pathlib.Path, *, checksum: str | None = None) -> bytes:
    header = {
        "version": "v1.20260720",
        "checksum": checksum or f"{fnv1a64(ROWS):016x}",
        "count": len(ROWS),
    }
    lines = [json.dumps(header, separators=(",", ":"))]
    lines += [json.dumps(row, separators=(",", ":")) for row in ROWS]
    raw = ("\n".join(lines) + "\n").encode()
    path.write_bytes(raw)
    return raw


def test_packages_verifiable_manifest_and_asset(tmp_path: pathlib.Path) -> None:
    raw = _write(tmp_path / "catalog.ndjson")
    out = tmp_path / "out"

    manifest = package_catalog(tmp_path / "catalog.ndjson", out, policy=POLICY)

    on_disk = json.loads((out / MANIFEST_NAME).read_text())
    assert on_disk == manifest
    assert manifest["schema"] == 1
    assert manifest["version"] == "v1.20260720"
    assert manifest["count"] == 2
    assert manifest["asset"] == (
        f"securities-v1.20260720-{manifest['checksum'][:8]}.ndjson.gz"
    )
    compressed = (out / str(manifest["asset"])).read_bytes()
    assert len(compressed) == manifest["gzip_size"]
    assert hashlib.sha256(compressed).hexdigest() == manifest["gzip_sha256"]
    assert gzip.decompress(compressed) == raw
    assert hashlib.sha256(raw).hexdigest() == manifest["sha256"]


def test_gzip_output_is_deterministic(tmp_path: pathlib.Path) -> None:
    _write(tmp_path / "catalog.ndjson")
    first = package_catalog(tmp_path / "catalog.ndjson", tmp_path / "a", policy=POLICY)
    second = package_catalog(tmp_path / "catalog.ndjson", tmp_path / "b", policy=POLICY)
    assert first["gzip_sha256"] == second["gzip_sha256"]


def test_refuses_invalid_catalog(tmp_path: pathlib.Path) -> None:
    _write(tmp_path / "catalog.ndjson", checksum="0" * 16)
    with pytest.raises(CatalogValidationError):
        package_catalog(tmp_path / "catalog.ndjson", tmp_path / "out", policy=POLICY)
    assert not (tmp_path / "out").exists()
