#!/usr/bin/env python3
"""Create deterministic, non-generative local image upscales and receipts."""

from __future__ import annotations

import argparse
import hashlib
import json
import platform
import subprocess
import sys
from pathlib import Path
from typing import Any

import numpy as np
import yaml
from PIL import Image, __version__ as PILLOW_VERSION


SCHEMA_VERSION = "idol_local_image_upscale_receipt.v1"
METHOD = "pillow_lanczos_v1"
DEFAULT_TARGET_LONG_EDGE = 3840
BLACK_THRESHOLD = 3
BLACK_TILE_SIZE = 64
RECEIPT_VALIDATOR = Path(__file__).with_name("validate_local_image_upscale_receipt.py")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def resolve_inside(raw: str | Path, root: Path, *, must_exist: bool = False) -> Path:
    path = Path(raw)
    path = path if path.is_absolute() else root / path
    path = path.resolve()
    try:
        path.relative_to(root)
    except ValueError as exc:
        raise ValueError(f"path is outside repository root: {path}") from exc
    if must_exist and not path.is_file():
        raise FileNotFoundError(f"source image is missing: {path}")
    return path


def relative(path: Path, root: Path) -> str:
    return path.relative_to(root).as_posix()


def target_dimensions(width: int, height: int, target_long_edge: int) -> tuple[int, int, str]:
    source_long_edge = max(width, height)
    if source_long_edge >= target_long_edge:
        return width, height, "normalized_png_no_downscale"
    scale = target_long_edge / source_long_edge
    return max(1, round(width * scale)), max(1, round(height * scale)), "lanczos_upscale"


def normalized_mode(image: Image.Image) -> str:
    return "RGBA" if "A" in image.getbands() or "transparency" in image.info else "RGB"


def pixel_scan(image: Image.Image) -> tuple[float, int]:
    rgb = np.asarray(image.convert("RGB"), dtype=np.uint8)
    near_black = np.all(rgb <= BLACK_THRESHOLD, axis=2)
    near_black_ratio = float(np.count_nonzero(near_black) / near_black.size)
    height, width = near_black.shape
    tile_count = 0
    for top in range(0, height, BLACK_TILE_SIZE):
        for left in range(0, width, BLACK_TILE_SIZE):
            tile = near_black[top : min(top + BLACK_TILE_SIZE, height), left : min(left + BLACK_TILE_SIZE, width)]
            if tile.shape == (BLACK_TILE_SIZE, BLACK_TILE_SIZE) and bool(np.all(tile)):
                tile_count += 1
    return near_black_ratio, tile_count


def image_ref(
    path: Path,
    root: Path,
    *,
    width: int,
    height: int,
    image_format: str,
    mode: str,
) -> dict[str, Any]:
    return {
        "path": relative(path, root),
        "sha256": sha256_file(path),
        "pixel_dimensions": {"width": width, "height": height},
        "format": image_format,
        "mode": mode,
    }


