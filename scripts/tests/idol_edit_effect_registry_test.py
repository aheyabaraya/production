#!/usr/bin/env python3
"""Regression tests for the shared 04FX machine registry contract."""

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

from lib.idol_edit_effect_registry import (  # noqa: E402
    EffectContractError,
    load_effect_registry,
    load_unique_yaml,
)
from validate_json_schema import load_document  # noqa: E402


class EditEffectRegistryTest(unittest.TestCase):
    def test_repository_registry_is_loadable_and_final_xfade_is_handle_bound(self) -> None:
        registry = load_effect_registry()
        self.assertEqual("supported_now", registry.effects["xfade"]["renderer_status"])
        self.assertIn("fade", registry.transitions)
        with self.assertRaisesRegex(EffectContractError, "transition_handle_contract"):
            registry.validate_parameters(
                "xfade",
                {"from_slot": "R01", "to_slot": "R02", "transition": "fade"},
                require_final_xfade_handles=True,
            )

    def test_duplicate_yaml_key_is_rejected_before_registry_use(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "duplicate.yaml"
            path.write_text(
                "schema_version: idol_edit_effect_registry.v1\n"
                "contract:\n"
                "  program_timeline_unit: frames\n"
                "  program_timeline_unit: seconds\n",
                encoding="utf-8",
            )
            with self.assertRaisesRegex(
                yaml.constructor.ConstructorError, "duplicate key"
            ):
                load_unique_yaml(path)
            with self.assertRaisesRegex(
                yaml.constructor.ConstructorError, "duplicate key"
            ):
                load_document(path)

    def test_unknown_effect_parameter_fails_closed(self) -> None:
        registry = load_effect_registry()
        with self.assertRaisesRegex(EffectContractError, "unsupported parameters"):
            registry.validate_parameters(
                "punch_zoom",
                {"factor": 1.04, "invented_parameter": 99},
            )

    def test_filter_facing_color_and_text_position_values_are_constrained(self) -> None:
        registry = load_effect_registry()
        with self.assertRaisesRegex(EffectContractError, "must be color"):
            registry.validate_parameters("flash", {"color": "white,negate"})
        with self.assertRaisesRegex(EffectContractError, "unsupported filter syntax"):
            registry.validate_parameters(
                "drawtext_hit", {"text": "SIGNAL", "x": "0,negate"}
            )


if __name__ == "__main__":
    unittest.main()
