#!/usr/bin/env python3
"""Create a source-first edit alignment draft for LOW.

This is a 04/edit evidence helper. It reads the selected audio, one baseline
recipe as a flow object, and source motion CSVs, then writes a new
idol_edit_marker_plan.v1 draft. Existing recipe timing is treated as a search
window, not as edit truth.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import re
from datetime import datetime
from pathlib import Path

try:
    import cv2
    import librosa
    import numpy as np
    import yaml
    from jsonschema import Draft202012Validator
except ModuleNotFoundError as exc:
    raise SystemExit(
        f"Missing Python dependency '{exc.name}'. Run this script through scripts/idol-video-python."
    ) from exc


def load_yaml(path: Path) -> dict:
    return yaml.safe_load(path.read_text(encoding="utf-8")) or {}


def rel(path: Path) -> str:
    return path.as_posix()


def source_to_motion_csv(run_root: Path, source: str) -> Path:
    prefix = "generations/video/raw/"
    if source.startswith(prefix):
        source_rel = source.removeprefix(prefix)
    else:
        source_rel = source
    return run_root / "generations/video/qc/sync-workbench-v1/motion" / f"{source_rel}.csv"


def read_motion_rows(path: Path, source_in: float, source_out: float) -> list[dict]:
    if not path.exists():
        return []
    rows = []
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


def compute_motion_rows(video_path: Path, source_in: float, source_out: float, sample_fps: float = 8.0) -> list[dict]:
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
    rows = []
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
    duration = float(librosa.get_duration(y=y, sr=sr))
    onset_env = librosa.onset.onset_strength(y=y, sr=sr)
    onset_frames = librosa.onset.onset_detect(onset_envelope=onset_env, sr=sr, units="frames")
    onset_times = librosa.frames_to_time(onset_frames, sr=sr)
    onset_strengths = onset_env[onset_frames] if len(onset_frames) else np.array([])
    tempo, beat_frames = librosa.beat.beat_track(onset_envelope=onset_env, sr=sr, units="frames")
    beat_times = librosa.frames_to_time(beat_frames, sr=sr)
    threshold = float(np.percentile(onset_strengths, 65)) if len(onset_strengths) else 0.0
    strong = []
    for time_seconds, strength in zip(onset_times, onset_strengths):
        if float(strength) >= threshold:
            strong.append(
                {
                    "time_seconds": round(float(time_seconds), 3),
                    "strength": round(float(strength), 4),
                }
            )
    return {
        "duration_seconds": round(duration, 3),
        "tempo_bpm": round(float(np.atleast_1d(tempo)[0]), 3),
        "beat_times": [round(float(t), 3) for t in beat_times],
        "strong_onsets": strong,
    }


def nearest(values: list[float], target: float) -> tuple[float | None, float | None]:
    if not values:
        return None, None
    best = min(values, key=lambda value: abs(value - target))
    return best, best - target


def markers_in_range(values: list[float], start: float, end: float, pad: float = 0.35) -> list[float]:
    return [round(value, 3) for value in values if start - pad <= value <= end + pad]


def cue_label(slot: str, note: str) -> str:
    text = re.sub(r"\s+", " ", note).strip()
    text = re.sub(r"^V\d+\s+keeps.*?\. ", "", text)
    if len(text) > 220:
        text = text[:217].rstrip() + "..."
    return text or slot


def section_id(slot: str, note: str, output_in: float) -> str:
    match = re.search(r"\b(S\d{2})\b", slot + " " + note)
    if match:
        return match.group(1)
    ranges = [
        (0, 5.707, "S00"),
        (5.707, 18.293, "S01"),
        (18.293, 34.859, "S02"),
        (34.859, 51.0, "S03"),
        (51.0, 67.0, "S04"),
        (67.0, 78.0, "S05"),
        (78.0, 88.0, "S06"),
        (88.0, 94.0, "S07"),
        (94.0, 100.0, "S07"),
        (100.0, 113.0, "S08"),
        (113.0, 132.0, "S09"),
        (132.0, 144.0, "S10"),
        (144.0, 156.0, "S11"),
        (156.0, 174.0, "S12"),
        (174.0, 187.0, "S13"),
        (187.0, 193.0, "S14"),
    ]
    for start, end, section in ranges:
        if start <= output_in < end:
            return section
    return "S00"


def cut_density(duration: float, section: str) -> str:
    if duration >= 4.5:
        return "hold"
    if section in {"S04", "S05", "S10", "S11", "S13"}:
        return "dense"
    if duration <= 1.8:
        return "hit_insert"
    if section in {"S06", "S14"}:
        return "deceleration"
    return "medium"


def slot_status(delta: float | None, missing_motion: bool, excluded: bool) -> str:
    if missing_motion:
        return "blocked"
    if excluded:
        return "fail"
    if delta is None:
        return "hold"
    adelta = abs(delta)
    if adelta <= 0.18:
        return "pass"
    if adelta <= 0.45:
        return "hold"
    return "fail"


def source_path(run_root: Path, source: str) -> Path:
    if source.startswith("generations/video/raw/"):
        return run_root / source
    return run_root / "generations/video/raw" / source


def build_plan(args: argparse.Namespace) -> dict:
    run_root = args.run_root
    recipe = load_yaml(args.recipe)
    source_index = load_yaml(args.source_index)
    audio_rel = recipe.get("audio_path") or "audio/selected/low-rubbery-low-eye-lean-selected.mp3"
    audio_path = run_root / audio_rel
    markers = audio_markers(audio_path)
    strong_times = [row["time_seconds"] for row in markers["strong_onsets"]]
    beat_times = markers["beat_times"]
    excluded_sources = set(recipe.get("source_use_policy", {}).get("still_excluded_sources", []))

    timeline = recipe.get("timeline", [])
    if not timeline:
        raise SystemExit(f"No timeline found in baseline recipe: {args.recipe}")

    slots = []
    decisions = {"pass": 0, "hold": 0, "fail": 0, "blocked": 0, "needs_founder": 0}
    source_count = int(source_index.get("source_count") or 0)

    for idx, row in enumerate(timeline, start=1):
        output_in = float(row["output_in"])
        output_out = float(row["output_out"])
        source_in = float(row["source_in"])
        source_out = float(row["source_out"])
        output_duration = float(row.get("output_duration") or (output_out - output_in))
        source_duration = max(source_out - source_in, 0.0001)
        source = str(row["source"])
        note = str(row.get("note") or row.get("slot") or "")
        section = section_id(str(row.get("slot", "")), note, output_in)
        motion_csv = source_to_motion_csv(run_root, source)
        motion_rows = read_motion_rows(motion_csv, source_in, source_out)
        if not motion_rows:
            motion_rows = compute_motion_rows(source_path(run_root, source), source_in, source_out)
        top_motion = max(motion_rows, key=lambda item: item["motion_score"]) if motion_rows else None

        mapped_output_peak = None
        nearest_onset = None
        onset_delta = None
        nearest_beat = None
        beat_delta = None
        if top_motion:
            progress = (top_motion["time_seconds"] - source_in) / source_duration
            mapped_output_peak = output_in + (progress * output_duration)
            nearest_onset, onset_delta = nearest(strong_times, mapped_output_peak)
            nearest_beat, beat_delta = nearest(beat_times, mapped_output_peak)

        excluded = source in excluded_sources
        status = slot_status(onset_delta, top_motion is None, excluded)
        decisions[status] += 1
        label = cue_label(str(row.get("slot", f"R{idx:02d}")), note)
        if top_motion:
            visible = f"{label}; optical-flow peak at source {top_motion['time_seconds']:.3f}s needs contact-sheet body/camera labeling"
            source_time = round(float(top_motion["time_seconds"]), 3)
            motion_score = round(float(top_motion["motion_score"]), 4)
        else:
            visible = f"{label}; no motion CSV evidence inside this source window"
            source_time = None
            motion_score = None

        basis = ["cue_role"]
        if nearest_onset is not None:
            basis.append("beat_or_onset")
        if top_motion is not None:
            basis.append("visible_body_landing")
        if "camera" in label.lower() or "gaze" in label.lower() or "eye" in label.lower():
            basis.append("gaze_lock")

        pass_note = "Hold for visual contact-sheet review before recipe lock."
        if status == "pass":
            pass_note = (
                f"Automatic evidence passes first screen: source motion peak maps to "
                f"{mapped_output_peak:.3f}s, within {abs(onset_delta):.3f}s of strong onset {nearest_onset:.3f}s. "
                "Still requires visual body/camera labeling before final recipe."
            )
        elif status == "hold":
            pass_note = (
                f"Near miss: source motion peak maps to {mapped_output_peak:.3f}s, "
                f"{abs(onset_delta):.3f}s from strong onset {nearest_onset:.3f}s. "
                "Review by playback; trim/shift only if body landing and camera connection read."
            )
        elif status == "fail":
            if excluded:
                pass_note = "Source is on the excluded list for this baseline; do not use unless founder explicitly reopens it."
            elif mapped_output_peak is not None and nearest_onset is not None:
                pass_note = (
                    f"Reject as marker-weak for source-first rebuild: source motion peak maps to "
                    f"{mapped_output_peak:.3f}s, {abs(onset_delta):.3f}s from nearest strong onset {nearest_onset:.3f}s."
                )
        elif status == "blocked":
            pass_note = "Blocked: no motion CSV evidence was found inside the declared source window."

        slot = {
            "slot": f"R{idx:02d}",
            "section_id": section,
            "transition_id": None,
            "output_range": {
                "start_seconds": round(output_in, 3),
                "end_seconds": round(output_out, 3),
                "label": "baseline search window only; not a cutpoint lock",
            },
            "cue_role": label,
            "nearby_markers": {
                "beats_seconds": markers_in_range(beat_times, output_in, output_out),
                "strong_onsets_seconds": markers_in_range(strong_times, output_in, output_out),
                "feature_boundaries_seconds": [],
                "lyric_or_section_handoff": label,
            },
            "source_candidates": [
                {
                    "candidate_id": f"{Path(source).stem}__{source_in:.3f}_{source_out:.3f}",
                    "source": source if source.startswith("generations/video/raw/") else f"generations/video/raw/{source}",
                    "source_in": round(source_in, 3),
                    "source_out": round(source_out, 3),
                    "speed_hint": round(source_duration / max(output_duration, 0.0001), 3),
                    "automatic_recognition_evidence": [
                        {
                            "signal_type": "motion_peak",
                            "artifact_or_method": rel(motion_csv),
                            "time_seconds": source_time,
                            "confidence": None,
                            "evidence_note": f"top optical-flow score in candidate window: {motion_score}",
                            "human_review_status": "pending",
                        }
                    ],
                    "note": "Candidate remains provisional until contact-sheet/playback confirms the visible body or camera event.",
                }
            ],
            "source_action_marker": {
                "visible_event": visible,
                "source_time_seconds": source_time,
                "body_part_or_motion": "visual review required; use recipe note as cue seed only",
                "camera_event": "visual review required",
            },
            "cut_density": cut_density(output_duration, section),
            "alignment_basis": sorted(set(basis)),
            "motion_continuity": "Carry only if the visible body route or camera direction leads into the next source; otherwise replace.",
            "audio_marker_alignment": (
                f"mapped_motion_peak={mapped_output_peak:.3f}s; nearest_strong_onset={nearest_onset:.3f}s; "
                f"onset_delta={onset_delta:+.3f}s; nearest_beat={nearest_beat:.3f}s; beat_delta={beat_delta:+.3f}s"
                if mapped_output_peak is not None and nearest_onset is not None and nearest_beat is not None
                else "no mapped motion peak; cannot align music marker, source action marker, and cue function yet"
            ),
            "derivative_impact": "A source-first 90s rebuild will invalidate v20 social cutdowns until a new master is reviewed.",
            "slot_status": status,
            "open_questions": [
                "Label the exact visible body landing, hand hit, foot hit, gaze lock, or camera stop from contact sheet/playback.",
                "Reject the source if that visible marker does not coincide with the nearest strong onset or beat.",
            ],
            "pass_fail_note": pass_note,
        }
        if not source_path(run_root, slot["source_candidates"][0]["source"]).exists():
            slot["slot_status"] = "blocked"
            decisions[status] -= 1
            decisions["blocked"] += 1
            slot["pass_fail_note"] = "Blocked: declared source file is missing."
        slots.append(slot)

    has_actual_tail_source = any(
        float(row.get("output_in", 9999.0)) <= 88.0 and float(row.get("output_out", -1.0)) >= 90.0
        for row in timeline
    )
    if not has_actual_tail_source:
        tail_slot_number = len(slots) + 1
        slots.append(
            {
                "slot": f"R{tail_slot_number:02d}",
                "section_id": "S07",
                "transition_id": "TAIL_88_90_NOT_SOURCE_FIRST",
                "output_range": {
                    "start_seconds": 88.0,
                    "end_seconds": 90.0,
                    "label": "v20 clone-fade tail excluded from source-first rebuild",
                },
                "cue_role": "88.000s restart / 90s clean-fade package tail",
                "nearby_markers": {
                    "beats_seconds": markers_in_range(beat_times, 88.0, 90.0),
                    "strong_onsets_seconds": markers_in_range(strong_times, 88.0, 90.0),
                    "feature_boundaries_seconds": [],
                    "lyric_or_section_handoff": "S07 restart begins at 88.000s; v20 clone fade is not moving source evidence.",
                },
                "source_candidates": [
                    {
                        "candidate_id": "needs_actual_source_not_v20_clone",
                        "source": "needs_actual_source_not_v20_clone",
                        "source_in": None,
                        "source_out": None,
                        "speed_hint": None,
                        "automatic_recognition_evidence": [
                            {
                                "signal_type": "source_health_flag",
                                "artifact_or_method": rel(args.recipe),
                                "time_seconds": None,
                                "confidence": None,
                                "evidence_note": "v20 final two seconds clone final frame under fade; user requested source-first rebuild.",
                                "human_review_status": "accepted_as_evidence",
                            }
                        ],
                        "note": "Do not use the v20 cloned still tail as source-first material.",
                    }
                ],
                "source_action_marker": {
                    "visible_event": "No actual source motion selected for 88.000-90.000s; v20 used a cloned final frame under fade.",
                    "source_time_seconds": None,
                    "body_part_or_motion": "missing moving source",
                    "camera_event": "missing source-clean camera stop",
                },
                "cut_density": "deceleration",
                "alignment_basis": ["beat_or_onset", "cue_role"],
                "motion_continuity": "Needs a real source endpoint or the rebuild should end before this tail.",
                "audio_marker_alignment": "Audio restart marker exists at 88.000s, but v20 tail has no moving source action marker.",
                "derivative_impact": "Blocks reuse of v20 90s package until new ending source is selected or master duration is relocked.",
                "slot_status": "blocked",
                "open_questions": [
                    "Select an actual moving source for the 88-90s tail or relock the rebuild endpoint before 88s.",
                ],
                "pass_fail_note": "Blocked for source-first rebuild: cloned fade tail is not usable source motion.",
            }
        )
        decisions["blocked"] += 1

    plan = {
        "schema_version": "idol_edit_marker_plan.v1",
        "content_id": "0526_SONG_SELECTION",
        "status": "source_first_rebuild_initial_alignment_not_recipe_lock",
        "source_audio": rel(audio_path),
        "source_selected_audio_analysis": "runs/2026-05-26/0526_SONG_SELECTION/research/selected-audio-analysis-v1.yaml",
        "source_audio_motion_director_map": "runs/2026-05-26/0526_SONG_SELECTION/research/audio-motion-director-map-v7.yaml",
        "source_cue_bpm_map": "runs/2026-05-26/0526_SONG_SELECTION/generations/video/qc/sync-workbench-v1/audio-markers/",
        "source_audio_beat_onset_summary": "runs/2026-05-26/0526_SONG_SELECTION/generations/video/qc/sync-workbench-v1/audio-beat-onset-summary.json",
        "source_recipe": rel(args.recipe),
        "owner": "04_edit",
        "use_rule": (
            "Use this as the first source-first rebuild evidence pass. Existing B## seconds and v20 timing are "
            "search windows only; recipe lock requires visual contact-sheet/playback confirmation of each source action marker."
        ),
        "upstream_intent_context": {
            "available": True,
            "sources": {
                "song_lock": "runs/2026-05-26/0526_SONG_SELECTION/00A-song-lock.yaml",
                "song_choreography_performance_mv_map": "runs/2026-05-26/0526_SONG_SELECTION/01-song-choreography-performance-mv-map.yaml",
                "master_storyboard": None,
                "prompt_packets": None,
                "review_board_or_cue_sheet": "runs/2026-05-26/0526_SONG_SELECTION/generations/video-prompts/upload-packs/low-video-input-packs-v1/PACK_INDEX.csv",
            },
            "use_as": [
                "intent_map",
                "candidate_narrowing",
                "cue_function_seed",
                "expected_motion_seed",
                "review_priority_seed",
            ],
            "not_edit_truth": [
                "source_in",
                "source_out",
                "speed_factor",
                "final_cutpoint",
                "final_candidate_selection",
                "final_geometry_override",
            ],
            "proof_required_in_04": [
                "actual_source_exists",
                "first_useful_action",
                "motion_peak",
                "beat_or_onset_alignment",
                "cue_function_alignment",
                "contact_sheet_qc",
                "preview_qc",
                "source_quality_qc",
            ],
            "efficiency_note": "Read baseline recipe notes only to name cue function; do not inherit its cut times.",
            "quality_note": "A pass here is automatic evidence only and still needs visual body/camera labeling.",
        },
        "initial_alignment_pass": {
            "analysis_inputs": {
                "selected_audio": rel(audio_path),
                "cue_sheet": "runs/2026-05-26/0526_SONG_SELECTION/generations/video-prompts/upload-packs/low-video-input-packs-v1/PACK_INDEX.csv",
                "song_lock": "runs/2026-05-26/0526_SONG_SELECTION/00A-song-lock.yaml",
                "song_choreography_performance_mv_map": "runs/2026-05-26/0526_SONG_SELECTION/01-song-choreography-performance-mv-map.yaml",
                "master_storyboard": None,
                "prompt_packets": None,
                "selected_audio_analysis": "runs/2026-05-26/0526_SONG_SELECTION/research/selected-audio-analysis-v1.yaml",
                "audio_motion_director_map": "runs/2026-05-26/0526_SONG_SELECTION/research/audio-motion-director-map-v7.yaml",
                "cue_bpm_map": "runs/2026-05-26/0526_SONG_SELECTION/generations/video/qc/sync-workbench-v1/audio-markers/",
                "audio_beat_onset_summary": "runs/2026-05-26/0526_SONG_SELECTION/generations/video/qc/sync-workbench-v1/audio-beat-onset-summary.json",
                "roughcut_or_current_recipe": rel(args.recipe),
                "source_motion_csv_dir": "runs/2026-05-26/0526_SONG_SELECTION/generations/video/qc/sync-workbench-v1/motion",
                "automatic_recognition_reports": [rel(args.source_index)],
            },
            "baseline_cut_read": {
                "roughcut_or_recipe": rel(args.recipe),
                "what_already_works": [
                    "The baseline provides cue labels and a source pool for search.",
                    "Several source windows have motion peaks near actual audio onsets and can move to visual review.",
                ],
                "what_is_not_marker_locked_yet": [
                    "Any slot whose source motion peak misses the nearest strong onset by more than 0.18s.",
                    "Any slot using v20 cloned fade tail or an excluded source.",
                    "Any slot where optical flow cannot be translated into a visible body/camera event.",
                ],
                "first_pass_goal": "Separate usable source-action candidates from duration-fit or v20-only timeline assumptions.",
            },
            "alignment_method": [
                "music_marker",
                "source_action_marker",
                "cue_function_marker",
                "motion_peak",
                "contact_sheet_qc",
                "roughcut_flow_read",
            ],
            "source_motion_scan": {
                "motion_csv_dir": "runs/2026-05-26/0526_SONG_SELECTION/generations/video/qc/sync-workbench-v1/motion",
                "source_first_seconds_scan": True,
                "motion_peak_scan": True,
                "candidate_source_contact_sheet": True,
            },
            "marker_lock_required_before_recipe": True,
            "pass_fail_rule": "A slot passes recipe-readiness only after music marker, source action marker, and cue function are visually confirmed together.",
        },
        "timeline_slots": slots,
    }
    plan["initial_alignment_pass"]["baseline_cut_read"]["source_first_rebuild_summary"] = {
        "created_at": datetime.now().astimezone().isoformat(timespec="seconds"),
        "baseline_recipe_read_as": "flow_search_window_not_edit_truth",
        "baseline_v20_status": "protected_reference_only_discarded_for_rebuild",
        "source_count": source_count,
        "audio_duration_seconds": markers["duration_seconds"],
        "automatic_tempo_bpm": markers["tempo_bpm"],
        "slot_status_counts": decisions,
    }
    return plan


def write_summary(plan: dict, path: Path) -> None:
    counts = {"pass": 0, "hold": 0, "fail": 0, "blocked": 0, "needs_founder": 0}
    for slot in plan["timeline_slots"]:
        counts[slot["slot_status"]] = counts.get(slot["slot_status"], 0) + 1
    blocked_or_failed = [
        slot
        for slot in plan["timeline_slots"]
        if slot["slot_status"] in {"fail", "blocked"}
    ][:12]
    lines = [
        "# LOW Source-First Rebuild Initial Alignment v1",
        "",
        "Status: `source_first_rebuild_initial_alignment_not_recipe_lock`",
        "",
        "## Rule",
        "",
        "- Existing beat split and v20 timing are search history only.",
        "- A cut can move forward only when the music marker, source body/camera marker, and cue function coincide on playback.",
        "- The v20 cloned fade tail is blocked as source-first material.",
        "",
        "## Inputs",
        "",
        f"- Source audio: `{plan['source_audio']}`",
        f"- Baseline recipe read as flow window: `{plan['source_recipe']}`",
        f"- Source index: `{plan['initial_alignment_pass']['analysis_inputs']['automatic_recognition_reports'][0]}`",
        "",
        "## Automatic First-Pass Counts",
        "",
        f"- pass evidence: {counts.get('pass', 0)}",
        f"- hold for visual review: {counts.get('hold', 0)}",
        f"- fail: {counts.get('fail', 0)}",
        f"- blocked: {counts.get('blocked', 0)}",
        "",
        "## First Fail/Block Queue",
        "",
    ]
    if not blocked_or_failed:
        lines.append("- None from automatic first pass.")
    for slot in blocked_or_failed:
        cand = slot["source_candidates"][0]
        lines.append(
            f"- `{slot['slot']}` `{slot['section_id']}` {slot['output_range']['start_seconds']:.3f}-{slot['output_range']['end_seconds']:.3f}s: "
            f"`{slot['slot_status']}` / `{cand['source']}` / {slot['pass_fail_note']}"
        )
    lines.extend(
        [
            "",
            "## Next Edit Action",
            "",
            "1. Open the hold/pass contact sheets and label the actual body landing, hand hit, foot hit, gaze lock, or camera stop.",
            "2. Reject any slot where that visible marker does not sit on the nearby onset/beat listed in the YAML.",
            "3. Only after the visual labels are filled, write a new source-clean recipe fragment.",
            "",
        ]
    )
    path.write_text("\n".join(lines), encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-root", type=Path, required=True)
    parser.add_argument("--recipe", type=Path, required=True)
    parser.add_argument("--source-index", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--summary", type=Path, required=True)
    parser.add_argument("--schema", type=Path, default=Path("schemas/edit-marker-plan.schema.json"))
    args = parser.parse_args()

    plan = build_plan(args)
    schema = json.loads(args.schema.read_text(encoding="utf-8"))
    errors = sorted(Draft202012Validator(schema).iter_errors(plan), key=lambda error: error.path)
    if errors:
        first = errors[0]
        raise SystemExit(f"Schema validation failed at {list(first.path)}: {first.message}")

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.summary.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(yaml.safe_dump(plan, allow_unicode=True, sort_keys=False), encoding="utf-8")
    write_summary(plan, args.summary)
    print(args.out)
    print(args.summary)
    counts = {"pass": 0, "hold": 0, "fail": 0, "blocked": 0, "needs_founder": 0}
    for slot in plan["timeline_slots"]:
        counts[slot["slot_status"]] = counts.get(slot["slot_status"], 0) + 1
    print(counts)


if __name__ == "__main__":
    main()
