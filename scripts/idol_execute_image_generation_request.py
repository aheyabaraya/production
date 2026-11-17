#!/usr/bin/env python3
"""Founder-gated image execution for active v12 and strict legacy v11 requests.

`preflight` is a non-contract runtime diagnostic, is non-generative, and may be
used in tests. Its stdout is not a durable receipt or promotion input. `execute`
supports the registered OpenAI gpt-image-2 lane and an xAI API lane only when
the central media lane points to a hash-matching provider-owned exact
model/endpoint/request/response profile. A selection-only or unregistered xAI
row holds before credential access and without fallback.

Secret values are read only inside the process, are never printed, hashed, or
written, and are never included in receipts or exception messages.
"""

from __future__ import annotations

import argparse
import base64
import binascii
import hashlib
import json
import mimetypes
import os
import re
import stat
import subprocess
import sys
import tempfile
import uuid
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

try:
    import yaml
except ImportError as error:  # pragma: no cover - repository runner includes PyYAML
    raise SystemExit("PyYAML is required") from error


ROOT = Path(__file__).resolve().parents[1]
PYTHON = ROOT / "scripts" / "idol-video-python"
SCHEMA_VALIDATOR = ROOT / "scripts" / "validate_json_schema.py"
REQUEST_SCHEMA = ROOT / "schemas" / "image-generation-request.schema.json"
LEGACY_REQUEST_SCHEMA = ROOT / "schemas" / "image-generation-request-v11-legacy.schema.json"
EXECUTION_RECEIPT_SCHEMA = ROOT / "schemas" / "image-generation-execution-receipt.schema.json"
LEGACY_EXECUTION_RECEIPT_SCHEMA = ROOT / "schemas" / "image-generation-execution-receipt-v3-legacy.schema.json"
XAI_PROFILE_SCHEMA = ROOT / "schemas" / "xai-api-media-provider-profiles.schema.json"
PROVIDER_REGISTRY = ROOT / "automation" / "harness-provider-profile-registry.yaml"
OPENAI_PROFILE = ROOT / "automation" / "providers" / "openai-image-profiles.yaml"
OPENAI_API_BASE = "https://api.openai.com"
OPENAI_GENERATIONS_ENDPOINT = "/v1/images/generations"
OPENAI_EDITS_ENDPOINT = "/v1/images/edits"
OPENAI_MODEL = "gpt-image-2"
LABELS = (
    "Identity reference rule",
    "Scene intent",
    "Visible details",
    "Action cue",
    "Avoid",
)
DEFAULT_ENV_FILES = {
    "openai": (ROOT / ".env.local", ROOT / ".runtime" / "secrets" / "openai-imagegen.env"),
    "xai_api": (ROOT / ".env.xai.local",),
}
ENV_NAMES = {"openai": "OPENAI_API_KEY", "xai_api": "XAI_API_KEY"}
XAI_SECRET_PATTERN = re.compile(r"^[A-Za-z0-9._-]{16,8192}$")
XAI_ENV_FILE_MAX_BYTES = 64 * 1024


class ExecutionError(RuntimeError):
    pass


def nonsecret_child_env() -> dict[str, str]:
    return {
        key: value
        for key, value in os.environ.items()
        if key not in ENV_NAMES.values()
    }


class RejectRedirectHandler(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req: Any, fp: Any, code: int, msg: str, headers: Any, newurl: str) -> None:
        raise urllib.error.HTTPError(req.full_url, code, "redirect forbidden by exact endpoint contract", headers, fp)


def open_without_redirect(request: urllib.request.Request, *, timeout: int) -> Any:
    return urllib.request.build_opener(RejectRedirectHandler()).open(request, timeout=timeout)


def canonical(value: Any) -> Any:
    if isinstance(value, dict):
        return {str(key): canonical(value[key]) for key in sorted(value, key=str)}
    if isinstance(value, list):
        return [canonical(item) for item in value]
    return value


