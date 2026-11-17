#!/usr/bin/env python3
"""Assemble an explicit source-bound reference comparison packet.

Consumes a lookup JSON page plus a request that names candidate ids and
window/individual evidence pointers. Verifies contained paths, current index
bytes, page budget, original-media provenance, and the exact five-frame
one-second Sequence contract. Never ranks, selects, scores diversity, infers
a semantic event, authors an observation, or grants creative PASS.
"""

from __future__ import annotations

import argparse
import html
import json
import math
import sys
from pathlib import Path
from typing import Any
from urllib.parse import unquote, urlparse

import yaml

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))
from lib.idol_artifact_integrity import HashBinder, atomic_cas_replace
import idol_reference_catalog_lookup as catalog_lookup

ROOT = Path(__file__).resolve().parents[1]
CONTRACT = "idol_reference_comparison_packet.v1"
SEQUENCE_FRAME_COUNT = 5
SEQUENCE_CADENCE_SECONDS = 1.0
CADENCE_TOLERANCE = 0.001
EVIDENCE_KINDS = frozenset(
    {
        "sequence_window",
        "individual_still",
        "source_window",
        "contact_sheet_navigation",
        "audio_measurement_window",
    }
)
NAMED_WINDOWS = frozenset({"sequence_window", "source_window", "audio_measurement_window"})
BIND_FROM_LOOKUP = frozenset({"frames", "selected_evidence"})
FORBIDDEN_REQUEST_KEYS = frozenset(
    {
        "ranking",
        "selection",
        "best_candidate",
        "diversity_score",
        "winner",
        "semantic_event",
        "observed_facts",
        "source_flow_reading",
    }
)
POINTER_ROLE_BY_KIND = {
    "sequence_window": "sequence_frame",
    "individual_still": "individual_still",
    "contact_sheet_navigation": "contact_sheet_navigation",
    "source_window": "source_window_pointer",
    "audio_measurement_window": "audio_measurement_window_pointer",
}
LOOKUP_COPY_FIELDS = (
    "identity_kind",
    "typed_need",
    "source_owned_id",
    "reference_unit_id",
    "source_identity",
    "source_family",
    "source_locator",
    "media_type",
    "source_manifest",
    "analysis_ref",
    "batch_pointer",
    "purpose_classes",
    "inspection_status",
    "reuse_status",
    "event_identity",
    "transfer_boundary",
    "do_not_transfer",
    "titles",
    "media_identity",
    "binding_fingerprint",
    "disposition",
    "bindable",
)
IMAGE_SUFFIXES = {".png", ".jpg", ".jpeg", ".webp", ".gif"}


class PacketError(RuntimeError):
    def __init__(self, reason: str) -> None:
        super().__init__(reason)
        self.reason = reason


def canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"), sort_keys=True)


def sha256_text(text: str) -> str:
    return catalog_lookup.sha256_bytes(text.encode("utf-8"))


def is_hex_sha256(value: Any) -> bool:
    if not isinstance(value, str) or len(value) != 64:
        return False
    try:
        int(value, 16)
    except ValueError:
        return False
    return True


def finite_nonnegative(value: Any) -> float | None:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    number = float(value)
    if not math.isfinite(number) or number < 0:
        return None
    return number


def declared_duration(document: dict[str, Any]) -> float | None:
    duration = finite_nonnegative(document.get("duration_seconds"))
    if duration is not None:
        return duration
    for media in document.get("media") or []:
        if isinstance(media, dict):
            item_duration = finite_nonnegative(media.get("duration_seconds"))
            if item_duration is not None:
                return item_duration
    discovery = document.get("discovery_metadata")
    if isinstance(discovery, dict):
        return finite_nonnegative(discovery.get("duration_seconds"))
    return None


def map_lookup_error(exc: catalog_lookup.LookupError) -> PacketError:
    reason = str(exc)
    if reason == "symlink_refused":
        return PacketError("symlink_refused")
    if reason == "file_missing":
        return PacketError("file_missing")
    return PacketError("path_escapes_root")


def contained_existing(root: Path, rel: str) -> Path:
    try:
        return catalog_lookup._contained_path(root, Path(rel))
    except catalog_lookup.LookupError as exc:
        raise map_lookup_error(exc) from exc


def contained_new_file(root: Path, rel: str) -> Path:
    path = Path(rel)
    if not rel or path.is_absolute() or ".." in path.parts:
        raise PacketError("path_escapes_root")
    declared = root / path
    cursor = declared if declared.exists() or declared.is_symlink() else declared.parent
    while True:
        if cursor.is_symlink():
            raise PacketError("symlink_refused")
        if cursor == root or cursor == cursor.parent:
            break
        cursor = cursor.parent
    resolved_root = root.resolve()
    try:
        declared.resolve().relative_to(resolved_root)
        declared.parent.resolve().relative_to(resolved_root)
    except ValueError as exc:
        raise PacketError("path_escapes_root") from exc
    return declared


def hash_existing(hasher: HashBinder, path: Path) -> str:
    before = len(hasher.fresh.holds)
    try:
        digest = hasher.sha256(path)
    except ValueError as exc:
        raise PacketError("snapshot_inconsistent") from exc
    if len(hasher.fresh.holds) > before:
        raise PacketError("snapshot_inconsistent")
    return digest


def bind_existing_bytes(hasher: HashBinder, path: Path, raw: bytes) -> str:
    before = len(hasher.fresh.holds)
    try:
        digest = hasher.bind_bytes(path, raw)
    except ValueError as exc:
        raise PacketError("snapshot_inconsistent") from exc
    if len(hasher.fresh.holds) > before:
        raise PacketError("snapshot_inconsistent")
    return digest


def file_uri(path: Path) -> str:
    return path.resolve().as_uri()


def path_from_file_uri(uri: str) -> Path:
    parsed = urlparse(uri)
    if parsed.scheme != "file":
        raise PacketError("html_uri_not_file")
    return Path(unquote(parsed.path))


