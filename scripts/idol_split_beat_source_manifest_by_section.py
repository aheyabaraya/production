#!/usr/bin/env python3
"""Split a routed beat source imagegen manifest into section manifests."""

from __future__ import annotations

import argparse
import copy
import json
import re
from pathlib import Path
from typing import Any


def json_dump(data: Any) -> str:
    return json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True) + "\n"


def load_yaml(path: Path) -> Any:
    import yaml  # type: ignore

    return yaml.safe_load(path.read_text(encoding="utf-8"))


def write_yaml(path: Path, data: Any) -> None:
    import yaml  # type: ignore

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        yaml.safe_dump(data, allow_unicode=True, sort_keys=False, width=120),
        encoding="utf-8",
    )


def resolve(path_text: str | Path) -> Path:
    path = Path(path_text)
    return path if path.is_absolute() else Path.cwd() / path


def section_from_keyframe(keyframe: dict[str, Any]) -> str:
    timeline = str(keyframe.get("timeline") or "")
    match = re.search(r"/\s*(S\d+)\b", timeline)
    if match:
        return match.group(1)
    beat_id = str(keyframe.get("beat_id") or "")
    match = re.search(r"\b(S\d+)\b", beat_id)
    return match.group(1) if match else "SXX"


def route_label(manifest: dict[str, Any], fallback: str) -> str:
    mode = ((manifest.get("generation_contract") or {}).get("prompt_header_mode") or "").strip()
    if mode == "two_frame_sheet":
        return "two-cut-solo"
    if mode == "single_frame_16x9":
        return "single-cut-multi"
    return fallback


def split_manifest(args: argparse.Namespace) -> dict[str, Any]:
    manifest_path = resolve(args.manifest)
    manifest = load_yaml(manifest_path)
    if not isinstance(manifest, dict):
        raise ValueError(f"manifest must be an object: {manifest_path}")
    keyframes = manifest.get("keyframes") or []
    if not isinstance(keyframes, list) or not keyframes:
        raise ValueError(f"manifest keyframes are missing: {manifest_path}")

    route = args.route_label or route_label(manifest, manifest_path.stem)
    out_dir = resolve(args.out_dir)
    written: list[dict[str, Any]] = []
    buckets: dict[str, list[dict[str, Any]]] = {}
    for keyframe in keyframes:
        section = section_from_keyframe(keyframe)
        buckets.setdefault(section, []).append(keyframe)

    for section, section_keyframes in sorted(buckets.items()):
        section_manifest = copy.deepcopy(manifest)
        section_manifest["status"] = "ready_for_generation"
        section_manifest["section_shard"] = {
            "section": section,
            "route": route,
            "source_manifest": str(manifest_path),
            "keyframe_count": len(section_keyframes),
            "submission_rule": "submit section shards one at a time; do not mix solo two-cut and multi-member single-cut routes in the same Batch API file",
        }
        scope = section_manifest.get("scope") if isinstance(section_manifest.get("scope"), list) else []
        section_manifest["scope"] = [f"{route} {section} beat source API submission shard"] + scope
        section_manifest["keyframes"] = copy.deepcopy(section_keyframes)
        contract = section_manifest.get("generation_contract") or {}
        if isinstance(contract, dict):
            contract["selected_generation_count"] = len(section_keyframes)
            contract["section_submission_rule"] = "section shard generated from routed beat source manifest"
            section_manifest["generation_contract"] = contract
        section_manifest["member_face_refs"] = {
            code: path
            for code, path in (manifest.get("member_face_refs") or {}).items()
            if code in {member for frame in section_keyframes for member in (frame.get("api_face_refs") or [])}
        }
        out_path = out_dir / f"{route}-{section.lower()}-generation-manifest.yaml"
        if out_path.exists() and not args.force:
            raise FileExistsError(f"manifest exists: {out_path}")
        if args.write:
            write_yaml(out_path, section_manifest)
        written.append(
            {
                "section": section,
                "route": route,
                "manifest": str(out_path),
                "keyframe_count": len(section_keyframes),
                "first_keyframe": section_keyframes[0].get("id", ""),
                "last_keyframe": section_keyframes[-1].get("id", ""),
            }
        )
    return {"source_manifest": str(manifest_path), "route": route, "write": bool(args.write), "sections": written}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--out-dir", required=True)
    parser.add_argument("--route-label", default="")
    parser.add_argument("--write", action="store_true")
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args()
    print(
        json_dump(
            {
                "ok": False,
                "error": (
                    "legacy beat-source manifest sharding is retired; "
                    "active generation is already section-scoped through idol_image_generation_request.v8"
                ),
            }
        ),
        end="",
    )
    return 1
    try:
        result = split_manifest(args)
    except Exception as error:  # noqa: BLE001
        print(json_dump({"ok": False, "error": str(error)}), end="")
        return 1
    print(json_dump({"ok": True, "result": result}), end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
