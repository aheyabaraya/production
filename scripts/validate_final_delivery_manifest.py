#!/usr/bin/env python3
"""Validate a pointer-first IDOL final-delivery inventory.

This validator checks structure, active run ownership, paths, byte sizes,
SHA-256 values, and declared relationships. It never selects media, changes
creative truth, grants public release, or authorizes cleanup.
"""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path
import sys
from typing import Any, Iterable

import yaml
from jsonschema import Draft202012Validator, FormatChecker


SCRIPT_DIR = Path(__file__).resolve().parent
ROOT = SCRIPT_DIR.parent
SCHEMA = ROOT / "schemas" / "final-delivery-manifest.schema.json"
sys.path.insert(0, str(SCRIPT_DIR))

from lib.idol_run_layout import resolve_run_identity, validate_run_manifest  # noqa: E402
from lib.idol_post05_trace import (  # noqa: E402
    canonical_object_sha256,
    normalize_production_graph_trace,
)
from lib.idol_social_release_contracts import (  # noqa: E402
    SocialContractError,
    validate_package_contract,
)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_mapping(path: Path, label: str) -> dict[str, Any]:
    try:
        value = yaml.safe_load(path.read_text(encoding="utf-8"))
    except OSError as error:
        raise ValueError(f"cannot read {label}: {path}: {error}") from error
    except yaml.YAMLError as error:
        raise ValueError(f"invalid YAML for {label}: {path}: {error}") from error
    if not isinstance(value, dict):
        raise ValueError(f"{label} root must be an object: {path}")
    return value


def has_symlink_component(path: Path, root: Path) -> bool:
    try:
        parts = path.relative_to(root).parts
    except ValueError:
        return True
    current = root
    for part in parts:
        current = current / part
        if current.is_symlink():
            return True
    return False


def resolve_repo_file(
    raw_path: Any,
    *,
    repo_root: Path,
    label: str,
    errors: list[str],
) -> Path | None:
    if not isinstance(raw_path, str) or not raw_path or Path(raw_path).is_absolute():
        errors.append(f"{label}.path must be a non-empty repo-relative path")
        return None
    candidate = repo_root / raw_path
    try:
        candidate.resolve().relative_to(repo_root)
    except ValueError:
        errors.append(f"{label}.path escapes the repository: {raw_path}")
        return None
    if has_symlink_component(candidate, repo_root):
        errors.append(f"{label}.path crosses a symlink: {raw_path}")
        return None
    if not candidate.is_file():
        errors.append(f"{label}.path is not a readable file: {raw_path}")
        return None
    return candidate


def check_binding(
    binding: Any,
    *,
    repo_root: Path,
    label: str,
    errors: list[str],
) -> Path | None:
    if not isinstance(binding, dict):
        errors.append(f"{label} must be an object")
        return None
    path = resolve_repo_file(
        binding.get("path"),
        repo_root=repo_root,
        label=label,
        errors=errors,
    )
    if path is None:
        return None
    try:
        actual_size = path.stat().st_size
        actual_sha = sha256_file(path)
    except OSError as error:
        errors.append(f"{label} cannot read bytes: {error}")
        return None
    expected_size = binding.get("size_bytes")
    if expected_size is not None and expected_size != actual_size:
        errors.append(
            f"{label}.size_bytes mismatch: expected {expected_size!r}, actual {actual_size}"
        )
    if binding.get("sha256") != actual_sha:
        errors.append(f"{label}.sha256 does not match file bytes")
    return path


def iter_indexed_bindings(document: dict[str, Any]) -> Iterable[tuple[str, dict[str, Any]]]:
    for name, binding in document.get("source_contracts", {}).items():
        if isinstance(binding, dict):
            yield f"source_contracts.{name}", binding
    for index, binding in enumerate(document.get("deliverables", [])):
        if isinstance(binding, dict):
            yield f"deliverables[{index}]", binding
    for index, binding in enumerate(document.get("used_originals", [])):
        if isinstance(binding, dict):
            yield f"used_originals[{index}]", binding
    for index, binding in enumerate(document.get("reference_dependencies", [])):
        if isinstance(binding, dict):
            yield f"reference_dependencies[{index}]", binding
    for index, binding in enumerate(document.get("lineage_records", [])):
        if isinstance(binding, dict):
            yield f"lineage_records[{index}]", binding
    cleanup = document.get("cleanup", {})
    if isinstance(cleanup, dict):
        for name in ("cleanup_plan", "founder_approval", "cleanup_receipt"):
            binding = cleanup.get(name)
            if isinstance(binding, dict):
                yield f"cleanup.{name}", binding