def assessment_scope(*, hashed: bool, freshness_verified: bool) -> dict[str, str]:
    scope = {
        "navigation": "explicit_request_only",
        "selected_page_byte_integrity": (
            "requested_evidence_hashed" if hashed else "not_performed"
        ),
        "selection": "unknown",
        "semantic_quality": "unknown",
        "observation_authorship": "not_authored",
        "sequence_unit_rule": "five_frames_one_unit",
        "contact_sheet_counts_as_units": "0",
    }
    scope["source_freshness"] = (
        "verified_current_index_bytes" if freshness_verified else "not_verified"
    )
    return scope


def hold_packet(reason: str, *, freshness_verified: bool = False) -> dict[str, Any]:
    return {
        "schema_version": CONTRACT,
        "status": "hold",
        "reason": reason,
        "candidates": [],
        "missing_or_held": [],
        "render": None,
        "cost": {
            "lookup_candidates_indexed": 0,
            "evidence_files_hashed": 0,
            "evidence_bytes_hashed": 0,
            "render_cells": 0,
        },
        "assessment_scope": assessment_scope(
            hashed=False, freshness_verified=freshness_verified
        ),
        "freshness": {"verified": False, "method": None},
    }


def copy_lookup_row(row: dict[str, Any]) -> dict[str, Any]:
    return {key: row.get(key) for key in LOOKUP_COPY_FIELDS}


def validate_request(
    request: dict[str, Any],
) -> tuple[dict[str, Any], list[dict[str, Any]], list[dict[str, Any]]]:
    if FORBIDDEN_REQUEST_KEYS.intersection(request):
        raise PacketError("forbidden_ranking_or_semantic_field")
    if request.get("schema_version") != CONTRACT:
        raise PacketError("unexpected_request_schema_version")
    named_gap_id = str(request.get("named_gap_id") or "").strip()
    if not named_gap_id:
        raise PacketError("named_gap_id_required")
    freshness = request.get("source_freshness")
    if not isinstance(freshness, dict):
        raise PacketError("source_freshness_required")
    catalog_sha256 = freshness.get("catalog_sha256")
    if not is_hex_sha256(catalog_sha256):
        raise PacketError("source_freshness_required")
    budget = request.get("page_budget")
    if not isinstance(budget, dict):
        raise PacketError("page_budget_required")

    def require_int(value: Any, minimum: int) -> int:
        if isinstance(value, bool) or not isinstance(value, int) or value < minimum:
            raise PacketError("page_budget_required")
        return value

    page_budget = {
        "max_candidates": require_int(budget.get("max_candidates"), 1),
        "max_evidence_items": require_int(budget.get("max_evidence_items"), 1),
        "max_render_cells": require_int(budget.get("max_render_cells"), 0),
    }
    candidates = request.get("requested_candidates")
    if not isinstance(candidates, list) or not candidates:
        raise PacketError("requested_candidates_required")
    seen_ids: set[str] = set()
    normalized_candidates: list[dict[str, Any]] = []
    for item in candidates:
        if not isinstance(item, dict):
            raise PacketError("requested_candidates_invalid")
        request_id = str(item.get("request_id") or "").strip()
        identity_kind = str(item.get("identity_kind") or "").strip()
        source_owned_id = str(item.get("source_owned_id") or "").strip()
        reference_unit_id = str(item.get("reference_unit_id") or "").strip()
        if not request_id:
            raise PacketError("request_id_required")
        if request_id in seen_ids:
            raise PacketError("duplicate_request_id")
        if not identity_kind:
            raise PacketError("identity_kind_required")
        if not source_owned_id and not reference_unit_id:
            raise PacketError("source_owned_id_or_reference_unit_id_required")
        seen_ids.add(request_id)
        normalized_candidates.append(
            {
                "request_id": request_id,
                "identity_kind": identity_kind,
                "source_owned_id": source_owned_id or None,
                "reference_unit_id": reference_unit_id or None,
            }
        )
    evidence_requests = request.get("evidence_requests")
    if not isinstance(evidence_requests, list) or not evidence_requests:
        raise PacketError("evidence_requests_required")
    normalized_evidence: list[dict[str, Any]] = []
    for item in evidence_requests:
        if not isinstance(item, dict):
            raise PacketError("evidence_requests_invalid")
        request_id = str(item.get("request_id") or "").strip()
        kind = str(item.get("evidence_kind") or "").strip()
        if request_id not in seen_ids:
            raise PacketError("unknown_evidence_request_id")
        if kind not in EVIDENCE_KINDS:
            raise PacketError("unsupported_evidence_kind")
        bind_from = item.get("bind_from_lookup")
        if bind_from is not None:
            bind_from = str(bind_from).strip()
            if bind_from not in BIND_FROM_LOOKUP:
                raise PacketError("unsupported_bind_from_lookup")
        pointers = item.get("pointers") or []
        if pointers and not isinstance(pointers, list):
            raise PacketError("evidence_pointers_invalid")
        window = item.get("window")
        if window is not None and not isinstance(window, dict):
            raise PacketError("window_invalid")
        normalized_evidence.append(
            {
                "request_id": request_id,
                "evidence_kind": kind,
                "bind_from_lookup": bind_from,
                "pointers": list(pointers or []),
                "window": window,
                "before_context": item.get("before_context"),
                "after_context": item.get("after_context"),
                "context_manifest": item.get("context_manifest"),
                "source_media": item.get("source_media"),
            }
        )
    if len(normalized_candidates) > page_budget["max_candidates"]:
        raise PacketError("page_budget_candidates_exceeded")
    return (
        {
            "named_gap_id": named_gap_id,
            "catalog_sha256": str(catalog_sha256),
            "lookup_query_digest": freshness.get("lookup_query_digest"),
            "page_budget": page_budget,
        },
        normalized_candidates,
        normalized_evidence,
    )


