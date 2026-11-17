#!/usr/bin/env python3
"""Validate active v6 04 marker plans and storyline/screen-node continuity."""

from __future__ import annotations

import argparse
import hashlib
import json
from fractions import Fraction
from pathlib import Path
from typing import Any

import jsonschema
import yaml

from lib.idol_run_layout import ACTIVE_RUN_ROOT_RE


ROOT = Path(__file__).resolve().parent.parent
SCHEMA_PATH = ROOT / "schemas" / "edit-marker-plan.schema.json"


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
        raise ValueError("edit marker plan must be a mapping")
    return payload


def infer_run_root(path: Path) -> Path | None:
    for parent in [path.parent, *path.parents]:
        parts = parent.parts
        runs_indices = [index for index, part in enumerate(parts) if part == "runs"]
        if not runs_indices:
            continue
        relative = "/".join(parts[runs_indices[-1] :])
        if ACTIVE_RUN_ROOT_RE.fullmatch(relative) or relative == "runs/2026-07-29/0729_ONE_MOVE":
            return parent
    return None


def resolve_binding_path(raw: str, plan_path: Path) -> Path:
    candidate = Path(raw)
    if candidate.is_absolute():
        return candidate.resolve()
    repo_candidate = (ROOT / candidate).resolve()
    if repo_candidate.is_file():
        return repo_candidate
    run_root = infer_run_root(plan_path)
    if run_root is not None:
        run_candidate = (run_root / candidate).resolve()
        if run_candidate.is_file():
            return run_candidate
    return (plan_path.parent / candidate).resolve()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def value_sha256(value: Any) -> str:
    payload = json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("plan", type=Path)
    parser.add_argument("--require-v6", action="store_true")
    args = parser.parse_args()
    path = args.plan.resolve()
    if not path.is_file():
        raise SystemExit(f"plan is not readable: {path}")
    try:
        payload = load_mapping(path)
    except (OSError, ValueError, yaml.YAMLError) as exc:
        raise SystemExit(str(exc)) from exc
    schema = json.loads(SCHEMA_PATH.read_text())
    errors = [
        f"schema {error.json_path}: {error.message}"
        for error in jsonschema.Draft202012Validator(schema).iter_errors(payload)
    ]
    version = payload.get("schema_version")
    if args.require_v6 and version != "idol_edit_marker_plan.v6":
        errors.append("idol_edit_marker_plan.v6 is required")
    if version == "idol_edit_marker_plan.v6" and not errors:
        source_manifest: dict[str, Any] = {}
        source_cues_by_id: dict[str, dict[str, Any]] = {}
        source_screen_nodes_by_id: dict[str, dict[str, Any]] = {}
        lineage_sources = payload["production_cut_lineage_sources"]
        for family in (
            "audio_branch_cut_placements",
            "video_prompt_manifests",
            "playback_review_records",
        ):
            for index, binding in enumerate(lineage_sources[family]):
                source_path = resolve_binding_path(binding["path"], path)
                label = f"production_cut_lineage_sources.{family}[{index}]"
                if not source_path.is_file():
                    errors.append(f"{label}.path is not readable: {source_path}")
                elif sha256_file(source_path) != binding["sha256"]:
                    errors.append(f"{label}.sha256 is stale")

        storyline = payload["storyline_lineage_projection"]
        manifest_binding = storyline["source_video_prompt_manifest"]
        manifest_path = resolve_binding_path(manifest_binding["path"], path)
        if not manifest_path.is_file():
            errors.append(
                "storyline_lineage_projection.source_video_prompt_manifest.path "
                f"is not readable: {manifest_path}"
            )
        elif sha256_file(manifest_path) != manifest_binding["sha256"]:
            errors.append(
                "storyline_lineage_projection.source_video_prompt_manifest.sha256 is stale"
            )
        else:
            source_manifest = load_mapping(manifest_path)
            if source_manifest.get("schema_version") != "idol_video_prompt_manifest.v8":
                errors.append("04 storyline source must use idol_video_prompt_manifest.v8")
            source_storyline = (
                source_manifest.get("storyline_lineage_projection", {}).get(
                    "projected_value"
                )
            )
            if storyline["source_value_sha256"] != value_sha256(source_storyline):
                errors.append("04 storyline lineage source hash is stale")
            if storyline["projected_value"] != source_storyline:
                errors.append(
                    "04 must exact-project the complete PRE-00-rooted full-storyline "
                    "lineage from 03V"
                )
            active = storyline["projected_value"].get("active_version", {})
            active_text = str(active.get("full_storyline_text", ""))
            if active.get("full_storyline_text_sha256") != hashlib.sha256(
                active_text.encode("utf-8")
            ).hexdigest():
                errors.append("04 active full storyline text hash is stale")
            declared_video_paths = {
                resolve_binding_path(binding["path"], path)
                for binding in lineage_sources["video_prompt_manifests"]
            }
            if manifest_path not in declared_video_paths:
                errors.append(
                    "04 storyline source is outside production_cut_lineage_sources."
                    "video_prompt_manifests"
                )

            screen = payload["screen_progression_projection"]
            source_screen = source_manifest.get("screen_progression_projection", {}).get(
                "projected_value"
            )
            if screen["source_video_prompt_manifest"] != manifest_binding:
                errors.append("04 storyline and screen progression must bind the same 03V manifest")
            if screen["source_value_sha256"] != value_sha256(source_screen):
                errors.append("04 screen progression source hash is stale")
            if screen["projected_value"] != source_screen:
                errors.append("04 must exact-project screen_progression_map from 03V")
            if isinstance(source_screen, dict):
                for node in source_screen.get("nodes", []):
                    if not isinstance(node, dict):
                        continue
                    node_id = str(node.get("node_id", ""))
                    if node_id:
                        source_screen_nodes_by_id[node_id] = node

            for cue in source_manifest.get("cues", []):
                if not isinstance(cue, dict):
                    continue
                cue_id = str(cue.get("cue_id", ""))
                if cue_id:
                    source_cues_by_id[cue_id] = cue

        audio_map_binding = payload["source_audio_motion_director_map"]
        audio_map_path = resolve_binding_path(audio_map_binding["path"], path)
        if not audio_map_path.is_file():
            errors.append(
                "source_audio_motion_director_map.path is not readable: "
                f"{audio_map_path}"
            )
        elif sha256_file(audio_map_path) != audio_map_binding["sha256"]:
            errors.append("source_audio_motion_director_map.sha256 is stale")

        fps_doc = payload["timebase"]["fps"]
        fps = Fraction(fps_doc["numerator"], fps_doc["denominator"])
        half_frame = 0.5 / float(fps)
        slots = payload["timeline_slots"]
        seen: set[str] = set()
        prior_end = 0
        for index, slot in enumerate(slots):
            label = f"timeline_slots[{index}] {slot['slot']}"
            if slot["slot"] in seen:
                errors.append(f"duplicate slot {slot['slot']}")
            seen.add(slot["slot"])
            frame_range = slot["output_range"]
            start = frame_range["start_frame"]
            end = frame_range["end_frame"]
            duration = frame_range["duration_frames"]
            if start != prior_end:
                errors.append(f"{label} creates frame gap/overlap after {prior_end}")
            if end - start != duration:
                errors.append(f"{label} duration_frames disagrees with frame range")
            prior_end = end
            if abs(frame_range["start_seconds"] - float(Fraction(start, 1) / fps)) > half_frame:
                errors.append(f"{label} start_seconds drifts more than half a frame")
            if abs(frame_range["end_seconds"] - float(Fraction(end, 1) / fps)) > half_frame:
                errors.append(f"{label} end_seconds drifts more than half a frame")
            decision = slot["incoming_cut_decision"]
            if index == 0 and decision is not None:
                errors.append("the first marker slot must have incoming_cut_decision: null")
            if index > 0 and decision is None:
                errors.append(f"{label} requires an incoming_cut_decision")
            if decision and decision["route"] == "send_04fx" and not decision.get("route_reason"):
                errors.append(f"{label} send_04fx requires route_reason")

            lineage = slot["source_lineage"]
            if lineage["source_origin"] == "03v_production_cut_derived":
                node = lineage["screen_progression_node"]
                cue_ids = lineage["source_03v_cue_ids"]
                core_ids = lineage["source_core_cut_ids"]
                branch_ids = lineage["source_branch_cut_ids"]
                if node["source_03v_cue_ids"] != cue_ids:
                    errors.append(
                        f"{label} screen_progression_node.source_03v_cue_ids must "
                        "exact-carry source_lineage.source_03v_cue_ids"
                    )
                if [node["core_cut_id"]] != core_ids:
                    errors.append(
                        f"{label} source_core_cut_ids must exactly contain the "
                        "screen-progression node core_cut_id"
                    )
                if node["branch_cut_ids"] != branch_ids:
                    errors.append(
                        f"{label} source_branch_cut_ids must exact-carry the "
                        "screen-progression node branch_cut_ids"
                    )

                source_node = source_screen_nodes_by_id.get(
                    node["screen_progression_node_id"]
                )
                if source_node is None:
                    errors.append(
                        f"{label} screen_progression_node_id is absent from the "
                        "bound 03V screen_progression_map"
                    )
                else:
                    projected_fields = {
                        "screen_progression_map_id": payload[
                            "screen_progression_projection"
                        ]["projected_value"].get("screen_progression_map_id"),
                        "screen_progression_node_id": source_node.get("node_id"),
                        "section_id": source_node.get("section_id"),
                        "major_scene_id": source_node.get("major_scene_id"),
                        "storyline_role": source_node.get("storyline_role"),
                        "observable_screen_proof": source_node.get(
                            "observable_screen_proof"
                        ),
                    }
                    for field, expected in projected_fields.items():
                        if node.get(field) != expected:
                            errors.append(
                                f"{label} screen_progression_node.{field} does not "
                                "exact-carry the bound 03V screen-progression node"
                            )

                referenced_cues: list[dict[str, Any]] = []
                for cue_id in cue_ids:
                    cue = source_cues_by_id.get(cue_id)
                    if cue is None:
                        errors.append(
                            f"{label} references unknown bound 03V cue {cue_id}"
                        )
                    else:
                        referenced_cues.append(cue)
                if referenced_cues:
                    cue_core_ids = list(
                        dict.fromkeys(str(cue.get("core_cut_id", "")) for cue in referenced_cues)
                    )
                    cue_branch_ids = list(
                        dict.fromkeys(
                            str(branch_id)
                            for cue in referenced_cues
                            for branch_id in cue.get("branch_cut_ids", [])
                        )
                    )
                    if cue_core_ids != core_ids:
                        errors.append(
                            f"{label} source_core_cut_ids do not exact-carry the "
                            "bound 03V cue Core ids"
                        )
                    if cue_branch_ids != branch_ids:
                        errors.append(
                            f"{label} source_branch_cut_ids do not exact-carry the "
                            "bound 03V cue Branch ids"
                        )
                    for cue in referenced_cues:
                        sources = cue.get("source_production_cut_images", [])
                        source_ids = [
                            str(source.get("production_cut_id", ""))
                            for source in sources
                            if isinstance(source, dict)
                        ]
                        source_hashes = [
                            str(source.get("sha256", ""))
                            for source in sources
                            if isinstance(source, dict)
                        ]
                        if source_ids != cue.get("source_image_ids"):
                            errors.append(
                                f"{label} bound 03V cue {cue.get('cue_id')} source "
                                "Production Cut ids are internally inconsistent"
                            )
                        if source_hashes != cue.get("source_pixel_hashes"):
                            errors.append(
                                f"{label} bound 03V cue {cue.get('cue_id')} source "
                                "Production Cut hashes are internally inconsistent"
                            )
                        official_core_ids = [
                            str(source.get("production_cut_id", ""))
                            for source in sources
                            if isinstance(source, dict)
                            and source.get("production_cut_type") == "official_core"
                        ]
                        source_branch_ids = [
                            str(source.get("production_cut_id", ""))
                            for source in sources
                            if isinstance(source, dict)
                            and source.get("production_cut_type") == "branch"
                        ]
                        unknown_types = [
                            source.get("production_cut_type")
                            for source in sources
                            if isinstance(source, dict)
                            and source.get("production_cut_type")
                            not in {"official_core", "branch"}
                        ]
                        if unknown_types:
                            errors.append(
                                f"{label} bound 03V cue {cue.get('cue_id')} has an "
                                "unknown Production Cut type"
                            )
                        if cue.get("core_cut_id") not in official_core_ids:
                            errors.append(
                                f"{label} bound 03V cue {cue.get('cue_id')} does not "
                                "carry its declared Official Core Production Cut"
                            )
                        if source_branch_ids != cue.get("branch_cut_ids"):
                            errors.append(
                                f"{label} bound 03V cue {cue.get('cue_id')} Branch "
                                "Production Cut type/id lineage is inconsistent"
                            )
        phase = payload["audio_phase_lock"]
        if phase["status"] == "manual_locked":
            if phase.get("anchor_seconds") is None or phase.get("anchor_beat_in_bar") is None:
                errors.append("manual_locked audio phase requires anchor_seconds and anchor_beat_in_bar")
            elif phase["anchor_beat_in_bar"] > phase["meter_beats"]:
                errors.append("audio phase anchor_beat_in_bar exceeds meter_beats")
    if errors:
        for error in errors:
            print(f"ERROR: {error}")
        raise SystemExit(1)
    print(
        "OK: v6 edit marker plan storyline, screen-progression and Production-Cut "
        "lineage, audio-map binding, and Edit Segment/Edit Boundary frame "
        "continuity valid"
    )


if __name__ == "__main__":
    main()
