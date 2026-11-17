#!/usr/bin/env python3
"""Index active IDOL raw video sources for edit selection.

The script reads the run-owned ``generations/video/raw`` tree, accepts
``raw/additional`` for added sources, and stops when the retired misspelled
folder is populated. It writes a compact YAML index with stream metadata,
motion peaks, and contact-sheet paths for editing QC.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import shutil
import subprocess
from pathlib import Path

try:
    import cv2
    import numpy as np
    import yaml
except ModuleNotFoundError as exc:
    raise SystemExit(
        f"Missing Python dependency '{exc.name}'. "
        "Run this script through scripts/idol-video-python."
    ) from exc

import idol_title_output_registry as title_registry
from lib.idol_artifact_integrity import IntegrityCache


REPO_ROOT = Path(__file__).resolve().parents[1]
CACHE_SCHEMA_VERSION = "idol_video_source_intake_cache.v4"
PROBE_CONTRACT_VERSION = "idol_video_source_probe.v2"
MOTION_PEAK_LIMIT = 8
PROBE_METADATA_FIELDS = (
    "duration_seconds",
    "width",
    "height",
    "fps",
    "codec",
    "probe_contract",
)


def run(cmd: list[str]) -> None:
    subprocess.run(cmd, check=True)


def tool_path(name: str) -> str:
    for prefix in ["/opt/homebrew/bin", "/usr/local/bin"]:
        preferred = Path(prefix) / name
        if preferred.exists():
            return str(preferred)
    found = shutil.which(name)
    if found:
        return found
    raise SystemExit(
        f"Missing required tool: {name}. "
        "Run through scripts/idol-video-python or install ffmpeg in Homebrew."
    )


def ffprobe_json(path: Path) -> dict:
    proc = subprocess.run(
        [
            tool_path("ffprobe"),
            "-v",
            "error",
            "-show_streams",
            "-show_format",
            "-of",
            "json",
            str(path),
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    return json.loads(proc.stdout)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def stable_sha256(value: object) -> str:
    encoded = json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def tool_version(name: str) -> str:
    proc = subprocess.run(
        [tool_path(name), "-version"],
        check=True,
        capture_output=True,
        text=True,
    )
    return (proc.stdout or proc.stderr).splitlines()[0].strip()


def implementation_fingerprints() -> dict[str, str]:
    script_sha = sha256_file(Path(__file__).resolve())
    common = {"script_sha256": script_sha, "python": tuple(__import__("sys").version_info[:3])}
    return {
        "probe": stable_sha256({**common, "ffprobe": tool_version("ffprobe")}),
        "motion": stable_sha256(
            {**common, "opencv": cv2.__version__, "numpy": np.__version__}
        ),
        "contact_sheet": stable_sha256({**common, "ffmpeg": tool_version("ffmpeg")}),
    }


def component_cache_key(
    *, source_sha256: str, relative_source: str, settings_sha256: str
) -> str:
    return stable_sha256(
        {
            "source_sha256": source_sha256,
            "relative_source": relative_source,
            "settings_sha256": settings_sha256,
        }
    )


def load_existing_index(output_path: Path) -> dict:
    if not output_path.is_file():
        return {}
    try:
        document = yaml.safe_load(output_path.read_text())
    except (OSError, UnicodeError, yaml.YAMLError):
        return {}
    return document if isinstance(document, dict) else {}


def source_entries_by_path(index: dict) -> dict[str, dict]:
    entries = index.get("sources", [])
    if not isinstance(entries, list):
        return {}
    return {
        entry["source"]: entry
        for entry in entries
        if isinstance(entry, dict) and isinstance(entry.get("source"), str)
    }


def cache_fingerprint(entry: dict, field: str) -> str | None:
    fingerprints = entry.get("cache_fingerprints", {})
    if not isinstance(fingerprints, dict):
        return None
    value = fingerprints.get(field)
    return value if isinstance(value, str) else None


def cache_evidence(entry: dict, field: str) -> str | None:
    evidence = entry.get("cache_evidence", {})
    if not isinstance(evidence, dict):
        return None
    value = evidence.get(field)
    return value if isinstance(value, str) else None


def probe_evidence_sha256(entry: dict) -> str:
    return stable_sha256({field: entry.get(field) for field in PROBE_METADATA_FIELDS})


def reusable_probe(entry: dict, cache_key: str, force_refresh: bool) -> bool:
    if force_refresh:
        return False
    if cache_fingerprint(entry, "probe_cache_key_sha256") != cache_key:
        return False
    if not all(field in entry for field in PROBE_METADATA_FIELDS):
        return False
    return cache_evidence(entry, "probe_output_sha256") == probe_evidence_sha256(entry)


def reusable_motion(entry: dict, cache_key: str, force_refresh: bool) -> bool:
    if force_refresh:
        return False
    return (
        cache_fingerprint(entry, "motion_cache_key_sha256") == cache_key
        and isinstance(entry.get("motion_peaks"), list)
        and cache_evidence(entry, "motion_output_sha256")
        == stable_sha256(entry["motion_peaks"])
    )


def reusable_contact_sheet(
    entry: dict,
    cache_key: str,
    expected_sheet_path: Path,
    force_refresh: bool,
) -> bool:
    if force_refresh:
        return False
    return (
        cache_fingerprint(entry, "contact_sheet_cache_key_sha256") == cache_key
        and entry.get("contact_sheet") == str(expected_sheet_path)
        and expected_sheet_path.is_file()
        and cache_evidence(entry, "contact_sheet_output_sha256")
        == sha256_file(expected_sheet_path)
    )


def intake_settings(
    *, include_motion: bool, sample_fps: float, write_contact_sheets: bool, contact_fps: float
) -> tuple[dict, dict, dict]:
    implementations = implementation_fingerprints()
    probe = {
        "contract_version": "ffprobe_stream_metadata.v2",
        "implementation_fingerprint_sha256": implementations["probe"],
        "show_streams": True,
        "show_format": True,
        "exclude_attached_picture_streams": True,
        "metadata_fields": list(PROBE_METADATA_FIELDS),
        "unknown_metadata_policy": (
            "Preserve unknown/partial geometry, frame-rate, scan, and color tags; "
            "do not infer a transform or delivery space."
        ),
    }
    motion = {
        "contract_version": "opencv_farneback_motion_peaks.v1",
        "implementation_fingerprint_sha256": implementations["motion"],
        "enabled": include_motion,
        "sample_fps": sample_fps,
        "peak_limit": MOTION_PEAK_LIMIT,
        "analysis_frame_size": [160, 90],
        "farneback": {
            "pyr_scale": 0.5,
            "levels": 3,
            "winsize": 15,
            "iterations": 3,
            "poly_n": 5,
            "poly_sigma": 1.2,
            "flags": 0,
        },
    }
    contact_sheet = {
        "contract_version": "ffmpeg_source_contact_sheet.v1",
        "implementation_fingerprint_sha256": implementations["contact_sheet"],
        "enabled": write_contact_sheets,
        "fps": contact_fps,
        "cell_size": [240, 135],
        "max_columns": 6,
        "padding": 4,
        "margin": 4,
        "timecode_overlay": True,
    }
    return probe, motion, contact_sheet


def selected_video_stream(probe: dict) -> dict:
    for stream in probe.get("streams", []):
        if stream.get("codec_type") != "video":
            continue
        if stream.get("disposition", {}).get("attached_pic") == 1:
            continue
        return stream
    raise ValueError("No non-attached video stream found")


def parse_rate(value: str | None) -> float | None:
    if not value or value in {"0/0", "N/A", "unknown"}:
        return None
    try:
        if "/" in value:
            numerator, denominator = value.split("/", 1)
            denominator_value = float(denominator)
            if denominator_value == 0:
                return None
            return float(numerator) / denominator_value
        return float(value)
    except (TypeError, ValueError):
        return None


def value_or_unknown(value: object) -> object:
    if value is None or value == "" or value == "N/A":
        return "unknown"
    return value


def integer_or_none(value: object) -> int | None:
    if value is None or value == "" or value == "N/A":
        return None
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def rotation_degrees(stream: dict) -> float | None:
    tags = stream.get("tags") or {}
    tag_rotation = tags.get("rotate") if isinstance(tags, dict) else None
    if tag_rotation not in (None, "", "N/A"):
        try:
            return round(float(tag_rotation), 6)
        except (TypeError, ValueError):
            pass
    for row in stream.get("side_data_list") or []:
        if not isinstance(row, dict) or row.get("rotation") in (None, "", "N/A"):
            continue
        try:
            return round(float(row["rotation"]), 6)
        except (TypeError, ValueError):
            continue
    return None


def frame_rate_contract(stream: dict) -> dict:
    avg_raw = str(stream.get("avg_frame_rate") or "unknown")
    nominal_raw = str(stream.get("r_frame_rate") or "unknown")
    avg_value = parse_rate(None if avg_raw == "unknown" else avg_raw)
    nominal_value = parse_rate(None if nominal_raw == "unknown" else nominal_raw)
    if avg_value is not None and nominal_value is not None:
        vfr_candidate = not math.isclose(
            avg_value,
            nominal_value,
            rel_tol=1e-4,
            abs_tol=1e-4,
        )
        rate_mode = "vfr_candidate" if vfr_candidate else "cfr_candidate"
        reason = (
            "avg_frame_rate differs from r_frame_rate; inspect timestamps before frame-canonical use"
            if vfr_candidate
            else "avg_frame_rate matches r_frame_rate; CFR remains a probe candidate until timestamp QC"
        )
    else:
        vfr_candidate = None
        rate_mode = "unknown"
        reason = "ffprobe did not expose both avg_frame_rate and r_frame_rate"
    return {
        "avg_frame_rate": avg_raw,
        "r_frame_rate": nominal_raw,
        "time_base": str(stream.get("time_base") or "unknown"),
        "start_pts": integer_or_none(stream.get("start_pts")),
        "duration_ts": integer_or_none(stream.get("duration_ts")),
        "frame_count": integer_or_none(stream.get("nb_frames")),
        "rate_mode": rate_mode,
        "vfr_candidate": vfr_candidate,
        "reason": reason,
    }


def color_contract(stream: dict) -> dict:
    tags = {
        "color_range": value_or_unknown(stream.get("color_range")),
        "color_space": value_or_unknown(stream.get("color_space")),
        "color_transfer": value_or_unknown(stream.get("color_transfer")),
        "color_primaries": value_or_unknown(stream.get("color_primaries")),
    }
    known_count = sum(value != "unknown" for value in tags.values())
    if known_count == len(tags):
        status = "tagged_complete"
    elif known_count == 0:
        status = "unknown"
    else:
        status = "tagged_partial"
    side_data_types = sorted(
        {
            str(row.get("side_data_type"))
            for row in (stream.get("side_data_list") or [])
            if isinstance(row, dict) and row.get("side_data_type")
        }
    )
    hdr_markers = ("mastering", "content light", "hdr", "dolby vision", "dovi")
    hdr_transfers = {"smpte2084", "arib-std-b67"}
    return {
        **tags,
        "metadata_status": status,
        "side_data_types": side_data_types,
        "hdr_metadata_present": any(
            any(marker in item.lower() for marker in hdr_markers)
            for item in side_data_types
        ),
        "hdr_transfer_candidate": (
            str(tags["color_transfer"]).lower() in hdr_transfers
        ),
        "interpretation_policy": (
            "measurement_only; unknown/partial tags require an explicit recipe interpretation, "
            "and writing delivery tags is not a color transform"
        ),
    }


def professional_probe_contract(stream: dict) -> dict:
    declared_bit_depth = integer_or_none(stream.get("bits_per_raw_sample"))
    if declared_bit_depth is None:
        declared_bit_depth = integer_or_none(stream.get("bits_per_sample"))
    return {
        "schema_version": PROBE_CONTRACT_VERSION,
        "stream_index": integer_or_none(stream.get("index")),
        "codec": {
            "name": str(stream.get("codec_name") or "unknown"),
            "profile": value_or_unknown(stream.get("profile")),
            "pixel_format": value_or_unknown(stream.get("pix_fmt")),
            "declared_bit_depth": declared_bit_depth,
            "declared_bit_depth_source": (
                "ffprobe_stream_field" if declared_bit_depth is not None else "unknown"
            ),
        },
        "frame_rate": frame_rate_contract(stream),
        "geometry": {
            "width": integer_or_none(stream.get("width")),
            "height": integer_or_none(stream.get("height")),
            "sample_aspect_ratio": value_or_unknown(stream.get("sample_aspect_ratio")),
            "display_aspect_ratio": value_or_unknown(stream.get("display_aspect_ratio")),
            "rotation_degrees": rotation_degrees(stream),
        },
        "scan": {
            "field_order": value_or_unknown(stream.get("field_order")),
        },
        "color": color_contract(stream),
    }


def motion_peaks(
    video_path: Path, sample_fps: float, limit: int = MOTION_PEAK_LIMIT
) -> list[dict]:
    cap = cv2.VideoCapture(str(video_path))
    native_fps = cap.get(cv2.CAP_PROP_FPS) or 24.0
    step = max(1, int(round(native_fps / sample_fps)))
    prev_gray = None
    rows = []
    frame_idx = -1
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        frame_idx += 1
        if frame_idx % step != 0:
            continue
        small = cv2.resize(frame, (160, 90))
        gray = cv2.cvtColor(small, cv2.COLOR_BGR2GRAY)
        if prev_gray is None:
            score = 0.0
        else:
            flow = cv2.calcOpticalFlowFarneback(
                prev_gray,
                gray,
                None,
                0.5,
                3,
                15,
                3,
                5,
                1.2,
                0,
            )
            mag, _ = cv2.cartToPolar(flow[..., 0], flow[..., 1])
            score = float(np.mean(mag))
        rows.append({"time_seconds": round(frame_idx / native_fps, 4), "motion_score": round(score, 6)})
        prev_gray = gray
    cap.release()
    return sorted(rows, key=lambda row: row["motion_score"], reverse=True)[:limit]


def safe_sheet_name(relative_source: str) -> str:
    normalized = relative_source.replace("/", "__")
    return re.sub(r"[^A-Za-z0-9_.-]+", "_", normalized).removesuffix(".mp4") + "-source-contact-sheet.png"


def make_contact_sheet(video_path: Path, out_path: Path, duration: float, fps: float) -> None:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    frame_count = max(1, math.ceil(duration * fps))
    columns = min(6, frame_count)
    rows = math.ceil(frame_count / columns)
    run(
        [
            tool_path("ffmpeg"),
            "-hide_banner",
            "-y",
            "-i",
            str(video_path),
            "-vf",
            (
                f"fps={fps},"
                "drawtext=text='%{pts\\:hms}':x=6:y=6:fontcolor=white:"
                "fontsize=18:box=1:boxcolor=black@0.65,"
                "scale=240:135:force_original_aspect_ratio=decrease,"
                "pad=240:135:(ow-iw)/2:(oh-ih)/2,"
                f"tile={columns}x{rows}:padding=4:margin=4"
            ),
            "-frames:v",
            "1",
            "-update",
            "1",
            str(out_path),
        ]
    )


def discover_sources(raw_dir: Path) -> list[Path]:
    retired_dir = raw_dir / "addiontal"
    if retired_dir.exists() and any(path.is_file() for path in retired_dir.rglob("*")):
        raise RuntimeError(
            "retired raw/addiontal source folder is populated; keep it as "
            "historical evidence and migrate selected bytes through a "
            "hash-bound plan into generations/video/raw/additional before "
            "active source intake"
        )
    sources_by_relative_path = {
        path.relative_to(raw_dir).as_posix(): path
        for path in raw_dir.rglob("*.mp4")
        if path.is_file()
    }
    return [sources_by_relative_path[key] for key in sorted(sources_by_relative_path)]


def build_index(
    run_root: Path,
    output_path: Path,
    write_contact_sheets: bool,
    include_motion: bool,
    sample_fps: float,
    contact_fps: float,
    force_refresh: bool = False,
    cache_stats: dict | None = None,
) -> dict:
    raw_dir = run_root / "generations/video/raw"
    sheet_dir = run_root / "generations/video/qc/contact-sheets/source-intake"
    integrity_cache = IntegrityCache(REPO_ROOT)
    previous_sources = source_entries_by_path(load_existing_index(output_path))
    probe_settings, motion_settings, contact_sheet_settings = intake_settings(
        include_motion=include_motion,
        sample_fps=sample_fps,
        write_contact_sheets=write_contact_sheets,
        contact_fps=contact_fps,
    )
    probe_settings_sha256 = stable_sha256(probe_settings)
    motion_settings_sha256 = stable_sha256(motion_settings)
    contact_sheet_settings_sha256 = stable_sha256(contact_sheet_settings)
    current_cache_stats = {
        "probe_hits": 0,
        "probe_misses": 0,
        "motion_hits": 0,
        "motion_misses": 0,
        "motion_skipped": 0,
        "contact_sheet_hits": 0,
        "contact_sheet_misses": 0,
        "contact_sheet_skipped": 0,
        "source_hash_cache_hits": 0,
        "source_hash_cache_misses": 0,
        "contact_sheet_hash_cache_hits": 0,
        "contact_sheet_hash_cache_misses": 0,
    }
    entries = []
    for source_path in discover_sources(raw_dir):
        relative_source = source_path.relative_to(raw_dir).as_posix()
        source_key = f"generations/video/raw/{relative_source}"
        previous = previous_sources.get(source_key, {})
        source_integrity = integrity_cache.inspect(
            source_path,
            "canonical_gate" if force_refresh else "repeat_local_validation",
        )
        source_digest = str(source_integrity["value"])
        current_cache_stats[
            "source_hash_cache_hits"
            if source_integrity["cache"] == "hit"
            else "source_hash_cache_misses"
        ] += 1
        probe_cache_key = component_cache_key(
            source_sha256=source_digest,
            relative_source=relative_source,
            settings_sha256=probe_settings_sha256,
        )
        motion_cache_key = component_cache_key(
            source_sha256=source_digest,
            relative_source=relative_source,
            settings_sha256=motion_settings_sha256,
        )
        contact_sheet_cache_key = component_cache_key(
            source_sha256=source_digest,
            relative_source=relative_source,
            settings_sha256=contact_sheet_settings_sha256,
        )

        if reusable_probe(previous, probe_cache_key, force_refresh):
            metadata = {field: previous[field] for field in PROBE_METADATA_FIELDS}
            current_cache_stats["probe_hits"] += 1
        else:
            probe = ffprobe_json(source_path)
            stream = selected_video_stream(probe)
            duration = float(
                probe.get("format", {}).get("duration") or stream.get("duration") or 0.0
            )
            metadata = {
                "duration_seconds": round(duration, 6),
                "width": int(stream["width"]),
                "height": int(stream["height"]),
                "fps": round(
                    parse_rate(stream.get("avg_frame_rate") or stream.get("r_frame_rate"))
                    or 0.0,
                    6,
                ),
                "codec": str(stream.get("codec_name") or "unknown"),
                "probe_contract": professional_probe_contract(stream),
            }
            current_cache_stats["probe_misses"] += 1

        duration = float(metadata["duration_seconds"])
        sheet_path = sheet_dir / safe_sheet_name(relative_source)
        contact_sheet_reused = False
        if write_contact_sheets:
            if reusable_contact_sheet(
                previous,
                contact_sheet_cache_key,
                sheet_path,
                force_refresh,
            ):
                current_cache_stats["contact_sheet_hits"] += 1
                contact_sheet_reused = True
            else:
                make_contact_sheet(source_path, sheet_path, duration, contact_fps)
                current_cache_stats["contact_sheet_misses"] += 1
        else:
            current_cache_stats["contact_sheet_skipped"] += 1
        contact_sheet_integrity = None
        if write_contact_sheets:
            contact_sheet_integrity = integrity_cache.sha256(
                sheet_path,
                force=not contact_sheet_reused,
            )
            current_cache_stats[
                "contact_sheet_hash_cache_hits"
                if contact_sheet_integrity["cache"] == "hit"
                else "contact_sheet_hash_cache_misses"
            ] += 1

        entry = {
            "source": source_key,
            **metadata,
            "contact_sheet": str(sheet_path) if write_contact_sheets else None,
            "source_group": relative_source.split("/", 1)[0] if "/" in relative_source else "raw",
            "source_sha256": source_digest,
            "cache_fingerprints": {
                "probe_cache_key_sha256": probe_cache_key,
                "motion_cache_key_sha256": motion_cache_key if include_motion else None,
                "contact_sheet_cache_key_sha256": (
                    contact_sheet_cache_key if write_contact_sheets else None
                ),
            },
        }
        if include_motion:
            if reusable_motion(previous, motion_cache_key, force_refresh):
                entry["motion_peaks"] = previous["motion_peaks"]
                current_cache_stats["motion_hits"] += 1
            else:
                entry["motion_peaks"] = motion_peaks(source_path, sample_fps)
                current_cache_stats["motion_misses"] += 1
        else:
            entry["motion_peaks"] = []
            current_cache_stats["motion_skipped"] += 1
        entry["cache_evidence"] = {
            "probe_output_sha256": stable_sha256(metadata),
            "motion_output_sha256": (
                stable_sha256(entry["motion_peaks"]) if include_motion else None
            ),
            "contact_sheet_output_sha256": (
                contact_sheet_integrity["value"]
                if contact_sheet_integrity is not None
                else None
            ),
        }
        entries.append(entry)

    integrity_cache.save()
    payload = {
        "schema_version": "idol_video_source_intake.v2",
        "content_id": run_root.name,
        "raw_video_dir": str(raw_dir),
        "additional_dir": str(raw_dir / "additional"),
        "cache_contract": {
            "schema_version": CACHE_SCHEMA_VERSION,
            "source_hash_algorithm": "sha256",
            "component_output_hash_algorithm": "sha256",
            "routine_source_hash_profile": "repeat_local_validation",
            "forced_refresh_hash_profile": "canonical_gate",
            "cache_authority": "performance_only_never_gate_or_approval",
            "promotion_rehash_profile": "promotion_or_external_transfer",
            "probe_settings_sha256": probe_settings_sha256,
            "motion_settings_sha256": motion_settings_sha256,
            "contact_sheet_settings_sha256": contact_sheet_settings_sha256,
            "force_refresh_supported": True,
            "reuse_rule": (
                "Reuse each probe, motion, or contact-sheet component only when its "
                "source SHA-256, component settings cache key, and cached-output "
                "SHA-256 match; --force bypasses reuse."
            ),
        },
        "source_count": len(entries),
        "sources": entries,
    }
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(yaml.safe_dump(payload, allow_unicode=True, sort_keys=False))
    if cache_stats is not None:
        cache_stats.clear()
        cache_stats.update(current_cache_stats)
    return payload


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--run-root",
        required=True,
        type=Path,
    )
    parser.add_argument("--output", type=Path)
    parser.add_argument("--skip-contact-sheets", action="store_true")
    parser.add_argument("--skip-motion", action="store_true")
    parser.add_argument("--album-key", default=title_registry.DEFAULT_ALBUM_KEY)
    parser.add_argument("--title-key", default=None)
    parser.add_argument("--title", default="")
    parser.add_argument("--skip-title-registry", action="store_true")
    parser.add_argument("--sample-fps", type=float, default=4.0)
    parser.add_argument("--contact-fps", type=float, default=1.0)
    parser.add_argument(
        "--force",
        action="store_true",
        help="Bypass source/config cache reuse and rebuild probe, motion, and contact-sheet outputs.",
    )
    args = parser.parse_args()

    if args.sample_fps <= 0:
        parser.error("--sample-fps must be greater than 0")
    if args.contact_fps <= 0:
        parser.error("--contact-fps must be greater than 0")

    output_path = (
        args.output
        or args.run_root / "generations/video/qc/source-intake/source-index-v2.yaml"
    )
    cache_stats = {}
    payload = build_index(
        run_root=args.run_root,
        output_path=output_path,
        write_contact_sheets=not args.skip_contact_sheets,
        include_motion=not args.skip_motion,
        sample_fps=args.sample_fps,
        contact_fps=args.contact_fps,
        force_refresh=args.force,
        cache_stats=cache_stats,
    )
    if not args.skip_title_registry:
        album = title_registry.album_key(args.album_key)
        track = title_registry.title_key(args.title_key, fallback=args.title or args.run_root.name)
        outputs = [
            {
                "output_type": "qc_artifact",
                "path": output_path,
                "source_run_root": args.run_root,
                "content_id": args.run_root.name,
                "source_step": "edit",
                "status": "exported",
                "notes": "raw video source intake index",
            }
        ]
        for source in payload.get("sources", []):
            source_path = args.run_root / str(source.get("source", ""))
            outputs.append(
                {
                    "output_type": "generated_video",
                    "path": source_path,
                    "source_run_root": args.run_root,
                    "content_id": args.run_root.name,
                    "source_step": "post_review_video",
                    "status": "imported",
                    "notes": "raw generated video source discovered for edit intake",
                }
            )
            sheet_path = source.get("contact_sheet")
            if sheet_path:
                sheet_output = Path(str(sheet_path))
                if not sheet_output.is_absolute() and not sheet_output.as_posix().startswith(args.run_root.as_posix()):
                    sheet_output = args.run_root / sheet_output
                outputs.append(
                    {
                        "output_type": "qc_artifact",
                        "path": sheet_output,
                        "source_run_root": args.run_root,
                        "content_id": args.run_root.name,
                        "source_step": "edit",
                        "status": "exported",
                        "notes": "video source contact sheet",
                    }
                )
        title_registry.register_outputs(
            album=album,
            title=track,
            title_display_name=args.title or track,
            content_id=args.run_root.name,
            run_root=title_registry.rel(args.run_root),
            outputs=outputs,
            status="generated",
            write=True,
        )
    print(output_path)
    print(f"sources={payload['source_count']}")
    print(
        "cache="
        f"probe:{cache_stats['probe_hits']}h/{cache_stats['probe_misses']}m,"
        f"motion:{cache_stats['motion_hits']}h/{cache_stats['motion_misses']}m/"
        f"{cache_stats['motion_skipped']}s,"
        f"contact_sheet:{cache_stats['contact_sheet_hits']}h/"
        f"{cache_stats['contact_sheet_misses']}m/"
        f"{cache_stats['contact_sheet_skipped']}s"
    )


if __name__ == "__main__":
    main()
