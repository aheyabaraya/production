from __future__ import annotations

import argparse
import json
import math
import re
import subprocess
from pathlib import Path
from typing import Any

import librosa
import matplotlib.pyplot as plt
import numpy as np


HOP_LENGTH = 512

SECTION_RE = re.compile(r"^\[(?P<section>[^\]|]+)(?:\|[^\]]*)?\]\s*$")

NOTE_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
MAJOR_PROFILE = np.array([6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88])
MINOR_PROFILE = np.array([6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17])


def scalar(value: Any) -> float | None:
    arr = np.asarray(value)
    if arr.shape == ():
        return float(arr)
    if arr.size == 0:
        return None
    return float(arr.reshape(-1)[0])


def dbfs(value: float) -> float:
    return round(20.0 * math.log10(max(float(value), 1e-12)), 2)


def read_ffprobe(path: Path) -> dict[str, Any]:
    cmd = [
        "ffprobe",
        "-v",
        "quiet",
        "-show_format",
        "-show_streams",
        "-print_format",
        "json",
        str(path),
    ]
    result = subprocess.run(cmd, check=True, text=True, capture_output=True)
    return json.loads(result.stdout)


def read_loudnorm(path: Path) -> dict[str, Any]:
    cmd = [
        "ffmpeg",
        "-hide_banner",
        "-nostats",
        "-i",
        str(path),
        "-af",
        "loudnorm=I=-14:TP=-1.5:LRA=11:print_format=json",
        "-f",
        "null",
        "-",
    ]
    result = subprocess.run(cmd, text=True, capture_output=True)
    text = result.stderr
    start = text.rfind("{")
    end = text.rfind("}")
    if start == -1 or end == -1 or end <= start:
        return {"error": "loudnorm_json_not_found"}
    try:
        return json.loads(text[start : end + 1])
    except json.JSONDecodeError as exc:
        return {"error": f"loudnorm_json_parse_failed: {exc}"}


def parse_lyrics(metadata_path: Path) -> dict[str, Any]:
    if not metadata_path.exists():
        return {"metadata_path": str(metadata_path), "lyrics_available": False, "sections": []}

    ffprobe = read_ffprobe(metadata_path)
    tags = ffprobe.get("format", {}).get("tags", {})
    lyrics = tags.get("lyrics-eng") or tags.get("lyrics") or ""
    sections: list[dict[str, Any]] = []
    current: dict[str, Any] | None = None

    for raw_line in lyrics.splitlines():
        line = raw_line.strip()
        match = SECTION_RE.match(line)
        if match:
            if current is not None:
                sections.append(current)
            current = {"section": match.group("section").strip(), "lines": []}
            continue
        if current is not None and line:
            current["lines"].append(line)
    if current is not None:
        sections.append(current)

    language_counts = {"korean": 0, "japanese": 0, "latin": 0}
    for section in sections:
        for line in section["lines"]:
            if re.search(r"[\uac00-\ud7af]", line):
                language_counts["korean"] += 1
            if re.search(r"[\u3040-\u30ff\u3400-\u9fff]", line):
                language_counts["japanese"] += 1
            if re.search(r"[A-Za-z]", line):
                language_counts["latin"] += 1

    return {
        "metadata_path": str(metadata_path),
        "lyrics_available": bool(lyrics),
        "title": tags.get("title"),
        "artist": tags.get("artist"),
        "comment": tags.get("comment"),
        "section_count": len(sections),
        "sections": sections,
        "language_line_counts": language_counts,
    }


def normalize_rows(matrix: np.ndarray) -> np.ndarray:
    means = np.mean(matrix, axis=1, keepdims=True)
    stds = np.std(matrix, axis=1, keepdims=True)
    return (matrix - means) / np.maximum(stds, 1e-8)


def smooth(values: np.ndarray, width: int) -> np.ndarray:
    if width <= 1 or values.size == 0:
        return values
    kernel = np.ones(width, dtype=float) / float(width)
    return np.convolve(values, kernel, mode="same")


