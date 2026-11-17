#!/usr/bin/env python3
"""Validate run-owned publishing-plan.md through a structured extract."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

try:
    import jsonschema
except ImportError as exc:  # pragma: no cover - environment guard
    raise SystemExit(
        "Missing dependency: jsonschema. Run with scripts/idol-video-python."
    ) from exc


ROOT = Path.cwd()
DEFAULT_SCHEMA = Path("schemas/publishing-plan.schema.json")
DEFAULT_RECORD_SCHEMA = Path("schemas/publishing-record.schema.json")
META_RE = re.compile(r"^(content_id|public_group_name|public_fan_name|status|created_at_kst|updated_at_kst):\s*(.+?)\s*$")
HEADING_RE = re.compile(r"^##\s+(.+?)\s*$")
CLOSED_STATUS_MARKERS = ("closed", "final_complete", "archived")


def clean_cell(value: str) -> str:
    text = value.strip()
    if text.startswith("`") and text.endswith("`") and len(text) >= 2:
        text = text[1:-1]
    text = text.replace("\\n", "\n")
    return text.strip()


def split_table_row(line: str) -> list[str]:
    stripped = line.strip()
    if not stripped.startswith("|") or not stripped.endswith("|"):
        return []
    return [clean_cell(part) for part in stripped.strip("|").split("|")]


def is_separator_row(cells: list[str]) -> bool:
    return bool(cells) and all(re.fullmatch(r":?-{2,}:?", cell.strip()) for cell in cells)


def slug_heading(value: str) -> str:
    return re.sub(r"\s+", " ", value.strip())


def section_ranges(lines: list[str]) -> dict[str, tuple[int, int]]:
    headings: list[tuple[str, int]] = []
    for idx, line in enumerate(lines):
        match = HEADING_RE.match(line)
        if match:
            headings.append((slug_heading(match.group(1)), idx))

    ranges: dict[str, tuple[int, int]] = {}
    for pos, (name, start) in enumerate(headings):
        end = headings[pos + 1][1] if pos + 1 < len(headings) else len(lines)
        ranges[name] = (start + 1, end)
    return ranges


def parse_metadata(lines: list[str]) -> dict[str, str]:
    metadata: dict[str, str] = {}
    for line in lines:
        if line.startswith("## "):
            break
        match = META_RE.match(line)
        if match:
            metadata[match.group(1)] = clean_cell(match.group(2))
    return metadata


def parse_table(lines: list[str], section_name: str) -> tuple[list[str], list[list[str]]]:
    ranges = section_ranges(lines)
    if section_name not in ranges:
        return [], []

    start, end = ranges[section_name]
    header: list[str] = []
    rows: list[list[str]] = []
    for line in lines[start:end]:
        cells = split_table_row(line)
        if not cells:
            continue
        if not header:
            header = cells
            continue
        if is_separator_row(cells):
            continue
        rows.append(cells)
    return header, rows


def normalize_platform(raw: str) -> str:
    value = raw.strip().lower()
    aliases = {
        "x": "x",
        "twitter": "x",
        "tiktok": "tiktok",
        "tt": "tiktok",
        "youtube": "youtube",
        "youtube shorts": "youtube_shorts",
        "youtube_shorts": "youtube_shorts",
        "ys": "youtube_shorts",
        "instagram reels": "instagram_reels",
        "instagram_reels": "instagram_reels",
        "reels": "instagram_reels"
    }
    return aliases.get(value, value.replace(" ", "_"))


def infer_platform_from_post_id(post_id: str, fallback: str) -> str:
    if fallback:
        return normalize_platform(fallback)
    if "-X-" in post_id:
        return "x"
    if "-TT-" in post_id:
        return "tiktok"
    if "-YS-" in post_id:
        return "youtube_shorts"
    if "-YT-" in post_id:
        return "youtube"
    return ""


def analysis_scope_for(platform: str) -> str:
    return "scheduler_whitelist" if platform == "x" else "date_based"


def parse_list_cell(raw: str) -> list[str]:
    value = raw.strip()
    if not value:
        return []
    if value.startswith("[") and value.endswith("]"):
        value = value[1:-1].strip()
    return [item.strip().strip("'\"") for item in value.split(",") if item.strip()]


def parse_draft_queue(lines: list[str]) -> list[dict[str, Any]]:
    header, rows = parse_table(lines, "Draft Queue")
    if not header:
        return []

    normalized_header = [cell.lower().replace(" ", "_") for cell in header]
    posts: list[dict[str, Any]] = []

    for row in rows:
        values = dict(zip(normalized_header, row))
        post_id = values.get("post_id", "")
        platform = infer_platform_from_post_id(post_id, values.get("platform", ""))
        clip = values.get("clip", "") or values.get("asset_or_clip", "")
        caption = (
            values.get("caption_/_title", "")
            or values.get("caption_or_description", "")
            or values.get("caption", "")
            or values.get("title", "")
        )
        slot = values.get("draft_slot_kst", "") or values.get("slot", "") or values.get("scheduled_at", "")
        post: dict[str, Any] = {
            "post_id": post_id,
            "platform": platform,
            "template_type": values.get("template_type", "") or "clip",
            "asset_or_clip": clip,
            "caption": caption,
            "slot": slot,
            "analysis_scope": values.get("analysis_scope", "") or analysis_scope_for(platform),
            "message": values.get("message", "") or values.get("message_line", "") or clip,
        }
        for field in (
            "content_lane",
            "media_kind",
            "api_upload_quality_profile",
            "api_upload_quality_receipt",
            "shared_media_source_post_id",
            "reply_to_post_id",
            "thread_role",
            "member_intro_line",
            "content_pillar",
            "primary_channel_job",
            "format_family",
            "duration_band",
            "hook_type",
            "first_frame_type",
            "payoff_timestamp",
            "edit_density",
        ):
            value = values.get(field, "").strip()
            if value:
                post[field] = value
        member = parse_list_cell(values.get("member", ""))
        if member:
            post["member"] = member
        intensity = values.get("harness_intensity", "").strip()
        if intensity:
            try:
                post["harness_intensity"] = int(intensity)
            except ValueError:
                post["harness_intensity"] = intensity
        posts.append(post)

    return posts


def parse_selected_short_clips(lines: list[str]) -> list[dict[str, Any]]:
    header, rows = parse_table(lines, "Selected Short Clips")
    if not header:
        return []

    normalized_header = [cell.lower().replace(" ", "_") for cell in header]
    clips: list[dict[str, Any]] = []
    for row in rows:
        values = dict(zip(normalized_header, row))
        clips.append(
            {
                "clip_id": values.get("clip_id", ""),
                "exported_file": values.get("exported_file", ""),
                "source_raw": values.get("source_raw", ""),
                "why_selected": values.get("why_selected", "")
            }
        )
    return clips


def normalized_table_values(header: list[str], row: list[str]) -> dict[str, str]:
    keys = [
        re.sub(r"[^0-9a-z]+", "_", cell.strip().lower()).strip("_")
        for cell in header
    ]
    return dict(zip(keys, row))


def parse_selected_master(lines: list[str]) -> list[dict[str, Any]]:
    header, rows = parse_table(lines, "Selected Master")
    return [
        {
            "clip_id": values.get("clip_id", ""),
            "public_pointer": values.get("public_pointer", ""),
            "why_selected": values.get("why_selected", ""),
        }
        for row in rows
        if (values := normalized_table_values(header, row))
    ]


def parse_platform_completion(lines: list[str]) -> list[dict[str, Any]]:
    header, rows = parse_table(lines, "Platform Completion")
    return [
        {
            "platform": normalize_platform(values.get("platform", "")),
            "status": values.get("status", ""),
            "id_or_url": values.get("id_or_url", ""),
            "evidence": values.get("evidence", ""),
        }
        for row in rows
        if (values := normalized_table_values(header, row))
    ]


def parse_closed_upload_history(lines: list[str]) -> list[dict[str, Any]]:
    header, rows = parse_table(lines, "Closed Upload History")
    return [
        {
            "post_id": values.get("post_id", ""),
            "platform": normalize_platform(values.get("platform", "")),
            "record": values.get("record", ""),
            "status": values.get("status", ""),
        }
        for row in rows
        if (values := normalized_table_values(header, row))
    ]


def section_text(lines: list[str], section_name: str) -> str:
    ranges = section_ranges(lines)
    if section_name not in ranges:
        return ""
    start, end = ranges[section_name]
    return "\n".join(lines[start:end]).strip()


def closed_record_state(lines: list[str]) -> bool:
    metadata = parse_metadata(lines)
    status = str(metadata.get("status") or "").lower()
    headings = set(section_ranges(lines))
    return any(marker in status for marker in CLOSED_STATUS_MARKERS) or "Closed Upload History" in headings


def extract_contract(path: Path, mode: str = "active") -> dict[str, Any]:
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines()
    if mode == "active" and closed_record_state(lines):
        raise ValueError(
            "immutable closed or archived publishing record cannot be validated as an active plan"
        )
    metadata = parse_metadata(lines)
    headings = [slug_heading(match.group(1)) for line in lines if (match := HEADING_RE.match(line))]
    if mode == "closed":
        return {
            "record_kind": "immutable_closed",
            **metadata,
            "sections": headings,
            "selected_master": parse_selected_master(lines),
            "platform_completion": parse_platform_completion(lines),
            "closed_upload_history": parse_closed_upload_history(lines),
            "approval_text": section_text(lines, "Approval State"),
        }
    return {
        "record_kind": "active_plan",
        **metadata,
        "sections": headings,
        "selected_short_clips": parse_selected_short_clips(lines),
        "draft_queue": parse_draft_queue(lines),
        "approval_text": section_text(lines, "Approval State"),
    }


def detect_mode(path: Path) -> str:
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines()
    return "closed" if closed_record_state(lines) else "active"


def error_path(error: jsonschema.ValidationError) -> str:
    if not error.absolute_path:
        return "$"
    return "$." + ".".join(str(part) for part in error.absolute_path)


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate IDOL publishing-plan.md.")
    parser.add_argument("publishing_plan", type=Path)
    parser.add_argument("--schema", type=Path, default=DEFAULT_SCHEMA)
    parser.add_argument("--record-schema", type=Path, default=DEFAULT_RECORD_SCHEMA)
    parser.add_argument("--mode", choices=["auto", "active", "closed"], default="auto")
    parser.add_argument("--print-extract", action="store_true")
    args = parser.parse_args()

    plan_path = args.publishing_plan
    if not plan_path.is_absolute():
        plan_path = ROOT / plan_path
    if not plan_path.is_file():
        print(f"ERROR: publishing plan is not readable: {args.publishing_plan}", file=sys.stderr)
        return 1

    mode = detect_mode(plan_path) if args.mode == "auto" else args.mode
    schema_path = args.record_schema if mode == "closed" else args.schema
    if not schema_path.is_absolute():
        schema_path = ROOT / schema_path
    schema = json.loads(schema_path.read_text(encoding="utf-8"))
    try:
        contract = extract_contract(plan_path, mode=mode)
    except ValueError as exc:
        print(f"{args.publishing_plan}: invalid", file=sys.stderr)
        print(f"  - $: {exc}", file=sys.stderr)
        return 1

    if args.print_extract:
        print(json.dumps(contract, ensure_ascii=False, indent=2))

    validator_cls = jsonschema.validators.validator_for(schema)
    validator_cls.check_schema(schema)
    validator = validator_cls(schema, format_checker=jsonschema.FormatChecker())
    errors = sorted(validator.iter_errors(contract), key=lambda err: list(err.absolute_path))

    if errors:
        print(f"{args.publishing_plan}: invalid", file=sys.stderr)
        for error in errors:
            print(f"  - {error_path(error)}: {error.message}", file=sys.stderr)
        return 1

    print(
        f"OK: {args.publishing_plan} (mode={mode}, "
        f"{len(contract.get('draft_queue', []))} draft row(s), "
        f"{len(contract.get('selected_short_clips', []))} selected clip(s), "
        f"{len(contract.get('closed_upload_history', []))} closed upload row(s))"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
