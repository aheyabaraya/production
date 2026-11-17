#!/usr/bin/env python3
"""Crop IDOL two-cut beat source sheets using manifest-fixed coordinates."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


MANIFEST_SCHEMA_VERSION = "idol_cut_only_keyframe_generation_manifest.v1"


def json_dump(data: Any) -> str:
    return json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True) + "\n"


def resolve_path(path_value: str | Path) -> Path:
    path = Path(path_value)
    return path if path.is_absolute() else Path.cwd() / path


def load_structured(path: Path) -> Any:
    if path.suffix.lower() == ".json":
        return json.loads(path.read_text(encoding="utf-8"))
    import yaml  # type: ignore

    return yaml.safe_load(path.read_text(encoding="utf-8"))


def load_manifest(path: Path) -> dict[str, Any]:
    manifest = load_structured(path)
    if not isinstance(manifest, dict):
        raise ValueError(f"manifest must be an object: {path}")
    if manifest.get("schema_version") != MANIFEST_SCHEMA_VERSION:
        raise ValueError(f"unsupported manifest schema: {manifest.get('schema_version')}")
    return manifest


def selected_keyframes(manifest: dict[str, Any], section: str) -> list[dict[str, Any]]:
    keyframes = [item for item in manifest.get("keyframes", []) if isinstance(item, dict)]
    if section == "all":
        return keyframes
    return [item for item in keyframes if item.get("section") == section]


def output_path_for_keyframe(manifest: dict[str, Any], keyframe: dict[str, Any]) -> Path:
    return resolve_path(str(manifest["output_root"])) / str(keyframe["output_image"])


def crop_output_path(manifest: dict[str, Any], keyframe: dict[str, Any], region: dict[str, Any]) -> Path:
    template = str(region["crop_output"])
    rendered = template.format(
        keyframe_id=str(keyframe["id"]),
        keyframe_id_lower=str(keyframe["id"]).lower(),
        source_group=str(keyframe.get("source_group", "")),
        source_group_lower=str(keyframe.get("source_group", "")).lower(),
    )
    return resolve_path(str(manifest["output_root"])) / rendered


def parse_region(name: str, value: Any) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ValueError(f"cut region must be an object: {name}")
    required = ("x", "y", "crop_output")
    for field in required:
        if field not in value:
            raise ValueError(f"cut region {name} missing field: {field}")
    width = value.get("width", value.get("w"))
    height = value.get("height", value.get("h"))
    if width is None:
        raise ValueError(f"cut region {name} missing field: width or w")
    if height is None:
        raise ValueError(f"cut region {name} missing field: height or h")
    return {
        "name": name,
        "x": int(value["x"]),
        "y": int(value["y"]),
        "width": int(width),
        "height": int(height),
        "crop_output": str(value["crop_output"]),
    }


def manifest_regions(manifest: dict[str, Any]) -> list[dict[str, Any]]:
    contract = manifest.get("generation_contract") or {}
    regions = contract.get("cut_regions") or {}
    if isinstance(regions, list) and regions:
        return [parse_region(str(value.get("id") or index), value) for index, value in enumerate(regions, start=1)]
    if not isinstance(regions, dict) or not regions:
        raise ValueError("manifest generation_contract.cut_regions is missing")
    return [parse_region(name, value) for name, value in regions.items()]


def crop_manifest(args: argparse.Namespace) -> dict[str, Any]:
    from PIL import Image

    manifest_path = resolve_path(args.manifest)
    manifest = load_manifest(manifest_path)
    keyframes = selected_keyframes(manifest, args.section)
    if not keyframes:
        raise ValueError(f"no keyframes selected for section: {args.section}")
    regions = manifest_regions(manifest)
    fixed_canvas = (manifest.get("generation_contract") or {}).get("fixed_canvas") or {}
    expected_width = int(fixed_canvas.get("width") or 0)
    expected_height = int(fixed_canvas.get("height") or 0)

    cropped: list[dict[str, Any]] = []
    skipped: list[dict[str, Any]] = []
    failed: list[dict[str, Any]] = []
    for keyframe in keyframes:
        sheet_path = output_path_for_keyframe(manifest, keyframe)
        if not sheet_path.exists():
            record = {"keyframe_id": keyframe.get("id", ""), "reason": "sheet_missing", "sheet": str(sheet_path)}
            if args.allow_missing:
                skipped.append(record)
                continue
            failed.append(record)
            continue
        try:
            with Image.open(sheet_path) as image:
                image = image.convert("RGB")
                if expected_width and expected_height and image.size != (expected_width, expected_height):
                    if not args.allow_size_mismatch:
                        failed.append(
                            {
                                "keyframe_id": keyframe.get("id", ""),
                                "reason": "sheet_size_mismatch",
                                "sheet": str(sheet_path),
                                "actual_size": list(image.size),
                                "expected_size": [expected_width, expected_height],
                            }
                        )
                        continue
                for region in regions:
                    box = (
                        region["x"],
                        region["y"],
                        region["x"] + region["width"],
                        region["y"] + region["height"],
                    )
                    if box[2] > image.width or box[3] > image.height:
                        failed.append(
                            {
                                "keyframe_id": keyframe.get("id", ""),
                                "region": region["name"],
                                "reason": "region_outside_sheet",
                                "sheet": str(sheet_path),
                                "box": list(box),
                                "actual_size": list(image.size),
                            }
                        )
                        continue
                    out_path = crop_output_path(manifest, keyframe, region)
                    if out_path.exists() and not args.force:
                        skipped.append(
                            {
                                "keyframe_id": keyframe.get("id", ""),
                                "region": region["name"],
                                "reason": "crop_exists",
                                "crop": str(out_path),
                            }
                        )
                        continue
                    if args.write:
                        out_path.parent.mkdir(parents=True, exist_ok=True)
                        image.crop(box).save(out_path)
                    cropped.append(
                        {
                            "keyframe_id": keyframe.get("id", ""),
                            "region": region["name"],
                            "sheet": str(sheet_path),
                            "crop": str(out_path),
                            "box": list(box),
                            "write": bool(args.write),
                        }
                    )
        except Exception as error:  # noqa: BLE001
            failed.append({"keyframe_id": keyframe.get("id", ""), "reason": str(error), "sheet": str(sheet_path)})

    report = {
        "manifest": str(manifest_path),
        "write": bool(args.write),
        "selected_keyframes": len(keyframes),
        "regions": [region["name"] for region in regions],
        "cropped_count": len(cropped),
        "skipped_count": len(skipped),
        "failed_count": len(failed),
        "cropped": cropped,
        "skipped": skipped,
        "failed": failed,
    }
    if args.report:
        report_path = resolve_path(args.report)
    else:
        report_path = resolve_path(str(manifest["output_root"])) / "crop-report.json"
    if args.write:
        report_path.parent.mkdir(parents=True, exist_ok=True)
        report_path.write_text(json_dump(report), encoding="utf-8")
    report["report_path"] = str(report_path)
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--section", default="all")
    parser.add_argument("--write", action="store_true")
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--allow-missing", action="store_true")
    parser.add_argument("--allow-size-mismatch", action="store_true")
    parser.add_argument("--report", default="")
    args = parser.parse_args()
    try:
        result = crop_manifest(args)
    except Exception as error:  # noqa: BLE001
        print(json_dump({"ok": False, "error": str(error)}), end="")
        return 1
    print(json_dump({"ok": True, "result": result}), end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