def choose_boundaries(novelty: np.ndarray, frame_times: np.ndarray, duration: float, target_segments: int) -> list[float]:
    min_spacing = 7.0 if duration < 190 else 8.0
    guard = 3.0
    target_boundaries = max(0, target_segments - 1)
    candidates: list[tuple[float, float]] = []

    for idx in range(1, novelty.size - 1):
        time_value = float(frame_times[min(idx, len(frame_times) - 1)])
        if time_value < guard or time_value > duration - guard:
            continue
        if novelty[idx] >= novelty[idx - 1] and novelty[idx] >= novelty[idx + 1]:
            candidates.append((float(novelty[idx]), time_value))

    candidates.sort(reverse=True)
    selected: list[float] = []
    for score, time_value in candidates:
        if len(selected) >= target_boundaries:
            break
        if all(abs(time_value - existing) >= min_spacing for existing in selected):
            selected.append(time_value)

    boundaries = [0.0] + sorted(selected) + [duration]
    cleaned = [boundaries[0]]
    for boundary in boundaries[1:-1]:
        if boundary - cleaned[-1] >= min_spacing and duration - boundary >= min_spacing:
            cleaned.append(boundary)
    cleaned.append(duration)
    return cleaned


def key_estimate(chroma: np.ndarray) -> list[dict[str, Any]]:
    vector = np.mean(chroma, axis=1)
    vector = (vector - np.mean(vector)) / max(np.std(vector), 1e-8)
    rows: list[dict[str, Any]] = []
    for root in range(12):
        major = np.roll(MAJOR_PROFILE, root)
        minor = np.roll(MINOR_PROFILE, root)
        major = (major - np.mean(major)) / np.std(major)
        minor = (minor - np.mean(minor)) / np.std(minor)
        rows.append({"key": f"{NOTE_NAMES[root]} major", "score": float(np.corrcoef(vector, major)[0, 1])})
        rows.append({"key": f"{NOTE_NAMES[root]} minor", "score": float(np.corrcoef(vector, minor)[0, 1])})
    rows.sort(key=lambda row: row["score"], reverse=True)
    return [{"key": row["key"], "score": round(row["score"], 4)} for row in rows[:4]]


def band_energy(y: np.ndarray, sr: int) -> dict[str, float]:
    n_fft = 2048
    stft = np.abs(librosa.stft(y, n_fft=n_fft, hop_length=HOP_LENGTH)) ** 2
    freqs = librosa.fft_frequencies(sr=sr, n_fft=n_fft)
    total = float(np.sum(stft)) or 1.0
    bands = {
        "sub_20_80hz": (20, 80),
        "bass_80_250hz": (80, 250),
        "low_mid_250_500hz": (250, 500),
        "vocal_body_500_2000hz": (500, 2000),
        "presence_2000_6000hz": (2000, 6000),
        "air_6000_16000hz": (6000, min(16000, sr / 2)),
    }
    output: dict[str, float] = {}
    for name, (low, high) in bands.items():
        mask = (freqs >= low) & (freqs < high)
        output[name] = round(float(np.sum(stft[mask, :]) / total), 6)
    return output


def segment_metrics(y: np.ndarray, sr: int, start: float, end: float) -> dict[str, Any]:
    start_sample = max(0, int(start * sr))
    end_sample = min(len(y), int(end * sr))
    segment = y[start_sample:end_sample]
    duration = max((end_sample - start_sample) / sr, 1e-8)
    if len(segment) < sr:
        return {"duration_seconds": round(end - start, 2)}

    rms = librosa.feature.rms(y=segment, frame_length=2048, hop_length=HOP_LENGTH)[0]
    onset_env = librosa.onset.onset_strength(y=segment, sr=sr, hop_length=HOP_LENGTH)
    onset_events = librosa.onset.onset_detect(onset_envelope=onset_env, sr=sr, hop_length=HOP_LENGTH, units="time")
    centroid = librosa.feature.spectral_centroid(y=segment, sr=sr, hop_length=HOP_LENGTH)[0]
    transient_to_energy = float(np.mean(onset_env) / max(float(np.mean(rms)), 1e-8))

    return {
        "duration_seconds": round(end - start, 2),
        "mean_rms": round(float(np.mean(rms)), 6),
        "peak_rms": round(float(np.max(rms)), 6),
        "mean_dbfs": dbfs(float(np.mean(rms))),
        "peak_dbfs": dbfs(float(np.max(np.abs(segment)))),
        "onset_count": int(len(onset_events)),
        "onsets_per_second": round(float(len(onset_events) / duration), 3),
        "mean_spectral_centroid": round(float(np.mean(centroid)), 2),
        "transient_to_energy_ratio": round(transient_to_energy, 4),
        "band_energy_share": band_energy(segment, sr),
    }


