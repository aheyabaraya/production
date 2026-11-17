#!/usr/bin/env python3
"""Prepare a run-owned IDOL video for quality-preserving platform API upload.

Dry-run performs no write and no external action.  ``--write`` either copies
already-compliant bytes without recompression or makes a local high-quality
2K/CFR-30 derivative.  Upload and public release remain separately approved.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import tempfile
from pathlib import Path
from typing import Any

import jsonschema
import yaml

from lib.idol_api_video_quality import (
    ApiVideoQualityError,
    QUALITY_PROFILE,
    ffprobe_document,
    inspect_api_upload_video,
    sha256_file,
    target_geometry,
)
from lib.idol_social_release_contracts import (
    SocialContractError,
    repo_relative,
    validate_run_owned_path,
    validate_run_scope,
)


ROOT = Path(__file__).resolve().parents[1]
SCHEMA = ROOT / "schemas/api-upload-video.schema.json"


def source_summary(document: dict[str, Any]) -> dict[str, Any]:
    streams = document.get("streams") or []
    video = next((row for row in streams if row.get("codec_type") == "video"), {})
    return {
        "width": int(video.get("width") or 0),
        "height": int(video.get("height") or 0),
        "avg_frame_rate": str(video.get("avg_frame_rate") or "unknown"),
    }


def source_is_compliant(path: Path) -> bool:
    try:
        inspect_api_upload_video(path)
        return True
    except ApiVideoQualityError:
        return False


def atomic_copy(source: Path, output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{output.name}.", dir=output.parent)
    os.close(descriptor)
    temporary = Path(temporary_name)
    try:
        with source.open("rb") as source_handle, temporary.open("wb") as target_handle:
            shutil.copyfileobj(source_handle, target_handle, length=1024 * 1024)
            target_handle.flush()
            os.fsync(target_handle.fileno())
        os.replace(temporary, output)
    finally:
        if temporary.exists():
            temporary.unlink()


def render_high_quality(source: Path, output: Path, width: int, height: int) -> None:
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        raise ApiVideoQualityError("ffmpeg is unavailable in the IDOL media runtime")
    output.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{output.stem}.", suffix=".mp4", dir=output.parent
    )
    os.close(descriptor)
    temporary = Path(temporary_name)
    try:
        command = [
            ffmpeg,
            "-hide_banner",
            "-loglevel",
            "error",
            "-y",
            "-i",
            str(source),
            "-map",
            "0:v:0",
            "-map",
            "0:a:0",
            "-vf",
            f"scale={width}:{height}:flags=lanczos,fps=30",
            "-c:v",
            "libx264",
            "-preset",
            "slow",
            "-crf",
            "14",
            "-profile:v",
            "high",
            "-pix_fmt",
            "yuv420p",
            "-r",
            "30",
            "-fps_mode",
            "cfr",
            "-c:a",
            "aac",
            "-b:a",
            "320k",
            "-ar",
            "48000",
            "-movflags",
            "+faststart",
            str(temporary),
        ]
        completed = subprocess.run(command, text=True, capture_output=True, check=False)
        if completed.returncode:
            detail = (completed.stderr or completed.stdout).strip()
            raise ApiVideoQualityError(f"2K30 API upload render failed: {detail}")
        os.replace(temporary, output)
    finally:
        if temporary.exists():
            temporary.unlink()


def atomic_write_yaml(path: Path, document: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            yaml.safe_dump(document, handle, allow_unicode=True, sort_keys=False)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary_name, path)
    finally:
        if os.path.exists(temporary_name):
            os.unlink(temporary_name)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-root", required=True)
    parser.add_argument("--content-id", required=True)
    parser.add_argument("--source", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--receipt", required=True)
    parser.add_argument("--write", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        run_path, run_rel = validate_run_scope(ROOT, args.run_root, args.content_id)
        source = validate_run_owned_path(
            ROOT, run_path, args.source, "API upload source", must_exist=True, file_only=True
        )
        output = validate_run_owned_path(
            ROOT, run_path, args.output, "API upload output", must_exist=False
        )
        receipt = validate_run_owned_path(
            ROOT, run_path, args.receipt, "API upload quality receipt", must_exist=False
        )
        if output.suffix.lower() != ".mp4":
            raise SocialContractError("API upload output must use .mp4")
        if receipt.suffix.lower() not in {".yaml", ".yml"}:
            raise SocialContractError("API upload receipt must use .yaml or .yml")
        if output == receipt or source == receipt:
            raise SocialContractError("source, output, and receipt paths must be distinct")

        source_probe = ffprobe_document(source)
        source_info = source_summary(source_probe)
        if source_info["width"] <= 0 or source_info["height"] <= 0:
            raise ApiVideoQualityError("API upload source has no readable video geometry")
        target_width, target_height = target_geometry(
            source_info["width"], source_info["height"]
        )
        mode = "byte_identical_copy" if source_is_compliant(source) else "high_quality_transcode"

        if not args.write:
            print(
                json.dumps(
                    {
                        "mode": "dry_run",
                        "content_id": args.content_id,
                        "run_root": run_rel,
                        "source": repo_relative(ROOT, source),
                        "output": repo_relative(ROOT, output),
                        "receipt": repo_relative(ROOT, receipt),
                        "transform_mode": mode,
                        "target_geometry": f"{target_width}x{target_height}",
                        "quality_profile": QUALITY_PROFILE,
                        "external_actions": 0,
                    },
                    ensure_ascii=False,
                    indent=2,
                )
            )
            return 0

        if output.exists() and output.resolve() != source.resolve():
            raise SocialContractError("API upload output already exists; choose a new explicit path")
        if receipt.exists():
            raise SocialContractError("API upload receipt already exists; choose a new explicit path")
        if mode == "byte_identical_copy":
            if output.resolve() != source.resolve():
                atomic_copy(source, output)
        else:
            if output.resolve() == source.resolve():
                raise SocialContractError("a transcode may not overwrite its source")
            render_high_quality(source, output, target_width, target_height)

        output_probe = inspect_api_upload_video(output)
        transform = {
            "mode": mode,
            "no_downscale": True,
            "scale_filter": "lanczos",
            "target_fps": "30/1_cfr",
            "video_codec": "libx264",
            "video_preset": "slow",
            "video_crf": 14,
            "pixel_format": "yuv420p",
            "audio_codec": "aac",
            "audio_bit_rate": 320000,
            "audio_sample_rate": 48000,
            "faststart": True,
        }
        document = {
            "schema_version": "idol_api_upload_video.v1",
            "content_id": args.content_id,
            "status": "prepared_local",
            "quality_profile": QUALITY_PROFILE,
            "source": {
                "path": repo_relative(ROOT, source),
                "sha256": sha256_file(source),
                **source_info,
            },
            "transform": transform,
            "output": {
                key: output_probe[key]
                for key in (
                    "path",
                    "sha256",
                    "bytes",
                    "width",
                    "height",
                    "avg_frame_rate",
                    "r_frame_rate",
                    "video_codec",
                    "pixel_format",
                    "audio_codec",
                    "audio_bit_rate",
                    "audio_sample_rate",
                    "duration_seconds",
                )
            },
            "external_action": "not_performed",
        }
        document["output"]["path"] = repo_relative(ROOT, output)
        schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
        jsonschema.Draft202012Validator(schema).validate(document)
        atomic_write_yaml(receipt, document)
        print(
            json.dumps(
                {
                    "mode": "written_local",
                    "output": repo_relative(ROOT, output),
                    "output_sha256": document["output"]["sha256"],
                    "receipt": repo_relative(ROOT, receipt),
                    "receipt_sha256": sha256_file(receipt),
                    "quality_profile": QUALITY_PROFILE,
                    "external_actions": 0,
                },
                ensure_ascii=False,
                indent=2,
            )
        )
        return 0
    except (SocialContractError, ApiVideoQualityError, jsonschema.ValidationError) as exc:
        print(json.dumps({"mode": "blocked", "error": str(exc)}, ensure_ascii=False))
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
