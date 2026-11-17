"""Canonical IDOL album/title/run path helpers.

New song/MV runs use exactly:
    runs/<album_key>/<title_key>/<run_id>

One exact in-flight date-first run may continue only when it is hash-bound in
``automation/run-layout-transition.yaml``. This is a bounded completion
exception, not a legacy path parser or a compatibility authoring branch.
"""

from __future__ import annotations

from dataclasses import dataclass
import hashlib
import json
from pathlib import Path
import re
from typing import Any, Mapping

import yaml


RUN_MANIFEST_NAME = "run-manifest.yaml"
RUN_MANIFEST_VERSION = "idol-run-manifest.v1"
RUN_LAYOUT_TRANSITION_RELATIVE = Path("automation/run-layout-transition.yaml")
RUN_LAYOUT_TRANSITION_VERSION = "idol-run-layout-transition.v1"
ALBUM_KEY_RE = re.compile(r"^[a-z0-9][a-z0-9-]{1,120}$")
TITLE_KEY_RE = re.compile(r"^[a-z0-9가-힣][a-z0-9가-힣-]{1,120}$")
RUN_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{2,120}$")
ACTIVE_RUN_ROOT_RE = re.compile(
    r"^runs/(?P<album_key>[a-z0-9][a-z0-9-]{1,120})/"
    r"(?P<title_key>[a-z0-9가-힣][a-z0-9가-힣-]{1,120})/"
    r"(?P<run_id>[A-Za-z0-9][A-Za-z0-9._-]{2,120})$"
)


@dataclass(frozen=True)
class RunAddress:
    album_key: str
    title_key: str
    run_id: str

    @property
    def relative_root(self) -> str:
        return f"runs/{self.album_key}/{self.title_key}/{self.run_id}"


def build_run_root(album_key: str, title_key: str, run_id: str) -> str:
    address = RunAddress(album_key=album_key, title_key=title_key, run_id=run_id)
    errors = validate_address(address)
    if errors:
        raise ValueError("; ".join(errors))
    return address.relative_root


def validate_address(address: RunAddress) -> list[str]:
    errors: list[str] = []
    if not ALBUM_KEY_RE.fullmatch(address.album_key):
        errors.append(f"invalid album_key: {address.album_key}")
    if not TITLE_KEY_RE.fullmatch(address.title_key):
        errors.append(f"invalid title_key: {address.title_key}")
    if not RUN_ID_RE.fullmatch(address.run_id):
        errors.append(f"invalid run_id: {address.run_id}")
    return errors


def parse_run_root(value: str | Path, repo_root: str | Path | None = None) -> RunAddress:
    path = Path(value)
    if path.is_absolute():
        if repo_root is None:
            raise ValueError("repo_root is required for an absolute run path")
        try:
            normalized = path.resolve().relative_to(Path(repo_root).resolve()).as_posix()
        except ValueError as exc:
            raise ValueError(f"run root is outside repository root: {path}") from exc
    else:
        normalized = path.as_posix().rstrip("/")
    match = ACTIVE_RUN_ROOT_RE.fullmatch(normalized)
    if not match:
        raise ValueError(
            "active run root must be runs/ALBUM_KEY/TITLE_KEY/RUN_ID; "
            f"got: {normalized}"
        )
    return RunAddress(**match.groupdict())


def _repo_relative(value: str | Path, repo_root: str | Path) -> tuple[Path, str]:
    root = Path(repo_root).resolve()
    path = Path(value)
    path = path.resolve() if path.is_absolute() else (root / path).resolve()
    try:
        relative = path.relative_to(root).as_posix()
    except ValueError as exc:
        raise ValueError(f"run root is outside repository root: {path}") from exc
    return path, relative


def _load_mapping(path: Path, label: str) -> Mapping[str, Any]:
    if not path.is_file():
        raise ValueError(f"{label} is missing: {path}")
    document = yaml.safe_load(path.read_text(encoding="utf-8"))
    if not isinstance(document, dict):
        raise ValueError(f"{label} root must be an object: {path}")
    return document


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _canonical_value(value: Any) -> Any:
    if isinstance(value, dict):
        return {
            str(key): _canonical_value(value[key])
            for key in sorted(value, key=lambda item: str(item))
        }
    if isinstance(value, list):
        return [_canonical_value(item) for item in value]
    return value


