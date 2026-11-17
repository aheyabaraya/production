from __future__ import annotations

import argparse
import csv
import json
import math
from pathlib import Path
from typing import Any

import librosa
import numpy as np


HOP_LENGTH = 512


def round_time(value: float, digits: int) -> float:
    return round(float(value), digits)


def scalar(value: Any) -> float | None:
    arr = np.asarray(value)
    if arr.shape == ():
        return float(arr)
    if arr.size == 0:
        return None
    return float(arr.reshape(-1)[0])


def parse_window_spec(value: str) -> tuple[str, float, float]:
    parts = value.split(":")
    if len(parts) != 3:
        raise argparse.ArgumentTypeError("window specs must be ID:start:end")
    label, start, end = parts
    try:
        start_f = float(start)
        end_f = float(end)
    except ValueError as exc:
        raise argparse.ArgumentTypeError("start/end must be numbers") from exc
    if not label or start_f < 0 or end_f <= start_f:
        raise argparse.ArgumentTypeError("window specs require ID and end > start >= 0")
    return label, start_f, end_f


def nearest_beat(time_value: float, beat_times: np.ndarray, digits: int) -> dict[str, Any]:
    if beat_times.size == 0:
        return {"beat_index": None, "time_sec": None, "delta_sec": None}
    idx = int(np.argmin(np.abs(beat_times - time_value)))
    return {
        "beat_index": idx + 1,
        "time_sec": round_time(float(beat_times[idx]), digits),
        "delta_sec": round_time(float(beat_times[idx] - time_value), digits),
    }


def meter_phase(
    beat_times: np.ndarray,
    meter_beats: int,
    anchor_seconds: float | None,
    anchor_beat_in_bar: int | None,
    tolerance: float,
) -> tuple[str, int, float | None]:
    """Return phase status, zero-based anchor beat index, and anchor delta."""
    if not 1 <= meter_beats <= 32:
        raise SystemExit("meter beats must be between 1 and 32")
    if (anchor_seconds is None) != (anchor_beat_in_bar is None):
        raise SystemExit("phase anchor seconds and beat-in-bar must be supplied together")
    if tolerance <= 0:
        raise SystemExit("phase anchor tolerance must be positive")
    if not len(beat_times):
        if anchor_seconds is not None:
            raise SystemExit("manual phase anchor cannot lock because no beats were detected")
        return "unverified_candidate", 0, None
    if anchor_seconds is None:
        return "unverified_candidate", 0, None
    distances = np.abs(beat_times - float(anchor_seconds))
    nearest_index = int(np.argmin(distances))
    delta = float(beat_times[nearest_index] - float(anchor_seconds))
    if abs(delta) > tolerance:
        raise SystemExit(
            f"phase anchor is {abs(delta):.4f}s from nearest detected beat; "
            f"tolerance is {tolerance:.4f}s"
        )
    if anchor_beat_in_bar is None or not 1 <= anchor_beat_in_bar <= meter_beats:
        raise SystemExit("--phase-anchor-beat-in-bar must be within --meter-beats")
    phase_origin = nearest_index - (anchor_beat_in_bar - 1)
    return "manual_locked", phase_origin, delta


def normalize_rows(matrix: np.ndarray) -> np.ndarray:
    if matrix.size == 0:
        return matrix
    norms = np.linalg.norm(matrix, axis=1, keepdims=True)
    return matrix / np.maximum(norms, 1e-8)


def window_metrics(
    start: float,
    end: float,
    frame_times: np.ndarray,
    rms: np.ndarray,
    onset_env_times: np.ndarray,
    onset_env: np.ndarray,
    onset_times: np.ndarray,
    beat_times: np.ndarray,
    rms_h: np.ndarray = None,
    rms_p: np.ndarray = None,
    digits: int = 3,
) -> dict[str, Any]:
    duration = max(end - start, 1e-8)
    rms_mask = (frame_times >= start) & (frame_times < end)
    onset_env_mask = (onset_env_times >= start) & (onset_env_times < end)
    onset_count = int(np.count_nonzero((onset_times >= start) & (onset_times < end)))
    beat_count = int(np.count_nonzero((beat_times >= start) & (beat_times < end)))
    res = {
        "duration_sec": round_time(duration, digits),
        "mean_rms": round(float(np.mean(rms[rms_mask])), 6) if np.any(rms_mask) else None,
        "peak_rms": round(float(np.max(rms[rms_mask])), 6) if np.any(rms_mask) else None,
        "mean_onset_strength": round(float(np.mean(onset_env[onset_env_mask])), 6)
        if np.any(onset_env_mask)
        else None,
        "detected_onset_count": onset_count,
        "detected_onsets_per_sec": round_time(onset_count / duration, digits),
        "beat_count": beat_count,
    }
    if rms_h is not None and np.any(rms_mask):
        res["mean_rms_harmonic"] = round(float(np.mean(rms_h[rms_mask])), 6)
        res["peak_rms_harmonic"] = round(float(np.max(rms_h[rms_mask])), 6)
    if rms_p is not None and np.any(rms_mask):
        res["mean_rms_percussive"] = round(float(np.mean(rms_p[rms_mask])), 6)
        res["peak_rms_percussive"] = round(float(np.max(rms_p[rms_mask])), 6)
    return res


