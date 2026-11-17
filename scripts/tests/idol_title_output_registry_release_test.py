#!/usr/bin/env python3
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[2]
PYTHON = ROOT / "scripts" / "idol-video-python"
DIRECT_PYTHON = Path(sys.executable)
SCRIPT = ROOT / "scripts" / "idol_title_output_registry.py"


class TitleOutputRegistryReleaseTest(unittest.TestCase):
    def registry(self, *, output_type: str = "remote_publication", status: str = "published") -> dict:
        path = "https://www.youtube.com/watch?v=TEST"
        return {
            "schema_version": "1.1",
            "album_key": "aurora-m",
            "title_key": "release-test",
            "title_display_name": "Release Test",
            "status": "packaged",
            "canonical_title_root": "catalog/albums/aurora-m/release-test",
            "content_ids": ["RELEASE_TEST"],
            "source_runs": [
                {
                    "run_root": "runs/aurora-m/release-test/RELEASE_TEST",
                    "content_id": "RELEASE_TEST",
                    "role": "owner",
                    "first_registered_at": "2026-07-10T00:00:00+09:00",
                    "last_updated_at": "2026-07-10T00:00:00+09:00",
                }
            ],
            "output_roots": {
                "title_root": "catalog/albums/aurora-m/release-test",
                "run_roots": ["runs/aurora-m/release-test/RELEASE_TEST"],
                "prompt_exports": "runs/*/*/*/exports/02B/prompts/",
                "imagegen_manifests": "runs/*/*/*/exports/02B/manifests/",
                "review_boards": "runs/*/*/*/generations/review-boards/",
                "branch_cut_images": "runs/*/*/*/generations/branch-cuts/",
                "video_prompts": "runs/*/*/*/generations/video-prompts/",
                "generated_videos": "runs/*/*/*/generations/video/",
                "edits": "runs/*/*/*/generations/video/master/",
                "packages": "runs/*/*/*/package/",
            },
            "outputs": [
                {
                    "output_id": "OUT_REMOTE_TEST",
                    "output_type": output_type,
                    "path": path,
                    "source_run_root": "runs/aurora-m/release-test/RELEASE_TEST",
                    "content_id": "RELEASE_TEST",
                    "source_step": "publishing_record",
                    "status": status,
                    "registered_at": "2026-07-10T00:00:00+09:00",
                    "last_seen_at": "2026-07-10T00:00:00+09:00",
                    "notes": "observed publication fact",
                }
            ],
            "latest_pointers": {output_type: path},
            "review_summary": {
                "founder_review_status": "pass",
                "passed_output_ids": ["OUT_REMOTE_TEST"],
                "held_output_ids": [],
                "rejected_output_ids": [],
            },
            "open_questions": [],
        }

    def validate(self, document: dict) -> tuple[subprocess.CompletedProcess[str], dict]:
        with tempfile.TemporaryDirectory(prefix="idol-registry-release-") as tmp:
            path = Path(tmp) / "output-registry.yaml"
            path.write_text(yaml.safe_dump(document, sort_keys=False), encoding="utf-8")
            result = subprocess.run(
                [str(PYTHON), str(SCRIPT), "validate", "--registry", str(path)],
                cwd=ROOT,
                text=True,
                capture_output=True,
                check=False,
            )
            return result, json.loads(result.stdout)

    def test_remote_publication_is_a_valid_nonlocal_pointer(self) -> None:
        document = self.registry()
        result, report = self.validate(document)
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertTrue(report["valid"])
        with tempfile.TemporaryDirectory(prefix="idol-registry-schema-") as tmp:
            path = Path(tmp) / "output-registry.yaml"
            path.write_text(yaml.safe_dump(document, sort_keys=False), encoding="utf-8")
            schema_result = subprocess.run(
                [
                    str(PYTHON),
                    str(ROOT / "scripts" / "validate_json_schema.py"),
                    str(ROOT / "schemas" / "title-output-registry.schema.json"),
                    str(path),
                ],
                cwd=ROOT,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(0, schema_result.returncode, schema_result.stderr)

    def test_remote_url_cannot_hide_under_a_local_output_type(self) -> None:
        result, report = self.validate(self.registry(output_type="social_asset"))
        self.assertNotEqual(0, result.returncode)
        self.assertTrue(any("use remote_publication" in error for error in report["errors"]))

    def test_remote_publication_requires_published_fact_status(self) -> None:
        result, report = self.validate(self.registry(status="planned"))
        self.assertNotEqual(0, result.returncode)
        self.assertTrue(any("must be published" in error for error in report["errors"]))

    def test_legacy_keyframe_registry_is_not_accepted_as_active(self) -> None:
        document = self.registry()
        document["schema_version"] = "1.0"
        document["output_roots"]["keyframe_images"] = document["output_roots"].pop("branch_cut_images")
        result, report = self.validate(document)
        self.assertNotEqual(0, result.returncode)
        self.assertTrue(any("legacy keyframe registries are evidence-only" in error for error in report["errors"]))
        self.assertTrue(any("use branch_cut_images" in error for error in report["errors"]))

    def test_register_path_records_branch_cut_identity(self) -> None:
        with tempfile.TemporaryDirectory(prefix="idol-registry-branch-cut-") as tmp:
            image = Path(tmp) / "runs/aurora-m/release-test/RELEASE_TEST/generations/branch-cuts/BC01.png"
            image.parent.mkdir(parents=True)
            image.write_bytes(b"branch-cut")
            result = subprocess.run(
                [
                    str(DIRECT_PYTHON),
                    str(SCRIPT),
                    "register-path",
                    "--run",
                    "runs/aurora-m/release-test/RELEASE_TEST",
                    "--album-key",
                    "aurora-m",
                    "--title-key",
                    "release-test",
                    "--output-type",
                    "branch_cut_image",
                    "--path",
                    image.relative_to(tmp).as_posix(),
                    "--packet-id",
                    "PKT_BC01",
                    "--core-cut-id",
                    "CC01",
                    "--branch-cut-id",
                    "BC01",
                    "--section-id",
                    "S01",
                    "--source-step",
                    "generated_branch_cut_review",
                    "--output-status",
                    "passed",
                    "--write",
                ],
                cwd=tmp,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(0, result.returncode, result.stderr)
            registry_path = Path(tmp) / "catalog/albums/aurora-m/release-test/output-registry.yaml"
            registry = yaml.safe_load(registry_path.read_text(encoding="utf-8"))
            self.assertEqual("1.1", registry["schema_version"])
            self.assertEqual("branch_cut_image", registry["outputs"][0]["output_type"])
            self.assertEqual("CC01", registry["outputs"][0]["core_cut_id"])
            self.assertEqual("BC01", registry["outputs"][0]["branch_cut_id"])
            self.assertIn("branch_cut_images", registry["output_roots"])
            schema_result = subprocess.run(
                [
                    str(PYTHON),
                    str(ROOT / "scripts" / "validate_json_schema.py"),
                    str(ROOT / "schemas" / "title-output-registry.schema.json"),
                    str(registry_path),
                ],
                cwd=tmp,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(0, schema_result.returncode, schema_result.stderr)

    def test_register_path_preserves_https_url_exactly(self) -> None:
        url = "https://www.youtube.com/watch?v=REGISTER_TEST"
        with tempfile.TemporaryDirectory(prefix="idol-registry-register-") as tmp:
            result = subprocess.run(
                [
                    str(DIRECT_PYTHON),
                    str(SCRIPT),
                    "register-path",
                    "--run",
                    "runs/aurora-m/release-test/RELEASE_TEST",
                    "--album-key",
                    "aurora-m",
                    "--title-key",
                    "release-test",
                    "--output-type",
                    "remote_publication",
                    "--path",
                    url,
                    "--source-step",
                    "publishing_record",
                    "--output-status",
                    "published",
                    "--write",
                ],
                cwd=tmp,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(0, result.returncode, result.stderr)
            registry_path = Path(tmp) / "catalog/albums/aurora-m/release-test/output-registry.yaml"
            registry = yaml.safe_load(registry_path.read_text(encoding="utf-8"))
            self.assertEqual(url, registry["outputs"][0]["path"])
            self.assertEqual(url, registry["latest_pointers"]["remote_publication"])

    def test_hold_authoring_request_is_registered_but_not_promoted_latest(self) -> None:
        with tempfile.TemporaryDirectory(prefix="idol-registry-hold-") as tmp:
            request = Path(tmp) / "runs/aurora-m/release-test/RELEASE_TEST/handoff/request.md"
            request.parent.mkdir(parents=True)
            request.write_text("hold", encoding="utf-8")
            result = subprocess.run(
                [
                    str(DIRECT_PYTHON),
                    str(SCRIPT),
                    "register-path",
                    "--run",
                    "runs/aurora-m/release-test/RELEASE_TEST",
                    "--album-key",
                    "aurora-m",
                    "--title-key",
                    "release-test",
                    "--output-type",
                    "video_prompt_authoring_request",
                    "--path",
                    request.relative_to(tmp).as_posix(),
                    "--source-step",
                    "post_review_video",
                    "--output-status",
                    "hold",
                    "--write",
                ],
                cwd=tmp,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(0, result.returncode, result.stderr)
            registry_path = Path(tmp) / "catalog/albums/aurora-m/release-test/output-registry.yaml"
            registry = yaml.safe_load(registry_path.read_text(encoding="utf-8"))
            self.assertEqual("hold", registry["outputs"][0]["status"])
            self.assertNotIn("video_prompt_authoring_request", registry["latest_pointers"])


if __name__ == "__main__":
    unittest.main()
