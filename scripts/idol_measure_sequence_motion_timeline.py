#!/usr/bin/env python3
"""Bounded Sequence-window machine measurement using installed ffmpeg and OpenCV.

Input -ss/-t bound the demux span. trim keeps source PTS. vsync passthrough and
showinfo share the emitted raw stream. frames_emitted is that raw output frame count. Cache envelopes store artifact SHA-256;
invocation cache-hit metadata stays off the artifact. Never authors motion
families, camera labels, Major counts, or PASS.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Any

try:
    import cv2
    import jsonschema
    import numpy as np
except ModuleNotFoundError as exc:
    raise SystemExit(
        f"Missing Python dependency '{exc.name}'. Run through scripts/idol-video-python."
    ) from exc

CONTRACT = "idol_sequence_motion_machine_measurement.v1"
AUTHORITY = "mechanical_observation_only_never_creative_pass"
ENVELOPE = "idol_sequence_motion_measurement_cache.v1"
AMBIGUITY = "unresolved_2d_projection_cannot_separate_camera_from_subject"
REQUIRED_SAMPLES = 5
STEP_SECONDS = 1.0
CADENCE_TOL = 0.001
PTS_MATCH_LIMIT = 0.5
MAX_PAD = 1.0
FARNEBACK = {
    "pyr_scale": 0.5,
    "levels": 3,
    "winsize": 15,
    "iterations": 3,
    "poly_n": 5,
    "poly_sigma": 1.2,
    "flags": 0,
}
SHOWINFO_RE = re.compile(
    r"n:\s*(\d+)\s+pts:\s*\S+\s+pts_time:(nan|[+-]?(?:\d+(?:\.\d+)?|\.\d+)(?:[eE][+-]?\d+)?)"
)


class MeasurementError(RuntimeError):
    def __init__(self, errors: list[str]):
        super().__init__("; ".join(errors))
        self.errors = errors


def fail(errors: list[str]) -> None:
    json.dump({"valid": False, "cache_hit": False, "errors": errors}, sys.stdout, indent=2, allow_nan=False)
    sys.stdout.write("\n")
    raise SystemExit(1)


def finite_number(value: Any, label: str, *, minimum: float | None = None, exclusive_minimum: float | None = None) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise MeasurementError([f"{label} must be a finite number"])
    number = float(value)
    if not math.isfinite(number):
        raise MeasurementError([f"{label} is NaN or Infinity"])
    if minimum is not None and number < minimum:
        raise MeasurementError([f"{label} is below {minimum}"])
    if exclusive_minimum is not None and number <= exclusive_minimum:
        raise MeasurementError([f"{label} must be greater than {exclusive_minimum}"])
    return number


def tool_path(name: str) -> str:
    for prefix in ("/opt/homebrew/bin", "/usr/local/bin"):
        preferred = Path(prefix) / name
        if preferred.exists():
            return str(preferred)
    found = shutil.which(name)
    if found:
        return found
    raise MeasurementError([f"missing required tool: {name}"])


def tool_version(name: str) -> str:
    result = subprocess.run([tool_path(name), "-version"], check=True, capture_output=True, text=True)
    return (result.stdout or result.stderr).splitlines()[0].strip()


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def canonical(value: Any) -> Any:
    if isinstance(value, dict):
        return {str(key): canonical(value[key]) for key in sorted(value, key=str)}
    if isinstance(value, list):
        return [canonical(item) for item in value]
    return value


def value_sha256(value: Any) -> str:
    encoded = json.dumps(canonical(value), ensure_ascii=False, separators=(",", ":"), sort_keys=True).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def artifact_bytes(document: dict[str, Any]) -> bytes:
    return (json.dumps(document, indent=2, ensure_ascii=False, allow_nan=False) + "\n").encode("utf-8")


def repo_join(path: Path, repo_root: Path) -> Path:
    return path if path.is_absolute() else repo_root / path


def reject_symlinks_to_root(path: Path, repo_root: Path, label: str) -> None:
    cursor = path
    while True:
        if cursor.is_symlink():
            raise MeasurementError([f"{label} traverses a symlink before resolve: {cursor}"])
        if cursor == repo_root or cursor == cursor.parent:
            break
        cursor = cursor.parent


def inside_repo(resolved: Path, repo_root: Path, label: str) -> Path:
    try:
        resolved.relative_to(repo_root)
    except ValueError as exc:
        raise MeasurementError([f"{label} escapes --repo-root"]) from exc
    return resolved


def contain_existing_file(path: Path, repo_root: Path, label: str) -> Path:
    raw = repo_join(path, repo_root)
    reject_symlinks_to_root(raw, repo_root, label)
    if raw.is_symlink():
        raise MeasurementError([f"{label} is a symlink"])
    if not raw.is_file():
        raise MeasurementError([f"{label} is missing or not a file"])
    return inside_repo(raw.resolve(strict=True), repo_root, label)


def contain_existing_dir(path: Path, repo_root: Path, label: str) -> Path:
    raw = repo_join(path, repo_root)
    reject_symlinks_to_root(raw, repo_root, label)
    if raw.is_symlink():
        raise MeasurementError([f"{label} is a symlink"])
    if not raw.is_dir():
        raise MeasurementError([f"{label} is missing or not a directory"])
    return inside_repo(raw.resolve(strict=True), repo_root, label)


def planned_under_repo(raw: Path, repo_root: Path, label: str) -> Path:
    ancestor = raw
    missing: list[str] = []
    while not ancestor.exists() and ancestor != repo_root and ancestor != ancestor.parent:
        missing.append(ancestor.name)
        ancestor = ancestor.parent
    reject_symlinks_to_root(ancestor, repo_root, f"{label} ancestor")
    if ancestor.is_symlink() or not ancestor.exists() or not ancestor.is_dir():
        raise MeasurementError([f"{label} has no existing directory ancestor inside --repo-root"])
    candidate = inside_repo(ancestor.resolve(strict=True), repo_root, f"{label} ancestor")
    for part in reversed(missing):
        candidate = candidate / part
    return inside_repo(candidate, repo_root, label)


def contain_new_or_existing_file(path: Path, repo_root: Path, label: str) -> Path:
    raw = repo_join(path, repo_root)
    if raw.is_symlink():
        raise MeasurementError([f"{label} is a symlink"])
    if raw.exists():
        if raw.is_dir():
            raise MeasurementError([f"{label} is a directory"])
        if not raw.is_file():
            raise MeasurementError([f"{label} exists and is not a file"])
        reject_symlinks_to_root(raw, repo_root, label)
        return inside_repo(raw.resolve(strict=True), repo_root, label)
    return planned_under_repo(raw, repo_root, label)


def contain_new_or_existing_dir(path: Path, repo_root: Path, label: str) -> Path:
    raw = repo_join(path, repo_root)
    if raw.exists():
        return contain_existing_dir(raw, repo_root, label)
    return planned_under_repo(raw, repo_root, label)


def write_all(fd: int, data: bytes) -> None:
    view = memoryview(data)
    sent = 0
    while sent < len(view):
        written = os.write(fd, view[sent:])
        if written <= 0:
            raise MeasurementError(["write returned no bytes"])
        sent += written


def atomic_create(path: Path, data: bytes, label: str) -> None:
    if path.is_symlink():
        raise MeasurementError([f"{label} is a symlink"])
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=".idol-smm-", suffix=".tmp", dir=str(path.parent))
    tmp_path = Path(tmp)
    try:
        write_all(fd, data)
        os.fsync(fd)
        os.close(fd)
        fd = -1
        try:
            os.link(tmp, path)
        except FileExistsError as exc:
            raise MeasurementError([f"refusing to clobber existing {label}"]) from exc
    finally:
        if fd >= 0:
            os.close(fd)
        try:
            tmp_path.unlink()
        except OSError:
            pass


def parse_rate(raw: Any) -> float | None:
    if raw in (None, "", "N/A", "0/0"):
        return None
    text = str(raw)
    try:
        if "/" in text:
            num_s, den_s = text.split("/", 1)
            num = float(num_s)
            den = float(den_s)
            if den == 0 or not math.isfinite(num) or not math.isfinite(den):
                return None
            value = num / den
        else:
            value = float(text)
    except (TypeError, ValueError):
        return None
    if not math.isfinite(value):
        raise MeasurementError(["frame rate is not finite"])
    if value <= 0:
        raise MeasurementError(["frame rate is zero or negative"])
    return value


def probe_video(video: Path) -> dict[str, Any]:
    result = subprocess.run(
        [
            tool_path("ffprobe"),
            "-v",
            "error",
            "-select_streams",
            "v:0",
            "-show_entries",
            "stream=width,height,avg_frame_rate,r_frame_rate,duration",
            "-show_entries",
            "format=duration",
            "-of",
            "json",
            str(video),
        ],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise MeasurementError([f"ffprobe could not decode the source: {(result.stderr or result.stdout).strip()}"])
    payload = json.loads(result.stdout)
    streams = [row for row in (payload.get("streams") or []) if isinstance(row, dict)]
    stream = streams[0] if streams else None
    if stream is None:
        raise MeasurementError(["ffprobe did not expose a video stream"])
    width = int(stream.get("width") or 0)
    height = int(stream.get("height") or 0)
    if width <= 0 or height <= 0:
        raise MeasurementError(["ffprobe width/height is missing or not positive"])
    duration = None
    for raw in (stream.get("duration"), (payload.get("format") or {}).get("duration")):
        if raw in (None, "", "N/A"):
            continue
        value = float(raw)
        if math.isfinite(value) and value > 0:
            duration = value
            break
    avg = stream.get("avg_frame_rate")
    rrate = stream.get("r_frame_rate")
    avg_v = parse_rate(avg)
    r_v = parse_rate(rrate)
    mode = "cfr"
    if avg_v is None or r_v is None or abs(avg_v - r_v) > 0.01:
        mode = "vfr_or_unknown"
    return {
        "width": width,
        "height": height,
        "duration": duration,
        "avg_frame_rate": None if avg in (None, "", "N/A") else str(avg),
        "r_frame_rate": None if rrate in (None, "", "N/A") else str(rrate),
        "mode": mode,
    }


def decode_window(video: Path, start: float, end: float, width: int, height: int) -> tuple[list[dict[str, Any]], int]:
    if end <= start:
        raise MeasurementError(["decode window duration is not positive"])
    frame_nbytes = width * height * 3
    result = subprocess.run(
        [
            tool_path("ffmpeg"),
            "-hide_banner",
            "-nostats",
            "-loglevel",
            "info",
            "-ss",
            f"{start:.6f}",
            "-t",
            f"{end - start:.6f}",
            "-i",
            str(video),
            "-copyts",
            "-avoid_negative_ts",
            "disabled",
            "-vsync",
            "passthrough",
            "-an",
            "-vf",
            (
                f"trim=start={start:.6f}:end={end:.6f},setpts=PTS,"
                f"scale={width}:{height}:flags=fast_bilinear,format=rgb24,showinfo"
            ),
            "-f",
            "rawvideo",
            "pipe:1",
        ],
        check=False,
        capture_output=True,
    )
    if result.returncode != 0:
        detail = result.stderr.decode("utf-8", "replace")[-800:].strip()
        raise MeasurementError([f"ffmpeg bounded decode failed: {detail}"])
    pts_rows: list[tuple[int, float]] = []
    for line in result.stderr.decode("utf-8", "replace").splitlines():
        match = SHOWINFO_RE.search(line)
        if not match:
            continue
        raw_pts = match.group(2)
        if raw_pts.lower() == "nan":
            raise MeasurementError(["ffmpeg showinfo pts_time is NaN; HOLD unknown timing"])
        pts = float(raw_pts)
        if not math.isfinite(pts):
            raise MeasurementError(["ffmpeg showinfo pts_time is not finite; HOLD unknown timing"])
        pts_rows.append((int(match.group(1)), pts))
    raw = result.stdout
    if frame_nbytes <= 0 or len(raw) % frame_nbytes != 0:
        raise MeasurementError(["ffmpeg rawvideo length is not an integer number of analysis frames"])
    count = len(raw) // frame_nbytes
    if count == 0:
        raise MeasurementError(["ffmpeg emitted no frames in the bounded window"])
    if len(pts_rows) != count:
        raise MeasurementError(
            [f"showinfo count {len(pts_rows)} != raw frame count {count}; cannot bind pixels to decoded PTS"]
        )
    if [index for index, _pts in pts_rows] != list(range(count)):
        raise MeasurementError(["showinfo n is not a contiguous same-stream decode index"])
    if pts_rows[0][1] < start - PTS_MATCH_LIMIT:
        raise MeasurementError(["decoded PTS do not track the requested source window; unknown timing HOLD"])
    if pts_rows[-1][1] > end + PTS_MATCH_LIMIT:
        raise MeasurementError(["decoded PTS extend past the bounded trim window"])
    frames = []
    for index, (_n, pts) in enumerate(pts_rows):
        frames.append(
            {
                "decode_frame_index": index,
                "pts_seconds": pts,
                "rgb": raw[index * frame_nbytes : (index + 1) * frame_nbytes],
            }
        )
    return frames, len(raw)


def select_samples(frames: list[dict[str, Any]], sample_times: list[float]) -> list[dict[str, Any]]:
    selected = []
    for order, requested in enumerate(sample_times, start=1):
        chosen = next((frame for frame in frames if frame["pts_seconds"] + 1e-9 >= requested), None)
        if chosen is None:
            raise MeasurementError([f"no same-stream decoded frame at or after {requested}"])
        if chosen["pts_seconds"] - requested > PTS_MATCH_LIMIT:
            raise MeasurementError(
                [f"decoded PTS {chosen['pts_seconds']} is more than {PTS_MATCH_LIMIT}s after requested {requested}"]
            )
        selected.append(
            {
                "order_index": order,
                "requested_timestamp_seconds": requested,
                "decoded_pts_seconds": chosen["pts_seconds"],
                "decode_frame_index": chosen["decode_frame_index"],
                "pixel_sha256": hashlib.sha256(chosen["rgb"]).hexdigest(),
            }
        )
    return selected


def motion_rows(frames: list[dict[str, Any]], width: int, height: int, luma_threshold: float) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    prev_gray = None
    prev_pts = None
    timeline = []
    cuts = []
    for frame in frames:
        rgb = np.frombuffer(frame["rgb"], dtype=np.uint8).reshape(height, width, 3)
        gray = cv2.cvtColor(rgb, cv2.COLOR_RGB2GRAY)
        if prev_gray is None or prev_pts is None:
            luma = 0.0
            magnitude = 0.0
        else:
            luma = float(np.mean(np.abs(gray.astype(np.float64) - prev_gray.astype(np.float64)) / 255.0))
            flow = cv2.calcOpticalFlowFarneback(
                prev_gray,
                gray,
                None,
                FARNEBACK["pyr_scale"],
                FARNEBACK["levels"],
                FARNEBACK["winsize"],
                FARNEBACK["iterations"],
                FARNEBACK["poly_n"],
                FARNEBACK["poly_sigma"],
                FARNEBACK["flags"],
            )
            mag, _ang = cv2.cartToPolar(flow[..., 0], flow[..., 1])
            magnitude = float(np.mean(mag))
            if luma >= luma_threshold:
                cuts.append(
                    {
                        "between_pts_seconds": [prev_pts, frame["pts_seconds"]],
                        "mean_abs_luma_delta": round(luma, 6),
                        "status": "candidate_discontinuity",
                    }
                )
        timeline.append(
            {
                "decode_frame_index": frame["decode_frame_index"],
                "pts_seconds": frame["pts_seconds"],
                "mean_abs_luma_delta": round(luma, 6),
                "mean_optical_flow_magnitude": round(magnitude, 6),
                "camera_subject_ambiguity": AMBIGUITY,
            }
        )
        prev_gray = gray
        prev_pts = frame["pts_seconds"]
    pts = [row["pts_seconds"] for row in timeline]
    if any(not math.isfinite(value) for value in pts) or any(right <= left for left, right in zip(pts, pts[1:])):
        raise MeasurementError(["decoded PTS are missing, not finite, or not strictly increasing; HOLD unknown timing"])
    return timeline, cuts


def parse_sample_times(raw: str) -> list[float]:
    times = []
    for item in raw.split(","):
        item = item.strip()
        if not item:
            continue
        times.append(finite_number(float(item), "sample timestamp", minimum=0.0))
    if len(times) != REQUIRED_SAMPLES:
        raise MeasurementError([f"exactly five Sequence sample timestamps are required; got {len(times)}"])
    if len(set(times)) != len(times):
        raise MeasurementError(["sample timestamps contain duplicates"])
    for index, (current, following) in enumerate(zip(times, times[1:]), start=1):
        if following <= current:
            raise MeasurementError(["sample timestamps must be strictly increasing"])
        if abs((following - current) - STEP_SECONDS) > CADENCE_TOL:
            raise MeasurementError([f"sample timestamps {index}-{index + 1} are not exact one-second cadence"])
    return times


def validate_schema(document: dict[str, Any], schema_path: Path) -> None:
    schema = json.loads(schema_path.read_text(encoding="utf-8"))
    errors = sorted(jsonschema.Draft202012Validator(schema).iter_errors(document), key=lambda err: list(err.path))
    if errors:
        raise MeasurementError([f"measurement schema: {errors[0].message}"])


def bound_fields(
    *,
    input_sha256: str,
    admitted_start: float,
    admitted_end: float,
    sample_times: list[float],
    parameters: dict[str, Any],
    runtime: dict[str, str],
) -> dict[str, Any]:
    return {
        "input_sha256": input_sha256,
        "admitted_start": admitted_start,
        "admitted_end": admitted_end,
        "sample_times": sample_times,
        "parameters": parameters,
        "runtime": runtime,
    }


def bound_fields_from_artifact(artifact: dict[str, Any]) -> dict[str, Any]:
    admitted = artifact.get("admitted_time_range_seconds") or {}
    return bound_fields(
        input_sha256=str((artifact.get("source") or {}).get("sha256") or ""),
        admitted_start=admitted.get("start"),
        admitted_end=admitted.get("end"),
        sample_times=list(artifact.get("sequence_sample_timestamps_seconds") or []),
        parameters=artifact.get("parameters") or {},
        runtime=artifact.get("runtime") or {},
    )


def build_artifact(
    *,
    input_sha256: str,
    admitted_start: float,
    admitted_end: float,
    sample_times: list[float],
    runtime: dict[str, str],
    parameters: dict[str, Any],
    probe: dict[str, Any],
    frames: list[dict[str, Any]],
    bytes_emitted: int,
    window_start: float,
    window_end: float,
    width: int,
    height: int,
    luma_threshold: float,
) -> dict[str, Any]:
    sampled = select_samples(frames, sample_times)
    timeline, cuts = motion_rows(frames, width, height, luma_threshold)
    return {
        "schema_version": CONTRACT,
        "authority": AUTHORITY,
        "source": {"sha256": input_sha256},
        "admitted_time_range_seconds": {"start": admitted_start, "end": admitted_end},
        "sequence_sample_timestamps_seconds": sample_times,
        "runtime": runtime,
        "parameters": parameters,
        "decode_work": {
            "passes": 1,
            "frames_emitted": len(frames),
            "bytes_emitted": bytes_emitted,
            "input_span_seconds": window_end - window_start,
            "window_seconds": {"start": window_start, "end": window_end},
        },
        "timing": {
            "mode": probe["mode"],
            "avg_frame_rate": probe["avg_frame_rate"],
            "r_frame_rate": probe["r_frame_rate"],
            "pts_source": "ffmpeg_showinfo_same_decode_stream",
        },
        "sampled_frames": sampled,
        "motion_timeline": timeline,
        "scene_cut_discontinuities": cuts,
    }


def load_valid_cache(
    cache_path: Path,
    live_fields: dict[str, Any],
    live_key: str,
    schema_path: Path,
) -> dict[str, Any] | None:
    if cache_path.is_symlink():
        raise MeasurementError(["cache artifact is a symlink"])
    if not cache_path.is_file():
        return None
    try:
        envelope = json.loads(cache_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise MeasurementError([f"tampered or unreadable cache envelope: {exc}"]) from exc
    if not isinstance(envelope, dict) or envelope.get("envelope_version") != ENVELOPE:
        raise MeasurementError(["cache envelope version is not the measurement cache envelope"])
    artifact = envelope.get("artifact")
    if not isinstance(artifact, dict):
        raise MeasurementError(["cache envelope is missing the measurement artifact"])
    payload = artifact_bytes(artifact)
    stored_key = value_sha256(bound_fields_from_artifact(artifact))
    live_equal = bound_fields_from_artifact(artifact) == live_fields
    if (
        not live_equal
        or stored_key != live_key
        or envelope.get("cache_key_sha256") != live_key
        or envelope.get("artifact_sha256") != sha256_bytes(payload)
    ):
        raise MeasurementError(["cached payload failed live bound-field equality or artifact SHA integrity"])
    validate_schema(artifact, schema_path)
    return artifact


def distinct_paths(paths: list[tuple[Path, str]]) -> None:
    resolved: dict[str, str] = {}
    for path, label in paths:
        key = str(path)
        if path.exists():
            key = str(path.resolve())
        previous = resolved.get(key)
        if previous:
            raise MeasurementError([f"{label} collides with {previous}"])
        resolved[key] = label


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", required=True, type=Path)
    parser.add_argument("--video", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--cache-dir", type=Path)
    parser.add_argument("--admitted-start", required=True, type=float)
    parser.add_argument("--admitted-end", required=True, type=float)
    parser.add_argument("--sample-times", required=True)
    parser.add_argument("--analysis-width", type=int, default=160)
    parser.add_argument("--analysis-height", type=int, default=90)
    parser.add_argument("--luma-delta-candidate-threshold", type=float, default=0.25)
    parser.add_argument("--window-end-pad-seconds", type=float, default=0.05)
    parser.add_argument("--force-refresh", action="store_true")
    args = parser.parse_args()
    started = time.perf_counter()
    try:
        if args.repo_root.is_symlink():
            raise MeasurementError(["--repo-root is a symlink"])
        repo_root = args.repo_root.resolve(strict=True)
        if not repo_root.is_dir():
            raise MeasurementError(["--repo-root is not a directory"])
        schema_path = contain_existing_file(
            repo_root / "schemas/sequence-motion-machine-measurement.schema.json",
            repo_root,
            "measurement schema",
        )
        video = contain_existing_file(args.video, repo_root, "--video")
        output = contain_new_or_existing_file(args.output, repo_root, "--output")
        cache_raw = args.cache_dir or (output.parent / "_machine-cache")
        cache_dir = contain_new_or_existing_dir(cache_raw, repo_root, "--cache-dir")
        if output == video:
            raise MeasurementError(["--output collides with --video"])
        if cache_dir == video:
            raise MeasurementError(["--cache-dir collides with --video"])
        if schema_path == video or schema_path == output:
            raise MeasurementError(["measurement schema collides with --video or --output"])
        admitted_start = finite_number(args.admitted_start, "--admitted-start", minimum=0.0)
        admitted_end = finite_number(args.admitted_end, "--admitted-end", exclusive_minimum=0.0)
        if admitted_end <= admitted_start:
            raise MeasurementError(["admitted end must be after start"])
        width = int(args.analysis_width)
        height = int(args.analysis_height)
        if width <= 0 or height <= 0:
            raise MeasurementError(["analysis dimensions must be positive"])
        luma_threshold = finite_number(args.luma_delta_candidate_threshold, "luma threshold", exclusive_minimum=0.0)
        pad = finite_number(args.window_end_pad_seconds, "window end pad", exclusive_minimum=0.0)
        if pad > MAX_PAD:
            raise MeasurementError(["window end pad exceeds 1s bounded-window ceiling"])
        sample_times = parse_sample_times(args.sample_times)
        if sample_times[0] < admitted_start - CADENCE_TOL or sample_times[-1] > admitted_end + CADENCE_TOL:
            raise MeasurementError(["sample timestamps are outside the admitted source range"])
        input_sha256 = sha256_file(video)
        probe = probe_video(video)
        if probe["duration"] is not None and sample_times[-1] > probe["duration"] + CADENCE_TOL:
            raise MeasurementError(["sample timestamps exceed probed duration"])
        runtime = {
            "ffmpeg_version": tool_version("ffmpeg"),
            "ffprobe_version": tool_version("ffprobe"),
            "opencv_version": cv2.__version__,
            "numpy_version": np.__version__,
            "script_sha256": sha256_file(Path(__file__).resolve()),
        }
        parameters = {
            "analysis_frame_size": [width, height],
            "luma_delta_candidate_threshold": luma_threshold,
            "window_end_pad_seconds": pad,
            "farneback": dict(FARNEBACK),
        }
        live_fields = bound_fields(
            input_sha256=input_sha256,
            admitted_start=admitted_start,
            admitted_end=admitted_end,
            sample_times=sample_times,
            parameters=parameters,
            runtime=runtime,
        )
        live_key = value_sha256(live_fields)
        cache_dir.mkdir(parents=True, exist_ok=True)
        if cache_dir.is_symlink():
            raise MeasurementError(["--cache-dir is a symlink"])
        cache_path = cache_dir / f"{live_key}.json"
        if cache_path.is_symlink():
            raise MeasurementError(["cache artifact is a symlink"])
        distinct_paths(
            [
                (video, "--video"),
                (schema_path, "measurement schema"),
                (output, "--output"),
                (cache_path, "cache artifact"),
            ]
        )
        artifact = None
        cache_hit = False
        if cache_path.exists() and not args.force_refresh:
            artifact = load_valid_cache(cache_path, live_fields, live_key, schema_path)
            cache_hit = artifact is not None
        if artifact is None:
            window_start = sample_times[0]
            window_end = sample_times[-1] + pad
            frames, emitted = decode_window(video, window_start, window_end, width, height)
            artifact = build_artifact(
                input_sha256=input_sha256,
                admitted_start=admitted_start,
                admitted_end=admitted_end,
                sample_times=sample_times,
                runtime=runtime,
                parameters=parameters,
                probe=probe,
                frames=frames,
                bytes_emitted=emitted,
                window_start=window_start,
                window_end=window_end,
                width=width,
                height=height,
                luma_threshold=luma_threshold,
            )
            validate_schema(artifact, schema_path)
        payload = artifact_bytes(artifact)
        artifact_sha = sha256_bytes(payload)
        envelope = {
            "envelope_version": ENVELOPE,
            "cache_key_sha256": live_key,
            "artifact_sha256": artifact_sha,
            "artifact": artifact,
        }
        envelope_bytes = (json.dumps(envelope, indent=2, ensure_ascii=False, allow_nan=False) + "\n").encode("utf-8")
        if cache_path.exists():
            if cache_path.is_symlink():
                raise MeasurementError(["cache artifact is a symlink"])
            existing_cache = cache_path.read_bytes()
            if existing_cache != envelope_bytes:
                raise MeasurementError(["refusing to overwrite a different cache envelope"])
        else:
            atomic_create(cache_path, envelope_bytes, "cache artifact")
        if output.exists():
            if output.is_symlink():
                raise MeasurementError(["--output is a symlink"])
            if output.is_dir():
                raise MeasurementError(["--output is a directory"])
            if output.read_bytes() != payload:
                raise MeasurementError(["--output already exists with different bytes"])
        else:
            atomic_create(output, payload, "--output")
        elapsed_ms = int(round((time.perf_counter() - started) * 1000))
        json.dump(
            {
                "valid": True,
                "cache_hit": cache_hit,
                "artifact_path": str(output),
                "artifact_sha256": artifact_sha,
                "cache_key_sha256": live_key,
                "elapsed_ms": elapsed_ms,
                "decode_work": artifact["decode_work"],
            },
            sys.stdout,
            indent=2,
            allow_nan=False,
        )
        sys.stdout.write("\n")
    except MeasurementError as exc:
        fail(exc.errors)
    except (OSError, UnicodeError, json.JSONDecodeError, subprocess.CalledProcessError, ValueError) as exc:
        fail([f"measurement HOLD: {exc.__class__.__name__}: {exc}"])


if __name__ == "__main__":
    main()