def verify_index_freshness(
    root: Path, lookup: dict[str, Any], request_digest: str, hasher: HashBinder
) -> dict[str, Any]:
    attested = lookup.get("catalog_digest")
    if not is_hex_sha256(attested):
        raise PacketError("lookup_result_missing_catalog_digest")
    if attested != request_digest:
        raise PacketError("stale_catalog_sha256")
    receipts = lookup.get("index_receipts") or lookup.get("indexes_consulted") or []
    if not isinstance(receipts, list) or not receipts:
        raise PacketError("lookup_index_receipts_required")
    verified: list[dict[str, Any]] = []
    catalog_actual = None
    for row in receipts:
        if not isinstance(row, dict) or not row.get("loaded"):
            continue
        locator = row.get("locator")
        digest = row.get("digest")
        if not locator or not is_hex_sha256(digest):
            continue
        path = contained_existing(root, str(locator))
        actual = hash_existing(hasher, path)
        if actual != digest:
            raise PacketError("stale_index_bytes")
        record = {
            "index_id": row.get("index_id"),
            "locator": str(locator),
            "sha256": actual,
        }
        verified.append(record)
        if row.get("index_id") == "REFERENCE_MANAGEMENT_CATALOG":
            catalog_actual = actual
    if catalog_actual is None:
        raise PacketError("catalog_index_receipt_required")
    if catalog_actual != attested:
        raise PacketError("stale_index_bytes")
    return {
        "attested_catalog_digest": attested,
        "verified": True,
        "method": "rehashed_lookup_index_receipts",
        "verified_indexes": verified,
    }


def index_lookup(
    lookup: dict[str, Any],
) -> tuple[dict[tuple[str, str, str], dict[str, Any]], dict[str, str]]:
    if lookup.get("status") == "hold" and not lookup.get("candidates"):
        raise PacketError("lookup_result_not_usable")
    raw_candidates = lookup.get("candidates")
    if raw_candidates is None:
        raw_candidates = []
    if not isinstance(raw_candidates, list):
        raise PacketError("lookup_candidates_invalid")
    grouped: dict[tuple[str, str, str], list[dict[str, Any]]] = {}
    for row in raw_candidates:
        if not isinstance(row, dict):
            raise PacketError("lookup_candidates_invalid")
        kind = str(row.get("identity_kind") or "")
        owned = str(row.get("source_owned_id") or "")
        ref = str(row.get("reference_unit_id") or "")
        if kind and owned:
            grouped.setdefault(("owned", kind, owned), []).append(row)
        if kind and ref:
            grouped.setdefault(("ref", kind, ref), []).append(row)
    unique: dict[tuple[str, str, str], dict[str, Any]] = {}
    for key, rows in grouped.items():
        if len(rows) != 1:
            raise PacketError("ambiguous_lookup_candidate_id")
        unique[key] = rows[0]
    held: dict[str, str] = {}
    for row in lookup.get("held_excluded") or []:
        if not isinstance(row, dict):
            continue
        identity = str(row.get("reference_unit_id") or row.get("source_owned_id") or "")
        reason = str(row.get("reason") or "held")
        if identity:
            held[identity] = reason
    return unique, held


def lookup_match(
    spec: dict[str, Any],
    indexed: dict[tuple[str, str, str], dict[str, Any]],
    held: dict[str, str],
) -> tuple[dict[str, Any] | None, str | None]:
    kind = spec["identity_kind"]
    owned = spec.get("source_owned_id")
    ref = spec.get("reference_unit_id")
    for identity in (owned, ref):
        if identity and identity in held:
            return None, held[identity]
    row_owned = indexed.get(("owned", kind, owned)) if owned else None
    row_ref = indexed.get(("ref", kind, ref)) if ref else None
    if owned and ref:
        if row_owned is None or row_ref is None or row_owned is not row_ref:
            return None, "inconsistent_owned_and_ref"
        row = row_owned
    else:
        row = row_owned or row_ref
    if row is None:
        return None, "missing_from_lookup_page"
    if row.get("bindable") is False:
        return None, str(row.get("hold_reason") or "unbindable")
    return row, None


def pointer_signature(pointer: Any) -> tuple[str, str, float | None] | None:
    parsed = catalog_lookup._pointer(pointer)
    if parsed is None:
        return None
    stamp = None
    if isinstance(pointer, dict):
        stamp = finite_nonnegative(pointer.get("source_timestamp_seconds"))
    return (parsed["path"], parsed["sha256"], stamp)


def original_media_from_row(
    root: Path, row: dict[str, Any], hasher: HashBinder, costs: dict[str, int]
) -> tuple[dict[str, Any] | None, str | None]:
    manifest_ptr = catalog_lookup._pointer(row.get("source_manifest"))
    if manifest_ptr is None:
        return None, "missing_source_manifest"
    path = contained_existing(root, manifest_ptr["path"])
    raw = path.read_bytes()
    digest = bind_existing_bytes(hasher, path, raw)
    costs["evidence_files_hashed"] += 1
    costs["evidence_bytes_hashed"] += len(raw)
    if digest != manifest_ptr["sha256"]:
        return None, "stale_source_manifest_sha256"
    try:
        document = yaml.safe_load(raw.decode("utf-8"))
    except (UnicodeDecodeError, yaml.YAMLError):
        return None, "source_manifest_invalid"
    if not isinstance(document, dict):
        return None, "source_manifest_invalid"
    duration = declared_duration(document)
    media_ptr = None
    for media in document.get("media") or []:
        if not isinstance(media, dict):
            continue
        if media.get("kind") not in {"video", "audio", None, ""}:
            continue
        parsed = catalog_lookup._pointer(media) or catalog_lookup._pointer(
            {"path": media.get("path"), "sha256": media.get("sha256")}
        )
        if parsed:
            media_ptr = parsed
            break
    if media_ptr is None:
        original = catalog_lookup._pointer(document.get("primary_original"))
        if original:
            media_ptr = original
    if media_ptr is None:
        return None, "original_media_required"
    media_path = contained_existing(root, media_ptr["path"])
    media_digest = hash_existing(hasher, media_path)
    costs["evidence_files_hashed"] += 1
    costs["evidence_bytes_hashed"] += media_path.stat().st_size
    if media_digest != media_ptr["sha256"]:
        return None, "stale_original_media_sha256"
    source_title = document.get("title")
    if not isinstance(source_title, str) or not source_title.strip():
        source_title = None
    else:
        source_title = source_title.strip()
    payload = {
        "role": "original_media",
        "path": media_ptr["path"],
        "sha256": media_digest,
        "byte_integrity": "hashed",
        "duration_seconds": duration,
        "counts_as_comparison_unit": False,
        "resolved_uri": file_uri(media_path),
    }
    if source_title is not None:
        payload["source_title"] = source_title
    return payload, None


