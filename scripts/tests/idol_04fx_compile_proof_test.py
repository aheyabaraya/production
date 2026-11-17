#!/usr/bin/env python3
"""Focused regression proof for immutable 04FX final compilation."""

from __future__ import annotations

import copy
import hashlib
import tempfile
import sys
import unittest
from pathlib import Path
from typing import Any
from unittest import mock

import yaml


ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "scripts"
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))

import validate_edit_finishing_fx_compile as validator  # noqa: E402
from idol_04fx_compile_recipe_effects import (  # noqa: E402
    build_compile_projection,
    digest_data,
)
from lib.idol_edit_effect_registry import (  # noqa: E402
    EffectContractError,
    load_effect_registry,
)


REGISTRY_PATH = ROOT / "automation" / "edit-effect-registry.yaml"


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_yaml(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        yaml.safe_dump(payload, allow_unicode=True, sort_keys=False),
        encoding="utf-8",
    )


class Idol04FxCompileProofTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_context = tempfile.TemporaryDirectory(
            prefix="idol-04fx-compile-proof-", dir="/private/tmp"
        )
        self.temp_root = Path(self.temp_context.name)
        self.registry = load_effect_registry()

    def tearDown(self) -> None:
        self.temp_context.cleanup()

    @staticmethod
    def _base_recipe(effects: list[dict[str, Any]] | None = None) -> dict[str, Any]:
        return {
            "schema_version": "idol_edit_recipe.v3",
            "status": "locked_for_04fx",
            "render_spec": {"fps": {"numerator": 24, "denominator": 1}},
            "timeline": [
                {
                    "segment_id": "SEG_R01",
                    "slot": "R01",
                    "marker_slot_ref": "R01",
                    "screen_progression_node": {
                        "screen_progression_map_id": "SPM_04FX_PROOF",
                        "screen_progression_node_id": "SPN_04FX_PROOF_R01",
                        "section_id": "S01",
                        "major_scene_id": "MJ01",
                        "core_cut_id": "C01",
                        "branch_cut_ids": ["BC01"],
                        "source_03v_cue_ids": ["03VCUE_04FX_PROOF_R01"],
                        "storyline_role": "resolve",
                        "observable_screen_proof": (
                            "The compiled recipe preserves the reviewed S01 screen state."
                        ),
                    },
                }
            ],
            "effects": effects or [],
        }

    @staticmethod
    def _passed_fx_map(recipe_sha256: str) -> dict[str, Any]:
        return {
            "status": "passed_for_final_render",
            "dependency_lock": {"source_recipe_sha256": recipe_sha256},
            "transition_opportunity_audit": {
                "audit_status": "complete_fx_passed"
            },
            "fx_records": [
                {
                    "fx_id": "FX_CANONICAL_PROOF",
                    "status": "pass",
                    "time_range": "0.000-0.125",
                    "effect_design": {
                        "effect_type": "brightness_pulse",
                        "program_start_frame": 0,
                        "duration_frames": 3,
                        "amount": 0.05,
                        "renderer_status": "supported_now",
                    },
                }
            ],
        }

    def _write_final_chain(
        self,
    ) -> tuple[Path, Path, Path, dict[str, Any], dict[str, Any]]:
        recipe_path = self.temp_root / "base-recipe.yaml"
        fx_map_path = self.temp_root / "04FX-finishing-map.yaml"
        output_path = self.temp_root / "compiled-recipe.yaml"
        manifest_path = self.temp_root / "compile-manifest.yaml"
        recipe = self._base_recipe()
        write_yaml(recipe_path, recipe)
        fx_map = self._passed_fx_map(sha256_file(recipe_path))
        write_yaml(fx_map_path, fx_map)
        output, projection = build_compile_projection(
            fx_map=fx_map,
            recipe=recipe,
            registry=self.registry,
            pass_only=True,
            merge_into_recipe=True,
            statuses={"pass"},
            source_fx_map=str(fx_map_path),
            source_recipe=str(recipe_path),
        )
        write_yaml(output_path, output)
        manifest = {
            "schema_version": "idol_04fx_compile_manifest.v1",
            "compile_mode": "final_pass_only",
            "source_bindings": {
                "fx_map": {
                    "path": str(fx_map_path),
                    "sha256": sha256_file(fx_map_path),
                },
                "recipe": {
                    "path": str(recipe_path),
                    "sha256": sha256_file(recipe_path),
                },
                "effect_registry": {
                    "path": str(REGISTRY_PATH),
                    "sha256": sha256_file(REGISTRY_PATH),
                },
            },
            "selection": {
                "audit_status": "complete_fx_passed",
                "selected_pass_fx_ids": projection["selected_ids"],
                "compiled_fx_ids": projection["compiled_ids"],
                "excluded_nonpass_fx_ids": [],
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
                "path": str(output_path),
                "kind": "merged_recipe",
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
        write_yaml(manifest_path, manifest)
        return manifest_path, output_path, recipe_path, manifest, output

    def test_validator_rebuilds_and_rejects_self_consistent_output_tampering(
        self,
    ) -> None:
        manifest_path, output_path, _recipe_path, manifest, output = (
            self._write_final_chain()
        )
        with mock.patch.object(validator, "run_validator") as run_validator:
            self.assertEqual(
                [],
                validator.validate_manifest(
                    manifest_path,
                    require_final=True,
                    immutable_receipt=True,
                ),
            )
            self.assertEqual(2, run_validator.call_count)
            for call in run_validator.call_args_list:
                self.assertIn("--immutable-receipt", call.args[0])

        forged_output = copy.deepcopy(output)
        forged_output["effects"][0]["note"] = "forged but registry-valid mutation"
        write_yaml(output_path, forged_output)
        forged_manifest = copy.deepcopy(manifest)
        compiled_04fx = [
            row
            for row in forged_output["effects"]
            if isinstance(row, dict) and row.get("origin") == "04fx"
        ]
        forged_manifest["compiled_output"]["sha256"] = sha256_file(output_path)
        forged_manifest["compiled_output"]["compiled_effects_sha256"] = digest_data(
            compiled_04fx
        )
        forged_manifest["compiled_output"]["merged_effects_sha256"] = digest_data(
            forged_output["effects"]
        )
        write_yaml(manifest_path, forged_manifest)

        with mock.patch.object(validator, "run_validator") as run_validator:
            errors = validator.validate_manifest(
                manifest_path,
                require_final=True,
                immutable_receipt=True,
            )
            self.assertEqual(2, run_validator.call_count)
            for call in run_validator.call_args_list:
                self.assertIn("--immutable-receipt", call.args[0])
        self.assertTrue(
            any("deterministic canonical projection" in error for error in errors),
            errors,
        )

    def test_zero_fx_allows_metadata_and_passed_04_xfade_but_rejects_hidden_fx(
        self,
    ) -> None:
        fx_map = {
            "transition_opportunity_audit": {
                "audit_status": "complete_no_fx_needed"
            },
            "fx_records": [],
        }
        metadata_recipe = self._base_recipe(
            [
                {
                    "type": "hard_cut_note",
                    "origin": "04_edit",
                    "note": "The reviewed hard cut is intentional.",
                }
            ]
        )
        output, _projection = build_compile_projection(
            fx_map=fx_map,
            recipe=metadata_recipe,
            registry=self.registry,
            pass_only=True,
            merge_into_recipe=True,
            statuses={"pass"},
            source_fx_map="04FX-finishing-map.yaml",
            source_recipe="base-recipe.yaml",
        )
        self.assertEqual(
            ["hard_cut_note"], [row["type"] for row in output["effects"]]
        )

        reviewed_xfade = copy.deepcopy(metadata_recipe)
        reviewed_xfade["effects"].append(
            {
                "type": "xfade",
                "fx_id": "FX_04_REVIEWED_XFADE",
                "origin": "04_edit",
                "status": "pass",
                "start_frame": 24,
                "duration_frames": 4,
                "transition": "fade",
                "from_slot": "R01",
                "to_slot": "R02",
                "transition_handle_ref": "HANDLE_R01_R02",
                "transition_handle_contract": {
                    "mode": "duration_preserving",
                    "fixed_program_cut_frame": 24,
                    "fixed_program_cut_seconds": 1.0,
                    "transition_frames": 4,
                    "pre_cut_frames": 2,
                    "post_cut_frames": 2,
                },
            }
        )
        xfade_output, _projection = build_compile_projection(
            fx_map=fx_map,
            recipe=reviewed_xfade,
            registry=self.registry,
            pass_only=True,
            merge_into_recipe=True,
            statuses={"pass"},
            source_fx_map="04FX-finishing-map.yaml",
            source_recipe="base-recipe.yaml",
        )
        self.assertEqual(
            ["hard_cut_note", "xfade"],
            [row["type"] for row in xfade_output["effects"]],
        )

        hidden_renderable = copy.deepcopy(metadata_recipe)
        hidden_renderable["effects"].append(
            {
                "type": "brightness_pulse",
                "origin": "04_edit",
                "start_frame": 0,
                "duration_frames": 1,
                "amount": 0.05,
            }
        )
        with self.assertRaisesRegex(
            EffectContractError,
            "complete_no_fx_needed forbids hidden renderable base-recipe effects",
        ):
            build_compile_projection(
                fx_map=fx_map,
                recipe=hidden_renderable,
                registry=self.registry,
                pass_only=True,
                merge_into_recipe=True,
                statuses={"pass"},
                source_fx_map="04FX-finishing-map.yaml",
                source_recipe="base-recipe.yaml",
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)
