#!/usr/bin/env python3
"""Validate active IDOL 04 v3 edit recipes with screen-node lineage checks.

Earlier recipe versions remain historical evidence only and fail active
validation.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import subprocess
from fractions import Fraction
from pathlib import Path
from typing import Any

import jsonschema
import yaml

from lib.idol_edit_effect_registry import EffectContractError, load_effect_registry
from lib.idol_run_layout import ACTIVE_RUN_ROOT_RE


ROOT = Path(__file__).resolve().parent.parent
SCHEMA_PATH = ROOT / "schemas" / "edit-recipe.schema.json"
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
EDIT_MAP_SCHEMA_VERSION = "idol_edit_map.v4"
MARKER_PLAN_SCHEMA_VERSION = "idol_edit_marker_plan.v6"


class UniqueKeyLoader(yaml.SafeLoader):
    pass


def construct_unique_mapping(
    loader: UniqueKeyLoader, node: yaml.MappingNode, deep: bool = False
) -> dict[str, Any]:
    mapping: dict[str, Any] = {}
    for key_node, value_node in node.value:
        key = loader.construct_object(key_node, deep=deep)
        if key in mapping:
            raise yaml.constructor.ConstructorError(
                "while constructing a mapping",
                node.start_mark,
                f"duplicate key: {key!r}",
                key_node.start_mark,
            )
        mapping[key] = loader.construct_object(value_node, deep=deep)
    return mapping


UniqueKeyLoader.add_constructor(
    yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, construct_unique_mapping
)


def load_mapping(path: Path) -> dict[str, Any]:
    payload = yaml.load(path.read_text(), Loader=UniqueKeyLoader) or {}
    if not isinstance(payload, dict):
        raise ValueError(f"recipe must be a mapping: {path}")
    return payload


def load_bound_mapping(path: Path, label: str, errors: list[str]) -> dict[str, Any]:
    try:
        payload = yaml.load(path.read_text(), Loader=UniqueKeyLoader) or {}
    except (OSError, yaml.YAMLError) as exc:
        errors.append(f"{label} is not parseable: {exc}")
        return {}
    if not isinstance(payload, dict):
        errors.append(f"{label} must be a mapping")
        return {}
    return payload


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def tool_path(name: str) -> str:
    for prefix in ("/opt/homebrew/bin", "/usr/local/bin"):
        path = Path(prefix) / name
        if path.exists():
            return str(path)
    found = shutil.which(name)
    if not found:
        raise ValueError(f"missing required tool: {name}")
    return found


def probe(path: Path) -> dict[str, Any]:
    result = subprocess.run(
        [
            tool_path("ffprobe"),
            "-v",
            "error",
            "-show_entries",
            "format=duration:stream=codec_type,width,height,r_frame_rate,avg_frame_rate,nb_frames,sample_rate,channel_layout,pix_fmt,color_range,color_space,color_transfer,color_primaries",
            "-of",
            "json",
            str(path),
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    return json.loads(result.stdout)


def infer_run_root(recipe_path: Path) -> Path | None:
    for parent in recipe_path.parents:
        parts = parent.parts
        runs_indices = [index for index, part in enumerate(parts) if part == "runs"]
        if not runs_indices:
            continue
        relative = "/".join(parts[runs_indices[-1] :])
        if ACTIVE_RUN_ROOT_RE.fullmatch(relative) or relative == "runs/2026-07-29/0729_ONE_MOVE":
            return parent
    return None


def resolve_path(value: Any, run_root: Path | None, base: Path) -> Path:
    raw = Path(str(value))
    if raw.is_absolute():
        return raw.resolve()
    if raw.parts and raw.parts[0] in {"runs", "automation", "schemas", "scripts"}:
        return (ROOT / raw).resolve()
    if run_root is not None:
        return (run_root / raw).resolve()
    return (base / raw).resolve()


def fps_fraction(value: Any) -> Fraction:
    if isinstance(value, dict):
        return Fraction(int(value["numerator"]), int(value["denominator"]))
    return Fraction(str(value))


def check_binding(
    binding: Any,
    label: str,
    run_root: Path | None,
    base: Path,
    errors: list[str],
    *,
    allow_stale_sha: bool = False,
) -> Path | None:
    if not isinstance(binding, dict):
        errors.append(f"{label} must be a path/SHA-256 binding")
        return None
    path = resolve_path(binding.get("path", ""), run_root, base)
    if run_root is not None:
        try:
            path.relative_to(run_root.resolve())
        except ValueError:
            errors.append(f"{label} escapes owning run: {path}")
            return None
    if not path.is_file():
        errors.append(f"{label} is not readable: {path}")
        return None
    if not allow_stale_sha and sha256_file(path) != str(binding.get("sha256", "")):
        errors.append(f"{label} SHA-256 mismatch")
    return path


def require_run_owned(
    path: Path, label: str, run_root: Path | None, errors: list[str]
) -> None:
    if run_root is None:
        return
    try:
        path.relative_to(run_root.resolve())
    except ValueError:
        errors.append(f"{label} escapes owning run: {path}")


def validate_legacy(
    payload: dict[str, Any], recipe_path: Path, require_v2: bool, mode: str
) -> tuple[list[str], list[str], dict[str, Any]]:
    errors: list[str] = [
        "idol_edit_recipe.v3 is required; earlier recipe versions are historical evidence only"
    ]
    warnings = [
        "historical recipe diagnostic: frame, hash, color, audio, and delivery locks may be incomplete"
    ]
    timeline = payload.get("timeline") or []
    if not isinstance(timeline, list) or not timeline:
        errors.append("legacy recipe timeline must contain at least one segment")
    prior_out = None
    for index, row in enumerate(timeline):
        if not isinstance(row, dict):
            errors.append(f"timeline[{index}] must be a mapping")
            continue
        try:
            source_in = float(row["source_in"])
            source_out = float(row["source_out"])
            output_in = float(row["output_in"])
            output_out = float(row["output_out"])
            duration = float(row["output_duration"])
        except (KeyError, TypeError, ValueError) as exc:
            errors.append(f"timeline[{index}] legacy timing is invalid: {exc}")
            continue
        if source_out <= source_in or output_out <= output_in or duration <= 0:
            errors.append(f"timeline[{index}] has a nonpositive source/output range")
        if abs((output_out - output_in) - duration) > 1e-3:
            errors.append(f"timeline[{index}] output_duration disagrees with output range")
        if prior_out is not None and abs(output_in - prior_out) > 1e-3:
            errors.append(f"timeline[{index}] creates a legacy timeline gap/overlap")
        prior_out = output_out
    return errors, warnings, {"schema_version": payload.get("schema_version", "legacy")}


def validate_v2(
    payload: dict[str, Any],
    recipe_path: Path,
    run_root: Path | None,
    mode: str,
    *,
    immutable_receipt: bool = False,
) -> tuple[list[str], list[str], dict[str, Any]]:
    errors: list[str] = []
    warnings: list[str] = []
    if immutable_receipt and mode != "final-render":
        errors.append("--immutable-receipt is valid only with mode=final-render")
    schema = json.loads(SCHEMA_PATH.read_text())
    validator = jsonschema.Draft202012Validator(schema)
    for error in sorted(validator.iter_errors(payload), key=lambda item: list(item.path)):
        errors.append(f"schema {error.json_path}: {error.message}")
    if errors:
        return errors, warnings, {"schema_version": payload.get("schema_version")}

    base = recipe_path.parent
    if run_root is not None and payload["content_id"] != run_root.name:
        errors.append(f"content_id must match owning run basename {run_root.name}")
    source_edit_map_path = check_binding(
        payload["source_edit_map"],
        "source_edit_map",
        run_root,
        base,
        errors,
        allow_stale_sha=immutable_receipt,
    )
    if (
        run_root is not None
        and source_edit_map_path is not None
        and source_edit_map_path != (run_root / "04-edit-map.yaml").resolve()
    ):
        errors.append("source_edit_map must resolve to the exact run-root 04-edit-map.yaml")
    marker_plan_path = check_binding(
        payload["source_edit_marker_plan"],
        "source_edit_marker_plan",
        run_root,
        base,
        errors,
    )
    marker_slots: dict[str, dict[str, Any]] = {}
    if source_edit_map_path is not None:
        edit_map = load_bound_mapping(source_edit_map_path, "source_edit_map", errors)
        if edit_map.get("schema_version") != EDIT_MAP_SCHEMA_VERSION:
            errors.append(f"source_edit_map must use active {EDIT_MAP_SCHEMA_VERSION}")
        if edit_map.get("content_id") != payload["content_id"]:
            errors.append("source_edit_map.content_id must match recipe content_id")
        marker_ref = edit_map.get("edit_marker_plan_ref")
        if not isinstance(marker_ref, dict):
            errors.append("source_edit_map.edit_marker_plan_ref must be a v3 path/SHA-256 binding")
        elif marker_plan_path is not None:
            if marker_ref.get("schema") != MARKER_PLAN_SCHEMA_VERSION:
                errors.append(
                    "source_edit_map.edit_marker_plan_ref.schema must be "
                    f"{MARKER_PLAN_SCHEMA_VERSION}"
                )
            edit_marker_path = resolve_path(
                marker_ref.get("path", ""), run_root, source_edit_map_path.parent
            )
            if edit_marker_path != marker_plan_path:
                errors.append(
                    "source_edit_map.edit_marker_plan_ref.path must match "
                    "source_edit_marker_plan.path"
                )
            if marker_ref.get("sha256") != sha256_file(marker_plan_path):
                errors.append("source_edit_map.edit_marker_plan_ref.sha256 mismatch")
    if marker_plan_path is not None:
        marker_plan = load_bound_mapping(
            marker_plan_path, "source_edit_marker_plan", errors
        )
        if marker_plan.get("schema_version") != MARKER_PLAN_SCHEMA_VERSION:
            errors.append(
                f"source_edit_marker_plan must use active {MARKER_PLAN_SCHEMA_VERSION}"
            )
        if marker_plan.get("content_id") != payload["content_id"]:
            errors.append("source_edit_marker_plan.content_id must match recipe content_id")
        timeline_slots = marker_plan.get("timeline_slots")
        if not isinstance(timeline_slots, list) or not timeline_slots:
            errors.append("source_edit_marker_plan.timeline_slots must contain Edit Slots")
        else:
            for index, marker_slot in enumerate(timeline_slots):
                label = f"source_edit_marker_plan.timeline_slots[{index}]"
                if not isinstance(marker_slot, dict):
                    errors.append(f"{label} must be a mapping")
                    continue
                slot_id = marker_slot.get("slot")
                if not isinstance(slot_id, str) or not slot_id:
                    errors.append(f"{label}.slot is required")
                    continue
                if slot_id in marker_slots:
                    errors.append(f"source_edit_marker_plan has duplicate Edit Slot {slot_id}")
                marker_slots[slot_id] = marker_slot
                lineage = marker_slot.get("source_lineage")
                if not isinstance(lineage, dict):
                    errors.append(
                        f"{label}.source_lineage must preserve Branch-Cut/03V lineage"
                    )
                    continue
                origin = lineage.get("source_origin")
                if origin == "03v_production_cut_derived":
                    for field in (
                        "source_03v_cue_ids",
                        "source_core_cut_ids",
                    ):
                        if not isinstance(lineage.get(field), list) or not lineage[field]:
                            errors.append(
                                f"{label}.source_lineage.{field} is required "
                                "for a 03V Production-Cut-derived Edit Slot"
                            )
                    branch_ids = lineage.get("source_branch_cut_ids")
                    if not isinstance(branch_ids, list):
                        errors.append(
                            f"{label}.source_lineage.source_branch_cut_ids must be "
                            "an array; it is empty for an Official Core-only 03V cue"
                        )
                    node = lineage.get("screen_progression_node")
                    if isinstance(node, dict):
                        if node.get("source_03v_cue_ids") != lineage.get(
                            "source_03v_cue_ids"
                        ):
                            errors.append(
                                f"{label}.source_lineage must exact-carry 03V cue ids "
                                "into screen_progression_node"
                            )
                        if [node.get("core_cut_id")] != lineage.get(
                            "source_core_cut_ids"
                        ):
                            errors.append(
                                f"{label}.source_lineage must exact-carry the Official "
                                "Core id into screen_progression_node"
                            )
                        if node.get("branch_cut_ids") != branch_ids:
                            errors.append(
                                f"{label}.source_lineage must exact-carry Branch ids "
                                "into screen_progression_node"
                            )
                elif origin == "current_run_non_production_cut_source":
                    targets = lineage.get("continuity_target_branch_cut_ids")
                    if not isinstance(targets, list) or not targets:
                        errors.append(
                            f"{label}.source_lineage.continuity_target_branch_cut_ids "
                            "is required for a non-Production-Cut source"
                        )
                else:
                    errors.append(f"{label}.source_lineage.source_origin is invalid")

    timebase_fps = fps_fraction(payload["timebase"]["fps"])
    render_fps = fps_fraction(payload["render_spec"]["fps"])
    if timebase_fps != render_fps:
        errors.append("timebase.fps must equal render_spec.fps")
    fps = timebase_fps
    frame_seconds = 1.0 / float(fps)
    half_frame = 0.5 * frame_seconds

    audio = payload["audio_program"]
    audio_path = resolve_path(audio["path"], run_root, base)
    renderer_audio_path = resolve_path(payload["audio_path"], run_root, base)
    require_run_owned(audio_path, "audio_program.path", run_root, errors)
    if audio_path != renderer_audio_path:
        errors.append("audio_path must resolve to audio_program.path")
    if not audio_path.is_file():
        errors.append(f"audio_program.path is not readable: {audio_path}")
    else:
        if sha256_file(audio_path) != audio["sha256"]:
            errors.append("audio_program SHA-256 mismatch")
        audio_probe = probe(audio_path)
        actual_audio_duration = float(audio_probe["format"]["duration"])
        if abs(actual_audio_duration - float(audio["duration_seconds"])) > 0.05:
            errors.append("audio_program.duration_seconds disagrees with ffprobe")
        audio_stream = next(
            (row for row in audio_probe.get("streams", []) if row.get("codec_type") == "audio"),
            {},
        )
        if int(audio_stream.get("sample_rate", 0)) != int(audio["sample_rate"]):
            errors.append("audio_program.sample_rate disagrees with ffprobe")
        if audio_stream.get("channel_layout") and audio_stream.get("channel_layout") != audio["channel_layout"]:
            errors.append("audio_program.channel_layout disagrees with ffprobe")

    timeline = payload["timeline"]
    segment_ids: set[str] = set()
    slots: set[str] = set()
    prior_out_frame = 0
    segment_by_slot: dict[str, dict[str, Any]] = {}
    source_durations: dict[Path, float] = {}
    for index, row in enumerate(timeline):
        label = f"timeline[{index}] {row['segment_id']}"
        if row["segment_id"] in segment_ids:
            errors.append(f"duplicate segment_id {row['segment_id']}")
        segment_ids.add(row["segment_id"])
        if row["slot"] in slots:
            errors.append(f"duplicate slot {row['slot']}")
        slots.add(row["slot"])
        segment_by_slot[row["slot"]] = row
        if row["slot"] != row["marker_slot_ref"]:
            errors.append(f"{label} slot must match marker_slot_ref")
        marker_slot = marker_slots.get(row["marker_slot_ref"])
        if marker_slot is None:
            errors.append(
                f"{label} marker_slot_ref is not present in the active v6 marker plan"
            )
        else:
            if marker_slot.get("section_id") not in row["section_ids"]:
                errors.append(
                    f"{label} section_ids must include the marker plan Edit Slot section"
                )
            if row.get("screen_progression_node") != marker_slot.get("source_lineage", {}).get("screen_progression_node"):
                errors.append(
                    f"{label} must exact-carry the marker-plan screen_progression_node"
                )

        start_frame = int(row["output_in_frame"])
        end_frame = int(row["output_out_frame"])
        duration_frames = int(row["duration_frames"])
        if start_frame != prior_out_frame:
            errors.append(
                f"{label} output_in_frame={start_frame} creates gap/overlap after {prior_out_frame}"
            )
        if end_frame - start_frame != duration_frames:
            errors.append(f"{label} duration_frames disagrees with frame range")
        prior_out_frame = end_frame
        projections = (
            ("output_in", start_frame),
            ("output_out", end_frame),
            ("output_duration", duration_frames),
        )
        for field, frame_value in projections:
            expected = float(Fraction(frame_value, 1) / fps)
            if abs(float(row[field]) - expected) > half_frame:
                errors.append(f"{label} {field} is more than half a frame from frame truth")

        source_path = resolve_path(row["source"], run_root, base)
        require_run_owned(source_path, f"{label} source", run_root, errors)
        if not source_path.is_file():
            errors.append(f"{label} source is not readable: {source_path}")
            continue
        if sha256_file(source_path) != row["source_sha256"]:
            errors.append(f"{label} source SHA-256 mismatch")
        source_probe_path = resolve_path(row["source_probe_ref"], run_root, base)
        require_run_owned(source_probe_path, f"{label} source_probe_ref", run_root, errors)
        if not source_probe_path.is_file():
            errors.append(f"{label} source_probe_ref is not readable: {source_probe_path}")
        elif sha256_file(source_probe_path) != row["source_probe_sha256"]:
            errors.append(f"{label} source_probe_sha256 mismatch")
        if source_path not in source_durations:
            source_durations[source_path] = float(probe(source_path)["format"]["duration"])
        source_in = float(row["source_in"])
        source_out = float(row["source_out"])
        if source_out <= source_in:
            errors.append(f"{label} source_out must exceed source_in")
        if source_out > source_durations[source_path] + half_frame:
            errors.append(f"{label} source_out exceeds ffprobe duration")
        output_duration = float(Fraction(duration_frames, 1) / fps)
        expected_speed = (source_out - source_in) / output_duration
        if abs(float(row["retime"]["speed_factor"]) - expected_speed) > 1e-4:
            errors.append(f"{label} retime.speed_factor disagrees with source/output range")
        if row["retime"]["mode"] == "variable_external_04" and mode == "final-render":
            errors.append(f"{label} variable retime is not supported by the local final renderer")
        grade = row.get("grade", "")
        if grade and grade not in payload["grade_profiles"]:
            errors.append(f"{label} references missing grade profile {grade}")

    program_frames = prior_out_frame
    program_seconds = float(Fraction(program_frames, 1) / fps)
    if audio_path.is_file() and float(audio["duration_seconds"]) + half_frame < program_seconds:
        errors.append("audio program is shorter than the frame-locked video program")

    handle_ids: set[str] = set()
    handled_boundaries: set[tuple[str, str]] = set()
    handles_by_id: dict[str, dict[str, Any]] = {}
    for index, handle in enumerate(payload["boundary_handle_contracts"]):
        label = f"boundary_handle_contracts[{index}] {handle['handle_id']}"
        if handle["handle_id"] in handle_ids:
            errors.append(f"duplicate handle_id {handle['handle_id']}")
        handle_ids.add(handle["handle_id"])
        handles_by_id[handle["handle_id"]] = handle
        boundary = (handle["from_slot"], handle["to_slot"])
        if boundary in handled_boundaries:
            errors.append(f"duplicate boundary handle for {boundary[0]} -> {boundary[1]}")
        handled_boundaries.add(boundary)
        try:
            from_index = next(i for i, row in enumerate(timeline) if row["slot"] == boundary[0])
        except StopIteration:
            errors.append(f"{label} from_slot is not in timeline")
            continue
        if from_index + 1 >= len(timeline) or timeline[from_index + 1]["slot"] != boundary[1]:
            errors.append(f"{label} slots must be exactly adjacent in timeline")
            continue
        outgoing = timeline[from_index]
        incoming = timeline[from_index + 1]
        cut_frame = int(outgoing["output_out_frame"])
        if int(handle["fixed_program_cut_frame"]) != cut_frame:
            errors.append(f"{label} fixed_program_cut_frame must equal adjacent cut frame {cut_frame}")
        if int(incoming["output_in_frame"]) != cut_frame:
            errors.append(f"{label} incoming output frame does not equal fixed cut")
        if int(handle["pre_cut_frames"]) + int(handle["post_cut_frames"]) != int(handle["transition_frames"]):
            errors.append(f"{label} pre_cut_frames + post_cut_frames must equal transition_frames")
        if "fixed_program_cut_seconds" in handle:
            expected_cut = float(Fraction(cut_frame, 1) / fps)
            if abs(float(handle["fixed_program_cut_seconds"]) - expected_cut) > half_frame:
                errors.append(f"{label} fixed_program_cut_seconds disagrees with frame truth")
        outgoing_path = resolve_path(outgoing["source"], run_root, base)
        incoming_path = resolve_path(incoming["source"], run_root, base)
        post_source = float(Fraction(int(handle["post_cut_frames"]), 1) / fps) * float(outgoing["retime"]["speed_factor"])
        pre_source = float(Fraction(int(handle["pre_cut_frames"]), 1) / fps) * float(incoming["retime"]["speed_factor"])
        if outgoing_path in source_durations and float(outgoing["source_out"]) + post_source > source_durations[outgoing_path] + half_frame:
            errors.append(f"{label} outgoing source handle is insufficient")
        if float(incoming["source_in"]) - pre_source < -half_frame:
            errors.append(f"{label} incoming source handle is insufficient")

    for name, profile in payload["grade_profiles"].items():
        if profile.get("lut_path"):
            lut_path = resolve_path(profile["lut_path"], run_root, base)
            if not lut_path.is_file():
                errors.append(f"grade_profiles.{name}.lut_path is not readable")
            elif sha256_file(lut_path) != profile.get("lut_sha256"):
                errors.append(f"grade_profiles.{name}.lut_sha256 mismatch")
        if mode == "final-render" and profile["review_status"] != "pass":
            errors.append(f"grade_profiles.{name} must pass before final render")

    registry = load_effect_registry()
    for index, effect in enumerate(payload["effects"]):
        if not isinstance(effect, dict):
            errors.append(f"effects[{index}] must be a mapping")
            continue
        try:
            canonical = registry.canonical_type(effect.get("type"))
            known = set(registry.payload["common_parameters"]) | set(
                registry.payload["parameter_specs"]
            )
            params = {key: value for key, value in effect.items() if key in known}
            registry.validate_parameters(
                canonical,
                params,
                require_final_xfade_handles=mode == "final-render" and canonical == "xfade",
            )
            if canonical == "xfade":
                handle_ref = effect.get("transition_handle_ref")
                if handle_ref and handle_ref not in handles_by_id:
                    errors.append(f"effects[{index}] transition_handle_ref is unknown")
                if mode == "final-render" and not handle_ref:
                    errors.append(f"effects[{index}] final xfade requires transition_handle_ref")
        except EffectContractError as exc:
            errors.append(f"effects[{index}]: {exc}")

    if mode == "final-render":
        if payload["status"] != "final_render_ready":
            errors.append("final-render mode requires status=final_render_ready")
        if "unknown" in payload["color_pipeline"]["input_interpretation"].lower() and "override" not in payload["color_pipeline"]["transform"].lower():
            errors.append("unknown input color metadata requires an explicit interpretation override")
        delivery_color = payload["color_pipeline"]["delivery"]
        for field in ("color_range", "color_space", "color_transfer", "color_primaries"):
            if str(delivery_color.get(field) or "").strip().lower() == "unknown":
                errors.append(f"final delivery color metadata requires a known {field}")
        mezzanine = payload["delivery_policy"]["mezzanine"]
        video_codec = str(mezzanine["video_codec"]).lower()
        audio_codec = str(mezzanine["audio_codec"]).lower()
        container = str(mezzanine["container"]).lower()
        if video_codec not in {"libx264", "h264", "prores_ks", "prores"}:
            errors.append(f"unsupported local final video codec {video_codec}")
        if audio_codec not in {"aac", "pcm_s16le", "pcm_s24le"}:
            errors.append(f"unsupported local final audio codec {audio_codec}")
        if video_codec in {"prores_ks", "prores"}:
            if container != "mov":
                errors.append("ProRes final delivery requires container=mov")
            if payload["render_spec"]["pixel_format"] not in {
                "yuv422p10le",
                "yuv444p10le",
                "yuva444p10le",
            }:
                errors.append(
                    "ProRes final delivery requires a supported 10-bit 4:2:2/4:4:4 pixel format"
                )
        if audio_codec.startswith("pcm_") and container == "mp4":
            errors.append("PCM final audio is not supported in container=mp4; use mov or mkv")

    report = {
        "schema_version": payload["schema_version"],
        "mode": mode,
        "fps": f"{fps.numerator}/{fps.denominator}",
        "program_frames": program_frames,
        "program_duration_seconds": program_seconds,
        "segment_count": len(timeline),
        "boundary_handle_count": len(payload["boundary_handle_contracts"]),
    }
    return errors, warnings, report


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("recipe", type=Path)
    parser.add_argument("--run-root", type=Path)
    parser.add_argument("--require-v3", action="store_true")
    parser.add_argument("--mode", choices=["preview", "final-render"], default="preview")
    parser.add_argument(
        "--immutable-receipt",
        action="store_true",
        help=(
            "Keep complete recipe/source/audio/handle/delivery validation but "
            "allow only source_edit_map.sha256 to remain the historical "
            "pre-render digest after the live edit map receives closeout status."
        ),
    )
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    if args.immutable_receipt and args.mode != "final-render":
        parser.error("--immutable-receipt requires --mode final-render")
    recipe_path = args.recipe.resolve()
    if not recipe_path.is_file():
        raise SystemExit(f"recipe is not readable: {recipe_path}")
    run_root = args.run_root.resolve() if args.run_root else infer_run_root(recipe_path)
    try:
        payload = load_mapping(recipe_path)
        if payload.get("schema_version") == "idol_edit_recipe.v3":
            errors, warnings, report = validate_v2(
                payload,
                recipe_path,
                run_root,
                args.mode,
                immutable_receipt=args.immutable_receipt,
            )
        else:
            errors, warnings, report = validate_legacy(
                payload, recipe_path, args.require_v3, args.mode
            )
    except (OSError, ValueError, yaml.YAMLError, subprocess.CalledProcessError) as exc:
        errors, warnings, report = [str(exc)], [], {}
    for warning in warnings:
        print(f"WARNING: {warning}")
    if args.report:
        report_payload = {
            "schema_version": "idol_edit_recipe_validation.v1",
            "recipe": str(args.recipe),
            "recipe_sha256": sha256_file(recipe_path),
            "status": "fail" if errors else "pass",
            "errors": errors,
            "warnings": warnings,
            **report,
        }
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(
            yaml.safe_dump(report_payload, allow_unicode=True, sort_keys=False)
        )
    if errors:
        for error in errors:
            print(f"ERROR: {error}")
        raise SystemExit(1)
    print("OK: edit recipe frame, source, retime, handle, color, audio, and delivery contract valid")


if __name__ == "__main__":
    main()
