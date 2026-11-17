#!/usr/bin/env python3
"""Refresh one registered source's canonical duration-aware review sheets locally."""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any

import yaml


ROOT = Path(__file__).resolve().parents[1]
QC_SCRIPT = ROOT / "scripts" / "idol_video_qc_sheet.py"
HUB_SCRIPT = ROOT / "scripts" / "idol_reference_hub.py"
SHORT_SOURCE_MAX_SECONDS = 60.0
SHORT_CADENCE = {
    "kind": "short_source",
    "preset": "one-second",
    "segment_seconds": 5,
    "directory": "segments-5s-1s",
    "stem_suffix": "5s-1s",
    "sampling_note": (
        "canonical 5-second source-time parts at 1-second sampling for a short source; "
        "selected detail is generated only after review"
    ),
}
FULL_CADENCE = {
    "kind": "full_or_long_source",
    "preset": "three-second",
    "segment_seconds": 15,
    "directory": "segments-15s",
    "stem_suffix": "15s",
    "sampling_note": (
        "canonical 15-second source-time parts at 3-second sampling for a full or long source; "
        "selected detail is generated only after review"
    ),
}


class SegmentRefreshError(RuntimeError):
    """Raised when a local source cannot be safely refreshed."""


def repo_file(raw: str, label: str) -> Path:
    path = Path(raw)
    if path.is_absolute():
        raise SegmentRefreshError(f"{label} must be repo-relative")
    candidate = ROOT / path
    if candidate.is_symlink() or not candidate.is_file():
        raise SegmentRefreshError(f"{label} must be an existing regular file: {raw}")
    try:
        candidate.resolve(strict=True).relative_to(ROOT.resolve())
    except ValueError as exc:
        raise SegmentRefreshError(f"{label} escapes the repository: {raw}") from exc
    return candidate


def repo_directory(raw: str, label: str) -> Path:
    path = Path(raw)
    if path.is_absolute():
        raise SegmentRefreshError(f"{label} must be repo-relative")
    candidate = ROOT / path
    if candidate.is_symlink() or not candidate.is_dir():
        raise SegmentRefreshError(f"{label} must be an existing regular directory: {raw}")
    try:
        candidate.resolve(strict=True).relative_to(ROOT.resolve())
    except ValueError as exc:
        raise SegmentRefreshError(f"{label} escapes the repository: {raw}") from exc
    return candidate


def relative(path: Path) -> str:
    try:
        return path.absolute().relative_to(ROOT.resolve()).as_posix()
    except ValueError as exc:
        raise SegmentRefreshError(f"path escapes the repository: {path}") from exc


def probe_duration(video: Path) -> float:
    candidates = [shutil.which("ffprobe"), "/opt/homebrew/bin/ffprobe"]
    for raw in candidates:
        if not raw:
            continue
        probe = Path(raw)
        if not probe.is_file():
            continue
        completed = subprocess.run(
            [
                str(probe),
                "-v",
                "error",
                "-show_entries",
                "format=duration",
                "-of",
                "default=noprint_wrappers=1:nokey=1",
                str(video),
            ],
            capture_output=True,
            check=False,
            text=True,
        )
        if completed.returncode == 0:
            try:
                duration = float(completed.stdout.strip())
            except ValueError:
                continue
            if duration > 0:
                return duration
    raise SegmentRefreshError(f"could not determine a positive duration for {relative(video)}")


def cadence_for_duration(duration: float) -> dict[str, str | int]:
    return SHORT_CADENCE if duration <= SHORT_SOURCE_MAX_SECONDS else FULL_CADENCE


def source_context(source_manifest_raw: str, video_raw: str | None) -> dict[str, Any]:
    manifest_path = repo_file(source_manifest_raw, "--source-manifest")
    document = yaml.safe_load(manifest_path.read_text(encoding="utf-8"))
    if not isinstance(document, dict) or document.get("artifact_type") != "source_manifest":
        raise SegmentRefreshError("--source-manifest must be an IDOL source_manifest")
    identity = document.get("identity")
    if not isinstance(identity, dict):
        raise SegmentRefreshError("source manifest identity is missing")
    platform_id = identity.get("platform_id")
    source_url = identity.get("normalized_url")
    source_root_raw = document.get("canonical_source_root")
    if not isinstance(platform_id, str) or not platform_id:
        raise SegmentRefreshError("source manifest platform_id is missing")
    if not isinstance(source_url, str) or not source_url:
        raise SegmentRefreshError("source manifest normalized_url is missing")
    if not isinstance(source_root_raw, str) or not source_root_raw.startswith(
        "source-materials/video-sources/"
    ):
        raise SegmentRefreshError("source manifest canonical_source_root is invalid")
    source_root = repo_directory(source_root_raw, "canonical_source_root")
    if source_root.resolve() != manifest_path.parent.resolve():
        raise SegmentRefreshError("source manifest is not stored at its canonical source root")

    candidates: list[Path] = []
    for media in document.get("media", []):
        if isinstance(media, dict) and media.get("kind") == "video":
            path = media.get("path")
            if isinstance(path, str):
                candidates.append(repo_file(path, "registered video"))
    if not candidates:
        raise SegmentRefreshError("source manifest has no registered local video")

    if video_raw is not None:
        requested = repo_file(video_raw, "--video")
        if requested.resolve() not in {item.resolve() for item in candidates}:
            raise SegmentRefreshError("--video must be one of the source manifest's registered videos")
        video = requested
    elif len(candidates) == 1:
        video = candidates[0]
    else:
        options = ", ".join(relative(item) for item in candidates)
        raise SegmentRefreshError(f"source has multiple registered videos; choose --video: {options}")

    approval = document.get("approval_basis")
    if not isinstance(approval, dict):
        raise SegmentRefreshError("source manifest approval_basis is missing")
    return {
        "manifest_path": manifest_path,
        "document": document,
        "source_root": source_root,
        "source_url": source_url,
        "platform_id": platform_id,
        "video": video,
        "approval": approval,
    }


