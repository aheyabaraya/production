#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import yaml
from jsonschema import Draft202012Validator

SCRIPTS_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS_DIR))

import idol_video_source_intake as intake  # noqa: E402


class IdolVideoSourceIntakeCacheTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory(
            prefix="idol-video-source-intake-cache-", dir="/private/tmp"
        )
        self.run_root = (
            Path(self.tmp.name)
            / "runs/test-album/cache-test/0710_CACHE_TEST"
        )
        self.source = (
            self.run_root / "generations/video/raw/additional/PKT_B01.mp4"
        )
        self.source.parent.mkdir(parents=True)
        self.source.write_bytes(b"fake-video-source-v1")
        self.output = (
            self.run_root
            / "generations/video/qc/source-intake/source-index-v2.yaml"
        )

    def tearDown(self) -> None:
        self.tmp.cleanup()

    @staticmethod
    def probe_document() -> dict:
        return {
            "streams": [
                {
                    "index": 0,
                    "codec_type": "video",
                    "disposition": {"attached_pic": 0},
                    "width": 1280,
                    "height": 720,
                    "avg_frame_rate": "24/1",
                    "r_frame_rate": "24/1",
                    "time_base": "1/12288",
                    "nb_frames": "60",
                    "codec_name": "h264",
                    "profile": "High",
                    "pix_fmt": "yuv420p",
                    "bits_per_raw_sample": "8",
                    "sample_aspect_ratio": "1:1",
                    "display_aspect_ratio": "16:9",
                    "field_order": "progressive",
                    "color_range": "tv",
                    "color_space": "bt709",
                    "color_transfer": "bt709",
                    "color_primaries": "bt709",
                }
            ],
            "format": {"duration": "2.5"},
        }

    @staticmethod
    def fake_motion(_path: Path, sample_fps: float) -> list[dict]:
        return [{"time_seconds": 0.5, "motion_score": round(sample_fps, 6)}]

    @staticmethod
    def fake_sheet(
        _video_path: Path, out_path: Path, _duration: float, fps: float
    ) -> None:
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_bytes(f"sheet-fps={fps}".encode("utf-8"))

    def build(self, *, sample_fps: float = 4.0, force_refresh: bool = False):
        stats: dict = {}
        payload = intake.build_index(
            run_root=self.run_root,
            output_path=self.output,
            write_contact_sheets=True,
            include_motion=True,
            sample_fps=sample_fps,
            contact_fps=1.0,
            force_refresh=force_refresh,
            cache_stats=stats,
        )
        return payload, stats

    def first_build(self):
        with (
            mock.patch.object(
                intake, "ffprobe_json", return_value=self.probe_document()
            ),
            mock.patch.object(
                intake, "motion_peaks", side_effect=self.fake_motion
            ),
            mock.patch.object(
                intake, "make_contact_sheet", side_effect=self.fake_sheet
            ),
        ):
            return self.build()

    def test_identical_source_and_settings_reuse_every_component_deterministically(self):
        first_payload, first_stats = self.first_build()
        first_bytes = self.output.read_bytes()

        with (
            mock.patch.object(
                intake,
                "ffprobe_json",
                side_effect=AssertionError("probe should be reused"),
            ),
            mock.patch.object(
                intake,
                "motion_peaks",
                side_effect=AssertionError("motion should be reused"),
            ),
            mock.patch.object(
                intake,
                "make_contact_sheet",
                side_effect=AssertionError("contact sheet should be reused"),
            ),
        ):
            second_payload, second_stats = self.build()

        self.assertEqual(first_payload, second_payload)
        self.assertEqual(first_bytes, self.output.read_bytes())
        self.assertEqual(1, first_stats["probe_misses"])
        self.assertEqual(1, first_stats["motion_misses"])
        self.assertEqual(1, first_stats["contact_sheet_misses"])
        self.assertEqual(1, second_stats["probe_hits"])
        self.assertEqual(1, second_stats["motion_hits"])
        self.assertEqual(1, second_stats["contact_sheet_hits"])

        source = second_payload["sources"][0]
        self.assertEqual(hashlib.sha256(self.source.read_bytes()).hexdigest(), source["source_sha256"])
        self.assertEqual("h264", source["codec"])
        probe_contract = source["probe_contract"]
        self.assertEqual("idol_video_source_probe.v2", probe_contract["schema_version"])
        self.assertEqual("cfr_candidate", probe_contract["frame_rate"]["rate_mode"])
        self.assertFalse(probe_contract["frame_rate"]["vfr_candidate"])
        self.assertEqual("tagged_complete", probe_contract["color"]["metadata_status"])
        self.assertEqual("bt709", probe_contract["color"]["color_primaries"])
        self.assertEqual(8, probe_contract["codec"]["declared_bit_depth"])
        for field in (
            "probe_cache_key_sha256",
            "motion_cache_key_sha256",
            "contact_sheet_cache_key_sha256",
        ):
            self.assertRegex(source["cache_fingerprints"][field], r"^[a-f0-9]{64}$")
        for field in (
            "probe_output_sha256",
            "motion_output_sha256",
            "contact_sheet_output_sha256",
        ):
            self.assertRegex(source["cache_evidence"][field], r"^[a-f0-9]{64}$")
        for field in (
            "probe_settings_sha256",
            "motion_settings_sha256",
            "contact_sheet_settings_sha256",
        ):
            self.assertRegex(second_payload["cache_contract"][field], r"^[a-f0-9]{64}$")
        self.assertEqual(
            "sha256", second_payload["cache_contract"]["component_output_hash_algorithm"]
        )
        self.assertEqual(
            "idol_video_source_intake_cache.v4",
            second_payload["cache_contract"]["schema_version"],
        )
        self.assertEqual("idol_video_source_intake.v2", second_payload["schema_version"])
        self.assertNotIn("legacy_additional_dir", second_payload)
        self.assertEqual(
            "repeat_local_validation",
            second_payload["cache_contract"]["routine_source_hash_profile"],
        )
        self.assertEqual(1, second_stats["source_hash_cache_hits"])
        self.assertEqual(1, second_stats["contact_sheet_hash_cache_hits"])
        schema = json.loads(
            (
                SCRIPTS_DIR.parent / "schemas/video-source-intake.schema.json"
            ).read_text(encoding="utf-8")
        )
        Draft202012Validator.check_schema(schema)
        self.assertEqual(
            [],
            list(Draft202012Validator(schema).iter_errors(second_payload)),
        )

    def test_populated_retired_misspelled_folder_holds_before_probe(self):
        retired_source = (
            self.run_root / "generations/video/raw/addiontal/RETIRED.mp4"
        )
        retired_source.parent.mkdir(parents=True)
        retired_source.write_bytes(b"historical-evidence")

        with self.assertRaisesRegex(
            RuntimeError,
            r"retired raw/addiontal.*hash-bound plan.*raw/additional",
        ):
            intake.build_index(
                run_root=self.run_root,
                output_path=self.output,
                write_contact_sheets=False,
                include_motion=False,
                sample_fps=4.0,
                contact_fps=1.0,
            )

    def test_frame_rate_mismatch_is_candidate_only_and_missing_color_stays_unknown(self):
        probe = self.probe_document()
        stream = probe["streams"][0]
        stream["avg_frame_rate"] = "24000/1001"
        stream["r_frame_rate"] = "30/1"
        for key in ("color_range", "color_space", "color_transfer", "color_primaries"):
            stream.pop(key)

        with (
            mock.patch.object(intake, "ffprobe_json", return_value=probe),
            mock.patch.object(intake, "motion_peaks", side_effect=self.fake_motion),
            mock.patch.object(
                intake, "make_contact_sheet", side_effect=self.fake_sheet
            ),
        ):
            payload, _ = self.build()

        contract = payload["sources"][0]["probe_contract"]
        self.assertEqual("vfr_candidate", contract["frame_rate"]["rate_mode"])
        self.assertTrue(contract["frame_rate"]["vfr_candidate"])
        self.assertEqual("unknown", contract["color"]["metadata_status"])
        self.assertEqual("unknown", contract["color"]["color_space"])
        self.assertIn("not a color transform", contract["color"]["interpretation_policy"])

    def test_unavailable_frame_rates_remain_unknown_instead_of_crashing(self):
        probe = self.probe_document()
        stream = probe["streams"][0]
        stream["avg_frame_rate"] = "N/A"
        stream["r_frame_rate"] = "0/0"

        with (
            mock.patch.object(intake, "ffprobe_json", return_value=probe),
            mock.patch.object(intake, "motion_peaks", side_effect=self.fake_motion),
            mock.patch.object(
                intake, "make_contact_sheet", side_effect=self.fake_sheet
            ),
        ):
            payload, _ = self.build()

        contract = payload["sources"][0]["probe_contract"]
        self.assertEqual("unknown", contract["frame_rate"]["rate_mode"])
        self.assertIsNone(contract["frame_rate"]["vfr_candidate"])
        self.assertEqual(0.0, payload["sources"][0]["fps"])

    def test_implementation_change_invalidates_only_affected_component(self):
        first_payload, _ = self.first_build()
        original = intake.implementation_fingerprints()
        changed = dict(original)
        changed["motion"] = "f" * 64
        with (
            mock.patch.object(intake, "implementation_fingerprints", return_value=changed),
            mock.patch.object(
                intake,
                "ffprobe_json",
                side_effect=AssertionError("probe implementation stayed current"),
            ),
            mock.patch.object(intake, "motion_peaks", side_effect=self.fake_motion) as motion,
            mock.patch.object(
                intake,
                "make_contact_sheet",
                side_effect=AssertionError("contact-sheet implementation stayed current"),
            ),
        ):
            second_payload, stats = self.build()

        motion.assert_called_once()
        self.assertEqual(1, stats["probe_hits"])
        self.assertEqual(1, stats["motion_misses"])
        self.assertEqual(1, stats["contact_sheet_hits"])
        self.assertNotEqual(
            first_payload["cache_contract"]["motion_settings_sha256"],
            second_payload["cache_contract"]["motion_settings_sha256"],
        )

    def test_skipped_contact_sheet_does_not_publish_a_missing_path(self):
        stats: dict = {}
        with (
            mock.patch.object(intake, "ffprobe_json", return_value=self.probe_document()),
            mock.patch.object(intake, "motion_peaks", side_effect=self.fake_motion),
        ):
            payload = intake.build_index(
                run_root=self.run_root,
                output_path=self.output,
                write_contact_sheets=False,
                include_motion=True,
                sample_fps=4.0,
                contact_fps=1.0,
                cache_stats=stats,
            )
        self.assertIsNone(payload["sources"][0]["contact_sheet"])
        self.assertIsNone(
            payload["sources"][0]["cache_evidence"]["contact_sheet_output_sha256"]
        )

    def test_motion_setting_change_invalidates_only_motion_component(self):
        first_payload, _ = self.first_build()
        with (
            mock.patch.object(
                intake,
                "ffprobe_json",
                side_effect=AssertionError("probe should remain fresh"),
            ),
            mock.patch.object(
                intake, "motion_peaks", side_effect=self.fake_motion
            ) as motion,
            mock.patch.object(
                intake,
                "make_contact_sheet",
                side_effect=AssertionError("contact sheet should remain fresh"),
            ),
        ):
            second_payload, stats = self.build(sample_fps=8.0)

        motion.assert_called_once()
        self.assertEqual(1, stats["probe_hits"])
        self.assertEqual(1, stats["motion_misses"])
        self.assertEqual(1, stats["contact_sheet_hits"])
        first_fingerprints = first_payload["sources"][0]["cache_fingerprints"]
        second_fingerprints = second_payload["sources"][0]["cache_fingerprints"]
        self.assertEqual(
            first_fingerprints["probe_cache_key_sha256"],
            second_fingerprints["probe_cache_key_sha256"],
        )
        self.assertNotEqual(
            first_fingerprints["motion_cache_key_sha256"],
            second_fingerprints["motion_cache_key_sha256"],
        )
        self.assertEqual(
            first_fingerprints["contact_sheet_cache_key_sha256"],
            second_fingerprints["contact_sheet_cache_key_sha256"],
        )

    def test_source_change_invalidates_probe_motion_and_contact_sheet(self):
        self.first_build()
        self.source.write_bytes(b"fake-video-source-v2")

        with (
            mock.patch.object(
                intake, "ffprobe_json", return_value=self.probe_document()
            ) as probe,
            mock.patch.object(
                intake, "motion_peaks", side_effect=self.fake_motion
            ) as motion,
            mock.patch.object(
                intake, "make_contact_sheet", side_effect=self.fake_sheet
            ) as sheet,
        ):
            payload, stats = self.build()

        probe.assert_called_once()
        motion.assert_called_once()
        sheet.assert_called_once()
        self.assertEqual(1, stats["probe_misses"])
        self.assertEqual(1, stats["motion_misses"])
        self.assertEqual(1, stats["contact_sheet_misses"])
        self.assertEqual(
            hashlib.sha256(self.source.read_bytes()).hexdigest(),
            payload["sources"][0]["source_sha256"],
        )

    def test_force_refresh_bypasses_all_reusable_components(self):
        first_payload, _ = self.first_build()
        with (
            mock.patch.object(
                intake, "ffprobe_json", return_value=self.probe_document()
            ) as probe,
            mock.patch.object(
                intake, "motion_peaks", side_effect=self.fake_motion
            ) as motion,
            mock.patch.object(
                intake, "make_contact_sheet", side_effect=self.fake_sheet
            ) as sheet,
        ):
            second_payload, stats = self.build(force_refresh=True)

        probe.assert_called_once()
        motion.assert_called_once()
        sheet.assert_called_once()
        self.assertEqual(first_payload, second_payload)
        self.assertEqual(1, stats["probe_misses"])
        self.assertEqual(1, stats["motion_misses"])
        self.assertEqual(1, stats["contact_sheet_misses"])

    def test_missing_contact_sheet_rebuilds_only_contact_sheet(self):
        payload, _ = self.first_build()
        Path(payload["sources"][0]["contact_sheet"]).unlink()

        with (
            mock.patch.object(
                intake,
                "ffprobe_json",
                side_effect=AssertionError("probe should remain fresh"),
            ),
            mock.patch.object(
                intake,
                "motion_peaks",
                side_effect=AssertionError("motion should remain fresh"),
            ),
            mock.patch.object(
                intake, "make_contact_sheet", side_effect=self.fake_sheet
            ) as sheet,
        ):
            _, stats = self.build()

        sheet.assert_called_once()
        self.assertEqual(1, stats["probe_hits"])
        self.assertEqual(1, stats["motion_hits"])
        self.assertEqual(1, stats["contact_sheet_misses"])

    def test_tampered_probe_metadata_rebuilds_only_probe_component(self):
        self.first_build()
        index = yaml.safe_load(self.output.read_text())
        index["sources"][0]["width"] = 9999
        self.output.write_text(yaml.safe_dump(index, sort_keys=False))

        with (
            mock.patch.object(
                intake, "ffprobe_json", return_value=self.probe_document()
            ) as probe,
            mock.patch.object(
                intake,
                "motion_peaks",
                side_effect=AssertionError("untampered motion should remain fresh"),
            ),
            mock.patch.object(
                intake,
                "make_contact_sheet",
                side_effect=AssertionError("untampered contact sheet should remain fresh"),
            ),
        ):
            payload, stats = self.build()

        probe.assert_called_once()
        self.assertEqual(1280, payload["sources"][0]["width"])
        self.assertEqual(1, stats["probe_misses"])
        self.assertEqual(1, stats["motion_hits"])
        self.assertEqual(1, stats["contact_sheet_hits"])

    def test_tampered_motion_evidence_rebuilds_only_motion_component(self):
        self.first_build()
        index = yaml.safe_load(self.output.read_text())
        index["sources"][0]["motion_peaks"][0]["motion_score"] = 9999.0
        self.output.write_text(yaml.safe_dump(index, sort_keys=False))

        with (
            mock.patch.object(
                intake,
                "ffprobe_json",
                side_effect=AssertionError("untampered probe should remain fresh"),
            ),
            mock.patch.object(
                intake, "motion_peaks", side_effect=self.fake_motion
            ) as motion,
            mock.patch.object(
                intake,
                "make_contact_sheet",
                side_effect=AssertionError("untampered contact sheet should remain fresh"),
            ),
        ):
            payload, stats = self.build()

        motion.assert_called_once()
        self.assertEqual(4.0, payload["sources"][0]["motion_peaks"][0]["motion_score"])
        self.assertEqual(1, stats["probe_hits"])
        self.assertEqual(1, stats["motion_misses"])
        self.assertEqual(1, stats["contact_sheet_hits"])

    def test_tampered_contact_sheet_bytes_rebuild_only_contact_sheet(self):
        payload, _ = self.first_build()
        Path(payload["sources"][0]["contact_sheet"]).write_bytes(b"tampered sheet")

        with (
            mock.patch.object(
                intake,
                "ffprobe_json",
                side_effect=AssertionError("untampered probe should remain fresh"),
            ),
            mock.patch.object(
                intake,
                "motion_peaks",
                side_effect=AssertionError("untampered motion should remain fresh"),
            ),
            mock.patch.object(
                intake, "make_contact_sheet", side_effect=self.fake_sheet
            ) as sheet,
        ):
            rebuilt, stats = self.build()

        sheet.assert_called_once()
        self.assertEqual(
            b"sheet-fps=1.0",
            Path(rebuilt["sources"][0]["contact_sheet"]).read_bytes(),
        )
        self.assertEqual(1, stats["probe_hits"])
        self.assertEqual(1, stats["motion_hits"])
        self.assertEqual(1, stats["contact_sheet_misses"])


if __name__ == "__main__":
    unittest.main()
