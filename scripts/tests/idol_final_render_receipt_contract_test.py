#!/usr/bin/env python3
"""Fail-closed tests for observed final-render receipt metadata."""

from __future__ import annotations

import tempfile
import unittest
from fractions import Fraction
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "scripts"
import sys

sys.path.insert(0, str(SCRIPTS))

import idol_video_ffmpeg_revise_render as renderer  # noqa: E402


class FinalRenderReceiptContractTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="idol-final-receipt-")
        self.root = Path(self.temp.name)
        self.recipe = self.root / "recipe.yaml"
        self.audio = self.root / "audio.wav"
        self.output = self.root / "master.mp4"
        self.manifest = self.root / "render-manifest.yaml"
        self.compile_manifest = self.root / "compile-manifest.yaml"
        for path in (self.recipe, self.audio, self.output, self.compile_manifest):
            path.write_bytes(path.name.encode("utf-8"))
        self.spec = renderer.RenderSpec(
            fps=Fraction(24, 1),
            width=1920,
            height=1080,
            fit_mode="fit_pad",
            background="black",
            pixel_format="yuv420p",
        )
        self.encoding = renderer.EncodingSpec(
            container="mp4",
            video_codec="libx264",
            audio_codec="aac",
            video_args=(),
            audio_args=(),
        )
        self.payload = {
            "color_pipeline": {
                "delivery": {
                    "color_range": "tv",
                    "color_space": "bt709",
                    "color_transfer": "bt709",
                    "color_primaries": "bt709",
                }
            }
        }

    def tearDown(self) -> None:
        self.temp.cleanup()

    def probe(self) -> dict[str, object]:
        return {
            "format": {"duration": "0.041667"},
            "streams": [
                {
                    "codec_type": "video",
                    "codec_name": "h264",
                    "width": 1920,
                    "height": 1080,
                    "avg_frame_rate": "24/1",
                    "nb_frames": "1",
                    "pix_fmt": "yuv420p",
                    "color_range": "tv",
                    "color_space": "bt709",
                    "color_transfer": "bt709",
                    "color_primaries": "bt709",
                },
                {"codec_type": "audio", "codec_name": "aac"},
            ],
        }

    def assert_rejected(self, probe: dict[str, object], message: str) -> None:
        with mock.patch.object(renderer, "ffprobe_media", return_value=probe):
            with self.assertRaisesRegex(SystemExit, message):
                renderer.write_render_receipt(
                    self.manifest,
                    recipe_path=self.recipe,
                    audio_path=self.audio,
                    output_path=self.output,
                    compile_manifest_path=self.compile_manifest,
                    spec=self.spec,
                    width=1920,
                    height=1080,
                    profile="final",
                    expected_frames=1,
                    encoding=self.encoding,
                    recipe_payload=self.payload,
                )
        self.assertFalse(self.manifest.exists())

    def test_rejects_geometry_mismatch(self) -> None:
        probe = self.probe()
        probe["streams"][0]["width"] = 1280  # type: ignore[index]
        self.assert_rejected(probe, "geometry")

    def test_rejects_fps_mismatch(self) -> None:
        probe = self.probe()
        probe["streams"][0]["avg_frame_rate"] = "25/1"  # type: ignore[index]
        self.assert_rejected(probe, "FPS")

    def test_rejects_codec_mismatch(self) -> None:
        probe = self.probe()
        probe["streams"][0]["codec_name"] = "hevc"  # type: ignore[index]
        self.assert_rejected(probe, "video codec")

    def test_rejects_pixel_format_mismatch(self) -> None:
        probe = self.probe()
        probe["streams"][0]["pix_fmt"] = "yuv444p"  # type: ignore[index]
        self.assert_rejected(probe, "pixel format")

    def test_rejects_color_tag_mismatch(self) -> None:
        probe = self.probe()
        probe["streams"][0]["color_primaries"] = "smpte170m"  # type: ignore[index]
        self.assert_rejected(probe, "color_primaries")


if __name__ == "__main__":
    unittest.main()
