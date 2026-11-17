import argparse
import contextlib
import importlib.util
import io
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

import yaml


SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))
from lib.idol_artifact_integrity import (  # noqa: E402
    HashBinder,
    IntegrityCache,
    publication_lock_path,
)

SCRIPT = SCRIPTS / "idol_video_reference_analysis_registry.py"
SPEC = importlib.util.spec_from_file_location("video_reference_analysis_registry", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC and SPEC.loader
SPEC.loader.exec_module(MODULE)


class VideoReferenceAnalysisRegistryTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.source_root = (
            self.root
            / "source-materials"
            / "video-sources"
            / "youtube"
            / "by-source"
            / "TEST123"
        )
        (self.source_root / "videos").mkdir(parents=True)
        self.video = self.source_root / "videos" / "TEST123.mp4"
        self.video.write_bytes(b"video-evidence")
        self.one_second = self.source_root / "analysis" / "whole-1s-manifest.json"
        self.one_second.parent.mkdir()
        self.one_second.write_text('{"sheet_count": 1}', encoding="utf-8")
        self.manifest = self.source_root / "source-manifest.yaml"
        self.manifest.write_text(
            yaml.safe_dump(
                {
                    "identity": {
                        "platform": "youtube",
                        "platform_id": "TEST123",
                        "normalized_url": "https://www.youtube.com/watch?v=TEST123",
                        "source_key": "youtube:TEST123",
                    },
                    "title": "Test source",
                    "media": [
                        {
                            "kind": "video",
                            "path": self.video.relative_to(self.root).as_posix(),
                        }
                    ],
                    "discovery_metadata": {"duration_seconds": 42.0},
                },
                sort_keys=False,
            ),
            encoding="utf-8",
        )
        self.analysis = self.source_root / "analysis" / "source-scene-reading-v2" / "first-read-v2.md"
        self.analysis.parent.mkdir(parents=True)
        self.analysis.write_text(
            "\n".join(
                [
                    "# Test",
                    "## 분석에 실제로 사용한 자료",
                    "video and one-second sheet",
                    "## 영상 전체의 큰 흐름",
                    "opening to ending",
                    "## 상세 장면 기록",
                    "### 0–8초",
                    "first event",
                    "### 9–17초",
                    "second event",
                    "### 18–27초",
                    "third event",
                    "## 공용 관찰에서 허용하는 전이 경계",
                    "camera route",
                    "## 공용 관찰에서 제외하는 전이 경계",
                    "source identity",
                ]
            ),
            encoding="utf-8",
        )

    def tearDown(self):
        self.temp.cleanup()

    def test_sync_starts_unanalysed(self):
        registry, errors = MODULE.build_registry(self.root, {})
        self.assertEqual([], errors)
        self.assertEqual(1, len(registry["sources"]))
        self.assertEqual("not_analyzed", registry["sources"][0]["analysis_state"])
        self.assertIn("미분석", MODULE.render_read_first(registry))

    def test_complete_record_requires_and_projects_exact_inputs(self):
        record = {
            "analysis_id": "TEST_WHOLE_FLOW_V1",
            "owner_scope": "source_materials_video_source",
            "authoring_stage": "source_first_read",
            "status": "complete",
            "analysis": {
                "path": self.analysis.relative_to(self.root).as_posix(),
                "sha256": MODULE.sha256(self.analysis),
            },
            "analysis_inputs": [
                {
                    "role": "original_video",
                    "path": self.video.relative_to(self.root).as_posix(),
                    "sha256": MODULE.sha256(self.video),
                },
                {
                    "role": "one_second_analysis_surface",
                    "path": self.one_second.relative_to(self.root).as_posix(),
                    "sha256": MODULE.sha256(self.one_second),
                },
            ],
            "coverage_summary": "0–42초 전체",
            "missing_analysis": [],
            "authorship_boundary": (
                "analysis_prose_is_human_or_assigned_model_authored_source_hub_is_canonical_owner"
            ),
        }
        existing = {
            "sources": [
                {
                    "source_key": "youtube:TEST123",
                    "analysis_records": [record],
                }
            ]
        }
        registry, errors = MODULE.build_registry(self.root, existing)
        self.assertEqual([], errors)
        source = registry["sources"][0]
        self.assertEqual("detailed_analysis_available", source["analysis_state"])
        read_first = MODULE.render_read_first(registry)
        self.assertIn("상세 분석 있음", read_first)
        self.assertIn("analysis/source-scene-reading-v2/first-read-v2.md", read_first)

    def test_complete_structure_rejects_missing_headings(self):
        self.analysis.write_text("# Incomplete\n### 0–8초\nonly one row\n", encoding="utf-8")
        errors = MODULE.check_analysis_structure(self.analysis, "complete")
        self.assertGreaterEqual(len(errors), 6)

    def complete_record(self):
        return {
            "analysis_id": "TEST_WHOLE_FLOW_V1",
            "owner_scope": "source_materials_video_source",
            "authoring_stage": "source_first_read",
            "status": "complete",
            "analysis": {
                "path": self.analysis.relative_to(self.root).as_posix(),
                "sha256": MODULE.sha256(self.analysis),
            },
            "analysis_inputs": [
                {
                    "role": "original_video",
                    "path": self.video.relative_to(self.root).as_posix(),
                    "sha256": MODULE.sha256(self.video),
                },
                {
                    "role": "one_second_analysis_surface",
                    "path": self.one_second.relative_to(self.root).as_posix(),
                    "sha256": MODULE.sha256(self.one_second),
                },
            ],
            "coverage_summary": "0–42초 전체",
            "missing_analysis": [],
            "authorship_boundary": (
                "analysis_prose_is_human_or_assigned_model_authored_source_hub_is_canonical_owner"
            ),
        }

    def test_stale_analysis_and_input_sha256_are_rejected(self):
        stale_analysis = self.complete_record()
        stale_analysis["analysis"]["sha256"] = "0" * 64
        _, errors = MODULE.build_registry(
            self.root,
            {"sources": [{"source_key": "youtube:TEST123", "analysis_records": [stale_analysis]}]},
        )
        self.assertTrue(any("stale analysis sha256" in item for item in errors))
        stale_input = self.complete_record()
        stale_input["analysis_inputs"][0]["sha256"] = "0" * 64
        _, errors = MODULE.build_registry(
            self.root,
            {"sources": [{"source_key": "youtube:TEST123", "analysis_records": [stale_input]}]},
        )
        self.assertTrue(any("stale input sha256" in item for item in errors))

    def test_duplicate_ids_are_hold(self):
        record = self.complete_record()
        _, errors = MODULE.build_registry(
            self.root,
            {
                "sources": [
                    {
                        "source_key": "youtube:TEST123",
                        "analysis_records": [record, dict(record)],
                    },
                    {"source_key": "youtube:TEST123", "analysis_records": []},
                ]
            },
        )
        self.assertTrue(any("duplicate analysis_id" in item for item in errors))
        self.assertTrue(any("duplicate source_key" in item for item in errors))

    def test_missing_manifest_holds_even_when_analysis_records_empty(self):
        existing = {
            "sources": [
                {
                    "source_key": "youtube:GONE",
                    "title": "keep metadata",
                    "duration_seconds": 12.0,
                    "analysis_state": "not_analyzed",
                    "analysis_records": [],
                }
            ]
        }
        _, errors = MODULE.build_registry(self.root, existing)
        self.assertTrue(any("HOLD missing_source: youtube:GONE" in item for item in errors))

    def test_hold_incomplete_is_preserved(self):
        record = self.complete_record()
        record["status"] = "hold_incomplete"
        record["coverage_summary"] = "partial hold"
        record["missing_analysis"] = ["whole-source flow"]
        registry, errors = MODULE.build_registry(
            self.root,
            {"sources": [{"source_key": "youtube:TEST123", "analysis_records": [record]}]},
        )
        self.assertEqual([], errors)
        kept = registry["sources"][0]["analysis_records"][0]
        self.assertEqual("hold_incomplete", kept["status"])
        self.assertEqual("partial hold", kept["coverage_summary"])
        self.assertEqual(["whole-source flow"], kept["missing_analysis"])
        self.assertNotIn("disposition", kept)

    def test_canonical_publication_holds_after_mtime_preserving_video_rewrite(self):
        record = self.complete_record()
        hasher = HashBinder(self.root, profile="canonical_gate")
        existing = {
            "sources": [{"source_key": "youtube:TEST123", "analysis_records": [record]}]
        }
        registry, errors = MODULE.build_registry(self.root, existing, hasher=hasher)
        self.assertEqual([], errors)
        stat = self.video.stat()
        self.video.write_bytes(b"video-evidencX")
        os.utime(self.video, ns=(stat.st_atime_ns, stat.st_mtime_ns))
        holds = hasher.verify_publication()
        self.assertTrue(any("HOLD snapshot_inconsistent" in item for item in holds))
        self.assertTrue(
            any(
                "input snapshot changed before publication" in item
                or "bytes changed since bind" in item
                for item in holds
            )
        )
        self.assertFalse(hasher.report()["durable_cache_used_for_binding"])
        self.assertEqual(registry["sources"][0]["analysis_state"], "detailed_analysis_available")

    def test_repeat_cache_hit_is_not_the_canonical_binding(self):
        record = self.complete_record()
        cache = IntegrityCache(self.root)
        before = cache.inspect(self.video, "repeat_local_validation")
        stat = self.video.stat()
        self.video.write_bytes(b"video-evidencX")
        os.utime(self.video, ns=(stat.st_atime_ns, stat.st_mtime_ns))
        warm = cache.inspect(self.video, "repeat_local_validation")
        self.assertEqual("hit", warm["cache"])
        self.assertEqual(before["value"], warm["value"])
        hasher = HashBinder(self.root, profile="canonical_gate")
        registry, errors = MODULE.build_registry(
            self.root,
            {"sources": [{"source_key": "youtube:TEST123", "analysis_records": [record]}]},
            hasher=hasher,
        )
        self.assertTrue(any("stale input sha256" in item for item in errors))
        bound = registry["sources"][0]["primary_media"]["sha256"]
        self.assertNotEqual(bound, warm["value"])

    def test_escaped_symlink_input_and_registry_are_rejected(self):
        outside = tempfile.TemporaryDirectory(prefix="idol-analysis-outside-")
        try:
            secret = Path(outside.name) / "secret.mp4"
            secret.write_bytes(b"OUTSIDE-VIDEO-BYTES")
            link = self.source_root / "videos" / "escape.mp4"
            link.symlink_to(secret)
            record = self.complete_record()
            record["analysis_inputs"][0]["path"] = link.relative_to(self.root).as_posix()
            record["analysis_inputs"][0]["sha256"] = "0" * 64
            _, errors = MODULE.build_registry(
                self.root,
                {"sources": [{"source_key": "youtube:TEST123", "analysis_records": [record]}]},
            )
            self.assertTrue(any("inside repository" in item for item in errors))
            escaped_registry = Path(outside.name) / "secret-registry.yaml"
            escaped_registry.write_text("secret: 1\n", encoding="utf-8")
            dest = self.root / MODULE.REGISTRY_REL
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.symlink_to(escaped_registry)
            args = argparse.Namespace(
                repo_root=str(self.root), integrity_profile="canonical_gate"
            )
            self.assertEqual(1, MODULE.command_sync(args))
        finally:
            outside.cleanup()

    def test_verify_read_first_identity_includes_sequence_units(self):
        record = self.complete_record()
        existing = {
            "sources": [{"source_key": "youtube:TEST123", "analysis_records": [record]}]
        }
        registry, errors = MODULE.build_registry(self.root, existing)
        self.assertEqual([], errors)
        unit_registry_path = (
            self.root / "source-materials/video-sources/sequence-unit-registry.yaml"
        )
        unit_registry_path.write_text(
            yaml.safe_dump(
                {
                    "schema_version": "idol_video_reference_sequence_unit_registry.v1",
                    "artifact_type": "sequence_unit_pointer_registry",
                    "registry_path": "source-materials/video-sources/sequence-unit-registry.yaml",
                    "units": [
                        {
                            "source_sequence_unit_id": "SU_01",
                            "source_key": "youtube:TEST123",
                            "source_time_range": "12-16",
                            "purpose_classes": ["visible_action_or_hold"],
                            "batch_pointer": {
                                "path": (
                                    "source-materials/video-sources/youtube/by-source/"
                                    "TEST123/analysis/reusable-sequence-units-v1.yaml"
                                ),
                                "sha256": "a" * 64,
                            },
                        }
                    ],
                },
                sort_keys=False,
            ),
            encoding="utf-8",
        )
        hasher = HashBinder(self.root, profile="canonical_gate")
        publish_errors = MODULE.write_registry_and_readme(
            registry,
            self.root,
            hasher=hasher,
            previous_registry=None,
            previous_readme=None,
        )
        self.assertEqual([], publish_errors)
        readme = (self.root / MODULE.READ_FIRST_REL).read_text(encoding="utf-8")
        self.assertIn("재사용 Sequence Units", readme)
        self.assertIn("SU_01", readme)
        self.assertEqual(readme, MODULE.render_read_first(registry, root=self.root))
        self.assertNotEqual(readme, MODULE.render_read_first(registry))
        args = argparse.Namespace(
            repo_root=str(self.root), integrity_profile="canonical_gate"
        )
        self.assertEqual(0, MODULE.command_verify(args))

    def test_canonical_binder_memos_repeat_path_in_one_operation(self):
        record = self.complete_record()
        hasher = HashBinder(self.root, profile="canonical_gate")
        _, errors = MODULE.build_registry(
            self.root,
            {"sources": [{"source_key": "youtube:TEST123", "analysis_records": [record]}]},
            hasher=hasher,
        )
        self.assertEqual([], errors)
        report = hasher.report()
        self.assertGreaterEqual(report["memo_hits"], 1)
        self.assertFalse(report["durable_cache_used_for_binding"])

    def test_repeat_local_validation_diagnostic_reports_disagreement_after_cache_save(self):
        record = self.complete_record()
        existing = {
            "sources": [{"source_key": "youtube:TEST123", "analysis_records": [record]}]
        }
        cache = IntegrityCache(self.root)
        before = cache.inspect(self.video, "repeat_local_validation")
        cache.save()
        stat = self.video.stat()
        self.video.write_bytes(b"video-evidencX")
        os.utime(self.video, ns=(stat.st_atime_ns, stat.st_mtime_ns))
        hasher = HashBinder(self.root, profile="repeat_local_validation")
        registry, errors = MODULE.build_registry(self.root, existing, hasher=hasher)
        report = hasher.report()
        self.assertEqual("repeat_local_validation", report["profile"])
        self.assertEqual("canonical_gate", report["write_binding"])
        self.assertFalse(report["durable_cache_used_for_binding"])
        self.assertGreaterEqual(report["diagnostic_disagreements_with_fresh"], 1)
        self.assertTrue(any("stale input sha256" in item for item in errors))
        self.assertNotEqual(
            registry["sources"][0]["primary_media"]["sha256"], before["value"]
        )

    def test_generated_registry_schema_holds_malformed_status(self):
        record = self.complete_record()
        record["status"] = "bogus"
        _, errors = MODULE.build_registry(
            self.root,
            {"sources": [{"source_key": "youtube:TEST123", "analysis_records": [record]}]},
        )
        self.assertTrue(any("HOLD malformed_registry" in item for item in errors))

    def test_sync_then_verify_is_idempotent_with_markdown_punctuation(self):
        document = yaml.safe_load(self.manifest.read_text(encoding="utf-8"))
        document["title"] = "Title: colon|pipe"
        self.manifest.write_text(yaml.safe_dump(document, sort_keys=False), encoding="utf-8")
        record = self.complete_record()
        registry, errors = MODULE.build_registry(
            self.root,
            {"sources": [{"source_key": "youtube:TEST123", "analysis_records": [record]}]},
        )
        self.assertEqual([], errors)
        hasher = HashBinder(self.root, profile="canonical_gate")
        publish_errors = MODULE.write_registry_and_readme(
            registry,
            self.root,
            hasher=hasher,
            previous_registry=None,
            previous_readme=None,
        )
        self.assertEqual([], publish_errors)
        args = argparse.Namespace(
            repo_root=str(self.root), integrity_profile="canonical_gate"
        )
        unanalysed_root = (
            self.root
            / "source-materials"
            / "video-sources"
            / "youtube"
            / "by-source"
            / "TEST456"
        )
        (unanalysed_root / "videos").mkdir(parents=True)
        unanalysed_video = unanalysed_root / "videos" / "TEST456.mp4"
        unanalysed_video.write_bytes(b"video-unanalysed")
        (unanalysed_root / "source-manifest.yaml").write_text(
            yaml.safe_dump(
                {
                    "identity": {
                        "platform": "youtube",
                        "platform_id": "TEST456",
                        "normalized_url": "https://www.youtube.com/watch?v=TEST456",
                        "source_key": "youtube:TEST456",
                    },
                    "title": "Table: colon|pipe",
                    "media": [
                        {
                            "kind": "video",
                            "path": unanalysed_video.relative_to(self.root).as_posix(),
                        }
                    ],
                    "discovery_metadata": {"duration_seconds": 12.0},
                },
                sort_keys=False,
            ),
            encoding="utf-8",
        )
        self.assertEqual(0, MODULE.command_sync(args))
        self.assertEqual(0, MODULE.command_verify(args))
        self.assertEqual(0, MODULE.command_sync(args))
        readme = (self.root / MODULE.READ_FIRST_REL).read_text(encoding="utf-8")
        self.assertIn("### Title: colon|pipe", readme)
        self.assertIn("| `youtube:TEST456` | Table: colon\\|pipe | 12.0초 | 미분석 |", readme)
        self.assertNotIn("HOLD escaped_path", readme)

    def test_second_write_failure_leaves_canonical_pending_derived_then_recovers(self):
        record = self.complete_record()
        existing = {
            "sources": [{"source_key": "youtube:TEST123", "analysis_records": [record]}]
        }
        registry, errors = MODULE.build_registry(self.root, existing)
        self.assertEqual([], errors)
        hasher = HashBinder(self.root, profile="canonical_gate")
        import lib.idol_artifact_integrity as integrity_mod
        real = integrity_mod.os.replace
        count = {"n": 0}

        def flaky(src, dst, *args, **kwargs):
            count["n"] += 1
            if count["n"] >= 2:
                raise OSError("injected second write failure")
            return real(src, dst, *args, **kwargs)

        integrity_mod.os.replace = flaky
        try:
            publish_errors = MODULE.write_registry_and_readme(
                registry,
                self.root,
                hasher=hasher,
                previous_registry=None,
                previous_readme=None,
            )
        finally:
            integrity_mod.os.replace = real
        self.assertTrue(
            any("derived_publication_incomplete" in item for item in publish_errors)
            or any("publication_write_failed" in item for item in publish_errors)
        )
        registry_path = self.root / MODULE.REGISTRY_REL
        readme_path = self.root / MODULE.READ_FIRST_REL
        self.assertTrue(registry_path.is_file())
        self.assertFalse(readme_path.exists())
        args = argparse.Namespace(
            repo_root=str(self.root), integrity_profile="canonical_gate"
        )
        self.assertEqual(1, MODULE.command_verify(args))
        hasher2 = HashBinder(self.root, profile="canonical_gate")
        recovered = MODULE.write_registry_and_readme(
            registry,
            self.root,
            hasher=hasher2,
            previous_registry=None,
            previous_readme=None,
        )
        self.assertEqual([], recovered)
        self.assertEqual(
            readme_path.read_text(encoding="utf-8"),
            MODULE.render_read_first(registry, root=self.root),
        )
        self.assertEqual(0, MODULE.command_verify(args))

    def test_concurrent_readme_change_is_not_overwritten(self):
        record = self.complete_record()
        existing = {
            "sources": [{"source_key": "youtube:TEST123", "analysis_records": [record]}]
        }
        registry, errors = MODULE.build_registry(self.root, existing)
        self.assertEqual([], errors)
        hasher = HashBinder(self.root, profile="canonical_gate")
        self.assertEqual(
            [],
            MODULE.write_registry_and_readme(
                registry,
                self.root,
                hasher=hasher,
                previous_registry=None,
                previous_readme=None,
            ),
        )
        registry_path = self.root / MODULE.REGISTRY_REL
        readme_path = self.root / MODULE.READ_FIRST_REL
        previous_registry = registry_path.read_text(encoding="utf-8")
        previous_readme = readme_path.read_text(encoding="utf-8")
        readme_path.write_text("foreign-concurrent\n", encoding="utf-8")
        hasher2 = HashBinder(self.root, profile="canonical_gate")
        held = MODULE.write_registry_and_readme(
            registry,
            self.root,
            hasher=hasher2,
            previous_registry=previous_registry,
            previous_readme=previous_readme,
        )
        self.assertTrue(any("concurrent_output_change" in item for item in held))
        self.assertEqual("foreign-concurrent\n", readme_path.read_text(encoding="utf-8"))
        self.assertEqual(previous_registry, registry_path.read_text(encoding="utf-8"))
        self.assertEqual(1, MODULE.command_verify(args := argparse.Namespace(
            repo_root=str(self.root), integrity_profile="canonical_gate"
        )))

    def test_write_registry_and_readme_normal_idempotence(self):
        record = self.complete_record()
        existing = {
            "sources": [{"source_key": "youtube:TEST123", "analysis_records": [record]}]
        }
        registry, errors = MODULE.build_registry(self.root, existing)
        self.assertEqual([], errors)
        hasher = HashBinder(self.root, profile="canonical_gate")
        first = MODULE.write_registry_and_readme(
            registry,
            self.root,
            hasher=hasher,
            previous_registry=None,
            previous_readme=None,
        )
        self.assertEqual([], first)
        registry_path = self.root / MODULE.REGISTRY_REL
        readme_path = self.root / MODULE.READ_FIRST_REL
        previous_registry = registry_path.read_text(encoding="utf-8")
        previous_readme = readme_path.read_text(encoding="utf-8")
        hasher2 = HashBinder(self.root, profile="canonical_gate")
        second = MODULE.write_registry_and_readme(
            registry,
            self.root,
            hasher=hasher2,
            previous_registry=previous_registry,
            previous_readme=previous_readme,
        )
        self.assertEqual([], second)
        self.assertEqual(previous_registry, registry_path.read_text(encoding="utf-8"))
        self.assertEqual(previous_readme, readme_path.read_text(encoding="utf-8"))
        args = argparse.Namespace(
            repo_root=str(self.root), integrity_profile="canonical_gate"
        )
        self.assertEqual(0, MODULE.command_verify(args))

    def test_analysis_ids_remain_case_sensitive(self):
        first = self.complete_record()
        first["analysis_id"] = "AbC-id"
        second = self.complete_record()
        second["analysis_id"] = "abc-id"
        registry, errors = MODULE.build_registry(
            self.root,
            {
                "sources": [
                    {
                        "source_key": "youtube:TEST123",
                        "analysis_records": [first, second],
                    }
                ]
            },
        )
        self.assertEqual([], errors)
        ids = [row["analysis_id"] for row in registry["sources"][0]["analysis_records"]]
        self.assertEqual(["AbC-id", "abc-id"], ids)

    def test_verify_symlink_lock_does_not_invent_stale_reason(self):
        record = self.complete_record()
        existing = {
            "sources": [{"source_key": "youtube:TEST123", "analysis_records": [record]}]
        }
        registry, errors = MODULE.build_registry(self.root, existing)
        self.assertEqual([], errors)
        hasher = HashBinder(self.root, profile="canonical_gate")
        self.assertEqual(
            [],
            MODULE.write_registry_and_readme(
                registry,
                self.root,
                hasher=hasher,
                previous_registry=None,
                previous_readme=None,
            ),
        )
        lock = publication_lock_path(self.root / MODULE.REGISTRY_REL)
        outside = tempfile.TemporaryDirectory()
        try:
            target = Path(outside.name) / "lock-target"
            target.write_text("x\n", encoding="utf-8")
            if lock.is_symlink() or lock.exists():
                lock.unlink()
            lock.symlink_to(target)
            args = argparse.Namespace(
                repo_root=str(self.root), integrity_profile="canonical_gate"
            )
            buf = io.StringIO()
            with contextlib.redirect_stderr(buf):
                code = MODULE.command_verify(args)
            text = buf.getvalue()
            self.assertEqual(1, code)
            self.assertIn("HOLD escaped_path", text)
            self.assertNotIn("READ-FIRST.md is stale", text)
            self.assertNotIn("changed during verify", text)
        finally:
            outside.cleanup()

    def scoped_prose(self) -> str:
        return "\n".join(
            [
                "## 분석에 실제로 사용한 자료",
                "video and extraction",
                "      cell_or_frame_locator: 10.000 sheet-001-cell-0001",
                "      cell_or_frame_locator: 12.000 sheet-001-cell-0003",
                "      cell_locator: 14.000",
                "## 공용 관찰에서 허용하는 전이 경계",
                "reuse grammar only",
                "## 공용 관찰에서 제외하는 전이 경계",
                "source identity",
            ]
        )

    def write_extraction(self, name: str, start: float, end: float, interval: float = 1.0) -> Path:
        path = self.source_root / "analysis" / name
        path.parent.mkdir(parents=True, exist_ok=True)
        stamps = []
        stamp = start
        while stamp <= end + 0.0001:
            stamps.append(stamp)
            stamp += interval
        path.write_text(
            json.dumps(
                {
                    "schema_version": "idol_video_qc_sheet_manifest.v1",
                    "source_video": {
                        "path": self.video.relative_to(self.root).as_posix(),
                        "sha256": MODULE.sha256(self.video),
                    },
                    "interval_seconds": interval,
                    "sheets": [{"timestamps": stamps}],
                }
            ),
            encoding="utf-8",
        )
        return path

    def test_complete_accepts_structured_locator_timestamps(self):
        self.analysis.write_text(
            "\n".join(
                [
                    "## 분석에 실제로 사용한 자료",
                    "## 영상 전체의 큰 흐름",
                    "## 상세 장면 기록",
                    "      cell_or_frame_locator: 14.000 sheet-001-cell-0001",
                    "      cell_or_frame_locator: 15.000 sheet-001-cell-0002",
                    "      cell_locator: 16.000",
                    "## 공용 관찰에서 허용하는 전이 경계",
                    "## 공용 관찰에서 제외하는 전이 경계",
                ]
            ),
            encoding="utf-8",
        )
        self.assertEqual([], MODULE.check_analysis_structure(self.analysis, "complete"))

    def test_scoped_only_stays_not_analyzed_and_holds_without_parent(self):
        scoped = self.source_root / "analysis" / "scoped.md"
        scoped.write_text(self.scoped_prose(), encoding="utf-8")
        extraction = self.write_extraction("window.json", 10.0, 14.0)
        foreign = self.source_root / "analysis" / "foreign.md"
        foreign.write_text("foreign parent\n", encoding="utf-8")
        record = {
            "analysis_id": "TEST_SCOPED_ONLY_V1",
            "owner_scope": "source_materials_video_source",
            "authoring_stage": "source_scoped_supplement",
            "status": "complete_scoped",
            "analysis": {
                "path": scoped.relative_to(self.root).as_posix(),
                "sha256": MODULE.sha256(scoped),
            },
            "analysis_inputs": [
                {
                    "role": "original_video",
                    "path": self.video.relative_to(self.root).as_posix(),
                    "sha256": MODULE.sha256(self.video),
                },
                {
                    "role": "parent_complete_analysis",
                    "path": foreign.relative_to(self.root).as_posix(),
                    "sha256": MODULE.sha256(foreign),
                },
                {
                    "role": "one_second_analysis_surface",
                    "path": extraction.relative_to(self.root).as_posix(),
                    "sha256": MODULE.sha256(extraction),
                },
            ],
            "coverage_summary": "10-14 only",
            "missing_analysis": [],
            "covered_ranges": [{"start_seconds": 10.0, "end_seconds": 14.0}],
            "authorship_boundary": (
                "analysis_prose_is_human_or_assigned_model_authored_"
                "source_hub_is_canonical_owner"
            ),
        }
        registry, errors = MODULE.build_registry(
            self.root,
            {"sources": [{"source_key": "youtube:TEST123", "analysis_records": [record]}]},
        )
        self.assertTrue(any("parent_complete_analysis" in item for item in errors))
        self.assertEqual("not_analyzed", registry["sources"][0]["analysis_state"])
        self.assertNotEqual("detailed_analysis_available", registry["sources"][0]["analysis_state"])

    def test_register_accepts_valid_scoped_and_keeps_ordinary_complete(self):
        hasher = HashBinder(self.root, profile="canonical_gate")
        complete = self.complete_record()
        registry, errors = MODULE.build_registry(
            self.root,
            {"sources": [{"source_key": "youtube:TEST123", "analysis_records": [complete]}]},
        )
        self.assertEqual([], errors)
        self.assertEqual("detailed_analysis_available", registry["sources"][0]["analysis_state"])
        self.assertEqual(
            [],
            MODULE.write_registry_and_readme(
                registry,
                self.root,
                hasher=hasher,
                previous_registry=None,
                previous_readme=None,
            ),
        )
        scoped = self.source_root / "analysis" / "scoped.md"
        scoped.write_text(self.scoped_prose(), encoding="utf-8")
        extraction = self.write_extraction("window.json", 10.0, 14.0)
        args = argparse.Namespace(
            repo_root=str(self.root),
            integrity_profile="canonical_gate",
            source_manifest=self.manifest.relative_to(self.root).as_posix(),
            analysis=scoped.relative_to(self.root).as_posix(),
            analysis_id="TEST_SCOPED_WINDOW_V1",
            authoring_stage="source_scoped_supplement",
            status="complete_scoped",
            coverage_summary="10-14 only",
            missing_analysis=[],
            covered_range=["10.000,14.000"],
            input=[
                f"original_video={self.video.relative_to(self.root).as_posix()}",
                f"parent_complete_analysis={self.analysis.relative_to(self.root).as_posix()}",
                f"one_second_analysis_surface={extraction.relative_to(self.root).as_posix()}",
            ],
        )
        self.assertEqual(0, MODULE.command_register(args))
        rebuilt, rebuilt_errors = MODULE.build_registry(
            self.root,
            yaml.safe_load((self.root / MODULE.REGISTRY_REL).read_text(encoding="utf-8")),
        )
        self.assertEqual([], rebuilt_errors)
        self.assertEqual("detailed_analysis_available", rebuilt["sources"][0]["analysis_state"])
        statuses = {row["status"] for row in rebuilt["sources"][0]["analysis_records"]}
        self.assertEqual({"complete", "complete_scoped"}, statuses)

    def test_register_and_build_reject_invalid_scope(self):
        hasher = HashBinder(self.root, profile="canonical_gate")
        complete = self.complete_record()
        registry, errors = MODULE.build_registry(
            self.root,
            {"sources": [{"source_key": "youtube:TEST123", "analysis_records": [complete]}]},
        )
        self.assertEqual([], errors)
        MODULE.write_registry_and_readme(
            registry,
            self.root,
            hasher=hasher,
            previous_registry=None,
            previous_readme=None,
        )
        scoped = self.source_root / "analysis" / "scoped.md"
        scoped.write_text(self.scoped_prose(), encoding="utf-8")
        extraction = self.write_extraction("window.json", 10.0, 14.0)
        other_video = self.source_root / "videos" / "other.mp4"
        other_video.write_bytes(b"other-video")
        base = dict(
            repo_root=str(self.root),
            integrity_profile="canonical_gate",
            source_manifest=self.manifest.relative_to(self.root).as_posix(),
            analysis=scoped.relative_to(self.root).as_posix(),
            analysis_id="TEST_SCOPED_BAD_V1",
            authoring_stage="source_scoped_supplement",
            status="complete_scoped",
            coverage_summary="bad",
            missing_analysis=[],
            input=[
                f"original_video={self.video.relative_to(self.root).as_posix()}",
                f"parent_complete_analysis={self.analysis.relative_to(self.root).as_posix()}",
                f"one_second_analysis_surface={extraction.relative_to(self.root).as_posix()}",
            ],
        )
        negative = argparse.Namespace(**base, covered_range=["-1,4"])
        self.assertEqual(1, MODULE.command_register(negative))
        over = argparse.Namespace(**base, covered_range=["40.000,50.000"])
        self.assertEqual(1, MODULE.command_register(over))
        scattered = self.write_extraction("scattered.json", 10.0, 14.0)
        payload = json.loads(scattered.read_text(encoding="utf-8"))
        payload["sheets"] = [{"timestamps": [10.0, 12.0, 40.0, 41.0, 42.0]}]
        scattered.write_text(json.dumps(payload), encoding="utf-8")
        bad_extract = argparse.Namespace(
            **{
                **base,
                "covered_range": ["10.000,14.000"],
                "input": [
                    f"original_video={self.video.relative_to(self.root).as_posix()}",
                    f"parent_complete_analysis={self.analysis.relative_to(self.root).as_posix()}",
                    f"one_second_analysis_surface={scattered.relative_to(self.root).as_posix()}",
                ],
            }
        )
        self.assertEqual(1, MODULE.command_register(bad_extract))
        wrong_video = argparse.Namespace(
            **{
                **base,
                "covered_range": ["10.000,14.000"],
                "input": [
                    f"original_video={other_video.relative_to(self.root).as_posix()}",
                    f"parent_complete_analysis={self.analysis.relative_to(self.root).as_posix()}",
                    f"one_second_analysis_surface={extraction.relative_to(self.root).as_posix()}",
                ],
            }
        )
        self.assertEqual(1, MODULE.command_register(wrong_video))
        bool_range = {
            "analysis_id": "TEST_SCOPED_BOOL_V1",
            "owner_scope": "source_materials_video_source",
            "authoring_stage": "source_scoped_supplement",
            "status": "complete_scoped",
            "analysis": {
                "path": scoped.relative_to(self.root).as_posix(),
                "sha256": MODULE.sha256(scoped),
            },
            "analysis_inputs": [
                {
                    "role": "original_video",
                    "path": self.video.relative_to(self.root).as_posix(),
                    "sha256": MODULE.sha256(self.video),
                },
                {
                    "role": "parent_complete_analysis",
                    "path": self.analysis.relative_to(self.root).as_posix(),
                    "sha256": MODULE.sha256(self.analysis),
                },
                {
                    "role": "one_second_analysis_surface",
                    "path": extraction.relative_to(self.root).as_posix(),
                    "sha256": MODULE.sha256(extraction),
                },
            ],
            "coverage_summary": "bool",
            "missing_analysis": [],
            "covered_ranges": [{"start_seconds": True, "end_seconds": 4}],
            "authorship_boundary": (
                "analysis_prose_is_human_or_assigned_model_authored_"
                "source_hub_is_canonical_owner"
            ),
        }
        _, bool_errors = MODULE.build_registry(
            self.root,
            {
                "sources": [
                    {
                        "source_key": "youtube:TEST123",
                        "analysis_records": [self.complete_record(), bool_range],
                    }
                ]
            },
        )
        self.assertTrue(any("covered_ranges" in item for item in bool_errors))

    def test_scoped_rejects_ambiguous_same_source_parent(self):
        scoped = self.source_root / "analysis" / "scoped.md"
        scoped.write_text(self.scoped_prose(), encoding="utf-8")
        extraction = self.write_extraction("window.json", 10.0, 14.0)
        complete = self.complete_record()
        held = dict(complete)
        held["analysis_id"] = "TEST_HELD_SAME_BYTES"
        held["status"] = "hold_incomplete"
        scoped_record = {
            "analysis_id": "TEST_SCOPED_AMBIGUOUS_PARENT_V1",
            "owner_scope": "source_materials_video_source",
            "authoring_stage": "source_scoped_supplement",
            "status": "complete_scoped",
            "analysis": {
                "path": scoped.relative_to(self.root).as_posix(),
                "sha256": MODULE.sha256(scoped),
            },
            "analysis_inputs": [
                {
                    "role": "original_video",
                    "path": self.video.relative_to(self.root).as_posix(),
                    "sha256": MODULE.sha256(self.video),
                },
                {
                    "role": "parent_complete_analysis",
                    "path": complete["analysis"]["path"],
                    "sha256": complete["analysis"]["sha256"],
                },
                {
                    "role": "one_second_analysis_surface",
                    "path": extraction.relative_to(self.root).as_posix(),
                    "sha256": MODULE.sha256(extraction),
                },
            ],
            "coverage_summary": "10-14 only",
            "missing_analysis": [],
            "covered_ranges": [{"start_seconds": 10.0, "end_seconds": 14.0}],
            "authorship_boundary": (
                "analysis_prose_is_human_or_assigned_model_authored_"
                "source_hub_is_canonical_owner"
            ),
        }
        _, errors = MODULE.build_registry(
            self.root,
            {
                "sources": [
                    {
                        "source_key": "youtube:TEST123",
                        "analysis_records": [complete, held, scoped_record],
                    }
                ]
            },
        )
        self.assertTrue(any("contradictory statuses" in item for item in errors))

    def test_scoped_rejects_unavailable_duration_and_broken_extraction_json(self):
        scoped = self.source_root / "analysis" / "scoped.md"
        scoped.write_text(self.scoped_prose(), encoding="utf-8")
        extraction = self.write_extraction("window.json", 10.0, 14.0)
        complete = self.complete_record()
        scoped_record = {
            "analysis_id": "TEST_SCOPED_DURATION_V1",
            "owner_scope": "source_materials_video_source",
            "authoring_stage": "source_scoped_supplement",
            "status": "complete_scoped",
            "analysis": {
                "path": scoped.relative_to(self.root).as_posix(),
                "sha256": MODULE.sha256(scoped),
            },
            "analysis_inputs": [
                {
                    "role": "original_video",
                    "path": self.video.relative_to(self.root).as_posix(),
                    "sha256": MODULE.sha256(self.video),
                },
                {
                    "role": "parent_complete_analysis",
                    "path": complete["analysis"]["path"],
                    "sha256": complete["analysis"]["sha256"],
                },
                {
                    "role": "one_second_analysis_surface",
                    "path": extraction.relative_to(self.root).as_posix(),
                    "sha256": MODULE.sha256(extraction),
                },
            ],
            "coverage_summary": "10-14 only",
            "missing_analysis": [],
            "covered_ranges": [{"start_seconds": 10.0, "end_seconds": 14.0}],
            "authorship_boundary": (
                "analysis_prose_is_human_or_assigned_model_authored_"
                "source_hub_is_canonical_owner"
            ),
        }
        primary = {
            "path": self.video.relative_to(self.root).as_posix(),
            "sha256": MODULE.sha256(self.video),
        }
        records = [complete, scoped_record]
        missing = MODULE.validate_scoped_source(
            records,
            primary_media=primary,
            duration_seconds=None,
            root=self.root,
        )
        self.assertTrue(any("duration is unavailable" in item for item in missing))
        nonfinite = MODULE.validate_scoped_source(
            records,
            primary_media=primary,
            duration_seconds=float("nan"),
            root=self.root,
        )
        self.assertTrue(any("duration is unavailable" in item for item in nonfinite))
        as_bool = MODULE.validate_scoped_source(
            records,
            primary_media=primary,
            duration_seconds=True,
            root=self.root,
        )
        self.assertTrue(any("duration is unavailable" in item for item in as_bool))
        broken = self.source_root / "analysis" / "broken.json"
        broken.write_text("{not json", encoding="utf-8")
        broken_record = dict(scoped_record)
        broken_record["analysis_id"] = "TEST_SCOPED_BROKEN_JSON_V1"
        broken_record["analysis_inputs"] = [
            scoped_record["analysis_inputs"][0],
            scoped_record["analysis_inputs"][1],
            {
                "role": "one_second_analysis_surface",
                "path": broken.relative_to(self.root).as_posix(),
                "sha256": MODULE.sha256(broken),
            },
        ]
        broken_errors = MODULE.validate_scoped_source(
            [complete, broken_record],
            primary_media=primary,
            duration_seconds=42.0,
            root=self.root,
        )
        self.assertTrue(any("not valid JSON" in item for item in broken_errors))
        document = yaml.safe_load(self.manifest.read_text(encoding="utf-8"))
        del document["discovery_metadata"]
        self.manifest.write_text(yaml.safe_dump(document, sort_keys=False), encoding="utf-8")
        _, build_errors = MODULE.build_registry(
            self.root,
            {
                "sources": [
                    {
                        "source_key": "youtube:TEST123",
                        "analysis_records": [complete, scoped_record],
                    }
                ]
            },
        )
        self.assertTrue(any("duration is unavailable" in item for item in build_errors))

    def test_duration_seconds_bool_does_not_validate_subsecond_scoped_window(self):
        cases = (
            (True, None),
            (False, None),
            (float("nan"), None),
            (float("inf"), None),
            (float("-inf"), None),
            (0, None),
            (-1, None),
            (0.5, 0.5),
            (1, 1.0),
            (42.0, 42.0),
        )
        for raw, expected in cases:
            got = MODULE.duration_seconds({"discovery_metadata": {"duration_seconds": raw}})
            if expected is None:
                self.assertIsNone(got, repr(raw))
            else:
                self.assertEqual(expected, got, repr(raw))
        scoped = self.source_root / "analysis" / "scoped.md"
        scoped.write_text(self.scoped_prose(), encoding="utf-8")
        extraction = self.write_extraction("subsecond.json", 0.0, 0.5, 0.25)
        complete = self.complete_record()
        scoped_record = {
            "analysis_id": "TEST_SCOPED_BOOL_DURATION_V1",
            "owner_scope": "source_materials_video_source",
            "authoring_stage": "source_scoped_supplement",
            "status": "complete_scoped",
            "analysis": {
                "path": scoped.relative_to(self.root).as_posix(),
                "sha256": MODULE.sha256(scoped),
            },
            "analysis_inputs": [
                {
                    "role": "original_video",
                    "path": self.video.relative_to(self.root).as_posix(),
                    "sha256": MODULE.sha256(self.video),
                },
                {
                    "role": "parent_complete_analysis",
                    "path": complete["analysis"]["path"],
                    "sha256": complete["analysis"]["sha256"],
                },
                {
                    "role": "one_second_analysis_surface",
                    "path": extraction.relative_to(self.root).as_posix(),
                    "sha256": MODULE.sha256(extraction),
                },
            ],
            "coverage_summary": "0-0.5 only",
            "missing_analysis": [],
            "covered_ranges": [{"start_seconds": 0.0, "end_seconds": 0.5}],
            "authorship_boundary": (
                "analysis_prose_is_human_or_assigned_model_authored_"
                "source_hub_is_canonical_owner"
            ),
        }
        existing = {
            "sources": [
                {
                    "source_key": "youtube:TEST123",
                    "analysis_records": [complete, scoped_record],
                }
            ]
        }
        document = yaml.safe_load(self.manifest.read_text(encoding="utf-8"))
        document["discovery_metadata"] = {"duration_seconds": True}
        self.manifest.write_text(yaml.safe_dump(document, sort_keys=False), encoding="utf-8")
        _, bool_duration_errors = MODULE.build_registry(self.root, existing)
        self.assertTrue(
            any("duration is unavailable" in item for item in bool_duration_errors)
        )
        document["discovery_metadata"] = {"duration_seconds": 1.0}
        self.manifest.write_text(yaml.safe_dump(document, sort_keys=False), encoding="utf-8")
        _, numeric_errors = MODULE.build_registry(self.root, existing)
        self.assertFalse(any("duration is unavailable" in item for item in numeric_errors))


if __name__ == "__main__":
    unittest.main()
