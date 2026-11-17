#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from typing import Any

import yaml


ROOT = Path(__file__).resolve().parents[2]
VALIDATOR = ROOT / "scripts" / "validate_harness_assignment_model_routing.py"
SELECTOR = ROOT / "automation" / "harness-assignment-model-routing.yaml"
GRAPH_ROUTING = ROOT / "automation" / "graph-default-routing.yaml"
CURSOR = ROOT / "automation" / "providers" / "cursor-agent-profiles.yaml"
GROK = ROOT / "automation" / "providers" / "grok-build-profiles.yaml"
GROK_SOURCE_RELATIVE = "automation/providers/grok-build-profiles.yaml"
CANONICAL_DIRECTOR_LANE_ID_PATTERNS = {
    "overall": r"^overall$",
    "planning_p1": r"^planning_p1$",
    "planning_p2": r"^planning_p2$",
    "planning_p3_ci": r"^planning_p3_c[1-9][0-9]*$",
    "section_cluster_v_ci": r"^section_cluster_v_c[1-9][0-9]*$",
    "edit_director": r"^edit_director$",
}
DIRECTOR_LANE_PATTERN_LABELS = {
    "overall": "overall",
    "planning_p1": "P1",
    "planning_p2": "P2",
    "planning_p3_ci": "P3",
    "section_cluster_v_ci": "V-Ci",
    "edit_director": "edit_director",
}
DIRECTOR_LANE_PATTERN_GRAMMAR = {
    "overall": "overall",
    "planning_p1": "planning_p1",
    "planning_p2": "planning_p2",
    "planning_p3_ci": "planning_p3_cN",
    "section_cluster_v_ci": "section_cluster_v_cN",
    "edit_director": "edit_director",
}
ASSIGNMENT_DIRECTOR_LANE_ID_PATTERN_PATHS = {
    "overall": ("graph_engineering_director_lanes", "overall", "lane_id_pattern"),
    "planning_p1": ("graph_engineering_director_lanes", "planning_cell", "lanes", "p1", "lane_id_pattern"),
    "planning_p2": ("graph_engineering_director_lanes", "planning_cell", "lanes", "p2", "lane_id_pattern"),
    "planning_p3_ci": ("graph_engineering_director_lanes", "planning_cell", "lanes", "p3_ci", "lane_id_pattern"),
    "section_cluster_v_ci": ("graph_engineering_director_lanes", "section_cluster", "lane_id_pattern"),
    "edit_director": ("graph_engineering_director_lanes", "edit_director", "lane_id_pattern"),
}


