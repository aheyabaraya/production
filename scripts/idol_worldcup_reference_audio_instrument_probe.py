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


BANDS = {
    "sub_weight_20_60": (20, 60),
    "kick_body_60_120": (60, 120),
    "bass_drum_120_250": (120, 250),
    "low_mid_250_500": (250, 500),
    "vocal_body_500_2000": (500, 2000),
    "presence_clap_2000_5000": (2000, 5000),
    "snap_hat_5000_8000": (5000, 8000),
    "air_shaker_8000_16000": (8000, 16000),
}


def stft_power(y: np.ndarray, sr: int):
    n_fft = 4096
    hop = 512
    power = np.abs(librosa.stft(y, n_fft=n_fft, hop_length=hop)) ** 2
    freqs = librosa.fft_frequencies(sr=sr, n_fft=n_fft)
    return power, freqs


def band_shares(y: np.ndarray, sr: int) -> dict[str, float]:
    power, freqs = stft_power(y, sr)
    total = float(np.sum(power)) or 1.0
    out = {}
    for name, (low, high) in BANDS.items():
        high = min(high, sr / 2)
        mask = (freqs >= low) & (freqs < high)
        out[name] = round(float(np.sum(power[mask, :]) / total), 6)
    return out


def band_onsets(y: np.ndarray, sr: int) -> dict[str, dict[str, float | int]]:
    y_perc = librosa.effects.hpss(y)[1]
    power, freqs = stft_power(y_perc, sr)
    out = {}
    for name, (low, high) in BANDS.items():
        high = min(high, sr / 2)
        mask = (freqs >= low) & (freqs < high)
        if not np.any(mask):
            continue
        envelope = np.mean(power[mask, :], axis=0)
        envelope = librosa.util.normalize(envelope)
        threshold = float(np.mean(envelope) + np.std(envelope))
        duration = librosa.get_duration(y=y, sr=sr)
        hit_count = int(np.count_nonzero(envelope > threshold))
        out[name] = {
            "hit_frames": hit_count,
            "hit_frames_per_second": round(hit_count / max(duration, 1e-6), 3),
            "mean": round(float(np.mean(envelope)), 6),
            "peak": round(float(np.max(envelope)), 6),
        }
    return out


def window_rows(y: np.ndarray, sr: int, seconds: float) -> list[dict[str, object]]:
    rows = []
    hop = int(sr * seconds)
    if hop <= 0:
        return rows
    for start in range(0, len(y), hop):
        end = min(len(y), start + hop)
        segment = y[start:end]
        if len(segment) < sr * 4:
            continue
        onset = librosa.onset.onset_strength(y=segment, sr=sr)
        harmonic, percussive = librosa.effects.hpss(segment)
        h_rms = np.mean(librosa.feature.rms(y=harmonic, frame_length=2048, hop_length=512)[0])
        p_rms = np.mean(librosa.feature.rms(y=percussive, frame_length=2048, hop_length=512)[0])
        rms = librosa.feature.rms(y=segment, frame_length=2048, hop_length=512)[0]
        shares = band_shares(segment, sr)
        rows.append(
            {
                "start": round(start / sr, 2),
                "end": round(end / sr, 2),
                "mean_rms": round(float(np.mean(rms)), 6),
                "onset_mean": round(float(np.mean(onset)), 6),
                "onsets_per_second": round(
                    float(np.count_nonzero(onset > np.mean(onset) + np.std(onset)) / max((end - start) / sr, 1e-6)),
                    3,
                ),
                "percussive_to_harmonic_rms_ratio": round(float(p_rms / max(h_rms, 1e-8)), 4),
                "band_shares": shares,
            }
        )
    return rows


def measurement_flags(overall: dict[str, float], onsets: dict[str, dict[str, float | int]], perc_ratio: float) -> list[str]:
    flags = []
    if overall["kick_body_60_120"] + overall["bass_drum_120_250"] > 0.33:
        flags.append("low_band_share_over_0_33")
    if overall["sub_weight_20_60"] > 0.06:
        flags.append("sub_band_share_over_0_06")
    if overall["presence_clap_2000_5000"] > 0.16:
        flags.append("presence_band_share_over_0_16")
    if overall["snap_hat_5000_8000"] + overall["air_shaker_8000_16000"] > 0.11:
        flags.append("high_band_share_over_0_11")
    if perc_ratio > 0.85:
        flags.append("percussive_to_harmonic_ratio_over_0_85")
    elif perc_ratio < 0.55:
        flags.append("percussive_to_harmonic_ratio_under_0_55")
    clap_hits = onsets.get("presence_clap_2000_5000", {}).get("hit_frames_per_second", 0)
    hat_hits = onsets.get("snap_hat_5000_8000", {}).get("hit_frames_per_second", 0)
    low_hits = onsets.get("kick_body_60_120", {}).get("hit_frames_per_second", 0)
    if low_hits and low_hits > 4.5:
        flags.append("low_body_hit_frames_per_second_over_4_5")
    if clap_hits and clap_hits > 5:
        flags.append("presence_hit_frames_per_second_over_5")
    if hat_hits and hat_hits > 5:
        flags.append("hat_hit_frames_per_second_over_5")
    return flags


