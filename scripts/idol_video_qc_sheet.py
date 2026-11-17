#!/usr/bin/env python3
"""Create timestamp-focused QC contact sheets for IDOL video review."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import tempfile
from pathlib import Path

try:
    import cv2
    import numpy as np
except ModuleNotFoundError as exc:
    raise SystemExit(
        f"Missing Python dependency '{exc.name}'. "
        "Run this script through scripts/idol-video-python."
    ) from exc


VIDEO_QC_PRESETS = {
    "half-second": {"interval": 0.5, "columns": 8, "thumb_width": 220, "thumb_height": 124},
    "dense-qc": {"interval": 0.25, "columns": 8, "thumb_width": 220, "thumb_height": 124},
    "one-second": {"interval": 1.0, "columns": 6, "thumb_width": 280, "thumb_height": 158},
    "two-second": {"interval": 2.0, "columns": 5, "thumb_width": 280, "thumb_height": 158},
    "three-second": {"interval": 3.0, "columns": 5, "thumb_width": 280, "thumb_height": 158},
    "broad-source": {"interval": 6.0, "columns": 5, "thumb_width": 280, "thumb_height": 158},
    "source-preview": {"interval": 0.5, "columns": 2, "thumb_width": 320, "thumb_height": 180},
    "founder-review": {"interval": 0.5, "columns": 4, "thumb_width": 360, "thumb_height": 203},
    "detail": {"interval": 0.25, "columns": 3, "thumb_width": 480, "thumb_height": 270},
}


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def file_evidence(path: Path) -> dict[str, str | int]:
    return {
        "path": path.as_posix(),
        "sha256": sha256_file(path),
        "size_bytes": path.stat().st_size,
    }


def timestamp_label(source_timestamp: float, label_offset: float) -> str:
    return (
        f"src {source_timestamp:06.3f}s / "
        f"song {source_timestamp + label_offset:06.3f}s"
    )


def cell_records(
    part_index: int,
    times: list[float],
    label_offset: float,
    cell_crops: list[dict[str, str | int]] | None = None,
) -> list[dict[str, str | float | int | dict[str, str | int]]]:
    if cell_crops is not None and len(cell_crops) != len(times):
        raise ValueError("cell crop count must match contact-sheet cell count")
    cells = []
    for cell_index, source_timestamp in enumerate(times, start=1):
        label_timestamp = source_timestamp + label_offset
        cell = {
            "cell_id": f"sheet-{part_index:03d}-cell-{cell_index:04d}",
            "order": cell_index,
            "source_timestamp_seconds": source_timestamp,
            "label_timestamp_seconds": round(label_timestamp, 6),
            "label": timestamp_label(source_timestamp, label_offset),
        }
        if cell_crops is not None:
            cell["cell_crop"] = cell_crops[cell_index - 1]
        cells.append(cell)
    return cells


def parse_times(value: str) -> list[float]:
    times = []
    for item in value.split(","):
        item = item.strip()
        if item:
            times.append(float(item))
    return times


def interval_times(start: float, duration: float, interval: float) -> list[float]:
    count = int(math.floor(duration / interval)) + 1
    return [round(start + idx * interval, 6) for idx in range(count)]


def split_times_by_segment(times: list[float], anchor: float, segment_duration: float) -> list[tuple[float, float, list[float]]]:
    groups: dict[int, list[float]] = {}
    for time_seconds in times:
        segment_index = int(math.floor(max(0.0, time_seconds - anchor) / segment_duration))
        groups.setdefault(segment_index, []).append(time_seconds)

    segments = []
    for segment_index in sorted(groups):
        segment_start = anchor + segment_index * segment_duration
        segment_end = segment_start + segment_duration
        segments.append((segment_start, segment_end, groups[segment_index]))
    return segments


def time_token(seconds: float) -> str:
    return f"{int(round(seconds * 1000)):08d}ms"


def part_output_path(out: Path, part_index: int, segment_start: float, segment_end: float) -> Path:
    suffix = out.suffix or ".png"
    stem = out.stem if out.suffix else out.name
    name = (
        f"{stem}-part-{part_index:03d}-"
        f"{time_token(segment_start)}-{time_token(segment_end)}{suffix}"
    )
    return out.with_name(name)


def plan_sheet_jobs(
    out: Path,
    times: list[float],
    segment_duration: float | None,
    start: float,
    explicit_times: bool,
) -> list[tuple[int, Path, float, float, list[float]]]:
    if segment_duration:
        anchor = start if not explicit_times else min(times)
        return [
            (
                part_index,
                part_output_path(out, part_index, segment_start, segment_end),
                segment_start,
                segment_end,
                segment_times,
            )
            for part_index, (segment_start, segment_end, segment_times) in enumerate(
                split_times_by_segment(times, anchor, segment_duration),
                start=1,
            )
        ]
    return [(1, out, min(times), max(times), times)]


def planned_crop_paths(
    cell_crops_dir: Path,
    jobs: list[tuple[int, Path, float, float, list[float]]],
    label_offset: float,
    suffix: str,
) -> list[Path]:
    paths: list[Path] = []
    for part_index, _path, _segment_start, _segment_end, segment_times in jobs:
        for cell in cell_records(part_index, segment_times, label_offset):
            paths.append(cell_crops_dir / f"{cell['cell_id']}{suffix}")
    return paths


def canonical_leaf(path: Path) -> Path:
    path = Path(path)
    return path.parent.resolve() / path.name


def inode_identity(path: Path, *, follow_symlinks: bool) -> tuple[int, int] | None:
    try:
        stat_result = path.stat() if follow_symlinks else path.lstat()
    except OSError:
        return None
    return (stat_result.st_dev, stat_result.st_ino)


def reject_output_leaf_symlink(path: Path) -> None:
    if path.is_symlink():
        raise SystemExit(f"Refusing output leaf symlink: {path}")


def reject_path_collisions(video: Path, outputs: list[tuple[str, Path]]) -> None:
    resolved_owners: dict[Path, str] = {}
    inode_owners: dict[tuple[int, int], str] = {}

    def claim(role: str, path: Path, *, follow_symlinks: bool) -> None:
        keys = [canonical_leaf(path)]
        if follow_symlinks:
            try:
                resolved = path.resolve()
            except OSError:
                resolved = None
            else:
                if resolved not in keys:
                    keys.append(resolved)
        for key in keys:
            owner = resolved_owners.get(key)
            if owner is not None:
                raise SystemExit(
                    f"Refusing colliding paths ({owner} and {role}): {path}"
                )
            resolved_owners[key] = role
        inode = inode_identity(path, follow_symlinks=follow_symlinks)
        if inode is None:
            return
        owner = inode_owners.get(inode)
        if owner is not None:
            raise SystemExit(
                f"Refusing colliding paths ({owner} and {role}): {path}"
            )
        inode_owners[inode] = role

    claim("input video", video, follow_symlinks=True)
    for role, path in outputs:
        claim(role, path, follow_symlinks=False)


def complete_v1_reuse_hit(
    manifest_path: Path,
    video: Path,
    *,
    preset: str,
    interval: float,
    label_offset: float,
    segment_duration: float | None,
    columns: int,
    thumb_width: int,
    thumb_height: int,
    cell_crops_dir: Path | None,
    jobs: list[tuple[int, Path, float, float, list[float]]],
    crop_suffix: str,
) -> bool:
    if not manifest_path.is_file() or manifest_path.is_symlink():
        return False
    try:
        payload = json.loads(manifest_path.read_text(encoding="utf-8"))
        current_source = file_evidence(video)
    except (OSError, json.JSONDecodeError, TypeError, ValueError):
        return False
    if not isinstance(payload, dict):
        return False
    if payload.get("schema_version") != "idol_video_qc_sheet_manifest.v1":
        return False
    if payload.get("generator_source_sha256") != sha256_file(Path(__file__)):
        return False
    if payload.get("video") != video.as_posix():
        return False
    source = payload.get("source_video")
    if not isinstance(source, dict):
        return False
    if any(key not in source for key in ("path", "sha256", "size_bytes")):
        return False
    if source.get("path") != video.as_posix():
        return False
    if (
        source.get("sha256") != current_source["sha256"]
        or source.get("size_bytes") != current_source["size_bytes"]
    ):
        return False
    if payload.get("preset") != preset:
        return False
    if payload.get("interval_seconds") != interval:
        return False
    if payload.get("label_offset_seconds") != label_offset:
        return False
    if payload.get("segment_duration_seconds") != segment_duration:
        return False
    if any(type(payload.get(key)) is not int for key in ("columns", "thumb_width", "thumb_height", "sheet_count")):
        return False
    if payload.get("columns") != columns:
        return False
    if payload.get("thumb_width") != thumb_width:
        return False
    if payload.get("thumb_height") != thumb_height:
        return False
    sheets = payload.get("sheets")
    if (
        not isinstance(sheets, list)
        or payload.get("sheet_count") != len(sheets)
        or len(sheets) != len(jobs)
    ):
        return False
    if cell_crops_dir is not None:
        crops = payload.get("cell_crops")
        if not isinstance(crops, dict):
            return False
        if crops.get("output_dir") != cell_crops_dir.as_posix():
            return False
        if crops.get("kind") != "timestamp_labelled_contact_sheet_cell":
            return False
        if crops.get("cell_count") != sum(len(job[4]) for job in jobs):
            return False
    elif "cell_crops" in payload:
        return False

    required_sheet_keys = (
        "part_index",
        "path",
        "sha256",
        "size_bytes",
        "timestamps",
        "timestamp_count",
        "cells",
        "source_time_range",
    )
    for (part_index, part_path, segment_start, segment_end, segment_times), sheet in zip(
        jobs, sheets, strict=True
    ):
        if not isinstance(sheet, dict):
            return False
        if any(key not in sheet for key in required_sheet_keys):
            return False
        if type(sheet["part_index"]) is not int or type(sheet["timestamp_count"]) is not int:
            return False
        if sheet["part_index"] != part_index:
            return False
        if not isinstance(sheet["path"], str) or canonical_leaf(Path(sheet["path"])) != canonical_leaf(part_path):
            return False
        if sheet["timestamps"] != segment_times:
            return False
        if sheet["timestamp_count"] != len(segment_times):
            return False
        if sheet["source_time_range"] != f"{segment_start:.3f}-{segment_end:.3f}":
            return False
        if part_path.is_symlink() or not part_path.is_file():
            return False
        try:
            evidence = file_evidence(part_path)
        except OSError:
            return False
        if evidence["sha256"] != sheet["sha256"] or evidence["size_bytes"] != sheet["size_bytes"]:
            return False
        cells = sheet.get("cells")
        if not isinstance(cells, list) or len(cells) != len(segment_times):
            return False
        expected_cells = cell_records(part_index, segment_times, label_offset)
        for expected, cell in zip(expected_cells, cells, strict=True):
            if not isinstance(cell, dict):
                return False
            if cell.get("cell_id") != expected["cell_id"]:
                return False
            if type(cell.get("order")) is not int or cell.get("order") != expected["order"]:
                return False
            if cell.get("source_timestamp_seconds") != expected["source_timestamp_seconds"]:
                return False
            if cell.get("label_timestamp_seconds") != expected["label_timestamp_seconds"]:
                return False
            if cell.get("label") != expected["label"]:
                return False
            if cell_crops_dir is None:
                if "cell_crop" in cell:
                    return False
                continue
            crop = cell.get("cell_crop")
            if not isinstance(crop, dict):
                return False
            if any(key not in crop for key in ("path", "sha256", "size_bytes")):
                return False
            planned_crop = cell_crops_dir / f"{expected['cell_id']}{crop_suffix}"
            if not isinstance(crop["path"], str):
                return False
            crop_path = Path(crop["path"])
            if canonical_leaf(crop_path) != canonical_leaf(planned_crop):
                return False
            if crop_path.is_symlink() or not crop_path.is_file():
                return False
            try:
                crop_evidence = file_evidence(crop_path)
            except OSError:
                return False
            if (
                crop_evidence["sha256"] != crop["sha256"]
                or crop_evidence["size_bytes"] != crop["size_bytes"]
            ):
                return False
    return True


def fit_frame(frame, width: int, height: int):
    src_h, src_w = frame.shape[:2]
    scale = min(width / src_w, height / src_h)
    new_w = max(1, int(round(src_w * scale)))
    new_h = max(1, int(round(src_h * scale)))
    resized = cv2.resize(frame, (new_w, new_h), interpolation=cv2.INTER_AREA)
    canvas = np.zeros((height, width, 3), dtype=np.uint8)
    x = (width - new_w) // 2
    y = (height - new_h) // 2
    canvas[y : y + new_h, x : x + new_w] = resized
    return canvas


def frame_at(cap, time_seconds: float):
    cap.set(cv2.CAP_PROP_POS_MSEC, max(0.0, time_seconds) * 1000.0)
    ok, frame = cap.read()
    if ok:
        return frame
    frame_count = cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0
    fps = cap.get(cv2.CAP_PROP_FPS) or 24.0
    if frame_count > 0:
        fallback = max(0, frame_count - 1)
        cap.set(cv2.CAP_PROP_POS_FRAMES, fallback)
        ok, frame = cap.read()
        if ok:
            return frame
    raise RuntimeError(f"Could not read frame at {time_seconds:.3f}s")


def draw_label(image, label: str):
    overlay = image.copy()
    cv2.rectangle(overlay, (0, 0), (image.shape[1], 25), (0, 0, 0), -1)
    cv2.addWeighted(overlay, 0.7, image, 0.3, 0, image)
    cv2.putText(
        image,
        label,
        (6, 18),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.48,
        (255, 255, 255),
        1,
        cv2.LINE_AA,
    )


def make_sheet(
    video: Path,
    out: Path,
    times: list[float],
    label_offset: float,
    columns: int,
    thumb_width: int,
    thumb_height: int,
    cell_crops_dir: Path | None = None,
    cell_ids: list[str] | None = None,
) -> list[dict[str, str | int]]:
    if cell_crops_dir is not None and (
        cell_ids is None or len(cell_ids) != len(times)
    ):
        raise ValueError("cell crop ids must exactly cover contact-sheet timestamps")
    if cell_crops_dir is None and cell_ids is not None:
        raise ValueError("cell crop ids require a cell crop output directory")

    if out.is_symlink():
        raise SystemExit(f"Refusing output leaf symlink: {out}")

    planned_crops: list[Path] = []
    if cell_crops_dir is not None and cell_ids is not None:
        suffix = out.suffix or ".png"
        for cell_id in cell_ids:
            if not isinstance(cell_id, str) or not cell_id or any(c in cell_id for c in ("/", "\\")) or cell_id in (".", ".."):
                raise ValueError("cell crop id must be a single filename component")
            crop_path = cell_crops_dir / f"{cell_id}{suffix}"
            if crop_path.is_symlink() or crop_path.exists():
                raise RuntimeError(
                    "Refusing to overwrite existing contact-sheet cell crop: "
                    f"{crop_path}"
                )
            planned_crops.append(crop_path)

    reject_path_collisions(video, [("sheet", out)] + [("crop", p) for p in planned_crops])
    cap = cv2.VideoCapture(str(video))
    try:
        if not cap.isOpened():
            raise SystemExit(f"Could not open video: {video}")

        thumbs = []
        for time_seconds in times:
            frame = frame_at(cap, time_seconds)
            thumb = fit_frame(frame, thumb_width, thumb_height)
            draw_label(thumb, timestamp_label(time_seconds, label_offset))
            thumbs.append(thumb)
    finally:
        cap.release()

    rows = int(math.ceil(len(thumbs) / columns))
    sheet = np.zeros((rows * thumb_height, columns * thumb_width, 3), dtype=np.uint8)
    for idx, thumb in enumerate(thumbs):
        row = idx // columns
        col = idx % columns
        y = row * thumb_height
        x = col * thumb_width
        sheet[y : y + thumb_height, x : x + thumb_width] = thumb

    out.parent.mkdir(parents=True, exist_ok=True)
    if not cv2.imwrite(str(out), sheet) or not out.is_file():
        raise RuntimeError(f"Could not write contact sheet: {out}")

    crop_records: list[dict[str, str | int]] = []
    if planned_crops:
        for crop_path, thumb in zip(planned_crops, thumbs, strict=True):
            crop_path.parent.mkdir(parents=True, exist_ok=True)
            if not cv2.imwrite(str(crop_path), thumb) or not crop_path.is_file():
                raise RuntimeError(f"Could not write contact-sheet cell crop: {crop_path}")
            crop_records.append(file_evidence(crop_path))
    return crop_records


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--video", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--times", help="Comma-separated timestamps relative to the input video.")
    parser.add_argument("--start", type=float, default=0.0)
    parser.add_argument("--duration", type=float)
    parser.add_argument("--preset", choices=sorted(VIDEO_QC_PRESETS), default="half-second")
    parser.add_argument("--interval", type=float)
    parser.add_argument("--label-offset", type=float, default=0.0)
    parser.add_argument("--columns", type=int)
    parser.add_argument("--thumb-width", type=int)
    parser.add_argument("--thumb-height", type=int)
    parser.add_argument(
        "--segment-duration",
        type=float,
        help="Split output into part sheets by source-time seconds, such as 30 or 60.",
    )
    parser.add_argument(
        "--manifest",
        type=Path,
        help="Optional JSON manifest path for split sheet outputs.",
    )
    parser.add_argument(
        "--cell-crops-dir",
        type=Path,
        help=(
            "Optional output directory for one timestamp-labelled crop per "
            "contact-sheet cell; each crop is hash-bound in the manifest."
        ),
    )
    args = parser.parse_args()

    preset = VIDEO_QC_PRESETS[args.preset]
    interval = args.interval if args.interval is not None else preset["interval"]
    columns = args.columns if args.columns is not None else preset["columns"]
    thumb_width = args.thumb_width if args.thumb_width is not None else preset["thumb_width"]
    thumb_height = args.thumb_height if args.thumb_height is not None else preset["thumb_height"]

    if not all(math.isfinite(value) for value in (args.start, interval, args.label_offset)) or interval <= 0:
        parser.error("start, interval and label offset must be finite; interval must be positive")
    if min(columns, thumb_width, thumb_height) <= 0:
        parser.error("columns and thumbnail dimensions must be positive")
    if args.duration is not None and (not math.isfinite(args.duration) or args.duration < 0):
        parser.error("duration must be finite and nonnegative")
    if args.segment_duration is not None and (not math.isfinite(args.segment_duration) or args.segment_duration <= 0):
        parser.error("segment duration must be finite and positive")
    if args.times:
        times = parse_times(args.times)
    else:
        if args.duration is None:
            parser.error("provide --times or --duration")
        times = interval_times(args.start, args.duration, interval)
    if not times or not all(math.isfinite(value) and value >= 0 for value in times):
        parser.error("finite nonnegative timestamps are required")
    if not args.video.is_file():
        parser.error("input video must be an existing regular file")

    if args.cell_crops_dir is not None and args.manifest is None:
        parser.error("--cell-crops-dir requires --manifest")
    if args.segment_duration:
        if args.segment_duration <= 0:
            parser.error("--segment-duration must be positive")

    jobs = plan_sheet_jobs(
        out=args.out,
        times=times,
        segment_duration=args.segment_duration,
        start=args.start,
        explicit_times=bool(args.times),
    )
    suffix = args.out.suffix or ".png"
    crop_paths = (
        planned_crop_paths(args.cell_crops_dir, jobs, args.label_offset, suffix)
        if args.cell_crops_dir is not None
        else []
    )
    named_outputs: list[tuple[str, Path]] = [
        (f"sheet-{part_index:03d}", path) for part_index, path, *_ in jobs
    ]
    named_outputs.extend(
        (f"cell-crop-{index:04d}", path)
        for index, path in enumerate(crop_paths, start=1)
    )
    if args.manifest is not None:
        named_outputs.append(("manifest", args.manifest))
    for _, output_path in named_outputs:
        reject_output_leaf_symlink(output_path)
    reject_path_collisions(args.video, named_outputs)
    if args.manifest is not None and complete_v1_reuse_hit(
        args.manifest,
        args.video,
        preset=args.preset,
        interval=interval,
        label_offset=args.label_offset,
        segment_duration=args.segment_duration,
        columns=columns,
        thumb_width=thumb_width,
        thumb_height=thumb_height,
        cell_crops_dir=args.cell_crops_dir,
        jobs=jobs,
        crop_suffix=suffix,
    ):
        return

    if args.manifest is not None and args.manifest.exists():
        raise SystemExit("Existing QC manifest cannot be reused: reconcile its source/version/output evidence before writing")
    for role, output_path in named_outputs:
        if output_path.exists():
            raise SystemExit(f"Refusing unowned existing {role}: {output_path}; retain or reconcile its version first")
        for parent in output_path.parents:
            if parent.exists() and not parent.is_dir():
                raise SystemExit(f"Output parent is not a directory: {parent}")
    for crop_path in crop_paths:
        if crop_path.is_symlink() or crop_path.exists():
            raise RuntimeError(
                "Refusing to overwrite existing contact-sheet cell crop: "
                f"{crop_path}"
            )

    records = []
    for part_index, part_path, segment_start, segment_end, segment_times in jobs:
        base_cells = cell_records(part_index, segment_times, args.label_offset)
        crop_records = make_sheet(
            video=args.video,
            out=part_path,
            times=segment_times,
            label_offset=args.label_offset,
            columns=columns,
            thumb_width=thumb_width,
            thumb_height=thumb_height,
            **(
                {
                    "cell_crops_dir": args.cell_crops_dir,
                    "cell_ids": [cell["cell_id"] for cell in base_cells],
                }
                if args.cell_crops_dir
                else {}
            ),
        )
        records.append(
            {
                "part_index": part_index,
                "path": part_path.as_posix(),
                "source_time_range": f"{segment_start:.3f}-{segment_end:.3f}",
                "timestamp_count": len(segment_times),
                "timestamps": segment_times,
                "cells": cell_records(
                    part_index,
                    segment_times,
                    args.label_offset,
                    crop_records if args.cell_crops_dir else None,
                ),
            }
        )

    if args.manifest:
        for record in records:
            sheet_evidence = file_evidence(Path(record["path"]))
            record["sha256"] = sheet_evidence["sha256"]
            record["size_bytes"] = sheet_evidence["size_bytes"]
        payload = {
            "schema_version": "idol_video_qc_sheet_manifest.v1",
            "generator_source_sha256": sha256_file(Path(__file__)),
            "video": args.video.as_posix(),
            "source_video": file_evidence(args.video),
            "preset": args.preset,
            "interval_seconds": interval,
            "label_offset_seconds": args.label_offset,
            "segment_duration_seconds": args.segment_duration,
            "columns": columns,
            "thumb_width": thumb_width,
            "thumb_height": thumb_height,
            "sheet_count": len(records),
            "sheets": records,
        }
        if args.cell_crops_dir:
            payload["cell_crops"] = {
                "output_dir": args.cell_crops_dir.as_posix(),
                "cell_count": sum(len(record["cells"]) for record in records),
                "kind": "timestamp_labelled_contact_sheet_cell",
            }
        args.manifest.parent.mkdir(parents=True, exist_ok=True)
        descriptor, temporary = tempfile.mkstemp(prefix=f".{args.manifest.name}.", dir=args.manifest.parent)
        try:
            with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
                handle.write(json.dumps(payload, indent=2, allow_nan=False) + "\n")
                handle.flush()
                os.fsync(handle.fileno())
            os.replace(temporary, args.manifest)
        finally:
            Path(temporary).unlink(missing_ok=True)


if __name__ == "__main__":
    main()