def pitch_rows(y: np.ndarray, sr: int, hop_length: int, digits: int) -> list[dict[str, Any]]:
    pitches, magnitudes = librosa.piptrack(y=y, sr=sr, n_fft=2048, hop_length=hop_length)
    if pitches.size == 0:
        return []
    frame_indices = np.arange(pitches.shape[1])
    max_bins = np.argmax(magnitudes, axis=0)
    hz_values = pitches[max_bins, frame_indices]
    mag_values = magnitudes[max_bins, frame_indices]
    max_mag = float(np.max(mag_values)) or 1.0
    times = librosa.frames_to_time(frame_indices, sr=sr, hop_length=hop_length)
    rows: list[dict[str, Any]] = []
    for idx, (time_value, hz, mag) in enumerate(zip(times, hz_values, mag_values), start=1):
        if hz <= 0 or mag <= 0:
            continue
        rows.append(
            {
                "frame_index": idx,
                "time_sec": round_time(float(time_value), digits),
                "dominant_pitch_hz": round(float(hz), 3),
                "note_proxy": librosa.hz_to_note(float(hz), octave=True),
                "strength_norm": round(float(mag / max_mag), 6),
            }
        )
    return rows


def motif_candidates(
    y: np.ndarray,
    sr: int,
    window_seconds: float,
    hop_seconds: float,
    min_gap_seconds: float,
    top_n: int,
    digits: int,
) -> list[dict[str, Any]]:
    window = max(int(window_seconds * sr), 1)
    hop = max(int(hop_seconds * sr), 1)
    features: list[np.ndarray] = []
    windows: list[tuple[float, float]] = []
    for start in range(0, max(len(y) - window + 1, 1), hop):
        end = min(start + window, len(y))
        segment = y[start:end]
        if segment.size < sr:
            continue
        chroma = librosa.feature.chroma_cqt(y=segment, sr=sr, hop_length=HOP_LENGTH)
        mfcc = librosa.feature.mfcc(y=segment, sr=sr, n_mfcc=8, hop_length=HOP_LENGTH)
        onset_env = librosa.onset.onset_strength(y=segment, sr=sr, hop_length=HOP_LENGTH)
        vec = np.concatenate(
            [
                np.mean(chroma, axis=1),
                np.std(chroma, axis=1),
                np.mean(mfcc, axis=1),
                np.std(mfcc, axis=1),
                np.array(
                    [
                        float(np.mean(onset_env)) if onset_env.size else 0.0,
                        float(np.std(onset_env)) if onset_env.size else 0.0,
                        float(np.max(onset_env)) if onset_env.size else 0.0,
                    ]
                ),
            ]
        )
        features.append(vec)
        windows.append((start / sr, end / sr))
    if len(features) < 2:
        return []

    matrix = normalize_rows(np.vstack(features))
    candidates: list[tuple[float, int, int]] = []
    for i in range(len(windows)):
        for j in range(i + 1, len(windows)):
            if abs(windows[j][0] - windows[i][0]) < min_gap_seconds:
                continue
            score = float(np.dot(matrix[i], matrix[j]))
            if math.isfinite(score):
                candidates.append((score, i, j))
    candidates.sort(reverse=True)
    rows: list[dict[str, Any]] = []
    used: set[tuple[int, int]] = set()
    for score, i, j in candidates:
        if len(rows) >= top_n:
            break
        key = (i, j)
        if key in used:
            continue
        used.add(key)
        rows.append(
            {
                "candidate_id": f"M{len(rows) + 1:03d}",
                "similarity": round(score, 6),
                "window_a": {
                    "start_sec": round_time(windows[i][0], digits),
                    "end_sec": round_time(windows[i][1], digits),
                },
                "window_b": {
                    "start_sec": round_time(windows[j][0], digits),
                    "end_sec": round_time(windows[j][1], digits),
                },
                "evidence_note": "Audio-feature similarity only; Codex must listen before naming hook, motif, or repeated phrase function.",
            }
        )
    return rows


