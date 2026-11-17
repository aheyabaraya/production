from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

import librosa
import numpy as np


HOP_LENGTH = 512
N_FFT = 4096
BANDS = {
    "sub_20_60hz": (20, 60),
    "kick_body_60_120hz": (60, 120),
    "bass_low_mid_120_250hz": (120, 250),
    "low_mid_250_500hz": (250, 500),
    "vocal_body_500_2000hz": (500, 2000),
    "presence_2000_5000hz": (2000, 5000),
    "snap_hat_5000_8000hz": (5000, 8000),
    "air_8000_16000hz": (8000, 16000),
}


def scalar(value: Any) -> float | None:
    arr = np.asarray(value)
    if arr.shape == ():
        return float(arr)
    if arr.size == 0:
        return None
    return float(arr.reshape(-1)[0])


def safe_round(value: float | None, digits: int = 6) -> float | None:
    if value is None or not np.isfinite(value):
        return None
    return round(float(value), digits)


def load_audio(path: Path, sample_rate: int) -> tuple[np.ndarray, int]:
    if not path.is_file():
        raise FileNotFoundError(f"audio file not found: {path}")
    y, sr = librosa.load(path, sr=sample_rate, mono=True)
    if y.size == 0:
        raise ValueError(f"audio file is empty or unreadable: {path}")
    return y, sr


def stft_power(y: np.ndarray, sr: int) -> tuple[np.ndarray, np.ndarray]:
    power = np.abs(librosa.stft(y, n_fft=N_FFT, hop_length=HOP_LENGTH)) ** 2
    freqs = librosa.fft_frequencies(sr=sr, n_fft=N_FFT)
    return power, freqs


def band_energy_share(y: np.ndarray, sr: int) -> dict[str, float]:
    power, freqs = stft_power(y, sr)
    total = float(np.sum(power)) or 1.0
    rows = {}
    for name, (low, high) in BANDS.items():
        high = min(high, sr / 2)
        mask = (freqs >= low) & (freqs < high)
        rows[name] = round(float(np.sum(power[mask, :]) / total), 6) if np.any(mask) else 0.0
    return rows


def percussive_band_hit_density(y: np.ndarray, sr: int, duration: float) -> dict[str, dict[str, float | int]]:
    _harmonic, percussive = librosa.effects.hpss(y)
    power, freqs = stft_power(percussive, sr)
    rows: dict[str, dict[str, float | int]] = {}
    for name, (low, high) in BANDS.items():
        high = min(high, sr / 2)
        mask = (freqs >= low) & (freqs < high)
        if not np.any(mask):
            continue
        envelope = np.mean(power[mask, :], axis=0)
        if np.max(envelope) > 0:
            envelope = librosa.util.normalize(envelope)
        threshold = float(np.mean(envelope) + np.std(envelope))
        hit_frames = int(np.count_nonzero(envelope > threshold))
        rows[name] = {
            "hit_frames": hit_frames,
            "hit_frames_per_second": round(hit_frames / max(duration, 1e-6), 3),
            "mean": round(float(np.mean(envelope)), 6),
            "peak": round(float(np.max(envelope)), 6),
        }
    return rows


