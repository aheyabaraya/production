#!/usr/bin/env python3
"""Regression tests for active/closed publishing-plan classification."""

from __future__ import annotations

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "validate_publishing_plan.py"
PYTHON = ROOT / "scripts" / "idol-video-python"
sys.path.insert(0, str(ROOT / "scripts"))

import validate_publishing_plan as validator  # noqa: E402


def active_plan(status: str) -> str:
    return "\n".join(
        [
            "content_id: RELEASE_MODE_TEST",
            "public_group_name: Loom",
            "public_fan_name: Harne",
            f"status: {status}",
            "created_at_kst: 2026-07-11T00:00:00+09:00",
            "updated_at_kst: 2026-07-11T00:00:00+09:00",
            "",
            "## Scope",
            "Test scope.",
            "",
            "## Tracking Convention",
            "Use post_id.",
            "",
            "## Draft Queue",
            "",
            "| Post ID | Platform | Draft slot KST | Clip | Caption / title |",
            "| --- | --- | --- | --- | --- |",
            "| RELEASE_MODE_TEST-YS-001 | youtube_shorts | 12:00 | clip-01 | Loom test |",
            "",
            "## Approval State",
            "Pending.",
            "",
        ]
    )


class ValidatePublishingPlanModesTest(unittest.TestCase):
    def write_plan(self, status: str) -> Path:
        temp = tempfile.NamedTemporaryFile(
            mode="w", suffix=".md", encoding="utf-8", delete=False
        )
        self.addCleanup(lambda: Path(temp.name).unlink(missing_ok=True))
        temp.write(active_plan(status))
        temp.close()
        return Path(temp.name)

    def write_text(self, text: str) -> Path:
        temp = tempfile.NamedTemporaryFile(
            mode="w", suffix=".md", encoding="utf-8", delete=False
        )
        self.addCleanup(lambda: Path(temp.name).unlink(missing_ok=True))
        temp.write(text)
        temp.close()
        return Path(temp.name)

    def test_archived_status_is_closed(self) -> None:
        path = self.write_plan("archived")
        self.assertEqual("closed", validator.detect_mode(path))
        with self.assertRaisesRegex(ValueError, "closed or archived"):
            validator.extract_contract(path, mode="active")

    def test_final_complete_status_is_closed(self) -> None:
        path = self.write_plan("final_complete_platform_records_closed")
        self.assertEqual("closed", validator.detect_mode(path))

    def test_explicit_active_mode_refuses_archived_record(self) -> None:
        path = self.write_plan("archived")
        result = subprocess.run(
            [str(PYTHON), str(SCRIPT), str(path), "--mode", "active"],
            cwd=ROOT,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertNotEqual(0, result.returncode)
        self.assertIn("immutable closed or archived", result.stderr)
        self.assertNotIn("Traceback", result.stderr)

    def test_draft_status_remains_active(self) -> None:
        path = self.write_plan("draft")
        self.assertEqual("active", validator.detect_mode(path))
        contract = validator.extract_contract(path, mode="active")
        self.assertEqual("active_plan", contract["record_kind"])

    def test_expanded_queue_fields_are_not_flattened_to_clip(self) -> None:
        text = active_plan("draft").replace(
            "| Post ID | Platform | Draft slot KST | Clip | Caption / title |\n"
            "| --- | --- | --- | --- | --- |\n"
            "| RELEASE_MODE_TEST-YS-001 | youtube_shorts | 12:00 | clip-01 | Loom test |",
            "| Post ID | Platform | Draft slot KST | Clip | Caption / title | Template Type | Content Lane | Format Family | API Upload Quality Profile | API Upload Quality Receipt | Shared Media Source Post ID | Member | Member Intro Line |\n"
            "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |\n"
            "| RELEASE_MODE_TEST-X-ROOT | x | 12:00 | clip-01 | Loom test | work_root | mv_cutdown | video | idol_api_upload_2k30_high_quality.v1 | exports/social/clip-01.receipt.yaml | | M02 | Seorin is holding the final frame. |",
        )
        path = self.write_text(text)
        contract = validator.extract_contract(path, mode="active")
        row = contract["draft_queue"][0]
        self.assertEqual("work_root", row["template_type"])
        self.assertEqual("mv_cutdown", row["content_lane"])
        self.assertEqual("video", row["format_family"])
        self.assertEqual(
            "idol_api_upload_2k30_high_quality.v1",
            row["api_upload_quality_profile"],
        )
        self.assertEqual(
            "exports/social/clip-01.receipt.yaml",
            row["api_upload_quality_receipt"],
        )
        self.assertEqual(["M02"], row["member"])
        self.assertEqual("Seorin is holding the final frame.", row["member_intro_line"])
        result = subprocess.run(
            [str(PYTHON), str(SCRIPT), str(path), "--mode", "active"],
            cwd=ROOT,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(0, result.returncode, result.stderr)


if __name__ == "__main__":
    unittest.main()
