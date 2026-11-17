from __future__ import annotations

import importlib.util
import tomllib
import unittest
from hashlib import sha256
from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[2]
PROJECT_CONFIG = ROOT / ".grok" / "config.toml"
PROJECT_SANDBOX = ROOT / ".grok" / "sandbox.toml"
BRIDGE = ROOT / ".grok" / "skills" / "idol-cli-bridge" / "scripts" / "open_cli.sh"
RESOLVE = ROOT / ".grok" / "skills" / "idol-cli-bridge" / "scripts" / "resolve_cli.py"
BRIDGE_SKILL = ROOT / ".grok" / "skills" / "idol-cli-bridge" / "SKILL.md"
SURFACE_REGISTRY = ROOT / "automation" / "harness-surface-version-registry.yaml"


def _load_resolve():
    spec = importlib.util.spec_from_file_location("idol_resolve_cli", RESOLVE)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class IdolGrokCliBridgeTest(unittest.TestCase):
    def test_goal_state_is_not_blocked_by_a_blanket_grok_home_edit_deny(self) -> None:
        config = tomllib.loads(PROJECT_CONFIG.read_text(encoding="utf-8"))
        rules = config["permission"]["rules"]

        blanket = [
            rule
            for rule in rules
            if rule.get("action") == "deny"
            and rule.get("tool") in {"read", "edit"}
            and rule.get("pattern") == "/Users/yuminseog/.grok/**"
        ]
        self.assertEqual([], blanket)

    def test_sensitive_grok_user_files_remain_protected(self) -> None:
        config = tomllib.loads(PROJECT_CONFIG.read_text(encoding="utf-8"))
        rules = config["permission"]["rules"]
        denied = {
            (rule.get("tool"), rule.get("pattern"))
            for rule in rules
            if rule.get("action") == "deny"
        }

        for tool in ("read", "edit"):
            self.assertIn((tool, "/Users/yuminseog/.grok/auth.json*"), denied)
            self.assertIn((tool, "/Users/yuminseog/.grok/mcp_credentials.json*"), denied)
        self.assertIn(("edit", "/Users/yuminseog/.grok/config.toml*"), denied)
        self.assertIn(("edit", "/Users/yuminseog/.grok/managed_config.toml*"), denied)
        self.assertIn(("edit", "/Users/yuminseog/.grok/requirements.toml*"), denied)
        self.assertIn(("edit", "/Users/yuminseog/.grok/hooks/**"), denied)
        self.assertIn(("edit", "/Users/yuminseog/.grok/bin/**"), denied)

    def test_idol_repo_sandbox_is_workspace_not_strict(self) -> None:
        sandbox = tomllib.loads(PROJECT_SANDBOX.read_text(encoding="utf-8"))
        profile = sandbox["profiles"]["idol-repo"]
        self.assertEqual("workspace", profile["extends"])
        self.assertTrue(profile["restrict_network"])
        self.assertIn(
            "/Users/yuminseog/aheyabaraya_hq_root/hq-control/creative/IDOL",
            profile["read_write"],
        )

    def test_user_sandbox_does_not_redefine_idol_repo(self) -> None:
        path = Path.home() / ".grok" / "sandbox.toml"
        if not path.is_file():
            return
        sandbox = tomllib.loads(path.read_text(encoding="utf-8"))
        self.assertNotIn("idol-repo", sandbox.get("profiles", {}))

    def test_bridge_disables_cursor_hooks_only_for_grok(self) -> None:
        script = BRIDGE.read_text(encoding="utf-8")
        self.assertIn("resolve_cli.py", script)
        self.assertNotIn("/Applications/ChatGPT.app", script)
        self.assertNotIn("/opt/homebrew/bin/cursor-agent", script)
        self.assertIn('if [[ "$key" == "grok" ]]; then', script)
        self.assertEqual(1, script.count("GROK_CURSOR_HOOKS_ENABLED=0"))
        self.assertLess(
            script.index('if [[ "$key" == "grok" ]]; then'),
            script.index("GROK_CURSOR_HOOKS_ENABLED=0"),
        )
        self.assertIn("--sandbox idol-repo", script)

    def test_version_order_prefers_newest_installed(self) -> None:
        resolve = _load_resolve()
        self.assertGreater(resolve.parse_version("grok 1.0.30 (abc) [stable]"), resolve.parse_version("grok 1.0.25 (def) [stable]"))
        self.assertGreater(resolve.parse_version("codex-cli 0.154.0-alpha.6.2"), resolve.parse_version("codex-cli 0.150.1"))
        self.assertGreater(resolve.parse_version("2026.09.10-fd3934a"), resolve.parse_version("2026.08.11-e8db854"))
        self.assertGreater(resolve.parse_version("1.0.30"), resolve.parse_version("1.0.30-alpha.1"))

    def test_resolver_selects_the_maximum_discovered_version(self) -> None:
        resolve = _load_resolve()
        for peer in ("grok", "cursor", "codex"):
            rows = resolve.inspect_peer(peer)
            self.assertTrue(rows, f"no installed {peer} binaries")
            self.assertEqual(rows[0]["key"], max(row["key"] for row in rows))
            self.assertTrue(Path(rows[0]["path"]).is_file())

    def test_runtime_surfaces_are_hash_bound_in_the_registry(self) -> None:
        registry = yaml.safe_load(SURFACE_REGISTRY.read_text(encoding="utf-8"))
        rows = {row["surface_id"]: row for row in registry["surfaces"]}
        expected = {
            "grok_project_config": PROJECT_CONFIG,
            "grok_project_sandbox": PROJECT_SANDBOX,
            "grok_skills_idol_cli_bridge": BRIDGE_SKILL,
            "grok_skills_idol_cli_bridge_open_cli": BRIDGE,
            "grok_skills_idol_cli_bridge_resolve_cli": RESOLVE,
        }

        for surface_id, path in expected.items():
            row = rows[surface_id]
            self.assertGreaterEqual(row["current_revision"], 1)
            self.assertEqual(path.relative_to(ROOT).as_posix(), row["path"])
            self.assertEqual(sha256(path.read_bytes()).hexdigest(), row["sha256"])


if __name__ == "__main__":
    unittest.main()
