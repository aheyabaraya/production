#!/usr/bin/env python3

from __future__ import annotations

import sys
import unittest
from pathlib import Path

import numpy as np


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

import idol_audio_precision_markers as precision  # noqa: E402
import idol_video_sync_workbench as workbench  # noqa: E402


class AudioPhaseContractTest(unittest.TestCase):
    def setUp(self) -> None:
        self.beats = np.asarray([0.5, 1.0, 1.5, 2.0, 2.5, 3.0])

    def test_no_manual_anchor_is_candidate_only_in_both_tools(self) -> None:
        self.assertEqual(
            ("unverified_candidate", 0, None),
            precision.meter_phase(self.beats, 4, None, None, 0.08),
        )
        self.assertEqual(
            ("unverified_candidate", 0, None),
            workbench.resolve_meter_phase(self.beats, 4, None, None, 0.08),
        )

    def test_manual_anchor_locks_declared_beat_in_bar(self) -> None:
        expected = ("manual_locked", 0, 0.0)
        self.assertEqual(
            expected,
            precision.meter_phase(self.beats, 4, 1.0, 2, 0.08),
        )
        self.assertEqual(
            expected,
            workbench.resolve_meter_phase(self.beats, 4, 1.0, 2, 0.08),
        )

    def test_out_of_tolerance_anchor_fails_in_both_tools(self) -> None:
        for resolver in (precision.meter_phase, workbench.resolve_meter_phase):
            with self.subTest(resolver=resolver.__module__):
                with self.assertRaisesRegex(SystemExit, "tolerance"):
                    resolver(self.beats, 4, 1.2, 2, 0.05)

    def test_partial_anchor_and_empty_detected_grid_fail_closed(self) -> None:
        for resolver in (precision.meter_phase, workbench.resolve_meter_phase):
            with self.subTest(resolver=resolver.__module__, case="partial"):
                with self.assertRaisesRegex(SystemExit, "supplied together"):
                    resolver(self.beats, 4, 1.0, None, 0.08)
            with self.subTest(resolver=resolver.__module__, case="empty"):
                with self.assertRaisesRegex(SystemExit, "no beats"):
                    resolver(np.asarray([]), 4, 1.0, 1, 0.08)


if __name__ == "__main__":
    unittest.main()
