#!/usr/bin/env python3
"""Fail-closed Cursor assignment adapter.

This module implements only actually available host capabilities. A Cursor
assignment is admissible only when its external Goal, project-hook lifecycle,
terminal result bytes, and their hashes remain independently observable.
Display labels and model self-reports are never evidence.
"""

from __future__ import annotations

import hashlib
import json
import os
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import yaml


ROOT = Path(__file__).resolve().parents[1]
CURSOR_PROFILES = Path("automation/providers/cursor-agent-profiles.yaml")
ASSIGNMENT_ROUTING = Path("automation/harness-assignment-model-routing.yaml")
FORBIDDEN_AUTO = {"auto", "cursor auto", "composer auto"}
FORBIDDEN_GROK_ALIAS = {"cursor grok", "cursor-grok", "grok-in-cursor"}
REGISTERED_CURSOR_GROK_PROFILE = "cursor_grok_46_xhigh"
PATH_ONLY_FORBIDDEN = {"path_only", "thumbnail", "placeholder", "unproven_mcp"}
ACTIVE_HARNESS_STATUSES = {"active", "active_text_only"}
CURSOR_IMAGE_EXTENSIONS = {".gif", ".jpeg", ".jpg", ".png", ".webp"}
SHA256_CHARS = frozenset("0123456789abcdef")
ACTIVE_RUNTIME_RECEIPT_VERSION = "idol-cursor-cli-runtime-receipt.v2"
LEGACY_RUNTIME_RECEIPT_VERSION = "idol-cursor-cli-runtime-receipt.v1"
ACTIVE_RUNTIME_RECEIPT_SCHEMA = "schemas/cursor-cli-runtime-receipt.schema.json"
LEGACY_RUNTIME_RECEIPT_SCHEMA = "schemas/cursor-cli-runtime-receipt-v1-legacy.schema.json"


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _read_json_object(path: Path, error: str) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ValueError(error) from exc
    if not isinstance(value, dict):
        raise ValueError(error)
    return value


def _is_sha256(value: str) -> bool:
    return len(value) == 64 and all(char in SHA256_CHARS for char in value)


def _validate_json_file_schema(
    *, root: Path, schema_relative: str, instance_path: Path, error: str
) -> None:
    completed = subprocess.run(
        [
            str(root / "scripts" / "idol-video-python"),
            str(root / "scripts" / "validate_json_schema.py"),
            str(root / schema_relative),
            str(instance_path),
        ],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
        cwd=root,
    )
    if completed.returncode != 0:
        raise ValueError(error)


def _validate_goal_evidence(
    *,
    goal_record: dict[str, Any],
    goal_path: Path,
    goal_sha256: str,
    objective_bytes: bytes,
    assignment_id: str,
    profile_id: str,
    root: Path,
) -> None:
    if not goal_path.is_file():
        raise ValueError("cursor_external_goal_path_missing")
    if not _is_sha256(goal_sha256) or _sha256(goal_path) != goal_sha256:
        raise ValueError("cursor_external_goal_hash_mismatch")
    _validate_json_file_schema(
        root=root,
        schema_relative="schemas/cursor-external-goal.schema.json",
        instance_path=goal_path,
        error="cursor_external_goal_schema_invalid",
    )
    persisted = _read_json_object(goal_path, "cursor_external_goal_record_invalid")
    if persisted != goal_record:
        raise ValueError("cursor_external_goal_record_bytes_mismatch")
    if persisted.get("assignment_id") != assignment_id or persisted.get("profile_id") != profile_id:
        raise ValueError("cursor_external_goal_assignment_mismatch")
    if persisted.get("objective_sha256") != hashlib.sha256(objective_bytes).hexdigest():
        raise ValueError("cursor_external_goal_objective_mismatch")


