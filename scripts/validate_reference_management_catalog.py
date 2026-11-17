#!/usr/bin/env python3
"""Validate the unified reference catalog and reusable still-image source hub.

This script checks schemas, pointer identity, file presence, SHA-256 values,
and cross-record ids. It never classifies a reference, authors an analysis,
downloads media, grants attachment permission, or advances a production gate.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import sys
from typing import Any, Iterable

import yaml

SCRIPT_DIR = Path(__file__).resolve().parent
ROOT = SCRIPT_DIR.parent
sys.path.insert(0, str(SCRIPT_DIR))

from validate_json_schema import load_document, validator_for  # noqa: E402


CATALOG_SCHEMA = ROOT / "schemas" / "reference-management-catalog.schema.json"
DEFAULT_CATALOG = ROOT / "catalog" / "references" / "reference-catalog.yaml"
IMAGE_CATALOG_SCHEMA = ROOT / "schemas" / "image-reference-source-catalog.schema.json"
IMAGE_MANIFEST_SCHEMA = ROOT / "schemas" / "image-reference-source-manifest.schema.json"
IMAGE_CATALOG = ROOT / "source-materials" / "image-sources" / "reference-image-catalog.yaml"
REQUIRED_SOURCE_INDEX_IDS = {
    "VIDEO_SOURCE_HUB",
    "VIDEO_ANALYSIS_REGISTRY",
    "IMAGE_SOURCE_HUB",
    "TITLE_REFERENCE_INDEXES",
    "REUSABLE_FUNCTION_LIBRARY",
}


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def schema_errors(document: Any, schema_path: Path, label: str) -> list[str]:
    try:
        schema = load_document(schema_path)
    except (OSError, json.JSONDecodeError, yaml.YAMLError, ValueError) as error:
        return [f"{label}: cannot load schema {schema_path}: {error}"]
    validator = validator_for(schema)
    return [
        f"{label} schema {'.'.join(str(part) for part in error.absolute_path) or '<root>'}: {error.message}"
        for error in sorted(validator.iter_errors(document), key=lambda item: list(item.absolute_path))
    ]


def resolve_repo_file(raw_path: Any, label: str, errors: list[str]) -> Path | None:
    if not isinstance(raw_path, str) or not raw_path or Path(raw_path).is_absolute():
        errors.append(f"{label}.path must be a non-empty repo-relative path")
        return None
    candidate = ROOT / raw_path
    try:
        candidate.resolve().relative_to(ROOT)
    except ValueError:
        errors.append(f"{label}.path escapes the repository: {raw_path}")
        return None
    if not candidate.is_file():
        errors.append(f"{label}.path is not a readable file: {raw_path}")
        return None
    return candidate


def check_file_ref(ref: Any, label: str, errors: list[str]) -> Path | None:
    if not isinstance(ref, dict):
        errors.append(f"{label} must be a file reference")
        return None
    path = resolve_repo_file(ref.get("path"), label, errors)
    if path is None:
        return None
    try:
        actual_sha = sha256_file(path)
    except OSError as error:
        errors.append(f"{label} cannot read bytes: {error}")
        return None
    if ref.get("sha256") != actual_sha:
        errors.append(f"{label}.sha256 does not match file bytes")
    return path


def canonical_value_sha256(value: Any) -> str:
    payload = json.dumps(
        value,
        sort_keys=True,
        ensure_ascii=False,
        separators=(",", ":"),
    ).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def check_cf_bridge_entry_set_ref(
    ref: dict[str, Any],
    *,
    run_root: str,
    label: str,
    errors: list[str],
) -> None:
    expected_path = f"{run_root}/research/CF-reference-bridge.yaml"
    if ref["path"] != expected_path:
        errors.append(f"{label}.path must equal the owning CF bridge {expected_path}")
    path = resolve_repo_file(ref["path"], label, errors)
    if path is None:
        return
    try:
        bridge = load_document(path)
    except (OSError, json.JSONDecodeError, yaml.YAMLError, ValueError) as error:
        errors.append(f"{label} cannot load CF bridge: {error}")
        return
    if not isinstance(bridge, dict):
        errors.append(f"{label} CF bridge root must be an object")
        return
    if bridge.get("schema_version") != ref["schema_version"]:
        errors.append(f"{label}.schema_version differs from the CF bridge")
    entries = {
        row.get("entry_id"): row
        for row in bridge.get("entries", [])
        if isinstance(row, dict) and isinstance(row.get("entry_id"), str)
    }
    missing = [entry_id for entry_id in ref["entry_ids"] if entry_id not in entries]
    if missing:
        errors.append(f"{label}.entry_ids names missing CF bridge entries: {missing!r}")
        return
    bound_values = [
        {"entry_id": entry_id, "entry": entries[entry_id]}
        for entry_id in ref["entry_ids"]
    ]
    if canonical_value_sha256(bound_values) != ref["entry_set_sha256"]:
        errors.append(
            f"{label}.entry_set_sha256 does not match the named CF bridge entries"
        )


def catalog_file_refs(document: dict[str, Any]) -> Iterable[tuple[str, dict[str, Any]]]:
    for index, row in enumerate(document.get("source_indexes", [])):
        if isinstance(row, dict) and row.get("locator_kind") == "file":
            yield (
                f"source_indexes[{index}]",
                {"path": row.get("locator"), "sha256": row.get("snapshot_sha256")},
            )
    for index, row in enumerate(document.get("reference_units", [])):
        if not isinstance(row, dict):
            continue
        yield f"reference_units[{index}].source_manifest", row.get("source_manifest")
        if isinstance(row.get("analysis_ref"), dict):
            yield f"reference_units[{index}].analysis_ref", row["analysis_ref"]
        for evidence_index, ref in enumerate(row.get("selected_evidence", [])):
            yield f"reference_units[{index}].selected_evidence[{evidence_index}]", ref
        for note_index, ref in enumerate(row.get("function_note_refs", [])):
            yield f"reference_units[{index}].function_note_refs[{note_index}]", ref
    for index, row in enumerate(document.get("usage_history", [])):
        if (
            isinstance(row, dict)
            and isinstance(row.get("binding_ref"), dict)
            and row["binding_ref"].get("binding_kind") is None
        ):
            yield f"usage_history[{index}].binding_ref", row["binding_ref"]


def validate_image_catalog(errors: list[str]) -> None:
    try:
        document = load_document(IMAGE_CATALOG)
    except (OSError, json.JSONDecodeError, yaml.YAMLError, ValueError) as error:
        errors.append(f"image catalog cannot be loaded: {error}")
        return
    errors.extend(schema_errors(document, IMAGE_CATALOG_SCHEMA, "image catalog"))
    manifest_validator = validator_for(load_document(IMAGE_MANIFEST_SCHEMA))

    seen_source_ids: set[str] = set()
    seen_identities: set[str] = set()
    for index, row in enumerate(document.get("sources", [])):
        if not isinstance(row, dict):
            continue
        source_id = str(row.get("source_id", ""))
        identity = str(row.get("source_identity", ""))
        if source_id in seen_source_ids:
            errors.append(f"image catalog sources[{index}].source_id is duplicated: {source_id}")
        if identity in seen_identities:
            errors.append(
                f"image catalog sources[{index}].source_identity is duplicated: {identity}"
            )
        seen_source_ids.add(source_id)
        seen_identities.add(identity)

        expected_manifest = (
            f"source-materials/image-sources/by-source/{source_id}/source-manifest.yaml"
        )
        expected_original_prefix = (
            f"source-materials/image-sources/by-source/{source_id}/originals/"
        )
        manifest_ref = row.get("manifest", {})
        original_ref = row.get("primary_original", {})
        if manifest_ref.get("path") != expected_manifest:
            errors.append(
                f"image catalog sources[{index}].manifest.path must equal "
                f"{expected_manifest}"
            )
        if not str(original_ref.get("path", "")).startswith(expected_original_prefix):
            errors.append(
                f"image catalog sources[{index}].primary_original.path must stay under "
                f"{expected_original_prefix}"
            )

        manifest_path = check_file_ref(
            manifest_ref, f"image catalog sources[{index}].manifest", errors
        )
        original_path = check_file_ref(
            original_ref,
            f"image catalog sources[{index}].primary_original",
            errors,
        )
        if manifest_path is None:
            continue
        try:
            manifest = load_document(manifest_path)
        except (OSError, json.JSONDecodeError, yaml.YAMLError, ValueError) as error:
            errors.append(f"image source manifest cannot be loaded: {manifest_path}: {error}")
            continue
        for error in sorted(
            manifest_validator.iter_errors(manifest), key=lambda item: list(item.absolute_path)
        ):
            location = ".".join(str(part) for part in error.absolute_path) or "<root>"
            errors.append(f"image source manifest {source_id} schema {location}: {error.message}")
        if manifest.get("source_id") != source_id:
            errors.append(f"image source manifest source_id mismatch: {source_id}")
        if manifest.get("source_identity") != identity:
            errors.append(f"image source manifest source_identity mismatch: {identity}")
        availability = manifest.get("availability", {})
        if isinstance(availability, dict):
            if availability.get("local_state") != row.get("local_state"):
                errors.append(f"image source manifest local_state mismatch: {source_id}")
            if availability.get("backup_state") != row.get("backup_state"):
                errors.append(f"image source manifest backup_state mismatch: {source_id}")
        if manifest.get("status") != row.get("status"):
            errors.append(f"image source manifest status mismatch: {source_id}")
        original = manifest.get("original", {})
        if isinstance(original, dict) and original_path is not None:
            if original.get("path") != row.get("primary_original", {}).get("path"):
                errors.append(f"image source manifest primary original path mismatch: {source_id}")
            if original.get("sha256") != row.get("primary_original", {}).get("sha256"):
                errors.append(f"image source manifest primary original SHA mismatch: {source_id}")
            if original.get("size_bytes") != original_path.stat().st_size:
                errors.append(f"image source manifest original size mismatch: {source_id}")


def validate_catalog(catalog_path: Path) -> list[str]:
    errors: list[str] = []
    try:
        document = load_document(catalog_path)
    except (OSError, json.JSONDecodeError, yaml.YAMLError, ValueError) as error:
        return [f"reference catalog cannot be loaded: {error}"]
    if not isinstance(document, dict):
        return ["reference catalog root must be an object"]
    errors.extend(schema_errors(document, CATALOG_SCHEMA, "reference catalog"))
    if errors:
        return errors

    source_index_ids = [
        str(row.get("index_id", ""))
        for row in document["source_indexes"]
        if isinstance(row, dict)
    ]
    if len(source_index_ids) != len(set(source_index_ids)):
        errors.append("source_indexes contains duplicate index_id values")
    missing_source_indexes = sorted(REQUIRED_SOURCE_INDEX_IDS - set(source_index_ids))
    unexpected_source_indexes = sorted(set(source_index_ids) - REQUIRED_SOURCE_INDEX_IDS)
    if missing_source_indexes:
        errors.append(
            "source_indexes is missing required ids: " + ", ".join(missing_source_indexes)
        )
    if unexpected_source_indexes:
        errors.append(
            "source_indexes contains unregistered ids: " + ", ".join(unexpected_source_indexes)
        )

    unit_ids: set[str] = set()
    usage_ids: set[str] = set()
    for index, row in enumerate(document["reference_units"]):
        unit_id = row["reference_unit_id"]
        if unit_id in unit_ids:
            errors.append(f"reference_units[{index}].reference_unit_id is duplicated: {unit_id}")
        unit_ids.add(unit_id)
    for index, row in enumerate(document["usage_history"]):
        usage_id = row["usage_id"]
        if usage_id in usage_ids:
            errors.append(f"usage_history[{index}].usage_id is duplicated: {usage_id}")
        usage_ids.add(usage_id)
        if row["reference_unit_id"] not in unit_ids:
            errors.append(
                f"usage_history[{index}] names unknown reference_unit_id: "
                f"{row['reference_unit_id']}"
            )
        production_lane = row["production_lane"]
        run_root = row["run_root"]
        expected_prefix = "cf/runs/" if production_lane == "cf" else "runs/"
        if not run_root.startswith(expected_prefix):
            errors.append(
                f"usage_history[{index}].run_root must start with {expected_prefix!r} "
                f"for production_lane {production_lane!r}"
            )
        binding_ref = row.get("binding_ref")
        if isinstance(binding_ref, dict) and binding_ref.get("binding_kind") == (
            "cf_reference_bridge_entry_set"
        ):
            if production_lane != "cf":
                errors.append(
                    f"usage_history[{index}].binding_ref uses a CF bridge for a "
                    f"non-CF production lane"
                )
            check_cf_bridge_entry_set_ref(
                binding_ref,
                run_root=run_root,
                label=f"usage_history[{index}].binding_ref",
                errors=errors,
            )

    for label, ref in catalog_file_refs(document):
        check_file_ref(ref, label, errors)
    validate_image_catalog(errors)
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Validate unified reference pointers, hashes, ids, and the still-image hub."
    )
    parser.add_argument(
        "catalog",
        nargs="?",
        type=Path,
        default=DEFAULT_CATALOG,
        help="Reference catalog path (default: catalog/references/reference-catalog.yaml)",
    )
    args = parser.parse_args()
    errors = validate_catalog(args.catalog)
    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print(
        "OK: unified reference source indexes, analyzed units, usage history, "
        "and still-image source pointers are valid"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
