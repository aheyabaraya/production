"""Local quality contract for IDOL/CF video bytes sent to platform APIs.

The module performs no network I/O.  It probes exact local bytes, requires the
2K/30fps delivery floor, and validates the run-owned preparation receipt used
by IDOL MV uploads.
"""

from __future__ import annotations

import hashlib
import json
import subprocess
from fractions import Fraction
from pathlib import Path
from typing import Any

import jsonschema
import yaml


QUALITY_PROFILE = "idol_api_upload_2k30_high_quality.v1"
RECEIPT_SCHEMA_VERSION = "idol_api_upload_video.v1"
MIN_LONG_EDGE = 2560
MIN_SHORT_EDGE = 1440
TARGET_FPS = Fraction(30, 1)
ALLOWED_VIDEO_CODECS = {"h264"}
ALLOWED_PIXEL_FORMATS = {"yuv420p"}
ALLOWED_AUDIO_CODECS = {"aac"}
MIN_AUDIO_BIT_RATE = 256_000
TARGET_AUDIO_SAMPLE_RATE = 48_000


class ApiVideoQualityError(RuntimeError):
    """Raised before external execution when video bytes miss the contract."""


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _fraction(value: Any, label: str) -> Fraction:
    try:
        rate = Fraction(str(value))
    except (ValueError, ZeroDivisionError) as exc:
        raise ApiVideoQualityError(f"{label} is unreadable: {value!r}") from exc
    if rate <= 0:
        raise ApiVideoQualityError(f"{label} must be positive")
    return rate


def _positive_int(value: Any, label: str) -> int:
    try:
        parsed = int(value)
    except (TypeError, ValueError) as exc:
        raise ApiVideoQualityError(f"{label} is unreadable: {value!r}") from exc
    if parsed <= 0:
        raise ApiVideoQualityError(f"{label} must be positive")
    return parsed


def ffprobe_document(path: Path, *, ffprobe: str = "ffprobe") -> dict[str, Any]:
    if not path.is_file():
        raise ApiVideoQualityError(f"API upload video is missing: {path}")
    command = [
        ffprobe,
        "-v",
        "error",
        "-show_entries",
        (
            "format=duration,size,bit_rate,format_name:"
            "stream=index,codec_type,codec_name,width,height,r_frame_rate,"
            "avg_frame_rate,pix_fmt,field_order,bit_rate,sample_rate,channels"
        ),
        "-of",
        "json",
        str(path),
    ]
    try:
        completed = subprocess.run(command, text=True, capture_output=True, check=False)
    except OSError as exc:
        raise ApiVideoQualityError("ffprobe is unavailable in the IDOL media runtime") from exc
    if completed.returncode:
        detail = (completed.stderr or completed.stdout).strip()
        raise ApiVideoQualityError(f"ffprobe could not read API upload video: {detail}")
    try:
        document = json.loads(completed.stdout)
    except json.JSONDecodeError as exc:
        raise ApiVideoQualityError("ffprobe returned invalid JSON") from exc
    if not isinstance(document, dict):
        raise ApiVideoQualityError("ffprobe result must be an object")
    return document


def validate_probe_document(
    document: dict[str, Any], *, label: str = "API upload video"
) -> dict[str, Any]:
    streams = document.get("streams") or []
    video_streams = [row for row in streams if row.get("codec_type") == "video"]
    audio_streams = [row for row in streams if row.get("codec_type") == "audio"]
    if len(video_streams) != 1:
        raise ApiVideoQualityError(f"{label} must contain exactly one video stream")
    if len(audio_streams) != 1:
        raise ApiVideoQualityError(f"{label} must contain exactly one audio stream")

    video = video_streams[0]
    audio = audio_streams[0]
    width = _positive_int(video.get("width"), f"{label} width")
    height = _positive_int(video.get("height"), f"{label} height")
    long_edge = max(width, height)
    short_edge = min(width, height)
    if long_edge < MIN_LONG_EDGE or short_edge < MIN_SHORT_EDGE:
        raise ApiVideoQualityError(
            f"{label} is below the 2K floor: {width}x{height}; "
            f"need long edge >= {MIN_LONG_EDGE} and short edge >= {MIN_SHORT_EDGE}"
        )

    average_fps = _fraction(video.get("avg_frame_rate"), f"{label} average FPS")
    nominal_fps = _fraction(video.get("r_frame_rate"), f"{label} nominal FPS")
    if average_fps != TARGET_FPS or nominal_fps != TARGET_FPS:
        raise ApiVideoQualityError(
            f"{label} must be exact CFR 30fps; got avg={average_fps}, nominal={nominal_fps}"
        )

    video_codec = str(video.get("codec_name") or "").lower()
    if video_codec not in ALLOWED_VIDEO_CODECS:
        raise ApiVideoQualityError(f"{label} video codec must be H.264")
    pixel_format = str(video.get("pix_fmt") or "").lower()
    if pixel_format not in ALLOWED_PIXEL_FORMATS:
        raise ApiVideoQualityError(f"{label} pixel format must be yuv420p")
    field_order = str(video.get("field_order") or "unknown").lower()
    if field_order not in {"progressive", "unknown"}:
        raise ApiVideoQualityError(f"{label} must be progressive, not {field_order}")

    audio_codec = str(audio.get("codec_name") or "").lower()
    if audio_codec not in ALLOWED_AUDIO_CODECS:
        raise ApiVideoQualityError(f"{label} audio codec must be AAC")
    sample_rate = _positive_int(audio.get("sample_rate"), f"{label} audio sample rate")
    if sample_rate != TARGET_AUDIO_SAMPLE_RATE:
        raise ApiVideoQualityError(
            f"{label} audio sample rate must be {TARGET_AUDIO_SAMPLE_RATE}Hz"
        )
    audio_bit_rate = _positive_int(audio.get("bit_rate"), f"{label} audio bit rate")
    if audio_bit_rate < MIN_AUDIO_BIT_RATE:
        raise ApiVideoQualityError(
            f"{label} audio bit rate {audio_bit_rate} is below {MIN_AUDIO_BIT_RATE}"
        )

    format_row = document.get("format") or {}
    format_name = str(format_row.get("format_name") or "").lower()
    if "mp4" not in format_name and "mov" not in format_name:
        raise ApiVideoQualityError(f"{label} container must be MP4-compatible")
    duration = float(format_row.get("duration") or 0)
    if duration <= 0:
        raise ApiVideoQualityError(f"{label} duration must be positive")

    return {
        "quality_profile": QUALITY_PROFILE,
        "width": width,
        "height": height,
        "long_edge": long_edge,
        "short_edge": short_edge,
        "avg_frame_rate": f"{average_fps.numerator}/{average_fps.denominator}",
        "r_frame_rate": f"{nominal_fps.numerator}/{nominal_fps.denominator}",
        "video_codec": video_codec,
        "pixel_format": pixel_format,
        "field_order": field_order,
        "video_bit_rate": int(video.get("bit_rate") or 0),
        "audio_codec": audio_codec,
        "audio_bit_rate": audio_bit_rate,
        "audio_sample_rate": sample_rate,
        "duration_seconds": duration,
        "byte_delivery": "exact_approved_bytes_no_uploader_transcode",
    }


