#!/usr/bin/env python3
"""Tests for the pointer-first final-delivery inventory validator."""

from __future__ import annotations

import hashlib
import importlib.util
from pathlib import Path
import shutil
import sys
import tempfile
import unittest

import yaml


REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "scripts" / "validate_final_delivery_manifest.py"
SCHEMA = REPO_ROOT / "schemas" / "final-delivery-manifest.schema.json"
SPEC = importlib.util.spec_from_file_location("validate_final_delivery_manifest", SCRIPT)
assert SPEC and SPEC.loader
VALIDATOR = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = VALIDATOR
SPEC.loader.exec_module(VALIDATOR)


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


class FinalDeliveryManifestTest(unittest.TestCase):
    def setUp(self) -> None:
        self.holder = tempfile.TemporaryDirectory()
        self.addCleanup(self.holder.cleanup)
        self.root = Path(self.holder.name)
        self.run_rel = "runs/aurora-m/one-move/RUN_001"
        self.run = self.root / self.run_rel
        self.run.mkdir(parents=True)
        (self.root / "schemas").mkdir(parents=True)
        shutil.copy2(REPO_ROOT / "schemas/package.schema.json", self.root / "schemas/package.schema.json")
        (self.run / "run-manifest.yaml").write_text(
            yaml.safe_dump(
                {
                    "schema_version": "idol-run-manifest.v1",
                    "album_key": "aurora-m",
                    "title_key": "one-move",
                    "run_id": "RUN_001",
                    "content_id": "ONE_MOVE_FINAL_001",
                    "status": "active",
                    "canonical_run_root": self.run_rel,
                    "artifact_revision_owner": "git",
                    "compatibility_authoring": "forbidden",
                },
                sort_keys=False,
            ),
            encoding="utf-8",
        )
        self.closeout = self.write(
            "review/edit-closeout.yaml",
            b"schema_version: idol_edit_qc_closeout.v3\n",
        )
        self.master = self.write("generations/video/master/final-master.mov", b"master-bytes")
        screen_node = {
            "screen_progression_map_id": "SPM_MASTER",
            "screen_progression_node_id": "SPN_MASTER_R01",
            "section_id": "S01",
            "major_scene_id": "MJ01",
            "core_cut_id": "C01",
            "branch_cut_ids": ["BC01"],
            "source_03v_cue_ids": ["03VCUE_MASTER_R01"],
            "storyline_role": "resolve",
            "observable_screen_proof": "The final master closes on the reviewed screen state.",
        }
        self.edit_map = self.write(
            "04-edit-map.yaml",
            yaml.safe_dump(
                {
                    "schema_version": "idol_edit_map.v4",
                    "content_id": "ONE_MOVE_FINAL_001",
                    "status": "qc_pass",
                    "edit_unit_screen_progression_nodes": [
                        {"edit_unit_id": "SEG_MASTER_R01", **screen_node}
                    ],
                },
                sort_keys=False,
            ).encode("utf-8"),
        )
        self.recipe = self.write(
            "generations/video/qc/final-recipe-v1.yaml",
            yaml.safe_dump(
                {
                    "schema_version": "idol_edit_recipe.v3",
                    "content_id": "ONE_MOVE_FINAL_001",
                    "timeline": [
                        {
                            "segment_id": "SEG_MASTER_R01",
                            "section_ids": ["S01"],
                            "screen_progression_node": screen_node,
                        }
                    ],
                },
                sort_keys=False,
            ).encode("utf-8"),
        )
        self.trace = {
            "schema_version": "idol_05_production_graph_trace.v1",
            "source_edit_map": {
                "artifact_type": "edit_map",
                "schema_version": "idol_edit_map.v4",
                "path": self.relative(self.edit_map),
                "sha256": digest(self.edit_map),
                "json_pointer": "/edit_unit_screen_progression_nodes",
            },
            "source_edit_recipe": {
                "artifact_type": "edit_recipe",
                "schema_version": "idol_edit_recipe.v3",
                "path": self.relative(self.recipe),
                "sha256": digest(self.recipe),
                "json_pointer": "/timeline",
            },
            "deliverable_bindings": [
                {
                    "output_id": "OUT_MASTER",
                    "edit_segment_ids": ["SEG_MASTER_R01"],
                    "screen_progression_node_ids": ["SPN_MASTER_R01"],
                    "section_ids": ["S01"],
                }
            ],
            "post05_mutation_boundary": (
                "post05_release_and_analytics_are_append_only_evidence_"
                "and_never_mutate_mv_truth"
            ),
        }
        self.package = self.write(
            "05-package.yaml",
            yaml.safe_dump(
                {
                    "schema_version": "idol_package.v2",
                    "content_id": "ONE_MOVE_FINAL_001",
                    "status": "packaged_ready_local",
                    "created_at_kst": "2026-07-30T09:00:00+09:00",
                    "created_by": "test",
                    "source_contracts": {"edit_map": self.relative(self.edit_map)},
                    "final_master": {
                        "output_id": "OUT_MASTER",
                        "path": self.relative(self.master),
                        "sha256": digest(self.master),
                        "role": "final_public_master",
                    },
                    "production_graph_trace": self.trace,
                    "deliverable_policy": {
                        "master_release_source": "OUT_MASTER",
                        "social_clip_source": "OUT_MASTER",
                        "raw_source_upload_policy": "never upload raw source",
                    },
                    "approval_gates": {
                        "local_final_master": "hash verified",
                        "public_release": "Founder approval required",
                        "upload_or_schedule": "Founder approval required",
                        "external_sync": "Founder approval required",
                    },
                },
                sort_keys=False,
            ).encode("utf-8"),
        )
        self.source = self.write(
            "generations/branch-cuts/S00/BC001/original.png",
            b"original-image-bytes",
        )
        self.prompt = self.write("02B-prompt-packets.yaml", b"schema_version: '2.1'\n")
        self.reference = self.root / "source-materials" / "video-sources" / "youtube" / "by-source" / "source-a" / "source-manifest.yaml"
        self.reference.parent.mkdir(parents=True)
        self.reference.write_bytes(b"schema_version: source.v1\n")
        self.manifest = self.run / "package" / "final-delivery" / "manifest.yaml"
        self.manifest.parent.mkdir(parents=True)
        self.document = self.make_document()
        self.write_manifest()

    def write(self, relative: str, payload: bytes) -> Path:
        path = self.run / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(payload)
        return path

    def relative(self, path: Path) -> str:
        return path.relative_to(self.root).as_posix()

    def binding(self, path: Path, schema_version: str, status: str) -> dict[str, object]:
        return {
            "path": self.relative(path),
            "sha256": digest(path),
            "size_bytes": path.stat().st_size,
            "schema_version": schema_version,
            "status": status,
        }

    def make_document(self) -> dict[str, object]:
        return {
            "schema_version": "idol-final-delivery-manifest.v2",
            "content_id": "ONE_MOVE_FINAL_001",
            "run_root": self.run_rel,
            "status": "inventory_complete",
            "purpose": "final_delivery_and_final_used_original_inventory",
            "updated_at": "2026-07-30T00:00:00Z",
            "source_contracts": {
                "edit_closeout": self.binding(
                    self.closeout,
                    "idol_edit_qc_closeout.v3",
                    "ready_for_05",
                ),
                "package": self.binding(
                    self.package,
                    "idol_package.v2",
                    "packaged_ready_local",
                ),
            },
            "deliverables": [
                {
                    "artifact_id": "MASTER",
                    "package_output_id": "OUT_MASTER",
                    "role": "quality_master",
                    "media_type": "video",
                    "path": self.relative(self.master),
                    "sha256": digest(self.master),
                    "size_bytes": self.master.stat().st_size,
                    "canonical_owner": True,
                    "derived_from_artifact_ids": ["BC001"],
                }
            ],
            "production_graph_trace": {
                "package_json_pointer": "/production_graph_trace",
                "package_trace_schema_version": "idol_05_production_graph_trace.v1",
                "source_value_sha256": VALIDATOR.canonical_object_sha256(
                    VALIDATOR.normalize_production_graph_trace(self.trace)
                ),
                "mutation_boundary": (
                    "final_delivery_and_post05_are_evidence_only_and_never_"
                    "mutate_05_or_04_truth"
                ),
            },
            "used_originals": [
                {
                    "source_id": "BC001",
                    "source_class": "generated_branch_cut_image",
                    "media_type": "image",
                    "path": self.relative(self.source),
                    "sha256": digest(self.source),
                    "size_bytes": self.source.stat().st_size,
                    "retention_reason": "used_by_final_recipe",
                    "used_by_artifact_ids": ["MASTER"],
                    "byte_preservation": "exact_original_bytes",
                }
            ],
            "reference_dependencies": [
                {
                    **self.binding(self.reference, "source.v1", "registered"),
                    "source_identity": "youtube:source-a",
                    "role": "source_manifest",
                }
            ],
            "lineage_records": [
                {
                    **self.binding(self.prompt, "2.1", "passed"),
                    "record_type": "prompt_packet",
                }
            ],
            "derivative_slate": {
                "status": "closed",
                "planned_deliverable_ids": ["MASTER"],
                "closed_deliverable_ids": ["MASTER"],
                "unresolved_outputs": [],
            },
            "quality_preservation": {
                "original_generated_image_bytes_preserved": True,
                "final_used_raw_video_bytes_preserved": True,
                "lossy_proxy_is_not_only_keeper": True,
                "final_master_is_hash_and_qc_bound": True,
                "delivery_recompression_is_derivative_only": True,
            },
            "cleanup": {
                "state": "not_requested",
                "automatic_deletion_forbidden": True,
                "reverse_reference_status": "pass",
                "cleanup_plan": None,
                "founder_approval": None,
                "cleanup_receipt": None,
            },
        }

    def write_manifest(self) -> None:
        self.manifest.write_text(
            yaml.safe_dump(self.document, sort_keys=False),
            encoding="utf-8",
        )

    def validate(self) -> list[str]:
        return VALIDATOR.validate_manifest(
            self.manifest,
            repo_root=self.root,
            schema_path=SCHEMA,
        )

    def test_complete_inventory_passes(self) -> None:
        self.assertEqual(self.validate(), [])

    def test_changed_used_original_is_held(self) -> None:
        self.source.write_bytes(b"changed-original")
        errors = self.validate()
        self.assertTrue(any("used_originals[0].sha256" in error for error in errors))

    def test_closed_slate_must_match_planned_outputs(self) -> None:
        self.document["derivative_slate"]["closed_deliverable_ids"] = []  # type: ignore[index]
        self.write_manifest()
        errors = self.validate()
        self.assertTrue(any("closed derivative_slate" in error for error in errors))

    def test_used_original_must_name_real_deliverable(self) -> None:
        self.document["used_originals"][0]["used_by_artifact_ids"] = ["MISSING"]  # type: ignore[index]
        self.write_manifest()
        errors = self.validate()
        self.assertTrue(any("unknown deliverables" in error for error in errors))

    def test_package_output_trace_digest_mismatch_is_held(self) -> None:
        self.document["production_graph_trace"]["source_value_sha256"] = "0" * 64  # type: ignore[index]
        self.write_manifest()
        errors = self.validate()
        self.assertTrue(any("does not match 05 package bytes" in error for error in errors))

    def test_package_trace_source_byte_change_is_held(self) -> None:
        self.edit_map.write_bytes(self.edit_map.read_bytes() + b"status: changed\n")
        errors = self.validate()
        self.assertTrue(any("source_edit_map SHA-256 mismatch" in error for error in errors))


if __name__ == "__main__":
    unittest.main()
