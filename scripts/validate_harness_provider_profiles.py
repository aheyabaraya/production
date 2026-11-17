#!/usr/bin/env python3
"""Validate the literal-free provider-profile index and exact provider sources."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
import tomllib
from pathlib import Path
from typing import Any, Iterable

import yaml
from jsonschema import Draft202012Validator


ROOT = Path(__file__).resolve().parents[1]
INDEX_PATH = Path("automation/harness-provider-profile-registry.yaml")
SCHEMA_PATH = Path("schemas/harness-provider-profile-registry.schema.json")
XAI_PROVIDER_SCHEMA_PATH = Path("schemas/xai-api-media-provider-profiles.schema.json")
RUN_ROUTE_SCHEMA_PATH = Path("development/front-planning-workbench/contracts/run-route-manifest.schema.json")
NUMERIC_AGENT_OVERRIDE_KEYS = {
    "max_threads",
    "max_concurrent_threads_per_session",
    "max_depth",
}
FORBIDDEN_INDEX_KEYS = {
    "exact_model",
    "model",
    "reasoning_effort",
    "model_reasoning_effort",
    "resolved_provider_model",
}
MODEL_LITERAL = re.compile(r"\b(?:gpt|grok)-[0-9]", re.IGNORECASE)
IMMUTABLE_PROFILE_KEY_ALGORITHM = "sha256_utf8_lf_assignment_profile_fields_v1"
RUNTIME_POLICY_KEY_ALGORITHM = "sha256_utf8_lf_grok_runtime_capabilities_v1"
READINESS_EVIDENCE_VERSION = "provider_source_readiness.v1"
CODEX_LOGICAL_PROFILE_TIERS = {
    "director_deep": ("gpt-5.6-sol", "xhigh"),
    "worker_high": ("gpt-5.6-luna", "max"),
}
GROK_LOGICAL_PROFILE_TIERS = {
    "director_deep": ("grok-4.6", "xhigh"),
    "frontier_director": ("grok-4.6", "xhigh"),
    # Compatibility ID only; current grok_worker_high provider-source effort is xhigh.
    "worker_high": ("grok-4.6", "xhigh"),
    "research_medium": ("grok-4.6", "medium"),
}
GROK_ACTIVATION_EVIDENCE_REFS = {
    "actual_binary_role_lifecycle_receipt": (
        "development/front-planning-workbench/docs/evidence/"
        "grok-1.0.3-role-lifecycle-receipt-2026-08-14.json"
    ),
    "cdd_session_router_implementation": "scripts/idol_director_dispatch_index.rb",
    "cdd_session_router_state_schema": "schemas/cdd-session-router-state.schema.json",
    "cdd_session_router_isolated_test": "scripts/tests/idol_cdd_session_router_test.rb",
    "cdd_successor_contract": "policies/harness-routing-and-sources.md",
}
GROK_DIRECTOR_SUCCESSOR_LIVE_EVIDENCE_PATH = (
    "development/front-planning-workbench/docs/evidence/"
    "grok-1.0.3-cdd-direct-session-router-receipt-2026-08-17.json"
)
GROK_DIRECTOR_SUCCESSOR_REQUIRED_CAPABILITIES = [
    "two_distinct_director_sessions",
    "successor_created_with_zero_model_turns",
    "successor_goal_completed_admission_without_assignment_completion",
    "actual_session_router_source_to_successor_state_sha_generation_cas",
    "inactive_source_denied_and_successor_authorized_after_commit",
    "rollback_denies_successor_and_reactivates_source",
    "exact_successor_resume_continue",
    "no_repo_media_external_writes",
    "no_cross_provider_fallback",
]
GROK_DIRECTOR_SUCCESSOR_OFFLINE_SEMANTICS = [
    "provider_neutral_current_cdd_route_resolution",
    "zero_turn_read_only_successor_session_new",
    "native_goal_before_admission_prompt",
    "durable_terminal_before_preflight_pass",
    "provider_native_goal_admission_mapping",
    "exact_router_state_sha_generation_cas",
    "inactive_source_denied_after_commit",
    "successor_authorized_only_after_commit",
    "rollback_denies_successor_and_reactivates_source",
    "every_operation_rechecks_current_router_state",
    "no_invented_grok_archive_api",
    "html_review_board_and_creative_bytes_immutable",
]
GROK_PROFILE_ACTIVATION_DECISIONS = {
    "grok_director_deep": {
        "status": "hold",
        "verified_requirements": [
            "create_send_wait_resume_continue",
            "fork_successor_with_retained_session",
            "harness_logical_retire_reactivate",
            "provider_native_goal_admission_event_and_attestation",
            "registered_session_router_active_role_singleton_cas",
            "pre00_to_05_no_fallback_shadow",
        ],
        "blocking_requirements": [
            "actual_binary_two_session_successor_receipt",
        ],
        "required_next_evidence": (
            "registered_grok_cdd_zero_turn_successor_goal_admission_router_"
            "cas_denial_rollback_receipt"
        ),
    },
    "grok_director_frontier": {
        "status": "hold",
        "verified_requirements": [
            "create_send_wait_resume_continue",
            "fork_successor_with_retained_session",
            "harness_logical_retire_reactivate",
            "provider_native_goal_admission_event_and_attestation",
            "registered_session_router_active_role_singleton_cas",
            "pre00_to_05_no_fallback_shadow",
        ],
        "blocking_requirements": [
            "actual_binary_two_session_successor_receipt",
        ],
        "required_next_evidence": (
            "registered_grok_cdd_zero_turn_successor_goal_admission_router_"
            "cas_denial_rollback_receipt"
        ),
    },
    "grok_worker_high": {
        "status": "ready",
        "verified_requirements": [
            "exact_department_dispatch",
            "native_goal_event_and_attestation",
            "parent_scoped_authority",
            "exact_output_and_return_recipient",
            "no_provider_fallback",
        ],
        "blocking_requirements": [],
        "required_next_evidence": "none",
    },
    "grok_worker_medium": {
        "status": "hold",
        "verified_requirements": [],
        "blocking_requirements": [
            "exact_provider_inventory_model_display_effort_receipt",
            "assignment_schema_registry_closure",
        ],
        "required_next_evidence": "grok_46_medium_research_inventory_and_registry_closure",
    },
}
GROK_DIRECTOR_READY_DECISION = {
    "status": "ready",
    "verified_requirements": [
        "create_send_wait_resume_continue",
        "fork_successor_with_retained_session",
        "harness_logical_retire_reactivate",
        "provider_native_goal_admission_event_and_attestation",
        "registered_session_router_active_role_singleton_cas",
        "pre00_to_05_no_fallback_shadow",
        "actual_binary_two_session_successor_receipt",
    ],
    "blocking_requirements": [],
    "required_next_evidence": "none",
}


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _sha256_lines(lines: Iterable[Any]) -> str:
    payload = "\n".join(str(value).lower() if isinstance(value, bool) else str(value) for value in lines)
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def _provider_source_readiness_evidence(assignment: dict[str, Any]) -> str:
    return _sha256_lines([
        READINESS_EVIDENCE_VERSION,
        assignment.get("assignment_id", ""),
        assignment.get("provider_source_path", ""),
        assignment.get("provider_source_sha256", ""),
        assignment.get("provider_profile_pointer", ""),
        assignment.get("model", ""),
        assignment.get("effort", ""),
        assignment.get("adapter_id", ""),
        assignment.get("auth_lane", ""),
        assignment.get("auth_authority_ref") or "",
        assignment.get("provider_capability_status", ""),
        assignment.get("provider_harness_status", ""),
        assignment.get("provider_full_owner_ready", False),
    ])


def _immutable_profile_key(assignment: dict[str, Any]) -> str:
    readiness = assignment.get("provider_source_readiness")
    readiness = readiness if isinstance(readiness, dict) else {}
    return _sha256_lines([
        IMMUTABLE_PROFILE_KEY_ALGORITHM,
        assignment.get("assignment_id", ""),
        assignment.get("provider", ""),
        assignment.get("adapter_id", ""),
        assignment.get("runtime_surface", ""),
        assignment.get("profile_id", ""),
        assignment.get("execution_profile_id", ""),
        assignment.get("logical_profile_alias", ""),
        assignment.get("model", ""),
        assignment.get("effort", ""),
        assignment.get("auth_lane", ""),
        assignment.get("auth_authority_ref") or "",
        assignment.get("provider_source_path", ""),
        assignment.get("provider_source_sha256", ""),
        assignment.get("provider_profile_pointer", ""),
        readiness.get("evidence_sha256", ""),
    ])


def _grok_runtime_policy_key(assignment: dict[str, Any]) -> str:
    runtime = assignment.get("runtime_capabilities")
    runtime = runtime if isinstance(runtime, dict) else {}
    write_paths = runtime.get("allowed_write_paths")
    write_paths = sorted(str(path) for path in write_paths) if isinstance(write_paths, list) else []
    return _sha256_lines([
        "grok_runtime_capabilities.v1",
        assignment.get("assignment_id", ""),
        runtime.get("execution_mode", ""),
        runtime.get("filesystem", ""),
        len(write_paths),
        *write_paths,
        runtime.get("web_search", False),
        runtime.get("provider_native_subagents", False),
        runtime.get("memory", False),
        runtime.get("imagine", False),
        runtime.get("authority_boundary", ""),
    ])


def _load_yaml(path: Path, errors: list[str]) -> dict[str, Any]:
    try:
        value = yaml.safe_load(path.read_text(encoding="utf-8"))
    except (OSError, yaml.YAMLError) as exc:
        errors.append(f"cannot parse {path}: {exc}")
        return {}
    if not isinstance(value, dict):
        errors.append(f"{path} must contain an object")
        return {}
    return value


def _load_json(path: Path, errors: list[str]) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        errors.append(f"cannot parse {path}: {exc}")
        return {}
    if not isinstance(value, dict):
        errors.append(f"{path} must contain an object")
        return {}
    return value


def _load_toml(path: Path, errors: list[str]) -> dict[str, Any]:
    try:
        with path.open("rb") as handle:
            value = tomllib.load(handle)
    except (OSError, tomllib.TOMLDecodeError) as exc:
        errors.append(f"cannot parse {path}: {exc}")
        return {}
    return value


def _walk(value: Any, pointer: str = "$") -> Iterable[tuple[str, Any]]:
    yield pointer, value
    if isinstance(value, dict):
        for key, item in value.items():
            yield from _walk(item, f"{pointer}.{key}")
    elif isinstance(value, list):
        for index, item in enumerate(value):
            yield from _walk(item, f"{pointer}[{index}]")


def _resolve_local_ref(root_schema: dict[str, Any], reference: str) -> dict[str, Any]:
    if not reference.startswith("#/"):
        raise ValueError(f"unsupported non-local schema reference {reference!r}")
    value: Any = root_schema
    for part in reference[2:].split("/"):
        part = part.replace("~1", "/").replace("~0", "~")
        value = value[part]
    if not isinstance(value, dict):
        raise ValueError(f"schema reference {reference!r} does not resolve to an object")
    return value


def _matches_type(value: Any, expected: str) -> bool:
    if expected == "object":
        return isinstance(value, dict)
    if expected == "array":
        return isinstance(value, list)
    if expected == "string":
        return isinstance(value, str)
    if expected == "integer":
        return isinstance(value, int) and not isinstance(value, bool)
    if expected == "boolean":
        return isinstance(value, bool)
    return True


def _schema_failures(
    value: Any,
    schema: dict[str, Any],
    root_schema: dict[str, Any],
    pointer: str,
) -> Iterable[str]:
    if "$ref" in schema:
        try:
            target = _resolve_local_ref(root_schema, str(schema["$ref"]))
        except (KeyError, TypeError, ValueError) as exc:
            yield f"{pointer}: {exc}"
            return
        yield from _schema_failures(value, target, root_schema, pointer)
        return
    if "const" in schema and value != schema["const"]:
        yield f"{pointer}: expected constant {schema['const']!r}, found {value!r}"
        return
    if "enum" in schema and value not in schema["enum"]:
        yield f"{pointer}: value {value!r} is outside enum {schema['enum']!r}"
        return
    expected_type = schema.get("type")
    if isinstance(expected_type, str) and not _matches_type(value, expected_type):
        yield f"{pointer}: expected {expected_type}, found {type(value).__name__}"
        return
    if isinstance(value, dict):
        required = schema.get("required", [])
        for key in required if isinstance(required, list) else []:
            if key not in value:
                yield f"{pointer}: missing required property {key!r}"
        min_properties = schema.get("minProperties")
        if isinstance(min_properties, int) and len(value) < min_properties:
            yield f"{pointer}: requires at least {min_properties} properties"
        properties = schema.get("properties")
        properties = properties if isinstance(properties, dict) else {}
        additional = schema.get("additionalProperties", True)
        for key, item in value.items():
            child = f"{pointer}.{key}"
            if key in properties and isinstance(properties[key], dict):
                yield from _schema_failures(item, properties[key], root_schema, child)
            elif additional is False:
                yield f"{child}: additional property is forbidden"
            elif isinstance(additional, dict):
                yield from _schema_failures(item, additional, root_schema, child)
    elif isinstance(value, list):
        min_items = schema.get("minItems")
        if isinstance(min_items, int) and len(value) < min_items:
            yield f"{pointer}: requires at least {min_items} items"
        if schema.get("uniqueItems") is True:
            encoded = [json.dumps(item, sort_keys=True, ensure_ascii=False) for item in value]
            if len(encoded) != len(set(encoded)):
                yield f"{pointer}: items must be unique"
        item_schema = schema.get("items")
        if isinstance(item_schema, dict):
            for index, item in enumerate(value):
                yield from _schema_failures(item, item_schema, root_schema, f"{pointer}[{index}]")
    elif isinstance(value, str):
        min_length = schema.get("minLength")
        if isinstance(min_length, int) and len(value) < min_length:
            yield f"{pointer}: string is shorter than {min_length}"
        pattern = schema.get("pattern")
        if isinstance(pattern, str) and re.search(pattern, value) is None:
            yield f"{pointer}: string does not match {pattern!r}"


def _validate_schema(index: dict[str, Any], schema: dict[str, Any], errors: list[str]) -> None:
    if not schema:
        return
    if schema.get("$schema") != "https://json-schema.org/draft/2020-12/schema":
        errors.append("provider registry schema must declare Draft 2020-12")
    for failure in Draft202012Validator(schema).iter_errors(index):
        pointer = "/" + "/".join(str(part) for part in failure.absolute_path)
        errors.append(f"provider registry schema {pointer}: {failure.message}")


def _validate_literal_free_index(index: dict[str, Any], errors: list[str]) -> None:
    for pointer, value in _walk(index):
        if isinstance(value, dict):
            forbidden = sorted(FORBIDDEN_INDEX_KEYS.intersection(value))
            if forbidden:
                errors.append(f"literal-free index {pointer} contains forbidden keys {forbidden}")
        elif isinstance(value, str) and MODEL_LITERAL.search(value):
            errors.append(f"literal-free index {pointer} contains an exact model literal")


def _source_set_digest(rows: list[tuple[str, str]]) -> str:
    payload = "".join(f"{path}:{digest}\n" for path, digest in sorted(rows))
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def _validate_codex_source_set(
    root: Path,
    alias: str,
    provider: dict[str, Any],
    errors: list[str],
) -> dict[str, tuple[str, str]]:
    role_profiles = provider.get("role_profiles")
    if not isinstance(role_profiles, dict):
        return {}
    resolved: dict[str, tuple[str, str]] = {}
    digest_rows: list[tuple[str, str]] = []
    for role, row in role_profiles.items():
        if not isinstance(row, dict):
            continue
        relative = str(row.get("source_path", ""))
        path = root / relative
        if not path.is_file():
            errors.append(f"{alias}.{role} provider source is missing: {relative}")
            continue
        actual_sha = _sha256(path)
        if row.get("source_sha256") != actual_sha:
            errors.append(f"{alias}.{role} provider source hash is stale: {relative}")
        digest_rows.append((relative, actual_sha))
        document = _load_toml(path, errors)
        if document.get("name") != row.get("profile_id"):
            errors.append(f"{alias}.{role} profile_id does not match {relative} name")
        model = document.get("model")
        effort = document.get("model_reasoning_effort")
        if not isinstance(model, str) or not model.strip():
            errors.append(f"{alias}.{role} exact model is missing from its Codex TOML")
        if not isinstance(effort, str) or not effort.strip():
            errors.append(f"{alias}.{role} exact effort is missing from its Codex TOML")
        if isinstance(model, str) and isinstance(effort, str):
            resolved[str(role)] = (model, effort)
    actual_set_sha = _source_set_digest(digest_rows)
    if provider.get("source_set_sha256") != actual_set_sha:
        errors.append(f"{alias}.codex source_set_sha256 is stale")
    values = set(resolved.values())
    if len(values) > 1:
        errors.append(f"{alias}.codex role profiles must resolve to one exact model/effort tier")
    expected_tier = CODEX_LOGICAL_PROFILE_TIERS.get(alias)
    if expected_tier is not None:
        for role, tier in resolved.items():
            if tier != expected_tier:
                errors.append(
                    f"{alias}.{role} Codex tier must be exact "
                    f"{expected_tier[0]}/{expected_tier[1]}"
                )
    return resolved


def _bound_grok_activation_ref(
    root: Path,
    evidence_refs: dict[str, Any],
    evidence_id: str,
    errors: list[str],
) -> Path | None:
    row = evidence_refs.get(evidence_id)
    if not isinstance(row, dict):
        errors.append(f"Grok non-media activation evidence is missing {evidence_id}")
        return None
    if set(row) != {"path", "sha256"}:
        errors.append(f"Grok activation evidence {evidence_id} must contain only path and sha256")
    expected_path = GROK_ACTIVATION_EVIDENCE_REFS[evidence_id]
    if row.get("path") != expected_path:
        errors.append(f"Grok activation evidence {evidence_id} path drifted")
        return None
    path = _contained_file(root, Path(expected_path), errors, f"Grok activation evidence {evidence_id}")
    if path is None:
        return None
    actual_sha = _sha256(path)
    if row.get("sha256") != actual_sha:
        errors.append(f"Grok activation evidence {evidence_id} hash is stale")
    return path


def _validate_grok_director_successor_live_evidence(
    root: Path,
    evidence: dict[str, Any],
    provider_document: dict[str, Any],
    errors: list[str],
) -> bool:
    row = evidence.get("director_successor_live_evidence")
    if not isinstance(row, dict):
        errors.append("Grok non-media activation evidence lacks the director successor live-evidence gate")
        return False
    expected_keys = {"status", "path", "sha256", "required_capabilities", "missing_action"}
    if set(row) != expected_keys:
        errors.append("Grok director successor live-evidence fields drifted")
    if row.get("path") != GROK_DIRECTOR_SUCCESSOR_LIVE_EVIDENCE_PATH:
        errors.append("Grok director successor live-evidence path drifted")
    if row.get("required_capabilities") != GROK_DIRECTOR_SUCCESSOR_REQUIRED_CAPABILITIES:
        errors.append("Grok director successor required-capability set drifted")
    if row.get("missing_action") != "hold_shared_director_deep_without_provider_fallback":
        errors.append("Missing Grok director successor evidence must HOLD without provider fallback")

    candidate_path = root / GROK_DIRECTOR_SUCCESSOR_LIVE_EVIDENCE_PATH
    status = row.get("status")
    if status == "required_missing":
        if row.get("sha256") is not None:
            errors.append("Missing Grok director successor evidence must carry sha256: null")
        if candidate_path.exists():
            errors.append("Grok director successor receipt exists but is not hash-bound as present")
        return False
    if status != "present":
        errors.append("Grok director successor live-evidence status must be required_missing or present")
        return False

    receipt_path = _contained_file(
        root,
        Path(GROK_DIRECTOR_SUCCESSOR_LIVE_EVIDENCE_PATH),
        errors,
        "Grok director successor live evidence",
    )
    if receipt_path is None:
        return False
    actual_sha = _sha256(receipt_path)
    if row.get("sha256") != actual_sha:
        errors.append("Grok director successor live-evidence hash is stale")
        return False
    receipt = _load_json(receipt_path, errors)
    if not receipt:
        return False
    if set(receipt) != {
        "evidence_kind",
        "status",
        "observed_at",
        "authority",
        "runtime",
        "sessions",
        "goal_admission",
        "router",
        "compatibility_revalidation",
        "continuation",
        "boundary",
    }:
        errors.append("Grok director successor live receipt fields drifted")
    if receipt.get("evidence_kind") != "noncanonical_actual_binary_grok_cdd_direct_session_router_receipt":
        errors.append("Grok director successor live receipt kind drifted")
    if receipt.get("status") != "pass":
        errors.append("Grok director successor live receipt must pass")
    if receipt.get("authority") != "evidence_only_no_creative_pass_no_provider_default_switch_no_canonical_write":
        errors.append("Grok director successor live receipt overstates authority")
    if not isinstance(receipt.get("observed_at"), str) or not receipt["observed_at"].strip():
        errors.append("Grok director successor live receipt observed_at is missing")

    runtime = receipt.get("runtime") if isinstance(receipt.get("runtime"), dict) else {}
    director_profile = provider_document.get("profiles", {}).get("grok_director_deep", {})
    expected_runtime = {
        "model": director_profile.get("exact_model"),
        "reasoning_effort": director_profile.get("reasoning_effort"),
        "auth_lane": "subscription_oauth",
        "xai_api_key_present": False,
        "sandbox": "idol-repo",
        "permission_mode": "plan",
        "web_search": False,
        "memory": False,
        "imagine": False,
        "canonical_or_media_writes_requested": False,
        "external_actions_requested": False,
        "probe_root_class": "bounded_private_tmp_noncanonical_proof",
    }
    for field, expected in expected_runtime.items():
        if runtime.get(field) != expected:
            errors.append(f"Grok director successor live receipt runtime.{field} must be {expected!r}")
    if not isinstance(runtime.get("binary_sha256"), str) or not re.fullmatch(r"[a-f0-9]{64}", runtime["binary_sha256"]):
        errors.append("Grok director successor live receipt binary_sha256 is invalid")
    baseline_receipt = _load_json(
        root / GROK_ACTIVATION_EVIDENCE_REFS["actual_binary_role_lifecycle_receipt"], errors
    )
    baseline_runtime = baseline_receipt.get("runtime") if isinstance(baseline_receipt.get("runtime"), dict) else {}
    if runtime.get("binary") != baseline_runtime.get("binary"):
        errors.append("Grok director successor live receipt binary path differs from the bound role lifecycle receipt")
    if runtime.get("binary_sha256") != baseline_runtime.get("binary_sha256"):
        errors.append("Grok director successor live receipt binary hash differs from the bound role lifecycle receipt")

    sessions = receipt.get("sessions") if isinstance(receipt.get("sessions"), dict) else {}
    source_id = sessions.get("source_session_id_sha256")
    successor_id = sessions.get("successor_session_id_sha256")
    if not isinstance(source_id, str) or not re.fullmatch(r"[a-f0-9]{64}", source_id):
        errors.append("Grok director successor source session digest is invalid")
    if not isinstance(successor_id, str) or not re.fullmatch(r"[a-f0-9]{64}", successor_id):
        errors.append("Grok director successor session digest is invalid")
    if sessions.get("distinct") is not True or source_id == successor_id:
        errors.append("Grok director successor live receipt must prove two distinct sessions")
    if sessions.get("successor_model_turns_before_admission") != 0:
        errors.append("Grok director successor must be created with zero model turns before admission")

    goal = receipt.get("goal_admission") if isinstance(receipt.get("goal_admission"), dict) else {}
    expected_goal = {
        "goal_semantics": "grok_goal_completed_admission",
        "goal_terminal_state": "complete",
        "goal_last_event": "goal_completed",
        "successor_assignment_state_after_goal": "admitted_read_only",
        "goal_completion_closes_assignment": False,
        "admission_status": "pass",
    }
    for field, expected in expected_goal.items():
        if goal.get(field) != expected:
            errors.append(f"Grok director successor live receipt goal_admission.{field} must be {expected!r}")
    for digest_field in (
        "goal_id_sha256",
        "goal_objective_sha256",
        "goal_terminal_event_sha256",
        "admission_digest",
    ):
        digest = goal.get(digest_field)
        if not isinstance(digest, str) or not re.fullmatch(r"[a-f0-9]{64}", digest):
            errors.append(f"Grok director successor live receipt goal_admission.{digest_field} is not a SHA-256")

    router = receipt.get("router") if isinstance(receipt.get("router"), dict) else {}
    router_ref = provider_document.get("nonmedia_activation_evidence", {}).get("evidence_refs", {})
    implementation_ref = router_ref.get("cdd_session_router_implementation", {})
    schema_ref = router_ref.get("cdd_session_router_state_schema", {})
    required_router = {
        "implementation_path": GROK_ACTIVATION_EVIDENCE_REFS["cdd_session_router_implementation"],
        "state_schema_path": GROK_ACTIVATION_EVIDENCE_REFS["cdd_session_router_state_schema"],
        "state_schema_version": "idol-cdd-session-router-state.v1",
        "state_generations": [0, 1, 2, 3],
        "source_active_before": True,
        "successor_read_only_before_commit": True,
        "source_denied_after_commit": True,
        "successor_authorized_after_commit": True,
        "successor_denied_after_rollback": True,
        "source_authorized_after_rollback": True,
        "simultaneous_writer_count_max": 1,
        "authorization_gate_operations": ["prompt", "resume", "dispatch", "review", "canonical_write"],
        "proof_state_root": "bounded_private_tmp_noncanonical_proof",
    }
    for field, expected in required_router.items():
        if router.get(field) != expected:
            errors.append(f"Grok director successor live receipt router.{field} must be {expected!r}")
    for digest_field in ("implementation_sha256", "state_schema_sha256"):
        digest = router.get(digest_field)
        if not isinstance(digest, str) or not re.fullmatch(r"[a-f0-9]{64}", digest):
            errors.append(f"Grok director successor live receipt router.{digest_field} is not a SHA-256")

    compatibility = (
        receipt.get("compatibility_revalidation")
        if isinstance(receipt.get("compatibility_revalidation"), dict)
        else {}
    )
    isolated_test_ref = router_ref.get("cdd_session_router_isolated_test", {})
    required_compatibility = {
        "status": "pass",
        "current_implementation_sha256": implementation_ref.get("sha256"),
        "current_state_schema_sha256": schema_ref.get("sha256"),
        "current_isolated_test_sha256": isolated_test_ref.get("sha256"),
        "change_scope": "add_cursor_provider_and_external_goal_runtime_receipt_branch",
        "grok_route_semantics_changed": False,
        "isolated_tests_pass": True,
        "live_grok_execution_repeated": False,
        "external_or_generative_actions": 0,
    }
    for field, expected in required_compatibility.items():
        if compatibility.get(field) != expected:
            errors.append(
                f"Grok director successor compatibility revalidation {field} must be {expected!r}"
            )
    if not isinstance(compatibility.get("recorded_at"), str) or not compatibility["recorded_at"].strip():
        errors.append("Grok director successor compatibility revalidation recorded_at is missing")
    for digest_field in (
        "initialize_receipt_sha256",
        "admit_receipt_sha256",
        "commit_receipt_sha256",
        "source_denial_receipt_sha256",
        "successor_authorization_receipt_sha256",
        "rollback_receipt_sha256",
        "successor_denial_receipt_sha256",
        "source_reactivation_authorization_receipt_sha256",
        "final_state_sha256",
    ):
        digest = router.get(digest_field)
        if not isinstance(digest, str) or not re.fullmatch(r"[a-f0-9]{64}", digest):
            errors.append(f"Grok director successor live receipt router.{digest_field} is not a SHA-256")

    continuation = receipt.get("continuation") if isinstance(receipt.get("continuation"), dict) else {}
    required_continuation = {
        "successor_session_loaded_exact": True,
        "successor_continue_response_completed": True,
        "successor_continue_durable_terminal": True,
        "clean_stop": True,
    }
    for field, expected in required_continuation.items():
        if continuation.get(field) != expected:
            errors.append(f"Grok director successor live receipt continuation.{field} must be {expected!r}")
    for digest_field in ("continue_prompt_sha256", "continue_terminal_event_sha256"):
        digest = continuation.get(digest_field)
        if not isinstance(digest, str) or not re.fullmatch(r"[a-f0-9]{64}", digest):
            errors.append(f"Grok director successor live receipt continuation.{digest_field} is not a SHA-256")

    boundary = receipt.get("boundary") if isinstance(receipt.get("boundary"), dict) else {}
    required_boundary = {
        "tracked_source_status_unchanged": True,
        "repository_write_count": 0,
        "media_generation_count": 0,
        "external_action_count": 0,
        "cross_provider_fallback_count": 0,
        "html_or_review_board_write_count": 0,
        "creative_or_canonical_write_count": 0,
    }
    for field, expected in required_boundary.items():
        if boundary.get(field) != expected:
            errors.append(f"Grok director successor live receipt boundary.{field} must be {expected!r}")
    return True


def _validate_grok_activation_evidence(
    root: Path,
    document: dict[str, Any],
    errors: list[str],
) -> dict[str, Any]:
    evidence = document.get("nonmedia_activation_evidence")
    if not isinstance(evidence, dict):
        errors.append("Grok provider source must bind non-media activation evidence")
        return {}
    if set(evidence) != {
        "evidence_scope",
        "external_or_generative_actions",
        "evidence_refs",
        "director_successor_offline_evidence",
        "director_successor_live_evidence",
        "profile_decisions",
    }:
        errors.append("Grok non-media activation evidence fields drifted")
    if evidence.get("evidence_scope") != "exact_profile_readiness_only_no_default_switch_no_creative_pass":
        errors.append("Grok activation evidence must not imply a default switch or creative PASS")
    if evidence.get("external_or_generative_actions") != 0:
        errors.append("Grok activation evidence must record zero external or generative actions")
    offline = evidence.get("director_successor_offline_evidence")
    expected_offline = {
        "status": "pass",
        "evidence_class": "mocked_acp_offline_contract",
        "verified_semantics": GROK_DIRECTOR_SUCCESSOR_OFFLINE_SEMANTICS,
        "live_binary_claim": False,
        "external_or_generative_actions": 0,
    }
    if offline != expected_offline:
        errors.append("Grok director successor offline evidence contract drifted")

    evidence_refs = evidence.get("evidence_refs")
    evidence_refs = evidence_refs if isinstance(evidence_refs, dict) else {}
    if set(evidence_refs) != set(GROK_ACTIVATION_EVIDENCE_REFS):
        errors.append("Grok activation evidence reference set drifted")
    resolved = {
        evidence_id: _bound_grok_activation_ref(root, evidence_refs, evidence_id, errors)
        for evidence_id in GROK_ACTIVATION_EVIDENCE_REFS
    }

    receipt_path = resolved.get("actual_binary_role_lifecycle_receipt")
    receipt = _load_json(receipt_path, errors) if receipt_path is not None else {}
    if receipt:
        if receipt.get("evidence_kind") != "noncanonical_actual_binary_grok_role_lifecycle_activation_receipt":
            errors.append("Grok role lifecycle receipt kind drifted")
        if receipt.get("status") != "pass":
            errors.append("Grok role lifecycle receipt must pass")
        if receipt.get("authority") != "evidence_only_no_creative_pass_no_provider_default_switch_no_canonical_write":
            errors.append("Grok role lifecycle receipt overstates authority")
        probe = receipt.get("probe") if isinstance(receipt.get("probe"), dict) else {}
        if probe.get("model_response_text_stored_or_disclosed") is not False:
            errors.append("Grok role lifecycle receipt must not store or disclose model response text")
        runtime = receipt.get("runtime") if isinstance(receipt.get("runtime"), dict) else {}
        expected_runtime = {
            "auth_lane": "subscription_oauth",
            "xai_api_key_present": False,
            "sandbox": "idol-repo",
            "permission_mode": "plan",
            "web_search": False,
            "memory": False,
            "imagine": False,
            "provider_native_subagents": True,
            "canonical_or_media_writes_requested": False,
            "tracked_source_status_unchanged": True,
        }
        for field, expected in expected_runtime.items():
            if runtime.get(field) != expected:
                errors.append(f"Grok role lifecycle receipt runtime.{field} must be {expected!r}")
        profiles = document.get("profiles") if isinstance(document.get("profiles"), dict) else {}
        selected_models = {
            profile.get("exact_model")
            for profile in profiles.values()
            if isinstance(profile, dict) and isinstance(profile.get("exact_model"), str)
        }
        if len(selected_models) != 1 or runtime.get("model") not in selected_models:
            errors.append("Grok role lifecycle receipt model differs from the exact provider source")
        role_cases = receipt.get("role_cases") if isinstance(receipt.get("role_cases"), list) else []
        cases = {
            row.get("case_id"): row
            for row in role_cases
            if isinstance(row, dict) and isinstance(row.get("case_id"), str)
        }
        expected_cases = {
            "director_deep_actual_binary": {
                "roles": ["overall_director", "creative_development_director", "edit_director"],
                "effort": "xhigh",
                "resume": True,
            },
            "worker_high_actual_binary": {
                "roles": ["department_worker", "mechanical_coordinator"],
                "effort": "high",
                "resume": False,
            },
        }
        if set(cases) != set(expected_cases):
            errors.append("Grok role lifecycle receipt case set drifted")
        for case_id, expected in expected_cases.items():
            row = cases.get(case_id)
            if not isinstance(row, dict):
                continue
            if row.get("logical_roles_covered_by_the_same_registered_profile") != expected["roles"]:
                errors.append(f"Grok role lifecycle receipt {case_id} role coverage drifted")
            if row.get("reasoning_effort") != expected["effort"]:
                errors.append(f"Grok role lifecycle receipt {case_id} effort drifted")
            for field in ("goal_state", "interrupted_after_exact_goal", "clean_stop", "stderr_nonempty"):
                expected_value = {
                    "goal_state": "active",
                    "interrupted_after_exact_goal": True,
                    "clean_stop": True,
                    "stderr_nonempty": False,
                }[field]
                if row.get(field) != expected_value:
                    errors.append(f"Grok role lifecycle receipt {case_id}.{field} must be {expected_value!r}")
            if expected["resume"]:
                if row.get("session_loaded_exact") is not True or row.get("continue_response_completed") is not True:
                    errors.append("Grok director lifecycle receipt lacks exact resume and continuation")
            for digest_field in ("session_id_sha256", "goal_command_sha256", "goal_id_sha256", "goal_event_raw_sha256"):
                if not isinstance(row.get(digest_field), str) or not re.fullmatch(r"[a-f0-9]{64}", row[digest_field]):
                    errors.append(f"Grok role lifecycle receipt {case_id}.{digest_field} is not a SHA-256")
        director_helper = cases.get("director_deep_actual_binary", {}).get("provider_internal_helper_pair", {})
        if not isinstance(director_helper, dict) or {
            "classification": director_helper.get("classification"),
            "spawned": director_helper.get("spawned"),
            "finished": director_helper.get("finished"),
            "same_child_id": director_helper.get("same_child_id"),
            "same_parent_session": director_helper.get("same_parent_session"),
            "same_parent_prompt": director_helper.get("same_parent_prompt"),
            "logical_idol_role_or_owner_granted": director_helper.get("logical_idol_role_or_owner_granted"),
            "canonical_writer_granted": director_helper.get("canonical_writer_granted"),
        } != {
            "classification": "official_harness_owned_goal_verifier_consistent",
            "spawned": 1,
            "finished": 1,
            "same_child_id": True,
            "same_parent_session": True,
            "same_parent_prompt": True,
            "logical_idol_role_or_owner_granted": False,
            "canonical_writer_granted": False,
        }:
            errors.append("Grok role lifecycle helper evidence is not bounded to the Goal verifier")
        worker_case = cases.get("worker_high_actual_binary", {})
        if worker_case.get("provider_internal_helper_events_before_goal_capture") != 0:
            errors.append("Grok worker lifecycle must capture the exact active Goal before provider-internal helper events")
        activation_scope = receipt.get("activation_scope")
        activation_scope = activation_scope if isinstance(activation_scope, dict) else {}
        expected_actual_binary_proofs = [
            "director_deep_xhigh_create_goal_wait_interrupt_resume_continue_clean_stop",
            "worker_high_create_goal_wait_clean_stop",
            "exact_active_goal_events",
            "repo_bound_plan_mode_and_sanitized_auth_lane",
            "paired_provider_internal_goal_verifier_child_lifecycle",
        ]
        expected_separate_repo_gates = [
            "run_route_assignment_and_exact_profile_binding",
            "logical_role_singleton_and_compare_and_swap",
            "department_dispatch_single_writer_and_return_recipient",
            "pre00_to_05_nonmedia_no_fallback_shadow",
            "Director_review_before_any_promotion",
        ]
        if activation_scope.get("actual_binary_proves") != expected_actual_binary_proofs:
            errors.append("Grok role lifecycle receipt actual-binary proof set drifted")
        if activation_scope.get("separate_repo_gates_still_required") != expected_separate_repo_gates:
            errors.append("Grok role lifecycle receipt separate repo-gate set drifted")

    router_path = resolved.get("cdd_session_router_implementation")
    router_text = router_path.read_text(encoding="utf-8") if router_path is not None else ""
    for fragment in (
        'when "route-initialize"',
        'when "route-admit"',
        'when "route-commit"',
        'when "route-authorize"',
        'when "route-rollback"',
        "compare-and-swap failed: state SHA changed",
        "denied #{operation} for inactive or read-only session",
        'expected_goal = case state["provider"]',
        '["grok_goal_completed_admission", "complete", "goal_completed"]',
        '["cursor_external_goal_runtime_receipt", "success", "cli_terminal_success"]',
    ):
        if fragment not in router_text:
            errors.append(f"CDD direct session router is missing {fragment!r}")

    router_schema_path = resolved.get("cdd_session_router_state_schema")
    router_schema = _load_json(router_schema_path, errors) if router_schema_path is not None else {}
    if router_schema.get("properties", {}).get("schema_version", {}).get("const") != "idol-cdd-session-router-state.v1":
        errors.append("CDD direct session router state schema version drifted")
    phase_values = router_schema.get("properties", {}).get("phase", {}).get("enum", [])
    if phase_values != ["successor_preflight", "successor_admitted", "successor_active", "rolled_back"]:
        errors.append("CDD direct session router phase set drifted")

    router_test_path = resolved.get("cdd_session_router_isolated_test")
    router_test_text = router_test_path.read_text(encoding="utf-8") if router_test_path is not None else ""
    for fragment in (
        "test_grok_goal_completion_admits_then_router_cas_and_rollback_gate_the_actual_writer",
        "assert_denied(committed, @source_session, \"prompt\")",
        "assert_authorized(committed, @successor_session, \"canonical_write\")",
        "assert_denied(rolled_back, @successor_session, \"prompt\")",
        "test_codex_uses_active_thread_goal_semantics_without_changing_router_cas",
        "test_cursor_uses_external_goal_runtime_receipt_without_changing_router_cas",
    ):
        if fragment not in router_test_text:
            errors.append(f"CDD direct session router isolated test is missing {fragment!r}")

    successor_contract_path = resolved.get("cdd_successor_contract")
    successor_contract_text = (
        " ".join(successor_contract_path.read_text(encoding="utf-8").split())
        if successor_contract_path is not None
        else ""
    )
    for fragment in (
        "idol-cdd-session-router-state.v1",
        "complete/goal_completed",
        "state SHA and generation",
        "every prompt/resume/dispatch/review/canonical-write operation",
        "HTML, review-board, storyline, Section, or canonical creative bytes",
    ):
        if fragment not in successor_contract_text:
            errors.append(f"Grok CDD direct successor contract is missing {fragment!r}")

    director_successor_ready = _validate_grok_director_successor_live_evidence(
        root, evidence, document, errors
    )
    decisions = evidence.get("profile_decisions")
    decisions = decisions if isinstance(decisions, dict) else {}
    expected_decisions = dict(GROK_PROFILE_ACTIVATION_DECISIONS)
    if director_successor_ready:
        expected_decisions["grok_director_deep"] = GROK_DIRECTOR_READY_DECISION
        expected_decisions["grok_director_frontier"] = GROK_DIRECTOR_READY_DECISION
    if decisions != expected_decisions:
        errors.append("Grok non-media profile activation decisions drifted")
    return decisions


def _validate_cursor_source(
    root: Path,
    alias: str,
    provider: dict[str, Any],
    errors: list[str],
) -> dict[str, Any] | None:
    relative = str(provider.get("source_path", ""))
    path = root / relative
    if not path.is_file():
        errors.append(f"{alias}.cursor provider source is missing: {relative}")
        return None
    actual_sha = _sha256(path)
    if provider.get("source_sha256") != actual_sha:
        errors.append(f"{alias}.cursor provider source hash is stale")
    document = _load_yaml(path, errors)
    if document.get("provider") != "cursor":
        errors.append("Cursor provider source must declare provider: cursor")
    if document.get("status") != "active_with_assignment_holds":
        errors.append("Cursor provider source must declare mixed active/held assignment status")
    evidence = document.get("capability_evidence")
    evidence = evidence if isinstance(evidence, dict) else {}
    if evidence.get("goal_identity_independently_observable") != "external_goal_record_sha_and_session_id":
        errors.append("Cursor external Goal record evidence is missing")
    expected_lifecycle = [
        "create_by_first_run",
        "send",
        "wait",
        "resume",
        "cancel",
        "logical_retire",
        "independent_successor_create",
    ]
    if evidence.get("lifecycle_operations_proven") != expected_lifecycle:
        errors.append("Cursor lifecycle operation evidence drifted")
    profiles = document.get("profiles")
    profiles = profiles if isinstance(profiles, dict) else {}
    profile_id = str(provider.get("provider_profile_id", ""))
    selected = profiles.get(profile_id)
    if profile_id == "cursor_advisory_index":
        selected = None
    elif not isinstance(selected, dict):
        errors.append(f"{alias}.cursor profile {profile_id!r} is missing")
    elif provider.get("harness_status") != selected.get("harness_status"):
        errors.append(f"{alias}.cursor graph-engineering status does not match provider profile")
    elif provider.get("full_owner_ready") is not selected.get("full_owner_ready"):
        errors.append(f"{alias}.cursor full-owner readiness does not match provider profile")
    expected_cursor_tiers = {
        "director_deep": (
            "cursor_sol_xhigh",
            "gpt-5.6-sol-xhigh",
            "xhigh",
        ),
        "frontier_director": (
            "cursor_grok_46_xhigh",
            "cursor-grok-4.6-xhigh",
            "xhigh",
        ),
        "worker_high": (
            "cursor_luna_max",
            "gpt-5.6-luna-max",
            "max",
        ),
        "research_medium": (
            "cursor_luna_xhigh",
            "gpt-5.6-luna-xhigh",
            "xhigh",
        ),
    }
    expected = expected_cursor_tiers.get(alias)
    if expected and isinstance(selected, dict):
        expected_profile_id, expected_model, expected_effort = expected
        if profile_id != expected_profile_id:
            errors.append(f"{alias}.cursor profile must be {expected_profile_id}")
        if selected.get("exact_model") != expected_model:
            errors.append(f"{alias}.cursor exact model must be {expected_model}")
        if selected.get("reasoning_effort") != expected_effort:
            errors.append(f"{alias}.cursor effort must be {expected_effort}")
    schema = _load_json(root / Path("schemas/cursor-agent-provider-profiles.schema.json"), errors)
    if document and schema:
        for failure in Draft202012Validator(schema).iter_errors(document):
            pointer = "/" + "/".join(str(part) for part in failure.absolute_path)
            errors.append(f"cursor provider source schema {pointer}: {failure.message}")
    luna_xhigh = profiles.get("cursor_luna_xhigh")
    luna_xhigh = luna_xhigh if isinstance(luna_xhigh, dict) else {}
    if luna_xhigh.get("harness_status") != "hold" or luna_xhigh.get("luna_max_alias") != "forbidden":
        errors.append("optional Luna Extra High must remain runtime-receipt HOLD and must not alias Luna Max")
    if luna_xhigh.get("exact_model") != "gpt-5.6-luna-xhigh" or luna_xhigh.get("expected_init_display") != "GPT-5.6 Luna 1M Extra High":
        errors.append("optional Luna Extra High must bind the live catalog model and display")
    if luna_xhigh.get("activation_evidence_required") != "external_goal_exact_cli_init_display_terminal_result":
        errors.append("optional Luna Extra High must require external Goal and exact runtime evidence")
    luna_max = profiles.get("cursor_luna_max")
    luna_max = luna_max if isinstance(luna_max, dict) else {}
    if luna_max.get("luna_xhigh_alias") != "forbidden":
        errors.append("current Luna Max must not alias Luna Extra High")
    cursor_grok = profiles.get("cursor_grok_46_xhigh")
    cursor_grok = cursor_grok if isinstance(cursor_grok, dict) else {}
    if cursor_grok.get("fast_mode") is not False or cursor_grok.get("logical_tier") != "frontier_director":
        errors.append("Cursor Grok Extra High must remain a non-fast frontier alternative")
    return {
        "source_path": relative,
        "source_sha256": actual_sha,
        "harness_status": provider.get("harness_status"),
        "full_owner_ready": provider.get("full_owner_ready"),
    }


def _validate_grok_source(
    root: Path,
    alias: str,
    provider: dict[str, Any],
    errors: list[str],
) -> tuple[str, str] | None:
    relative = str(provider.get("source_path", ""))
    path = root / relative
    if not path.is_file():
        errors.append(f"{alias}.grok provider source is missing: {relative}")
        return None
    actual_sha = _sha256(path)
    if provider.get("source_sha256") != actual_sha:
        errors.append(f"{alias}.grok provider source hash is stale")
    document = _load_yaml(path, errors)
    if document.get("provider") != "grok":
        errors.append("Grok provider source must declare provider: grok")
    policy = document.get("profile_source_policy")
    policy = policy if isinstance(policy, dict) else {}
    expected_policy = {
        "exact_model_and_effort_owner": "this_file",
        "resolved_snapshot_required": True,
        "live_inventory_refresh_required": True,
        "requested_observed_match_required": True,
        "silent_downgrade_or_fallback": "forbidden",
        "provider_native_subagents": "default_enabled",
        "project_numeric_helper_override": "none",
        "accepted_auth_lanes": ["subscription_oauth", "founder_approved_existing_xai_api_key"],
        "auth_material_storage": "runtime_environment_only_never_registry_log_receipt_or_ui",
        "child_shell_secret_inheritance": "forbidden",
    }
    if policy != expected_policy:
        errors.append("Grok provider source policy must preserve exact ownership, native helpers, and no fallback")
    profiles = document.get("profiles")
    profiles = profiles if isinstance(profiles, dict) else {}
    evidence = document.get("nonmedia_activation_evidence")
    evidence = evidence if isinstance(evidence, dict) else {}
    activation_decisions = evidence.get("profile_decisions")
    activation_decisions = activation_decisions if isinstance(activation_decisions, dict) else {}
    if alias == "director_deep":
        activation_decisions = _validate_grok_activation_evidence(root, document, errors)
    profile_id = str(provider.get("provider_profile_id", ""))
    profile = profiles.get(profile_id)
    if not isinstance(profile, dict):
        errors.append(f"{alias}.grok profile {profile_id!r} is missing from {relative}")
        return None
    for field in ("exact_model", "reasoning_effort"):
        if not isinstance(profile.get(field), str) or not str(profile.get(field)).strip():
            errors.append(f"{alias}.grok profile must own non-empty {field}")
    expected_tier = GROK_LOGICAL_PROFILE_TIERS.get(alias)
    if expected_tier is not None:
        expected_model, expected_effort = expected_tier
        if profile.get("exact_model") != expected_model:
            errors.append(f"{alias}.grok exact_model must be {expected_model!r}")
        if profile.get("reasoning_effort") != expected_effort:
            errors.append(f"{alias}.grok reasoning_effort must be {expected_effort!r}")
    expected_roles = {
        "frontier_director": {
            "overall_director",
            "creative_development_director",
            "edit_director",
        },
        "director_deep": {
            "overall_director",
            "creative_development_director",
            "edit_director",
        },
        "frontier_director": {
            "overall_director",
            "creative_development_director",
            "edit_director",
        },
        "worker_high": {"worker", "department_worker", "mechanical_coordinator", "section_image_motion_worker"},
        "research_medium": {"research_worker", "department_worker"},
    }.get(alias)
    if expected_roles is not None and set(profile.get("eligible_logical_roles", [])) != expected_roles:
        errors.append(f"{alias}.grok eligible logical roles drifted")
    expected_readiness_requirements = {
        "director_deep": (
            "owner_readiness_requires",
            [
                "create_send_wait_resume_continue",
                "fork_successor_with_retained_session",
                "harness_logical_retire_reactivate",
                "provider_native_goal_admission_event_and_attestation",
                "registered_session_router_active_role_singleton_cas",
                "pre00_to_05_no_fallback_shadow",
                "actual_binary_two_session_successor_receipt",
            ],
        ),
        "frontier_director": (
            "owner_readiness_requires",
            [
                "create_send_wait_resume_continue",
                "fork_successor_with_retained_session",
                "harness_logical_retire_reactivate",
                "provider_native_goal_admission_event_and_attestation",
                "registered_session_router_active_role_singleton_cas",
                "pre00_to_05_no_fallback_shadow",
                "actual_binary_two_session_successor_receipt",
            ],
        ),
        "worker_high": (
            "worker_readiness_requires",
            [
                "exact_department_dispatch",
                "native_goal_event_and_attestation",
                "parent_scoped_authority",
                "exact_output_and_return_recipient",
                "no_provider_fallback",
            ],
        ),
        "research_medium": (
            "worker_readiness_requires",
            [
                "exact_department_dispatch",
                "native_goal_event_and_attestation",
                "parent_scoped_authority",
                "exact_output_and_return_recipient",
                "no_provider_fallback",
            ],
        ),
    }.get(alias)
    if expected_readiness_requirements is not None:
        field, expected_requirements = expected_readiness_requirements
        if profile.get(field) != expected_requirements:
            errors.append(f"{alias}.grok {field} drifted")
    director_live_evidence = evidence.get("director_successor_live_evidence")
    director_live_evidence = director_live_evidence if isinstance(director_live_evidence, dict) else {}
    director_claims_ready = director_live_evidence.get("status") == "present"
    expected_activation = {
        "director_deep": {
            "capability_status": "founder_verified",
            "harness_status": "active" if director_claims_ready else "migration_pending",
            "full_owner_ready": director_claims_ready,
            "decision": "ready" if director_claims_ready else "hold",
        },
        "frontier_director": {
            "capability_status": "founder_verified",
            "harness_status": "active" if director_claims_ready else "migration_pending",
            "full_owner_ready": director_claims_ready,
            "decision": "ready" if director_claims_ready else "hold",
        },
        "worker_high": {
            "capability_status": "founder_verified",
            "harness_status": "active",
            "full_owner_ready": True,
            "decision": "ready",
        },
        "research_medium": {
            "capability_status": "hold",
            "harness_status": "hold",
            "full_owner_ready": False,
            "decision": "hold",
        },
    }.get(
        alias,
        {
            "capability_status": "hold",
            "harness_status": "hold",
            "full_owner_ready": False,
            "decision": "hold",
        },
    )
    for field, expected in {
        "capability_status": expected_activation["capability_status"],
        "harness_status": expected_activation["harness_status"],
        "full_owner_ready": expected_activation["full_owner_ready"],
        "unavailable_or_mismatch_action": "hold_and_report",
    }.items():
        if profile.get(field) != expected:
            errors.append(f"{alias}.grok profile {field} must be {expected!r}")
        if provider.get(field) != expected and field in provider:
            errors.append(f"{alias}.grok index {field} must match its provider source")
    decision = activation_decisions.get(profile_id)
    if not isinstance(decision, dict) or decision.get("status") != expected_activation["decision"]:
        errors.append(f"{alias}.grok activation decision must be {expected_activation['decision']!r}")
    model = profile.get("exact_model")
    effort = profile.get("reasoning_effort")
    return (model, effort) if isinstance(model, str) and isinstance(effort, str) else None


def _validate_openai_image_source(
    root: Path,
    lane: dict[str, Any],
    errors: list[str],
) -> dict[str, str] | None:
    relative = str(lane.get("provider_profile_source", ""))
    path = root / relative
    if not path.is_file():
        errors.append(f"OpenAI image provider source is missing: {relative}")
        return None
    actual_sha = _sha256(path)
    if lane.get("provider_profile_source_sha256") != actual_sha:
        errors.append("OpenAI image provider source hash is stale")
    document = _load_yaml(path, errors)
    if document.get("schema_version") != "idol-openai-image-provider-profiles.v1":
        errors.append("OpenAI image provider source schema_version drifted")
    if document.get("provider") != "openai":
        errors.append("OpenAI image provider source must declare provider: openai")
    policy = document.get("profile_source_policy")
    expected_policy = {
        "exact_model_owner": "this_file",
        "resolved_snapshot_required": True,
        "requested_observed_match_required": True,
        "silent_model_or_auth_fallback": "forbidden",
    }
    if policy != expected_policy:
        errors.append("OpenAI image provider source policy drifted")
    profiles = document.get("profiles")
    profiles = profiles if isinstance(profiles, dict) else {}
    profile_id = lane.get("provider_profile_id")
    profile = profiles.get(profile_id) if isinstance(profile_id, str) else None
    if not isinstance(profile, dict):
        errors.append(f"OpenAI image profile {profile_id!r} is missing from {relative}")
        return None
    if not isinstance(profile.get("exact_model"), str) or not profile["exact_model"].strip():
        errors.append("OpenAI image provider source must own a non-empty exact_model")
    for field in ("image_adapter_id", "auth_lane"):
        if profile.get(field) != lane.get(field):
            errors.append(f"OpenAI image {field} must match the literal-free index")
    for field, expected in {
        "capability_status": "active",
        "harness_status": "active",
        "default_enabled": False,
        "unavailable_or_mismatch_action": "hold_and_report",
    }.items():
        if profile.get(field) != expected:
            errors.append(f"OpenAI image profile {field} must be {expected!r}")
    model = profile.get("exact_model")
    adapter = profile.get("image_adapter_id")
    if isinstance(model, str) and isinstance(adapter, str):
        return {"model": model, "image_adapter_id": adapter}
    return None


def _validate_codex_native_media_source(
    root: Path,
    lane: dict[str, Any],
    errors: list[str],
) -> dict[str, str] | None:
    relative = str(lane.get("provider_profile_source", ""))
    path = root / relative
    if not path.is_file():
        errors.append(f"Codex native media provider source is missing: {relative}")
        return None
    actual_sha = _sha256(path)
    if lane.get("provider_profile_source_sha256") != actual_sha:
        errors.append("Codex native media provider source hash is stale")
    document = _load_yaml(path, errors)
    expected_header = {
        "schema_version": "idol-codex-native-media-provider-profiles.v1",
        "status": "active",
        "provider": "codex",
        "runtime_surface": "codex_app_session",
    }
    for field, expected in expected_header.items():
        if document.get(field) != expected:
            errors.append(f"Codex native media provider source {field} must be {expected!r}")
    expected_policy = {
        "exact_native_tool_owner": "this_file",
        "backend_model_identity_claim": "forbidden",
        "current_assignment_provider_match_required": True,
        "runtime_tool_inventory_match_required": True,
        "provider_specific_capability_only": True,
        "cross_provider_tool_aliasing": "forbidden",
        "cross_provider_auth_inheritance": "forbidden",
        "automatic_fallback": "none",
    }
    if document.get("profile_source_policy") != expected_policy:
        errors.append("Codex native media provider source policy drifted")
    profiles = document.get("profiles")
    profiles = profiles if isinstance(profiles, dict) else {}
    profile_id = lane.get("provider_profile_id")
    profile = profiles.get(profile_id) if isinstance(profile_id, str) else None
    if not isinstance(profile, dict):
        errors.append(f"Codex native media profile {profile_id!r} is missing from {relative}")
        return None
    expected_profile = {
        "execution_adapter_id": lane.get("image_adapter_id"),
        "provider_model_or_tool": "codex_imagegen",
        "selected_native_tool": "imagegen",
        "auth_lane": lane.get("auth_lane"),
        "capability_status": "registered_exact",
        "harness_status": "active",
        "current_session_binding_required": True,
        "exact_tool_inventory_required": True,
        "prompt_rewrite_policy": "forbidden",
        "output_contract": lane.get("image_output_contract"),
        "output_count": 1,
        "automatic_fallback": "none",
        "unavailable_or_mismatch_action": "hold_and_report",
    }
    if profile != expected_profile:
        errors.append("Codex native ImageGen profile must exactly match its provider-specific lane")
    return {
        "provider_profile_id": str(profile_id),
        "image_adapter_id": str(profile.get("execution_adapter_id", "")),
        "selected_native_tool": str(profile.get("selected_native_tool", "")),
    }


def _validate_grok_media_source(
    root: Path,
    lane: dict[str, Any],
    errors: list[str],
) -> None:
    relative = str(lane.get("provider_profile_source", ""))
    path = root / relative
    if not path.is_file():
        errors.append(f"Grok media provider source is missing: {relative}")
        return
    if lane.get("provider_profile_source_sha256") != _sha256(path):
        errors.append("Grok subscription lane provider profile source hash is stale")
    document = _load_yaml(path, errors)
    activation = document.get("media_activation_evidence")
    activation = activation if isinstance(activation, dict) else {}
    video_activation = activation.get("video_subscription_cli")
    video_activation = video_activation if isinstance(video_activation, dict) else {}
    expected_activation = {
        "status": "pass_for_registered_lane_not_generation",
        "zero_model_turns": True,
        "generation_calls": 0,
        "registered_adapter_command": "idol-grok-live-video-prompt",
        "direct_imagine_video_command_present": False,
        "current_assignment_inventory_or_adapter_match_required": True,
        "cue_specific_founder_external_generation_authority_required": True,
        "automatic_fallback": "none",
    }
    for field, expected in expected_activation.items():
        if video_activation.get(field) != expected:
            errors.append(f"Grok video activation evidence {field} must be {expected!r}")
    receipt_relative = video_activation.get("path")
    receipt_path = root / str(receipt_relative or "")
    if not receipt_path.is_file():
        errors.append("Grok video activation evidence receipt is missing")
    elif video_activation.get("sha256") != _sha256(receipt_path):
        errors.append("Grok video activation evidence receipt hash is stale")
    else:
        receipt = _load_json(receipt_path, errors)
        if receipt.get("status") != "pass_for_registered_lane_not_generation":
            errors.append("Grok video activation receipt must not claim generation PASS")
        probe = receipt.get("acp_probe") if isinstance(receipt.get("acp_probe"), dict) else {}
        if probe.get("initialize_pass") is not True or probe.get("session_new_pass") is not True:
            errors.append("Grok video activation receipt must bind one initialized ACP session")
        if probe.get("zero_model_turns") is not True or probe.get("generation_calls") != 0:
            errors.append("Grok video activation receipt must remain zero-turn and non-generative")
        if probe.get("registered_video_adapter_command_present") is not True:
            errors.append("Grok video activation receipt lacks the registered video adapter command")
        disposition = receipt.get("activation_disposition")
        disposition = disposition if isinstance(disposition, dict) else {}
        if disposition.get("harness_registration") != "active":
            errors.append("Grok video activation receipt must register the graph-engineering lane as active")
        if disposition.get("founder_cue_specific_external_generation_authority_required") is not True:
            errors.append("Grok video activation receipt must retain cue-specific Founder authority")
        if disposition.get("automatic_fallback") != "none":
            errors.append("Grok video activation receipt must forbid automatic fallback")
    media = document.get("media_capabilities")
    media = media if isinstance(media, dict) else {}
    image = media.get("image_subscription_cli")
    image = image if isinstance(image, dict) else {}
    expected_image = {
        "auth_lane": lane.get("auth_lane"),
        "capability_status": lane.get("capability_status"),
        "harness_status": lane.get("image_harness_status"),
        "adapter_id": lane.get("image_adapter_id"),
        "tools": lane.get("image_tools"),
        "tool_selection": lane.get("image_tool_selection"),
        "prompt_rewrite_policy": lane.get("image_prompt_rewrite_policy"),
        "output_contract": lane.get("image_output_contract"),
        "local_output_required": True,
        "automatic_fallback": lane.get("automatic_fallback"),
    }
    if image != expected_image:
        errors.append("Grok image media capability must exactly match the literal-free index")
    video = media.get("video_subscription_cli")
    video = video if isinstance(video, dict) else {}
    expected_video = {
        "auth_lane": lane.get("auth_lane"),
        "capability_status": lane.get("capability_status"),
        "harness_status": lane.get("video_harness_status"),
        "adapter_id": lane.get("video_adapter_id"),
        "tools": lane.get("video_tools"),
        "direct_image_to_video": lane.get("direct_image_to_video"),
        "prompt_rewrite_policy": lane.get("video_prompt_rewrite_policy"),
        "automatic_fallback": lane.get("automatic_fallback"),
        "output_contract": lane.get("video_output_contract"),
        "local_output_required": lane.get("video_local_output_required"),
        "current_assignment_inventory_or_adapter_match_required": lane.get(
            "video_runtime_inventory_or_adapter_match_required"
        ),
        "cue_specific_founder_external_generation_authority_required": lane.get(
            "video_founder_external_generation_authority_required"
        ),
        "allowed_durations_seconds": lane.get("video_durations_seconds"),
        "allowed_resolutions": lane.get("resolutions"),
        "resolution_1080p": lane.get("resolution_1080p"),
    }
    if video != expected_video:
        errors.append("Grok video media capability must exactly match the literal-free index")


def _validate_provider_specific_selection_policy(index: dict[str, Any], errors: list[str]) -> None:
    policy = index.get("selection_policy")
    policy = policy if isinstance(policy, dict) else {}
    expected = {
        "provider_omitted_image_request": "current_session_native",
        "current_session_native_resolution": "exact_current_assignment_provider_registered_media_lane",
        "explicit_api_selection_required": True,
        "provider_specific_capability_binding": "exact_provider_source_and_runtime_inventory",
        "shared_contract_scope": "logical_role_goal_dispatch_successor_review_only",
        "cross_provider_tool_or_auth_aliasing": "forbidden",
        "unsupported_provider_capability_action": "hold_without_cross_provider_fallback",
        "api_default_enabled": False,
    }
    for field, value in expected.items():
        if policy.get(field) != value:
            errors.append(f"provider selection policy {field} must be {value!r}")


def _validate_xai_media_source(
    root: Path,
    lane: dict[str, Any],
    errors: list[str],
) -> dict[str, Any]:
    """Resolve only an exact registered xAI source; every other branch stays held."""
    if lane.get("selection_only") is True:
        errors.append(
            "xAI API media legacy selection-only evidence cannot be the current central lane"
        )
        return {
            "registration_status": "legacy_selection_only",
            "ready": False,
            "unavailable_action": "hold_without_fallback",
        }

    registration_status = lane.get("registration_status")
    if registration_status == "registration_required":
        expected = {
            "provider": "xai",
            "auth_lane": "founder_approved_api",
            "capability_status": "registration_required",
            "harness_status": "hold",
            "registration_status": "registration_required",
            "default_enabled": False,
            "selection_only": False,
            "automatic_fallback": "none",
        }
        if lane != expected:
            errors.append(
                "xAI API media registration_required lane is not the exact fail-closed shape"
            )
        return {
            "registration_status": "registration_required",
            "capability_status": lane.get("capability_status"),
            "harness_status": lane.get("harness_status"),
            "ready": False,
            "unavailable_action": "hold_before_credentials_or_network_without_fallback",
        }

    if registration_status != "registered_exact":
        errors.append(
            "xAI API media must be registration_required HOLD or registered_exact active"
        )
        return {
            "registration_status": registration_status,
            "ready": False,
            "unavailable_action": "hold_without_fallback",
        }

    expected_lane = {
        "provider": "xai",
        "auth_lane": "founder_approved_api",
        "capability_status": "active",
        "harness_status": "active",
        "registration_status": "registered_exact",
        "image_adapter_id": "xai_api_media",
        "image_output_contract": "exact_expected_output_path_sha256_pixel_review",
        "default_enabled": False,
        "selection_only": False,
        "automatic_fallback": "none",
    }
    for field, expected in expected_lane.items():
        if lane.get(field) != expected:
            errors.append(
                f"registered xAI API media {field} must be {expected!r}"
            )

    relative = str(lane.get("provider_profile_source", ""))
    path = _contained_file(
        root,
        Path(relative),
        errors,
        "registered xAI API media provider source",
    )
    if path is None:
        return {
            "registration_status": "registered_exact",
            "ready": False,
            "unavailable_action": "hold_without_fallback",
        }
    actual_sha = _sha256(path)
    if lane.get("provider_profile_source_sha256") != actual_sha:
        errors.append("registered xAI API media provider source hash is stale")

    document = _load_json(path, errors) if path.suffix.lower() == ".json" else _load_yaml(path, errors)
    source_schema = _load_json(root / XAI_PROVIDER_SCHEMA_PATH, errors)
    if document and source_schema:
        for failure in Draft202012Validator(source_schema).iter_errors(document):
            pointer = "/" + "/".join(str(part) for part in failure.absolute_path)
            errors.append(f"registered xAI API provider source schema {pointer}: {failure.message}")

    expected_header = {
        "schema_version": "idol-xai-api-media-provider-profiles.v1",
        "status": "active",
        "provider": "xai_api",
        "runtime_surface": "xai_media_api",
    }
    for field, expected in expected_header.items():
        if document.get(field) != expected:
            errors.append(
                f"registered xAI API provider source {field} must be {expected!r}"
            )
    expected_policy = {
        "exact_model_owner": "this_file",
        "exact_endpoint_owner": "this_file",
        "resolved_snapshot_required": True,
        "requested_observed_match_required": True,
        "silent_model_or_auth_fallback": "forbidden",
    }
    if document.get("profile_source_policy") != expected_policy:
        errors.append("registered xAI API provider source policy drifted")

    profiles = document.get("profiles")
    profiles = profiles if isinstance(profiles, dict) else {}
    profile_id = lane.get("provider_profile_id")
    profile = profiles.get(profile_id) if isinstance(profile_id, str) else None
    if not isinstance(profile, dict):
        errors.append(
            f"registered xAI API profile {profile_id!r} is missing from {relative}"
        )
        return {
            "registration_status": "registered_exact",
            "provider_profile_id": profile_id,
            "provider_profile_source": relative,
            "provider_profile_source_sha256": actual_sha,
            "ready": False,
            "unavailable_action": "hold_without_fallback",
        }

    expected_profile = {
        "image_adapter_id": lane.get("image_adapter_id"),
        "auth_lane": lane.get("auth_lane"),
        "capability_status": "active",
        "harness_status": "active",
        "default_enabled": False,
        "automatic_fallback": "none",
        "unavailable_or_mismatch_action": "hold_and_report",
    }
    for field, expected in expected_profile.items():
        if profile.get(field) != expected:
            errors.append(
                f"registered xAI API profile {field} must be {expected!r}"
            )
    model = profile.get("exact_model")
    if not isinstance(model, str) or not model.strip():
        errors.append("registered xAI API profile exact_model is missing")
    return {
        "registration_status": "registered_exact",
        "capability_status": lane.get("capability_status"),
        "harness_status": lane.get("harness_status"),
        "provider_profile_id": profile_id,
        "provider_profile_source": relative,
        "provider_profile_source_sha256": actual_sha,
        "model": model,
        "image_adapter_id": profile.get("image_adapter_id"),
        "ready": (
            lane.get("provider_profile_source_sha256") == actual_sha
            and isinstance(model, str)
            and bool(model.strip())
        ),
        "unavailable_action": "hold_without_fallback",
    }


def _validate_role_contracts(index: dict[str, Any], errors: list[str]) -> None:
    profiles = index.get("logical_profiles")
    profiles = profiles if isinstance(profiles, dict) else {}
    expected_roles = {
        "director_deep": {
            "overall_director",
            "creative_development_director",
            "edit_director",
        },
        "worker_high": {"worker", "department_worker", "mechanical_coordinator", "section_image_motion_worker"},
        "research_medium": {"research_worker", "department_worker"},
    }
    expected_cursor_profiles = {
        "frontier_director": "cursor_grok_46_xhigh",
        "director_deep": "cursor_sol_xhigh",
        "worker_high": "cursor_luna_max",
        "research_medium": "cursor_luna_xhigh",
    }
    for alias, roles in expected_roles.items():
        row = profiles.get(alias)
        row = row if isinstance(row, dict) else {}
        if set(row.get("eligible_logical_roles", [])) != roles:
            errors.append(f"{alias} eligible logical roles drifted")
        providers = row.get("providers")
        providers = providers if isinstance(providers, dict) else {}
        if "codex" in providers:
            errors.append(f"{alias}.codex text-model provider must be legacy-pinned, not active")
        cursor = providers.get("cursor")
        cursor = cursor if isinstance(cursor, dict) else {}
        if cursor.get("provider_profile_id") != expected_cursor_profiles[alias]:
            errors.append(f"{alias}.cursor provider profile drifted")
        expected_cursor_pair = {
            "frontier_director": ("founder_verified", "active", False),
            "director_deep": ("founder_verified", "active", True),
            "worker_high": ("founder_verified", "active_text_only", True),
            "research_medium": ("hold", "hold", False),
        }[alias]
        if (
            cursor.get("capability_status"),
            cursor.get("harness_status"),
            cursor.get("full_owner_ready"),
        ) != expected_cursor_pair:
            errors.append(f"{alias}.cursor harness/full-owner readiness pair is invalid")
        grok = providers.get("grok")
        grok = grok if isinstance(grok, dict) else {}
        expected_grok_capability = "hold" if alias == "research_medium" else "founder_verified"
        if grok.get("capability_status") != expected_grok_capability:
            errors.append(
                f"{alias}.grok capability must remain {expected_grok_capability}"
            )
        activation_pair = (grok.get("harness_status"), grok.get("full_owner_ready"))
        allowed_activation_pairs = {
            "frontier_director": {("migration_pending", False), ("active", True)},
            "director_deep": {("migration_pending", False), ("active", True)},
            "worker_high": {("active", True)},
            "research_medium": {("hold", False)},
        }[alias]
        if activation_pair not in allowed_activation_pairs:
            errors.append(f"{alias}.grok harness/full-owner readiness pair is invalid: {activation_pair!r}")


def _validate_profile_instructions(root: Path, index: dict[str, Any], errors: list[str]) -> None:
    profiles = index.get("logical_profiles", {})
    director = profiles.get("director_deep", {}).get("providers", {}).get("codex", {})
    workers = profiles.get("worker_high", {}).get("providers", {}).get("codex", {})
    if not director and not workers:
        return
    rows = {}
    rows.update(director.get("role_profiles", {}))
    rows.update(workers.get("role_profiles", {}))
    instructions: dict[str, str] = {}
    for role, row in rows.items():
        if not isinstance(row, dict):
            continue
        document = _load_toml(root / str(row.get("source_path", "")), errors)
        instructions[role] = " ".join(str(document.get("developer_instructions", "")).lower().split())
    required_phrases = {
        "overall_director": (
            "provider-native/default internal helpers",
            "every image, pixel-review, motion storyboard, prompt, and playback return goes first to the continuing cdd",
        ),
        "creative_development_director": (
            "actual core/branch pixels",
            "stay active through the passed 03v handoff",
        ),
        "edit_director": (
            "canonical edit map",
            "return the merged, reviewed milestone only to the overall director",
        ),
        "general_worker": (
            "provider-native internal helpers",
            "physical_session_recommended",
        ),
        "section_image_motion_worker": (
            "creative development director",
            "motion storyboards, and playback",
        ),
    }
    for role, phrases in required_phrases.items():
        body = instructions.get(role, "")
        for phrase in phrases:
            if phrase not in body:
                errors.append(f"{role} Codex profile is missing {phrase!r}")


def _validate_config(root: Path, errors: list[str]) -> None:
    document = _load_toml(root / ".codex/config.toml", errors)
    agents = document.get("agents")
    agents = agents if isinstance(agents, dict) else {}
    forbidden = sorted(NUMERIC_AGENT_OVERRIDE_KEYS.intersection(agents))
    if forbidden:
        errors.append(f".codex/config.toml contains forbidden numeric agent overrides {forbidden}")
    for key in ("model", "model_reasoning_effort", "model_verbosity"):
        if key in document:
            errors.append(f".codex/config.toml.{key} must remain unpinned")


def _run_route_alias(role: str, provider: str | None = None) -> str:
    return "director_deep" if role in {
        "overall_director",
        "creative_development_director",
        "edit_director",
    } else "worker_high"


def _codex_role_profile_key(role: str) -> str:
    if role in {"overall_director", "creative_development_director", "edit_director"}:
        return role
    if role == "section_owner":
        return "section_image_motion_worker"
    return "general_worker"


def _contained_file(root: Path, supplied: Path, errors: list[str], label: str) -> Path | None:
    candidate = supplied if supplied.is_absolute() else root / supplied
    try:
        resolved = candidate.resolve(strict=True)
        resolved.relative_to(root.resolve())
    except (OSError, ValueError):
        errors.append(f"{label} must resolve to a readable repository-contained file")
        return None
    if not resolved.is_file():
        errors.append(f"{label} must resolve to a file")
        return None
    return resolved


def _validate_run_route_manifest(
    root: Path,
    supplied_path: Path,
    index: dict[str, Any],
    errors: list[str],
) -> dict[str, Any]:
    manifest_path = _contained_file(root, supplied_path, errors, "run-route manifest")
    if manifest_path is None:
        return {}
    try:
        relative_manifest = manifest_path.relative_to(root.resolve()).as_posix()
    except ValueError:
        relative_manifest = str(manifest_path)
    manifest = _load_json(manifest_path, errors)
    schema = _load_json(root / RUN_ROUTE_SCHEMA_PATH, errors)
    if manifest and schema:
        for failure in Draft202012Validator(schema).iter_errors(manifest):
            pointer = "/" + "/".join(str(part) for part in failure.absolute_path)
            errors.append(f"run-route manifest schema {pointer}: {failure.message}")

    binding = manifest.get("provider_profile_registry_binding")
    binding = binding if isinstance(binding, dict) else {}
    registry_relative = str(binding.get("registry_path", ""))
    registry_path = root / INDEX_PATH
    registry_sha = _sha256(registry_path) if registry_path.is_file() else ""
    expected_binding = {
        "registry_path": str(INDEX_PATH),
        "registry_sha256": registry_sha,
        "schema_version": "idol-harness-provider-profile-registry.v1",
        "runtime_rehash_required": True,
        "provider_source_rehash_required": True,
        "exact_model_effort_match_required": True,
        "director_full_owner_ready_required": True,
        "mismatch_action": "hold_and_report",
    }
    if binding != expected_binding:
        errors.append("run-route manifest provider profile registry binding is stale or not fail-closed")
    if registry_relative != str(INDEX_PATH):
        errors.append("run-route manifest provider registry path is not canonical")

    compatibility = manifest.get("profile_compatibility")
    compatibility = compatibility if isinstance(compatibility, dict) else {}
    skill_registry_path = root / "automation/harness-skill-load-profiles.yaml"
    expected_skill_registry_sha = _sha256(skill_registry_path) if skill_registry_path.is_file() else ""
    if compatibility.get("registry_path") != "automation/harness-skill-load-profiles.yaml":
        errors.append("run-route manifest skill-load profile registry path is not canonical")
    if compatibility.get("registry_sha256") != expected_skill_registry_sha:
        errors.append("run-route manifest skill-load profile registry hash is stale")
    role_profile_allowlist = compatibility.get("role_profile_allowlist")
    role_profile_allowlist = role_profile_allowlist if isinstance(role_profile_allowlist, dict) else {}
    if manifest.get("immutable_profile_key_algorithm") != IMMUTABLE_PROFILE_KEY_ALGORITHM:
        errors.append("run-route manifest immutable profile key algorithm is unsupported")
    if manifest.get("runtime_policy_key_algorithm") != RUNTIME_POLICY_KEY_ALGORITHM:
        errors.append("run-route manifest Grok runtime-policy key algorithm is unsupported")

    profiles = index.get("logical_profiles")
    profiles = profiles if isinstance(profiles, dict) else {}
    resolved_rows: list[dict[str, Any]] = []
    directors = {"overall_director", "creative_development_director", "edit_director"}
    run_root = str(manifest.get("run_root", "")).rstrip("/")
    for position, assignment in enumerate(manifest.get("assignments", [])):
        if not isinstance(assignment, dict):
            continue
        assignment_id = str(assignment.get("assignment_id", f"index-{position}"))
        role = str(assignment.get("studio_role", ""))
        provider_name = str(assignment.get("provider", ""))
        auth_lane = str(assignment.get("auth_lane", ""))
        auth_authority_ref = assignment.get("auth_authority_ref")
        profile_id = str(assignment.get("profile_id", ""))
        if profile_id not in [str(value) for value in role_profile_allowlist.get(role, [])]:
            errors.append(f"run-route assignment {assignment_id} profile_id is outside the exact role allowlist")
        alias = _run_route_alias(role, provider_name)
        if provider_name == "cursor" and profile_id in {
            "cursor_opus_thinking_high",
            "cursor_fable_thinking_xhigh",
            "cursor_sol_xhigh",
            "cursor_grok_46_xhigh",
            "cursor_gemini_31_pro_thinking_high",
        } and role == "department_worker":
            alias = "cursor_advisory"
        provider = profiles.get(alias, {}).get("providers", {}).get(provider_name, {})
        if not isinstance(provider, dict):
            errors.append(f"run-route assignment {assignment_id} has no registered {alias}/{provider_name} provider")
            continue

        if provider_name == "codex":
            profile_key = _codex_role_profile_key(role)
            source_profile = provider.get("role_profiles", {}).get(profile_key, {})
            source_profile = source_profile if isinstance(source_profile, dict) else {}
            source_path = str(source_profile.get("source_path", ""))
            source_sha = str(source_profile.get("source_sha256", ""))
            profile_pointer = f"{source_path}#root"
            source_document = _load_toml(root / source_path, errors) if source_path else {}
            exact_model = source_document.get("model")
            exact_effort = source_document.get("model_reasoning_effort")
            exact_adapter = "codex_app_server"
            exact_execution_profile_id = source_profile.get("profile_id")
            capability_status = provider.get("capability_status")
            harness_status = provider.get("harness_status")
            full_owner_ready = provider.get("full_owner_ready")
        elif provider_name == "grok":
            source_path = str(provider.get("source_path", ""))
            source_sha = str(provider.get("source_sha256", ""))
            provider_profile_id = str(provider.get("provider_profile_id", ""))
            profile_pointer = f"{source_path}#/profiles/{provider_profile_id}"
            source_document = _load_yaml(root / source_path, errors) if source_path else {}
            selected = source_document.get("profiles", {}).get(provider_profile_id, {})
            selected = selected if isinstance(selected, dict) else {}
            exact_model = selected.get("exact_model")
            exact_effort = selected.get("reasoning_effort")
            exact_adapter = "grok_acp"
            exact_execution_profile_id = provider_profile_id
            capability_status = provider.get("capability_status")
            harness_status = provider.get("harness_status")
            full_owner_ready = provider.get("full_owner_ready")
            runtime_capabilities = assignment.get("runtime_capabilities")
            runtime_capabilities = runtime_capabilities if isinstance(runtime_capabilities, dict) else {}
            if assignment.get("runtime_policy_key") != _grok_runtime_policy_key(assignment):
                errors.append(f"run-route assignment {assignment_id} Grok runtime policy key is stale or inexact")
            if runtime_capabilities.get("allowed_write_paths") != []:
                errors.append(f"run-route assignment {assignment_id} Grok runtime cannot own direct write paths")
            if runtime_capabilities.get("authority_boundary") != "work_package_only_no_external_mutation_or_promotion_without_separate_gate":
                errors.append(f"run-route assignment {assignment_id} Grok runtime authority boundary drifted")
            if runtime_capabilities.get("execution_mode") == "proposal_only":
                expected_proposal = {
                    "execution_mode": "proposal_only",
                    "filesystem": "read_only",
                    "allowed_write_paths": [],
                    "web_search": False,
                    "provider_native_subagents": False,
                    "memory": False,
                    "imagine": False,
                    "authority_boundary": "work_package_only_no_external_mutation_or_promotion_without_separate_gate",
                }
                if runtime_capabilities != expected_proposal:
                    errors.append(f"run-route assignment {assignment_id} Grok proposal-only capabilities drifted")
        elif provider_name == "cursor":
            source_path = str(provider.get("source_path", ""))
            source_sha = str(provider.get("source_sha256", ""))
            provider_profile_id = str(assignment.get("execution_profile_id") or provider.get("provider_profile_id", ""))
            profile_pointer = f"{source_path}#/profiles/{provider_profile_id}"
            source_document = _load_yaml(root / source_path, errors) if source_path else {}
            selected = source_document.get("profiles", {}).get(provider_profile_id, {})
            selected = selected if isinstance(selected, dict) else {}
            exact_model = selected.get("exact_model")
            exact_effort = selected.get("reasoning_effort")
            exact_adapter = "cursor_cli_local"
            exact_execution_profile_id = provider_profile_id
            capability_status = provider.get("capability_status")
            harness_status = provider.get("harness_status")
            full_owner_ready = provider.get("full_owner_ready")
            selected_available = selected.get("harness_status") in {"active", "active_text_only"}
            if selected.get("default_enabled") is not False:
                errors.append(
                    f"run-route assignment {assignment_id} Cursor profile must keep default_enabled false"
                )
            if selected_available:
                if assignment.get("binding_state") == "held":
                    errors.append(f"run-route assignment {assignment_id} available Cursor profile is unexpectedly held")
                if not full_owner_ready:
                    errors.append(f"run-route assignment {assignment_id} available Cursor profile is not owner-ready")
            else:
                if assignment.get("binding_state") != "held":
                    errors.append(f"run-route assignment {assignment_id} held Cursor profile must stay held")
        else:
            errors.append(f"run-route assignment {assignment_id} has unsupported provider {provider_name!r}")
            continue

        if provider_name == "codex":
            if auth_lane != "installed_codex_auth" or auth_authority_ref is not None:
                errors.append(f"run-route assignment {assignment_id} Codex auth lane is not exact")
        elif provider_name == "cursor":
            if auth_lane != "cursor_cli_file_credential_store":
                errors.append(f"run-route assignment {assignment_id} Cursor auth lane is not exact")
        elif auth_lane == "subscription_oauth":
            if auth_authority_ref is not None:
                errors.append(f"run-route assignment {assignment_id} subscription OAuth must not carry an API-key authority ref")
        elif auth_lane == "founder_approved_existing_xai_api_key":
            if not isinstance(auth_authority_ref, str) or not auth_authority_ref.strip():
                errors.append(f"run-route assignment {assignment_id} XAI API-key lane lacks a run-owned Founder authority ref")
            elif not run_root or not auth_authority_ref.startswith(f"{run_root}/"):
                errors.append(f"run-route assignment {assignment_id} XAI API-key authority ref is outside the exact run root")
        else:
            errors.append(f"run-route assignment {assignment_id} Grok auth lane is unsupported")

        actual_source_sha = _sha256(root / source_path) if source_path and (root / source_path).is_file() else ""
        expected = {
            "adapter_id": exact_adapter,
            "execution_profile_id": exact_execution_profile_id,
            "logical_profile_alias": alias,
            "model": exact_model,
            "effort": exact_effort,
            "provider_source_path": source_path,
            "provider_source_sha256": source_sha,
            "provider_profile_pointer": profile_pointer,
            "provider_capability_status": capability_status,
            "provider_harness_status": harness_status,
            "provider_full_owner_ready": full_owner_ready,
        }
        for field, value in expected.items():
            if assignment.get(field) != value:
                errors.append(f"run-route assignment {assignment_id} {field} differs from the exact provider source")
        if source_sha != actual_source_sha:
            errors.append(f"run-route assignment {assignment_id} provider source hash is stale")
        readiness = assignment.get("provider_source_readiness")
        readiness = readiness if isinstance(readiness, dict) else {}
        expected_readiness_status = "held" if assignment.get("binding_state") == "held" else "ready"
        expected_readiness = {
            "status": expected_readiness_status,
            "provider_source_rehashed": source_sha == actual_source_sha and bool(source_sha),
            "profile_model_effort_exact": assignment.get("model") == exact_model and assignment.get("effort") == exact_effort,
            "adapter_exact": assignment.get("adapter_id") == exact_adapter,
            "auth_lane_exact": (
                (provider_name == "codex" and auth_lane == "installed_codex_auth" and auth_authority_ref is None)
                or (
                    provider_name == "cursor"
                    and auth_lane == "cursor_cli_file_credential_store"
                    and auth_authority_ref is None
                )
                or (provider_name == "grok" and auth_lane == "subscription_oauth" and auth_authority_ref is None)
                or (
                    provider_name == "grok"
                    and auth_lane == "founder_approved_existing_xai_api_key"
                    and isinstance(auth_authority_ref, str)
                    and bool(auth_authority_ref.strip())
                    and bool(run_root)
                    and auth_authority_ref.startswith(f"{run_root}/")
                )
            ),
            "no_fallback": assignment.get("fallback_behavior") == "hold_and_report",
            "evidence_sha256": _provider_source_readiness_evidence(assignment),
        }
        if readiness != expected_readiness:
            errors.append(f"run-route assignment {assignment_id} provider source readiness evidence is stale or inexact")
        if assignment.get("immutable_profile_key") != _immutable_profile_key(assignment):
            errors.append(f"run-route assignment {assignment_id} immutable profile key is stale or inexact")
        if role in directors and (harness_status != "active" or full_owner_ready is not True):
            errors.append(f"run-route assignment {assignment_id} Director provider is not full-owner ready")
        if role not in directors and harness_status not in {"active", "active_text_only", "shadow_passed"} and assignment.get("binding_state") != "held":
            errors.append(f"run-route assignment {assignment_id} provider is migration-pending but not held")
        resolved_rows.append({
            "assignment_id": assignment_id,
            "provider": provider_name,
            "logical_profile_alias": alias,
            "provider_source_path": source_path,
            "provider_source_sha256": actual_source_sha,
            "provider_profile_pointer": profile_pointer,
            "auth_lane": auth_lane,
            "auth_authority_ref": auth_authority_ref,
            "capability_status": capability_status,
            "model": exact_model,
            "effort": exact_effort,
            "harness_status": harness_status,
            "full_owner_ready": full_owner_ready,
        })

    return {
        "path": relative_manifest,
        "sha256": _sha256(manifest_path),
        "manifest_id": manifest.get("manifest_id"),
        "registry_path": str(INDEX_PATH),
        "registry_sha256": registry_sha,
        "assignments": resolved_rows,
    }


def validate(root: Path, run_route_manifest: Path | None = None) -> tuple[list[str], dict[str, Any]]:
    errors: list[str] = []
    index = _load_yaml(root / INDEX_PATH, errors)
    schema = _load_json(root / SCHEMA_PATH, errors)
    if index and schema:
        _validate_schema(index, schema, errors)
        _validate_literal_free_index(index, errors)
        _validate_role_contracts(index, errors)
        _validate_config(root, errors)
        _validate_profile_instructions(root, index, errors)
    resolved: dict[str, Any] = {}
    profiles = index.get("logical_profiles") if isinstance(index, dict) else {}
    profiles = profiles if isinstance(profiles, dict) else {}
    for alias, row in profiles.items():
        if not isinstance(row, dict):
            continue
        providers = row.get("providers")
        providers = providers if isinstance(providers, dict) else {}
        codex = providers.get("codex")
        grok = providers.get("grok")
        if isinstance(codex, dict):
            resolved.setdefault(alias, {})["codex"] = _validate_codex_source_set(
                root, str(alias), codex, errors
            )
        if isinstance(grok, dict):
            resolved.setdefault(alias, {})["grok"] = _validate_grok_source(
                root, str(alias), grok, errors
            )
        cursor = providers.get("cursor")
        if isinstance(cursor, dict):
            resolved.setdefault(alias, {})["cursor"] = _validate_cursor_source(
                root, str(alias), cursor, errors
            )
    grok_models = {
        value["grok"][0]
        for value in resolved.values()
        if isinstance(value, dict)
        and isinstance(value.get("grok"), tuple)
        and isinstance(value["grok"][0], str)
    }
    if len(grok_models) > 1:
        errors.append("director_deep and worker_high Grok profiles must use one selected build")
    _validate_provider_specific_selection_policy(index, errors)
    media = index.get("media_lanes") if isinstance(index, dict) else {}
    media = media if isinstance(media, dict) else {}
    resolved_media: dict[str, Any] = {}
    codex_native = media.get("codex_session_native")
    if isinstance(codex_native, dict):
        errors.append("Codex native ImageGen lane must be legacy-pinned outside the active registry")
    openai_image = media.get("openai_image_api_current")
    if isinstance(openai_image, dict):
        resolved_media["openai_image_api_current"] = _validate_openai_image_source(
            root, openai_image, errors
        )
    subscription = media.get("grok_build_oauth_subscription")
    if isinstance(subscription, dict):
        _validate_grok_media_source(root, subscription, errors)
        resolved_media["grok_build_oauth_subscription"] = {
            "image_adapter_id": subscription.get("image_adapter_id"),
            "image_tools": subscription.get("image_tools"),
            "video_tools": subscription.get("video_tools"),
            "video_durations_seconds": subscription.get("video_durations_seconds"),
            "resolutions": subscription.get("resolutions"),
        }
    xai = media.get("xai_api_media")
    if isinstance(xai, dict):
        resolved_media["xai_api_media"] = _validate_xai_media_source(
            root, xai, errors
        )
    run_route_evidence = (
        _validate_run_route_manifest(root, run_route_manifest, index, errors)
        if run_route_manifest is not None and isinstance(index, dict)
        else None
    )
    grok_nonmedia_profiles = {
        alias: {
            "harness_status": row.get("providers", {}).get("grok", {}).get("harness_status"),
            "full_owner_ready": row.get("providers", {}).get("grok", {}).get("full_owner_ready"),
        }
        for alias, row in profiles.items()
        if isinstance(row, dict) and isinstance((row.get("providers") or {}).get("grok"), dict)
    }
    required_grok_route_aliases = {"frontier_director", "worker_high"}
    grok_full_route_ready = required_grok_route_aliases.issubset(grok_nonmedia_profiles) and all(
        grok_nonmedia_profiles[alias]["harness_status"] == "active"
        and grok_nonmedia_profiles[alias]["full_owner_ready"] is True
        for alias in required_grok_route_aliases
    )
    return errors, {
        "index": str(INDEX_PATH),
        "schema": str(SCHEMA_PATH),
        "logical_profiles": sorted(profiles),
        "resolved_profiles": resolved,
        "resolved_media_lanes": resolved_media,
        "grok_nonmedia_readiness": {
            "profiles": grok_nonmedia_profiles,
            "full_route_ready": grok_full_route_ready,
            "founder_default_switch_review_allowed": grok_full_route_ready,
            "unavailable_action": "hold_without_cross_provider_fallback",
        },
        "run_route_manifest": run_route_evidence,
        "external_or_generative_actions": 0,
    }


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT, help="IDOL repository root")
    parser.add_argument("--run-route-manifest", type=Path, help="also validate one run-owned Workbench route manifest against current provider sources")
    parser.add_argument("--json", action="store_true", help="emit machine-readable output")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    root = args.root.expanduser().resolve()
    errors, evidence = validate(root, args.run_route_manifest)
    result = {
        "status": "pass" if not errors else "fail",
        "root": str(root),
        "evidence": evidence,
        "errors": errors,
    }
    if args.json:
        print(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True))
    elif errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
    else:
        print("OK: provider profiles, literal-free index, source hashes, and role routing are valid")
    return 0 if not errors else 1


if __name__ == "__main__":
    raise SystemExit(main())
