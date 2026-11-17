from __future__ import annotations

import argparse
import json
from pathlib import Path

import librosa
import numpy as np


def scalar(value):
    arr = np.asarray(value)
    if arr.shape == ():
        return float(arr)
    if arr.size == 0:
        return None
    return float(arr.reshape(-1)[0])


def top_windows(y: np.ndarray, sr: int, win_seconds: int = 15, limit: int = 4):
    rows = []
    hop = int(sr * win_seconds)
    if hop <= 0:
        return rows
    for start in range(0, len(y), hop):
        end = min(len(y), start + hop)
        segment = y[start:end]
        if len(segment) < sr * 3:
            continue
        rms = librosa.feature.rms(y=segment, frame_length=2048, hop_length=512)[0]
        onset = librosa.onset.onset_strength(y=segment, sr=sr)
        duration = (end - start) / sr
        rows.append(
            {
                "start": round(start / sr, 2),
                "end": round(end / sr, 2),
                "mean_rms": round(float(np.mean(rms)), 6),
                "peak_rms": round(float(np.max(rms)), 6),
                "onset_mean": round(float(np.mean(onset)), 6),
                "onset_peak": round(float(np.max(onset)), 6),
                "onsets_per_second": round(
                    float(np.count_nonzero(onset > np.mean(onset) + np.std(onset)) / duration), 3
                ),
            }
        )
    return sorted(rows, key=lambda row: (row["mean_rms"], row["onset_mean"]), reverse=True)[:limit]


def band_energy(y: np.ndarray, sr: int):
    stft = np.abs(librosa.stft(y, n_fft=2048, hop_length=512)) ** 2
    freqs = librosa.fft_frequencies(sr=sr, n_fft=2048)
    total = float(np.sum(stft)) or 1.0
    bands = {
        "sub_20_80hz": (20, 80),
        "bass_80_250hz": (80, 250),
        "low_mid_250_500hz": (250, 500),
        "mid_500_2000hz": (500, 2000),
        "presence_2000_6000hz": (2000, 6000),
        "air_6000_11025hz": (6000, sr / 2),
    }
    out = {}
    for name, (low, high) in bands.items():
        mask = (freqs >= low) & (freqs < high)
        out[name] = round(float(np.sum(stft[mask, :]) / total), 6)
    return out


def analyze_file(path: Path):
    y, sr = librosa.load(path, sr=22050, mono=True)
    duration = librosa.get_duration(y=y, sr=sr)
    onset_env = librosa.onset.onset_strength(y=y, sr=sr)
    tempo, beats = librosa.beat.beat_track(onset_envelope=onset_env, sr=sr)
    tempo_value = scalar(tempo)
    beat_times = librosa.frames_to_time(beats, sr=sr)
    rms = librosa.feature.rms(y=y, frame_length=2048, hop_length=512)[0]
    centroid = librosa.feature.spectral_centroid(y=y, sr=sr)[0]
    rolloff = librosa.feature.spectral_rolloff(y=y, sr=sr)[0]
    zcr = librosa.feature.zero_crossing_rate(y, frame_length=2048, hop_length=512)[0]
    onset_events = librosa.onset.onset_detect(onset_envelope=onset_env, sr=sr, units="time")
    harmonic, percussive = librosa.effects.hpss(y)
    harmonic_rms = librosa.feature.rms(y=harmonic, frame_length=2048, hop_length=512)[0]
    percussive_rms = librosa.feature.rms(y=percussive, frame_length=2048, hop_length=512)[0]
    h_mean = float(np.mean(harmonic_rms))
    p_mean = float(np.mean(percussive_rms))

    beat_intervals = np.diff(beat_times) if len(beat_times) > 1 else np.array([])
    beat_stability = None
    if beat_intervals.size:
        beat_stability = float(np.std(beat_intervals) / max(np.mean(beat_intervals), 1e-6))

    result = {
        "file": str(path),
        "duration_seconds": round(float(duration), 3),
        "estimated_tempo_bpm": round(float(tempo_value), 3) if tempo_value else None,
        "tempo_source": "librosa beat_track estimate from extracted Bilibili reference audio",
        "beat_count": int(len(beats)),
        "beat_stability_cv": round(beat_stability, 4) if beat_stability is not None else None,
        "onset_count": int(len(onset_events)),
        "onsets_per_second": round(float(len(onset_events) / duration), 3) if duration else None,
        "mean_rms": round(float(np.mean(rms)), 6),
        "peak_rms": round(float(np.max(rms)), 6),
        "mean_spectral_centroid": round(float(np.mean(centroid)), 3),
        "mean_spectral_rolloff": round(float(np.mean(rolloff)), 3),
        "mean_zero_crossing_rate": round(float(np.mean(zcr)), 6),
        "percussive_to_harmonic_rms_ratio": round(p_mean / max(h_mean, 1e-8), 4),
        "band_energy_share": band_energy(y, sr),
        "top_15s_windows": top_windows(y, sr),
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
            "view_count": info.get("view_count"),
            "like_count": info.get("like_count"),
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
                "analysis_count": len(results),
                "method_note": (
                    "Measurement-only reference-audio metrics. These values do not decide song fit, section function, "
                    "arrangement, instrument use, melody, or prompt wording."
                ),
                "results": results,
            },
            fh,
            indent=2,
            ensure_ascii=False,
        )


if __name__ == "__main__":
    main()
