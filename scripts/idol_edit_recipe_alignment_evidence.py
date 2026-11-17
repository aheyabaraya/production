#!/usr/bin/env python3
"""Create source-first alignment evidence for an IDOL edit recipe.

This helper is evidence-only. It maps selected-audio target markers from a
marker decision table back into the original source clips, then compares those
target source times with local optical-flow peaks and the selected audio onset
grid.
"""

from __future__ import annotations

import argparse
import csv
import math
from pathlib import Path

try:
    import cv2
    import librosa
    import numpy as np
    import yaml
except ModuleNotFoundError as exc:
    raise SystemExit(
        f"Missing Python dependency '{exc.name}'. Run this script through scripts/idol-video-python."
    ) from exc


def load_yaml(path: Path) -> dict:
    return yaml.safe_load(path.read_text(encoding="utf-8")) or {}


def rel(path: Path) -> str:
    return path.as_posix()


def source_path(run_root: Path, source: str) -> Path:
    if source.startswith("generations/video/raw/"):
        return run_root / source
    return run_root / "generations/video/raw" / source


def source_to_motion_csv(run_root: Path, source: str) -> Path:
    prefix = "generations/video/raw/"
    source_rel = source.removeprefix(prefix) if source.startswith(prefix) else source
    return run_root / "generations/video/qc/sync-workbench-v1/motion" / f"{source_rel}.csv"


def read_motion_csv(path: Path, source_in: float, source_out: float) -> list[dict]:
    if not path.exists():
        return []
    rows: list[dict] = []
    with path.open(newline="", encoding="utf-8") as fh:
        reader = csv.DictReader(fh)
        for row in reader:
            try:
                time_seconds = float(row["time_seconds"])
                motion_score = float(row["motion_score"])
            except (KeyError, TypeError, ValueError):
                continue
            if source_in <= time_seconds <= source_out:
                rows.append({"time_seconds": time_seconds, "motion_score": motion_score})
    return rows


def compute_motion_rows(video_path: Path, source_in: float, source_out: float, sample_fps: float) -> list[dict]:
    if not video_path.exists():
        return []
    cap = cv2.VideoCapture(str(video_path))
    if not cap.isOpened():
        return []
    native_fps = cap.get(cv2.CAP_PROP_FPS) or 24.0
    start_frame = max(0, int(math.floor(source_in * native_fps)))
    end_frame = max(start_frame, int(math.ceil(source_out * native_fps)))
    step = max(1, int(round(native_fps / sample_fps)))
    cap.set(cv2.CAP_PROP_POS_FRAMES, start_frame)
    rows: list[dict] = []
    prev_gray = None
    frame_idx = start_frame - 1
    while frame_idx < end_frame:
        ok, frame = cap.read()
        if not ok:
            break
        frame_idx += 1
        if frame_idx % step != 0:
            continue
        time_seconds = frame_idx / native_fps
        if time_seconds < source_in or time_seconds > source_out:
            continue
        small = cv2.resize(frame, (160, 90))
        gray = cv2.cvtColor(small, cv2.COLOR_BGR2GRAY)
        if prev_gray is None:
            score = 0.0
        else:
            flow = cv2.calcOpticalFlowFarneback(prev_gray, gray, None, 0.5, 3, 15, 3, 5, 1.2, 0)
            mag, _ = cv2.cartToPolar(flow[..., 0], flow[..., 1])
            score = float(np.mean(mag))
        rows.append({"time_seconds": round(time_seconds, 4), "motion_score": round(score, 6)})
        prev_gray = gray
    cap.release()
    return rows


def audio_markers(audio_path: Path) -> dict:
    y, sr = librosa.load(audio_path, sr=None, mono=True)
    onset_env = librosa.onset.onset_strength(y=y, sr=sr)
    onset_frames = librosa.onset.onset_detect(onset_envelope=onset_env, sr=sr, units="frames")
    onset_times = librosa.frames_to_time(onset_frames, sr=sr)
    onset_strengths = onset_env[onset_frames] if len(onset_frames) else np.array([])
    tempo, beat_frames = librosa.beat.beat_track(onset_envelope=onset_env, sr=sr, units="frames")
    beat_times = librosa.frames_to_time(beat_frames, sr=sr)
    threshold = float(np.percentile(onset_strengths, 65)) if len(onset_strengths) else 0.0
    strong = [
        {"time_seconds": round(float(t), 3), "strength": round(float(s), 4)}
        for t, s in zip(onset_times, onset_strengths)
        if float(s) >= threshold
    ]
    return {
        "tempo_bpm": round(float(np.atleast_1d(tempo)[0]), 3),
        "strong_onsets": strong,
        "beats": [round(float(t), 3) for t in beat_times],
    }


