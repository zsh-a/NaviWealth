"""Validate the committed securities catalog.

The catalog committed to Git is bundled into the NSH client and published
out-of-band on the rolling ``securities-catalog`` release. This validator is
the gate that makes that policy safe:

* verify NDJSON structure, row count, uniqueness, ordering, and FNV checksum;
* reject future-dated or suspiciously small per-market catalogs.

The default policy reflects the expected output of
``tool/build-asset-catalog.sh --full``. Tests can pass a smaller policy to
exercise the validator with compact fixtures.
"""

from __future__ import annotations

import argparse
import collections
import dataclasses
import datetime as dt
import json
import pathlib
import re
import sys
from collections.abc import Mapping

from tool.asset_catalog.build import KNOWN_MARKETS, KNOWN_TYPES, fnv1a64

DEFAULT_CATALOG_PATH = pathlib.Path("assets/catalog/securities.v1.ndjson")
VERSION_RE = re.compile(r"^v1\.(\d{4})(\d{2})(\d{2})$")

# Deliberately conservative floors. They catch stub/degraded feeds while
# leaving ample headroom for normal listing-count fluctuations.
DEFAULT_MIN_MARKET_COUNTS: tuple[tuple[str, int], ...] = (
    ("cn_a", 4_000),
    ("hk_stock", 1_500),
    ("us_stock", 5_000),
    ("crypto", 400),
)


class CatalogValidationError(RuntimeError):
    """One or more release catalog invariants failed."""


@dataclasses.dataclass(frozen=True)
class ReleasePolicy:
    min_market_counts: tuple[tuple[str, int], ...] = DEFAULT_MIN_MARKET_COUNTS


DEFAULT_RELEASE_POLICY = ReleasePolicy()


@dataclasses.dataclass(frozen=True)
class CatalogReport:
    version: str
    checksum: str
    row_count: int
    market_counts: Mapping[str, int]
    raw_bytes: bytes


def validate_catalog(
    path: pathlib.Path,
    *,
    policy: ReleasePolicy = DEFAULT_RELEASE_POLICY,
    today: dt.date | None = None,
) -> CatalogReport:
    """Validate a catalog file and return its release metadata."""
    errors: list[str] = []
    try:
        raw = path.read_bytes()
    except OSError as exc:
        raise CatalogValidationError(f"cannot read catalog {path}: {exc}") from exc

    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise CatalogValidationError(f"{path}: catalog is not UTF-8: {exc}") from exc

    objects: list[dict[str, object]] = []
    for line_number, line in enumerate(text.splitlines(), start=1):
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        try:
            decoded = json.loads(stripped)
        except json.JSONDecodeError as exc:
            errors.append(f"line {line_number}: invalid JSON: {exc.msg}")
            continue
        if not isinstance(decoded, dict):
            errors.append(f"line {line_number}: expected a JSON object")
            continue
        objects.append(decoded)

    if not objects:
        raise CatalogValidationError(f"{path}: catalog has no header or entries")

    header, *entries = objects
    version = header.get("version")
    checksum = header.get("checksum")
    declared_count = header.get("count")
    if not isinstance(version, str):
        errors.append("header.version must be a string")
        version = ""
    if not isinstance(checksum, str) or not re.fullmatch(r"[0-9a-f]{16}", checksum):
        errors.append("header.checksum must be 16 lowercase hexadecimal characters")
        checksum = ""
    if not isinstance(declared_count, int) or isinstance(declared_count, bool):
        errors.append("header.count must be an integer")
    elif declared_count != len(entries):
        errors.append(
            f"header.count={declared_count} does not match {len(entries)} entries"
        )

    seen: set[tuple[str, str]] = set()
    row_keys: list[tuple[str, str]] = []
    market_counts: collections.Counter[str] = collections.Counter()
    for index, entry in enumerate(entries, start=2):
        required: dict[str, str] = {}
        for field in ("s", "m", "t", "c"):
            value = entry.get(field)
            if not isinstance(value, str) or not value.strip():
                errors.append(f"line {index}: required field {field!r} is missing")
            else:
                required[field] = value.strip()
        if len(required) != 4:
            continue

        symbol = required["s"]
        market = required["m"]
        type_name = required["t"]
        if market not in KNOWN_MARKETS:
            errors.append(f"line {index}: unknown market {market!r} for {symbol}")
        if type_name not in KNOWN_TYPES:
            errors.append(f"line {index}: unknown type {type_name!r} for {symbol}")

        key = (market, symbol.casefold())
        if key in seen:
            errors.append(f"line {index}: duplicate market/symbol {market}:{symbol}")
        else:
            seen.add(key)
        row_keys.append((market, symbol))
        market_counts[market] += 1

    if row_keys != sorted(row_keys):
        errors.append("entries are not in canonical market/symbol order")

    if checksum:
        calculated = f"{fnv1a64(entries):016x}"
        if checksum != calculated:
            errors.append(
                f"header.checksum={checksum} does not match calculated {calculated}"
            )

    catalog_date = _catalog_date(version, errors)
    effective_today = today or dt.datetime.now(dt.timezone.utc).date()
    if catalog_date is not None:
        age = (effective_today - catalog_date).days
        if age < -1:
            errors.append(
                f"catalog version date {catalog_date.isoformat()} is in the future"
            )

    for market, minimum in policy.min_market_counts:
        actual = market_counts[market]
        if actual < minimum:
            errors.append(
                f"market {market!r} has {actual} entries; release minimum is {minimum}"
            )

    if errors:
        formatted = "\n".join(f"  - {message}" for message in errors)
        raise CatalogValidationError(f"{path}: validation failed:\n{formatted}")

    return CatalogReport(
        version=version,
        checksum=checksum,
        row_count=len(entries),
        market_counts=dict(sorted(market_counts.items())),
        raw_bytes=raw,
    )


