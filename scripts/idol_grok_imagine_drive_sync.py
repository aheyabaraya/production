#!/usr/bin/env python3
"""Stage a founder-facing 02-03 Grok Imagine package into drive-sync.

The run-owned package remains the source of truth. This script creates the
Drive staging copy under:

drive-sync/02_GPT_GROK_HANDOFF/02-03_<TITLE_KEY>_grok-imagine/<CONTENT_ID>/<VERSION>/

It keeps cue folders self-contained for manual upload and hardlinks repeated
face-reference WebP files where the local filesystem supports hardlinks.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
from datetime import date
from pathlib import Path
from typing import Any

from idol_asset_drive_sync import sync_asset_context
import idol_title_output_registry as title_registry


HANDOFF_ROOT = Path("drive-sync/02_GPT_GROK_HANDOFF")


def json_dump(data: Any) -> str:
    return json.dumps(data, ensure_ascii=False, indent=2) + "\n"


def slug(value: str) -> str:
    return re.sub(r"[^0-9A-Za-z가-힣]+", "-", value).strip("-").lower()


def content_id_from_run(run: Path) -> str:
    return run.name


def package_sort_key(path: Path) -> tuple[int, float, str]:
    match = re.search(r"-v(\d+)-webp$", path.name)
    version = int(match.group(1)) if match else -1
    return (version, path.stat().st_mtime, path.name)


def detect_package(run: Path) -> Path:
    handoff = run / "handoff"
    candidates = sorted(handoff.glob("02-03-grok-imagine-*-webp"), key=package_sort_key)
    if not candidates:
        raise FileNotFoundError(f"no 02-03 Grok Imagine WebP package found under {handoff}")
    return candidates[-1]


def package_version(package: Path) -> str:
    prefix = "02-03-grok-imagine-"
    name = package.name
    if name.startswith(prefix):
        return name[len(prefix) :]
    return name


def copy_package(source: Path, destination: Path, *, write: bool) -> None:
    if not source.exists():
        raise FileNotFoundError(source)
    if not write:
        return
    if destination.exists():
        shutil.rmtree(destination)
    shutil.copytree(source, destination)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def hardlink_duplicate_face_refs(root: Path, *, write: bool) -> dict[str, Any]:
    groups: dict[str, list[Path]] = {}
    cues_root = root / "cues"
    for path in sorted(cues_root.rglob("*face-ref_*.webp")):
        if path.is_file():
            groups.setdefault(sha256_file(path), []).append(path)

    linked: list[dict[str, str]] = []
    for digest, paths in groups.items():
        if len(paths) < 2:
            continue
        master = paths[0]
        for path in paths[1:]:
            try:
                same_inode = (
                    master.stat().st_dev == path.stat().st_dev
                    and master.stat().st_ino == path.stat().st_ino
                )
            except FileNotFoundError:
                same_inode = False
            if same_inode:
                continue
            linked.append({"master": str(master), "linked": str(path), "sha256": digest})
            if write:
                tmp = path.with_suffix(path.suffix + ".tmp-link")
                if tmp.exists():
                    tmp.unlink()
                os.link(master, tmp)
                tmp.replace(path)

    report = {
        "package": str(root),
        "operation": "hardlink_duplicate_face_refs_after_drive_sync_stage",
        "linked_count": len(linked),
        "linked": linked,
    }
    if write:
        (root / "optimization-report.json").write_text(json_dump(report), encoding="utf-8")
    return report


def markdown_cells(line: str) -> list[str]:
    return [cell.strip() for cell in line.strip().strip("|").split("|")]


def markdown_row(cells: list[str]) -> str:
    return "| " + " | ".join(cell.replace("|", "/") for cell in cells) + " |\n"


def markdown_separator_cell(cell: str) -> bool:
    return bool(re.fullmatch(r":?-{3,}:?", cell.strip()))


def compact_text(value: str, limit: int = 260) -> str:
    text = " ".join(str(value).replace("\n", " ").split())
    text = text.strip().strip("'\"")
    text = text.replace("''", "'")
    if len(text) <= limit:
        return text
    cut = text.rfind(" ", 0, max(0, limit - 3))
    if cut < 80:
        cut = limit - 3
    return text[:cut].rstrip(" ,.;:") + "..."


def load_layout_slots(review_dir: Path) -> dict[str, dict[str, Any]]:
    slots: dict[str, dict[str, Any]] = {}
    for path in sorted(review_dir.glob("layout-v*.json")):
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError):
            continue
        for slot in data.get("slots", []):
            slot_id = str(slot.get("slot", "")).strip()
            if slot_id:
                slots[slot_id] = slot
    return slots


def collect_prompt_metadata(package: Path) -> dict[str, dict[str, str]]:
    metadata: dict[str, dict[str, str]] = {}
    prompt_names = {"00_prompt.md", "00_USE_THIS_PROMPT.md", "prompt.txt"}
    for path in sorted(p for p in package.rglob("*") if p.is_file() and p.name in prompt_names):
        try:
            text = path.read_text(encoding="utf-8")
        except OSError:
            continue
        slot_match = re.search(r"^Slot:\s*([A-Za-z0-9]+)", text, re.M)
        if not slot_match:
            slot_match = re.search(r"^#\s*([A-Za-z0-9]+)\s*/", text, re.M)
        if not slot_match:
            continue
        action_match = re.search(r"Action and camera:\s*\n\s*([^\n`#]+)", text)
        function_match = re.search(r"^Function:\s*(.+)$", text, re.M)
        source_match = re.search(r"^Source board:\s*(.+)$", text, re.M)
        world_match = re.search(r"^(Keep the same .+?)$", text, re.M)
        action = action_match.group(1).strip() if action_match else ""
        summary_parts = []
        if function_match:
            summary_parts.append(f"Function: {function_match.group(1).strip()}")
        if action:
            summary_parts.append(f"Action: {action}")
        if source_match:
            summary_parts.append(f"Source: {source_match.group(1).strip()}")
        if world_match:
            summary_parts.append(world_match.group(1).strip())
        slot_id = slot_match.group(1)
        metadata.setdefault(slot_id, {})
        if action:
            metadata[slot_id].setdefault("action_hint", compact_text(action, 220))
        if summary_parts:
            metadata[slot_id].setdefault("prompt_summary", compact_text("; ".join(summary_parts), 300))
    return metadata


def run_root_from_package(package: Path) -> Path | None:
    parts = package.resolve().parts
    if "runs" not in parts:
        return None
    index = parts.index("runs")
    if len(parts) < index + 3:
        return None
    return Path(*parts[: index + 3])


def split_yamlish_blocks(text: str, key: str) -> list[str]:
    pattern = re.compile(rf"(?m)^\s*-\s+{re.escape(key)}:\s*")
    matches = list(pattern.finditer(text))
    blocks: list[str] = []
    for index, match in enumerate(matches):
        end = matches[index + 1].start() if index + 1 < len(matches) else len(text)
        blocks.append(text[match.start() : end])
    return blocks


def extract_yamlish_value(block: str, key: str) -> str:
    lines = block.splitlines()
    for index, line in enumerate(lines):
        match = re.match(rf"^(\s*)(?:-\s+)?{re.escape(key)}:\s*(.*)$", line)
        if not match:
            continue
        indent = len(match.group(1))
        parts = [match.group(2).strip()]
        for following in lines[index + 1 :]:
            if not following.strip():
                continue
            next_indent = len(following) - len(following.lstrip())
            if re.match(r"^(?:-\s+)?[\w-]+:\s*", following.lstrip()):
                break
            if next_indent <= indent and following.lstrip().startswith("- "):
                break
            parts.append(following.strip())
        return compact_text(" ".join(part for part in parts if part), 900)
    return ""


def extract_yamlish_values(block: str, key: str) -> list[str]:
    values: list[str] = []
    lines = block.splitlines()
    for index, line in enumerate(lines):
        match = re.match(rf"^(\s*)(?:-\s+)?{re.escape(key)}:\s*(.*)$", line)
        if not match:
            continue
        indent = len(match.group(1))
        parts = [match.group(2).strip()]
        for following in lines[index + 1 :]:
            if not following.strip():
                continue
            next_indent = len(following) - len(following.lstrip())
            if re.match(r"^(?:-\s+)?[\w-]+:\s*", following.lstrip()):
                break
            if next_indent <= indent and following.lstrip().startswith("- "):
                break
            parts.append(following.strip())
        values.append(compact_text(" ".join(part for part in parts if part), 300))
    return values


def cue_bpm_map_sort_key(path: Path) -> tuple[int, float, str]:
    match = re.search(r"cue-bpm-map-v(\d+)\.ya?ml$", path.name)
    version = int(match.group(1)) if match else -1
    return (version, path.stat().st_mtime, path.name)


def latest_cue_bpm_map_path(run_root: Path | None) -> Path | None:
    if not run_root:
        return None
    research = run_root / "research"
    paths = sorted(research.glob("cue-bpm-map-v*.yaml"), key=cue_bpm_map_sort_key)
    if not paths:
        return None
    return paths[-1]


def validate_cue_bpm_map(run_root: Path | None) -> dict[str, Any] | None:
    path = latest_cue_bpm_map_path(run_root)
    if not path:
        return None
    result = subprocess.run(
        ["ruby", "scripts/validate_cue_bpm_map.rb", str(path)],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        details = "\n".join(part.strip() for part in (result.stdout, result.stderr) if part.strip())
        raise RuntimeError(f"cue BPM map validation failed for {path}:\n{details}")
    return {
        "path": str(path),
        "status": "validated",
        "stdout": result.stdout.strip(),
        "stderr": result.stderr.strip(),
    }


def load_cue_tempo_summaries(run_root: Path | None) -> dict[str, str]:
    path = latest_cue_bpm_map_path(run_root)
    if not path:
        return {}
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        return {}
    summaries: dict[str, str] = {}
    for block in split_yamlish_blocks(text, "slot"):
        slot_id = extract_yamlish_value(block, "slot")
        summary = extract_yamlish_value(block, "tempo_pulse_summary")
        if slot_id and summary:
            summaries[slot_id] = compact_text(summary, 190)
    return summaries


def load_cue_audio_summaries(run_root: Path | None) -> dict[str, str]:
    path = latest_cue_bpm_map_path(run_root)
    if not path:
        return {}
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        return {}
    summaries: dict[str, str] = {}
    for block in split_yamlish_blocks(text, "slot"):
        slot_id = extract_yamlish_value(block, "slot")
        summary = extract_yamlish_value(block, "audio_cue_summary")
        if slot_id and summary:
            summaries[slot_id] = compact_text(summary, 220)
    return summaries


def action_chain_from_text(value: str) -> str:
    text = compact_text(value, 500)
    for marker in (". Acting:", ". Director", ". Framing", ". Full-body", ". Beat"):
        if marker in text:
            text = text.split(marker, 1)[0]
    return compact_text(text, 260)


def packet_ids_for_layout_slot(slot: dict[str, Any]) -> list[str]:
    ids: list[str] = []
    for key in ("generated_packet_id", "packet_id"):
        value = str(slot.get(key, "")).strip()
        if value:
            ids.append(value)
    for key in ("image", "source"):
        value = str(slot.get(key, "")).strip()
        for match in re.findall(r"PKT_[A-Za-z0-9_]+", value):
            ids.append(match)
    source = str(slot.get("source", "")).strip()
    source_prefix = source.split()[0] if source else ""
    if source_prefix:
        ids.append(f"PKT_{source_prefix}")
        ids.append(source_prefix)
    seen: set[str] = set()
    ordered: list[str] = []
    for packet_id in ids:
        if packet_id not in seen:
            seen.add(packet_id)
            ordered.append(packet_id)
    return ordered


def packet_summary_from_block(block: str) -> dict[str, str]:
    visible_actions = extract_yamlish_values(block, "visible_body_action")
    action_chain = ""
    if visible_actions:
        action_chain = " -> ".join(
            f"CUT{index + 1:02d} {action}" for index, action in enumerate(visible_actions[:3])
        )
    if not action_chain:
        for key in ("performance_action", "action_carry_guard", "continuity_sentence"):
            value = extract_yamlish_value(block, key)
            if value:
                action_chain = action_chain_from_text(value)
                break

    prompt_parts = []
    for key in ("primary_visual_job", "message_basis", "choreography_basis", "mv_world_basis"):
        value = extract_yamlish_value(block, key)
        if value:
            prompt_parts.append(value)
    if not prompt_parts:
        for key in ("message_function", "song_function", "integrated_direction", "light_world"):
            value = extract_yamlish_value(block, key)
            if value:
                prompt_parts.append(value)
    if not prompt_parts:
        selection_reason = extract_yamlish_value(block, "selection_reason")
        if selection_reason:
            prompt_parts.append(selection_reason)

    return {
        "cut_summary": compact_text(action_chain, 280) if action_chain else "",
        "prompt_summary": compact_text("; ".join(prompt_parts), 330) if prompt_parts else "",
    }


def prompt_label_value(text: str, label: str) -> str:
    lines = text.splitlines()
    prefix = f"{label}:"
    for index, line in enumerate(lines):
        stripped = line.strip()
        if not stripped.startswith(prefix):
            continue
        parts = [stripped[len(prefix) :].strip()]
        for following in lines[index + 1 :]:
            following = following.strip()
            if not following or following.startswith("#"):
                break
            if re.match(r"^[A-Z][A-Za-z0-9 /+&()'-]{1,60}:\s+", following):
                break
            parts.append(following)
        return compact_text(" ".join(part for part in parts if part), 900)
    return ""


def prompt_label_value_any(text: str, labels: tuple[str, ...]) -> str:
    for label in labels:
        value = prompt_label_value(text, label)
        if value:
            return value
    return ""


def prompt_cut_summary_from_text(text: str) -> str:
    normalized = " ".join(text.split())
    parts: list[str] = []
    for cut in ("CUT01", "CUT02", "CUT03"):
        match = re.search(
            rf"\b{cut}:\s*(.*?)(?=\s*\bCUT0[1-3]:|\s*Camera:|\s*Wardrobe:|\s*Avoid:|$)",
            normalized,
        )
        if match:
            parts.append(f"{cut} {match.group(1).strip().rstrip('.')}")
    return compact_text(" -> ".join(parts), 320) if parts else ""


def prompt_packet_id_from_path(path: Path, text: str) -> str:
    heading_match = re.search(r"^#\s+(PKT_[A-Za-z0-9_]+)\b", text, re.M)
    if heading_match:
        return heading_match.group(1)
    name_match = re.search(r"(PKT_[A-Za-z0-9_]+)-prompt\.md$", path.name)
    return name_match.group(1) if name_match else ""


def export_prompt_summary_from_text(text: str) -> dict[str, str]:
    prompt_parts = []
    for labels, display in (
        (("Scene intent",), "Scene"),
        (("Visible details", "Visual evidence"), "Visual"),  # legacy fallback label
        (("Beat response",), "Beat"),
    ):
        value = prompt_label_value_any(text, labels)
        if value:
            prompt_parts.append(f"{display}: {value}")
    return {
        "cut_summary": prompt_cut_summary_from_text(text),
        "prompt_summary": compact_text("; ".join(prompt_parts), 380) if prompt_parts else "",
    }


def load_export_prompt_summaries(run_root: Path) -> dict[str, dict[str, str]]:
    summaries: dict[str, dict[str, str]] = {}
    exports_root = run_root / "exports" / "02B"
    if not exports_root.exists():
        return summaries
    for path in sorted(exports_root.glob("prompts-*/*-prompt.md")) + sorted(
        (exports_root / "prompts").glob("*-prompt.md")
    ):
        try:
            text = path.read_text(encoding="utf-8")
        except OSError:
            continue
        packet_id = prompt_packet_id_from_path(path, text)
        if not packet_id:
            continue
        summary = export_prompt_summary_from_text(text)
        if summary.get("cut_summary") or summary.get("prompt_summary"):
            summaries[packet_id] = summary
    return summaries


def merge_packet_summary(base: dict[str, str], incoming: dict[str, str]) -> dict[str, str]:
    merged = dict(base)
    for key in ("cut_summary", "prompt_summary"):
        if incoming.get(key) and not merged.get(key):
            merged[key] = incoming[key]
    return merged


def load_run_packet_summaries(package: Path) -> dict[str, dict[str, str]]:
    run_root = run_root_from_package(package)
    if not run_root:
        return {}
    summaries: dict[str, dict[str, str]] = {}
    packet_path = run_root / "02B-prompt-packets.yaml"
    if packet_path.exists():
        text = packet_path.read_text(encoding="utf-8")
        for block in split_yamlish_blocks(text, "packet_id"):
            packet_id = extract_yamlish_value(block, "packet_id")
            if not packet_id:
                continue
            summary = packet_summary_from_block(block)
            summaries[packet_id] = summary
            beat_id = extract_yamlish_value(block, "beat_id")
            if beat_id:
                summaries.setdefault(beat_id, summary)
                summaries.setdefault(f"PKT_{beat_id}", summary)
    storyboard_path = run_root / "02A-master-storyboard.yaml"
    if storyboard_path.exists():
        text = storyboard_path.read_text(encoding="utf-8")
        for block in split_yamlish_blocks(text, "beat_id"):
            beat_id = extract_yamlish_value(block, "beat_id")
            if not beat_id:
                continue
            summary = packet_summary_from_block(block)
            summaries.setdefault(beat_id, summary)
            summaries.setdefault(f"PKT_{beat_id}", summary)
    for packet_id, summary in load_export_prompt_summaries(run_root).items():
        summaries[packet_id] = merge_packet_summary(summaries.get(packet_id, {}), summary)
    return summaries


def action_hint_for_slot(
    slot_id: str,
    row: dict[str, str],
    layout_slots: dict[str, dict[str, Any]],
    prompt_metadata: dict[str, dict[str, str]],
) -> str:
    layout = layout_slots.get(slot_id, {})
    for key in (
        "action_hint",
        "visible_action",
        "visible_body_action",
        "body_action",
        "route_action",
        "performance_action",
    ):
        value = str(layout.get(key, "")).strip()
        if value:
            return value
    if prompt_metadata.get(slot_id, {}).get("action_hint"):
        return prompt_metadata[slot_id]["action_hint"]
    direction_value = str(layout.get("direction", "")).strip()
    if direction_value:
        return direction_value
    direction = row.get("Direction", "").strip()
    if direction:
        return direction
    member = row.get("Member", "").strip() or "The named member or unit"
    role = row.get("Role", "").strip()
    if role:
        return f"{member} carries the {role} moment with a clear visible body action."
    return f"{member} performs the cue with a clear visible body action."


def packet_summary_for_slot(
    slot_id: str,
    layout_slots: dict[str, dict[str, Any]],
    packet_summaries: dict[str, dict[str, str]],
    key: str,
) -> str:
    layout = layout_slots.get(slot_id, {})
    for packet_id in packet_ids_for_layout_slot(layout):
        summary = packet_summaries.get(packet_id, {})
        if summary.get(key):
            return summary[key]
    return ""


def cut_summary_for_slot(
    slot_id: str,
    row: dict[str, str],
    layout_slots: dict[str, dict[str, Any]],
    packet_summaries: dict[str, dict[str, str]],
    prompt_metadata: dict[str, dict[str, str]],
) -> str:
    packet_summary = packet_summary_for_slot(slot_id, layout_slots, packet_summaries, "cut_summary")
    if packet_summary:
        return packet_summary
    action_hint = row.get("Action Hint", "").strip() or action_hint_for_slot(
        slot_id, row, layout_slots, prompt_metadata
    )
    return compact_text(f"CUT01-CUT03 should carry this visible action chain: {action_hint}", 260)


def should_replace_cut_summary(current: str, slot_id: str, layout_slots: dict[str, dict[str, Any]], packet_summaries: dict[str, dict[str, str]]) -> bool:
    if not current.strip():
        return True
    if not packet_summary_for_slot(slot_id, layout_slots, packet_summaries, "cut_summary"):
        return False
    return current.strip().startswith("CUT01-CUT03 should carry this visible action chain:")


def prompt_summary_for_slot(
    slot_id: str,
    row: dict[str, str],
    layout_slots: dict[str, dict[str, Any]],
    packet_summaries: dict[str, dict[str, str]],
    prompt_metadata: dict[str, dict[str, str]],
) -> str:
    packet_summary = packet_summary_for_slot(slot_id, layout_slots, packet_summaries, "prompt_summary")
    if packet_summary:
        return packet_summary
    prompt_summary = prompt_metadata.get(slot_id, {}).get("prompt_summary")
    if prompt_summary:
        return prompt_summary
    role = row.get("Role", "").strip()
    direction = row.get("Direction", "").strip()
    action_hint = row.get("Action Hint", "").strip()
    parts = [part for part in (f"Role: {role}" if role else "", action_hint, direction) if part]
    return compact_text("; ".join(parts), 300)


def should_replace_prompt_summary(current: str, slot_id: str, layout_slots: dict[str, dict[str, Any]], packet_summaries: dict[str, dict[str, str]]) -> bool:
    if not current.strip():
        return True
    if not packet_summary_for_slot(slot_id, layout_slots, packet_summaries, "prompt_summary"):
        return False
    current = current.strip()
    return current.startswith("Function:") or "Keep the same dark mirror stage world" in current


def normalize_cue_sheet_action_hints(
    cue_sheet: Path,
    *,
    layout_slots: dict[str, dict[str, Any]],
    packet_summaries: dict[str, dict[str, str]],
    prompt_metadata: dict[str, dict[str, str]],
    cue_tempo: dict[str, str],
    cue_audio: dict[str, str],
    write: bool,
) -> dict[str, Any]:
    try:
        lines = cue_sheet.read_text(encoding="utf-8").splitlines(keepends=True)
    except OSError:
        return {"path": str(cue_sheet), "changed": False, "error": "read_failed"}

    changed = False
    rows_touched = 0
    new_lines: list[str] = []
    i = 0
    while i < len(lines):
        line = lines[i]
        if not line.startswith("|"):
            new_lines.append(line)
            i += 1
            continue

        old_header = markdown_cells(line)
        if "Slot" not in old_header or "Direction" not in old_header:
            new_lines.append(line)
            i += 1
            continue

        action_columns = ["Action Hint", "Cut Summary", "Prompt Summary"]
        generated_columns = ["Tempo/Pulse", "Audio Cue"] + action_columns
        base_header = [cell for cell in old_header if cell not in generated_columns]
        header: list[str] = []
        tempo_inserted = False
        for cell in base_header:
            header.append(cell)
            if cell == "Time":
                header.append("Tempo/Pulse")
                header.append("Audio Cue")
                tempo_inserted = True
        if not tempo_inserted:
            direction_index = header.index("Direction")
            header = header[:direction_index] + ["Tempo/Pulse", "Audio Cue"] + header[direction_index:]
        direction_index = header.index("Direction")
        header = header[:direction_index] + action_columns + header[direction_index:]
        if header != old_header:
            changed = True
        new_lines.append(markdown_row(header))
        i += 1

        if i < len(lines) and lines[i].startswith("|"):
            separator = markdown_cells(lines[i])
            if separator and all(markdown_separator_cell(cell) for cell in separator):
                new_lines.append(markdown_row(["---"] * len(header)))
                i += 1

        while i < len(lines) and lines[i].startswith("|"):
            cells = markdown_cells(lines[i])
            if cells and all(markdown_separator_cell(cell) for cell in cells):
                new_lines.append(lines[i])
                i += 1
                continue

            while len(cells) < len(old_header):
                cells.append("")
            row = {old_header[index]: cells[index] for index in range(min(len(old_header), len(cells)))}
            slot_id = row.get("Slot", "").strip()
            if slot_id and cue_tempo.get(slot_id) and row.get("Tempo/Pulse", "").strip() != cue_tempo[slot_id]:
                row["Tempo/Pulse"] = cue_tempo[slot_id]
                rows_touched += 1
                changed = True
            if slot_id and cue_audio.get(slot_id) and row.get("Audio Cue", "").strip() != cue_audio[slot_id]:
                row["Audio Cue"] = cue_audio[slot_id]
                rows_touched += 1
                changed = True
            if not row.get("Action Hint", "").strip() and slot_id:
                row["Action Hint"] = action_hint_for_slot(slot_id, row, layout_slots, prompt_metadata)
                rows_touched += 1
                changed = True
            if slot_id and should_replace_cut_summary(
                row.get("Cut Summary", ""), slot_id, layout_slots, packet_summaries
            ):
                new_cut_summary = cut_summary_for_slot(
                    slot_id, row, layout_slots, packet_summaries, prompt_metadata
                )
                if new_cut_summary != row.get("Cut Summary", ""):
                    row["Cut Summary"] = new_cut_summary
                    rows_touched += 1
                    changed = True
            if slot_id and should_replace_prompt_summary(
                row.get("Prompt Summary", ""), slot_id, layout_slots, packet_summaries
            ):
                new_prompt_summary = prompt_summary_for_slot(
                    slot_id, row, layout_slots, packet_summaries, prompt_metadata
                )
                if new_prompt_summary != row.get("Prompt Summary", ""):
                    row["Prompt Summary"] = new_prompt_summary
                    rows_touched += 1
                    changed = True
            new_lines.append(markdown_row([row.get(column, "") for column in header]))
            i += 1
        continue

    if changed and write:
        cue_sheet.write_text("".join(new_lines), encoding="utf-8")
    return {
        "path": str(cue_sheet),
        "changed": changed,
        "rows_touched": rows_touched,
    }


def ensure_package_cue_sheet_action_hints(
    package: Path,
    *,
    write: bool,
    run_root: Path | None = None,
) -> dict[str, Any]:
    cue_sheets = sorted(package.glob("*/cue-sheet-v*.md"))
    cue_sheets += sorted(package.glob("*/*/cue-sheet-v*.md"))
    cue_sheets = sorted(set(cue_sheets))
    prompt_metadata = collect_prompt_metadata(package)
    packet_summaries = load_run_packet_summaries(package)
    resolved_run_root = run_root or run_root_from_package(package)
    cue_bpm_validation = validate_cue_bpm_map(resolved_run_root)
    cue_tempo = load_cue_tempo_summaries(resolved_run_root)
    cue_audio = load_cue_audio_summaries(resolved_run_root)
    reports = []
    for cue_sheet in cue_sheets:
        reports.append(
            normalize_cue_sheet_action_hints(
                cue_sheet,
                layout_slots=load_layout_slots(cue_sheet.parent),
                packet_summaries=packet_summaries,
                prompt_metadata=prompt_metadata,
                cue_tempo=cue_tempo,
                cue_audio=cue_audio,
                write=write,
            )
        )
    return {
        "package": str(package),
        "write": write,
        "cue_sheet_count": len(cue_sheets),
        "changed_count": sum(1 for report in reports if report.get("changed")),
        "rows_touched": sum(int(report.get("rows_touched", 0)) for report in reports),
        "cue_bpm_validation": cue_bpm_validation,
        "cue_sheets": reports,
    }


def cue_count(package: Path) -> int:
    cues = package / "cues"
    if not cues.exists():
        return 0
    return sum(1 for path in cues.iterdir() if path.is_dir())


def write_parent_readme(parent: Path, content_id: str, title_key: str, version: str, pass_date: str, *, write: bool) -> Path:
    path = parent / "README.md"
    text = f"""# {content_id} Grok Imagine Handoff