def timestamp_in_bounds(stamp: float | None, duration: float | None) -> bool:
    if stamp is None:
        return False
    if duration is None:
        return True
    return stamp <= duration + CADENCE_TOLERANCE


def bind_pointer(
    root: Path,
    pointer: Any,
    role: str,
    hasher: HashBinder,
    costs: dict[str, int],
    *,
    allowed: set[tuple[str, str, float | None]] | None = None,
    duration: float | None = None,
) -> tuple[dict[str, Any] | None, str | None]:
    if pointer is not None and not isinstance(pointer, dict):
        return None, "malformed_pointer"
    parsed = catalog_lookup._pointer(pointer)
    if parsed is None:
        return None, "malformed_pointer"
    signature = pointer_signature(pointer)
    if allowed is not None and signature not in allowed:
        return None, "foreign_source_evidence"
    path = contained_existing(root, parsed["path"])
    actual = hash_existing(hasher, path)
    costs["evidence_files_hashed"] += 1
    costs["evidence_bytes_hashed"] += path.stat().st_size
    if actual != parsed["sha256"]:
        return None, "stale_evidence_sha256"
    stamp = finite_nonnegative(pointer.get("source_timestamp_seconds")) if isinstance(pointer, dict) else None
    if stamp is not None and not timestamp_in_bounds(stamp, duration):
        return None, "timestamp_out_of_bounds"
    item: dict[str, Any] = {
        "role": role,
        "path": parsed["path"],
        "sha256": actual,
        "byte_integrity": "hashed",
        "counts_as_comparison_unit": role == "individual_still",
        "resolved_uri": file_uri(path),
    }
    if stamp is not None:
        item["source_timestamp_seconds"] = stamp
    if isinstance(pointer, dict) and pointer.get("order") is not None:
        item["order"] = pointer.get("order")
    if role in {"contact_sheet_navigation", "before_context", "after_context", "sequence_frame"}:
        item["counts_as_comparison_unit"] = False
    if role == "contact_sheet_navigation":
        item["unit_count"] = 0
        item["note"] = "contact_sheet_is_navigation_only"
    return item, None


def sequence_reason(frames: list[dict[str, Any]]) -> str | None:
    if len(frames) != SEQUENCE_FRAME_COUNT:
        return "sequence_window_requires_exact_five_frames"
    if all(frame.get("order") is None for frame in frames):
        for index, frame in enumerate(frames, start=1):
            frame["order"] = index
    if [frame.get("order") for frame in frames] != list(range(1, SEQUENCE_FRAME_COUNT + 1)):
        return "sequence_window_requires_ordered_frames_1_to_5"
    stamps: list[float] = []
    for frame in frames:
        stamp = finite_nonnegative(frame.get("source_timestamp_seconds"))
        if stamp is None:
            return "sequence_window_missing_timestamps"
        stamps.append(stamp)
    for current, following in zip(stamps, stamps[1:]):
        if abs((following - current) - SEQUENCE_CADENCE_SECONDS) > CADENCE_TOLERANCE:
            return "sequence_window_cadence"
    return None


def load_qc_context_manifest(
    root: Path, pointer: Any, hasher: HashBinder, costs: dict[str, int]
) -> tuple[dict[str, Any] | None, str | None]:
    parsed = catalog_lookup._pointer(pointer)
    if parsed is None:
        return None, "malformed_pointer"
    path = contained_existing(root, parsed["path"])
    raw = path.read_bytes()
    digest = bind_existing_bytes(hasher, path, raw)
    costs["evidence_files_hashed"] += 1
    costs["evidence_bytes_hashed"] += len(raw)
    if digest != parsed["sha256"]:
        return None, "stale_context_manifest_sha256"
    try:
        document = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        return None, "context_manifest_invalid"
    if not isinstance(document, dict):
        return None, "context_manifest_invalid"
    if document.get("schema_version") != "idol_video_qc_sheet_manifest.v1":
        return None, "unsupported_context_manifest"
    return document, None


def match_context_sheet(
    document: dict[str, Any], pointer: Any, original: dict[str, Any]
) -> tuple[dict[str, Any] | None, str | None]:
    source_video = document.get("source_video") if isinstance(document.get("source_video"), dict) else {}
    video_ptr = catalog_lookup._pointer(source_video) or catalog_lookup._pointer(
        {"path": source_video.get("path"), "sha256": source_video.get("sha256")}
    )
    if video_ptr is None:
        return None, "context_manifest_missing_source_video"
    if video_ptr["path"] != original.get("path") or video_ptr["sha256"] != original.get("sha256"):
        return None, "foreign_source_evidence"
    parsed = catalog_lookup._pointer(pointer)
    if parsed is None:
        return None, "malformed_pointer"
    for sheet in document.get("sheets") or []:
        if not isinstance(sheet, dict):
            continue
        if sheet.get("path") == parsed["path"] and sheet.get("sha256") == parsed["sha256"]:
            return sheet, None
        for cell in sheet.get("cells") or []:
            if not isinstance(cell, dict):
                continue
            crop = catalog_lookup._pointer(cell) or catalog_lookup._pointer(cell.get("cell_crop"))
            if crop and crop["path"] == parsed["path"] and crop["sha256"] == parsed["sha256"]:
                return cell, None
    return None, "context_not_in_manifest"


def planned_evidence_count(item: dict[str, Any], lookup_row: dict[str, Any] | None) -> int:
    count = 1 if item["evidence_kind"] in NAMED_WINDOWS else 0
    pointers = item.get("pointers") or []
    if pointers:
        count += len(pointers)
    elif item.get("bind_from_lookup") == "frames":
        frames = (lookup_row or {}).get("frames") or []
        count += len(frames) if frames else SEQUENCE_FRAME_COUNT
    elif item.get("bind_from_lookup") == "selected_evidence":
        selected = (lookup_row or {}).get("selected_evidence") or []
        count += len(selected) if selected else 1
    else:
        count += 1
    if catalog_lookup._pointer(item.get("before_context")):
        count += 1
    if catalog_lookup._pointer(item.get("after_context")):
        count += 1
    if catalog_lookup._pointer(item.get("context_manifest")):
        count += 1
    return count