def _catalog_date(version: str, errors: list[str]) -> dt.date | None:
    match = VERSION_RE.fullmatch(version)
    if match is None:
        errors.append("header.version must match v1.YYYYMMDD")
        return None
    try:
        return dt.date(*(int(part) for part in match.groups()))
    except ValueError:
        errors.append(f"header.version contains an invalid date: {version!r}")
        return None


def _parse_minimums(values: list[str] | None) -> tuple[tuple[str, int], ...]:
    if values is None:
        return DEFAULT_MIN_MARKET_COUNTS
    parsed: list[tuple[str, int]] = []
    for value in values:
        market, separator, raw_minimum = value.partition("=")
        if not separator or not market:
            raise argparse.ArgumentTypeError(
                f"invalid --min-market {value!r}; expected MARKET=COUNT"
            )
        try:
            minimum = int(raw_minimum)
        except ValueError as exc:
            raise argparse.ArgumentTypeError(
                f"invalid --min-market count in {value!r}: must be non-negative"
            ) from exc
        if minimum < 0:
            raise argparse.ArgumentTypeError(
                f"invalid --min-market count in {value!r}: must be non-negative"
            )
        parsed.append((market, minimum))
    return tuple(parsed)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--catalog", type=pathlib.Path, default=DEFAULT_CATALOG_PATH)
    parser.add_argument(
        "--min-market",
        action="append",
        metavar="MARKET=COUNT",
        help="override all default per-market release floors",
    )
    args = parser.parse_args(argv)

    try:
        minimums = _parse_minimums(args.min_market)
        policy = ReleasePolicy(min_market_counts=minimums)
        report = validate_catalog(args.catalog, policy=policy)
    except (CatalogValidationError, argparse.ArgumentTypeError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    markets = ", ".join(
        f"{market}={count}" for market, count in report.market_counts.items()
    )
    print(
        f"OK: securities catalog {report.version} "
        f"rows={report.row_count} checksum={report.checksum} ({markets})"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