def write_json_atomic(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    temporary.replace(path)


def build_receipt(operations: list[dict[str, Any]]) -> dict[str, Any]:
    return {
        "schema_version": SCHEMA_VERSION,
        "status": "complete",
        "policy": {
            "method": METHOD,
            "output_format": "PNG",
            "preserve_aspect_ratio": True,
            "crop": False,
            "sharpening": False,
            "generative_enhancement": False,
            "no_downscale": True,
        },
        "runtime": {"python": platform.python_version(), "pillow": PILLOW_VERSION},
        "operations": operations,
    }


def upscale_one(
    source: Path,
    output: Path,
    root: Path,
    *,
    purpose: str,
    target_long_edge: int,
    replace: bool,
) -> dict[str, Any]:
    if source == output:
        raise ValueError("source and output paths must differ")
    if output.suffix.lower() != ".png":
        raise ValueError(f"output must use .png: {output}")
    if output.exists() and not replace:
        raise FileExistsError(f"output already exists; pass --replace to rewrite: {output}")

    with Image.open(source) as opened:
        opened.load()
        source_format = (opened.format or source.suffix.lstrip(".") or "UNKNOWN").upper()
        source_original_mode = opened.mode
        source_width, source_height = opened.size
        source_mode = normalized_mode(opened)
        source_image = opened.convert(source_mode)
        source_ratio, source_tiles = pixel_scan(source_image)
        width, height, action = target_dimensions(source_image.width, source_image.height, target_long_edge)
        if action == "lanczos_upscale":
            output_image = source_image.resize((width, height), Image.Resampling.LANCZOS)
        else:
            output_image = source_image.copy()
        save_kwargs: dict[str, Any] = {"format": "PNG", "compress_level": 6, "optimize": False}
        if opened.info.get("icc_profile"):
            save_kwargs["icc_profile"] = opened.info["icc_profile"]
        if opened.info.get("dpi"):
            save_kwargs["dpi"] = opened.info["dpi"]

        output.parent.mkdir(parents=True, exist_ok=True)
        temporary = output.with_name(f".{output.name}.tmp.png")
        output_image.save(temporary, **save_kwargs)
        temporary.replace(output)

        with Image.open(output) as verified:
            verified.load()
            if verified.format != "PNG" or verified.size != (width, height):
                raise ValueError(f"written output failed PNG/dimension verification: {output}")
            output_ratio, output_tiles = pixel_scan(verified)
            source_ref = image_ref(
                source,
                root,
                width=source_width,
                height=source_height,
                image_format=source_format,
                mode=source_original_mode,
            )
            output_ref = image_ref(
                output,
                root,
                width=verified.width,
                height=verified.height,
                image_format="PNG",
                mode=verified.mode,
            )

    aspect_delta = abs((width / height) - (source_ref["pixel_dimensions"]["width"] / source_ref["pixel_dimensions"]["height"]))
    return {
        "purpose": purpose,
        "action": action,
        "target_long_edge": target_long_edge,
        "scale_factor": max(width, height) / max(
            source_ref["pixel_dimensions"]["width"], source_ref["pixel_dimensions"]["height"]
        ),
        "source": source_ref,
        "output": output_ref,
        "pixel_qc": {
            "decode_pass": True,
            "aspect_ratio_delta": aspect_delta,
            "source_near_black_ratio": source_ratio,
            "output_near_black_ratio": output_ratio,
            "near_black_ratio_delta": output_ratio - source_ratio,
            "source_solid_black_tile_count": source_tiles,
            "output_solid_black_tile_count": output_tiles,
            "solid_black_tile_count_delta": output_tiles - source_tiles,
        },
    }


def parse_item(value: str, root: Path) -> tuple[Path, Path]:
    if "=" not in value:
        raise ValueError("--item must be SOURCE=OUTPUT")
    source_raw, output_raw = value.split("=", 1)
    return resolve_inside(source_raw, root, must_exist=True), resolve_inside(output_raw, root)


def run_images(args: argparse.Namespace) -> dict[str, Any]:
    root = Path(args.root).resolve()
    receipt = resolve_inside(args.receipt, root)
    pairs = [parse_item(item, root) for item in args.item]
    outputs = [output for _, output in pairs]
    if len(set(outputs)) != len(outputs):
        raise ValueError("duplicate output paths are not allowed")
    operations = [
        upscale_one(
            source,
            output,
            root,
            purpose=args.purpose,
            target_long_edge=args.target_long_edge,
            replace=args.replace,
        )
        for source, output in pairs
    ]
    document = build_receipt(operations)
    write_json_atomic(receipt, document)
    return {"status": "complete", "receipt": relative(receipt, root), "operation_count": len(operations)}


def load_review(path: Path) -> dict[str, Any]:
    value = yaml.safe_load(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise TypeError("generated Branch-Cut review must be an object")
    return value


def review_output_path(source: Path, packet_id: str, root: Path, explicit_dir: str | None) -> Path:
    if explicit_dir:
        output_dir = resolve_inside(explicit_dir, root)
    else:
        relative_source = source.relative_to(root)
        try:
            generation_index = relative_source.parts.index("generations")
        except ValueError as exc:
            raise ValueError(f"reviewed image is not under a run generations folder: {source}") from exc
        run_root = root.joinpath(*relative_source.parts[:generation_index])
        output_dir = run_root / "generations" / "upscaled"
    return output_dir / f"{packet_id}.png"


def reusable_passed_operation(
    source: Path,
    output: Path,
    sidecar: Path,
    root: Path,
    *,
    purpose: str,
    target_long_edge: int,
    replace: bool,
) -> dict[str, Any] | None:
    if replace:
        return None
    if not output.exists() and not sidecar.exists():
        return None
    if not output.is_file() or not sidecar.is_file():
        raise FileExistsError(
            f"existing passed-review derivative is incomplete; use --replace only after review: {output}"
        )
    validation = subprocess.run(
        [
            sys.executable,
            str(RECEIPT_VALIDATOR),
            str(sidecar),
            "--root",
            str(root),
            "--source",
            str(source),
            "--output",
            str(output),
            "--purpose",
            purpose,
            "--minimum-long-edge",
            str(target_long_edge),
            "--json",
        ],
        cwd=root,
        capture_output=True,
        text=True,
        check=False,
    )
    if validation.returncode != 0:
        detail = (validation.stderr or validation.stdout).strip()
        raise FileExistsError(
            "existing passed-review derivative failed exact receipt validation; "
            f"use --replace only after review: {output}: {detail}"
        )
    receipt = json.loads(sidecar.read_text(encoding="utf-8"))
    matches = [
        operation
        for operation in receipt.get("operations", [])
        if resolve_inside(operation.get("source", {}).get("path", ""), root) == source
        and resolve_inside(operation.get("output", {}).get("path", ""), root) == output
    ]
    if len(matches) != 1:
        raise ValueError(f"validated receipt does not contain one exact passed-review operation: {sidecar}")
    return matches[0]


def run_passed_review(args: argparse.Namespace) -> dict[str, Any]:
    root = Path(args.root).resolve()
    review_path = resolve_inside(args.review, root, must_exist=True)
    review = load_review(review_path)
    if review.get("schema_version") != "idol_generated_branch_cut_review.v4":
        raise ValueError("only idol_generated_branch_cut_review.v4 is supported")
    if review.get("status") != "passed":
        raise ValueError("review status must be passed before local upscaling")
    rows = review.get("branch_cut_reviews")
    if not isinstance(rows, list) or not rows:
        raise ValueError("review has no branch_cut_reviews")

    prepared: list[tuple[dict[str, Any], Path, Path, Path]] = []
    for row in rows:
        if not isinstance(row, dict) or row.get("decision") != "pass":
            raise ValueError("every branch_cut_review decision must be pass")
        packet_id = str(row.get("packet_id") or "")
        source = resolve_inside(str(row.get("image_path") or ""), root, must_exist=True)
        if sha256_file(source) != row.get("image_sha256"):
            raise ValueError(f"{packet_id}: reviewed image SHA-256 is stale")
        output = review_output_path(source, packet_id, root, args.output_dir)
        sidecar = Path(f"{source}.upscale.json")
        prepared.append((row, source, output, sidecar))

    results = []
    for row, source, output, sidecar in prepared:
        operation = reusable_passed_operation(
            source,
            output,
            sidecar,
            root,
            purpose="post_02b_passed_image",
            target_long_edge=args.target_long_edge,
            replace=args.replace,
        )
        reused = operation is not None
        if operation is None:
            operation = upscale_one(
                source,
                output,
                root,
                purpose="post_02b_passed_image",
                target_long_edge=args.target_long_edge,
                replace=args.replace,
            )
            write_json_atomic(sidecar, build_receipt([operation]))
        results.append(
            {
                "packet_id": row["packet_id"],
                "source": relative(source, root),
                "output": relative(output, root),
                "receipt": relative(sidecar, root),
                "reused": reused,
            }
        )
    return {"status": "complete", "review": relative(review_path, root), "results": results}


def run_passed_visuals(args: argparse.Namespace) -> dict[str, Any]:
    root = Path(args.root).resolve()
    pairs = [parse_item(item, root) for item in args.item]
    outputs = [output for _, output in pairs]
    if len(set(outputs)) != len(outputs):
        raise ValueError("duplicate output paths are not allowed")

    prepared = []
    for source, output in pairs:
        sidecar = Path(f"{source}.upscale.json")
        operation = reusable_passed_operation(
            source,
            output,
            sidecar,
            root,
            purpose="founder_passed_generated_visual",
            target_long_edge=args.target_long_edge,
            replace=args.replace,
        )
        prepared.append((source, output, sidecar, operation))

    results = []
    for source, output, sidecar, operation in prepared:
        reused = operation is not None
        if operation is None:
            operation = upscale_one(
                source,
                output,
                root,
                purpose="founder_passed_generated_visual",
                target_long_edge=args.target_long_edge,
                replace=args.replace,
            )
            write_json_atomic(sidecar, build_receipt([operation]))
        results.append(
            {
                "source": relative(source, root),
                "output": relative(output, root),
                "receipt": relative(sidecar, root),
                "reused": reused,
            }
        )
    return {"status": "complete", "results": results}


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    images = subparsers.add_parser("images", help="upscale one or more explicit source/output pairs")
    images.add_argument("--root", default=".")
    images.add_argument("--receipt", required=True)
    images.add_argument("--item", action="append", required=True, help="SOURCE=OUTPUT; repeat as needed")
    images.add_argument(
        "--purpose",
        choices=["member_face_only", "founder_passed_generated_visual", "general"],
        default="general",
    )
    images.add_argument("--target-long-edge", type=int, default=DEFAULT_TARGET_LONG_EDGE)
    images.add_argument("--replace", action="store_true")
    images.set_defaults(handler=run_images)

    review = subparsers.add_parser("passed-review", help="upscale every passed image in a generated review")
    review.add_argument("--root", default=".")
    review.add_argument("--review", required=True)
    review.add_argument("--output-dir")
    review.add_argument("--target-long-edge", type=int, default=DEFAULT_TARGET_LONG_EDGE)
    review.add_argument("--replace", action="store_true")
    review.set_defaults(handler=run_passed_review)

    visuals = subparsers.add_parser(
        "passed-visuals",
        help="upscale exact generated image outputs selected by explicit Founder PASS cards",
    )
    visuals.add_argument("--root", default=".")
    visuals.add_argument("--item", action="append", required=True, help="SOURCE=OUTPUT; repeat as needed")
    visuals.add_argument("--target-long-edge", type=int, default=DEFAULT_TARGET_LONG_EDGE)
    visuals.add_argument("--replace", action="store_true")
    visuals.set_defaults(handler=run_passed_visuals)
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    if args.target_long_edge < 64:
        parser.error("--target-long-edge must be at least 64")
    try:
        result = args.handler(args)
    except (FileExistsError, FileNotFoundError, OSError, TypeError, ValueError, yaml.YAMLError) as exc:
        print(json.dumps({"status": "failed", "error": str(exc)}, ensure_ascii=False, indent=2))
        return 1
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
