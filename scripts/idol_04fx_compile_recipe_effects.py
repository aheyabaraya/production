#!/usr/bin/env python3
"""Compile reviewed 04FX records into the existing 04 recipe effect lane.

The compiler is mechanical: it canonicalizes types and parameters through the
shared effect registry, preserves 04-owned base effects, and never changes the
timeline. Final pass-only mode fails if one passed FX cannot be represented.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
import re
import subprocess
import tempfile
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

from lib.idol_edit_effect_registry import (
    EffectContractError,
    EffectRegistry,
    load_effect_registry,
    load_unique_yaml,
)
from lib.idol_run_layout import ACTIVE_RUN_ROOT_RE


ROOT = Path(__file__).resolve().parent.parent
FX_VALIDATOR = ROOT / "scripts" / "validate_edit_finishing_fx.rb"
RECIPE_VALIDATOR = ROOT / "scripts" / "validate_edit_recipe.py"
VIDEO_PYTHON = ROOT / "scripts" / "idol-video-python"
TIME_RANGE_RE = re.compile(
    r"(?P<a>\d+(?:\.\d+)?)\s*[-–—to]+\s*(?P<b>\d+(?:\.\d+)?)",
    re.IGNORECASE,
)


def load_yaml(path: Path) -> dict[str, Any]:
    payload = load_unique_yaml(path) or {}
    if not isinstance(payload, dict):
        raise SystemExit(f"Expected mapping YAML: {path}")
    return payload


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def digest_data(value: Any) -> str:
    encoded = json.dumps(
        value, ensure_ascii=False, sort_keys=True, separators=(",", ":")
    ).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def parse_fps(payload: dict[str, Any]) -> tuple[Fraction, str]:
    render_spec = payload.get("render_spec") or {}
    fps = render_spec.get("fps", payload.get("fps", 24))
    if isinstance(fps, dict):
        numerator = int(fps.get("numerator", 0))
        denominator = int(fps.get("denominator", 0))
        if numerator <= 0 or denominator <= 0:
            raise SystemExit("render_spec.fps numerator/denominator must be positive")
        value = Fraction(numerator, denominator)
    elif isinstance(fps, str):
        value = Fraction(fps)
    else:
        value = Fraction(str(fps))
    if value <= 0:
        raise SystemExit("recipe fps must be positive")
    return value, f"{value.numerator}/{value.denominator}"


def parse_time_range(value: str | None) -> tuple[float | None, float | None]:
    if not value:
        return None, None
    match = TIME_RANGE_RE.search(str(value))
    if not match:
        return None, None
    start = float(match.group("a"))
    end = float(match.group("b"))
    return (end, start) if end < start else (start, end)


def design_parameters(
    record: dict[str, Any], design: dict[str, Any], registry: EffectRegistry
) -> dict[str, Any]:
    parameters = dict(design.get("parameters") or {})
    known = set(registry.payload["common_parameters"]) | set(
        registry.payload["parameter_specs"]
    )
    for key in known:
        declared: list[tuple[str, Any]] = []
        if key in parameters:
            declared.append(("effect_design.parameters", parameters[key]))
        if key in design:
            declared.append(("effect_design", design[key]))
        if key in record:
            declared.append(("fx_record", record[key]))
        if declared:
            first_value = declared[0][1]
            conflicts = [source for source, value in declared[1:] if value != first_value]
            if conflicts:
                sources = ", ".join(source for source, _value in declared)
                raise EffectContractError(
                    f"parameter {key!r} has conflicting duplicate values across {sources}"
                )
            parameters[key] = first_value
    if "transition_handle_contract" in design:
        parameters["transition_handle_contract"] = design[
            "transition_handle_contract"
        ]
    return parameters


def compile_effect(
    record: dict[str, Any],
    *,
    fps: Fraction,
    registry: EffectRegistry,
    require_final: bool,
    boundary_handles: dict[str, dict[str, Any]],
) -> dict[str, Any]:
    design = record.get("effect_design") or {}
    if not isinstance(design, dict):
        raise EffectContractError("effect_design must be a mapping")

    canonical, spec = registry.effect_spec(design.get("effect_type"))
    renderer_status = str(design.get("renderer_status", "supported_now"))
    registry_renderer_status = str(spec["renderer_status"])
    if registry_renderer_status == "metadata_only":
        renderer_status = "metadata_only"
        if str(record.get("status")) == "pass":
            raise EffectContractError(
                f"{canonical}: metadata-only records cannot be passed as finishing FX; "
                "close a clean cut as transition_opportunity_audit disposition=none_needed"
            )
    elif registry_renderer_status != "supported_now":
        raise EffectContractError(
            f"{canonical}: registry renderer_status={registry_renderer_status} cannot compile"
        )
    if renderer_status not in {"supported_now", "metadata_only"}:
        raise EffectContractError(
            f"{canonical}: renderer_status={renderer_status} cannot compile"
        )

    range_start, range_end = parse_time_range(record.get("time_range"))
    raw_start = design.get("program_start_seconds", range_start)
    if raw_start is None:
        raise EffectContractError(
            f"{canonical}: need effect_design.program_start_seconds or parseable time_range"
        )
    start_frame = design.get("program_start_frame")
    if start_frame is None:
        start_frame = round(float(raw_start) * float(fps))
    if not isinstance(start_frame, int) or isinstance(start_frame, bool) or start_frame < 0:
        raise EffectContractError(f"{canonical}: program_start_frame must be an integer >= 0")

    duration_frames = design.get("duration_frames")
    if not isinstance(duration_frames, int) or isinstance(duration_frames, bool):
        if range_start is not None and range_end is not None:
            duration_frames = max(1, round((range_end - range_start) * float(fps)))
        else:
            raise EffectContractError(f"{canonical}: duration_frames must be an integer")
    if duration_frames <= 0:
        raise EffectContractError(f"{canonical}: duration_frames must be > 0")

    start = float(Fraction(start_frame, 1) / fps)
    duration = float(Fraction(duration_frames, 1) / fps)
    parameters = design_parameters(record, design, registry)
    handle_ref = str(design.get("transition_handle_ref", ""))
    if canonical == "xfade" and handle_ref:
        handle = boundary_handles.get(handle_ref)
        if handle is None:
            raise EffectContractError(
                f"xfade: transition_handle_ref {handle_ref!r} is not in source recipe"
            )
        parameters["transition_handle_contract"] = copy.deepcopy(handle)
        parameters["from_slot"] = str(design.get("from_slot") or handle["from_slot"])
        parameters["to_slot"] = str(design.get("to_slot") or handle["to_slot"])
    parameters.update(
        {
            "start": start,
            "duration": duration,
            "start_frame": start_frame,
            "duration_frames": duration_frames,
            "fx_id": str(record.get("fx_id", "")),
            "status": str(record.get("status", "")),
            "origin": "04fx",
        }
    )
    normalized = registry.validate_parameters(
        canonical,
        parameters,
        require_final_xfade_handles=require_final,
    )
    normalized["type"] = canonical
    if canonical == "xfade":
        normalized["transition"] = str(
            normalized.get("transition")
            or normalized.get("xfade_transition")
            or "fade"
        )
        handles = normalized.get("transition_handle_contract")
        if handle_ref:
            normalized["transition_handle_ref"] = handle_ref
        if isinstance(handles, dict):
            fixed_frame = handles["fixed_program_cut_frame"]
            if fixed_frame != start_frame:
                raise EffectContractError(
                    "xfade: fixed_program_cut_frame must equal program_start_frame"
                )
            if handles["transition_frames"] != duration_frames:
                raise EffectContractError(
                    "xfade: transition_frames must equal duration_frames"
                )
            seconds = handles.get("fixed_program_cut_seconds")
            if seconds is not None and abs(float(seconds) - start) > 0.5 / float(fps):
                raise EffectContractError(
                    "xfade: fixed_program_cut_seconds disagrees with fixed_program_cut_frame"
                )
    return normalized


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


def resolve_declared_path(value: Any, run_root: Path) -> Path:
    path = Path(str(value))
    if path.is_absolute():
        return path.resolve()
    text = path.as_posix()
    if text.startswith("runs/"):
        return (ROOT / path).resolve()
    return (run_root / path).resolve()


def validate_final_sources(fx_map_path: Path, recipe_path: Path, fx_map: dict[str, Any]) -> None:
    if fx_map.get("schema_version") != "idol_edit_finishing_fx.v2":
        raise SystemExit("--pass-only final compile requires idol_edit_finishing_fx.v2")
    if fx_map.get("status") != "passed_for_final_render":
        raise SystemExit("--pass-only requires FX map status=passed_for_final_render")
    completed = (fx_map.get("transition_opportunity_audit") or {}).get("audit_status")
    if completed not in {"complete_no_fx_needed", "complete_fx_passed"}:
        raise SystemExit("--pass-only requires a completed final transition opportunity audit")

    result = subprocess.run(
        ["ruby", str(FX_VALIDATOR), str(fx_map_path)],
        cwd=ROOT,
        text=True,
        capture_output=True,
    )
    if result.returncode:
        raise SystemExit(
            "04FX semantic validation failed before final compile:\n"
            + (result.stderr or result.stdout)
        )

    run_root = infer_run_root(fx_map_path.resolve())
    if run_root is None:
        raise SystemExit("cannot infer owning run root for final FX compile")
    declared_recipe = resolve_declared_path(fx_map.get("source_recipe"), run_root)
    if declared_recipe != recipe_path.resolve():
        raise SystemExit(
            f"--recipe {recipe_path} does not match FX source_recipe {declared_recipe}"
        )
    expected_sha = str((fx_map.get("dependency_lock") or {}).get("source_recipe_sha256", ""))
    if sha256_file(recipe_path) != expected_sha:
        raise SystemExit("source recipe SHA-256 does not match FX dependency lock")


def validate_recipe(path: Path, *, mode: str) -> None:
    result = subprocess.run(
        [
            str(VIDEO_PYTHON),
            str(RECIPE_VALIDATOR),
            str(path),
            "--require-v3",
            "--mode",
            mode,
        ],
        cwd=ROOT,
        text=True,
        capture_output=True,
    )
    if result.returncode:
        raise SystemExit(
            f"edit recipe {mode} validation failed:\n"
            + (result.stdout or result.stderr)
        )


def atomic_write_yaml(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            yaml.safe_dump(payload, handle, allow_unicode=True, sort_keys=False)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(tmp_name, path)
    finally:
        if os.path.exists(tmp_name):
            os.unlink(tmp_name)


def default_manifest_path(output: Path) -> Path:
    return output.with_name(f"{output.stem}-compile-manifest{output.suffix}")


def build_compile_projection(
    *,
    fx_map: dict[str, Any],
    recipe: dict[str, Any],
    registry: EffectRegistry,
    pass_only: bool,
    merge_into_recipe: bool,
    statuses: set[str],
    source_fx_map: str,
    source_recipe: str,
) -> tuple[dict[str, Any], dict[str, Any]]:
    """Return the one canonical output projection for the bound inputs.

    Both the writer and the receipt validator call this function.  This keeps a
    compile manifest from becoming self-authenticating: changing an output and
    refreshing its recorded hashes is insufficient unless the output can be
    reproduced exactly from the bound FX map, base recipe, and effect registry.
    """

    fps, fps_text = parse_fps(recipe)
    boundary_handles = {
        str(handle.get("handle_id")): handle
        for handle in (recipe.get("boundary_handle_contracts") or [])
        if isinstance(handle, dict) and handle.get("handle_id")
    }
    allowed = {"pass"} if pass_only else set(statuses)
    records = fx_map.get("fx_records") or []
    if not isinstance(records, list):
        raise EffectContractError("fx_records must be a list")
    all_ids = [
        str(record.get("fx_id", ""))
        for record in records
        if isinstance(record, dict)
    ]
    duplicate_ids = sorted(
        {value for value in all_ids if value and all_ids.count(value) > 1}
    )
    if duplicate_ids:
        raise EffectContractError(
            "duplicate fx_id values: " + ", ".join(duplicate_ids)
        )

    selected_ids: list[str] = []
    excluded: list[dict[str, Any]] = []
    compiled: list[dict[str, Any]] = []
    errors: list[str] = []
    for record in records:
        if not isinstance(record, dict):
            if pass_only:
                errors.append("non-mapping fx_records item")
            continue
        status = str(record.get("status", ""))
        fx_id = str(record.get("fx_id", ""))
        if status not in allowed:
            excluded.append({"fx_id": fx_id, "reason": f"status={status}"})
            continue
        selected_ids.append(fx_id)
        try:
            compiled.append(
                compile_effect(
                    record,
                    fps=fps,
                    registry=registry,
                    require_final=pass_only,
                    boundary_handles=boundary_handles,
                )
            )
        except EffectContractError as exc:
            errors.append(f"fx_id={fx_id}: {exc}")

    compiled_ids = [str(effect.get("fx_id", "")) for effect in compiled]
    if errors or compiled_ids != selected_ids:
        details = errors or [
            f"selected pass ids {selected_ids!r} do not match compiled ids {compiled_ids!r}"
        ]
        raise EffectContractError("FX compile failed:\n- " + "\n- ".join(details))

    existing_effects = recipe.get("effects") or []
    if not isinstance(existing_effects, list):
        raise EffectContractError("recipe.effects must be a list")
    preserved_base = [
        copy.deepcopy(effect)
        for effect in existing_effects
        if not (isinstance(effect, dict) and effect.get("origin") == "04fx")
    ]
    audit_status = (fx_map.get("transition_opportunity_audit") or {}).get(
        "audit_status"
    )
    if pass_only and audit_status == "complete_no_fx_needed":
        if compiled:
            raise EffectContractError(
                "complete_no_fx_needed must compile zero passed 04FX records"
            )
        hidden_renderable: list[str] = []
        for index, effect in enumerate(preserved_base):
            if not isinstance(effect, dict):
                hidden_renderable.append(f"effects[{index}]=non_mapping")
                continue
            try:
                canonical, spec = registry.effect_spec(effect.get("type"))
            except EffectContractError:
                hidden_renderable.append(
                    f"effects[{index}]={effect.get('type') or 'missing_type'}"
                )
                continue
            if spec.get("renderer_status") == "metadata_only":
                continue
            handle = effect.get("transition_handle_contract") or {}
            passed_04_xfade = (
                canonical == "xfade"
                and effect.get("origin") == "04_edit"
                and effect.get("status") == "pass"
                and bool(effect.get("transition_handle_ref"))
                and isinstance(handle, dict)
                and handle.get("mode") == "duration_preserving"
            )
            if not passed_04_xfade:
                hidden_renderable.append(f"effects[{index}]={canonical}")
        if hidden_renderable:
            raise EffectContractError(
                "complete_no_fx_needed forbids hidden renderable base-recipe "
                "effects; only registry metadata-only annotations and explicit "
                "passed duration-preserving origin=04_edit xfade transitions "
                "may remain: "
                + ", ".join(hidden_renderable)
            )

    merged_effects = preserved_base + compiled
    registry_sha256 = sha256_file(ROOT / "automation" / "edit-effect-registry.yaml")
    compile_note = {
        "schema_version": "idol_04fx_compile_note.v2",
        "mode": "final_pass_only" if pass_only else "preview",
        "source_fx_map": source_fx_map,
        "source_recipe": source_recipe,
        "fps": fps_text,
        "selected_fx_ids": selected_ids,
        "compiled_fx_ids": compiled_ids,
        "excluded_nonselected": excluded,
        "preserved_base_effect_count": len(preserved_base),
        "replaced_prior_04fx_effect_count": len(existing_effects)
        - len(preserved_base),
        "effect_registry": "automation/edit-effect-registry.yaml",
        "effect_registry_sha256": registry_sha256,
        "compiled_effects_sha256": digest_data(compiled),
        "merged_effects_sha256": digest_data(merged_effects),
    }
    if merge_into_recipe:
        out_doc = copy.deepcopy(recipe)
        out_doc["effects"] = merged_effects
        out_doc["effects_compile_note"] = compile_note
        if pass_only:
            out_doc["status"] = "final_render_ready"
        output_kind = "merged_recipe"
    else:
        out_doc = {
            "schema_version": "idol_04fx_compiled_recipe_effects.v2",
            **compile_note,
            "effects": merged_effects,
            "usage": (
                "Use --merge-into-recipe for a renderable recipe. This sidecar is "
                "an inspectable effect projection only."
            ),
        }
        output_kind = "effects_projection"

    return out_doc, {
        "audit_status": audit_status,
        "selected_ids": selected_ids,
        "compiled_ids": compiled_ids,
        "excluded": excluded,
        "compiled": compiled,
        "merged_effects": merged_effects,
        "preserved_base_count": len(preserved_base),
        "replaced_prior_04fx_count": len(existing_effects) - len(preserved_base),
        "compile_note": compile_note,
        "output_kind": output_kind,
    }


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Compile reviewed 04FX map records into recipe effects."
    )
    parser.add_argument("--fx-map", type=Path, required=True)
    parser.add_argument("--recipe", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--manifest", type=Path)
    parser.add_argument(
        "--statuses",
        default="pass,preview_needed,draft",
        help="Statuses to include for a preview compile.",
    )
    parser.add_argument(
        "--pass-only", action="store_true", help="Strict final compile of pass records."
    )
    parser.add_argument(
        "--merge-into-recipe",
        action="store_true",
        help="Write a renderable full recipe with 04FX-origin effects replaced.",
    )
    args = parser.parse_args()

    if args.pass_only and not args.merge_into_recipe:
        parser.error("--pass-only requires --merge-into-recipe for a renderable final artifact")

    fx_map_path = args.fx_map.resolve()
    recipe_path = args.recipe.resolve()
    output_path = args.output.resolve()
    if output_path in {fx_map_path, recipe_path}:
        raise SystemExit("--output must not overwrite the source FX map or source recipe")

    fx_map = load_yaml(fx_map_path)
    recipe = load_yaml(recipe_path)
    registry = load_effect_registry()
    if args.pass_only:
        validate_final_sources(fx_map_path, recipe_path, fx_map)
        validate_recipe(recipe_path, mode="preview")

    statuses = {
        value.strip() for value in args.statuses.split(",") if value.strip()
    }
    try:
        out_doc, projection = build_compile_projection(
            fx_map=fx_map,
            recipe=recipe,
            registry=registry,
            pass_only=args.pass_only,
            merge_into_recipe=args.merge_into_recipe,
            statuses=statuses,
            source_fx_map=str(args.fx_map),
            source_recipe=str(args.recipe),
        )
    except EffectContractError as exc:
        raise SystemExit(f"FX compile failed; no output written:\n- {exc}") from exc

    atomic_write_yaml(output_path, out_doc)
    if args.pass_only:
        try:
            validate_recipe(output_path, mode="final-render")
        except SystemExit:
            output_path.unlink(missing_ok=True)
            raise
    manifest_path = (args.manifest or default_manifest_path(args.output)).resolve()
    if manifest_path in {fx_map_path, recipe_path, output_path}:
        output_path.unlink(missing_ok=True)
        raise SystemExit("compile manifest path must be distinct from sources and output")
    manifest = {
        "schema_version": "idol_04fx_compile_manifest.v1",
        "compile_mode": "final_pass_only" if args.pass_only else "preview",
        "source_bindings": {
            "fx_map": {"path": str(args.fx_map), "sha256": sha256_file(fx_map_path)},
            "recipe": {"path": str(args.recipe), "sha256": sha256_file(recipe_path)},
            "effect_registry": {
                "path": "automation/edit-effect-registry.yaml",
                "sha256": projection["compile_note"]["effect_registry_sha256"],
            },
        },
        "selection": {
            "audit_status": projection["audit_status"],
            "selected_pass_fx_ids": projection["selected_ids"] if args.pass_only else [],
            "compiled_fx_ids": projection["compiled_ids"],
            "excluded_nonpass_fx_ids": [row["fx_id"] for row in projection["excluded"]],
            "skipped_pass_fx_ids": [],
        },
        "merge_policy": {
            "policy": "preserve_04_base_replace_prior_04fx",
            "preserved_base_effect_count": projection["preserved_base_count"],
            "replaced_prior_04fx_effect_count": projection[
                "replaced_prior_04fx_count"
            ],
        },
        "compiled_output": {
            "path": str(args.output),
            "kind": projection["output_kind"],
            "sha256": sha256_file(output_path),
            "compiled_effects_sha256": projection["compile_note"][
                "compiled_effects_sha256"
            ],
            "merged_effects_sha256": projection["compile_note"][
                "merged_effects_sha256"
            ],
            "total_effect_count": len(projection["merged_effects"]),
            "compiled_04fx_count": len(projection["compiled"]),
        },
    }
    atomic_write_yaml(manifest_path, manifest)
    print(output_path)
    print(manifest_path)
    print(
        f"compiled={len(projection['compiled'])} excluded={len(projection['excluded'])} "
        f"preserved_base={projection['preserved_base_count']}"
    )


if __name__ == "__main__":
    main()