def qc_command(
    context: dict[str, Any], duration: float
) -> tuple[list[str], Path, Path, dict[str, str | int]]:
    source_root = context["source_root"]
    platform_id = context["platform_id"]
    cadence = cadence_for_duration(duration)
    sheets_dir = source_root / "contact-sheets" / str(cadence["directory"])
    manifest = source_root / "analysis" / f"{platform_id}-{cadence['directory']}-manifest.json"
    output = sheets_dir / f"{platform_id}-{cadence['stem_suffix']}.png"
    command = [
        sys.executable,
        str(QC_SCRIPT),
        "--video",
        relative(context["video"]),
        "--out",
        relative(output.parent) + "/" + output.name,
        "--start",
        "0",
        "--duration",
        f"{duration:.6f}",
        "--preset",
        str(cadence["preset"]),
        "--segment-duration",
        str(cadence["segment_seconds"]),
        "--manifest",
        relative(manifest.parent) + "/" + manifest.name,
    ]
    return command, output, manifest, cadence


def ingest_command(
    context: dict[str, Any], manifest: Path, cadence: dict[str, str | int]
) -> list[str]:
    document = context["document"]
    generated = json.loads(manifest.read_text(encoding="utf-8"))
    sheets = generated.get("sheets")
    if not isinstance(sheets, list) or not sheets:
        raise SegmentRefreshError("generated QC manifest has no contact sheets")
    command = [
        sys.executable,
        str(HUB_SCRIPT),
        "ingest-local",
        "--url",
        context["source_url"],
        "--media",
        relative(context["video"]),
        "--contact-sheet-manifest",
        relative(manifest),
        "--replace-contact-sheets",
        "--sampling-note",
        str(cadence["sampling_note"]),
    ]
    for sheet in sheets:
        if not isinstance(sheet, dict) or not isinstance(sheet.get("path"), str):
            raise SegmentRefreshError("generated QC manifest has an invalid sheet path")
        command.extend(["--contact-sheet", sheet["path"]])
    title = document.get("title")
    if isinstance(title, str) and title.strip():
        command.extend(["--title", title])

    approval = context["approval"]
    if approval.get("mode") == "historical_existing_only":
        command.append("--historical-existing")
        basis = approval.get("basis")
        if isinstance(basis, str) and basis.strip():
            command.extend(["--approval-basis", basis])
    else:
        basis = approval.get("basis")
        approved_url = approval.get("approved_url")
        if not isinstance(basis, str) or not basis.strip() or not isinstance(approved_url, str) or not approved_url:
            raise SegmentRefreshError(
                "existing non-historical source lacks its approval binding; hold for repair instead of rewriting it"
            )
        command.extend(["--approval-basis", basis, "--approved-url", approved_url])
    return command


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(
        description="Regenerate one registered source with duration-aware canonical contact sheets"
    )
    value.add_argument("--source-manifest", required=True)
    value.add_argument("--video", help="required only when the source owns multiple registered videos")
    value.add_argument("--apply", action="store_true", help="write sheets and replace the active contact-sheet index")
    return value


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    try:
        context = source_context(args.source_manifest, args.video)
        duration = probe_duration(context["video"])
        qc, output, manifest, cadence = qc_command(context, duration)
        plan = {
            "source_manifest": relative(context["manifest_path"]),
            "video": relative(context["video"]),
            "duration_seconds": round(duration, 6),
            "cadence": cadence["kind"],
            "preset": cadence["preset"],
            "segment_duration_seconds": cadence["segment_seconds"],
            "output_pattern": relative(output.parent) + "/" + output.name,
            "manifest": relative(manifest),
            "apply_required": True,
        }
        if not args.apply:
            print(json.dumps({"decision": "dry_run", **plan}, ensure_ascii=False, indent=2))
            return 0
        subprocess.run(qc, cwd=ROOT, check=True)
        subprocess.run(ingest_command(context, manifest, cadence), cwd=ROOT, check=True)
        print(json.dumps({"decision": "refreshed", **plan}, ensure_ascii=False, indent=2))
        return 0
    except (OSError, SegmentRefreshError, subprocess.CalledProcessError, ValueError, yaml.YAMLError) as exc:
        print(json.dumps({"status": "hold", "error": str(exc)}, ensure_ascii=False, indent=2))
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
