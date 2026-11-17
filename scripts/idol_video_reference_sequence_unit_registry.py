#!/usr/bin/env python3
"""Validate authored reusable Sequence Unit batches and project pointer registry.

Scripts never author Unit observations or current-title disposition.
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
from jsonschema import Draft202012Validator

SCRIPTS_DIR = Path(__file__).resolve().parent
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))
from lib.idol_artifact_integrity import (
    HashBinder,
    PublicationTarget,
    publish_canonical_derived,
    read_publication_snapshot,
)


ROOT = Path(__file__).resolve().parents[1]
SCHEMA = ROOT / "schemas" / "video-reference-sequence-unit-registry.schema.json"
BATCH_GLOB = "source-materials/video-sources/**/analysis/reusable-sequence-units-v1.yaml"
REGISTRY_REL = Path("source-materials/video-sources/sequence-unit-registry.yaml")
FORBIDDEN_FIELDS = {"album_key", "section_id", "mj_id", "disposition"}
SEQUENCE_FRAME_COUNT = 5
SEQUENCE_CADENCE_SECONDS = 1.0
CADENCE_TOLERANCE = 0.001


class RegistryError(RuntimeError):
    pass


def sha256_file(path: Path, *, hasher: HashBinder | None = None) -> str:
    if hasher is not None:
        return hasher.sha256(path)
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


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


def resolve_contained_file(raw: str, root: Path) -> tuple[Path | None, str | None]:
    root_resolved = root.resolve()
    path = Path(raw)
    candidate = path if path.is_absolute() else root_resolved / path
    try:
        resolved = candidate.resolve(strict=False)
        resolved.relative_to(root_resolved)
    except (OSError, ValueError):
        return None, f"HOLD escaped_path: path must stay inside repository: {raw}"
    if not resolved.is_file():
        return None, f"HOLD missing_pointer: file is missing: {raw}"
    return resolved, None


def finite_nonnegative_timestamp(value: object) -> float | None:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    number = float(value)
    if not math.isfinite(number) or number < 0:
        return None
    return number


def load_yaml(path: Path) -> dict[str, Any]:
    value = yaml.safe_load(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise RegistryError(f"{path} must contain an object")
    return value


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


def validate_batch(
    document: dict[str, Any],
    *,
    path: Path,
    root: Path,
    hasher: HashBinder | None = None,
) -> list[str]:
    errors: list[str] = []
    schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
    for error in Draft202012Validator(schema).iter_errors(document):
        errors.append(f"HOLD malformed_mapping: {path}: {error.message}")
    if document.get("artifact_type") != "reusable_sequence_unit_batch":
        errors.append(f"HOLD malformed_mapping: {path}: expected reusable_sequence_unit_batch")
        return errors
    batch_manifest = document.get("source_manifest")
    if isinstance(batch_manifest, dict):
        resolved, problem = resolve_contained_file(
            str(batch_manifest.get("path") or ""), root
        )
        if problem:
            errors.append(f"{path}: batch source_manifest {problem}")
        elif sha256_file(resolved, hasher=hasher) != batch_manifest.get("sha256"):
            errors.append(f"{path}: batch source_manifest sha256 is stale")
    seen_ids: set[str] = set()
    seen_signatures: set[tuple[str, ...]] = set()
    previous_last_frame: str | None = None
    previous_id: str | None = None
    previous_event: str | None = None
    typed_units: list[dict[str, Any]] = []
    for unit in document.get("units") or []:
        if not isinstance(unit, dict):
            errors.append(f"HOLD malformed_mapping: {path}: unit must be an object")
            continue
        typed_units.append(unit)
        leaked = FORBIDDEN_FIELDS.intersection(unit)
        if leaked:
            errors.append(f"{path}: unit may not contain {sorted(leaked)}")
        unit_id = str(unit.get("source_sequence_unit_id") or "")
        if unit_id in seen_ids:
            errors.append(f"HOLD duplicate_id: {path}: duplicate source_sequence_unit_id {unit_id}")
        seen_ids.add(unit_id)
        if unit.get("source_key") != document.get("source_key"):
            errors.append(f"{path}: unit {unit_id} source_key must match batch")
        if unit.get("source_manifest") != batch_manifest:
            errors.append(
                f"HOLD source_manifest_mismatch: {path}: unit {unit_id} source_manifest must exactly match batch source_manifest"
            )
        frames = unit.get("frames") if isinstance(unit.get("frames"), list) else []
        orders = [frame.get("order") for frame in frames if isinstance(frame, dict)]
        if orders != list(range(1, SEQUENCE_FRAME_COUNT + 1)):
            errors.append(
                f"HOLD malformed_mapping: {path}: unit {unit_id} must have frames ordered 1..{SEQUENCE_FRAME_COUNT}"
            )
        stamps: list[float] = []
        for index, frame in enumerate(frames, start=1):
            if not isinstance(frame, dict):
                errors.append(
                    f"HOLD malformed_mapping: {path}: unit {unit_id} frame {index} must be a mapping"
                )
                continue
            raw_frame_path = str(frame.get("path") or "")
            resolved_frame, frame_problem = resolve_contained_file(raw_frame_path, root)
            if frame_problem:
                errors.append(f"{path}: unit {unit_id} frame {frame_problem}")
            elif sha256_file(resolved_frame, hasher=hasher) != frame.get("sha256"):
                errors.append(
                    f"{path}: unit {unit_id} frame sha256 is stale: {raw_frame_path}"
                )
            stamp = finite_nonnegative_timestamp(frame.get("source_timestamp_seconds"))
            if stamp is None:
                errors.append(
                    f"HOLD invalid_timestamp: {path}: unit {unit_id} frame {index} timestamp must be a finite nonnegative number"
                )
            else:
                stamps.append(stamp)
        if len(stamps) == SEQUENCE_FRAME_COUNT:
            for index, (current, following) in enumerate(zip(stamps, stamps[1:]), start=1):
                if abs((following - current) - SEQUENCE_CADENCE_SECONDS) > CADENCE_TOLERANCE:
                    errors.append(
                        f"HOLD cadence: {path}: unit {unit_id} frames {index}-{index + 1} are not consecutive exact one-second samples"
                    )
        signature = tuple(
            f"{frame.get('path')}:{frame.get('sha256')}:{frame.get('source_timestamp_seconds')}"
            for frame in frames
            if isinstance(frame, dict)
        )
        if signature in seen_signatures:
            errors.append(
                f"HOLD duplicate_signature: {path}: unit {unit_id} duplicates an exact frame/time signature"
            )
        seen_signatures.add(signature)
        event_identity = str(unit.get("event_identity") or "")
        if unit.get("linked_previous_unit_id"):
            if unit.get("linked_previous_unit_id") != previous_id:
                errors.append(f"{path}: unit {unit_id} linked_previous_unit_id is not contiguous")
            if previous_event is not None and event_identity != previous_event:
                errors.append(
                    f"HOLD event_identity: {path}: unit {unit_id} linked units must share event_identity"
                )
            first_frame = frames[0]["path"] if frames and isinstance(frames[0], dict) else None
            if previous_last_frame and first_frame == previous_last_frame:
                errors.append(f"{path}: linked units must not duplicate boundary frames")
        previous_last_frame = frames[-1]["path"] if frames and isinstance(frames[-1], dict) else None
        previous_id = unit_id
        previous_event = event_identity
        for pointer_key in ("source_manifest", "analysis_ref"):
            pointer = unit.get(pointer_key)
            if not isinstance(pointer, dict):
                continue
            resolved, problem = resolve_contained_file(str(pointer.get("path") or ""), root)
            if problem:
                errors.append(f"{path}: {pointer_key} {problem}")
                continue
            if sha256_file(resolved, hasher=hasher) != pointer.get("sha256"):
                errors.append(f"{path}: {pointer_key} sha256 is stale")
    by_id: dict[str, dict[str, Any]] = {}
    for unit in typed_units:
        unit_id = str(unit.get("source_sequence_unit_id") or "")
        if unit_id:
            by_id[unit_id] = unit
    for unit in typed_units:
        unit_id = str(unit.get("source_sequence_unit_id") or "")
        nxt = unit.get("linked_next_unit_id")
        prev = unit.get("linked_previous_unit_id")
        if nxt not in (None, ""):
            nxt_id = str(nxt)
            if nxt_id not in by_id:
                errors.append(
                    f"HOLD linked_next_unknown: {path}: unit {unit_id} linked_next_unit_id {nxt_id} is not in this batch"
                )
            elif str(by_id[nxt_id].get("linked_previous_unit_id") or "") != unit_id:
                errors.append(
                    f"HOLD linked_reciprocity: {path}: unit {unit_id} linked_next_unit_id is not reciprocated"
                )
            elif str(by_id[nxt_id].get("event_identity") or "") != str(unit.get("event_identity") or ""):
                errors.append(
                    f"HOLD event_identity: {path}: unit {unit_id} linked_next_unit_id must share event_identity"
                )
        if prev not in (None, ""):
            prev_id = str(prev)
            if prev_id not in by_id:
                errors.append(
                    f"HOLD linked_previous_unknown: {path}: unit {unit_id} linked_previous_unit_id {prev_id} is not in this batch"
                )
            elif str(by_id[prev_id].get("linked_next_unit_id") or "") != unit_id:
                errors.append(
                    f"HOLD linked_reciprocity: {path}: unit {unit_id} linked_previous_unit_id is not reciprocated"
                )
    return errors


def collect_batches(root: Path) -> tuple[list[Path], list[str]]:
    root_resolved = root.resolve()
    paths: list[Path] = []
    errors: list[str] = []
    for path in sorted(root.glob(BATCH_GLOB)):
        resolved, problem = resolve_contained_file(str(path), root)
        if problem:
            try:
                path.resolve(strict=False).relative_to(root_resolved)
            except (OSError, ValueError):
                errors.append(f"HOLD escaped_path: {path} batch resolves outside repository")
                continue
            errors.append(f"{path}: {problem}")
            continue
        paths.append(resolved)
    return paths, errors


def build_registry(
    root: Path,
    *,
    hasher: HashBinder | None = None,
    integrity_profile: str = "canonical_gate",
) -> tuple[dict[str, Any], list[str]]:
    if hasher is None:
        hasher = HashBinder(root, profile=integrity_profile)
    errors: list[str] = []
    pointers: list[dict[str, Any]] = []
    seen_ids: set[str] = set()
    seen_signatures: set[tuple[str, ...]] = set()
    found_batches: set[str] = set()
    batch_paths, glob_errors = collect_batches(root)
    errors.extend(glob_errors)
    for path in batch_paths:
        document, batch_digest, parse_errors = load_mapping_from_path(path, hasher=hasher)
        errors.extend(parse_errors)
        if parse_errors:
            continue
        errors.extend(validate_batch(document, path=path, root=root, hasher=hasher))
        rel = path.relative_to(root.resolve()).as_posix()
        found_batches.add(rel)
        batch_pointer = {"path": rel, "sha256": batch_digest}
        for unit in document.get("units") or []:
            if not isinstance(unit, dict):
                continue
            unit_id = str(unit.get("source_sequence_unit_id") or "")
            if unit_id in seen_ids:
                errors.append(f"HOLD duplicate_id: {rel}: duplicate source_sequence_unit_id {unit_id}")
            seen_ids.add(unit_id)
            frames = unit.get("frames") if isinstance(unit.get("frames"), list) else []
            signature = tuple(
                f"{frame.get('path')}:{frame.get('sha256')}:{frame.get('source_timestamp_seconds')}"
                for frame in frames
                if isinstance(frame, dict)
            )
            if signature and signature in seen_signatures:
                errors.append(
                    f"HOLD duplicate_signature: {rel}: unit {unit_id} duplicates an exact frame/time signature"
                )
            if signature:
                seen_signatures.add(signature)
            pointers.append(
                {
                    "source_sequence_unit_id": unit.get("source_sequence_unit_id"),
                    "source_key": unit.get("source_key"),
                    "source_time_range": unit.get("source_time_range"),
                    "purpose_classes": list(unit.get("purpose_classes") or []),
                    "batch_pointer": batch_pointer,
                }
            )
    existing_dest, existing_error = contained_registry_destination(REGISTRY_REL, root)
    if existing_error:
        errors.append(existing_error)
    elif existing_dest is not None and existing_dest.exists():
        existing = load_yaml(existing_dest)
        if existing.get("artifact_type") == "sequence_unit_pointer_registry":
            for unit in existing.get("units") or []:
                if not isinstance(unit, dict):
                    continue
                batch_path = str((unit.get("batch_pointer") or {}).get("path") or "")
                if batch_path and batch_path not in found_batches:
                    errors.append(
                        f"HOLD missing_batch: {batch_path}: previously indexed Sequence Unit batch is missing; refuse to drop units"
                    )
    pointers.sort(key=lambda item: str(item.get("source_sequence_unit_id") or ""))
    registry = {
        "schema_version": "idol_video_reference_sequence_unit_registry.v1",
        "artifact_type": "sequence_unit_pointer_registry",
        "registry_path": REGISTRY_REL.as_posix(),
        "units": pointers,
    }
    return registry, errors


def read_first_appendix(root: Path) -> list[str]:
    registry_path = root / REGISTRY_REL
    if not registry_path.is_file():
        return []
    registry = load_yaml(registry_path)
    if not registry.get("units"):
        return []
    lines = ["## 재사용 Sequence Units", ""]
    grouped: dict[str, list[dict[str, Any]]] = {}
    for unit in registry["units"]:
        grouped.setdefault(str(unit.get("source_key") or ""), []).append(unit)
    for source_key in sorted(grouped):
        units = grouped[source_key]
        lines.append(f"- 소스 `{source_key}`: {len(units)} Units")
        for unit in units:
            lines.append(
                f"  - `{unit['source_sequence_unit_id']}` · {unit['source_time_range']} · "
                f"{', '.join(unit.get('purpose_classes') or [])} · `{unit['batch_pointer']['path']}`"
            )
        lines.append("")
    return lines


def write_registry(
    root: Path,
    *,
    check: bool = False,
    integrity_profile: str = "canonical_gate",
) -> tuple[dict[str, Any], list[str], dict[str, Any]]:
    hasher = HashBinder(root, profile=integrity_profile)
    dest, dest_error = contained_registry_destination(REGISTRY_REL, root)
    previous = None
    if dest_error:
        empty = {
            "schema_version": "idol_video_reference_sequence_unit_registry.v1",
            "artifact_type": "sequence_unit_pointer_registry",
            "registry_path": REGISTRY_REL.as_posix(),
            "units": [],
        }
        return empty, [dest_error], hasher.report()
    if dest is not None and dest.exists():
        previous = dest.read_text(encoding="utf-8")
    registry, errors = build_registry(root, hasher=hasher)
    errors.extend(hasher.verify_publication())
    integrity = hasher.report()
    if errors:
        return registry, errors, integrity
    content = yaml.safe_dump(registry, sort_keys=False)
    assert dest is not None
    if check:
        snapshot, snap_holds = read_publication_snapshot([dest])
        errors.extend(snap_holds)
        if snap_holds:
            return registry, errors, integrity
        if snapshot.get(str(dest)) != content:
            errors.append("sequence-unit-registry is stale")
        return registry, errors, integrity
    report = publish_canonical_derived(
        canonical=[PublicationTarget(dest, content, previous, role="canonical")]
    )
    errors.extend(report.holds)
    return registry, errors, integrity


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Reusable Sequence Unit registry producer")
    parser.add_argument("--repo-root", default=str(ROOT))
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--json", action="store_true")
    parser.add_argument(
        "--integrity-profile",
        choices=("canonical_gate", "repeat_local_validation"),
        default="canonical_gate",
    )
    args = parser.parse_args(argv)
    root = Path(args.repo_root).expanduser().resolve()
    registry, errors, integrity = write_registry(
        root, check=args.check, integrity_profile=args.integrity_profile
    )
    if errors:
        print(
            json.dumps(
                {"status": "hold", "errors": errors, "integrity": integrity},
                ensure_ascii=False,
                indent=2,
            ),
            file=sys.stderr,
        )
        return 1
    if args.json:
        payload = dict(registry)
        payload["integrity"] = integrity
        print(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True))
    else:
        print(
            json.dumps(
                {
                    "status": "pass",
                    "unit_count": len(registry["units"]),
                    "registry_path": REGISTRY_REL.as_posix(),
                    "integrity": integrity,
                },
                ensure_ascii=False,
            )
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