def _active_stage_sequence_sha256(stage_registry: Mapping[str, Any]) -> str:
    stages = sorted(
        (
            row
            for row in stage_registry.get("stages", [])
            if isinstance(row, dict) and row.get("active") is True
        ),
        key=lambda row: (int(row.get("order", 0)), str(row.get("stage_id", ""))),
    )
    keys = (
        "stage_id",
        "order",
        "code",
        "owner_skill",
        "scope",
        "inputs",
        "founder_gate",
    )
    rows = [{key: row.get(key) for key in keys} for row in stages]
    encoded = json.dumps(
        _canonical_value(rows),
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def load_transition_registry(repo_root: str | Path) -> Mapping[str, Any]:
    root = Path(repo_root).resolve()
    return _load_mapping(
        root / RUN_LAYOUT_TRANSITION_RELATIVE,
        "run layout transition registry",
    )


def registered_transition_entry(
    value: str | Path,
    repo_root: str | Path,
) -> Mapping[str, Any] | None:
    """Return only an exact registered in-flight exception.

    There is deliberately no date-first fallback or wildcard matching.
    """

    _, relative = _repo_relative(value, repo_root)
    registry_path = Path(repo_root).resolve() / RUN_LAYOUT_TRANSITION_RELATIVE
    if not registry_path.is_file():
        return None
    registry = _load_mapping(registry_path, "run layout transition registry")
    matches = [
        row
        for row in registry.get("in_flight_exceptions", [])
        if isinstance(row, dict) and row.get("run_root") == relative
    ]
    if len(matches) > 1:
        raise ValueError(
            f"run layout transition registry has duplicate entries for: {relative}"
        )
    return matches[0] if matches else None


def resolve_run_address(
    value: str | Path,
    repo_root: str | Path,
) -> tuple[RunAddress, str, Mapping[str, Any] | None]:
    """Resolve a canonical run or the one exact registered transition."""

    try:
        return parse_run_root(value, repo_root), "album_layout", None
    except ValueError as canonical_error:
        entry = registered_transition_entry(value, repo_root)
        if entry is None:
            raise canonical_error
        address = RunAddress(
            album_key=str(entry.get("album_key", "")),
            title_key=str(entry.get("title_key", "")),
            run_id=str(entry.get("run_id", "")),
        )
        errors = validate_address(address)
        if errors:
            raise ValueError("; ".join(errors))
        return address, "registered_in_flight_transition", entry


def resolve_run_identity(
    value: str | Path,
    repo_root: str | Path,
) -> Mapping[str, Any]:
    """Return the active identity source after the caller validates the run."""

    path, relative = _repo_relative(value, repo_root)
    address, layout_status, entry = resolve_run_address(path, repo_root)
    if layout_status == "album_layout":
        identity_path = path / RUN_MANIFEST_NAME
        document = load_run_manifest(path)
    else:
        identity_path = Path(repo_root).resolve() / RUN_LAYOUT_TRANSITION_RELATIVE
        document = entry or {}
    return {
        "path": path,
        "relative_root": relative,
        "layout_status": layout_status,
        "address": address,
        "identity_path": identity_path,
        "document": document,
        "content_id": str(document.get("content_id", "")),
        "status": (
            str(document.get("status", ""))
            if layout_status == "album_layout"
            else "active"
        ),
    }


def load_run_manifest(run_root: str | Path) -> Mapping[str, Any]:
    manifest_path = Path(run_root) / RUN_MANIFEST_NAME
    if not manifest_path.is_file():
        raise ValueError(f"run manifest is missing: {manifest_path}")
    document = yaml.safe_load(manifest_path.read_text(encoding="utf-8"))
    if not isinstance(document, dict):
        raise ValueError(f"run manifest root must be an object: {manifest_path}")
    return document


def _validate_transition(
    *,
    path: Path,
    relative: str,
    repo_root: Path,
    address: RunAddress,
    entry: Mapping[str, Any],
    require_directory: bool,
) -> list[str]:
    errors: list[str] = []
    registry_path = repo_root / RUN_LAYOUT_TRANSITION_RELATIVE
    try:
        registry = load_transition_registry(repo_root)
    except (ValueError, yaml.YAMLError) as exc:
        return [str(exc)]
    expected_registry = {
        "schema_version": RUN_LAYOUT_TRANSITION_VERSION,
        "status": "active",
        "active_run_template": "runs/ALBUM_KEY/TITLE_KEY/RUN_ID",
        "generic_date_first_authoring": "forbidden",
        "new_date_first_run_creation": "forbidden",
        "quality_flow_change_authority": "none",
    }
    for key, expected in expected_registry.items():
        if registry.get(key) != expected:
            errors.append(
                f"run layout transition {key} must be {expected!r}; "
                f"got {registry.get(key)!r}"
            )
    if require_directory and not path.is_dir():
        errors.append(f"run root is not a directory: {relative}")
        return errors
    expected_entry = {
        "run_root": relative,
        "state": "in_flight_finish_in_place",
        "current_next_allowed": True,
        "existing_canonical_continuation_allowed": True,
        "new_run_creation_allowed": False,
        "migration_execution_allowed": False,
        "expires_when": "run_closed_or_validated_migration_completed",
    }
    for key, expected in expected_entry.items():
        if entry.get(key) != expected:
            errors.append(
                f"registered transition {key} must be {expected!r}; "
                f"got {entry.get(key)!r}"
            )
    if address.run_id != Path(relative).name:
        errors.append("registered transition run_id must match the source folder name")
    try:
        expected_target = build_run_root(
            address.album_key, address.title_key, address.run_id
        )
        if entry.get("target_run_root") != expected_target:
            errors.append(
                "registered transition target_run_root must equal the canonical "
                f"album/title/run address {expected_target}"
            )
    except ValueError as exc:
        errors.append(str(exc))

    migration = entry.get("migration_plan")
    if not isinstance(migration, dict):
        errors.append("registered transition migration_plan must be an object")
    else:
        migration_value = str(migration.get("path", ""))
        try:
            migration_path = (repo_root / migration_value).resolve()
            migration_path.relative_to(repo_root)
        except (ValueError, OSError):
            migration_path = repo_root
            errors.append("registered transition migration plan must stay in repository")
        if migration_path == repo_root or not migration_path.is_file():
            errors.append(
                f"registered transition migration plan is missing: {migration_value}"
            )
        else:
            actual = _sha256(migration_path)
            if migration.get("sha256") != actual:
                errors.append(
                    "registered transition migration plan SHA-256 mismatch: "
                    f"expected {migration.get('sha256')!r}, got {actual!r}"
                )
            try:
                plan = _load_mapping(migration_path, "run migration plan")
                if plan.get("status") != migration.get("required_status"):
                    errors.append(
                        "registered transition migration plan status differs from "
                        "the required status"
                    )
                if plan.get("source_run_root") != relative:
                    errors.append(
                        "registered transition migration plan source differs from "
                        "the registered run"
                    )
                if plan.get("target_run_root") != entry.get("target_run_root"):
                    errors.append(
                        "registered transition migration plan target differs from "
                        "the registered target"
                    )
                if plan.get("automatic_move_performed") is not False:
                    errors.append(
                        "registered transition migration plan must confirm that no "
                        "automatic move was performed"
                    )
            except (ValueError, yaml.YAMLError) as exc:
                errors.append(str(exc))

    flow = entry.get("flow_lock")
    if not isinstance(flow, dict):
        errors.append("registered transition flow_lock must be an object")
    else:
        registry_value = str(flow.get("stage_registry_path", ""))
        if registry_value != "automation/harness-stage-registry.yaml":
            errors.append(
                "registered transition stage_registry_path must be "
                "automation/harness-stage-registry.yaml"
            )
        stage_path = (repo_root / registry_value).resolve()
        if not stage_path.is_file():
            errors.append(
                f"registered transition stage registry is missing: {registry_value}"
            )
        else:
            registry_sha = _sha256(stage_path)
            if flow.get("stage_registry_sha256") != registry_sha:
                errors.append(
                    "registered transition stage registry SHA-256 differs from "
                    "the active registry"
                )
            try:
                stage_document = _load_mapping(stage_path, "stage registry")
                semantic_sha = _active_stage_sequence_sha256(stage_document)
                if flow.get("stage_sequence_sha256") != semantic_sha:
                    errors.append(
                        "registered transition stage sequence SHA-256 differs from "
                        "the active PRE-00 through 05 flow"
                    )
            except (ValueError, yaml.YAMLError) as exc:
                errors.append(str(exc))
    if not registry_path.is_file():
        errors.append(f"run layout transition registry is missing: {registry_path}")
    return errors


def validate_run_manifest(
    run_root: str | Path,
    repo_root: str | Path,
    *,
    require_directory: bool = True,
) -> list[str]:
    root = Path(repo_root).resolve()
    try:
        path, relative = _repo_relative(run_root, root)
    except ValueError as exc:
        return [str(exc)]
    errors: list[str] = []
    try:
        address, layout_status, transition = resolve_run_address(path, root)
    except ValueError as exc:
        return [str(exc)]
    if layout_status == "registered_in_flight_transition":
        return _validate_transition(
            path=path,
            relative=relative,
            repo_root=root,
            address=address,
            entry=transition or {},
            require_directory=require_directory,
        )
    if require_directory and not path.is_dir():
        errors.append(f"run root is not a directory: {address.relative_root}")
        return errors
    try:
        manifest = load_run_manifest(path)
    except ValueError as exc:
        errors.append(str(exc))
        return errors
    expected = {
        "schema_version": RUN_MANIFEST_VERSION,
        "album_key": address.album_key,
        "title_key": address.title_key,
        "run_id": address.run_id,
        "canonical_run_root": address.relative_root,
        "artifact_revision_owner": "git",
        "compatibility_authoring": "forbidden",
    }
    for key, value in expected.items():
        if manifest.get(key) != value:
            errors.append(
                f"run manifest {key} must be {value!r}; got {manifest.get(key)!r}"
            )
    return errors