def pitch_proxy(y: np.ndarray, sr: int) -> dict[str, float | str | None]:
    pitches, magnitudes = librosa.piptrack(y=y, sr=sr, n_fft=2048, hop_length=HOP_LENGTH)
    if pitches.size == 0:
        return {
            "method": "librosa.piptrack_dominant_frequency_proxy",
            "median_hz": None,
            "mean_hz": None,
            "std_hz": None,
            "slope_hz_per_second": None,
            "coverage": 0.0,
            "note": "No dominant pitch proxy frames detected.",
        }

    frame_indices = np.arange(pitches.shape[1])
    max_bins = np.argmax(magnitudes, axis=0)
    values = pitches[max_bins, frame_indices]
    valid = values > 0
    valid_values = values[valid]
    if valid_values.size < 3:
        return {
            "method": "librosa.piptrack_dominant_frequency_proxy",
            "median_hz": None,
            "mean_hz": None,
            "std_hz": None,
            "slope_hz_per_second": None,
            "coverage": round(float(np.count_nonzero(valid) / max(values.size, 1)), 4),
            "note": "Too few dominant pitch proxy frames for a stable contour read.",
        }

    times = librosa.frames_to_time(frame_indices[valid], sr=sr, hop_length=HOP_LENGTH)
    slope = None
    if times.size >= 3 and np.ptp(times) > 0:
        slope = float(np.polyfit(times, valid_values, 1)[0])
    return {
        "method": "librosa.piptrack_dominant_frequency_proxy",
        "median_hz": safe_round(float(np.median(valid_values)), 3),
        "mean_hz": safe_round(float(np.mean(valid_values)), 3),
        "std_hz": safe_round(float(np.std(valid_values)), 3),
        "slope_hz_per_second": safe_round(slope, 6),
        "coverage": round(float(valid_values.size / max(values.size, 1)), 4),
        "note": "Polyphonic dominant-frequency proxy only. Codex must listen and write the melody/topline function.",
    }


def chroma_summary(y: np.ndarray, sr: int) -> dict[str, float | str | None]:
    chroma = librosa.feature.chroma_cqt(y=y, sr=sr, hop_length=HOP_LENGTH)
    if chroma.size == 0:
        return {
            "dominant_chroma": None,
            "chroma_change_mean": None,
            "chroma_change_peak": None,
            "note": "No chroma proxy available.",
        }
    names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    means = np.mean(chroma, axis=1)
    deltas = np.linalg.norm(np.diff(chroma, axis=1), axis=0) if chroma.shape[1] > 1 else np.array([])
    return {
        "dominant_chroma": names[int(np.argmax(means))],
        "chroma_change_mean": safe_round(float(np.mean(deltas)), 6) if deltas.size else None,
        "chroma_change_peak": safe_round(float(np.max(deltas)), 6) if deltas.size else None,
        "note": "Chroma proxy only. It is evidence for harmony/topline listening, not a key or chord decision.",
    }


def window_features(y: np.ndarray, sr: int, window_seconds: float) -> list[dict[str, Any]]:
    rows = []
    hop = int(sr * window_seconds)
    if hop <= 0:
        return rows
    for start in range(0, len(y), hop):
        end = min(len(y), start + hop)
        segment = y[start:end]
        if len(segment) < sr * 3:
            continue
        duration = (end - start) / sr
        rms = librosa.feature.rms(y=segment, frame_length=2048, hop_length=HOP_LENGTH)[0]
        onset_env = librosa.onset.onset_strength(y=segment, sr=sr, hop_length=HOP_LENGTH)
        harmonic, percussive = librosa.effects.hpss(segment)
        h_rms = np.mean(librosa.feature.rms(y=harmonic, frame_length=2048, hop_length=HOP_LENGTH)[0])
        p_rms = np.mean(librosa.feature.rms(y=percussive, frame_length=2048, hop_length=HOP_LENGTH)[0])
        rows.append(
            {
                "start": round(start / sr, 2),
                "end": round(end / sr, 2),
                "duration_seconds": round(duration, 2),
                "mean_rms": round(float(np.mean(rms)), 6),
                "peak_rms": round(float(np.max(rms)), 6),
                "onset_mean": round(float(np.mean(onset_env)), 6),
                "onset_peak": round(float(np.max(onset_env)), 6),
                "onsets_per_second": round(
                    float(np.count_nonzero(onset_env > np.mean(onset_env) + np.std(onset_env)) / max(duration, 1e-6)),
                    3,
                ),
                "percussive_to_harmonic_rms_ratio": round(float(p_rms / max(h_rms, 1e-8)), 4),
                "band_energy_share": band_energy_share(segment, sr),
                "pitch_proxy": pitch_proxy(segment, sr),
                "chroma_proxy": chroma_summary(segment, sr),
            }
        )
    return rows


