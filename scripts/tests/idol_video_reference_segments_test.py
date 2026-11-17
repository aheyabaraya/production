#!/usr/bin/env python3
"""Regression checks for canonical source-sheet refresh planning."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path


SCRIPTS_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS_DIR))

import idol_video_reference_segments as segments  # noqa: E402


class IdolVideoReferenceSegmentsTest(unittest.TestCase):
    def test_canonical_cadence_is_duration_aware(self) -> None:
        short = segments.cadence_for_duration(60.0)
        full = segments.cadence_for_duration(60.001)
        self.assertEqual("one-second", short["preset"])
        self.assertEqual(5, short["segment_seconds"])
        self.assertEqual("three-second", full["preset"])
        self.assertEqual(15, full["segment_seconds"])

    def test_qc_command_uses_interval_sheets_not_cell_crops(self) -> None:
        context = {
            "source_root": segments.ROOT / "source-materials/video-sources/youtube/by-source/test-source",
            "platform_id": "test-source",
            "video": segments.ROOT / "source-materials/video-sources/youtube/by-source/test-source/videos/test-source.mp4",
        }
        command, output, manifest, cadence = segments.qc_command(context, 42.0)
        self.assertIn("--preset", command)
        self.assertEqual("one-second", command[command.index("--preset") + 1])
        self.assertEqual("5", command[command.index("--segment-duration") + 1])
        self.assertNotIn("--cell-crops-dir", command)
        self.assertEqual("short_source", cadence["kind"])
        self.assertIn("contact-sheets/segments-5s-1s", output.as_posix())
        self.assertTrue(manifest.name.endswith("-segments-5s-1s-manifest.json"))

    def test_full_source_command_keeps_three_second_fifteen_second_cadence(self) -> None:
        context = {
            "source_root": segments.ROOT / "source-materials/video-sources/youtube/by-source/test-source",
            "platform_id": "test-source",
            "video": segments.ROOT / "source-materials/video-sources/youtube/by-source/test-source/videos/test-source.mp4",
        }
        command, output, manifest, cadence = segments.qc_command(context, 61.0)
        self.assertEqual("three-second", command[command.index("--preset") + 1])
        self.assertEqual("15", command[command.index("--segment-duration") + 1])
        self.assertEqual("full_or_long_source", cadence["kind"])
        self.assertIn("contact-sheets/segments-15s", output.as_posix())
        self.assertTrue(manifest.name.endswith("-segments-15s-manifest.json"))


if __name__ == "__main__":
    unittest.main()
