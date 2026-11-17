#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import tomllib
import unittest
from pathlib import Path
from typing import Callable

import yaml


ROOT = Path(__file__).resolve().parents[2]
VALIDATOR = ROOT / "scripts/validate_idol_model_routing_agents.py"
TEST_MODE_ENV = "IDOL_ROUTING_TEST_MODE"


class ValidateIdolModelRoutingAgentsTest(unittest.TestCase):
    def run_validator(
        self,
        root: Path,
        catalog: Path | None = None,
        *,
        json_output: bool = True,
        test_mode: bool = True,
    ) -> subprocess.CompletedProcess[str]:
        command = [sys.executable, str(VALIDATOR), "--root", str(root)]
        if json_output:
            command.append("--json")
        if catalog:
            command.extend(["--catalog-json", str(catalog)])
        environment = os.environ.copy()
        if test_mode:
            environment[TEST_MODE_ENV] = "1"
        else:
            environment.pop(TEST_MODE_ENV, None)
        return subprocess.run(
            command,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
            env=environment,
        )

    def fixture(self) -> tuple[tempfile.TemporaryDirectory[str], Path, Path]:
        temporary = tempfile.TemporaryDirectory(prefix="idol-routing-v33-")
        root = Path(temporary.name)
        (root / ".codex/agents").mkdir(parents=True)
        (root / ".grok/skills/idol-grok-harness-owner/references").mkdir(parents=True)
        (root / "automation/providers").mkdir(parents=True)
        (root / "schemas").mkdir(parents=True)
        shutil.copy2(ROOT / ".codex/config.toml", root / ".codex/config.toml")
        for path in (ROOT / ".codex/agents").glob("*.toml"):
            shutil.copy2(path, root / ".codex/agents" / path.name)
        shutil.copy2(
            ROOT / ".grok/skills/idol-grok-harness-owner/SKILL.md",
            root / ".grok/skills/idol-grok-harness-owner/SKILL.md",
        )
        shutil.copy2(
            ROOT / ".grok/skills/idol-grok-harness-owner/references/subagent-roster.md",
            root / ".grok/skills/idol-grok-harness-owner/references/subagent-roster.md",
        )
        for relative in (
            "automation/harness-execution-contract.yaml",
            "automation/harness-provider-profile-registry.yaml",
            "automation/providers/grok-build-profiles.yaml",
            "automation/providers/openai-image-profiles.yaml",
            "automation/providers/cursor-agent-profiles.yaml",
            "schemas/harness-provider-profile-registry.schema.json",
            "schemas/cursor-agent-provider-profiles.schema.json",
            "schemas/harness-assignment-model-routing.schema.json",
            "automation/harness-assignment-model-routing.yaml",
        ):
            source = ROOT / relative
            destination = root / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, destination)

        index = yaml.safe_load(
            (root / "automation/harness-provider-profile-registry.yaml").read_text(encoding="utf-8")
        )
        required: dict[str, set[str]] = {}
        for logical in index["logical_profiles"].values():
            codex = logical.get("providers", {}).get("codex")
            if not isinstance(codex, dict) or "role_profiles" not in codex:
                continue
            for row in codex["role_profiles"].values():
                with (root / row["source_path"]).open("rb") as handle:
                    profile = tomllib.load(handle)
                required.setdefault(profile["model"], set()).add(profile["model_reasoning_effort"])
        catalog = root / "catalog.json"
        catalog.write_text(
            json.dumps(
                {
                    "models": [
                        {
                            "slug": model,
                            "supported_reasoning_levels": [
                                {"effort": effort} for effort in sorted(efforts)
                            ],
                        }
                        for model, efforts in sorted(required.items())
                    ]
                }
            ),
            encoding="utf-8",
        )
        return temporary, root, catalog

    def mutate_yaml(self, path: Path, callback: Callable[[dict], None]) -> None:
        document = yaml.safe_load(path.read_text(encoding="utf-8"))
        callback(document)
        path.write_text(
            yaml.safe_dump(document, sort_keys=False, allow_unicode=True),
            encoding="utf-8",
        )

    def test_current_v33_provider_and_role_routing_passes(self) -> None:
        temporary, _fixture_root, catalog = self.fixture()
        self.addCleanup(temporary.cleanup)
        result = self.run_validator(ROOT, catalog)
        self.assertEqual(0, result.returncode, result.stderr or result.stdout)
        payload = json.loads(result.stdout)
        self.assertEqual("pass", payload["status"])
        self.assertEqual([], payload["errors"])
        self.assertEqual(
            "idol-harness-execution-contract.v36",
            payload["evidence"]["execution_contract_version"],
        )
        self.assertEqual(0, payload["evidence"]["external_or_generative_actions"])
        self.assertEqual(
            "hold_and_report",
            payload["evidence"]["capability_check"]["unavailable_pair_action"],
        )

    def test_plain_entrypoint_reports_v33_success(self) -> None:
        temporary, _fixture_root, catalog = self.fixture()
        self.addCleanup(temporary.cleanup)
        result = self.run_validator(ROOT, catalog, json_output=False)
        self.assertEqual(0, result.returncode, result.stderr or result.stdout)
        self.assertIn("IDOL v35 keeps provider candidates separate", result.stdout)
        self.assertEqual("", result.stderr)

    def test_cursor_luna_image_cannot_alias_grok_tool(self) -> None:
        temporary, root, catalog = self.fixture()
        self.addCleanup(temporary.cleanup)
        self.mutate_yaml(
            root / "automation/harness-execution-contract.yaml",
            lambda document: document["image_generation"]["provider_model_resolution"]["cursor_luna_image"].update(
                {"adapter": "grok_image"}
            ),
        )
        result = self.run_validator(root, catalog)
        self.assertEqual(1, result.returncode, result.stderr or result.stdout)
        payload = json.loads(result.stdout)
        self.assertTrue(
            any("provider_model_resolution" in error for error in payload["errors"]),
            payload["errors"],
        )

    def test_catalog_fixture_is_rejected_outside_test_mode(self) -> None:
        temporary, root, catalog = self.fixture()
        self.addCleanup(temporary.cleanup)
        result = self.run_validator(root, catalog, test_mode=False)
        self.assertEqual(2, result.returncode)
        self.assertEqual("", result.stdout)
        self.assertIn("--catalog-json is test-only", result.stderr)

    def test_legacy_codex_runtime_catalog_is_not_required(self) -> None:
        temporary, root, catalog = self.fixture()
        self.addCleanup(temporary.cleanup)
        result = self.run_validator(root, catalog)
        payload = json.loads(result.stdout)
        self.assertFalse(
            any("runtime catalog lacks" in error for error in payload["errors"]),
            payload["errors"],
        )

    def test_post_02a_return_drift_is_rejected(self) -> None:
        temporary, root, catalog = self.fixture()
        self.addCleanup(temporary.cleanup)
        self.mutate_yaml(
            root / "automation/harness-execution-contract.yaml",
            lambda document: document["return_routing"].update(
                image_and_03v_recipient_role="overall_director"
            ),
        )
        result = self.run_validator(root, catalog)
        self.assertNotEqual(0, result.returncode)
        payload = json.loads(result.stdout)
        self.assertTrue(any("image_and_03v_recipient_role" in error for error in payload["errors"]))

    def test_duplicate_director_binding_is_rejected(self) -> None:
        temporary, root, catalog = self.fixture()
        self.addCleanup(temporary.cleanup)
        self.mutate_yaml(
            root / "automation/harness-execution-contract.yaml",
            lambda document: document["active_role_bindings"]["creative_development_director"].update(
                required_active_binding_count=2
            ),
        )
        result = self.run_validator(root, catalog)
        self.assertNotEqual(0, result.returncode)
        payload = json.loads(result.stdout)
        self.assertTrue(any("exactly one active binding" in error for error in payload["errors"]))

    def test_shared_contract_static_director_binding_is_rejected(self) -> None:
        temporary, root, catalog = self.fixture()
        self.addCleanup(temporary.cleanup)
        self.mutate_yaml(
            root / "automation/harness-execution-contract.yaml",
            lambda document: document["active_role_bindings"]["overall_director"].update(
                binding_id="ACTIVE-OD-STATIC",
                execution_profile_id="codex_overall_director_deep",
            ),
        )
        result = self.run_validator(root, catalog)
        self.assertNotEqual(0, result.returncode)
        payload = json.loads(result.stdout)
        self.assertTrue(any("must not materialize run field" in error for error in payload["errors"]))

    def test_shared_contract_resolved_profile_inventory_is_rejected(self) -> None:
        temporary, root, catalog = self.fixture()
        self.addCleanup(temporary.cleanup)
        self.mutate_yaml(
            root / "automation/harness-execution-contract.yaml",
            lambda document: document["provider_profile_resolution"].update(resolved_profiles=[]),
        )
        result = self.run_validator(root, catalog)
        self.assertNotEqual(0, result.returncode)
        payload = json.loads(result.stdout)
        self.assertTrue(any("must not materialize resolved provider profiles" in error for error in payload["errors"]))

    def test_grok_shared_skill_model_literal_is_rejected(self) -> None:
        temporary, root, catalog = self.fixture()
        self.addCleanup(temporary.cleanup)
        skill = root / ".grok/skills/idol-grok-harness-owner/SKILL.md"
        skill.write_text(skill.read_text(encoding="utf-8") + "\nexact model example: grok-9.9\n", encoding="utf-8")
        result = self.run_validator(root, catalog)
        self.assertNotEqual(0, result.returncode)
        payload = json.loads(result.stdout)
        self.assertTrue(any("exact provider model literal" in error for error in payload["errors"]))

    def test_stale_director_boot_pack_instruction_is_rejected(self) -> None:
        temporary, root, catalog = self.fixture()
        self.addCleanup(temporary.cleanup)
        profile = root / ".codex/agents/idol-sol-creative-synthesis.toml"
        profile.write_text(
            profile.read_text(encoding="utf-8").replace("Boot Pack v3", "Boot Pack v2"),
            encoding="utf-8",
        )
        result = self.run_validator(root, catalog)
        self.assertNotEqual(0, result.returncode)
        payload = json.loads(result.stdout)
        self.assertTrue(any("boot pack v3" in error for error in payload["errors"]))


if __name__ == "__main__":
    unittest.main()