def nearest_value(values: list[float], target: float) -> tuple[float | None, float | None]:
    if not values:
        return None, None
    best = min(values, key=lambda item: abs(item - target))
    return best, best - target


def nearest_peak(rows: list[dict], target_source_time: float, radius: float) -> dict | None:
    candidates = [row for row in rows if abs(row["time_seconds"] - target_source_time) <= radius]
    if not candidates:
        return None
    return max(candidates, key=lambda row: row["motion_score"])


def top_peaks(rows: list[dict], count: int = 5, min_gap: float = 0.18) -> list[dict]:
    selected: list[dict] = []
    for row in sorted(rows, key=lambda item: item["motion_score"], reverse=True):
        if all(abs(row["time_seconds"] - existing["time_seconds"]) >= min_gap for existing in selected):
            selected.append(row)
        if len(selected) >= count:
            break
    return selected


def find_segment(recipe: dict, source: str, start: float, end: float) -> dict | None:
    for segment in recipe.get("timeline", []):
        if str(segment.get("source")) != source:
            continue
        output_in = float(segment["output_in"])
        output_out = float(segment["output_out"])
        if output_in - 0.02 <= start and end <= output_out + 0.02:
            return segment
    return None


def map_source_to_output(segment: dict, source_time: float) -> float:
    source_in = float(segment["source_in"])
    source_duration = float(segment.get("source_duration") or (float(segment["source_out"]) - source_in))
    output_in = float(segment["output_in"])
    output_duration = float(segment.get("output_duration") or (float(segment["output_out"]) - output_in))
    progress = (source_time - source_in) / max(source_duration, 0.0001)
    return output_in + progress * output_duration


def map_output_to_source(segment: dict, output_time: float) -> float:
    output_in = float(segment["output_in"])
    output_duration = float(segment.get("output_duration") or (float(segment["output_out"]) - output_in))
    source_in = float(segment["source_in"])
    source_duration = float(segment.get("source_duration") or (float(segment["source_out"]) - source_in))
    progress = (output_time - output_in) / max(output_duration, 0.0001)
    return source_in + progress * source_duration


def evaluate_status(target_output_time: float, mapped_peak_output: float | None, target_kind: str) -> str:
    if mapped_peak_output is None:
        return "no_local_motion_peak"
    delta = abs(mapped_peak_output - target_output_time)
    if target_kind == "endpoint":
        return "endpoint_frame_exists_motion_peak_optional" if delta <= 0.45 else "endpoint_frame_exists_peak_not_on_marker"
    if delta <= 0.18:
        return "pass"
    if delta <= 0.35:
        return "hold"
    return "fail"


def target_kind(visible_event: str, marker: float) -> str:
    text = visible_event.lower()
    if "endpoint" in text or abs(marker - 90.0) <= 0.04:
        return "endpoint"
    return "hit"