def inspect_api_upload_video(path: Path, *, ffprobe: str = "ffprobe") -> dict[str, Any]:
    if path.suffix.lower() != ".mp4":
        raise ApiVideoQualityError(f"API upload video must use .mp4: {path}")
    result = validate_probe_document(ffprobe_document(path, ffprobe=ffprobe), label=str(path))
    result["path"] = str(path)
    result["sha256"] = sha256_file(path)
    result["bytes"] = path.stat().st_size
    return result


def resolve_run_path(repo_root: Path, run_root: Path, value: Any, label: str) -> Path:
    raw = Path(str(value or ""))
    candidate = raw if raw.is_absolute() else repo_root / raw
    candidate = candidate.resolve()
    try:
        candidate.relative_to(run_root.resolve())
    except ValueError as exc:
        raise ApiVideoQualityError(f"{label} must stay inside the owning run") from exc
    return candidate


def load_receipt(path: Path) -> dict[str, Any]:
    try:
        if path.suffix.lower() == ".json":
            value = json.loads(path.read_text(encoding="utf-8"))
        else:
            value = yaml.safe_load(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError, yaml.YAMLError) as exc:
        raise ApiVideoQualityError(f"API upload quality receipt is unreadable: {path}") from exc
    if not isinstance(value, dict):
        raise ApiVideoQualityError("API upload quality receipt must be an object")
    return value


def validate_quality_receipt(
    *,
    repo_root: Path,
    run_root: Path,
    content_id: str,
    asset_path: Path,
    receipt_path: Path,
    probe: dict[str, Any],
) -> dict[str, Any]:
    if not receipt_path.is_file():
        raise ApiVideoQualityError(f"API upload quality receipt is missing: {receipt_path}")
    try:
        receipt_path.resolve().relative_to(run_root.resolve())
    except ValueError as exc:
        raise ApiVideoQualityError("API upload quality receipt must stay inside the owning run") from exc
    document = load_receipt(receipt_path)
    schema_path = repo_root / "schemas" / "api-upload-video.schema.json"
    schema = json.loads(schema_path.read_text(encoding="utf-8"))
    errors = sorted(
        jsonschema.Draft202012Validator(schema).iter_errors(document),
        key=lambda error: list(error.absolute_path),
    )
    if errors:
        detail = "; ".join(error.message for error in errors)
        raise ApiVideoQualityError(f"API upload quality receipt schema failure: {detail}")
    if document.get("content_id") != content_id:
        raise ApiVideoQualityError("API upload quality receipt content_id does not match")
    output = document.get("output") or {}
    bound_output = resolve_run_path(repo_root, run_root, output.get("path"), "receipt output")
    if bound_output != asset_path.resolve():
        raise ApiVideoQualityError("API upload quality receipt points to a different asset")
    live_sha = sha256_file(asset_path)
    if output.get("sha256") != live_sha or probe.get("sha256") != live_sha:
        raise ApiVideoQualityError("API upload asset changed after quality receipt")
    for field in (
        "width",
        "height",
        "avg_frame_rate",
        "r_frame_rate",
        "video_codec",
        "pixel_format",
        "audio_codec",
        "audio_bit_rate",
        "audio_sample_rate",
    ):
        if output.get(field) != probe.get(field):
            raise ApiVideoQualityError(f"API upload quality receipt {field} is stale")
    return {
        "path": str(receipt_path),
        "sha256": sha256_file(receipt_path),
        "schema_version": RECEIPT_SCHEMA_VERSION,
        "quality_profile": QUALITY_PROFILE,
        "transform_mode": str((document.get("transform") or {}).get("mode") or ""),
    }


def target_geometry(width: int, height: int) -> tuple[int, int]:
    """Return an even, aspect-preserving geometry that never downscales."""

    width = _positive_int(width, "source width")
    height = _positive_int(height, "source height")
    scale = max(1.0, MIN_LONG_EDGE / max(width, height), MIN_SHORT_EDGE / min(width, height))
    target_width = max(width, int(round(width * scale / 2.0)) * 2)
    target_height = max(height, int(round(height * scale / 2.0)) * 2)
    return target_width, target_height