Flow: `02-03`
Title key: `{title_key}`
Pass / handoff date: `{pass_date}`

Active package:

`{version}/`

Use this Drive staging copy for manual Grok Imagine work. The canonical source
package remains in the run folder.

## Start Here

1. Open `{version}/00-review/cue-board-v12.webp`.
2. Check `{version}/00-review/cue-sheet-v12.md` for the cue's `Tempo/Pulse`,
   `Audio Cue`, `Action Hint`, `Cut Summary`, and `Prompt Summary`.
3. Pick a cue.
4. Open that cue folder under `{version}/cues/`.
5. Upload files in numeric order.
6. Paste `00_prompt.md`.

## Notes

- All images in this staging package are WebP.
- Face refs are included inside each cue folder for convenience.
- Repeated face refs are hardlinked locally where supported.
- Shared asset context is available at
  `drive-sync/02_GPT_GROK_HANDOFF/00_ASSET_CONTEXT/`.
"""
    if write:
        parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
    return path


def write_packet(
    content_id: str,
    title_key: str,
    pass_date: str,
    source_package: Path,
    destination_package: Path,
    version: str,
    *,
    write: bool,
) -> Path:
    packet_name = f"grok-imagine-02-03-{title_key}-{version}.md"
    path = HANDOFF_ROOT / packet_name
    rel_package = destination_package.relative_to(HANDOFF_ROOT)
    text = f"""# Handoff Packet

