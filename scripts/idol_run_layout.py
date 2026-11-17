#!/usr/bin/env python3
"""Create, validate, or plan a one-time migration for active IDOL runs."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import sys
from typing import Any

import yaml

from lib.idol_run_layout import (
    RUN_MANIFEST_NAME,
    RUN_MANIFEST_VERSION,
    build_run_root,
    parse_run_root,
    validate_run_manifest,
)


ROOT = Path(__file__).resolve().parent.parent
STAGE_REGISTRY = ROOT / "automation/harness-stage-registry.yaml"
TEXT_SUFFIXES = {
    ".md", ".txt", ".yaml", ".yml", ".json", ".jsonl", ".toml", ".rb",
    ".py", ".sh", ".js", ".ts", ".tsx", ".html", ".css", ".csv", ".tsv",
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def stage_lock() -> dict[str, Any]:
    document = yaml.safe_load(STAGE_REGISTRY.read_text(encoding="utf-8"))
    stages = sorted(
        (row for row in document.get("stages", []) if row.get("active") is True),
        key=lambda row: row["order"],
    )
    semantic_rows = [
        {
            key: row.get(key)
            for key in (
                "stage_id",
                "order",
                "code",
                "owner_skill",
                "scope",
                "inputs",
                "founder_gate",
            )
        }
        for row in stages
    ]
    encoded = json.dumps(
        semantic_rows, ensure_ascii=False, sort_keys=True, separators=(",", ":")
    ).encode("utf-8")
    return {
        "stage_registry_path": "automation/harness-stage-registry.yaml",
        "stage_registry_sha256": sha256(STAGE_REGISTRY),
        "stage_sequence_sha256": hashlib.sha256(encoded).hexdigest(),
        "stage_codes": [row["code"] for row in stages],
    }


def init_run(args: argparse.Namespace) -> int:
    relative = build_run_root(args.album_key, args.title_key, args.run_id)
    run_path = ROOT / relative
    manifest_path = run_path / RUN_MANIFEST_NAME
    if run_path.exists() and any(run_path.iterdir()):
        raise ValueError(f"refusing to initialize a non-empty run root: {relative}")
    run_path.mkdir(parents=True, exist_ok=True)
    manifest = {
        "schema_version": RUN_MANIFEST_VERSION,
        "status": "active",
        "album_key": args.album_key,
        "title_key": args.title_key,
        "run_id": args.run_id,
        "content_id": args.content_id,
        "canonical_run_root": relative,
        "created_at": datetime.now(timezone.utc).isoformat(),
        "run_sequence": args.run_sequence,
        "previous_run_root": args.previous_run_root,
        "migrated_from": None,
        "artifact_revision_owner": "git",
        "compatibility_authoring": "forbidden",
        "integrity_policy_version": "idol-artifact-integrity.v1",
        "flow_lock": stage_lock(),
    }
    manifest_path.write_text(
        yaml.safe_dump(manifest, sort_keys=False, allow_unicode=True),
        encoding="utf-8",
    )
    print(relative)
    return 0


def validate_run(args: argparse.Namespace) -> int:
    errors = validate_run_manifest(args.run_root, ROOT)
    result = {
        "valid": not errors,
        "run_root": str(args.run_root),
        "errors": errors,
    }
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if not errors else 1


def text_reference_inventory(source_relative: str) -> tuple[list[str], int, int]:
    files: list[str] = []
    occurrences = 0
    sha_lines = 0
    ignored_roots = {".git", ".runtime", "node_modules"}
    for path in ROOT.rglob("*"):
        if not path.is_file() or any(part in ignored_roots for part in path.parts):
            continue
        if path.suffix.lower() not in TEXT_SUFFIXES:
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        count = text.count(source_relative)
        if count:
            files.append(path.relative_to(ROOT).as_posix())
            occurrences += count
            sha_lines += sum(
                1
                for line in text.splitlines()
                if source_relative in line
                and re.search(r"(?:sha256|value_sha|artifact_sha)", line, re.I)
            )
    return sorted(files), occurrences, sha_lines


def migration_plan(args: argparse.Namespace) -> int:
    source = Path(args.source_run)
    source = source if source.is_absolute() else ROOT / source
    source = source.resolve()
    if not source.is_dir():
        raise ValueError(f"source run is not a directory: {args.source_run}")
    source_relative = source.relative_to(ROOT).as_posix()
    run_id = args.run_id or source.name
    target_relative = build_run_root(args.album_key, args.title_key, run_id)
    target = ROOT / target_relative
    reference_files, occurrences, hash_lines = text_reference_inventory(source_relative)
    files = [path for path in source.rglob("*") if path.is_file()]
    bytes_total = sum(path.stat().st_size for path in files)
    blockers: list[str] = []
    if target.exists():
        blockers.append("target_run_root_already_exists")
    if occurrences:
        blockers.append("path_rewrite_and_reverse_reference_validation_required")
    if hash_lines or any(
        "sha256" in path.name.lower()
        for path in files
        if path.suffix.lower() in {".yaml", ".yml", ".json"}
    ):
        blockers.append("hash_dependency_reprojection_required")
    plan = {
        "schema_version": "idol-run-migration-plan.v1",
        "status": "hold" if blockers else "ready_for_exact_move",
        "source_run_root": source_relative,
        "target_run_root": target_relative,
        "album_key": args.album_key,
        "title_key": args.title_key,
        "run_id": run_id,
        "file_count": len(files),
        "byte_size": bytes_total,
        "reference_file_count": len(reference_files),
        "reference_occurrence_count": occurrences,
        "path_and_hash_same_line_count": hash_lines,
        "reference_files": reference_files,
        "required_checks": [
            "exact_path_rewrite_map",
            "reverse_reference_scan",
            "affected_file_sha256_recompute",
            "source_value_hash_reprojection",
            "all_active_stage_schema_and_validator_checks",
            "current_next_and_title_registry_atomic_switch",
            "source_root_absent_and_target_root_present_after_switch",
        ],
        "blockers": sorted(set(blockers)),
        "automatic_move_performed": False,
    }
    rendered = yaml.safe_dump(plan, sort_keys=False, allow_unicode=True)
    if args.output:
        output = Path(args.output)
        output = output if output.is_absolute() else ROOT / output
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(rendered, encoding="utf-8")
        print(output.relative_to(ROOT).as_posix())
    else:
        print(rendered, end="")
    return 0 if not blockers else 1


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser()
    subparsers = root.add_subparsers(dest="command", required=True)

    init = subparsers.add_parser("init")
    init.add_argument("--album-key", required=True)
    init.add_argument("--title-key", required=True)
    init.add_argument("--run-id", required=True)
    init.add_argument("--content-id", required=True)
    init.add_argument("--run-sequence", type=int, default=1)
    init.add_argument("--previous-run-root")
    init.set_defaults(func=init_run)

    validate = subparsers.add_parser("validate")
    validate.add_argument("run_root")
    validate.set_defaults(func=validate_run)

    plan = subparsers.add_parser("plan-migration")
    plan.add_argument("source_run")
    plan.add_argument("--album-key", required=True)
    plan.add_argument("--title-key", required=True)
    plan.add_argument("--run-id")
    plan.add_argument("--output")
    plan.set_defaults(func=migration_plan)
    return root


def main() -> int:
    args = parser().parse_args()
    try:
        return args.func(args)
    except (ValueError, OSError, yaml.YAMLError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