class ValidateHarnessAssignmentModelRoutingTest(unittest.TestCase):
    def run_validator(self, root: Path | None = None) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(VALIDATOR), "--root", str(root or ROOT)],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )

    def _set_nested(self, document: dict[str, Any], path: tuple[str, ...], value: Any) -> None:
        cursor: Any = document
        for key in path[:-1]:
            cursor = cursor[key]
        cursor[path[-1]] = value

    def _loosen_lane_id_pattern_consts(self, node: Any) -> None:
        if isinstance(node, dict):
            pattern = node.get("lane_id_pattern")
            if isinstance(pattern, dict) and "const" in pattern:
                node["lane_id_pattern"] = {"type": "string", "minLength": 1}
            for value in node.values():
                self._loosen_lane_id_pattern_consts(value)
        elif isinstance(node, list):
            for item in node:
                self._loosen_lane_id_pattern_consts(item)

    def test_shipped_selector_defaults_to_grok_and_holds_cursor_until_founder_asks(self) -> None:
        result = self.run_validator()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("assignment-model-routing: pass", result.stdout)
        document = yaml.safe_load(SELECTOR.read_text(encoding="utf-8"))
        self.assertEqual(document["selector_policy"]["default_provider"], "grok")
        self.assertEqual(document["selector_policy"]["default_runtime_surface"], "grok_cli")
        self.assertTrue(document["selector_policy"]["non_grok_requires_founder_explicit_substitute"])
        self.assertFalse(document["selector_policy"]["founder_default_switch_required_for_activation"])
        self.assertEqual(
            document["concurrency"]["proposed_future_operational_ceiling"]["status"],
            "activated",
        )
        self.assertEqual(
            document["concurrency"]["proposed_future_operational_ceiling"]["activation"],
            "founder_activated_current_request",
        )
        grok_rows = [row for row in document["assignments"] if row["provider"] == "grok"]
        self.assertGreaterEqual(len(grok_rows), 7)
        for row in grok_rows:
            if row["assignment_id"] in {
                "planning_cdd_p1",
                "planning_cdd_p2",
                "planning_cdd_p3_ci",
                "section_cluster_cdd_v_ci",
            }:
                self.assertEqual(row["activation"], "graph_v2_after_verified_default_switch")
                self.assertEqual(row["status"], "shadow_registered_hold")
                continue
            if row["logical_profile_alias"] == "research_medium":
                self.assertEqual(row["activation"], "disabled_hold")
                self.assertEqual(row["status"], "implementation_required_hold")
                self.assertEqual(row["profile_id"], "grok_worker_medium")
                continue
            self.assertEqual(row["activation"], "default_active")
            self.assertEqual(row["status"], "default_active_grok_cli")
        cursor_rows = [row for row in document["assignments"] if row["provider"] == "cursor"]
        self.assertGreaterEqual(len(cursor_rows), 5)
        for row in cursor_rows:
            self.assertEqual(row["topology"], "new_cursor_physical_chat")
            if row["profile_id"] == "cursor_luna_xhigh" or row["assignment_id"] in {
                "cursor_grok_46_frontier_overall_director",
                "cursor_grok_46_frontier_creative_development_director",
                "cursor_grok_46_frontier_edit_director",
            }:
                self.assertEqual(row["activation"], "disabled_hold")
                self.assertEqual(row["status"], "implementation_required_hold")
                continue
            self.assertEqual(row["activation"], "founder_explicit_substitute")
            self.assertEqual(row["status"], "available_founder_explicit_substitute")
        self.assertEqual(
            document["concurrency"]["proposed_future_operational_ceiling"]["ordinary_physical_workers"],
            14,
        )
        self.assertEqual(
            document["concurrency"]["proposed_future_operational_ceiling"]["hard_safety_ceiling"],
            14,
        )
        lanes = document["graph_engineering_director_lanes"]
        self.assertTrue(lanes["no_fixed_cdd_count"])
        self.assertEqual(lanes["planning_cell"]["lanes"]["p3_ci"]["assignment_id"], "planning_cdd_p3_ci")
        self.assertEqual(lanes["section_cluster"]["assignment_id"], "section_cluster_cdd_v_ci")
        graph_routing = yaml.safe_load(GRAPH_ROUTING.read_text(encoding="utf-8"))
        patterns = graph_routing["cohort_succession"]["lane_id_pattern"]
        self.assertEqual(patterns, CANONICAL_DIRECTOR_LANE_ID_PATTERNS)
        for key, path in ASSIGNMENT_DIRECTOR_LANE_ID_PATTERN_PATHS.items():
            cursor: Any = document
            for part in path:
                cursor = cursor[part]
            self.assertEqual(cursor, patterns[key], key)
        nine = next(row for row in lanes["cohort_partition"]["examples"] if row["section_count"] == 9)
        self.assertEqual(nine["cohorts"], [3, 3, 3])
        p3 = re.compile(patterns["planning_p3_ci"])
        v_ci = re.compile(patterns["section_cluster_v_ci"])
        for index in (1, 2, 3):
            self.assertRegex(f"planning_p3_c{index}", p3)
            self.assertRegex(f"section_cluster_v_c{index}", v_ci)
        assignment_ids = {row["assignment_id"] for row in document["assignments"]}
        self.assertNotIn("planning_cdd_p3_c1", assignment_ids)
        self.assertNotIn("section_cluster_cdd_v_c1", assignment_ids)
        for assignment_id in (
            "overall_director",
            "creative_development_director",
            "edit_director",
            "planning_cdd_p1",
            "planning_cdd_p3_ci",
            "section_cluster_cdd_v_ci",
        ):
            row = next(item for item in document["assignments"] if item["assignment_id"] == assignment_id)
            self.assertEqual(row["logical_profile_alias"], "frontier_director")
            self.assertNotIn(row["profile_id"], {"grok_worker_high", "grok_worker_medium"})

    def test_ordinary_worker_roles_cannot_silently_downgrade_to_high(self) -> None:
        grok_source = yaml.safe_load(GROK.read_text(encoding="utf-8"))
        worker_profile = grok_source["profiles"]["grok_worker_high"]
        self.assertEqual(worker_profile["exact_model"], "grok-4.6")
        self.assertEqual(worker_profile["reasoning_effort"], "xhigh")
        selector = yaml.safe_load(SELECTOR.read_text(encoding="utf-8"))
        worker_rows = [
            row
            for row in selector["assignments"]
            if row.get("provider") == "grok"
            and row.get("profile_id") == "grok_worker_high"
            and row.get("activation") == "default_active"
        ]
        self.assertGreaterEqual(len(worker_rows), 1)
        for row in worker_rows:
            resolved = grok_source["profiles"][row["profile_id"]]
            self.assertEqual(resolved["reasoning_effort"], "xhigh", row["assignment_id"])

        with tempfile.TemporaryDirectory() as tmp:
            sandbox = Path(tmp) / "idol"
            self._copy_routing_tree(sandbox)
            grok_path = sandbox / GROK.relative_to(ROOT)
            grok = yaml.safe_load(grok_path.read_text(encoding="utf-8"))
            grok["profiles"]["grok_worker_high"]["reasoning_effort"] = "high"
            grok_path.write_text(yaml.safe_dump(grok, sort_keys=False), encoding="utf-8")
            digest = hashlib.sha256(grok_path.read_bytes()).hexdigest()
            registry_path = sandbox / "automation" / "harness-provider-profile-registry.yaml"
            registry = yaml.safe_load(registry_path.read_text(encoding="utf-8"))
            self._refresh_source_hash_edges(registry, GROK_SOURCE_RELATIVE, digest)
            registry_path.write_text(yaml.safe_dump(registry, sort_keys=False), encoding="utf-8")
            result = self.run_validator(sandbox)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Grok worker effort must remain xhigh in provider source", result.stderr)

    def test_rejects_model_literal_in_selector(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            sandbox = Path(tmp) / "idol"
            self._copy_routing_tree(sandbox)
            selector = yaml.safe_load((sandbox / SELECTOR.relative_to(ROOT)).read_text(encoding="utf-8"))
            selector["assignments"][0]["notes"] = "do not use grok-4.6 here"
            (sandbox / SELECTOR.relative_to(ROOT)).write_text(
                yaml.safe_dump(selector, sort_keys=False),
                encoding="utf-8",
            )
            result = self.run_validator(sandbox)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("must not contain provider model literals", result.stderr)

    def test_rejects_headless_grok_route_without_matching_native_goal(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            sandbox = Path(tmp) / "idol"
            self._copy_routing_tree(sandbox)
            contract_path = sandbox / "automation" / "harness-execution-contract.yaml"
            contract = yaml.safe_load(contract_path.read_text(encoding="utf-8"))
            grok = contract["studio_session_routing"]["provider_adapters"]["grok"]
            grok["runtime_surface"] = "registered_grok_native_or_headless_session"
            grok["lifecycle_operations"]["create"] = "native_or_headless_create"
            grok["goal_admission"]["headless_without_matching_native_goal_event"] = "allowed"
            grok["goal_admission"]["unavailable_action"] = "continue_without_goal"
            contract_path.write_text(yaml.safe_dump(contract, sort_keys=False), encoding="utf-8")

            result = self.run_validator(sandbox)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("admit only TUI /goal or ACP matching native Goal", result.stderr)
            self.assertIn("HOLD with zero work and zero output", result.stderr)

    def test_rejects_making_fable_or_luna_the_default_route(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            sandbox = Path(tmp) / "idol"
            self._copy_routing_tree(sandbox)
            cursor_path = sandbox / CURSOR.relative_to(ROOT)
            cursor = yaml.safe_load(cursor_path.read_text(encoding="utf-8"))
            cursor["profiles"]["cursor_fable_thinking_xhigh"]["default_enabled"] = True
            cursor_path.write_text(yaml.safe_dump(cursor, sort_keys=False), encoding="utf-8")
            result = self.run_validator(sandbox)
            self.assertNotEqual(result.returncode, 0)
            self.assertTrue(
                "default_enabled" in result.stderr or "schema" in result.stderr,
                result.stderr,
            )

    def test_cursor_profiles_are_available_only_as_founder_substitutes(self) -> None:
        document = yaml.safe_load(CURSOR.read_text(encoding="utf-8"))
        self.assertEqual(
            document["capability_evidence"]["goal_identity_independently_observable"],
            "external_goal_record_sha_and_session_id",
        )
        for profile_id in (
            "cursor_opus_thinking_high",
            "cursor_sol_xhigh",
            "cursor_grok_46_xhigh",
            "cursor_luna_max",
            "cursor_luna_xhigh",
            "cursor_gemini_31_pro_thinking_high",
            "cursor_fable_thinking_xhigh",
        ):
            self.assertFalse(document["profiles"][profile_id]["default_enabled"])
        self.assertEqual(document["profiles"]["cursor_fable_thinking_xhigh"]["harness_status"], "active")
        self.assertEqual(
            document["profiles"]["cursor_luna_max"]["media_capability_status"],
            "founder_authorized_optional_image",
        )
        self.assertEqual(document["profiles"]["cursor_luna_max"]["luna_xhigh_alias"], "forbidden")
        self.assertEqual(document["profiles"]["cursor_luna_xhigh"]["harness_status"], "hold")
        self.assertEqual(document["profiles"]["cursor_luna_xhigh"]["exact_model"], "gpt-5.6-luna-xhigh")
        self.assertEqual(document["profiles"]["cursor_luna_xhigh"]["expected_init_display"], "GPT-5.6 Luna 1M Extra High")
        self.assertEqual(document["profiles"]["cursor_luna_xhigh"]["catalog_status"], "live_inventory_verified_2026_09_03")
        self.assertEqual(document["profiles"]["cursor_luna_xhigh"]["luna_max_alias"], "forbidden")
        self.assertFalse(document["profiles"]["cursor_grok_46_xhigh"]["fast_mode"])
        self.assertEqual(document["profiles"]["cursor_grok_46_xhigh"]["logical_tier"], "frontier_director")
        lanes = yaml.safe_load(SELECTOR.read_text(encoding="utf-8"))["graph_engineering_director_lanes"]
        rows = list(lanes["planning_cell"]["lanes"].values()) + [lanes["section_cluster"]]
        for row in rows:
            self.assertEqual(row["physical_toml_semantics"], "codex_role_template_only_never_provider_selection")
            self.assertEqual(row["provider_runtime_profile_id"], "grok_director_frontier")

    def test_rejects_fixed_cdd_count_and_frontier_downgrade(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            sandbox = Path(tmp) / "idol"
            self._copy_routing_tree(sandbox)
            selector_path = sandbox / SELECTOR.relative_to(ROOT)
            selector = yaml.safe_load(selector_path.read_text(encoding="utf-8"))
            selector["assignments"].append(
                {
                    "assignment_id": "planning_cdd_p3_c1",
                    "studio_role": "creative_development_director",
                    "profile_id": "grok_worker_high",
                    "logical_profile_alias": "worker_high",
                    "provider": "grok",
                    "topology": "physical_grok_cli",
                    "activation": "default_active",
                    "return_recipient": "overall_director",
                    "no_fallback": True,
                    "status": "default_active_grok_cli",
                    "goal_first": "required_observable_native_goal",
                    "authority": "illegal_fixed_cdd",
                }
            )
            selector_path.write_text(yaml.safe_dump(selector, sort_keys=False), encoding="utf-8")
            result = self.run_validator(sandbox)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("unexpected rows", result.stderr)

    def test_graph_cdd_rows_cannot_activate_before_verified_default_switch(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            sandbox = Path(tmp) / "idol"
            self._copy_routing_tree(sandbox)
            selector_path = sandbox / SELECTOR.relative_to(ROOT)
            selector = yaml.safe_load(selector_path.read_text(encoding="utf-8"))
            row = next(item for item in selector["assignments"] if item["assignment_id"] == "planning_cdd_p1")
            row["activation"] = "default_active"
            row["status"] = "default_active_grok_cli"
            selector_path.write_text(yaml.safe_dump(selector, sort_keys=False), encoding="utf-8")
            result = self.run_validator(sandbox)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("must wait for the verified default switch", result.stderr)

    def test_rejects_stale_p3_and_v_lane_id_patterns(self) -> None:
        for key in CANONICAL_DIRECTOR_LANE_ID_PATTERNS:
            with tempfile.TemporaryDirectory() as tmp:
                sandbox = Path(tmp) / "idol"
                self._copy_routing_tree(sandbox)
                selector_path = sandbox / SELECTOR.relative_to(ROOT)
                selector = yaml.safe_load(selector_path.read_text(encoding="utf-8"))
                self._set_nested(
                    selector,
                    ASSIGNMENT_DIRECTOR_LANE_ID_PATTERN_PATHS[key],
                    f"^mutated_{key}$",
                )
                selector_path.write_text(yaml.safe_dump(selector, sort_keys=False), encoding="utf-8")
                schema_path = sandbox / "schemas" / "harness-assignment-model-routing.schema.json"
                schema = json.loads(schema_path.read_text(encoding="utf-8"))
                self._loosen_lane_id_pattern_consts(schema)
                schema_path.write_text(json.dumps(schema), encoding="utf-8")
                result = self.run_validator(sandbox)
                self.assertNotEqual(result.returncode, 0, key)
                label = DIRECTOR_LANE_PATTERN_LABELS[key]
                grammar = DIRECTOR_LANE_PATTERN_GRAMMAR[key]
                self.assertIn(
                    f"assignment-routing {label} lane_id_pattern must match canonical {grammar} grammar",
                    result.stderr,
                    key,
                )
                self.assertIn(
                    f"assignment-routing {label} lane_id_pattern must match graph-default-routing",
                    result.stderr,
                    key,
                )
                self.assertNotIn(
                    f"graph-default-routing {label} lane_id_pattern must match canonical {grammar} grammar",
                    result.stderr,
                )

    def test_rejects_graph_default_routing_lane_id_pattern_drift(self) -> None:
        for key in CANONICAL_DIRECTOR_LANE_ID_PATTERNS:
            with tempfile.TemporaryDirectory() as tmp:
                sandbox = Path(tmp) / "idol"
                self._copy_routing_tree(sandbox)
                routing_path = sandbox / GRAPH_ROUTING.relative_to(ROOT)
                routing = yaml.safe_load(routing_path.read_text(encoding="utf-8"))
                routing["cohort_succession"]["lane_id_pattern"][key] = f"^mutated_{key}$"
                routing_path.write_text(yaml.safe_dump(routing, sort_keys=False), encoding="utf-8")
                result = self.run_validator(sandbox)
                self.assertNotEqual(result.returncode, 0, key)
                label = DIRECTOR_LANE_PATTERN_LABELS[key]
                grammar = DIRECTOR_LANE_PATTERN_GRAMMAR[key]
                self.assertIn(
                    f"graph-default-routing {label} lane_id_pattern must match canonical {grammar} grammar",
                    result.stderr,
                    key,
                )
                self.assertIn(
                    f"assignment-routing {label} lane_id_pattern must match graph-default-routing",
                    result.stderr,
                    key,
                )
                self.assertNotIn(
                    f"assignment-routing {label} lane_id_pattern must match canonical {grammar} grammar",
                    result.stderr,
                )

    def test_rejects_stale_cursor_provider_registry_hash(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            sandbox = Path(tmp) / "idol"
            self._copy_routing_tree(sandbox)
            registry_path = sandbox / "automation" / "harness-provider-profile-registry.yaml"
            registry = yaml.safe_load(registry_path.read_text(encoding="utf-8"))
            registry["logical_profiles"]["cursor_advisory"]["providers"]["cursor"][
                "source_sha256"
            ] = "0" * 64
            registry_path.write_text(yaml.safe_dump(registry, sort_keys=False), encoding="utf-8")
            result = self.run_validator(sandbox)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("provider registry cursor source_sha256 is stale", result.stderr)

    def _refresh_source_hash_edges(self, node: Any, relative: str, digest: str) -> None:
        if isinstance(node, dict):
            if node.get("source_path") == relative:
                node["source_sha256"] = digest
            if node.get("provider_profile_source") == relative:
                node["provider_profile_source_sha256"] = digest
            for value in node.values():
                self._refresh_source_hash_edges(value, relative, digest)
        elif isinstance(node, list):
            for item in node:
                self._refresh_source_hash_edges(item, relative, digest)

    def _copy_routing_tree(self, sandbox: Path) -> None:
        for relative in (
            SELECTOR,
            SELECTOR.with_name("harness-assignment-model-routing.yaml"),
            ROOT / "schemas" / "harness-assignment-model-routing.schema.json",
            GRAPH_ROUTING,
            CURSOR,
            ROOT / "schemas" / "cursor-agent-provider-profiles.schema.json",
            ROOT / "automation" / "providers" / "grok-build-profiles.yaml",
            ROOT / "automation" / "harness-provider-profile-registry.yaml",
            ROOT / "automation" / "harness-execution-contract.yaml",
        ):
            source = relative if relative.is_absolute() else ROOT / relative
            dest = sandbox / source.relative_to(ROOT)
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, dest)


if __name__ == "__main__":
    unittest.main()
