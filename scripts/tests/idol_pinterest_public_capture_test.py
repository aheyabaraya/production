#!/usr/bin/env python3
"""Unit checks for the public Pinterest still capture helper."""

from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "idol_pinterest_public_capture.py"
SPEC = importlib.util.spec_from_file_location("idol_pinterest_public_capture", SCRIPT)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class PinterestPublicCaptureTest(unittest.TestCase):
    def test_accepts_public_pin_hosts_only(self) -> None:
        self.assertEqual(MODULE.public_pin_url("https://www.pinterest.com/pin/123/"), "https://www.pinterest.com/pin/123/")
        self.assertEqual(MODULE.public_pin_url("https://pin.it/example"), "https://pin.it/example")
        with self.assertRaises(ValueError):
            MODULE.public_pin_url("https://example.com/pin/123")
        with self.assertRaises(ValueError):
            MODULE.public_pin_url("http://www.pinterest.com/pin/123/")

    def test_enforces_720px_short_edge(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            too_small = Path(folder) / "small.png"
            valid = Path(folder) / "valid.png"
            Image.new("RGB", (719, 1200), "white").save(too_small)
            Image.new("RGB", (720, 1280), "white").save(valid)
            with self.assertRaisesRegex(ValueError, "minimum is 720px"):
                MODULE.inspect_image(too_small, 720)
            result = MODULE.inspect_image(valid, 720)
            self.assertEqual((result["width"], result["height"]), (720, 1280))

    def test_production_output_is_repo_relative_and_bounded(self) -> None:
        self.assertTrue(str(MODULE.repo_output_dir("runs/A/T/R/research/reference-intake/pinterest")).startswith(str(ROOT)))
        with self.assertRaises(ValueError):
            MODULE.repo_output_dir("/tmp/pinterest")
        with self.assertRaises(ValueError):
            MODULE.repo_output_dir("wiki/pinterest")


if __name__ == "__main__":
    unittest.main()