def bind_evidence_request(
    root: Path,
    item: dict[str, Any],
    lookup_row: dict[str, Any] | None,
    hasher: HashBinder,
    costs: dict[str, int],
) -> tuple[list[dict[str, Any]], list[dict[str, str]], dict[str, Any], dict[str, Any] | None, dict[str, Any] | None, str | None]:
    kind = item["evidence_kind"]
    bound: list[dict[str, Any]] = []
    held_items: list[dict[str, str]] = []
    pointer_holds: list[dict[str, str]] = []
    original = None
    duration = None
    needs_original = kind in NAMED_WINDOWS or item.get("before_context") is not None or item.get(
        "after_context"
    ) is not None
    if needs_original:
        if lookup_row is None:
            return [], [], {}, None, None, "missing_from_lookup_page"
        original, original_reason = original_media_from_row(root, lookup_row, hasher, costs)
        if original_reason:
            return [], [], {}, None, None, original_reason
        duration = (original or {}).get("duration_seconds")
        requested_media = item.get("source_media")
        if requested_media is not None:
            parsed = catalog_lookup._pointer(requested_media)
            if parsed is None:
                return [], [], {}, original, None, "malformed_pointer"
            if parsed["path"] != original["path"] or parsed["sha256"] != original["sha256"]:
                return [], [], {}, original, None, "foreign_source_evidence"

    def add_pointer(pointer: Any, role: str, allowed: set[tuple[str, str, float | None]] | None) -> None:
        evidence, reason = bind_pointer(
            root, pointer, role, hasher, costs, allowed=allowed, duration=duration
        )
        if reason:
            path = ""
            if isinstance(pointer, dict):
                path = str(pointer.get("path") or "")
            hold = {"path": path, "reason": reason}
            pointer_holds.append(hold)
            held_items.append(hold)
            return
        if evidence:
            bound.append(evidence)

    lookup_frame_sigs = set()
    lookup_still_sigs = set()
    if lookup_row is not None:
        for frame in lookup_row.get("frames") or []:
            signature = pointer_signature(frame)
            if signature:
                lookup_frame_sigs.add(signature)
        for still in lookup_row.get("selected_evidence") or []:
            signature = pointer_signature(still)
            if signature:
                lookup_still_sigs.add(signature)

    if kind in {"source_window", "audio_measurement_window"}:
        window = item.get("window") if isinstance(item.get("window"), dict) else None
        start = finite_nonnegative((window or {}).get("start_seconds"))
        end = finite_nonnegative((window or {}).get("end_seconds"))
        if start is None or end is None or end <= start:
            return [], [], {}, original, None, "source_window_requires_time_range"
        if not timestamp_in_bounds(start, duration) or not timestamp_in_bounds(end, duration):
            return [], [], {}, original, None, "timestamp_out_of_bounds"
        bound.append(
            {
                "role": kind,
                "path": original["path"] if original else None,
                "sha256": original["sha256"] if original else None,
                "byte_integrity": "hashed" if original else "window_declared_only",
                "start_seconds": start,
                "end_seconds": end,
                "counts_as_comparison_unit": True,
                "resolved_uri": (original or {}).get("resolved_uri"),
                "semantic_event": None,
                "measurement_bucket": None,
            }
        )
        if item.get("pointers"):
            allowed_extras = lookup_frame_sigs | lookup_still_sigs
            for pointer in item["pointers"]:
                stamp = (
                    finite_nonnegative(pointer.get("source_timestamp_seconds"))
                    if isinstance(pointer, dict)
                    else None
                )
                if stamp is not None and (
                    stamp < start or stamp > end + CADENCE_TOLERANCE
                ):
                    path = str(pointer.get("path") or "") if isinstance(pointer, dict) else ""
                    hold = {"path": path, "reason": "timestamp_out_of_bounds"}
                    pointer_holds.append(hold)
                    held_items.append(hold)
                    continue
                add_pointer(pointer, POINTER_ROLE_BY_KIND[kind], allowed_extras)
    elif item.get("pointers"):
        role = POINTER_ROLE_BY_KIND[kind]
        allowed = None
        if kind == "sequence_window":
            allowed = lookup_frame_sigs
        elif kind == "individual_still":
            allowed = lookup_still_sigs
        for pointer in item["pointers"]:
            add_pointer(pointer, role, allowed)
    elif item.get("bind_from_lookup") == "frames":
        if lookup_row is None:
            return [], [], {}, original, None, "missing_from_lookup_page"
        frames = lookup_row.get("frames") or []
        if not isinstance(frames, list) or not frames:
            return [], [], {}, original, None, "missing_lookup_frames"
        for frame in frames:
            add_pointer(frame, "sequence_frame", lookup_frame_sigs)
    elif item.get("bind_from_lookup") == "selected_evidence":
        if lookup_row is None:
            return [], [], {}, original, None, "missing_from_lookup_page"
        selected = lookup_row.get("selected_evidence") or []
        if not isinstance(selected, list) or not selected:
            return [], [], {}, original, None, "missing_lookup_selected_evidence"
        for pointer in selected:
            add_pointer(pointer, "individual_still", lookup_still_sigs)
    else:
        missing = {
            "sequence_window": "sequence_window_requires_frames_or_pointers",
            "individual_still": "individual_still_requires_pointers",
            "contact_sheet_navigation": "contact_sheet_requires_pointer",
            "source_window": "source_window_requires_time_range",
            "audio_measurement_window": "source_window_requires_time_range",
        }[kind]
        return [], [], {}, original, None, missing

    context: dict[str, Any] = {}
    if item.get("before_context") is not None or item.get("after_context") is not None:
        if original is None:
            held_items.append({"path": "", "reason": "original_media_required"})
        elif catalog_lookup._pointer(item.get("context_manifest")) is None:
            held_items.append({"path": "", "reason": "missing_context_manifest"})
        else:
            manifest_doc, man_reason = load_qc_context_manifest(
                root, item.get("context_manifest"), hasher, costs
            )
            if man_reason:
                loc = ""
                if isinstance(item.get("context_manifest"), dict):
                    loc = str(item.get("context_manifest").get("path") or "")
                held_items.append({"path": loc, "reason": man_reason})
            else:
                for key, role in (
                    ("before_context", "before_context"),
                    ("after_context", "after_context"),
                ):
                    if item.get(key) is None:
                        continue
                    sheet, match_reason = match_context_sheet(
                        manifest_doc, item.get(key), original
                    )
                    if match_reason:
                        path = ""
                        if isinstance(item.get(key), dict):
                            path = str(item.get(key).get("path") or "")
                        held_items.append({"path": path, "reason": match_reason})
                        continue
                    evidence, reason = bind_pointer(
                        root,
                        item.get(key),
                        role,
                        hasher,
                        costs,
                        allowed=None,
                        duration=duration,
                    )
                    if reason:
                        path = ""
                        if isinstance(item.get(key), dict):
                            path = str(item.get(key).get("path") or "")
                        held_items.append({"path": path, "reason": reason})
                        continue
                    if evidence is not None:
                        range_text = None
                        if isinstance(sheet, dict):
                            range_text = sheet.get("source_time_range")
                            if range_text is None and sheet.get("source_timestamp_seconds") is not None:
                                range_text = str(sheet.get("source_timestamp_seconds"))
                        if range_text:
                            evidence["source_time_range"] = range_text
                        evidence["semantic_event"] = None
                        evidence["counts_as_comparison_unit"] = False
                        context[role] = evidence

    sequence_unit = None
    malformed = None
    if kind == "sequence_window":
        frames = [row for row in bound if row.get("role") == "sequence_frame"]
        if pointer_holds:
            malformed = pointer_holds[0]["reason"]
        else:
            malformed = sequence_reason(frames)
        if malformed is None:
            sequence_unit = {
                "unit_count": 1,
                "counts_as_comparison_unit": True,
                "frame_count": SEQUENCE_FRAME_COUNT,
                "cadence_seconds": SEQUENCE_CADENCE_SECONDS,
            }
            for frame in frames:
                frame["counts_as_comparison_unit"] = False
    if kind == "contact_sheet_navigation":
        for row in bound:
            row["counts_as_comparison_unit"] = False
            row["unit_count"] = 0
            row["note"] = "contact_sheet_is_navigation_only"
    return bound, held_items, context, original, sequence_unit, malformed


