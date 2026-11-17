#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import hashlib
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from jsonschema import Draft202012Validator


ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = ROOT / "scripts" / "idol_cursor_assignment_adapter.py"


def load_adapter():
    spec = importlib.util.spec_from_file_location("idol_cursor_assignment_adapter", MODULE_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class IdolCursorAssignmentAdapterTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.adapter = load_adapter()

    def write_fake_cursor_agent(
        self,
        path: Path,
        *,
        catalog_model: str = "claude-opus-5-thinking-high",
        init_display: str = "Claude Opus 5 300K High",
        init_session: str = "session-test-1",
        result_session: str = "session-test-1",
        request_id: str | None = "request-1",
        include_result: bool = True,
        api_key_source: str = "login",
        include_hook_receipt: bool = True,
        hook_allowed: bool = True,
        hook_session: str | None = None,
        hook_goal_sha256: str | None = None,
    ) -> None:
        init_event = json.dumps(
            {
                "type": "system",
                "subtype": "init",
                "apiKeySource": api_key_source,
                "session_id": init_session,
                "model": init_display,
            }
        )
        result_event = json.dumps(
            {
                "type": "result",
                "subtype": "success",
                "is_error": False,
                "session_id": result_session,
                "request_id": request_id,
                "result": "ok",
            }
        )
        result_line = f"print({result_event!r})\n" if include_result else ""
        hook_line = ""
        if include_hook_receipt:
            hook_line = (
                "receipt_path = os.environ.get('IDOL_CURSOR_RECEIPT_PATH')\n"
                "if receipt_path:\n"
                "    hook = {\n"
                "        'schema_version': 'idol-cursor-hook-receipt.v1',\n"
                "        'recorded_at': '2026-09-03T00:00:00+00:00',\n"
                "        'assignment_id': os.environ.get('IDOL_CURSOR_ASSIGNMENT_ID'),\n"
                "        'profile_id': os.environ.get('IDOL_CURSOR_PROFILE_ID'),\n"
                "        'event': 'sessionStart',\n"
                f"        'conversation_id': {str(hook_session or init_session)!r},\n"
                "        'generation_id': None,\n"
                f"        'model_id': {catalog_model!r},\n"
                "        'model_params': {},\n"
                "        'model_evidence_available': True,\n"
                "        'cursor_version': 'test',\n"
                "        'goal_path': os.environ.get('IDOL_CURSOR_GOAL_PATH'),\n"
                f"        'goal_sha256': {hook_goal_sha256!r} or os.environ.get('IDOL_CURSOR_GOAL_SHA256'),\n"
                "        'attachments': [],\n"
                f"        'allowed': {hook_allowed!r},\n"
                f"        'hold_reason': {None if hook_allowed else 'test_hook_denied'!r},\n"
                "    }\n"
                "    with open(receipt_path, 'w', encoding='utf-8') as handle:\n"
                "        handle.write(json.dumps(hook, sort_keys=True) + '\\n')\n"
            )
        path.write_text(
            "#!/usr/bin/env python3\n"
            "import json\n"
            "import os\n"
            "import sys\n"
            "if len(sys.argv) > 1 and sys.argv[1] == 'models':\n"
            f"    print('{catalog_model} - test catalog display')\n"
            "    raise SystemExit(0)\n"
            f"{hook_line}"
            f"print({init_event!r})\n"
            f"{result_line}",
            encoding="utf-8",
        )
        os.chmod(path, 0o755)

    def build_admission_assignment(
        self,
        root: Path,
        *,
        assignment_id: str,
        profile_id: str,
        exact_model: str,
        init_display: str,
        effort: str,
        objective: str = "bounded admission test",
        session_id: str = "session-admission-1",
    ) -> dict:
        goal_path = root / "goal.json"
        goal = self.adapter.create_external_goal_record(
            assignment_id=assignment_id,
            profile_id=profile_id,
            objective=objective,
            output_path=goal_path,
        )
        result_path = root / "result.md"
        result_path.write_text("ok", encoding="utf-8")
        hook_path = root / "hooks.jsonl"
        hook_path.write_text(
            json.dumps(
                {
                    "schema_version": "idol-cursor-hook-receipt.v1",
                    "recorded_at": "2026-09-03T00:00:00+00:00",
                    "assignment_id": assignment_id,
                    "profile_id": profile_id,
                    "event": "sessionStart",
                    "conversation_id": session_id,
                    "generation_id": None,
                    "model_id": exact_model,
                    "model_params": {},
                    "model_evidence_available": True,
                    "cursor_version": "test",
                    "goal_path": str(goal_path),
                    "goal_sha256": goal["sha256"],
                    "attachments": [],
                    "allowed": True,
                    "hold_reason": None,
                },
                sort_keys=True,
            )
            + "\n",
            encoding="utf-8",
        )
        runtime = {
            "schema_version": "idol-cursor-cli-runtime-receipt.v2",
            "assignment_id": assignment_id,
            "profile_id": profile_id,
            "source": "cursor_cli_stream_json",
            "api_key_source": "login",
            "exact_cli_model": exact_model,
            "catalog_display": "test",
            "observed_init_display": init_display,
            "session_id": session_id,
            "request_id": "request-admission-1",
            "terminal_status": "success",
            "goal_path": str(goal_path),
            "goal_sha256": goal["sha256"],
            "hook_receipt_path": str(hook_path),
            "hook_receipt_sha256": hashlib.sha256(hook_path.read_bytes()).hexdigest(),
            "hook_receipt_byte_size": hook_path.stat().st_size,
            "result_path": str(result_path),
            "result_sha256": hashlib.sha256(result_path.read_bytes()).hexdigest(),
            "result_byte_size": result_path.stat().st_size,
            "attachments": [],
            "resume_session_id": None,
            "recorded_at": "2026-09-03T00:00:00+00:00",
            "hold_reason": None,
        }
        return {
            "assignment_id": assignment_id,
            "provider": "cursor",
            "topology": "new_cursor_physical_chat",
            "requested_model": exact_model,
            "requested_effort": effort,
            "founder_explicit_substitute": True,
            "objective": objective,
            "goal_record": goal["record"],
            "runtime_receipt": runtime,
        }

    def shipped_cursor_selector_and_profile(self, assignment_id: str) -> tuple[dict, dict]:
        routing = self.adapter.load_assignment_routing()
        selector = next(
            (
                row
                for row in routing.get("assignments", [])
                if isinstance(row, dict) and row.get("assignment_id") == assignment_id
            ),
            None,
        )
        self.assertIsInstance(selector, dict, assignment_id)
        profiles = self.adapter.load_cursor_profiles()
        profile = (profiles.get("profiles") or {}).get(selector.get("profile_id"))
        self.assertIsInstance(profile, dict, assignment_id)
        return selector, profile

    def test_status_entrypoint_passes_root_to_capability_lookup(self) -> None:
        completed = subprocess.run(
            [sys.executable, str(MODULE_PATH)],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
            cwd=ROOT,
        )
        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertIn("cursor_status=", completed.stdout)
        self.assertIn("goal_observable=", completed.stdout)

    def test_external_goal_required_before_work(self) -> None:
        result = self.adapter.admit_cursor_assignment(
            {
                "assignment_id": "pre00_close_direction_review",
                "provider": "cursor",
                "topology": "new_cursor_physical_chat",
                "requested_model": "claude-opus-5-thinking-high",
                "requested_effort": "thinking_high",
                "founder_explicit_substitute": True,
            }
        )
        self.assertEqual(result["status"], "hold")
        self.assertEqual(result["reason"], "cursor_external_goal_record_required")
        self.assertEqual(result["fallback"], "none")

    def test_admission_holds_when_goal_file_missing(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            assignment = self.build_admission_assignment(
                Path(tmp),
                assignment_id="cursor_grok_46_advisory_worker",
                profile_id="cursor_grok_46_xhigh",
                exact_model="cursor-grok-4.6-xhigh",
                init_display="Cursor Grok 4.6 Extra High",
                effort="xhigh",
            )
            Path(assignment["runtime_receipt"]["goal_path"]).unlink()
            result = self.adapter.admit_cursor_assignment(assignment)
            self.assertEqual(result["status"], "hold", result)
            self.assertEqual(result["reason"], "cursor_external_goal_path_missing", result)

    def test_v1_runtime_receipt_new_authoring_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            assignment = self.build_admission_assignment(
                Path(tmp),
                assignment_id="cursor_grok_46_advisory_worker",
                profile_id="cursor_grok_46_xhigh",
                exact_model="cursor-grok-4.6-xhigh",
                init_display="Cursor Grok 4.6 Extra High",
                effort="xhigh",
            )
            runtime = dict(assignment["runtime_receipt"])
            runtime["schema_version"] = self.adapter.LEGACY_RUNTIME_RECEIPT_VERSION
            runtime.pop("hook_receipt_sha256", None)
            runtime.pop("hook_receipt_byte_size", None)
            assignment["runtime_receipt"] = runtime
            result = self.adapter.admit_cursor_assignment(assignment)
            self.assertEqual(result["status"], "hold", result)
            self.assertEqual(
                result["reason"],
                "cursor_runtime_receipt_v1_new_authoring_forbidden",
                result,
            )

            v1_path = Path(tmp) / "runtime-v1.json"
            v1_path.write_text(json.dumps(runtime, sort_keys=True), encoding="utf-8")
            v1_schema = json.loads(
                (ROOT / "schemas/cursor-cli-runtime-receipt-v1-legacy.schema.json").read_text(
                    encoding="utf-8"
                )
            )
            v2_schema = json.loads(
                (ROOT / "schemas/cursor-cli-runtime-receipt.schema.json").read_text(
                    encoding="utf-8"
                )
            )
            self.assertEqual([], list(Draft202012Validator(v1_schema).iter_errors(runtime)))
            self.assertNotEqual([], list(Draft202012Validator(v2_schema).iter_errors(runtime)))
            blocked = self.adapter.parse_cursor_runtime_receipt(
                v1_path, allow_legacy_parse=False
            )
            self.assertEqual(blocked["status"], "hold", blocked)
            self.assertEqual(
                blocked["reason"],
                "cursor_runtime_receipt_v1_new_authoring_forbidden",
                blocked,
            )
            parsed = self.adapter.parse_cursor_runtime_receipt(
                v1_path, allow_legacy_parse=True
            )
            self.assertEqual(parsed["status"], "pass", parsed)
            self.assertEqual(parsed["mode"], "parse_only_legacy", parsed)

    def test_cursor_without_founder_substitute_holds_even_when_otherwise_valid(self) -> None:
        result = self.adapter.admit_cursor_assignment(
            {
                "assignment_id": "pre00_close_direction_review",
                "provider": "cursor",
                "topology": "new_cursor_physical_chat",
                "requested_model": "claude-opus-5-thinking-high",
                "requested_effort": "thinking_high",
                "goal_record": {
                    "status": "active",
                    "assignment_id": "pre00_close_direction_review",
                    "profile_id": "cursor_opus_thinking_high",
                },
                "runtime_receipt": {
                    "source": "cursor_cli_stream_json",
                    "exact_cli_model": "claude-opus-5-thinking-high",
                    "observed_init_display": "Claude Opus 5 300K High",
                    "session_id": "session-1",
                    "terminal_status": "success",
                },
            }
        )
        self.assertEqual(result["status"], "hold")
        self.assertEqual(result["reason"], "founder_explicit_substitute_required")

    def test_cursor_overall_and_cdd_hold_without_founder_explicit_substitute(self) -> None:
        expected_roles = {
            "cursor_overall_director": "overall_director",
            "cursor_creative_development_director": "creative_development_director",
        }
        for assignment_id, studio_role in expected_roles.items():
            for substitute in (None, False, "true"):
                with self.subTest(assignment_id=assignment_id, substitute=substitute):
                    selector, profile = self.shipped_cursor_selector_and_profile(assignment_id)
                    self.assertEqual(selector.get("studio_role"), studio_role, assignment_id)
                    self.assertEqual(selector.get("provider"), "cursor", assignment_id)
                    self.assertNotEqual(selector.get("activation"), "default_active", assignment_id)
                    self.assertEqual(
                        selector.get("activation"),
                        "founder_explicit_substitute",
                        assignment_id,
                    )
                    self.assertEqual(
                        selector.get("status"),
                        "available_founder_explicit_substitute",
                        assignment_id,
                    )
                    self.assertIs(profile.get("default_enabled"), False, assignment_id)
                    with tempfile.TemporaryDirectory() as tmp:
                        assignment = self.build_admission_assignment(
                            Path(tmp),
                            assignment_id=assignment_id,
                            profile_id=str(selector["profile_id"]),
                            exact_model=str(profile["exact_model"]),
                            init_display=str(profile["expected_init_display"]),
                            effort=str(profile["reasoning_effort"]),
                        )
                        if substitute is None:
                            assignment.pop("founder_explicit_substitute", None)
                        else:
                            assignment["founder_explicit_substitute"] = substitute
                        result = self.adapter.admit_cursor_assignment(assignment)
                        self.assertEqual(result["status"], "hold", result)
                        self.assertEqual(
                            result["reason"],
                            "founder_explicit_substitute_required",
                            result,
                        )
                        self.assertEqual(result["activation"], "disabled_hold", result)
                        self.assertEqual(result["fallback"], "none", result)

    def test_cursor_overall_and_cdd_founder_explicit_substitute_is_not_banned(self) -> None:
        expected_roles = {
            "cursor_overall_director": "overall_director",
            "cursor_creative_development_director": "creative_development_director",
        }
        for assignment_id, studio_role in expected_roles.items():
            with self.subTest(assignment_id=assignment_id):
                selector, profile = self.shipped_cursor_selector_and_profile(assignment_id)
                self.assertEqual(selector.get("studio_role"), studio_role, assignment_id)
                self.assertIs(profile.get("default_enabled"), False, assignment_id)
                with tempfile.TemporaryDirectory() as tmp:
                    assignment = self.build_admission_assignment(
                        Path(tmp),
                        assignment_id=assignment_id,
                        profile_id=str(selector["profile_id"]),
                        exact_model=str(profile["exact_model"]),
                        init_display=str(profile["expected_init_display"]),
                        effort=str(profile["reasoning_effort"]),
                    )
                    result = self.adapter.admit_cursor_assignment(assignment)
                    self.assertEqual(result["status"], "pass", result)
                    self.assertEqual(result["assignment_id"], assignment_id, result)
                    self.assertEqual(result["profile_id"], selector["profile_id"], result)
                    self.assertEqual(
                        result["activation"],
                        "founder_explicit_substitute",
                        result,
                    )
                    self.assertNotEqual(result["activation"], "default_active", result)

    def test_default_grok_overall_and_cdd_ids_hold_on_cursor_admit(self) -> None:
        for assignment_id in ("overall_director", "creative_development_director"):
            with self.subTest(assignment_id=assignment_id):
                routing = self.adapter.load_assignment_routing()
                selector = next(
                    (
                        row
                        for row in routing.get("assignments", [])
                        if isinstance(row, dict) and row.get("assignment_id") == assignment_id
                    ),
                    None,
                )
                self.assertIsInstance(selector, dict, assignment_id)
                self.assertEqual(selector.get("provider"), "grok", assignment_id)
                self.assertEqual(selector.get("activation"), "default_active", assignment_id)
                result = self.adapter.admit_cursor_assignment(
                    {
                        "assignment_id": assignment_id,
                        "provider": "cursor",
                        "topology": "new_cursor_physical_chat",
                        "founder_explicit_substitute": True,
                    }
                )
                self.assertEqual(result["status"], "hold", result)
                self.assertEqual(result["reason"], "cursor_profile_missing", result)
                self.assertEqual(result["activation"], "disabled_hold", result)
                self.assertEqual(result["fallback"], "none", result)

    def test_active_opus_assignment_accepts_external_goal_and_runtime_receipt(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            assignment = self.build_admission_assignment(
                Path(tmp),
                assignment_id="pre00_close_direction_review",
                profile_id="cursor_opus_thinking_high",
                exact_model="claude-opus-5-thinking-high",
                init_display="Claude Opus 5 300K High",
                effort="thinking_high",
            )
            result = self.adapter.admit_cursor_assignment(assignment)
            self.assertEqual(result["status"], "pass", result)
            self.assertEqual(result["activation"], "founder_explicit_substitute")

    def test_rejects_cursor_auto(self) -> None:
        result = self.adapter.admit_cursor_assignment(
            {
                "assignment_id": "pre00_close_direction_review",
                "provider": "cursor",
                "topology": "new_cursor_physical_chat",
                "auto": True,
            }
        )
        self.assertEqual(result["reason"], "cursor_auto_forbidden")

    def test_rejects_cursor_grok_alias(self) -> None:
        result = self.adapter.admit_cursor_assignment(
            {
                "assignment_id": "pre00_close_direction_review",
                "provider": "cursor",
                "topology": "new_cursor_physical_chat",
                "requested_model": "cursor grok",
            }
        )
        self.assertEqual(result["reason"], "cursor_grok_forbidden")

    def test_optional_luna_xhigh_assignment_holds_until_runtime_receipt_admission(self) -> None:
        result = self.adapter.admit_cursor_assignment(
            {
                "assignment_id": "optional_cursor_luna_xhigh_worker",
                "provider": "cursor",
                "topology": "new_cursor_physical_chat",
                "requested_model": "gpt-5.6-luna-xhigh",
                "requested_effort": "xhigh",
                "founder_explicit_substitute": True,
                "goal_record": {
                    "status": "active",
                    "assignment_id": "optional_cursor_luna_xhigh_worker",
                    "profile_id": "cursor_luna_xhigh",
                },
                "runtime_receipt": {
                    "source": "cursor_cli_stream_json",
                    "exact_cli_model": "gpt-5.6-luna-xhigh",
                    "observed_init_display": "GPT-5.6 Luna 1M Extra High",
                    "session_id": "session-luna-xhigh-1",
                    "terminal_status": "success",
                },
            }
        )
        self.assertEqual(result["status"], "hold")
        self.assertEqual(result["fallback"], "none")
        self.assertIn(
            result["reason"],
            {
                "cursor_profile_held",
                "cursor_route_not_founder_selected",
            },
        )

    def test_cursor_grok_frontier_director_assignment_holds_until_full_owner_ready(self) -> None:
        expected_roles = {
            "cursor_grok_46_frontier_overall_director": "overall_director",
            "cursor_grok_46_frontier_creative_development_director": "creative_development_director",
        }
        for assignment_id, studio_role in expected_roles.items():
            with self.subTest(assignment_id=assignment_id):
                selector, profile = self.shipped_cursor_selector_and_profile(assignment_id)
                self.assertEqual(selector.get("studio_role"), studio_role, assignment_id)
                self.assertIsNot(profile.get("full_owner_ready"), True, assignment_id)
                result = self.adapter.admit_cursor_assignment(
                    {
                        "assignment_id": assignment_id,
                        "provider": "cursor",
                        "topology": "new_cursor_physical_chat",
                        "requested_model": profile["exact_model"],
                        "requested_effort": profile["reasoning_effort"],
                        "founder_explicit_substitute": True,
                        "goal_record": {
                            "status": "active",
                            "assignment_id": assignment_id,
                            "profile_id": selector["profile_id"],
                        },
                        "runtime_receipt": {
                            "source": "cursor_cli_stream_json",
                            "exact_cli_model": profile["exact_model"],
                            "observed_init_display": profile["expected_init_display"],
                            "session_id": "session-grok-frontier-1",
                            "terminal_status": "success",
                        },
                    }
                )
                self.assertEqual(result["status"], "hold", result)
                self.assertEqual(result["reason"], "cursor_profile_not_full_owner_ready", result)

    def test_registered_cursor_grok_xhigh_non_fast_assignment_passes(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            assignment = self.build_admission_assignment(
                Path(tmp),
                assignment_id="cursor_grok_46_advisory_worker",
                profile_id="cursor_grok_46_xhigh",
                exact_model="cursor-grok-4.6-xhigh",
                init_display="Cursor Grok 4.6 Extra High",
                effort="xhigh",
                session_id="session-grok-1",
            )
            result = self.adapter.admit_cursor_assignment(assignment)
            self.assertEqual(result["status"], "pass", result)

    def test_admission_holds_on_goal_and_hook_evidence_drift(self) -> None:
        cases = {
            "objective": ("objective", "different objective", "cursor_external_goal_objective_mismatch"),
            "goal_hash": (
                "goal_sha256",
                "0" * 64,
                "cursor_external_goal_hash_mismatch",
            ),
            "hook_hash": (
                "hook_receipt_sha256",
                "0" * 64,
                "cursor_hook_receipt_sha_mismatch",
            ),
            "result_hash": (
                "result_sha256",
                "0" * 64,
                "cursor_result_sha_mismatch",
            ),
            "hook_session": ("hook_session", "different-session", "cursor_hook_receipt_session_mismatch"),
        }
        for label, (field, value, expected_reason) in cases.items():
            with self.subTest(label=label), tempfile.TemporaryDirectory() as tmp:
                assignment = self.build_admission_assignment(
                    Path(tmp),
                    assignment_id="cursor_grok_46_advisory_worker",
                    profile_id="cursor_grok_46_xhigh",
                    exact_model="cursor-grok-4.6-xhigh",
                    init_display="Cursor Grok 4.6 Extra High",
                    effort="xhigh",
                )
                runtime = assignment["runtime_receipt"]
                if field == "objective":
                    assignment["objective"] = value
                elif field == "goal_sha256":
                    runtime["goal_sha256"] = value
                elif field == "hook_receipt_sha256":
                    runtime["hook_receipt_sha256"] = value
                elif field == "result_sha256":
                    runtime["result_sha256"] = value
                else:
                    hook_path = Path(runtime["hook_receipt_path"])
                    hook = json.loads(hook_path.read_text(encoding="utf-8"))
                    hook["conversation_id"] = value
                    hook_path.write_text(json.dumps(hook, sort_keys=True) + "\n", encoding="utf-8")
                    runtime["hook_receipt_sha256"] = hashlib.sha256(hook_path.read_bytes()).hexdigest()
                    runtime["hook_receipt_byte_size"] = hook_path.stat().st_size
                result = self.adapter.admit_cursor_assignment(assignment)
                self.assertEqual(result["status"], "hold", result)
                self.assertEqual(result["reason"], expected_reason, result)

    def test_run_registered_cursor_grok_uses_non_fast_model_and_persists_result(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            fake = Path(tmp) / "cursor-agent"
            self.write_fake_cursor_agent(
                fake,
                catalog_model="cursor-grok-4.6-xhigh",
                init_display="Cursor Grok 4.6 Extra High",
            )
            result = self.adapter.run_cursor_assignment(
                assignment_id="cursor_grok_46_advisory_worker",
                prompt="bounded read-only test",
                cursor_agent=str(fake),
                work_dir=Path(tmp) / "work",
                founder_explicit_substitute=True,
            )
            self.assertEqual(result["status"], "pass", result)
            receipt = json.loads(Path(result["runtime_receipt_path"]).read_text(encoding="utf-8"))
            self.assertEqual(receipt["exact_cli_model"], "cursor-grok-4.6-xhigh")
            self.assertNotIn("fast", receipt["exact_cli_model"])
            self.assertEqual("ok", Path(result["result_path"]).read_text(encoding="utf-8"))

    def test_display_label_is_not_evidence(self) -> None:
        result = self.adapter.attest_actual_model(
            {
                "assignment_id": "pre00_close_direction_review",
                "runtime_receipt": {
                    "exact_cli_model": "claude-opus-5-thinking-high",
                    "observed_init_display": "Claude Opus 5 300K High",
                    "session_id": "session-1",
                    "terminal_status": "success",
                    "source": "display_label",
                },
            },
            profile={
                "exact_model": "claude-opus-5-thinking-high",
                "expected_init_display": "Claude Opus 5 300K High",
                "reasoning_effort": "thinking_high",
            },
            evidence={
                "actual_model_attestation_proven": "exact_cli_argument_catalog_init_display_terminal_result"
            },
        )
        self.assertEqual(result["reason"], "attestation_source_insufficient")

    def test_fable_to_opus_substitution_holds(self) -> None:
        result = self.adapter.detect_fable_substitution(
            {
                "assignment_id": "fp_close_direction_review",
                "founder_explicit_substitute": True,
                "observed_model": "Claude Opus 5",
            }
        )
        self.assertEqual(result["status"], "hold")
        self.assertEqual(result["reason"], "fable_to_opus_substitution")

    def test_fable_without_founder_substitute_holds(self) -> None:
        result = self.adapter.detect_fable_substitution(
            {
                "assignment_id": "fp_close_direction_review",
                "observed_model": "claude-fable-5-thinking-xhigh",
            }
        )
        self.assertEqual(result["status"], "hold")
        self.assertEqual(result["reason"], "founder_explicit_substitute_required")

    def test_fable_matching_model_passes_when_founder_names_it(self) -> None:
        result = self.adapter.detect_fable_substitution(
            {
                "assignment_id": "fp_close_direction_review",
                "founder_explicit_substitute": True,
                "observed_model": "claude-fable-5-thinking-xhigh",
            }
        )
        self.assertEqual(result["status"], "pass")

    def test_gemini_path_only_attachment_holds(self) -> None:
        result = self.adapter.validate_gemini_attachment(
            {
                "assignment_id": "visual_evidence_analysis",
                "attachments": [{"kind": "path_only", "path": "/tmp/image.png"}],
            }
        )
        self.assertEqual(result["status"], "hold")
        self.assertIn(
            result["reason"],
            {"gemini_binary_attachment_unproven", "gemini_path_only_or_placeholder_forbidden"},
        )

    def test_gemini_cli_image_flag_binds_exact_attachment_receipt(self) -> None:
        attachment = ROOT / ".runtime" / "cursor-adapter-tests" / "fixture.png"
        attachment.parent.mkdir(parents=True, exist_ok=True)
        attachment.write_bytes(b"\x89PNG\r\n\x1a\nfixture")
        try:
            with tempfile.TemporaryDirectory() as tmp:
                fake = Path(tmp) / "cursor-agent"
                self.write_fake_cursor_agent(
                    fake,
                    catalog_model="gemini-3.1-pro",
                    init_display="Gemini 3.1 Pro",
                )
                result = self.adapter.run_cursor_assignment(
                    assignment_id="visual_evidence_analysis",
                    prompt="inspect the bound image",
                    cursor_agent=str(fake),
                    work_dir=Path(tmp) / "work",
                    attachment_paths=[attachment],
                    founder_explicit_substitute=True,
                )
                self.assertEqual(result["status"], "pass", result)
                receipt = json.loads(
                    Path(result["runtime_receipt_path"]).read_text(encoding="utf-8")
                )
                self.assertEqual(1, len(receipt["attachments"]))
                self.assertEqual(
                    ".runtime/cursor-adapter-tests/fixture.png",
                    receipt["attachments"][0]["path"],
                )
        finally:
            attachment.unlink(missing_ok=True)

    def test_proven_lifecycle_operations_pass(self) -> None:
        for operation in (
            "create_by_first_run",
            "send",
            "wait",
            "resume",
            "cancel",
            "logical_retire",
            "independent_successor_create",
        ):
            result = self.adapter.lifecycle_operation(operation)
            self.assertEqual(result["status"], "pass")

    def test_run_cursor_assignment_parses_catalog_init_and_terminal(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            fake = Path(tmp) / "cursor-agent"
            self.write_fake_cursor_agent(fake)
            result = self.adapter.run_cursor_assignment(
                assignment_id="pre00_close_direction_review",
                prompt="bounded test",
                cursor_agent=str(fake),
                work_dir=Path(tmp) / "work",
                founder_explicit_substitute=True,
            )
            self.assertEqual(result["status"], "pass", result)
            self.assertEqual(result["session_id"], "session-test-1")
            self.assertEqual("ok", Path(result["result_path"]).read_text(encoding="utf-8"))
            goal = json.loads(Path(result["goal_path"]).read_text(encoding="utf-8"))
            goal_schema = json.loads(
                (ROOT / "schemas/cursor-external-goal.schema.json").read_text(encoding="utf-8")
            )
            self.assertEqual([], list(Draft202012Validator(goal_schema).iter_errors(goal)))
            receipt = json.loads(
                Path(result["runtime_receipt_path"]).read_text(encoding="utf-8")
            )
            receipt_schema = json.loads(
                (ROOT / "schemas/cursor-cli-runtime-receipt.schema.json").read_text(encoding="utf-8")
            )
            self.assertEqual([], list(Draft202012Validator(receipt_schema).iter_errors(receipt)))
            self.assertEqual(result["result_path"], receipt["result_path"])
            self.assertEqual(2, receipt["result_byte_size"])
            result_bytes = Path(receipt["result_path"]).read_bytes()
            hook_bytes = Path(receipt["hook_receipt_path"]).read_bytes()
            self.assertEqual(self.adapter.ACTIVE_RUNTIME_RECEIPT_VERSION, receipt["schema_version"])
            self.assertNotEqual(
                self.adapter.LEGACY_RUNTIME_RECEIPT_VERSION,
                receipt["schema_version"],
            )
            self.assertEqual(hashlib.sha256(result_bytes).hexdigest(), receipt["result_sha256"])
            self.assertEqual(hashlib.sha256(hook_bytes).hexdigest(), receipt["hook_receipt_sha256"])
            self.assertEqual(len(hook_bytes), receipt["hook_receipt_byte_size"])
            parsed = self.adapter.parse_cursor_runtime_receipt(
                Path(result["runtime_receipt_path"]),
                allow_legacy_parse=False,
            )
            self.assertEqual(parsed["status"], "pass", parsed)
            self.assertEqual(parsed["mode"], "active_authoring", parsed)

    def test_run_cursor_assignment_holds_on_runtime_evidence_drift(self) -> None:
        cases = {
            "catalog": (
                {"catalog_model": "other-model"},
                {},
                "cursor_exact_model_unavailable",
            ),
            "init_display": (
                {"init_display": "Unexpected Model"},
                {},
                "cursor_init_display_mismatch",
            ),
            "missing_result": (
                {"include_result": False},
                {},
                "cursor_terminal_evidence_incomplete",
            ),
            "session": (
                {"result_session": "different-session"},
                {},
                "cursor_session_id_mismatch",
            ),
            "request": (
                {"request_id": None},
                {},
                "cursor_request_id_missing",
            ),
            "resume": (
                {},
                {"resume_session_id": "expected-resume-session"},
                "cursor_resume_session_mismatch",
            ),
            "auth": (
                {"api_key_source": "env"},
                {},
                "cursor_auth_source_mismatch",
            ),
            "hook_missing": (
                {"include_hook_receipt": False},
                {},
                "cursor_hook_receipt_missing",
            ),
            "hook_denied": (
                {"hook_allowed": False},
                {},
                "cursor_hook_receipt_denied",
            ),
            "hook_session": (
                {"hook_session": "different-session"},
                {},
                "cursor_hook_receipt_session_mismatch",
            ),
        }
        for label, (fake_options, run_options, expected_reason) in cases.items():
            with self.subTest(label=label), tempfile.TemporaryDirectory() as tmp:
                fake = Path(tmp) / "cursor-agent"
                self.write_fake_cursor_agent(fake, **fake_options)
                result = self.adapter.run_cursor_assignment(
                    assignment_id="pre00_close_direction_review",
                    prompt="bounded negative test",
                    cursor_agent=str(fake),
                    work_dir=Path(tmp) / "work",
                    founder_explicit_substitute=True,
                    **run_options,
                )
                self.assertEqual(result["status"], "hold", result)
                self.assertEqual(result["reason"], expected_reason, result)

    def test_runtime_receipt_v2_success_requires_result_and_hook_evidence(self) -> None:
        schema = json.loads(
            (ROOT / "schemas/cursor-cli-runtime-receipt.schema.json").read_text(encoding="utf-8")
        )
        validator = Draft202012Validator(schema)
        missing_fields = {
            "session_id": (None, "attested_session_missing"),
            "result_path": (None, "cursor_result_path_missing"),
            "result_sha256": (None, "cursor_result_sha_mismatch"),
            "result_byte_size": (None, "cursor_result_byte_size_mismatch"),
            "hook_receipt_sha256": (None, "cursor_hook_receipt_sha_mismatch"),
            "hook_receipt_byte_size": (None, "cursor_hook_receipt_byte_size_mismatch"),
        }
        with tempfile.TemporaryDirectory() as tmp:
            assignment = self.build_admission_assignment(
                Path(tmp),
                assignment_id="cursor_grok_46_advisory_worker",
                profile_id="cursor_grok_46_xhigh",
                exact_model="cursor-grok-4.6-xhigh",
                init_display="Cursor Grok 4.6 Extra High",
                effort="xhigh",
            )
            valid = assignment["runtime_receipt"]
            self.assertEqual([], list(validator.iter_errors(valid)))
            profiles = self.adapter.load_cursor_profiles()
            profile = profiles["profiles"]["cursor_grok_46_xhigh"]
            evidence = {
                "actual_model_attestation_proven": "exact_cli_argument_catalog_init_display_terminal_result"
            }
            for field, (value, expected_reason) in missing_fields.items():
                broken = dict(valid)
                broken[field] = value
                self.assertNotEqual([], list(validator.iter_errors(broken)), field)
                broken_assignment = dict(assignment)
                broken_assignment["runtime_receipt"] = broken
                admitted = self.adapter.admit_cursor_assignment(broken_assignment)
                self.assertEqual(admitted["status"], "hold", (field, admitted))
                self.assertEqual(admitted["reason"], expected_reason, (field, admitted))
                attested = self.adapter.attest_actual_model(
                    broken_assignment,
                    profile=profile,
                    evidence=evidence,
                )
                self.assertEqual(attested["status"], "hold", (field, attested))
                self.assertEqual(attested["reason"], expected_reason, (field, attested))

            error_receipt = dict(valid)
            error_receipt.update(
                {
                    "terminal_status": "error",
                    "result_path": None,
                    "result_sha256": None,
                    "result_byte_size": None,
                    "hook_receipt_sha256": None,
                    "hook_receipt_byte_size": None,
                    "hold_reason": "cursor_run_failed",
                }
            )
            self.assertEqual([], list(validator.iter_errors(error_receipt)))


if __name__ == "__main__":
    unittest.main()
