#!/usr/bin/env python3
"""Measure an IDOL 04 master without making a creative or Founder verdict.

The report binds the exact master, optional recipe, and selected audio; records
video/color/audio facts; compares frame/delivery expectations; and surfaces
black, silence, freeze, and exact duplicate-frame candidates for human review.
It never normalizes audio and never turns measurements into edit approval.
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
import tempfile
from fractions import Fraction
from pathlib import Path
from typing import Any, Callable

try:
    import jsonschema
    import numpy as np
    import yaml
except ModuleNotFoundError as exc:
    raise SystemExit(
        f"Missing Python dependency '{exc.name}'. "
        "Run this script through scripts/idol-video-python."
    ) from exc

from lib.idol_run_layout import ACTIVE_RUN_ROOT_RE


ROOT = Path(__file__).resolve().parent.parent
SCHEMA_PATH = ROOT / "schemas/edit-delivery-qc.schema.json"
NUMBER = r"(?:[-+]?\d+(?:\.\d+)?|-?inf)"


class UniqueKeyLoader(yaml.SafeLoader):
    pass


def construct_unique_mapping(
    loader: UniqueKeyLoader, node: yaml.MappingNode, deep: bool = False
) -> dict[str, Any]:
    mapping: dict[str, Any] = {}
    for key_node, value_node in node.value:
        key = loader.construct_object(key_node, deep=deep)
        if key in mapping:
            raise yaml.constructor.ConstructorError(
                "while constructing a mapping",
                node.start_mark,
                f"duplicate key: {key!r}",
                key_node.start_mark,
            )
        mapping[key] = loader.construct_object(value_node, deep=deep)
    return mapping


UniqueKeyLoader.add_constructor(
    yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, construct_unique_mapping
)


def load_mapping(path: Path) -> dict[str, Any]:
    payload = yaml.load(path.read_text(encoding="utf-8"), Loader=UniqueKeyLoader) or {}
    if not isinstance(payload, dict):
        raise ValueError(f"expected a mapping: {path}")
    return payload


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def tool_path(name: str) -> str:
    for prefix in ("/opt/homebrew/bin", "/usr/local/bin"):
        candidate = Path(prefix) / name
        if candidate.exists():
            return str(candidate)
    found = shutil.which(name)
    if found:
        return found
    raise ValueError(f"missing required tool: {name}")


def tool_version(name: str) -> str:
    result = subprocess.run(
        [tool_path(name), "-version"],
        check=True,
        capture_output=True,
        text=True,
    )
    return (result.stdout or result.stderr).splitlines()[0].strip()


def run_capture(command: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        check=True,
        capture_output=True,
        text=True,
    )


def ffprobe_document(path: Path) -> dict[str, Any]:
    result = run_capture(
        [
            tool_path("ffprobe"),
            "-v",
            "error",
            "-show_streams",
            "-show_format",
            "-of",
            "json",
            str(path),
        ]
    )
    payload = json.loads(result.stdout)
    if not isinstance(payload, dict):
        raise ValueError(f"ffprobe did not return a mapping: {path}")
    return payload


def first_stream(probe: dict[str, Any], kind: str) -> dict[str, Any] | None:
    for stream in probe.get("streams") or []:
        if not isinstance(stream, dict) or stream.get("codec_type") != kind:
            continue
        if kind == "video" and stream.get("disposition", {}).get("attached_pic") == 1:
            continue
        return stream
    return None


def numeric(value: Any) -> float | None:
    if value in (None, "", "N/A", "inf", "+inf", "-inf"):
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def integer(value: Any) -> int | None:
    number = numeric(value)
    return int(number) if number is not None else None


def value_or_unknown(value: Any) -> Any:
    return "unknown" if value in (None, "", "N/A") else value


def parse_rate(value: Any) -> Fraction | None:
    if value in (None, "", "N/A", "0/0"):
        return None
    try:
        return Fraction(str(value))
    except (ValueError, ZeroDivisionError):
        return None


def format_rate(value: Fraction | None) -> str | None:
    if value is None:
        return None
    return f"{value.numerator}/{value.denominator}"


def duration_seconds(probe: dict[str, Any], stream: dict[str, Any] | None) -> float | None:
    stream_duration = numeric((stream or {}).get("duration"))
    if stream_duration is not None:
        return stream_duration
    return numeric((probe.get("format") or {}).get("duration"))


def rotation_degrees(stream: dict[str, Any]) -> float | None:
    tags = stream.get("tags") or {}
    if isinstance(tags, dict) and numeric(tags.get("rotate")) is not None:
        return numeric(tags.get("rotate"))
    for row in stream.get("side_data_list") or []:
        if isinstance(row, dict) and numeric(row.get("rotation")) is not None:
            return numeric(row.get("rotation"))
    return None


def color_summary(stream: dict[str, Any]) -> dict[str, Any]:
    fields = {
        "color_range": value_or_unknown(stream.get("color_range")),
        "color_space": value_or_unknown(stream.get("color_space")),
        "color_transfer": value_or_unknown(stream.get("color_transfer")),
        "color_primaries": value_or_unknown(stream.get("color_primaries")),
    }
    known = sum(value != "unknown" for value in fields.values())
    status = (
        "tagged_complete"
        if known == 4
        else ("unknown" if known == 0 else "tagged_partial")
    )
    side_data_types = sorted(
        {
            str(row.get("side_data_type"))
            for row in stream.get("side_data_list") or []
            if isinstance(row, dict) and row.get("side_data_type")
        }
    )
    hdr_markers = ("mastering", "content light", "hdr", "dolby vision", "dovi")
    hdr_transfers = {"smpte2084", "arib-std-b67"}
    return {
        **fields,
        "metadata_status": status,
        "side_data_types": side_data_types,
        "hdr_metadata_present": any(
            any(marker in item.lower() for marker in hdr_markers)
            for item in side_data_types
        ),
        "hdr_transfer_candidate": (
            str(fields["color_transfer"]).lower() in hdr_transfers
        ),
        "interpretation_policy": "metadata facts only; tags do not prove a color transform",
    }


def frame_rate_summary(stream: dict[str, Any]) -> dict[str, Any]:
    avg_raw = str(stream.get("avg_frame_rate") or "unknown")
    nominal_raw = str(stream.get("r_frame_rate") or "unknown")
    avg = parse_rate(avg_raw)
    nominal = parse_rate(nominal_raw)
    if avg is not None and nominal is not None:
        vfr_candidate = avg != nominal
        rate_mode = "vfr_candidate" if vfr_candidate else "cfr_candidate"
    else:
        vfr_candidate = None
        rate_mode = "unknown"
    return {
        "avg_frame_rate": avg_raw,
        "r_frame_rate": nominal_raw,
        "observed_fps": format_rate(avg or nominal),
        "time_base": value_or_unknown(stream.get("time_base")),
        "frame_count_declared": integer(stream.get("nb_frames")),
        "rate_mode": rate_mode,
        "vfr_candidate": vfr_candidate,
    }


def video_probe_summary(probe: dict[str, Any], stream: dict[str, Any]) -> dict[str, Any]:
    bit_depth = integer(stream.get("bits_per_raw_sample"))
    if bit_depth is None:
        bit_depth = integer(stream.get("bits_per_sample"))
    return {
        "stream_index": integer(stream.get("index")),
        "duration_seconds": duration_seconds(probe, stream),
        "codec": value_or_unknown(stream.get("codec_name")),
        "profile": value_or_unknown(stream.get("profile")),
        "width": integer(stream.get("width")),
        "height": integer(stream.get("height")),
        "sample_aspect_ratio": value_or_unknown(stream.get("sample_aspect_ratio")),
        "display_aspect_ratio": value_or_unknown(stream.get("display_aspect_ratio")),
        "rotation_degrees": rotation_degrees(stream),
        "pixel_format": value_or_unknown(stream.get("pix_fmt")),
        "declared_bit_depth": bit_depth,
        "field_order": value_or_unknown(stream.get("field_order")),
        "frame_rate": frame_rate_summary(stream),
        "color": color_summary(stream),
    }


def audio_probe_summary(
    probe: dict[str, Any], stream: dict[str, Any] | None
) -> dict[str, Any] | None:
    if stream is None:
        return None
    return {
        "stream_index": integer(stream.get("index")),
        "duration_seconds": duration_seconds(probe, stream),
        "codec": value_or_unknown(stream.get("codec_name")),
        "profile": value_or_unknown(stream.get("profile")),
        "sample_format": value_or_unknown(stream.get("sample_fmt")),
        "sample_rate": integer(stream.get("sample_rate")),
        "channels": integer(stream.get("channels")),
        "channel_layout": value_or_unknown(stream.get("channel_layout")),
        "time_base": value_or_unknown(stream.get("time_base")),
        "start_time_seconds": numeric(stream.get("start_time")),
        "bit_rate": integer(stream.get("bit_rate")),
    }


def parse_ebur128(text: str) -> dict[str, float | None]:
    summary = text[text.rfind("Summary:") :] if "Summary:" in text else text

    def field(pattern: str) -> float | None:
        match = re.search(pattern, summary, flags=re.MULTILINE)
        return numeric(match.group(1)) if match else None

    return {
        "integrated_lufs": field(rf"^\s*I:\s*({NUMBER})\s+LUFS"),
        "integrated_threshold_lufs": field(rf"^\s*Threshold:\s*({NUMBER})\s+LUFS"),
        "loudness_range_lu": field(rf"^\s*LRA:\s*({NUMBER})\s+LU"),
        "lra_low_lufs": field(rf"^\s*LRA low:\s*({NUMBER})\s+LUFS"),
        "lra_high_lufs": field(rf"^\s*LRA high:\s*({NUMBER})\s+LUFS"),
        "true_peak_dbtp": field(rf"^\s*Peak:\s*({NUMBER})\s+dBFS"),
    }


def loudness_measurement(path: Path) -> dict[str, Any]:
    result = run_capture(
        [
            tool_path("ffmpeg"),
            "-hide_banner",
            "-nostats",
            "-i",
            str(path),
            "-map",
            "0:a:0",
            "-filter:a",
            "ebur128=peak=true:framelog=quiet",
            "-f",
            "null",
            "-",
        ]
    )
    return parse_ebur128(result.stderr)


def decoded_sample_measurement(path: Path, clip_threshold: float) -> dict[str, Any]:
    command = [
        tool_path("ffmpeg"),
        "-v",
        "error",
        "-i",
        str(path),
        "-map",
        "0:a:0",
        "-vn",
        "-acodec",
        "pcm_f32le",
        "-f",
        "f32le",
        "-",
    ]
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if process.stdout is None or process.stderr is None:
        raise RuntimeError("could not open FFmpeg PCM pipes")
    peak = 0.0
    clipped = 0
    total = 0
    remainder = b""
    while True:
        chunk = process.stdout.read(1024 * 1024)
        if not chunk:
            break
        buffer = remainder + chunk
        usable = len(buffer) - (len(buffer) % 4)
        if usable:
            samples = np.frombuffer(buffer[:usable], dtype="<f4")
            absolute = np.abs(samples)
            if absolute.size:
                peak = max(peak, float(np.max(absolute)))
                clipped += int(np.count_nonzero(absolute >= clip_threshold))
                total += int(absolute.size)
        remainder = buffer[usable:]
    stderr = process.stderr.read().decode("utf-8", errors="replace")
    return_code = process.wait()
    if return_code != 0:
        raise RuntimeError(f"FFmpeg PCM decode failed: {stderr.strip()}")
    peak_dbfs = 20.0 * math.log10(peak) if peak > 0 else None
    return {
        "sample_peak_amplitude": round(peak, 9),
        "sample_peak_dbfs": round(peak_dbfs, 6) if peak_dbfs is not None else None,
        "clip_amplitude_threshold": clip_threshold,
        "samples_at_or_above_threshold": clipped,
        "decoded_sample_value_count": total,
        "clipping_interpretation": (
            "decoded sample threshold count; lossy codec overs and true-peak risk remain separate"
        ),
    }


def silence_measurement(
    path: Path, duration: float | None, noise_db: float, minimum_duration: float
) -> dict[str, Any]:
    result = run_capture(
        [
            tool_path("ffmpeg"),
            "-hide_banner",
            "-nostats",
            "-i",
            str(path),
            "-map",
            "0:a:0",
            "-filter:a",
            f"silencedetect=noise={noise_db}dB:d={minimum_duration}",
            "-f",
            "null",
            "-",
        ]
    )
    events: list[tuple[str, float, float | None]] = []
    for line in result.stderr.splitlines():
        start = re.search(r"silence_start:\s*([-+\d.]+)", line)
        if start:
            events.append(("start", float(start.group(1)), None))
        end = re.search(
            r"silence_end:\s*([-+\d.]+)\s*\|\s*silence_duration:\s*([-+\d.]+)",
            line,
        )
        if end:
            events.append(("end", float(end.group(1)), float(end.group(2))))
    intervals: list[dict[str, float]] = []
    pending_start: float | None = None
    for kind, value, measured_duration in events:
        if kind == "start":
            pending_start = value
        elif pending_start is not None:
            intervals.append(
                {
                    "start_seconds": round(pending_start, 6),
                    "end_seconds": round(value, 6),
                    "duration_seconds": round(
                        measured_duration
                        if measured_duration is not None
                        else value - pending_start,
                        6,
                    ),
                }
            )
            pending_start = None
    if pending_start is not None and duration is not None and duration >= pending_start:
        intervals.append(
            {
                "start_seconds": round(pending_start, 6),
                "end_seconds": round(duration, 6),
                "duration_seconds": round(duration - pending_start, 6),
            }
        )
    lead = 0.0
    trail = 0.0
    if intervals and intervals[0]["start_seconds"] <= 0.001:
        lead = intervals[0]["duration_seconds"]
    if intervals and duration is not None and intervals[-1]["end_seconds"] >= duration - 0.02:
        trail = intervals[-1]["duration_seconds"]
    return {
        "noise_threshold_db": noise_db,
        "minimum_duration_seconds": minimum_duration,
        "intervals": intervals,
        "lead_silence_seconds": round(lead, 6),
        "trail_silence_seconds": round(trail, 6),
    }


def audio_measurement(
    path: Path,
    probe_summary: dict[str, Any],
    clip_threshold: float,
    silence_noise_db: float,
    silence_minimum: float,
) -> dict[str, Any]:
    return {
        "loudness": loudness_measurement(path),
        "decoded_samples": decoded_sample_measurement(path, clip_threshold),
        "silence": silence_measurement(
            path,
            numeric(probe_summary.get("duration_seconds")),
            silence_noise_db,
            silence_minimum,
        ),
    }


def blackdetect_measurement(
    path: Path, minimum_duration: float, pixel_threshold: float, picture_ratio: float
) -> dict[str, Any]:
    result = run_capture(
        [
            tool_path("ffmpeg"),
            "-hide_banner",
            "-nostats",
            "-i",
            str(path),
            "-an",
            "-vf",
            f"blackdetect=d={minimum_duration}:pix_th={pixel_threshold}:pic_th={picture_ratio}",
            "-f",
            "null",
            "-",
        ]
    )
    intervals = []
    pattern = re.compile(
        r"black_start:([-+\d.]+)\s+black_end:([-+\d.]+)\s+black_duration:([-+\d.]+)"
    )
    for match in pattern.finditer(result.stderr):
        intervals.append(
            {
                "start_seconds": round(float(match.group(1)), 6),
                "end_seconds": round(float(match.group(2)), 6),
                "duration_seconds": round(float(match.group(3)), 6),
            }
        )
    return {
        "minimum_duration_seconds": minimum_duration,
        "pixel_threshold": pixel_threshold,
        "picture_black_ratio": picture_ratio,
        "intervals": intervals,
        "interpretation": "candidate intervals only; intentional void frames require edit review",
    }


def freezedetect_measurement(
    path: Path, noise: float, minimum_duration: float
) -> dict[str, Any]:
    result = run_capture(
        [
            tool_path("ffmpeg"),
            "-hide_banner",
            "-nostats",
            "-i",
            str(path),
            "-an",
            "-vf",
            f"freezedetect=n={noise}:d={minimum_duration}",
            "-f",
            "null",
            "-",
        ]
    )
    starts = [
        float(value)
        for value in re.findall(r"lavfi\.freezedetect\.freeze_start:\s*([-+\d.]+)", result.stderr)
    ]
    ends = [
        float(value)
        for value in re.findall(r"lavfi\.freezedetect\.freeze_end:\s*([-+\d.]+)", result.stderr)
    ]
    durations = [
        float(value)
        for value in re.findall(
            r"lavfi\.freezedetect\.freeze_duration:\s*([-+\d.]+)",
            result.stderr,
        )
    ]
    intervals = []
    for index, start in enumerate(starts):
        end = ends[index] if index < len(ends) else None
        measured = durations[index] if index < len(durations) else None
        intervals.append(
            {
                "start_seconds": round(start, 6),
                "end_seconds": round(end, 6) if end is not None else None,
                "duration_seconds": round(measured, 6) if measured is not None else None,
            }
        )
    return {
        "noise_tolerance": noise,
        "minimum_duration_seconds": minimum_duration,
        "intervals": intervals,
        "interpretation": (
            "freeze candidates only; intentional holds and retime cadence require "
            "playback review"
        ),
    }


def frame_hash_cadence(path: Path) -> dict[str, Any]:
    result = run_capture(
        [
            tool_path("ffmpeg"),
            "-v",
            "error",
            "-i",
            str(path),
            "-map",
            "0:v:0",
            "-an",
            "-f",
            "framehash",
            "-hash",
            "sha256",
            "-",
        ]
    )
    hashes = []
    for line in result.stdout.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        fields = [field.strip() for field in stripped.split(",")]
        if len(fields) >= 6:
            hashes.append(fields[-1])
    adjacent_pairs = 0
    runs: list[dict[str, int]] = []
    run_start: int | None = None
    for index, digest in enumerate(hashes):
        if index > 0 and digest == hashes[index - 1]:
            adjacent_pairs += 1
            if run_start is None:
                run_start = index - 1
        elif run_start is not None:
            runs.append(
                {
                    "start_frame": run_start,
                    "end_frame_exclusive": index,
                    "frame_count": index - run_start,
                }
            )
            run_start = None
    if run_start is not None:
        runs.append(
            {
                "start_frame": run_start,
                "end_frame_exclusive": len(hashes),
                "frame_count": len(hashes) - run_start,
            }
        )
    denominator = max(1, len(hashes) - 1)
    return {
        "status": "measured",
        "frame_count": len(hashes),
        "adjacent_exact_duplicate_pairs": adjacent_pairs,
        "adjacent_exact_duplicate_pair_ratio": round(adjacent_pairs / denominator, 9),
        "exact_duplicate_runs": runs,
        "maximum_exact_duplicate_run_frames": max(
            (row["frame_count"] for row in runs), default=0
        ),
        "interpretation": (
            "decoded-frame identity candidates only; repeats may be intentional holds, "
            "and non-identical cadence judder still needs playback review"
        ),
    }


def infer_run_root(path: Path) -> Path | None:
    for parent in path.parents:
        parts = parent.parts
        runs_indices = [index for index, part in enumerate(parts) if part == "runs"]
        if not runs_indices:
            continue
        relative = "/".join(parts[runs_indices[-1] :])
        if ACTIVE_RUN_ROOT_RE.fullmatch(relative) or relative == "runs/2026-07-29/0729_ONE_MOVE":
            return parent
    return None


def resolve_recipe_path(value: Any, recipe_path: Path, run_root: Path | None) -> Path:
    raw = Path(str(value))
    if raw.is_absolute():
        return raw.resolve()
    if raw.parts and raw.parts[0] == "runs":
        return (ROOT / raw).resolve()
    if run_root is not None:
        return (run_root / raw).resolve()
    return (recipe_path.parent / raw).resolve()


def recipe_expectations(recipe_path: Path) -> tuple[dict[str, Any], Path | None]:
    payload = load_mapping(recipe_path)
    run_root = infer_run_root(recipe_path)
    version = str(payload.get("schema_version") or "legacy")
    result: dict[str, Any] = {
        "schema_version": version,
        "expected_program_frames": None,
        "expected_duration_seconds": None,
        "expected_fps": None,
        "render_spec": None,
        "delivery_color": None,
        "mezzanine": None,
        "selected_audio_path": None,
        "selected_audio_sha256": None,
        "audio_qc_targets": {},
        "retimed_segments": [],
    }
    timeline = payload.get("timeline") or []
    if version == "idol_edit_recipe.v3":
        fps = Fraction(
            int(payload["timebase"]["fps"]["numerator"]),
            int(payload["timebase"]["fps"]["denominator"]),
        )
        frames = int(timeline[-1]["output_out_frame"]) if timeline else 0
        result.update(
            {
                "expected_program_frames": frames,
                "expected_duration_seconds": float(Fraction(frames, 1) / fps),
                "expected_fps": format_rate(fps),
                "render_spec": payload.get("render_spec"),
                "delivery_color": payload.get("color_pipeline", {}).get("delivery"),
                "mezzanine": payload.get("delivery_policy", {}).get("mezzanine"),
                "selected_audio_path": resolve_recipe_path(
                    payload["audio_program"]["path"], recipe_path, run_root
                ),
                "selected_audio_sha256": payload["audio_program"]["sha256"],
                "audio_qc_targets": payload.get("delivery_policy", {}).get(
                    "audio_qc_targets", {}
                ),
                "retimed_segments": [
                    {
                        "segment_id": row.get("segment_id"),
                        "slot": row.get("slot"),
                        "speed_factor": row.get("retime", {}).get("speed_factor"),
                        "cadence_method": row.get("retime", {}).get("cadence_method"),
                    }
                    for row in timeline
                    if row.get("retime", {}).get("mode") != "constant"
                    or not math.isclose(
                        float(row.get("retime", {}).get("speed_factor", 1.0)),
                        1.0,
                        rel_tol=1e-6,
                        abs_tol=1e-6,
                    )
                ],
            }
        )
    else:
        if timeline:
            result["expected_duration_seconds"] = numeric(timeline[-1].get("output_out"))
        audio_value = payload.get("audio_path")
        if audio_value:
            result["selected_audio_path"] = resolve_recipe_path(
                audio_value, recipe_path, run_root
            )
        result["retimed_segments"] = [
            {
                "segment_id": row.get("segment_id") or row.get("slot"),
                "slot": row.get("slot"),
                "speed_factor": (
                    (float(row["source_out"]) - float(row["source_in"]))
                    / float(row["output_duration"])
                ),
                "cadence_method": "legacy_unspecified",
            }
            for row in timeline
            if all(key in row for key in ("source_in", "source_out", "output_duration"))
            and not math.isclose(
                (float(row["source_out"]) - float(row["source_in"]))
                / float(row["output_duration"]),
                1.0,
                rel_tol=1e-6,
                abs_tol=1e-6,
            )
        ]
    return result, run_root


def aspect_ratio_normalized(value: Any) -> str | None:
    if value in (None, "", "unknown", "N/A"):
        return None
    return str(value).replace(":", "/")


def compare_program(
    video: dict[str, Any],
    cadence: dict[str, Any],
    expectations: dict[str, Any],
    audio: dict[str, Any] | None = None,
    master_path: Path | None = None,
) -> dict[str, Any]:
    observed_rate = parse_rate(video.get("frame_rate", {}).get("observed_fps"))
    expected_rate = parse_rate(expectations.get("expected_fps"))
    observed_frames = cadence.get("frame_count")
    if not observed_frames:
        observed_frames = video.get("frame_rate", {}).get("frame_count_declared")
    observed_duration = numeric(video.get("duration_seconds"))
    expected_duration = numeric(expectations.get("expected_duration_seconds"))
    delta_seconds = (
        observed_duration - expected_duration
        if observed_duration is not None and expected_duration is not None
        else None
    )
    delta_frames = (
        delta_seconds * float(expected_rate or observed_rate)
        if delta_seconds is not None and (expected_rate or observed_rate) is not None
        else None
    )
    render_spec = expectations.get("render_spec") or {}
    expected_color = expectations.get("delivery_color") or {}
    observed_color = video.get("color") or {}
    mezzanine = expectations.get("mezzanine") or {}
    expected_video_codec = str(mezzanine.get("video_codec") or "").lower() or None
    expected_audio_codec = str(mezzanine.get("audio_codec") or "").lower() or None
    expected_video_probe_codec = {
        "libx264": "h264",
        "h264": "h264",
        "prores_ks": "prores",
        "prores": "prores",
    }.get(expected_video_codec, expected_video_codec)
    observed_video_codec = str(video.get("codec") or "").lower() or None
    observed_audio_codec = str((audio or {}).get("codec") or "").lower() or None
    observed_container = (
        master_path.suffix.lower().lstrip(".") if master_path is not None else None
    )
    return {
        "recipe_schema_version": expectations.get("schema_version"),
        "expected_program_frames": expectations.get("expected_program_frames"),
        "observed_program_frames": observed_frames,
        "program_frame_count_matches": (
            observed_frames == expectations.get("expected_program_frames")
            if observed_frames is not None
            and expectations.get("expected_program_frames") is not None
            else None
        ),
        "expected_duration_seconds": expected_duration,
        "observed_duration_seconds": observed_duration,
        "duration_delta_seconds": round(delta_seconds, 9) if delta_seconds is not None else None,
        "duration_delta_frames": round(delta_frames, 6) if delta_frames is not None else None,
        "expected_fps": format_rate(expected_rate),
        "observed_fps": format_rate(observed_rate),
        "fps_matches": observed_rate == expected_rate if observed_rate and expected_rate else None,
        "geometry": {
            "expected_width": render_spec.get("width"),
            "observed_width": video.get("width"),
            "width_matches": (
                video.get("width") == render_spec.get("width")
                if render_spec.get("width") is not None
                else None
            ),
            "expected_height": render_spec.get("height"),
            "observed_height": video.get("height"),
            "height_matches": (
                video.get("height") == render_spec.get("height")
                if render_spec.get("height") is not None
                else None
            ),
            "expected_sample_aspect_ratio": aspect_ratio_normalized(
                render_spec.get("sample_aspect_ratio")
            ),
            "observed_sample_aspect_ratio": aspect_ratio_normalized(
                video.get("sample_aspect_ratio")
            ),
            "sample_aspect_ratio_matches": (
                aspect_ratio_normalized(render_spec.get("sample_aspect_ratio"))
                == aspect_ratio_normalized(video.get("sample_aspect_ratio"))
                if render_spec.get("sample_aspect_ratio") is not None
                else None
            ),
            "expected_pixel_format": render_spec.get("pixel_format"),
            "observed_pixel_format": video.get("pixel_format"),
            "pixel_format_matches": (
                render_spec.get("pixel_format") == video.get("pixel_format")
                if render_spec.get("pixel_format") is not None
                else None
            ),
        },
        "color_metadata": {
            key: {
                "expected": expected_color.get(key),
                "observed": observed_color.get(key),
                "matches": (
                    expected_color.get(key) == observed_color.get(key)
                    if expected_color.get(key) is not None
                    and observed_color.get(key) not in (None, "unknown")
                    else None
                ),
            }
            for key in ("color_range", "color_space", "color_transfer", "color_primaries")
        },
        "delivery_encoding": {
            "expected_container": mezzanine.get("container"),
            "observed_container_from_extension": observed_container,
            "container_matches": (
                str(mezzanine.get("container")).lower() == observed_container
                if mezzanine.get("container") and observed_container
                else None
            ),
            "expected_video_codec": expected_video_codec,
            "observed_video_codec": observed_video_codec,
            "video_codec_matches": (
                expected_video_probe_codec == observed_video_codec
                if expected_video_probe_codec and observed_video_codec
                else None
            ),
            "expected_audio_codec": expected_audio_codec,
            "observed_audio_codec": observed_audio_codec,
            "audio_codec_matches": (
                expected_audio_codec == observed_audio_codec
                if expected_audio_codec and observed_audio_codec
                else None
            ),
        },
        "comparison_policy": (
            "mechanical comparison only; mismatches do not make a creative verdict"
        ),
    }


def audio_delivery_delta(
    master_probe: dict[str, Any] | None,
    selected_probe: dict[str, Any] | None,
    master_measurement: dict[str, Any] | None,
    selected_measurement: dict[str, Any] | None,
    fps: Fraction | None,
) -> dict[str, Any]:
    if not master_probe or not selected_probe:
        return {"status": "comparison_unavailable"}
    duration_delta = (
        numeric(master_probe.get("duration_seconds"))
        - numeric(selected_probe.get("duration_seconds"))
        if numeric(master_probe.get("duration_seconds")) is not None
        and numeric(selected_probe.get("duration_seconds")) is not None
        else None
    )
    master_loudness = (master_measurement or {}).get("loudness") or {}
    selected_loudness = (selected_measurement or {}).get("loudness") or {}

    def delta(field: str) -> float | None:
        left = numeric(master_loudness.get(field))
        right = numeric(selected_loudness.get(field))
        return round(left - right, 6) if left is not None and right is not None else None

    return {
        "status": "measured",
        "duration_delta_seconds": round(duration_delta, 9) if duration_delta is not None else None,
        "duration_delta_frames": (
            round(duration_delta * float(fps), 6)
            if duration_delta is not None and fps is not None
            else None
        ),
        "sample_rate_matches": master_probe.get("sample_rate") == selected_probe.get("sample_rate"),
        "channel_layout_matches": master_probe.get("channel_layout")
        == selected_probe.get("channel_layout"),
        "integrated_lufs_delta": delta("integrated_lufs"),
        "loudness_range_lu_delta": delta("loudness_range_lu"),
        "true_peak_dbtp_delta": delta("true_peak_dbtp"),
        "interpretation": "delivery comparison only; lossy encode differences require listening",
    }


def target_comparison(
    measurement: dict[str, Any] | None, expectations: dict[str, Any]
) -> dict[str, Any]:
    targets = expectations.get("audio_qc_targets") or {}
    loudness = (measurement or {}).get("loudness") or {}
    measured_i = numeric(loudness.get("integrated_lufs"))
    measured_tp = numeric(loudness.get("true_peak_dbtp"))
    target_i = numeric(targets.get("integrated_lufs_target"))
    ceiling = numeric(targets.get("true_peak_ceiling_dbtp"))
    return {
        "normalization_policy": targets.get(
            "normalization_policy", "analysis_only_no_auto_normalize"
        ),
        "integrated_lufs_target": target_i,
        "measured_integrated_lufs": measured_i,
        "integrated_lufs_delta": (
            round(measured_i - target_i, 6)
            if measured_i is not None and target_i is not None
            else None
        ),
        "true_peak_ceiling_dbtp": ceiling,
        "measured_true_peak_dbtp": measured_tp,
        "true_peak_within_ceiling": (
            measured_tp <= ceiling
            if measured_tp is not None and ceiling is not None
            else None
        ),
        "verdict_policy": "report target deltas only; do not normalize or infer Founder approval",
    }


def safe_measurement(
    label: str,
    function: Callable[[], dict[str, Any]],
    issues: list[str],
) -> dict[str, Any] | None:
    try:
        return function()
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as exc:
        issues.append(f"{label} failed: {exc}")
        return None


def write_report(path: Path, payload: dict[str, Any]) -> None:
    schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
    jsonschema.Draft202012Validator(schema).validate(payload)
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.suffix.lower() == ".json":
        serialized = json.dumps(payload, ensure_ascii=False, indent=2) + "\n"
    else:
        serialized = yaml.safe_dump(payload, allow_unicode=True, sort_keys=False)
    descriptor, temporary = tempfile.mkstemp(
        prefix=f".{path.name}.", suffix=".tmp", dir=path.parent
    )
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            handle.write(serialized)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
    except Exception:
        Path(temporary).unlink(missing_ok=True)
        raise


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Measure IDOL 04 master delivery without changing or approving it."
    )
    parser.add_argument("--video", type=Path, required=True)
    parser.add_argument("--recipe", type=Path)
    parser.add_argument("--selected-audio", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--black-min-duration", type=float, default=0.04)
    parser.add_argument("--black-pixel-threshold", type=float, default=0.10)
    parser.add_argument("--black-picture-ratio", type=float, default=0.98)
    parser.add_argument("--silence-noise-db", type=float, default=-60.0)
    parser.add_argument("--silence-min-duration", type=float, default=0.10)
    parser.add_argument("--freeze-noise", type=float, default=0.001)
    parser.add_argument("--freeze-min-duration", type=float, default=0.50)
    parser.add_argument("--clip-amplitude-threshold", type=float, default=0.999999)
    parser.add_argument("--skip-frame-hash", action="store_true")
    args = parser.parse_args()

    if not args.video.is_file():
        raise SystemExit(f"master video is not readable: {args.video}")
    if args.recipe and not args.recipe.is_file():
        raise SystemExit(f"recipe is not readable: {args.recipe}")
    if not 0 < args.clip_amplitude_threshold <= 1.5:
        parser.error("--clip-amplitude-threshold must be in (0, 1.5]")
    for label, value in (
        ("--black-pixel-threshold", args.black_pixel_threshold),
        ("--black-picture-ratio", args.black_picture_ratio),
        ("--freeze-noise", args.freeze_noise),
    ):
        if not 0 <= value <= 1:
            parser.error(f"{label} must be in [0, 1]")
    for label, value in (
        ("--black-min-duration", args.black_min_duration),
        ("--silence-min-duration", args.silence_min_duration),
        ("--freeze-min-duration", args.freeze_min_duration),
    ):
        if value <= 0:
            parser.error(f"{label} must be positive")

    issues: list[str] = []
    master_probe_document = ffprobe_document(args.video)
    master_video_stream = first_stream(master_probe_document, "video")
    if master_video_stream is None:
        raise SystemExit("master has no non-attached video stream")
    master_audio_stream = first_stream(master_probe_document, "audio")
    video_probe = video_probe_summary(master_probe_document, master_video_stream)
    master_audio_probe = audio_probe_summary(master_probe_document, master_audio_stream)
    if master_audio_probe is None:
        issues.append("master has no audio stream")

    expectations: dict[str, Any] = {
        "schema_version": None,
        "expected_program_frames": None,
        "expected_duration_seconds": None,
        "expected_fps": None,
        "render_spec": None,
        "delivery_color": None,
        "mezzanine": None,
        "selected_audio_path": None,
        "selected_audio_sha256": None,
        "audio_qc_targets": {},
        "retimed_segments": [],
    }
    recipe_binding = None
    if args.recipe:
        expectations, _ = recipe_expectations(args.recipe.resolve())
        recipe_binding = {
            "path": str(args.recipe),
            "sha256": sha256_file(args.recipe),
        }

    selected_audio_path = args.selected_audio
    if selected_audio_path is None and expectations.get("selected_audio_path"):
        selected_audio_path = Path(expectations["selected_audio_path"])
    selected_audio_binding = None
    selected_probe_document = None
    selected_audio_probe = None
    if selected_audio_path is not None:
        if not selected_audio_path.is_file():
            issues.append(f"selected audio is not readable: {selected_audio_path}")
        else:
            selected_digest = sha256_file(selected_audio_path)
            selected_audio_binding = {
                "path": str(selected_audio_path),
                "sha256": selected_digest,
            }
            expected_digest = expectations.get("selected_audio_sha256")
            if expected_digest and selected_digest != expected_digest:
                issues.append("selected audio SHA-256 differs from recipe audio_program")
            selected_probe_document = ffprobe_document(selected_audio_path)
            selected_audio_probe = audio_probe_summary(
                selected_probe_document, first_stream(selected_probe_document, "audio")
            )
            if selected_audio_probe is None:
                issues.append("selected audio file has no audio stream")

    master_audio_measurement = None
    if master_audio_probe is not None:
        master_audio_measurement = safe_measurement(
            "master audio measurement",
            lambda: audio_measurement(
                args.video,
                master_audio_probe,
                args.clip_amplitude_threshold,
                args.silence_noise_db,
                args.silence_min_duration,
            ),
            issues,
        )
    selected_audio_measurement = None
    if selected_audio_probe is not None and selected_audio_path is not None:
        selected_audio_measurement = safe_measurement(
            "selected audio measurement",
            lambda: audio_measurement(
                selected_audio_path,
                selected_audio_probe,
                args.clip_amplitude_threshold,
                args.silence_noise_db,
                args.silence_min_duration,
            ),
            issues,
        )

    black = safe_measurement(
        "blackdetect",
        lambda: blackdetect_measurement(
            args.video,
            args.black_min_duration,
            args.black_pixel_threshold,
            args.black_picture_ratio,
        ),
        issues,
    ) or {"status": "measurement_failed", "intervals": []}
    freeze = safe_measurement(
        "freezedetect",
        lambda: freezedetect_measurement(
            args.video, args.freeze_noise, args.freeze_min_duration
        ),
        issues,
    ) or {"status": "measurement_failed", "intervals": []}
    if args.skip_frame_hash:
        cadence = {
            "status": "skipped_by_operator",
            "frame_count": video_probe.get("frame_rate", {}).get("frame_count_declared"),
            "interpretation": "exact duplicate-frame cadence was not measured",
        }
    else:
        cadence = safe_measurement(
            "frame hash cadence",
            lambda: frame_hash_cadence(args.video),
            issues,
        ) or {"status": "measurement_failed", "frame_count": None}

    expected_fps = parse_rate(expectations.get("expected_fps"))
    observed_fps = parse_rate(video_probe.get("frame_rate", {}).get("observed_fps"))
    report = {
        "schema_version": "idol_edit_delivery_qc.v1",
        "status": "measurement_incomplete" if issues else "measurement_complete",
        "measurement_only": True,
        "normalization_policy": "analysis_only_no_auto_normalize",
        "human_playback_review_required": True,
        "source_bindings": {
            "master_video": {
                "path": str(args.video),
                "sha256": sha256_file(args.video),
            },
            "recipe": recipe_binding,
            "selected_audio": selected_audio_binding,
        },
        "tooling": {
            "script": {
                "path": str(Path(__file__).resolve()),
                "sha256": sha256_file(Path(__file__).resolve()),
            },
            "report_schema": {
                "path": str(SCHEMA_PATH),
                "sha256": sha256_file(SCHEMA_PATH),
            },
            "ffmpeg": tool_version("ffmpeg"),
            "ffprobe": tool_version("ffprobe"),
            "settings": {
                "black_min_duration_seconds": args.black_min_duration,
                "black_pixel_threshold": args.black_pixel_threshold,
                "black_picture_ratio": args.black_picture_ratio,
                "silence_noise_db": args.silence_noise_db,
                "silence_min_duration_seconds": args.silence_min_duration,
                "freeze_noise_tolerance": args.freeze_noise,
                "freeze_min_duration_seconds": args.freeze_min_duration,
                "clip_amplitude_threshold": args.clip_amplitude_threshold,
                "frame_hash_algorithm": "sha256" if not args.skip_frame_hash else None,
            },
        },
        "video_probe": video_probe,
        "master_audio_probe": master_audio_probe,
        "selected_audio_probe": selected_audio_probe,
        "program_comparison": compare_program(
            video_probe,
            cadence,
            expectations,
            master_audio_probe,
            args.video,
        ),
        "audio_measurements": {
            "master": master_audio_measurement,
            "selected_audio": selected_audio_measurement,
            "delivery_delta": audio_delivery_delta(
                master_audio_probe,
                selected_audio_probe,
                master_audio_measurement,
                selected_audio_measurement,
                expected_fps or observed_fps,
            ),
        },
        "video_measurements": {
            "blackdetect": black,
            "freezedetect": freeze,
            "frame_hash_cadence": cadence,
        },
        "retime_cadence": {
            "recipe_retimed_segments": expectations.get("retimed_segments") or [],
            "exact_duplicate_candidates": cadence,
            "freeze_candidates": freeze.get("intervals", []),
            "automatic_interpretation": "candidate_only",
            "human_review_surfaces": [
                "body_mechanics",
                "face_and_gaze_speed",
                "hands_feet_and_garment_motion",
                "camera_judder",
            ],
        },
        "target_comparison": target_comparison(
            master_audio_measurement, expectations
        ),
        "issues": issues,
        "manual_review_required": [
            "identity_body_hand_foot_preservation",
            "retime_body_mechanics_and_camera_judder",
            "source_family_and_actual_color_transform",
            "intentional_vs_accidental_black_freeze_and_silence",
            "selected_audio_playback_sync_and_encoder_delay",
        ],
    }
    write_report(args.output, report)
    print(args.output)
    print(f"status={report['status']}")
    print(f"issues={len(issues)}")


if __name__ == "__main__":
    main()
