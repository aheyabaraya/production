#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import math
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
LAUNCHER = ROOT / "scripts/idol-video-python"
SCRIPT = ROOT / "scripts/idol_measure_sequence_motion_timeline.py"
AMBIGUITY = "unresolved_2d_projection_cannot_separate_camera_from_subject"


def tool_path(name: str) -> str:
    for prefix in ("/opt/homebrew/bin", "/usr/local/bin"):
        candidate = Path(prefix) / name
        if candidate.exists():
            return str(candidate)
    found = shutil.which(name)
    if not found:
        raise unittest.SkipTest(f"missing {name}")
    return found


class IdolMeasureSequenceMotionTimelineTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if not LAUNCHER.is_file() or not SCRIPT.is_file():
            raise unittest.SkipTest("measurement runtime missing")
        cls.ffmpeg = tool_path("ffmpeg")
        tool_path("ffprobe")

    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory(prefix="idol-smm-", dir="/private/tmp")
        self.work = Path(self.tmp.name)
        self.repo = self.work / "repo"
        (self.repo / "schemas").mkdir(parents=True)
        shutil.copy(
            ROOT / "schemas/sequence-motion-machine-measurement.schema.json",
            self.repo / "schemas/sequence-motion-machine-measurement.schema.json",
        )
        self.media = self.repo / "media"
        self.media.mkdir()

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def encode(self, name: str, args: list[str]) -> Path:
        path = self.media / name
        completed = subprocess.run(args + [str(path)], check=False, capture_output=True)
        if completed.returncode != 0:
            raise unittest.SkipTest(completed.stderr.decode("utf-8", "replace"))
        return path

    def measure(
        self,
        video: Path,
        extra: list[str] | None = None,
        samples: str = "0,1,2,3,4",
        admitted: tuple[str, str] = ("0", "4"),
        output: Path | None = None,
    ) -> dict:
        output = output or (self.repo / "results" / "nested" / "out.json")
        cache_dir = self.repo / "cache"
        command = [
            str(LAUNCHER),
            str(SCRIPT),
            "--repo-root",
            str(self.repo),
            "--video",
            str(video),
            "--output",
            str(output),
            "--cache-dir",
            str(cache_dir),
            "--admitted-start",
            admitted[0],
            "--admitted-end",
            admitted[1],
            "--sample-times",
            samples,
        ]
        if extra:
            command.extend(extra)
        completed = subprocess.run(command, check=False, capture_output=True, text=True)
        payload = json.loads(completed.stdout) if completed.stdout.strip() else {}
        artifact = json.loads(output.read_text()) if output.is_file() else None
        return {
            "status": completed.returncode,
            "stdout": payload,
            "stderr": completed.stderr,
            "output": output,
            "cache_dir": cache_dir,
            "artifact": artifact,
        }

    def test_nested_new_output_dir_and_hard_cut_candidate(self) -> None:
        video = self.encode(
            "cut.mp4",
            [
                self.ffmpeg, "-hide_banner", "-loglevel", "error", "-y",
                "-f", "lavfi", "-i", "color=c=black:s=160x90:r=24:d=2",
                "-f", "lavfi", "-i", "color=c=white:s=160x90:r=24:d=3",
                "-filter_complex", "[0:v][1:v]concat=n=2:v=1:a=0",
                "-c:v", "libx264", "-pix_fmt", "yuv420p",
            ],
        )
        result = self.measure(video)
        self.assertEqual(result["status"], 0, result["stderr"] + str(result["stdout"]))
        artifact = result["artifact"]
        self.assertTrue(result["output"].is_file())
        self.assertEqual(artifact["schema_version"], "idol_sequence_motion_machine_measurement.v1")
        self.assertNotIn("cache_hit", artifact)
        self.assertNotIn("user_selected_tool_name", artifact)
        self.assertEqual(artifact["sequence_sample_timestamps_seconds"], [0.0, 1.0, 2.0, 3.0, 4.0])
        self.assertTrue(all(row["camera_subject_ambiguity"] == AMBIGUITY for row in artifact["motion_timeline"]))
        pts = [row["pts_seconds"] for row in artifact["motion_timeline"]]
        self.assertTrue(all(right > left for left, right in zip(pts, pts[1:])))
        self.assertEqual(len(artifact["motion_timeline"]), artifact["decode_work"]["frames_emitted"])
        self.assertTrue(
            any(row["mean_abs_luma_delta"] >= 0.25 for row in artifact["motion_timeline"])
            or any(pair[0] < 2.0 <= pair[1] for pair in (row["between_pts_seconds"] for row in artifact["scene_cut_discontinuities"]))
        )
        self.assertTrue(all(row["status"] == "candidate_discontinuity" for row in artifact["scene_cut_discontinuities"]))
        self.assertNotIn("observed_motion_family", artifact)
        self.assertNotIn("pan", json.dumps(artifact.get("authority")))

    def test_late_window_emitted_frames_stay_in_trim_and_are_bounded(self) -> None:
        video = self.encode(
            "long.mp4",
            [
                self.ffmpeg, "-hide_banner", "-loglevel", "error", "-y",
                "-f", "lavfi", "-i", "color=c=green:s=160x90:r=24:d=120",
                "-c:v", "libx264", "-pix_fmt", "yuv420p",
            ],
        )
        result = self.measure(
            video,
            samples="20,21,22,23,24",
            admitted=("0", "120"),
            output=self.repo / "results" / "late-longtail.json",
        )
        self.assertEqual(result["status"], 0, result["stderr"] + str(result["stdout"]))
        work = result["artifact"]["decode_work"]
        last_pts = result["artifact"]["motion_timeline"][-1]["pts_seconds"]
        self.assertLess(work["frames_emitted"], 200)
        self.assertLess(work["input_span_seconds"], 6.0)
        self.assertGreaterEqual(work["window_seconds"]["start"], 20.0 - 0.001)
        self.assertLess(work["window_seconds"]["end"], 26.0)
        self.assertLess(last_pts, 26.0)
        first_pts = result["artifact"]["sampled_frames"][0]["decoded_pts_seconds"]
        self.assertGreaterEqual(first_pts, 19.5)
        self.assertTrue(all(row["pts_seconds"] >= 19.5 for row in result["artifact"]["motion_timeline"]))

    def test_nonzero_small_window_and_vfr_passthrough_pts(self) -> None:
        small = self.encode(
            "nifr.mp4",
            [
                self.ffmpeg, "-hide_banner", "-loglevel", "error", "-y",
                "-f", "lavfi", "-i", "color=c=green:s=160x90:r=12.5:d=6",
                "-c:v", "libx264", "-pix_fmt", "yuv420p",
            ],
        )
        first = self.measure(
            small,
            samples="1,2,3,4,5",
            admitted=("0", "6"),
            output=self.repo / "results" / "nifr.json",
        )
        self.assertEqual(first["status"], 0, first["stderr"])
        self.assertTrue(all(math.isfinite(row["decoded_pts_seconds"]) for row in first["artifact"]["sampled_frames"]))
        self.assertGreaterEqual(first["artifact"]["sampled_frames"][0]["decoded_pts_seconds"], 0.5)
        vfr = self.encode(
            "vfr.mp4",
            [
                self.ffmpeg, "-hide_banner", "-loglevel", "error", "-y",
                "-f", "lavfi", "-i", "color=c=red:s=160x90:r=24:d=2",
                "-f", "lavfi", "-i", "color=c=blue:s=160x90:r=30:d=3",
                "-filter_complex", "[0:v][1:v]concat=n=2:v=1:a=0",
                "-vsync", "passthrough",
                "-c:v", "libx264", "-pix_fmt", "yuv420p",
            ],
        )
        second = self.measure(vfr, output=self.repo / "results" / "vfr.json")
        self.assertEqual(second["status"], 0, second["stderr"])
        pts = [row["pts_seconds"] for row in second["artifact"]["motion_timeline"]]
        self.assertTrue(all(right > left for left, right in zip(pts, pts[1:])))
        self.assertEqual(len(pts), second["artifact"]["decode_work"]["frames_emitted"])

    def test_cache_hit_preserves_bytes_and_timeline_mutation_is_detected(self) -> None:
        video = self.encode(
            "solid.mp4",
            [
                self.ffmpeg, "-hide_banner", "-loglevel", "error", "-y",
                "-f", "lavfi", "-i", "color=c=green:s=160x90:r=24:d=5",
                "-c:v", "libx264", "-pix_fmt", "yuv420p",
            ],
        )
        first = self.measure(video)
        self.assertEqual(first["status"], 0, first["stderr"])
        self.assertFalse(first["stdout"]["cache_hit"])
        sha = first["stdout"]["artifact_sha256"]
        self.assertEqual(hashlib.sha256(first["output"].read_bytes()).hexdigest(), sha)
        second = self.measure(video)
        self.assertEqual(second["status"], 0, second["stderr"])
        self.assertTrue(second["stdout"]["cache_hit"])
        self.assertEqual(second["stdout"]["artifact_sha256"], sha)
        self.assertEqual(hashlib.sha256(second["output"].read_bytes()).hexdigest(), sha)
        cache_files = list(second["cache_dir"].glob("*.json"))
        self.assertEqual(len(cache_files), 1)
        envelope = json.loads(cache_files[0].read_text())
        old_key = envelope["cache_key_sha256"]
        envelope["artifact"]["motion_timeline"][1]["mean_abs_luma_delta"] = 0.999
        envelope["cache_key_sha256"] = old_key
        cache_files[0].write_text(json.dumps(envelope, indent=2) + "\n")
        third = self.measure(video)
        self.assertNotEqual(third["status"], 0)
        self.assertFalse(third["stdout"].get("valid", True))

    def test_rejects_collisions_escape_and_nonfinite_inputs(self) -> None:
        video = self.encode(
            "ok.mp4",
            [
                self.ffmpeg, "-hide_banner", "-loglevel", "error", "-y",
                "-f", "lavfi", "-i", "color=c=green:s=160x90:r=24:d=5",
                "-c:v", "libx264", "-pix_fmt", "yuv420p",
            ],
        )
        collide = subprocess.run(
            [str(LAUNCHER), str(SCRIPT), "--repo-root", str(self.repo), "--video", str(video), "--output", str(video), "--admitted-start", "0", "--admitted-end", "4", "--sample-times", "0,1,2,3,4"],
            check=False, capture_output=True, text=True,
        )
        self.assertNotEqual(collide.returncode, 0)
        self.assertIn("collides", collide.stdout)
        escaped = subprocess.run(
            [str(LAUNCHER), str(SCRIPT), "--repo-root", str(self.repo), "--video", str(video), "--output", str(self.work / "outside.json"), "--admitted-start", "0", "--admitted-end", "4", "--sample-times", "0,1,2,3,4"],
            check=False, capture_output=True, text=True,
        )
        self.assertNotEqual(escaped.returncode, 0)
        nan = self.measure(video, extra=["--admitted-start", "nan"])
        self.assertNotEqual(nan["status"], 0)
        inf = subprocess.run(
            [str(LAUNCHER), str(SCRIPT), "--repo-root", str(self.repo), "--video", str(video), "--output", str(self.repo / "inf.json"), "--admitted-start", "0", "--admitted-end", "inf", "--sample-times", "0,1,2,3,4"],
            check=False, capture_output=True, text=True,
        )
        self.assertNotEqual(inf.returncode, 0)
        dim = self.measure(video, extra=["--analysis-width", "0"])
        self.assertNotEqual(dim["status"], 0)
        oob = self.measure(video, samples="0,1,2,3,8", admitted=("0", "4"))
        self.assertNotEqual(oob["status"], 0)
        two = self.measure(video, samples="0,2,4,6,8", admitted=("0", "8"))
        self.assertNotEqual(two["status"], 0)

    def test_undecodable_bytes_hold(self) -> None:
        fake = self.media / "fake.mp4"
        fake.write_bytes(b"registered source video fixture bytes\n")
        result = self.measure(fake)
        self.assertNotEqual(result["status"], 0)


if __name__ == "__main__":
    unittest.main()
