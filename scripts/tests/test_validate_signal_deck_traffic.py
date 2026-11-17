#!/usr/bin/env python3
"""Regression tests for the aggregate-only Signal Deck traffic ledger."""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
VALIDATOR = ROOT / "scripts" / "validate_signal_deck_traffic.py"


def valid_row() -> dict[str, object]:
    return {
        "captured_at": "2026-07-30T10:15:00+09:00",
        "metric_name": "visits_count",
        "count": 18,
        "provider": "vercel_web_analytics_api",
        "environment": "production",
        "measurement_window": "provider_default_window",
        "source": "official_vercel_web_analytics_api",
        "source_locator": "/v1/query/web-analytics/visits/count",
        "data_completeness": "partial",
        "known_gaps": ["No fixed window is configured."],
        "collector_version": "loom_metric_collector.v1",
    }


class SignalDeckTrafficValidatorTest(unittest.TestCase):
    def validate(self, row: dict[str, object]) -> subprocess.CompletedProcess[str]:
        with tempfile.TemporaryDirectory() as temporary:
            ledger = Path(temporary) / "traffic.jsonl"
            ledger.write_text(json.dumps(row) + "\n", encoding="utf-8")
            return subprocess.run(
                [sys.executable, str(VALIDATOR), str(ledger)],
                capture_output=True,
                text=True,
                check=False,
            )

    def test_valid_aggregate_snapshot_passes(self) -> None:
        result = self.validate(valid_row())
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_event_identifier_is_rejected(self) -> None:
        row = valid_row()
        row["visitor_id"] = "must-not-be-stored"
        result = self.validate(row)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("visitor_id", result.stderr)


if __name__ == "__main__":
    unittest.main()
