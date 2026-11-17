#!/usr/bin/env python3
"""Atomically close one observed public post into analytics and Loom Signal Deck.

This helper performs local, deterministic projection only. It never uploads,
publishes, schedules, calls a platform API, deploys the web app, or chooses a
member/track/CF/visual. Those mappings must already be authored in the exact
run-owned closeout record supplied with ``--closeout``.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
import re
import sys
import tempfile
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, urlparse

import yaml  # type: ignore
from jsonschema import Draft202012Validator  # type: ignore

import idol_title_output_registry as title_registry
from lib.idol_post05_trace import (
    RELEASE_PRODUCTION_TRACE_TRIGGER_FIELDS,
    RELEASE_PRODUCTION_TRACE_FIELDS,
    RELEASE_PROVENANCE_VERSION,
    canonical_object_sha256,
    normalize_production_graph_trace,
)
from lib.idol_social_release_contracts import (
    SocialContractError,
    package_deliverable_manifest,
    validate_package_contract,
)


DEFAULT_SCHEMA = "schemas/signal-deck-publication.schema.json"
DEFAULT_POSTS = "analytics/records/platform-posts.jsonl"
DEFAULT_METRICS = "analytics/records/platform-metrics.jsonl"
DEFAULT_PUBLICATIONS = "web/data/signalDeckPublications.json"


class CloseoutError(ValueError):
    pass


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def repo_path(root: Path, value: str | Path) -> Path:
    raw = Path(value)
    resolved = raw.resolve() if raw.is_absolute() else (root / raw).resolve()
    try:
        resolved.relative_to(root)
    except ValueError as exc:
        raise CloseoutError(f"path escapes repository root: {value}") from exc
    return resolved


def relative(root: Path, path: Path) -> str:
    return path.resolve().relative_to(root).as_posix()


def load_json(path: Path) -> dict[str, Any]:
    if not path.is_file():
        raise CloseoutError(f"JSON file is missing: {path}")
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise CloseoutError(f"JSON root must be an object: {path}")
    return value


def load_jsonl(path: Path) -> list[dict[str, Any]]:
    if not path.is_file():
        raise CloseoutError(f"JSONL file is missing: {path}")
    rows: list[dict[str, Any]] = []
    for line_no, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip():
            continue
        value = json.loads(line)
        if not isinstance(value, dict):
            raise CloseoutError(f"{path}:{line_no}: row must be an object")
        rows.append(value)
    return rows


def dump_json(value: dict[str, Any]) -> bytes:
    return (json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode("utf-8")


def dump_jsonl(rows: list[dict[str, Any]]) -> bytes:
    return (
        "\n".join(json.dumps(row, ensure_ascii=False) for row in rows) + "\n"
    ).encode("utf-8")


def dump_yaml(value: dict[str, Any]) -> bytes:
    return yaml.safe_dump(value, allow_unicode=True, sort_keys=False).encode("utf-8")


def validate_against_def(schema: dict[str, Any], def_name: str, value: Any) -> None:
    wrapper = {
        "$schema": schema.get("$schema"),
        "$defs": schema.get("$defs", {}),
        "$ref": f"#/$defs/{def_name}",
    }
    errors = sorted(Draft202012Validator(wrapper).iter_errors(value), key=lambda error: list(error.path))
    if errors:
        messages = []
        for error in errors:
            location = ".".join(str(part) for part in error.absolute_path) or "$"
            messages.append(f"{location}: {error.message}")
        raise CloseoutError(f"{def_name} schema validation failed: {'; '.join(messages)}")


def validate_document(schema: dict[str, Any], value: Any, label: str) -> None:
    errors = sorted(Draft202012Validator(schema).iter_errors(value), key=lambda error: list(error.path))
    if errors:
        messages = []
        for error in errors:
            location = ".".join(str(part) for part in error.absolute_path) or "$"
            messages.append(f"{location}: {error.message}")
        raise CloseoutError(f"{label} schema validation failed: {'; '.join(messages)}")


def parse_published_at(value: str) -> datetime:
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise CloseoutError("published_at must be ISO-8601") from exc
    if parsed.tzinfo is None or parsed.utcoffset() is None:
        raise CloseoutError("published_at must include an explicit timezone")
    return parsed


def extract_platform_id(platform: str, published_url: str) -> str:
    parsed = urlparse(published_url)
    host = (parsed.hostname or "").lower()
    path = parsed.path.rstrip("/")

    if parsed.scheme != "https":
        raise CloseoutError("published_url must use HTTPS")

    if platform == "tiktok":
        if host not in {"tiktok.com", "www.tiktok.com", "m.tiktok.com"}:
            raise CloseoutError("TikTok published_url must use tiktok.com")
        match = re.search(r"/video/(\d+)$", path)
        if not match:
            raise CloseoutError("TikTok URL must expose the public numeric video id")
        return match.group(1)

    if platform in {"youtube", "youtube_shorts"}:
        if host == "youtu.be":
            video_id = path.lstrip("/").split("/")[0]
        elif host in {"youtube.com", "www.youtube.com", "m.youtube.com"}:
            shorts = re.search(r"/shorts/([A-Za-z0-9_-]{6,})$", path)
            video_id = shorts.group(1) if shorts else parse_qs(parsed.query).get("v", [""])[0]
        else:
            raise CloseoutError("YouTube published_url must use youtube.com or youtu.be")
        if not re.fullmatch(r"[A-Za-z0-9_-]{6,}", video_id or ""):
            raise CloseoutError("YouTube URL must expose a valid video id")
        return video_id

    if platform == "instagram_reels":
        if host not in {"instagram.com", "www.instagram.com"}:
            raise CloseoutError("Instagram published_url must use instagram.com")
        match = re.search(r"/reels?/([A-Za-z0-9_-]+)$", path)
        if not match:
            raise CloseoutError("Instagram URL must expose the public Reel id")
        return match.group(1)

    raise CloseoutError(f"unsupported Signal Deck embed platform: {platform}")


def embed_url(platform: str, platform_post_id: str) -> str:
    if platform in {"youtube", "youtube_shorts"}:
        return f"https://www.youtube.com/embed/{platform_post_id}?playsinline=1&rel=0"
    if platform == "tiktok":
        return (
            f"https://www.tiktok.com/player/v1/{platform_post_id}"
            "?music_info=0&description=0&controls=0&progress_bar=0&play_button=0"
            "&volume_control=0&fullscreen_button=0&timestamp=0&closed_caption=0"
            "&native_context_menu=0&autoplay=0&loop=0&rel=0"
        )
    if platform == "instagram_reels":
        return f"https://www.instagram.com/reel/{platform_post_id}/embed"
    raise CloseoutError(f"unsupported Signal Deck embed platform: {platform}")


def exact_row(rows: list[dict[str, Any]], post_id: str, label: str) -> tuple[int, dict[str, Any]]:
    matches = [(index, row) for index, row in enumerate(rows) if row.get("post_id") == post_id]
    if len(matches) != 1:
        raise CloseoutError(f"{label} must contain exactly one row for post_id {post_id}; found {len(matches)}")
    return matches[0]


def require_queue_evidence(row: dict[str, Any], label: str) -> None:
    caption = row.get("caption") or row.get("caption_or_description") or row.get("description")
    required = {
        "caption": caption,
        "tracking_code": row.get("tracking_code"),
        "asset_or_clip": row.get("asset_or_clip"),
    }
    missing = [name for name, value in required.items() if not value]
    if missing:
        raise CloseoutError(f"{label} is missing public-closeout evidence: {', '.join(missing)}")


def validate_release_production_trace(
    *,
    root: Path,
    run_root: Path,
    content_id: str,
    queue_row: dict[str, Any],
    ledger_row: dict[str, Any],
    queue_asset: Path,
    queue_asset_sha256: str,
) -> dict[str, Any]:
    """Revalidate and preserve an optional v2 05 -> 04 production trace.

    Legacy/non-05 posts may omit it. Once any trace field is present, the exact
    complete set is mandatory and may only be copied into analytics evidence.
    """

    if not any(field in queue_row for field in RELEASE_PRODUCTION_TRACE_TRIGGER_FIELDS):
        return {}
    missing = [field for field in RELEASE_PRODUCTION_TRACE_FIELDS if not queue_row.get(field)]
    if missing:
        raise CloseoutError(
            "run queue has an incomplete release production trace: " + ", ".join(missing)
        )
    if queue_row["release_provenance_version"] != RELEASE_PROVENANCE_VERSION:
        raise CloseoutError("run queue release_provenance_version is not active")
    for field in RELEASE_PRODUCTION_TRACE_FIELDS:
        if field in ledger_row and ledger_row.get(field) != queue_row.get(field):
            raise CloseoutError(
                f"run queue and global ledger disagree on release production trace field {field}"
            )

    package_path = repo_path(root, str(queue_row["release_package_contract"]))
    if package_path != (run_root / "05-package.yaml").resolve() or not package_path.is_file():
        raise CloseoutError("release_package_contract must be the readable run-root 05-package.yaml")
    if sha256_file(package_path) != str(queue_row["release_package_contract_sha256"]):
        raise CloseoutError("release_package_contract_sha256 is stale or mismatched")
    try:
        _package_path, package, deliverables = validate_package_contract(
            repo_root=root,
            run_path=run_root,
            content_id=content_id,
            package_contract=package_path,
            allow_closed=True,
            require_final_lineage=False,
        )
        deliverable_manifest = package_deliverable_manifest(
            repo_root=root,
            run_path=run_root,
            document=package,
            deliverables=deliverables,
        )
    except SocialContractError as exc:
        raise CloseoutError(f"release package validation failed: {exc}") from exc
    trace = package.get("production_graph_trace")
    if not isinstance(trace, dict):
        raise CloseoutError("release package has no production_graph_trace")

    source_map = trace.get("source_edit_map") or {}
    source_recipe = trace.get("source_edit_recipe") or {}
    for label, source in (("source_edit_map", source_map), ("source_edit_recipe", source_recipe)):
        if not isinstance(source, dict):
            raise CloseoutError(f"production_graph_trace.{label} must be an object")
        source_path = repo_path(root, str(source.get("path") or ""))
        try:
            source_path.relative_to(run_root)
        except ValueError as exc:
            raise CloseoutError(f"production_graph_trace.{label} must stay inside the run") from exc
        if not source_path.is_file() or sha256_file(source_path) != str(source.get("sha256") or ""):
            raise CloseoutError(f"production_graph_trace.{label} bytes are stale or missing")
    if repo_path(root, str(source_map.get("path") or "")) != (run_root / "04-edit-map.yaml").resolve():
        raise CloseoutError("production_graph_trace.source_edit_map is not the run-root 04-edit-map.yaml")

    bindings = trace.get("deliverable_bindings") or []
    if not isinstance(bindings, list):
        raise CloseoutError("production_graph_trace.deliverable_bindings must be an array")
    binding_by_output = {
        str(binding.get("output_id") or ""): binding
        for binding in bindings
        if isinstance(binding, dict) and binding.get("output_id")
    }
    output_id = str(queue_row["release_package_output_id"])
    binding = binding_by_output.get(output_id)
    if binding is None:
        raise CloseoutError("release_package_output_id is absent from production_graph_trace")
    expected_arrays = {
        "release_edit_segment_ids": list(binding.get("edit_segment_ids") or []),
        "release_screen_progression_node_ids": sorted(
            binding.get("screen_progression_node_ids") or []
        ),
        "release_section_ids": sorted(binding.get("section_ids") or []),
    }
    for field, expected in expected_arrays.items():
        actual = list(queue_row.get(field) or [])
        if field != "release_edit_segment_ids":
            actual = sorted(actual)
        if actual != expected:
            raise CloseoutError(f"{field} does not match the exact package output graph")

    normalized_trace = normalize_production_graph_trace(trace)
    trace_sha256 = canonical_object_sha256(normalized_trace)
    if trace_sha256 != str(queue_row["release_production_graph_trace_sha256"]):
        raise CloseoutError("release_production_graph_trace_sha256 is stale or mismatched")

    if canonical_object_sha256(deliverable_manifest) != str(
        queue_row["release_package_deliverable_manifest_sha256"]
    ):
        raise CloseoutError(
            "release_package_deliverable_manifest_sha256 is stale or mismatched"
        )
    matches = [item for item in deliverables if str(item.get("output_id") or "") == output_id]
    if len(matches) != 1:
        raise CloseoutError("release_package_output_id must identify exactly one 05 deliverable")
    output = matches[0]
    if str(queue_row["release_package_output_role"]) != str(output.get("role") or ""):
        raise CloseoutError("release_package_output_role does not match the 05 deliverable")
    if not str(output.get("path") or ""):
        raise CloseoutError("release_package_output_id does not name a local 05 deliverable")
    output_path = repo_path(root, str(output["path"]))
    linkage = str(queue_row["release_package_linkage"])
    if linkage == "exact_deliverable" and queue_asset != output_path:
        raise CloseoutError("release asset is not the exact declared 05 deliverable")
    if linkage == "child_of_upload_package":
        try:
            queue_asset.relative_to(output_path)
        except ValueError as exc:
            raise CloseoutError("release asset is not inside its declared upload package") from exc
    declared_output_sha = str(output.get("sha256") or "")
    if declared_output_sha and output_path.is_file() and sha256_file(output_path) != declared_output_sha:
        raise CloseoutError("declared 05 deliverable SHA-256 is stale")
    if str(queue_row["release_asset_sha256"]) != queue_asset_sha256:
        raise CloseoutError("release_asset_sha256 does not match the public-closeout asset")
    return {field: copy.deepcopy(queue_row[field]) for field in RELEASE_PRODUCTION_TRACE_FIELDS}


def validate_target_mapping(root: Path, signal_deck: dict[str, Any]) -> None:
    content_kind = signal_deck["content_kind"]
    if content_kind == "mv":
        target_path = root / "web/data/tracks.ts"
        target_id = signal_deck["track_id"]
    else:
        target_path = root / "web/data/cf.ts"
        target_id = signal_deck["cf_id"]
    if not target_path.is_file():
        raise CloseoutError(f"Signal Deck target catalog is missing: {relative(root, target_path)}")
    ids = set(re.findall(r'\bid:\s*"([^"]+)"', target_path.read_text(encoding="utf-8")))
    if target_id not in ids:
        raise CloseoutError(f"Signal Deck {content_kind} target is not registered: {target_id}")


def validate_visuals(root: Path, signal_deck: dict[str, Any]) -> None:
    publication_members = set(signal_deck["member_codes"])
    for visual in signal_deck["visuals"]:
        visual_members = set(visual["member_codes"])
        if not visual_members.issubset(publication_members):
            raise CloseoutError(f"visual {visual['id']} names a member outside the publication mapping")

        source_path = repo_path(root, visual["source_path"])
        web_path = repo_path(root, visual["web_path"])
        if not source_path.is_file():
            raise CloseoutError(f"visual source is missing: {visual['source_path']}")
        if not web_path.is_file():
            raise CloseoutError(f"web-ready visual is missing: {visual['web_path']}")
        if sha256_file(source_path) != visual["source_sha256"]:
            raise CloseoutError(f"visual source SHA-256 is stale: {visual['source_path']}")
        if sha256_file(web_path) != visual["web_sha256"]:
            raise CloseoutError(f"web visual SHA-256 is stale: {visual['web_path']}")

        expected_src = "/" + relative(root, web_path).removeprefix("web/public/")
        if visual["src"] != expected_src:
            raise CloseoutError(
                f"visual src {visual['src']} does not match web_path projection {expected_src}"
            )
        if visual["lineage_mode"] == "exact_copy" and visual["source_sha256"] != visual["web_sha256"]:
            raise CloseoutError(f"exact-copy visual hashes differ: {visual['id']}")


def make_publication(
    closeout: dict[str, Any], platform_post_id: str, player_url: str
) -> dict[str, Any]:
    signal_deck = closeout["signal_deck"]
    publication: dict[str, Any] = {
        "post_id": closeout["post_id"],
        "content_id": closeout["content_id"],
        "content_kind": signal_deck["content_kind"],
        "content_label": signal_deck["content_label"],
        "platform": closeout["platform"],
        "platform_post_id": platform_post_id,
        "published_url": closeout["published_url"],
        "embed_url": player_url,
        "published_at": closeout["published_at"],
        "title": signal_deck["title"],
        "member_visibility": signal_deck["member_visibility"],
        "member_codes": signal_deck["member_codes"],
        "duration": signal_deck.get("duration"),
        "views": None,
        "likes": None,
        "visuals": signal_deck["visuals"],
    }
    if signal_deck["content_kind"] == "mv":
        publication["track_id"] = signal_deck["track_id"]
    else:
        publication["cf_id"] = signal_deck["cf_id"]
    return publication


def upsert_publication(
    document: dict[str, Any], publication: dict[str, Any]
) -> dict[str, Any]:
    next_document = copy.deepcopy(document)
    rows = next_document.setdefault("publications", [])
    if not isinstance(rows, list):
        raise CloseoutError("Signal Deck publications must be an array")

    for row in rows:
        if row.get("post_id") != publication["post_id"] and (
            row.get("platform"), row.get("platform_post_id")
        ) == (publication["platform"], publication["platform_post_id"]):
            raise CloseoutError("Signal Deck platform post id is already bound to another post_id")

    replaced = False
    for index, row in enumerate(rows):
        if row.get("post_id") == publication["post_id"]:
            rows[index] = publication
            replaced = True
            break
    if not replaced:
        rows.append(publication)
    rows.sort(key=lambda row: (row.get("published_at", ""), row.get("post_id", "")), reverse=True)
    return next_document


def prepare_registry(
    root: Path, registry_path: Path, closeout: dict[str, Any], registered_at: str
) -> dict[str, Any]:
    registry = yaml.safe_load(registry_path.read_text(encoding="utf-8"))
    if not isinstance(registry, dict):
        raise CloseoutError("title output registry must be a YAML object")
    if closeout["content_id"] not in registry.get("content_ids", []):
        raise CloseoutError("title registry does not own the closeout content_id")
    source_roots = {row.get("run_root") for row in registry.get("source_runs", []) if isinstance(row, dict)}
    if closeout["run_root"] not in source_roots:
        raise CloseoutError("title registry does not own the closeout run_root")

    next_registry = copy.deepcopy(registry)
    existing = next(
        (
            row
            for row in next_registry.get("outputs", [])
            if isinstance(row, dict)
            and row.get("output_type") == "remote_publication"
            and row.get("path") == closeout["published_url"]
        ),
        None,
    )
    created = existing is None
    if created:
        title_registry.upsert_output(
            next_registry,
            {
                "output_type": "remote_publication",
                "path": closeout["published_url"],
                "source_run_root": closeout["run_root"],
                "content_id": closeout["content_id"],
                "source_step": "social_public_closeout",
                "status": "published",
                "notes": f"public post {closeout['post_id']} published_at {closeout['published_at']}",
            },
        )
    else:
        if existing.get("content_id") != closeout["content_id"] or existing.get("status") != "published":
            raise CloseoutError("existing remote publication conflicts with closeout ownership/status")
    if created:
        next_registry.setdefault("latest_pointers", {})["remote_publication"] = closeout["published_url"]
        for row in next_registry.get("source_runs", []):
            if isinstance(row, dict) and row.get("run_root") == closeout["run_root"]:
                row["last_updated_at"] = registered_at
    return next_registry


def validate_staged_registry(root: Path, data: bytes) -> None:
    with tempfile.NamedTemporaryFile(
        mode="wb", suffix=".yaml", prefix="idol-public-closeout-registry-", delete=False, dir=root
    ) as handle:
        handle.write(data)
        temp_path = Path(handle.name)
    try:
        result = title_registry.validate_registry(temp_path)
        if not result.get("valid"):
            raise CloseoutError(
                "staged title registry failed validation: " + "; ".join(result.get("errors", []))
            )
    finally:
        temp_path.unlink(missing_ok=True)


def atomic_replace_many(targets: dict[Path, bytes]) -> None:
    staged: dict[Path, Path] = {}
    backups: dict[Path, bytes | None] = {
        path: path.read_bytes() if path.exists() else None for path in targets
    }
    replaced: list[Path] = []
    try:
        for target, data in targets.items():
            target.parent.mkdir(parents=True, exist_ok=True)
            with tempfile.NamedTemporaryFile(
                mode="wb", prefix=f".{target.name}.", suffix=".tmp", delete=False, dir=target.parent
            ) as handle:
                handle.write(data)
                handle.flush()
                os.fsync(handle.fileno())
                staged[target] = Path(handle.name)
        for target, temp_path in staged.items():
            os.replace(temp_path, target)
            replaced.append(target)
    except Exception:
        for target in reversed(replaced):
            backup = backups[target]
            if backup is None:
                target.unlink(missing_ok=True)
            else:
                with tempfile.NamedTemporaryFile(
                    mode="wb", prefix=f".{target.name}.rollback.", delete=False, dir=target.parent
                ) as handle:
                    handle.write(backup)
                    handle.flush()
                    os.fsync(handle.fileno())
                    rollback = Path(handle.name)
                os.replace(rollback, target)
        raise
    finally:
        for temp_path in staged.values():
            temp_path.unlink(missing_ok=True)


def result_path_for(closeout_path: Path) -> Path:
    return closeout_path.with_name(f"{closeout_path.stem}.result.json")


def execute(args: argparse.Namespace) -> dict[str, Any]:
    root = Path(args.root).resolve()
    if not root.is_dir():
        raise CloseoutError(f"repository root is missing: {root}")
    os.chdir(root)

    schema_path = repo_path(root, args.schema)
    closeout_path = repo_path(root, args.closeout)
    posts_path = repo_path(root, args.posts)
    metrics_path = repo_path(root, args.metrics)
    publications_path = repo_path(root, args.signal_deck_publications)
    schema = load_json(schema_path)
    closeout = load_json(closeout_path)
    validate_against_def(schema, "closeout", closeout)

    run_root = repo_path(root, closeout["run_root"])
    try:
        closeout_path.relative_to(run_root)
    except ValueError as exc:
        raise CloseoutError("closeout record must live inside its declared run_root") from exc

    source_queue_path = repo_path(root, closeout["source_queue"])
    registry_path = repo_path(root, closeout["title_registry"])
    try:
        source_queue_path.relative_to(run_root)
    except ValueError as exc:
        raise CloseoutError("source_queue must live inside the declared run_root") from exc
    if not registry_path.is_file():
        raise CloseoutError(f"title registry is missing: {closeout['title_registry']}")

    published_at = parse_published_at(closeout["published_at"])
    platform_post_id = extract_platform_id(closeout["platform"], closeout["published_url"])
    player_url = embed_url(closeout["platform"], platform_post_id)
    validate_target_mapping(root, closeout["signal_deck"])
    validate_visuals(root, closeout["signal_deck"])

    posts = load_jsonl(posts_path)
    queue_rows = load_jsonl(source_queue_path)
    post_index, post_row = exact_row(posts, closeout["post_id"], "global platform ledger")
    _, queue_row = exact_row(queue_rows, closeout["post_id"], "run-owned source queue")
    for label, row in (("global platform ledger", post_row), ("run-owned source queue", queue_row)):
        if row.get("content_id") != closeout["content_id"]:
            raise CloseoutError(f"{label} content_id does not match closeout")
        if row.get("platform") != closeout["platform"]:
            raise CloseoutError(f"{label} platform does not match closeout")
        require_queue_evidence(row, label)
    for field in ("caption", "tracking_code"):
        queue_value = queue_row.get(field)
        ledger_value = post_row.get(field)
        if queue_value and ledger_value and queue_value != ledger_value:
            raise CloseoutError(f"run queue and global ledger disagree on {field}")

    queue_asset = repo_path(root, queue_row["asset_or_clip"])
    ledger_asset = repo_path(root, post_row["asset_or_clip"])
    try:
        queue_asset.relative_to(run_root)
    except ValueError as exc:
        raise CloseoutError("run queue asset_or_clip must stay inside the declared run_root") from exc
    if not queue_asset.is_file() or not ledger_asset.is_file():
        raise CloseoutError("run queue and global ledger asset_or_clip paths must both exist")
    queue_asset_sha = sha256_file(queue_asset)
    ledger_asset_sha = sha256_file(ledger_asset)
    if queue_asset_sha != ledger_asset_sha:
        raise CloseoutError("run queue and global ledger asset_or_clip bytes differ")
    production_trace_projection = validate_release_production_trace(
        root=root,
        run_root=run_root,
        content_id=closeout["content_id"],
        queue_row=queue_row,
        ledger_row=post_row,
        queue_asset=queue_asset,
        queue_asset_sha256=queue_asset_sha,
    )

    for row in posts:
        if row.get("post_id") == closeout["post_id"]:
            continue
        if (row.get("platform"), row.get("platform_post_id")) == (
            closeout["platform"],
            platform_post_id,
        ):
            raise CloseoutError("platform_post_id is already bound to another post_id")

    result_path = repo_path(root, args.result) if args.result else result_path_for(closeout_path)
    try:
        result_path.relative_to(run_root)
    except ValueError as exc:
        raise CloseoutError("result record must live inside the declared run_root") from exc
    existing_result = load_json(result_path) if result_path.is_file() else None
    if existing_result and any(
        existing_result.get(field) != closeout.get(field)
        for field in ("post_id", "content_id", "platform", "published_url", "published_at")
    ):
        raise CloseoutError("existing immutable result does not match this closeout")
    registered_at = (
        existing_result.get("registered_at")
        if existing_result and existing_result.get("registered_at")
        else datetime.now().astimezone().isoformat(timespec="seconds")
    )
    publication = make_publication(closeout, platform_post_id, player_url)
    validate_against_def(schema, "publication", publication)

    next_post = copy.deepcopy(post_row)
    next_post.update(
        {
            "status": "published",
            "platform_post_id": platform_post_id,
            "published_url": closeout["published_url"],
            "published_at": closeout["published_at"],
            "embed_url": player_url,
            "public_share_registered_at": post_row.get("public_share_registered_at") or registered_at,
            "signal_deck_publication": {
                "content_kind": publication["content_kind"],
                "content_label": publication["content_label"],
                "member_codes": publication["member_codes"],
                "track_id": publication.get("track_id"),
                "cf_id": publication.get("cf_id"),
                "visual_ids": [visual["id"] for visual in publication["visuals"]],
            },
            "public_closeout_queue_asset": relative(root, queue_asset),
            "public_closeout_asset_sha256": queue_asset_sha,
        }
    )
    next_post.update(production_trace_projection)
    next_posts = copy.deepcopy(posts)
    next_posts[post_index] = next_post

    publications = load_json(publications_path)
    validate_document(schema, publications, "Signal Deck publication registry")
    next_publications = upsert_publication(publications, publication)
    validate_document(schema, next_publications, "staged Signal Deck publication registry")

    next_registry = prepare_registry(root, registry_path, closeout, registered_at)
    posts_bytes = dump_jsonl(next_posts)
    publications_bytes = dump_json(next_publications)
    registry_bytes = dump_yaml(next_registry)
    validate_staged_registry(root, registry_bytes)

    # The registered social validator accepts explicit staged paths and reads no platform API.
    with tempfile.NamedTemporaryFile(
        mode="wb", suffix=".jsonl", prefix="idol-public-closeout-posts-", delete=False, dir=root
    ) as handle:
        handle.write(posts_bytes)
        staged_posts_path = Path(handle.name)
    try:
        import subprocess

        completed = subprocess.run(
            ["ruby", "scripts/validate_social_analytics.rb", str(staged_posts_path), str(metrics_path)],
            cwd=root,
            capture_output=True,
            text=True,
            check=False,
        )
        if completed.returncode != 0:
            detail = (completed.stderr or completed.stdout).strip()
            raise CloseoutError(f"staged social ledger failed validation: {detail}")
    finally:
        staged_posts_path.unlink(missing_ok=True)

    checkpoints = {
        "T+24h": (published_at + timedelta(hours=24)).isoformat(timespec="seconds"),
        "T+72h": (published_at + timedelta(hours=72)).isoformat(timespec="seconds"),
        "T+7d": (published_at + timedelta(days=7)).isoformat(timespec="seconds"),
    }
    output_hashes = {
        relative(root, posts_path): sha256_bytes(posts_bytes),
        relative(root, publications_path): sha256_bytes(publications_bytes),
        relative(root, registry_path): sha256_bytes(registry_bytes),
    }
    result: dict[str, Any] = {
        "schema_version": "idol_social_public_closeout_result.v1",
        "status": "applied" if args.apply else "dry_run_pass",
        "post_id": closeout["post_id"],
        "content_id": closeout["content_id"],
        "platform": closeout["platform"],
        "platform_post_id": platform_post_id,
        "published_url": closeout["published_url"],
        "published_at": closeout["published_at"],
        "registered_at": registered_at,
        "signal_deck_members": publication["member_codes"],
        "signal_deck_target": publication.get("track_id") or publication.get("cf_id"),
        "visual_ids": [visual["id"] for visual in publication["visuals"]],
        "metric_checkpoints": checkpoints,
        "output_sha256": output_hashes,
        "external_action": False,
        "platform_api_called": False,
        "signal_deck_deploy_required": True,
    }
    result_bytes = dump_json(result)

    if args.apply and existing_result:
        current_matches = (
            posts_path.read_bytes() == posts_bytes
            and publications_path.read_bytes() == publications_bytes
            and registry_path.read_bytes() == registry_bytes
        )
        if not current_matches:
            raise CloseoutError(
                "immutable closeout result exists but canonical projections drifted; author a reviewed repair instead of overwriting the result"
            )
        already_applied = copy.deepcopy(existing_result)
        already_applied["status"] = "already_applied"
        already_applied["result_path"] = relative(root, result_path)
        already_applied["result_sha256"] = sha256_file(result_path)
        return already_applied

    if args.apply:
        atomic_replace_many(
            {
                posts_path: posts_bytes,
                publications_path: publications_bytes,
                registry_path: registry_bytes,
                result_path: result_bytes,
            }
        )
        result["result_path"] = relative(root, result_path)
        result["result_sha256"] = sha256_file(result_path)
    return result


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--closeout", required=True, help="Run-owned public closeout JSON record")
    parser.add_argument("--root", default=Path(__file__).resolve().parents[1], help="Repository root")
    parser.add_argument("--schema", default=DEFAULT_SCHEMA)
    parser.add_argument("--posts", default=DEFAULT_POSTS)
    parser.add_argument("--metrics", default=DEFAULT_METRICS)
    parser.add_argument("--signal-deck-publications", default=DEFAULT_PUBLICATIONS)
    parser.add_argument("--result", default=None, help="Optional run-owned result JSON path")
    parser.add_argument("--apply", action="store_true", help="Atomically write local closeout surfaces")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        result = execute(args)
    except (CloseoutError, json.JSONDecodeError, yaml.YAMLError) as exc:
        print(json.dumps({"status": "hold", "error": str(exc)}, ensure_ascii=False, indent=2))
        return 1
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
