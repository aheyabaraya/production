#!/usr/bin/env python3
"""Seed conservative 04FX review opportunities from 04 and audio evidence.

This helper never locks a cut or passes an effect.  Frame timing comes from the
04 recipe, cut craft comes from the 04 marker plan, and unverified meter phase
is never promoted into transition evidence.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from collections import defaultdict
from fractions import Fraction
from pathlib import Path
from typing import Any

try:
    import yaml
except ModuleNotFoundError as exc:
    raise SystemExit(
        f"Missing Python dependency '{exc.name}'. "
        "Run this script through scripts/idol-video-python."
    ) from exc

from lib.idol_edit_effect_registry import load_unique_yaml

RETURN_TO_04_STATUSES = {"fail", "hold", "blocked", "needs_founder"}
NO_EFFECT_METHODS = {"clean_hard_cut", "cut_on_action"}
VISIBLE_ALIGNMENT_TERMS = {
    "visible_body_landing",
    "hand_hit",
    "foot_hit",
    "gaze_lock",
    "camera_move",
}
EVENT_KIND_PRIORITY = {
    "section_boundary": 0,
    "lyric_gate": 1,
    "drop_or_release": 2,
    "onset_gate": 3,
    "story_handoff": 4,
    "other_musical_turn": 5,
}
AUDIO_ONSET_KEYS = (
    "strong_onsets_ranked",
    "top_onset_markers",
    "strong_onsets_seconds",
)
AUDIO_DROP_KEYS = (
    "energy_jump_candidates",
    "drop_or_release_seconds",
    "drop_release_markers",
    "drop_or_release_gates",
)
AUDIO_LYRIC_KEYS = (
    "lyric_gate_seconds",
    "lyric_gates",
    "lyric_markers",
    "lyric_or_section_gates",
    "vocal_or_lyric_gates",
)


def load_yaml(path: Path) -> dict[str, Any]:
    payload = load_unique_yaml(path) or {}
    if not isinstance(payload, dict):
        raise SystemExit(f"Expected mapping YAML: {path}")
    return payload


def load_json(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text())
    if not isinstance(payload, dict):
        raise SystemExit(f"Expected JSON object: {path}")
    return payload


def parse_fraction(value: Any) -> Fraction:
    if isinstance(value, dict):
        return Fraction(int(value["numerator"]), int(value["denominator"]))
    if isinstance(value, str) and "/" in value:
        return Fraction(value)
    return Fraction(str(value))


def recipe_fps(recipe: dict[str, Any]) -> Fraction:
    value = (
        (recipe.get("render_spec") or {}).get("fps")
        or (recipe.get("timebase") or {}).get("fps")
        or recipe.get("fps")
        or 24
    )
    try:
        fps = parse_fraction(value)
    except (KeyError, TypeError, ValueError, ZeroDivisionError) as exc:
        raise SystemExit(f"invalid recipe FPS {value!r}: {exc}") from exc
    if fps <= 0:
        raise SystemExit("recipe FPS must be positive")
    return fps


def number_list(values: Any, *keys: str) -> list[float]:
    result: list[float] = []
    if values is None:
        rows: list[Any] = []
    elif isinstance(values, list | tuple):
        rows = list(values)
    else:
        rows = [values]
    for value in rows:
        raw = value
        if isinstance(value, dict):
            raw = None
            for key in keys:
                if value.get(key) is not None:
                    raw = value[key]
                    break
        try:
            result.append(float(raw))
        except (TypeError, ValueError):
            continue
    return result


def nearest_frame(
    frame_value: int, candidates: list[float], fps: Fraction
) -> tuple[float | None, float | None]:
    if not candidates:
        return None, None
    best = min(candidates, key=lambda t: abs((Fraction(str(t)) * fps) - frame_value))
    delta = float(Fraction(str(best)) * fps - frame_value)
    return best, delta


def frame_from_seconds(value: Any, fps: Fraction) -> int:
    """Round non-negative seconds to the nearest frame, halves upward."""
    return int(Fraction(str(float(value))) * fps + Fraction(1, 2))


def coverage_digest(event_ids: list[str]) -> str:
    payload = "".join(f"{event_id}\n" for event_id in sorted(set(event_ids)))
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def segment_slot(segment: dict[str, Any]) -> str:
    return str(segment.get("slot") or segment.get("marker_slot_ref") or "").strip()


def segment_marker_slot(segment: dict[str, Any]) -> str:
    return str(segment.get("marker_slot_ref") or segment.get("slot") or "").strip()


def segment_sections(segment: dict[str, Any]) -> list[str]:
    values = segment.get("section_ids")
    if values is None:
        values = [segment.get("section_id")] if segment.get("section_id") else []
    if isinstance(values, str):
        values = [values]
    return [str(value) for value in (values or []) if str(value).strip()]


def cut_frame(segment: dict[str, Any], fps: Fraction) -> int:
    if segment.get("output_out_frame") is not None:
        return int(segment["output_out_frame"])
    seconds = segment.get("output_out", segment.get("output_in", 0.0))
    return int(round(float(seconds) * float(fps)))


def segment_frame_range(
    segment: dict[str, Any], fps: Fraction
) -> tuple[int, int]:
    if segment.get("output_in_frame") is not None:
        start = int(segment["output_in_frame"])
    else:
        start = frame_from_seconds(segment.get("output_in", 0.0), fps)
    if segment.get("output_out_frame") is not None:
        end = int(segment["output_out_frame"])
    else:
        end = frame_from_seconds(segment.get("output_out", 0.0), fps)
    return start, end


def sections_for_frame(
    timeline: list[dict[str, Any]], frame: int, fps: Fraction
) -> list[str]:
    for segment in timeline:
        if not isinstance(segment, dict):
            continue
        start, end = segment_frame_range(segment, fps)
        if start <= frame < end:
            return segment_sections(segment)
    return []


def time_values(payload: dict[str, Any], keys: tuple[str, ...]) -> list[float]:
    values: list[float] = []
    for key in keys:
        values.extend(
            number_list(
                payload.get(key),
                "time_seconds",
                "time_sec",
                "seconds",
                "start_seconds",
                "program_time",
            )
        )
    return values


def audio_gate_times(payload: dict[str, Any]) -> dict[str, list[float]]:
    onsets = time_values(payload, AUDIO_ONSET_KEYS)
    drops = time_values(payload, AUDIO_DROP_KEYS)
    lyrics = time_values(payload, AUDIO_LYRIC_KEYS)
    for row in payload.get("cue_tempo_map") or []:
        if not isinstance(row, dict):
            continue
        onsets.extend(number_list(row.get("nearby_strong_onsets_seconds")))
        drops.extend(time_values(row, AUDIO_DROP_KEYS))
        lyrics.extend(time_values(row, AUDIO_LYRIC_KEYS))
    return {
        "onset_gate": sorted(set(onsets)),
        "drop_or_release": sorted(set(drops)),
        "lyric_gate": sorted(set(lyrics)),
    }


def expected_coverage_events(
    recipe: dict[str, Any],
    marker_plan: dict[str, Any],
    audio_summary: dict[str, Any],
    fps: Fraction,
) -> list[dict[str, Any]]:
    timeline = [row for row in (recipe.get("timeline") or []) if isinstance(row, dict)]
    if not timeline:
        return []
    _program_start, program_end = segment_frame_range(timeline[-1], fps)
    events: dict[str, dict[str, Any]] = {}

    def add(
        event_id: str,
        frame: int,
        kind: str,
        source: str,
        section_ids: list[str],
        **detail: Any,
    ) -> None:
        if frame < 0 or frame >= program_end:
            return
        events[event_id] = {
            "event_id": event_id,
            "program_frame": frame,
            "kind": kind,
            "source": source,
            "section_ids": sorted(set(section_ids)),
            **detail,
        }

    for index in range(len(timeline) - 1):
        left = timeline[index]
        right = timeline[index + 1]
        left_slot = segment_slot(left) or f"IDX{index + 1:03d}"
        right_slot = segment_slot(right) or f"IDX{index + 2:03d}"
        frame = cut_frame(left, fps)
        left_sections = sorted(set(segment_sections(left)))
        right_sections = sorted(set(segment_sections(right)))
        section_ids = sorted(set(left_sections + right_sections))
        add(
            f"recipe_cut:{left_slot}:{right_slot}:f{frame}",
            frame,
            "story_handoff",
            "recipe",
            section_ids,
            outgoing_slot=left_slot,
            incoming_slot=right_slot,
        )
        if left_sections and right_sections and left_sections != right_sections:
            left_token = "+".join(left_sections)
            right_token = "+".join(right_sections)
            add(
                f"recipe_section:{left_token}>{right_token}:f{frame}",
                frame,
                "section_boundary",
                "recipe",
                section_ids,
                outgoing_slot=left_slot,
                incoming_slot=right_slot,
            )

    for index, row in enumerate(marker_plan.get("timeline_slots") or [], start=1):
        if not isinstance(row, dict):
            continue
        slot = str(row.get("slot") or f"IDX{index:03d}").strip()
        sections = [str(row.get("section_id"))] if row.get("section_id") else []
        nearby = row.get("nearby_markers") or {}
        if not isinstance(nearby, dict):
            nearby = {}
        for value in number_list(nearby.get("strong_onsets_seconds")):
            frame = frame_from_seconds(value, fps)
            add(
                f"marker_onset:{slot}:f{frame}",
                frame,
                "onset_gate",
                "marker_plan",
                sections or sections_for_frame(timeline, frame, fps),
                marker_slot=slot,
            )
        for value in number_list(nearby.get("feature_boundaries_seconds")):
            frame = frame_from_seconds(value, fps)
            add(
                f"marker_drop:{slot}:f{frame}",
                frame,
                "drop_or_release",
                "marker_plan",
                sections or sections_for_frame(timeline, frame, fps),
                marker_slot=slot,
            )
        if str(nearby.get("lyric_or_section_handoff") or "").strip():
            output_range = row.get("output_range") or {}
            if isinstance(output_range, dict) and output_range.get("start_frame") is not None:
                frame = int(output_range["start_frame"])
            else:
                frame = frame_from_seconds(
                    (output_range or {}).get("start_seconds", 0.0), fps
                )
            add(
                f"marker_lyric:{slot}:f{frame}",
                frame,
                "lyric_gate",
                "marker_plan",
                sections or sections_for_frame(timeline, frame, fps),
                marker_slot=slot,
            )

    for kind, values in audio_gate_times(audio_summary).items():
        prefix = {
            "onset_gate": "audio_onset",
            "drop_or_release": "audio_drop",
            "lyric_gate": "audio_lyric",
        }[kind]
        for value in values:
            frame = frame_from_seconds(value, fps)
            add(
                f"{prefix}:f{frame}",
                frame,
                kind,
                "audio_or_cue_map",
                sections_for_frame(timeline, frame, fps),
            )
    return sorted(events.values(), key=lambda row: (row["program_frame"], row["event_id"]))


def marker_slots(marker_plan: dict[str, Any]) -> dict[str, dict[str, Any]]:
    result: dict[str, dict[str, Any]] = {}
    for row in marker_plan.get("timeline_slots") or []:
        if not isinstance(row, dict):
            continue
        slot = str(row.get("slot") or "").strip()
        if slot:
            result[slot] = row
    return result


def phase_evidence(
    summary: dict[str, Any], precision: dict[str, Any]
) -> tuple[str, list[float], str]:
    for label, payload in (("audio_summary", summary), ("precision_map", precision)):
        phase = payload.get("meter_phase") or {}
        if phase.get("status") != "manual_locked":
            continue
        candidates = number_list(
            payload.get("bar_start_locked_seconds"), "time_seconds", "time_sec"
        )
        candidates += number_list(
            payload.get("bar_start_locked_markers"), "time_seconds", "time_sec"
        )
        candidates += number_list(
            payload.get("beat_2_4_phase_locked_seconds"), "time_seconds", "time_sec"
        )
        candidates += number_list(
            payload.get("beat_2_4_phase_locked_markers"), "time_seconds", "time_sec"
        )
        return "manual_locked", sorted(set(candidates)), label
    return "unverified_candidate", [], "none"


def visible_hit_evidence(marker: dict[str, Any] | None) -> tuple[bool, list[str]]:
    if not marker:
        return False, []
    basis = {str(value) for value in marker.get("alignment_basis") or []}
    action = marker.get("source_action_marker") or {}
    decision = marker.get("incoming_cut_decision") or {}
    action_bits = [
        str(action.get(key) or "").strip()
        for key in ("visible_event", "body_part_or_motion", "camera_event")
    ]
    evidence_bits = [
        str(decision.get(key) or "").strip()
        for key in ("pre_cut_evidence", "cut_frame_evidence", "post_cut_evidence")
    ]
    has_named_action = any(action_bits)
    has_visible_basis = bool(basis & VISIBLE_ALIGNMENT_TERMS)
    has_cut_evidence = any(evidence_bits)
    labels = sorted(basis & VISIBLE_ALIGNMENT_TERMS)
    labels += [bit for bit in action_bits if bit]
    return has_named_action and (has_visible_basis or has_cut_evidence), labels


def marker_route(marker: dict[str, Any] | None) -> tuple[str | None, dict[str, Any]]:
    if not marker:
        return None, {}
    decision = marker.get("incoming_cut_decision") or {}
    if not isinstance(decision, dict):
        return None, {}
    return decision.get("route"), decision


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Seed conservative draft 04FX transition review points."
    )
    parser.add_argument("--recipe", type=Path, required=True)
    parser.add_argument("--audio-summary", type=Path, required=True)
    parser.add_argument("--precision-map", type=Path)
    parser.add_argument(
        "--marker-plan",
        type=Path,
        help="04 marker plan used only to strengthen review evidence; the seed never selects FX.",
    )
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument(
        "--safe-default-effect",
        default=None,
        help=(
            "Deprecated compatibility hint. The v2 seed records it but does not "
            "preselect or apply an effect."
        ),
    )
    parser.add_argument(
        "--onset-match-frames",
        type=int,
        default=3,
        help="Maximum frame delta for onset/section-gate review evidence.",
    )
    parser.add_argument(
        "--impact-match-frames",
        type=int,
        default=1,
        help="Maximum frame delta for energy-impact review evidence.",
    )
    args = parser.parse_args()

    if args.onset_match_frames < 0 or args.impact_match_frames < 0:
        parser.error("frame tolerances must be non-negative")

    recipe = load_yaml(args.recipe)
    summary = load_json(args.audio_summary)
    precision = load_json(args.precision_map) if args.precision_map else {}
    marker_plan = load_yaml(args.marker_plan) if args.marker_plan else {}
    marker_by_slot = marker_slots(marker_plan)
    fps = recipe_fps(recipe)

    timeline = recipe.get("timeline") or []
    if not isinstance(timeline, list) or not timeline:
        raise SystemExit("recipe.timeline is empty")

    gates = audio_gate_times(summary)
    onset_times = gates["onset_gate"]
    energy_jumps = gates["drop_or_release"]
    phase_status, locked_phase_times, phase_source = phase_evidence(summary, precision)
    expected_events = expected_coverage_events(recipe, marker_plan, summary, fps)
    events_by_frame: dict[int, list[dict[str, Any]]] = defaultdict(list)
    for event in expected_events:
        events_by_frame[int(event["program_frame"])].append(event)

    points: list[dict[str, Any]] = []
    evidence_index: dict[str, dict[str, Any]] = {}
    boundary_index = 0
    gate_index = 0
    for frame in sorted(events_by_frame):
        frame_events = sorted(events_by_frame[frame], key=lambda row: row["event_id"])
        coverage_ids = [str(row["event_id"]) for row in frame_events]
        coverage_kinds = sorted(
            {str(row["kind"]) for row in frame_events},
            key=lambda value: EVENT_KIND_PRIORITY[value],
        )
        primary_kind = coverage_kinds[0]
        section_ids = sorted(
            {
                section_id
                for row in frame_events
                for section_id in row.get("section_ids") or []
            }
        )
        recipe_cut = next(
            (
                row
                for row in frame_events
                if str(row["event_id"]).startswith("recipe_cut:")
            ),
            None,
        )
        marker_ref = str((recipe_cut or {}).get("incoming_slot") or "")
        marker = marker_by_slot.get(marker_ref)
        decision_route, decision = marker_route(marker)
        visible_hit, visible_labels = visible_hit_evidence(marker)
        slot_status = str((marker or {}).get("slot_status") or "unknown")
        method = str(decision.get("method") or "")
        no_effect_pass = bool(decision.get("no_effect_pass"))
        near_onset, onset_delta_f = nearest_frame(frame, onset_times, fps)
        near_jump, jump_delta_f = nearest_frame(frame, energy_jumps, fps)
        near_phase, phase_delta_f = nearest_frame(frame, locked_phase_times, fps)
        onset_aligned = onset_delta_f is not None and abs(onset_delta_f) <= args.onset_match_frames
        energy_aligned = jump_delta_f is not None and abs(jump_delta_f) <= args.impact_match_frames
        phase_aligned = phase_delta_f is not None and abs(phase_delta_f) <= args.onset_match_frames

        if recipe_cut:
            boundary_index += 1
            outgoing = str(recipe_cut.get("outgoing_slot") or "LEFT")
            incoming = str(recipe_cut.get("incoming_slot") or "RIGHT")
            point_id = f"SEED_B{boundary_index:03d}_{outgoing}_{incoming}"
            if slot_status in RETURN_TO_04_STATUSES or decision_route == "return_04":
                review_signal = "return_to_04"
                rationale = (
                    f"04 marker {marker_ref or incoming} is {slot_status!r} or routes back to 04; "
                    "FX cannot repair source timing, continuity, or cutpoint truth."
                )
            elif method in NO_EFFECT_METHODS and no_effect_pass and decision_route == "keep_04":
                review_signal = "explicit_no_effect_pass"
                rationale = (
                    f"04 explicitly passes {method} without an effect at frame {frame}; "
                    "confirm that the readable hard/action cut still holds on full-master playback."
                )
            elif decision_route == "send_04fx" and visible_hit and (
                onset_aligned or energy_aligned or phase_aligned
            ):
                review_signal = "boundary_with_visible_fx_route"
                rationale = (
                    f"Recipe boundary at frame {frame} has a visible 04 action and aligned "
                    "audio evidence; review playback before authoring any linked FX record."
                )
            else:
                review_signal = "measured_boundary_review"
                rationale = (
                    f"Recipe boundary at frame {frame} is mandatory audit coverage; decide from "
                    "full-master playback whether the cut needs no effect, a reviewed FX proposal, "
                    "or a return to 04."
                )
        else:
            gate_index += 1
            point_id = f"SEED_G{gate_index:03d}_F{frame:06d}"
            review_signal = "standalone_hash_bound_gate"
            labels = ", ".join(coverage_kinds)
            rationale = (
                f"Standalone hash-bound {labels} event at frame {frame} is mandatory review "
                "coverage; measurement alone does not select or pass an effect."
            )

        seconds = float(Fraction(frame, 1) / fps)
        point = {
            "point_id": point_id,
            "program_time": round(seconds, 6),
            "program_frame": frame,
            "kind": primary_kind,
            "section_ids": section_ids,
            "coverage_event_ids": coverage_ids,
            "coverage_kinds": coverage_kinds,
            "disposition": "review_candidate",
            "rationale": rationale,
            "evidence_ref": f"evidence_index.{point_id}",
        }
        points.append(point)
        evidence_index[point_id] = {
            "program_frame": frame,
            "program_seconds_projection": round(seconds, 6),
            "coverage_events": frame_events,
            "nearest_onset_seconds": near_onset,
            "onset_delta_frames": round(onset_delta_f, 4) if onset_delta_f is not None else None,
            "nearest_energy_jump_seconds": near_jump,
            "energy_jump_delta_frames": round(jump_delta_f, 4) if jump_delta_f is not None else None,
            "meter_phase_status": phase_status,
            "nearest_locked_phase_seconds": near_phase,
            "locked_phase_delta_frames": round(phase_delta_f, 4) if phase_delta_f is not None else None,
            "marker_slot_ref": marker_ref or None,
            "marker_slot_status": slot_status,
            "incoming_cut_method": method or None,
            "incoming_cut_route": decision_route,
            "no_effect_pass": no_effect_pass,
            "visible_action_evidence": visible_labels,
            "review_signal": review_signal,
        }

    doc = {
        "schema": "idol_04fx_transition_opportunity_seed.v2",
        "status": "draft_seed_only",
        "catalog_ref": "skills/idol-edit-finishing-fx/references/local-ffmpeg-transition-effect-catalog.md",
        "effect_registry_ref": "automation/edit-effect-registry.yaml",
        "source_recipe": str(args.recipe),
        "source_audio_summary": str(args.audio_summary),
        "source_precision_map": str(args.precision_map) if args.precision_map else None,
        "source_marker_plan": str(args.marker_plan) if args.marker_plan else None,
        "timebase": {
            "fps": {"numerator": fps.numerator, "denominator": fps.denominator},
            "canonical_unit": "frames",
        },
        "phase_evidence": {
            "status": phase_status,
            "source": phase_source,
            "locked_marker_count": len(locked_phase_times),
            "unverified_phase_used_for_candidate_ranking": False,
        },
        "human_review_required": True,
        "not_allowed_to_lock": [
            "source_in",
            "source_out",
            "speed_factor",
            "final_cutpoint",
            "fx_pass",
            "founder_pass_fail",
        ],
        "transition_opportunity_audit": {
            "audit_status": "draft",
            "catalog_ref": "skills/idol-edit-finishing-fx/references/local-ffmpeg-transition-effect-catalog.md",
            "coverage_contract": {
                "coverage_version": "recipe_marker_audio_exact_v1",
                "coverage_scope": "full_master",
                "digest_algorithm": "sha256_sorted_utf8_lines_v1",
                "expected_event_count": len(expected_events),
                "covered_event_count": len(
                    {
                        event_id
                        for point in points
                        for event_id in point["coverage_event_ids"]
                    }
                ),
                "expected_event_ids_sha256": coverage_digest(
                    [str(row["event_id"]) for row in expected_events]
                ),
                "covered_event_ids_sha256": coverage_digest(
                    [
                        event_id
                        for point in points
                        for event_id in point["coverage_event_ids"]
                    ]
                ),
            },
            "safe_defaults_applied": False,
            "note": (
                "Frame/evidence seed only; no effect type or FX record is selected. "
                "Codex/Founder must watch playback, create linked FX records only when justified, "
                "and resolve every candidate before a final 04FX audit."
            ),
            "points": points,
        },
        "seed_summary": {
            "point_count": len(points),
            "review_candidate_count": len(points),
            "section_boundary_count": sum(
                1 for point in points if point["kind"] == "section_boundary"
            ),
            "coverage_event_count": len(expected_events),
            "standalone_gate_point_count": sum(
                1
                for point in points
                if not any(
                    event_id.startswith("recipe_cut:")
                    for event_id in point["coverage_event_ids"]
                )
            ),
            "effect_preselection_count": 0,
            "legacy_safe_default_hint_not_selected": args.safe_default_effect,
        },
        "evidence_index": evidence_index,
    }

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(yaml.safe_dump(doc, allow_unicode=True, sort_keys=False))
    print(args.output)
    print(f"points={len(points)} fps={fps} effect_preselections=0")


if __name__ == "__main__":
    main()