def comparison_unit_count(
    evidence: list[dict[str, Any]], sequence_unit: dict[str, Any] | None
) -> int:
    count = 1 if sequence_unit and sequence_unit.get("counts_as_comparison_unit") else 0
    for item in evidence:
        if item.get("role") == "sequence_frame":
            continue
        if item.get("counts_as_comparison_unit"):
            count += 1
    return count


def render_html(packet: dict[str, Any], max_cells: int) -> tuple[str, bool, int]:
    shown = 0
    truncated = False
    chunks = [
        "<!DOCTYPE html>",
        '<html lang="en"><head><meta charset="utf-8">',
        "<title>IDOL reference comparison evidence (mechanical view)</title>",
        "<style>body{font-family:sans-serif;background:#111;color:#eee;max-width:1100px;margin:24px auto;padding:0 16px}img{max-width:240px;display:block}figure{display:inline-block;margin:8px;vertical-align:top}.nav{border:1px dashed #888;padding:8px}.meta{font-size:12px;color:#bbb}</style>",
        "</head><body>",
        "<h1>IDOL reference comparison evidence (mechanical view)</h1>",
        "<p>This view presents requested evidence pointers only. It does not rank candidates, infer semantic events, author observations, or grant creative PASS. A contact sheet is navigation only and is not a comparison unit. Five Sequence frames are one unit.</p>",
        f'<p class="meta">packet_status={html.escape(str(packet.get("status")))} named_gap_id={html.escape(str(packet.get("named_gap_id") or ""))}</p>',
    ]

    def emit(item: dict[str, Any], original: dict[str, Any] | None) -> None:
        nonlocal shown, truncated
        if shown >= max_cells:
            truncated = True
            return
        shown += 1
        uri = str(item.get("resolved_uri") or "")
        role = str(item.get("role") or "")
        stamp = item.get("source_timestamp_seconds")
        if stamp is None:
            stamp = item.get("start_seconds")
        nav = role == "contact_sheet_navigation" or item.get("note") == "contact_sheet_is_navigation_only"
        css = ' class="nav"' if nav else ""
        caption = role
        if item.get("order") is not None:
            caption = f"{role} {item.get('order')}"
        if item.get("source_time_range"):
            caption += f" · {item.get('source_time_range')} sampled range"
        elif stamp is not None:
            caption += f" · {stamp}s"
        if nav:
            caption += " (navigation only; not a comparison unit)"
        chunks.append(f"<figure{css}>")
        if uri and Path(item.get("path") or "").suffix.lower() in IMAGE_SUFFIXES:
            chunks.append(
                f'<img src="{html.escape(uri, quote=True)}" alt="{html.escape(role, quote=True)} evidence pointer">'
            )
        media_uri = (original or {}).get("resolved_uri")
        if media_uri and stamp is not None:
            href = f"{media_uri}#t={stamp}"
            chunks.append(
                f'<p class="meta"><a href="{html.escape(href, quote=True)}">source media {html.escape(str(stamp))}s</a></p>'
            )
        elif media_uri and role in NAMED_WINDOWS:
            chunks.append(
                f'<p class="meta"><a href="{html.escape(str(media_uri), quote=True)}">source media</a></p>'
            )
        chunks.append(f'<figcaption>{html.escape(caption)}</figcaption>')
        details = []
        if item.get("path"):
            details.append(f"path={item.get('path')}")
        if item.get("sha256"):
            details.append(f"sha256={item.get('sha256')}")
        details.append(f"role={role}")
        chunks.append(
            f'<details class="meta"><summary>path/SHA/role</summary><p>{html.escape(" ".join(details))}</p></details></figure>'
        )

    for candidate in packet.get("candidates") or []:
        request_id = html.escape(str(candidate.get("request_id") or ""))
        lookup_row = candidate.get("lookup_row") if isinstance(candidate.get("lookup_row"), dict) else {}
        original = candidate.get("original_media") if isinstance(candidate.get("original_media"), dict) else None
        source_title = (original or {}).get("source_title") or lookup_row.get("source_identity") or request_id
        chunks.append(f"<section><h2>{html.escape(str(source_title))}</h2>")
        if lookup_row.get("event_identity"):
            chunks.append(f"<p>event_identity: {html.escape(str(lookup_row.get('event_identity')))}</p>")
        if lookup_row.get("purpose_classes"):
            chunks.append(
                f"<p>purpose_classes: {html.escape(', '.join(str(item) for item in lookup_row.get('purpose_classes')))}</p>"
            )
        if lookup_row.get("transfer_boundary"):
            chunks.append(
                f"<p>transfer_boundary: {html.escape(str(lookup_row.get('transfer_boundary')))}</p>"
            )
        if lookup_row.get("do_not_transfer"):
            chunks.append(
                f"<p>do_not_transfer: {html.escape(str(lookup_row.get('do_not_transfer')))}</p>"
            )
        chunks.append(
            f'<details class="meta"><summary>request mechanics</summary><p>'
            f"request_id={request_id} binding_status={html.escape(str(candidate.get('binding_status') or ''))} "
            f"comparison_unit_count={html.escape(str(candidate.get('comparison_unit_count')))} "
            f"identity_kind={html.escape(str(lookup_row.get('identity_kind') or candidate.get('identity_kind') or ''))} "
            f"source_owned_id={html.escape(str(candidate.get('source_owned_id') or ''))}</p></details>"
        )
        if candidate.get("hold_reason"):
            chunks.append(
                f"<p>held or missing reason: {html.escape(str(candidate.get('hold_reason')))}</p>"
            )
        for item in candidate.get("evidence") or []:
            if isinstance(item, dict):
                emit(item, original)
        context = candidate.get("context") if isinstance(candidate.get("context"), dict) else {}
        for item in context.values():
            if isinstance(item, dict):
                emit(item, original)
        chunks.append("</section>")
    chunks.append("</body></html>")
    return "\n".join(chunks), truncated, shown


