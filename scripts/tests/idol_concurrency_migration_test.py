#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = ROOT / "scripts" / "idol_concurrency_migration.py"


def load_module():
    spec = importlib.util.spec_from_file_location("idol_concurrency_migration", MODULE_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class IdolConcurrencyMigrationTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.mod = load_module()

    def test_current_8_grok_6_cursor_consts_are_authoritative(self) -> None:
        inventory = self.mod.inventory_current_capacity()
        self.assertTrue(inventory["current_still_authoritative"], inventory)
        self.assertEqual(inventory["current_active"]["ordinary_combined_creative_workers"], 14)
        self.assertEqual(inventory["current_active"]["reviewed_maximum_combined_creative_workers"], 14)
        self.assertEqual(inventory["current_active"]["post_02a_sections.ordinary_maximum"], 14)
        self.assertEqual(inventory["current_active"]["post_02a_sections.reviewed_maximum"], 14)
        self.assertEqual(
            inventory["current_active"]["provider_capacity.grok_nonroot.ordinary_maximum"],
            8,
        )
        self.assertEqual(
            inventory["current_active"]["provider_capacity.grok_nonroot.reviewed_maximum"],
            8,
        )
        self.assertEqual(
            inventory["current_active"]["provider_capacity.cursor_nonroot.ordinary_maximum"],
            6,
        )
        self.assertEqual(
            inventory["current_active"]["provider_capacity.cursor_nonroot.reviewed_maximum"],
            6,
        )
        self.assertEqual(
            inventory["current_active"]["pre_02a_development_wave.maximum_active_department_sessions"],
            14,
        )

    def test_8_grok_6_cursor_ceiling_is_founder_activated(self) -> None:
        ceiling = self.mod.future_ceiling()
        self.assertEqual(ceiling["status"], "activated")
        self.assertEqual(ceiling["activation"], "founder_activated_current_request")
        self.assertEqual(ceiling["ordinary_physical_workers"], 14)
        self.assertEqual(ceiling["hard_safety_ceiling"], 14)

    def test_n_less_than_14_keeps_ceiling_and_uses_lower_live_cap(self) -> None:
        result = self.mod.evaluate_activation(observed_n=6)
        self.assertEqual(result["status"], "activated")
        self.assertTrue(result["activated"])
        self.assertFalse(result["replacement_values_invented"])
        self.assertFalse(result["launch_to_fill_capacity"])
        self.assertTrue(result["lower_provider_runtime_cap_always_wins"])
        self.assertEqual(result["observed_n"], 6)
        self.assertEqual(result["effective_live_cap"], 6)
        self.assertIn("lt_14", result["reason"])
        self.assertEqual(result["future_ceiling"]["ordinary_physical_workers"], 14)

    def test_unproven_n_keeps_activated_ceiling(self) -> None:
        result = self.mod.evaluate_activation(observed_n=None)
        self.assertEqual(result["status"], "activated")
        self.assertTrue(result["activated"])
        self.assertIn("live_n_unproven", result["reason"])
        self.assertFalse(result["launch_to_fill_capacity"])

    def test_observed_capacity_cannot_raise_the_hard_ceiling(self) -> None:
        result = self.mod.evaluate_activation(observed_n=20)
        self.assertEqual(result["status"], "activated")
        self.assertEqual(result["effective_live_cap"], 14)
        self.assertFalse(result["launch_to_fill_capacity"])
        self.assertTrue(result["lower_provider_runtime_cap_always_wins"])

    def test_source_only_probe_does_not_claim_live_n(self) -> None:
        probe = self.mod.probe_grok_live_n(allow_network=False)
        self.assertEqual(probe["status"], "hold")
        self.assertIsNone(probe["observed_n"])
        self.assertFalse(probe["hard_safety_ceiling_claimed"])


if __name__ == "__main__":
    unittest.main()
