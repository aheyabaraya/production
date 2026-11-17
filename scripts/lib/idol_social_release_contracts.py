"""Shared fail-closed contracts for IDOL social release automation.

This module performs local path ownership, content scope, SHA-256, and
schema-backed Founder approval checks.  It never performs network I/O.
"""

from __future__ import annotations

import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

try:
    import jsonschema
except ImportError as exc:  # pragma: no cover - environment guard
    raise SystemExit(
        "Missing dependency: jsonschema. Run with scripts/idol-video-python."
    ) from exc

try:
    import yaml
except ImportError as exc:  # pragma: no cover - environment guard
    raise SystemExit(
        "Missing dependency: PyYAML. Run with scripts/idol-video-python."
    ) from exc

from lib.idol_run_layout import resolve_run_identity, validate_run_manifest
from lib.idol_post05_trace import (
    CURRENT_PACKAGE_VERSION,
    POST05_MUTATION_BOUNDARY,
    PRODUCTION_GRAPH_TRACE_VERSION,
    canonical_object_sha256,
    normalize_production_graph_trace,
)


SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
APPROVAL_SCHEMA = Path("schemas/platform-release-approval.schema.json")
SOCIAL_SCHEMA = Path("schemas/social-analytics.schema.json")
PACKAGE_SCHEMA = Path("schemas/package.schema.json")
FX_MAP_SCHEMA = Path("schemas/edit-finishing-fx.schema.json")
FX_COMPILE_SCHEMA = Path("schemas/edit-finishing-fx-compile-manifest.schema.json")
FINAL_RENDER_SCHEMA = Path("schemas/edit-render-manifest.schema.json")
LINEAGE_ELIGIBLE_PACKAGE_STATUSES = {
    "packaged_ready_local",
    "ready_for_social_planning",
    "founder_review",
    "approved_for_public_release",
    "final_complete_platform_records_closed",
}
PUBLIC_RELEASE_PACKAGE_STATUSES = {
    "approved_for_public_release",
    "final_complete_platform_records_closed",
}
PUBLIC_METADATA_PLATFORMS = {"tiktok", "youtube", "youtube_shorts", "instagram_reels"}
REQUIRED_PUBLIC_HASHTAGS = ["#AI", "#AIIdol", "#Kpop", "#VirtualIdol", "#Loom"]
QUEUE_EXECUTION_FIELDS = {
    "draft_status",
    "draft_platform_id",
    "draft_url",
    "draft_checked_at",
    "draft_error",
    "draft_verified_status",
    "platform_post_id",
    "published_url",
    "published_at",
    "release_approval_status",
    "release_approval_source",
    "release_approval_artifact",
    "release_approval_artifact_sha256",
    "release_approval_queue_sha256",
    "release_approval_action",
    "release_approval_updated_at",
    "release_approved_at",
    "release_asset_sha256",
    "release_provenance_version",
    "release_package_contract",
    "release_package_contract_sha256",
    "release_package_deliverable_manifest_sha256",
    "release_package_output_id",
    "release_package_output_role",
    "release_package_linkage",
    "release_production_graph_trace_sha256",
    "release_edit_segment_ids",
    "release_screen_progression_node_ids",
    "release_section_ids",
    "release_asset_snapshot",
    "release_asset_snapshot_sha256",
    "release_api_upload_quality_profile",
    "release_api_upload_quality_receipt",
    "release_api_upload_quality_receipt_sha256",
    "upload_attempt_id",
    "upload_attempt_record",
    "draft_attempt_reconciliation_required",
    "manual_upload_package",
    "publishing_plan",
}


class SocialContractError(RuntimeError):
    """Raised before any write or network action when release scope is unsafe."""


def resolve_path(repo_root: Path, value: str | Path) -> Path:
    path = Path(value)
    if not path.is_absolute():
        path = repo_root / path
    return path.resolve()


def repo_relative(repo_root: Path, value: str | Path) -> str:
    path = resolve_path(repo_root, value)
    try:
        return path.relative_to(repo_root.resolve()).as_posix()
    except ValueError as exc:
        raise SocialContractError(f"path is outside the IDOL repository: {path}") from exc


def require_within(path: Path, owner: Path, label: str) -> None:
    try:
        path.resolve().relative_to(owner.resolve())
    except ValueError as exc:
        raise SocialContractError(f"{label} must stay under {owner}: {path}") from exc


def validate_run_scope(repo_root: Path, run_root: str | Path, content_id: str) -> tuple[Path, str]:
    repo_root = repo_root.resolve()
    run_path = resolve_path(repo_root, run_root)
    require_within(run_path, repo_root, "run root")
    run_rel = repo_relative(repo_root, run_path)
    if not run_path.is_dir():
        raise SocialContractError(f"run root is not a readable directory: {run_rel}")
    identity_errors = validate_run_manifest(run_path, repo_root)
    if identity_errors:
        raise SocialContractError("; ".join(identity_errors))
    identity = resolve_run_identity(run_path, repo_root)
    if identity["content_id"] != content_id:
        raise SocialContractError(
            f"content_id {content_id!r} does not match run identity "
            f"{identity['content_id']!r}"
        )
    return run_path, run_rel


def validate_run_owned_path(
    repo_root: Path,
    run_path: Path,
    value: str | Path,
    label: str,
    *,
    must_exist: bool,
    file_only: bool = False,
) -> Path:
    path = resolve_path(repo_root, value)
    require_within(path, run_path, label)
    if must_exist and not path.exists():
        raise SocialContractError(f"{label} is not readable: {repo_relative(repo_root, path)}")
    if must_exist and file_only and not path.is_file():
        raise SocialContractError(f"{label} must be a file: {repo_relative(repo_root, path)}")
    return path


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _hashtag_key(value: Any) -> str:
    return str(value).strip().lower().replace(" ", "")


