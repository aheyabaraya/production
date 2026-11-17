#!/usr/bin/env python3

from __future__ import annotations

import json
import hashlib
import subprocess
import tempfile
import unittest
from pathlib import Path

import jsonschema
import yaml


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "idol_04fx_transition_opportunity_seed.py"
VIDEO_PYTHON = ROOT / "scripts" / "idol-video-python"
FX_SCHEMA = ROOT / "schemas" / "edit-finishing-fx.schema.json"


class TransitionOpportunitySeedTest(unittest.TestCase):
    def test_seed_is_mergeable_review_only_audit(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            tmp = Path(tmp_dir)
            recipe_path = tmp / "recipe.yaml"
            audio_path = tmp / "audio-summary.json"
            marker_path = tmp / "marker-plan.yaml"
            output_path = tmp / "seed.yaml"

            recipe = {
                "render_spec": {"fps": {"numerator": 24, "denominator": 1}},
                "timeline": [
                    {
                        "slot": "R01",
                        "marker_slot_ref": "R01",
                        "section_ids": ["S01"],
                        "output_in_frame": 0,
                        "output_out_frame": 24,
                    },
                    {
                        "slot": "R02",
                        "marker_slot_ref": "R02",
                        "section_ids": ["S01"],
                        "output_in_frame": 24,
                        "output_out_frame": 48,
                    },
                    {
                        "slot": "R03",
                        "marker_slot_ref": "R03",
                        "section_ids": ["S02"],
                        "output_in_frame": 48,
                        "output_out_frame": 72,
                    },
                ],
            }
            audio_summary = {
                "strong_onsets_ranked": [
                    {"time_seconds": 1.0},
                    {"time_seconds": 2.0},
                ],
                "energy_jump_candidates": [{"time_seconds": 1.5}],
            }
            marker_plan = {
                "timeline_slots": [
                    self.marker_row("R02"),
                    self.marker_row("R03"),
                ]
            }

            recipe_path.write_text(yaml.safe_dump(recipe, sort_keys=False))
            audio_path.write_text(json.dumps(audio_summary))
            marker_path.write_text(yaml.safe_dump(marker_plan, sort_keys=False))

            subprocess.run(
                [
                    str(VIDEO_PYTHON),
                    str(SCRIPT),
                    "--recipe",
                    str(recipe_path),
                    "--audio-summary",
                    str(audio_path),
                    "--marker-plan",
                    str(marker_path),
                    "--output",
                    str(output_path),
                ],
                cwd=ROOT,
                check=True,
                capture_output=True,
                text=True,
            )

            seed = yaml.safe_load(output_path.read_text())
            audit = seed["transition_opportunity_audit"]
            points = audit["points"]

            self.assertTrue(points)
            self.assertEqual(
                {point["disposition"] for point in points}, {"review_candidate"}
            )
            forbidden = {
                "from_slot",
                "to_slot",
                "proposed_effect_type",
                "fx_id_ref",
            }
            for point in points:
                self.assertFalse(forbidden.intersection(point))

            boundary_points = [
                point for point in points if point["kind"] == "section_boundary"
            ]
            self.assertEqual(len(boundary_points), 1)
            self.assertEqual(boundary_points[0]["program_frame"], 48)
            same_section_point = next(
                point for point in points if point["program_frame"] == 24
            )
            self.assertNotEqual(same_section_point["kind"], "section_boundary")

            evidence = seed["evidence_index"]
            same_section_evidence = evidence[same_section_point["point_id"]]
            covered_recipe_cut = next(
                event
                for event in same_section_evidence["coverage_events"]
                if event["event_id"].startswith("recipe_cut:")
            )
            self.assertEqual(covered_recipe_cut["outgoing_slot"], "R01")
            self.assertEqual(covered_recipe_cut["incoming_slot"], "R02")
            self.assertFalse(
                any(
                    event["event_id"].startswith("recipe_section:")
                    for event in same_section_evidence["coverage_events"]
                )
            )
            all_covered_ids = {
                event_id
                for point in points
                for event_id in point["coverage_event_ids"]
            }
            coverage = audit["coverage_contract"]
            self.assertEqual(coverage["expected_event_count"], len(all_covered_ids))
            self.assertEqual(coverage["covered_event_count"], len(all_covered_ids))
            self.assertEqual(
                coverage["expected_event_ids_sha256"],
                self.coverage_digest(all_covered_ids),
            )
            self.assertEqual(
                coverage["covered_event_ids_sha256"],
                self.coverage_digest(all_covered_ids),
            )
            self.assertEqual(seed["seed_summary"]["effect_preselection_count"], 0)

            schema = json.loads(FX_SCHEMA.read_text())
            candidate_map = self.minimal_fx_map(audit, recipe_path)
            errors = sorted(
                jsonschema.Draft202012Validator(schema).iter_errors(candidate_map),
                key=lambda error: list(error.absolute_path),
            )
            self.assertEqual([], [error.message for error in errors])

    def test_seed_has_no_24_item_cap_and_includes_standalone_lyric_marker_gates(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            tmp = Path(tmp_dir)
            recipe_path = tmp / "recipe.yaml"
            audio_path = tmp / "audio-summary.json"
            marker_path = tmp / "marker-plan.yaml"
            output_path = tmp / "seed.yaml"
            recipe_path.write_text(
                yaml.safe_dump(
                    {
                        "render_spec": {
                            "fps": {"numerator": 24, "denominator": 1}
                        },
                        "timeline": [
                            {
                                "slot": "R01",
                                "marker_slot_ref": "R01",
                                "section_ids": ["S01"],
                                "output_in_frame": 0,
                                "output_out_frame": 2400,
                            }
                        ],
                    },
                    sort_keys=False,
                )
            )
            audio_path.write_text(
                json.dumps(
                    {
                        "strong_onsets_ranked": [{"time_seconds": 70.25}],
                        "energy_jump_candidates": [
                            {"time_seconds": index + 0.25} for index in range(30)
                        ],
                        "lyric_gate_seconds": [50.5],
                    }
                )
            )
            marker_path.write_text(
                yaml.safe_dump(
                    {
                        "timeline_slots": [
                            {
                                **self.marker_row("R01"),
                                "section_id": "S01",
                                "output_range": {"start_frame": 1200},
                                "nearby_markers": {
                                    "strong_onsets_seconds": [40.0],
                                    "feature_boundaries_seconds": [45.0],
                                    "lyric_or_section_handoff": "vocal handoff",
                                },
                            }
                        ]
                    },
                    sort_keys=False,
                )
            )

            subprocess.run(
                [
                    str(VIDEO_PYTHON),
                    str(SCRIPT),
                    "--recipe",
                    str(recipe_path),
                    "--audio-summary",
                    str(audio_path),
                    "--marker-plan",
                    str(marker_path),
                    "--output",
                    str(output_path),
                ],
                cwd=ROOT,
                check=True,
                capture_output=True,
                text=True,
            )
            seed = yaml.safe_load(output_path.read_text())
            audit = seed["transition_opportunity_audit"]
            points = audit["points"]
            event_ids = {
                event_id
                for point in points
                for event_id in point["coverage_event_ids"]
            }

            self.assertEqual(
                30,
                len([event_id for event_id in event_ids if event_id.startswith("audio_drop:")]),
            )
            self.assertIn("audio_lyric:f1212", event_ids)
            self.assertIn("marker_lyric:R01:f1200", event_ids)
            self.assertIn("marker_onset:R01:f960", event_ids)
            self.assertIn("marker_drop:R01:f1080", event_ids)
            self.assertTrue(all(point["disposition"] == "review_candidate" for point in points))
            self.assertEqual(0, seed["seed_summary"]["effect_preselection_count"])
            self.assertEqual(len(event_ids), audit["coverage_contract"]["expected_event_count"])
            self.assertEqual(
                self.coverage_digest(event_ids),
                audit["coverage_contract"]["expected_event_ids_sha256"],
            )

    @staticmethod
    def marker_row(slot: str) -> dict[str, object]:
        return {
            "slot": slot,
            "slot_status": "pass",
            "alignment_basis": ["visible_body_landing"],
            "source_action_marker": {
                "visible_event": "the foot plants on the cut frame",
                "body_part_or_motion": "lead foot plant",
                "camera_event": "camera stops with the body",
            },
            "incoming_cut_decision": {
                "route": "send_04fx",
                "method": "boundary_review",
                "cut_frame_evidence": "incoming body and camera stop are readable",
            },
        }

    @staticmethod
    def coverage_digest(event_ids: object) -> str:
        payload = "".join(f"{event_id}\n" for event_id in sorted(set(event_ids)))
        return hashlib.sha256(payload.encode("utf-8")).hexdigest()

    @staticmethod
    def minimal_fx_map(
        audit: dict[str, object], recipe_path: Path
    ) -> dict[str, object]:
        return {
            "schema_version": "idol_edit_finishing_fx.v2",
            "content_id": "TEST_04FX_SEED",
            "status": "draft",
            "source_edit_map": "04-edit-map.yaml",
            "source_recipe": str(recipe_path),
            "source_edit_marker_plan": "generations/video/qc/edit-marker-plan-v6.yaml",
            "source_audio_or_cue_map": "generations/video/qc/audio-cue-map-v1.yaml",
            "effect_registry_ref": "automation/edit-effect-registry.yaml",
            "dependency_lock": {
                "digest_algorithm": "sha256",
                "source_recipe_sha256": "1" * 64,
                "source_edit_map_sha256": "2" * 64,
                "source_edit_marker_plan_sha256": "3" * 64,
                "source_audio_or_cue_map_sha256": "4" * 64,
                "passed_preview_sha256": "5" * 64,
            },
            "preview_gate": {
                "gate_type": "full_master",
                "section_ids": ["S01", "S02"],
                "preview_path": "preview.mp4",
                "edit_preview_status": "pass",
                "fx_allowed": True,
            },
            "track_tone_world_guard": {
                "tone_and_manner": "preserve the accepted preview tone",
                "world_space_preserve": "preserve section space continuity",
                "identity_body_preserve": "preserve face and body readability",
                "color_light_limits": "no unreviewed flash or exposure shift",
                "repeated_effect_drift_guard": "review every point independently",
            },
            "transition_opportunity_audit": audit,
            "fx_records": [],
            "final_render_policy": {
                "include_only_passed_fx": True,
                "single_high_quality_render_after_fx_pass": True,
                "timing_change_returns_to_04_edit": True,
                "post_edit_transition_audit_required_before_final_master": True,
                "final_qc_no_new_creative_fx_by_default": True,
            },
            "automation_boundaries": [
                "This seed supplies measurable review evidence only."
            ],
        }


if __name__ == "__main__":
    unittest.main()
