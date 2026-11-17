#!/usr/bin/env python3

from __future__ import annotations

import hashlib
import sys
import tempfile
import unittest
from fractions import Fraction
from pathlib import Path
from unittest import mock

import yaml


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

import validate_edit_recipe as validator  # noqa: E402


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


class EditRecipeValidatorTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_context = tempfile.TemporaryDirectory(
            prefix="idol-edit-recipe-validator-", dir="/private/tmp"
        )
        self.root = Path(self.temp_context.name)
        self.run_root = self.root / "runs" / "2099-12-31" / "TEST_EDIT_RECIPE"
        self.run_root.mkdir(parents=True)
        self.recipe_path = self.run_root / "generations/video/qc/recipe.yaml"
        self.recipe_path.parent.mkdir(parents=True)
        self.edit_map = self.run_root / "04-edit-map.yaml"
        self.marker = self.run_root / "generations/video/qc/marker.yaml"
        self.audio_branch_placement = (
            self.run_root / "work/04-lineage/audio-branch-cut-placement.yaml"
        )
        self.video_prompt_manifest = (
            self.run_root / "work/04-lineage/03V-video-prompt-manifest.yaml"
        )
        self.playback_review = (
            self.run_root / "work/04-lineage/03V-playback-review.yaml"
        )
        self.audio = self.run_root / "audio/selected/master.wav"
        self.source = self.run_root / "generations/video/raw/source.mp4"
        self.probe_report = self.run_root / "generations/video/qc/source-probe.yaml"
        for path, content in (
            (self.audio_branch_placement, b"audio Branch-Cut placement\n"),
            (self.video_prompt_manifest, b"03V prompt manifest\n"),
            (self.playback_review, b"03V playback review\n"),
            (self.audio, b"audio fixture\n"),
            (self.source, b"video fixture\n"),
            (self.probe_report, b"source probe\n"),
        ):
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(content)
        marker_payload = {
            "schema_version": "idol_edit_marker_plan.v6",
            "content_id": self.run_root.name,
            "timeline_slots": [
                {
                    "slot": "R01",
                    "section_id": "S00",
                    "source_lineage": {
                        "screen_progression_node": {
                            "screen_progression_map_id": "SPM_TEST_EDIT_RECIPE",
                            "screen_progression_node_id": "SPN_S00_R01",
                            "section_id": "S00",
                            "major_scene_id": "MJ00",
                            "core_cut_id": "C00",
                            "branch_cut_ids": ["BCS00_R01"],
                            "source_03v_cue_ids": ["03VCUE_S00_R01"],
                            "storyline_role": "release",
                            "observable_screen_proof": "The passed source visibly completes the route.",
                        },
                        "source_origin": "03v_production_cut_derived",
                        "source_03v_cue_ids": ["03VCUE_S00_R01"],
                        "source_core_cut_ids": ["C00"],
                        "source_branch_cut_ids": ["BCS00_R01"],
                        "continuity_target_branch_cut_ids": [],
                        "lineage_note": "This Edit Slot derives from the passed 03V Branch Cut.",
                    },
                }
            ],
        }
        self.marker.write_text(yaml.safe_dump(marker_payload, sort_keys=False))
        edit_map_payload = {
            "schema_version": "idol_edit_map.v4",
            "content_id": self.run_root.name,
            "edit_marker_plan_ref": {
                "schema": "idol_edit_marker_plan.v6",
                "path": self.marker.relative_to(self.run_root).as_posix(),
                "sha256": sha256(self.marker),
                "status": "recipe_ready",
            },
        }
        self.edit_map.write_text(yaml.safe_dump(edit_map_payload, sort_keys=False))

    def tearDown(self) -> None:
        self.temp_context.cleanup()

    def payload(self, fps: Fraction = Fraction(24, 1)) -> dict:
        duration_frames = 24
        duration = float(Fraction(duration_frames, 1) / fps)
        source_in = 0.5
        source_out = source_in + duration
        return {
            "schema_version": "idol_edit_recipe.v3",
            "content_id": self.run_root.name,
            "status": "final_render_ready",
            "owner": "04_edit",
            "source_edit_map": {
                "path": self.edit_map.relative_to(self.run_root).as_posix(),
                "sha256": sha256(self.edit_map),
            },
            "source_edit_marker_plan": {
                "path": self.marker.relative_to(self.run_root).as_posix(),
                "sha256": sha256(self.marker),
            },
            "audio_program": {
                "path": self.audio.relative_to(self.run_root).as_posix(),
                "sha256": sha256(self.audio),
                "duration_seconds": 2.0,
                "sample_rate": 48000,
                "channel_layout": "stereo",
                "start_sample": 0,
            },
            "audio_path": self.audio.relative_to(self.run_root).as_posix(),
            "timebase": {
                "fps": {"numerator": fps.numerator, "denominator": fps.denominator},
                "start_timecode": "00:00:00:00",
                "drop_frame": False,
                "frame_interval": "start_inclusive_end_exclusive",
            },
            "render_spec": {
                "fps": {"numerator": fps.numerator, "denominator": fps.denominator},
                "width": 300,
                "height": 200,
                "sample_aspect_ratio": "1/1",
                "fit_mode": "fit_pad",
                "background": "black",
                "pixel_format": "yuv422p10le",
            },
            "color_pipeline": {
                "input_interpretation": "Explicit Rec.709 source interpretation override.",
                "working_space": "Rec.709 gamma 2.4",
                "transform": "Explicit Rec.709 pass-through override.",
                "delivery": {
                    "color_range": "tv",
                    "color_space": "bt709",
                    "color_transfer": "bt709",
                    "color_primaries": "bt709",
                },
            },
            "timeline": [
                {
                    "segment_id": "SEG_R01",
                    "slot": "R01",
                    "marker_slot_ref": "R01",
                    "screen_progression_node": {
                        "screen_progression_map_id": "SPM_TEST_EDIT_RECIPE",
                        "screen_progression_node_id": "SPN_S00_R01",
                        "section_id": "S00",
                        "major_scene_id": "MJ00",
                        "core_cut_id": "C00",
                        "branch_cut_ids": ["BCS00_R01"],
                        "source_03v_cue_ids": ["03VCUE_S00_R01"],
                        "storyline_role": "release",
                        "observable_screen_proof": "The passed source visibly completes the route.",
                    },
                    "section_ids": ["S00"],
                    "source": self.source.relative_to(self.run_root).as_posix(),
                    "source_sha256": sha256(self.source),
                    "source_probe_ref": self.probe_report.relative_to(self.run_root).as_posix(),
                    "source_probe_sha256": sha256(self.probe_report),
                    "source_in": source_in,
                    "source_out": source_out,
                    "output_in_frame": 0,
                    "output_out_frame": duration_frames,
                    "duration_frames": duration_frames,
                    "output_in": 0.0,
                    "output_out": duration,
                    "output_duration": duration,
                    "retime": {
                        "mode": "constant",
                        "speed_factor": 1.0,
                        "cadence_method": "frame_sampling",
                        "cadence_qc_required": True,
                    },
                    "geometry": {
                        "policy": "inherit_render_spec",
                        "anchor_x": 0.5,
                        "anchor_y": 0.5,
                    },
                }
            ],
            "boundary_handle_contracts": [],
            "grade_profiles": {},
            "effects": [],
            "delivery_policy": {
                "mezzanine": {
                    "container": "mov",
                    "video_codec": "prores_ks",
                    "audio_codec": "pcm_s24le",
                    "chroma_policy": "4:2:2 10-bit mezzanine",
                },
                "platform_derivatives": [],
                "audio_qc_targets": {
                    "integrated_lufs_target": None,
                    "true_peak_ceiling_dbtp": -1.0,
                    "normalization_policy": "analysis_only_no_auto_normalize",
                },
            },
            "qc_requirements": {
                "frame_step_cutpoint_qc": True,
                "color_metadata_qc": True,
                "audio_delivery_qc": True,
                "retime_cadence_qc": True,
                "black_and_silence_qc": True,
            },
        }

    @staticmethod
    def fake_probe(path: Path) -> dict:
        if path.suffix == ".wav":
            return {
                "format": {"duration": "2.0"},
                "streams": [
                    {
                        "codec_type": "audio",
                        "sample_rate": "48000",
                        "channel_layout": "stereo",
                    }
                ],
            }
        return {
            "format": {"duration": "5.0"},
            "streams": [{"codec_type": "video", "width": 640, "height": 360}],
        }

    def validate(
        self,
        payload: dict,
        mode: str = "final-render",
        *,
        immutable_receipt: bool = False,
    ) -> list[str]:
        self.recipe_path.write_text(yaml.safe_dump(payload, sort_keys=False))
        with mock.patch.object(validator, "probe", side_effect=self.fake_probe):
            errors, _warnings, _report = validator.validate_v2(
                payload,
                self.recipe_path,
                self.run_root,
                mode,
                immutable_receipt=immutable_receipt,
            )
        return errors

    def test_valid_frame_math_for_common_rational_rates(self) -> None:
        for fps in (Fraction(24, 1), Fraction(25, 1), Fraction(30000, 1001)):
            with self.subTest(fps=fps):
                self.assertEqual([], self.validate(self.payload(fps)))

    def test_recipe_must_exact_carry_marker_screen_progression_node(self) -> None:
        payload = self.payload()
        payload["timeline"][0]["screen_progression_node"]["screen_progression_node_id"] = "SPN_DRIFT"
        errors = self.validate(payload)
        self.assertTrue(any("exact-carry" in error for error in errors), errors)

    def test_official_core_only_marker_and_recipe_carry_passes(self) -> None:
        marker = yaml.safe_load(self.marker.read_text())
        lineage = marker["timeline_slots"][0]["source_lineage"]
        lineage["source_branch_cut_ids"] = []
        lineage["screen_progression_node"]["branch_cut_ids"] = []
        self.marker.write_text(yaml.safe_dump(marker, sort_keys=False))

        edit_map = yaml.safe_load(self.edit_map.read_text())
        edit_map["edit_marker_plan_ref"]["sha256"] = sha256(self.marker)
        self.edit_map.write_text(yaml.safe_dump(edit_map, sort_keys=False))

        payload = self.payload()
        payload["source_edit_marker_plan"]["sha256"] = sha256(self.marker)
        payload["source_edit_map"]["sha256"] = sha256(self.edit_map)
        payload["timeline"][0]["screen_progression_node"]["branch_cut_ids"] = []
        self.assertEqual([], self.validate(payload))

    def test_marker_node_and_lineage_branch_mismatch_fails_closed(self) -> None:
        marker = yaml.safe_load(self.marker.read_text())
        marker["timeline_slots"][0]["source_lineage"]["source_branch_cut_ids"] = []
        self.marker.write_text(yaml.safe_dump(marker, sort_keys=False))

        edit_map = yaml.safe_load(self.edit_map.read_text())
        edit_map["edit_marker_plan_ref"]["sha256"] = sha256(self.marker)
        self.edit_map.write_text(yaml.safe_dump(edit_map, sort_keys=False))

        payload = self.payload()
        payload["source_edit_marker_plan"]["sha256"] = sha256(self.marker)
        payload["source_edit_map"]["sha256"] = sha256(self.edit_map)
        errors = self.validate(payload)
        self.assertTrue(
            any("exact-carry Branch ids" in error for error in errors), errors
        )

    def test_frame_gap_source_overrun_and_variable_retime_fail_closed(self) -> None:
        payload = self.payload()
        row = payload["timeline"][0]
        row["output_in_frame"] = 1
        row["output_out_frame"] = 25
        row["output_in"] = 1 / 24
        row["output_out"] = 25 / 24
        row["source_out"] = 6.0
        row["retime"] = {
            "mode": "variable_external_04",
            "speed_factor": 5.5,
            "cadence_method": "optical_flow_external",
            "cadence_qc_required": True,
        }
        errors = self.validate(payload)
        self.assertTrue(any("gap/overlap" in error for error in errors), errors)
        self.assertTrue(any("exceeds ffprobe duration" in error for error in errors), errors)
        self.assertTrue(any("variable retime" in error for error in errors), errors)

    def test_stale_source_hash_and_unknown_color_without_override_fail(self) -> None:
        payload = self.payload()
        payload["timeline"][0]["source_sha256"] = "0" * 64
        payload["color_pipeline"]["input_interpretation"] = "unknown"
        payload["color_pipeline"]["transform"] = "Rec.709 pass-through"
        errors = self.validate(payload)
        self.assertTrue(any("source SHA-256 mismatch" in error for error in errors), errors)
        self.assertTrue(any("explicit interpretation override" in error for error in errors), errors)

    def test_immutable_receipt_allows_only_historical_edit_map_digest(self) -> None:
        payload = self.payload()
        edit_map = yaml.safe_load(self.edit_map.read_text())
        edit_map["final_closeout_inventory"] = {"status": "ready_for_05"}
        self.edit_map.write_text(yaml.safe_dump(edit_map, sort_keys=False))
        live_errors = self.validate(payload)
        self.assertTrue(
            any("source_edit_map SHA-256 mismatch" in error for error in live_errors),
            live_errors,
        )
        self.assertEqual(
            [], self.validate(payload, immutable_receipt=True)
        )

        self.marker.write_bytes(b"marker plan changed after render\n")
        receipt_errors = self.validate(payload, immutable_receipt=True)
        self.assertTrue(
            any("source_edit_marker_plan SHA-256 mismatch" in error for error in receipt_errors),
            receipt_errors,
        )

    def test_source_edit_map_must_be_exact_run_root_owner(self) -> None:
        payload = self.payload()
        alternate = self.run_root / "review/04-edit-map-copy.yaml"
        alternate.parent.mkdir(parents=True, exist_ok=True)
        alternate.write_bytes(b"alternate edit map\n")
        payload["source_edit_map"] = {
            "path": alternate.relative_to(self.run_root).as_posix(),
            "sha256": sha256(alternate),
        }
        errors = self.validate(payload)
        self.assertTrue(
            any("exact run-root 04-edit-map" in error for error in errors), errors
        )

    def test_active_recipe_rejects_legacy_or_unlined_marker_plan(self) -> None:
        payload = self.payload()
        marker = yaml.safe_load(self.marker.read_text())
        marker["schema_version"] = "idol_edit_marker_plan.v2"
        marker["timeline_slots"][0].pop("source_lineage")
        self.marker.write_text(yaml.safe_dump(marker, sort_keys=False))
        payload["source_edit_marker_plan"]["sha256"] = sha256(self.marker)
        edit_map = yaml.safe_load(self.edit_map.read_text())
        edit_map["edit_marker_plan_ref"]["sha256"] = sha256(self.marker)
        self.edit_map.write_text(yaml.safe_dump(edit_map, sort_keys=False))
        payload["source_edit_map"]["sha256"] = sha256(self.edit_map)
        errors = self.validate(payload)
        self.assertTrue(
            any("must use active idol_edit_marker_plan.v6" in error for error in errors),
            errors,
        )
        self.assertTrue(
            any("must preserve Branch-Cut/03V lineage" in error for error in errors),
            errors,
        )

    def test_immutable_receipt_cannot_weaken_preview_mode(self) -> None:
        errors = self.validate(
            self.payload(), mode="preview", immutable_receipt=True
        )
        self.assertTrue(
            any("valid only with mode=final-render" in error for error in errors),
            errors,
        )

    def test_final_mezzanine_codec_container_and_pixel_format_are_coherent(self) -> None:
        payload = self.payload()
        payload["delivery_policy"]["mezzanine"]["container"] = "mp4"
        payload["render_spec"]["pixel_format"] = "yuv420p"
        payload["color_pipeline"]["delivery"]["color_transfer"] = "unknown"
        errors = self.validate(payload)
        self.assertTrue(any("ProRes final delivery requires container=mov" in error for error in errors), errors)
        self.assertTrue(any("10-bit" in error for error in errors), errors)
        self.assertTrue(any("PCM final audio" in error for error in errors), errors)
        self.assertTrue(any("known color_transfer" in error for error in errors), errors)

    def test_duplicate_yaml_key_is_rejected_before_semantic_validation(self) -> None:
        self.recipe_path.write_text(
            "schema_version: idol_edit_recipe.v3\nstatus: draft\nstatus: hold\n"
        )
        with self.assertRaisesRegex(yaml.constructor.ConstructorError, "duplicate key"):
            validator.load_mapping(self.recipe_path)

    def test_historical_recipe_cannot_pass_active_validation(self) -> None:
        legacy = {
            "schema_version": "idol_video_sync_workbench.v1",
            "timeline": [
                {
                    "source_in": 0.0,
                    "source_out": 1.0,
                    "output_in": 0.0,
                    "output_out": 1.0,
                    "output_duration": 1.0,
                }
            ],
        }
        errors, warnings, _report = validator.validate_legacy(
            legacy, self.recipe_path, False, "preview"
        )
        self.assertTrue(any("historical evidence only" in error for error in errors))
        self.assertTrue(warnings)
        errors, _warnings, _report = validator.validate_legacy(
            legacy, self.recipe_path, True, "final-render"
        )
        self.assertTrue(any("historical evidence only" in error for error in errors))


if __name__ == "__main__":
    unittest.main()
