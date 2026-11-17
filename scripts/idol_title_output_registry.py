#!/usr/bin/env python3
"""Maintain album/title registries for IDOL track boards and post-02B artifacts."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from datetime import datetime
from pathlib import Path
from typing import Any

from lib.idol_run_layout import (
    ACTIVE_RUN_ROOT_RE,
    registered_transition_entry,
    validate_run_manifest,
)


SCHEMA_VERSION = "1.1"
DEFAULT_ALBUM_KEY = "aurora-m"
CATALOG_ROOT = Path("catalog/albums")
RUN_ROOT_RE = ACTIVE_RUN_ROOT_RE
OUTPUT_TYPES = {
    "02b_prompt_export",
    "02a_high_density_section_link_review",
    "track_creative_board",
    "01a_visual_board",
    "album_look_lock",
    "solo_section_reference_board",
    "solo_reference_sheet_image",
    "space_reference_contact_sheet_image",
    "object_system_lock",
    "object_contact_sheet_image",
    "background_board_image",
    "wardrobe_board_image",
    "wardrobe_contact_sheet_image",
    "unit_character_board_image",
    "album_asset_manifest",
    "album_reference_index",
    "album_contact_sheet_index",
    "reference_cache_manifest",
    "reference_source_video",
    "reference_source_image",
    "reference_source_audio",
    "reference_contact_sheet",
    "imagegen_manifest",
    "review_board_image",
    "branch_cut_image",
    "contact_sheet_image",
    "batch_api_state",
    "batch_api_request",
    "batch_api_result",
    "drive_handoff_package",
    "video_prompt",
    "03v_source_snapshot",
    "video_prompt_source_pack",
    "video_prompt_authoring_request",
    "generated_video",
    "edit_master",
    "cutdown",
    "short",
    "package",
    "social_asset",
    "publishing_record",
    "analytics_snapshot",
    "remote_publication",
    "qc_artifact",
    "other",
}
LATEST_POINTER_EXCLUDED_STATUSES = {"declared", "hold", "missing", "archived"}
REMOTE_REFERENCE_RE = re.compile(r"^https://[^\s]+$")


def load_yaml(path: Path) -> Any:
    import yaml  # type: ignore

    return yaml.safe_load(path.read_text(encoding="utf-8"))


def dump_yaml(path: Path, data: Any) -> None:
    import yaml  # type: ignore

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(yaml.safe_dump(data, allow_unicode=True, sort_keys=False), encoding="utf-8")


def now_iso() -> str:
    return datetime.now().astimezone().isoformat(timespec="seconds")


def slug(value: str) -> str:
    lowered = str(value or "").strip().lower()
    lowered = re.sub(r"[^0-9a-z가-힣]+", "-", lowered)
    lowered = re.sub(r"^-+|-+$", "", lowered)
    return lowered


def album_key(value: str | None) -> str:
    key = slug(value or DEFAULT_ALBUM_KEY)
    if not re.match(r"^[0-9a-z][0-9a-z-]{1,120}$", key):
        raise ValueError(f"invalid album_key: {value}")
    return key


def title_key(value: str | None, *, fallback: str) -> str:
    key = slug(value or fallback)
    if not re.match(r"^[0-9a-z가-힣][0-9a-z가-힣-]{1,120}$", key):
        raise ValueError(f"invalid title_key: {value or fallback}")
    return key


def rel(path: str | Path) -> str:
    raw = str(path)
    if REMOTE_REFERENCE_RE.match(raw):
        return raw
    p = Path(raw)
    if not p.is_absolute():
        return p.as_posix()
    try:
        return p.relative_to(Path.cwd()).as_posix()
    except ValueError:
        return p.as_posix()


def normalize_run_root(path: str | Path, *, infer_from_child: bool = False) -> str:
    value = rel(path).rstrip("/")
    if not value:
        return ""
    if RUN_ROOT_RE.match(value):
        return value
    if infer_from_child and value.startswith("runs/"):
        parts = Path(value).parts
        if len(parts) >= 4:
            candidate = "/".join(parts[:4])
            if RUN_ROOT_RE.match(candidate):
                return candidate
    transition_candidates = [value]
    if infer_from_child and value.startswith("runs/"):
        parts = Path(value).parts
        if len(parts) >= 3:
            transition_candidates.append("/".join(parts[:3]))
    for candidate in dict.fromkeys(transition_candidates):
        entry = registered_transition_entry(candidate, Path.cwd())
        if entry is None:
            continue
        errors = validate_run_manifest(candidate, Path.cwd())
        if errors:
            raise ValueError("; ".join(errors))
        return candidate
    raise ValueError(
        "source run root must be runs/ALBUM_KEY/TITLE_KEY/RUN_ID or the exact "
        "registered in-flight transition; "
        f"got {value}. Pass the owning run root, not a subfolder."
    )


def content_id_from_run_root(run_root: str) -> str:
    normalized = normalize_run_root(run_root)
    return Path(normalized).name if normalized else ""


def registry_paths(album: str, title: str) -> dict[str, str]:
    root = CATALOG_ROOT / album / title
    return {
        "title_root": root.as_posix(),
        "output_registry_path": (root / "output-registry.yaml").as_posix(),
    }


def output_id(output_type: str, path: str, packet_id: str | None = None) -> str:
    seed = f"{output_type}:{packet_id or ''}:{path}"
    return "OUT_" + hashlib.sha1(seed.encode("utf-8")).hexdigest()[:10].upper()


def latest_pointer_candidate(status: str) -> bool:
    return str(status or "").strip() not in LATEST_POINTER_EXCLUDED_STATUSES


def remote_reference(path: str, output_type: str) -> bool:
    """Allow observed public URLs only in their dedicated registry lane."""
    return output_type == "remote_publication" and bool(REMOTE_REFERENCE_RE.match(path))


def default_registry(
    *,
    album: str,
    title: str,
    title_display_name: str,
    content_id: str,
    run_root: str,
    status: str = "active",
) -> dict[str, Any]:
    paths = registry_paths(album, title)
    return {
        "schema_version": SCHEMA_VERSION,
        "album_key": album,
        "title_key": title,
        "title_display_name": title_display_name or title,
        "status": status,
        "canonical_title_root": paths["title_root"],
        "content_ids": [content_id] if content_id else [],
        "source_runs": [],
        "output_roots": {
            "title_root": paths["title_root"],
            "track_creative_board": (Path(paths["title_root"]) / "track-creative-board.yaml").as_posix(),
            "visual_boards": "runs/*/*/*/visual-boards/",
            "run_roots": [run_root] if run_root else [],
            "prompt_exports": "runs/*/*/*/exports/02B/prompts/",
            "imagegen_manifests": "runs/*/*/*/exports/02B/manifests/",
            "review_boards": "runs/*/*/*/generations/review-boards/",
            "branch_cut_images": "runs/*/*/*/generations/branch-cuts/",
            "contact_sheets": "runs/*/*/*/generations/image/*/contact-sheets/",
            "reference_index": (Path(paths["title_root"]) / "reference-index.yaml").as_posix(),
            "contact_sheet_index": (Path(paths["title_root"]) / "contact-sheet-index.yaml").as_posix(),
            "reference_cache_roots": [],
            "canonical_album_assets": f"assets/members/album-assets/{album}/{title}",
            "video_prompts": "runs/*/*/*/generations/video-prompts/",
            "generated_videos": "runs/*/*/*/generations/video/",
            "edits": "runs/*/*/*/generations/video/master/",
            "packages": "runs/*/*/*/package/",
        },
        "outputs": [],
        "latest_pointers": {},
        "review_summary": {
            "founder_review_status": "not_reviewed",
            "passed_output_ids": [],
            "held_output_ids": [],
            "rejected_output_ids": [],
        },
        "open_questions": [],
    }


def load_registry(
    *,
    album: str,
    title: str,
    title_display_name: str,
    content_id: str,
    run_root: str,
    status: str = "active",
) -> tuple[Path, dict[str, Any]]:
    run_root = normalize_run_root(run_root) if run_root else ""
    path = Path(registry_paths(album, title)["output_registry_path"])
    if path.exists():
        registry = load_yaml(path) or {}
        if str(registry.get("schema_version") or "") != SCHEMA_VERSION:
            raise ValueError(
                f"output registry must use active schema {SCHEMA_VERSION}; "
                "legacy keyframe registries are evidence-only and are not auto-migrated"
            )
    else:
        registry = default_registry(
            album=album,
            title=title,
            title_display_name=title_display_name,
            content_id=content_id,
            run_root=run_root,
            status=status,
        )
    registry.setdefault("content_ids", [])
    if content_id and content_id not in registry["content_ids"]:
        registry["content_ids"].append(content_id)
    roots = registry.setdefault("output_roots", {})
    paths = registry_paths(album, title)
    roots.setdefault("title_root", paths["title_root"])
    roots.setdefault("track_creative_board", (Path(paths["title_root"]) / "track-creative-board.yaml").as_posix())
    roots.setdefault("visual_boards", "runs/*/*/*/visual-boards/")
    roots.setdefault("run_roots", [])
    if run_root and run_root not in registry["output_roots"]["run_roots"]:
        registry["output_roots"]["run_roots"].append(run_root)
    return path, registry


def upsert_source_run(registry: dict[str, Any], *, run_root: str, content_id: str, role: str = "production_run") -> None:
    if not run_root:
        return
    run_root = normalize_run_root(run_root)
    stamp = now_iso()
    for entry in registry.setdefault("source_runs", []):
        if entry.get("run_root") == run_root:
            entry["last_updated_at"] = stamp
            entry["content_id"] = content_id or entry.get("content_id", "")
            entry["role"] = role or entry.get("role", "production_run")
            return
    registry["source_runs"].append(
        {
            "run_root": run_root,
            "content_id": content_id,
            "role": role,
            "first_registered_at": stamp,
            "last_updated_at": stamp,
        }
    )


def upsert_output(registry: dict[str, Any], output: dict[str, Any]) -> str:
    output_type = str(output.get("output_type") or "other")
    if output_type not in OUTPUT_TYPES:
        raise ValueError(f"unsupported output_type: {output_type}")
    path = rel(str(output.get("path") or ""))
    if not path:
        raise ValueError("output path is required")
    packet_id = output.get("packet_id")
    oid = str(output.get("output_id") or output_id(output_type, path, packet_id))
    stamp = now_iso()
    source_run_root = str(output.get("source_run_root") or "")
    if source_run_root:
        source_run_root = normalize_run_root(source_run_root, infer_from_child=True)
    normalized = {
        "output_id": oid,
        "output_type": output_type,
        "path": path,
        "source_run_root": source_run_root,
        "content_id": str(output.get("content_id") or ""),
        "packet_id": packet_id if packet_id not in ("", None) else None,
        "core_cut_id": output.get("core_cut_id") if output.get("core_cut_id") not in ("", None) else None,
        "branch_cut_id": output.get("branch_cut_id") if output.get("branch_cut_id") not in ("", None) else None,
        "beat_id": output.get("beat_id") if output.get("beat_id") not in ("", None) else None,
        "section_id": output.get("section_id") if output.get("section_id") not in ("", None) else None,
        "source_step": str(output.get("source_step") or "other"),
        "status": str(output.get("status") or "declared"),
        "registered_at": stamp,
        "last_seen_at": stamp,
        "notes": str(output.get("notes") or ""),
    }
    outputs = registry.setdefault("outputs", [])
    for idx, existing in enumerate(outputs):
        if existing.get("output_id") == oid or (
            existing.get("output_type") == output_type
            and existing.get("path") == path
            and existing.get("packet_id") == normalized["packet_id"]
        ):
            normalized["registered_at"] = existing.get("registered_at", stamp)
            outputs[idx] = {**existing, **normalized}
            break
    else:
        outputs.append(normalized)
    latest_pointers = registry.setdefault("latest_pointers", {})
    if latest_pointer_candidate(normalized["status"]):
        latest_pointers[output_type] = path
    elif latest_pointers.get(output_type) == path:
        latest_pointers.pop(output_type)
    return oid


def register_outputs(
    *,
    album: str,
    title: str,
    title_display_name: str,
    content_id: str,
    run_root: str,
    outputs: list[dict[str, Any]],
    status: str = "active",
    write: bool = False,
) -> dict[str, Any]:
    run_root = normalize_run_root(run_root) if run_root else ""
    registry_path, registry = load_registry(
        album=album,
        title=title,
        title_display_name=title_display_name,
        content_id=content_id,
        run_root=run_root,
        status=status,
    )
    registry["status"] = status
    upsert_source_run(registry, run_root=run_root, content_id=content_id)
    output_ids = [upsert_output(registry, output) for output in outputs]
    if write:
        dump_yaml(registry_path, registry)
    return {
        "registry_path": registry_path.as_posix(),
        "write": bool(write),
        "output_count": len(outputs),
        "output_ids": output_ids,
    }


def register_02b_export_rows(
    *,
    album: str,
    title: str,
    title_display_name: str,
    content_id: str,
    run_root: str,
    rows: list[dict[str, Any]],
    write: bool = False,
) -> dict[str, Any]:
    outputs: list[dict[str, Any]] = []
    for row in rows:
        packet_id = str(row.get("packet_id") or "")
        core_cut_id = str(row.get("core_cut_id") or "")
        branch_cut_id = str(row.get("branch_cut_id") or "")
        section_id = str(row.get("section_id") or "")
        common = {
            "source_run_root": run_root,
            "content_id": content_id,
            "packet_id": packet_id,
            "core_cut_id": core_cut_id,
            "branch_cut_id": branch_cut_id,
            "section_id": section_id,
        }
        if row.get("prompt_path"):
            outputs.append(
                {
                    **common,
                    "output_type": "02b_prompt_export",
                    "path": row["prompt_path"],
                    "source_step": "export_manifest",
                    "status": "exported",
                    "notes": "02B Branch-Cut five-line prompt export.",
                }
            )
        if row.get("manifest_path"):
            outputs.append(
                {
                    **common,
                    "output_type": "imagegen_manifest",
                    "path": row["manifest_path"],
                    "source_step": "export_manifest",
                    "status": "exported",
                    "notes": "Pre-API imagegen manifest.",
                }
            )
        if row.get("expected_output_path"):
            outputs.append(
                {
                    **common,
                    "output_type": "branch_cut_image",
                    "path": row["expected_output_path"],
                    "source_step": "API_preflight_validation",
                    "status": "declared",
                    "notes": "Expected Branch-Cut image path declared before generation.",
                }
            )
    return register_outputs(
        album=album,
        title=title,
        title_display_name=title_display_name,
        content_id=content_id,
        run_root=run_root,
        outputs=outputs,
        status="active",
        write=write,
    )


def register_batch_state_data(state_path: Path, state: dict[str, Any], *, write: bool = False) -> dict[str, Any]:
    catalog = state.get("title_catalog") or {}
    album = album_key(catalog.get("album_key"))
    title = title_key(catalog.get("title_key"), fallback=str(state.get("content_id") or "untitled"))
    title_display_name = str(catalog.get("title_display_name") or title)
    run_root = normalize_run_root(str(state.get("run_root") or ""), infer_from_child=True)
    content_id = str(state.get("content_id") or "")
    files = state.get("local_files") or {}
    outputs = [
        {
            "output_type": "batch_api_state",
            "path": state_path,
            "source_run_root": run_root,
            "content_id": content_id,
            "source_step": "API_preflight_validation",
            "status": "prepared",
            "notes": "OpenAI Batch API local state.",
        },
        {
            "output_type": "batch_api_request",
            "path": state.get("request_jsonl_path", ""),
            "source_run_root": run_root,
            "content_id": content_id,
            "source_step": "API_preflight_validation",
            "status": "prepared",
            "notes": "OpenAI Batch API request JSONL.",
        },
    ]
    for key in ("output_jsonl_path", "error_jsonl_path", "import_report_path"):
        if files.get(key):
            outputs.append(
                {
                    "output_type": "batch_api_result",
                    "path": files[key],
                    "source_run_root": run_root,
                    "content_id": content_id,
                    "source_step": "submit",
                    "status": "declared",
                    "notes": f"Batch API {key}.",
                }
            )
    return register_outputs(
        album=album,
        title=title,
        title_display_name=title_display_name,
        content_id=content_id,
        run_root=run_root,
        outputs=outputs,
        status="active",
        write=write,
    )


def register_generated_review_image_from_manifest(
    manifest_path: Path,
    manifest: dict[str, Any],
    output_path: Path,
    *,
    write: bool = False,
) -> dict[str, Any]:
    album = album_key(manifest.get("album_key"))
    title = title_key(manifest.get("title_key"), fallback=str(manifest.get("content_id") or "untitled"))
    title_display_name = str(manifest.get("title_display_name") or title)
    source_packet_path = Path(str(manifest.get("source_packet_path") or ""))
    run_root = normalize_run_root(source_packet_path.parent, infer_from_child=True) if str(source_packet_path) else ""
    content_id = str(manifest.get("content_id") or "")
    common = {
        "source_run_root": run_root,
        "content_id": content_id,
        "packet_id": manifest.get("packet_id"),
        "core_cut_id": manifest.get("core_cut_id"),
        "branch_cut_id": manifest.get("branch_cut_id"),
        "beat_id": manifest.get("beat_id"),
        "section_id": manifest.get("section_id"),
    }
    outputs = [
        {
            **common,
            "output_type": "imagegen_manifest",
            "path": manifest_path,
            "source_step": "generated_board_review",
            "status": "generated",
            "notes": "Manifest updated after generated image import.",
        },
        {
            **common,
            "output_type": "branch_cut_image",
            "path": output_path,
            "source_step": "generated_board_review",
            "status": "generated",
            "notes": "Generated Branch-Cut image imported from an execution result.",
        },
    ]
    return register_outputs(
        album=album,
        title=title,
        title_display_name=title_display_name,
        content_id=content_id,
        run_root=run_root,
        outputs=outputs,
        status="generated",
        write=write,
    )


def command_ensure(args: argparse.Namespace) -> dict[str, Any]:
    run_root = normalize_run_root(args.run)
    content_id = content_id_from_run_root(run_root)
    album = album_key(args.album_key)
    title = title_key(args.title_key, fallback=args.title or content_id)
    result = register_outputs(
        album=album,
        title=title,
        title_display_name=args.title or title,
        content_id=content_id,
        run_root=run_root,
        outputs=[],
        status=args.status,
        write=args.write,
    )
    return result


def command_register_path(args: argparse.Namespace) -> dict[str, Any]:
    run_root = normalize_run_root(args.run)
    content_id = content_id_from_run_root(run_root)
    album = album_key(args.album_key)
    title = title_key(args.title_key, fallback=args.title or content_id)
    return register_outputs(
        album=album,
        title=title,
        title_display_name=args.title or title,
        content_id=content_id,
        run_root=run_root,
        outputs=[
            {
                "output_type": args.output_type,
                "path": args.path,
                "source_run_root": run_root,
                "content_id": content_id,
                "packet_id": args.packet_id,
                "core_cut_id": args.core_cut_id,
                "branch_cut_id": args.branch_cut_id,
                "beat_id": args.beat_id,
                "section_id": args.section_id,
                "source_step": args.source_step,
                "status": args.output_status,
                "notes": args.notes or "",
            }
        ],
        status=args.registry_status,
        write=args.write,
    )


def command_register_02b_export(args: argparse.Namespace) -> dict[str, Any]:
    run_root = normalize_run_root(args.run)
    content_id = content_id_from_run_root(run_root)
    export_index = Path(args.export_index or Path(args.run) / "exports/02B/export-index.yaml")
    index = load_yaml(export_index) or {}
    catalog = index.get("title_catalog") or {}
    album = album_key(args.album_key or catalog.get("album_key"))
    title = title_key(args.title_key or catalog.get("title_key"), fallback=args.title or content_id)
    rows = index.get("requests") or []
    return register_02b_export_rows(
        album=album,
        title=title,
        title_display_name=args.title or catalog.get("title_display_name") or title,
        content_id=str(index.get("content_id") or content_id),
        run_root=run_root,
        rows=rows,
        write=args.write,
    )


def command_register_batch_state(args: argparse.Namespace) -> dict[str, Any]:
    state_path = Path(args.state)
    state = json.loads(state_path.read_text(encoding="utf-8"))
    return register_batch_state_data(state_path, state, write=args.write)


def validate_registry(path: Path) -> dict[str, Any]:
    registry = load_yaml(path) or {}
    errors: list[str] = []
    warnings: list[str] = []

    if str(registry.get("schema_version") or "") != SCHEMA_VERSION:
        errors.append(
            f"schema_version must be active {SCHEMA_VERSION}; legacy keyframe registries are evidence-only"
        )
    output_roots = registry.get("output_roots") or {}
    if "keyframe_images" in output_roots:
        errors.append("output_roots.keyframe_images is retired; use branch_cut_images")
    if not str(output_roots.get("branch_cut_images") or ""):
        errors.append("output_roots.branch_cut_images is required")

    source_run_roots: set[str] = set()
    for idx, entry in enumerate(registry.get("source_runs") or []):
        run_root = str(entry.get("run_root") or "")
        try:
            normalized = normalize_run_root(run_root)
        except ValueError as exc:
            errors.append(f"source_runs[{idx}].run_root: {exc}")
        else:
            source_run_roots.add(normalized)

    for idx, run_root in enumerate((registry.get("output_roots") or {}).get("run_roots") or []):
        try:
            normalized = normalize_run_root(str(run_root))
        except ValueError as exc:
            errors.append(f"output_roots.run_roots[{idx}]: {exc}")
        else:
            source_run_roots.add(normalized)

    outputs = registry.get("outputs") or []
    output_paths_by_type: dict[str, set[str]] = {}
    outputs_by_type_path: dict[tuple[str, str], list[dict[str, Any]]] = {}
    for idx, output in enumerate(outputs):
        output_type = str(output.get("output_type") or "")
        output_path = str(output.get("path") or "")
        output_status = str(output.get("status") or "")
        if output_type not in OUTPUT_TYPES:
            errors.append(f"outputs[{idx}].output_type is not active: {output_type}")
        output_paths_by_type.setdefault(output_type, set()).add(output_path)
        outputs_by_type_path.setdefault((output_type, output_path), []).append(output)

        if output_type == "remote_publication":
            if not remote_reference(output_path, output_type):
                errors.append(
                    f"outputs[{idx}].path must be an https URL for remote_publication: {output_path}"
                )
            if output_status != "published":
                errors.append(
                    f"outputs[{idx}].status must be published for remote_publication: {output_status}"
                )
        elif output_path.startswith(("http://", "https://")):
            errors.append(
                f"outputs[{idx}].path is remote but output_type is {output_type}; use remote_publication"
            )

        if (
            output_path
            and not Path(output_path).exists()
            and not remote_reference(output_path, output_type)
            and output_status not in {"declared", "missing"}
        ):
            errors.append(
                f"outputs[{idx}].path is not readable for status {output_status}: {output_path}"
            )

        source_run_root = str(output.get("source_run_root") or "")
        if source_run_root:
            try:
                normalized = normalize_run_root(source_run_root)
            except ValueError as exc:
                errors.append(f"outputs[{idx}].source_run_root: {exc}")
                normalized = ""
            if normalized and source_run_roots and normalized not in source_run_roots:
                warnings.append(
                    f"outputs[{idx}].source_run_root is not listed in source_runs/output_roots: {normalized}"
                )
            if output_path.startswith("runs/") and normalized and not output_path.startswith(normalized + "/"):
                errors.append(
                    f"outputs[{idx}].path is outside its source_run_root: {output_path}"
                )
        if output_path.startswith("catalog/albums/") and output_type not in {
            "track_creative_board",
            "album_reference_index",
            "album_contact_sheet_index",
        }:
            warnings.append(
                f"outputs[{idx}].path is under catalog; catalog should stay pointer-only: {output_path}"
            )
        if output_path.startswith("drive-sync/") and output_type != "drive_handoff_package":
            warnings.append(
                f"outputs[{idx}].path is under drive-sync but output_type is {output_type}: {output_path}"
            )

    for output_type, pointer_path in (registry.get("latest_pointers") or {}).items():
        if pointer_path not in output_paths_by_type.get(output_type, set()):
            errors.append(
                f"latest_pointers.{output_type} does not match a registered output path: {pointer_path}"
            )
            continue

        pointer_rows = outputs_by_type_path.get((str(output_type), str(pointer_path)), [])
        if not Path(str(pointer_path)).exists() and not remote_reference(str(pointer_path), str(output_type)):
            errors.append(
                f"latest_pointers.{output_type} points to a missing file: {pointer_path}"
            )
        pointer_statuses = {str(row.get("status") or "") for row in pointer_rows}
        excluded_statuses = sorted(pointer_statuses & LATEST_POINTER_EXCLUDED_STATUSES)
        if excluded_statuses:
            errors.append(
                f"latest_pointers.{output_type} points to non-current status {', '.join(excluded_statuses)}: {pointer_path}"
            )

    return {
        "registry_path": path.as_posix(),
        "valid": not errors,
        "error_count": len(errors),
        "warning_count": len(warnings),
        "output_count": len(outputs),
        "errors": errors,
        "warnings": warnings,
    }


def command_validate(args: argparse.Namespace) -> dict[str, Any]:
    return validate_registry(Path(args.registry))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    ensure = subparsers.add_parser("ensure", help="create or update a title registry shell")
    ensure.add_argument("--run", required=True)
    ensure.add_argument("--album-key", default=DEFAULT_ALBUM_KEY)
    ensure.add_argument("--title-key", default=None)
    ensure.add_argument("--title", default="")
    ensure.add_argument("--status", default="active")
    ensure.add_argument("--write", action="store_true")
    ensure.set_defaults(func=command_ensure)

    register_path = subparsers.add_parser("register-path", help="register one output path")
    register_path.add_argument("--run", required=True)
    register_path.add_argument("--album-key", default=DEFAULT_ALBUM_KEY)
    register_path.add_argument("--title-key", default=None)
    register_path.add_argument("--title", default="")
    register_path.add_argument("--output-type", required=True, choices=sorted(OUTPUT_TYPES))
    register_path.add_argument("--path", required=True)
    register_path.add_argument("--packet-id", default=None)
    register_path.add_argument("--core-cut-id", default=None)
    register_path.add_argument("--branch-cut-id", default=None)
    register_path.add_argument("--beat-id", default=None)
    register_path.add_argument("--section-id", default=None)
    register_path.add_argument("--source-step", default="other")
    register_path.add_argument("--output-status", default="declared")
    register_path.add_argument("--registry-status", default="active")
    register_path.add_argument("--notes", default="")
    register_path.add_argument("--write", action="store_true")
    register_path.set_defaults(func=command_register_path)

    register_02b = subparsers.add_parser("register-02b-export", help="register all rows from a 02B export index")
    register_02b.add_argument("--run", required=True)
    register_02b.add_argument("--export-index", default=None)
    register_02b.add_argument("--album-key", default=None)
    register_02b.add_argument("--title-key", default=None)
    register_02b.add_argument("--title", default="")
    register_02b.add_argument("--write", action="store_true")
    register_02b.set_defaults(func=command_register_02b_export)

    register_batch = subparsers.add_parser("register-batch-state", help="register a prepared Batch API state")
    register_batch.add_argument("--state", required=True)
    register_batch.add_argument("--write", action="store_true")
    register_batch.set_defaults(func=command_register_batch_state)

    validate = subparsers.add_parser("validate", help="validate a title output registry")
    validate.add_argument("--registry", required=True)
    validate.set_defaults(func=command_validate)

    args = parser.parse_args()
    try:
        result = args.func(args)
    except ValueError as exc:
        result = {
            "valid": False,
            "error_count": 1,
            "warning_count": 0,
            "errors": [str(exc)],
            "warnings": [],
        }
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if result.get("valid", True) else 1


if __name__ == "__main__":
    raise SystemExit(main())