def validate_manifest(
    manifest_path: Path,
    *,
    repo_root: Path = ROOT,
    schema_path: Path = SCHEMA,
) -> list[str]:
    root = repo_root.resolve()
    manifest = manifest_path.resolve()
    errors: list[str] = []
    try:
        document = load_mapping(manifest, "final delivery manifest")
        schema = load_mapping(schema_path, "final delivery schema")
    except ValueError as error:
        return [str(error)]

    validator = Draft202012Validator(schema, format_checker=FormatChecker())
    for error in sorted(validator.iter_errors(document), key=lambda item: list(item.path)):
        location = ".".join(str(part) for part in error.path) or "<root>"
        errors.append(f"schema {location}: {error.message}")
    if errors:
        return errors

    run_root_value = document["run_root"]
    run_path = root / run_root_value
    run_errors = validate_run_manifest(run_path, root)
    errors.extend(f"run_root: {error}" for error in run_errors)
    if not run_errors:
        try:
            identity = resolve_run_identity(run_path, root)
        except ValueError as error:
            errors.append(f"run_root: {error}")
        else:
            if document["content_id"] != identity["content_id"]:
                errors.append(
                    "content_id does not match the validated run identity: "
                    f"{document['content_id']!r} != {identity['content_id']!r}"
                )

    expected_manifest = run_path / "package" / "final-delivery" / "manifest.yaml"
    if manifest != expected_manifest.resolve():
        errors.append(
            "manifest must use the stable path "
            f"{expected_manifest.relative_to(root).as_posix()}"
        )

    deliverable_ids: set[str] = set()
    deliverable_paths: set[str] = set()
    byte_owners: dict[tuple[str, int], str] = {}
    for index, item in enumerate(document["deliverables"]):
        label = f"deliverables[{index}]"
        artifact_id = item["artifact_id"]
        if artifact_id in deliverable_ids:
            errors.append(f"{label}.artifact_id is duplicated: {artifact_id}")
        deliverable_ids.add(artifact_id)
        path_value = item["path"]
        if path_value in deliverable_paths:
            errors.append(f"{label}.path is duplicated: {path_value}")
        deliverable_paths.add(path_value)
        if not path_value.startswith(f"{run_root_value}/"):
            errors.append(f"{label}.path must stay inside the owning run")
        byte_key = (item["sha256"], item["size_bytes"])
        previous = byte_owners.get(byte_key)
        if previous and previous != path_value:
            errors.append(
                f"{label} duplicates canonical bytes already owned by {previous}; "
                "keep one path and point to it"
            )
        byte_owners[byte_key] = path_value
        for parent_id in item["derived_from_artifact_ids"]:
            if parent_id == artifact_id:
                errors.append(f"{label} cannot derive from itself")

    source_ids: set[str] = set()
    source_paths: set[str] = set()
    for index, item in enumerate(document["used_originals"]):
        label = f"used_originals[{index}]"
        source_id = item["source_id"]
        if source_id in source_ids:
            errors.append(f"{label}.source_id is duplicated: {source_id}")
        source_ids.add(source_id)
        path_value = item["path"]
        if path_value in source_paths:
            errors.append(f"{label}.path is duplicated: {path_value}")
        source_paths.add(path_value)
        if not (
            path_value.startswith(f"{run_root_value}/")
            or path_value.startswith("source-materials/")
            or path_value.startswith("assets/")
        ):
            errors.append(
                f"{label}.path must be run-owned or use source-materials/assets"
            )
        unknown_uses = sorted(set(item["used_by_artifact_ids"]) - deliverable_ids)
        if unknown_uses:
            errors.append(
                f"{label}.used_by_artifact_ids names unknown deliverables: "
                f"{', '.join(unknown_uses)}"
            )
        byte_key = (item["sha256"], item["size_bytes"])
        previous = byte_owners.get(byte_key)
        if previous and previous != path_value:
            errors.append(
                f"{label} duplicates canonical bytes already owned by {previous}; "
                "keep one path and point to it"
            )
        byte_owners[byte_key] = path_value

    for index, item in enumerate(document["deliverables"]):
        unknown_parents = sorted(
            set(item["derived_from_artifact_ids"]) - deliverable_ids - source_ids
        )
        if unknown_parents:
            errors.append(
                f"deliverables[{index}].derived_from_artifact_ids names unknown "
                f"artifacts: {', '.join(unknown_parents)}"
            )

    slate = document["derivative_slate"]
    planned = set(slate["planned_deliverable_ids"])
    closed = set(slate["closed_deliverable_ids"])
    unknown_planned = sorted(planned - deliverable_ids)
    if unknown_planned:
        errors.append(
            "derivative_slate.planned_deliverable_ids names unknown deliverables: "
            f"{', '.join(unknown_planned)}"
        )
    unknown_closed = sorted(closed - planned)
    if unknown_closed:
        errors.append(
            "derivative_slate.closed_deliverable_ids is not a subset of planned: "
            f"{', '.join(unknown_closed)}"
        )
    if slate["status"] == "closed" and planned != closed:
        missing = ", ".join(sorted(planned - closed)) or "none"
        extra = ", ".join(sorted(closed - planned)) or "none"
        errors.append(
            "closed derivative_slate must close the exact planned set "
            f"(missing: {missing}; extra: {extra})"
        )

    checked_paths: dict[str, str] = {}
    for label, binding in iter_indexed_bindings(document):
        path_value = str(binding.get("path", ""))
        prior = checked_paths.get(path_value)
        if prior and label.startswith(("deliverables", "used_originals")):
            errors.append(f"{label}.path duplicates {prior}: {path_value}")
        checked_paths[path_value] = prior or label
        check_binding(binding, repo_root=root, label=label, errors=errors)

    if document.get("schema_version") == "idol-final-delivery-manifest.v2":
        package_binding = document.get("source_contracts", {}).get("package")
        package_path = None
        if isinstance(package_binding, dict):
            package_path = resolve_repo_file(
                package_binding.get("path"),
                repo_root=root,
                label="source_contracts.package",
                errors=errors,
            )
        if package_path is not None:
            try:
                _path, package, package_deliverable_rows = validate_package_contract(
                    repo_root=root,
                    run_path=run_path,
                    content_id=document["content_id"],
                    package_contract=package_path,
                    allow_closed=True,
                    require_final_lineage=False,
                )
            except SocialContractError as error:
                errors.append(f"source_contracts.package validation failed: {error}")
            else:
                trace = package.get("production_graph_trace")
                if isinstance(trace, dict):
                    expected_trace_sha = canonical_object_sha256(
                        normalize_production_graph_trace(trace)
                    )
                    if (
                        document.get("production_graph_trace", {}).get("source_value_sha256")
                        != expected_trace_sha
                    ):
                        errors.append(
                            "production_graph_trace.source_value_sha256 does not match 05 package bytes"
                        )
                package_outputs: dict[str, dict[str, Any]] = {}
                for output in package_deliverable_rows:
                    output_id = str(output.get("output_id") or "")
                    package_outputs[output_id] = output
                for index, deliverable in enumerate(document["deliverables"]):
                    output_id = str(deliverable.get("package_output_id") or "")
                    output = package_outputs.get(output_id)
                    if output is None:
                        errors.append(
                            f"deliverables[{index}].package_output_id is absent from 05 package: {output_id}"
                        )
                        continue
                    if str(output.get("path") or "") != deliverable["path"]:
                        errors.append(
                            f"deliverables[{index}].path does not match its 05 package output"
                        )
                    package_sha = str(output.get("sha256") or "")
                    if package_sha and package_sha != deliverable["sha256"]:
                        errors.append(
                            f"deliverables[{index}].sha256 does not match its 05 package output"
                        )

    return errors


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Validate IDOL final deliverables and exact final-used source bytes."
    )
    parser.add_argument("manifest", type=Path)
    args = parser.parse_args()
    errors = validate_manifest(args.manifest)
    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print(
        "OK: final deliverables, exact used originals, reference dependencies, "
        "05-to-04 production trace, lineage, derivative slate, and cleanup boundaries are valid"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
