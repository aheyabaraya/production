#!/usr/bin/env python3
"""Preserve one approved public Pinterest still without authoring creative truth."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import sys
import tempfile
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from PIL import Image, UnidentifiedImageError


ROOT = Path(__file__).resolve().parents[1]
PIN_HOSTS = {"pinterest.com", "www.pinterest.com", "pin.it"}
ALLOWED_OUTPUT_PREFIXES = (
    "runs/",
    "source-materials/image-sources/by-source/",
)
SOURCE_KINDS = {"main_reference", "supporting_visual_reference"}
ACCESS_METHODS = {
    "public_no_account_download",
    "public_no_account_screenshot",
    "existing_local_file",
}
MAX_DOWNLOAD_BYTES = 32 * 1024 * 1024


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def public_pin_url(value: str) -> str:
    parsed = urllib.parse.urlparse(value)
    host = (parsed.hostname or "").lower()
    if parsed.scheme != "https" or host not in PIN_HOSTS:
        raise ValueError("pin URL must be a public https Pinterest or pin.it URL")
    if parsed.username or parsed.password:
        raise ValueError("pin URL must not contain credentials")
    return value


def repo_output_dir(value: str) -> Path:
    raw = Path(value)
    if raw.is_absolute():
        raise ValueError("output directory must be repository-relative")
    normalized = raw.as_posix().lstrip("./")
    if not any(normalized.startswith(prefix) for prefix in ALLOWED_OUTPUT_PREFIXES):
        raise ValueError("output directory must stay in run reference-intake or reusable image-source storage")
    path = (ROOT / raw).resolve()
    try:
        path.relative_to(ROOT)
    except ValueError as exc:
        raise ValueError("output directory escapes repository") from exc
    return path


def download_public_image(url: str, pin_url: str, destination: Path) -> None:
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password:
        raise ValueError("image URL must be a public credential-free https URL")
    request = urllib.request.Request(
        url,
        headers={
            "User-Agent": "Mozilla/5.0 IDOL-Public-Still-Capture/1.0",
            "Referer": pin_url,
            "Accept": "image/avif,image/webp,image/png,image/jpeg,image/*;q=0.8",
        },
    )
    with urllib.request.urlopen(request, timeout=30) as response, destination.open("wb") as output:
        content_type = str(response.headers.get("Content-Type", "")).lower()
        if not content_type.startswith("image/"):
            raise ValueError(f"image URL returned non-image content: {content_type or 'unknown'}")
        total = 0
        while True:
            chunk = response.read(1024 * 1024)
            if not chunk:
                break
            total += len(chunk)
            if total > MAX_DOWNLOAD_BYTES:
                raise ValueError("Pinterest still exceeds the 32 MB capture limit")
            output.write(chunk)
    if destination.stat().st_size == 0:
        raise ValueError("Pinterest still download returned empty bytes")


def inspect_image(path: Path, min_short_edge: int) -> dict[str, Any]:
    try:
        with Image.open(path) as image:
            image.load()
            width, height = image.size
            image_format = str(image.format or "").upper()
    except (UnidentifiedImageError, OSError) as exc:
        raise ValueError("captured bytes are not a readable still image") from exc
    if image_format not in {"JPEG", "PNG", "WEBP", "TIFF"}:
        raise ValueError(f"unsupported still-image format: {image_format or 'unknown'}")
    if min(width, height) < min_short_edge:
        raise ValueError(
            f"captured still short edge is {min(width, height)}px; minimum is {min_short_edge}px"
        )
    suffix_by_format = {"JPEG": ".jpg", "PNG": ".png", "WEBP": ".webp", "TIFF": ".tiff"}
    mime_by_format = {"JPEG": "image/jpeg", "PNG": "image/png", "WEBP": "image/webp", "TIFF": "image/tiff"}
    return {
        "width": width,
        "height": height,
        "format": image_format,
        "suffix": suffix_by_format[image_format],
        "mime_type": mime_by_format[image_format],
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pin-url", required=True)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--image-url")
    source.add_argument("--source-file")
    parser.add_argument("--candidate-id", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--capture-basis", required=True)
    parser.add_argument("--access-method", required=True, choices=sorted(ACCESS_METHODS))
    parser.add_argument("--proposed-source-kind", required=True, choices=sorted(SOURCE_KINDS))
    parser.add_argument("--role", required=True)
    parser.add_argument("--min-short-edge", type=int, default=720)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if os.environ.get("IDOL_PINTEREST_CAPTURE_APPROVED") != "1":
        raise ValueError("set IDOL_PINTEREST_CAPTURE_APPROVED=1 for this exact current-task capture")
    if not args.capture_basis.strip() or not args.role.strip():
        raise ValueError("capture basis and role must be nonempty")
    if args.min_short_edge < 720:
        raise ValueError("Pinterest still minimum short edge cannot be lower than 720px")
    if not args.candidate_id.replace("-", "").replace("_", "").isalnum():
        raise ValueError("candidate id must contain only letters, digits, hyphens, or underscores")

    pin_url = public_pin_url(args.pin_url)
    output_dir = repo_output_dir(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    temporary_fd, temporary_name = tempfile.mkstemp(prefix="idol-pinterest-", suffix=".image", dir="/tmp")
    os.close(temporary_fd)
    temporary = Path(temporary_name)
    try:
        if args.image_url:
            if args.access_method != "public_no_account_download":
                raise ValueError("--image-url requires public_no_account_download")
            download_public_image(args.image_url, pin_url, temporary)
            source_locator = args.image_url
        else:
            source_path = Path(args.source_file).expanduser().resolve()
            if not source_path.is_file() or source_path.is_symlink():
                raise ValueError("source file is missing or symlinked")
            shutil.copyfile(source_path, temporary)
            source_locator = str(source_path)

        image = inspect_image(temporary, args.min_short_edge)
        destination = output_dir / f"{args.candidate_id}{image['suffix']}"
        receipt_path = output_dir / f"{args.candidate_id}.capture.json"
        if destination.exists() or receipt_path.exists():
            raise FileExistsError("capture output already exists; use a new candidate id")
        shutil.copyfile(temporary, destination)
        relative = destination.relative_to(ROOT).as_posix()
        receipt = {
            "mechanical_only": True,
            "tool": "idol_pinterest_public_capture.py",
            "candidate_id": args.candidate_id,
            "pin_url": pin_url,
            "source_locator": source_locator,
            "access_method": args.access_method,
            "capture_basis": args.capture_basis,
            "captured_at": datetime.now(timezone.utc).isoformat(),
            "proposed_source_kind": args.proposed_source_kind,
            "role": args.role,
            "image": {
                "path": relative,
                "sha256": sha256(destination),
                "size_bytes": destination.stat().st_size,
                "mime_type": image["mime_type"],
                "width": image["width"],
                "height": image["height"],
                "minimum_short_edge": args.min_short_edge,
            },
            "creative_selection_or_attachment_approved": False,
        }
        receipt_path.write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(json.dumps({"image": receipt["image"], "receipt": receipt_path.relative_to(ROOT).as_posix()}, ensure_ascii=False))
        return 0
    finally:
        temporary.unlink(missing_ok=True)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (ValueError, FileExistsError) as error:
        print(f"Pinterest capture held: {error}", file=sys.stderr)
        raise SystemExit(2)