Status: ready for manual Grok Imagine transfer
Created: {pass_date} KST
Title key: {title_key}
Target: Founder / Grok Imagine
Owner: Codex

## Task

Use the {version} 02-03 Grok Imagine WebP cue kits to generate video/image
motion outputs cue by cue.

## Context

This packet belongs to:

`{content_id}`

The package is a convenience staging copy for Drive sync. The run-owned source
package remains under:

`{source_package}`

## Inputs

- Drive package:
  `{rel_package}/`
- Review cue board:
  `{rel_package}/00-review/cue-board-v12.webp`
- Review cue sheet:
  `{rel_package}/00-review/cue-sheet-v12.md`
- Cue index:
  `{rel_package}/README.md`
- Active asset context:
  `00_ASSET_CONTEXT/`

Each cue folder contains:

- `00_prompt.md`
- `01_review-board.webp`
- cue-specific `02_face-ref_*.webp` / `03_face-ref_*.webp` when needed
- `README.md`

## Output Needed

- Use one cue folder at a time.
- Use the review cue sheet's `Tempo/Pulse`, `Audio Cue`, `Action Hint`,
  `Cut Summary`, and `Prompt Summary` columns as the compact guide for cue
  timing/pulse, audio energy/onset/motion pressure, what the member or unit
  visibly does, how the three cuts should read, and what the original prompt
  was trying to carry.
