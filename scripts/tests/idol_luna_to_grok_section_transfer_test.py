#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import sys
import unittest
from copy import deepcopy
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = ROOT / "scripts" / "idol_luna_to_grok_section_transfer.py"


def load_module():
    spec = importlib.util.spec_from_file_location("idol_luna_to_grok_section_transfer", MODULE_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class IdolLunaToGrokSectionTransferTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.mod = load_module()

    def valid_state(self) -> dict:
        return {
            "route_enabled": True,
            "founder_selected_exact_run_and_section": True,
            "simultaneous_owners": False,
            "cdd_review": "complete",
            "cas_generation": 3,
            "expected_cas_generation": 3,
            "luna": {
                "stage": "02b_image_pixel_closed",
                "returned_to": "creative_development_director",
                "active": True,
                "authority": "active",
            },
            "grok": {
                "active": False,
                "authority": "inactive",
                "new_dispatch_and_goal": True,
                "read_before_goal": False,
                "duplicate_generation": False,
            },
            "assignment_record": {
                "source_provider": "cursor",
                "target_provider": "grok",
                "source_session_id": "cursor-luna-1",
                "target_session_id": "grok-03v-1",
                "source_dispatch_id": "D1",
                "target_dispatch_id": "D2",
                "source_goal_id": "G1",
                "target_goal_id": "G2",
                "attempt_id": "A2",
                "section_id": "S01",
                "cut_ids": ["C01"],
                "checkpoint": "chk-1",
                "owner_locks": ["section_owner"],
                "review_receipt": "cdd-pass",
            },
            "carry": {
                "prompts": ["p"],
                "pixels": ["px"],
                "attachments": ["a"],
                "ids": ["id"],
                "output_paths": ["out"],
                "hashes": ["h"],
                "continuity": ["c"],
                "stop_conditions": ["s"],
            },
        }

    def test_disabled_route_holds_without_pretending_physical_transfer_is_enough(self) -> None:
        state = self.valid_state()
        state["route_enabled"] = False
        state["physical_transfer_metadata_present"] = True
        result = self.mod.transfer_section_owner(state)
        self.assertEqual(result["status"], "hold")
        self.assertEqual(result["reason"], "founder_explicit_substitute_required")
        self.assertTrue(result["source_owner_active"])
        self.assertFalse(result["target_owner_active"])

    def test_cas_inactivates_luna_before_grok_authority(self) -> None:
        result = self.mod.transfer_section_owner(self.valid_state())
        self.assertEqual(result["status"], "pass")
        self.assertFalse(result["source_owner_active"])
        self.assertTrue(result["target_owner_active"])

    def test_rollback_denies_grok_and_restores_checkpoint(self) -> None:
        state = self.valid_state()
        state["rollback_requested"] = True
        result = self.mod.transfer_section_owner(state)
        self.assertEqual(result["status"], "rolled_back")
        self.assertTrue(result["source_owner_active"])
        self.assertFalse(result["target_owner_active"])
        self.assertEqual(result["checkpoint"], "chk-1")

    def test_simultaneous_owners_and_duplicate_generation_are_impossible(self) -> None:
        overlapping = self.valid_state()
        overlapping["simultaneous_owners"] = True
        result = self.mod.transfer_section_owner(overlapping)
        self.assertEqual(result["reason"], "simultaneous_owners_forbidden")

        duplicate = self.valid_state()
        duplicate["grok"]["duplicate_generation"] = True
        result = self.mod.transfer_section_owner(duplicate)
        self.assertEqual(result["reason"], "duplicate_generation_impossible")

    def test_rewritten_carry_holds(self) -> None:
        state = self.valid_state()
        state["carry"]["prompts_rewritten"] = True
        result = self.mod.transfer_section_owner(state)
        self.assertEqual(result["reason"], "carry_must_remain_unchanged")

    def test_default_state_copy_does_not_mutate_caller(self) -> None:
        state = self.valid_state()
        original = deepcopy(state)
        self.mod.transfer_section_owner(state)
        self.assertEqual(state, original)


if __name__ == "__main__":
    unittest.main()