def analyze_track(label: str, path: Path, sample_rate: int, window_seconds: float) -> dict[str, Any]:
    y, sr = load_audio(path, sample_rate)
    duration = float(librosa.get_duration(y=y, sr=sr))
    onset_env = librosa.onset.onset_strength(y=y, sr=sr, hop_length=HOP_LENGTH)
    tempo, beats = librosa.beat.beat_track(onset_envelope=onset_env, sr=sr, hop_length=HOP_LENGTH)
    beat_times = librosa.frames_to_time(beats, sr=sr, hop_length=HOP_LENGTH)
    beat_intervals = np.diff(beat_times) if beat_times.size > 1 else np.array([])
    rms = librosa.feature.rms(y=y, frame_length=2048, hop_length=HOP_LENGTH)[0]
    centroid = librosa.feature.spectral_centroid(y=y, sr=sr, hop_length=HOP_LENGTH)[0]
    rolloff = librosa.feature.spectral_rolloff(y=y, sr=sr, hop_length=HOP_LENGTH)[0]
    zcr = librosa.feature.zero_crossing_rate(y, frame_length=2048, hop_length=HOP_LENGTH)[0]
    harmonic, percussive = librosa.effects.hpss(y)
    h_rms = np.mean(librosa.feature.rms(y=harmonic, frame_length=2048, hop_length=HOP_LENGTH)[0])
    p_rms = np.mean(librosa.feature.rms(y=percussive, frame_length=2048, hop_length=HOP_LENGTH)[0])
    onset_events = librosa.onset.onset_detect(onset_envelope=onset_env, sr=sr, hop_length=HOP_LENGTH, units="time")
    windows = window_features(y, sr, window_seconds)
    top_windows = sorted(
        windows,
        key=lambda row: (row["mean_rms"], row["onset_mean"], row["onsets_per_second"]),
        reverse=True,
    )[:8]

    return {
        "label": label,
        "path": str(path),
        "duration_seconds": round(duration, 3),
        "sample_rate": sr,
        "estimated_tempo_bpm": safe_round(scalar(tempo), 3),
        "tempo_source": "librosa beat_track estimate; use as evidence only",
        "beat_count": int(len(beats)),
        "beat_stability_cv": safe_round(float(np.std(beat_intervals) / max(np.mean(beat_intervals), 1e-8)), 4)
        if beat_intervals.size
        else None,
        "onset_count": int(len(onset_events)),
        "onsets_per_second": round(float(len(onset_events) / max(duration, 1e-6)), 3),
        "mean_rms": round(float(np.mean(rms)), 6),
        "peak_rms": round(float(np.max(rms)), 6),
        "mean_spectral_centroid": round(float(np.mean(centroid)), 3),
        "mean_spectral_rolloff": round(float(np.mean(rolloff)), 3),
        "mean_zero_crossing_rate": round(float(np.mean(zcr)), 6),
        "percussive_to_harmonic_rms_ratio": round(float(p_rms / max(h_rms, 1e-8)), 4),
        "band_energy_share": band_energy_share(y, sr),
        "percussive_band_hit_density": percussive_band_hit_density(y, sr, duration),
        "pitch_proxy": pitch_proxy(y, sr),
        "chroma_proxy": chroma_summary(y, sr),
        "top_active_windows": top_windows,
        "method_note": (
            "Extraction-only reference music features. These numbers do not identify instruments, "
            "write melody analysis, decide song fit, or produce Suno prompt wording. Codex/human "
            "listening must write arrangement_instrumentation_fit and melody_topline_fit."
        ),
    }


