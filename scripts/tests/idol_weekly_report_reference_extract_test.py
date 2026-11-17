from __future__ import annotations

import base64
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "idol_weekly_report_reference_extract.py"
INTEGRATED_TEMPLATE = ROOT / "source-materials" / "idol-activity-reports" / "weekly" / "TEMPLATE.html"
BRAND_TEMPLATE = ROOT / "source-materials" / "idol-activity-reports" / "weekly" / "REPRESENTATIVE-IDOL-BRAND-TEMPLATE.html"


class WeeklyReportReferenceExtractTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.repo = Path(self.temporary.name)
        self.weekly = self.repo / "source-materials" / "idol-activity-reports" / "weekly"
        self.weekly.mkdir(parents=True)
        self.run_root = self.repo / "runs" / "2026-07-14" / "TEST_REFERENCE"
        self.run_root.mkdir(parents=True)
        self.evidence_id = "evidence-test-01"
        self.reference_id = "WIR-2026-29-TEST-01"
        self.image_bytes = b"\x89PNG\r\n\x1a\nreference-test"
        self.report = self.weekly / "2026-29-idol-activity-report.html"
        self.ledger = self.weekly / "2026-29-reference-image-ledger.md"
        self.write_fixture()

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def write_fixture(
        self, *, placeholder: bool = False, eligible: bool = True, direct_reference: bool = True
    ) -> None:
        image = base64.b64encode(self.image_bytes).decode("ascii")
        placeholder_attribute = ' data-placeholder="true"' if placeholder else ""
        eligibility_attribute = (
            ' data-album-visual-reference="direct_reference_after_run_selection"' if eligible else ""
        )
        scope_attribute = (
            ' data-album-visual-scope="explicit_reference_selection_required"'
            if direct_reference
            else ""
        )
        self.report.write_text(
            "<html><body><dl><dt>status</dt><dd>complete</dd></dl>"
            f'<figure id="figure-test-01" data-evidence-id="{self.evidence_id}" '
            f'data-reference-id="{self.reference_id}" '
            f"{eligibility_attribute}{scope_attribute}>"
            f'<img{placeholder_attribute} src="data:image/png;base64,{image}"></figure>'
            "</body></html>",
            encoding="utf-8",
        )
        self.ledger.write_text(
            f"# ledger\nreference_id: {self.reference_id}\nimage_evidence_id: {self.evidence_id}\n",
            encoding="utf-8",
        )

    def command(self, *extra: str) -> list[str]:
        return [
            sys.executable,
            str(SCRIPT),
            "--repo-root",
            str(self.repo),
            "--report",
            str(self.report),
            "--ledger",
            str(self.ledger),
            "--evidence-id",
            self.evidence_id,
            "--reference-id",
            self.reference_id,
            "--run-root",
            str(self.run_root),
            *extra,
        ]

    def test_verify_only_keeps_report_image_inline(self) -> None:
        result = subprocess.run(self.command("--verify-only"), text=True, capture_output=True, check=False)
        self.assertEqual(0, result.returncode, result.stderr)
        manifest = json.loads(result.stdout)
        self.assertEqual("verified", manifest["status"])
        self.assertTrue(manifest["semantic_read_order"].startswith("html_visual_reference_board"))
        self.assertTrue(manifest["album_visual_reference_eligible"])
        self.assertTrue(manifest["general_direction_eligible"])
        self.assertFalse(manifest["generation_attachment_authorized"])
        self.assertFalse((self.run_root / "research" / "weekly-report-reference-extracts").exists())

    def test_extracts_exact_bytes_and_manifest_into_registered_run_path(self) -> None:
        result = subprocess.run(self.command(), text=True, capture_output=True, check=False)
        self.assertEqual(0, result.returncode, result.stderr)
        manifest = json.loads(result.stdout)
        output = self.repo / manifest["extracted_path"]
        manifest_path = output.with_suffix(".json")
        self.assertEqual(self.image_bytes, output.read_bytes())
        self.assertTrue(manifest_path.is_file())
        saved = json.loads(manifest_path.read_text(encoding="utf-8"))
        self.assertEqual(manifest["embedded_derivative_sha256"], saved["extracted_sha256"])
        self.assertEqual("figure-test-01", saved["source_figure_id"])

    def test_rejects_placeholder_even_when_report_claims_complete(self) -> None:
        self.write_fixture(placeholder=True)
        result = subprocess.run(self.command(), text=True, capture_output=True, check=False)
        self.assertEqual(2, result.returncode)
        self.assertIn("placeholder", result.stderr)

    def test_rejects_figure_not_marked_for_album_visual_reference_intake(self) -> None:
        self.write_fixture(eligible=False)
        result = subprocess.run(self.command(), text=True, capture_output=True, check=False)
        self.assertEqual(2, result.returncode)
        self.assertIn("direct reference after run selection", result.stderr)

    def test_rejects_figure_without_explicit_direct_reference_scope(self) -> None:
        self.write_fixture(direct_reference=False)
        result = subprocess.run(self.command(), text=True, capture_output=True, check=False)
        self.assertEqual(2, result.returncode)
        self.assertIn("direct-reference", result.stderr)

    def test_templates_mark_every_evidence_figure_as_album_visual_reference(self) -> None:
        for template, expected_figures in ((INTEGRATED_TEMPLATE, 2), (BRAND_TEMPLATE, 4)):
            content = template.read_text(encoding="utf-8")
            self.assertIn("html_visual_reference_board_then_ledger_then_album_intake_extract", content)
            self.assertEqual(
                expected_figures,
                content.count('data-album-visual-reference="direct_reference_after_run_selection"'),
            )
            self.assertEqual(
                expected_figures,
                content.count('data-album-visual-scope="explicit_reference_selection_required"'),
            )
            self.assertEqual(expected_figures, content.count("앨범 비주얼 참조 역할"))


if __name__ == "__main__":
    unittest.main()
