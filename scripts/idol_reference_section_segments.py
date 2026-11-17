from __future__ import annotations

import argparse
import json
from pathlib import Path

import librosa
import numpy as np


HOP_LENGTH = 512


def scalar(value):
    arr = np.asarray(value)
    if arr.shape == ():
        return float(arr)
    if arr.size == 0:
        return None
    return float(arr.reshape(-1)[0])


def normalize_rows(matrix: np.ndarray) -> np.ndarray:
    means = np.mean(matrix, axis=1, keepdims=True)
    stds = np.std(matrix, axis=1, keepdims=True)
    return (matrix - means) / np.maximum(stds, 1e-8)


def smooth(values: np.ndarray, width: int) -> np.ndarray:
    if width <= 1 or values.size == 0:
        return values
    kernel = np.ones(width, dtype=float) / float(width)
    return np.convolve(values, kernel, mode="same")


def choose_boundaries(novelty: np.ndarray, frame_times: np.ndarray, duration: float, target_segments: int):
    if novelty.size == 0:
        return [0.0, duration]

    min_spacing = 10.0 if duration < 120 else 14.0
    guard = 7.5
    target_boundaries = max(0, target_segments - 1)
    candidates = []

    for idx in range(1, novelty.size - 1):
        t = float(frame_times[min(idx, len(frame_times) - 1)])
        if t < guard or t > duration - guard:
            continue
        if novelty[idx] >= novelty[idx - 1] and novelty[idx] >= novelty[idx + 1]:
            candidates.append((float(novelty[idx]), t))

    candidates.sort(reverse=True)
    selected = []
    for score, t in candidates:
        if len(selected) >= target_boundaries:
            break
        if all(abs(t - existing) >= min_spacing for existing in selected):
            selected.append(t)

    boundaries = [0.0] + sorted(selected) + [duration]

    # Remove accidental tiny sections.
    cleaned = [boundaries[0]]
    for boundary in boundaries[1:-1]:
        if boundary - cleaned[-1] >= min_spacing and duration - boundary >= min_spacing:
            cleaned.append(boundary)
    cleaned.append(duration)

    return cleaned


def segment_measurement_bucket(index: int, total: int, energy_rank: int, onset_rank: int) -> str:
    if index == 0:
        return "opening_window"
    if index == total - 1:
        return "final_window"
    if energy_rank <= 2 and onset_rank <= 3:
        return "high_energy_high_onset_window"
    if index in (1, 2) and energy_rank > 2:
        return "early_lower_energy_window"
    if index >= total - 3 and energy_rank <= 4:
        return "late_higher_energy_window"
    if energy_rank >= max(4, total - 2):
        return "lower_energy_window"
    return "mid_track_measurement_window"


def segment_metrics(y: np.ndarray, sr: int, start: float, end: float):
    start_sample = max(0, int(start * sr))
    end_sample = min(len(y), int(end * sr))
    segment = y[start_sample:end_sample]
    duration = max((end_sample - start_sample) / sr, 1e-8)
    if segment.size < sr:
        return {
            "mean_rms": None,
            "peak_rms": None,
            "onsets_per_second": None,
            "mean_spectral_centroid": None,
        }

    rms = librosa.feature.rms(y=segment, frame_length=2048, hop_length=HOP_LENGTH)[0]
    onset_env = librosa.onset.onset_strength(y=segment, sr=sr, hop_length=HOP_LENGTH)
    onset_events = librosa.onset.onset_detect(onset_envelope=onset_env, sr=sr, hop_length=HOP_LENGTH, units="time")
    centroid = librosa.feature.spectral_centroid(y=segment, sr=sr, hop_length=HOP_LENGTH)[0]

    return {
        "mean_rms": round(float(np.mean(rms)), 6),
        "peak_rms": round(float(np.max(rms)), 6),
        "onsets_per_second": round(float(len(onset_events) / duration), 3),
        "mean_spectral_centroid": round(float(np.mean(centroid)), 3),
    }