def write_tsv(path: Path, fieldnames: list[str], rows: list[dict[str, Any]]) -> None:
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames, delimiter="\t", extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Extract sub-second beat, onset, pitch-proxy, and motif-candidate evidence from an IDOL audio file."
    )
    parser.add_argument("--audio", required=True, type=Path)
    parser.add_argument("--out-dir", required=True, type=Path)
    parser.add_argument("--prefix", default="audio-precision")
    parser.add_argument("--label", default=None)
    parser.add_argument("--mode", choices=["selected-audio", "reference-audio"], default="selected-audio")
    parser.add_argument("--sample-rate", type=int, default=22050)
    parser.add_argument("--precision", type=int, default=3)
    parser.add_argument("--motif-window-seconds", type=float, default=4.0)
    parser.add_argument("--motif-hop-seconds", type=float, default=2.0)
    parser.add_argument("--motif-min-gap-seconds", type=float, default=8.0)
    parser.add_argument("--top-motif-candidates", type=int, default=40)
    parser.add_argument("--meter-beats", type=int, default=4)
    parser.add_argument("--phase-anchor-seconds", type=float)
    parser.add_argument("--phase-anchor-beat-in-bar", type=int)
    parser.add_argument("--phase-anchor-tolerance", type=float, default=0.08)
    parser.add_argument("--section", action="append", type=parse_window_spec, default=[])
    parser.add_argument("--slot", action="append", type=parse_window_spec, default=[])
    args = parser.parse_args()

    if not 1 <= args.meter_beats <= 32:
        parser.error("--meter-beats must be between 1 and 32")
    if (args.phase_anchor_seconds is None) != (args.phase_anchor_beat_in_bar is None):
        parser.error("phase anchor seconds and beat-in-bar must be supplied together")
    if args.phase_anchor_tolerance <= 0:
        parser.error("--phase-anchor-tolerance must be positive")

    if not args.audio.is_file():
        raise SystemExit(f"audio file not found: {args.audio}")

    args.out_dir.mkdir(parents=True, exist_ok=True)
    y, sr = librosa.load(args.audio, sr=args.sample_rate, mono=True)
    if y.size == 0:
        raise SystemExit(f"audio file is empty or unreadable: {args.audio}")

    duration = float(librosa.get_duration(y=y, sr=sr))
    rms = librosa.feature.rms(y=y, frame_length=2048, hop_length=HOP_LENGTH)[0]
    frame_times = librosa.frames_to_time(np.arange(len(rms)), sr=sr, hop_length=HOP_LENGTH)
    onset_env = librosa.onset.onset_strength(y=y, sr=sr, hop_length=HOP_LENGTH)
    onset_env_times = librosa.frames_to_time(np.arange(len(onset_env)), sr=sr, hop_length=HOP_LENGTH)
    tempo, beat_frames = librosa.beat.beat_track(y=y, sr=sr, hop_length=HOP_LENGTH, start_bpm=129.0, tightness=100)
    beat_times = librosa.frames_to_time(beat_frames, sr=sr, hop_length=HOP_LENGTH)
    beat_intervals = np.diff(beat_times)
    onset_frames = librosa.onset.onset_detect(y=y, sr=sr, hop_length=HOP_LENGTH, units="frames")
    onset_times = librosa.frames_to_time(onset_frames, sr=sr, hop_length=HOP_LENGTH)

    # Additional extraction for current graph-engineering review: hpss separation
    # Allows viewing percussive (rhythm/beat focused) and harmonic (melody/vocal) components together
    # with audio-motion-director-map and other evidence. Useful for combined timing and motion planning.
    y_harmonic, y_percussive = librosa.effects.hpss(y)
    rms_h = librosa.feature.rms(y=y_harmonic, frame_length=2048, hop_length=HOP_LENGTH)[0]
    rms_p = librosa.feature.rms(y=y_percussive, frame_length=2048, hop_length=HOP_LENGTH)[0]

    onset_strengths = []
    for time_value in onset_times:
        idx = int(np.argmin(np.abs(onset_env_times - time_value)))
        onset_strengths.append(float(onset_env[idx]))
    onset_strengths_array = np.asarray(onset_strengths, dtype=float)
    max_onset_strength = float(np.max(onset_strengths_array)) if onset_strengths_array.size else 1.0

    phase_status, phase_origin, phase_anchor_delta = meter_phase(
        beat_times,
        args.meter_beats,
        args.phase_anchor_seconds,
        args.phase_anchor_beat_in_bar,
        args.phase_anchor_tolerance,
    )
    beat_rows = []
    for zero_index, time_value in enumerate(beat_times):
        index = zero_index + 1
        beat_in_bar = ((zero_index - phase_origin) % args.meter_beats) + 1
        beat_rows.append(
            {
                "beat_index": index,
                "time_sec": f"{round_time(float(time_value), args.precision):.{args.precision}f}",
                "bar_index_candidate": int((zero_index - phase_origin) // args.meter_beats) + 1,
                "beat_in_bar": beat_in_bar,
                "phase_status": phase_status,
            }
        )

    onset_rows = []
    for index, (time_value, strength) in enumerate(zip(onset_times, onset_strengths_array), start=1):
        nearest = nearest_beat(float(time_value), beat_times, args.precision)
        onset_rows.append(
            {
                "onset_index": index,
                "time_sec": f"{round_time(float(time_value), args.precision):.{args.precision}f}",
                "strength_norm": f"{round(float(strength / max_onset_strength), 6):.6f}",
                "nearest_beat_index": nearest["beat_index"],
                "nearest_beat_time_sec": nearest["time_sec"],
                "delta_sec": nearest["delta_sec"],
            }
        )

    pitch = pitch_rows(y, sr, HOP_LENGTH, args.precision)
    pitch_tsv_rows = [
        {
            "frame_index": row["frame_index"],
            "time_sec": f"{row['time_sec']:.{args.precision}f}",
            "dominant_pitch_hz": f"{row['dominant_pitch_hz']:.3f}",
            "note_proxy": row["note_proxy"],
            "strength_norm": f"{row['strength_norm']:.6f}",
        }
        for row in pitch
    ]

    motif_rows = motif_candidates(
        y,
        sr,
        args.motif_window_seconds,
        args.motif_hop_seconds,
        args.motif_min_gap_seconds,
        args.top_motif_candidates,
        args.precision,
    )
    motif_tsv_rows = [
        {
            "candidate_id": row["candidate_id"],
            "similarity": row["similarity"],
            "window_a_start_sec": row["window_a"]["start_sec"],
            "window_a_end_sec": row["window_a"]["end_sec"],
            "window_b_start_sec": row["window_b"]["start_sec"],
            "window_b_end_sec": row["window_b"]["end_sec"],
            "evidence_note": row["evidence_note"],
        }
        for row in motif_rows
    ]

    def build_windows(specs: list[tuple[str, float, float]]) -> list[dict[str, Any]]:
        rows = []
        for label, start, end in specs:
            rows.append(
                {
                    "id": label,
                    "start_sec": round_time(start, args.precision),
                    "end_sec": round_time(end, args.precision),
                    "start_nearest_beat": nearest_beat(start, beat_times, args.precision),
                    "end_nearest_beat": nearest_beat(end, beat_times, args.precision),
                    "metrics": window_metrics(
                        start,
                        end,
                        frame_times,
                        rms,
                        onset_env_times,
                        onset_env,
                        onset_times,
                        beat_times,
                        rms_h,
                        rms_p,
                        args.precision,
                    ),
                }
            )
        return rows

    pitch_values = np.asarray([row["dominant_pitch_hz"] for row in pitch], dtype=float)
    pitch_summary = {
        "method": "librosa.piptrack dominant-frequency proxy on full mix",
        "coverage_frames": int(len(pitch)),
        "median_hz": round(float(np.median(pitch_values)), 3) if pitch_values.size else None,
        "p10_hz": round(float(np.percentile(pitch_values, 10)), 3) if pitch_values.size else None,
        "p90_hz": round(float(np.percentile(pitch_values, 90)), 3) if pitch_values.size else None,
        "note": "Pitch proxy is not isolated vocal transcription. Use vocal stem separation or manual listening for stronger vocal-register claims.",
    }

    # Energy-jump and low-energy assist markers for 04FX opportunity seeding.
    energy_jump_candidates: list[dict[str, Any]] = []
    low_energy_hold_windows: list[dict[str, Any]] = []
    if rms.size > 4:
        rms_norm = rms / max(float(np.max(rms)), 1e-8)
        delta = np.diff(rms_norm)
        threshold = float(np.percentile(delta, 92))
        last_t = -999.0
        for idx, value in enumerate(delta):
            if value < threshold:
                continue
            t = float(frame_times[min(idx + 1, len(frame_times) - 1)])
            if t - last_t < 0.35:
                continue
            nearest = nearest_beat(t, beat_times, args.precision)
            energy_jump_candidates.append(
                {
                    "time_sec": round_time(t, args.precision),
                    "delta_norm": round(float(value), 6),
                    "nearest_beat_index": nearest["beat_index"],
                    "nearest_beat_time_sec": nearest["time_sec"],
                    "delta_sec": nearest["delta_sec"],
                }
            )
            last_t = t
        quiet = rms_norm < max(0.12, float(np.percentile(rms_norm, 15)))
        start_idx = None
        for idx, is_quiet in enumerate(quiet):
            if is_quiet and start_idx is None:
                start_idx = idx
            if (not is_quiet or idx == len(quiet) - 1) and start_idx is not None:
                end_idx = idx if not is_quiet else idx
                start_t = float(frame_times[start_idx])
                end_t = float(frame_times[end_idx])
                if end_t - start_t >= 0.45:
                    low_energy_hold_windows.append(
                        {
                            "start_sec": round_time(start_t, args.precision),
                            "end_sec": round_time(end_t, args.precision),
                            "duration_sec": round_time(end_t - start_t, args.precision),
                        }
                    )
                start_idx = None

    perc_onset_env = librosa.onset.onset_strength(y=y_percussive, sr=sr, hop_length=HOP_LENGTH)
    perc_onset_frames = librosa.onset.onset_detect(
        onset_envelope=perc_onset_env, sr=sr, hop_length=HOP_LENGTH, units="frames"
    )
    perc_onset_times = librosa.frames_to_time(perc_onset_frames, sr=sr, hop_length=HOP_LENGTH)
    percussive_onset_markers = []
    for index, time_value in enumerate(perc_onset_times, start=1):
        nearest = nearest_beat(float(time_value), beat_times, args.precision)
        percussive_onset_markers.append(
            {
                "onset_index": index,
                "time_sec": round_time(float(time_value), args.precision),
                "nearest_beat_index": nearest["beat_index"],
                "nearest_beat_time_sec": nearest["time_sec"],
                "delta_sec": nearest["delta_sec"],
            }
        )

    payload = {
        "schema_version": "idol_audio_precision_markers.v1_2",
        "status": "measurement_evidence_only",
        "mode": args.mode,
        "label": args.label or args.audio.stem,
        "source_audio": str(args.audio),
        "precision": {"time_unit": "seconds", "rounded_decimal_places": args.precision},
        "global_metrics": {
            "duration_sec": round_time(duration, args.precision),
            "sample_rate": sr,
            "tempo_bpm": round_time(scalar(tempo) or 0.0, args.precision),
            "detected_beat_count": int(len(beat_rows)),
            "median_beat_interval_sec": round_time(float(np.median(beat_intervals)), args.precision)
            if beat_intervals.size
            else None,
            "beat_interval_cv": round(float(np.std(beat_intervals) / max(np.mean(beat_intervals), 1e-8)), 6)
            if beat_intervals.size
            else None,
            "detected_onset_count": int(len(onset_rows)),
            "detected_percussive_onset_count": int(len(percussive_onset_markers)),
            "energy_jump_candidate_count": int(len(energy_jump_candidates)),
            "low_energy_hold_window_count": int(len(low_energy_hold_windows)),
        },
        "pitch_proxy_summary": pitch_summary,
        "meter_phase": {
            "status": phase_status,
            "meter_beats": args.meter_beats,
            "anchor_seconds": args.phase_anchor_seconds,
            "anchor_beat_in_bar": args.phase_anchor_beat_in_bar,
            "nearest_detected_beat_delta_seconds": (
                round_time(phase_anchor_delta, args.precision)
                if phase_anchor_delta is not None
                else None
            ),
            "use_rule": (
                "Only manual_locked phase may be treated as bar-position evidence; "
                "unverified candidates cannot justify an automatic transition."
            ),
        },
        "sections": build_windows(args.section),
        "slots": build_windows(args.slot),
        "bar_start_candidate_markers": (
            [row for row in beat_rows if row["beat_in_bar"] == 1]
            if phase_status == "unverified_candidate"
            else []
        ),
        "beat_2_4_phase_candidate_markers": (
            [row for row in beat_rows if int(row["beat_in_bar"]) in {2, 4}]
            if phase_status == "unverified_candidate" and args.meter_beats >= 4
            else []
        ),
        "bar_start_locked_markers": (
            [row for row in beat_rows if row["beat_in_bar"] == 1]
            if phase_status == "manual_locked"
            else []
        ),
        "beat_2_4_phase_locked_markers": (
            [row for row in beat_rows if int(row["beat_in_bar"]) in {2, 4}]
            if phase_status == "manual_locked" and args.meter_beats >= 4
            else []
        ),
        "bar_markers_4beat": [row for row in beat_rows if row["beat_in_bar"] == 1]
        if args.meter_beats == 4
        else [],
        "backbeat_markers_4beat": [row for row in beat_rows if int(row["beat_in_bar"]) in {2, 4}]
        if args.meter_beats == 4
        else [],
        "legacy_phase_warning": (
            "bar_markers_4beat/backbeat_markers_4beat are compatibility aliases. "
            "When phase is unverified they reflect a first-detected-beat candidate, "
            "not a confirmed bar start or acoustic backbeat."
        ),
        "top_onset_markers": sorted(
            [
                {
                    "onset_index": int(row["onset_index"]),
                    "time_sec": float(row["time_sec"]),
                    "strength_norm": float(row["strength_norm"]),
                    "nearest_beat_index": row["nearest_beat_index"],
                    "nearest_beat_time_sec": row["nearest_beat_time_sec"],
                    "delta_sec": row["delta_sec"],
                }
                for row in onset_rows
            ],
            key=lambda row: row["strength_norm"],
            reverse=True,
        )[:200],
        "percussive_onset_markers": percussive_onset_markers[:200],
        "energy_jump_candidates": energy_jump_candidates[:100],
        "low_energy_hold_windows": low_energy_hold_windows[:100],
        "motif_repetition_candidates": motif_rows,
        "mode_policy": {
            "selected_audio": "May feed selected-audio analysis, audio-motion director map, track creative board, 00/00A, 01/02A, edit marker planning, and 04FX transition-opportunity seeding after human review.",
            "reference_audio": "May feed reference-song fit, Suno prompt planning, motif/hook analysis, vocal/pitch evidence, and source lineage. Do not produce cut pressure scores or MV section video functions from reference audio alone.",
        },
        "assist_policy": {
            "allowed_use": [
                "bpm_candidate_evidence",
                "beat_grid_evidence",
                "onset_cluster_evidence",
                "pitch_contour_proxy_evidence",
                "motif_repetition_candidate_evidence",
                "precision_edit_marker_evidence",
                "04fx_transition_opportunity_seed",
            ],
            "not_allowed_to_lock": [
                "source_in",
                "source_out",
                "speed_factor",
                "final_cutpoint",
                "final_candidate_selection",
                "founder_pass_fail",
            ],
        },
        "human_review_required": True,
        "sidecar_files": {
            "beat_grid_tsv": str(args.out_dir / f"{args.prefix}-beat-grid.tsv"),
            "onset_candidates_tsv": str(args.out_dir / f"{args.prefix}-onset-candidates.tsv"),
            "pitch_contour_tsv": str(args.out_dir / f"{args.prefix}-pitch-contour.tsv"),
            "motif_candidates_tsv": str(args.out_dir / f"{args.prefix}-motif-candidates.tsv"),
        },
    }

    json_path = args.out_dir / f"{args.prefix}-marker-map.json"
    json_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n")
    write_tsv(
        args.out_dir / f"{args.prefix}-beat-grid.tsv",
        ["beat_index", "time_sec", "bar_index_candidate", "beat_in_bar", "phase_status"],
        beat_rows,
    )
    write_tsv(
        args.out_dir / f"{args.prefix}-onset-candidates.tsv",
        ["onset_index", "time_sec", "strength_norm", "nearest_beat_index", "nearest_beat_time_sec", "delta_sec"],
        onset_rows,
    )
    write_tsv(
        args.out_dir / f"{args.prefix}-pitch-contour.tsv",
        ["frame_index", "time_sec", "dominant_pitch_hz", "note_proxy", "strength_norm"],
        pitch_tsv_rows,
    )
    write_tsv(
        args.out_dir / f"{args.prefix}-motif-candidates.tsv",
        [
            "candidate_id",
            "similarity",
            "window_a_start_sec",
            "window_a_end_sec",
            "window_b_start_sec",
            "window_b_end_sec",
            "evidence_note",
        ],
        motif_tsv_rows,
    )
    print(json_path)


if __name__ == "__main__":
    main()