def build(args: argparse.Namespace) -> dict:
    run_root = args.run_root
    recipe = load_yaml(args.recipe)
    marker_table = load_yaml(args.marker_table)
    audio_path = run_root / str(recipe.get("audio_path") or "audio/selected/low-rubbery-low-eye-lean-selected.mp3")
    markers = audio_markers(audio_path)
    strong_times = [row["time_seconds"] for row in markers["strong_onsets"]]
    beat_times = markers["beats"]

    evidence_rows = []
    segment_cache: dict[str, list[dict]] = {}
    for decision in marker_table.get("decisions", []):
        if "rejected" in str(decision.get("candidate_status", "")):
            continue
        output_range = str(decision.get("output_range", ""))
        try:
            output_start, output_end = [float(part) for part in output_range.split("-", 1)]
        except ValueError:
            continue
        source = str(decision.get("source", ""))
        segment = find_segment(recipe, source, output_start, output_end)
        if segment is None:
            evidence_rows.append(
                {
                    "output_range": output_range,
                    "source": source,
                    "status": "blocked_segment_not_found_in_recipe",
                }
            )
            continue
        source_in = float(segment["source_in"])
        source_out = float(segment["source_out"])
        cache_key = f"{source}|{source_in:.3f}|{source_out:.3f}"
        if cache_key not in segment_cache:
            motion_csv = source_to_motion_csv(run_root, source)
            rows = read_motion_csv(motion_csv, source_in, source_out)
            if not rows or args.recompute_motion:
                rows = compute_motion_rows(source_path(run_root, source), source_in, source_out, args.sample_fps)
            segment_cache[cache_key] = rows
        rows = segment_cache[cache_key]
        source_peaks = top_peaks(rows)
        target_checks = []
        for check in decision.get("alignment_checks", []):
            target = float(check["selected_audio_marker"])
            expected_source = map_output_to_source(segment, target)
            local_peak = nearest_peak(rows, expected_source, args.local_peak_radius)
            mapped_peak_output = map_source_to_output(segment, local_peak["time_seconds"]) if local_peak else None
            nearest_onset, onset_delta = nearest_value(strong_times, target)
            nearest_beat, beat_delta = nearest_value(beat_times, target)
            kind = target_kind(str(check.get("visible_event", "")), target)
            target_checks.append(
                {
                    "selected_audio_marker": round(target, 3),
                    "visible_event": check.get("visible_event"),
                    "expected_source_time": round(expected_source, 3),
                    "local_peak_source_time": round(float(local_peak["time_seconds"]), 3) if local_peak else None,
                    "local_peak_motion_score": round(float(local_peak["motion_score"]), 6) if local_peak else None,
                    "mapped_peak_output_time": round(float(mapped_peak_output), 3) if mapped_peak_output is not None else None,
                    "peak_to_target_delta_seconds": round(float(mapped_peak_output - target), 3)
                    if mapped_peak_output is not None
                    else None,
                    "nearest_strong_onset": round(float(nearest_onset), 3) if nearest_onset is not None else None,
                    "strong_onset_delta_seconds": round(float(onset_delta), 3) if onset_delta is not None else None,
                    "nearest_beat": round(float(nearest_beat), 3) if nearest_beat is not None else None,
                    "beat_delta_seconds": round(float(beat_delta), 3) if beat_delta is not None else None,
                    "target_kind": kind,
                    "automatic_status": evaluate_status(target, mapped_peak_output, kind),
                }
            )
        evidence_rows.append(
            {
                "output_range": output_range,
                "slot": segment.get("slot"),
                "source": source,
                "source_range": f"{source_in:.3f}-{source_out:.3f}",
                "output_range_from_recipe": f"{float(segment['output_in']):.3f}-{float(segment['output_out']):.3f}",
                "speed_factor": segment.get("speed_factor"),
                "top_motion_peaks": [
                    {
                        "source_time": round(float(row["time_seconds"]), 3),
                        "mapped_output_time": round(float(map_source_to_output(segment, row["time_seconds"])), 3),
                        "motion_score": round(float(row["motion_score"]), 6),
                    }
                    for row in source_peaks
                ],
                "target_checks": target_checks,
            }
        )

    return {
        "schema_version": "idol_edit_recipe_alignment_evidence.v1",
        "content_id": recipe.get("content_id"),
        "status": "automatic_recognition_assist_review_required",
        "source_recipe": rel(args.recipe),
        "source_marker_table": rel(args.marker_table),
        "source_audio": rel(audio_path),
        "method": {
            "motion": "local optical-flow peaks in original source clip windows",
            "audio": "librosa selected-audio beat/onset assist",
            "use_rule": "Evidence only; pass still requires contact-sheet/playback review.",
            "sample_fps": args.sample_fps,
            "local_peak_radius_seconds": args.local_peak_radius,
        },
        "audio_summary": {
            "tempo_bpm": markers["tempo_bpm"],
            "strong_onset_count": len(strong_times),
            "beat_count": len(beat_times),
        },
        "alignment_evidence": evidence_rows,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-root", type=Path, required=True)
    parser.add_argument("--recipe", type=Path, required=True)
    parser.add_argument("--marker-table", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--sample-fps", type=float, default=24.0)
    parser.add_argument("--local-peak-radius", type=float, default=0.35)
    parser.add_argument("--recompute-motion", action="store_true")
    args = parser.parse_args()
    payload = build(args)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(yaml.safe_dump(payload, allow_unicode=True, sort_keys=False), encoding="utf-8")
    print(args.output)


if __name__ == "__main__":
    main()
