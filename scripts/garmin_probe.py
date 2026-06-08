#!/usr/bin/env python3
"""Garmin Connect protocol probe — Phase 1 of Garmin integration plan.

Validates which Garmin Connect endpoints return usable data, what the
field shapes are, and what rate limits apply. No Flutter code; pure
Python using `python-garminconnect`.

Usage:
    cd scripts/
    uv venv garmin-probe
    source garmin-probe/bin/activate
    uv pip install garminconnect

    # Interactive (prompts for credentials) — CN region by default
    python garmin_probe.py

    # With env vars
    GARMIN_EMAIL=you@example.com GARMIN_PASSWORD=secret python garmin_probe.py

    # Specify date range (default: last 7 days)
    python garmin_probe.py --from 2026-06-01 --to 2026-06-07

    # Use global region (not CN)
    python garmin_probe.py --region global

Output: scripts/garmin_sample_output.json
"""

import argparse
import json
import os
import sys
import time
from datetime import datetime, timedelta, date
from pathlib import Path

try:
    from garminconnect import Garmin
except ImportError:
    print("ERROR: garminconnect not installed. Run: uv pip install garminconnect")
    sys.exit(1)


def probe_daily(client: Garmin, d: str) -> dict:
    """Probe all daily endpoints for a single date."""
    result = {}
    endpoints = {
        "steps": lambda: client.get_steps_data(d),
        "sleep": lambda: client.get_sleep_data(d),
        "rhr": lambda: client.get_rhr_day(d),
        "hrv": lambda: client.get_hrv_data(d),
        "body_battery": lambda: client.get_body_battery(d),
        "stress": lambda: client.get_stress_data(d),
        "user_summary": lambda: client.get_user_summary(d),
        "weight": lambda: client.get_daily_weigh_ins(d),
    }
    for name, fn in endpoints.items():
        t0 = time.monotonic()
        try:
            data = fn()
            elapsed = time.monotonic() - t0
            result[name] = {
                "ok": True,
                "elapsed_ms": round(elapsed * 1000),
                "data": data,
                "raw_keys": list(data.keys()) if isinstance(data, dict) else (
                    [list(item.keys()) for item in data[:3]] if isinstance(data, list) and data else []
                ),
            }
        except Exception as e:
            elapsed = time.monotonic() - t0
            result[name] = {
                "ok": False,
                "elapsed_ms": round(elapsed * 1000),
                "error": str(e),
                "error_type": type(e).__name__,
            }
    return result


def probe_activities(client: Garmin, start: int = 0, limit: int = 10) -> dict:
    """Probe activity endpoints."""
    result = {}
    t0 = time.monotonic()
    try:
        data = client.get_activities(start, limit)
        elapsed = time.monotonic() - t0
        result["activities"] = {
            "ok": True,
            "elapsed_ms": round(elapsed * 1000),
            "count": len(data),
            "sample_keys": [list(item.keys()) for item in data[:3]] if data else [],
            "data": data,
        }
    except Exception as e:
        elapsed = time.monotonic() - t0
        result["activities"] = {
            "ok": False,
            "elapsed_ms": round(elapsed * 1000),
            "error": str(e),
            "error_type": type(e).__name__,
        }
    return result


def probe_training_status(client: Garmin) -> dict:
    """Probe training status / VO2 max."""
    result = {}
    t0 = time.monotonic()
    try:
        data = client.get_training_status()
        elapsed = time.monotonic() - t0
        result["training_status"] = {
            "ok": True,
            "elapsed_ms": round(elapsed * 1000),
            "data": data,
            "raw_keys": list(data.keys()) if isinstance(data, dict) else str(type(data)),
        }
    except Exception as e:
        elapsed = time.monotonic() - t0
        result["training_status"] = {
            "ok": False,
            "elapsed_ms": round(elapsed * 1000),
            "error": str(e),
            "error_type": type(e).__name__,
        }
    return result


