#!/usr/bin/env python3
"""Network-free pointer shortlist for the cross-run reference catalog.

This script never inspects media, ranks candidates, or authors disposition.
Default catalog mode stays compatible. Explicit multi-index mode may emit
source-owned pointer candidates from declared hub, image, and sequence indexes.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import sys
from pathlib import Path
from typing import Any

import yaml

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))
from lib.idol_artifact_integrity import HashBinder
from idol_video_reference_analysis_registry import validate_scoped_source


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CATALOG = Path("catalog/references/reference-catalog.yaml")
DEFAULT_ANALYSIS_REGISTRY = Path(
    "source-materials/video-sources/reference-analysis-registry.yaml"
)
DEFAULT_SEQUENCE_REGISTRY = Path(
    "source-materials/video-sources/sequence-unit-registry.yaml"
)
DEFAULT_VIDEO_HUB = Path("source-materials/video-sources/reference-hub-catalog.yaml")
DEFAULT_IMAGE_CATALOG = Path("source-materials/image-sources/reference-image-catalog.yaml")
SCHEMA_VERSION = "idol_reference_management_catalog.v3"
SEQUENCE_BATCH_VERSION = "idol_video_reference_sequence_unit_registry.v1"
INDEX_MODES = frozenset({"catalog", "multi"})
NEED_KINDS = frozenset({"any", "sequence", "unclassified"})
RECORD_KINDS = frozenset(
    {
        "catalog_reference_unit",
        "source_sequence_unit",
        "video_hub_source",
        "image_source",
    }
)
PAGE_ORDERS = frozenset({"unit_id", "distinct_source"})
DEFAULT_RETRIEVAL_VIEWS = {
    "major_or_feeling": ["major_scene_grammar_or_feeling"],
    "background_and_light": ["background_and_space", "lighting_color_material"],
    "action": [
        "subject_state_or_pose",
        "visible_action_or_hold",
        "object_environment_response",
    ],
    "camera": ["still_camera_and_composition"],
    "edit": ["edit_or_transition"],
}
NONBINDABLE_INSPECTION = frozenset(
    {
        "restricted",
        "unresolved_origin",
        "incomplete",
        "hold_incomplete",
        "not_analyzed",
        "rejected",
    }
)
NONBINDABLE_REUSE = frozenset({"restricted", "do_not_reuse", "unresolved_origin", "rejected"})
USABLE_ANALYSIS_STATE = "detailed_analysis_available"
COMPLETE_RECORD_STATUS = "complete"
SCOPED_RECORD_STATUS = "complete_scoped"
PARENT_COMPLETE_ROLE = "parent_complete_analysis"
ORIGINAL_VIDEO_ROLE = "original_video"
SEQUENCE_FRAME_COUNT = 5
SEQUENCE_CADENCE_SECONDS = 1.0
CADENCE_TOLERANCE = 0.001
IMAGE_HOLD_STATUS = frozenset({"hold", "retired"})


class LookupError(RuntimeError):
    pass


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _source_family(identity: str) -> str:
    value = str(identity or "")
    if ":" in value:
        return value.split(":", 1)[0] + ":"
    return value


def _pointer(value: Any) -> dict[str, str] | None:
    if not isinstance(value, dict):
        return None
    path = value.get("path")
    digest = value.get("sha256")
    if not path or not digest:
        return None
    return {"path": str(path), "sha256": str(digest)}


def _media_identity(
    source_identity: str, source_locator: str, manifest_sha: str, analysis_sha: str
) -> str:
    return sha256_bytes(
        "|".join([source_identity, source_locator, manifest_sha, analysis_sha]).encode("utf-8")
    )


def _binding_fingerprint(
    purpose_classes: list[str], selected_evidence: list[dict[str, str]]
) -> str:
    return sha256_bytes(
        json.dumps(
            {"purpose_classes": purpose_classes, "selected_evidence": selected_evidence},
            sort_keys=True,
        ).encode("utf-8")
    )


def _contained_path(root: Path, rel: Path) -> Path:
    if rel.is_absolute() or ".." in rel.parts:
        raise LookupError("path must stay inside the repository")
    declared = root / rel
    cursor = declared
    while True:
        if cursor.is_symlink():
            raise LookupError("symlink_refused")
        if cursor == root or cursor == cursor.parent:
            break
        cursor = cursor.parent
    resolved_root = root.resolve()
    resolved = declared.resolve()
    try:
        resolved.relative_to(resolved_root)
    except ValueError as exc:
        raise LookupError("path must stay inside the repository") from exc
    if resolved.is_symlink():
        raise LookupError("symlink_refused")
    if not resolved.is_file():
        raise LookupError("file_missing")
    return resolved


def _contained_file(root: Path, rel: Path) -> tuple[Path, bytes]:
    path = _contained_path(root, rel)
    return path, path.read_bytes()


def _load_yaml_mapping(
    root: Path, rel: Path, *, required: bool, missing_code: str, invalid_code: str
) -> tuple[dict[str, Any] | None, str | None, int]:
    try:
        _path, raw = _contained_file(root, rel)
    except LookupError as exc:
        if str(exc) == "file_missing":
            if required:
                raise LookupError(missing_code) from exc
            return None, None, 0
        raise
    digest = sha256_bytes(raw)
    try:
        document = yaml.safe_load(raw.decode("utf-8"))
    except (UnicodeDecodeError, yaml.YAMLError) as exc:
        raise LookupError(invalid_code) from exc
    if not isinstance(document, dict):
        raise LookupError(invalid_code)
    return document, digest, len(raw)


def load_catalog(root: Path, catalog_rel: Path, expected_sha256: str | None) -> dict[str, Any]:
    document, digest, _size = _load_yaml_mapping(
        root,
        catalog_rel,
        required=True,
        missing_code="catalog file is missing",
        invalid_code="catalog must contain an object",
    )
    if document is None or digest is None:
        raise LookupError("catalog file is missing")
    if expected_sha256 and expected_sha256 != digest:
        raise LookupError("stale_catalog_sha256")
    if document.get("schema_version") != SCHEMA_VERSION:
        raise LookupError("unexpected catalog schema_version")
    return document


def _held_or_excluded(unit: dict[str, Any]) -> str | None:
    inspection = str(unit.get("inspection_status") or "")
    reuse = str(unit.get("reuse_status") or "")
    if inspection in {"restricted", "unresolved_origin", "incomplete"} or reuse in {
        "restricted",
        "do_not_reuse",
        "unresolved_origin",
    }:
        return "restricted_or_unresolved_origin"
    if inspection in NONBINDABLE_INSPECTION:
        return f"inspection_status_{inspection}"
    if reuse in NONBINDABLE_REUSE:
        return f"reuse_status_{reuse}"
    if not unit.get("reference_unit_id") or not unit.get("source_identity"):
        return "incomplete_identity"
    manifest = unit.get("source_manifest") if isinstance(unit.get("source_manifest"), dict) else {}
    if not manifest.get("path") or not manifest.get("sha256"):
        return "incomplete_source_manifest_pointer"
    return None


def _requested_held(inspection_status: str | None, reuse_status: str | None) -> bool:
    return inspection_status in NONBINDABLE_INSPECTION or reuse_status in NONBINDABLE_REUSE


def _haystack(row: dict[str, Any]) -> str:
    titles = row.get("titles") if isinstance(row.get("titles"), list) else [row.get("title") or ""]
    return " ".join(
        [
            str(row.get("reference_unit_id") or ""),
            str(row.get("source_owned_id") or ""),
            str(row.get("source_identity") or ""),
            str(row.get("source_locator") or ""),
            " ".join(str(item) for item in titles),
            " ".join(str(item) for item in row.get("search_terms") or []),
        ]
    ).lower()


def _matches(
    row: dict[str, Any],
    *,
    source_families: list[str],
    purpose_classes: list[str],
    view_classes: list[str],
    search_terms: list[str],
    media_kind: str | None,
    need_kind: str,
    record_kinds: list[str],
    inspection_status: str | None = None,
    reuse_status: str | None = None,
) -> bool:
    identity = str(row.get("source_identity") or "")
    if source_families and not any(identity.startswith(family) for family in source_families):
        return False
    unit_purposes = {str(item) for item in row.get("purpose_classes") or []}
    if purpose_classes and unit_purposes.isdisjoint(set(purpose_classes)):
        return False
    if view_classes and unit_purposes.isdisjoint(set(view_classes)):
        return False
    if media_kind and str(row.get("media_type") or "") != media_kind:
        return False
    if need_kind != "any" and str(row.get("typed_need") or "unclassified") != need_kind:
        return False
    if record_kinds and str(row.get("identity_kind") or "") not in set(record_kinds):
        return False
    if inspection_status and str(row.get("inspection_status") or "") != inspection_status:
        return False
    if reuse_status and str(row.get("reuse_status") or "") != reuse_status:
        return False
    if search_terms and not any(term.lower() in _haystack(row) for term in search_terms):
        return False
    return True


def _index_locator(catalog: dict[str, Any], index_id: str) -> Path | None:
    for row in catalog.get("source_indexes") or []:
        if not isinstance(row, dict):
            raise LookupError("catalog_source_index_invalid")
        if row.get("index_id") != index_id:
            continue
        if row.get("locator_kind") == "file" and row.get("locator"):
            return Path(str(row["locator"]))
    return None


def _retrieval_view_classes(catalog: dict[str, Any], retrieval_view: str | None) -> list[str]:
    if not retrieval_view:
        return []
    views = catalog.get("retrieval_views")
    if not isinstance(views, dict) or not views:
        views = DEFAULT_RETRIEVAL_VIEWS
    if retrieval_view not in views:
        raise LookupError("unknown_retrieval_view")
    values = views.get(retrieval_view)
    if not isinstance(values, list):
        raise LookupError("unknown_retrieval_view")
    return [str(item) for item in values]


def _upsert_index(rows: list[dict[str, Any]], item: dict[str, Any]) -> None:
    for existing in rows:
        if existing.get("index_id") == item.get("index_id"):
            existing.update(item)
            return
    rows.append(item)


def _require_list(value: Any, code: str) -> list[Any]:
    if value is None:
        return []
    if not isinstance(value, list):
        raise LookupError(code)
    return value


def _analysis_index(document: dict[str, Any] | None) -> dict[str, dict[str, Any]]:
    index: dict[str, dict[str, Any]] = {}
    if not document:
        return index
    for row in _require_list(document.get("sources"), "analysis_registry_invalid"):
        if not isinstance(row, dict):
            raise LookupError("analysis_registry_invalid")
        key = str(row.get("source_key") or "")
        if not key:
            continue
        if key in index:
            raise LookupError("duplicate_analysis_source_key")
        records = []
        for record in _require_list(row.get("analysis_records"), "analysis_registry_invalid"):
            if not isinstance(record, dict):
                raise LookupError("analysis_registry_invalid")
            pointer = _pointer(record.get("analysis"))
            inputs = []
            for item in _require_list(record.get("analysis_inputs"), "analysis_registry_invalid"):
                if not isinstance(item, dict):
                    raise LookupError("analysis_registry_invalid")
                inp = _pointer(item)
                if inp:
                    inputs.append({"role": str(item.get("role") or ""), **inp})
            records.append(
                {
                    "status": record.get("status"),
                    "analysis": pointer,
                    "inputs": inputs,
                    "covered_ranges": record.get("covered_ranges"),
                }
            )
        index[key] = {
            "analysis_state": row.get("analysis_state"),
            "duration_seconds": row.get("duration_seconds"),
            "primary_media": _pointer(row.get("primary_media")),
            "records": records,
        }
    return index


def _hash_pointer(
    root: Path,
    pointer: dict[str, str],
    hasher: HashBinder,
    costs: dict[str, int],
    invalidated: set[str],
) -> str:
    path = _contained_path(root, Path(pointer["path"]))
    key = str(path)
    if key in invalidated:
        raise LookupError("path_invalidated_in_operation")
    hold_before = len(hasher.fresh.holds)
    before_fresh = hasher.fresh.fresh_reads
    actual = hasher.sha256(path)
    if hasher.fresh.fresh_reads > before_fresh:
        costs["pointer_files_hashed"] += 1
    else:
        costs["pointer_hash_memo_hits"] += 1
    if len(hasher.fresh.holds) > hold_before:
        invalidated.add(key)
        raise LookupError("path_invalidated_in_operation")
    if actual != pointer["sha256"]:
        invalidated.add(key)
    return actual


def _finite_nonnegative(value: Any) -> float | None:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    number = float(value)
    if not math.isfinite(number) or number < 0:
        return None
    return number


def _covered_ranges(value: Any) -> list[dict[str, float]] | None:
    if not isinstance(value, list) or not value:
        return None
    ranges: list[dict[str, float]] = []
    for item in value:
        if not isinstance(item, dict):
            return None
        start = _finite_nonnegative(item.get("start_seconds"))
        end = _finite_nonnegative(item.get("end_seconds"))
        if start is None or end is None or end < start:
            return None
        ranges.append({"start_seconds": start, "end_seconds": end})
    return ranges


def _sequence_stamps(frames: Any) -> list[float] | None:
    if not isinstance(frames, list) or len(frames) != SEQUENCE_FRAME_COUNT:
        return None
    stamps: list[float] = []
    orders: list[Any] = []
    for frame in frames:
        if not isinstance(frame, dict):
            return None
        stamp = _finite_nonnegative(frame.get("source_timestamp_seconds"))
        if stamp is None:
            return None
        stamps.append(stamp)
        orders.append(frame.get("order"))
    if orders != list(range(1, SEQUENCE_FRAME_COUNT + 1)):
        return None
    for current, following in zip(stamps, stamps[1:]):
        if abs((following - current) - SEQUENCE_CADENCE_SECONDS) > CADENCE_TOLERANCE:
            return None
    return stamps


def _role_pointers(record: dict[str, Any], role: str) -> list[dict[str, str]]:
    found: list[dict[str, str]] = []
    for item in record.get("inputs") or record.get("analysis_inputs") or []:
        if not isinstance(item, dict) or str(item.get("role") or "") != role:
            continue
        pointer = _pointer(item)
        if pointer:
            found.append(pointer)
    return found


def _unique_role_pointer(
    record: dict[str, Any], role: str
) -> tuple[str | None, dict[str, str] | None]:
    found = _role_pointers(record, role)
    if not found:
        return "missing", None
    if len(found) != 1:
        return "duplicate", None
    return None, found[0]


def _complete_parent(
    analysis_by_source: dict[str, dict[str, Any]],
    pointer: dict[str, str],
    source_identity: str,
) -> tuple[str | None, str | None, dict[str, Any] | None]:
    local_complete: list[dict[str, Any]] = []
    local_contradictory = False
    foreign_complete: list[tuple[str, dict[str, Any]]] = []
    for key, source in analysis_by_source.items():
        for record in source.get("records") or []:
            analysis = record.get("analysis") if isinstance(record.get("analysis"), dict) else None
            if not analysis:
                continue
            if analysis.get("path") != pointer.get("path") or analysis.get("sha256") != pointer.get(
                "sha256"
            ):
                continue
            status = record.get("status")
            if key == source_identity:
                if status == COMPLETE_RECORD_STATUS:
                    local_complete.append(record)
                else:
                    local_contradictory = True
            elif status == COMPLETE_RECORD_STATUS:
                foreign_complete.append((key, record))
    if local_contradictory or len(local_complete) > 1:
        return "scoped_parent_ambiguous", None, None
    if len(local_complete) == 1:
        return None, source_identity, local_complete[0]
    if len(foreign_complete) == 1:
        return "scoped_parent_foreign", foreign_complete[0][0], foreign_complete[0][1]
    if foreign_complete:
        return "scoped_parent_ambiguous", None, None
    return "scoped_parent_not_complete", None, None


def _producer_analysis_record(entry: dict[str, Any], analysis_id: str) -> dict[str, Any]:
    analysis = entry.get("analysis") if isinstance(entry.get("analysis"), dict) else None
    if not analysis:
        analysis = {
            "path": str(entry.get("path") or ""),
            "sha256": str(entry.get("sha256") or ""),
        }
    inputs = []
    for item in entry.get("analysis_inputs") or entry.get("inputs") or []:
        if not isinstance(item, dict):
            continue
        pointer = _pointer(item)
        if pointer:
            inputs.append({"role": str(item.get("role") or ""), **pointer})
    return {
        "analysis_id": analysis_id,
        "status": entry.get("status"),
        "analysis": analysis,
        "analysis_inputs": inputs,
        "covered_ranges": entry.get("covered_ranges"),
    }


def _stamps_range_status(stamps: list[float], ranges: list[dict[str, float]]) -> str | None:
    covering = [
        rng
        for rng in ranges
        if all(
            rng["start_seconds"] - CADENCE_TOLERANCE <= stamp <= rng["end_seconds"] + CADENCE_TOLERANCE
            for stamp in stamps
        )
    ]
    if covering:
        return None
    if all(
        any(
            rng["start_seconds"] - CADENCE_TOLERANCE <= stamp <= rng["end_seconds"] + CADENCE_TOLERANCE
            for rng in ranges
        )
        for stamp in stamps
    ):
        return "scoped_timestamps_disjoint"
    return "scoped_timestamps_out_of_range"


def _scoped_declared_cache(
    *,
    catalog_ptr: dict[str, str],
    identity_kind: str,
    frames: Any,
    source_identity: str,
    source: dict[str, Any],
    analysis_by_source: dict[str, dict[str, Any]],
    exact_scoped: list[dict[str, Any]],
    state: Any,
) -> dict[str, Any]:
    empty = {
        "status": "matching_record_not_complete",
        "catalog_analysis_ref": catalog_ptr,
        "matched_registry_records": exact_scoped,
        "registry_analysis_state": state,
        "byte_verify": "not_requested",
        "analysis_binding_ready": False,
    }
    if identity_kind != "source_sequence_unit":
        return empty
    scoped = exact_scoped[0]
    ranges = _covered_ranges(scoped.get("covered_ranges"))
    if ranges is None:
        empty["status"] = "scoped_covered_ranges_invalid"
        return empty
    duration = _finite_nonnegative(source.get("duration_seconds"))
    if duration is None:
        empty["status"] = "scoped_duration_unavailable"
        return empty
    if any(
        rng["start_seconds"] > duration + CADENCE_TOLERANCE
        or rng["end_seconds"] > duration + CADENCE_TOLERANCE
        for rng in ranges
    ):
        empty["status"] = "scoped_range_outside_duration"
        return empty
    parent_role, parent_ptr = _unique_role_pointer(scoped, PARENT_COMPLETE_ROLE)
    if parent_role == "duplicate":
        empty["status"] = "scoped_input_role_ambiguous"
        return empty
    if parent_ptr is None:
        empty["status"] = "scoped_parent_missing"
        return empty
    parent_reason, parent_key, parent = _complete_parent(
        analysis_by_source, parent_ptr, source_identity
    )
    if parent_reason:
        empty["status"] = parent_reason
        return empty
    if parent is None or parent_key != source_identity:
        empty["status"] = "scoped_parent_not_complete"
        return empty
    video_role, scoped_video = _unique_role_pointer(scoped, ORIGINAL_VIDEO_ROLE)
    parent_video_role, parent_video = _unique_role_pointer(parent, ORIGINAL_VIDEO_ROLE)
    if video_role == "duplicate" or parent_video_role == "duplicate":
        empty["status"] = "scoped_input_role_ambiguous"
        return empty
    primary = _pointer(source.get("primary_media"))
    if primary is None:
        empty["status"] = "scoped_primary_media_missing"
        return empty
    if scoped_video is None or parent_video is None:
        empty["status"] = "scoped_original_video_missing"
        return empty
    if scoped_video != parent_video or scoped_video != primary:
        empty["status"] = "scoped_original_not_source_bound"
        return empty
    stamps = _sequence_stamps(frames)
    if stamps is None:
        empty["status"] = "scoped_sequence_frames_invalid"
        return empty
    stamp_status = _stamps_range_status(stamps, ranges)
    if stamp_status:
        empty["status"] = stamp_status
        return empty
    parent_entry = {
        "status": parent.get("status"),
        "path": (parent.get("analysis") or {}).get("path"),
        "sha256": (parent.get("analysis") or {}).get("sha256"),
        "inputs": list(parent.get("inputs") or []),
    }
    return {
        "status": "declared_scoped_agreement",
        "catalog_analysis_ref": catalog_ptr,
        "matched_registry_records": exact_scoped + [parent_entry],
        "registry_analysis_state": state,
        "byte_verify": "not_requested",
        "analysis_binding_ready": False,
        "primary_media": primary,
        "duration_seconds": source.get("duration_seconds"),
    }


def _declared_analysis_cache(
    *,
    row: dict[str, Any],
    analysis_by_source: dict[str, dict[str, Any]] | None,
) -> dict[str, Any]:
    catalog_ptr = _pointer(row.get("analysis_ref"))
    source_identity = str(row.get("source_identity") or "")
    empty = {
        "catalog_analysis_ref": catalog_ptr,
        "matched_registry_records": [],
        "registry_analysis_state": None,
        "byte_verify": "not_requested",
        "analysis_binding_ready": False,
    }
    if analysis_by_source is None:
        empty["status"] = "index_unavailable" if catalog_ptr else "missing_catalog_pointer"
        return empty
    source = analysis_by_source.get(source_identity)
    if source is None:
        empty["status"] = "registry_source_missing"
        return empty
    records = source.get("records") or []
    exact: list[dict[str, Any]] = []
    complete_other: list[dict[str, Any]] = []
    for record in records:
        pointer = record.get("analysis") if isinstance(record.get("analysis"), dict) else None
        if not pointer:
            continue
        entry = {
            "status": record.get("status"),
            "path": pointer.get("path"),
            "sha256": pointer.get("sha256"),
            "inputs": list(record.get("inputs") or []),
        }
        if record.get("status") == SCOPED_RECORD_STATUS:
            entry["covered_ranges"] = record.get("covered_ranges")
        if (
            catalog_ptr
            and pointer.get("path") == catalog_ptr.get("path")
            and pointer.get("sha256") == catalog_ptr.get("sha256")
        ):
            exact.append(entry)
        elif record.get("status") == COMPLETE_RECORD_STATUS:
            complete_other.append(entry)
    state = source.get("analysis_state")
    if catalog_ptr:
        complete_exact = [item for item in exact if item.get("status") == COMPLETE_RECORD_STATUS]
        scoped_exact = [item for item in exact if item.get("status") == SCOPED_RECORD_STATUS]
        held_exact = [
            item
            for item in exact
            if item.get("status") not in {COMPLETE_RECORD_STATUS, SCOPED_RECORD_STATUS}
        ]
        mixed = sum(bool(group) for group in (complete_exact, scoped_exact, held_exact))
        if mixed > 1 or len(scoped_exact) > 1:
            status = "matching_record_status_ambiguous"
            matched = exact
        elif scoped_exact:
            return _scoped_declared_cache(
                catalog_ptr=catalog_ptr,
                identity_kind=str(row.get("identity_kind") or ""),
                frames=row.get("frames"),
                source_identity=source_identity,
                source=source,
                analysis_by_source=analysis_by_source,
                exact_scoped=scoped_exact,
                state=state,
            )
        elif held_exact:
            status = "matching_record_not_complete"
            matched = held_exact
        elif complete_exact and state != USABLE_ANALYSIS_STATE:
            status = "source_analysis_not_usable"
            matched = complete_exact
        elif complete_exact:
            status = "declared_complete_agreement"
            matched = complete_exact
        else:
            status = "declared_pointer_mismatch"
            matched = complete_other
    else:
        if complete_other and state == USABLE_ANALYSIS_STATE:
            status = "registry_complete_declared"
            matched = complete_other
        elif complete_other:
            status = "source_analysis_not_usable"
            matched = complete_other
        else:
            status = "missing_catalog_pointer"
            matched = []
    return {
        "status": status,
        "catalog_analysis_ref": catalog_ptr,
        "matched_registry_records": matched,
        "registry_analysis_state": state,
        "byte_verify": "not_requested",
        "analysis_binding_ready": False,
    }


def _collect_verify_pointers(row: dict[str, Any]) -> list[dict[str, str]]:
    cache = row.get("analysis_cache") if isinstance(row.get("analysis_cache"), dict) else {}
    targets: list[dict[str, str]] = []
    catalog_ptr = cache.get("catalog_analysis_ref") if isinstance(cache, dict) else None
    if isinstance(catalog_ptr, dict) and catalog_ptr.get("path") and catalog_ptr.get("sha256"):
        targets.append({"path": str(catalog_ptr["path"]), "sha256": str(catalog_ptr["sha256"])})
    for record in (cache.get("matched_registry_records") or []) if isinstance(cache, dict) else []:
        if record.get("status") not in {COMPLETE_RECORD_STATUS, SCOPED_RECORD_STATUS}:
            continue
        if record.get("path") and record.get("sha256"):
            targets.append({"path": str(record["path"]), "sha256": str(record["sha256"])})
        for inp in record.get("inputs") or []:
            pointer = _pointer(inp)
            if pointer:
                targets.append(pointer)
    for key, pointer in _row_pointers(row):
        if key in {"source_manifest", "frame", "selected_evidence", "analysis_ref"}:
            targets.append(pointer)
    unique: list[dict[str, str]] = []
    seen: set[tuple[str, str]] = set()
    for pointer in targets:
        item = (pointer["path"], pointer["sha256"])
        if item in seen:
            continue
        seen.add(item)
        unique.append(pointer)
    return unique


def _verify_analysis_cache(
    row: dict[str, Any],
    root: Path,
    hasher: HashBinder,
    costs: dict[str, int],
    invalidated: set[str],
) -> None:
    cache = row.get("analysis_cache")
    if not isinstance(cache, dict):
        return
    if cache.get("status") not in {
        "declared_complete_agreement",
        "registry_complete_declared",
        "declared_scoped_agreement",
    }:
        cache["analysis_binding_ready"] = False
        cache["byte_verify"] = "not_eligible"
        return
    unique = _collect_verify_pointers(row)
    if not unique:
        cache["status"] = "analysis_verification_unavailable"
        cache["byte_verify"] = "unavailable"
        cache["analysis_binding_ready"] = False
        return
    try:
        for pointer in unique:
            actual = _hash_pointer(root, pointer, hasher, costs, invalidated)
            if actual != pointer["sha256"]:
                cache["status"] = "verified_hash_mismatch"
                cache["byte_verify"] = "mismatched"
                cache["analysis_binding_ready"] = False
                return
    except (LookupError, ValueError):
        cache["status"] = "analysis_verification_unavailable"
        cache["byte_verify"] = "unavailable"
        cache["analysis_binding_ready"] = False
        return
    if cache.get("status") == "declared_scoped_agreement":
        cache["byte_verify"] = "agreed"
        primary = _pointer(cache.get("primary_media"))
        if primary is None:
            cache["status"] = "scoped_primary_media_missing"
            cache["analysis_binding_ready"] = False
            return
        matched = cache.get("matched_registry_records") or []
        scoped_rows = [item for item in matched if item.get("status") == SCOPED_RECORD_STATUS]
        parent_rows = [item for item in matched if item.get("status") == COMPLETE_RECORD_STATUS]
        if len(scoped_rows) != 1 or len(parent_rows) != 1:
            cache["status"] = "scoped_parent_ambiguous"
            cache["analysis_binding_ready"] = False
            return
        errors = validate_scoped_source(
            [
                _producer_analysis_record(scoped_rows[0], "scoped"),
                _producer_analysis_record(parent_rows[0], "parent"),
            ],
            primary_media=primary,
            duration_seconds=_finite_nonnegative(cache.get("duration_seconds")),
            root=root,
        )
        if errors:
            cache["status"] = "scoped_producer_validation_failed"
            cache["analysis_binding_ready"] = False
            return
        cache["status"] = "verified_scoped_agreement"
        cache["analysis_binding_ready"] = True
        return
    cache["status"] = "verified_complete_agreement"
    cache["byte_verify"] = "agreed"
    cache["analysis_binding_ready"] = True


def _row_pointers(row: dict[str, Any]) -> list[tuple[str, dict[str, str]]]:
    pointers: list[tuple[str, dict[str, str]]] = []
    for key in ("source_manifest", "analysis_ref", "batch_pointer"):
        pointer = _pointer(row.get(key))
        if pointer:
            pointers.append((key, pointer))
    for item in row.get("selected_evidence") or []:
        pointer = _pointer(item)
        if pointer:
            pointers.append(("selected_evidence", pointer))
    for item in row.get("frames") or []:
        pointer = _pointer(item)
        if pointer:
            pointers.append(("frame", pointer))
    return pointers


def _availability_reason(root: Path, row: dict[str, Any], costs: dict[str, int]) -> str | None:
    for key, pointer in _row_pointers(row):
        costs["files_stat_checked"] += 1
        try:
            _contained_path(root, Path(pointer["path"]))
        except LookupError as exc:
            if str(exc) == "file_missing":
                return f"declared_path_missing_{key}"
            return str(exc)
    return None


def _base_candidate(
    *,
    identity_kind: str,
    typed_need: str,
    source_owned_id: str,
    source_identity: str,
    source_locator: str,
    media_type: str | None,
    source_manifest: dict[str, str] | None,
    analysis_ref: dict[str, str] | None,
    purpose_classes: list[str],
    search_terms: list[str],
    selected_evidence: list[dict[str, str]],
    titles: list[str],
    inspection_status: str | None,
    reuse_status: str | None,
    batch_pointer: dict[str, str] | None,
    reference_unit_id: str | None,
    disposition: str | None,
    bindable: bool,
    frames: list[dict[str, Any]] | None = None,
    transfer_boundary: str | None = None,
    do_not_transfer: str | None = None,
    event_identity: str | None = None,
) -> dict[str, Any]:
    manifest_sha = (source_manifest or {}).get("sha256") or ""
    analysis_sha = (analysis_ref or {}).get("sha256") or ""
    return {
        "identity_kind": identity_kind,
        "typed_need": typed_need,
        "source_owned_id": source_owned_id,
        "reference_unit_id": reference_unit_id,
        "source_identity": source_identity,
        "source_family": _source_family(source_identity),
        "source_locator": source_locator,
        "media_type": media_type,
        "source_manifest": source_manifest,
        "analysis_ref": analysis_ref,
        "batch_pointer": batch_pointer,
        "selected_evidence": selected_evidence,
        "purpose_classes": purpose_classes,
        "search_terms": search_terms,
        "titles": titles,
        "inspection_status": inspection_status,
        "reuse_status": reuse_status,
        "frames": frames or [],
        "transfer_boundary": transfer_boundary,
        "do_not_transfer": do_not_transfer,
        "event_identity": event_identity,
        "media_identity": _media_identity(
            source_identity, source_locator, manifest_sha, analysis_sha
        ),
        "binding_fingerprint": _binding_fingerprint(purpose_classes, selected_evidence),
        "disposition": disposition,
        "bindable": bindable,
    }


def _catalog_rows(
    units: Any,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    bindable: list[dict[str, Any]] = []
    held_rows: list[dict[str, Any]] = []
    for unit in _require_list(units, "catalog_reference_units_invalid"):
        if not isinstance(unit, dict):
            raise LookupError("catalog_reference_units_invalid")
        reason = _held_or_excluded(unit)
        evidence = [
            pointer
            for pointer in (_pointer(item) for item in (unit.get("selected_evidence") or []))
            if pointer
        ]
        row = _base_candidate(
            identity_kind="catalog_reference_unit",
            typed_need="unclassified",
            source_owned_id=str(unit.get("reference_unit_id") or ""),
            source_identity=str(unit.get("source_identity") or ""),
            source_locator=str(unit.get("source_locator") or ""),
            media_type=str(unit.get("media_type") or "") or None,
            source_manifest=_pointer(unit.get("source_manifest")),
            analysis_ref=_pointer(unit.get("analysis_ref")),
            purpose_classes=[str(item) for item in unit.get("purpose_classes") or []],
            search_terms=[str(item) for item in unit.get("search_terms") or []],
            selected_evidence=evidence,
            titles=[str(unit.get("title") or "")],
            inspection_status=str(unit.get("inspection_status") or "") or None,
            reuse_status=str(unit.get("reuse_status") or "") or None,
            batch_pointer=None,
            reference_unit_id=str(unit.get("reference_unit_id") or "") or None,
            disposition=None if reason else "candidate_for_worker_review",
            bindable=reason is None,
        )
        if reason:
            row["hold_reason"] = reason
            held_rows.append(row)
            continue
        bindable.append(row)
    return bindable, held_rows


def _hub_rows(document: dict[str, Any] | None) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    if not document:
        return rows
    for source in _require_list(document.get("sources"), "video_hub_invalid"):
        if not isinstance(source, dict):
            raise LookupError("video_hub_invalid")
        source_key = str(source.get("source_key") or "")
        if not source_key:
            continue
        occurrence = None
        for item in _require_list(source.get("occurrences"), "video_hub_invalid"):
            if not isinstance(item, dict):
                raise LookupError("video_hub_invalid")
            occurrence = item
            break
        manifest = None
        if occurrence:
            manifest = _pointer(
                {
                    "path": occurrence.get("source_index_path"),
                    "sha256": occurrence.get("source_index_sha256"),
                }
            )
        rows.append(
            _base_candidate(
                identity_kind="video_hub_source",
                typed_need="unclassified",
                source_owned_id=source_key,
                source_identity=source_key,
                source_locator=str(source.get("canonical_source_root") or ""),
                media_type="video",
                source_manifest=manifest,
                analysis_ref=None,
                purpose_classes=[],
                search_terms=[],
                selected_evidence=[],
                titles=[str(item) for item in source.get("titles") or [] if item],
                inspection_status=None,
                reuse_status=None,
                batch_pointer=None,
                reference_unit_id=None,
                disposition=None,
                bindable=True,
            )
        )
    return rows


def _image_rows(
    document: dict[str, Any] | None,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    rows: list[dict[str, Any]] = []
    held: list[dict[str, Any]] = []
    if not document:
        return rows, held
    for source in _require_list(document.get("sources"), "image_catalog_invalid"):
        if not isinstance(source, dict):
            raise LookupError("image_catalog_invalid")
        source_id = str(source.get("source_id") or "")
        status = str(source.get("status") or "")
        local_state = str(source.get("local_state") or "")
        original = _pointer(source.get("primary_original"))
        row = _base_candidate(
            identity_kind="image_source",
            typed_need="unclassified",
            source_owned_id=source_id,
            source_identity=str(source.get("source_identity") or ""),
            source_locator=(original or {}).get("path") or str(source.get("source_identity") or ""),
            media_type="image",
            source_manifest=_pointer(source.get("manifest")),
            analysis_ref=None,
            purpose_classes=[],
            search_terms=[],
            selected_evidence=[original] if original else [],
            titles=[str(source.get("source_title") or "")],
            inspection_status=None,
            reuse_status=None,
            batch_pointer=None,
            reference_unit_id=None,
            disposition=None,
            bindable=status not in IMAGE_HOLD_STATUS and local_state != "missing",
        )
        if not row["bindable"]:
            row["hold_reason"] = f"image_status_{status or local_state}"
            held.append(row)
            continue
        rows.append(row)
    return rows, held


def _sequence_pointer_rows(document: dict[str, Any] | None) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    if not document:
        return rows
    seen: set[tuple[str, str]] = set()
    for unit in _require_list(document.get("units"), "sequence_registry_invalid"):
        if not isinstance(unit, dict):
            raise LookupError("sequence_registry_invalid")
        unit_id = str(unit.get("source_sequence_unit_id") or "")
        source_key = str(unit.get("source_key") or "")
        if not unit_id or not source_key:
            continue
        key = (unit_id, source_key)
        if key in seen:
            raise LookupError("duplicate_sequence_registry_id")
        seen.add(key)
        batch = _pointer(unit.get("batch_pointer"))
        rows.append(
            _base_candidate(
                identity_kind="source_sequence_unit",
                typed_need="sequence",
                source_owned_id=unit_id,
                source_identity=source_key,
                source_locator=str(unit.get("source_time_range") or ""),
                media_type="video",
                source_manifest=None,
                analysis_ref=None,
                purpose_classes=[str(item) for item in unit.get("purpose_classes") or []],
                search_terms=[],
                selected_evidence=[],
                titles=[],
                inspection_status=None,
                reuse_status=None,
                batch_pointer=batch,
                reference_unit_id=None,
                disposition=None,
                bindable=True,
            )
        )
    return rows


def _load_sequence_batch(
    root: Path,
    pointer: dict[str, str],
    memo: dict[tuple[str, str], dict[str, Any]],
    costs: dict[str, int],
) -> dict[str, Any]:
    key = (pointer["path"], pointer["sha256"])
    cached = memo.get(key)
    if cached is not None:
        costs["pointer_hash_memo_hits"] += 1
        return cached
    costs["batches_loaded"] += 1
    _path, raw = _contained_file(root, Path(pointer["path"]))
    digest = sha256_bytes(raw)
    costs["batch_bytes_hashed"] += len(raw)
    if digest != pointer["sha256"]:
        raise LookupError("batch_sha_mismatch")
    try:
        document = yaml.safe_load(raw.decode("utf-8"))
    except (UnicodeDecodeError, yaml.YAMLError) as exc:
        raise LookupError("sequence_batch_invalid") from exc
    if not isinstance(document, dict):
        raise LookupError("sequence_batch_invalid")
    if document.get("schema_version") != SEQUENCE_BATCH_VERSION:
        raise LookupError("sequence_batch_invalid")
    if document.get("artifact_type") != "reusable_sequence_unit_batch":
        raise LookupError("sequence_batch_invalid")
    memo[key] = document
    return document


def _enrich_sequence_row(
    row: dict[str, Any],
    root: Path,
    batch_memo: dict[tuple[str, str], dict[str, Any]],
    costs: dict[str, int],
) -> str | None:
    pointer = _pointer(row.get("batch_pointer"))
    if not pointer:
        return "missing_batch_pointer"
    try:
        batch = _load_sequence_batch(root, pointer, batch_memo, costs)
    except LookupError as exc:
        if str(exc) == "file_missing":
            return "batch_missing"
        return str(exc)
    matches = []
    for unit in _require_list(batch.get("units"), "sequence_batch_invalid"):
        if not isinstance(unit, dict):
            raise LookupError("sequence_batch_invalid")
        if unit.get("source_sequence_unit_id") == row.get("source_owned_id") and unit.get(
            "source_key"
        ) == row.get("source_identity"):
            matches.append(unit)
    if not matches:
        return "sequence_unit_missing_from_batch"
    if len(matches) > 1:
        return "duplicate_sequence_batch_unit"
    unit = matches[0]
    frames = []
    for frame in _require_list(unit.get("frames"), "sequence_batch_invalid"):
        if not isinstance(frame, dict):
            raise LookupError("sequence_batch_invalid")
        pointer = _pointer(frame)
        if not pointer:
            continue
        frames.append(
            {
                "order": frame.get("order"),
                "path": pointer["path"],
                "sha256": pointer["sha256"],
                "source_timestamp_seconds": frame.get("source_timestamp_seconds"),
            }
        )
    row["source_manifest"] = _pointer(unit.get("source_manifest"))
    row["analysis_ref"] = _pointer(unit.get("analysis_ref"))
    row["search_terms"] = [str(item) for item in unit.get("search_terms") or []]
    row["purpose_classes"] = [str(item) for item in unit.get("purpose_classes") or []]
    row["frames"] = frames
    row["transfer_boundary"] = str(unit.get("transfer_boundary") or "") or None
    row["do_not_transfer"] = str(unit.get("do_not_transfer") or "") or None
    row["event_identity"] = str(unit.get("event_identity") or "") or None
    row["source_locator"] = str(unit.get("source_time_range") or row.get("source_locator") or "")
    row["media_identity"] = _media_identity(
        str(row.get("source_identity") or ""),
        str(row.get("source_locator") or ""),
        (row.get("source_manifest") or {}).get("sha256") or "",
        (row.get("analysis_ref") or {}).get("sha256") or "",
    )
    row["binding_fingerprint"] = _binding_fingerprint(
        list(row.get("purpose_classes") or []), list(row.get("selected_evidence") or [])
    )
    return None


def _sort_key(row: dict[str, Any]) -> tuple[str, str]:
    return (
        str(row.get("identity_kind") or ""),
        str(row.get("reference_unit_id") or row.get("source_owned_id") or ""),
    )


def _source_record_signature(row: dict[str, Any]) -> str:
    payload = {
        "identity_kind": row.get("identity_kind"),
        "source_owned_id": row.get("source_owned_id"),
        "source_identity": row.get("source_identity"),
        "source_locator": row.get("source_locator"),
        "media_type": row.get("media_type"),
        "source_manifest": row.get("source_manifest"),
        "analysis_ref": row.get("analysis_ref"),
        "batch_pointer": row.get("batch_pointer"),
        "purpose_classes": row.get("purpose_classes"),
        "selected_evidence": row.get("selected_evidence"),
        "frames": row.get("frames"),
        "transfer_boundary": row.get("transfer_boundary"),
        "do_not_transfer": row.get("do_not_transfer"),
        "event_identity": row.get("event_identity"),
        "inspection_status": row.get("inspection_status"),
        "reuse_status": row.get("reuse_status"),
        "search_terms": row.get("search_terms"),
    }
    return sha256_bytes(json.dumps(payload, sort_keys=True).encode("utf-8"))


def _collapse_rows(
    rows: list[dict[str, Any]],
) -> tuple[list[dict[str, Any]], list[dict[str, str]], list[dict[str, str]]]:
    grouped: dict[tuple[str, str], list[dict[str, Any]]] = {}
    for row in rows:
        key = (str(row.get("identity_kind") or ""), str(row.get("source_owned_id") or ""))
        grouped.setdefault(key, []).append(row)
    kept: list[dict[str, Any]] = []
    collapsed: list[dict[str, str]] = []
    holds: list[dict[str, str]] = []
    for key, items in grouped.items():
        signatures = {_source_record_signature(item) for item in items}
        if len(items) == 1:
            kept.append(items[0])
            continue
        if len(signatures) == 1:
            ordered = sorted(items, key=_sort_key)
            kept.append(ordered[0])
            for extra in ordered[1:]:
                collapsed.append(
                    {
                        "kept_source_owned_id": str(ordered[0].get("source_owned_id") or ""),
                        "dropped_source_owned_id": str(extra.get("source_owned_id") or ""),
                        "identity_kind": key[0],
                    }
                )
            continue
        holds.append(
            {
                "reference_unit_id": key[1],
                "reason": "duplicate_identity_ambiguity",
            }
        )
    return kept, collapsed, holds


def _order_matches(rows: list[dict[str, Any]], page_order: str) -> list[dict[str, Any]]:
    if page_order == "unit_id":
        return sorted(rows, key=_sort_key)
    grouped: dict[str, list[dict[str, Any]]] = {}
    for row in rows:
        grouped.setdefault(str(row.get("source_identity") or ""), []).append(row)
    for source in grouped:
        grouped[source].sort(key=_sort_key)
    ordered: list[dict[str, Any]] = []
    sources = sorted(grouped)
    offsets = {source: 0 for source in sources}
    progress = True
    while progress:
        progress = False
        for source in sources:
            offset = offsets[source]
            bucket = grouped[source]
            if offset < len(bucket):
                ordered.append(bucket[offset])
                offsets[source] = offset + 1
                progress = True
    return ordered


def _public_candidate(row: dict[str, Any], search_terms: list[str]) -> dict[str, Any]:
    payload = {
        "identity_kind": row["identity_kind"],
        "typed_need": row["typed_need"],
        "source_owned_id": row["source_owned_id"],
        "reference_unit_id": row["reference_unit_id"],
        "source_identity": row["source_identity"],
        "source_family": row["source_family"],
        "source_locator": row["source_locator"],
        "media_type": row["media_type"],
        "source_manifest": row["source_manifest"],
        "analysis_ref": row["analysis_ref"],
        "batch_pointer": row["batch_pointer"],
        "selected_evidence": row["selected_evidence"],
        "purpose_classes": row["purpose_classes"],
        "search_term_hits": [term for term in search_terms if term.lower() in _haystack(row)],
        "inspection_status": row["inspection_status"],
        "reuse_status": row["reuse_status"],
        "frames": row.get("frames") or [],
        "transfer_boundary": row.get("transfer_boundary"),
        "do_not_transfer": row.get("do_not_transfer"),
        "event_identity": row.get("event_identity"),
        "analysis_cache": row.get("analysis_cache"),
        "analysis_binding_ready": bool((row.get("analysis_cache") or {}).get("analysis_binding_ready")),
        "media_identity": row["media_identity"],
        "binding_fingerprint": row["binding_fingerprint"],
        "local_usage_history_pointer": row.get("local_usage_history_pointer"),
        "disposition": row["disposition"],
        "bindable": row["bindable"],
    }
    return payload


def _assessment_scope(
    *,
    metadata_match_count: int,
    byte_integrity_requested: bool,
) -> dict[str, str]:
    return {
        "navigation": "found_candidates" if metadata_match_count else "no_candidates",
        "selected_page_byte_integrity": (
            "selected_metadata_page" if byte_integrity_requested else "not_requested"
        ),
        "selection": "unknown",
        "semantic_quality": "unknown",
        "source_identity_counts": "source_identity_string_uniqueness_only",
    }


def lookup(
    *,
    root: Path = ROOT,
    catalog_rel: Path = DEFAULT_CATALOG,
    catalog_sha256: str | None = None,
    named_gap_id: str,
    source_families: list[str] | None = None,
    purpose_classes: list[str] | None = None,
    search_terms: list[str] | None = None,
    media_kind: str | None = None,
    inspection_status: str | None = None,
    reuse_status: str | None = None,
    album_title_index: str | None = None,
    batch_size: int = 20,
    cursor: int = 0,
    index_mode: str = "catalog",
    need_kind: str = "any",
    record_kinds: list[str] | None = None,
    retrieval_view: str | None = None,
    page_order: str = "unit_id",
    check_availability: bool = False,
    require_analysis: bool = False,
    verify_index_hashes: bool = False,
    analysis_registry_rel: Path | None = None,
    sequence_registry_rel: Path | None = None,
    video_hub_rel: Path | None = None,
    image_catalog_rel: Path | None = None,
    max_held_excluded: int = 200,
) -> dict[str, Any]:
    if not named_gap_id.strip():
        raise LookupError("named_gap_id is required")
    if batch_size < 1:
        raise LookupError("batch_size must be at least 1")
    if cursor < 0:
        raise LookupError("cursor must be at least 0")
    if max_held_excluded < 0:
        raise LookupError("max_held_excluded must be at least 0")
    index_mode = (index_mode or "catalog").strip()
    if index_mode not in INDEX_MODES:
        raise LookupError("unsupported_index_mode")
    need_kind = (need_kind or "any").strip()
    if need_kind not in NEED_KINDS:
        raise LookupError("unsupported_need_kind")
    page_order = (page_order or "unit_id").strip()
    if page_order not in PAGE_ORDERS:
        raise LookupError("unsupported_page_order")
    kinds = record_kinds or []
    if any(kind not in RECORD_KINDS for kind in kinds):
        raise LookupError("unsupported_record_kind")
    catalog_document, catalog_digest, catalog_size = _load_yaml_mapping(
        root,
        catalog_rel,
        required=True,
        missing_code="catalog file is missing",
        invalid_code="catalog must contain an object",
    )
    if catalog_document is None or catalog_digest is None:
        raise LookupError("catalog file is missing")
    if catalog_sha256 and catalog_sha256 != catalog_digest:
        raise LookupError("stale_catalog_sha256")
    if catalog_document.get("schema_version") != SCHEMA_VERSION:
        raise LookupError("unexpected catalog schema_version")
    view_classes = _retrieval_view_classes(catalog_document, retrieval_view)
    costs = {
        "catalog_units_scanned": 0,
        "index_rows_scanned": 0,
        "yaml_documents_loaded": 1,
        "index_bytes_hashed": catalog_size,
        "batches_loaded": 0,
        "batch_bytes_hashed": 0,
        "pointer_files_hashed": 0,
        "pointer_hash_memo_hits": 0,
        "files_stat_checked": 0,
        "duplicates_collapsed": 0,
        "duplicate_identity_holds": 0,
        "analysis_markdown_opened": 0,
    }
    indexes_consulted: list[dict[str, Any]] = []
    _upsert_index(
        indexes_consulted,
        {
            "index_id": "REFERENCE_MANAGEMENT_CATALOG",
            "locator": catalog_rel.as_posix(),
            "loaded": True,
            "digest": catalog_digest,
            "byte_size": catalog_size,
            "row_count": len(catalog_document.get("reference_units") or []),
            "status": "loaded",
            "role": "catalog_reference_units",
        },
    )
    for declared in catalog_document.get("source_indexes") or []:
        if not isinstance(declared, dict):
            raise LookupError("catalog_source_index_invalid")
        if declared.get("index_id"):
            _upsert_index(
                indexes_consulted,
                {
                    "index_id": declared.get("index_id"),
                    "locator": declared.get("locator"),
                    "locator_kind": declared.get("locator_kind"),
                    "declared_status": declared.get("status"),
                    "loaded": False,
                    "digest": None,
                    "byte_size": 0,
                    "row_count": 0,
                    "status": "declared",
                    "role": "catalog_source_index_pointer",
                },
            )
    analysis_rel = (
        analysis_registry_rel
        or _index_locator(catalog_document, "VIDEO_ANALYSIS_REGISTRY")
        or DEFAULT_ANALYSIS_REGISTRY
    )
    analysis_document, analysis_digest, analysis_size = _load_yaml_mapping(
        root,
        analysis_rel,
        required=analysis_registry_rel is not None,
        missing_code="analysis_registry_missing",
        invalid_code="analysis_registry_invalid",
    )
    if analysis_document is not None:
        costs["yaml_documents_loaded"] += 1
        costs["index_bytes_hashed"] += analysis_size
    analysis_by_source = _analysis_index(analysis_document)
    _upsert_index(
        indexes_consulted,
        {
            "index_id": "VIDEO_ANALYSIS_REGISTRY",
            "locator": analysis_rel.as_posix(),
            "loaded": analysis_document is not None,
            "digest": analysis_digest,
            "byte_size": analysis_size,
            "row_count": len(analysis_by_source),
            "status": "loaded" if analysis_document is not None else "missing",
            "role": "analysis_pointer_cache",
        },
    )
    sequence_document = None
    sequence_digest = None
    sequence_size = 0
    sequence_rel = sequence_registry_rel or DEFAULT_SEQUENCE_REGISTRY
    if index_mode == "multi" or sequence_registry_rel is not None:
        sequence_document, sequence_digest, sequence_size = _load_yaml_mapping(
            root,
            sequence_rel,
            required=sequence_registry_rel is not None,
            missing_code="sequence_registry_missing",
            invalid_code="sequence_registry_invalid",
        )
        if sequence_document is not None:
            costs["yaml_documents_loaded"] += 1
            costs["index_bytes_hashed"] += sequence_size
        _upsert_index(
            indexes_consulted,
            {
                "index_id": "SEQUENCE_UNIT_REGISTRY",
                "locator": sequence_rel.as_posix(),
                "loaded": sequence_document is not None,
                "digest": sequence_digest,
                "byte_size": sequence_size,
                "row_count": len((sequence_document or {}).get("units") or []),
                "status": "loaded" if sequence_document is not None else "missing",
                "role": "source_sequence_unit_pointers",
            },
        )
    hub_document = None
    image_document = None
    if index_mode == "multi":
        hub_rel = (
            video_hub_rel
            or _index_locator(catalog_document, "VIDEO_SOURCE_HUB")
            or DEFAULT_VIDEO_HUB
        )
        hub_document, hub_digest, hub_size = _load_yaml_mapping(
            root,
            hub_rel,
            required=video_hub_rel is not None,
            missing_code="video_hub_missing",
            invalid_code="video_hub_invalid",
        )
        if hub_document is not None:
            costs["yaml_documents_loaded"] += 1
            costs["index_bytes_hashed"] += hub_size
        _upsert_index(
            indexes_consulted,
            {
                "index_id": "VIDEO_SOURCE_HUB",
                "locator": hub_rel.as_posix(),
                "loaded": hub_document is not None,
                "digest": hub_digest,
                "byte_size": hub_size,
                "row_count": len((hub_document or {}).get("sources") or []),
                "status": "loaded" if hub_document is not None else "missing",
                "role": "video_source_family",
            },
        )
        image_rel = (
            image_catalog_rel
            or _index_locator(catalog_document, "IMAGE_SOURCE_HUB")
            or DEFAULT_IMAGE_CATALOG
        )
        image_document, image_digest, image_size = _load_yaml_mapping(
            root,
            image_rel,
            required=image_catalog_rel is not None,
            missing_code="image_catalog_missing",
            invalid_code="image_catalog_invalid",
        )
        if image_document is not None:
            costs["yaml_documents_loaded"] += 1
            costs["index_bytes_hashed"] += image_size
        _upsert_index(
            indexes_consulted,
            {
                "index_id": "IMAGE_SOURCE_HUB",
                "locator": image_rel.as_posix(),
                "loaded": image_document is not None,
                "digest": image_digest,
                "byte_size": image_size,
                "row_count": len((image_document or {}).get("sources") or []),
                "status": "loaded" if image_document is not None else "missing",
                "role": "image_source_family",
            },
        )
    catalog_rows, catalog_held = _catalog_rows(catalog_document.get("reference_units"))
    costs["catalog_units_scanned"] = len(catalog_rows) + len(catalog_held)
    emitted = list(catalog_rows)
    held_rows = list(catalog_held)
    if index_mode == "multi":
        hub_rows = _hub_rows(hub_document)
        image_rows, image_held = _image_rows(image_document)
        sequence_rows = _sequence_pointer_rows(sequence_document)
        costs["index_rows_scanned"] = len(hub_rows) + len(image_rows) + len(sequence_rows)
        emitted.extend(hub_rows)
        emitted.extend(image_rows)
        emitted.extend(sequence_rows)
        held_rows.extend(image_held)
    families = source_families or []
    purposes = purpose_classes or []
    terms = search_terms or []
    match_kwargs = {
        "source_families": families,
        "purpose_classes": purposes,
        "view_classes": view_classes,
        "search_terms": terms,
        "media_kind": media_kind,
        "need_kind": need_kind,
        "record_kinds": kinds,
    }
    held: list[dict[str, str]] = []
    for row in held_rows:
        held.append(
            {
                "reference_unit_id": str(row.get("reference_unit_id") or row.get("source_owned_id") or ""),
                "reason": str(row.get("hold_reason") or "held"),
            }
        )
    bindable_status = None if _requested_held(inspection_status, reuse_status) else inspection_status
    bindable_reuse = None if _requested_held(inspection_status, reuse_status) else reuse_status
    selected: list[dict[str, Any]] = []
    batch_memo: dict[tuple[str, str], dict[str, Any]] = {}
    for row in emitted:
        row["local_usage_history_pointer"] = album_title_index
        if row.get("identity_kind") == "source_sequence_unit":
            if not _matches(row, **match_kwargs, inspection_status=None, reuse_status=None):
                cheap = dict(match_kwargs)
                cheap["search_terms"] = []
                if not _matches(row, **cheap, inspection_status=None, reuse_status=None):
                    continue
            reason = _enrich_sequence_row(row, root, batch_memo, costs)
            if reason:
                held.append(
                    {
                        "reference_unit_id": str(row.get("source_owned_id") or ""),
                        "reason": reason,
                    }
                )
                continue
        if not _matches(
            row,
            **match_kwargs,
            inspection_status=bindable_status,
            reuse_status=bindable_reuse,
        ):
            continue
        if _requested_held(inspection_status, reuse_status):
            continue
        selected.append(row)
    selected, collapsed, ambiguous = _collapse_rows(selected)
    costs["duplicates_collapsed"] = len(collapsed)
    costs["duplicate_identity_holds"] = len(ambiguous)
    held.extend(ambiguous)
    metadata_ordered = _order_matches(selected, page_order)
    if cursor > 0 and cursor >= len(metadata_ordered):
        raise LookupError("cursor_out_of_range")
    metadata_page = metadata_ordered[cursor : cursor + batch_size]
    next_cursor = (
        cursor + len(metadata_page)
        if cursor + len(metadata_page) < len(metadata_ordered)
        else None
    )
    hasher = (
        HashBinder(root, profile="canonical_gate")
        if require_analysis or verify_index_hashes
        else None
    )
    invalidated: set[str] = set()
    page: list[dict[str, Any]] = []
    for row in metadata_page:
        row["analysis_cache"] = _declared_analysis_cache(
            row=row,
            analysis_by_source=analysis_by_source if analysis_document is not None else None,
        )
        if check_availability:
            availability = _availability_reason(root, row, costs)
            if availability:
                held.append(
                    {
                        "reference_unit_id": str(
                            row.get("reference_unit_id") or row.get("source_owned_id") or ""
                        ),
                        "reason": availability,
                    }
                )
                continue
        if hasher is not None:
            _verify_analysis_cache(row, root, hasher, costs, invalidated)
            if require_analysis and not (row.get("analysis_cache") or {}).get(
                "analysis_binding_ready"
            ):
                held.append(
                    {
                        "reference_unit_id": str(
                            row.get("reference_unit_id") or row.get("source_owned_id") or ""
                        ),
                        "reason": "analysis_evidence_not_ready",
                    }
                )
                continue
        page.append(row)
    if hasher is not None:
        for msg in hasher.verify_publication():
            for key in hasher.fresh.rows:
                if key in msg:
                    invalidated.add(key)
        kept_page: list[dict[str, Any]] = []
        for row in page:
            cache = row.get("analysis_cache") if isinstance(row.get("analysis_cache"), dict) else {}
            if not cache.get("analysis_binding_ready"):
                kept_page.append(row)
                continue
            tainted = False
            for pointer in _collect_verify_pointers(row):
                try:
                    resolved = _contained_path(root, Path(pointer["path"]))
                except LookupError:
                    tainted = True
                    break
                if str(resolved) in invalidated:
                    tainted = True
                    break
            if tainted:
                cache["analysis_binding_ready"] = False
                cache["status"] = "analysis_verification_unavailable"
                cache["byte_verify"] = "unavailable"
                held.append(
                    {
                        "reference_unit_id": str(
                            row.get("reference_unit_id") or row.get("source_owned_id") or ""
                        ),
                        "reason": "analysis_evidence_not_ready",
                    }
                )
                continue
            kept_page.append(row)
        page = kept_page
    diagnostics: list[dict[str, Any]] = []
    if _requested_held(inspection_status, reuse_status):
        for row in held_rows:
            if inspection_status and str(row.get("inspection_status") or "") != inspection_status:
                continue
            if reuse_status and str(row.get("reuse_status") or "") != reuse_status:
                continue
            if not _matches(
                row,
                **match_kwargs,
                inspection_status=None,
                reuse_status=None,
            ):
                continue
            if len(diagnostics) >= max_held_excluded:
                break
            diagnostics.append(
                {
                    "reference_unit_id": row.get("reference_unit_id"),
                    "source_owned_id": row.get("source_owned_id"),
                    "source_identity": row.get("source_identity"),
                    "inspection_status": row.get("inspection_status"),
                    "reuse_status": row.get("reuse_status"),
                    "reason": row.get("hold_reason"),
                    "bindable": False,
                    "disposition": row.get("reuse_status") or row.get("inspection_status"),
                }
            )
    query = {
        "named_gap_id": named_gap_id,
        "source_families": families,
        "purpose_classes": purposes,
        "search_terms": terms,
        "media_kind": media_kind,
        "inspection_status": inspection_status,
        "reuse_status": reuse_status,
        "album_title_index": album_title_index,
        "batch_size": batch_size,
        "cursor": cursor,
        "index_mode": index_mode,
        "need_kind": need_kind,
        "record_kinds": kinds,
        "retrieval_view": retrieval_view,
        "page_order": page_order,
        "check_availability": check_availability,
        "require_analysis": require_analysis,
        "verify_index_hashes": verify_index_hashes,
        "max_held_excluded": max_held_excluded,
    }
    match_sources = {str(item.get("source_identity") or "") for item in metadata_ordered}
    page_sources = {str(item.get("source_identity") or "") for item in page}
    page_verified_count = sum(
        1
        for item in page
        if (item.get("analysis_cache") or {}).get("analysis_binding_ready")
    )
    coverage = {
        "metadata_match_count": len(metadata_ordered),
        "page_verified_count": page_verified_count,
        "match_count": len(metadata_ordered),
        "returned_count": len(page),
        "distinct_source_count": len(match_sources),
        "returned_source_count": len(page_sources),
        "distinct_media_identity_count": len(
            {str(item.get("media_identity") or "") for item in metadata_ordered}
        ),
        "truncated": next_cursor is not None,
        "query_exhausted": next_cursor is None,
        "held_excluded_count": len(held),
        "held_excluded_truncated": len(held) > max_held_excluded,
        "collapsed_duplicate_count": len(collapsed),
        "duplicate_identity_holds": len(ambiguous),
        "verification_scope": (
            "selected_metadata_page"
            if require_analysis or verify_index_hashes
            else "navigation_declared_only"
        ),
        "metadata_page_count": len(metadata_page),
    }
    if not metadata_ordered:
        status = "no_match"
        reason = "no_local_fit"
    elif page or next_cursor is not None:
        status = "pass"
        reason = None
    else:
        status = "no_match"
        reason = "no_local_fit"
    return {
        "status": status,
        "named_gap_id": named_gap_id,
        "query_digest": sha256_bytes(json.dumps(query, sort_keys=True).encode("utf-8")),
        "catalog_digest": catalog_digest,
        "index_receipts": [
            {
                "index_id": row.get("index_id"),
                "locator": row.get("locator"),
                "digest": row.get("digest"),
                "byte_size": row.get("byte_size"),
                "loaded": row.get("loaded"),
            }
            for row in indexes_consulted
        ],
        "match_count": len(metadata_ordered),
        "returned_count": len(page),
        "next_cursor": next_cursor,
        "candidates": [_public_candidate(row, terms) for row in page],
        "held_excluded": held[:max_held_excluded],
        "nonbindable_diagnostics": diagnostics,
        "collapsed_duplicates": collapsed[:20],
        "coverage": coverage,
        "cost": costs,
        "indexes_consulted": indexes_consulted,
        "ranking": None,
        "selection": None,
        "assessment_scope": _assessment_scope(
            metadata_match_count=len(metadata_ordered),
            byte_integrity_requested=bool(require_analysis or verify_index_hashes),
        ),
        "reason": reason,
    }


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Pointer-only reference catalog lookup")
    parser.add_argument("--repo-root", default=str(ROOT))
    parser.add_argument("--catalog", default=str(DEFAULT_CATALOG))
    parser.add_argument("--catalog-sha256")
    parser.add_argument("--named-gap-id", required=True)
    parser.add_argument("--source-family", action="append", default=[])
    parser.add_argument("--purpose-class", action="append", default=[])
    parser.add_argument("--search-term", action="append", default=[])
    parser.add_argument("--media-kind")
    parser.add_argument("--inspection-status")
    parser.add_argument("--reuse-status")
    parser.add_argument("--album-title-index")
    parser.add_argument("--batch-size", type=int, default=20)
    parser.add_argument("--cursor", type=int, default=0)
    parser.add_argument("--index-mode", default="catalog")
    parser.add_argument("--need-kind", default="any")
    parser.add_argument("--record-kind", action="append", default=[])
    parser.add_argument("--retrieval-view")
    parser.add_argument("--page-order", default="unit_id")
    parser.add_argument("--check-availability", action="store_true")
    parser.add_argument("--require-analysis", action="store_true")
    parser.add_argument("--verify-index-hashes", action="store_true")
    parser.add_argument("--analysis-registry")
    parser.add_argument("--sequence-registry")
    parser.add_argument("--video-hub")
    parser.add_argument("--image-catalog")
    parser.add_argument("--max-held-excluded", type=int, default=200)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        result = lookup(
            root=Path(args.repo_root),
            catalog_rel=Path(args.catalog),
            catalog_sha256=args.catalog_sha256,
            named_gap_id=args.named_gap_id,
            source_families=args.source_family,
            purpose_classes=args.purpose_class,
            search_terms=args.search_term,
            media_kind=args.media_kind,
            inspection_status=args.inspection_status,
            reuse_status=args.reuse_status,
            album_title_index=args.album_title_index,
            batch_size=args.batch_size,
            cursor=args.cursor,
            index_mode=args.index_mode,
            need_kind=args.need_kind,
            record_kinds=args.record_kind,
            retrieval_view=args.retrieval_view,
            page_order=args.page_order,
            check_availability=args.check_availability,
            require_analysis=args.require_analysis,
            verify_index_hashes=args.verify_index_hashes,
            analysis_registry_rel=Path(args.analysis_registry) if args.analysis_registry else None,
            sequence_registry_rel=Path(args.sequence_registry) if args.sequence_registry else None,
            video_hub_rel=Path(args.video_hub) if args.video_hub else None,
            image_catalog_rel=Path(args.image_catalog) if args.image_catalog else None,
            max_held_excluded=args.max_held_excluded,
        )
    except LookupError as exc:
        print(json.dumps({"status": "hold", "reason": str(exc)}, ensure_ascii=False), file=sys.stderr)
        return 1
    print(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True))
    return 0 if result["status"] != "no_match" else 3


if __name__ == "__main__":
    raise SystemExit(main())