def preflight_new(root: Path, rel: str, protected: set[Path]) -> Path:
    dest = contained_new_file(root, rel)
    resolved = dest.resolve()
    if resolved in protected:
        raise PacketError("output_collides_with_input")
    if dest.exists() or dest.is_symlink():
        raise PacketError("output_exists_create_only")
    return dest


def publish_new(root: Path, rel: str, content: str, protected: set[Path]) -> Path:
    dest = preflight_new(root, rel, protected)
    err = atomic_cas_replace(dest, content, previous=None)
    if err:
        raise PacketError("output_exists_create_only")
    return dest


def assemble_packet(
    *,
    root: Path,
    request: dict[str, Any],
    lookup: dict[str, Any],
    hasher: HashBinder,
    render_rel: str | None = None,
    output_rel: str | None = None,
) -> dict[str, Any]:
    header, specs, evidence_reqs = validate_request(request)
    if not isinstance(lookup, dict):
        raise PacketError("lookup_result_not_usable")
    if str(lookup.get("named_gap_id") or "") != header["named_gap_id"]:
        raise PacketError("named_gap_id_mismatch")
    query_digest = header.get("lookup_query_digest")
    if query_digest:
        if not is_hex_sha256(query_digest) or query_digest != lookup.get("query_digest"):
            raise PacketError("lookup_query_digest_mismatch")
    freshness = verify_index_freshness(root, lookup, header["catalog_sha256"], hasher)
    indexed, held = index_lookup(lookup)
    costs = {
        "lookup_candidates_indexed": len(lookup.get("candidates") or []),
        "evidence_files_hashed": 0,
        "evidence_bytes_hashed": 0,
        "render_cells": 0,
    }
    planned = 0
    for spec in specs:
        row, _reason = lookup_match(spec, indexed, held)
        for item in evidence_reqs:
            if item["request_id"] == spec["request_id"]:
                planned += planned_evidence_count(item, row)
    if planned > header["page_budget"]["max_evidence_items"]:
        raise PacketError("page_budget_evidence_exceeded")

    candidates_out: list[dict[str, Any]] = []
    missing: list[dict[str, Any]] = []
    bound_count = 0
    for spec in specs:
        row, miss = lookup_match(spec, indexed, held)
        related = [item for item in evidence_reqs if item["request_id"] == spec["request_id"]]
        if miss:
            status = "held" if miss != "missing_from_lookup_page" else "missing"
            if miss == "inconsistent_owned_and_ref":
                status = "malformed"
            missing.append({"request_id": spec["request_id"], "reason": miss})
            candidates_out.append(
                {
                    "request_id": spec["request_id"],
                    "identity_kind": spec["identity_kind"],
                    "source_owned_id": spec.get("source_owned_id"),
                    "reference_unit_id": spec.get("reference_unit_id"),
                    "binding_status": status,
                    "hold_reason": miss,
                    "lookup_row": copy_lookup_row(row) if row else None,
                    "original_media": None,
                    "sequence_unit": None,
                    "comparison_unit_count": 0,
                    "evidence": [],
                    "context": None,
                }
            )
            continue
        evidence: list[dict[str, Any]] = []
        context: dict[str, Any] = {}
        held_reasons: list[dict[str, str]] = []
        original = None
        sequence_unit = None
        malformed = None
        if not related:
            missing.append({"request_id": spec["request_id"], "reason": "missing_evidence"})
            candidates_out.append(
                {
                    "request_id": spec["request_id"],
                    "identity_kind": spec["identity_kind"],
                    "source_owned_id": spec.get("source_owned_id"),
                    "reference_unit_id": spec.get("reference_unit_id"),
                    "binding_status": "missing",
                    "hold_reason": "missing_evidence",
                    "lookup_row": copy_lookup_row(row) if row else None,
                    "original_media": None,
                    "sequence_unit": None,
                    "comparison_unit_count": 0,
                    "evidence": [],
                    "context": None,
                }
            )
            continue
        for item in related:
            bound, held_items, ctx, orig, seq, mal = bind_evidence_request(
                root, item, row, hasher, costs
            )
            evidence.extend(bound)
            held_reasons.extend(held_items)
            context.update(ctx)
            if orig:
                original = orig
            if seq:
                sequence_unit = seq
            if mal:
                malformed = mal
        if malformed:
            binding = "malformed"
            hold_reason = malformed
            sequence_unit = None
            missing.append({"request_id": spec["request_id"], "reason": malformed})
        elif held_reasons and evidence:
            binding = "partial"
            hold_reason = held_reasons[0]["reason"]
            for row_held in held_reasons:
                missing.append({"request_id": spec["request_id"], **row_held})
        elif held_reasons:
            binding = "held"
            hold_reason = held_reasons[0]["reason"]
            for row_held in held_reasons:
                missing.append({"request_id": spec["request_id"], **row_held})
        elif not evidence:
            binding = "missing"
            hold_reason = "missing_evidence"
            missing.append({"request_id": spec["request_id"], "reason": "missing_evidence"})
        else:
            binding = "bound"
            hold_reason = None
            bound_count += 1
        candidates_out.append(
            {
                "request_id": spec["request_id"],
                "identity_kind": spec["identity_kind"],
                "source_owned_id": spec.get("source_owned_id"),
                "reference_unit_id": spec.get("reference_unit_id"),
                "binding_status": binding,
                "hold_reason": hold_reason,
                "lookup_row": copy_lookup_row(row) if row else None,
                "original_media": original,
                "sequence_unit": sequence_unit,
                "comparison_unit_count": comparison_unit_count(evidence, sequence_unit),
                "evidence": evidence,
                "context": context or None,
            }
        )

    if bound_count == len(specs) and not missing:
        status = "assembled"
        reason = None
    else:
        status = "partial"
        reason = "missing_or_held_evidence"
    publication_holds = hasher.verify_publication()
    if publication_holds:
        raise PacketError("snapshot_inconsistent")
    packet = {
        "schema_version": CONTRACT,
        "status": status,
        "reason": reason,
        "named_gap_id": header["named_gap_id"],
        "request_digest": sha256_text(canonical_json(request)),
        "catalog_digest": header["catalog_sha256"],
        "lookup_query_digest": lookup.get("query_digest"),
        "lookup_coverage": lookup.get("coverage")
        if isinstance(lookup.get("coverage"), dict)
        else None,
        "page_budget": header["page_budget"],
        "assessment_scope": assessment_scope(
            hashed=costs["evidence_files_hashed"] > 0, freshness_verified=True
        ),
        "freshness": freshness,
        "candidates": candidates_out,
        "missing_or_held": missing,
        "cost": costs,
        "render": None,
    }
    protected = {Path(key) for key in hasher.fresh.rows}
    outputs_written: list[dict[str, str]] = []
    packet["outputs_written"] = outputs_written
    if render_rel:
        preflight_new(root, render_rel, protected)
    if output_rel:
        preflight_new(root, output_rel, protected)
    if render_rel and output_rel:
        if contained_new_file(root, render_rel).resolve() == contained_new_file(
            root, output_rel
        ).resolve():
            raise PacketError("output_collides_with_input")
    if render_rel:
        try:
            html_text, truncated, shown = render_html(
                packet, header["page_budget"]["max_render_cells"]
            )
            written = html_text + "\n"
            dest = publish_new(root, render_rel, written, protected)
            protected.add(dest.resolve())
            costs["render_cells"] = shown
            outputs_written.append(
                {"kind": "render", "path": render_rel, "sha256": sha256_text(written)}
            )
            packet["render"] = {
                "path": render_rel,
                "sha256": sha256_text(written),
                "truncated": truncated,
                "cell_count": shown,
            }
            packet["outputs_written"] = list(outputs_written)
            packet["cost"] = costs
        except PacketError as exc:
            packet["output_write_error"] = str(exc)
            packet["outputs_written"] = list(outputs_written)
            return packet
    if output_rel:
        try:
            text = json.dumps(packet, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
            publish_new(root, output_rel, text, protected)
            outputs_written.append(
                {"kind": "packet", "path": output_rel, "sha256": sha256_text(text)}
            )
            packet["outputs_written"] = list(outputs_written)
        except PacketError as cop_exc:
            packet["output_write_error"] = str(cop_exc)
            packet["outputs_written"] = list(outputs_written)
    return packet


def load_json_file(root: Path, rel: str, hasher: HashBinder) -> dict[str, Any]:
    path = contained_existing(root, rel)
    raw = path.read_bytes()
    bind_existing_bytes(hasher, path, raw)
    try:
        loaded = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise PacketError("json_invalid") from exc
    if not isinstance(loaded, dict):
        raise PacketError("json_invalid")
    return loaded


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Assemble a source-bound comparison packet from explicitly requested "
            "lookup candidate ids and evidence pointers"
        )
    )
    parser.add_argument("--repo-root", default=str(ROOT))
    parser.add_argument("--request", required=True)
    parser.add_argument("--lookup-result", required=True)
    parser.add_argument("--output")
    parser.add_argument("--render-html")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    root = Path(args.repo_root)
    hasher = HashBinder(root, profile="canonical_gate")
    try:
        request = load_json_file(root, args.request, hasher)
        lookup = load_json_file(root, args.lookup_result, hasher)
        packet = assemble_packet(
            root=root,
            request=request,
            lookup=lookup,
            hasher=hasher,
            render_rel=args.render_html,
            output_rel=args.output,
        )
        if packet.get("output_write_error"):
            code = 1
        else:
            code = 0 if packet["status"] == "assembled" else 3
    except PacketError as cop_exc:
        packet = hold_packet(cop_exc.reason)
        code = 1
    print(json.dumps(packet, ensure_ascii=False, indent=2, sort_keys=True))
    return code


if __name__ == "__main__":
    raise SystemExit(main())
