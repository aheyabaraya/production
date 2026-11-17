#!/usr/bin/env python3
"""Validate privacy-preserving Loom Signal Deck traffic snapshots."""

from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_LEDGER = ROOT / "analytics" / "records" / "signal-deck-traffic.jsonl"
REQUIRED = {
    "captured_at",
    "metric_name",
    "count",
    "provider",
    "environment",
    "measurement_window",
    "source",
    "source_locator",
    "data_completeness",
    "collector_version",
}
OPTIONAL = {"known_gaps"}
FORBIDDEN_IDENTIFIERS = {
    "ip",
    "ip_address",
    "cookie",
    "cookies",
    "visitor_id",
    "session_id",
    "user_id",
    "email",
    "referrer_url",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("ledger", nargs="?", default=str(DEFAULT_LEDGER))
    return parser.parse_args()


def valid_time(value: Any) -> bool:
    if not isinstance(value, str) or not value:
        return False
    try:
        datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return False
    return True


def contains_forbidden_key(value: Any) -> str | None:
    if isinstance(value, dict):
        for key, child in value.items():
            if str(key).lower() in FORBIDDEN_IDENTIFIERS:
                return str(key)
            nested = contains_forbidden_key(child)
            if nested:
                return nested
    elif isinstance(value, list):
        for child in value:
            nested = contains_forbidden_key(child)
            if nested:
                return nested
    return None


def validate_row(row: dict[str, Any], label: str) -> list[str]:
    errors: list[str] = []
    keys = set(row)
    missing = sorted(REQUIRED - keys)
    unknown = sorted(keys - REQUIRED - OPTIONAL)
    if missing:
        errors.append(f"{label}: missing required fields: {', '.join(missing)}")
    if unknown:
        errors.append(f"{label}: unsupported fields: {', '.join(unknown)}")
    forbidden = contains_forbidden_key(row)
    if forbidden:
        errors.append(f"{label}: personal/event identifier is forbidden: {forbidden}")
    if not valid_time(row.get("captured_at")):
        errors.append(f"{label}: captured_at must be ISO-8601")
    if row.get("metric_name") != "visits_count":
        errors.append(f"{label}: metric_name must be visits_count")
    count = row.get("count")
    if isinstance(count, bool) or not isinstance(count, int) or count < 0:
        errors.append(f"{label}: count must be a non-negative integer")
    if row.get("provider") != "vercel_web_analytics_api":
        errors.append(f"{label}: provider must be vercel_web_analytics_api")
    if row.get("environment") != "production":
        errors.append(f"{label}: environment must be production")
    if row.get("measurement_window") != "provider_default_window":
        errors.append(f"{label}: measurement_window must be provider_default_window")
    if row.get("source") != "official_vercel_web_analytics_api":
        errors.append(f"{label}: source must be official_vercel_web_analytics_api")
    if row.get("source_locator") != "/v1/query/web-analytics/visits/count":
        errors.append(f"{label}: source_locator must be the aggregate visits endpoint")
    if row.get("data_completeness") not in {"complete", "partial"}:
        errors.append(f"{label}: data_completeness must be complete or partial")
    if row.get("collector_version") != "loom_metric_collector.v1":
        errors.append(f"{label}: collector_version must be loom_metric_collector.v1")
    if "known_gaps" in row:
        gaps = row["known_gaps"]
        if not isinstance(gaps, list) or any(not isinstance(item, str) or not item for item in gaps):
            errors.append(f"{label}: known_gaps must be a list of non-empty strings")
        elif len(gaps) != len(set(gaps)):
            errors.append(f"{label}: known_gaps must not repeat values")
    return errors


def main() -> int:
    args = parse_args()
    ledger = Path(args.ledger)
    if not ledger.is_file():
        print(f"ERROR: signal-deck traffic ledger is missing: {ledger}", file=sys.stderr)
        return 1

    errors: list[str] = []
    captured: set[str] = set()
    rows = 0
    for line_no, raw in enumerate(ledger.read_text(encoding="utf-8").splitlines(), 1):
        text = raw.strip()
        if not text:
            continue
        rows += 1
        label = f"signal-deck-traffic:{line_no}"
        try:
            row = json.loads(text)
        except json.JSONDecodeError:
            errors.append(f"{label}: invalid JSON")
            continue
        if not isinstance(row, dict):
            errors.append(f"{label}: row must be an object")
            continue
        errors.extend(validate_row(row, label))
        captured_at = row.get("captured_at")
        if isinstance(captured_at, str):
            if captured_at in captured:
                errors.append(f"{label}: captured_at duplicates another traffic snapshot")
            captured.add(captured_at)

    if errors:
        print("\n".join(f"ERROR: {item}" for item in errors), file=sys.stderr)
        return 1
    print(f"OK: {rows} Signal Deck traffic snapshot(s) validated")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
