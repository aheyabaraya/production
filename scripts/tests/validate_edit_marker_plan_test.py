#!/usr/bin/env python3
"""Semantic regression tests for active idol_edit_marker_plan.v6 validation."""

from __future__ import annotations

import copy
import hashlib
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from typing import Any

import yaml


ROOT = Path(__file__).resolve().parents[2]
VALIDATOR = ROOT / "scripts" / "validate_edit_marker_plan.py"


def write_yaml(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        yaml.safe_dump(payload, allow_unicode=True, sort_keys=False),
        encoding="utf-8",
    )


class ValidateEditMarkerPlanTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_context = tempfile.TemporaryDirectory(
            prefix="idol-edit-marker-plan-", dir="/private/tmp"
        )
        self.temp_root = Path(self.temp_context.name)
        self.audio_placement = self._source_file(
            "sources/audio-branch-cut-placement.yaml", b"audio-placement-v4"
        )
        storyline_text = (
            "The film opens on a fixed route, accumulates the consequences of one "
            "deliberate change, and ends with that displaced route retained."
        )
        storyline_sha = hashlib.sha256(storyline_text.encode("utf-8")).hexdigest()
        self.storyline = {
            "contract_version": "front_planning_storyline_lineage.v1",
            "pre00_lineage": {
                "pre00_storyline_original": {
                    "version_id": "PRE00_STORYLINE_V001",
                    "full_storyline_text": storyline_text,
                    "full_storyline_text_sha256": storyline_sha,
                    "reference_bindings": [],
                }
            },
            "front_planning_revisions": [],
            "active_version": {
                "lineage_scope": "pre00",
                "version_id": "PRE00_STORYLINE_V001",
                "version_json_pointer": "/storyline_lineage/pre00_lineage/pre00_storyline_original",
                "full_storyline_text": storyline_text,
                "full_storyline_text_sha256": storyline_sha,
            },
        }
        self.screen_progression = {
            "screen_progression_map_id": "SPM_EDIT_MARKER_TEST_001",
            "nodes": [
                {
                    "node_id": "SPN_S00_R00",
                    "node_type": "core_slot",
                    "section_id": "S00",
                    "major_scene_id": "MJ00",
                    "source_id": "C00",
                    "storyline_role": "carry_and_release",
                    "observable_screen_proof": "The declared hand/foot state is visible in the passed playback.",
                    "continuity_in": "The opening hold is readable.",
                    "continuity_out": "The hold releases toward S01.",
                },
                {
                    "node_id": "SPN_S01_R01",
                    "node_type": "core_slot",
                    "section_id": "S01",
                    "major_scene_id": "MJ01",
                    "source_id": "C01",
                    "storyline_role": "carry_and_release",
                    "observable_screen_proof": "The declared hand/foot state is visible in the passed playback.",
                    "continuity_in": "The S00 release arrives.",
                    "continuity_out": "The action resolves in frame.",
                },
            ],
        }
        core_hash_00 = "1" * 64
        core_hash_01 = "2" * 64
        branch_hash_01 = "3" * 64
        self.video_cues = [
            {
                "cue_id": "03VCUE_S00_R00",
                "screen_progression_map_id": "SPM_EDIT_MARKER_TEST_001",
                "screen_progression_node_id": "SPN_S00_R00",
                "section_id": "S00",
                "major_scene_id": "MJ00",
                "core_cut_id": "C00",
                "branch_cut_ids": [],
                "source_production_cut_images": [
                    {
                        "production_cut_id": "C00",
                        "production_cut_type": "official_core",
                        "parent_core_cut_id": "C00",
                        "sha256": core_hash_00,
                    }
                ],
                "source_image_ids": ["C00"],
                "source_pixel_hashes": [core_hash_00],
            },
            {
                "cue_id": "03VCUE_S01_R01",
                "screen_progression_map_id": "SPM_EDIT_MARKER_TEST_001",
                "screen_progression_node_id": "SPN_S01_R01",
                "section_id": "S01",
                "major_scene_id": "MJ01",
                "core_cut_id": "C01",
                "branch_cut_ids": ["BCS01_R01"],
                "source_production_cut_images": [
                    {
                        "production_cut_id": "C01",
                        "production_cut_type": "official_core",
                        "parent_core_cut_id": "C01",
                        "sha256": core_hash_01,
                    },
                    {
                        "production_cut_id": "BCS01_R01",
                        "production_cut_type": "branch",
                        "parent_core_cut_id": "C01",
                        "sha256": branch_hash_01,
                    },
                ],
                "source_image_ids": ["C01", "BCS01_R01"],
                "source_pixel_hashes": [core_hash_01, branch_hash_01],
            },
        ]
        self.video_manifest = self.temp_root / "sources/03v-video-prompt-manifest.yaml"
        write_yaml(
            self.video_manifest,
            {
                "schema_version": "idol_video_prompt_manifest.v8",
                "storyline_lineage_projection": {
                    "projected_value": self.storyline,
                },
                "screen_progression_projection": {
                    "projected_value": self.screen_progression,
                },
                "cues": self.video_cues,
            },
        )
        self.playback_review = self._source_file(
            "sources/03v-playback-review.yaml", b"playback-review"
        )
        self.audio_motion_map = self._source_file(
            "sources/audio-motion-director-map.yaml", b"audio-motion-map-v1"
        )

    def tearDown(self) -> None:
        self.temp_context.cleanup()

    def _source_file(self, relative: str, payload: bytes) -> Path:
        path = self.temp_root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(payload)
        return path

    @staticmethod
    def _binding(path: Path) -> dict[str, str]:
        return {
            "path": str(path),
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        }

    @staticmethod
    def _value_sha(value: Any) -> str:
        return hashlib.sha256(
            json.dumps(
                value,
                ensure_ascii=False,
                sort_keys=True,
                separators=(",", ":"),
            ).encode("utf-8")
        ).hexdigest()

    @staticmethod
    def _decision(route: str = "keep_04") -> dict[str, Any]:
        return {
            "method": "cut_on_action",
            "timing_relation": "exact_hit",
            "timing_offset_frames": 0,
            "pre_cut_evidence": "The outgoing hand reaches the right frame edge one frame before the cut.",
            "cut_frame_evidence": "The hand clears as the snare lands on the exact cut frame.",
            "post_cut_evidence": "The incoming foot is already planted and the face stays readable.",
            "story_attention_handoff": "Attention transfers from the outgoing hand to the incoming face.",
            "screen_direction_or_composition": "Both motions continue left-to-right across the same eyeline height.",
            "no_effect_pass": True,
            "route": route,
        }

    @classmethod
    def _slot(
        cls,
        *,
        slot: str,
        section_id: str,
        start_frame: int,
        end_frame: int,
        decision: dict[str, Any] | None,
        branch_cut_ids: list[str] | None = None,
    ) -> dict[str, Any]:
        fps = 24
        branch_ids = (
            [f"BC{section_id}_{slot}"]
            if branch_cut_ids is None
            else branch_cut_ids
        )
        return {
            "slot": slot,
            "section_id": section_id,
            "transition_id": None if decision is None else f"CUT_{slot}",
            "output_range": {
                "start_seconds": start_frame / fps,
                "end_seconds": end_frame / fps,
                "start_frame": start_frame,
                "end_frame": end_frame,
                "duration_frames": end_frame - start_frame,
            },
            "cue_role": "Identity hold" if decision is None else "Section action handoff",
            "nearby_markers": {
                "beats_seconds": [start_frame / fps],
                "strong_onsets_seconds": [start_frame / fps],
                "feature_boundaries_seconds": [],
                "lyric_or_section_handoff": "section handoff" if decision else None,
            },
            "source_lineage": {
                "screen_progression_node": {
                    "screen_progression_map_id": "SPM_EDIT_MARKER_TEST_001",
                    "screen_progression_node_id": f"SPN_{section_id}_{slot}",
                    "section_id": section_id,
                    "major_scene_id": f"MJ{section_id[1:]}",
                    "core_cut_id": f"C{section_id[1:]}",
                    "branch_cut_ids": branch_ids,
                    "source_03v_cue_ids": [f"03VCUE_{section_id}_{slot}"],
                    "storyline_role": "carry_and_release",
                    "observable_screen_proof": "The declared hand/foot state is visible in the passed playback.",
                },
                "source_origin": "03v_production_cut_derived",
                "source_03v_cue_ids": [f"03VCUE_{section_id}_{slot}"],
                "source_core_cut_ids": [f"C{section_id[1:]}"],
                "source_branch_cut_ids": branch_ids,
                "continuity_target_branch_cut_ids": [],
                "lineage_note": (
                    "This Edit Slot uses the passed 03V motion carrying the "
                    "declared Branch Cut; the final Edit Segment count remains 04-owned."
                ),
            },
            "source_candidates": [
                {
                    "candidate_id": f"SRC_{slot}",
                    "source": f"generations/video/raw/{slot.lower()}.mp4",
                    "source_in": 0.0,
                    "source_out": 1.5,
                    "speed_hint": 1.0,
                    "note": "Synthetic validator fixture candidate.",
                }
            ],
            "source_action_marker": {
                "visible_event": "The hand clears the frame and the next foot lands cleanly.",
                "source_time_seconds": 0.5,
                "body_part_or_motion": "hand exit and foot plant",
                "camera_event": "locked medium framing",
                "source_frame": 12,
                "source_fps": {"numerator": 24, "denominator": 1},
            },
            "incoming_cut_decision": decision,
            "cut_density": "hold" if decision is None else "medium",
            "alignment_basis": ["beat_or_onset", "visible_body_landing", "cue_role"],
            "motion_continuity": "The outgoing hand direction continues into the incoming foot route.",
            "story_flow_continuity": "The identity hold releases into the next member action.",
            "space_visible_feeling_progression": "The corridor depth remains stable while attention moves forward.",
            "directorial_transition_intent": "Use the body-direction match as the transition reason.",
            "audio_marker_alignment": "The snare, hand exit, foot plant, and section function share the cut frame.",
            "derivative_impact": "The cut remains readable in the short derivative.",
            "slot_status": "pass",
            "open_questions": [],
            "pass_fail_note": "The source action and selected-audio marker align without forced duration fitting.",
        }

    def valid_plan(self) -> dict[str, Any]:
        return {
            "schema_version": "idol_edit_marker_plan.v6",
            "content_id": "EDIT_MARKER_TEST_001",
            "status": "recipe_ready",
            "owner": "04_edit",
            "storyline_lineage_projection": {
                "source_video_prompt_manifest": self._binding(self.video_manifest),
                "source_video_prompt_manifest_json_pointer": "/storyline_lineage_projection/projected_value",
                "source_value_sha256": self._value_sha(self.storyline),
                "projected_value": copy.deepcopy(self.storyline),
                "consumption_rule": "read_complete_pre00_original_active_full_text_revision_history_density_review_and_reference_receipts_before_edit_timing_or_cutpoint_authorship",
            },
            "screen_progression_projection": {
                "source_video_prompt_manifest": self._binding(self.video_manifest),
                "source_video_prompt_manifest_json_pointer": "/screen_progression_projection/projected_value",
                "source_value_sha256": self._value_sha(self.screen_progression),
                "projected_value": copy.deepcopy(self.screen_progression),
                "consumption_rule": "exact_copy_no_paraphrase_or_default",
            },
            "production_cut_lineage_sources": {
                "audio_branch_cut_placements": [self._binding(self.audio_placement)],
                "video_prompt_manifests": [self._binding(self.video_manifest)],
                "playback_review_records": [self._binding(self.playback_review)],
            },
            "source_audio": "audio/selected/master.wav",
            "source_selected_audio_analysis": "research/selected-audio-analysis-v1.yaml",
            "source_audio_motion_director_map": self._binding(self.audio_motion_map),
            "source_audio_beat_onset_summary": "generations/video/qc/audio-beat-onset-summary.json",
            "source_recipe": None,
            "timebase": {
                "fps": {"numerator": 24, "denominator": 1},
                "frame_interval": "start_inclusive_end_exclusive",
                "drop_frame": False,
                "start_timecode": "00:00:00:00",
            },
            "audio_phase_lock": {
                "status": "manual_locked",
                "meter_beats": 4,
                "phase_source": "Founder/Codex listening lock at the first full bar.",
                "anchor_seconds": 0.5,
                "anchor_beat_in_bar": 1,
                "use_rule": "Use the manual phase only as reviewed meter context; exact cuts remain 04 decisions.",
            },
            "use_rule": "Use this plan for source windows and recipe timing only.",
            "upstream_intent_context": {
                "available": True,
                "sources": {
                    "song_lock": "00A-song-lock.yaml",
                    "song_choreography_performance_mv_map": "01-song-choreography-performance-mv-map.yaml",
                    "master_storyboard": "02A-master-storyboard.yaml",
                    "prompt_packets": "02B-prompt-packets.yaml",
                    "review_board_or_cue_sheet": "review/03-review.yaml",
                },
                "use_as": ["intent_map", "candidate_narrowing", "cue_function_seed"],
                "not_edit_truth": [
                    "source_in",
                    "source_out",
                    "speed_factor",
                    "final_cutpoint",
                    "final_candidate_selection",
                    "final_geometry_override",
                ],
                "proof_required_in_04": [
                    "actual_source_exists",
                    "first_useful_action",
                    "motion_peak",
                    "beat_or_onset_alignment",
                    "cue_function_alignment",
                    "contact_sheet_qc",
                    "preview_qc",
                    "source_quality_qc",
                ],
            },
            "initial_alignment_pass": {
                "analysis_inputs": {
                    "selected_audio": "audio/selected/master.wav",
                    "cue_sheet": "review/03-review.yaml",
                    "audio_motion_director_map": str(self.audio_motion_map),
                },
                "baseline_cut_read": {
                    "roughcut_or_recipe": "none_new_run",
                    "what_already_works": [],
                    "what_is_not_marker_locked_yet": ["R00 to R01 boundary"],
                    "first_pass_goal": "Align actual source motion to the selected-audio markers.",
                },
                "alignment_method": [
                    "music_marker",
                    "source_action_marker",
                    "cue_function_marker",
                ],
                "source_motion_scan": {
                    "motion_csv_dir": None,
                    "source_first_seconds_scan": True,
                    "motion_peak_scan": True,
                    "candidate_source_contact_sheet": True,
                },
                "marker_lock_required_before_recipe": True,
                "pass_fail_rule": "Pass only when music, visible action, and cue function agree.",
            },
            "timeline_slots": [
                self._slot(
                    slot="R00",
                    section_id="S00",
                    start_frame=0,
                    end_frame=24,
                    decision=None,
                    branch_cut_ids=[],
                ),
                self._slot(
                    slot="R01",
                    section_id="S01",
                    start_frame=24,
                    end_frame=48,
                    decision=self._decision(),
                ),
            ],
        }

    def _validate(
        self, payload: dict[str, Any], case_name: str
    ) -> subprocess.CompletedProcess[str]:
        path = self.temp_root / case_name / "edit-marker-plan-v6.yaml"
        write_yaml(path, payload)
        return subprocess.run(
            [sys.executable, str(VALIDATOR), str(path), "--require-v6"],
            cwd=ROOT,
            text=True,
            capture_output=True,
        )

    def _rewrite_video_manifest(
        self, plan: dict[str, Any], mutate: Any
    ) -> None:
        manifest = yaml.safe_load(self.video_manifest.read_text(encoding="utf-8"))
        mutate(manifest)
        write_yaml(self.video_manifest, manifest)
        binding = self._binding(self.video_manifest)
        plan["storyline_lineage_projection"]["source_video_prompt_manifest"] = copy.deepcopy(binding)
        plan["screen_progression_projection"]["source_video_prompt_manifest"] = copy.deepcopy(binding)
        plan["production_cut_lineage_sources"]["video_prompt_manifests"] = [
            copy.deepcopy(binding)
        ]

    @staticmethod
    def _combined_output(result: subprocess.CompletedProcess[str]) -> str:
        return result.stdout + result.stderr

    def test_schema_valid_two_slot_fixture_passes(self) -> None:
        plan = self.valid_plan()
        self.assertEqual([], plan["timeline_slots"][0]["source_lineage"]["source_branch_cut_ids"])
        result = self._validate(plan, "valid-core-only-and-branch")
        self.assertEqual(0, result.returncode, self._combined_output(result))
        self.assertIn(
            "Edit Segment/Edit Boundary frame continuity valid", result.stdout
        )

    def test_branch_lineage_mismatch_is_rejected(self) -> None:
        plan = self.valid_plan()
        plan["timeline_slots"][1]["source_lineage"]["source_branch_cut_ids"] = []
        result = self._validate(plan, "branch-lineage-mismatch")
        self.assertNotEqual(0, result.returncode)
        self.assertIn(
            "source_branch_cut_ids must exact-carry",
            self._combined_output(result),
        )

    def test_core_lineage_mismatch_is_rejected(self) -> None:
        plan = self.valid_plan()
        plan["timeline_slots"][0]["source_lineage"]["source_core_cut_ids"] = ["C99"]
        result = self._validate(plan, "core-lineage-mismatch")
        self.assertNotEqual(0, result.returncode)
        self.assertIn(
            "source_core_cut_ids must exactly contain",
            self._combined_output(result),
        )

    def test_bound_production_cut_type_and_id_mismatch_is_rejected(self) -> None:
        plan = self.valid_plan()

        def mutate(manifest: dict[str, Any]) -> None:
            branch = manifest["cues"][1]["source_production_cut_images"][1]
            branch["production_cut_type"] = "official_core"

        self._rewrite_video_manifest(plan, mutate)
        result = self._validate(plan, "production-cut-type-id-mismatch")
        self.assertNotEqual(0, result.returncode)
        self.assertIn(
            "Branch Production Cut type/id lineage is inconsistent",
            self._combined_output(result),
        )

    def test_bound_production_cut_hash_mismatch_is_rejected(self) -> None:
        plan = self.valid_plan()

        def mutate(manifest: dict[str, Any]) -> None:
            manifest["cues"][0]["source_pixel_hashes"][0] = "f" * 64

        self._rewrite_video_manifest(plan, mutate)
        result = self._validate(plan, "production-cut-hash-mismatch")
        self.assertNotEqual(0, result.returncode)
        self.assertIn(
            "Production Cut hashes are internally inconsistent",
            self._combined_output(result),
        )

    def test_screen_progression_projection_must_exact_copy_03v(self) -> None:
        plan = self.valid_plan()
        plan["screen_progression_projection"]["projected_value"]["nodes"][0]["section_id"] = "S99"
        result = self._validate(plan, "screen-progression-drift")
        self.assertNotEqual(0, result.returncode)
        self.assertIn("exact-project screen_progression_map", self._combined_output(result))

    def test_production_cut_lineage_is_required_for_every_edit_slot(self) -> None:
        plan = self.valid_plan()
        plan["timeline_slots"][1].pop("source_lineage")
        result = self._validate(plan, "missing-branch-lineage")
        self.assertNotEqual(0, result.returncode)
        self.assertIn("source_lineage", self._combined_output(result))

    def test_non_production_cut_source_names_continuity_target(self) -> None:
        plan = self.valid_plan()
        lineage = plan["timeline_slots"][1]["source_lineage"]
        lineage.update(
            {
                "source_origin": "current_run_non_production_cut_source",
                "source_03v_cue_ids": [],
                "source_core_cut_ids": [],
                "source_branch_cut_ids": [],
                "continuity_target_branch_cut_ids": [],
                "lineage_note": "Founder-supplied current-run insert.",
            }
        )
        result = self._validate(plan, "non-branch-without-target")
        self.assertNotEqual(0, result.returncode)
        self.assertIn("continuity_target_branch_cut_ids", self._combined_output(result))

    def test_frame_continuity_gap_is_rejected(self) -> None:
        plan = self.valid_plan()
        second_range = plan["timeline_slots"][1]["output_range"]
        second_range.update(
            {
                "start_frame": 25,
                "end_frame": 49,
                "duration_frames": 24,
                "start_seconds": 25 / 24,
                "end_seconds": 49 / 24,
            }
        )
        result = self._validate(plan, "frame-gap")
        self.assertNotEqual(0, result.returncode)
        self.assertIn("creates frame gap/overlap after 24", self._combined_output(result))

    def test_first_decision_must_be_null_and_following_decision_is_required(self) -> None:
        first_invalid = self.valid_plan()
        first_invalid["timeline_slots"][0]["incoming_cut_decision"] = copy.deepcopy(
            first_invalid["timeline_slots"][1]["incoming_cut_decision"]
        )
        first_result = self._validate(first_invalid, "first-decision-not-null")
        self.assertNotEqual(0, first_result.returncode)
        self.assertIn(
            "first marker slot must have incoming_cut_decision: null",
            self._combined_output(first_result),
        )

        following_invalid = self.valid_plan()
        following_invalid["timeline_slots"][1]["incoming_cut_decision"] = None
        following_result = self._validate(following_invalid, "following-decision-null")
        self.assertNotEqual(0, following_result.returncode)
        self.assertIn(
            "requires an incoming_cut_decision",
            self._combined_output(following_result),
        )

    def test_send_04fx_requires_route_reason(self) -> None:
        plan = self.valid_plan()
        decision = plan["timeline_slots"][1]["incoming_cut_decision"]
        decision["route"] = "send_04fx"
        decision.pop("route_reason", None)
        missing_result = self._validate(plan, "send-04fx-without-reason")
        self.assertNotEqual(0, missing_result.returncode)
        self.assertIn("send_04fx requires route_reason", self._combined_output(missing_result))

        decision["route_reason"] = (
            "The hard cut already passes; 04FX should test one restrained boundary dip."
        )
        valid_result = self._validate(plan, "send-04fx-with-reason")
        self.assertEqual(0, valid_result.returncode, self._combined_output(valid_result))

    def test_manual_phase_lock_requires_valid_anchor(self) -> None:
        missing_anchor = self.valid_plan()
        missing_anchor["audio_phase_lock"]["anchor_seconds"] = None
        missing_result = self._validate(missing_anchor, "manual-phase-missing-anchor")
        self.assertNotEqual(0, missing_result.returncode)
        self.assertIn(
            "manual_locked audio phase requires anchor_seconds and anchor_beat_in_bar",
            self._combined_output(missing_result),
        )

        out_of_meter = self.valid_plan()
        out_of_meter["audio_phase_lock"]["anchor_beat_in_bar"] = 5
        meter_result = self._validate(out_of_meter, "manual-phase-out-of-meter")
        self.assertNotEqual(0, meter_result.returncode)
        self.assertIn(
            "audio phase anchor_beat_in_bar exceeds meter_beats",
            self._combined_output(meter_result),
        )

    def test_audio_motion_map_hash_must_match_current_bytes(self) -> None:
        plan = self.valid_plan()
        plan["source_audio_motion_director_map"]["sha256"] = "0" * 64
        result = self._validate(plan, "stale-audio-motion-map")
        self.assertNotEqual(0, result.returncode)
        self.assertIn(
            "source_audio_motion_director_map.sha256 is stale",
            self._combined_output(result),
        )

    def test_duplicate_yaml_key_is_rejected(self) -> None:
        path = self.temp_root / "duplicate-key" / "edit-marker-plan-v6.yaml"
        write_yaml(path, self.valid_plan())
        source = path.read_text(encoding="utf-8")
        source = source.replace(
            "status: recipe_ready\n",
            "status: recipe_ready\nstatus: duplicate_value\n",
            1,
        )
        path.write_text(source, encoding="utf-8")
        result = subprocess.run(
            [sys.executable, str(VALIDATOR), str(path), "--require-v6"],
            cwd=ROOT,
            text=True,
            capture_output=True,
        )
        self.assertNotEqual(0, result.returncode)
        self.assertIn("duplicate key: 'status'", self._combined_output(result))


if __name__ == "__main__":
    unittest.main(verbosity=2)
