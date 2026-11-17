#!/usr/bin/env python3
"""Validate a hash-bound 04FX compile manifest and compiled output."""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
from pathlib import Path
from typing import Any

import jsonschema
import yaml

from idol_04fx_compile_recipe_effects import build_compile_projection
from lib.idol_edit_effect_registry import (
    EffectContractError,
    load_effect_registry,
    load_unique_yaml,
)


ROOT = Path(__file__).resolve().parent.parent
SCHEMA_PATH = ROOT / "schemas" / "edit-finishing-fx-compile-manifest.schema.json"
FX_VALIDATOR = ROOT / "scripts" / "validate_edit_finishing_fx.rb"
RECIPE_VALIDATOR = ROOT / "scripts" / "validate_edit_recipe.py"
VIDEO_PYTHON = ROOT / "scripts" / "idol-video-python"
EFFECT_REGISTRY = ROOT / "automation" / "edit-effect-registry.yaml"


def load_mapping(path: Path) -> dict[str, Any]:
    payload = load_unique_yaml(path) or {}
    if not isinstance(payload, dict):
        raise ValueError(f"expected mapping: {path}")
    return payload


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def digest_data(value: Any) -> str:
    encoded = json.dumps(
        value, ensure_ascii=False, sort_keys=True, separators=(",", ":")
    ).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def resolve_path(value: str, manifest_path: Path) -> Path:
    raw = Path(value)
    if raw.is_absolute():
        return raw.resolve()
    if raw.parts and raw.parts[0] in {"runs", "automation", "schemas", "scripts"}:
        return (ROOT / raw).resolve()
    local = (manifest_path.parent / raw).resolve()
    if local.exists():
        return local
    return (ROOT / raw).resolve()


def run_validator(command: list[str], label: str, errors: list[str]) -> None:
    result = subprocess.run(
        command,
        cwd=ROOT,
        text=True,
        capture_output=True,
    )
    if result.returncode:
        detail = (result.stdout or result.stderr).strip()
        errors.append(f"{label} failed: {detail}")


