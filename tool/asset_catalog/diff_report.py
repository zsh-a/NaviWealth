"""Catalog diff report.

Compares the previously-built ``securities.v1.ndjson`` (if any) against
the freshly-rebuilt one and emits a human-readable diff:

    added:    23  (+0.11%)
    removed:   8  (-0.04%)
    renamed: 102  (0.51%)

When the percentage of *added* or *removed* rows exceeds ``--threshold``
(default 5%), the script exits non-zero so a CI run can stop and require
human confirmation. Renames (same ``(market, symbol)``, different name)
are reported but never trip the threshold — they're expected churn.

Usage:

    python3 -m tool.asset_catalog.diff_report \\
        --previous apps/mobile/assets/catalog/securities.v1.ndjson \\
        --current  /tmp/securities.v1.new.ndjson \\
        --threshold 0.05
"""
from __future__ import annotations

import argparse
import json
import pathlib
import sys


def load_entries(path: pathlib.Path) -> dict[tuple[str, str], dict]:
    """Read an NDJSON catalog and index by ``(market, symbol)``.

    The first line is the header; data rows follow. Missing files return
    an empty index so a first-time build doesn't crash.
    """
    if not path.exists():
        return {}
    out: dict[tuple[str, str], dict] = {}
    with path.open("r", encoding="utf-8") as fh:
        next(fh, None)  # header
        for line in fh:
            line = line.strip()
            if not line:
                continue
            entry = json.loads(line)
            key = (entry.get("m", ""), entry.get("s", "").lower())
            out[key] = entry
    return out


def diff(
    previous: dict[tuple[str, str], dict],
    current: dict[tuple[str, str], dict],
) -> dict[str, int]:
    prev_keys = set(previous)
    curr_keys = set(current)
    added = curr_keys - prev_keys
    removed = prev_keys - curr_keys
    common = prev_keys & curr_keys

    renamed = 0
    for key in common:
        if previous[key].get("nc") != current[key].get("nc"):
            renamed += 1
            continue
        if previous[key].get("ne") != current[key].get("ne"):
            renamed += 1
            continue
        if previous[key].get("t") != current[key].get("t"):
            renamed += 1

    return {
        "previous": len(prev_keys),
        "current": len(curr_keys),
        "added": len(added),
        "removed": len(removed),
        "renamed": renamed,
    }


def format_report(stats: dict[str, int]) -> str:
    prev = max(stats["previous"], 1)
    curr = max(stats["current"], 1)
    pct_added = stats["added"] / curr * 100
    pct_removed = stats["removed"] / prev * 100
    pct_renamed = stats["renamed"] / curr * 100
    return (
        f"catalog diff:\n"
        f"  previous rows: {stats['previous']}\n"
        f"  current rows:  {stats['current']}\n"
        f"  added:         {stats['added']:6d}  (+{pct_added:.2f}%)\n"
        f"  removed:       {stats['removed']:6d}  (-{pct_removed:.2f}%)\n"
        f"  renamed:       {stats['renamed']:6d}  ({pct_renamed:.2f}%)\n"
    )


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--previous", type=pathlib.Path, required=True)
    parser.add_argument("--current", type=pathlib.Path, required=True)
    parser.add_argument(
        "--threshold",
        type=float,
        default=0.05,
        help="fail if added or removed exceeds this fraction (default 0.05 = 5%%)",
    )
    args = parser.parse_args(argv)

    prev = load_entries(args.previous)
    curr = load_entries(args.current)
    stats = diff(prev, curr)
    sys.stdout.write(format_report(stats))

    if not prev:
        # First build — nothing to compare against.
        return 0
    fraction_changed = max(
        stats["added"] / max(stats["current"], 1),
        stats["removed"] / max(stats["previous"], 1),
    )
    if fraction_changed > args.threshold:
        sys.stderr.write(
            f"warning: change ratio {fraction_changed:.2%} exceeds threshold "
            f"{args.threshold:.2%}\n"
        )
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