def main():
    parser = argparse.ArgumentParser(description="Garmin Connect protocol probe")
    parser.add_argument("--from", dest="from_date", help="Start date (YYYY-MM-DD)")
    parser.add_argument("--to", dest="to_date", help="End date (YYYY-MM-DD)")
    parser.add_argument("--output", default="garmin_sample_output.json", help="Output file")
    parser.add_argument("--region", default="cn", choices=["cn", "global"],
                        help="Garmin region: cn (China) or global (default: cn)")
    args = parser.parse_args()

    # Resolve dates
    today = date.today()
    if args.to_date:
        to_date = date.fromisoformat(args.to_date)
    else:
        to_date = today - timedelta(days=1)  # yesterday
    if args.from_date:
        from_date = date.fromisoformat(args.from_date)
    else:
        from_date = to_date - timedelta(days=6)  # 7 days

    # Credentials
    email = os.environ.get("GARMIN_EMAIL")
    password = os.environ.get("GARMIN_PASSWORD")
    if not email:
        email = input("Garmin email: ").strip()
    if not password:
        import getpass
        password = getpass.getpass("Garmin password: ")

    is_cn = args.region == "cn"
    print(f"Probing Garmin Connect ({'CN' if is_cn else 'Global'}): {from_date} → {to_date}")
    print(f"Output: {args.output}")
    print()

    # Authenticate
    print("Authenticating...")
    t0 = time.monotonic()
    try:
        client = Garmin(email, password, is_cn=is_cn)
        client.login()
        auth_elapsed = time.monotonic() - t0
        print(f"  ✓ Authenticated ({auth_elapsed:.1f}s)")
    except Exception as e:
        print(f"  ✗ Auth failed: {e}")
        print()
        print("If MFA is required, you may need to:")
        print("  1. Disable MFA temporarily for this probe")
        print("  2. Or use the garminconnect MFA flow (see library docs)")
        sys.exit(1)

    results = {
        "authenticated_at": datetime.now().isoformat() + "Z",
        "probe_window": f"{from_date}..{to_date}",
        "auth_elapsed_ms": round(auth_elapsed * 1000),
        "daily": {},
        "activities": {},
        "training_status": {},
    }

    # Probe each day
    dates = [from_date + timedelta(days=i) for i in range((to_date - from_date).days + 1)]
    for i, d in enumerate(dates):
        ds = d.isoformat()
        print(f"  Day {i+1}/{len(dates)}: {ds} ...", end=" ", flush=True)
        t0 = time.monotonic()
        day_result = probe_daily(client, ds)
        elapsed = time.monotonic() - t0
        ok_count = sum(1 for v in day_result.values() if v.get("ok"))
        print(f"{ok_count}/{len(day_result)} ok ({elapsed:.1f}s)")
        results["daily"][ds] = day_result
        # Rate limit courtesy
        if i < len(dates) - 1:
            time.sleep(0.5)

    # Probe activities
    print("  Activities...", end=" ", flush=True)
    results["activities"] = probe_activities(client)
    ok = results["activities"].get("activities", {}).get("ok", False)
    count = results["activities"].get("activities", {}).get("count", 0)
    print(f"{'✓' if ok else '✗'} ({count} activities)")

    # Probe training status
    print("  Training status...", end=" ", flush=True)
    results["training_status"] = probe_training_status(client)
    ok = results["training_status"].get("training_status", {}).get("ok", False)
    print(f"{'✓' if ok else '✗'}")

    # Write output
    output_path = Path(args.output)
    with open(output_path, "w") as f:
        json.dump(results, f, indent=2, default=str)
    print()
    print(f"Done. Output written to {output_path}")

    # Summary
    total_days = len(dates)
    endpoint_names = ["steps", "sleep", "rhr", "hrv", "body_battery", "stress", "user_summary", "weight"]
    print()
    print("Endpoint success summary:")
    for ep in endpoint_names:
        ok_days = sum(
            1 for d in results["daily"].values()
            if d.get(ep, {}).get("ok", False)
        )
        print(f"  {ep:20s} {ok_days}/{total_days} days")

    # Rate limit notes
    errors = []
    for ds, day in results["daily"].items():
        for ep, val in day.items():
            if not val.get("ok"):
                errors.append(f"  {ds} {ep}: {val.get('error_type')}: {val.get('error')}")
    if errors:
        print()
        print("Errors:")
        for e in errors[:20]:
            print(e)
        if len(errors) > 20:
            print(f"  ... and {len(errors) - 20} more")


if __name__ == "__main__":
    main()
