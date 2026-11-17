from __future__ import annotations

import hashlib
import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

import yaml


REPO = Path(__file__).resolve().parents[2]
VIDEO_PYTHON = REPO / "scripts/idol-video-python"
SCRIPT = REPO / "scripts/idol_social_public_closeout.py"


class SocialPublicCloseoutTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.run = self.root / "runs/aurora-m/demo-track/demo-run"
        self.queue = self.run / "exports/social/demo/platform-posts.jsonl"
        self.closeout = self.run / "review/public-closeout.json"
        self.posts = self.root / "analytics/records/platform-posts.jsonl"
        self.metrics = self.root / "analytics/records/platform-metrics.jsonl"
        self.publications = self.root / "web/data/signalDeckPublications.json"
        self.registry = self.root / "catalog/albums/aurora-m/demo-track/output-registry.yaml"
        self.source_visual = self.run / "generations/image/demo-hero.webp"
        self.web_visual = self.root / "web/public/assets/tracks/demo/demo-hero.webp"
        self.run_asset = self.run / "generations/video/master/demo.mp4"

        for path in (
            self.queue,
            self.closeout,
            self.posts,
            self.metrics,
            self.publications,
            self.registry,
            self.source_visual,
            self.web_visual,
            self.run_asset,
        ):
            path.parent.mkdir(parents=True, exist_ok=True)

        (self.root / "schemas").mkdir(parents=True, exist_ok=True)
        shutil.copy2(
            REPO / "schemas/signal-deck-publication.schema.json",
            self.root / "schemas/signal-deck-publication.schema.json",
        )
        shutil.copy2(
            REPO / "schemas/package.schema.json",
            self.root / "schemas/package.schema.json",
        )
        (self.root / "scripts").mkdir(parents=True, exist_ok=True)
        shutil.copy2(
            REPO / "scripts/validate_social_analytics.rb",
            self.root / "scripts/validate_social_analytics.rb",
        )
        (self.root / "scripts/lib").mkdir(parents=True, exist_ok=True)
        shutil.copy2(
            REPO / "scripts/lib/idol_social_taxonomy.rb",
            self.root / "scripts/lib/idol_social_taxonomy.rb",
        )
        (self.root / "web/data/tracks.ts").write_text(
            'export const tracks = [{ id: "loom-track-demo", title: "Demo" }];\n',
            encoding="utf-8",
        )
        (self.root / "web/data/cf.ts").write_text("export const cfCampaigns = [];\n", encoding="utf-8")

        visual_bytes = b"webp-fixture-bytes"
        visual_sha = hashlib.sha256(visual_bytes).hexdigest()
        self.source_visual.write_bytes(visual_bytes)
        self.web_visual.write_bytes(visual_bytes)
        self.run_asset.write_bytes(b"video-fixture-bytes")

        self.row = {
            "post_id": "DEMO_TRACK_001-YS-001",
            "content_id": "DEMO_TRACK_001",
            "platform": "youtube_shorts",
            "template_type": "clip",
            "message": "A demo signal opens.",
            "asset_or_clip": "runs/aurora-m/demo-track/demo-run/generations/video/master/demo.mp4",
            "caption": "A demo signal opens.",
            "hashtags": ["#AI", "#AIIdol", "#Kpop", "#VirtualIdol", "#Loom"],
            "scheduled_at": "2026-08-01T12:00:00+09:00",
            "status": "planned",
            "analysis_scope": "date_based",
            "tracking_code": "DEMO-YS-001",
        }
        row_line = json.dumps(self.row, ensure_ascii=False) + "\n"
        self.posts.write_text(row_line, encoding="utf-8")
        self.queue.write_text(row_line, encoding="utf-8")
        self.metrics.write_text("", encoding="utf-8")
        self.publications.write_text(
            json.dumps(
                {
                    "schema_version": "idol_signal_deck_publication.v1",
                    "status": "active",
                    "publications": [],
                },
                indent=2,
            )
            + "\n",
            encoding="utf-8",
        )
        self.registry.write_text(
            yaml.safe_dump(
                {
                    "schema_version": "1.1",
                    "album_key": "aurora-m",
                    "title_key": "demo-track",
                    "title_display_name": "Demo Track",
                    "status": "packaged",
                    "canonical_title_root": "catalog/albums/aurora-m/demo-track",
                    "content_ids": ["DEMO_TRACK_001"],
                    "source_runs": [
                        {
                            "run_root": "runs/aurora-m/demo-track/demo-run",
                            "content_id": "DEMO_TRACK_001",
                            "role": "production_run",
                            "first_registered_at": "2026-08-01T12:00:00+09:00",
                            "last_updated_at": "2026-08-01T12:00:00+09:00",
                        }
                    ],
                    "output_roots": {
                        "title_root": "catalog/albums/aurora-m/demo-track",
                        "run_roots": ["runs/aurora-m/demo-track/demo-run"],
                        "branch_cut_images": "runs/aurora-m/demo-track/demo-run/generations/branch-cuts/",
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
                allow_unicode=True,
                sort_keys=False,
            ),
            encoding="utf-8",
        )
        self.closeout.write_text(
            json.dumps(
                {
                    "schema_version": "idol_social_public_closeout.v1",
                    "post_id": self.row["post_id"],
                    "content_id": self.row["content_id"],
                    "platform": "youtube_shorts",
                    "published_url": "https://youtube.com/shorts/AbCdEf12345",
                    "published_at": "2026-08-01T12:10:00+09:00",
                    "run_root": "runs/aurora-m/demo-track/demo-run",
                    "source_queue": "runs/aurora-m/demo-track/demo-run/exports/social/demo/platform-posts.jsonl",
                    "title_registry": "catalog/albums/aurora-m/demo-track/output-registry.yaml",
                    "signal_deck": {
                        "content_kind": "mv",
                        "content_label": "Demo Track",
                        "title": "Demo Track · opening cut",
                        "member_visibility": "visible",
                        "member_codes": ["M01"],
                        "track_id": "loom-track-demo",
                        "duration": 12,
                        "visuals": [
                            {
                                "id": "demo-hero",
                                "member_codes": ["M01"],
                                "src": "/assets/tracks/demo/demo-hero.webp",
                                "alt": "M01 in the Demo Track opening visual",
                                "source_path": "runs/aurora-m/demo-track/demo-run/generations/image/demo-hero.webp",
                                "source_sha256": visual_sha,
                                "web_path": "web/public/assets/tracks/demo/demo-hero.webp",
                                "web_sha256": visual_sha,
                                "lineage_mode": "exact_copy",
                            }
                        ],
                    },
                },
                indent=2,
            )
            + "\n",
            encoding="utf-8",
        )

    def tearDown(self) -> None:
        self.temp.cleanup()

    def run_closeout(self, *extra: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [
                str(VIDEO_PYTHON),
                str(SCRIPT),
                "--root",
                str(self.root),
                "--closeout",
                self.closeout.relative_to(self.root).as_posix(),
                *extra,
            ],
            cwd=REPO,
            capture_output=True,
            text=True,
            check=False,
        )

    @staticmethod
    def object_digest(value: object) -> str:
        payload = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
        return hashlib.sha256(payload.encode("utf-8")).hexdigest()

    def enable_production_trace(self) -> None:
        edit_map = self.run / "04-edit-map.yaml"
        recipe = self.run / "generations/video/qc/final-recipe-v1.yaml"
        screen_node = {
            "screen_progression_map_id": "SPM_DEMO",
            "screen_progression_node_id": "SPN_DEMO_R01",
            "section_id": "S01",
            "major_scene_id": "MJ01",
            "core_cut_id": "C01",
            "branch_cut_ids": ["BC01"],
            "source_03v_cue_ids": ["03VCUE_DEMO_R01"],
            "storyline_role": "resolve",
            "observable_screen_proof": "The demo closes on the reviewed visible state.",
        }
        edit_map.write_text(
            yaml.safe_dump(
                {
                    "schema_version": "idol_edit_map.v4",
                    "content_id": "DEMO_TRACK_001",
                    "status": "qc_pass",
                    "edit_unit_screen_progression_nodes": [
                        {"edit_unit_id": "SEG_DEMO_R01", **screen_node}
                    ],
                },
                sort_keys=False,
            ),
            encoding="utf-8",
        )
        recipe.parent.mkdir(parents=True, exist_ok=True)
        recipe.write_text(
            yaml.safe_dump(
                {
                    "schema_version": "idol_edit_recipe.v3",
                    "content_id": "DEMO_TRACK_001",
                    "timeline": [
                        {
                            "segment_id": "SEG_DEMO_R01",
                            "section_ids": ["S01"],
                            "screen_progression_node": screen_node,
                        }
                    ],
                },
                sort_keys=False,
            ),
            encoding="utf-8",
        )
        source_map = {
            "artifact_type": "edit_map",
            "schema_version": "idol_edit_map.v4",
            "path": edit_map.relative_to(self.root).as_posix(),
            "sha256": hashlib.sha256(edit_map.read_bytes()).hexdigest(),
            "json_pointer": "/edit_unit_screen_progression_nodes",
        }
        source_recipe = {
            "artifact_type": "edit_recipe",
            "schema_version": "idol_edit_recipe.v3",
            "path": recipe.relative_to(self.root).as_posix(),
            "sha256": hashlib.sha256(recipe.read_bytes()).hexdigest(),
            "json_pointer": "/timeline",
        }
        binding = {
            "output_id": "OUT_DEMO_MASTER",
            "edit_segment_ids": ["SEG_DEMO_R01"],
            "screen_progression_node_ids": ["SPN_DEMO_R01"],
            "section_ids": ["S01"],
        }
        trace = {
            "schema_version": "idol_05_production_graph_trace.v1",
            "source_edit_map": source_map,
            "source_edit_recipe": source_recipe,
            "deliverable_bindings": [binding],
            "post05_mutation_boundary": (
                "post05_release_and_analytics_are_append_only_evidence_"
                "and_never_mutate_mv_truth"
            ),
        }
        asset_sha = hashlib.sha256(self.run_asset.read_bytes()).hexdigest()
        asset_rel = self.run_asset.relative_to(self.root).as_posix()
        package = {
            "schema_version": "idol_package.v2",
            "content_id": self.row["content_id"],
            "status": "packaged_ready_local",
            "created_at_kst": "2026-08-01T11:00:00+09:00",
            "created_by": "test",
            "source_contracts": {"edit_map": source_map["path"]},
            "final_master": {
                "output_id": "OUT_DEMO_MASTER",
                "path": asset_rel,
                "sha256": asset_sha,
                "role": "final_public_master",
            },
            "production_graph_trace": trace,
            "deliverable_policy": {
                "master_release_source": "OUT_DEMO_MASTER",
                "social_clip_source": "OUT_DEMO_MASTER",
                "raw_source_upload_policy": "never upload raw source",
            },
            "approval_gates": {
                "local_final_master": "hash verified",
                "public_release": "Founder approval required",
                "upload_or_schedule": "Founder approval required",
                "external_sync": "Founder approval required",
            },
        }
        package_path = self.run / "05-package.yaml"
        package_path.write_text(yaml.safe_dump(package, sort_keys=False), encoding="utf-8")
        normalized_trace = {
            "schema_version": trace["schema_version"],
            "source_edit_map": {
                "artifact_type": source_map["artifact_type"],
                "schema_version": source_map["schema_version"],
                "path": source_map["path"],
                "sha256": source_map["sha256"],
                "json_pointer": source_map["json_pointer"],
            },
            "source_edit_recipe": {
                "artifact_type": source_recipe["artifact_type"],
                "schema_version": source_recipe["schema_version"],
                "path": source_recipe["path"],
                "sha256": source_recipe["sha256"],
                "json_pointer": source_recipe["json_pointer"],
            },
            "deliverable_bindings": [binding],
            "post05_mutation_boundary": trace["post05_mutation_boundary"],
        }
        trace_sha = self.object_digest(normalized_trace)
        deliverable_manifest = {
            "schema_version": "idol_package.v2",
            "content_id": self.row["content_id"],
            "deliverables": [
                {
                    "output_id": "OUT_DEMO_MASTER",
                    "path": asset_rel,
                    "sha256": asset_sha,
                    "role": "final_public_master",
                    "edit_segment_ids": ["SEG_DEMO_R01"],
                    "screen_progression_node_ids": ["SPN_DEMO_R01"],
                    "section_ids": ["S01"],
                }
            ],
            "production_graph_trace_sha256": trace_sha,
        }
        queue_row = dict(self.row)
        queue_row.update(
            {
                "release_provenance_version": "idol_release_provenance.v2",
                "release_package_contract": package_path.relative_to(self.root).as_posix(),
                "release_package_contract_sha256": hashlib.sha256(
                    package_path.read_bytes()
                ).hexdigest(),
                "release_package_deliverable_manifest_sha256": self.object_digest(
                    deliverable_manifest
                ),
                "release_package_output_id": "OUT_DEMO_MASTER",
                "release_package_output_role": "final_public_master",
                "release_package_linkage": "exact_deliverable",
                "release_production_graph_trace_sha256": trace_sha,
                "release_edit_segment_ids": ["SEG_DEMO_R01"],
                "release_screen_progression_node_ids": ["SPN_DEMO_R01"],
                "release_section_ids": ["S01"],
                "release_asset_sha256": asset_sha,
            }
        )
        self.queue.write_text(json.dumps(queue_row) + "\n", encoding="utf-8")

    def test_dry_run_is_read_only(self) -> None:
        before = self.posts.read_bytes()
        completed = self.run_closeout()
        self.assertEqual(0, completed.returncode, completed.stdout + completed.stderr)
        self.assertEqual("dry_run_pass", json.loads(completed.stdout)["status"])
        self.assertEqual(before, self.posts.read_bytes())
        self.assertFalse(self.closeout.with_name("public-closeout.result.json").exists())

    def test_apply_updates_ledger_signal_deck_and_registry_once(self) -> None:
        first = self.run_closeout("--apply")
        self.assertEqual(0, first.returncode, first.stdout + first.stderr)

        post = json.loads(self.posts.read_text(encoding="utf-8"))
        self.assertEqual("published", post["status"])
        self.assertEqual("AbCdEf12345", post["platform_post_id"])
        self.assertEqual(["M01"], post["signal_deck_publication"]["member_codes"])

        publications = json.loads(self.publications.read_text(encoding="utf-8"))["publications"]
        self.assertEqual(1, len(publications))
        self.assertEqual("loom-track-demo", publications[0]["track_id"])

        registry = yaml.safe_load(self.registry.read_text(encoding="utf-8"))
        remote_rows = [row for row in registry["outputs"] if row["output_type"] == "remote_publication"]
        self.assertEqual(1, len(remote_rows))
        self.assertEqual("published", remote_rows[0]["status"])

        result_path = self.closeout.with_name("public-closeout.result.json")
        first_result_bytes = result_path.read_bytes()
        second = self.run_closeout("--apply")
        self.assertEqual(0, second.returncode, second.stdout + second.stderr)
        self.assertEqual("already_applied", json.loads(second.stdout)["status"])
        self.assertEqual(first_result_bytes, result_path.read_bytes())
        publications = json.loads(self.publications.read_text(encoding="utf-8"))["publications"]
        registry = yaml.safe_load(self.registry.read_text(encoding="utf-8"))
        remote_rows = [row for row in registry["outputs"] if row["output_type"] == "remote_publication"]
        self.assertEqual(1, len(publications))
        self.assertEqual(1, len(remote_rows))

    def test_apply_copies_verified_release_trace_into_analytics_evidence(self) -> None:
        self.enable_production_trace()
        completed = self.run_closeout("--apply")
        self.assertEqual(0, completed.returncode, completed.stdout + completed.stderr)
        post = json.loads(self.posts.read_text(encoding="utf-8"))
        self.assertEqual(["SEG_DEMO_R01"], post["release_edit_segment_ids"])
        self.assertEqual(["SPN_DEMO_R01"], post["release_screen_progression_node_ids"])
        self.assertEqual(["S01"], post["release_section_ids"])
        self.assertEqual("OUT_DEMO_MASTER", post["release_package_output_id"])

    def test_stale_graph_digest_holds_without_mutating_analytics(self) -> None:
        self.enable_production_trace()
        queue_row = json.loads(self.queue.read_text(encoding="utf-8"))
        queue_row["release_production_graph_trace_sha256"] = "0" * 64
        self.queue.write_text(json.dumps(queue_row) + "\n", encoding="utf-8")
        before = self.posts.read_bytes()
        completed = self.run_closeout("--apply")
        self.assertNotEqual(0, completed.returncode)
        self.assertEqual("hold", json.loads(completed.stdout)["status"])
        self.assertEqual(before, self.posts.read_bytes())

    def test_url_platform_mismatch_holds_without_writes(self) -> None:
        closeout = json.loads(self.closeout.read_text(encoding="utf-8"))
        closeout["published_url"] = "https://www.tiktok.com/@loom/video/123456789"
        self.closeout.write_text(json.dumps(closeout, indent=2) + "\n", encoding="utf-8")
        before = self.posts.read_bytes()

        completed = self.run_closeout("--apply")
        self.assertNotEqual(0, completed.returncode)
        self.assertEqual("hold", json.loads(completed.stdout)["status"])
        self.assertEqual(before, self.posts.read_bytes())


if __name__ == "__main__":
    unittest.main()
