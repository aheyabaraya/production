#!/usr/bin/env python3
"""Validate a local image upscale receipt against exact source/output bytes."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import sys
from pathlib import Path
from typing import Any

import numpy as np
from jsonschema import Draft202012Validator
from PIL import Image


BLACK_THRESHOLD = 3
BLACK_TILE_SIZE = 64


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def resolve_inside(raw: str | Path, root: Path) -> Path:
    path = Path(raw)
    path = path if path.is_absolute() else root / path
    path = path.resolve()
    try:
        path.relative_to(root)
    except ValueError as exc:
        raise ValueError(f"path is outside repository root: {path}") from exc
    return path


def pixel_scan(image: Image.Image) -> tuple[float, int]:
    rgb = np.asarray(image.convert("RGB"), dtype=np.uint8)
    near_black = np.all(rgb <= BLACK_THRESHOLD, axis=2)
    ratio = float(np.count_nonzero(near_black) / near_black.size)
    height, width = near_black.shape
    tiles = 0
    for top in range(0, height, BLACK_TILE_SIZE):
        for left in range(0, width, BLACK_TILE_SIZE):
            tile = near_black[top : min(top + BLACK_TILE_SIZE, height), left : min(left + BLACK_TILE_SIZE, width)]
            if tile.shape == (BLACK_TILE_SIZE, BLACK_TILE_SIZE) and bool(np.all(tile)):
                tiles += 1
    return ratio, tiles


def actual_image(path: Path) -> dict[str, Any]:
    with Image.open(path) as image:
        image.load()
        ratio, tiles = pixel_scan(image)
        return {
            "sha256": sha256_file(path),
            "width": image.width,
            "height": image.height,
            "format": image.format,
            "mode": image.mode,
            "near_black_ratio": ratio,
            "solid_black_tile_count": tiles,
        }


def validate_operation(operation: dict[str, Any], root: Path, errors: list[str], index: int) -> None:
    label = f"operations[{index}]"
    try:
        source_path = resolve_inside(operation["source"]["path"], root)
        output_path = resolve_inside(operation["output"]["path"], root)
    except (KeyError, TypeError, ValueError) as exc:
        errors.append(f"{label}: {exc}")
        return
    if not source_path.is_file():
        errors.append(f"{label}: source is missing")
        return
    if not output_path.is_file():
        errors.append(f"{label}: output is missing")
        return
    try:
        source_actual = actual_image(source_path)
        output_actual = actual_image(output_path)
    except (OSError, ValueError) as exc:
        errors.append(f"{label}: image decode failed: {exc}")
        return

    for side, actual in (("source", source_actual), ("output", output_actual)):
        declared = operation[side]
        if declared.get("sha256") != actual["sha256"]:
            errors.append(f"{label}: {side} SHA-256 is stale")
        dimensions = declared.get("pixel_dimensions", {})
        if dimensions.get("width") != actual["width"] or dimensions.get("height") != actual["height"]:
            errors.append(f"{label}: {side} pixel dimensions are stale")
        if declared.get("format") != actual["format"]:
            errors.append(f"{label}: {side} format is stale")
        if declared.get("mode") != actual["mode"]:
            errors.append(f"{label}: {side} mode is stale")

    if output_actual["format"] != "PNG":
        errors.append(f"{label}: output must be PNG")
    source_long = max(source_actual["width"], source_actual["height"])
    target_long = int(operation.get("target_long_edge", 0))
    expected_long = max(source_long, target_long)
    if max(output_actual["width"], output_actual["height"]) != expected_long:
        errors.append(f"{label}: output long edge does not match no-downscale target")
    scale = expected_long / source_long
    expected_width = source_actual["width"] if scale == 1 else round(source_actual["width"] * scale)
    expected_height = source_actual["height"] if scale == 1 else round(source_actual["height"] * scale)
    if (output_actual["width"], output_actual["height"]) != (expected_width, expected_height):
        errors.append(f"{label}: output dimensions do not preserve the source aspect ratio")
    actual_scale = max(output_actual["width"], output_actual["height"]) / source_long
    if not math.isclose(float(operation.get("scale_factor", 0)), actual_scale, rel_tol=0, abs_tol=1e-12):
        errors.append(f"{label}: scale_factor is stale")

    qc = operation.get("pixel_qc", {})
    source_ratio = source_actual["near_black_ratio"]
    output_ratio = output_actual["near_black_ratio"]
    ratio_delta = output_ratio - source_ratio
    source_tiles = source_actual["solid_black_tile_count"]
    output_tiles = output_actual["solid_black_tile_count"]
    expected_qc = {
        "source_near_black_ratio": source_ratio,
        "output_near_black_ratio": output_ratio,
        "near_black_ratio_delta": ratio_delta,
        "source_solid_black_tile_count": source_tiles,
        "output_solid_black_tile_count": output_tiles,
        "solid_black_tile_count_delta": output_tiles - source_tiles,
    }
    for key, expected in expected_qc.items():
        declared = qc.get(key)
        if isinstance(expected, float):
            if not isinstance(declared, (int, float)) or not math.isclose(float(declared), expected, rel_tol=0, abs_tol=1e-12):
                errors.append(f"{label}: pixel_qc.{key} is stale")
        elif declared != expected:
            errors.append(f"{label}: pixel_qc.{key} is stale")
    aspect_delta = abs(
        (output_actual["width"] / output_actual["height"])
        - (source_actual["width"] / source_actual["height"])
    )
    if not isinstance(qc.get("aspect_ratio_delta"), (int, float)) or not math.isclose(
        float(qc["aspect_ratio_delta"]), aspect_delta, rel_tol=0, abs_tol=1e-12
    ):
        errors.append(f"{label}: pixel_qc.aspect_ratio_delta is stale")
    if ratio_delta > 0.01:
        errors.append(f"{label}: near-black pixel ratio increased by more than 1 percentage point")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("receipt")
    parser.add_argument("--root", default=".")
    parser.add_argument("--source")
    parser.add_argument("--output")
    parser.add_argument(
        "--purpose",
        choices=[
            "member_face_only",
            "post_02b_passed_image",
            "founder_passed_generated_visual",
            "general",
        ],
    )
    parser.add_argument("--minimum-long-edge", type=int)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()

    root = Path(args.root).resolve()
    errors: list[str] = []
    try:
        receipt_path = resolve_inside(args.receipt, root)
        schema_path = Path(__file__).resolve().parent.parent / "schemas" / "local-image-upscale-receipt.schema.json"
        document = json.loads(receipt_path.read_text(encoding="utf-8"))
        schema = json.loads(schema_path.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError, OSError, ValueError) as exc:
        document = {}
        errors.append(str(exc))

    if document:
        validator = Draft202012Validator(schema)
        errors.extend(
            f"schema: {'/'.join(str(part) for part in error.absolute_path) or '<root>'}: {error.message}"
            for error in sorted(validator.iter_errors(document), key=lambda item: list(item.absolute_path))
        )
        operations = document.get("operations", []) if isinstance(document, dict) else []
        for index, operation in enumerate(operations):
            if isinstance(operation, dict):
                validate_operation(operation, root, errors, index)
        if args.source:
            expected_source = resolve_inside(args.source, root)
            matching = [
                operation
                for operation in operations
                if resolve_inside(operation.get("source", {}).get("path", ""), root) == expected_source
            ]
            if len(matching) != 1:
                errors.append("receipt must contain exactly one operation for --source")
            operations = matching
        if args.output:
            expected_output = resolve_inside(args.output, root)
            if len(operations) != 1 or resolve_inside(operations[0].get("output", {}).get("path", ""), root) != expected_output:
                errors.append("receipt output does not match --output")
        if args.purpose and (not operations or any(operation.get("purpose") != args.purpose for operation in operations)):
            errors.append("receipt purpose does not match --purpose")
        if args.minimum_long_edge:
            for operation in operations:
                dimensions = operation.get("output", {}).get("pixel_dimensions", {})
                if max(int(dimensions.get("width", 0)), int(dimensions.get("height", 0))) < args.minimum_long_edge:
                    errors.append(f"receipt output long edge is below {args.minimum_long_edge}")

    result = {"valid": not errors, "schema_version": document.get("schema_version"), "errors": errors}
    if args.json:
        print(json.dumps(result, ensure_ascii=False, indent=2))
    elif errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
    else:
        print("OK: local image upscale receipt matches exact source/output bytes and non-generative policy")
    return 0 if not errors else 1


if __name__ == "__main__":
    raise SystemExit(main())
