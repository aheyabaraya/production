#!/usr/bin/env python3
"""Fail-closed checks for retired beat-source authoring and paid submission."""

from __future__ import annotations

import json
from pathlib import Path
import subprocess
import sys
import unittest


ROOT = Path(__file__).resolve().parents[2]


class LegacyBeatSourceRetirementTest(unittest.TestCase):
    def run_script(self, script: str, *arguments: str) -> dict[str, object]:
        result = subprocess.run(
            [sys.executable, str(ROOT / "scripts" / script), *arguments],
            cwd=ROOT,
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 1, result.stderr or result.stdout)
        payload = json.loads(result.stdout)
        self.assertFalse(payload["ok"])
        return payload

    def test_manifest_builder_is_retired_before_input_read(self) -> None:
        payload = self.run_script(
            "idol_build_two_cut_source_manifest.py",
            "--packet-path",
            "missing-packet.yaml",
        )
        self.assertIn("retired", str(payload["error"]))

    def test_manifest_sharder_is_retired_before_input_read(self) -> None:
        payload = self.run_script(
            "idol_split_beat_source_manifest_by_section.py",
            "--manifest",
            "missing-manifest.yaml",
            "--out-dir",
            "missing-output",
        )
        self.assertIn("retired", str(payload["error"]))

    def test_runner_prepare_and_submit_are_retired_before_local_or_external_access(self) -> None:
        prepare = self.run_script(
            "idol_cut_keyframe_batch_api_runner.py",
            "prepare",
            "--manifest",
            "missing-manifest.yaml",
        )
        submit = self.run_script(
            "idol_cut_keyframe_batch_api_runner.py",
            "submit",
            "--state",
            "missing-state.json",
            "--write",
            "--founder-approved",
        )
        self.assertIn("retired", str(prepare["error"]))
        self.assertIn("retired", str(submit["error"]))


if __name__ == "__main__":
    unittest.main()