def markdown_report(payload: dict[str, Any]) -> str:
    lines = [
        "# Reference Music Feature Extract",
        "",
        payload["method_note"],
        "",
    ]
    for result in payload["results"]:
        lines.extend(
            [
                f"## {result['label']}",
                "",
                f"- source: `{result['path']}`",
                f"- duration: `{result['duration_seconds']}s`",
                f"- estimated_tempo_bpm: `{result['estimated_tempo_bpm']}`",
                f"- onsets_per_second: `{result['onsets_per_second']}`",
                f"- percussive_to_harmonic_rms_ratio: `{result['percussive_to_harmonic_rms_ratio']}`",
                f"- pitch_proxy_median_hz: `{result['pitch_proxy']['median_hz']}`",
                f"- pitch_proxy_slope_hz_per_second: `{result['pitch_proxy']['slope_hz_per_second']}`",
                f"- dominant_chroma_proxy: `{result['chroma_proxy']['dominant_chroma']}`",
                "",
                "### Band Energy Share",
                "",
            ]
        )
        for key, value in result["band_energy_share"].items():
            lines.append(f"- `{key}`: `{value}`")
        lines.extend(["", "### Top Active Windows", ""])
        for row in result["top_active_windows"]:
            low = row["band_energy_share"]["kick_body_60_120hz"] + row["band_energy_share"]["bass_low_mid_120_250hz"]
            high = row["band_energy_share"]["snap_hat_5000_8000hz"] + row["band_energy_share"]["air_8000_16000hz"]
            lines.append(
                f"- `{row['start']}-{row['end']}s`: rms `{row['mean_rms']}`, onset `{row['onset_mean']}`, "
                f"onsets/sec `{row['onsets_per_second']}`, perc/harm `{row['percussive_to_harmonic_rms_ratio']}`, "
                f"low `{low:.3f}`, high `{high:.3f}`, pitch median `{row['pitch_proxy']['median_hz']}`"
            )
        lines.append("")
    return "\n".join(lines)


def parse_track(value: str) -> tuple[str, Path]:
    if "=" not in value:
        raise argparse.ArgumentTypeError("track must be LABEL=/path/to/audio")
    label, raw_path = value.split("=", 1)
    label = label.strip()
    if not label:
        raise argparse.ArgumentTypeError("track label must not be blank")
    return label, Path(raw_path)


def discover_tracks(audio_dir: Path, pattern: str) -> list[tuple[str, Path]]:
    return [(path.stem, path) for path in sorted(audio_dir.glob(pattern)) if path.is_file()]


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Extract reference-song audio features for human/Codex arrangement and melody analysis."
    )
    parser.add_argument("--track", action="append", type=parse_track, default=[], help="LABEL=/path/to/audio")
    parser.add_argument("--audio-dir", type=Path, help="Optional directory of reference audio files.")
    parser.add_argument("--pattern", default="REF_*.*", help="Glob pattern used with --audio-dir.")
    parser.add_argument("--out-json", required=True, type=Path)
    parser.add_argument("--out-md", type=Path)
    parser.add_argument("--sample-rate", type=int, default=22050)
    parser.add_argument("--window-seconds", type=float, default=15.0)
    args = parser.parse_args()

    tracks = list(args.track)
    if args.audio_dir:
        tracks.extend(discover_tracks(args.audio_dir, args.pattern))
    if not tracks:
        parser.error("provide at least one --track or --audio-dir")

    results = [analyze_track(label, path, args.sample_rate, args.window_seconds) for label, path in tracks]
    payload = {
        "schema": "idol_reference_music_feature_extract.v1",
        "analysis_count": len(results),
        "method_note": (
            "Extraction-only reference music features. Scripts may support speed and evidence collection, "
            "but arrangement, instrument-use, melody, topline, meaning, and prompt decisions remain Codex/human analysis."
        ),
        "results": results,
    }

    args.out_json.parent.mkdir(parents=True, exist_ok=True)
    args.out_json.write_text(json.dumps(payload, indent=2, ensure_ascii=False), encoding="utf-8")
    if args.out_md:
        args.out_md.parent.mkdir(parents=True, exist_ok=True)
        args.out_md.write_text(markdown_report(payload), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
