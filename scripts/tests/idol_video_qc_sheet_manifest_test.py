#!/usr/bin/env python3
"""Focused manifest and write-failure tests for idol_video_qc_sheet.py."""

from __future__ import annotations

import hashlib
import os
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import numpy as np


ROOT = Path(__file__).resolve().parents[2]
SCRIPTS_DIR = ROOT / "scripts"
sys.path.insert(0, str(SCRIPTS_DIR))

import idol_video_qc_sheet as qc  # noqa: E402


def sha256_bytes(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


class FakeCapture:
    def isOpened(self) -> bool:
        return True

    def release(self) -> None:
        return None


class IdolVideoQcSheetManifestTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_context = tempfile.TemporaryDirectory(
            prefix="idol-video-qc-sheet-", dir="/private/tmp"
        )
        self.temp_root = Path(self.temp_context.name)
        self.video = self.temp_root / "source.mp4"
        self.video_bytes = b"durable-source-video-evidence"
        self.video.write_bytes(self.video_bytes)

    def tearDown(self) -> None:
        self.temp_context.cleanup()

    @staticmethod
    def fake_make_sheet(
        video: Path,
        out: Path,
        times: list[float],
        label_offset: float,
        columns: int,
        thumb_width: int,
        thumb_height: int,
        cell_crops_dir: Path | None = None,
        cell_ids: list[str] | None = None,
    ) -> list[dict[str, str | int]]:
        del video, label_offset, columns, thumb_width, thumb_height
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_bytes(
            (out.name + ":" + ",".join(str(value) for value in times)).encode(
                "utf-8"
            )
        )
        crop_records: list[dict[str, str | int]] = []
        if cell_crops_dir is not None and cell_ids is not None:
            suffix = out.suffix or ".png"
            for cell_id, time_seconds in zip(cell_ids, times, strict=True):
                crop_path = cell_crops_dir / f"{cell_id}{suffix}"
                crop_path.parent.mkdir(parents=True, exist_ok=True)
                crop_path.write_bytes(f"{cell_id}:{time_seconds}".encode("utf-8"))
                crop_records.append(qc.file_evidence(crop_path))
        return crop_records

    def run_main(self, *arguments: str) -> int:
        argv = ["idol_video_qc_sheet.py", *arguments]
        self.make_sheet_calls = 0
        with (
            mock.patch.object(sys, "argv", argv),
            mock.patch.object(qc, "make_sheet", side_effect=self.fake_make_sheet) as mocked,
        ):
            try:
                qc.main()
            finally:
                self.make_sheet_calls = mocked.call_count
        return self.make_sheet_calls

    def test_broad_source_manifest_is_a_hash_bound_ordered_frame_index(self) -> None:
        out = self.temp_root / "broad-source.png"
        manifest = self.temp_root / "broad-source-manifest.json"

        self.run_main(
            "--video",
            str(self.video),
            "--out",
            str(out),
            "--duration",
            "12",
            "--preset",
            "broad-source",
            "--label-offset",
            "1.25",
            "--manifest",
            str(manifest),
        )

        payload = json.loads(manifest.read_text(encoding="utf-8"))
        self.assertEqual("idol_video_qc_sheet_manifest.v1", payload["schema_version"])
        self.assertEqual(str(self.video), payload["video"])
        self.assertEqual(
            {
                "path": str(self.video),
                "sha256": sha256_bytes(self.video_bytes),
                "size_bytes": len(self.video_bytes),
            },
            payload["source_video"],
        )
        self.assertEqual("broad-source", payload["preset"])
        self.assertEqual(6.0, payload["interval_seconds"])
        self.assertEqual(1, payload["sheet_count"])

        sheet = payload["sheets"][0]
        sheet_bytes = out.read_bytes()
        self.assertEqual(str(out), sheet["path"])
        self.assertEqual(sha256_bytes(sheet_bytes), sheet["sha256"])
        self.assertEqual(len(sheet_bytes), sheet["size_bytes"])
        self.assertEqual([0.0, 6.0, 12.0], sheet["timestamps"])
        self.assertEqual(
            [
                "sheet-001-cell-0001",
                "sheet-001-cell-0002",
                "sheet-001-cell-0003",
            ],
            [cell["cell_id"] for cell in sheet["cells"]],
        )
        self.assertEqual([1, 2, 3], [cell["order"] for cell in sheet["cells"]])
        self.assertEqual(
            [0.0, 6.0, 12.0],
            [cell["source_timestamp_seconds"] for cell in sheet["cells"]],
        )
        self.assertEqual(
            [1.25, 7.25, 13.25],
            [cell["label_timestamp_seconds"] for cell in sheet["cells"]],
        )
        self.assertEqual(
            "src 06.000s / song 07.250s", sheet["cells"][1]["label"]
        )

    def test_split_manifest_keeps_existing_part_paths_and_per_sheet_cell_order(self) -> None:
        out = self.temp_root / "split.png"
        manifest = self.temp_root / "split-manifest.json"

        self.run_main(
            "--video",
            str(self.video),
            "--out",
            str(out),
            "--duration",
            "12",
            "--preset",
            "broad-source",
            "--segment-duration",
            "10",
            "--manifest",
            str(manifest),
        )

        payload = json.loads(manifest.read_text(encoding="utf-8"))
        expected_paths = [
            qc.part_output_path(out, 1, 0.0, 10.0),
            qc.part_output_path(out, 2, 10.0, 20.0),
        ]
        self.assertEqual(
            [str(path) for path in expected_paths],
            [sheet["path"] for sheet in payload["sheets"]],
        )
        self.assertFalse(out.exists())
        self.assertEqual(
            [[0.0, 6.0], [12.0]],
            [sheet["timestamps"] for sheet in payload["sheets"]],
        )
        self.assertEqual(
            [
                ["sheet-001-cell-0001", "sheet-001-cell-0002"],
                ["sheet-002-cell-0001"],
            ],
            [
                [cell["cell_id"] for cell in sheet["cells"]]
                for sheet in payload["sheets"]
            ],
        )
        for path, sheet in zip(expected_paths, payload["sheets"], strict=True):
            data = path.read_bytes()
            self.assertEqual(sha256_bytes(data), sheet["sha256"])
            self.assertEqual(len(data), sheet["size_bytes"])

    def test_make_sheet_fails_when_opencv_does_not_write_the_image(self) -> None:
        out = self.temp_root / "write-failure.png"
        frame = np.zeros((16, 16, 3), dtype=np.uint8)
        with (
            mock.patch.object(qc.cv2, "VideoCapture", return_value=FakeCapture()),
            mock.patch.object(qc, "frame_at", return_value=frame),
            mock.patch.object(qc.cv2, "imwrite", return_value=False),
        ):
            with self.assertRaisesRegex(RuntimeError, "Could not write contact sheet"):
                qc.make_sheet(
                    video=self.video,
                    out=out,
                    times=[0.0],
                    label_offset=0.0,
                    columns=1,
                    thumb_width=64,
                    thumb_height=36,
                )

    def test_make_sheet_writes_hash_bound_individual_cell_crops(self) -> None:
        out = self.temp_root / "crop-source.png"
        crops_dir = self.temp_root / "cells"
        frame = np.zeros((16, 16, 3), dtype=np.uint8)
        frame[:, :, 1] = 255
        with (
            mock.patch.object(qc.cv2, "VideoCapture", return_value=FakeCapture()),
            mock.patch.object(qc, "frame_at", return_value=frame),
        ):
            crops = qc.make_sheet(
                video=self.video,
                out=out,
                times=[0.0, 1.0],
                label_offset=0.0,
                columns=2,
                thumb_width=64,
                thumb_height=36,
                cell_crops_dir=crops_dir,
                cell_ids=["sheet-001-cell-0001", "sheet-001-cell-0002"],
            )

        self.assertEqual(2, len(crops))
        self.assertEqual(
            [
                str(crops_dir / "sheet-001-cell-0001.png"),
                str(crops_dir / "sheet-001-cell-0002.png"),
            ],
            [crop["path"] for crop in crops],
        )
        for crop in crops:
            crop_path = Path(str(crop["path"]))
            self.assertTrue(crop_path.is_file())
            self.assertEqual(sha256_bytes(crop_path.read_bytes()), crop["sha256"])
            self.assertEqual(crop_path.stat().st_size, crop["size_bytes"])

        cells = qc.cell_records(1, [0.0, 1.0], 0.0, crops)
        self.assertEqual(crops[0], cells[0]["cell_crop"])
        self.assertEqual(crops[1], cells[1]["cell_crop"])

    def test_make_sheet_existing_crop_does_not_write_sheet(self) -> None:
        out = self.temp_root / "crop-source.png"
        crops_dir = self.temp_root / "cells"
        crops_dir.mkdir()
        (crops_dir / "sheet-001-cell-0001.png").write_bytes(b"existing-crop")
        with (
            mock.patch.object(qc.cv2, "VideoCapture") as capture,
            mock.patch.object(qc.cv2, "imwrite") as imwrite,
        ):
            with self.assertRaisesRegex(RuntimeError, "existing contact-sheet cell crop"):
                qc.make_sheet(
                    video=self.video,
                    out=out,
                    times=[0.0],
                    label_offset=0.0,
                    columns=1,
                    thumb_width=64,
                    thumb_height=36,
                    cell_crops_dir=crops_dir,
                    cell_ids=["sheet-001-cell-0001"],
                )
        capture.assert_not_called()
        imwrite.assert_not_called()
        self.assertFalse(out.exists())

    def test_existing_crop_conflict_writes_zero_sheets(self) -> None:
        out = self.temp_root / "split.png"
        manifest = self.temp_root / "split-manifest.json"
        crops_dir = self.temp_root / "cells"
        crops_dir.mkdir()
        existing = crops_dir / "sheet-002-cell-0001.png"
        existing.write_bytes(b"preexisting-crop")
        with self.assertRaisesRegex(SystemExit, "unowned existing"):
            self.run_main(
                "--video",
                str(self.video),
                "--out",
                str(out),
                "--duration",
                "12",
                "--preset",
                "broad-source",
                "--segment-duration",
                "10",
                "--manifest",
                str(manifest),
                "--cell-crops-dir",
                str(crops_dir),
            )
        self.assertEqual(0, self.make_sheet_calls)
        self.assertFalse(qc.part_output_path(out, 1, 0.0, 10.0).exists())
        self.assertFalse(qc.part_output_path(out, 2, 10.0, 20.0).exists())
        self.assertFalse(manifest.exists())
        self.assertEqual(b"preexisting-crop", existing.read_bytes())

    def test_source_and_sheet_manifest_collisions_are_rejected(self) -> None:
        out = self.temp_root / "sheet.png"
        with self.assertRaisesRegex(SystemExit, "colliding paths"):
            self.run_main(
                "--video",
                str(self.video),
                "--out",
                str(out),
                "--times",
                "0",
                "--manifest",
                str(self.video),
            )
        self.assertEqual(0, self.make_sheet_calls)
        self.assertFalse(out.exists())

        same = self.temp_root / "same.png"
        with self.assertRaisesRegex(SystemExit, "colliding paths"):
            self.run_main(
                "--video",
                str(self.video),
                "--out",
                str(same),
                "--times",
                "0",
                "--manifest",
                str(same),
            )
        self.assertEqual(0, self.make_sheet_calls)
        self.assertFalse(same.exists())

    def test_input_inode_alias_is_rejected(self) -> None:
        out = self.temp_root / "aliased-out.png"
        os.link(str(self.video), str(out))
        with self.assertRaisesRegex(SystemExit, "colliding paths"):
            self.run_main(
                "--video",
                str(self.video),
                "--out",
                str(out),
                "--times",
                "0",
            )
        self.assertEqual(0, self.make_sheet_calls)
        self.assertEqual(self.video_bytes, out.read_bytes())

    def test_dangling_output_leaf_symlink_is_rejected(self) -> None:
        out = self.temp_root / "sheet.png"
        out.symlink_to(self.temp_root / "missing-target.png")
        with self.assertRaisesRegex(SystemExit, "output leaf symlink"):
            self.run_main(
                "--video",
                str(self.video),
                "--out",
                str(out),
                "--times",
                "0",
            )
        self.assertEqual(0, self.make_sheet_calls)
        self.assertTrue(out.is_symlink())
        self.assertFalse(out.exists())

    def test_complete_identical_reuse_preserves_mtime_and_file_count(self) -> None:
        out = self.temp_root / "broad-source.png"
        manifest = self.temp_root / "broad-source-manifest.json"
        args = (
            "--video",
            str(self.video),
            "--out",
            str(out),
            "--duration",
            "12",
            "--preset",
            "broad-source",
            "--label-offset",
            "1.25",
            "--manifest",
            str(manifest),
        )
        self.assertEqual(1, self.run_main(*args))
        sheet_mtime = out.stat().st_mtime_ns
        manifest_mtime = manifest.stat().st_mtime_ns
        file_count = sum(1 for path in self.temp_root.rglob("*") if path.is_file())
        self.assertEqual(0, self.run_main(*args))
        self.assertEqual(sheet_mtime, out.stat().st_mtime_ns)
        self.assertEqual(manifest_mtime, manifest.stat().st_mtime_ns)
        self.assertEqual(
            file_count,
            sum(1 for path in self.temp_root.rglob("*") if path.is_file()),
        )

    def test_changed_output_refuses_false_reuse(self) -> None:
        out = self.temp_root / "broad-source.png"
        manifest = self.temp_root / "broad-source-manifest.json"
        args = (
            "--video",
            str(self.video),
            "--out",
            str(out),
            "--duration",
            "12",
            "--preset",
            "broad-source",
            "--manifest",
            str(manifest),
        )
        self.run_main(*args)
        out.write_bytes(b"tampered-output-bytes")
        with self.assertRaisesRegex(SystemExit, "cannot be reused"):
            self.run_main(*args)
        self.assertEqual(0, self.make_sheet_calls)
        self.assertEqual(b"tampered-output-bytes", out.read_bytes())
        payload = json.loads(manifest.read_text(encoding="utf-8"))
        del payload["sheets"][0]["sha256"]
        manifest.write_text(json.dumps(payload) + "\n", encoding="utf-8")
        before = manifest.read_bytes()
        with self.assertRaisesRegex(SystemExit, "cannot be reused"):
            self.run_main(*args)
        self.assertEqual(0, self.make_sheet_calls)
        self.assertEqual(before, manifest.read_bytes())

    def test_split_crop_manifest_stays_v1_hash_bound(self) -> None:
        out = self.temp_root / "split.png"
        manifest = self.temp_root / "split-manifest.json"
        crops_dir = self.temp_root / "cells"
        self.run_main(
            "--video",
            str(self.video),
            "--out",
            str(out),
            "--duration",
            "12",
            "--preset",
            "broad-source",
            "--segment-duration",
            "10",
            "--manifest",
            str(manifest),
            "--cell-crops-dir",
            str(crops_dir),
        )
        payload = json.loads(manifest.read_text(encoding="utf-8"))
        self.assertEqual("idol_video_qc_sheet_manifest.v1", payload["schema_version"])
        expected_paths = [
            qc.part_output_path(out, 1, 0.0, 10.0),
            qc.part_output_path(out, 2, 10.0, 20.0),
        ]
        self.assertEqual(
            [str(path) for path in expected_paths],
            [sheet["path"] for sheet in payload["sheets"]],
        )
        self.assertEqual(
            {
                "output_dir": str(crops_dir),
                "cell_count": 3,
                "kind": "timestamp_labelled_contact_sheet_cell",
            },
            payload["cell_crops"],
        )
        self.assertEqual(
            [[0.0, 6.0], [12.0]],
            [sheet["timestamps"] for sheet in payload["sheets"]],
        )
        written = [
            cell["cell_crop"] for sheet in payload["sheets"] for cell in sheet["cells"]
        ]
        self.assertEqual(
            [
                str(crops_dir / "sheet-001-cell-0001.png"),
                str(crops_dir / "sheet-001-cell-0002.png"),
                str(crops_dir / "sheet-002-cell-0001.png"),
            ],
            [crop["path"] for crop in written],
        )
        for crop in written:
            crop_path = Path(str(crop["path"]))
            self.assertTrue(crop_path.is_file())
            self.assertEqual(sha256_bytes(crop_path.read_bytes()), crop["sha256"])
            self.assertEqual(crop_path.stat().st_size, crop["size_bytes"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
