#!/usr/bin/env python3
"""Regression tests for the IDOL instruction-surface audit."""

from __future__ import annotations

import copy
import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT_PATH = REPO_ROOT / "scripts" / "idol_instruction_surface_audit.py"
POLICY_PATH = REPO_ROOT / "automation" / "instruction-surface-policy.yaml"

SPEC = importlib.util.spec_from_file_location("idol_instruction_surface_audit", SCRIPT_PATH)
assert SPEC and SPEC.loader
AUDIT = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = AUDIT
SPEC.loader.exec_module(AUDIT)


class InstructionSurfaceAuditTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.live_policy = AUDIT.load_policy(POLICY_PATH)

    def make_fixture(self) -> tuple[tempfile.TemporaryDirectory[str], Path, dict]:
        holder = tempfile.TemporaryDirectory()
        root = Path(holder.name)
        files = {
            "AGENTS.md": """# Agents\n<!-- idol-invariant: one -->\nalpha beta gamma\n""",
            "wiki/router.md": """# Router\ndetail.md\nACTIVATE DETAIL\n""",
            "wiki/INDEX.md": """# Index\ndetail.md\n""",
            "wiki/maintenance.md": """# Maintenance\nwiki/history.md\n""",
            "wiki/detail.md": """# Detail\n## Section Index\n## Required Detail\n""",
            "wiki/history.md": """Status: frozen\nold record\n""",
        }
        for relative, text in files.items():
            path = root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text, encoding="utf-8")
        policy = {
            "priority": "quality_first_efficiency_second",
            "measurement": {
                "long_section_detail_index_threshold_words": 20,
                "size_finding_authority": "diagnostic_or_hold_only",
                "size_remediation_authority": "founder_explicit_current_request_only",
                "automatic_size_remediation": False,
            },
            "surfaces": [
                {"id": "agents", "path": "AGENTS.md", "role": "always", "target_words": 20, "reviewed_ceiling_words": 30},
                {"id": "router", "path": "wiki/router.md", "role": "router", "target_words": 20, "reviewed_ceiling_words": 30},
            ],
            "startup_profiles": [
                {"id": "startup", "paths": ["AGENTS.md", "wiki/router.md", "wiki/INDEX.md"], "target_words": 50, "reviewed_ceiling_words": 70}
            ],
            "conditional_references": [
                {
                    "id": "detail",
                    "path": "wiki/detail.md",
                    "indexed_by": "wiki/INDEX.md",
                    "indexed_token": "detail.md",
                    "routed_by": "wiki/router.md",
                    "routed_token": "detail.md",
                    "activation_pattern": "ACTIVATE DETAIL",
                    "load_mode": "section",
                    "required_headings": ["## Section Index", "## Required Detail"],
                }
            ],
            "protected_invariants": [
                {"id": "one", "path": "AGENTS.md", "marker": "<!-- idol-invariant: one -->", "required_terms": ["alpha", "beta", "gamma"]}
            ],
            "maintenance_history": {
                "active_path": "wiki/maintenance.md",
                "frozen_path": "wiki/history.md",
                "frozen_status_marker": "Status: frozen",
                "active_pointer_required": "wiki/history.md",
                "frozen_max_words": 4,
                "frozen_excluded_from_startup_profiles": True,
                "active_forbidden_patterns": [r"^## Historical Changes\s*$", r"^- \*\*\d{4}-\d{2}-\d{2}\*\*:"],
            },
            "reviewed_size_exceptions": [],
        }
        return holder, root, policy

    def test_live_repository_passes(self) -> None:
        report = AUDIT.audit(REPO_ROOT, self.live_policy)
        self.assertEqual(report["status"], "pass", report["errors"])
        self.assertEqual(
            len(report["protected_invariants"]),
            len(self.live_policy["protected_invariants"]),
        )
        self.assertTrue(report["maintenance_history"]["excluded_from_startup"])
        self.assertEqual(report["size_change_control"]["remediation_authority"], "founder_explicit_current_request_only")
        self.assertFalse(report["size_change_control"]["automatic_remediation"])
        self.assertEqual(report["runtime_load_measurement"]["status"], "pass")
        self.assertGreater(len(report["runtime_load_measurement"]["checkpoints"]), 0)
        self.assertTrue(all(row["kind"] == "static_bootstrap_diagnostic" for row in report["startup_profiles"]))

    def test_target_excess_warns_without_failure(self) -> None:
        holder, root, policy = self.make_fixture()
        self.addCleanup(holder.cleanup)
        policy["surfaces"][0]["target_words"] = 1
        report = AUDIT.audit(root, policy)
        self.assertEqual(report["status"], "pass")
        self.assertIn("target_exceeded", {row["code"] for row in report["warnings"]})

    def test_reviewed_ceiling_excess_fails(self) -> None:
        holder, root, policy = self.make_fixture()
        self.addCleanup(holder.cleanup)
        policy["surfaces"][0]["reviewed_ceiling_words"] = 2
        report = AUDIT.audit(root, policy)
        self.assertEqual(report["status"], "fail")
        self.assertIn("reviewed_ceiling_exceeded", {row["code"] for row in report["errors"]})

    def test_size_remediation_cannot_be_implicitly_authorized(self) -> None:
        holder, root, policy = self.make_fixture()
        self.addCleanup(holder.cleanup)
        policy["measurement"]["automatic_size_remediation"] = True
        report = AUDIT.audit(root, policy)
        self.assertEqual(report["status"], "fail")
        self.assertIn("automatic_size_remediation_forbidden", {row["code"] for row in report["errors"]})

    def test_missing_invariant_term_fails(self) -> None:
        holder, root, policy = self.make_fixture()
        self.addCleanup(holder.cleanup)
        policy["protected_invariants"][0]["required_terms"].append("delta")
        report = AUDIT.audit(root, policy)
        self.assertIn("invariant_term_missing", {row["code"] for row in report["errors"]})

    def test_canonical_detail_term_is_checked_separately(self) -> None:
        holder, root, policy = self.make_fixture()
        self.addCleanup(holder.cleanup)
        policy["protected_invariants"][0]["root_required_terms"] = ["alpha"]
        policy["protected_invariants"][0]["detail_path"] = "wiki/detail.md"
        policy["protected_invariants"][0]["detail_heading"] = "## Required Detail"
        policy["protected_invariants"][0]["detail_required_terms"] = ["missing-detail"]
        report = AUDIT.audit(root, policy)
        self.assertIn("invariant_detail_term_missing", {row["code"] for row in report["errors"]})

    def test_runtime_checkpoint_measurement_uses_exact_selected_paths(self) -> None:
        holder, root, policy = self.make_fixture()
        self.addCleanup(holder.cleanup)
        (root / "skill.md").write_text("one two three", encoding="utf-8")
        (root / "read.md").write_text("four five", encoding="utf-8")
        (root / "automation").mkdir(parents=True, exist_ok=True)
        (root / "automation/harness-skill-load-profiles.yaml").write_text(
            """status: active
skill_bindings:
  - binding_id: skill
    path: skill.md
read_bindings:
  - binding_id: read
    path: read.md
profiles:
  - profile_id: harness_maintenance
    phase_load:
      checkpoints:
        - checkpoint_id: check
          required_skill_ids: [skill]
          required_read_ids: [read]
""",
            encoding="utf-8",
        )
        policy["runtime_load_measurement"] = {
            "registry_path": "automation/harness-skill-load-profiles.yaml",
            "target_words": 4,
            "reviewed_ceiling_words": 10,
            "target_paths": 1,
            "reviewed_ceiling_paths": 2,
            "profile_checkpoint_overrides": [],
        }
        report = AUDIT.audit(root, policy)
        self.assertEqual(report["status"], "pass", report["errors"])
        row = report["runtime_load_measurement"]["checkpoints"][0]
        self.assertEqual((row["selected_path_count"], row["selected_word_count"]), (2, 5))
        self.assertEqual(report["runtime_load_measurement"]["status"], "pass")
        self.assertEqual({item["code"] for item in report["warnings"]}, {"runtime_target_exceeded"})

    def test_runtime_checkpoint_ceiling_fails_without_remediation(self) -> None:
        holder, root, policy = self.make_fixture()
        self.addCleanup(holder.cleanup)
        (root / "skill.md").write_text("one two three", encoding="utf-8")
        (root / "read.md").write_text("four five", encoding="utf-8")
        (root / "automation").mkdir(parents=True, exist_ok=True)
        (root / "automation/harness-skill-load-profiles.yaml").write_text(
            """status: active
skill_bindings:
  - binding_id: skill
    path: skill.md
read_bindings:
  - binding_id: read
    path: read.md
profiles:
  - profile_id: harness_maintenance
    phase_load:
      checkpoints:
        - checkpoint_id: check
          required_skill_ids: [skill]
          required_read_ids: [read]
""",
            encoding="utf-8",
        )
        policy["runtime_load_measurement"] = {
            "registry_path": "automation/harness-skill-load-profiles.yaml",
            "target_words": 10,
            "reviewed_ceiling_words": 4,
            "target_paths": 10,
            "reviewed_ceiling_paths": 2,
            "profile_checkpoint_overrides": [],
        }
        report = AUDIT.audit(root, policy)
        codes = {item["code"] for item in report["errors"]}
        self.assertIn("runtime_threshold_invalid", codes)
        self.assertIn("runtime_reviewed_ceiling_exceeded", codes)

    def test_routing_contract_required_and_forbidden_terms(self) -> None:
        holder, root, policy = self.make_fixture()
        self.addCleanup(holder.cleanup)
        policy["routing_consistency_contracts"] = [
            {
                "id": "router_contract",
                "path": "wiki/router.md",
                "required_terms": ["ACTIVATE DETAIL"],
                "forbidden_terms": ["legacy routing"],
            }
        ]
        report = AUDIT.audit(root, policy)
        self.assertEqual(report["status"], "pass", report["errors"])

        (root / "wiki/router.md").write_text("# Router\nlegacy routing\n", encoding="utf-8")
        report = AUDIT.audit(root, policy)
        codes = {row["code"] for row in report["errors"]}
        self.assertIn("routing_contract_term_missing", codes)
        self.assertIn("routing_contract_forbidden_term", codes)

    def test_missing_conditional_file_fails(self) -> None:
        holder, root, policy = self.make_fixture()
        self.addCleanup(holder.cleanup)
        (root / "wiki/detail.md").unlink()
        report = AUDIT.audit(root, policy)
        self.assertIn("file_missing", {row["code"] for row in report["errors"]})

    def test_missing_index_route_activation_or_heading_fails(self) -> None:
        holder, root, policy = self.make_fixture()
        self.addCleanup(holder.cleanup)
        (root / "wiki/INDEX.md").write_text("# Index\n", encoding="utf-8")
        (root / "wiki/router.md").write_text("# Router\n", encoding="utf-8")
        (root / "wiki/detail.md").write_text("# Detail\n", encoding="utf-8")
        report = AUDIT.audit(root, policy)
        codes = {row["code"] for row in report["errors"]}
        self.assertTrue({"conditional_index_missing", "conditional_route_missing", "conditional_activation_missing", "conditional_heading_missing"}.issubset(codes))

    def test_long_conditional_detail_has_no_length_cap_when_indexed(self) -> None:
        holder, root, policy = self.make_fixture()
        self.addCleanup(holder.cleanup)
        detail = "# Detail\n## Section Index\n## Required Detail\n" + "word " * 1000
        (root / "wiki/detail.md").write_text(detail, encoding="utf-8")
        report = AUDIT.audit(root, policy)
        self.assertEqual(report["status"], "pass", report["errors"])

    def test_active_dated_history_and_frozen_growth_fail(self) -> None:
        holder, root, policy = self.make_fixture()
        self.addCleanup(holder.cleanup)
        (root / "wiki/maintenance.md").write_text("wiki/history.md\n- **2026-07-11**: append\n", encoding="utf-8")
        (root / "wiki/history.md").write_text("Status: frozen\n" + "word " * 10, encoding="utf-8")
        report = AUDIT.audit(root, policy)
        codes = {row["code"] for row in report["errors"]}
        self.assertIn("active_history_append_pattern", codes)
        self.assertIn("frozen_history_grew", codes)

    def test_frozen_history_in_startup_fails(self) -> None:
        holder, root, policy = self.make_fixture()
        self.addCleanup(holder.cleanup)
        policy = copy.deepcopy(policy)
        policy["startup_profiles"][0]["paths"].append("wiki/history.md")
        report = AUDIT.audit(root, policy)
        self.assertIn("frozen_history_in_startup", {row["code"] for row in report["errors"]})


if __name__ == "__main__":
    unittest.main()