def top_windows(y: np.ndarray, sr: int, window_seconds: float = 12.0, limit: int = 8) -> list[dict[str, Any]]:
    hop_samples = int(sr * window_seconds)
    rows: list[dict[str, Any]] = []
    for start_sample in range(0, len(y), hop_samples):
        end_sample = min(len(y), start_sample + hop_samples)
        segment = y[start_sample:end_sample]
        if len(segment) < sr * 4:
            continue
        start = start_sample / sr
        end = end_sample / sr
        metrics = segment_metrics(y, sr, start, end)
        rows.append({"start": round(start, 2), "end": round(end, 2), **metrics})
    rows.sort(
        key=lambda row: (
            row.get("mean_rms", 0.0),
            row.get("onsets_per_second", 0.0),
            row.get("transient_to_energy_ratio", 0.0),
        ),
        reverse=True,
    )
    return rows[:limit]


def analyze_track(label: str, audio_path: Path, metadata_path: Path | None, out_dir: Path | None) -> dict[str, Any]:
    y, sr = librosa.load(audio_path, sr=22050, mono=True)
    duration = float(librosa.get_duration(y=y, sr=sr))
    onset_env = librosa.onset.onset_strength(y=y, sr=sr, hop_length=HOP_LENGTH)
    tempo, beats = librosa.beat.beat_track(onset_envelope=onset_env, sr=sr, hop_length=HOP_LENGTH)
    tempo_value = scalar(tempo)
    beat_times = librosa.frames_to_time(beats, sr=sr, hop_length=HOP_LENGTH)
    beat_intervals = np.diff(beat_times) if len(beat_times) > 1 else np.array([])

    rms = librosa.feature.rms(y=y, frame_length=2048, hop_length=HOP_LENGTH)[0]
    centroid = librosa.feature.spectral_centroid(y=y, sr=sr, hop_length=HOP_LENGTH)[0]
    rolloff = librosa.feature.spectral_rolloff(y=y, sr=sr, hop_length=HOP_LENGTH)[0]
    chroma = librosa.feature.chroma_stft(y=y, sr=sr, hop_length=HOP_LENGTH)
    mfcc = librosa.feature.mfcc(y=y, sr=sr, hop_length=HOP_LENGTH, n_mfcc=8)
    transient_to_energy = float(np.mean(onset_env) / max(float(np.mean(rms)), 1e-8))

    lyric_info = parse_lyrics(metadata_path or audio_path.with_suffix(".mp3"))
    target_segments = lyric_info.get("section_count") or int(np.clip(round(duration / 22.0), 7, 11))

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
    boundaries = choose_boundaries(novelty, frame_times, duration, int(target_segments))

    section_names = [row["section"] for row in lyric_info.get("sections", [])]
    sections: list[dict[str, Any]] = []
    for idx in range(len(boundaries) - 1):
        start = float(boundaries[idx])
        end = float(boundaries[idx + 1])
        name = section_names[idx] if idx < len(section_names) else f"auto_section_{idx + 1}"
        section = {
            "id": f"S{idx:02d}",
            "label": name,
            "start": round(start, 2),
            "end": round(end, 2),
            **segment_metrics(y, sr, start, end),
        }
        sections.append(section)

    energy_sorted = sorted(sections, key=lambda row: row.get("mean_rms", 0.0), reverse=True)
    onset_sorted = sorted(sections, key=lambda row: row.get("onsets_per_second", 0.0), reverse=True)
    energy_rank = {row["id"]: index + 1 for index, row in enumerate(energy_sorted)}
    onset_rank = {row["id"]: index + 1 for index, row in enumerate(onset_sorted)}
    for section in sections:
        section["energy_rank"] = energy_rank[section["id"]]
        section["onset_density_rank"] = onset_rank[section["id"]]

    first_15 = segment_metrics(y, sr, 0.0, min(15.0, duration))

    plot_path = None
    if out_dir is not None:
        out_dir.mkdir(parents=True, exist_ok=True)
        plot_path = out_dir / f"{label}_energy_novelty.png"
        fig, ax1 = plt.subplots(figsize=(14, 4))
        rms_times = librosa.frames_to_time(np.arange(rms.size), sr=sr, hop_length=HOP_LENGTH)
        ax1.plot(rms_times, rms, color="#1f77b4", linewidth=0.8, label="RMS")
        ax1.set_ylabel("RMS")
        ax2 = ax1.twinx()
        ax2.plot(frame_times, novelty[: len(frame_times)], color="#d62728", alpha=0.55, linewidth=0.8, label="novelty")
        ax2.set_ylabel("novelty")
        for boundary in boundaries:
            ax1.axvline(boundary, color="#111111", alpha=0.2, linewidth=0.8)
        ax1.set_title(label)
        ax1.set_xlabel("seconds")
        fig.tight_layout()
        fig.savefig(plot_path, dpi=140)
        plt.close(fig)

    ffprobe = read_ffprobe(audio_path)
    return {
        "label": label,
        "audio_path": str(audio_path),
        "metadata_path": str(metadata_path or audio_path.with_suffix(".mp3")),
        "duration_seconds": round(duration, 3),
        "audio_format": ffprobe.get("format", {}).get("format_name"),
        "sample_rate": sr,
        "estimated_tempo_bpm": round(float(tempo_value), 3) if tempo_value else None,
        "half_time_bpm": round(float(tempo_value) / 2.0, 3) if tempo_value else None,
        "double_time_bpm": round(float(tempo_value) * 2.0, 3) if tempo_value else None,
        "beat_count": int(len(beats)),
        "beat_stability_cv": round(float(np.std(beat_intervals) / max(np.mean(beat_intervals), 1e-8)), 4)
        if beat_intervals.size
        else None,
        "onset_count": int(len(librosa.onset.onset_detect(onset_envelope=onset_env, sr=sr, hop_length=HOP_LENGTH))),
        "onsets_per_second": round(
            float(
                len(librosa.onset.onset_detect(onset_envelope=onset_env, sr=sr, hop_length=HOP_LENGTH))
                / max(duration, 1e-8)
            ),
            3,
        ),
        "mean_rms": round(float(np.mean(rms)), 6),
        "peak_rms": round(float(np.max(rms)), 6),
        "mean_dbfs": dbfs(float(np.mean(rms))),
        "peak_dbfs": dbfs(float(np.max(np.abs(y)))),
        "mean_spectral_centroid": round(float(np.mean(centroid)), 2),
        "mean_spectral_rolloff": round(float(np.mean(rolloff)), 2),
        "transient_to_energy_ratio": round(transient_to_energy, 4),
        "key_estimate": key_estimate(chroma),
        "loudnorm": read_loudnorm(audio_path),
        "overall_band_energy_share": band_energy(y, sr),
        "first_15_seconds": first_15,
        "top_12s_windows": top_windows(y, sr),
        "lyric_metadata": lyric_info,
        "section_candidates": sections,
        "plot_path": str(plot_path) if plot_path else None,
        "method_note": (
            "Automatic measurement from local audio. Chroma key rows are proxy candidates, not a key lock. "
            "Section times are novelty-aligned candidates mapped to embedded lyric sections; verify by listening before production lock."
        ),
    }


