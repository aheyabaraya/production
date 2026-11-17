#!/usr/bin/env python3
"""Export active 02B packets as local prompt and ordered-reference manifests."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path
from typing import Any

import yaml


ROOT = Path(__file__).resolve().parent.parent
ACTIVE_02B_VERSION = "2.6"
EXPORT_INDEX_VERSION = "idol_02b_export_index.v4"
PACKET_MANIFEST_VERSION = "idol_02b_packet_export_manifest.v4"
PROMPT_LABELS = [
    "Identity reference rule",
    "Scene intent",
    "Visible details",
    "Action cue",
    "Avoid",
]
FACE_ONLY_PATTERN = re.compile(r"(^|/)face-only-reference(?:-|\.|/)", re.IGNORECASE)
RETIRED_NO_MIC_PATTERN = re.compile(
    r"(?:^|[/_-])no[-_]mic(?:[-_. /]|$)", re.IGNORECASE
)
TEMPORAL_CAMERA_PATTERN = re.compile(
    r"\b(?:camera\s+(?:push(?:es)?|pull(?:s)?|pan(?:s)?|tilt(?:s)?|track(?:s)?|"
    r"orbit(?:s)?|doll(?:y|ies)|crane(?:s)?|zoom(?:s)?)|push[- ]?in|pull[- ]?out|"
    r"dolly[- ]?(?:in|out)|camera\s+speed|motion\s+envelope)\b",
    re.IGNORECASE,
)


class ExportError(RuntimeError):
    """Raised when an active 02B packet cannot be exported safely."""


def load_mapping(path: Path) -> dict[str, Any]:
    value = yaml.safe_load(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ExportError(f"{path} must contain an object")
    return value


def canonical_sha256(value: Any) -> str:
    payload = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def resolve_repo_path(raw: str, *, must_exist: bool = False) -> Path:
    path = Path(raw)
    if not path.is_absolute():
        path = ROOT / path
    path = path.resolve(strict=False)
    try:
        path.relative_to(ROOT)
    except ValueError as error:
        raise ExportError(f"path escapes the IDOL repository: {raw}") from error
    if must_exist and not path.is_file():
        raise ExportError(f"required file is missing: {repo_relative(path)}")
    return path


def repo_relative(path: Path) -> str:
    return path.resolve(strict=False).relative_to(ROOT).as_posix()


def validate_prompt(packet: dict[str, Any]) -> dict[str, Any]:
    packet_id = str(packet.get("packet_id", ""))
    block = packet.get("compiled_prompt_block")
    if not isinstance(block, dict):
        raise ExportError(f"{packet_id}: compiled_prompt_block is missing")
    expected_lines = [
        f"Identity reference rule: {block.get('identity_reference_rule', '')}",
        f"Scene intent: {block.get('scene_intent', '')}",
        f"Visible details: {block.get('visible_details', '')}",
        f"Action cue: {block.get('action_cue', '')}",
        f"Avoid: {block.get('avoid', '')}",
    ]
    prompt_text = str(block.get("full_prompt_text", ""))
    if prompt_text.splitlines() != expected_lines:
        raise ExportError(f"{packet_id}: prompt must contain exactly the fixed five lines")
    if block.get("label_order") != PROMPT_LABELS:
        raise ExportError(f"{packet_id}: prompt label order is not active")
    if hashlib.sha256(prompt_text.encode("utf-8")).hexdigest() != block.get("full_prompt_sha256"):
        raise ExportError(f"{packet_id}: prompt SHA-256 is stale")
    visible_details = str(block.get("visible_details", ""))
    for term in ("4K", "high quality", "high detail"):
        if term not in visible_details:
            raise ExportError(f"{packet_id}: Visible details is missing {term}")
    if TEMPORAL_CAMERA_PATTERN.search(prompt_text):
        raise ExportError(f"{packet_id}: temporal camera motion belongs to 03V")
    return block


def export_quality_model(packet: dict[str, Any]) -> str:
    packet_id = str(packet.get("packet_id", ""))
    execution = packet.get("execution") if isinstance(packet.get("execution"), dict) else {}
    adapter = str(execution.get("execution_adapter_id", ""))
    model = execution.get("provider_model_or_tool")
    if adapter == "openai_api_gpt_image_2":
        if model != "gpt-image-2":
            raise ExportError(f"{packet_id}: OpenAI execution must stay on gpt-image-2")
        return "gpt-image-2"
    if adapter in {"grok_image", "codex_imagegen", "xai_api_media"}:
        if not isinstance(model, str) or not model:
            raise ExportError(f"{packet_id}: native execution is missing provider_model_or_tool")
        return model
    raise ExportError(f"{packet_id}: execution adapter is not active")


def validate_attachment(
    packet_id: str,
    binding: dict[str, Any],
    package_album_key: str,
    package_title_key: str,
) -> dict[str, Any]:
    raw_path = str(binding.get("actual_path", ""))
    path = resolve_repo_path(raw_path, must_exist=True)
    relative = repo_relative(path)
    if FACE_ONLY_PATTERN.search(relative):
        raise ExportError(f"{packet_id}: face-only reference entered the active attachment order")
    if RETIRED_NO_MIC_PATTERN.search(relative):
        raise ExportError(
            f"{packet_id}: retired no-mic/no_mic path entered the active attachment order"
        )
    digest = file_sha256(path)
    if digest != binding.get("sha256"):
        raise ExportError(f"{packet_id}: stale attachment SHA-256 for {binding.get('binding_id')}")
    role = str(binding.get("role", ""))
    if role == "current_title_member_visual":
        prefix = f"assets/members/album-assets/{package_album_key}/{package_title_key}/"
        if not relative.startswith(prefix):
            raise ExportError(f"{packet_id}: member visual is outside the current-title package")
    elif role not in {"governing_scene_or_sequence_reference", "supporting_component_reference"}:
        raise ExportError(f"{packet_id}: attachment role is not active")
    result = {
        "input_slot": binding.get("order"),
        "role": role,
        "binding_id": binding.get("binding_id"),
        "asset_id": binding.get("asset_id"),
        "path": relative,
        "sha256": digest,
        "pixel_inspection_status": binding.get("pixel_inspection_status"),
        "locked": binding.get("locked"),
    }
    return result


def packet_manifest(
    source_path: Path,
    source_sha256: str,
    document: dict[str, Any],
    packet: dict[str, Any],
) -> tuple[dict[str, Any], str]:
    packet_id = str(packet["packet_id"])
    if packet.get("mode") != "official_branch":
        raise ExportError(f"{packet_id}: 02B export accepts only official_branch packets")
    block = validate_prompt(packet)
    rendered = packet.get("rendered_five_lines")
    if isinstance(rendered, dict) and rendered != block:
        raise ExportError(f"{packet_id}: rendered_five_lines differs from compiled_prompt_block")
    locked_visuals = packet.get("visual_reference_bindings")
    attachments = packet.get("attachments")
    if isinstance(locked_visuals, list):
        expected_attachments = [
            {
                "order": row.get("order"),
                "role": (
                    "current_title_member_visual"
                    if row.get("reference_scope") == "member_visual"
                    else "governing_scene_or_sequence_reference"
                ),
                "binding_id": row.get("binding_id"),
                "asset_id": row.get("asset_id"),
                "actual_path": row.get("actual_path"),
                "sha256": row.get("sha256"),
                "pixel_inspection_status": "passed",
                "locked": True,
            }
            for row in locked_visuals
            if isinstance(row, dict)
        ]
        if attachments != expected_attachments:
            raise ExportError(
                f"{packet_id}: attachments must remain the transport projection of locked 02A visual_reference_bindings"
            )
    member_lock = packet.get("member_visual_lock", {})
    album_key = str(member_lock.get("package_album_key", ""))
    title_key = str(member_lock.get("package_title_key", ""))
    bindings = packet.get("attachments")
    if not isinstance(bindings, list):
        raise ExportError(f"{packet_id}: active {ACTIVE_02B_VERSION} attachments must be an array")
    if [row.get("order") for row in bindings] != list(range(1, len(bindings) + 1)):
        raise ExportError(f"{packet_id}: attachment order must be contiguous from 1")
    ordered = [
        validate_attachment(packet_id, row, album_key, title_key)
        for row in bindings
        if isinstance(row, dict)
    ]
    member_inputs = [row for row in ordered if row["role"] == "current_title_member_visual"]
    scene_inputs = [row for row in ordered if row["role"] != "current_title_member_visual"]
    selected_ids = [str(value) for value in packet.get("five_line_components", {}).get("identity_reference_rule", {}).get("current_title_visual_bindings", [])]
    if selected_ids != [str(row["asset_id"]) for row in member_inputs]:
        raise ExportError(f"{packet_id}: member-visual selection differs from combined attachment order")
    applicability = str(packet.get("member_visual_applicability", ""))
    if applicability == "meaningfully_visible" and not member_inputs:
        raise ExportError(f"{packet_id}: required current-title member visual is missing")
    if applicability in {"visible_but_member_visual_unnecessary", "not_visible"} and member_inputs:
        raise ExportError(f"{packet_id}: no-member Branch Cut still carries a member visual")
    if applicability not in {"meaningfully_visible", "visible_but_member_visual_unnecessary", "not_visible"}:
        raise ExportError(f"{packet_id}: member_visual_applicability is not active")

    prompt_text = str(block["full_prompt_text"])
    manifest = {
        "schema_version": PACKET_MANIFEST_VERSION,
        "content_id": document["content_id"],
        "packet_id": packet_id,
        "mode": packet["mode"],
        "core_cut_id": packet["core_cut_id"],
        "branch_cut_id": packet["branch_cut_id"],
        "execution_section_id": packet["execution_section_id"],
        "source_02b": {
            "path": repo_relative(source_path),
            "sha256": source_sha256,
            "schema_version": ACTIVE_02B_VERSION,
        },
        "packet_value_sha256": canonical_sha256(packet),
        "prompt": {
            "full_prompt_text": prompt_text,
            "full_prompt_sha256": block["full_prompt_sha256"],
            "label_order": PROMPT_LABELS,
        },
        "member_visual_applicability": applicability,
        "member_visual_inputs": member_inputs,
        "scene_reference_inputs": scene_inputs,
        "attachment_order": ordered,
        "attachment_order_sha256": canonical_sha256(ordered),
        "quality_contract": {
            "model": export_quality_model(packet),
            "quality": "highest_available",
            "dimension_policy": "maximum_supported_dimensions_for_locked_aspect_ratio",
            "required_prompt_terms": ["4K", "high quality", "high detail"],
        },
        "expected_output_path": packet["export_contract"]["expected_output_path"],
        "execution_boundary": {
            "local_export_only": True,
            "paid_generation_approved": False,
            "external_execution_approved": False,
            "request_builder": "scripts/idol_prepare_image_generation_request.rb",
        },
    }
    return manifest, prompt_text


def write_yaml(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        yaml.safe_dump(value, allow_unicode=True, sort_keys=False),
        encoding="utf-8",
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path", help="Canonical approved 02B-prompt-packets.yaml")
    parser.add_argument("--packet-id", action="append", default=[], help="Export only the named packet; repeat as needed")
    parser.add_argument("--output-root", default="", help="Default: RUN/exports/02B")
    parser.add_argument("--dry-run", action="store_true", help="Validate without writing")
    args = parser.parse_args()

    source_path = resolve_repo_path(args.path, must_exist=True)
    document = load_mapping(source_path)
    if document.get("schema_version") != ACTIVE_02B_VERSION:
        raise ExportError(f"only active 02B schema {ACTIVE_02B_VERSION} can be exported")
    if document.get("status") != "approved":
        raise ExportError("canonical 02B must be approved before export")
    packets = [row for row in document.get("prompt_packets", []) if isinstance(row, dict)]
    wanted = set(args.packet_id)
    if wanted:
        packets = [row for row in packets if row.get("packet_id") in wanted]
        missing = wanted - {str(row.get("packet_id")) for row in packets}
        if missing:
            raise ExportError("missing packet ids: " + ", ".join(sorted(missing)))
    if not packets:
        raise ExportError("no packets selected")
    if any(packet.get("status") != "approved" for packet in packets):
        raise ExportError("every exported packet must be approved")

    run_root = source_path.parent
    output_root = resolve_repo_path(args.output_root) if args.output_root else run_root / "exports" / "02B"
    try:
        output_root.relative_to(run_root)
    except ValueError as error:
        raise ExportError("output root must stay inside the owning run") from error

    source_sha256 = file_sha256(source_path)
    rows: list[dict[str, Any]] = []
    for packet in packets:
        manifest, prompt_text = packet_manifest(source_path, source_sha256, document, packet)
        section_id = str(packet["execution_section_id"])
        packet_id = str(packet["packet_id"])
        packet_root = output_root / "sections" / section_id / packet_id
        manifest_path = packet_root / "manifest.yaml"
        prompt_path = packet_root / "prompt.txt"
        manifest_yaml = yaml.safe_dump(manifest, allow_unicode=True, sort_keys=False)
        manifest_sha256 = hashlib.sha256(manifest_yaml.encode("utf-8")).hexdigest()
        if not args.dry_run:
            packet_root.mkdir(parents=True, exist_ok=True)
            manifest_path.write_text(manifest_yaml, encoding="utf-8")
            prompt_path.write_bytes(prompt_text.encode("utf-8"))
        rows.append(
            {
                "packet_id": packet_id,
                "section_id": section_id,
                "core_cut_id": packet["core_cut_id"],
                "branch_cut_id": packet["branch_cut_id"],
                "manifest_path": repo_relative(manifest_path),
                "manifest_sha256": manifest_sha256,
                "prompt_path": repo_relative(prompt_path),
                "prompt_sha256": hashlib.sha256(prompt_text.encode("utf-8")).hexdigest(),
                "expected_output_path": packet["export_contract"]["expected_output_path"],
            }
        )

    index = {
        "schema_version": EXPORT_INDEX_VERSION,
        "content_id": document["content_id"],
        "source_02b": {
            "path": repo_relative(source_path),
            "sha256": source_sha256,
            "schema_version": ACTIVE_02B_VERSION,
        },
        "status": "local_export_only",
        "requests": rows,
        "execution_boundary": {
            "paid_generation_approved": False,
            "external_execution_approved": False,
            "one_packet_one_request_required": True,
        },
    }
    index_path = output_root / "export-index.yaml"
    if not args.dry_run:
        write_yaml(index_path, index)

    print(
        json.dumps(
            {
                "exported": not args.dry_run,
                "index": repo_relative(index_path),
                "packet_count": len(rows),
                "source_02b_sha256": source_sha256,
                "paid_generation_approved": False,
            },
            ensure_ascii=False,
        )
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ExportError as error:
        raise SystemExit(f"02B export failed: {error}") from error