- Read `00_ASSET_CONTEXT/registries/` and relevant `members/Mxx/` images when
  member identity, unit structure, or voice role affects the output.
- Upload `01_review-board.webp`.
- Upload the cue folder's face refs only if identity locking is needed.
- Paste `00_prompt.md`.
- Save generated outputs back under the run folder, grouped by cue.

## Source / Evidence Requirement

Not required; this is a manual production handoff.

## Do Not Do

- Do not use character boards as Grok Imagine identity inputs.
- Do not change canonical source files from Drive.
- Do not approve paid publishing or external uploads from this packet alone.
- Do not mix face refs from other cue folders unless the founder explicitly asks.

## Return Format

```yaml
cue_id:
grok_output_file:
status:
notes:
next_action:
```
"""
    if write:
        HANDOFF_ROOT.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
    return path


def replace_active_package_block(readme: Path, active_package: str, packet_name: str, *, write: bool) -> None:
    if not readme.exists():
        return
    text = readme.read_text(encoding="utf-8")
    text = re.sub(
        r"Current active packet:\n\n```text\n.*?\n```",
        f"Current active packet:\n\n```text\n{packet_name}\n```",
        text,
        flags=re.S,
    )
    text = re.sub(
        r"(### (?:Active|Staged) 02-03 Grok Imagine Package\n\n```text\n).*?(\n```)",
        rf"\g<1>{active_package}\g<2>",
        text,
        flags=re.S,
    )
    if write:
        readme.write_text(text, encoding="utf-8")


def ensure_manifest_entry(manifest: Path, packet_name: str, package_path: str, *, write: bool) -> None:
    if not manifest.exists():
        return
    text = manifest.read_text(encoding="utf-8")
    packet_entry = f"- `{packet_name}`"
    package_entry = f"- `{package_path}`"
    if packet_entry not in text:
        request_heading = (
            "Founder-requested request packets only:"
            if "Founder-requested request packets only:" in text
            else "Active request packets:"
        )
        text = text.replace(
            f"{request_heading}\n\n",
            f"{request_heading}\n\n{packet_entry}\n",
            1,
        )
    package_heading = "Founder-requested staged asset handoff packages:"
    legacy_package_heading = "Active asset handoff packages:"
    if package_heading not in text and legacy_package_heading not in text:
        text = text.replace(
            "Templates and guidance:\n\n",
            f"{package_heading}\n\n\nTemplates and guidance:\n\n",
            1,
        )
    if package_entry not in text:
        heading = package_heading if package_heading in text else legacy_package_heading
        text = text.replace(
            f"{heading}\n\n",
            f"{heading}\n\n{package_entry}\n",
            1,
        )
    if write:
        manifest.write_text(text, encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--run", required=True, help="Run root, e.g. runs/ALBUM_KEY/TITLE_KEY/RUN_ID")
    parser.add_argument("--pass-date", default=date.today().isoformat())
    parser.add_argument("--album-key", default=title_registry.DEFAULT_ALBUM_KEY, help="Stable album key for catalog/albums.")
    parser.add_argument("--title-key", help="Stable title-song key for active handoff files. Defaults to CONTENT_ID slug.")
    parser.add_argument("--source-package", help="Run-owned package path. Defaults to latest 02-03-grok-imagine-*-webp.")
    parser.add_argument("--write", action="store_true")
    parser.add_argument(
        "--founder-requested",
        action="store_true",
        help="Confirm the founder explicitly requested this Grok/Drive handoff staging.",
    )
    args = parser.parse_args()
    if args.write and not args.founder_requested:
        parser.error("refusing to write Grok/Drive handoff without --founder-requested")

    run = Path(args.run)
    content_id = content_id_from_run(run)
    album_key = title_registry.album_key(args.album_key)
    title_key = title_registry.title_key(args.title_key, fallback=content_id)
    source_package = Path(args.source_package) if args.source_package else detect_package(run)
    version = package_version(source_package)
    destination_parent = HANDOFF_ROOT / f"02-03_{title_key}_grok-imagine" / content_id
    destination_package = destination_parent / version
    active_package = str(destination_package.relative_to(HANDOFF_ROOT)) + "/"

    source_cue_sheet_hints = ensure_package_cue_sheet_action_hints(source_package, write=args.write, run_root=run)
    copy_package(source_package, destination_package, write=args.write)
    destination_cue_sheet_hints = (
        ensure_package_cue_sheet_action_hints(destination_package, write=args.write, run_root=run)
        if args.write
        else None
    )
    optimization = hardlink_duplicate_face_refs(destination_package, write=args.write)
    asset_context = sync_asset_context(
        write=args.write,
        sync_date=args.pass_date,
        founder_requested=args.founder_requested,
    )
    parent_readme = write_parent_readme(destination_parent, content_id, title_key, version, args.pass_date, write=args.write)
    packet_path = write_packet(content_id, title_key, args.pass_date, source_package, destination_package, version, write=args.write)
    replace_active_package_block(HANDOFF_ROOT / "README.md", active_package, packet_path.name, write=args.write)
    ensure_manifest_entry(
        Path("drive-sync/MANIFEST.md"),
        packet_path.name,
        "02_GPT_GROK_HANDOFF/" + active_package,
        write=args.write,
    )
    registry_report = None
    if args.write:
        registry_report = title_registry.register_outputs(
            album=album_key,
            title=title_key,
            title_display_name=title_key,
            content_id=content_id,
            run_root=title_registry.rel(run),
            outputs=[
                {
                    "output_type": "drive_handoff_package",
                    "path": destination_parent,
                    "source_run_root": run,
                    "content_id": content_id,
                    "source_step": "drive_sync",
                    "status": "exported",
                    "notes": "02-03 Grok Imagine Drive staging parent",
                },
                {
                    "output_type": "drive_handoff_package",
                    "path": destination_package,
                    "source_run_root": run,
                    "content_id": content_id,
                    "source_step": "drive_sync",
                    "status": "exported",
                    "notes": "02-03 Grok Imagine Drive staging package",
                },
                {
                    "output_type": "drive_handoff_package",
                    "path": packet_path,
                    "source_run_root": run,
                    "content_id": content_id,
                    "source_step": "drive_sync",
                    "status": "exported",
                    "notes": "Grok Imagine handoff packet",
                },
            ],
            status="active",
            write=True,
        )

    result = {
        "write": args.write,
        "content_id": content_id,
        "album_key": album_key,
        "title_key": title_key,
        "title_output_registry_path": str(Path("catalog/albums") / album_key / title_key / "output-registry.yaml"),
        "pass_date": args.pass_date,
        "founder_requested": args.founder_requested,
        "source_package": str(source_package),
        "destination_package": str(destination_package),
        "cue_count": cue_count(destination_package if args.write else source_package),
        "source_cue_sheet_hints": source_cue_sheet_hints,
        "destination_cue_sheet_hints": destination_cue_sheet_hints,
        "optimization_linked_count": optimization["linked_count"],
        "asset_context": asset_context,
        "packet": str(packet_path),
        "parent_readme": str(parent_readme),
        "title_registry": registry_report,
    }
    print(json_dump(result), end="")


if __name__ == "__main__":
    main()