def markdown_report(payload: dict[str, Any]) -> str:
    lines = [
        "# LEFT_IN_THAT_NIGHT Candidate Audio Probe",
        "",
        "Automatic local measurements. Use as evidence for creative listening and market evaluation, not as a final song, key, or section lock by itself.",
        "",
    ]

    for result in payload["results"]:
        lines.extend(
            [
                f"## {result['label']}",
                "",
                f"- duration: `{result['duration_seconds']}s`",
                f"- estimated tempo: `{result['estimated_tempo_bpm']} BPM`",
                f"- half/double feel: `{result['half_time_bpm']}` / `{result['double_time_bpm']} BPM`",
                f"- beat stability CV: `{result['beat_stability_cv']}`",
                f"- onsets/sec: `{result['onsets_per_second']}`",
                f"- mean / peak dBFS: `{result['mean_dbfs']}` / `{result['peak_dbfs']}`",
                f"- integrated loudness estimate: `{result['loudnorm'].get('input_i')}` LUFS, true peak `{result['loudnorm'].get('input_tp')}` dBTP, LRA `{result['loudnorm'].get('input_lra')}`",
                f"- transient/energy ratio: `{result['transient_to_energy_ratio']}`",
                f"- chroma-proxy key candidates: {', '.join([row['key'] + ' ' + str(row['score']) for row in result['key_estimate']])}",
                f"- lyrics sections: `{result['lyric_metadata'].get('section_count')}`; language line counts `{result['lyric_metadata'].get('language_line_counts')}`",
                f"- plot: `{result['plot_path']}`",
                "",
                "### First 15 Seconds",
                "",
            ]
        )
        first = result["first_15_seconds"]
        lines.append(
            f"- rms `{first.get('mean_rms')}`, onsets/sec `{first.get('onsets_per_second')}`, "
            f"centroid `{first.get('mean_spectral_centroid')}`, transient/energy `{first.get('transient_to_energy_ratio')}`"
        )
        lines.extend(["", "### Top 12s Windows", ""])
        for row in result["top_12s_windows"][:5]:
            lines.append(
                f"- `{row['start']}-{row['end']}s`: rms `{row.get('mean_rms')}`, "
                f"onsets/sec `{row.get('onsets_per_second')}`, transient/energy `{row.get('transient_to_energy_ratio')}`"
            )
        lines.extend(["", "### Section Candidates", ""])
        for section in result["section_candidates"]:
            lines.append(
                f"- `{section['id']}` `{section['label']}` `{section['start']}-{section['end']}s`: "
                f"rms `{section.get('mean_rms')}`, onsets/sec `{section.get('onsets_per_second')}`, "
                f"energy rank `{section.get('energy_rank')}`, onset rank `{section.get('onset_density_rank')}`"
            )
        lines.append("")
    return "\n".join(lines)


