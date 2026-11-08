"""Package the committed securities catalog for out-of-band distribution.

Installed apps poll ``catalog-manifest.json`` on the rolling
``securities-catalog`` GitHub Release and download the gzip asset it names,
so listing refreshes ship without a new APK. This script validates the
committed NDJSON with the release gate, then writes into ``--output``:

* ``securities-<version>-<checksum8>.ndjson.gz`` — deterministic gzip
  (mtime 0). The name is content-addressed so a client holding an older
  manifest never downloads mismatched bytes while assets are being swapped.
* ``catalog-manifest.json`` — the metadata ``SecuritiesCatalogManifest``
  parses on device. Keep ``MANIFEST_SCHEMA`` in sync with
  ``kSecuritiesCatalogManifestSchema`` in the app.
"""

from __future__ import annotations

import argparse
import gzip
import hashlib
import io
import json
import pathlib
import sys

from tool.asset_catalog.validate_release import (
    DEFAULT_CATALOG_PATH,
    DEFAULT_RELEASE_POLICY,
    CatalogValidationError,
    ReleasePolicy,
    validate_catalog,
)

MANIFEST_SCHEMA = 1
MANIFEST_NAME = "catalog-manifest.json"


def deterministic_gzip(data: bytes) -> bytes:
    buffer = io.BytesIO()
    with gzip.GzipFile(
        filename="", mode="wb", fileobj=buffer, compresslevel=9, mtime=0
    ) as fh:
        fh.write(data)
    return buffer.getvalue()


def package_catalog(
    catalog: pathlib.Path,
    output: pathlib.Path,
    *,
    policy: ReleasePolicy = DEFAULT_RELEASE_POLICY,
) -> dict[str, object]:
    report = validate_catalog(catalog, policy=policy)
    compressed = deterministic_gzip(report.raw_bytes)
    asset = f"securities-{report.version}-{report.checksum[:8]}.ndjson.gz"
    manifest: dict[str, object] = {
        "schema": MANIFEST_SCHEMA,
        "version": report.version,
        "checksum": report.checksum,
        "count": report.row_count,
        "sha256": hashlib.sha256(report.raw_bytes).hexdigest(),
        "asset": asset,
        "gzip_sha256": hashlib.sha256(compressed).hexdigest(),
        "gzip_size": len(compressed),
        "markets": dict(report.market_counts),
    }
    output.mkdir(parents=True, exist_ok=True)
    (output / asset).write_bytes(compressed)
    (output / MANIFEST_NAME).write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    return manifest


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--catalog", type=pathlib.Path, default=DEFAULT_CATALOG_PATH)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    args = parser.parse_args(argv)
    try:
        manifest = package_catalog(args.catalog, args.output)
    except CatalogValidationError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    print(
        f"OK: packaged catalog {manifest['version']} rows={manifest['count']} "
        f"asset={manifest['asset']} ({manifest['gzip_size']} bytes)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