def queue_approval_sha256(rows: list[dict[str, Any]]) -> str:
    """Hash action-bearing queue truth while ignoring result/projection fields.

    Required public hashtags are normalized exactly as the uploader will apply
    them, so the approval digest binds the effective draft metadata rather than
    a weaker preflight copy.
    """

    projected: list[dict[str, Any]] = []
    for source in rows:
        row = {key: value for key, value in source.items() if key not in QUEUE_EXECUTION_FIELDS}
        if row.get("platform") in PUBLIC_METADATA_PLATFORMS:
            tags = [str(tag).strip() for tag in (row.get("hashtags") or []) if str(tag).strip()]
            seen = {_hashtag_key(tag) for tag in tags}
            for required in REQUIRED_PUBLIC_HASHTAGS:
                if _hashtag_key(required) not in seen:
                    tags.append(required)
                    seen.add(_hashtag_key(required))
            row["hashtags"] = tags
            caption = str(row.get("caption") or "").rstrip()
            caption_keys = {part.lower() for part in caption.replace("\n", " ").split()}
            missing = [tag for tag in tags if tag.lower() not in caption_keys]
            if missing:
                tag_line = " ".join(missing)
                row["caption"] = (caption + "\n\n" + tag_line).strip() if caption else tag_line
        projected.append(row)
    payload = json.dumps(projected, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def load_structured(path: Path) -> dict[str, Any]:
    if path.suffix.lower() == ".json":
        value = json.loads(path.read_text(encoding="utf-8"))
    else:
        value = yaml.safe_load(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise SocialContractError(f"structured artifact must be an object: {path}")
    return value


def load_jsonl(path: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    seen: set[str] = set()
    for line_no, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if not line.strip():
            continue
        try:
            row = json.loads(line)
        except json.JSONDecodeError as exc:
            raise SocialContractError(f"invalid JSONL at {path}:{line_no}: {exc}") from exc
        if not isinstance(row, dict):
            raise SocialContractError(f"queue row must be an object at {path}:{line_no}")
        post_id = str(row.get("post_id") or "")
        if not post_id:
            raise SocialContractError(f"queue row is missing post_id at {path}:{line_no}")
        if post_id in seen:
            raise SocialContractError(f"duplicate post_id in run queue: {post_id}")
        seen.add(post_id)
        rows.append(row)
    if not rows:
        raise SocialContractError(f"run-owned queue has no rows: {path}")
    return rows


def validate_queue_scope(
    repo_root: Path,
    run_path: Path,
    content_id: str,
    queue: str | Path,
) -> tuple[Path, list[dict[str, Any]], str]:
    queue_path = validate_run_owned_path(
        repo_root, run_path, queue, "queue", must_exist=True, file_only=True
    )
    rows = load_jsonl(queue_path)
    foreign = sorted(
        {
            str(row.get("content_id") or "<missing>")
            for row in rows
            if str(row.get("content_id") or "") != content_id
        }
    )
    if foreign:
        raise SocialContractError(
            "run-owned queue may contain only the requested content_id; found: "
            + ", ".join(foreign)
        )
    social_schema = json.loads((repo_root / SOCIAL_SCHEMA).read_text(encoding="utf-8"))
    row_schema = {
        "$schema": social_schema.get("$schema", "https://json-schema.org/draft/2020-12/schema"),
        "$ref": "#/$defs/platform_post",
        "$defs": social_schema.get("$defs") or {},
    }
    validator_cls = jsonschema.validators.validator_for(row_schema)
    validator_cls.check_schema(row_schema)
    validator = validator_cls(row_schema, format_checker=jsonschema.FormatChecker())
    row_errors: list[str] = []
    for index, row in enumerate(rows):
        for error in validator.iter_errors(row):
            location = "$" if not error.absolute_path else "$." + ".".join(
                map(str, error.absolute_path)
            )
            row_errors.append(f"row[{index}] {location}: {error.message}")
    if row_errors:
        raise SocialContractError("run-owned queue schema failure: " + "; ".join(row_errors))
    rows_by_id = {str(row["post_id"]): row for row in rows}
    relation_errors: list[str] = []
    for index, row in enumerate(rows):
        post_id = str(row["post_id"])
        for field in ("shared_media_source_post_id", "reply_to_post_id"):
            source_id = str(row.get(field) or "").strip()
            if not source_id:
                continue
            if source_id == post_id:
                relation_errors.append(f"row[{index}] {field} cannot reference the same post_id")
                continue
            source = rows_by_id.get(source_id)
            if source is None:
                relation_errors.append(
                    f"row[{index}] {field} {source_id!r} is absent from the same run-owned queue"
                )
            elif str(source.get("content_id") or "") != content_id:
                relation_errors.append(f"row[{index}] {field} must stay inside content_id {content_id}")
    if relation_errors:
        raise SocialContractError("run-owned queue relation failure: " + "; ".join(relation_errors))
    return queue_path, rows, queue_approval_sha256(rows)


def validate_schema(document: dict[str, Any], schema_path: Path, *, label: str) -> None:
    schema = json.loads(schema_path.read_text(encoding="utf-8"))
    validator_cls = jsonschema.validators.validator_for(schema)
    validator_cls.check_schema(schema)
    errors = sorted(validator_cls(schema).iter_errors(document), key=lambda err: list(err.absolute_path))
    if not errors:
        return
    details = []
    for error in errors:
        location = "$" if not error.absolute_path else "$." + ".".join(map(str, error.absolute_path))
        details.append(f"{location}: {error.message}")
    raise SocialContractError(f"{label} schema failure: " + "; ".join(details))


def _resolve_artifact_binding(
    *,
    repo_root: Path,
    run_path: Path,
    owner_path: Path,
    binding: Any,
    label: str,
    run_owned: bool = True,
) -> tuple[Path, str]:
    if not isinstance(binding, dict):
        raise SocialContractError(f"{label} must be a path/SHA-256 binding")
    value = str(binding.get("path") or "")
    declared_sha = str(binding.get("sha256") or "").lower()
    if not value or not SHA256_RE.fullmatch(declared_sha):
        raise SocialContractError(f"{label} must declare a readable path and lowercase SHA-256")
    raw = Path(value)
    if raw.is_absolute():
        path = raw.resolve()
    elif raw.parts and raw.parts[0] in {
        "runs",
        "automation",
        "schemas",
        "scripts",
        "skills",
    }:
        path = (repo_root / raw).resolve()
    else:
        local = (owner_path.parent / raw).resolve()
        path = local if local.exists() else (repo_root / raw).resolve()
    require_within(path, repo_root, label)
    if run_owned:
        require_within(path, run_path, label)
    if not path.is_file():
        raise SocialContractError(f"{label} is not readable: {repo_relative(repo_root, path)}")
    actual_sha = sha256_file(path)
    if actual_sha != declared_sha:
        raise SocialContractError(
            f"{label} SHA-256 mismatch: expected {declared_sha}, got {actual_sha}"
        )
    return path, actual_sha


def _require_same_binding(
    *,
    repo_root: Path,
    run_path: Path,
    owner_path: Path,
    binding: Any,
    expected_path: Path,
    expected_sha: str,
    label: str,
) -> Path:
    path, digest = _resolve_artifact_binding(
        repo_root=repo_root,
        run_path=run_path,
        owner_path=owner_path,
        binding=binding,
        label=label,
    )
    if path != expected_path.resolve() or digest != expected_sha:
        raise SocialContractError(f"{label} does not match the owning package lineage")
    return path


def _validate_typed_package_ref(
    *,
    repo_root: Path,
    run_path: Path,
    source_contracts: dict[str, Any],
    field: str,
    schema_path: Path,
) -> tuple[Path, str, dict[str, Any]]:
    ref = source_contracts.get(field)
    if not isinstance(ref, dict):
        raise SocialContractError(f"source_contracts.{field} must be a typed artifact reference")
    path = validate_run_owned_path(
        repo_root,
        run_path,
        str(ref.get("path") or ""),
        f"source_contracts.{field}",
        must_exist=True,
        file_only=True,
    )
    declared_sha = str(ref.get("sha256") or "").lower()
    if not SHA256_RE.fullmatch(declared_sha):
        raise SocialContractError(f"source_contracts.{field}.sha256 must be lowercase SHA-256")
    actual_sha = sha256_file(path)
    if actual_sha != declared_sha:
        raise SocialContractError(
            f"source_contracts.{field}.sha256 is stale or mismatched"
        )
    artifact = load_structured(path)
    validate_schema(artifact, repo_root / schema_path, label=f"source_contracts.{field}")
    if str(artifact.get("schema_version") or "") != str(ref.get("schema_version") or ""):
        raise SocialContractError(
            f"source_contracts.{field}.schema_version does not match the referenced artifact"
        )
    return path, actual_sha, artifact


def validate_final_package_lineage(
    *,
    repo_root: Path,
    run_path: Path,
    content_id: str,
    document: dict[str, Any],
) -> dict[str, Any]:
    """Revalidate the exact 04FX -> compile -> final-render -> 05 byte chain."""

    source_contracts = document.get("source_contracts")
    if not isinstance(source_contracts, dict):
        raise SocialContractError("05-package.yaml source_contracts must be a mapping")

    edit_map_value = str(source_contracts.get("edit_map") or "")
    edit_map_path = validate_run_owned_path(
        repo_root,
        run_path,
        edit_map_value,
        "source_contracts.edit_map",
        must_exist=True,
        file_only=True,
    )
    if edit_map_path != (run_path / "04-edit-map.yaml").resolve():
        raise SocialContractError("source_contracts.edit_map must be the exact run-root 04-edit-map.yaml")
    closeout_validator = (repo_root / "scripts" / "validate_edit_map_readiness.rb").resolve()
    if not closeout_validator.is_file():
        raise SocialContractError("missing 04 closeout semantic validator")
    closeout = subprocess.run(
        ["ruby", str(closeout_validator), "--mode", "closeout", str(edit_map_path)],
        cwd=repo_root,
        text=True,
        capture_output=True,
    )
    if closeout.returncode:
        detail = (closeout.stdout or closeout.stderr).strip()
        raise SocialContractError(f"04 closeout semantic validation failed: {detail}")

    fx_path, fx_sha, fx_map = _validate_typed_package_ref(
        repo_root=repo_root,
        run_path=run_path,
        source_contracts=source_contracts,
        field="finishing_fx_map",
        schema_path=FX_MAP_SCHEMA,
    )
    compile_path, compile_sha, compile_manifest = _validate_typed_package_ref(
        repo_root=repo_root,
        run_path=run_path,
        source_contracts=source_contracts,
        field="finishing_fx_compile_manifest",
        schema_path=FX_COMPILE_SCHEMA,
    )
    render_path, _render_sha, render_manifest = _validate_typed_package_ref(
        repo_root=repo_root,
        run_path=run_path,
        source_contracts=source_contracts,
        field="final_render_manifest",
        schema_path=FINAL_RENDER_SCHEMA,
    )

    if str(fx_map.get("content_id") or "") != content_id:
        raise SocialContractError("04FX map content_id does not match the package")
    if fx_map.get("status") != "passed_for_final_render":
        raise SocialContractError("04FX map is not passed_for_final_render")
    if (fx_map.get("preview_gate") or {}).get("gate_type") != "full_master":
        raise SocialContractError("final package requires a full_master 04FX preview gate")
    audit_status = str(
        (fx_map.get("transition_opportunity_audit") or {}).get("audit_status") or ""
    )
    if audit_status not in {"complete_no_fx_needed", "complete_fx_passed"}:
        raise SocialContractError("04FX transition-opportunity audit is not final")
    fx_edit_map_value = str(fx_map.get("source_edit_map") or "")
    raw_fx_edit_map = Path(fx_edit_map_value)
    if raw_fx_edit_map.is_absolute():
        fx_edit_map_path = raw_fx_edit_map.resolve()
    elif raw_fx_edit_map.parts and raw_fx_edit_map.parts[0] == "runs":
        fx_edit_map_path = (repo_root / raw_fx_edit_map).resolve()
    else:
        fx_edit_map_path = (run_path / raw_fx_edit_map).resolve()
    require_within(fx_edit_map_path, run_path, "04FX source edit map")
    if fx_edit_map_path != edit_map_path:
        raise SocialContractError("04FX map source_edit_map does not point to the package edit map")

    if compile_manifest.get("compile_mode") != "final_pass_only":
        raise SocialContractError("04FX compile manifest is not final_pass_only")
    compile_bindings = compile_manifest.get("source_bindings") or {}
    _require_same_binding(
        repo_root=repo_root,
        run_path=run_path,
        owner_path=compile_path,
        binding=compile_bindings.get("fx_map"),
        expected_path=fx_path,
        expected_sha=fx_sha,
        label="04FX compile source FX map",
    )
    _source_recipe_path, source_recipe_sha = _resolve_artifact_binding(
        repo_root=repo_root,
        run_path=run_path,
        owner_path=compile_path,
        binding=compile_bindings.get("recipe"),
        label="04FX compile source recipe",
    )
    registry_path, _registry_sha = _resolve_artifact_binding(
        repo_root=repo_root,
        run_path=run_path,
        owner_path=compile_path,
        binding=compile_bindings.get("effect_registry"),
        label="04FX effect registry",
        run_owned=False,
    )
    if registry_path != (repo_root / "automation" / "edit-effect-registry.yaml").resolve():
        raise SocialContractError("04FX compile manifest must bind the canonical effect registry")
    if str((fx_map.get("dependency_lock") or {}).get("source_recipe_sha256") or "") != source_recipe_sha:
        raise SocialContractError("04FX map does not bind the compile source recipe bytes")

    selection = compile_manifest.get("selection") or {}
    selected_ids = list(selection.get("selected_pass_fx_ids") or [])
    compiled_ids = list(selection.get("compiled_fx_ids") or [])
    if selection.get("audit_status") != audit_status:
        raise SocialContractError("04FX compile audit status does not match the audited FX map")
    if selected_ids != compiled_ids or list(selection.get("skipped_pass_fx_ids") or []):
        raise SocialContractError("04FX final compile did not include every selected passed FX record")
    if audit_status == "complete_no_fx_needed" and compiled_ids:
        raise SocialContractError("complete_no_fx_needed must compile zero 04FX records")
    if audit_status == "complete_fx_passed" and not compiled_ids:
        raise SocialContractError("complete_fx_passed must compile at least one 04FX record")

    compiled_output = compile_manifest.get("compiled_output") or {}
    if compiled_output.get("kind") != "merged_recipe":
        raise SocialContractError("final 04FX compile output must be a merged recipe")
    compiled_recipe_path, compiled_recipe_sha = _resolve_artifact_binding(
        repo_root=repo_root,
        run_path=run_path,
        owner_path=compile_path,
        binding=compiled_output,
        label="04FX compiled final recipe",
    )
    compiled_recipe = load_structured(compiled_recipe_path)
    if compiled_recipe.get("schema_version") != "idol_edit_recipe.v3":
        raise SocialContractError("04FX compiled output must be idol_edit_recipe.v3")
    if str(compiled_recipe.get("content_id") or "") != content_id:
        raise SocialContractError("04FX compiled recipe content_id does not match the package")
    recipe_edit_binding = compiled_recipe.get("source_edit_map")
    if not isinstance(recipe_edit_binding, dict):
        raise SocialContractError("compiled recipe must bind the historical source_edit_map")
    raw_recipe_edit_map = Path(str(recipe_edit_binding.get("path") or ""))
    if raw_recipe_edit_map.is_absolute():
        recipe_edit_map_path = raw_recipe_edit_map.resolve()
    elif raw_recipe_edit_map.parts and raw_recipe_edit_map.parts[0] == "runs":
        recipe_edit_map_path = (repo_root / raw_recipe_edit_map).resolve()
    else:
        recipe_edit_map_path = (run_path / raw_recipe_edit_map).resolve()
    require_within(recipe_edit_map_path, run_path, "compiled recipe source_edit_map")
    if recipe_edit_map_path != edit_map_path:
        raise SocialContractError(
            "compiled recipe source_edit_map does not point to the exact package edit map"
        )
    historical_edit_map_sha = str(recipe_edit_binding.get("sha256") or "").lower()
    if not SHA256_RE.fullmatch(historical_edit_map_sha):
        raise SocialContractError("compiled recipe source_edit_map historical SHA-256 is invalid")
    if historical_edit_map_sha != str(
        (fx_map.get("dependency_lock") or {}).get("source_edit_map_sha256") or ""
    ):
        raise SocialContractError(
            "compiled recipe and 04FX map disagree on the historical pre-render edit-map digest"
        )
    legacy_final_recipe = str(source_contracts.get("final_recipe") or "")
    if legacy_final_recipe:
        legacy_final_recipe_path = validate_run_owned_path(
            repo_root,
            run_path,
            legacy_final_recipe,
            "source_contracts.final_recipe",
            must_exist=True,
            file_only=True,
        )
        if legacy_final_recipe_path != compiled_recipe_path:
            raise SocialContractError(
                "deprecated source_contracts.final_recipe does not match the canonical compiled final recipe"
            )
    for supporting_field in ("final_qc_review", "closeout_review"):
        supporting_value = str(source_contracts.get(supporting_field) or "")
        if supporting_value:
            validate_run_owned_path(
                repo_root,
                run_path,
                supporting_value,
                f"source_contracts.{supporting_field} supporting record",
                must_exist=True,
                file_only=True,
            )
    compile_validator = (
        repo_root / "scripts" / "validate_edit_finishing_fx_compile.py"
    ).resolve()
    if not compile_validator.is_file():
        raise SocialContractError("missing deterministic 04FX compile validator")
    compile_validation = subprocess.run(
        [
            sys.executable,
            str(compile_validator),
            str(compile_path),
            "--expect-output",
            str(compiled_recipe_path),
            "--require-final",
            "--immutable-receipt",
        ],
        cwd=repo_root,
        text=True,
        capture_output=True,
    )
    if compile_validation.returncode:
        detail = (compile_validation.stdout or compile_validation.stderr).strip()
        raise SocialContractError(
            f"deterministic 04FX compile validation failed: {detail}"
        )
    effects = compiled_recipe.get("effects") or []
    if not isinstance(effects, list):
        raise SocialContractError("04FX compiled recipe effects must be an array")
    compiled_04fx = [
        effect
        for effect in effects
        if isinstance(effect, dict) and effect.get("origin") == "04fx"
    ]
    if canonical_object_sha256(compiled_04fx) != str(compiled_output.get("compiled_effects_sha256") or ""):
        raise SocialContractError("04FX compiled effect-list digest is stale or mismatched")
    if canonical_object_sha256(effects) != str(compiled_output.get("merged_effects_sha256") or ""):
        raise SocialContractError("04FX merged effect-list digest is stale or mismatched")
    if len(effects) != compiled_output.get("total_effect_count") or len(compiled_04fx) != compiled_output.get("compiled_04fx_count"):
        raise SocialContractError("04FX compiled effect counts are stale or mismatched")

    if render_manifest.get("profile") != "final":
        raise SocialContractError("final render manifest profile must be final")
    render_bindings = render_manifest.get("source_bindings") or {}
    _require_same_binding(
        repo_root=repo_root,
        run_path=run_path,
        owner_path=render_path,
        binding=render_bindings.get("fx_compile_manifest"),
        expected_path=compile_path,
        expected_sha=compile_sha,
        label="final render 04FX compile manifest",
    )
    _require_same_binding(
        repo_root=repo_root,
        run_path=run_path,
        owner_path=render_path,
        binding=render_bindings.get("recipe"),
        expected_path=compiled_recipe_path,
        expected_sha=compiled_recipe_sha,
        label="final render recipe",
    )
    audio_path, audio_sha = _resolve_artifact_binding(
        repo_root=repo_root,
        run_path=run_path,
        owner_path=render_path,
        binding=render_bindings.get("audio"),
        label="final render audio",
    )
    recipe_audio = compiled_recipe.get("audio_program") or {}
    if isinstance(recipe_audio, dict) and recipe_audio.get("path"):
        _require_same_binding(
            repo_root=repo_root,
            run_path=run_path,
            owner_path=compiled_recipe_path,
            binding=recipe_audio,
            expected_path=audio_path,
            expected_sha=audio_sha,
            label="compiled recipe audio program",
        )

    output_path, output_sha = _resolve_artifact_binding(
        repo_root=repo_root,
        run_path=run_path,
        owner_path=render_path,
        binding=render_manifest.get("output"),
        label="final render output",
    )
    expected_frames = (render_manifest.get("render_spec") or {}).get("expected_frame_count")
    if (render_manifest.get("output") or {}).get("frame_count") != expected_frames:
        raise SocialContractError("final render receipt frame count is not the complete program frame count")
    final_master = document.get("final_master")
    if not isinstance(final_master, dict):
        raise SocialContractError("final-ready 05 package requires a hash-bound final_master")
    master_path = validate_run_owned_path(
        repo_root,
        run_path,
        str(final_master.get("path") or ""),
        "05 final_master",
        must_exist=True,
        file_only=True,
    )
    master_sha = str(final_master.get("sha256") or "").lower()
    if master_path != output_path or master_sha != output_sha or sha256_file(master_path) != master_sha:
        raise SocialContractError("05 final_master does not match the exact final render output")
    return {
        "edit_map_path": edit_map_path,
        "compiled_recipe_path": compiled_recipe_path,
        "compiled_recipe_sha256": compiled_recipe_sha,
    }


def validate_approval_artifact(
    *,
    repo_root: Path,
    run_path: Path,
    run_rel: str,
    content_id: str,
    queue_path: Path,
    queue_rows: list[dict[str, Any]],
    queue_sha256: str,
    package_contract_path: Path,
    package_contract_sha256: str,
    package_deliverable_manifest_sha256: str,
    artifact: str | Path,
    expected_sha256: str,
    required_action: str,
) -> tuple[Path, dict[str, Any], str]:
    approval_path = validate_run_owned_path(
        repo_root, run_path, artifact, "Founder approval artifact", must_exist=True, file_only=True
    )
    approval_rel_to_run = approval_path.relative_to(run_path)
    if (
        not approval_rel_to_run.parts
        or approval_rel_to_run.parts[0] != "review"
        or not approval_path.name.startswith("platform-release-approval-")
        or approval_path.suffix.lower() not in {".yaml", ".yml", ".json"}
    ):
        raise SocialContractError(
            "Founder approval artifact must be review/platform-release-approval-vN.yaml|json"
        )
    normalized_expected = str(expected_sha256 or "").strip().lower()
    if not SHA256_RE.fullmatch(normalized_expected):
        raise SocialContractError("--approval-sha256 must be an explicit 64-character SHA-256")
    actual_sha = sha256_file(approval_path)
    if actual_sha != normalized_expected:
        raise SocialContractError(
            f"Founder approval artifact hash mismatch: expected {normalized_expected}, got {actual_sha}"
        )
    document = load_structured(approval_path)
    validate_schema(
        document,
        repo_root / APPROVAL_SCHEMA,
        label="Founder approval artifact",
    )
    if document.get("status") != "active":
        raise SocialContractError("Founder approval artifact is not active")
    if document.get("founder_explicit_approval") is not True:
        raise SocialContractError("Founder approval artifact lacks explicit approval")
    if str(document.get("run_root") or "") != run_rel:
        raise SocialContractError("Founder approval artifact run_root does not match --run-root")
    if str(document.get("content_id") or "") != content_id:
        raise SocialContractError("Founder approval artifact content_id does not match --content-id")
    queue_rel = repo_relative(repo_root, queue_path)
    if str(document.get("queue_path") or "") != queue_rel:
        raise SocialContractError("Founder approval artifact queue_path does not match --queue")
    if str(document.get("queue_sha256") or "").lower() != queue_sha256:
        raise SocialContractError("Founder approval artifact queue_sha256 is stale or mismatched")
    validated_package_path = validate_run_owned_path(
        repo_root,
        run_path,
        package_contract_path,
        "05 package contract",
        must_exist=True,
        file_only=True,
    )
    if validated_package_path != (run_path / "05-package.yaml").resolve():
        raise SocialContractError(
            "Founder approval validation requires the exact run-root 05-package.yaml"
        )
    normalized_package_sha = str(package_contract_sha256 or "").strip().lower()
    if not SHA256_RE.fullmatch(normalized_package_sha):
        raise SocialContractError("package contract SHA-256 must be 64 lowercase hex characters")
    if sha256_file(validated_package_path) != normalized_package_sha:
        raise SocialContractError("05-package.yaml changed before Founder approval validation")
    normalized_manifest_sha = str(package_deliverable_manifest_sha256 or "").strip().lower()
    if not SHA256_RE.fullmatch(normalized_manifest_sha):
        raise SocialContractError(
            "package deliverable manifest SHA-256 must be 64 lowercase hex characters"
        )
    package_rel = repo_relative(repo_root, validated_package_path)
    if str(document.get("package_contract_path") or "") != package_rel:
        raise SocialContractError(
            "Founder approval artifact package_contract_path does not match the exact run-root 05-package.yaml"
        )
    if (
        str(document.get("package_contract_sha256") or "").lower()
        != normalized_package_sha
    ):
        raise SocialContractError(
            "Founder approval artifact package_contract_sha256 is stale or mismatched"
        )
    if (
        str(document.get("package_deliverable_manifest_sha256") or "").lower()
        != normalized_manifest_sha
    ):
        raise SocialContractError(
            "Founder approval artifact package deliverable manifest is stale or mismatched"
        )
    if required_action not in set(document.get("allowed_actions") or []):
        raise SocialContractError(
            f"Founder approval artifact does not allow action {required_action!r}"
        )
    approved_post_ids = set(document.get("approved_post_ids") or [])
    queue_by_id = {str(row.get("post_id") or ""): row for row in queue_rows}
    missing_post_ids = sorted(approved_post_ids - set(queue_by_id))
    if missing_post_ids:
        raise SocialContractError(
            "Founder approval artifact names post IDs absent from the exact queue: "
            + ", ".join(missing_post_ids)
        )
    approved_platforms = set(document.get("approved_platforms") or [])
    post_platforms = {
        str(queue_by_id[post_id].get("platform") or "") for post_id in approved_post_ids
    }
    if approved_platforms != post_platforms:
        raise SocialContractError(
            "Founder approval artifact approved_platforms must exactly match the "
            "platforms of approved_post_ids"
        )
    asset_records = document.get("approved_assets") or []
    asset_post_ids = [str(item.get("post_id") or "") for item in asset_records]
    if len(asset_post_ids) != len(set(asset_post_ids)):
        raise SocialContractError("Founder approval artifact has duplicate approved_assets post_id")
    if set(asset_post_ids) != approved_post_ids:
        raise SocialContractError(
            "Founder approval artifact approved_assets must cover exactly approved_post_ids"
        )
    for record in asset_records:
        post_id = str(record.get("post_id") or "")
        row = queue_by_id.get(post_id)
        if row is None:
            raise SocialContractError(f"approved asset post_id is absent from queue: {post_id}")
        asset_path = validate_run_owned_path(
            repo_root,
            run_path,
            str(row.get("asset_or_clip") or ""),
            f"approved asset for {post_id}",
            must_exist=True,
            file_only=True,
        )
        asset_rel = repo_relative(repo_root, asset_path)
        if str(record.get("path") or "") != asset_rel:
            raise SocialContractError(f"approved asset path does not match queue row for {post_id}")
        expected_asset_sha = str(record.get("sha256") or "").lower()
        actual_asset_sha = sha256_file(asset_path)
        if actual_asset_sha != expected_asset_sha:
            raise SocialContractError(
                f"approved asset SHA-256 mismatch for {post_id}: expected {expected_asset_sha}, got {actual_asset_sha}"
            )
    return approval_path, document, actual_sha


def package_deliverables(document: dict[str, Any]) -> list[dict[str, Any]]:
    deliverables: list[dict[str, Any]] = []
    final_master = document.get("final_master")
    if isinstance(final_master, dict):
        deliverables.append(final_master)
    for value in (document.get("package_outputs") or {}).values():
        if isinstance(value, list):
            deliverables.extend(
                item for item in value if isinstance(item, dict) and item.get("output_id")
            )
        elif isinstance(value, dict) and value.get("output_id"):
            deliverables.append(value)
    return deliverables


def validate_package_graph_trace(
    *,
    repo_root: Path,
    run_path: Path,
    package_path: Path,
    content_id: str,
    document: dict[str, Any],
    deliverables: list[dict[str, Any]],
) -> dict[str, Any]:
    """Validate the exact 05 output -> 04 segment -> screen-node edge.

    This is structural and byte-level provenance only. It never judges an edit,
    grants release, or permits post-05 evidence to rewrite the 04 sources.
    """

    if str(document.get("schema_version") or "") != CURRENT_PACKAGE_VERSION:
        raise SocialContractError(
            "post-05 projection requires idol_package.v2 with production_graph_trace; "
            "idol_package.v1 is compatibility-read-only through its isolated legacy schema"
        )
    trace = document.get("production_graph_trace")
    if not isinstance(trace, dict):
        raise SocialContractError("05-package.yaml production_graph_trace must be an object")
    if trace.get("schema_version") != PRODUCTION_GRAPH_TRACE_VERSION:
        raise SocialContractError("05-package.yaml production_graph_trace version is not active")
    if trace.get("post05_mutation_boundary") != POST05_MUTATION_BOUNDARY:
        raise SocialContractError("05-package.yaml post-05 mutation boundary is missing or changed")

    edit_map_path, edit_map_sha = _resolve_artifact_binding(
        repo_root=repo_root,
        run_path=run_path,
        owner_path=package_path,
        binding=trace.get("source_edit_map"),
        label="production_graph_trace.source_edit_map",
    )
    if edit_map_path != (run_path / "04-edit-map.yaml").resolve():
        raise SocialContractError(
            "production_graph_trace.source_edit_map must be the exact run-root 04-edit-map.yaml"
        )
    if str((trace.get("source_edit_map") or {}).get("path") or "") != repo_relative(
        repo_root, edit_map_path
    ):
        raise SocialContractError(
            "production_graph_trace.source_edit_map.path must be repository-relative"
        )
    edit_map = load_structured(edit_map_path)
    if edit_map.get("schema_version") != "idol_edit_map.v4":
        raise SocialContractError("production graph source edit map must be idol_edit_map.v4")
    if str(edit_map.get("content_id") or "") != content_id:
        raise SocialContractError("production graph source edit map content_id does not match")

    recipe_path, recipe_sha = _resolve_artifact_binding(
        repo_root=repo_root,
        run_path=run_path,
        owner_path=package_path,
        binding=trace.get("source_edit_recipe"),
        label="production_graph_trace.source_edit_recipe",
    )
    if str((trace.get("source_edit_recipe") or {}).get("path") or "") != repo_relative(
        repo_root, recipe_path
    ):
        raise SocialContractError(
            "production_graph_trace.source_edit_recipe.path must be repository-relative"
        )
    recipe = load_structured(recipe_path)
    if recipe.get("schema_version") != "idol_edit_recipe.v3":
        raise SocialContractError("production graph source edit recipe must be idol_edit_recipe.v3")
    if str(recipe.get("content_id") or "") != content_id:
        raise SocialContractError("production graph source edit recipe content_id does not match")

    map_rows = edit_map.get("edit_unit_screen_progression_nodes")
    if not isinstance(map_rows, list) or not map_rows:
        raise SocialContractError(
            "production graph source edit map has no edit_unit_screen_progression_nodes"
        )
    map_by_segment: dict[str, dict[str, Any]] = {}
    for index, row in enumerate(map_rows):
        if not isinstance(row, dict):
            raise SocialContractError(
                f"edit_unit_screen_progression_nodes[{index}] must be an object"
            )
        segment_id = str(row.get("edit_unit_id") or "")
        if not segment_id:
            raise SocialContractError(
                f"edit_unit_screen_progression_nodes[{index}].edit_unit_id is missing"
            )
        if segment_id in map_by_segment:
            raise SocialContractError(
                f"production graph edit map has duplicate edit_unit_id: {segment_id}"
            )
        map_by_segment[segment_id] = row

    timeline = recipe.get("timeline")
    if not isinstance(timeline, list) or not timeline:
        raise SocialContractError("production graph source edit recipe has no timeline")
    segment_facts: dict[str, dict[str, Any]] = {}
    timeline_order: dict[str, int] = {}
    compared_node_fields = (
        "screen_progression_map_id",
        "screen_progression_node_id",
        "section_id",
        "major_scene_id",
        "core_cut_id",
        "branch_cut_ids",
        "source_03v_cue_ids",
        "storyline_role",
        "observable_screen_proof",
    )
    for index, segment in enumerate(timeline):
        if not isinstance(segment, dict):
            raise SocialContractError(f"edit recipe timeline[{index}] must be an object")
        segment_id = str(segment.get("segment_id") or "")
        if not segment_id:
            raise SocialContractError(f"edit recipe timeline[{index}].segment_id is missing")
        if segment_id in segment_facts:
            raise SocialContractError(f"production graph recipe has duplicate segment_id: {segment_id}")
        node = segment.get("screen_progression_node")
        if not isinstance(node, dict):
            raise SocialContractError(
                f"edit recipe timeline segment {segment_id} has no screen_progression_node"
            )
        map_node = map_by_segment.get(segment_id)
        if map_node is None:
            raise SocialContractError(
                f"edit recipe segment {segment_id} is absent from 04 edit_unit_screen_progression_nodes"
            )
        mismatches = [field for field in compared_node_fields if node.get(field) != map_node.get(field)]
        if mismatches:
            raise SocialContractError(
                f"edit recipe segment {segment_id} disagrees with 04 screen node fields: "
                + ", ".join(mismatches)
            )
        section_ids = segment.get("section_ids")
        if not isinstance(section_ids, list) or not section_ids:
            raise SocialContractError(f"edit recipe segment {segment_id} has no section_ids")
        normalized_sections = sorted({str(value) for value in section_ids if str(value)})
        node_section = str(node.get("section_id") or "")
        if not node_section or node_section not in normalized_sections:
            raise SocialContractError(
                f"edit recipe segment {segment_id} section_ids omit its screen node section"
            )
        node_id = str(node.get("screen_progression_node_id") or "")
        if not node_id:
            raise SocialContractError(
                f"edit recipe segment {segment_id} has no screen_progression_node_id"
            )
        segment_facts[segment_id] = {
            "screen_progression_node_id": node_id,
            "section_ids": normalized_sections,
        }
        timeline_order[segment_id] = index

    bindings = trace.get("deliverable_bindings")
    if not isinstance(bindings, list) or not bindings:
        raise SocialContractError("production_graph_trace.deliverable_bindings is empty")
    binding_by_output: dict[str, dict[str, Any]] = {}
    for index, binding in enumerate(bindings):
        if not isinstance(binding, dict):
            raise SocialContractError(f"deliverable_bindings[{index}] must be an object")
        output_id = str(binding.get("output_id") or "")
        if not output_id:
            raise SocialContractError(f"deliverable_bindings[{index}].output_id is missing")
        if output_id in binding_by_output:
            raise SocialContractError(f"production graph has duplicate output_id: {output_id}")
        segment_ids = [str(value) for value in (binding.get("edit_segment_ids") or [])]
        if not segment_ids or len(segment_ids) != len(set(segment_ids)):
            raise SocialContractError(
                f"production graph output {output_id} needs unique edit_segment_ids"
            )
        unknown = sorted(set(segment_ids) - set(segment_facts))
        if unknown:
            raise SocialContractError(
                f"production graph output {output_id} names unknown edit segments: "
                + ", ".join(unknown)
            )
        if segment_ids != sorted(segment_ids, key=timeline_order.__getitem__):
            raise SocialContractError(
                f"production graph output {output_id} edit_segment_ids must follow recipe order"
            )
        expected_nodes = sorted(
            {segment_facts[segment_id]["screen_progression_node_id"] for segment_id in segment_ids}
        )
        expected_sections = sorted(
            {
                section_id
                for segment_id in segment_ids
                for section_id in segment_facts[segment_id]["section_ids"]
            }
        )
        declared_nodes = sorted(str(value) for value in (binding.get("screen_progression_node_ids") or []))
        declared_sections = sorted(str(value) for value in (binding.get("section_ids") or []))
        if declared_nodes != expected_nodes:
            raise SocialContractError(
                f"production graph output {output_id} screen_progression_node_ids are not the exact segment projection"
            )
        if declared_sections != expected_sections:
            raise SocialContractError(
                f"production graph output {output_id} section_ids are not the exact segment projection"
            )
        binding_by_output[output_id] = {
            "output_id": output_id,
            "edit_segment_ids": segment_ids,
            "screen_progression_node_ids": expected_nodes,
            "section_ids": expected_sections,
        }

    deliverable_ids = [str(item.get("output_id") or "") for item in deliverables]
    if set(deliverable_ids) != set(binding_by_output):
        missing = sorted(set(deliverable_ids) - set(binding_by_output))
        extra = sorted(set(binding_by_output) - set(deliverable_ids))
        raise SocialContractError(
            "production graph must bind the exact 05 deliverable set "
            f"(missing: {missing or ['none']}; extra: {extra or ['none']})"
        )

    normalized_trace = normalize_production_graph_trace(trace)
    return {
        "edit_map_path": edit_map_path,
        "edit_map_sha256": edit_map_sha,
        "recipe_path": recipe_path,
        "recipe_sha256": recipe_sha,
        "binding_by_output": binding_by_output,
        "normalized_trace": normalized_trace,
        "trace_sha256": canonical_object_sha256(normalized_trace),
    }


def package_deliverable_manifest(
    *,
    repo_root: Path,
    run_path: Path,
    document: dict[str, Any],
    deliverables: list[dict[str, Any]],
) -> dict[str, Any]:
    """Return the compact, deterministic 05 deliverable surface.

    The exact package bytes are bound separately by ``package_contract_sha256``.
    This manifest makes the declared output surface inspectable without hashing
    every unrelated master on every upload retry.  If a deliverable declares a
    file SHA-256, the live file is nevertheless re-hashed and must match.
    """

    locator_fields = (
        "public_url",
        "youtube_url",
        "embed_url",
        "platform_url",
        "platform_id",
        "youtube_id",
    )
    trace = document.get("production_graph_trace")
    trace_bindings = {
        str(binding.get("output_id") or ""): binding
        for binding in ((trace or {}).get("deliverable_bindings") or [])
        if isinstance(binding, dict)
    }
    normalized_trace = None
    trace_sha256 = None
    if isinstance(trace, dict):
        normalized_trace = normalize_production_graph_trace(trace)
        trace_sha256 = canonical_object_sha256(normalized_trace)
    normalized: list[dict[str, Any]] = []
    for item in deliverables:
        output_id = str(item.get("output_id") or "")
        record: dict[str, Any] = {
            "output_id": output_id,
            "role": str(item.get("role") or ""),
        }
        local_value = str(item.get("path") or "")
        if local_value:
            local_path = validate_run_owned_path(
                repo_root,
                run_path,
                local_value,
                f"package deliverable {output_id}",
                must_exist=False,
            )
            record["path"] = repo_relative(repo_root, local_path)
            declared_sha = str(item.get("sha256") or "").lower()
            if declared_sha:
                if not local_path.is_file():
                    raise SocialContractError(
                        f"package deliverable {output_id} declares sha256 but is not a readable file"
                    )
                actual_sha = sha256_file(local_path)
                if actual_sha != declared_sha:
                    raise SocialContractError(
                        f"package deliverable SHA-256 mismatch for {output_id}: expected {declared_sha}, got {actual_sha}"
                    )
                record["sha256"] = declared_sha
        for field in locator_fields:
            value = str(item.get(field) or "")
            if value:
                record[field] = value
        graph_binding = trace_bindings.get(output_id)
        if graph_binding:
            record["edit_segment_ids"] = list(graph_binding.get("edit_segment_ids") or [])
            record["screen_progression_node_ids"] = sorted(
                graph_binding.get("screen_progression_node_ids") or []
            )
            record["section_ids"] = sorted(graph_binding.get("section_ids") or [])
        normalized.append(record)
    normalized.sort(key=lambda item: item["output_id"])
    result = {
        "schema_version": str(document.get("schema_version") or ""),
        "content_id": str(document.get("content_id") or ""),
        "deliverables": normalized,
    }
    if normalized_trace is not None and trace_sha256 is not None:
        result["production_graph_trace_sha256"] = trace_sha256
    return result


def validate_package_contract(
    *,
    repo_root: Path,
    run_path: Path,
    content_id: str,
    package_contract: str | Path,
    allow_closed: bool = False,
    require_final_lineage: bool = True,
) -> tuple[Path, dict[str, Any], list[dict[str, Any]]]:
    """Validate a 05 package for final readiness or a nonpublic draft projection.

    Public-release and closed statuses always revalidate the complete
    04 -> 04FX -> compile -> final-render lineage. Callers may disable that
    lineage only for nonpublic base-package and social-planning work.
    """
    path = validate_run_owned_path(
        repo_root,
        run_path,
        package_contract,
        "05 package contract",
        must_exist=True,
        file_only=True,
    )
    if path != (run_path / "05-package.yaml").resolve():
        raise SocialContractError("--package-contract must be the run-root 05-package.yaml")
    document = load_structured(path)
    validate_schema(document, repo_root / PACKAGE_SCHEMA, label="05 package contract")
    if str(document.get("content_id") or "") != content_id:
        raise SocialContractError("05-package.yaml content_id does not match --content-id")
    status = str(document.get("status") or "")
    blocked_statuses = {
        "draft",
        "blocked",
        "hold",
        "archived",
        "final_complete_platform_records_closed",
    }
    deliverables = package_deliverables(document)
    if not deliverables:
        raise SocialContractError("05-package.yaml declares no deliverables")
    graph_trace = validate_package_graph_trace(
        repo_root=repo_root,
        run_path=run_path,
        package_path=path,
        content_id=content_id,
        document=document,
        deliverables=deliverables,
    )
    final_lineage = None
    if status in PUBLIC_RELEASE_PACKAGE_STATUSES or (
        require_final_lineage and status in LINEAGE_ELIGIBLE_PACKAGE_STATUSES
    ):
        final_lineage = validate_final_package_lineage(
            repo_root=repo_root,
            run_path=run_path,
            content_id=content_id,
            document=document,
        )
    if final_lineage is not None:
        if graph_trace["edit_map_path"] != final_lineage["edit_map_path"]:
            raise SocialContractError("production graph edit map does not match final render lineage")
        if (
            graph_trace["recipe_path"] != final_lineage["compiled_recipe_path"]
            or graph_trace["recipe_sha256"] != final_lineage["compiled_recipe_sha256"]
        ):
            raise SocialContractError(
                "production graph edit recipe does not match the exact compiled final recipe"
            )
    if status in blocked_statuses and not (
        allow_closed and status == "final_complete_platform_records_closed"
    ):
        raise SocialContractError(f"05-package.yaml status is not release-projectable: {status}")
    seen_ids: set[str] = set()
    for deliverable in deliverables:
        output_id = str(deliverable.get("output_id") or "")
        if output_id in seen_ids:
            raise SocialContractError(f"05-package.yaml has duplicate output_id: {output_id}")
        seen_ids.add(output_id)
        local_path = str(deliverable.get("path") or "")
        if local_path:
            validate_run_owned_path(
                repo_root,
                run_path,
                local_path,
                f"package deliverable {output_id}",
                must_exist=False,
            )
    return path, document, deliverables


def validate_queue_asset_linkage(
    *,
    repo_root: Path,
    run_path: Path,
    rows: list[dict[str, Any]],
    deliverables: list[dict[str, Any]],
) -> list[dict[str, str]]:
    by_id = {str(item.get("output_id") or ""): item for item in deliverables}
    local_deliverables: list[tuple[Path, str, str]] = []
    linkage_rows: list[dict[str, str]] = []
    for item in deliverables:
        value = str(item.get("path") or "")
        if value:
            local_deliverables.append(
                (
                    resolve_path(repo_root, value),
                    str(item.get("role") or ""),
                    str(item.get("output_id") or ""),
                )
            )
    for row in rows:
        post_id = str(row.get("post_id") or "<unknown>")
        asset = validate_run_owned_path(
            repo_root,
            run_path,
            str(row.get("asset_or_clip") or ""),
            f"asset_or_clip for {post_id}",
            must_exist=True,
            file_only=True,
        )
        declared_output_id = str(row.get("package_output_id") or "")
        candidates = local_deliverables
        if declared_output_id:
            declared = by_id.get(declared_output_id)
            if declared is None:
                raise SocialContractError(
                    f"{post_id}: package_output_id is absent from 05-package.yaml: {declared_output_id}"
                )
            declared_path = str(declared.get("path") or "")
            candidates = (
                [
                    (
                        resolve_path(repo_root, declared_path),
                        str(declared.get("role") or ""),
                        declared_output_id,
                    )
                ]
                if declared_path
                else []
            )
        matched: tuple[Path, str, str, str] | None = None
        for deliverable_path, role, output_id in candidates:
            if asset == deliverable_path:
                matched = (deliverable_path, role, output_id, "exact_deliverable")
                break
        if matched is None:
            for deliverable_path, role, output_id in candidates:
                if role not in {"platform_upload_package", "manual_upload_package"}:
                    continue
                try:
                    asset.relative_to(deliverable_path)
                except ValueError:
                    continue
                matched = (
                    deliverable_path,
                    role,
                    output_id,
                    "child_of_upload_package",
                )
                break
        if matched is None:
            raise SocialContractError(
                f"{post_id}: asset_or_clip is not a declared 05 deliverable or child of a declared platform/manual upload package"
            )
        deliverable_path, role, output_id, linkage = matched
        linkage_rows.append(
            {
                "post_id": post_id,
                "asset_path": repo_relative(repo_root, asset),
                "asset_sha256": sha256_file(asset),
                "package_output_id": output_id,
                "package_output_role": role,
                "package_output_path": repo_relative(repo_root, deliverable_path),
                "linkage": linkage,
            }
        )
    return linkage_rows


def validate_registry_scope(
    *,
    repo_root: Path,
    run_rel: str,
    content_id: str,
    registry: str | Path,
) -> tuple[Path, dict[str, Any]]:
    path = resolve_path(repo_root, registry)
    catalog_root = (repo_root / "catalog/albums").resolve()
    require_within(path, catalog_root, "title registry")
    if path.name != "output-registry.yaml" or not path.is_file():
        raise SocialContractError(f"title registry is not readable: {repo_relative(repo_root, path)}")
    document = load_structured(path)
    if content_id not in set(document.get("content_ids") or []):
        raise SocialContractError("title registry content_ids does not contain --content-id")
    source_roots = {
        str(item.get("run_root") or "")
        for item in (document.get("source_runs") or [])
        if isinstance(item, dict)
    }
    output_roots = document.get("output_roots") or {}
    source_roots.update(str(value) for value in (output_roots.get("run_roots") or []))
    if output_roots.get("run_root"):
        source_roots.add(str(output_roots["run_root"]))
    if run_rel not in source_roots:
        raise SocialContractError("title registry does not name the requested run owner")
    canonical = str(document.get("canonical_title_root") or "")
    if canonical != repo_relative(repo_root, path.parent):
        raise SocialContractError("title registry canonical_title_root does not match registry location")
    return path, document