def value_sha256(value: Any) -> str:
    payload = json.dumps(canonical(value), ensure_ascii=False, separators=(",", ":"))
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_mapping(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8")) if path.suffix.lower() == ".json" else yaml.safe_load(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError, yaml.YAMLError) as error:
        raise ExecutionError(f"cannot read structured artifact: {path}") from error
    if not isinstance(value, dict):
        raise ExecutionError(f"structured artifact must be an object: {path}")
    return value


def repo_path(raw: str, *, must_exist: bool = False) -> Path:
    path = Path(raw)
    path = path if path.is_absolute() else ROOT / path
    path = path.resolve(strict=False)
    try:
        path.relative_to(ROOT.resolve())
    except ValueError as error:
        raise ExecutionError(f"path escapes repository: {raw}") from error
    if must_exist and not path.is_file():
        raise ExecutionError(f"required file is missing: {path.relative_to(ROOT)}")
    return path


def relative(path: Path) -> str:
    return path.resolve(strict=False).relative_to(ROOT.resolve()).as_posix()


def validate_schema(path: Path, schema: Path = REQUEST_SCHEMA) -> None:
    result = subprocess.run(
        [str(PYTHON), str(SCHEMA_VALIDATOR), str(schema), str(path)],
        cwd=ROOT,
        env=nonsecret_child_env(),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if result.returncode:
        detail = (result.stderr or result.stdout).strip()
        raise ExecutionError(f"request failed v12/legacy-v11 schema validation: {detail}")


def validate_document_schema(document: dict[str, Any], schema: Path, label: str) -> None:
    with tempfile.NamedTemporaryFile(mode="w", suffix=".json", encoding="utf-8") as handle:
        json.dump(document, handle, ensure_ascii=False, sort_keys=True)
        handle.flush()
        result = subprocess.run(
            [str(PYTHON), str(SCHEMA_VALIDATOR), str(schema), handle.name],
            cwd=ROOT,
            env=nonsecret_child_env(),
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
    if result.returncode:
        detail = (result.stderr or result.stdout).strip()
        raise ExecutionError(f"{label} failed active schema validation: {detail}")


def resolve_pointer(document: Any, pointer: str) -> Any:
    if not pointer.startswith("/"):
        raise ExecutionError("source JSON pointer must begin with /")
    value = document
    for raw in pointer.split("/")[1:]:
        token = raw.replace("~1", "/").replace("~0", "~")
        try:
            value = value[int(token)] if isinstance(value, list) else value[token]
        except (KeyError, IndexError, ValueError, TypeError) as error:
            raise ExecutionError(f"source JSON pointer does not resolve: {pointer}") from error
    return value


def allowed_env_file(path: Path, *, provider: str | None = None) -> None:
    try:
        metadata = os.lstat(path)
    except OSError as error:
        raise ExecutionError(f"credential env file is missing: {relative(path)}") from error
    if stat.S_ISLNK(metadata.st_mode) or path.is_symlink():
        raise ExecutionError(f"credential env file must not be a symlink: {relative(path)}")
    if not stat.S_ISREG(metadata.st_mode):
        raise ExecutionError(f"credential env file is missing: {relative(path)}")
    try:
        path.resolve().relative_to(ROOT.resolve())
    except ValueError as error:
        raise ExecutionError("credential env file must stay inside the repository") from error
    ignored = subprocess.run(
        ["git", "check-ignore", "-q", str(path)],
        cwd=ROOT,
        env=nonsecret_child_env(),
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    if ignored.returncode != 0:
        raise ExecutionError(f"credential env file is not git-ignored: {relative(path)}")
    if provider == "xai_api":
        if metadata.st_uid != os.geteuid() or stat.S_IMODE(metadata.st_mode) & 0o077:
            raise ExecutionError(
                "xAI credential env file must be current-user-owned with mode 0600 or stricter"
            )
        if metadata.st_size > XAI_ENV_FILE_MAX_BYTES:
            raise ExecutionError("xAI credential env file exceeds the 64 KiB security limit")


def validate_xai_secret_shape(value: str) -> None:
    if not XAI_SECRET_PATTERN.fullmatch(value):
        raise ExecutionError("XAI_API_KEY has an invalid private transport shape")


def dotenv_secret(path: Path, env_name: str, *, provider: str) -> str | None:
    allowed_env_file(path, provider=provider)
    try:
        raw = path.read_bytes()
        text = raw.decode("utf-8") if provider == "xai_api" else raw.decode("utf-8", errors="ignore")
    except UnicodeDecodeError as error:
        raise ExecutionError("xAI credential env file must be valid UTF-8") from error

    matches: list[str] = []
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        if line.startswith("export "):
            line = line[len("export ") :].strip()
        key, value = line.split("=", 1)
        if key.strip() != env_name:
            continue
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
            value = value[1:-1]
        matches.append(value.strip())

    if provider == "xai_api" and len(matches) > 1:
        raise ExecutionError("xAI credential env file contains duplicate XAI_API_KEY entries")
    value = matches[0] if matches else ""
    if not value:
        return None
    if provider == "xai_api":
        validate_xai_secret_shape(value)
    return value


def dotenv_credential_present(path: Path, env_name: str, *, provider: str) -> bool:
    if not path.is_file() and not path.is_symlink():
        return False
    return dotenv_secret(path, env_name, provider=provider) is not None


def parse_dotenv_secret(path: Path, env_name: str, *, provider: str) -> str | None:
    return dotenv_secret(path, env_name, provider=provider)


def credential_file_candidates(provider: str, explicit_env_file: str | None) -> tuple[Path, ...]:
    if not explicit_env_file:
        return DEFAULT_ENV_FILES[provider]
    path = repo_path(explicit_env_file, must_exist=True)
    if provider == "xai_api" and path != DEFAULT_ENV_FILES[provider][0].resolve(strict=False):
        raise ExecutionError("xAI API credential file must be the ignored repository .env.xai.local path")
    return (path,)


def credential_presence(provider: str, explicit_env_file: str | None, *, process_env_only: bool = False) -> str:
    env_name = ENV_NAMES[provider]
    process_value = os.environ.get(env_name, "")
    if process_value:
        if provider == "xai_api":
            validate_xai_secret_shape(process_value)
        return "process_environment"
    if process_env_only:
        raise ExecutionError(f"{env_name} is not present in the process environment")
    candidates = credential_file_candidates(provider, explicit_env_file)
    for path in candidates:
        if dotenv_credential_present(path, env_name, provider=provider):
            return relative(path)
    raise ExecutionError(f"{env_name} is not present in the process environment or an allowed ignored dotenv file")


def load_credential_for_confirmed_execute(provider: str, explicit_env_file: str | None, *, process_env_only: bool = False) -> str:
    env_name = ENV_NAMES[provider]
    process_value = os.environ.get(env_name, "")
    if process_value:
        if provider == "xai_api":
            validate_xai_secret_shape(process_value)
        return process_value
    if process_env_only:
        raise ExecutionError(f"{env_name} is not present in the process environment")
    candidates = credential_file_candidates(provider, explicit_env_file)
    for path in candidates:
        if not dotenv_credential_present(path, env_name, provider=provider):
            continue
        secret = parse_dotenv_secret(path, env_name, provider=provider)
        if secret:
            return secret
    raise ExecutionError(f"{env_name} is not present in the process environment or an allowed ignored dotenv file")


def require_artifact_ref(ref: Any, label: str) -> tuple[Path, dict[str, Any]]:
    if not isinstance(ref, dict):
        raise ExecutionError(f"{label} must be an artifact reference")
    path = repo_path(str(ref.get("path", "")), must_exist=True)
    if file_sha256(path) != str(ref.get("sha256", "")):
        raise ExecutionError(f"{label} SHA-256 is stale")
    return path, load_mapping(path)


def validate_request(request_path: Path, request: dict[str, Any]) -> dict[str, Any]:
    request_version = request.get("schema_version")
    packet_version = {
        "idol_image_generation_request.v11": "2.5",
        "idol_image_generation_request.v12": "2.6",
    }.get(request_version)
    if packet_version is None:
        raise ExecutionError("only active v12 or strict legacy v11 image requests are executable")
    request_schema = REQUEST_SCHEMA if request_version == "idol_image_generation_request.v12" else LEGACY_REQUEST_SCHEMA
    validate_schema(request_path, request_schema)
    if request.get("status") != "ready":
        hold_reasons = request.get("hold_reasons")
        if isinstance(hold_reasons, list):
            provider_hold = next(
                (
                    str(reason)
                    for reason in hold_reasons
                    if "xAI API media" in str(reason)
                    and "HOLD" in str(reason)
                    and "no fallback" in str(reason)
                ),
                None,
            )
            if provider_hold:
                raise ExecutionError(f"xAI API media activation HOLD: {provider_hold}")
        raise ExecutionError("only a ready v12 or legacy-v11 request may execute")
    if request.get("hold_reasons"):
        raise ExecutionError("ready request must not carry hold reasons")
    if request.get("mode") not in {"fp_hero_core", "official_core", "official_branch"}:
        raise ExecutionError("request mode is not an active one-cut mode")

    prompt = request.get("prompt") or {}
    text = str(prompt.get("full_prompt_text", ""))
    lines = text.splitlines()
    if len(lines) != 5 or any(not lines[index].startswith(f"{label}:") for index, label in enumerate(LABELS)):
        raise ExecutionError("request prompt must be exactly the five canonical labeled lines")
    if hashlib.sha256(text.encode("utf-8")).hexdigest() != prompt.get("full_prompt_sha256"):
        raise ExecutionError("request prompt SHA-256 is stale")

    source_path, source = require_artifact_ref(request.get("source_prompt_packet"), "source_prompt_packet")
    source_ref = request["source_prompt_packet"]
    if source.get("schema_version") != packet_version or source.get("status") != "approved":
        raise ExecutionError(f"source Prompt Packets must be approved {packet_version} for {request_version}")
    packet = resolve_pointer(source, str(source_ref.get("json_pointer", "")))
    if value_sha256(packet) != source_ref.get("value_sha256"):
        raise ExecutionError("source Prompt Packet value SHA-256 is stale")
    if packet.get("packet_id") != request.get("packet_id"):
        raise ExecutionError("source Prompt Packet id differs from request")
    if packet.get("rendered_five_lines") != prompt:
        raise ExecutionError("request prompt differs from approved Prompt Packet")
    if packet.get("attachments") != request.get("attachments"):
        raise ExecutionError("request attachments differ from approved Prompt Packet order")
    if request_version == "idol_image_generation_request.v12":
        if packet.get("reference_role_plan") != request.get("reference_role_plan"):
            raise ExecutionError("request reference_role_plan differs from approved Prompt Packet")
        if request.get("mode") == "official_branch" and packet.get("section_cohort_id") != request.get("section_cohort_id"):
            raise ExecutionError("request section cohort differs from approved Prompt Packet")
    expected_execution = dict(packet.get("execution") or {})
    expected_execution["founder_generation_authority_id"] = request.get("approval", {}).get("founder_generation_authority_id")
    if expected_execution != request.get("execution"):
        raise ExecutionError("request execution snapshot differs from approved Prompt Packet")

    attachments = list(request.get("attachments") or [])
    if [row.get("order") for row in attachments] != list(range(1, len(attachments) + 1)):
        raise ExecutionError("attachment order must be contiguous from 1")
    for index, row in enumerate(attachments):
        path = repo_path(str(row.get("actual_path", "")), must_exist=True)
        if file_sha256(path) != row.get("sha256"):
            raise ExecutionError(f"attachment {index + 1} SHA-256 is stale")
        if row.get("pixel_inspection_status") != "passed" or row.get("locked") is not True:
            raise ExecutionError(f"attachment {index + 1} is not locked and pixel-passed")
    if value_sha256(attachments) != request.get("attachment_order_sha256"):
        raise ExecutionError("attachment order SHA-256 is stale")
    if request_version == "idol_image_generation_request.v12":
        plan = request.get("reference_role_plan") or {}
        binding_ids = [str(row.get("binding_id", "")) for row in attachments]
        if plan.get("attachment_order_binding_ids") != binding_ids:
            raise ExecutionError("reference role plan attachment order differs from transport order")
        physical_inputs = [(str(row.get("actual_path", "")), str(row.get("sha256", ""))) for row in attachments]
        if len(set(physical_inputs)) != len(physical_inputs):
            raise ExecutionError("identical attachment bytes must be registered once")
        groups = list(plan.get("logical_role_groups") or [])
        roles = [str(row.get("logical_role", "")) for row in groups]
        if len(groups) > 4 or len(set(roles)) != len(roles) or not {"character_visual", "scene_visual_package", "motion_reference"}.issubset(roles):
            raise ExecutionError("v12 requires unique character, scene, and motion logical reference roles with no fifth role")

    approval_path, approval = require_artifact_ref(request.get("approval", {}).get("approval_source"), "approval_source")
    if approval.get("schema_version") != "idol_image_generation_section_approval.v6":
        raise ExecutionError("approval source must be active v6")
    if approval.get("source_prompt_packets_sha256") != file_sha256(source_path):
        raise ExecutionError("approval source Prompt Packets SHA-256 is stale")
    authority = str(request.get("approval", {}).get("founder_generation_authority_id", ""))
    if not authority or authority != approval.get("founder_generation_authority_id"):
        raise ExecutionError("Founder generation authority differs from exact approval")
    if request.get("approval", {}).get("external_execution_approved") is not True or request.get("approval", {}).get("paid_generation_approved") is not True:
        raise ExecutionError("exact external and paid Founder approval is required")
    if approval.get("external_execution_approved") is not True or approval.get("paid_generation_approved") is not True:
        raise ExecutionError("approval source does not authorize external paid execution")
    if approval.get("approved_output_count") != 1 or not str(approval.get("spend_envelope", "")).strip():
        raise ExecutionError("approval must bind exactly one output and a non-empty spend envelope")
    if approval.get("automatic_fallback") != "none":
        raise ExecutionError("approval fallback must be none")
    approval_row = next((row for row in approval.get("packets", []) if row.get("packet_id") == request.get("packet_id")), None)
    if not approval_row:
        raise ExecutionError("approval does not contain the exact packet")
    expected_paths = [row.get("actual_path") for row in attachments]
    expected_hashes = [row.get("sha256") for row in attachments]
    output_path = repo_path(str(request.get("expected_output", {}).get("path", "")))
    if not output_path.is_relative_to(repo_path(str(request.get("run", "")))):
        raise ExecutionError("expected output escapes the owning run")
    if request.get("execution", {}).get("expected_output_path") != relative(output_path):
        raise ExecutionError("execution expected output path differs from request")
    if (
        approval_row.get("prompt_sha256") != prompt.get("full_prompt_sha256")
        or approval_row.get("approved_attachment_paths") != expected_paths
        or approval_row.get("approved_attachment_sha256s") != expected_hashes
        or approval_row.get("expected_output_path") != relative(output_path)
        or approval_row.get("output_count") != 1
        or approval_row.get("decision") != "approved_for_current_job"
    ):
        raise ExecutionError("approval packet prompt/attachment/output/count bytes differ")

    execution = request.get("execution") or {}
    for key in (
        "execution_adapter_id",
        "provider",
        "auth_lane",
        "provider_profile_id",
        "provider_profile_sha256",
        "provider_capability_snapshot_sha256",
    ):
        if str(approval.get(key, "")) != str(execution.get(key, "")):
            raise ExecutionError(f"approval {key} differs from request")
    if execution.get("automatic_fallback") != "none" or request.get("integrity_contract", {}).get("provider_auth_model_fallback") != "none":
        raise ExecutionError("provider/auth/model fallback must be none")
    if execution.get("prompt_rewrite_policy") != "forbidden" or request.get("integrity_contract", {}).get("prompt_rewrite_policy") != "forbidden":
        raise ExecutionError("prompt rewrite must be forbidden")
    if execution.get("output_count") != 1 or request.get("quality_contract", {}).get("output_count") != 1:
        raise ExecutionError("one request must produce exactly one output")

    return {
        "request_path": relative(request_path),
        "request_sha256": file_sha256(request_path),
        "source_prompt_packets_path": relative(source_path),
        "approval_path": relative(approval_path),
        "approval_sha256": file_sha256(approval_path),
        "founder_generation_authority_id": authority,
        "spend_envelope": approval["spend_envelope"],
        "prompt_text": text,
        "attachments": [(repo_path(row["actual_path"], must_exist=True), row) for row in attachments],
        "output_path": output_path,
    }


def exact_https_endpoint(api_base_url: str, endpoint_path: str) -> str:
    parsed = urllib.parse.urlsplit(api_base_url)
    try:
        port = parsed.port
    except ValueError as error:
        raise ExecutionError("registered API base contains an invalid port") from error
    if (
        parsed.scheme != "https"
        or not parsed.hostname
        or port not in {None, 443}
        or parsed.username is not None
        or parsed.password is not None
        or parsed.query
        or parsed.fragment
        or parsed.path not in {"", "/"}
    ):
        raise ExecutionError("registered API base must be an exact credential-free HTTPS origin")
    if (
        not endpoint_path.startswith("/")
        or endpoint_path.startswith("//")
        or ".." in endpoint_path.split("/")
        or "?" in endpoint_path
        or "#" in endpoint_path
    ):
        raise ExecutionError("registered API endpoint path is unsafe")
    return api_base_url.rstrip("/") + endpoint_path


def validate_xai_request_contract(operation: dict[str, Any]) -> None:
    request_contract = operation.get("request_contract") or {}
    field_names = [
        request_contract.get("model_field"),
        request_contract.get("prompt_field"),
        request_contract.get("output_count_field"),
    ]
    attachment_field = request_contract.get("attachment_field")
    if attachment_field is not None:
        field_names.append(attachment_field)
    if any(not isinstance(field, str) or not field for field in field_names) or len(set(field_names)) != len(field_names):
        raise ExecutionError("registered xAI request field names must be nonempty and distinct")
    fixed_fields = request_contract.get("fixed_fields") or {}
    if any(field in fixed_fields for field in field_names):
        raise ExecutionError("registered xAI fixed fields must not override model, prompt, count, or attachments")


def validate_provider(request: dict[str, Any], context: dict[str, Any]) -> dict[str, Any]:
    execution = request["execution"]
    adapter = execution["execution_adapter_id"]
    registry = load_mapping(PROVIDER_REGISTRY)
    if adapter == "openai_api_gpt_image_2":
        lane = registry.get("media_lanes", {}).get("openai_image_api_current", {})
        profile = load_mapping(OPENAI_PROFILE)
        source_sha = file_sha256(OPENAI_PROFILE)
        if (
            execution.get("provider") != "openai"
            or execution.get("provider_model_or_tool") != OPENAI_MODEL
            or execution.get("selected_native_tool") is not None
            or execution.get("auth_lane") != "founder_approved_api"
            or execution.get("provider_profile_id") != "openai_image_api_current"
            or execution.get("provider_profile_sha256") != source_sha
            or execution.get("provider_capability_snapshot_sha256") != file_sha256(PROVIDER_REGISTRY)
            or lane.get("image_adapter_id") != adapter
            or lane.get("provider_profile_source_sha256") != source_sha
            or profile.get("profiles", {}).get("openai_image_api_current", {}).get("exact_model") != OPENAI_MODEL
            or lane.get("automatic_fallback") != "none"
        ):
            raise ExecutionError("OpenAI lane differs from the active gpt-image-2 provider snapshot")
        endpoint = OPENAI_EDITS_ENDPOINT if context["attachments"] else OPENAI_GENERATIONS_ENDPOINT
        return {
            "provider": "openai",
            "credential_env_name": "OPENAI_API_KEY",
            "endpoint": endpoint,
            "transport": "multipart_form_data_image_array" if context["attachments"] else "json",
            "response_image_encoding": "base64_json",
            "api_version": execution["cli_or_api_version"],
            "selection_only": False,
        }
    if adapter == "xai_api_media":
        lane = registry.get("media_lanes", {}).get("xai_api_media", {})
        registry_sha = file_sha256(PROVIDER_REGISTRY)
        if lane.get("selection_only") is True:
            raise ExecutionError("xAI API media activation HOLD: no exact registered provider profile is active and no fallback is allowed")

        source_path_value = lane.get("provider_profile_source")
        source_sha = lane.get("provider_profile_source_sha256")
        profile_id = lane.get("provider_profile_id")
        if not all(isinstance(value, str) and value for value in (source_path_value, source_sha, profile_id)):
            raise ExecutionError("xAI API media activation HOLD: registered lane lacks an exact provider profile source, SHA-256, or profile id; no fallback is allowed")
        profile_path = repo_path(source_path_value, must_exist=True)
        actual_source_sha = file_sha256(profile_path)
        if actual_source_sha != source_sha:
            raise ExecutionError("registered xAI API provider profile source SHA-256 is stale")
        profile_source = load_mapping(profile_path)
        validate_document_schema(profile_source, XAI_PROFILE_SCHEMA, "xAI API provider profile source")
        profile = profile_source.get("profiles", {}).get(profile_id)
        if not isinstance(profile, dict):
            raise ExecutionError("registered xAI API provider profile id does not resolve")
        operation_id = "image_edit" if context["attachments"] else "image_gen"
        operation = profile.get("operations", {}).get(operation_id)
        if not isinstance(operation, dict):
            raise ExecutionError(f"registered xAI API profile does not support required {operation_id} operation")
        validate_xai_request_contract(operation)
        exact_url = exact_https_endpoint(str(profile.get("api_base_url", "")), str(operation.get("endpoint_path", "")))
        if (
            execution.get("provider") != "xai_api"
            or execution.get("auth_lane") != "founder_approved_api"
            or execution.get("selected_native_tool") is not None
            or execution.get("provider_model_or_tool") != profile.get("exact_model")
            or execution.get("provider_profile_id") != profile_id
            or execution.get("provider_profile_sha256") != actual_source_sha
            or execution.get("provider_capability_snapshot_sha256") != registry_sha
            or execution.get("cli_or_api_version") != profile.get("api_version")
            or lane.get("provider") != "xai"
            or lane.get("auth_lane") != "founder_approved_api"
            or lane.get("capability_status") != "active"
            or lane.get("harness_status") != "active"
            or lane.get("registration_status") != "registered_exact"
            or lane.get("image_adapter_id") != "xai_api_media"
            or lane.get("image_output_contract") != "exact_expected_output_path_sha256_pixel_review"
            or lane.get("default_enabled") is not False
            or lane.get("selection_only") is not False
            or lane.get("automatic_fallback") != "none"
            or profile.get("default_enabled") is not False
            or profile.get("automatic_fallback") != "none"
        ):
            raise ExecutionError("xAI API request differs from the exact registered default-disabled provider snapshot")
        return {
            "provider": "xai_api",
            "credential_env_name": "XAI_API_KEY",
            "endpoint": operation["endpoint_path"],
            "url": exact_url,
            "transport": operation["transport"],
            "response_image_encoding": operation["response_contract"]["image_encoding"],
            "api_version": profile["api_version"],
            "profile": profile,
            "operation": operation,
            "operation_id": operation_id,
            "selection_only": False,
        }
    raise ExecutionError("this executor accepts only active OpenAI or xAI API request lanes")


def safe_preflight(request_path: Path, request: dict[str, Any], env_file: str | None, *, process_env_only: bool = False) -> tuple[dict[str, Any], dict[str, Any]]:
    context = validate_request(request_path, request)
    provider = validate_provider(request, context)
    context["provider_runtime"] = provider
    credential_source = credential_presence(provider["provider"], env_file, process_env_only=process_env_only)
    execution = request["execution"]
    report = {
        "schema_version": "idol_image_generation_execution_preflight.v1",
        "contract_status": "non_contract_runtime_diagnostic",
        "ok": True,
        "external_call_performed": False,
        "request_path": context["request_path"],
        "request_sha256": context["request_sha256"],
        "packet_id": request["packet_id"],
        "mode": request["mode"],
        "cut_id": request["cut_pointer"]["cut_id"],
        "execution_adapter_id": execution["execution_adapter_id"],
        "provider": provider["provider"],
        "provider_model_or_tool": execution["provider_model_or_tool"],
        "auth_lane": execution["auth_lane"],
        "provider_profile_id": execution["provider_profile_id"],
        "provider_profile_sha256": execution["provider_profile_sha256"],
        "provider_capability_snapshot_sha256": execution["provider_capability_snapshot_sha256"],
        "credential_env_name": provider["credential_env_name"],
        "credential_present": True,
        "credential_source": credential_source,
        "prompt_sha256": request["prompt"]["full_prompt_sha256"],
        "attachment_count": len(context["attachments"]),
        "attachment_order_sha256": request["attachment_order_sha256"],
        "output_count": 1,
        "expected_output_path": relative(context["output_path"]),
        "founder_generation_authority_id": context["founder_generation_authority_id"],
        "spend_envelope": context["spend_envelope"],
        "automatic_fallback": "none",
        "prompt_rewrite_policy": "forbidden",
        "selection_only": provider["selection_only"],
        "ready_for_execute": not provider["selection_only"],
        "endpoint": provider["endpoint"],
        "transport": provider["transport"],
        "response_image_encoding": provider["response_image_encoding"],
    }
    return report, context


def image_data_url(path: Path) -> str:
    mime = mimetypes.guess_type(path.name)[0] or "image/png"
    return f"data:{mime};base64,{base64.b64encode(path.read_bytes()).decode('ascii')}"


def openai_payload(_request: dict[str, Any], context: dict[str, Any]) -> dict[str, Any]:
    return {
        "model": OPENAI_MODEL,
        "prompt": context["prompt_text"],
        "n": 1,
        "size": "1536x1024",
        "quality": "high",
        "output_format": "png",
    }


def multipart_body(
    fields: dict[str, Any],
    attachments: list[tuple[Path, dict[str, Any]]],
    *,
    attachment_field: str = "image[]",
) -> tuple[bytes, str]:
    boundary = f"idol-image-{uuid.uuid4().hex}"
    chunks: list[bytes] = []
    for name, value in fields.items():
        chunks.extend(
            [
                f"--{boundary}\r\n".encode("ascii"),
                f'Content-Disposition: form-data; name="{name}"\r\n\r\n'.encode("ascii"),
                str(value).encode("utf-8"),
                b"\r\n",
            ]
        )
    for index, (path, _row) in enumerate(attachments, start=1):
        mime = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
        filename = f"attachment-{index}{path.suffix.lower() or '.png'}"
        chunks.extend(
            [
                f"--{boundary}\r\n".encode("ascii"),
                f'Content-Disposition: form-data; name="{attachment_field}"; filename="{filename}"\r\n'.encode("ascii"),
                f"Content-Type: {mime}\r\n\r\n".encode("ascii"),
                path.read_bytes(),
                b"\r\n",
            ]
        )
    chunks.append(f"--{boundary}--\r\n".encode("ascii"))
    return b"".join(chunks), f"multipart/form-data; boundary={boundary}"


def openai_http_request(request: dict[str, Any], context: dict[str, Any], secret: str) -> urllib.request.Request:
    endpoint = OPENAI_EDITS_ENDPOINT if context["attachments"] else OPENAI_GENERATIONS_ENDPOINT
    fields = openai_payload(request, context)
    if context["attachments"]:
        body, content_type = multipart_body(fields, context["attachments"])
    else:
        body = json.dumps(fields, ensure_ascii=False).encode("utf-8")
        content_type = "application/json"
    return urllib.request.Request(
        OPENAI_API_BASE + endpoint,
        data=body,
        method="POST",
        headers={"Authorization": f"Bearer {secret}", "Content-Type": content_type},
    )


def perform_openai(request: dict[str, Any], context: dict[str, Any], secret: str) -> bytes:
    http_request = openai_http_request(request, context, secret)
    try:
        with urllib.request.urlopen(http_request, timeout=180) as response:
            body = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        raise ExecutionError(f"OpenAI image request failed with HTTP {error.code}; no fallback was attempted") from error
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as error:
        raise ExecutionError("OpenAI image request failed; no fallback was attempted") from error
    data = body.get("data") if isinstance(body, dict) else None
    if not isinstance(data, list) or len(data) != 1 or not isinstance(data[0], dict):
        raise ExecutionError("OpenAI response did not contain exactly one image")
    encoded = data[0].get("b64_json")
    if not isinstance(encoded, str) or not encoded:
        raise ExecutionError("OpenAI response lacks one base64 image payload")
    try:
        return base64.b64decode(encoded, validate=True)
    except (ValueError, binascii.Error) as error:
        raise ExecutionError("OpenAI response image payload is invalid") from error


def xai_payload(request: dict[str, Any], context: dict[str, Any], provider: dict[str, Any]) -> dict[str, Any]:
    operation = provider["operation"]
    contract = operation["request_contract"]
    fields = dict(contract.get("fixed_fields") or {})
    fields[contract["model_field"]] = request["execution"]["provider_model_or_tool"]
    fields[contract["prompt_field"]] = context["prompt_text"]
    fields[contract["output_count_field"]] = 1
    attachments = context["attachments"]
    transport = operation["transport"]
    attachment_field = contract.get("attachment_field")
    if provider["operation_id"] == "image_gen":
        if attachments or attachment_field is not None or operation.get("attachment_policy") != "forbidden":
            raise ExecutionError("registered xAI image_gen operation must forbid attachments")
    else:
        if not attachments or not attachment_field or operation.get("attachment_policy") != "required_all_ordered":
            raise ExecutionError("registered xAI image_edit operation must carry every ordered attachment")
        if transport == "json_data_url_array":
            fields[attachment_field] = [image_data_url(path) for path, _row in attachments]
        elif transport == "json_base64_array":
            fields[attachment_field] = [base64.b64encode(path.read_bytes()).decode("ascii") for path, _row in attachments]
        elif transport != "multipart_form_data_image_array":
            raise ExecutionError("registered xAI image_edit transport is unsupported")
    return fields


def xai_http_request(request: dict[str, Any], context: dict[str, Any], secret: str, provider: dict[str, Any]) -> urllib.request.Request:
    fields = xai_payload(request, context, provider)
    operation = provider["operation"]
    transport = operation["transport"]
    if transport == "multipart_form_data_image_array":
        body, content_type = multipart_body(
            fields,
            context["attachments"],
            attachment_field=operation["request_contract"]["attachment_field"],
        )
    else:
        body = json.dumps(fields, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        content_type = "application/json"
    return urllib.request.Request(
        provider["url"],
        data=body,
        method="POST",
        headers={"Authorization": f"Bearer {secret}", "Content-Type": content_type},
    )


def read_limited_response(response: Any, *, limit_bytes: int = 100 * 1024 * 1024) -> bytes:
    body = response.read(limit_bytes + 1)
    if len(body) > limit_bytes:
        raise ExecutionError("xAI API response exceeds the registered image transport safety limit")
    if not body:
        raise ExecutionError("xAI API response contains no image bytes")
    return body


def exact_output_url(raw_url: str, allowed_hosts: list[str]) -> str:
    parsed = urllib.parse.urlsplit(raw_url)
    allowed = {host.casefold() for host in allowed_hosts}
    try:
        port = parsed.port
    except ValueError as error:
        raise ExecutionError("xAI API output URL contains an invalid port") from error
    if (
        parsed.scheme != "https"
        or not parsed.hostname
        or parsed.hostname.casefold() not in allowed
        or port not in {None, 443}
        or parsed.username is not None
        or parsed.password is not None
        or parsed.fragment
    ):
        raise ExecutionError("xAI API output URL is outside the exact registered HTTPS host allowlist")
    return raw_url


def xai_response_image_bytes(body: bytes, provider: dict[str, Any]) -> tuple[bytes | None, str | None]:
    response_contract = provider["operation"]["response_contract"]
    encoding = response_contract["image_encoding"]
    if encoding == "raw_body":
        return body, None
    try:
        document = json.loads(body.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ExecutionError("xAI API response is not valid JSON for the registered response contract") from error
    items = resolve_pointer(document, response_contract["items_json_pointer"])
    if not isinstance(items, list) or len(items) != 1:
        raise ExecutionError("xAI API response did not contain exactly one registered image item")
    value = resolve_pointer(items[0], response_contract["image_value_json_pointer"])
    if not isinstance(value, str) or not value:
        raise ExecutionError("xAI API response image value is missing")
    if encoding == "base64_json":
        try:
            return base64.b64decode(value, validate=True), None
        except (ValueError, binascii.Error) as error:
            raise ExecutionError("xAI API response base64 image payload is invalid") from error
    if encoding == "https_url":
        return None, exact_output_url(value, response_contract["output_url_allowed_hosts"])
    raise ExecutionError("registered xAI API response encoding is unsupported")


def perform_xai(request: dict[str, Any], context: dict[str, Any], secret: str, provider: dict[str, Any]) -> bytes:
    http_request = xai_http_request(request, context, secret, provider)
    try:
        with open_without_redirect(http_request, timeout=180) as response:
            body = read_limited_response(response)
    except urllib.error.HTTPError as error:
        raise ExecutionError(f"xAI image request failed with HTTP {error.code}; no fallback was attempted") from error
    except (urllib.error.URLError, TimeoutError) as error:
        raise ExecutionError("xAI image request failed; no fallback was attempted") from error
    image_bytes, output_url = xai_response_image_bytes(body, provider)
    if image_bytes is not None:
        return image_bytes
    try:
        output_request = urllib.request.Request(output_url, method="GET")
        with open_without_redirect(output_request, timeout=180) as response:
            final_url = response.geturl()
            exact_output_url(final_url, provider["operation"]["response_contract"]["output_url_allowed_hosts"])
            return read_limited_response(response)
    except urllib.error.HTTPError as error:
        raise ExecutionError(f"xAI output download failed with HTTP {error.code}; no fallback was attempted") from error
    except (urllib.error.URLError, TimeoutError) as error:
        raise ExecutionError("xAI output download failed; no fallback was attempted") from error


def validate_execution_receipt(
    receipt: dict[str, Any],
    request: dict[str, Any],
    context: dict[str, Any],
    image_bytes: bytes,
    provider: dict[str, Any],
) -> None:
    receipt_schema = (
        EXECUTION_RECEIPT_SCHEMA
        if receipt.get("schema_version") == "idol_image_generation_execution_receipt.v4"
        else LEGACY_EXECUTION_RECEIPT_SCHEMA
    )
    validate_document_schema(receipt, receipt_schema, "image execution receipt")
    execution = request["execution"]
    expected = {
        "request_path": context["request_path"],
        "request_sha256": context["request_sha256"],
        "approval_path": context["approval_path"],
        "approval_sha256": context["approval_sha256"],
        "packet_id": request["packet_id"],
        "mode": request["mode"],
        "cut_id": request["cut_pointer"]["cut_id"],
        "execution_adapter_id": execution["execution_adapter_id"],
        "provider": execution["provider"],
        "provider_model_or_tool": execution["provider_model_or_tool"],
        "selected_native_tool": execution.get("selected_native_tool"),
        "auth_lane": execution["auth_lane"],
        "provider_profile_id": execution["provider_profile_id"],
        "runtime_version": execution["cli_or_api_version"],
        "provider_profile_sha256": execution["provider_profile_sha256"],
        "provider_capability_snapshot_sha256": execution["provider_capability_snapshot_sha256"],
        "founder_generation_authority_id": context["founder_generation_authority_id"],
        "spend_envelope": context["spend_envelope"],
        "prompt_sha256": request["prompt"]["full_prompt_sha256"],
        "attachment_order_sha256": request["attachment_order_sha256"],
        "endpoint": provider["endpoint"],
        "transport": provider["transport"],
        "response_image_encoding": provider["response_image_encoding"],
        "native_session_binding": None,
        "output_path": relative(context["output_path"]),
        "output_sha256": hashlib.sha256(image_bytes).hexdigest(),
    }
    if request.get("schema_version") == "idol_image_generation_request.v12":
        expected["request_schema_version"] = request["schema_version"]
        expected["reference_role_plan_sha256"] = value_sha256(request["reference_role_plan"])
        if request.get("section_cohort_id") is not None:
            expected["section_cohort_id"] = request["section_cohort_id"]
    for field, value in expected.items():
        if receipt.get(field) != value:
            raise ExecutionError(f"image execution receipt {field} differs from the exact request or returned bytes")


def write_output(path: Path, image_bytes: bytes, receipt: dict[str, Any]) -> Path:
    if path.exists():
        raise ExecutionError(f"expected output already exists; overwrite is forbidden: {relative(path)}")
    receipt_path = Path(f"{path}.execution.json")
    if receipt_path.exists():
        raise ExecutionError(f"execution receipt already exists; overwrite is forbidden: {relative(receipt_path)}")
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=path.parent, prefix=f".{path.name}.", delete=False) as handle:
        temp_path = Path(handle.name)
        handle.write(image_bytes)
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(temp_path, path)
    with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, prefix=f".{receipt_path.name}.", delete=False, encoding="utf-8") as handle:
        receipt_temp_path = Path(handle.name)
        handle.write(json.dumps(receipt, ensure_ascii=False, indent=2, sort_keys=True) + "\n")
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(receipt_temp_path, receipt_path)
    return receipt_path


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    for name in ("preflight", "execute"):
        child = subparsers.add_parser(name)
        child.add_argument("request")
        child.add_argument("--env-file", default=None, help="Ignored local dotenv file; xAI accepts only repository .env.xai.local; secret values are never printed")
        child.add_argument("--process-env-only", action="store_true", help="Disable dotenv discovery; intended for isolated tests and sealed runtimes")
        if name == "execute":
            child.add_argument("--founder-authority-id", required=True)
            child.add_argument("--confirm-external-paid-execution", action="store_true")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        request_path = repo_path(args.request, must_exist=True)
        request = load_mapping(request_path)
        report, context = safe_preflight(request_path, request, args.env_file, process_env_only=args.process_env_only)
        if args.command == "preflight":
            print(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True))
            return 0
        if report["selection_only"]:
            raise ExecutionError("xAI API media activation HOLD: no exact endpoint/model execution profile is registered and no fallback is allowed")
        if not args.confirm_external_paid_execution:
            raise ExecutionError("execute requires --confirm-external-paid-execution")
        if args.founder_authority_id != context["founder_generation_authority_id"]:
            raise ExecutionError("runtime Founder authority id differs from the exact request approval")
        provider = context["provider_runtime"]
        secret = load_credential_for_confirmed_execute(provider["provider"], args.env_file, process_env_only=args.process_env_only)
        if provider["provider"] == "openai":
            image_bytes = perform_openai(request, context, secret)
        elif provider["provider"] == "xai_api":
            image_bytes = perform_xai(request, context, secret, provider)
        else:  # pragma: no cover - validate_provider fails before this boundary
            raise ExecutionError("registered image execution provider is unsupported")
        execution = request["execution"]
        receipt_version = (
            "idol_image_generation_execution_receipt.v4"
            if request["schema_version"] == "idol_image_generation_request.v12"
            else "idol_image_generation_execution_receipt.v3"
        )
        receipt = {
            "schema_version": receipt_version,
            "artifact_type": "image_generation_execution_receipt",
            "status": "generated_pending_pixel_review",
            "external_call_performed": True,
            "request_path": context["request_path"],
            "request_sha256": context["request_sha256"],
            "approval_path": context["approval_path"],
            "approval_sha256": context["approval_sha256"],
            "packet_id": request["packet_id"],
            "mode": request["mode"],
            "cut_id": request["cut_pointer"]["cut_id"],
            "execution_adapter_id": execution["execution_adapter_id"],
            "provider": execution["provider"],
            "provider_model_or_tool": execution["provider_model_or_tool"],
            "selected_native_tool": execution.get("selected_native_tool"),
            "auth_lane": execution["auth_lane"],
            "provider_profile_id": execution["provider_profile_id"],
            "runtime_version": execution["cli_or_api_version"],
            "provider_profile_sha256": execution["provider_profile_sha256"],
            "provider_capability_snapshot_sha256": execution["provider_capability_snapshot_sha256"],
            "founder_generation_authority_id": context["founder_generation_authority_id"],
            "spend_envelope": context["spend_envelope"],
            "prompt_sha256": request["prompt"]["full_prompt_sha256"],
            "attachment_order_sha256": request["attachment_order_sha256"],
            "endpoint": report["endpoint"],
            "transport": report["transport"],
            "response_image_encoding": report["response_image_encoding"],
            "native_session_binding": None,
            "output_count": 1,
            "output_path": relative(context["output_path"]),
            "output_sha256": hashlib.sha256(image_bytes).hexdigest(),
            "automatic_fallback": "none",
            "prompt_rewrite_policy": "forbidden",
            "full_size_pixel_review_status": "pending",
            "03v_handoff_allowed": False,
            "secret_values_recorded": False,
        }
        if receipt_version == "idol_image_generation_execution_receipt.v4":
            receipt["request_schema_version"] = request["schema_version"]
            receipt["reference_role_plan_sha256"] = value_sha256(request["reference_role_plan"])
            if request.get("section_cohort_id") is not None:
                receipt["section_cohort_id"] = request["section_cohort_id"]
        validate_execution_receipt(receipt, request, context, image_bytes, provider)
        receipt_path = write_output(context["output_path"], image_bytes, receipt)
        print(json.dumps({"ok": True, "output_path": relative(context["output_path"]), "receipt_path": relative(receipt_path), "output_count": 1, "status": "generated_pending_pixel_review"}, ensure_ascii=False, indent=2, sort_keys=True))
        return 0
    except ExecutionError as error:
        print(f"image generation execution failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
