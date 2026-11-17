#!/usr/bin/env python3
"""Build a beat-aware roughcut workbench for IDOL video clips.

This script keeps the edit recipe easy to change: adjust the recipe YAML,
rerun, and it will emit a roughcut plus lightweight audio/motion reports.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path

try:
    import cv2
    import librosa
    import numpy as np
    import soundfile as sf
    import yaml
    from moviepy import (
        AudioFileClip,
        ColorClip,
        CompositeVideoClip,
        VideoFileClip,
        concatenate_videoclips,
    )
except ModuleNotFoundError as exc:
    raise SystemExit(
        f"Missing Python dependency '{exc.name}'. "
        "Run this script through scripts/idol-video-python."
    ) from exc

import idol_title_output_registry as title_registry


TARGET_SIZE = (1920, 1080)
FPS = 24


@dataclass(frozen=True)
class Segment:
    slot: str
    source: str
    start: float
    end: float
    out_duration: float | None = None
    note: str = ""


DEFAULT_RECIPE: list[Segment] = [
    Segment("R01", "r1.mp4", 0.0, 8.0, 8.0, "Longer opener per founder note."),
    Segment("R02", "r2.mp4", 0.0, 8.0, 8.0, "Rap refusal stays full 8s."),
    Segment("R03", "r3-2.mp4", 0.0, 7.8, 8.0, "Use forward sweep, cut before it loses taste."),
    Segment("R04", "r4.mp4", 0.0, 8.0, 8.0, "Cue-sheet verse shape drop."),
    Segment("R05", "r5-1.mp4", 0.0, 4.0, 4.0, "Reflection lift part A."),
    Segment("R05", "r5-2.mp4", 2.2, 6.2, 4.0, "Reflection lift part B, intended combine."),
    Segment("R06", "r6-2-trun 3sec.mp4", 0.0, 8.96, 8.0, "Pre-chorus lift compressed slightly."),
    Segment("R07", "r7.mp4", 0.0, 5.0, 5.0, "Rena insert."),
    Segment("R08", "r8.mp4", 0.0, 5.0, 5.0, "Aria insert; main stream only."),
    Segment("R09", "r9-2(additional).mp4", 0.0, 4.95, 4.5, "Wide chorus body read."),
    Segment("R09", "r9.mp4", 1.4, 5.25, 3.5, "Close hand-lock hit."),
    Segment("R10", "r10.mp4", 0.0, 6.0, 6.0, "Short hook impact."),
    Segment("R11", "r11.mp4", 0.0, 5.0, 5.0, "Tight moved short seat."),
    Segment("R12", "r12(until 5sec).mp4", 0.0, 5.0, 5.0, "Solo rap-vocal pickup."),
    Segment("R13", "r13(until7sec).mp4", 0.0, 6.0, 6.0, "Shion start."),
    Segment("R14", "r14.mp4", 0.0, 5.0, 5.0, "Body memory push."),
    Segment("R15", "r15.mp4", 0.0, 6.0, 6.0, "Six-second threshold hit."),
    Segment("R16", "r16-1-high pitch.mp4", 1.2, 4.2, 3.0, "Mid-entry high pickup."),
    Segment("R17", "r17.mp4", 0.0, 6.0, 6.0, "Short solo bridge."),
]


def run(cmd: list[str]) -> None:
    subprocess.run(cmd, check=True)


def tool_path(name: str) -> str:
    for prefix in ["/opt/homebrew/bin", "/usr/local/bin"]:
        preferred = Path(prefix) / name
        if preferred.exists():
            return str(preferred)
    found = shutil.which(name)
    if found:
        return found
    raise SystemExit(
        f"Missing required tool: {name}. "
        "Run through scripts/idol-video-python or install ffmpeg in Homebrew."
    )


def ffprobe_duration(path: Path) -> float:
    proc = subprocess.run(
        [
            tool_path("ffprobe"),
            "-v",
            "error",
            "-show_entries",
            "format=duration",
            "-of",
            "default=noprint_wrappers=1:nokey=1",
            str(path),
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    return float(proc.stdout.strip())


def fit_16x9(clip):
    width, height = clip.size
    scale = min(TARGET_SIZE[0] / width, TARGET_SIZE[1] / height)
    new_size = (int(width * scale), int(height * scale))
    return (
        clip.resized(new_size)
        .with_background_color(size=TARGET_SIZE, color=(0, 0, 0), pos=("center", "center"))
        .with_fps(FPS)
    )


def segment_clip(raw_dir: Path, seg: Segment):
    clip = VideoFileClip(str(raw_dir / seg.source), audio=False)
    sub = clip.subclipped(seg.start, seg.end)
    source_duration = seg.end - seg.start
    if seg.out_duration and not math.isclose(source_duration, seg.out_duration, abs_tol=0.02):
        factor = source_duration / seg.out_duration
        sub = sub.with_speed_scaled(factor=factor)
    return fit_16x9(sub)


def slice_recipe_for_preview(
    recipe: list[Segment],
    preview_start: float,
    preview_duration: float,
) -> list[Segment]:
    preview_end = preview_start + preview_duration
    cursor = 0.0
    sliced = []
    for seg in recipe:
        source_duration = seg.end - seg.start
        output_duration = seg.out_duration or source_duration
        output_start = cursor
        output_end = cursor + output_duration
        cursor = output_end
        overlap_start = max(preview_start, output_start)
        overlap_end = min(preview_end, output_end)
        if overlap_end <= overlap_start:
            continue
        speed_factor = source_duration / output_duration
        source_in = seg.start + ((overlap_start - output_start) * speed_factor)
        source_out = seg.start + ((overlap_end - output_start) * speed_factor)
        sliced.append(
            Segment(
                slot=seg.slot,
                source=seg.source,
                start=source_in,
                end=source_out,
                out_duration=overlap_end - overlap_start,
                note=f"Preview slice {preview_start:.3f}-{preview_end:.3f}s: {seg.note}",
            )
        )
    if not sliced:
        raise ValueError(
            f"No recipe segments overlap preview window {preview_start}-{preview_end}s"
        )
    return sliced


def resolve_meter_phase(
    beat_times: np.ndarray,
    meter_beats: int,
    phase_anchor_seconds: float | None,
    phase_anchor_beat_in_bar: int | None,
    phase_anchor_tolerance: float,
) -> tuple[str, int, float | None]:
    """Resolve an explicitly anchored meter phase without guessing a downbeat."""
    if not 1 <= meter_beats <= 32:
        raise SystemExit("meter beats must be between 1 and 32")
    if (phase_anchor_seconds is None) != (phase_anchor_beat_in_bar is None):
        raise SystemExit("phase anchor seconds and beat-in-bar must be supplied together")
    if phase_anchor_tolerance <= 0:
        raise SystemExit("phase anchor tolerance must be positive")
    if phase_anchor_seconds is None:
        return "unverified_candidate", 0, None
    if not len(beat_times):
        raise SystemExit("manual phase anchor cannot lock because no beats were detected")
    if not 1 <= int(phase_anchor_beat_in_bar) <= meter_beats:
        raise SystemExit("phase anchor beat-in-bar must be within the declared meter")

    distances = np.abs(beat_times - float(phase_anchor_seconds))
    nearest_index = int(np.argmin(distances))
    phase_delta = float(beat_times[nearest_index] - float(phase_anchor_seconds))
    if abs(phase_delta) > phase_anchor_tolerance:
        raise SystemExit(
            f"phase anchor is {abs(phase_delta):.4f}s from the nearest detected beat; "
            f"tolerance is {phase_anchor_tolerance:.4f}s"
        )
    phase_origin = nearest_index - (int(phase_anchor_beat_in_bar) - 1)
    return "manual_locked", phase_origin, phase_delta


def analyze_audio(
    audio_path: Path,
    out_dir: Path,
    *,
    meter_beats: int = 4,
    phase_anchor_seconds: float | None = None,
    phase_anchor_beat_in_bar: int | None = None,
    phase_anchor_tolerance: float = 0.08,
) -> dict:
    """Build edit-assist beat/onset summary.

    Backward-compatible core fields are preserved. v2 fields refine 04/04FX
    opportunity seeding only; they never lock cut timing.
    """
    hop = 512
    y, sr = librosa.load(audio_path, sr=None, mono=True)
    tempo, beat_frames = librosa.beat.beat_track(y=y, sr=sr, units="frames", hop_length=hop)
    beat_times = librosa.frames_to_time(beat_frames, sr=sr, hop_length=hop)
    onset_env = librosa.onset.onset_strength(y=y, sr=sr, hop_length=hop)
    onset_env_times = librosa.frames_to_time(np.arange(len(onset_env)), sr=sr, hop_length=hop)
    onset_frames = librosa.onset.onset_detect(
        onset_envelope=onset_env, sr=sr, hop_length=hop, units="frames"
    )
    onset_times = librosa.frames_to_time(onset_frames, sr=sr, hop_length=hop)
    rms = librosa.feature.rms(y=y, frame_length=2048, hop_length=hop)[0]
    rms_times = librosa.frames_to_time(np.arange(len(rms)), sr=sr, hop_length=hop)
    duration = librosa.get_duration(y=y, sr=sr)

    y_h, y_p = librosa.effects.hpss(y)
    onset_env_p = librosa.onset.onset_strength(y=y_p, sr=sr, hop_length=hop)
    perc_onset_frames = librosa.onset.onset_detect(
        onset_envelope=onset_env_p, sr=sr, hop_length=hop, units="frames"
    )
    perc_onset_times = librosa.frames_to_time(perc_onset_frames, sr=sr, hop_length=hop)

    onset_strengths = []
    for t in onset_times:
        idx = int(np.argmin(np.abs(onset_env_times - t)))
        onset_strengths.append(float(onset_env[idx]))
    onset_strengths_arr = np.asarray(onset_strengths, dtype=float)
    max_onset = float(np.max(onset_strengths_arr)) if onset_strengths_arr.size else 1.0
    ranked_onsets = sorted(
        [
            {
                "time_seconds": round(float(t), 3),
                "strength_norm": round(float(s / max_onset), 6),
            }
            for t, s in zip(onset_times, onset_strengths_arr)
        ],
        key=lambda row: row["strength_norm"],
        reverse=True,
    )

    # Energy jumps: large positive RMS deltas (section/drop candidates).
    energy_jumps = []
    if rms.size > 4:
        rms_norm = rms / max(float(np.max(rms)), 1e-8)
        delta = np.diff(rms_norm)
        threshold = float(np.percentile(delta, 92))
        last_t = -999.0
        for idx, value in enumerate(delta):
            if value < threshold:
                continue
            t = float(rms_times[min(idx + 1, len(rms_times) - 1)])
            if t - last_t < 0.35:
                continue
            energy_jumps.append(
                {
                    "time_seconds": round(t, 3),
                    "delta_norm": round(float(value), 6),
                }
            )
            last_t = t

    # Low-energy holds: quiet windows that may need fade/hold treatment, not auto cuts.
    low_energy_holds = []
    if rms.size:
        rms_norm = rms / max(float(np.max(rms)), 1e-8)
        quiet = rms_norm < max(0.12, float(np.percentile(rms_norm, 15)))
        start_idx = None
        for idx, is_quiet in enumerate(quiet):
            if is_quiet and start_idx is None:
                start_idx = idx
            if (not is_quiet or idx == len(quiet) - 1) and start_idx is not None:
                end_idx = idx if not is_quiet else idx
                start_t = float(rms_times[start_idx])
                end_t = float(rms_times[end_idx])
                if end_t - start_t >= 0.45:
                    low_energy_holds.append(
                        {
                            "start_seconds": round(start_t, 3),
                            "end_seconds": round(end_t, 3),
                            "duration_seconds": round(end_t - start_t, 3),
                        }
                    )
                start_idx = None

    phase_status, phase_origin, phase_delta = resolve_meter_phase(
        beat_times,
        meter_beats,
        phase_anchor_seconds,
        phase_anchor_beat_in_bar,
        phase_anchor_tolerance,
    )

    beat_rows = []
    bar_starts = []
    beat_2_4 = []
    for idx, t in enumerate(beat_times):
        beat_in_bar = ((idx - phase_origin) % meter_beats) + 1
        beat_rows.append(
            {
                "beat_index": idx + 1,
                "time_seconds": round(float(t), 3),
                "beat_in_bar": beat_in_bar,
                "phase_status": phase_status,
            }
        )
        if beat_in_bar == 1:
            bar_starts.append(round(float(t), 3))
        if meter_beats >= 4 and beat_in_bar in {2, 4}:
            beat_2_4.append(round(float(t), 3))

    result = {
        "schema_version": "idol_audio_beat_onset_summary.v2_1",
        "status": "measurement_evidence_only",
        "audio_path": str(audio_path),
        "duration_seconds": round(float(duration), 3),
        "tempo_bpm": round(float(np.atleast_1d(tempo)[0]), 3),
        "beat_count": int(len(beat_times)),
        "onset_count": int(len(onset_times)),
        "first_beats_seconds": [round(float(t), 3) for t in beat_times[:32]],
        "strong_onsets_seconds": [round(float(t), 3) for t in onset_times[:64]],
        "rms_mean": round(float(np.mean(rms)), 6),
        "rms_p95": round(float(np.percentile(rms, 95)), 6),
        # v2 assist fields (optional consumers; never lock 04 cuts)
        "meter_phase": {
            "status": phase_status,
            "meter_beats": meter_beats,
            "anchor_seconds": phase_anchor_seconds,
            "anchor_beat_in_bar": phase_anchor_beat_in_bar,
            "nearest_detected_beat_delta_seconds": (
                round(phase_delta, 6) if phase_delta is not None else None
            ),
            "use_rule": (
                "Only manual_locked phase is bar-position evidence. Candidate phase "
                "cannot justify an automatic transition or cut."
            ),
        },
        "bar_start_candidate_seconds": bar_starts[:256]
        if phase_status == "unverified_candidate"
        else [],
        "beat_2_4_phase_candidate_seconds": beat_2_4[:512]
        if phase_status == "unverified_candidate"
        else [],
        "bar_start_locked_seconds": bar_starts[:256]
        if phase_status == "manual_locked"
        else [],
        "beat_2_4_phase_locked_seconds": beat_2_4[:512]
        if phase_status == "manual_locked"
        else [],
        "downbeat_seconds": bar_starts[:256] if meter_beats == 4 else [],
        "backbeat_seconds": beat_2_4[:512] if meter_beats == 4 else [],
        "legacy_phase_warning": (
            "downbeat_seconds/backbeat_seconds are compatibility aliases. Without a "
            "manual phase lock they are first-detected-beat candidates, not confirmed "
            "bar starts or acoustic backbeats."
        ),
        "beat_grid_head_seconds": [round(float(t), 3) for t in beat_times[:128]],
        "strong_onsets_ranked": ranked_onsets[:128],
        "percussive_onset_seconds": [round(float(t), 3) for t in perc_onset_times[:128]],
        "energy_jump_candidates": energy_jumps[:64],
        "low_energy_hold_windows": low_energy_holds[:64],
        "assist_policy": {
            "allowed_use": [
                "04_marker_seed",
                "04fx_transition_opportunity_seed",
                "cue_bpm_nearby_onset_evidence",
            ],
            "not_allowed_to_lock": [
                "source_in",
                "source_out",
                "speed_factor",
                "final_cutpoint",
                "final_candidate_selection",
                "founder_pass_fail",
            ],
            "human_review_required": True,
        },
    }
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "audio-beat-onset-summary.json").write_text(
        json.dumps(result, indent=2, ensure_ascii=False) + "\n"
    )
    with (out_dir / "audio-beats.csv").open("w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["beat_index", "time_seconds", "beat_in_bar"])
        for row in beat_rows:
            writer.writerow([row["beat_index"], row["time_seconds"], row["beat_in_bar"]])
    return result


def motion_profile(video_path: Path, out_csv: Path, sample_fps: float = 4.0) -> dict:
    cap = cv2.VideoCapture(str(video_path))
    native_fps = cap.get(cv2.CAP_PROP_FPS) or 24.0
    step = max(1, int(round(native_fps / sample_fps)))
    prev_gray = None
    rows = []
    frame_idx = -1
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        frame_idx += 1
        if frame_idx % step != 0:
            continue
        small = cv2.resize(frame, (160, 90))
        gray = cv2.cvtColor(small, cv2.COLOR_BGR2GRAY)
        if prev_gray is None:
            score = 0.0
        else:
            flow = cv2.calcOpticalFlowFarneback(
                prev_gray, gray, None, 0.5, 3, 15, 3, 5, 1.2, 0
            )
            mag, _ = cv2.cartToPolar(flow[..., 0], flow[..., 1])
            score = float(np.mean(mag))
        time_seconds = frame_idx / native_fps
        rows.append((round(time_seconds, 4), round(score, 6)))
        prev_gray = gray
    cap.release()

    out_csv.parent.mkdir(parents=True, exist_ok=True)
    with out_csv.open("w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["time_seconds", "motion_score"])
        writer.writerows(rows)
    top = sorted(rows, key=lambda row: row[1], reverse=True)[:8]
    return {"video": str(video_path), "sample_fps": sample_fps, "top_motion_peaks": top}


def load_recipe(recipe_path: Path) -> list[Segment]:
    payload = yaml.safe_load(recipe_path.read_text()) or {}
    recipe = []
    for row in payload.get("timeline", []):
        source = row["source"]
        if source.startswith("generations/video/raw/"):
            source = source.removeprefix("generations/video/raw/")
        recipe.append(
            Segment(
                slot=row["slot"],
                source=source,
                start=float(row["source_in"]),
                end=float(row["source_out"]),
                out_duration=float(row.get("output_duration") or row["source_out"] - row["source_in"]),
                note=row.get("note", ""),
            )
        )
    if not recipe:
        raise ValueError(f"No timeline segments found in {recipe_path}")
    return recipe


def write_recipe(
    run_root: Path,
    out_dir: Path,
    recipe: list[Segment],
    audio_summary: dict,
    motion_summaries: list[dict],
    recipe_path: Path,
    recipe_payload: dict | None = None,
) -> None:
    timeline = []
    cursor = 0.0
    for seg in recipe:
        source_duration = seg.end - seg.start
        out_duration = seg.out_duration or source_duration
        timeline.append(
            {
                "slot": seg.slot,
                "source": f"generations/video/raw/{seg.source}",
                "source_in": seg.start,
                "source_out": seg.end,
                "source_duration": round(source_duration, 3),
                "output_in": round(cursor, 3),
                "output_out": round(cursor + out_duration, 3),
                "output_duration": round(out_duration, 3),
                "speed_factor": round(source_duration / out_duration, 4),
                "note": seg.note,
            }
        )
        cursor += out_duration

    payload = {
        "schema_version": "idol_video_sync_workbench.v1",
        "content_id": run_root.name,
        "status": "draft_manual_adjustment_ready",
        "total_duration_seconds": round(cursor, 3),
        "audio_summary": audio_summary,
        "timeline": timeline,
        "motion_summaries": motion_summaries,
        "edit_rule": (
            "Edit timeline source/source_in/source_out/output_duration in this YAML, "
            "then rerun scripts/idol-video-python scripts/idol_video_sync_workbench.py; "
            "do not hand-edit generated media."
        ),
    }
    for key in [
        "base_recipe",
        "candidate_notes",
        "effects",
        "fix_notes",
        "founder_combo_notes",
        "founder_request",
        "source_limit_note",
    ]:
        if recipe_payload and key in recipe_payload:
            payload[key] = recipe_payload[key]
    recipe_path.parent.mkdir(parents=True, exist_ok=True)
    recipe_path.write_text(yaml.safe_dump(payload, allow_unicode=True, sort_keys=False))


def slice_effects(
    effects: list[dict],
    preview_start: float,
    preview_duration: float,
) -> list[dict]:
    preview_end = preview_start + preview_duration
    sliced = []
    for effect in effects:
        if "start" not in effect:
            continue
        start = float(effect["start"])
        duration = float(effect.get("duration", 0.16))
        end = start + duration
        if end <= preview_start or start >= preview_end:
            continue
        copied = dict(effect)
        copied["start"] = max(0.0, start - preview_start)
        copied["duration"] = min(end, preview_end) - max(start, preview_start)
        sliced.append(copied)
    return sliced


def effect_source_path(raw_dir: Path, source: str) -> Path:
    source_path = Path(source)
    marker = Path("generations/video/raw")
    parts = source_path.parts
    marker_parts = marker.parts
    for idx in range(len(parts) - len(marker_parts) + 1):
        if parts[idx : idx + len(marker_parts)] == marker_parts:
            source_path = Path(*parts[idx + len(marker_parts) :])
            break
    if source_path.is_absolute():
        return source_path
    return raw_dir / source_path


def apply_effects(clip, effects: list[dict], raw_dir: Path):
    overlays = [clip]
    for effect in effects:
        effect_type = effect.get("type")
        if effect_type == "hard_cut_note":
            continue
        if "start" not in effect:
            continue
        start = max(0.0, float(effect["start"]))
        duration = float(effect.get("duration", 0.16))
        end = min(start + duration, clip.duration)
        if end <= start:
            continue
        if effect_type in {"flash", "dip_flash"}:
            opacity = float(effect.get("opacity", 0.72 if effect_type == "flash" else 0.45))
            color = tuple(effect.get("color", [255, 255, 255] if effect_type == "flash" else [0, 0, 0]))
            overlays.append(
                ColorClip(size=TARGET_SIZE, color=color, duration=end - start)
                .with_start(start)
                .with_opacity(opacity)
            )
        elif effect_type == "punch_zoom":
            factor = float(effect.get("factor", 1.06))
            overlays.append(
                clip.subclipped(start, end)
                .resized(factor)
                .with_start(start)
                .with_position(("center", "center"))
            )
        elif effect_type == "micro_freeze":
            frame_t = min(start, max(0.0, clip.duration - (1 / FPS)))
            overlays.append(
                clip.to_ImageClip(t=frame_t)
                .with_duration(end - start)
                .with_start(start)
                .with_fps(FPS)
            )
        elif effect_type == "source_overlay":
            source = effect.get("source")
            if not source:
                continue
            source_in = float(effect.get("source_in", 0.0))
            source_out = float(effect.get("source_out", source_in + (end - start)))
            source_duration = max(0.0, source_out - source_in)
            output_duration = end - start
            if source_duration <= 0 or output_duration <= 0:
                continue
            overlay = VideoFileClip(str(effect_source_path(raw_dir, source)), audio=False).subclipped(
                source_in,
                source_out,
            )
            if not math.isclose(source_duration, output_duration, abs_tol=0.02):
                overlay = overlay.with_speed_scaled(factor=source_duration / output_duration)
            opacity = float(effect.get("opacity", 0.32))
            overlays.append(
                fit_16x9(overlay)
                .with_duration(output_duration)
                .with_start(start)
                .with_opacity(opacity)
            )
    if len(overlays) == 1:
        return clip
    return CompositeVideoClip(overlays, size=TARGET_SIZE).with_duration(clip.duration).with_fps(FPS)


def build_roughcut(
    run_root: Path,
    audio_path: Path,
    output_path: Path,
    recipe: list[Segment],
    preset: str,
    effects: list[dict],
    audio_start: float = 0.0,
) -> None:
    raw_dir = run_root / "generations/video/raw"
    clips = []
    for seg in recipe:
        clips.append(segment_clip(raw_dir, seg))
    joined = concatenate_videoclips(clips, method="compose")
    joined = apply_effects(joined, effects, raw_dir)
    audio = AudioFileClip(str(audio_path)).subclipped(
        audio_start,
        audio_start + joined.duration,
    )
    joined = joined.with_audio(audio)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    joined.write_videofile(
        str(output_path),
        fps=FPS,
        codec="libx264",
        audio_codec="aac",
        preset=preset,
        threads=8,
        logger=None,
    )
    joined.close()
    audio.close()
    for clip in clips:
        clip.close()


def make_qc_sheet(video_path: Path, out_path: Path) -> None:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    duration = ffprobe_duration(video_path)
    frame_count = math.ceil(duration)
    columns = 12 if frame_count <= 108 else 15
    rows = math.ceil(frame_count / columns)
    thumb_w = 240 if frame_count <= 108 else 180
    thumb_h = 135 if frame_count <= 108 else 101
    run(
        [
            tool_path("ffmpeg"),
            "-hide_banner",
            "-y",
            "-i",
            str(video_path),
            "-vf",
            (
                "fps=1,"
                "drawtext=text='%{pts\\:hms}':x=6:y=6:fontcolor=white:"
                "fontsize=18:box=1:boxcolor=black@0.65,"
                f"scale={thumb_w}:{thumb_h}:force_original_aspect_ratio=decrease,"
                f"pad={thumb_w}:{thumb_h}:(ow-iw)/2:(oh-ih)/2,"
                f"tile={columns}x{rows}:padding=4:margin=4"
            ),
            "-frames:v",
            "1",
            "-update",
            "1",
            str(out_path),
        ]
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--run-root",
        default="runs/2026-05-24/AURORA_M_FULL_CODE_ROOT_SIGNAL",
        type=Path,
    )
    parser.add_argument(
        "--recipe",
        type=Path,
        help="Editable recipe YAML. Defaults to the run-owned sync-workbench recipe.",
    )
    parser.add_argument(
        "--write-default-recipe",
        action="store_true",
        help="Overwrite the recipe YAML from the script's default R01-R17 plan before rendering.",
    )
    parser.add_argument(
        "--output",
        type=Path,
        help="Output mp4 path. Defaults to the current v3 workbench output.",
    )
    parser.add_argument(
        "--qc-sheet",
        type=Path,
        help="Output 1-second QC contact sheet path.",
    )
    parser.add_argument(
        "--preset",
        default="medium",
        help="libx264 preset for MoviePy/ffmpeg render.",
    )
    parser.add_argument("--album-key", default=title_registry.DEFAULT_ALBUM_KEY)
    parser.add_argument("--title-key", default=None)
    parser.add_argument("--title", default="")
    parser.add_argument("--skip-title-registry", action="store_true")
    parser.add_argument(
        "--preview-start",
        type=float,
        help="Render only a timeline window starting at this output second.",
    )
    parser.add_argument(
        "--preview-duration",
        type=float,
        help="Preview window duration in seconds. Requires --preview-start.",
    )
    parser.add_argument(
        "--preview-end",
        type=float,
        help="Preview window end in output seconds. Alternative to --preview-duration.",
    )
    parser.add_argument(
        "--audio-track",
        type=Path,
        help="Selected audio file to use for marker analysis and render audio.",
    )
    parser.add_argument(
        "--audio-start",
        type=float,
        default=0.0,
        help=(
            "Selected-audio start time for the rendered output. "
            "Use for section calibration previews whose recipe timeline starts at 0."
        ),
    )
    parser.add_argument("--meter-beats", type=int, default=4)
    parser.add_argument("--phase-anchor-seconds", type=float)
    parser.add_argument("--phase-anchor-beat-in-bar", type=int)
    parser.add_argument("--phase-anchor-tolerance", type=float, default=0.08)
    args = parser.parse_args()
    if not 1 <= args.meter_beats <= 32:
        parser.error("--meter-beats must be between 1 and 32")
    if (args.phase_anchor_seconds is None) != (args.phase_anchor_beat_in_bar is None):
        parser.error("phase anchor seconds and beat-in-bar must be supplied together")
    if args.phase_anchor_tolerance <= 0:
        parser.error("--phase-anchor-tolerance must be positive")
    if args.preview_start is None and (args.preview_duration is not None or args.preview_end is not None):
        parser.error("--preview-start is required for preview rendering")
    if args.preview_start is not None and (args.preview_duration is None) == (args.preview_end is None):
        parser.error("provide exactly one of --preview-duration or --preview-end with --preview-start")
    preview_duration = None
    if args.preview_start is not None:
        preview_duration = (
            float(args.preview_duration)
            if args.preview_duration is not None
            else float(args.preview_end) - float(args.preview_start)
        )
        if preview_duration <= 0:
            parser.error("preview duration must be positive")
    run_root = args.run_root
    out_dir = run_root / "generations/video/qc/sync-workbench-v1"
    out_dir.mkdir(parents=True, exist_ok=True)
    recipe_path = args.recipe or out_dir / "sync-workbench-recipe-v1.yaml"
    audio_path = args.audio_track or run_root / "audio/selected/loom-dubut.mp3"
    if not audio_path.is_absolute():
        audio_path = Path(audio_path)
        if not audio_path.exists():
            audio_path = run_root / audio_path
    if not audio_path.exists():
        raise SystemExit(f"Missing selected audio track: {audio_path}")
    if recipe_path.exists() and not args.write_default_recipe:
        recipe_payload = yaml.safe_load(recipe_path.read_text()) or {}
        recipe = load_recipe(recipe_path)
    else:
        recipe_payload = {}
        recipe = DEFAULT_RECIPE

    preview_mode = args.preview_start is not None
    render_recipe = recipe
    render_effects = recipe_payload.get("effects", [])
    audio_start = float(args.audio_start)
    if audio_start < 0:
        parser.error("--audio-start must be non-negative")
    if preview_mode:
        render_recipe = slice_recipe_for_preview(
            recipe,
            float(args.preview_start),
            float(preview_duration),
        )
        render_effects = slice_effects(
            render_effects,
            float(args.preview_start),
            float(preview_duration),
        )
        audio_start += float(args.preview_start)

    audio_summary = analyze_audio(
        audio_path,
        out_dir,
        meter_beats=args.meter_beats,
        phase_anchor_seconds=args.phase_anchor_seconds,
        phase_anchor_beat_in_bar=args.phase_anchor_beat_in_bar,
        phase_anchor_tolerance=args.phase_anchor_tolerance,
    )

    selected_sources = sorted({seg.source for seg in render_recipe})
    motion_summaries = []
    for source in selected_sources:
        video_path = run_root / "generations/video/raw" / source
        motion_summaries.append(
            motion_profile(video_path, out_dir / "motion" / f"{source}.csv")
        )

    if not preview_mode:
        write_recipe(run_root, out_dir, recipe, audio_summary, motion_summaries, recipe_path, recipe_payload)

    if args.output:
        output_path = args.output
    elif preview_mode:
        preview_end = float(args.preview_start) + float(preview_duration)
        label = f"{float(args.preview_start):06.2f}-{preview_end:06.2f}".replace(".", "p")
        output_path = run_root / "generations/video/qc/previews" / f"{recipe_path.stem}-preview-{label}.mp4"
    else:
        output_path = run_root / "generations/video/master/root-signal-r01-r17-sync-workbench-v3.mp4"
    build_roughcut(run_root, audio_path, output_path, render_recipe, args.preset, render_effects, audio_start)
    if args.qc_sheet:
        qc_sheet = args.qc_sheet
    elif preview_mode:
        qc_sheet = (
            run_root
            / "generations/video/qc/contact-sheets"
            / f"{output_path.stem}-1sec-qc-contact-sheet.png"
        )
    else:
        qc_sheet = run_root / "generations/video/qc/contact-sheets/root-signal-r01-r17-sync-workbench-v3-1sec-qc-contact-sheet.png"
    make_qc_sheet(
        output_path,
        qc_sheet,
    )
    if not args.skip_title_registry:
        album = title_registry.album_key(args.album_key)
        track = title_registry.title_key(args.title_key, fallback=args.title or run_root.name)
        output_type = "qc_artifact" if preview_mode else "edit_master"
        output_status = "exported" if preview_mode else "generated"
        title_registry.register_outputs(
            album=album,
            title=track,
            title_display_name=args.title or track,
            content_id=run_root.name,
            run_root=title_registry.rel(run_root),
            outputs=[
                {
                    "output_type": output_type,
                    "path": output_path,
                    "source_run_root": run_root,
                    "content_id": run_root.name,
                    "source_step": "edit",
                    "status": output_status,
                    "notes": "video sync workbench output",
                },
                {
                    "output_type": "qc_artifact",
                    "path": qc_sheet,
                    "source_run_root": run_root,
                    "content_id": run_root.name,
                    "source_step": "edit",
                    "status": "exported",
                    "notes": "video sync workbench QC sheet",
                },
            ],
            status="generated",
            write=True,
        )
    print(output_path)


if __name__ == "__main__":
    main()
