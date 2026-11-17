#!/usr/bin/env python3
"""Fail-closed Cursor hook for assignment, model, Goal, and attachment evidence.

The hook is inert for ordinary Cursor chats. A routed IDOL assignment opts in
with ``IDOL_CURSOR_ROUTED_ASSIGNMENT=1`` and supplies an external Goal record,
expected model identity/parameters, and an append-only receipt path.
"""

from __future__ import annotations

import hashlib
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _params(payload: dict[str, Any]) -> dict[str, str]:
    rows = payload.get("model_params")
    if not isinstance(rows, list):
        return {}
    result: dict[str, str] = {}
    for row in rows:
        if isinstance(row, dict) and isinstance(row.get("id"), str):
            result[row["id"]] = str(row.get("value", ""))
    return result


def _read_goal(path: Path, expected_sha: str) -> dict[str, Any]:
    if not path.is_file():
        raise ValueError("cursor_goal_record_missing")
    actual_sha = _sha256(path)
    if not expected_sha or actual_sha != expected_sha:
        raise ValueError("cursor_goal_record_sha_mismatch")
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ValueError("cursor_goal_record_invalid") from exc
    if not isinstance(value, dict) or value.get("status") != "active":
        raise ValueError("cursor_goal_record_not_active")
    return value


def _attachment_rows(payload: dict[str, Any]) -> list[dict[str, Any]]:
    attachments = payload.get("attachments")
    if not isinstance(attachments, list):
        return []
    result: list[dict[str, Any]] = []
    for item in attachments:
        if not isinstance(item, dict):
            continue
        raw_path = item.get("file_path")
        if not isinstance(raw_path, str) or not raw_path:
            continue
        path = Path(raw_path).expanduser().resolve()
        row: dict[str, Any] = {
            "type": item.get("type"),
            "path": str(path),
            "bytes_present": path.is_file(),
        }
        if path.is_file():
            row["sha256"] = _sha256(path)
            row["byte_size"] = path.stat().st_size
        result.append(row)
    return result


def _append_receipt(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        handle.write("\n")


def _response(
    allowed: bool,
    reason: str | None = None,
    *,
    event: str = "",
) -> dict[str, Any]:
    if event == "preToolUse":
        if allowed:
            return {"permission": "allow"}
        return {
            "permission": "deny",
            "user_message": reason
            or "IDOL Cursor assignment guard denied this tool call.",
            "agent_message": reason
            or "The routed IDOL assignment model/Goal evidence does not match.",
        }
    if event in {"afterAgentResponse", "stop", "sessionStart"}:
        return {}
    if allowed:
        return {"continue": True}
    return {
        "continue": False,
        "user_message": reason or "IDOL Cursor assignment guard denied this prompt.",
    }


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, OSError):
        print(json.dumps(_response(False, "Invalid Cursor hook payload.")))
        return 0

    event = str(payload.get("hook_event_name") or "")
    if os.environ.get("IDOL_CURSOR_ROUTED_ASSIGNMENT") != "1":
        print(json.dumps(_response(True, event=event)))
        return 0

    assignment_id = os.environ.get("IDOL_CURSOR_ASSIGNMENT_ID", "")
    profile_id = os.environ.get("IDOL_CURSOR_PROFILE_ID", "")
    expected_model = os.environ.get("IDOL_CURSOR_EXPECTED_MODEL_ID", "")
    expected_effort = os.environ.get("IDOL_CURSOR_EXPECTED_EFFORT", "")
    expected_context = os.environ.get("IDOL_CURSOR_EXPECTED_CONTEXT", "")
    expected_thinking = os.environ.get("IDOL_CURSOR_EXPECTED_THINKING", "")
    goal_path = Path(os.environ.get("IDOL_CURSOR_GOAL_PATH", ""))
    goal_sha = os.environ.get("IDOL_CURSOR_GOAL_SHA256", "")
    receipt_path = Path(os.environ.get("IDOL_CURSOR_RECEIPT_PATH", ""))

    denied_reason: str | None = None
    goal: dict[str, Any] = {}
    try:
        goal = _read_goal(goal_path, goal_sha)
    except ValueError as exc:
        denied_reason = str(exc)

    if goal and (
        goal.get("assignment_id") != assignment_id
        or goal.get("profile_id") != profile_id
    ):
        denied_reason = "cursor_goal_record_assignment_mismatch"

    model_id = str(payload.get("model_id") or "")
    params = _params(payload)
    model_evidence_available = bool(model_id or params)
    if model_evidence_available:
        if expected_model and model_id != expected_model:
            denied_reason = "cursor_model_id_mismatch"
        if expected_effort and params.get("effort") != expected_effort:
            denied_reason = "cursor_model_effort_mismatch"
        if expected_context and params.get("context") != expected_context:
            denied_reason = "cursor_model_context_mismatch"
        if expected_thinking and params.get("thinking") != expected_thinking:
            denied_reason = "cursor_model_thinking_mismatch"

    attachments = _attachment_rows(payload)
    if (
        event == "beforeSubmitPrompt"
        and os.environ.get("IDOL_CURSOR_REQUIRE_BINARY_ATTACHMENTS") == "1"
        and not attachments
    ):
        denied_reason = "cursor_binary_attachment_required"
    if any(not row.get("bytes_present") for row in attachments):
        denied_reason = "cursor_attachment_bytes_missing"

    receipt = {
        "schema_version": "idol-cursor-hook-receipt.v1",
        "recorded_at": datetime.now(timezone.utc).isoformat(),
        "assignment_id": assignment_id,
        "profile_id": profile_id,
        "event": event,
        "conversation_id": payload.get("conversation_id")
        or payload.get("session_id"),
        "generation_id": payload.get("generation_id"),
        "model_id": model_id,
        "model_params": params,
        "model_evidence_available": model_evidence_available,
        "cursor_version": payload.get("cursor_version"),
        "goal_path": str(goal_path),
        "goal_sha256": goal_sha,
        "attachments": attachments,
        "allowed": denied_reason is None,
        "hold_reason": denied_reason,
    }
    if str(receipt_path):
        _append_receipt(receipt_path, receipt)

    print(
        json.dumps(
            _response(
                denied_reason is None,
                denied_reason,
                event=event,
            )
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