def _validate_hook_evidence(
    *,
    hook_receipt_path: Path,
    hook_receipt_sha256: str,
    assignment_id: str,
    profile_id: str,
    goal_path: Path,
    goal_sha256: str,
    session_id: str,
) -> tuple[str, int]:
    if not hook_receipt_path.is_file():
        raise ValueError("cursor_hook_receipt_missing")
    if (
        not _is_sha256(hook_receipt_sha256)
        or _sha256(hook_receipt_path) != hook_receipt_sha256
    ):
        raise ValueError("cursor_hook_receipt_sha_mismatch")
    rows: list[dict[str, Any]] = []
    try:
        for raw_line in hook_receipt_path.read_text(encoding="utf-8").splitlines():
            value = json.loads(raw_line)
            if not isinstance(value, dict):
                raise ValueError
            rows.append(value)
    except (OSError, json.JSONDecodeError, ValueError) as exc:
        raise ValueError("cursor_hook_receipt_invalid") from exc
    if not rows:
        raise ValueError("cursor_hook_receipt_empty")
    session_start_count = 0
    for row in rows:
        if row.get("schema_version") != "idol-cursor-hook-receipt.v1":
            raise ValueError("cursor_hook_receipt_schema_invalid")
        if row.get("assignment_id") != assignment_id or row.get("profile_id") != profile_id:
            raise ValueError("cursor_hook_receipt_assignment_mismatch")
        if Path(str(row.get("goal_path") or "")).resolve() != goal_path.resolve() or row.get("goal_sha256") != goal_sha256:
            raise ValueError("cursor_hook_receipt_goal_mismatch")
        if row.get("allowed") is not True or row.get("hold_reason") is not None:
            raise ValueError("cursor_hook_receipt_denied")
        event = str(row.get("event") or "")
        conversation_id = row.get("conversation_id")
        if event == "sessionStart":
            session_start_count += 1
            if conversation_id != session_id:
                raise ValueError("cursor_hook_receipt_session_mismatch")
        elif conversation_id not in (None, "", session_id):
            raise ValueError("cursor_hook_receipt_session_mismatch")
    if session_start_count < 1:
        raise ValueError("cursor_hook_required_event_missing")
    return hook_receipt_sha256, hook_receipt_path.stat().st_size


def _validate_result_evidence(runtime: dict[str, Any]) -> None:
    raw_path = runtime.get("result_path")
    raw_sha = str(runtime.get("result_sha256") or "")
    raw_size = runtime.get("result_byte_size")
    if not isinstance(raw_path, str) or not raw_path:
        raise ValueError("cursor_result_path_missing")
    result_path = Path(raw_path)
    if not result_path.is_file():
        raise ValueError("cursor_result_bytes_missing")
    if not _is_sha256(raw_sha) or _sha256(result_path) != raw_sha:
        raise ValueError("cursor_result_sha_mismatch")
    if not isinstance(raw_size, int) or raw_size < 1 or result_path.stat().st_size != raw_size:
        raise ValueError("cursor_result_byte_size_mismatch")


def _hold_legacy_runtime_authoring(schema_version: Any, assignment_id: str) -> dict[str, Any] | None:
    if schema_version == LEGACY_RUNTIME_RECEIPT_VERSION:
        return _hold("cursor_runtime_receipt_v1_new_authoring_forbidden", assignment_id)
    if schema_version != ACTIVE_RUNTIME_RECEIPT_VERSION:
        return _hold("cursor_runtime_receipt_version_invalid", assignment_id)
    return None


def parse_cursor_runtime_receipt(
    path: Path,
    *,
    root: Path = ROOT,
    allow_legacy_parse: bool = False,
) -> dict[str, Any]:
    """Read a persisted Cursor runtime receipt. v1 is parse-only and never new authoring."""
    try:
        data = _read_json_object(path, "cursor_runtime_receipt_invalid")
    except ValueError as exc:
        return _hold(str(exc), "")
    assignment_id = str(data.get("assignment_id") or "")
    version = data.get("schema_version")
    if version == LEGACY_RUNTIME_RECEIPT_VERSION:
        if allow_legacy_parse is not True:
            return _hold("cursor_runtime_receipt_v1_new_authoring_forbidden", assignment_id)
        try:
            _validate_json_file_schema(
                root=root,
                schema_relative=LEGACY_RUNTIME_RECEIPT_SCHEMA,
                instance_path=path,
                error="cursor_runtime_receipt_legacy_parse_invalid",
            )
        except ValueError as exc:
            return _hold(str(exc), assignment_id)
        return {
            "status": "pass",
            "mode": "parse_only_legacy",
            "assignment_id": assignment_id,
            "receipt": data,
        }
    rejected = _hold_legacy_runtime_authoring(version, assignment_id)
    if rejected is not None:
        return rejected
    try:
        _validate_json_file_schema(
            root=root,
            schema_relative=ACTIVE_RUNTIME_RECEIPT_SCHEMA,
            instance_path=path,
            error="cursor_runtime_receipt_schema_invalid",
        )
    except ValueError as exc:
        return _hold(str(exc), assignment_id)
    return {
        "status": "pass",
        "mode": "active_authoring",
        "assignment_id": assignment_id,
        "receipt": data,
    }


