from __future__ import annotations

import copy
import sys
import tempfile
import unittest
from argparse import Namespace
from pathlib import Path
from unittest.mock import patch

import yaml


ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "scripts"
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))

from lib.idol_api_video_quality import (  # noqa: E402
    ApiVideoQualityError,
    QUALITY_PROFILE,
    sha256_file,
    target_geometry,
    validate_probe_document,
    validate_quality_receipt,
)
import idol_platform_draft_upload as draft_uploader  # noqa: E402


def probe_document(
    *,
    width: int = 1440,
    height: int = 2560,
    average_fps: str = "30/1",
    nominal_fps: str = "30/1",
    audio_bit_rate: str = "320000",
) -> dict:
    return {
        "streams": [
            {
                "index": 0,
                "codec_type": "video",
                "codec_name": "h264",
                "width": width,
                "height": height,
                "r_frame_rate": nominal_fps,
                "avg_frame_rate": average_fps,
                "pix_fmt": "yuv420p",
                "field_order": "progressive",
                "bit_rate": "20000000",
            },
            {
                "index": 1,
                "codec_type": "audio",
                "codec_name": "aac",
                "r_frame_rate": "0/0",
                "avg_frame_rate": "0/0",
                "bit_rate": audio_bit_rate,
                "sample_rate": "48000",
                "channels": 2,
            },
        ],
        "format": {
            "duration": "34.0",
            "size": "86088509",
            "bit_rate": "20256119",
            "format_name": "mov,mp4,m4a,3gp,3g2,mj2",
        },
    }


def receipt_document(asset: Path, probe: dict, content_id: str) -> dict:
    return {
        "schema_version": "idol_api_upload_video.v1",
        "content_id": content_id,
        "status": "prepared_local",
        "quality_profile": QUALITY_PROFILE,
        "source": {
            "path": str(asset),
            "sha256": sha256_file(asset),
            "width": 1440,
            "height": 2560,
            "avg_frame_rate": "30/1",
        },
        "transform": {
            "mode": "byte_identical_copy",
            "no_downscale": True,
            "scale_filter": "lanczos",
            "target_fps": "30/1_cfr",
            "video_codec": "libx264",
            "video_preset": "slow",
            "video_crf": 14,
            "pixel_format": "yuv420p",
            "audio_codec": "aac",
            "audio_bit_rate": 320000,
            "audio_sample_rate": 48000,
            "faststart": True,
        },
        "output": {
            "path": str(asset),
            "sha256": sha256_file(asset),
            "bytes": asset.stat().st_size,
            **{
                field: probe[field]
                for field in (
                    "width",
                    "height",
                    "avg_frame_rate",
                    "r_frame_rate",
                    "video_codec",
                    "pixel_format",
                    "audio_codec",
                    "audio_bit_rate",
                    "audio_sample_rate",
                    "duration_seconds",
                )
            },
        },
        "external_action": "not_performed",
    }


