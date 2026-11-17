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


def analyze_intro(path: Path, seconds: float):
    y, sr = librosa.load(path, sr=22050, mono=True)
    y = y[: int(sr * seconds)]
    duration = librosa.get_duration(y=y, sr=sr)
    onset_env = librosa.onset.onset_strength(y=y, sr=sr)
    tempo, beats = librosa.beat.beat_track(onset_envelope=onset_env, sr=sr)
    tempo_value = scalar(tempo)
    onset_events = librosa.onset.onset_detect(onset_envelope=onset_env, sr=sr, units="time")
    rms = librosa.feature.rms(y=y, frame_length=2048, hop_length=512)[0]
    harmonic, percussive = librosa.effects.hpss(y)
    h_mean = float(np.mean(librosa.feature.rms(y=harmonic, frame_length=2048, hop_length=512)[0]))
    p_mean = float(np.mean(librosa.feature.rms(y=percussive, frame_length=2048, hop_length=512)[0]))
    return {
        "file": str(path),
        "intro_seconds": round(float(duration), 3),
        "estimated_intro_tempo_bpm": round(float(tempo_value), 3) if tempo_value else None,
        "beat_count": int(len(beats)),
        "onset_count": int(len(onset_events)),
        "onsets_per_second": round(float(len(onset_events) / duration), 3) if duration else None,
        "mean_rms": round(float(np.mean(rms)), 6),
        "peak_rms": round(float(np.max(rms)), 6),
        "percussive_to_harmonic_rms_ratio": round(p_mean / max(h_mean, 1e-8), 4),
        "band_energy_share": band_energy(y, sr),
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--audio-dir", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--seconds", type=float, default=15.0)
    args = parser.parse_args()

    audio_dir = Path(args.audio_dir)
    results = []
    for path in sorted(audio_dir.glob("REF_*.m4a")):
        result = analyze_intro(path, args.seconds)
        info_path = path.with_suffix(".info.json")
        if info_path.exists():
            with info_path.open("r", encoding="utf-8") as fh:
                info = json.load(fh)
            result["bilibili"] = {
                "id": info.get("id"),
                "title": info.get("title"),
                "uploader": info.get("uploader"),
                "webpage_url": info.get("webpage_url"),
                "duration": info.get("duration"),
                "upload_date": info.get("upload_date"),
            }
        results.append(result)

    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("w", encoding="utf-8") as fh:
        json.dump(
            {
                "intro_seconds": args.seconds,
                "analysis_count": len(results),
                "method_note": (
                    "Measurement-only reference intro metrics. These values do not decide song fit, section function, "
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