def _attachment_receipts(root: Path, paths: list[Path]) -> list[dict[str, Any]]:
    receipts: list[dict[str, Any]] = []
    resolved_root = root.resolve()
    for supplied in paths:
        resolved = supplied.expanduser().resolve()
        try:
            relative = resolved.relative_to(resolved_root)
        except ValueError as exc:
            raise ValueError("cursor_attachment_outside_workspace") from exc
        if not resolved.is_file():
            raise ValueError("cursor_attachment_missing")
        if resolved.suffix.lower() not in CURSOR_IMAGE_EXTENSIONS:
            raise ValueError("cursor_attachment_type_unsupported")
        receipts.append(
            {
                "path": relative.as_posix(),
                "sha256": _sha256(resolved),
                "byte_size": resolved.stat().st_size,
            }
        )
    return receipts


def load_cursor_profiles(root: Path = ROOT) -> dict[str, Any]:
    value = yaml.safe_load((root / CURSOR_PROFILES).read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError("cursor profile source must be an object")
    return value


def load_assignment_routing(root: Path = ROOT) -> dict[str, Any]:
    value = yaml.safe_load((root / ASSIGNMENT_ROUTING).read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError("assignment routing must be an object")
    return value


def _capability(root: Path) -> dict[str, Any]:
    profiles = load_cursor_profiles(root)
    evidence = profiles.get("capability_evidence")
    return evidence if isinstance(evidence, dict) else {}


def admit_cursor_assignment(
    assignment: dict[str, Any],
    *,
    root: Path = ROOT,
) -> dict[str, Any]:
    """Admit a Cursor assignment only from independently observable evidence."""
    routing = load_assignment_routing(root)
    profiles = load_cursor_profiles(root)
    evidence = _capability(root)
    assignment_id = str(assignment.get("assignment_id") or "")
    requested_model = str(assignment.get("requested_model") or "")
    requested_effort = str(assignment.get("requested_effort") or "")
    observed_model = assignment.get("observed_model")
    observed_effort = assignment.get("observed_effort")
    display_label = str(assignment.get("display_label") or "")
    model_self_report = str(assignment.get("model_self_report") or "")
    auto = bool(assignment.get("auto"))
    topology = str(assignment.get("topology") or "")

    if auto or display_label.lower() in FORBIDDEN_AUTO or requested_model.lower() in FORBIDDEN_AUTO:
        return _hold("cursor_auto_forbidden", assignment_id)
    if topology != "new_cursor_physical_chat":
        return _hold("cursor_requires_new_physical_chat", assignment_id)
    if assignment.get("provider") != "cursor":
        return _hold("cursor_provider_required", assignment_id)

    selector = next(
        (
            row
            for row in routing.get("assignments", [])
            if isinstance(row, dict) and row.get("assignment_id") == assignment_id
        ),
        None,
    )
    if selector is None:
        return _hold("unknown_cursor_assignment", assignment_id)
    profile_id = selector.get("profile_id")
    profile = (profiles.get("profiles") or {}).get(profile_id)
    if not isinstance(profile, dict):
        return _hold("cursor_profile_missing", assignment_id)
    contains_cursor_grok = any(
        token in " ".join([requested_model, display_label]).lower()
        for token in FORBIDDEN_GROK_ALIAS
    )
    if contains_cursor_grok and profile_id != REGISTERED_CURSOR_GROK_PROFILE:
        return _hold("cursor_grok_forbidden", assignment_id)
    if profile_id == REGISTERED_CURSOR_GROK_PROFILE and profile.get("fast_mode") is not False:
        return _hold("cursor_grok_fast_mode_forbidden", assignment_id)
    if selector.get("studio_role") in {
        "overall_director",
        "creative_development_director",
        "edit_director",
    } and profile.get("full_owner_ready") is not True:
        return _hold("cursor_profile_not_full_owner_ready", assignment_id)
    profile_status = str(profile.get("harness_status") or "")
    if profile_status not in ACTIVE_HARNESS_STATUSES:
        return _hold("cursor_profile_held", assignment_id)
    if assignment.get("founder_explicit_substitute") is not True:
        return _hold("founder_explicit_substitute_required", assignment_id)
    if (
        selector.get("activation") != "founder_explicit_substitute"
        or selector.get("status") != "available_founder_explicit_substitute"
    ):
        return _hold("cursor_route_not_founder_selected", assignment_id)

    if requested_model and requested_model != profile.get("exact_model"):
        return _hold("requested_model_mismatch", assignment_id)
    if requested_effort and requested_effort != profile.get("reasoning_effort"):
        return _hold("requested_effort_mismatch", assignment_id)

    goal_record = assignment.get("goal_record")
    if not isinstance(goal_record, dict):
        return _hold("cursor_external_goal_record_required", assignment_id)
    objective = assignment.get("objective")
    if not isinstance(objective, str) or not objective:
        return _hold("cursor_external_goal_objective_required", assignment_id)
    runtime = assignment.get("runtime_receipt")
    if not isinstance(runtime, dict):
        return _hold("cursor_runtime_receipt_required", assignment_id)
    rejected_version = _hold_legacy_runtime_authoring(
        runtime.get("schema_version"), assignment_id
    )
    if rejected_version is not None:
        return rejected_version
    raw_goal_path = runtime.get("goal_path")
    raw_goal_sha256 = str(runtime.get("goal_sha256") or "")
    if not isinstance(raw_goal_path, str) or not raw_goal_path:
        return _hold("cursor_external_goal_path_missing", assignment_id)
    try:
        _validate_goal_evidence(
            goal_record=goal_record,
            goal_path=Path(raw_goal_path),
            goal_sha256=raw_goal_sha256,
            objective_bytes=objective.encode("utf-8"),
            assignment_id=assignment_id,
            profile_id=str(profile_id),
            root=root,
        )
    except ValueError as exc:
        return _hold(str(exc), assignment_id)

    attestation = attest_actual_model(assignment, profile=profile, evidence=evidence)
    if attestation.get("status") != "pass":
        return attestation
    if runtime.get("assignment_id") != assignment_id or runtime.get("profile_id") != profile_id:
        return _hold("cursor_runtime_receipt_assignment_mismatch", assignment_id)
    if runtime.get("goal_path") != raw_goal_path or runtime.get("goal_sha256") != raw_goal_sha256:
        return _hold("cursor_runtime_goal_binding_mismatch", assignment_id)
    try:
        _validate_result_evidence(runtime)
        raw_hook_path = runtime.get("hook_receipt_path")
        if not isinstance(raw_hook_path, str) or not raw_hook_path:
            raise ValueError("cursor_hook_receipt_missing")
        _validate_hook_evidence(
            hook_receipt_path=Path(raw_hook_path),
            hook_receipt_sha256=str(runtime.get("hook_receipt_sha256") or ""),
            assignment_id=assignment_id,
            profile_id=str(profile_id),
            goal_path=Path(raw_goal_path),
            goal_sha256=raw_goal_sha256,
            session_id=str(runtime.get("session_id") or ""),
        )
        if Path(raw_hook_path).stat().st_size != runtime.get("hook_receipt_byte_size"):
            raise ValueError("cursor_hook_receipt_byte_size_mismatch")
    except ValueError as exc:
        return _hold(str(exc), assignment_id)

    if display_label and not assignment.get("independent_runtime_attestation"):
        return _hold("display_label_is_not_evidence", assignment_id)
    if model_self_report and not assignment.get("independent_runtime_attestation"):
        return _hold("model_self_report_is_not_evidence", assignment_id)
    if observed_model not in (None, profile.get("exact_model")):
        return _hold("observed_model_mismatch", assignment_id)
    if observed_effort not in (None, profile.get("reasoning_effort")):
        return _hold("observed_effort_mismatch", assignment_id)

    return {
        "status": "pass",
        "assignment_id": assignment_id,
        "profile_id": profile_id,
        "activation": "founder_explicit_substitute",
    }


def attest_actual_model(
    assignment: dict[str, Any],
    *,
    profile: dict[str, Any],
    evidence: dict[str, Any],
) -> dict[str, Any]:
    assignment_id = str(assignment.get("assignment_id") or "")
    if evidence.get("actual_model_attestation_proven") != (
        "exact_cli_argument_catalog_init_display_terminal_result"
    ):
        return _hold("cursor_actual_model_attestation_unproven", assignment_id)
    runtime = assignment.get("runtime_receipt")
    if not isinstance(runtime, dict):
        return _hold("cursor_runtime_receipt_required", assignment_id)
    if runtime.get("exact_cli_model") != profile.get("exact_model"):
        return _hold("attested_model_mismatch", assignment_id)
    if runtime.get("observed_init_display") != profile.get("expected_init_display"):
        return _hold("attested_init_display_mismatch", assignment_id)
    if runtime.get("session_id") in (None, ""):
        return _hold("attested_session_missing", assignment_id)
    if runtime.get("terminal_status") != "success":
        return _hold("attested_terminal_not_success", assignment_id)
    if runtime.get("source") != "cursor_cli_stream_json":
        return _hold("attestation_source_insufficient", assignment_id)
    result_path = runtime.get("result_path")
    result_sha = str(runtime.get("result_sha256") or "")
    result_size = runtime.get("result_byte_size")
    hook_path = runtime.get("hook_receipt_path")
    hook_sha = str(runtime.get("hook_receipt_sha256") or "")
    hook_size = runtime.get("hook_receipt_byte_size")
    if not isinstance(result_path, str) or not result_path:
        return _hold("cursor_result_path_missing", assignment_id)
    if not _is_sha256(result_sha):
        return _hold("cursor_result_sha_mismatch", assignment_id)
    if not isinstance(result_size, int) or result_size < 1:
        return _hold("cursor_result_byte_size_mismatch", assignment_id)
    if not isinstance(hook_path, str) or not hook_path:
        return _hold("cursor_hook_receipt_missing", assignment_id)
    if not _is_sha256(hook_sha):
        return _hold("cursor_hook_receipt_sha_mismatch", assignment_id)
    if not isinstance(hook_size, int) or hook_size < 1:
        return _hold("cursor_hook_receipt_byte_size_mismatch", assignment_id)
    return {"status": "pass", "assignment_id": assignment_id}


def detect_fable_substitution(assignment: dict[str, Any], *, root: Path = ROOT) -> dict[str, Any]:
    profiles = load_cursor_profiles(root)
    evidence = _capability(root)
    assignment_id = str(assignment.get("assignment_id") or "fp_close_direction_review")
    profile = (profiles.get("profiles") or {}).get("cursor_fable_thinking_xhigh") or {}
    observed = str(assignment.get("observed_model") or assignment.get("independent_runtime_attestation", {}).get("model") or "")
    if evidence.get("fable_retention_approval") != "founder_authorized_current_request":
        return _hold("fable_retention_unbound", assignment_id)
    if assignment.get("founder_explicit_substitute") is not True:
        return _hold("founder_explicit_substitute_required", assignment_id)
    rejected = {str(item).lower() for item in profile.get("reject_substitution_to") or []}
    if observed.lower() in rejected or "opus" in observed.lower():
        return _hold("fable_to_opus_substitution", assignment_id)
    if observed and observed != profile.get("exact_model"):
        return _hold("fable_model_mismatch", assignment_id)
    return {"status": "pass", "assignment_id": assignment_id}


def validate_gemini_attachment(assignment: dict[str, Any], *, root: Path = ROOT) -> dict[str, Any]:
    evidence = _capability(root)
    assignment_id = str(assignment.get("assignment_id") or "visual_evidence_analysis")
    if evidence.get("gemini_binary_attachment_delivery") != "proven_cli_image_flag_exact_bytes":
        return _hold("gemini_binary_attachment_unproven", assignment_id)
    attachments = assignment.get("attachments")
    if not isinstance(attachments, list) or not attachments:
        return _hold("gemini_actual_binary_required", assignment_id)
    for item in attachments:
        if not isinstance(item, dict):
            return _hold("gemini_attachment_must_be_object", assignment_id)
        kind = str(item.get("kind") or "")
        if kind in PATH_ONLY_FORBIDDEN or item.get("path_only") is True:
            return _hold("gemini_path_only_or_placeholder_forbidden", assignment_id)
        if kind != "cli_image_flag":
            return _hold("gemini_cli_image_flag_required", assignment_id)
        if not item.get("sha256") or not item.get("bytes_present"):
            return _hold("gemini_actual_binary_required", assignment_id)
    return {"status": "pass", "assignment_id": assignment_id, "attachment_count": len(attachments)}


def lifecycle_operation(operation: str, *, root: Path = ROOT) -> dict[str, Any]:
    evidence = _capability(root)
    proven = evidence.get("lifecycle_operations_proven")
    proven = proven if isinstance(proven, list) else []
    if operation not in proven:
        return _hold("cursor_lifecycle_operation_unproven", operation)
    return {"status": "pass", "operation": operation}


def list_cursor_models(
    *,
    cursor_agent: str = "cursor-agent",
    timeout: int = 30,
) -> dict[str, str]:
    env = os.environ.copy()
    env["AGENT_CLI_CREDENTIAL_STORE"] = "file"
    completed = subprocess.run(
        [cursor_agent, "models"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
        check=False,
        env=env,
    )
    if completed.returncode != 0:
        raise RuntimeError("cursor_model_catalog_unavailable")
    models: dict[str, str] = {}
    for raw_line in completed.stdout.splitlines():
        if " - " not in raw_line:
            continue
        model_id, display = raw_line.split(" - ", 1)
        model_id = model_id.strip()
        if model_id and model_id != "auto":
            models[model_id] = display.strip()
    return models


def create_external_goal_record(
    *,
    assignment_id: str,
    profile_id: str,
    objective: str,
    output_path: Path,
) -> dict[str, Any]:
    record = {
        "schema_version": "idol-cursor-external-goal.v1",
        "assignment_id": assignment_id,
        "profile_id": profile_id,
        "objective_sha256": hashlib.sha256(objective.encode("utf-8")).hexdigest(),
        "status": "active",
        "created_at": datetime.now(timezone.utc).isoformat(),
    }
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(
        json.dumps(record, ensure_ascii=False, sort_keys=True),
        encoding="utf-8",
    )
    return {
        "record": record,
        "path": str(output_path),
        "sha256": _sha256(output_path),
    }


def run_cursor_assignment(
    *,
    assignment_id: str,
    prompt: str,
    root: Path = ROOT,
    cursor_agent: str = "cursor-agent",
    resume_session_id: str | None = None,
    mode: str = "ask",
    timeout: int = 900,
    work_dir: Path | None = None,
    attachment_paths: list[Path] | None = None,
    founder_explicit_substitute: bool = False,
) -> dict[str, Any]:
    """Run one Founder-selected Cursor CLI assignment and write host-owned receipts."""
    if mode not in {"agent", "ask", "plan"}:
        return _hold("cursor_mode_invalid", assignment_id)
    if founder_explicit_substitute is not True:
        return _hold("founder_explicit_substitute_required", assignment_id)
    selector_doc = load_assignment_routing(root)
    profile_doc = load_cursor_profiles(root)
    selector = next(
        (
            row
            for row in selector_doc.get("assignments", [])
            if isinstance(row, dict) and row.get("assignment_id") == assignment_id
        ),
        None,
    )
    if not isinstance(selector, dict):
        return _hold("unknown_cursor_assignment", assignment_id)
    profile_id = str(selector.get("profile_id") or "")
    profile = (profile_doc.get("profiles") or {}).get(profile_id)
    if not isinstance(profile, dict):
        return _hold("cursor_profile_missing", assignment_id)
    if selector.get("studio_role") in {
        "overall_director",
        "creative_development_director",
        "edit_director",
    } and profile.get("full_owner_ready") is not True:
        return _hold("cursor_profile_not_full_owner_ready", assignment_id)
    if (
        selector.get("activation") != "founder_explicit_substitute"
        or selector.get("status") != "available_founder_explicit_substitute"
        or profile.get("harness_status") not in ACTIVE_HARNESS_STATUSES
        or profile.get("default_enabled") is not False
    ):
        return _hold("cursor_route_not_founder_selected", assignment_id)

    exact_model = str(profile.get("exact_model") or "")
    expected_display = str(profile.get("expected_init_display") or "")
    try:
        attachments = _attachment_receipts(root, list(attachment_paths or []))
    except ValueError as exc:
        return _hold(str(exc), assignment_id)
    if profile.get("attachment_policy") == "actual_binary_cli_image_flag" and not attachments:
        return _hold("cursor_binary_attachment_required", assignment_id)
    try:
        catalog = list_cursor_models(cursor_agent=cursor_agent)
    except (RuntimeError, subprocess.TimeoutExpired):
        return _hold("cursor_model_catalog_unavailable", assignment_id)
    if exact_model not in catalog:
        return _hold("cursor_exact_model_unavailable", assignment_id)

    base = work_dir or (root / ".runtime" / "cursor-assignments" / assignment_id)
    base.mkdir(parents=True, exist_ok=True)
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    goal_path = base / f"goal-{timestamp}.json"
    hook_receipt_path = base / f"hooks-{timestamp}.jsonl"
    runtime_receipt_path = base / f"runtime-{timestamp}.json"
    goal = create_external_goal_record(
        assignment_id=assignment_id,
        profile_id=profile_id,
        objective=prompt,
        output_path=goal_path,
    )
    try:
        _validate_goal_evidence(
            goal_record=goal["record"],
            goal_path=goal_path,
            goal_sha256=goal["sha256"],
            objective_bytes=prompt.encode("utf-8"),
            assignment_id=assignment_id,
            profile_id=profile_id,
            root=root,
        )
    except ValueError as exc:
        return _hold(str(exc), assignment_id)

    env = os.environ.copy()
    env.update(
        {
            "AGENT_CLI_CREDENTIAL_STORE": "file",
            "IDOL_CURSOR_ROUTED_ASSIGNMENT": "1",
            "IDOL_CURSOR_ASSIGNMENT_ID": assignment_id,
            "IDOL_CURSOR_PROFILE_ID": profile_id,
            "IDOL_CURSOR_GOAL_PATH": str(goal_path),
            "IDOL_CURSOR_GOAL_SHA256": goal["sha256"],
            "IDOL_CURSOR_RECEIPT_PATH": str(hook_receipt_path),
            "IDOL_CURSOR_EXPECTED_MODEL_ID": exact_model,
        }
    )
    command = [
        cursor_agent,
        "--trust",
        "--workspace",
        str(root),
    ]
    if resume_session_id:
        command.extend(["--resume", resume_session_id])
    for attachment in attachments:
        command.extend(["--image", str(root / attachment["path"])])
    command.extend(["--model", exact_model])
    if mode != "agent":
        command.extend(["--mode", mode])
    command.extend(["--print", "--output-format", "stream-json", prompt])
    timed_out = False
    try:
        completed = subprocess.run(
            command,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout,
            check=False,
            env=env,
            cwd=root,
        )
    except subprocess.TimeoutExpired as exc:
        timed_out = True
        completed = subprocess.CompletedProcess(
            command,
            124,
            stdout=exc.stdout or "",
            stderr=exc.stderr or "",
        )

    init_event: dict[str, Any] | None = None
    result_event: dict[str, Any] | None = None
    for raw_line in completed.stdout.splitlines():
        try:
            event = json.loads(raw_line)
        except json.JSONDecodeError:
            continue
        if not isinstance(event, dict):
            continue
        if event.get("type") == "system" and event.get("subtype") == "init":
            init_event = event
        if event.get("type") == "result":
            result_event = event

    result_text = result_event.get("result") if result_event else None
    result_path: Path | None = None
    result_sha256: str | None = None
    result_byte_size: int | None = None
    if isinstance(result_text, str) and result_text:
        result_path = base / f"result-{timestamp}.md"
        result_path.write_text(result_text, encoding="utf-8")
        result_sha256 = _sha256(result_path)
        result_byte_size = result_path.stat().st_size

    hold_reason: str | None = None
    hook_receipt_sha256: str | None = None
    hook_receipt_byte_size: int | None = None
    if timed_out:
        hold_reason = "cursor_run_timeout"
    elif completed.returncode != 0:
        hold_reason = "cursor_run_failed"
    elif not init_event or not result_event:
        hold_reason = "cursor_terminal_evidence_incomplete"
    elif init_event.get("apiKeySource") != "login":
        hold_reason = "cursor_auth_source_mismatch"
    elif init_event.get("model") != expected_display:
        hold_reason = "cursor_init_display_mismatch"
    elif result_event.get("subtype") != "success" or result_event.get("is_error") is True:
        hold_reason = "cursor_terminal_not_success"
    elif not init_event.get("session_id") or not result_event.get("session_id"):
        hold_reason = "cursor_session_id_missing"
    elif init_event.get("session_id") != result_event.get("session_id"):
        hold_reason = "cursor_session_id_mismatch"
    elif resume_session_id and init_event.get("session_id") != resume_session_id:
        hold_reason = "cursor_resume_session_mismatch"
    elif not result_event.get("request_id"):
        hold_reason = "cursor_request_id_missing"
    elif result_path is None:
        hold_reason = "cursor_result_bytes_missing"
    else:
        try:
            if not hook_receipt_path.is_file():
                raise ValueError("cursor_hook_receipt_missing")
            hook_receipt_sha256 = _sha256(hook_receipt_path)
            hook_receipt_byte_size = hook_receipt_path.stat().st_size
            _validate_hook_evidence(
                hook_receipt_path=hook_receipt_path,
                hook_receipt_sha256=hook_receipt_sha256,
                assignment_id=assignment_id,
                profile_id=profile_id,
                goal_path=goal_path,
                goal_sha256=goal["sha256"],
                session_id=str(init_event.get("session_id") or ""),
            )
        except (OSError, ValueError) as exc:
            hold_reason = str(exc)

    runtime_receipt = {
        "schema_version": ACTIVE_RUNTIME_RECEIPT_VERSION,
        "assignment_id": assignment_id,
        "profile_id": profile_id,
        "source": "cursor_cli_stream_json",
        "api_key_source": init_event.get("apiKeySource") if init_event else None,
        "exact_cli_model": exact_model,
        "catalog_display": catalog.get(exact_model),
        "observed_init_display": init_event.get("model") if init_event else None,
        "session_id": init_event.get("session_id") if init_event else None,
        "request_id": result_event.get("request_id") if result_event else None,
        "terminal_status": (
            "success"
            if hold_reason is None
            and result_event
            and result_event.get("subtype") == "success"
            and result_event.get("is_error") is not True
            else "error"
        ),
        "goal_path": str(goal_path),
        "goal_sha256": goal["sha256"],
        "hook_receipt_path": str(hook_receipt_path),
        "hook_receipt_sha256": hook_receipt_sha256,
        "hook_receipt_byte_size": hook_receipt_byte_size,
        "result_path": str(result_path) if result_path else None,
        "result_sha256": result_sha256,
        "result_byte_size": result_byte_size,
        "attachments": attachments,
        "resume_session_id": resume_session_id,
        "recorded_at": datetime.now(timezone.utc).isoformat(),
        "hold_reason": hold_reason,
    }
    runtime_receipt_path.write_text(
        json.dumps(runtime_receipt, ensure_ascii=False, sort_keys=True),
        encoding="utf-8",
    )
    parsed_receipt = parse_cursor_runtime_receipt(
        runtime_receipt_path,
        root=root,
        allow_legacy_parse=False,
    )
    if parsed_receipt.get("status") != "pass" and hold_reason is None:
        hold_reason = str(
            parsed_receipt.get("reason") or "cursor_runtime_receipt_schema_invalid"
        )
        runtime_receipt["terminal_status"] = "error"
        runtime_receipt["hold_reason"] = hold_reason
        runtime_receipt_path.write_text(
            json.dumps(runtime_receipt, ensure_ascii=False, sort_keys=True),
            encoding="utf-8",
        )
    if hold_reason:
        held = _hold(hold_reason, assignment_id)
        held.update(
            {
                "runtime_receipt_path": str(runtime_receipt_path),
                "goal_path": str(goal_path),
            }
        )
        return held
    return {
        "status": "pass",
        "assignment_id": assignment_id,
        "profile_id": profile_id,
        "session_id": runtime_receipt["session_id"],
        "request_id": runtime_receipt["request_id"],
        "runtime_receipt_path": str(runtime_receipt_path),
        "goal_path": str(goal_path),
        "result_path": str(result_path),
    }


def _hold(reason: str, assignment_id: str) -> dict[str, Any]:
    return {
        "status": "hold",
        "reason": reason,
        "assignment_id": assignment_id,
        "activation": "disabled_hold",
        "fallback": "none",
    }


def main() -> int:
    profiles = load_cursor_profiles()
    print(f"cursor_status={profiles.get('status')}")
    print(f"goal_observable={_capability(ROOT).get('goal_identity_independently_observable')}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