def analyze_track(label: str, path: Path, sr: int, window_seconds: float) -> dict[str, object]:
    y, loaded_sr = librosa.load(path, sr=sr, mono=True)
    duration = librosa.get_duration(y=y, sr=loaded_sr)
    onset_env = librosa.onset.onset_strength(y=y, sr=loaded_sr)
    tempo, beats = librosa.beat.beat_track(onset_envelope=onset_env, sr=loaded_sr)
    beat_times = librosa.frames_to_time(beats, sr=loaded_sr)
    beat_intervals = np.diff(beat_times) if len(beat_times) > 1 else np.array([])
    harmonic, percussive = librosa.effects.hpss(y)
    h_rms = np.mean(librosa.feature.rms(y=harmonic, frame_length=2048, hop_length=512)[0])
    p_rms = np.mean(librosa.feature.rms(y=percussive, frame_length=2048, hop_length=512)[0])
    shares = band_shares(y, loaded_sr)
    onsets = band_onsets(y, loaded_sr)
    windows = window_rows(y, loaded_sr, window_seconds)
    top_windows = sorted(
        windows,
        key=lambda row: (
            row["mean_rms"],
            row["onset_mean"],
            row["percussive_to_harmonic_rms_ratio"],
        ),
        reverse=True,
    )[:8]
    perc_ratio = float(p_rms / max(h_rms, 1e-8))
    return {
        "label": label,
        "path": str(path),
        "duration_seconds": round(float(duration), 3),
        "estimated_tempo_bpm": round(float(scalar(tempo)), 3) if scalar(tempo) else None,
        "beat_count": int(len(beats)),
        "beat_stability_cv": round(float(np.std(beat_intervals) / max(np.mean(beat_intervals), 1e-8)), 4)
        if beat_intervals.size
        else None,
        "overall_band_energy_share": shares,
        "band_percussive_hit_density": onsets,
        "percussive_to_harmonic_rms_ratio": round(perc_ratio, 4),
        "top_windows": top_windows,
        "measurement_flags": measurement_flags(shares, onsets, perc_ratio),
        "method_note": (
            "Measurement-only one-off probe. These flags do not identify instruments, write arrangement guidance, "
            "or decide prompt language; Codex/human listening must interpret them."
        ),
    }


def markdown_report(results: list[dict[str, object]]) -> str:
    lines = [
        "# World Cup Reference Audio Instrument Probe",
        "",
        "This one-off probe uses local reference audio only. It reports measurement flags, not automatic instrument transcription or arrangement guidance.",
        "",
    ]
    for result in results:
        lines.extend(
            [
                f"## {result['label']}",
                "",
                f"- source: `{result['path']}`",
                f"- duration: `{result['duration_seconds']}s`",
                f"- estimated tempo: `{result['estimated_tempo_bpm']} BPM`",
                f"- percussive/harmonic RMS ratio: `{result['percussive_to_harmonic_rms_ratio']}`",
                "",
                "### Band Energy Share",
                "",
            ]
        )
        for key, value in result["overall_band_energy_share"].items():
            lines.append(f"- `{key}`: `{value}`")
        lines.extend(["", "### Measurement Flags", ""])
        for flag in result["measurement_flags"]:
            lines.append(f"- `{flag}`")
        lines.extend(["", "### Loud / Active Windows", ""])
        for row in result["top_windows"]:
            bands = row["band_shares"]
            lines.append(
                f"- `{row['start']}-{row['end']}s`: rms `{row['mean_rms']}`, onset `{row['onset_mean']}`, "
                f"perc/harm `{row['percussive_to_harmonic_rms_ratio']}`, "
                f"low `{bands['kick_body_60_120'] + bands['bass_drum_120_250']:.3f}`, "
                f"clap/presence `{bands['presence_clap_2000_5000']:.3f}`, "
                f"hat/air `{bands['snap_hat_5000_8000'] + bands['air_shaker_8000_16000']:.3f}`"
            )
        lines.append("")
    return "\n".join(lines)


def parse_track(value: str) -> tuple[str, Path]:
    if "=" not in value:
        raise argparse.ArgumentTypeError("track must be LABEL=/path/to/audio.wav")
    label, path = value.split("=", 1)
    return label, Path(path)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--track", action="append", type=parse_track, required=True)
    parser.add_argument("--out-json", required=True)
    parser.add_argument("--out-md", required=True)
    parser.add_argument("--sr", type=int, default=44100)
    parser.add_argument("--window-seconds", type=float, default=15.0)
    args = parser.parse_args()

    results = [analyze_track(label, path, args.sr, args.window_seconds) for label, path in args.track]
    payload = {"analysis_count": len(results), "results": results}

    out_json = Path(args.out_json)
    out_json.parent.mkdir(parents=True, exist_ok=True)
    out_json.write_text(json.dumps(payload, indent=2, ensure_ascii=False), encoding="utf-8")

    out_md = Path(args.out_md)
    out_md.parent.mkdir(parents=True, exist_ok=True)
    out_md.write_text(markdown_report(results), encoding="utf-8")


if __name__ == "__main__":
    main()
