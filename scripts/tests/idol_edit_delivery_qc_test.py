#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

import jsonschema
import yaml


ROOT = Path(__file__).resolve().parents[2]
LAUNCHER = ROOT / "scripts/idol-video-python"
SCRIPT = ROOT / "scripts/idol_edit_delivery_qc.py"


def tool_path(name: str) -> str:
    for prefix in ("/opt/homebrew/bin", "/usr/local/bin"):
        candidate = Path(prefix) / name
        if candidate.exists():
            return str(candidate)
    found = shutil.which(name)
    if not found:
        raise unittest.SkipTest(f"missing {name}")
    return found


class IdolEditDeliveryQcTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory(
            prefix="idol-edit-delivery-qc-", dir="/private/tmp"
        )
        self.root = Path(self.tmp.name)
        self.master = self.root / "master.mkv"
        self.selected = self.root / "selected.wav"
        subprocess.run(
            [
                tool_path("ffmpeg"),
                "-hide_banner",
                "-loglevel",
                "error",
                "-y",
                "-f",
                "lavfi",
                "-i",
                "color=c=black:s=64x64:r=24:d=1",
                "-f",
                "lavfi",
                "-i",
                "sine=frequency=440:sample_rate=48000:duration=1",
                "-shortest",
                "-c:v",
                "libx264",
                "-pix_fmt",
                "yuv420p",
                "-color_range",
                "tv",
                "-colorspace",
                "bt709",
                "-color_trc",
                "bt709",
                "-color_primaries",
                "bt709",
                "-c:a",
                "pcm_s16le",
                str(self.master),
            ],
            check=True,
        )
        subprocess.run(
            [
                tool_path("ffmpeg"),
                "-hide_banner",
                "-loglevel",
                "error",
                "-y",
                "-f",
                "lavfi",
                "-i",
                "sine=frequency=440:sample_rate=48000:duration=1",
                "-c:a",
                "pcm_s16le",
                str(self.selected),
            ],
            check=True,
        )

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def run_qc(
        self,
        video: Path,
        output: Path,
        selected: Path | None = None,
        recipe: Path | None = None,
    ):
        command = [
            str(LAUNCHER),
            str(SCRIPT),
            "--video",
            str(video),
            "--output",
            str(output),
            "--black-min-duration",
            "0.02",
            "--freeze-min-duration",
            "0.2",
        ]
        if selected is not None:
            command.extend(["--selected-audio", str(selected)])
        if recipe is not None:
            command.extend(["--recipe", str(recipe)])
        return subprocess.run(command, check=True, capture_output=True, text=True)

    def write_v3_recipe(self) -> Path:
        recipe = self.root / "edit-recipe.yaml"
        source_probe = self.root / "source-index.yaml"
        source_probe.write_text("schema_version: source-probe-fixture.v1\n")
        selected_digest = hashlib.sha256(self.selected.read_bytes()).hexdigest()
        master_digest = hashlib.sha256(self.master.read_bytes()).hexdigest()
        source_probe_digest = hashlib.sha256(source_probe.read_bytes()).hexdigest()
        payload = {
            "schema_version": "idol_edit_recipe.v3",
            "content_id": "TEST_EDIT_QC",
            "status": "draft",
            "owner": "04_edit",
            "source_edit_map": {"path": "edit-map.yaml", "sha256": "0" * 64},
            "source_edit_marker_plan": {
                "path": "edit-marker-plan.yaml",
                "sha256": "1" * 64,
            },
            "audio_program": {
                "path": str(self.selected),
                "sha256": selected_digest,
                "duration_seconds": 1.0,
                "sample_rate": 48000,
                "channel_layout": "mono",
                "start_sample": 0,
            },
            "audio_path": str(self.selected),
            "timebase": {
                "fps": {"numerator": 24, "denominator": 1},
                "start_timecode": "00:00:00:00",
                "drop_frame": False,
                "frame_interval": "start_inclusive_end_exclusive",
            },
            "render_spec": {
                "fps": {"numerator": 24, "denominator": 1},
                "width": 64,
                "height": 64,
                "sample_aspect_ratio": "1/1",
                "fit_mode": "fit_pad",
                "background": "black",
                "pixel_format": "yuv420p",
            },
            "color_pipeline": {
                "input_interpretation": "source tags only",
                "working_space": "bt709",
                "transform": "identity",
                "delivery": {
                    "color_range": "tv",
                    "color_space": "bt709",
                    "color_transfer": "bt709",
                    "color_primaries": "bt709",
                },
            },
            "timeline": [
                {
                    "segment_id": "SEG_TEST_01",
                    "slot": "R01",
                    "marker_slot_ref": "R01",
                    "screen_progression_node": {
                        "screen_progression_map_id": "SPM_TEST_EDIT_QC",
                        "screen_progression_node_id": "SPN_TEST_EDIT_QC_R01",
                        "section_id": "S01",
                        "major_scene_id": "MJ01",
                        "core_cut_id": "C01",
                        "branch_cut_ids": ["BC01"],
                        "source_03v_cue_ids": ["03VCUE_TEST_EDIT_QC_R01"],
                        "storyline_role": "resolve",
                        "observable_screen_proof": (
                            "The tested program preserves the reviewed S01 screen state."
                        ),
                    },
                    "section_ids": ["S01"],
                    "source": str(self.master),
                    "source_sha256": master_digest,
                    "source_probe_ref": str(source_probe),
                    "source_probe_sha256": source_probe_digest,
                    "source_in": 0.0,
                    "source_out": 1.0,
                    "output_in_frame": 0,
                    "output_out_frame": 24,
                    "duration_frames": 24,
                    "output_in": 0.0,
                    "output_out": 1.0,
                    "output_duration": 1.0,
                    "retime": {
                        "mode": "constant",
                        "speed_factor": 1.0,
                        "cadence_method": "frame_sampling",
                        "cadence_qc_required": False,
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
                    "container": "mkv",
                    "video_codec": "h264",
                    "audio_codec": "pcm_s16le",
                    "chroma_policy": "4:2:0",
                },
                "platform_derivatives": [],
                "audio_qc_targets": {
                    "integrated_lufs_target": -18.0,
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
        schema = json.loads(
            (ROOT / "schemas/edit-recipe.schema.json").read_text(encoding="utf-8")
        )
        jsonschema.Draft202012Validator(schema).validate(payload)
        recipe.write_text(yaml.safe_dump(payload, sort_keys=False))
        return recipe

    def test_measurement_report_binds_media_and_keeps_human_review_boundary(self):
        output = self.root / "delivery-qc.yaml"
        result = self.run_qc(self.master, output, self.selected)
        payload = yaml.safe_load(output.read_text())

        self.assertIn("status=measurement_complete", result.stdout)
        self.assertEqual("idol_edit_delivery_qc.v1", payload["schema_version"])
        self.assertTrue(payload["measurement_only"])
        self.assertTrue(payload["human_playback_review_required"])
        self.assertEqual(
            "analysis_only_no_auto_normalize", payload["normalization_policy"]
        )
        self.assertRegex(
            payload["source_bindings"]["master_video"]["sha256"], r"^[a-f0-9]{64}$"
        )
        self.assertRegex(payload["tooling"]["script"]["sha256"], r"^[a-f0-9]{64}$")
        self.assertRegex(
            payload["tooling"]["report_schema"]["sha256"], r"^[a-f0-9]{64}$"
        )
        self.assertEqual("bt709", payload["video_probe"]["color"]["color_space"])
        self.assertEqual(
            24,
            payload["video_measurements"]["frame_hash_cadence"]["frame_count"],
        )
        self.assertGreater(
            payload["video_measurements"]["frame_hash_cadence"][
                "adjacent_exact_duplicate_pairs"
            ],
            0,
        )
        self.assertTrue(payload["video_measurements"]["blackdetect"]["intervals"])
        self.assertIsNotNone(
            payload["audio_measurements"]["master"]["loudness"]["integrated_lufs"]
        )
        self.assertEqual([], payload["issues"])
        self.assertIn(
            "retime_body_mechanics_and_camera_judder",
            payload["manual_review_required"],
        )

    def test_json_output_and_missing_master_audio_are_reported_without_fake_pass(self):
        silent_video = self.root / "silent.mkv"
        subprocess.run(
            [
                tool_path("ffmpeg"),
                "-hide_banner",
                "-loglevel",
                "error",
                "-y",
                "-f",
                "lavfi",
                "-i",
                "color=c=blue:s=64x64:r=24:d=0.5",
                "-c:v",
                "libx264",
                "-pix_fmt",
                "yuv420p",
                str(silent_video),
            ],
            check=True,
        )
        output = self.root / "delivery-qc.json"
        result = self.run_qc(silent_video, output)
        payload = json.loads(output.read_text())

        self.assertIn("status=measurement_incomplete", result.stdout)
        self.assertEqual("measurement_incomplete", payload["status"])
        self.assertIsNone(payload["master_audio_probe"])
        self.assertIsNone(payload["audio_measurements"]["master"])
        self.assertTrue(any("no audio stream" in issue for issue in payload["issues"]))
        self.assertNotIn("pass", payload["status"])

    def test_v3_recipe_supplies_audio_and_frame_canonical_delivery_expectations(self):
        recipe = self.write_v3_recipe()
        output = self.root / "delivery-qc-recipe.yaml"
        self.run_qc(self.master, output, recipe=recipe)
        payload = yaml.safe_load(output.read_text())

        self.assertEqual(
            "idol_edit_recipe.v3",
            payload["program_comparison"]["recipe_schema_version"],
        )
        self.assertTrue(payload["program_comparison"]["program_frame_count_matches"])
        self.assertTrue(payload["program_comparison"]["fps_matches"])
        self.assertTrue(
            payload["program_comparison"]["geometry"]["pixel_format_matches"]
        )
        encoding = payload["program_comparison"]["delivery_encoding"]
        self.assertTrue(encoding["container_matches"])
        self.assertTrue(encoding["video_codec_matches"])
        self.assertTrue(encoding["audio_codec_matches"])
        self.assertEqual(
            hashlib.sha256(self.selected.read_bytes()).hexdigest(),
            payload["source_bindings"]["selected_audio"]["sha256"],
        )
        self.assertEqual(
            "analysis_only_no_auto_normalize",
            payload["target_comparison"]["normalization_policy"],
        )
        self.assertEqual([], payload["issues"])


if __name__ == "__main__":
    unittest.main()
