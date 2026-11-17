#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "idol_cursor_model_guard.py"


class IdolCursorModelGuardTest(unittest.TestCase):
    def run_hook(
        self,
        payload: dict,
        env: dict[str, str] | None = None,
    ) -> subprocess.CompletedProcess[str]:
        merged = os.environ.copy()
        merged.update(env or {})
        return subprocess.run(
            [sys.executable, str(SCRIPT)],
            input=json.dumps(payload),
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=merged,
            check=False,
        )

    def test_ordinary_chat_is_inert(self) -> None:
        result = self.run_hook({"hook_event_name": "preToolUse"})
        self.assertEqual(result.returncode, 0)
        self.assertEqual(json.loads(result.stdout), {"permission": "allow"})

    def test_routed_model_mismatch_denies_tool(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            goal = root / "goal.json"
            goal.write_text(
                json.dumps(
                    {
                        "status": "active",
                        "assignment_id": "probe",
                        "profile_id": "cursor_opus_thinking_high",
                    },
                    sort_keys=True,
                ),
                encoding="utf-8",
            )
            goal_sha = hashlib.sha256(goal.read_bytes()).hexdigest()
            result = self.run_hook(
                {
                    "hook_event_name": "preToolUse",
                    "conversation_id": "session-1",
                    "model_id": "wrong-model",
                    "model_params": [{"id": "effort", "value": "high"}],
                },
                {
                    "IDOL_CURSOR_ROUTED_ASSIGNMENT": "1",
                    "IDOL_CURSOR_ASSIGNMENT_ID": "probe",
                    "IDOL_CURSOR_PROFILE_ID": "cursor_opus_thinking_high",
                    "IDOL_CURSOR_EXPECTED_MODEL_ID": "claude-opus-5",
                    "IDOL_CURSOR_EXPECTED_EFFORT": "high",
                    "IDOL_CURSOR_GOAL_PATH": str(goal),
                    "IDOL_CURSOR_GOAL_SHA256": goal_sha,
                    "IDOL_CURSOR_RECEIPT_PATH": str(root / "receipt.jsonl"),
                },
            )
            self.assertEqual(result.returncode, 0)
            self.assertEqual(json.loads(result.stdout)["permission"], "deny")
            receipt = json.loads((root / "receipt.jsonl").read_text().splitlines()[-1])
            self.assertEqual(receipt["hold_reason"], "cursor_model_id_mismatch")

    def test_stale_goal_hash_denies_tool(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            goal = root / "goal.json"
            goal.write_text(
                json.dumps(
                    {
                        "status": "active",
                        "assignment_id": "probe",
                        "profile_id": "cursor_opus_thinking_high",
                    },
                    sort_keys=True,
                ),
                encoding="utf-8",
            )
            result = self.run_hook(
                {"hook_event_name": "preToolUse", "conversation_id": "session-1"},
                {
                    "IDOL_CURSOR_ROUTED_ASSIGNMENT": "1",
                    "IDOL_CURSOR_ASSIGNMENT_ID": "probe",
                    "IDOL_CURSOR_PROFILE_ID": "cursor_opus_thinking_high",
                    "IDOL_CURSOR_GOAL_PATH": str(goal),
                    "IDOL_CURSOR_GOAL_SHA256": "0" * 64,
                    "IDOL_CURSOR_RECEIPT_PATH": str(root / "receipt.jsonl"),
                },
            )
            self.assertEqual(json.loads(result.stdout)["permission"], "deny")
            receipt = json.loads((root / "receipt.jsonl").read_text().splitlines()[-1])
            self.assertEqual(
                receipt["hold_reason"],
                "cursor_goal_record_sha_mismatch",
            )


if __name__ == "__main__":
    unittest.main()