def analyze_file(path: Path):
    y, sr = librosa.load(path, sr=22050, mono=True)
    duration = float(librosa.get_duration(y=y, sr=sr))
    onset_env = librosa.onset.onset_strength(y=y, sr=sr, hop_length=HOP_LENGTH)
    tempo, beats = librosa.beat.beat_track(onset_envelope=onset_env, sr=sr, hop_length=HOP_LENGTH)
    tempo_value = scalar(tempo)

    rms = librosa.feature.rms(y=y, frame_length=2048, hop_length=HOP_LENGTH)[0]
    centroid = librosa.feature.spectral_centroid(y=y, sr=sr, hop_length=HOP_LENGTH)[0]
    rolloff = librosa.feature.spectral_rolloff(y=y, sr=sr, hop_length=HOP_LENGTH)[0]
    chroma = librosa.feature.chroma_stft(y=y, sr=sr, hop_length=HOP_LENGTH)
    mfcc = librosa.feature.mfcc(y=y, sr=sr, hop_length=HOP_LENGTH, n_mfcc=8)

    min_frames = min(rms.size, onset_env.size, centroid.size, rolloff.size, chroma.shape[1], mfcc.shape[1])
    features = np.vstack(
        [
            rms[:min_frames],
            onset_env[:min_frames],
            centroid[:min_frames],
            rolloff[:min_frames],
            chroma[:, :min_frames],
            mfcc[:, :min_frames],
        ]
    )
    features = normalize_rows(features)
    lag = max(1, int(round(sr / HOP_LENGTH)))
    padded = np.pad(features, ((0, 0), (lag, 0)), mode="edge")[:, :min_frames]
    novelty = np.linalg.norm(features - padded, axis=0)
    novelty = smooth(novelty, max(3, int(round((sr / HOP_LENGTH) * 1.5))))
    frame_times = librosa.frames_to_time(np.arange(min_frames), sr=sr, hop_length=HOP_LENGTH)

    target_segments = int(np.clip(round(duration / 25.0), 6, 10))
    boundaries = choose_boundaries(novelty, frame_times, duration, target_segments)

    raw_sections = []
    for idx in range(len(boundaries) - 1):
        start = float(boundaries[idx])
        end = float(boundaries[idx + 1])
        metrics = segment_metrics(y, sr, start, end)
        raw_sections.append(
            {
                "id": f"S{idx:02d}",
                "start": round(start, 2),
                "end": round(end, 2),
                "duration_seconds": round(end - start, 2),
                **metrics,
            }
        )

    energy_sorted = sorted(raw_sections, key=lambda row: row["mean_rms"] or 0, reverse=True)
    onset_sorted = sorted(raw_sections, key=lambda row: row["onsets_per_second"] or 0, reverse=True)
    energy_rank = {row["id"]: idx + 1 for idx, row in enumerate(energy_sorted)}
    onset_rank = {row["id"]: idx + 1 for idx, row in enumerate(onset_sorted)}

    sections = []
    for idx, row in enumerate(raw_sections):
        e_rank = energy_rank[row["id"]]
        o_rank = onset_rank[row["id"]]
        sections.append(
            {
                **row,
                "energy_rank": e_rank,
                "onset_density_rank": o_rank,
                "measurement_bucket": segment_measurement_bucket(idx, len(raw_sections), e_rank, o_rank),
                "listening_check_required": True,
            }
        )

    result = {
        "file": str(path),
        "duration_seconds": round(duration, 3),
        "estimated_tempo_bpm": round(float(tempo_value), 3) if tempo_value else None,
        "target_segment_count": target_segments,
        "actual_segment_count": len(sections),
        "method_note": "Automatic whole-track reference segmentation from RMS, onset, spectral, chroma, and MFCC novelty. Buckets are measurement labels only, not section-function decisions; selected-audio analysis still requires full listening and lyric/transcript review.",
        "section_candidates": sections,
    }

    info_path = path.with_suffix(".info.json")
    if info_path.exists():
        with info_path.open("r", encoding="utf-8") as fh:
            info = json.load(fh)
        result["bilibili"] = {
            "id": info.get("id"),
            "display_id": info.get("display_id"),
            "title": info.get("title"),
            "uploader": info.get("uploader"),
            "webpage_url": info.get("webpage_url"),
            "duration": info.get("duration"),
            "upload_date": info.get("upload_date"),
        }

    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--audio-dir", required=True)
    parser.add_argument("--out", required=True)
    args = parser.parse_args()

    audio_dir = Path(args.audio_dir)
    results = [analyze_file(path) for path in sorted(audio_dir.glob("REF_*.m4a"))]

    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("w", encoding="utf-8") as fh:
        json.dump(
            {
                "schema": "idol_reference_section_segments.v1",
                "analysis_count": len(results),
                "results": results,
            },
            fh,
            indent=2,
            ensure_ascii=False,
        )


if __name__ == "__main__":
    main()