class ApiVideoQualityTest(unittest.TestCase):
    def test_accepts_cf_reference_shape_and_rate(self) -> None:
        result = validate_probe_document(probe_document())
        self.assertEqual(QUALITY_PROFILE, result["quality_profile"])
        self.assertEqual((1440, 2560), (result["width"], result["height"]))
        self.assertEqual("30/1", result["avg_frame_rate"])
        self.assertEqual("exact_approved_bytes_no_uploader_transcode", result["byte_delivery"])

    def test_rejects_sub_2k_video(self) -> None:
        with self.assertRaisesRegex(ApiVideoQualityError, "below the 2K floor"):
            validate_probe_document(probe_document(width=1080, height=1920))

    def test_rejects_24fps_and_vfr(self) -> None:
        with self.assertRaisesRegex(ApiVideoQualityError, "exact CFR 30fps"):
            validate_probe_document(probe_document(average_fps="24/1", nominal_fps="24/1"))
        with self.assertRaisesRegex(ApiVideoQualityError, "exact CFR 30fps"):
            validate_probe_document(probe_document(average_fps="30/1", nominal_fps="60/1"))

    def test_rejects_low_audio_delivery(self) -> None:
        with self.assertRaisesRegex(ApiVideoQualityError, "audio bit rate"):
            validate_probe_document(probe_document(audio_bit_rate="192000"))

    def test_target_geometry_never_downscales_and_preserves_common_ratios(self) -> None:
        self.assertEqual((2560, 1440), target_geometry(1920, 1080))
        self.assertEqual((1440, 2560), target_geometry(720, 1280))
        self.assertEqual((3840, 2160), target_geometry(3840, 2160))
        self.assertEqual((2048, 2560), target_geometry(1080, 1350))

    def test_receipt_binds_exact_asset_and_live_probe(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            run_root = Path(temporary)
            asset = run_root / "idol-2k30.mp4"
            asset.write_bytes(b"approved-video-bytes")
            probe = validate_probe_document(probe_document())
            probe["sha256"] = sha256_file(asset)
            receipt_path = run_root / "idol-2k30.receipt.yaml"
            receipt_path.write_text(
                yaml.safe_dump(receipt_document(asset, probe, "IDOL_MV_TEST_001"), sort_keys=False),
                encoding="utf-8",
            )
            validated = validate_quality_receipt(
                repo_root=ROOT,
                run_root=run_root,
                content_id="IDOL_MV_TEST_001",
                asset_path=asset,
                receipt_path=receipt_path,
                probe=probe,
            )
            self.assertEqual(QUALITY_PROFILE, validated["quality_profile"])

            stale = copy.deepcopy(receipt_document(asset, probe, "IDOL_MV_TEST_001"))
            stale["output"]["avg_frame_rate"] = "24/1"
            receipt_path.write_text(yaml.safe_dump(stale, sort_keys=False), encoding="utf-8")
            with self.assertRaisesRegex(ApiVideoQualityError, "schema failure"):
                validate_quality_receipt(
                    repo_root=ROOT,
                    run_root=run_root,
                    content_id="IDOL_MV_TEST_001",
                    asset_path=asset,
                    receipt_path=receipt_path,
                    probe=probe,
                )

    def test_automatic_uploader_requires_profile_and_receipt_before_network(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            run_root = Path(temporary)
            asset = run_root / "idol-2k30.mp4"
            asset.write_bytes(b"approved-video-bytes")
            receipt = run_root / "idol-2k30.receipt.yaml"
            receipt.write_text("receipt: fixture\n", encoding="utf-8")
            args = Namespace(
                _run_path=str(run_root),
                content_id="IDOL_MV_TEST_001",
            )
            row = {
                "post_id": "IDOL_MV_TEST_001-YS-001",
                "asset_or_clip": str(asset),
                "api_upload_quality_profile": QUALITY_PROFILE,
                "api_upload_quality_receipt": str(receipt),
            }
            probe = {
                **validate_probe_document(probe_document()),
                "sha256": sha256_file(asset),
            }
            with (
                patch.object(
                    draft_uploader,
                    "validate_run_owned_path",
                    side_effect=lambda _root, _run, value, _label, **_kwargs: Path(value),
                ),
                patch.object(draft_uploader, "row_asset_path", return_value=asset),
                patch.object(draft_uploader, "inspect_api_upload_video", return_value=probe),
                patch.object(
                    draft_uploader,
                    "validate_quality_receipt",
                    return_value={"sha256": "a" * 64, "transform_mode": "byte_identical_copy"},
                ),
                patch.object(
                    draft_uploader,
                    "repo_relative",
                    side_effect=lambda _root, value: Path(value).name,
                ),
            ):
                validated = draft_uploader.validate_api_upload_video_row(row, args)
            self.assertEqual(QUALITY_PROFILE, validated["quality_profile"])
            self.assertEqual("30/1", validated["avg_frame_rate"])

            missing = dict(row)
            missing.pop("api_upload_quality_receipt")
            with self.assertRaisesRegex(draft_uploader.UploadError, "receipt is required"):
                draft_uploader.validate_api_upload_video_row(missing, args)


if __name__ == "__main__":
    unittest.main()