def parse_track(value: str) -> tuple[str, Path]:
    if "=" not in value:
        raise argparse.ArgumentTypeError("track must be LABEL=/path/to/audio")
    label, path = value.split("=", 1)
    return label, Path(path)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--track", action="append", type=parse_track, required=True)
    parser.add_argument("--out-json", required=True)
    parser.add_argument("--out-md", required=True)
    parser.add_argument("--out-dir")
    args = parser.parse_args()

    out_dir = Path(args.out_dir) if args.out_dir else None
    results = []
    for label, audio_path in args.track:
        metadata_path = audio_path.with_suffix(".mp3")
        results.append(analyze_track(label, audio_path, metadata_path, out_dir))

    payload = {
        "schema": "idol_candidate_audio_probe.v1",
        "analysis_count": len(results),
        "method_note": (
            "Measurement-only candidate audio probe. Tempo, key, and section rows are evidence candidates; "
            "Codex/human listening must decide selected-audio analysis, the audio-motion map, and 00A lock."
        ),
        "results": results,
    }

    out_json = Path(args.out_json)
    out_json.parent.mkdir(parents=True, exist_ok=True)
    out_json.write_text(json.dumps(payload, indent=2, ensure_ascii=False), encoding="utf-8")

    out_md = Path(args.out_md)
    out_md.parent.mkdir(parents=True, exist_ok=True)
    out_md.write_text(markdown_report(payload), encoding="utf-8")


if __name__ == "__main__":
    main()