def validate_manifest(
    manifest_path: Path,
    *,
    expect_output: Path | None = None,
    require_final: bool = False,
    immutable_receipt: bool = False,
) -> list[str]:
    errors: list[str] = []
    manifest = load_mapping(manifest_path)
    schema = json.loads(SCHEMA_PATH.read_text())
    try:
        jsonschema.Draft202012Validator(schema).validate(manifest)
    except jsonschema.ValidationError as exc:
        errors.append(f"schema: {exc.json_path}: {exc.message}")
        return errors
    if immutable_receipt and (
        not require_final or manifest.get("compile_mode") != "final_pass_only"
    ):
        errors.append(
            "--immutable-receipt requires --require-final and compile_mode=final_pass_only"
        )

    resolved: dict[str, Path] = {}
    for name, binding in manifest["source_bindings"].items():
        path = resolve_path(binding["path"], manifest_path)
        resolved[name] = path
        if not path.is_file():
            errors.append(f"source_bindings.{name} is not readable: {path}")
        elif sha256_file(path) != binding["sha256"]:
            errors.append(f"source_bindings.{name} SHA-256 mismatch")
    registry_binding = resolved.get("effect_registry")
    if registry_binding is not None and registry_binding != EFFECT_REGISTRY.resolve():
        errors.append(
            "source_bindings.effect_registry must resolve to the canonical "
            "automation/edit-effect-registry.yaml"
        )

    output = manifest["compiled_output"]
    output_path = resolve_path(output["path"], manifest_path)
    if not output_path.is_file():
        errors.append(f"compiled_output is not readable: {output_path}")
        return errors
    if sha256_file(output_path) != output["sha256"]:
        errors.append("compiled_output SHA-256 mismatch")
    if expect_output is not None and output_path != expect_output.resolve():
        errors.append(
            f"compiled_output path {output_path} does not match expected {expect_output.resolve()}"
        )

    try:
        output_doc = load_mapping(output_path)
    except ValueError as exc:
        errors.append(str(exc))
        return errors
    effects = output_doc.get("effects") or []
    if not isinstance(effects, list):
        errors.append("compiled output effects must be a list")
        return errors
    compiled_04fx = [
        effect
        for effect in effects
        if isinstance(effect, dict) and effect.get("origin") == "04fx"
    ]
    if digest_data(compiled_04fx) != output["compiled_effects_sha256"]:
        errors.append("compiled 04FX effect-list digest mismatch")
    if digest_data(effects) != output["merged_effects_sha256"]:
        errors.append("merged effect-list digest mismatch")
    if len(effects) != output["total_effect_count"]:
        errors.append("compiled_output.total_effect_count mismatch")
    if len(compiled_04fx) != output["compiled_04fx_count"]:
        errors.append("compiled_output.compiled_04fx_count mismatch")

    selection = manifest["selection"]
    compiled_ids = [str(effect.get("fx_id", "")) for effect in compiled_04fx]
    if compiled_ids != selection["compiled_fx_ids"]:
        errors.append("selection.compiled_fx_ids does not match compiled output order")
    if manifest["compile_mode"] == "final_pass_only":
        if selection["selected_pass_fx_ids"] != compiled_ids:
            errors.append("final selected_pass_fx_ids must equal compiled_fx_ids")
        if selection["skipped_pass_fx_ids"]:
            errors.append("final compile cannot skip passed FX")
        if output["kind"] != "merged_recipe":
            errors.append("final compile output must be a merged recipe")
        fx_map_path = resolved.get("fx_map")
        recipe_path = resolved.get("recipe")
        registry_path = resolved.get("effect_registry")
        if (
            fx_map_path
            and fx_map_path.is_file()
            and recipe_path
            and recipe_path.is_file()
            and registry_path
            and registry_path.is_file()
        ):
            fx_map = load_mapping(fx_map_path)
            recipe = load_mapping(recipe_path)
            if fx_map.get("status") != "passed_for_final_render":
                errors.append("final compile source FX map is not passed_for_final_render")
            expected_recipe_sha = str(
                (fx_map.get("dependency_lock") or {}).get("source_recipe_sha256", "")
            )
            if expected_recipe_sha != sha256_file(recipe_path):
                errors.append("FX map dependency lock does not match source recipe")
            fx_command = ["ruby", str(FX_VALIDATOR)]
            if immutable_receipt:
                fx_command.append("--immutable-receipt")
            fx_command.append(str(fx_map_path))
            run_validator(
                fx_command,
                "source 04FX semantic validation",
                errors,
            )
            try:
                canonical_output, canonical = build_compile_projection(
                    fx_map=fx_map,
                    recipe=recipe,
                    registry=load_effect_registry(registry_path),
                    pass_only=True,
                    merge_into_recipe=True,
                    statuses={"pass"},
                    source_fx_map=str(manifest["source_bindings"]["fx_map"]["path"]),
                    source_recipe=str(manifest["source_bindings"]["recipe"]["path"]),
                )
            except EffectContractError as exc:
                errors.append(f"deterministic canonical projection failed: {exc}")
            else:
                if canonical_output != output_doc:
                    errors.append(
                        "compiled output does not equal the deterministic canonical "
                        "projection from the bound FX map, base recipe, and effect registry "
                        f"(expected {digest_data(canonical_output)}, got {digest_data(output_doc)})"
                    )
                if manifest["merge_policy"]["preserved_base_effect_count"] != canonical[
                    "preserved_base_count"
                ]:
                    errors.append(
                        "merge_policy.preserved_base_effect_count does not match "
                        "the deterministic canonical projection"
                    )
                if manifest["merge_policy"][
                    "replaced_prior_04fx_effect_count"
                ] != canonical["replaced_prior_04fx_count"]:
                    errors.append(
                        "merge_policy.replaced_prior_04fx_effect_count does not match "
                        "the deterministic canonical projection"
                    )
        recipe_command = [
            str(VIDEO_PYTHON),
            str(RECIPE_VALIDATOR),
            str(output_path),
            "--require-v3",
            "--mode",
            "final-render",
        ]
        if immutable_receipt:
            recipe_command.append("--immutable-receipt")
        run_validator(
            recipe_command,
            "compiled final recipe validation",
            errors,
        )
    elif require_final:
        errors.append("final compile manifest required, got preview manifest")

    return errors


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--expect-output", type=Path)
    parser.add_argument("--require-final", action="store_true")
    parser.add_argument(
        "--immutable-receipt",
        action="store_true",
        help=(
            "Rebuild and compare the immutable FX-map/recipe/registry projection "
            "without reopening mutable pre-render edit-map freshness. Use only "
            "after the 04 closeout gate validates the live edit-map receipt chain."
        ),
    )
    args = parser.parse_args()
    if args.immutable_receipt and not args.require_final:
        parser.error("--immutable-receipt requires --require-final")
    manifest_path = args.manifest.resolve()
    if not manifest_path.is_file():
        raise SystemExit(f"manifest is not readable: {manifest_path}")
    try:
        errors = validate_manifest(
            manifest_path,
            expect_output=args.expect_output,
            require_final=args.require_final,
            immutable_receipt=args.immutable_receipt,
        )
    except (OSError, ValueError, yaml.YAMLError) as exc:
        errors = [str(exc)]
    if errors:
        for error in errors:
            print(f"ERROR: {error}")
        raise SystemExit(1)
    print("OK: 04FX compile manifest hashes, selection, and compiled effects are valid")


if __name__ == "__main__":
    main()
