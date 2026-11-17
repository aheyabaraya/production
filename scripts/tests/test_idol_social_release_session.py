#!/usr/bin/env python3
"""No-network tests for the one-review social release session."""

from __future__ import annotations

import io
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

import idol_social_release_session as release_session  # noqa: E402


class SocialReleaseSessionTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.content_id = "TEST_SOCIAL_001"
        self.run_rel = "runs/aurora-m/test-social/test-run-001"
        self.run = self.root / self.run_rel
        self.batch = self.run / "exports/social/batch-v1"
        self.queue = self.batch / "platform-posts.jsonl"
        self.asset = self.run / "generations/social/final-vertical.mp4"
        self.registry = self.root / "catalog/albums/aurora-m/test-social/output-registry.yaml"
        self.posts = self.root / "analytics/records/platform-posts.jsonl"
        self.metrics = self.root / "analytics/records/platform-metrics.jsonl"
        self.publications = self.root / "web/data/signalDeckPublications.json"
        for path in (self.queue, self.asset, self.registry, self.posts, self.metrics, self.publications):
            path.parent.mkdir(parents=True, exist_ok=True)
        (self.root / "schemas").mkdir(parents=True, exist_ok=True)
        for name in (
            "social-release-session.schema.json",
            "publishing-plan.schema.json",
            "social-analytics.schema.json",
            "package.schema.json",
            "platform-release-approval.schema.json",
        ):
            (self.root / "schemas" / name).write_bytes((REPO / "schemas" / name).read_bytes())

        (self.run / "run-manifest.yaml").write_text(
            yaml.safe_dump(
                {
                    "schema_version": "idol-run-manifest.v1",
                    "status": "active",
                    "album_key": "aurora-m",
                    "title_key": "test-social",
                    "run_id": "test-run-001",
                    "content_id": self.content_id,
                    "canonical_run_root": self.run_rel,
                    "artifact_revision_owner": "git",
                    "compatibility_authoring": "forbidden",
                },
                sort_keys=False,
            ),
            encoding="utf-8",
        )
        edit_map = self.run / "04-edit-map.yaml"
        screen_node = {
            "screen_progression_map_id": "SPM_TEST_SOCIAL_001",
            "screen_progression_node_id": "SPN_TEST_SOCIAL_001_R01",
            "section_id": "S01",
            "major_scene_id": "MJ01",
            "core_cut_id": "C01",
            "branch_cut_ids": ["BC01"],
            "source_03v_cue_ids": ["03VCUE_TEST_SOCIAL_001_R01"],
            "storyline_role": "resolve",
            "observable_screen_proof": "The finished fixture shows the reviewed resolution.",
        }
        edit_map.write_text(
            yaml.safe_dump(
                {
                    "schema_version": "idol_edit_map.v4",
                    "content_id": self.content_id,
                    "status": "local_complete",
                    "edit_unit_screen_progression_nodes": [
                        {"edit_unit_id": "SEG_TEST_R01", **screen_node}
                    ],
                },
                sort_keys=False,
            ),
            encoding="utf-8",
        )
        recipe = self.run / "generations/video/qc/final-recipe-v1.yaml"
        recipe.parent.mkdir(parents=True, exist_ok=True)
        recipe.write_text(
            yaml.safe_dump(
                {
                    "schema_version": "idol_edit_recipe.v3",
                    "content_id": self.content_id,
                    "timeline": [
                        {
                            "segment_id": "SEG_TEST_R01",
                            "section_ids": ["S01"],
                            "screen_progression_node": screen_node,
                        }
                    ],
                },
                sort_keys=False,
            ),
            encoding="utf-8",
        )
        self.asset.write_bytes(b"finished-content-bytes")
        asset_rel = self.asset.relative_to(self.root).as_posix()
        asset_sha = release_session.sha256_file(self.asset)
        (self.run / "05-package.yaml").write_text(
            yaml.safe_dump(
                {
                    "schema_version": "idol_package.v2",
                    "content_id": self.content_id,
                    "status": "ready_for_social_planning",
                    "created_at_kst": "2026-08-09T12:00:00+09:00",
                    "created_by": "test",
                    "source_contracts": {"edit_map": edit_map.relative_to(self.root).as_posix()},
                    "final_master": {
                        "output_id": "test_social_master",
                        "path": asset_rel,
                        "sha256": asset_sha,
                        "role": "short_derivative",
                    },
                    "package_outputs": {
                        "short_derivatives": {
                            "output_id": "test_social_short",
                            "path": asset_rel,
                            "sha256": asset_sha,
                            "role": "short_derivative",
                        }
                    },
                    "production_graph_trace": {
                        "schema_version": "idol_05_production_graph_trace.v1",
                        "source_edit_map": {
                            "artifact_type": "edit_map",
                            "schema_version": "idol_edit_map.v4",
                            "path": edit_map.relative_to(self.root).as_posix(),
                            "sha256": release_session.sha256_file(edit_map),
                            "json_pointer": "/edit_unit_screen_progression_nodes",
                        },
                        "source_edit_recipe": {
                            "artifact_type": "edit_recipe",
                            "schema_version": "idol_edit_recipe.v3",
                            "path": recipe.relative_to(self.root).as_posix(),
                            "sha256": release_session.sha256_file(recipe),
                            "json_pointer": "/timeline",
                        },
                        "deliverable_bindings": [
                            {
                                "output_id": output_id,
                                "edit_segment_ids": ["SEG_TEST_R01"],
                                "screen_progression_node_ids": [
                                    "SPN_TEST_SOCIAL_001_R01"
                                ],
                                "section_ids": ["S01"],
                            }
                            for output_id in ("test_social_master", "test_social_short")
                        ],
                        "post05_mutation_boundary": (
                            "post05_release_and_analytics_are_append_only_evidence_"
                            "and_never_mutate_mv_truth"
                        ),
                    },
                    "deliverable_policy": {
                        "master_release_source": "test_social_master",
                        "social_clip_source": "test_social_short",
                        "raw_source_upload_policy": "exact finished bytes only",
                    },
                    "approval_gates": {
                        "local_final_master": "hash verified",
                        "public_release": "Founder approval required",
                        "upload_or_schedule": "Founder approval required",
                        "external_sync": "Founder approval required",
                    },
                },
                sort_keys=False,
            ),
            encoding="utf-8",
        )
        self.row = {
            "post_id": f"{self.content_id}-YS-001",
            "content_id": self.content_id,
            "platform": "youtube_shorts",
            "template_type": "clip",
            "message": "One finished signal.",
            "asset_or_clip": asset_rel,
            "caption": "One finished signal.\n\n#AI #AIIdol #Kpop #VirtualIdol #Loom",
            "hashtags": ["#AI", "#AIIdol", "#Kpop", "#VirtualIdol", "#Loom"],
            "scheduled_at": "2026-08-09T18:00:00+09:00",
            "status": "planned",
            "analysis_scope": "date_based",
            "delivery_mode": "platform_draft",
            "tracking_code": "TEST-YS-001",
            "draft_status": "not_uploaded",
        }
        self.write_queue(self.row)
        (self.run / "publishing-plan.md").write_text(
            "\n".join(
                [
                    f"content_id: {self.content_id}",
                    "public_group_name: Loom",
                    "public_fan_name: Harne",
                    "status: founder_review",
                    "created_at_kst: 2026-08-09T12:00:00+09:00",
                    "updated_at_kst: 2026-08-09T12:00:00+09:00",
                    "",
                    "## Scope",
                    "One local social batch.",
                    "",
                    "## Tracking Convention",
                    "Use post_id.",
                    "",
                    "## Draft Queue",
                    "",
                    "| Post ID | Platform | Draft slot KST | Clip | Caption / title |",
                    "| --- | --- | --- | --- | --- |",
                    f"| {self.row['post_id']} | youtube_shorts | 18:00 | final-vertical.mp4 | One finished signal. |",
                    "",
                    "## Approval State",
                    "Pending one Founder decision.",
                    "",
                ]
            ),
            encoding="utf-8",
        )
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
                            "first_registered_at": "2026-08-09T12:00:00+09:00",
                            "last_updated_at": "2026-08-09T12:00:00+09:00",
                        }
                    ],
                    "output_roots": {
                        "title_root": "catalog/albums/aurora-m/test-social",
                        "run_roots": [self.run_rel],
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
        self.posts.write_text(json.dumps(self.row) + "\n", encoding="utf-8")
        self.metrics.write_text("", encoding="utf-8")
        self.publications.write_text(
            json.dumps(
                {
                    "schema_version": "idol_signal_deck_publication.v1",
                    "status": "active",
                    "publications": [],
                }
            )
            + "\n",
            encoding="utf-8",
        )
        self.root_patch = mock.patch.multiple(
            release_session,
            ROOT=self.root,
            SESSION_SCHEMA=self.root / "schemas/social-release-session.schema.json",
            PLAN_SCHEMA=self.root / "schemas/publishing-plan.schema.json",
            GLOBAL_POSTS=self.posts,
            GLOBAL_METRICS=self.metrics,
            WEB_PUBLICATIONS=self.publications,
        )
        self.root_patch.start()
        self.addCleanup(self.root_patch.stop)

    def tearDown(self) -> None:
        self.temp.cleanup()

    def write_queue(self, row: dict[str, object]) -> None:
        self.queue.write_text(json.dumps(row, ensure_ascii=False) + "\n", encoding="utf-8")

    def invoke(self, *args: str) -> tuple[int, dict[str, object]]:
        output = io.StringIO()
        with mock.patch.object(sys, "argv", ["idol_social_release_session.py", *args]), redirect_stdout(output):
            code = release_session.main()
        return code, json.loads(output.getvalue())

    def register(self) -> dict[str, object]:
        code, result = self.invoke(
            "register",
            "--run-root",
            self.run_rel,
            "--queue",
            self.queue.relative_to(self.root).as_posix(),
            "--registry",
            self.registry.relative_to(self.root).as_posix(),
            "--at",
            "2026-08-09T12:00:00+09:00",
            "--apply",
        )
        self.assertEqual(0, code, result)
        return result

    def refresh(self, at: str = "2026-08-09T12:10:00+09:00") -> dict[str, object]:
        code, result = self.invoke(
            "refresh",
            "--session",
            f"{self.run_rel}/review/{release_session.SESSION_NAME}",
            "--at",
            at,
            "--apply",
        )
        self.assertEqual(0, code, result)
        return result

    def test_register_writes_one_founder_packet_with_zero_external_actions(self) -> None:
        result = self.register()
        self.assertEqual("founder_review", result["status"])
        self.assertEqual(0, result["external_actions"])
        session = json.loads((self.run / "review" / release_session.SESSION_NAME).read_text())
        self.assertEqual("founder_decision", session["next_action"])
        packet = (self.run / "review" / release_session.PACKET_NAME).read_text()
        self.assertIn("답변은 한 번만", packet)
        self.assertIn("PASS DRAFT", packet)

    def test_refresh_skips_exactly_unchanged_state_without_rewrite(self) -> None:
        self.register()
        session_path = self.run / "review" / release_session.SESSION_NAME
        packet_path = self.run / "review" / release_session.PACKET_NAME
        before = (session_path.read_bytes(), packet_path.read_bytes())
        result = self.refresh()
        after = (session_path.read_bytes(), packet_path.read_bytes())
        self.assertEqual("unchanged", result["mode"])
        self.assertFalse(result["changed"])
        self.assertEqual(before, after)

    def test_exact_approval_advances_without_a_second_founder_decision(self) -> None:
        self.register()
        session = json.loads((self.run / "review" / release_session.SESSION_NAME).read_text())
        approval = {
            "schema_version": "idol_platform_release_approval.v1",
            "approval_id": "APPROVAL_TEST_SOCIAL_001",
            "status": "active",
            "run_root": self.run_rel,
            "content_id": self.content_id,
            "queue_path": session["source_bindings"]["queue"]["path"],
            "queue_sha256": session["source_bindings"]["queue"]["action_sha256"],
            "package_contract_path": session["source_bindings"]["package_contract"]["path"],
            "package_contract_sha256": session["source_bindings"]["package_contract"]["sha256"],
            "package_deliverable_manifest_sha256": session["source_bindings"]["package_contract"]["deliverable_manifest_sha256"],
            "allowed_actions": ["platform_draft_upload"],
            "approved_platforms": ["youtube_shorts"],
            "approved_post_ids": [self.row["post_id"]],
            "approved_assets": [
                {
                    "post_id": self.row["post_id"],
                    "path": self.row["asset_or_clip"],
                    "sha256": release_session.sha256_file(self.asset),
                }
            ],
            "founder_explicit_approval": True,
            "approval_source": "Founder exact reply: PASS DRAFT",
            "approved_at_kst": "2026-08-09T12:05:00+09:00",
            "approval_note": "Exact queue and bytes only.",
        }
        approval_path = self.run / "review/platform-release-approval-v1.json"
        approval_path.write_text(json.dumps(approval, indent=2) + "\n", encoding="utf-8")
        result = self.refresh()
        self.assertEqual("approved_waiting_external", result["status"])
        self.assertEqual("external_action_requires_current_authority", result["next_action"])
        packet = (self.run / "review" / release_session.PACKET_NAME).read_text()
        self.assertIn("재판단 불필요", packet)

    def test_action_copy_change_invalidates_stale_approval(self) -> None:
        self.test_exact_approval_advances_without_a_second_founder_decision()
        changed = dict(self.row)
        changed["caption"] = "A corrected exact line.\n\n#AI #AIIdol #Kpop #VirtualIdol #Loom"
        self.write_queue(changed)
        result = self.refresh("2026-08-09T12:20:00+09:00")
        self.assertEqual("founder_review", result["status"])
        self.assertTrue(any("stale_or_invalid_approval" in item for item in result["warnings"]))

    def test_public_closeout_and_three_fixed_windows_complete_session(self) -> None:
        self.register()
        published = dict(self.row)
        published.update(
            {
                "status": "published",
                "published_url": "https://youtube.com/shorts/AbCdEf12345",
                "platform_post_id": "AbCdEf12345",
                "published_at": "2026-08-09T18:01:00+09:00",
            }
        )
        self.posts.write_text(json.dumps(published) + "\n", encoding="utf-8")
        self.publications.write_text(
            json.dumps(
                {
                    "schema_version": "idol_signal_deck_publication.v1",
                    "status": "active",
                    "publications": [
                        {"post_id": self.row["post_id"], "content_id": self.content_id}
                    ],
                }
            )
            + "\n",
            encoding="utf-8",
        )
        first = self.refresh("2026-08-09T18:02:00+09:00")
        self.assertEqual("closed_metrics_due", first["status"])
        rows = []
        for index, window in enumerate(release_session.FIXED_WINDOWS):
            rows.append(
                {
                    "captured_at": f"2026-08-{10 + index:02d}T18:01:00+09:00",
                    "observed_date": f"2026-08-{10 + index:02d}",
                    "post_id": self.row["post_id"],
                    "content_id": self.content_id,
                    "platform": "youtube_shorts",
                    "views": 10 + index,
                    "engagement": index,
                    "source": "test_fixed_checkpoint",
                    "measurement_window": window,
                    "checkpoint_target_at": f"2026-08-{10 + index:02d}T18:01:00+09:00",
                    "checkpoint_lag_seconds": 0,
                }
            )
        self.metrics.write_text("\n".join(json.dumps(row) for row in rows) + "\n", encoding="utf-8")
        final = self.refresh("2026-08-17T18:02:00+09:00")
        self.assertEqual("measured", final["status"])
        self.assertEqual("none", final["next_action"])


if __name__ == "__main__":
    unittest.main()
