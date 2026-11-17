#!/usr/bin/env python3
"""No-network regression tests for IDOL social release safety contracts."""

from __future__ import annotations

import io
import hashlib
import json
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest import mock

import yaml


SCRIPTS = Path(__file__).resolve().parents[1]
REPO = SCRIPTS.parent
sys.path.insert(0, str(SCRIPTS))

import idol_platform_draft_upload as uploader  # noqa: E402
import idol_social_release_sync as release_sync  # noqa: E402
import validate_publishing_plan as publishing_validator  # noqa: E402
from lib.idol_social_release_contracts import (  # noqa: E402
    SocialContractError,
    canonical_object_sha256,
    package_deliverable_manifest,
    queue_approval_sha256,
    sha256_file,
    validate_approval_artifact,
    validate_package_contract,
    validate_queue_scope,
    validate_run_scope,
)


class SocialReleaseContractsTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        (self.root / "schemas").mkdir(parents=True)
        secrets_root = self.root / ".runtime/secrets"
        secrets_root.mkdir(parents=True)
        (secrets_root / "youtube-client-secret.json").write_text(
            json.dumps(
                {
                    "installed": {
                        "client_id": "offline-client-id",
                        "client_secret": "offline-client-secret",
                    }
                }
            ),
            encoding="utf-8",
        )
        (secrets_root / "youtube-token.json").write_text(
            json.dumps(
                {
                    "access_token": "offline-access-token",
                    "refresh_token": "offline-refresh-token",
                }
            ),
            encoding="utf-8",
        )
        for schema_name in (
            "platform-release-approval.schema.json",
            "social-analytics.schema.json",
            "title-output-registry.schema.json",
            "package.schema.json",
            "publishing-plan.schema.json",
            "edit-finishing-fx.schema.json",
            "edit-finishing-fx-compile-manifest.schema.json",
            "edit-render-manifest.schema.json",
        ):
            source = REPO / "schemas" / schema_name
            (self.root / "schemas" / schema_name).write_bytes(source.read_bytes())
        self.content_id = "TEST_SOCIAL_RELEASE"
        self.run_rel = f"runs/aurora-m/test-social/{self.content_id}"
        self.run = self.root / self.run_rel
        self.batch = self.run / "exports/social/batch-v1"
        self.batch.mkdir(parents=True)
        (self.run / "run-manifest.yaml").write_text(
            yaml.safe_dump(
                {
                    "schema_version": "idol-run-manifest.v1",
                    "status": "active",
                    "album_key": "aurora-m",
                    "title_key": "test-social",
                    "run_id": self.content_id,
                    "content_id": self.content_id,
                    "canonical_run_root": self.run_rel,
                    "artifact_revision_owner": "git",
                    "compatibility_authoring": "forbidden",
                },
                sort_keys=False,
            ),
            encoding="utf-8",
        )
        self.asset = self.batch / "clip-01.mp4"
        self.asset.write_bytes(b"local-no-network-video")
        self.final_lineage = self.write_final_lineage_fixture()
        self.queue = self.batch / "platform-posts.jsonl"
        self.tracker = self.batch / "draft-upload-tracker.md"
        self.log = self.batch / "platform-upload-log.jsonl"
        self.package = self.batch / "manual-upload-package"
        self.package_contract = self.run / "05-package.yaml"
        self.plan = self.run / "publishing-plan.md"
        self.registry = self.root / "catalog/albums/aurora-m/test-social/output-registry.yaml"
        self.row = {
            "post_id": f"{self.content_id}-YS-001",
            "content_id": self.content_id,
            "platform": "youtube_shorts",
            "template_type": "clip",
            "message": "Keep moving.",
            "asset_or_clip": self.asset.relative_to(self.root).as_posix(),
            "caption": "Loom Test / Clip 01",
            "hashtags": ["#Loom"],
            "scheduled_at": "2026-07-10T12:00:00+09:00",
            "status": "planned",
            "analysis_scope": "date_based",
            "delivery_mode": "platform_draft",
            "tracking_code": "L-T99-C01",
            "visible_label": "Loom Test / Clip 01",
            "draft_status": "not_uploaded",
        }
        self.api_quality_patcher = mock.patch.object(
            uploader,
            "validate_api_upload_video_row",
            side_effect=lambda row, _args: {
                "post_id": str(row.get("post_id") or ""),
                "quality_profile": "idol_api_upload_2k30_high_quality.v1",
                "quality_receipt": "exports/social/test-quality.receipt.yaml",
                "quality_receipt_sha256": "9" * 64,
                "asset_sha256": sha256_file(self.asset),
                "width": 1440,
                "height": 2560,
                "avg_frame_rate": "30/1",
                "r_frame_rate": "30/1",
                "video_codec": "h264",
                "audio_codec": "aac",
                "audio_bit_rate": 320000,
                "byte_delivery": "exact_approved_bytes_no_uploader_transcode",
                "transform_mode": "byte_identical_copy",
            },
        )
        self.api_quality_patcher.start()
        self.addCleanup(self.api_quality_patcher.stop)
        self.write_queue([self.row])
        self.package_contract.write_text(
            yaml.safe_dump(
                {
                    "schema_version": "idol_package.v2",
                    "content_id": self.content_id,
                    "status": "packaged_ready_local",
                    "created_at_kst": "2026-07-10T10:00:00+09:00",
                    "created_by": "test",
                    "source_contracts": {
                        "edit_map": self.final_lineage["edit_map"],
                        "finishing_fx_map": self.final_lineage["finishing_fx_map"],
                        "finishing_fx_compile_manifest": self.final_lineage[
                            "finishing_fx_compile_manifest"
                        ],
                        "final_render_manifest": self.final_lineage[
                            "final_render_manifest"
                        ],
                    },
                    "final_master": {
                        "output_id": "OUT_TEST_MASTER",
                        "path": self.final_lineage["final_master_path"],
                        "sha256": self.final_lineage["final_master_sha256"],
                        "role": "final_public_master",
                    },
                    "package_outputs": {
                        "short_derivatives": {
                            "output_id": "OUT_TEST_SOCIAL_SHORT",
                            "path": self.asset.relative_to(self.root).as_posix(),
                            "role": "short_derivative",
                        }
                    },
                    "production_graph_trace": {
                        "schema_version": "idol_05_production_graph_trace.v1",
                        "source_edit_map": {
                            "artifact_type": "edit_map",
                            "schema_version": "idol_edit_map.v4",
                            "path": self.final_lineage["edit_map"],
                            "sha256": self.final_lineage["edit_map_sha256"],
                            "json_pointer": "/edit_unit_screen_progression_nodes",
                        },
                        "source_edit_recipe": {
                            "artifact_type": "edit_recipe",
                            "schema_version": "idol_edit_recipe.v3",
                            "path": self.final_lineage["final_recipe"],
                            "sha256": self.final_lineage["final_recipe_sha256"],
                            "json_pointer": "/timeline",
                        },
                        "deliverable_bindings": [
                            {
                                "output_id": output_id,
                                "edit_segment_ids": ["SEG_RELEASE_R01"],
                                "screen_progression_node_ids": [
                                    "SPN_TEST_SOCIAL_RELEASE_R01"
                                ],
                                "section_ids": ["S01"],
                            }
                            for output_id in (
                                "OUT_TEST_MASTER",
                                "OUT_TEST_SOCIAL_SHORT",
                            )
                        ],
                        "post05_mutation_boundary": (
                            "post05_release_and_analytics_are_append_only_evidence_"
                            "and_never_mutate_mv_truth"
                        ),
                    },
                    "deliverable_policy": {
                        "master_release_source": "test master",
                        "social_clip_source": "declared short derivative",
                        "raw_source_upload_policy": "do not upload raw source",
                    },
                    "approval_gates": {
                        "local_final_master": "local test fixture",
                        "public_release": "requires Founder approval",
                        "upload_or_schedule": "requires Founder approval",
                        "external_sync": "requires Founder approval",
                    },
                },
                sort_keys=False,
            ),
            encoding="utf-8",
        )
        self.plan.write_text(
            "\n".join(
                [
                    f"content_id: {self.content_id}",
                    "public_group_name: Loom",
                    "public_fan_name: Harne",
                    "status: draft",
                    "created_at_kst: 2026-07-10T10:00:00+09:00",
                    "updated_at_kst: 2026-07-10T10:00:00+09:00",
                    "",
                    "## Scope",
                    "Local test.",
                    "",
                    "## Tracking Convention",
                    "Use post_id.",
                    "",
                    "## Draft Queue",
                    "",
                    "| Post ID | Platform | Draft slot KST | Clip | Caption / title |",
                    "| --- | --- | --- | --- | --- |",
                    f"| {self.row['post_id']} | youtube_shorts | 12:00 | clip-01 | Loom Test / Clip 01 |",
                    "",
                    "## Approval State",
                    "Pending.",
                    "",
                ]
            ),
            encoding="utf-8",
        )
        self.registry.parent.mkdir(parents=True)
        self.registry.write_text(
            yaml.safe_dump(
                {
                    "schema_version": "1.1",
                    "album_key": "aurora-m",
                    "title_key": "test-social",
                    "title_display_name": "Test Social",
                    "status": "active",
                    "canonical_title_root": "catalog/albums/aurora-m/test-social",
                    "content_ids": [self.content_id],
                    "source_runs": [
                        {
                            "run_root": self.run_rel,
                            "content_id": self.content_id,
                            "role": "production_run",
                            "first_registered_at": "2026-07-10T10:00:00+09:00",
                            "last_updated_at": "2026-07-10T10:00:00+09:00",
                        }
                    ],
                    "output_roots": {
                        "title_root": "catalog/albums/aurora-m/test-social",
                        "run_roots": [self.run_rel],
                        "prompt_exports": f"{self.run_rel}/exports/02B/prompts/",
                        "imagegen_manifests": f"{self.run_rel}/exports/02B/manifests/",
                        "review_boards": f"{self.run_rel}/generations/review-boards/",
                        "branch_cut_images": f"{self.run_rel}/generations/branch-cuts/",
                        "video_prompts": f"{self.run_rel}/generations/video-prompts/",
                        "generated_videos": f"{self.run_rel}/generations/video/",
                        "edits": f"{self.run_rel}/generations/video/master/",
                        "packages": f"{self.run_rel}/exports/social/",
                    },
                    "outputs": [],
                    "latest_pointers": {},
                    "review_summary": {
                        "founder_review_status": "not_reviewed",
                        "passed_output_ids": [],
                        "held_output_ids": [],
                        "rejected_output_ids": [],
                    },
                    "open_questions": [],
                },
                sort_keys=False,
            ),
            encoding="utf-8",
        )

    def tearDown(self) -> None:
        self.temp.cleanup()

    def write_final_lineage_fixture(self) -> dict[str, object]:
        def write_yaml(path: Path, payload: dict[str, object]) -> None:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(
                yaml.safe_dump(payload, allow_unicode=True, sort_keys=False),
                encoding="utf-8",
            )

        scripts = self.root / "scripts"
        scripts.mkdir(parents=True, exist_ok=True)
        (scripts / "validate_edit_map_readiness.rb").write_text(
            "exit(ARGV.include?('--mode') && ARGV.include?('closeout') ? 0 : 1)\n",
            encoding="utf-8",
        )
        (scripts / "validate_edit_finishing_fx_compile.py").write_text(
            "import sys\nraise SystemExit(0 if '--immutable-receipt' in sys.argv else 2)\n",
            encoding="utf-8",
        )
        registry = self.root / "automation/edit-effect-registry.yaml"
        write_yaml(registry, {"schema_version": "idol_edit_effect_registry.v1", "effects": {}})

        edit_map = self.run / "04-edit-map.yaml"
        marker = self.run / "generations/video/qc/edit-marker-plan-v1.yaml"
        audio = self.run / "audio/selected/master.wav"
        preview = self.run / "generations/video/qc/previews/final-audit-preview-v1.mp4"
        final_master = self.run / "generations/video/master/final-master-v1.mp4"
        edit_map.parent.mkdir(parents=True, exist_ok=True)
        screen_node = {
            "screen_progression_map_id": "SPM_TEST_SOCIAL_RELEASE",
            "screen_progression_node_id": "SPN_TEST_SOCIAL_RELEASE_R01",
            "section_id": "S01",
            "major_scene_id": "MJ01",
            "core_cut_id": "C01",
            "branch_cut_ids": ["BC01"],
            "source_03v_cue_ids": ["03VCUE_TEST_SOCIAL_RELEASE_R01"],
            "storyline_role": "resolve",
            "observable_screen_proof": (
                "The release fixture preserves the reviewed final screen state."
            ),
        }
        write_yaml(
            edit_map,
            {
                "schema_version": "idol_edit_map.v4",
                "content_id": self.content_id,
                "status": "qc_pass",
                "edit_unit_screen_progression_nodes": [
                    {"edit_unit_id": "SEG_RELEASE_R01", **screen_node}
                ],
            },
        )
        write_yaml(marker, {"content_id": self.content_id, "status": "locked"})
        audio.parent.mkdir(parents=True, exist_ok=True)
        audio.write_bytes(b"test-audio")
        preview.parent.mkdir(parents=True, exist_ok=True)
        preview.write_bytes(b"passed-full-master-preview")
        final_master.parent.mkdir(parents=True, exist_ok=True)
        final_master.write_bytes(b"immutable-final-master")

        fx_root = self.run / "generations/video/qc/finishing-fx-v1"
        base_recipe = fx_root / "base-recipe-v1.yaml"
        final_recipe = fx_root / "final-recipe-v1.yaml"
        base_payload = {
            "schema_version": "idol_edit_recipe.v3",
            "content_id": self.content_id,
            "source_edit_map": {
                "path": edit_map.relative_to(self.run).as_posix(),
                "sha256": sha256_file(edit_map),
            },
            "audio_program": {
                "path": audio.relative_to(self.root).as_posix(),
                "sha256": sha256_file(audio),
            },
            "timeline": [
                {
                    "segment_id": "SEG_RELEASE_R01",
                    "slot": "R01",
                    "marker_slot_ref": "R01",
                    "section_ids": ["S01"],
                    "screen_progression_node": screen_node,
                }
            ],
            "effects": [],
        }
        write_yaml(base_recipe, base_payload)
        write_yaml(final_recipe, dict(base_payload))

        fx_map = fx_root / "04FX-finishing-map-v1.yaml"
        coverage_event_id = "EVT_FIXTURE_FULL_MASTER_START"
        coverage_digest = hashlib.sha256(
            f"{coverage_event_id}\n".encode("utf-8")
        ).hexdigest()
        write_yaml(
            fx_map,
            {
                "schema_version": "idol_edit_finishing_fx.v2",
                "content_id": self.content_id,
                "status": "passed_for_final_render",
                "source_edit_map": edit_map.relative_to(self.run).as_posix(),
                "source_recipe": base_recipe.relative_to(self.run).as_posix(),
                "source_edit_marker_plan": marker.relative_to(self.run).as_posix(),
                "source_audio_or_cue_map": audio.relative_to(self.run).as_posix(),
                "effect_registry_ref": "automation/edit-effect-registry.yaml",
                "dependency_lock": {
                    "digest_algorithm": "sha256",
                    "source_edit_map_sha256": sha256_file(edit_map),
                    "source_recipe_sha256": sha256_file(base_recipe),
                    "source_edit_marker_plan_sha256": sha256_file(marker),
                    "source_audio_or_cue_map_sha256": sha256_file(audio),
                    "passed_preview_sha256": sha256_file(preview),
                },
                "preview_gate": {
                    "gate_type": "full_master",
                    "section_ids": ["S00"],
                    "preview_path": preview.relative_to(self.run).as_posix(),
                    "edit_preview_status": "passed",
                    "fx_allowed": True,
                },
                "track_tone_world_guard": {
                    "tone_and_manner": "Preserve the passed full-master test preview.",
                    "world_space_preserve": "Do not alter fixture geometry.",
                    "identity_body_preserve": "Do not alter fixture identity pixels.",
                    "color_light_limits": "Do not add unreviewed exposure changes.",
                    "repeated_effect_drift_guard": "No additional effect is needed.",
                },
                "transition_opportunity_audit": {
                    "audit_status": "complete_no_fx_needed",
                    "catalog_ref": (
                        "skills/idol-edit-finishing-fx/references/"
                        "local-ffmpeg-transition-effect-catalog.md"
                    ),
                    "coverage_contract": {
                        "coverage_version": "recipe_marker_audio_exact_v1",
                        "coverage_scope": "full_master",
                        "digest_algorithm": "sha256_sorted_utf8_lines_v1",
                        "expected_event_count": 1,
                        "covered_event_count": 1,
                        "expected_event_ids_sha256": coverage_digest,
                        "covered_event_ids_sha256": coverage_digest,
                    },
                    "points": [
                        {
                            "point_id": "TP_FULL_MASTER_START",
                            "program_time": 0.0,
                            "program_frame": 0,
                            "kind": "other_musical_turn",
                            "section_ids": ["S00"],
                            "coverage_event_ids": [coverage_event_id],
                            "coverage_kinds": ["other_musical_turn"],
                            "disposition": "none_needed",
                            "rationale": "The full-master audit found no added transition need.",
                        }
                    ],
                },
                "fx_records": [],
                "final_render_policy": {
                    "include_only_passed_fx": True,
                    "single_high_quality_render_after_fx_pass": True,
                    "timing_change_returns_to_04_edit": True,
                    "post_edit_transition_audit_required_before_final_master": True,
                    "final_qc_no_new_creative_fx_by_default": True,
                },
                "automation_boundaries": [
                    "This fixture proves a completed zero-FX audit without selecting an effect."
                ],
            },
        )

        compile_manifest = fx_root / "final-compile-manifest-v1.yaml"
        empty_digest = canonical_object_sha256([])
        write_yaml(
            compile_manifest,
            {
                "schema_version": "idol_04fx_compile_manifest.v1",
                "compile_mode": "final_pass_only",
                "source_bindings": {
                    "fx_map": {
                        "path": fx_map.relative_to(self.root).as_posix(),
                        "sha256": sha256_file(fx_map),
                    },
                    "recipe": {
                        "path": base_recipe.relative_to(self.root).as_posix(),
                        "sha256": sha256_file(base_recipe),
                    },
                    "effect_registry": {
                        "path": registry.relative_to(self.root).as_posix(),
                        "sha256": sha256_file(registry),
                    },
                },
                "selection": {
                    "audit_status": "complete_no_fx_needed",
                    "selected_pass_fx_ids": [],
                    "compiled_fx_ids": [],
                    "excluded_nonpass_fx_ids": [],
                    "skipped_pass_fx_ids": [],
                },
                "merge_policy": {
                    "policy": "preserve_04_base_replace_prior_04fx",
                    "preserved_base_effect_count": 0,
                    "replaced_prior_04fx_effect_count": 0,
                },
                "compiled_output": {
                    "path": final_recipe.relative_to(self.root).as_posix(),
                    "kind": "merged_recipe",
                    "sha256": sha256_file(final_recipe),
                    "compiled_effects_sha256": empty_digest,
                    "merged_effects_sha256": empty_digest,
                    "total_effect_count": 0,
                    "compiled_04fx_count": 0,
                },
            },
        )

        render_manifest = self.run / "generations/video/qc/final-render-manifest-v1.yaml"
        write_yaml(
            render_manifest,
            {
                "schema_version": "idol_edit_render_manifest.v1",
                "profile": "final",
                "source_bindings": {
                    "recipe": {
                        "path": final_recipe.relative_to(self.root).as_posix(),
                        "sha256": sha256_file(final_recipe),
                    },
                    "audio": {
                        "path": audio.relative_to(self.root).as_posix(),
                        "sha256": sha256_file(audio),
                    },
                    "fx_compile_manifest": {
                        "path": compile_manifest.relative_to(self.root).as_posix(),
                        "sha256": sha256_file(compile_manifest),
                    },
                },
                "render_spec": {
                    "fps": {"numerator": 24, "denominator": 1},
                    "width": 1080,
                    "height": 1920,
                    "pixel_format": "yuv420p",
                    "fit_mode": "fit_pad",
                    "expected_frame_count": 1,
                },
                "encoding": {
                    "container": "mp4",
                    "requested_video_codec": "h264",
                    "requested_audio_codec": "aac",
                },
                "output": {
                    "path": final_master.relative_to(self.root).as_posix(),
                    "sha256": sha256_file(final_master),
                    "duration_seconds": 1 / 24,
                    "frame_count": 1,
                    "width": 1080,
                    "height": 1920,
                    "avg_frame_rate": "24/1",
                    "video_codec": "h264",
                    "audio_codec": "aac",
                    "pixel_format": "yuv420p",
                    "color_range": "tv",
                    "color_space": "bt709",
                    "color_transfer": "bt709",
                    "color_primaries": "bt709",
                },
            },
        )

        def typed_ref(
            artifact_type: str, schema_version: str, path: Path
        ) -> dict[str, str]:
            return {
                "artifact_type": artifact_type,
                "schema_version": schema_version,
                "path": path.relative_to(self.root).as_posix(),
                "sha256": sha256_file(path),
                "validation_status": "pass",
            }

        return {
            "edit_map": edit_map.relative_to(self.root).as_posix(),
            "edit_map_sha256": sha256_file(edit_map),
            "final_recipe": final_recipe.relative_to(self.root).as_posix(),
            "final_recipe_sha256": sha256_file(final_recipe),
            "finishing_fx_map": typed_ref(
                "finishing_fx_map", "idol_edit_finishing_fx.v2", fx_map
            ),
            "finishing_fx_compile_manifest": typed_ref(
                "finishing_fx_compile_manifest",
                "idol_04fx_compile_manifest.v1",
                compile_manifest,
            ),
            "final_render_manifest": typed_ref(
                "final_render_manifest",
                "idol_edit_render_manifest.v1",
                render_manifest,
            ),
            "final_master_path": final_master.relative_to(self.root).as_posix(),
            "final_master_sha256": sha256_file(final_master),
        }

    def write_queue(self, rows: list[dict[str, object]]) -> None:
        self.queue.write_text(
            "\n".join(json.dumps(row, ensure_ascii=False) for row in rows) + "\n",
            encoding="utf-8",
        )

    def package_lock(self) -> tuple[Path, str, str]:
        package_path, package_document, deliverables = validate_package_contract(
            repo_root=self.root,
            run_path=self.run,
            content_id=self.content_id,
            package_contract=self.package_contract,
        )
        package_manifest = package_deliverable_manifest(
            repo_root=self.root,
            run_path=self.run,
            document=package_document,
            deliverables=deliverables,
        )
        return (
            package_path,
            sha256_file(package_path),
            canonical_object_sha256(package_manifest),
        )

    def approval(self, actions: list[str]) -> tuple[Path, str]:
        rows = [json.loads(line) for line in self.queue.read_text().splitlines() if line]
        package_path, package_sha, package_manifest_sha = self.package_lock()
        path = self.run / "review/platform-release-approval-v1.yaml"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(
            yaml.safe_dump(
                {
                    "schema_version": "idol_platform_release_approval.v1",
                    "approval_id": "APPROVAL_TEST_SOCIAL_RELEASE",
                    "status": "active",
                    "run_root": self.run_rel,
                    "content_id": self.content_id,
                    "queue_path": self.queue.relative_to(self.root).as_posix(),
                    "queue_sha256": queue_approval_sha256(rows),
                    "package_contract_path": package_path.relative_to(self.root.resolve()).as_posix(),
                    "package_contract_sha256": package_sha,
                    "package_deliverable_manifest_sha256": package_manifest_sha,
                    "allowed_actions": actions,
                    "approved_platforms": ["youtube_shorts"],
                    "approved_post_ids": [self.row["post_id"]],
                    "approved_assets": [
                        {
                            "post_id": self.row["post_id"],
                            "path": self.asset.relative_to(self.root).as_posix(),
                            "sha256": sha256_file(self.asset),
                        }
                    ],
                    "founder_explicit_approval": True,
                    "approval_source": "founder_test_fixture",
                    "approved_at_kst": "2026-07-10T11:00:00+09:00",
                },
                sort_keys=False,
            ),
            encoding="utf-8",
        )
        return path, sha256_file(path)

    def uploader_argv(
        self,
        *,
        approval: Path | None = None,
        approval_sha: str = "",
        tracker: Path | None = None,
        log: Path | None = None,
        package_contract: Path | None = None,
        apply: bool = True,
        retry_failed: bool = False,
        skip_title_registry: bool = False,
        platforms: list[str] | None = None,
    ) -> list[str]:
        argv = [
            "idol_platform_draft_upload.py",
            "--run-root",
            self.run_rel,
            "--content-id",
            self.content_id,
            "--queue",
            self.queue.relative_to(self.root).as_posix(),
            "--tracker",
            (tracker or self.tracker).relative_to(self.root).as_posix(),
            "--log",
            (log or self.log).relative_to(self.root).as_posix(),
            "--title-key",
            "test-social",
        ]
        if package_contract is not None:
            argv.extend(
                [
                    "--package-contract",
                    package_contract.relative_to(self.root).as_posix(),
                ]
            )
        if approval is not None:
            argv.extend(
                [
                    "--approval-artifact",
                    approval.relative_to(self.root).as_posix(),
                    "--approval-sha256",
                    approval_sha,
                ]
            )
        if apply:
            argv.append("--apply")
        if skip_title_registry:
            argv.append("--skip-title-registry")
        if retry_failed:
            argv.append("--retry-failed")
        for platform in platforms or []:
            argv.extend(["--platform", platform])
        return argv

    def test_approval_is_schema_and_hash_bound(self) -> None:
        approval, approval_sha = self.approval(["platform_draft_upload"])
        run_path, run_rel = validate_run_scope(self.root, self.run_rel, self.content_id)
        queue_path, _rows, queue_sha = validate_queue_scope(
            self.root, run_path, self.content_id, self.queue
        )
        package_path, package_sha, package_manifest_sha = self.package_lock()
        _path, document, actual_sha = validate_approval_artifact(
            repo_root=self.root,
            run_path=run_path,
            run_rel=run_rel,
            content_id=self.content_id,
            queue_path=queue_path,
            queue_rows=_rows,
            queue_sha256=queue_sha,
            package_contract_path=package_path,
            package_contract_sha256=package_sha,
            package_deliverable_manifest_sha256=package_manifest_sha,
            artifact=approval,
            expected_sha256=approval_sha,
            required_action="platform_draft_upload",
        )
        self.assertTrue(document["founder_explicit_approval"])
        self.assertEqual(actual_sha, approval_sha)
        with self.assertRaises(SocialContractError):
            validate_approval_artifact(
                repo_root=self.root,
                run_path=run_path,
                run_rel=run_rel,
                content_id=self.content_id,
                queue_path=queue_path,
                queue_rows=_rows,
                queue_sha256=queue_sha,
                package_contract_path=package_path,
                package_contract_sha256=package_sha,
                package_deliverable_manifest_sha256=package_manifest_sha,
                artifact=approval,
                expected_sha256="0" * 64,
                required_action="platform_draft_upload",
            )

    def test_expanded_multi_lane_queue_preserves_shared_media_relation(self) -> None:
        root_row = dict(self.row)
        root_row.update(
            {
                "post_id": f"{self.content_id}-X-ROOT",
                "platform": "x",
                "template_type": "work_root",
                "content_lane": "cf_film_drop",
                "format_family": "video",
                "content_pillar": "cf_finish",
                "primary_channel_job": "discovery",
                "member": ["M02"],
                "member_intro_line": "Seorin is holding the final frame.",
                "analysis_scope": "scheduler_whitelist",
                "delivery_mode": "public_api_post",
            }
        )
        derived_row = dict(self.row)
        derived_row.update(
            {
                "template_type": "derived_clip",
                "content_lane": "derived_clip_3_8",
                "format_family": "video",
                "content_pillar": "cf_finish",
                "primary_channel_job": "discovery",
                "shared_media_source_post_id": root_row["post_id"],
            }
        )
        self.write_queue([root_row, derived_row])
        run_path, _run_rel = validate_run_scope(self.root, self.run_rel, self.content_id)
        _queue_path, rows, _queue_sha = validate_queue_scope(
            self.root, run_path, self.content_id, self.queue
        )
        self.assertEqual(root_row["post_id"], rows[1]["shared_media_source_post_id"])

    def test_shared_media_relation_must_resolve_inside_the_same_queue(self) -> None:
        invalid = dict(self.row)
        invalid["shared_media_source_post_id"] = "MISSING-X-ROOT"
        self.write_queue([invalid])
        run_path, _run_rel = validate_run_scope(self.root, self.run_rel, self.content_id)
        with self.assertRaisesRegex(SocialContractError, "shared_media_source_post_id"):
            validate_queue_scope(self.root, run_path, self.content_id, self.queue)

    def test_approval_platform_scope_must_exactly_match_approved_posts(self) -> None:
        approval, _approval_sha = self.approval(["platform_draft_upload"])
        document = yaml.safe_load(approval.read_text(encoding="utf-8"))
        document["approved_platforms"].append("x")
        approval.write_text(yaml.safe_dump(document, sort_keys=False), encoding="utf-8")
        run_path, run_rel = validate_run_scope(self.root, self.run_rel, self.content_id)
        queue_path, rows, queue_sha = validate_queue_scope(
            self.root, run_path, self.content_id, self.queue
        )
        package_path, package_sha, package_manifest_sha = self.package_lock()
        with self.assertRaisesRegex(SocialContractError, "approved_platforms must exactly match"):
            validate_approval_artifact(
                repo_root=self.root,
                run_path=run_path,
                run_rel=run_rel,
                content_id=self.content_id,
                queue_path=queue_path,
                queue_rows=rows,
                queue_sha256=queue_sha,
                package_contract_path=package_path,
                package_contract_sha256=package_sha,
                package_deliverable_manifest_sha256=package_manifest_sha,
                artifact=approval,
                expected_sha256=sha256_file(approval),
                required_action="platform_draft_upload",
            )

    def test_queue_approval_digest_ignores_only_projection_and_result_fields(self) -> None:
        baseline = queue_approval_sha256([dict(self.row)])
        projected = dict(self.row)
        projected.update(
            {
                "release_approval_status": "approved_for_manual_draft_upload",
                "release_approval_artifact_sha256": "a" * 64,
                "release_approval_queue_sha256": baseline,
                "release_approval_action": "manual_draft_upload",
                "release_asset_sha256": sha256_file(self.asset),
                "draft_status": "uploaded_private_draft",
                "draft_platform_id": "offline-id",
            }
        )
        self.assertEqual(queue_approval_sha256([projected]), baseline)
        projected["caption"] = "Changed public copy"
        self.assertNotEqual(queue_approval_sha256([projected]), baseline)

    def test_upload_apply_without_approval_fails_before_network(self) -> None:
        argv = [
            "idol_platform_draft_upload.py",
            "--run-root",
            self.run_rel,
            "--content-id",
            self.content_id,
            "--queue",
            self.queue.relative_to(self.root).as_posix(),
            "--tracker",
            self.tracker.relative_to(self.root).as_posix(),
            "--log",
            self.log.relative_to(self.root).as_posix(),
            "--package-contract",
            self.package_contract.relative_to(self.root).as_posix(),
            "--title-key",
            "test-social",
            "--apply",
        ]
        with mock.patch.object(uploader, "ROOT", self.root), mock.patch.object(
            uploader, "run_one"
        ) as run_one, mock.patch.object(sys, "argv", argv), redirect_stdout(io.StringIO()):
            self.assertEqual(uploader.main(), 2)
            run_one.assert_not_called()

    def test_upload_apply_cannot_skip_title_registry(self) -> None:
        approval, approval_sha = self.approval(["platform_draft_upload"])
        argv = self.uploader_argv(
            approval=approval,
            approval_sha=approval_sha,
            package_contract=self.package_contract,
            skip_title_registry=True,
        )
        original_queue = self.queue.read_bytes()
        original_registry = self.registry.read_bytes()
        output = io.StringIO()
        with mock.patch.object(uploader, "ROOT", self.root), mock.patch.object(
            uploader, "run_one"
        ) as run_one, mock.patch.object(uploader, "http_request") as http_request, mock.patch.object(
            sys, "argv", argv
        ), redirect_stdout(output):
            self.assertEqual(uploader.main(), 2, output.getvalue())
            run_one.assert_not_called()
            http_request.assert_not_called()
        self.assertIn("cannot use --skip-title-registry", output.getvalue())
        self.assertEqual(self.queue.read_bytes(), original_queue)
        self.assertEqual(self.registry.read_bytes(), original_registry)

    def test_upload_rejects_unsupported_platform_draft_before_selection(self) -> None:
        instagram_row = dict(self.row)
        instagram_row["post_id"] = f"{self.content_id}-IG-001"
        instagram_row["platform"] = "instagram_reels"
        self.write_queue([instagram_row])
        argv = self.uploader_argv(
            package_contract=self.package_contract,
            apply=False,
        )
        output = io.StringIO()
        with mock.patch.object(uploader, "ROOT", self.root), mock.patch.object(
            uploader, "http_request"
        ) as http_request, mock.patch.object(sys, "argv", argv), redirect_stdout(output):
            self.assertEqual(uploader.main(), 2, output.getvalue())
            http_request.assert_not_called()
        self.assertIn("unsupported automatic uploader platform", output.getvalue())
        self.assertIn("instagram_reels", output.getvalue())

    def test_upload_rejects_archived_title_registry_before_network(self) -> None:
        approval, approval_sha = self.approval(["platform_draft_upload"])
        registry = yaml.safe_load(self.registry.read_text(encoding="utf-8"))
        registry["status"] = "archived"
        self.registry.write_text(yaml.safe_dump(registry, sort_keys=False), encoding="utf-8")
        argv = self.uploader_argv(
            approval=approval,
            approval_sha=approval_sha,
            package_contract=self.package_contract,
        )
        output = io.StringIO()
        with mock.patch.object(uploader, "ROOT", self.root), mock.patch.object(
            uploader, "run_one"
        ) as run_one, mock.patch.object(uploader, "http_request") as http_request, mock.patch.object(
            sys, "argv", argv
        ), redirect_stdout(output):
            self.assertEqual(uploader.main(), 2, output.getvalue())
            run_one.assert_not_called()
            http_request.assert_not_called()
        self.assertIn("immutable archived/closed state", output.getvalue())

    def test_release_contract_rejects_archived_and_closed_package_states(self) -> None:
        baseline = yaml.safe_load(self.package_contract.read_text(encoding="utf-8"))
        for status in ("archived", "final_complete_platform_records_closed"):
            with self.subTest(status=status):
                document = dict(baseline)
                document["status"] = status
                self.package_contract.write_text(
                    yaml.safe_dump(document, sort_keys=False), encoding="utf-8"
                )
                with self.assertRaisesRegex(SocialContractError, "not release-projectable"):
                    validate_package_contract(
                        repo_root=self.root,
                        run_path=self.run,
                        content_id=self.content_id,
                        package_contract=self.package_contract,
                    )

    def test_final_package_rejects_forged_typed_reference_hash(self) -> None:
        document = yaml.safe_load(self.package_contract.read_text(encoding="utf-8"))
        document["source_contracts"]["finishing_fx_map"]["sha256"] = "0" * 64
        self.package_contract.write_text(
            yaml.safe_dump(document, sort_keys=False), encoding="utf-8"
        )
        with self.assertRaisesRegex(SocialContractError, "stale or mismatched"):
            validate_package_contract(
                repo_root=self.root,
                run_path=self.run,
                content_id=self.content_id,
                package_contract=self.package_contract,
            )

    def test_final_package_rejects_render_to_compile_binding_forgery(self) -> None:
        document = yaml.safe_load(self.package_contract.read_text(encoding="utf-8"))
        render_ref = document["source_contracts"]["final_render_manifest"]
        render_path = self.root / render_ref["path"]
        render = yaml.safe_load(render_path.read_text(encoding="utf-8"))
        render["source_bindings"]["fx_compile_manifest"]["sha256"] = "0" * 64
        render_path.write_text(
            yaml.safe_dump(render, sort_keys=False), encoding="utf-8"
        )
        render_ref["sha256"] = sha256_file(render_path)
        self.package_contract.write_text(
            yaml.safe_dump(document, sort_keys=False), encoding="utf-8"
        )
        with self.assertRaisesRegex(SocialContractError, "04FX compile manifest SHA-256 mismatch"):
            validate_package_contract(
                repo_root=self.root,
                run_path=self.run,
                content_id=self.content_id,
                package_contract=self.package_contract,
            )

    def test_final_package_requires_passing_04_closeout_semantics(self) -> None:
        (self.root / "scripts/validate_edit_map_readiness.rb").write_text(
            "warn 'fixture closeout failed'; exit 1\n", encoding="utf-8"
        )
        with self.assertRaisesRegex(SocialContractError, "04 closeout semantic validation failed"):
            validate_package_contract(
                repo_root=self.root,
                run_path=self.run,
                content_id=self.content_id,
                package_contract=self.package_contract,
            )

    def test_final_package_requires_deterministic_compile_revalidation(self) -> None:
        (self.root / "scripts/validate_edit_finishing_fx_compile.py").write_text(
            "print('fixture compile proof failed'); raise SystemExit(1)\n",
            encoding="utf-8",
        )
        with self.assertRaisesRegex(
            SocialContractError, "deterministic 04FX compile validation failed"
        ):
            validate_package_contract(
                repo_root=self.root,
                run_path=self.run,
                content_id=self.content_id,
                package_contract=self.package_contract,
            )

    def test_final_package_holds_post_render_edit_map_closeout_update(self) -> None:
        edit_map = self.run / "04-edit-map.yaml"
        edit_map.write_text(
            edit_map.read_text(encoding="utf-8")
            + "final_closeout_inventory:\n  status: qc_pass\n",
            encoding="utf-8",
        )
        with self.assertRaisesRegex(SocialContractError, "SHA-256 mismatch"):
            validate_package_contract(
                repo_root=self.root,
                run_path=self.run,
                content_id=self.content_id,
                package_contract=self.package_contract,
            )

    def test_final_package_holds_wrong_screen_node_projection(self) -> None:
        document = yaml.safe_load(self.package_contract.read_text(encoding="utf-8"))
        document["production_graph_trace"]["deliverable_bindings"][0][
            "screen_progression_node_ids"
        ] = ["SPN_WRONG"]
        self.package_contract.write_text(
            yaml.safe_dump(document, sort_keys=False), encoding="utf-8"
        )
        with self.assertRaisesRegex(SocialContractError, "exact segment projection"):
            validate_package_contract(
                repo_root=self.root,
                run_path=self.run,
                content_id=self.content_id,
                package_contract=self.package_contract,
            )

    def test_final_package_requires_exact_run_root_edit_map_owner(self) -> None:
        alternate = self.run / "review/04-edit-map-copy.yaml"
        alternate.parent.mkdir(parents=True, exist_ok=True)
        alternate.write_text("content_id: TEST_SOCIAL_RELEASE\n", encoding="utf-8")
        document = yaml.safe_load(self.package_contract.read_text(encoding="utf-8"))
        document["source_contracts"]["edit_map"] = alternate.relative_to(
            self.root
        ).as_posix()
        self.package_contract.write_text(
            yaml.safe_dump(document, sort_keys=False), encoding="utf-8"
        )
        with self.assertRaisesRegex(SocialContractError, "exact run-root 04-edit-map"):
            validate_package_contract(
                repo_root=self.root,
                run_path=self.run,
                content_id=self.content_id,
                package_contract=self.package_contract,
            )

    def test_deprecated_final_recipe_cannot_create_second_recipe_truth(self) -> None:
        document = yaml.safe_load(self.package_contract.read_text(encoding="utf-8"))
        document["source_contracts"]["final_recipe"] = (
            f"{self.run_rel}/generations/video/qc/finishing-fx-v1/base-recipe-v1.yaml"
        )
        self.package_contract.write_text(
            yaml.safe_dump(document, sort_keys=False), encoding="utf-8"
        )
        with self.assertRaisesRegex(
            SocialContractError, "does not match the canonical compiled final recipe"
        ):
            validate_package_contract(
                repo_root=self.root,
                run_path=self.run,
                content_id=self.content_id,
                package_contract=self.package_contract,
            )

    def test_nonpublic_social_planning_scope_can_omit_separate_04fx_lineage(self) -> None:
        document = yaml.safe_load(self.package_contract.read_text(encoding="utf-8"))
        document["status"] = "ready_for_social_planning"
        document["source_contracts"].pop("finishing_fx_map")
        document["source_contracts"].pop("finishing_fx_compile_manifest")
        document["source_contracts"].pop("final_render_manifest")
        self.package_contract.write_text(
            yaml.safe_dump(document, sort_keys=False), encoding="utf-8"
        )
        path, _document, _deliverables = validate_package_contract(
            repo_root=self.root,
            run_path=self.run,
            content_id=self.content_id,
            package_contract=self.package_contract,
            require_final_lineage=False,
        )
        self.assertEqual(self.package_contract.resolve(), path)

    def test_default_final_readiness_still_requires_separate_04fx_lineage(self) -> None:
        document = yaml.safe_load(self.package_contract.read_text(encoding="utf-8"))
        document["status"] = "ready_for_social_planning"
        document["source_contracts"].pop("finishing_fx_map")
        document["source_contracts"].pop("finishing_fx_compile_manifest")
        document["source_contracts"].pop("final_render_manifest")
        self.package_contract.write_text(
            yaml.safe_dump(document, sort_keys=False), encoding="utf-8"
        )
        with self.assertRaisesRegex(SocialContractError, "typed artifact reference"):
            validate_package_contract(
                repo_root=self.root,
                run_path=self.run,
                content_id=self.content_id,
                package_contract=self.package_contract,
            )

    def test_public_release_status_cannot_omit_separate_04fx_lineage(self) -> None:
        document = yaml.safe_load(self.package_contract.read_text(encoding="utf-8"))
        document["status"] = "approved_for_public_release"
        document["source_contracts"].pop("final_render_manifest")
        self.package_contract.write_text(
            yaml.safe_dump(document, sort_keys=False), encoding="utf-8"
        )
        with self.assertRaisesRegex(SocialContractError, "schema failure"):
            validate_package_contract(
                repo_root=self.root,
                run_path=self.run,
                content_id=self.content_id,
                package_contract=self.package_contract,
                require_final_lineage=False,
            )

    def test_upload_apply_refuses_immutable_closed_publishing_record(self) -> None:
        approval, approval_sha = self.approval(["platform_draft_upload"])
        plan_text = self.plan.read_text(encoding="utf-8").replace(
            "status: draft", "status: final_complete_platform_records_closed"
        )
        self.plan.write_text(
            plan_text + "\n## Closed Upload History\n\nImmutable.\n",
            encoding="utf-8",
        )
        argv = [
            "idol_platform_draft_upload.py",
            "--run-root",
            self.run_rel,
            "--content-id",
            self.content_id,
            "--queue",
            self.queue.relative_to(self.root).as_posix(),
            "--tracker",
            self.tracker.relative_to(self.root).as_posix(),
            "--log",
            self.log.relative_to(self.root).as_posix(),
            "--package-contract",
            self.package_contract.relative_to(self.root).as_posix(),
            "--approval-artifact",
            approval.relative_to(self.root).as_posix(),
            "--approval-sha256",
            approval_sha,
            "--title-key",
            "test-social",
            "--apply",
        ]
        output = io.StringIO()
        with mock.patch.object(uploader, "ROOT", self.root), mock.patch.object(
            uploader, "run_one"
        ) as run_one, mock.patch.object(sys, "argv", argv), redirect_stdout(output):
            self.assertEqual(uploader.main(), 2, output.getvalue())
            run_one.assert_not_called()
        self.assertIn("immutable closed state", output.getvalue())

    def test_upload_dry_run_emits_hash_bound_approval_asset_manifest(self) -> None:
        argv = [
            "idol_platform_draft_upload.py",
            "--run-root",
            self.run_rel,
            "--content-id",
            self.content_id,
            "--queue",
            self.queue.relative_to(self.root).as_posix(),
            "--tracker",
            self.tracker.relative_to(self.root).as_posix(),
            "--log",
            self.log.relative_to(self.root).as_posix(),
            "--package-contract",
            self.package_contract.relative_to(self.root).as_posix(),
        ]
        output = io.StringIO()
        with mock.patch.object(uploader, "ROOT", self.root), mock.patch.object(
            uploader, "http_request"
        ) as http_request, mock.patch.object(sys, "argv", argv), redirect_stdout(output):
            self.assertEqual(uploader.main(), 0, output.getvalue())
            http_request.assert_not_called()
        report = json.loads(output.getvalue())
        self.assertEqual(
            report["approval_assets"][0]["asset_sha256"], sha256_file(self.asset)
        )

    def test_upload_apply_uses_only_approved_rows_without_network(self) -> None:
        approval, approval_sha = self.approval(["platform_draft_upload"])
        argv = [
            "idol_platform_draft_upload.py",
            "--run-root",
            self.run_rel,
            "--content-id",
            self.content_id,
            "--queue",
            self.queue.relative_to(self.root).as_posix(),
            "--tracker",
            self.tracker.relative_to(self.root).as_posix(),
            "--log",
            self.log.relative_to(self.root).as_posix(),
            "--package-contract",
            self.package_contract.relative_to(self.root).as_posix(),
            "--approval-artifact",
            approval.relative_to(self.root).as_posix(),
            "--approval-sha256",
            approval_sha,
            "--title-key",
            "test-social",
            "--apply",
        ]
        result = uploader.UploadResult(
            post_id=self.row["post_id"],
            platform="youtube_shorts",
            ok=True,
            draft_status="uploaded_private_draft",
            draft_platform_id="offline-test-id",
        )
        with mock.patch.object(uploader, "ROOT", self.root), mock.patch.object(
            uploader, "run_one", return_value=result
        ) as run_one, mock.patch.object(uploader, "http_request") as http_request, mock.patch.object(
            sys, "argv", argv
        ), redirect_stdout(io.StringIO()):
            self.assertEqual(uploader.main(), 0)
            run_one.assert_called_once()
            http_request.assert_not_called()
        updated = json.loads(self.queue.read_text().splitlines()[0])
        self.assertEqual(updated["draft_platform_id"], "offline-test-id")
        self.assertTrue(self.tracker.is_file())
        self.assertTrue(self.log.is_file())
        self.assertEqual(updated["release_approval_artifact_sha256"], approval_sha)
        log_row = json.loads(self.log.read_text().splitlines()[0])
        self.assertEqual(log_row["release_approval_artifact_sha256"], approval_sha)
        self.assertEqual(log_row["release_approval_queue_sha256"], updated["release_approval_queue_sha256"])
        self.assertIn("release_approval_artifact_sha256", self.tracker.read_text())
        registry = yaml.safe_load(self.registry.read_text(encoding="utf-8"))
        self.assertEqual(registry["status"], "packaged")
        registered_paths = {item["path"] for item in registry["outputs"]}
        self.assertIn(self.tracker.relative_to(self.root).as_posix(), registered_paths)
        self.assertIn(self.log.relative_to(self.root).as_posix(), registered_paths)

    def test_upload_rejects_same_path_asset_replaced_after_approval(self) -> None:
        approval, approval_sha = self.approval(["platform_draft_upload"])
        self.asset.write_bytes(b"X" * len(self.asset.read_bytes()))
        argv = [
            "idol_platform_draft_upload.py",
            "--run-root",
            self.run_rel,
            "--content-id",
            self.content_id,
            "--queue",
            self.queue.relative_to(self.root).as_posix(),
            "--tracker",
            self.tracker.relative_to(self.root).as_posix(),
            "--log",
            self.log.relative_to(self.root).as_posix(),
            "--package-contract",
            self.package_contract.relative_to(self.root).as_posix(),
            "--approval-artifact",
            approval.relative_to(self.root).as_posix(),
            "--approval-sha256",
            approval_sha,
            "--title-key",
            "test-social",
            "--apply",
        ]
        output = io.StringIO()
        with mock.patch.object(uploader, "ROOT", self.root), mock.patch.object(
            uploader, "run_one"
        ) as run_one, mock.patch.object(sys, "argv", argv), redirect_stdout(output):
            self.assertEqual(uploader.main(), 2, output.getvalue())
            run_one.assert_not_called()
        self.assertIn("asset SHA-256 mismatch", output.getvalue())

    def test_upload_apply_requires_exact_package_contract_before_network(self) -> None:
        approval, approval_sha = self.approval(["platform_draft_upload"])
        argv = self.uploader_argv(
            approval=approval,
            approval_sha=approval_sha,
            package_contract=None,
        )
        output = io.StringIO()
        with mock.patch.object(uploader, "ROOT", self.root), mock.patch.object(
            uploader, "run_one"
        ) as run_one, mock.patch.object(sys, "argv", argv), redirect_stdout(output):
            self.assertEqual(uploader.main(), 2, output.getvalue())
            run_one.assert_not_called()
        self.assertIn("--package-contract is required", output.getvalue())

    def test_upload_rejects_package_changed_after_founder_approval(self) -> None:
        approval, approval_sha = self.approval(["platform_draft_upload"])
        document = yaml.safe_load(self.package_contract.read_text(encoding="utf-8"))
        document["deliverable_policy"]["social_clip_source"] = "changed after approval"
        self.package_contract.write_text(
            yaml.safe_dump(document, sort_keys=False), encoding="utf-8"
        )
        argv = self.uploader_argv(
            approval=approval,
            approval_sha=approval_sha,
            package_contract=self.package_contract,
        )
        output = io.StringIO()
        with mock.patch.object(uploader, "ROOT", self.root), mock.patch.object(
            uploader, "run_one"
        ) as run_one, mock.patch.object(sys, "argv", argv), redirect_stdout(output):
            self.assertEqual(uploader.main(), 2, output.getvalue())
            run_one.assert_not_called()
        self.assertIn("package_contract_sha256 is stale or mismatched", output.getvalue())

    def test_upload_rejects_asset_not_declared_by_package(self) -> None:
        document = yaml.safe_load(self.package_contract.read_text(encoding="utf-8"))
        document["package_outputs"]["short_derivatives"]["path"] = (
            self.batch / "different.mp4"
        ).relative_to(self.root).as_posix()
        self.package_contract.write_text(
            yaml.safe_dump(document, sort_keys=False), encoding="utf-8"
        )
        argv = self.uploader_argv(
            package_contract=self.package_contract,
            apply=False,
        )
        output = io.StringIO()
        with mock.patch.object(uploader, "ROOT", self.root), mock.patch.object(
            uploader, "http_request"
        ) as http_request, mock.patch.object(sys, "argv", argv), redirect_stdout(output):
            self.assertEqual(uploader.main(), 2, output.getvalue())
            http_request.assert_not_called()
        self.assertIn("not a declared 05 deliverable", output.getvalue())

    def test_upload_rejects_active_plan_owned_by_other_content(self) -> None:
        approval, approval_sha = self.approval(["platform_draft_upload"])
        self.plan.write_text(
            self.plan.read_text(encoding="utf-8").replace(
                f"content_id: {self.content_id}", "content_id: FOREIGN_CONTENT"
            ),
            encoding="utf-8",
        )
        argv = self.uploader_argv(
            approval=approval,
            approval_sha=approval_sha,
            package_contract=self.package_contract,
        )
        output = io.StringIO()
        with mock.patch.object(uploader, "ROOT", self.root), mock.patch.object(
            uploader, "run_one"
        ) as run_one, mock.patch.object(sys, "argv", argv), redirect_stdout(output):
            self.assertEqual(uploader.main(), 2, output.getvalue())
            run_one.assert_not_called()
        self.assertIn("content_id does not match", output.getvalue())

    def test_upload_evidence_paths_cannot_overwrite_contracts(self) -> None:
        approval, approval_sha = self.approval(["platform_draft_upload"])
        protected = {
            "publishing plan": self.plan,
            "package contract": self.package_contract,
            "Founder approval": approval,
        }
        for label, target in protected.items():
            with self.subTest(label=label):
                original = target.read_bytes()
                argv = self.uploader_argv(
                    approval=approval,
                    approval_sha=approval_sha,
                    tracker=target,
                    package_contract=self.package_contract,
                )
                output = io.StringIO()
                with mock.patch.object(uploader, "ROOT", self.root), mock.patch.object(
                    uploader, "run_one"
                ) as run_one, mock.patch.object(sys, "argv", argv), redirect_stdout(output):
                    self.assertEqual(uploader.main(), 2, output.getvalue())
                    run_one.assert_not_called()
                self.assertEqual(target.read_bytes(), original)

    def test_upload_log_cannot_alias_action_queue(self) -> None:
        approval, approval_sha = self.approval(["platform_draft_upload"])
        original = self.queue.read_bytes()
        argv = self.uploader_argv(
            approval=approval,
            approval_sha=approval_sha,
            log=self.queue,
            package_contract=self.package_contract,
        )
        output = io.StringIO()
        with mock.patch.object(uploader, "ROOT", self.root), mock.patch.object(
            uploader, "run_one"
        ) as run_one, mock.patch.object(sys, "argv", argv), redirect_stdout(output):
            self.assertEqual(uploader.main(), 2, output.getvalue())
            run_one.assert_not_called()
        self.assertEqual(self.queue.read_bytes(), original)
        self.assertIn("pairwise distinct", output.getvalue())

    def test_upload_records_started_intent_and_uses_content_addressed_snapshot(self) -> None:
        approval, approval_sha = self.approval(["platform_draft_upload"])
        argv = self.uploader_argv(
            approval=approval,
            approval_sha=approval_sha,
            package_contract=self.package_contract,
        )

        def inspect_started(row: dict[str, object], args: object) -> uploader.UploadResult:
            self.assertEqual(row["draft_status"], "upload_in_progress")
            snapshot = Path(args._asset_snapshot_by_post[self.row["post_id"]])
            self.assertNotEqual(snapshot, self.asset.resolve())
            self.assertEqual(sha256_file(snapshot), sha256_file(self.asset))
            self.assertIn(sha256_file(self.asset), snapshot.as_posix())
            attempt_path = self.root / str(row["upload_attempt_record"])
            intent = json.loads(attempt_path.read_text(encoding="utf-8"))
            self.assertEqual(intent["status"], "started")
            self.assertEqual(intent["asset_snapshot_path"], snapshot.relative_to(self.root.resolve()).as_posix())
            self.assertEqual(intent["package_contract_sha256"], sha256_file(self.package_contract))
            return uploader.UploadResult(
                post_id=self.row["post_id"],
                platform="youtube_shorts",
                ok=True,
                draft_status="uploaded_private_draft",
                draft_platform_id="offline-snapshot-id",
            )

        with mock.patch.object(uploader, "ROOT", self.root), mock.patch.object(
            uploader, "run_one", side_effect=inspect_started
        ), mock.patch.object(sys, "argv", argv), redirect_stdout(io.StringIO()):
            self.assertEqual(uploader.main(), 0)
        updated = json.loads(self.queue.read_text(encoding="utf-8").splitlines()[0])
        attempt_path = self.root / updated["upload_attempt_record"]
        attempt = json.loads(attempt_path.read_text(encoding="utf-8"))
        self.assertEqual(attempt["status"], "completed")
        self.assertNotIn("draft_attempt_reconciliation_required", updated)
        self.assertEqual(updated["release_asset_snapshot_sha256"], sha256_file(self.asset))
        self.assertEqual(updated["release_package_output_id"], "OUT_TEST_SOCIAL_SHORT")
        self.assertEqual(updated["release_provenance_version"], "idol_release_provenance.v2")
        self.assertEqual(updated["release_edit_segment_ids"], ["SEG_RELEASE_R01"])
        self.assertEqual(
            updated["release_screen_progression_node_ids"],
            ["SPN_TEST_SOCIAL_RELEASE_R01"],
        )
        self.assertEqual(updated["release_section_ids"], ["S01"])
        log_row = json.loads(self.log.read_text(encoding="utf-8").splitlines()[0])
        self.assertEqual(log_row["upload_attempt_id"], updated["upload_attempt_id"])
        self.assertEqual(
            log_row["release_package_deliverable_manifest_sha256"],
            updated["release_package_deliverable_manifest_sha256"],
        )

    def test_chunk_manifest_blocks_same_size_byte_swap_before_request(self) -> None:
        expected_sha = sha256_file(self.asset)
        size, chunk_locks = uploader.build_verified_chunk_manifest(
            self.asset,
            chunk_size=5,
            expected_sha256=expected_sha,
        )
        self.asset.write_bytes(b"X" * size)
        with mock.patch.object(uploader.request, "urlopen") as urlopen:
            with self.assertRaisesRegex(uploader.UploadError, "bytes changed before request"):
                uploader.youtube_resumable_upload(
                    "https://upload.invalid/session",
                    self.asset,
                    "offline-token",
                    expected_size=size,
                    chunk_locks=chunk_locks,
                    runtime_assert=lambda: None,
                    timeout=1,
                )
            urlopen.assert_not_called()

    def test_tiktok_chunk_plan_has_exact_declared_chunk_count(self) -> None:
        size = 130 * 1024 * 1024 + 17
        chunk_size, count = uploader.tiktok_upload_plan(size, max_chunk_mb=64)
        self.assertEqual(count, 3)
        self.assertEqual((size + chunk_size - 1) // chunk_size, count)
        self.assertLessEqual(chunk_size, 64 * 1024 * 1024)
        self.assertGreaterEqual(size - chunk_size * (count - 1), 1)

    def test_crash_leaves_started_attempt_and_blocks_retry(self) -> None:
        approval, approval_sha = self.approval(["platform_draft_upload"])
        argv = self.uploader_argv(
            approval=approval,
            approval_sha=approval_sha,
            package_contract=self.package_contract,
        )
        with mock.patch.object(uploader, "ROOT", self.root), mock.patch.object(
            uploader, "run_one", side_effect=RuntimeError("simulated process crash")
        ), mock.patch.object(sys, "argv", argv), redirect_stdout(io.StringIO()):
            with self.assertRaisesRegex(RuntimeError, "simulated process crash"):
                uploader.main()
        attempts = list((self.run / "exports/social/upload-attempts").glob("*.json"))
        self.assertEqual(len(attempts), 1)
        self.assertEqual(json.loads(attempts[0].read_text())["status"], "started")

        retry_argv = self.uploader_argv(
            approval=approval,
            approval_sha=approval_sha,
            package_contract=self.package_contract,
            retry_failed=True,
        )
        output = io.StringIO()
        with mock.patch.object(uploader, "ROOT", self.root), mock.patch.object(
            uploader, "run_one"
        ) as run_one, mock.patch.object(sys, "argv", retry_argv), redirect_stdout(output):
            self.assertEqual(uploader.main(), 2, output.getvalue())
            run_one.assert_not_called()
        self.assertIn("unresolved started/unknown upload attempt", output.getvalue())

    def test_unknown_attempt_blocks_automatic_retry(self) -> None:
        approval, approval_sha = self.approval(["platform_draft_upload"])
        argv = self.uploader_argv(
            approval=approval,
            approval_sha=approval_sha,
            package_contract=self.package_contract,
        )
        unknown_result = uploader.UploadResult(
            post_id=self.row["post_id"],
            platform="youtube_shorts",
            ok=False,
            draft_status="failed_api_upload",
            error="ambiguous network result",
        )
        with mock.patch.object(uploader, "ROOT", self.root), mock.patch.object(
            uploader, "run_one", return_value=unknown_result
        ), mock.patch.object(sys, "argv", argv), redirect_stdout(io.StringIO()):
            self.assertEqual(uploader.main(), 1)
        attempt_path = next((self.run / "exports/social/upload-attempts").glob("*.json"))
        self.assertEqual(json.loads(attempt_path.read_text())["status"], "unknown")

        retry_argv = self.uploader_argv(
            approval=approval,
            approval_sha=approval_sha,
            package_contract=self.package_contract,
            retry_failed=True,
        )
        output = io.StringIO()
        with mock.patch.object(uploader, "ROOT", self.root), mock.patch.object(
            uploader, "run_one"
        ) as run_one, mock.patch.object(sys, "argv", retry_argv), redirect_stdout(output):
            self.assertEqual(uploader.main(), 2, output.getvalue())
            run_one.assert_not_called()
        self.assertIn("unknown upload attempt", output.getvalue())

    def test_retry_safe_failure_is_finalized_and_can_retry(self) -> None:
        approval, approval_sha = self.approval(["platform_draft_upload"])
        argv = self.uploader_argv(
            approval=approval,
            approval_sha=approval_sha,
            package_contract=self.package_contract,
        )
        safe_failure = uploader.UploadResult(
            post_id=self.row["post_id"],
            platform="youtube_shorts",
            ok=False,
            draft_status="failed_api_upload",
            error="credential refresh rejected before upload creation",
            attempt_status="failed",
        )
        with mock.patch.object(uploader, "ROOT", self.root), mock.patch.object(
            uploader, "run_one", return_value=safe_failure
        ), mock.patch.object(sys, "argv", argv), redirect_stdout(io.StringIO()):
            self.assertEqual(uploader.main(), 1)
        attempt_path = next((self.run / "exports/social/upload-attempts").glob("*.json"))
        self.assertEqual(json.loads(attempt_path.read_text())["status"], "failed")
        failed_row = json.loads(self.queue.read_text().splitlines()[0])
        self.assertNotIn("draft_attempt_reconciliation_required", failed_row)

        retry_argv = self.uploader_argv(
            approval=approval,
            approval_sha=approval_sha,
            package_contract=self.package_contract,
            retry_failed=True,
        )
        success = uploader.UploadResult(
            post_id=self.row["post_id"],
            platform="youtube_shorts",
            ok=True,
            draft_status="uploaded_private_draft",
            draft_platform_id="retry-safe-success",
            attempt_status="completed",
        )
        with mock.patch.object(uploader, "ROOT", self.root), mock.patch.object(
            uploader, "run_one", return_value=success
        ), mock.patch.object(sys, "argv", retry_argv), redirect_stdout(io.StringIO()):
            self.assertEqual(uploader.main(), 0)

    def test_mixed_queue_defaults_to_automatic_draft_adapters(self) -> None:
        x_row = dict(self.row)
        x_row.update(
            {
                "post_id": f"{self.content_id}-X-001",
                "platform": "x",
                "delivery_mode": "public_api_post",
                "analysis_scope": "scheduler_whitelist",
            }
        )
        instagram_row = dict(self.row)
        instagram_row.update(
            {
                "post_id": f"{self.content_id}-IG-001",
                "platform": "instagram_reels",
                "delivery_mode": "manual_upload_package",
            }
        )
        self.write_queue([self.row, x_row, instagram_row])
        argv = self.uploader_argv(
            package_contract=self.package_contract,
            apply=False,
        )
        output = io.StringIO()
        with mock.patch.object(uploader, "ROOT", self.root), mock.patch.object(
            sys, "argv", argv
        ), redirect_stdout(output):
            self.assertEqual(uploader.main(), 0, output.getvalue())
        payload = json.loads(output.getvalue())
        self.assertEqual(payload["selected"], [self.row["post_id"]])

    def test_manual_platform_filters_are_routed_away_from_draft_uploader(self) -> None:
        argv = self.uploader_argv(
            package_contract=self.package_contract,
            apply=False,
            platforms=["x", "instagram_reels"],
        )
        output = io.StringIO()
        with mock.patch.object(uploader, "ROOT", self.root), mock.patch.object(
            sys, "argv", argv
        ), redirect_stdout(output):
            self.assertEqual(uploader.main(), 2, output.getvalue())
        self.assertIn("dedicated public X adapter", output.getvalue())
        self.assertIn("manual Instagram release package lane", output.getvalue())

    def test_release_projector_is_local_and_run_scoped(self) -> None:
        argv = [
            "idol_social_release_sync.py",
            "--run-root",
            self.run_rel,
            "--content-id",
            self.content_id,
            "--queue",
            self.queue.relative_to(self.root).as_posix(),
            "--package-contract",
            self.package_contract.relative_to(self.root).as_posix(),
            "--package",
            self.package.relative_to(self.root).as_posix(),
            "--publishing-plan",
            self.plan.relative_to(self.root).as_posix(),
            "--registry",
            self.registry.relative_to(self.root).as_posix(),
            "--projected-at",
            "2026-07-10T11:30:00+09:00",
            "--apply",
        ]
        output = io.StringIO()
        with mock.patch.object(release_sync, "ROOT", self.root), mock.patch.object(
            sys, "argv", argv
        ), redirect_stdout(output):
            self.assertEqual(release_sync.main(), 0, output.getvalue())
        updated = json.loads(self.queue.read_text().splitlines()[0])
        self.assertEqual(updated["release_approval_status"], "pending_founder_approval")
        self.assertEqual(updated["release_approval_artifact"], "")
        self.assertTrue((self.package / "README.md").is_file())
        self.assertIn("## Release Approval Sync", self.plan.read_text())
        registry = yaml.safe_load(self.registry.read_text())
        self.assertEqual(registry["status"], "packaged")
        registry_schema = json.loads(
            (REPO / "schemas/title-output-registry.schema.json").read_text()
        )
        publishing_validator.jsonschema.validate(registry, registry_schema)
        result = json.loads(output.getvalue().splitlines()[-1])
        journal = self.root / result["recovery_journal"]
        self.assertEqual(json.loads(journal.read_text())["status"], "committed")

    def test_release_projector_apply_cannot_skip_title_registry(self) -> None:
        argv = [
            "idol_social_release_sync.py",
            "--run-root",
            self.run_rel,
            "--content-id",
            self.content_id,
            "--queue",
            self.queue.relative_to(self.root).as_posix(),
            "--package-contract",
            self.package_contract.relative_to(self.root).as_posix(),
            "--package",
            self.package.relative_to(self.root).as_posix(),
            "--publishing-plan",
            self.plan.relative_to(self.root).as_posix(),
            "--registry",
            self.registry.relative_to(self.root).as_posix(),
            "--projected-at",
            "2026-07-10T11:30:00+09:00",
            "--apply",
            "--skip-title-registry",
        ]
        original_queue = self.queue.read_bytes()
        original_plan = self.plan.read_bytes()
        original_registry = self.registry.read_bytes()
        output = io.StringIO()
        with mock.patch.object(release_sync, "ROOT", self.root), mock.patch.object(
            sys, "argv", argv
        ), redirect_stdout(output):
            self.assertEqual(release_sync.main(), 2, output.getvalue())
        self.assertIn("cannot use --skip-title-registry", output.getvalue())
        self.assertEqual(self.queue.read_bytes(), original_queue)
        self.assertEqual(self.plan.read_bytes(), original_plan)
        self.assertEqual(self.registry.read_bytes(), original_registry)
        self.assertFalse(self.package.exists())

    def test_release_projector_rejects_archived_publishing_plan(self) -> None:
        self.plan.write_text(
            self.plan.read_text(encoding="utf-8").replace("status: draft", "status: archived"),
            encoding="utf-8",
        )
        argv = [
            "idol_social_release_sync.py",
            "--run-root",
            self.run_rel,
            "--content-id",
            self.content_id,
            "--queue",
            self.queue.relative_to(self.root).as_posix(),
            "--package-contract",
            self.package_contract.relative_to(self.root).as_posix(),
            "--package",
            self.package.relative_to(self.root).as_posix(),
            "--publishing-plan",
            self.plan.relative_to(self.root).as_posix(),
            "--registry",
            self.registry.relative_to(self.root).as_posix(),
            "--projected-at",
            "2026-07-10T11:30:00+09:00",
            "--apply",
        ]
        original_queue = self.queue.read_bytes()
        original_registry = self.registry.read_bytes()
        output = io.StringIO()
        with mock.patch.object(release_sync, "ROOT", self.root), mock.patch.object(
            sys, "argv", argv
        ), redirect_stdout(output):
            self.assertEqual(release_sync.main(), 2, output.getvalue())
        self.assertIn("immutable closed state", output.getvalue())
        self.assertEqual(self.queue.read_bytes(), original_queue)
        self.assertEqual(self.registry.read_bytes(), original_registry)
        self.assertFalse(self.package.exists())

    def test_release_projector_applies_only_hash_bound_approved_rows(self) -> None:
        approval, approval_sha = self.approval(["manual_draft_upload", "platform_draft_upload"])
        argv = [
            "idol_social_release_sync.py",
            "--run-root",
            self.run_rel,
            "--content-id",
            self.content_id,
            "--queue",
            self.queue.relative_to(self.root).as_posix(),
            "--package-contract",
            self.package_contract.relative_to(self.root).as_posix(),
            "--package",
            self.package.relative_to(self.root).as_posix(),
            "--publishing-plan",
            self.plan.relative_to(self.root).as_posix(),
            "--registry",
            self.registry.relative_to(self.root).as_posix(),
            "--projected-at",
            "2026-07-10T11:30:00+09:00",
            "--approval-status",
            "approved_for_manual_draft_upload",
            "--approval-artifact",
            approval.relative_to(self.root).as_posix(),
            "--approval-sha256",
            approval_sha,
            "--apply",
        ]
        output = io.StringIO()
        with mock.patch.object(release_sync, "ROOT", self.root), mock.patch.object(
            sys, "argv", argv
        ), redirect_stdout(output):
            self.assertEqual(release_sync.main(), 0, output.getvalue())
        updated = json.loads(self.queue.read_text().splitlines()[0])
        self.assertEqual(updated["release_approval_artifact_sha256"], approval_sha)
        self.assertEqual(
            queue_approval_sha256([updated]),
            yaml.safe_load(approval.read_text())["queue_sha256"],
        )

    def test_release_projector_rejects_package_changed_after_approval(self) -> None:
        approval, approval_sha = self.approval(
            ["manual_draft_upload", "platform_draft_upload"]
        )
        document = yaml.safe_load(self.package_contract.read_text(encoding="utf-8"))
        document["deliverable_policy"]["social_clip_source"] = "changed after approval"
        self.package_contract.write_text(
            yaml.safe_dump(document, sort_keys=False), encoding="utf-8"
        )
        original_queue = self.queue.read_bytes()
        argv = [
            "idol_social_release_sync.py",
            "--run-root",
            self.run_rel,
            "--content-id",
            self.content_id,
            "--queue",
            self.queue.relative_to(self.root).as_posix(),
            "--package-contract",
            self.package_contract.relative_to(self.root).as_posix(),
            "--package",
            self.package.relative_to(self.root).as_posix(),
            "--publishing-plan",
            self.plan.relative_to(self.root).as_posix(),
            "--registry",
            self.registry.relative_to(self.root).as_posix(),
            "--projected-at",
            "2026-07-10T11:30:00+09:00",
            "--approval-status",
            "approved_for_manual_draft_upload",
            "--approval-artifact",
            approval.relative_to(self.root).as_posix(),
            "--approval-sha256",
            approval_sha,
            "--apply",
        ]
        output = io.StringIO()
        with mock.patch.object(release_sync, "ROOT", self.root), mock.patch.object(
            sys, "argv", argv
        ), redirect_stdout(output):
            self.assertEqual(release_sync.main(), 2, output.getvalue())
        self.assertEqual(self.queue.read_bytes(), original_queue)
        self.assertIn("package_contract_sha256 is stale or mismatched", output.getvalue())

    def test_manual_package_replaces_same_size_stale_bytes_by_hash(self) -> None:
        row = dict(self.row)
        row["release_asset_sha256"] = sha256_file(self.asset)
        package_root = self.batch / "manual-upload-package-hash-test"
        dirname = release_sync.platform_dir(str(row["platform"]))
        video_name, _text_name = release_sync.package_names(row)
        target = package_root / dirname / video_name
        target.parent.mkdir(parents=True)
        target.write_bytes(b"Z" * len(self.asset.read_bytes()))
        with mock.patch.object(release_sync, "ROOT", self.root):
            release_sync.sync_packages(
                [row],
                package_root=package_root,
                run_path=self.run,
                content_id=self.content_id,
                status="pending_founder_approval",
                projected_at="2026-07-10T11:30:00+09:00",
            )
        self.assertEqual(target.read_bytes(), self.asset.read_bytes())

    def test_atomic_projection_rolls_back_after_late_replace_failure(self) -> None:
        root = self.batch / "transaction-test"
        root.mkdir(parents=True)
        destination_one = root / "one.txt"
        destination_two = root / "two.txt"
        stage_one = root / ".one.stage"
        stage_two = root / ".two.stage"
        journal = root / "journal.json"
        destination_one.write_text("old-one")
        destination_two.write_text("old-two")
        stage_one.write_text("new-one")
        stage_two.write_text("new-two")
        original_replace = release_sync.os.replace

        def fail_second_stage(source: object, destination: object) -> None:
            if Path(source) == stage_two and Path(destination) == destination_two:
                raise OSError("injected late replace failure")
            original_replace(source, destination)

        with mock.patch.object(release_sync.os, "replace", side_effect=fail_second_stage):
            with self.assertRaises(SocialContractError):
                release_sync.commit_projection(
                    staged_destinations=[
                        (stage_one, destination_one),
                        (stage_two, destination_two),
                    ],
                    journal_path=journal,
                    projection_digest_value="a" * 64,
                )
        self.assertEqual(destination_one.read_text(), "old-one")
        self.assertEqual(destination_two.read_text(), "old-two")
        self.assertEqual(json.loads(journal.read_text())["status"], "rolled_back")

    def test_pulso_closed_record_and_final_package_audit_migration_gate(self) -> None:
        plan = REPO / "runs/2026-06-11/0611_WORLD_CUP_PULSO/publishing-plan.md"
        self.assertEqual(publishing_validator.detect_mode(plan), "closed")
        record = publishing_validator.extract_contract(plan, mode="closed")
        record_schema = json.loads((REPO / "schemas/publishing-record.schema.json").read_text())
        publishing_validator.jsonschema.validate(record, record_schema)

        package = yaml.safe_load(
            (REPO / "runs/2026-06-11/0611_WORLD_CUP_PULSO/05-package.yaml").read_text()
        )
        package_schema = json.loads((REPO / "schemas/package.schema.json").read_text())
        with self.assertRaises(publishing_validator.jsonschema.ValidationError):
            publishing_validator.jsonschema.validate(package, package_schema)

        package["source_contracts"].update(
            {
                "finishing_fx_map": {
                    "artifact_type": "finishing_fx_map",
                    "schema_version": "idol_edit_finishing_fx.v2",
                    "path": "generations/video/qc/finishing-fx-v1/04FX-finishing-map-v1.yaml",
                    "sha256": "1" * 64,
                    "validation_status": "pass",
                },
                "finishing_fx_compile_manifest": {
                    "artifact_type": "finishing_fx_compile_manifest",
                    "schema_version": "idol_04fx_compile_manifest.v1",
                    "path": "generations/video/qc/finishing-fx-v1/final-compile-manifest-v1.yaml",
                    "sha256": "2" * 64,
                    "validation_status": "pass",
                },
                "final_render_manifest": {
                    "artifact_type": "final_render_manifest",
                    "schema_version": "idol_edit_render_manifest.v1",
                    "path": "generations/video/qc/final-render-manifest-v1.yaml",
                    "sha256": "3" * 64,
                    "validation_status": "pass",
                },
            }
        )
        with self.assertRaises(publishing_validator.jsonschema.ValidationError):
            publishing_validator.jsonschema.validate(package, package_schema)


if __name__ == "__main__":
    unittest.main()
