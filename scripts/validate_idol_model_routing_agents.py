#!/usr/bin/env python3
"""Validate active IDOL role routing against provider-profile and v33 truth."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import tomllib
from pathlib import Path
from typing import Any, Iterable

import yaml

from validate_harness_provider_profiles import validate as validate_provider_profiles
from validate_harness_assignment_model_routing import validate as validate_assignment_routing


ROOT = Path(__file__).resolve().parents[1]
TEST_MODE_ENV = "IDOL_ROUTING_TEST_MODE"
PROVIDER_REGISTRY = Path("automation/harness-provider-profile-registry.yaml")
PROVIDER_SCHEMA = Path("schemas/harness-provider-profile-registry.schema.json")
EXECUTION_CONTRACT = Path("automation/harness-execution-contract.yaml")
DIRECTOR_ROLES = {
    "overall_director",
    "creative_development_director",
    "edit_director",
}
REQUIRED_PROVIDER_NEUTRAL_ROLES = DIRECTOR_ROLES | {
    "song_room",
    "department_worker",
    "member_visual_identity_owner",
    "section_owner",
    "edit_shard_worker",
    "mechanical_coordinator",
}
MODEL_LITERAL = re.compile(r"\b(?:gpt|grok)-[0-9]", re.IGNORECASE)


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


def _load_toml(path: Path, errors: list[str]) -> dict[str, Any]:
    try:
        with path.open("rb") as handle:
            value = tomllib.load(handle)
    except (OSError, tomllib.TOMLDecodeError) as exc:
        errors.append(f"cannot parse {path}: {exc}")
        return {}
    return value


def _normalize(value: Any) -> str:
    return " ".join(str(value).lower().split())


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _iter_resolved_profiles(value: Any) -> Iterable[dict[str, Any]]:
    if isinstance(value, list):
        for row in value:
            if isinstance(row, dict):
                yield row
    elif isinstance(value, dict):
        if "logical_profile_alias" in value:
            yield value
        else:
            for row in value.values():
                yield from _iter_resolved_profiles(row)


def _contains_key(value: Any, key: str) -> bool:
    if isinstance(value, dict):
        return key in value or any(_contains_key(item, key) for item in value.values())
    if isinstance(value, list):
        return any(_contains_key(item, key) for item in value)
    return False


def _provider_index(root: Path, errors: list[str]) -> dict[str, Any]:
    return _load_yaml(root / PROVIDER_REGISTRY, errors)


def _validate_agent_directory(root: Path, errors: list[str]) -> dict[str, dict[str, Any]]:
    directory = root / ".codex/agents"
    documents: dict[str, dict[str, Any]] = {}
    if not directory.is_dir():
        errors.append(".codex/agents directory is missing")
        return documents
    for path in sorted(directory.glob("*.toml")):
        document = _load_toml(path, errors)
        name = document.get("name")
        if not isinstance(name, str) or not name:
            errors.append(f"{path.relative_to(root)} must declare a non-empty name")
            continue
        if name in documents:
            errors.append(f"duplicate Codex provider profile name {name!r}")
            continue
        documents[name] = document
        for field in ("model", "model_reasoning_effort", "model_verbosity", "developer_instructions"):
            if not isinstance(document.get(field), str) or not str(document.get(field)).strip():
                errors.append(f"{path.relative_to(root)} must declare non-empty {field}")
    return documents


def _validate_codex_instruction_contract(
    documents: dict[str, dict[str, Any]], errors: list[str]
) -> None:
    required_phrases = {
        "idol_sol_creative_synthesis": (
            "overall remains the only founder-conversation owner",
            "boot pack v3",
            "03v playback workers",
        ),
        "idol_sol_creative_development_director": (
            "overall-led founder conversation",
            "idol-director-boot-pack.v3",
            "after exact 02a authorization, receive every one-section image/03v worker return",
        ),
        "idol_sol_edit_director": (
            "second founder conversation owner",
            "return the merged, reviewed milestone only to the overall director",
        ),
    }
    for profile_id, phrases in required_phrases.items():
        document = documents.get(profile_id)
        if not isinstance(document, dict):
            errors.append(f"required Codex director profile is missing: {profile_id}")
            continue
        instructions = _normalize(document.get("developer_instructions", ""))
        for phrase in phrases:
            if _normalize(phrase) not in instructions:
                errors.append(f"{profile_id} is missing maintainability invariant {phrase!r}")
        if "owns the pre-02a founder conversation" in instructions:
            errors.append(
                f"{profile_id} cannot own a second Founder conversation; Overall is exclusive"
            )


def _validate_execution_contract(root: Path, errors: list[str]) -> dict[str, Any]:
    contract = _load_yaml(root / EXECUTION_CONTRACT, errors)
    if contract.get("schema_version") != "idol-harness-execution-contract.v36":
        errors.append("execution contract must use idol-harness-execution-contract.v36")

    authority = contract.get("authority")
    authority = authority if isinstance(authority, dict) else {}
    missing_roles = sorted(REQUIRED_PROVIDER_NEUTRAL_ROLES.difference(authority))
    if missing_roles:
        errors.append(f"execution authority is missing provider-neutral roles {missing_roles}")

    resolution = contract.get("provider_profile_resolution")
    resolution = resolution if isinstance(resolution, dict) else {}
    for field, expected in {
        "registry_path": str(PROVIDER_REGISTRY),
        "registry_schema": str(PROVIDER_SCHEMA),
    }.items():
        if resolution.get(field) != expected:
            errors.append(f"provider_profile_resolution.{field} must be {expected!r}")
    registry_sha = resolution.get("registry_sha256")
    if not isinstance(registry_sha, str) or len(registry_sha) != 64:
        errors.append("provider_profile_resolution.registry_sha256 must be a SHA-256")
    else:
        try:
            actual_registry_sha = _sha256(root / PROVIDER_REGISTRY)
        except OSError as exc:
            errors.append(f"cannot hash {root / PROVIDER_REGISTRY}: {exc}")
        else:
            if registry_sha != actual_registry_sha:
                errors.append("provider_profile_resolution.registry_sha256 is stale")
    expected_resolution_contract = {
        "candidate_registry_role": "available_profiles_only",
        "active_resolution_owner": "run_owned_resolved_profile_snapshot",
        "run_snapshot_required_fields": [
            "logical_profile_alias",
            "execution_profile_id",
            "provider",
            "resolved_provider_model",
            "reasoning_effort",
            "provider_capability_snapshot_sha256",
            "resolved_profile_snapshot_ref",
            "fallback_policy",
        ],
        "exact_model_literal_owner": "provider_specific_profile_or_immutable_run_snapshot_only",
        "fallback_policy": "forbidden",
    }
    for field, expected in expected_resolution_contract.items():
        if resolution.get(field) != expected:
            errors.append(f"provider_profile_resolution.{field} must be {expected!r}")
    if "resolved_profiles" in resolution:
        errors.append("shared execution contract must not materialize resolved provider profiles")

    image_generation = contract.get("image_generation")
    image_generation = image_generation if isinstance(image_generation, dict) else {}
    media_resolution = image_generation.get("provider_model_resolution")
    media_resolution = media_resolution if isinstance(media_resolution, dict) else {}
    expected_media_resolution = {
        "provider_omitted_image_request": "current_session_native",
        "current_session_native_provider_binding": "exact_current_assignment_provider",
        "cursor_luna_image": {
            "profile_source": "exact_registered_cursor_profile",
            "adapter": "cursor_luna_image",
            "condition": "explicit_founder_selection_and_media_transfer_proof_only",
            "current_status": "available_founder_explicit_substitute",
        },
        "openai_api_gpt_image_2": {
            "model": "gpt-image-2",
            "condition": "exact_registered_openai_api_lane",
        },
        "grok_build_oauth_subscription": {
            "model_or_tool_source": "exact_registered_grok_provider_profile_and_selected_native_tool",
            "condition": "exact_registered_subscription_lane",
        },
        "xai_api_media": {
            "model_source": "exact_hash_bound_registered_provider_profile",
            "missing_registration_action": "hold_before_credentials_or_network",
        },
        "explicit_api_selection_required": True,
        "cross_provider_tool_auth_or_model_aliasing": "forbidden",
        "automatic_fallback": "none",
    }
    if media_resolution != expected_media_resolution:
        errors.append(
            "image_generation.provider_model_resolution must keep provider-omitted work on the exact current-session native tool, require explicit API selection, and forbid cross-provider aliasing/fallback"
        )

    bindings = contract.get("active_role_bindings")
    bindings = bindings if isinstance(bindings, dict) else {}
    binding_metadata = {
        "ownership": "run_owned_resolved_profile_snapshot",
        "provider_registry_role": "candidate_inventory_only",
        "static_binding_materialization": "forbidden_in_shared_contract",
    }
    expected_binding_keys = DIRECTOR_ROLES | set(binding_metadata)
    if set(bindings) != expected_binding_keys:
        errors.append("active_role_bindings must expose run-owned metadata and exactly Overall, CDD, and Edit Director requirements")
    for field, expected in binding_metadata.items():
        if bindings.get(field) != expected:
            errors.append(f"active_role_bindings.{field} must be {expected!r}")
    required_binding_fields = {
        "required_active_binding_count",
        "logical_role",
        "logical_profile_alias",
        "return_recipient_role",
        "founder_conversation_authority",
    }
    for role in sorted(DIRECTOR_ROLES):
        binding = bindings.get(role)
        if not isinstance(binding, dict):
            errors.append(f"active_role_bindings.{role} must be an object")
            continue
        if set(binding) != required_binding_fields:
            errors.append(
                f"active_role_bindings.{role} must expose exactly {sorted(required_binding_fields)}"
            )
        if binding.get("required_active_binding_count") != 1:
            errors.append(f"active_role_bindings.{role} must require exactly one active binding")
        if binding.get("logical_role") != role:
            errors.append(f"active_role_bindings.{role}.logical_role must be {role}")
        if binding.get("logical_profile_alias") != "director_deep":
            errors.append(f"active_role_bindings.{role} must use director_deep")
        for forbidden_field in ("binding_id", "binding_status", "active_binding_count", "execution_profile_id", "provider", "session_id"):
            if forbidden_field in binding:
                errors.append(f"active_role_bindings.{role} must not materialize run field {forbidden_field}")
        expected_recipient = "founder" if role == "overall_director" else "overall_director"
        if binding.get("return_recipient_role") != expected_recipient:
            errors.append(
                f"active_role_bindings.{role}.return_recipient_role must be {expected_recipient}"
            )
        expected_conversation = "exclusive_owner" if role == "overall_director" else "none"
        if binding.get("founder_conversation_authority") != expected_conversation:
            errors.append(
                f"active_role_bindings.{role}.founder_conversation_authority must be "
                f"{expected_conversation}"
            )

    founder_conversation = contract.get("founder_conversation")
    founder_conversation = founder_conversation if isinstance(founder_conversation, dict) else {}
    if founder_conversation.get("owner_role") != "overall_director":
        errors.append("founder_conversation.owner_role must be overall_director")
    if founder_conversation.get("concurrent_second_conversation_owner_allowed") is not False:
        errors.append("a concurrent second Founder conversation owner must be forbidden")

    topology = contract.get("execution_topology")
    topology = topology if isinstance(topology, dict) else {}
    helper = topology.get("provider_native_helper_policy")
    helper = helper if isinstance(helper, dict) else {}
    expected_helper = {
        "availability": "default",
        "project_numeric_gate": "none",
        "depth_gate": "none",
        "logical_role_granted": False,
    }
    if helper != expected_helper:
        errors.append("provider-native helper policy must use native defaults without role or numeric/depth gates")
    transfer = topology.get("physical_transfer_policy")
    transfer = transfer if isinstance(transfer, dict) else {}
    if transfer.get("same_work_package_simultaneous_internal_and_physical_owner") != "forbidden":
        errors.append("internal and physical owners may not overlap for one Work Package")

    return_routing = contract.get("return_routing")
    return_routing = return_routing if isinstance(return_routing, dict) else {}
    expected_returns = {
        "image_and_03v_recipient_role": "creative_development_director",
        "stage_04_shards_recipient_role": "edit_director",
        "reviewed_director_milestones_recipient_role": "overall_director",
        "founder_conversation_owner_role": "overall_director",
    }
    for field, expected in expected_returns.items():
        if return_routing.get(field) != expected:
            errors.append(f"return_routing.{field} must be {expected!r}")

    if not isinstance(contract.get("transport_closure"), dict):
        errors.append("execution contract must expose transport_closure")
    for forbidden in ("max_threads", "max_depth", "max_concurrent_subagents"):
        if _contains_key(contract.get("execution_topology"), forbidden):
            errors.append(f"execution_topology must not contain project helper override {forbidden}")
    return contract


def _validate_grok_routing_text(root: Path, errors: list[str]) -> None:
    paths = (
        root / ".grok/skills/idol-grok-harness-owner/SKILL.md",
        root / ".grok/skills/idol-grok-harness-owner/references/subagent-roster.md",
    )
    bodies: dict[str, str] = {}
    for path in paths:
        try:
            raw = path.read_text(encoding="utf-8")
        except OSError as exc:
            errors.append(f"cannot read {path}: {exc}")
            continue
        bodies[path.name] = _normalize(raw)
        if MODEL_LITERAL.search(raw):
            errors.append(f"{path.relative_to(root)} must not duplicate an exact provider model literal")
        if "max_depth" in raw or "max_threads" in raw:
            errors.append(f"{path.relative_to(root)} must not impose a project numeric/depth helper override")
    owner = bodies.get("SKILL.md", "")
    for phrase in (
        "director_deep",
        "worker_high",
        "full_owner_ready",
        "provider-native/default internal helpers",
        "actual images, motion storyboards, prompts, and playback only to the continuing cdd",
        "logical_retire",
        "reactivate",
        "there is no silent fallback",
    ):
        if phrase not in owner:
            errors.append(f"Grok graph-engineering owner is missing {phrase!r}")
    roster = bodies.get("subagent-roster.md", "")
    for phrase in (
        "provider-native/default internal helpers",
        "physical_session_recommended",
        "image, and 03v workers return only to the cdd",
        "edit shards return only to the edit director",
    ):
        if phrase not in roster:
            errors.append(f"Grok worker roster is missing {phrase!r}")


def _required_codex_capabilities(root: Path, index: dict[str, Any], errors: list[str]) -> dict[str, list[str]]:
    required: dict[str, set[str]] = {}
    profiles = index.get("logical_profiles")
    profiles = profiles if isinstance(profiles, dict) else {}
    for logical in profiles.values():
        if not isinstance(logical, dict):
            continue
        codex = logical.get("providers", {}).get("codex") if isinstance(logical.get("providers"), dict) else None
        if not isinstance(codex, dict):
            continue
        role_profiles = codex.get("role_profiles")
        role_profiles = role_profiles if isinstance(role_profiles, dict) else {}
        for row in role_profiles.values():
            if not isinstance(row, dict):
                continue
            document = _load_toml(root / str(row.get("source_path", "")), errors)
            model = document.get("model")
            effort = document.get("model_reasoning_effort")
            if isinstance(model, str) and isinstance(effort, str):
                required.setdefault(model, set()).add(effort)
    return {model: sorted(efforts) for model, efforts in sorted(required.items())}


def _load_catalog(catalog_path: Path | None, errors: list[str]) -> tuple[dict[str, Any], str]:
    if catalog_path is not None:
        source = str(catalog_path)
        try:
            raw = catalog_path.read_text(encoding="utf-8")
        except OSError as exc:
            errors.append(f"cannot read runtime model catalog: {exc}")
            return {}, source
    else:
        source = "codex debug models"
        try:
            completed = subprocess.run(
                ["codex", "debug", "models"],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )
        except OSError as exc:
            errors.append(f"cannot execute runtime model catalog preflight: {exc}")
            return {}, source
        if completed.returncode != 0:
            message = completed.stderr.strip() or completed.stdout.strip()
            errors.append(f"runtime model catalog preflight failed: {message}")
            return {}, source
        raw = completed.stdout
    try:
        value = json.loads(raw)
    except json.JSONDecodeError as exc:
        errors.append(f"runtime model catalog is not valid JSON: {exc}")
        return {}, source
    if not isinstance(value, dict):
        errors.append("runtime model catalog must contain an object")
        return {}, source
    return value, source


def _validate_catalog(
    catalog: dict[str, Any],
    source: str,
    required: dict[str, list[str]],
    errors: list[str],
) -> dict[str, Any]:
    rows = {row.get("slug"): row for row in catalog.get("models", []) if isinstance(row, dict)}
    active: dict[str, list[str]] = {}
    for model, required_efforts in required.items():
        row = rows.get(model) if isinstance(rows.get(model), dict) else {}
        efforts = [item.get("effort") for item in row.get("supported_reasoning_levels", []) if isinstance(item, dict)]
        active[model] = [value for value in efforts if isinstance(value, str)]
        missing = [effort for effort in required_efforts if effort not in efforts]
        if missing:
            errors.append(f"runtime catalog lacks {missing} for a resolved Codex provider profile; route must HOLD")
    return {
        "source": source,
        "required_model_efforts_from_provider_sources": required,
        "active_model_efforts": active,
        "unavailable_pair_action": "hold_and_report",
    }


def validate(root: Path, catalog_path: Path | None = None) -> tuple[list[str], dict[str, Any]]:
    errors: list[str] = []
    provider_errors, provider_evidence = validate_provider_profiles(root)
    errors.extend(f"provider profile: {error}" for error in provider_errors)
    assignment_errors = validate_assignment_routing(root)
    errors.extend(f"assignment routing: {error}" for error in assignment_errors)
    index = _provider_index(root, errors)
    agent_documents = _validate_agent_directory(root, errors)
    _validate_codex_instruction_contract(agent_documents, errors)
    contract = _validate_execution_contract(root, errors)
    _validate_grok_routing_text(root, errors)
    required = _required_codex_capabilities(root, index, errors)
    catalog, source = _load_catalog(catalog_path, errors)
    capability = (
        _validate_catalog(catalog, source, required, errors)
        if catalog
        else {
            "source": source,
            "required_model_efforts_from_provider_sources": required,
            "unavailable_pair_action": "hold_and_report",
        }
    )
    return errors, {
        "provider_profiles": provider_evidence,
        "execution_contract_version": contract.get("schema_version"),
        "capability_check": capability,
        "external_or_generative_actions": 0,
    }


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT, help="IDOL repository root")
    parser.add_argument("--catalog-json", type=Path, help="inject a deterministic test catalog")
    parser.add_argument("--json", action="store_true", help="emit a machine-readable result")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if args.catalog_json and os.environ.get(TEST_MODE_ENV) != "1":
        parser.error(f"--catalog-json is test-only; set {TEST_MODE_ENV}=1 in deterministic tests")
    root = args.root.expanduser().resolve()
    catalog = args.catalog_json.expanduser().resolve() if args.catalog_json else None
    errors, evidence = validate(root, catalog)
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
        print(
            "OK: IDOL v35 keeps provider candidates separate from run-owned resolution, requires "
            "one OD/CDD/Edit role binding, returns image/03V to CDD and 04 shards to Edit Director"
        )
    return 0 if not errors else 1


if __name__ == "__main__":
    raise SystemExit(main())
