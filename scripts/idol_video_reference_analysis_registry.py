#!/usr/bin/env python3
"""Maintain the source-owned read-first index for local video reference analyses.

This script never authors creative observations. It scans canonical source
manifests, hashes declared analysis inputs, checks a small required-heading
contract, and renders an AI/model-readable first-read file.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import sys
from pathlib import Path
from typing import Any

import yaml

SCRIPTS_DIR = Path(__file__).resolve().parent
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))
from jsonschema import Draft202012Validator
from lib.idol_artifact_integrity import (
    HashBinder,
    PublicationTarget,
    publish_canonical_derived,
    read_publication_snapshot,
)


SCHEMA_VERSION = "idol_video_reference_analysis_registry.v2"
ANALYSIS_SCHEMA = Path(__file__).resolve().parents[1] / "schemas" / "video-reference-analysis-registry.schema.json"
REGISTRY_REL = Path("source-materials/video-sources/reference-analysis-registry.yaml")
READ_FIRST_REL = Path("source-materials/video-sources/READ-FIRST.md")
SOURCE_GLOBS = (
    "source-materials/video-sources/bilibili/by-source/*/source-manifest.yaml",
    "source-materials/video-sources/youtube/by-source/*/source-manifest.yaml",
)
COMPLETE_HEADINGS = (
    "## 분석에 실제로 사용한 자료",
    "## 영상 전체의 큰 흐름",
    "## 상세 장면 기록",
    "## 공용 관찰에서 허용하는 전이 경계",
    "## 공용 관찰에서 제외하는 전이 경계",
)
TIMECODE_RE = re.compile(
    r"(?m)^[ \t]*(?:#{2,4}\s+|[-*]\s+)?(?:"
    r"\d{1,3}:\d{2}(?::\d{2})?"
    r"|\d{1,3}(?:\.\d+)?\s*[–~-]\s*\d{1,3}(?:\.\d+)?\s*초"
    r"|(?:cell_or_frame_locator|cell_locator)\s*:\s*\d+(?:\.\d+)?)"
)
PARENT_COMPLETE_ROLE = "parent_complete_analysis"
SCOPED_STATUS = "complete_scoped"
SCOPED_HEADINGS = (
    "## 분석에 실제로 사용한 자료",
    "## 공용 관찰에서 허용하는 전이 경계",
    "## 공용 관찰에서 제외하는 전이 경계",
)
EXTRACTION_ROLES = {
    "one_second_analysis_surface",
    "selected_range_surface",
    "subsecond_turn_surface",
}
CADENCE_TOLERANCE = 0.001
MAX_EXTRACTION_INTERVAL = 1.0
INPUT_ROLES = {
    "original_video",
    "source_manifest",
    "navigation_surface",
    "one_second_analysis_surface",
    "selected_range_surface",
    "subsecond_turn_surface",
    "selected_frame_or_crop",
    PARENT_COMPLETE_ROLE,
    "other_hash_bound_evidence",
}


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def resolve_root(args: argparse.Namespace) -> Path:
    raw = getattr(args, "repo_root", None)
    if raw:
        return Path(str(raw)).expanduser().resolve()
    return repo_root()


def integrity_profile_of(args: argparse.Namespace) -> str:
    return str(getattr(args, "integrity_profile", None) or "canonical_gate")


def emit_integrity(hasher: HashBinder) -> None:
    print(json.dumps({"integrity": hasher.report()}, ensure_ascii=False), file=sys.stderr)


def sha256(path: Path, *, hasher: HashBinder | None = None) -> str:
    if hasher is not None:
        return hasher.sha256(path)
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_yaml(path: Path) -> dict[str, Any]:
    if not path.is_file():
        return {}
    loaded = yaml.safe_load(path.read_text(encoding="utf-8"))
    return loaded if isinstance(loaded, dict) else {}


def rel_path(path: Path, root: Path) -> str:
    resolved = path.resolve()
    try:
        return resolved.relative_to(root.resolve()).as_posix()
    except ValueError as exc:
        raise ValueError(f"path must stay inside repository: {path}") from exc


def reject_registry_symlink_or_escape(
    candidate: Path, root_resolved: Path, label: str
) -> str | None:
    if candidate.is_symlink():
        try:
            resolved = candidate.resolve(strict=False)
            resolved.relative_to(root_resolved)
        except (OSError, ValueError):
            return f"HOLD escaped_path: {label} resolves outside repository"
        return (
            f"HOLD escaped_path: {label} is a symlink; refuse registry IO through symlink"
        )
    try:
        resolved = candidate.resolve(strict=False)
        resolved.relative_to(root_resolved)
    except (OSError, ValueError):
        return f"HOLD escaped_path: {label} resolves outside repository"
    return None


def contained_registry_destination(
    rel: Path, root: Path
) -> tuple[Path | None, str | None]:
    root_resolved = root.resolve()
    dest = root_resolved / rel
    if dest.exists() or dest.is_symlink():
        error = reject_registry_symlink_or_escape(
            dest, root_resolved, rel.as_posix()
        )
        if error:
            return None, error
    try:
        dest.resolve(strict=False).relative_to(root_resolved)
        dest.parent.resolve().relative_to(root_resolved)
    except (OSError, ValueError):
        return None, (
            f"HOLD escaped_path: {rel.as_posix()} output destination resolves outside repository"
        )
    return dest, None


def load_contained_registry(
    rel: Path, root: Path, *, missing_ok: bool
) -> tuple[dict[str, Any], str | None, str | None]:
    dest, error = contained_registry_destination(rel, root)
    if error:
        return {}, None, error
    assert dest is not None
    if not dest.exists():
        if missing_ok:
            return {}, None, None
        return {}, None, f"missing registry: {rel.as_posix()}"
    text = dest.read_text(encoding="utf-8")
    loaded = yaml.safe_load(text)
    return loaded if isinstance(loaded, dict) else {}, text, None


def load_contained_text(
    rel: Path, root: Path, *, missing_ok: bool
) -> tuple[str | None, str | None]:
    dest, error = contained_registry_destination(rel, root)
    if error:
        return None, error
    assert dest is not None
    if not dest.exists():
        if missing_ok:
            return None, None
        return None, f"missing file: {rel.as_posix()}"
    return dest.read_text(encoding="utf-8"), None


def load_mapping_from_path(
    path: Path, *, hasher: HashBinder | None = None
) -> tuple[dict[str, Any], str, list[str]]:
    raw = path.read_bytes()
    digest = (
        hasher.bind_bytes(path, raw) if hasher is not None else hashlib.sha256(raw).hexdigest()
    )
    try:
        loaded = yaml.safe_load(raw.decode("utf-8"))
    except yaml.YAMLError as exc:
        return {}, digest, [f"HOLD malformed_mapping: {path}: {exc}"]
    if not isinstance(loaded, dict):
        return {}, digest, [f"HOLD malformed_mapping: {path} must contain an object"]
    return loaded, digest, []


def validate_generated_registry(registry: dict[str, Any]) -> list[str]:
    schema = json.loads(ANALYSIS_SCHEMA.read_text(encoding="utf-8"))
    return [
        f"HOLD malformed_registry: {error.message}"
        for error in Draft202012Validator(schema).iter_errors(registry)
    ]


def resolve_repo_path(raw: str, root: Path) -> Path:
    root_resolved = root.resolve()
    path = Path(raw)
    candidate = path if path.is_absolute() else root_resolved / path
    try:
        resolved = candidate.resolve(strict=False)
        resolved.relative_to(root_resolved)
    except (OSError, ValueError) as exc:
        raise ValueError(f"HOLD escaped_path: path must stay inside repository: {raw}") from exc
    if not resolved.is_file():
        raise ValueError(f"file is missing: {raw}")
    return resolved


def source_manifests(root: Path) -> tuple[list[Path], list[str]]:
    root_resolved = root.resolve()
    paths: list[Path] = []
    errors: list[str] = []
    for pattern in SOURCE_GLOBS:
        for path in root.glob(pattern):
            try:
                resolved = path.resolve(strict=False)
                resolved.relative_to(root_resolved)
            except (OSError, ValueError):
                errors.append(
                    f"HOLD escaped_path: {path} source manifest resolves outside repository"
                )
                continue
            if resolved.is_file():
                paths.append(resolved)
    return sorted(set(paths)), errors


def source_identity(manifest: dict[str, Any]) -> str:
    identity = manifest.get("identity") or {}
    return str(identity.get("source_key") or "")


def source_title(manifest: dict[str, Any], fallback: str) -> str:
    title = str(manifest.get("title") or "").strip()
    return title or fallback


def duration_seconds(manifest: dict[str, Any]) -> float | None:
    value = (manifest.get("discovery_metadata") or {}).get("duration_seconds")
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)) and math.isfinite(value) and value > 0:
        return float(value)
    return None


def primary_media(
    manifest: dict[str, Any],
    root: Path,
    *,
    hasher: HashBinder | None = None,
) -> dict[str, str] | None:
    for row in manifest.get("media") or []:
        if not isinstance(row, dict) or row.get("kind") != "video":
            continue
        raw_path = str(row.get("path") or "")
        if not raw_path:
            continue
        path = resolve_repo_path(raw_path, root)
        return {
            "path": rel_path(path, root),
            "sha256": sha256(path, hasher=hasher),
        }
    return None


def parse_covered_range(value: str) -> dict[str, float]:
    text = str(value).strip().replace("–", "-").replace("~", "-")
    if "," in text:
        left, right = text.split(",", 1)
    elif ":" in text:
        left, right = text.split(":", 1)
    elif "-" in text:
        left, right = text.split("-", 1)
    else:
        raise ValueError("covered-range must be START,END")
    start = _finite_nonneg(float(left))
    end = _finite_nonneg(float(right))
    if start is None or end is None or end < start:
        raise ValueError("covered-range must be finite nonnegative numbers with end >= start")
    return {"start_seconds": start, "end_seconds": end}


def _finite_nonneg(value: object) -> float | None:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    number = float(value)
    if not math.isfinite(number) or number < 0:
        return None
    return number


def normalize_covered_ranges(raw: object) -> tuple[list[dict[str, float]], list[str]]:
    if not isinstance(raw, list) or not raw:
        return [], [
            "HOLD covered_ranges: complete_scoped requires at least one start_seconds/end_seconds range"
        ]
    ranges: list[dict[str, float]] = []
    errors: list[str] = []
    for item in raw:
        if not isinstance(item, dict):
            errors.append("HOLD covered_ranges: range must be a mapping")
            continue
        start = _finite_nonneg(item.get("start_seconds"))
        end = _finite_nonneg(item.get("end_seconds"))
        if start is None or end is None:
            errors.append(
                "HOLD covered_ranges: start_seconds and end_seconds must be finite nonnegative numbers"
            )
            continue
        if end < start:
            errors.append("HOLD covered_ranges: end_seconds must be >= start_seconds")
            continue
        ranges.append({"start_seconds": start, "end_seconds": end})
    return ranges, errors


def _cadence_points(start: float, end: float, interval: float) -> list[float]:
    if interval <= 0:
        return []
    points: list[float] = []
    stamp = start
    while stamp <= end + CADENCE_TOLERANCE:
        points.append(stamp)
        stamp += interval
        if len(points) > 10000:
            return []
    return points


def _extraction_timestamps(payload: dict[str, Any]) -> tuple[float | None, list[float]]:
    interval = _finite_nonneg(payload.get("interval_seconds"))
    stamps: list[float] = []
    for sheet in payload.get("sheets") or []:
        if not isinstance(sheet, dict):
            continue
        for raw in sheet.get("timestamps") or []:
            stamp = _finite_nonneg(raw)
            if stamp is not None:
                stamps.append(stamp)
        for cell in sheet.get("cells") or []:
            if not isinstance(cell, dict):
                continue
            stamp = _finite_nonneg(cell.get("source_timestamp_seconds"))
            if stamp is not None:
                stamps.append(stamp)
    return interval, stamps


def extraction_covers_range(
    payload: dict[str, Any],
    *,
    video_path: str,
    video_sha: str,
    start: float,
    end: float,
) -> bool:
    source_video = payload.get("source_video")
    if not isinstance(source_video, dict):
        return False
    if str(source_video.get("path") or "") != video_path:
        return False
    if str(source_video.get("sha256") or "") != video_sha:
        return False
    interval, stamps = _extraction_timestamps(payload)
    if interval is None or interval <= 0 or interval > MAX_EXTRACTION_INTERVAL:
        return False
    expected = _cadence_points(start, end, interval)
    if len(expected) < 2:
        return False
    return all(
        any(abs(stamp - point) <= CADENCE_TOLERANCE for stamp in stamps)
        for point in expected
    )


def validate_scoped_source(
    records: list[dict[str, Any]],
    *,
    primary_media: dict[str, str] | None,
    duration_seconds: float | None,
    root: Path,
) -> list[str]:
    statuses_by_key: dict[tuple[object, object], set[str]] = {}
    for item in records:
        analysis = item.get("analysis") if isinstance(item.get("analysis"), dict) else {}
        key = (analysis.get("path"), analysis.get("sha256"))
        status = str(item.get("status") or "")
        if not status:
            continue
        statuses_by_key.setdefault(key, set()).add(status)
    errors: list[str] = []
    for row in records:
        if row.get("status") != SCOPED_STATUS:
            continue
        analysis_id = str(row.get("analysis_id") or "")
        ranges, range_errors = normalize_covered_ranges(row.get("covered_ranges"))
        errors.extend(f"{analysis_id}: {item}" for item in range_errors)
        duration = _finite_nonneg(duration_seconds)
        if duration is None:
            errors.append(
                f"{analysis_id}: source duration is unavailable; refuse to assert covered_ranges bounds"
            )
        else:
            for item in ranges:
                if item["end_seconds"] > duration + CADENCE_TOLERANCE:
                    errors.append(
                        f"{analysis_id}: covered_ranges end_seconds exceeds source duration"
                    )
        videos = [
            item for item in row.get("analysis_inputs") or [] if item.get("role") == "original_video"
        ]
        if not primary_media:
            errors.append(f"{analysis_id}: complete_scoped requires the source primary video")
        elif len(videos) != 1 or (
            videos[0].get("path") != primary_media.get("path")
            or videos[0].get("sha256") != primary_media.get("sha256")
        ):
            errors.append(
                f"{analysis_id}: original_video must be this source manifest's actual video"
            )
        parents = [
            item
            for item in row.get("analysis_inputs") or []
            if item.get("role") == PARENT_COMPLETE_ROLE
        ]
        if len(parents) != 1:
            errors.append(
                f"{analysis_id}: complete_scoped requires exactly one parent_complete_analysis input"
            )
        else:
            key = (parents[0].get("path"), parents[0].get("sha256"))
            statuses = statuses_by_key.get(key, set())
            if statuses == {"complete"}:
                pass
            elif "complete" in statuses:
                errors.append(
                    f"{analysis_id}: parent_complete_analysis has contradictory statuses for the same path and sha256"
                )
            elif "hold_incomplete" in statuses:
                errors.append(
                    f"{analysis_id}: parent_complete_analysis is hold_incomplete; refuse to bootstrap whole-source complete"
                )
            else:
                errors.append(
                    f"{analysis_id}: parent_complete_analysis is not a registered complete analysis for this source"
                )
        video_path = (primary_media or {}).get("path") or ""
        video_sha = (primary_media or {}).get("sha256") or ""
        covered = set()
        for item in row.get("analysis_inputs") or []:
            if item.get("role") not in EXTRACTION_ROLES:
                continue
            try:
                payload = json.loads(
                    resolve_repo_path(str(item.get("path") or ""), root).read_text(encoding="utf-8")
                )
            except json.JSONDecodeError:
                errors.append(f"{analysis_id}: extraction manifest is not valid JSON")
                continue
            except (OSError, UnicodeDecodeError, ValueError):
                errors.append(f"{analysis_id}: extraction manifest is not readable")
                continue
            if not isinstance(payload, dict):
                errors.append(f"{analysis_id}: extraction manifest is not a JSON object")
                continue
            for index, window in enumerate(ranges):
                if extraction_covers_range(
                    payload,
                    video_path=video_path,
                    video_sha=video_sha,
                    start=window["start_seconds"],
                    end=window["end_seconds"],
                ):
                    covered.add(index)
        if ranges and covered != set(range(len(ranges))):
            errors.append(
                f"{analysis_id}: extraction manifest does not provide complete sampled coverage at the declared cadence"
            )
    return errors


def record_state(records: list[dict[str, Any]]) -> str:
    active = [row for row in records if row.get("status") != "superseded"]
    if any(row.get("status") == "complete" for row in active):
        return "detailed_analysis_available"
    if any(row.get("status") == "hold_incomplete" for row in active):
        return "analysis_hold_incomplete"
    if active and all(row.get("status") == "rejected" for row in active):
        return "analysis_rejected_for_current_use"
    return "not_analyzed"


def check_analysis_structure(path: Path, status: str) -> list[str]:
    errors: list[str] = []
    if status == "complete":
        headings = COMPLETE_HEADINGS
        needed = 3
    elif status == SCOPED_STATUS:
        headings = SCOPED_HEADINGS
        needed = 3
    else:
        return errors
    text = path.read_text(encoding="utf-8")
    for heading in headings:
        if heading not in text:
            errors.append(f"{path}: missing required heading {heading}")
    if len(TIMECODE_RE.findall(text)) < needed:
        errors.append(
            f"{path}: {status} analysis needs at least three timestamped scene rows"
        )
    return errors


def normalized_existing_records(
    records: list[dict[str, Any]],
    root: Path,
    *,
    hasher: HashBinder | None = None,
) -> tuple[list[dict[str, Any]], list[str]]:
    normalized: list[dict[str, Any]] = []
    errors: list[str] = []
    seen_ids: set[str] = set()
    for record in records:
        if not isinstance(record, dict):
            errors.append("HOLD malformed_mapping: analysis record must be a mapping")
            continue
        analysis_id = str(record.get("analysis_id") or "")
        if not analysis_id:
            errors.append("HOLD malformed_mapping: analysis_id is missing")
            continue
        if analysis_id in seen_ids:
            errors.append(f"HOLD duplicate_analysis_id: {analysis_id}: duplicate analysis_id")
            continue
        seen_ids.add(analysis_id)
        try:
            analysis_ref = record.get("analysis") or {}
            analysis_path = resolve_repo_path(str(analysis_ref.get("path") or ""), root)
            actual_analysis_sha = sha256(analysis_path, hasher=hasher)
            if analysis_ref.get("sha256") != actual_analysis_sha:
                errors.append(f"{analysis_ref.get('path')}: stale analysis sha256")
            inputs: list[dict[str, str]] = []
            for item in record.get("analysis_inputs") or []:
                role = str(item.get("role") or "")
                if role not in INPUT_ROLES:
                    errors.append(f"{analysis_id}: unsupported input role {role}")
                    continue
                input_path = resolve_repo_path(str(item.get("path") or ""), root)
                actual_input_sha = sha256(input_path, hasher=hasher)
                if item.get("sha256") != actual_input_sha:
                    errors.append(f"{item.get('path')}: stale input sha256")
                inputs.append(
                    {
                        "role": role,
                        "path": rel_path(input_path, root),
                        "sha256": actual_input_sha,
                    }
                )
            status = str(record.get("status") or "")
            errors.extend(check_analysis_structure(analysis_path, status))
            roles = {item["role"] for item in inputs}
            covered_ranges: list[dict[str, float]] = []
            if status == "complete":
                if "original_video" not in roles:
                    errors.append(f"{record.get('analysis_id')}: complete analysis lacks original_video")
                if "one_second_analysis_surface" not in roles:
                    errors.append(
                        f"{record.get('analysis_id')}: complete analysis lacks one_second_analysis_surface"
                    )
                if record.get("missing_analysis"):
                    errors.append(f"{record.get('analysis_id')}: complete analysis has missing_analysis")
                if record.get("covered_ranges"):
                    errors.append(
                        f"{record.get('analysis_id')}: complete analysis must not declare covered_ranges"
                    )
            if status == SCOPED_STATUS:
                covered_ranges, range_errors = normalize_covered_ranges(
                    record.get("covered_ranges")
                )
                errors.extend(
                    f"{record.get('analysis_id')}: {item}" for item in range_errors
                )
                if "original_video" not in roles:
                    errors.append(
                        f"{record.get('analysis_id')}: complete_scoped analysis lacks original_video"
                    )
                if PARENT_COMPLETE_ROLE not in roles:
                    errors.append(
                        f"{record.get('analysis_id')}: complete_scoped analysis lacks parent_complete_analysis"
                    )
                if not (roles & EXTRACTION_ROLES):
                    errors.append(
                        f"{record.get('analysis_id')}: complete_scoped analysis lacks extraction manifest input"
                    )
                if record.get("missing_analysis"):
                    errors.append(
                        f"{record.get('analysis_id')}: complete_scoped analysis has missing_analysis"
                    )
            normalized_row = {
                "analysis_id": str(record.get("analysis_id") or ""),
                "owner_scope": "source_materials_video_source",
                "authoring_stage": str(record.get("authoring_stage") or ""),
                "status": status,
                "analysis": {
                    "path": rel_path(analysis_path, root),
                    "sha256": actual_analysis_sha,
                },
                "analysis_inputs": inputs,
                "coverage_summary": str(record.get("coverage_summary") or ""),
                "missing_analysis": [
                    str(item) for item in record.get("missing_analysis") or []
                ],
                "authorship_boundary": (
                    "analysis_prose_is_human_or_assigned_model_authored_"
                    "source_hub_is_canonical_owner"
                ),
            }
            if status == SCOPED_STATUS and covered_ranges:
                normalized_row["covered_ranges"] = covered_ranges
            normalized.append(normalized_row)
        except ValueError as exc:
            errors.append(str(exc))
    return sorted(normalized, key=lambda row: row["analysis_id"]), errors


def build_registry(
    root: Path,
    existing: dict[str, Any],
    *,
    hasher: HashBinder | None = None,
    integrity_profile: str = "canonical_gate",
) -> tuple[dict[str, Any], list[str]]:
    if hasher is None:
        hasher = HashBinder(root, profile=integrity_profile)
    errors: list[str] = []
    existing_by_key: dict[str, dict[str, Any]] = {}
    for row in existing.get("sources") or []:
        if not isinstance(row, dict):
            errors.append("HOLD malformed_mapping: existing source row must be a mapping")
            continue
        key = str(row.get("source_key") or "")
        if not key:
            errors.append("HOLD malformed_mapping: existing source_key is missing")
            continue
        if key in existing_by_key:
            errors.append(f"HOLD duplicate_source_key: {key}: duplicate source_key in existing registry")
            continue
        existing_by_key[key] = row
    sources: list[dict[str, Any]] = []
    seen_keys: set[str] = set()
    manifest_paths, glob_errors = source_manifests(root)
    errors.extend(glob_errors)
    for manifest_path in manifest_paths:
        manifest, manifest_digest, parse_errors = load_mapping_from_path(
            manifest_path, hasher=hasher
        )
        errors.extend(parse_errors)
        if parse_errors:
            continue
        source_key = source_identity(manifest)
        if not source_key:
            errors.append(f"{rel_path(manifest_path, root)}: source_key is missing")
            continue
        if source_key in seen_keys:
            errors.append(
                f"HOLD duplicate_source_key: {rel_path(manifest_path, root)}: duplicate source_key {source_key}"
            )
            continue
        seen_keys.add(source_key)
        previous = existing_by_key.get(source_key) or {}
        records, record_errors = normalized_existing_records(
            previous.get("analysis_records") or [],
            root,
            hasher=hasher,
        )
        errors.extend(record_errors)
        primary = primary_media(manifest, root, hasher=hasher)
        duration = duration_seconds(manifest)
        errors.extend(
            validate_scoped_source(
                records,
                primary_media=primary,
                duration_seconds=duration,
                root=root,
            )
        )
        sources.append(
            {
                "source_key": source_key,
                "title": source_title(manifest, manifest_path.parent.name),
                "duration_seconds": duration,
                "source_manifest": {
                    "path": rel_path(manifest_path, root),
                    "sha256": manifest_digest,
                },
                "primary_media": primary,
                "analysis_state": record_state(records),
                "analysis_records": records,
            }
        )
    for source_key, previous in existing_by_key.items():
        if source_key in seen_keys:
            continue
        errors.append(
            f"HOLD missing_source: {source_key} current source manifest is absent; refuse to drop previous metadata"
        )
    registry = {
        "schema_version": SCHEMA_VERSION,
        "artifact_type": "video_reference_analysis_registry",
        "hub_root": "source-materials/video-sources",
        "read_first_path": READ_FIRST_REL.as_posix(),
        "analysis_owner_contract": {
            "shared_hub_role": (
                "source_identity_media_hashes_navigation_and_canonical_source_observation"
            ),
            "creative_owner": (
                "source_owned_human_or_assigned_model_layer_a_b_observation"
            ),
            "complete_requires": [
                "exact_analysis_inputs",
                "whole_source_flow",
                "detailed_timestamped_scene_observations",
                "source_transfer_boundary",
                "source_exclusion_boundary",
            ],
            "machine_validation_boundary": (
                "paths_hashes_required_headings_and_declared_status_only_"
                "no_creative_adequacy_claim"
            ),
        },
        "sources": sorted(sources, key=lambda row: row["source_key"]),
        "automation_boundaries": {
            "network_access": False,
            "creative_authoring": False,
            "analysis_completion_inference": False,
            "download_or_generation_approval": False,
        },
    }
    errors.extend(validate_generated_registry(registry))
    return registry, errors


def status_label(state: str) -> str:
    return {
        "detailed_analysis_available": "상세 분석 있음",
        "analysis_hold_incomplete": "분석 미완료",
        "analysis_rejected_for_current_use": "현재 사용 제외",
        "not_analyzed": "미분석",
    }[state]


def render_read_first(registry: dict[str, Any], *, root: Path | None = None) -> str:
    complete = [
        row
        for row in registry["sources"]
        if row["analysis_state"] != "not_analyzed"
    ]
    unanalysed = [
        row
        for row in registry["sources"]
        if row["analysis_state"] == "not_analyzed"
    ]
    lines = [
        "# 로컬 영상 레퍼런스 — 먼저 읽기",
        "",
        "새 세션은 원본 영상이나 프레임 시트를 다시 열기 전에 이 파일을 먼저 읽는다.",
        "여기서 `상세 분석 있음`인 소스 공용 분석본을 찾은 뒤, 그 분석본에 적힌",
        "입력 파일·전체 흐름·시간대별 장면 기록을 먼저 사용한다.",
        "",
        "단, 원본 바이트가 바뀌었거나 분석이 `미완료`인 경우, 또는 Founder가",
        "다시 보라고 지시한 경우에는 해당 영상과 선택 구간을 다시 확인한다.",
        "",
        "## 상태 읽는 법",
        "",
        "- **상세 분석 있음**: 원본 영상과 1초 분석 시트가 해시로 연결되고,",
        "  전체 흐름과 시간대별 행동 기록이 있는 상태.",
        "- **분석 미완료**: 파일은 있으나 큰 흐름이나 상세 행동 기록이 빠진 상태.",
        "- **현재 사용 제외**: 공용 소스 관찰로 쓰지 않기로 닫은 상태.",
        "- **미분석**: 다운로드·프레임 정리만 되었고 창작 분석은 아직 없는 상태.",
        "",
        "## 분석이 등록된 소스",
        "",
    ]
    if not complete:
        lines.extend(["아직 없습니다.", ""])
    for source in complete:
        duration = source["duration_seconds"]
        duration_text = f"{duration:.3f}초" if duration is not None else "길이 미확인"
        lines.extend(
            [
                f"### {source['title']}",
                "",
                f"- 소스: `{source['source_key']}` · {duration_text}",
                f"- 상태: **{status_label(source['analysis_state'])}**",
                f"- 원본 기록: `{source['source_manifest']['path']}`",
            ]
        )
        for record in source["analysis_records"]:
            lines.extend(
                [
                    f"- 분석본: `{record['analysis']['path']}`",
                    f"  - 소유/작성 단계: `{record['owner_scope']}` · `{record['authoring_stage']}`",
                    f"  - 상태/범위: `{record['status']}` · {record['coverage_summary']}",
                    "  - 실제 분석 입력:",
                ]
            )
            for item in record["analysis_inputs"]:
                lines.append(f"    - `{item['role']}` · `{item['path']}`")
            if record["missing_analysis"]:
                lines.append("  - 아직 빠진 분석:")
                for item in record["missing_analysis"]:
                    lines.append(f"    - {item}")
        lines.append("")
    lines.extend(
        [
            "## 아직 상세 분석이 없는 소스",
            "",
            "| 소스 | 제목 | 길이 | 상태 |",
            "|---|---|---:|---|",
        ]
    )
    if unanalysed:
        for source in unanalysed:
            duration = source["duration_seconds"]
            duration_text = f"{duration:.1f}초" if duration is not None else "미확인"
            safe_title = source["title"].replace("|", "\\|")
            lines.append(
                f"| `{source['source_key']}` | {safe_title} | {duration_text} | 미분석 |"
            )
    else:
        lines.append("| - | 없음 | - | - |")
    lines.extend(
        [
            "",
            "## 상세 분석본 필수 구성",
            "",
            "1. **분석에 실제로 사용한 자료** — 원본 영상, 1초 시트, 선택 구간,",
            "   필요하면 0.5초 전환 시트까지 경로와 해시를 적는다.",
            "2. **영상 전체의 큰 흐름** — 도입부터 결말까지 무엇이 어떻게",
            "   바뀌는지 큰 단위로 적는다.",
            "3. **상세 장면 기록** — 시간대마다 누가 어디서 무엇을 어떤 순서로",
            "   하는지, 몸·표정·시선·사물·공간·카메라·편집 변화를 적는다.",
            "4. **공용 관찰의 허용/제외 전이 경계** — 소스에서 관찰된 사실과",
            "   멤버 정체성·원작 세계관·브랜드 등 이전할 수 없는 요소를 분리한다.",
            "",
            "이 파일은 길잡이일 뿐 창작 분석을 대신하지 않는다. 자동 도구는 경로,",
            "해시, 필수 제목과 선언된 상태만 확인하며 장면 해석의 적절성을 판단하지 않는다.",
            "",
        ]
    )
    if root is not None:
        unit_registry, _previous, unit_error = load_contained_registry(
            Path("source-materials/video-sources/sequence-unit-registry.yaml"),
            root,
            missing_ok=True,
        )
        if unit_error:
            lines.extend(["", unit_error, ""])
        units = unit_registry.get("units") if isinstance(unit_registry.get("units"), list) else []
        if units:
            lines.extend(["## 재사용 Sequence Units", ""])
            grouped: dict[str, list[dict[str, Any]]] = {}
            for unit in units:
                if isinstance(unit, dict):
                    grouped.setdefault(str(unit.get("source_key") or ""), []).append(unit)
            for source_key in sorted(grouped):
                rows = grouped[source_key]
                lines.append(f"- 소스 `{source_key}`: {len(rows)} Units")
                for unit in rows:
                    lines.append(
                        f"  - `{unit.get('source_sequence_unit_id')}` · {unit.get('source_time_range')} · "
                        f"{', '.join(unit.get('purpose_classes') or [])} · `{((unit.get('batch_pointer') or {}).get('path'))}`"
                    )
                lines.append("")
    return "\n".join(lines)


def write_registry_and_readme(
    registry: dict[str, Any],
    root: Path,
    *,
    hasher: HashBinder,
    previous_registry: str | None,
    previous_readme: str | None,
) -> list[str]:
    errors = hasher.verify_publication()
    registry_dest, registry_error = contained_registry_destination(REGISTRY_REL, root)
    readme_dest, readme_error = contained_registry_destination(READ_FIRST_REL, root)
    if registry_error:
        errors.append(registry_error)
    if readme_error:
        errors.append(readme_error)
    errors.extend(validate_generated_registry(registry))
    if errors or registry_dest is None or readme_dest is None:
        return errors
    registry_text = yaml.safe_dump(
        registry,
        allow_unicode=True,
        sort_keys=False,
        width=1000,
    )
    readme_text = render_read_first(registry, root=root)
    if readme_text.find("HOLD escaped_path:") >= 0:
        errors.append("HOLD escaped_path: sequence-unit-registry.yaml is not a contained registry input")
        return errors
    report = publish_canonical_derived(
        canonical=[
            PublicationTarget(
                registry_dest,
                registry_text,
                previous_registry,
                role="canonical",
            )
        ],
        derived=[
            PublicationTarget(
                readme_dest,
                readme_text,
                previous_readme,
                role="derived",
            )
        ],
    )
    return report.holds


def command_sync(args: argparse.Namespace) -> int:
    root = resolve_root(args)
    hasher = HashBinder(root, profile=integrity_profile_of(args))
    existing, previous_registry, load_error = load_contained_registry(
        REGISTRY_REL, root, missing_ok=True
    )
    previous_readme, readme_error = load_contained_text(
        READ_FIRST_REL, root, missing_ok=True
    )
    if load_error or readme_error:
        emit_integrity(hasher)
        print("\n".join([item for item in (load_error, readme_error) if item]), file=sys.stderr)
        return 1
    registry, errors = build_registry(root, existing, hasher=hasher)
    if errors:
        emit_integrity(hasher)
        print("\n".join(errors), file=sys.stderr)
        return 1
    publish_errors = write_registry_and_readme(
        registry,
        root,
        hasher=hasher,
        previous_registry=previous_registry,
        previous_readme=previous_readme,
    )
    emit_integrity(hasher)
    if publish_errors:
        print("\n".join(publish_errors), file=sys.stderr)
        return 1
    print(f"synced {len(registry['sources'])} source rows")
    return 0


def parse_input(
    value: str,
    root: Path,
    *,
    hasher: HashBinder | None = None,
) -> dict[str, str]:
    role, separator, raw_path = value.partition("=")
    if not separator or role not in INPUT_ROLES or not raw_path:
        raise ValueError("input must be ROLE=REPO_PATH with a supported role")
    path = resolve_repo_path(raw_path, root)
    return {
        "role": role,
        "path": rel_path(path, root),
        "sha256": sha256(path, hasher=hasher),
    }


def command_register(args: argparse.Namespace) -> int:
    root = resolve_root(args)
    hasher = HashBinder(root, profile=integrity_profile_of(args))
    existing, previous_registry, load_error = load_contained_registry(
        REGISTRY_REL, root, missing_ok=True
    )
    previous_readme, readme_error = load_contained_text(
        READ_FIRST_REL, root, missing_ok=True
    )
    if load_error or readme_error:
        emit_integrity(hasher)
        print("\n".join([item for item in (load_error, readme_error) if item]), file=sys.stderr)
        return 1
    manifest_path = resolve_repo_path(args.source_manifest, root)
    manifest = load_yaml(manifest_path)
    source_key = source_identity(manifest)
    if not source_key:
        print("source manifest has no source_key", file=sys.stderr)
        return 1
    analysis_path = resolve_repo_path(args.analysis, root)
    inputs = [parse_input(value, root, hasher=hasher) for value in args.input]
    status = args.status
    structure_errors = check_analysis_structure(analysis_path, status)
    roles = {item["role"] for item in inputs}
    covered_ranges: list[dict[str, float]] = []
    if status == "complete":
        if "original_video" not in roles:
            structure_errors.append("complete analysis requires original_video input")
        if "one_second_analysis_surface" not in roles:
            structure_errors.append(
                "complete analysis requires one_second_analysis_surface input"
            )
        if args.missing_analysis:
            structure_errors.append("complete analysis cannot declare missing_analysis")
        if getattr(args, "covered_range", None):
            structure_errors.append("complete analysis must not declare covered_ranges")
    if status == SCOPED_STATUS:
        if args.missing_analysis:
            structure_errors.append("complete_scoped analysis cannot declare missing_analysis")
        try:
            covered_ranges = [
                parse_covered_range(item) for item in (getattr(args, "covered_range", None) or [])
            ]
        except ValueError as exc:
            structure_errors.append(str(exc))
        if not covered_ranges:
            structure_errors.append("complete_scoped requires --covered-range START,END")
        if "original_video" not in roles:
            structure_errors.append("complete_scoped analysis requires original_video input")
        if PARENT_COMPLETE_ROLE not in roles:
            structure_errors.append(
                "complete_scoped analysis requires parent_complete_analysis input"
            )
        if not (roles & EXTRACTION_ROLES):
            structure_errors.append(
                "complete_scoped analysis requires an extraction manifest input"
            )
    if structure_errors:
        print("\n".join(structure_errors), file=sys.stderr)
        return 1
    registry, errors = build_registry(root, existing, hasher=hasher)
    if errors:
        emit_integrity(hasher)
        print("\n".join(errors), file=sys.stderr)
        return 1
    source = next((row for row in registry["sources"] if row["source_key"] == source_key), None)
    if source is None:
        emit_integrity(hasher)
        print(f"source is not registered in canonical hub: {source_key}", file=sys.stderr)
        return 1
    record = {
        "analysis_id": args.analysis_id,
        "owner_scope": "source_materials_video_source",
        "authoring_stage": args.authoring_stage,
        "status": status,
        "analysis": {
            "path": rel_path(analysis_path, root),
            "sha256": sha256(analysis_path, hasher=hasher),
        },
        "analysis_inputs": inputs,
        "coverage_summary": args.coverage_summary,
        "missing_analysis": args.missing_analysis,
        "authorship_boundary": (
            "analysis_prose_is_human_or_assigned_model_authored_source_hub_is_canonical_owner"
        ),
    }
    if status == SCOPED_STATUS:
        record["covered_ranges"] = covered_ranges
    merged = [
        row for row in source["analysis_records"] if row["analysis_id"] != args.analysis_id
    ] + [record]
    scoped_errors = validate_scoped_source(
        merged,
        primary_media=source.get("primary_media"),
        duration_seconds=source.get("duration_seconds"),
        root=root,
    )
    if scoped_errors:
        emit_integrity(hasher)
        print("\n".join(scoped_errors), file=sys.stderr)
        return 1
    source["analysis_records"] = merged
    source["analysis_records"] = sorted(
        source["analysis_records"], key=lambda row: row["analysis_id"]
    )
    source["analysis_state"] = record_state(source["analysis_records"])
    publish_errors = write_registry_and_readme(
        registry,
        root,
        hasher=hasher,
        previous_registry=previous_registry,
        previous_readme=previous_readme,
    )
    emit_integrity(hasher)
    if publish_errors:
        print("\n".join(publish_errors), file=sys.stderr)
        return 1
    print(f"registered {args.analysis_id} for {source_key}")
    return 0


def command_verify(args: argparse.Namespace) -> int:
    root = resolve_root(args)
    hasher = HashBinder(root, profile=integrity_profile_of(args))
    existing, previous_registry, load_error = load_contained_registry(
        REGISTRY_REL, root, missing_ok=False
    )
    if load_error:
        emit_integrity(hasher)
        print(load_error, file=sys.stderr)
        return 1
    registry, errors = build_registry(root, existing, hasher=hasher)
    errors.extend(hasher.verify_publication())
    errors.extend(validate_generated_registry(registry))
    if existing != registry:
        errors.append("reference-analysis-registry.yaml is stale; run sync")
    registry_dest, registry_dest_error = contained_registry_destination(
        REGISTRY_REL, root
    )
    if registry_dest_error:
        errors.append(registry_dest_error)
    readme_dest, readme_error = contained_registry_destination(READ_FIRST_REL, root)
    if readme_error:
        errors.append(readme_error)
    elif readme_dest is None or not readme_dest.exists():
        errors.append(f"missing read-first file: {READ_FIRST_REL}")
    if (
        registry_dest is not None
        and readme_dest is not None
        and readme_dest.exists()
    ):
        snapshot, snap_holds = read_publication_snapshot(
            [registry_dest, readme_dest]
        )
        errors.extend(snap_holds)
        if not snap_holds:
            current_registry = snapshot.get(str(registry_dest))
            current_readme = snapshot.get(str(readme_dest))
            if previous_registry is not None and current_registry != previous_registry:
                errors.append(
                    f"HOLD concurrent_output_change: {registry_dest} changed during verify"
                )
            expected_readme = render_read_first(registry, root=root)
            if current_readme != expected_readme:
                if "READ-FIRST.md is stale; run sync" not in errors:
                    errors.append("READ-FIRST.md is stale; run sync")
    emit_integrity(hasher)
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print(f"verified {len(registry['sources'])} source rows")
    return 0


def parser() -> argparse.ArgumentParser:
    root_parser = argparse.ArgumentParser()
    root_parser.add_argument("--repo-root")
    root_parser.add_argument(
        "--integrity-profile",
        choices=("canonical_gate", "repeat_local_validation"),
        default="canonical_gate",
    )
    subparsers = root_parser.add_subparsers(dest="command", required=True)
    sync = subparsers.add_parser("sync")
    sync.set_defaults(func=command_sync)

    register = subparsers.add_parser("register")
    register.add_argument("--source-manifest", required=True)
    register.add_argument("--analysis", required=True)
    register.add_argument("--analysis-id", required=True)
    register.add_argument("--authoring-stage", required=True)
    register.add_argument(
        "--status",
        required=True,
        choices=(
            "complete",
            "complete_scoped",
            "hold_incomplete",
            "rejected",
            "superseded",
        ),
    )
    register.add_argument("--coverage-summary", required=True)
    register.add_argument("--covered-range", action="append", default=[])
    register.add_argument("--missing-analysis", action="append", default=[])
    register.add_argument("--input", action="append", default=[], required=True)
    register.set_defaults(func=command_register)

    verify = subparsers.add_parser("verify")
    verify.set_defaults(func=command_verify)
    return root_parser


def main() -> int:
    args = parser().parse_args()
    try:
        return int(args.func(args))
    except (OSError, ValueError, yaml.YAMLError) as exc:
        print(str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
