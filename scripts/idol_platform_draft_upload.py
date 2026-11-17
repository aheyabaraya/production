#!/usr/bin/env python3
"""Upload one explicitly approved, run-owned IDOL social batch as drafts.

Dry-run is local-only. ``--apply`` fails before any network request unless the
run/content/path scope and a schema-valid, SHA-256-bound Founder approval
artifact all match the queue's canonical action-bearing content.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import mimetypes
import os
import re
import shutil
import time
import uuid
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable
from urllib import error, parse, request

import idol_title_output_registry as title_registry
import validate_publishing_plan as publishing_plan_validator
import yaml
from lib.idol_social_release_contracts import (
    SocialContractError,
    canonical_object_sha256,
    package_deliverable_manifest,
    repo_relative,
    sha256_file,
    validate_approval_artifact,
    validate_package_contract,
    validate_queue_asset_linkage,
    validate_queue_scope,
    validate_registry_scope,
    validate_run_owned_path,
    validate_run_scope,
    validate_schema,
)
from lib.idol_post05_trace import RELEASE_PROVENANCE_VERSION
from lib.idol_platform_credentials import load_env
from lib.idol_platform_credentials import status_for_platform
from lib.idol_api_video_quality import (
    ApiVideoQualityError,
    QUALITY_PROFILE as API_VIDEO_QUALITY_PROFILE,
    inspect_api_upload_video,
    validate_quality_receipt,
)


ROOT = Path(__file__).resolve().parents[1]
IDOL_RUNTIME_SECRETS = ROOT / ".runtime/secrets"
DEFAULT_X_ENV = IDOL_RUNTIME_SECRETS / "x.env"
DEFAULT_TIKTOK_ENV = IDOL_RUNTIME_SECRETS / "tiktok.env"
DEFAULT_TIKTOK_TOKEN = IDOL_RUNTIME_SECRETS / "tiktok-token.json"
DEFAULT_YOUTUBE_CLIENT_SECRET = IDOL_RUNTIME_SECRETS / "youtube-client-secret.json"
DEFAULT_YOUTUBE_TOKEN = IDOL_RUNTIME_SECRETS / "youtube-token.json"

PUBLIC_PLATFORM_HASHTAG_PLATFORMS = {"tiktok", "youtube", "youtube_shorts", "instagram_reels"}
KNOWN_SOCIAL_RELEASE_PLATFORMS = {
    "x",
    "tiktok",
    "youtube",
    "youtube_shorts",
    "instagram_reels",
}
AUTOMATIC_DRAFT_UPLOAD_PLATFORMS = {"tiktok", "youtube", "youtube_shorts"}
REQUIRED_PUBLIC_PLATFORM_HASHTAGS = ["#AI", "#AIIdol", "#Kpop", "#VirtualIdol", "#Loom"]


class UploadError(RuntimeError):
    def __init__(
        self,
        message: str,
        *,
        status: int | None = None,
        body: str | None = None,
        retry_safe: bool = False,
    ) -> None:
        super().__init__(message)
        self.status = status
        self.body = body
        self.retry_safe = retry_safe


@dataclass
class UploadResult:
    post_id: str
    platform: str
    ok: bool
    draft_status: str
    draft_platform_id: str = ""
    draft_url: str = ""
    error: str = ""
    raw: dict[str, Any] | None = None
    attempt_status: str = "unknown"


@dataclass(frozen=True)
class UploadChunkLock:
    start: int
    end: int
    sha256: str

    @property
    def length(self) -> int:
        return self.end - self.start + 1


def build_verified_chunk_manifest(
    file_path: Path,
    *,
    chunk_size: int,
    expected_sha256: str,
) -> tuple[int, list[UploadChunkLock]]:
    """Hash the approved snapshot once and bind every later request body."""

    if chunk_size <= 0:
        raise UploadError("upload chunk size must be positive")
    initial = file_path.stat()
    size = initial.st_size
    if size <= 0:
        raise UploadError("approved upload asset is empty")
    overall = hashlib.sha256()
    locks: list[UploadChunkLock] = []
    offset = 0
    with file_path.open("rb") as handle:
        while offset < size:
            payload = handle.read(min(chunk_size, size - offset))
            if not payload:
                raise UploadError("approved upload asset ended while building chunk manifest")
            overall.update(payload)
            locks.append(
                UploadChunkLock(
                    start=offset,
                    end=offset + len(payload) - 1,
                    sha256=hashlib.sha256(payload).hexdigest(),
                )
            )
            offset += len(payload)
    final = file_path.stat()
    if (initial.st_dev, initial.st_ino, initial.st_size) != (
        final.st_dev,
        final.st_ino,
        final.st_size,
    ):
        raise UploadError("approved upload asset changed while building chunk manifest")
    actual_sha = overall.hexdigest()
    if actual_sha != expected_sha256:
        raise UploadError(
            f"approved upload asset SHA-256 changed before upload: expected {expected_sha256}, got {actual_sha}"
        )
    return size, locks


def read_verified_chunk(
    handle: Any,
    *,
    file_path: Path,
    expected_size: int,
    lock: UploadChunkLock,
) -> bytes:
    """Read one request body and prove it still matches the preflight manifest."""

    if file_path.stat().st_size != expected_size:
        raise UploadError("approved upload asset size changed before chunk request")
    handle.seek(lock.start)
    payload = handle.read(lock.length)
    if len(payload) != lock.length or hashlib.sha256(payload).hexdigest() != lock.sha256:
        raise UploadError(
            f"approved upload asset bytes changed before request at {lock.start}-{lock.end}"
        )
    return payload


def now_iso() -> str:
    return datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")


def read_json(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    return json.loads(path.read_text())


def row_asset_path(row: dict[str, Any], args: argparse.Namespace, *, must_exist: bool = True) -> Path:
    post_id = str(row.get("post_id") or "")
    snapshot_by_post = getattr(args, "_asset_snapshot_by_post", {})
    value = str(snapshot_by_post.get(post_id) or row.get("asset_or_clip") or "")
    if not value:
        raise UploadError(f"{row.get('post_id', '<unknown>')}: asset_or_clip is required")
    try:
        path = validate_run_owned_path(
            ROOT,
            Path(args._run_path),
            value,
            f"asset_or_clip for {row.get('post_id', '<unknown>')}",
            must_exist=must_exist,
            file_only=True,
        )
        expected = getattr(args, "_approved_asset_sha_by_post", {}).get(post_id)
        if expected:
            actual = sha256_file(path)
            if actual != expected:
                raise SocialContractError(
                    f"approved asset/snapshot SHA-256 changed before upload for {row.get('post_id', '<unknown>')}"
                )
        return path
    except SocialContractError as exc:
        raise UploadError(str(exc)) from exc


def validate_api_upload_video_row(
    row: dict[str, Any], args: argparse.Namespace
) -> dict[str, Any]:
    post_id = str(row.get("post_id") or "<unknown>")
    if str(row.get("api_upload_quality_profile") or "") != API_VIDEO_QUALITY_PROFILE:
        raise UploadError(
            f"{post_id}: api_upload_quality_profile must be {API_VIDEO_QUALITY_PROFILE}"
        )
    receipt_value = str(row.get("api_upload_quality_receipt") or "")
    if not receipt_value:
        raise UploadError(f"{post_id}: api_upload_quality_receipt is required")
    run_path = Path(args._run_path)
    receipt_path = validate_run_owned_path(
        ROOT,
        run_path,
        receipt_value,
        f"API upload quality receipt for {post_id}",
        must_exist=True,
        file_only=True,
    )
    approved_asset_path = validate_run_owned_path(
        ROOT,
        run_path,
        str(row.get("asset_or_clip") or ""),
        f"approved API upload asset for {post_id}",
        must_exist=True,
        file_only=True,
    )
    upload_path = row_asset_path(row, args)
    try:
        probe = inspect_api_upload_video(upload_path)
        receipt = validate_quality_receipt(
            repo_root=ROOT,
            run_root=run_path,
            content_id=args.content_id,
            asset_path=approved_asset_path,
            receipt_path=receipt_path,
            probe=probe,
        )
    except ApiVideoQualityError as exc:
        raise UploadError(f"{post_id}: {exc}") from exc
    return {
        "post_id": post_id,
        "quality_profile": API_VIDEO_QUALITY_PROFILE,
        "asset_path": repo_relative(ROOT, approved_asset_path),
        "asset_sha256": probe["sha256"],
        "width": probe["width"],
        "height": probe["height"],
        "avg_frame_rate": probe["avg_frame_rate"],
        "r_frame_rate": probe["r_frame_rate"],
        "video_codec": probe["video_codec"],
        "audio_codec": probe["audio_codec"],
        "audio_bit_rate": probe["audio_bit_rate"],
        "byte_delivery": probe["byte_delivery"],
        "quality_receipt": repo_relative(ROOT, receipt_path),
        "quality_receipt_sha256": receipt["sha256"],
        "transform_mode": receipt["transform_mode"],
    }


def validate_api_upload_video_rows(
    rows: list[dict[str, Any]], args: argparse.Namespace
) -> list[dict[str, Any]]:
    return [validate_api_upload_video_row(row, args) for row in rows]


def load_rows(path: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for line in path.read_text().splitlines():
        if line.strip():
            rows.append(json.loads(line))
    return rows


def write_rows(path: Path, rows: list[dict[str, Any]]) -> None:
    payload = (
        "\n".join(
            json.dumps(row, ensure_ascii=False, separators=(",", ":")) for row in rows
        )
        + "\n"
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.tmp-{uuid.uuid4().hex}")
    try:
        with temporary.open("w", encoding="utf-8") as handle:
            handle.write(payload)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
        fsync_directory(path.parent)
    finally:
        if temporary.exists():
            temporary.unlink()


def fsync_directory(path: Path) -> None:
    descriptor = os.open(path, os.O_RDONLY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def atomic_write_json(path: Path, document: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.tmp-{uuid.uuid4().hex}")
    try:
        with temporary.open("w", encoding="utf-8") as handle:
            json.dump(document, handle, ensure_ascii=False, indent=2)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
        fsync_directory(path.parent)
    finally:
        if temporary.exists():
            temporary.unlink()


def atomic_write_secret_json(path: Path, document: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.tmp-{uuid.uuid4().hex}")
    try:
        with temporary.open("w", encoding="utf-8") as handle:
            json.dump(document, handle, ensure_ascii=False, indent=2)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temporary, 0o600)
        os.replace(temporary, path)
        os.chmod(path, 0o600)
        fsync_directory(path.parent)
    finally:
        if temporary.exists():
            temporary.unlink()


def atomic_write_text(path: Path, payload: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.tmp-{uuid.uuid4().hex}")
    try:
        with temporary.open("w", encoding="utf-8") as handle:
            handle.write(payload)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
        fsync_directory(path.parent)
    finally:
        if temporary.exists():
            temporary.unlink()


def validate_upload_evidence_lane(
    *,
    run_path: Path,
    queue_path: Path,
    tracker_path: Path,
    log_path: Path,
) -> None:
    if tracker_path.suffix.lower() != ".md":
        raise SocialContractError("tracker must be a run-owned Markdown file")
    if log_path.suffix.lower() != ".jsonl":
        raise SocialContractError("upload log must be a run-owned JSONL file")
    if tracker_path.parent != log_path.parent:
        raise SocialContractError("tracker and upload log must share one social batch lane")
    preferred_root = (run_path / "exports/social").resolve()
    try:
        tracker_path.relative_to(preferred_root)
        log_path.relative_to(preferred_root)
        return
    except ValueError:
        pass
    relative_parent = tracker_path.parent.relative_to(run_path)
    social_named = any(part.lower() == "social" or part.lower().startswith("social-") for part in relative_parent.parts)
    if not social_named or queue_path.parent != tracker_path.parent:
        raise SocialContractError(
            "tracker/log must stay under run-owned exports/social or the queue's existing run-owned social batch lane"
        )


def validate_pairwise_distinct(paths: dict[str, Path]) -> None:
    by_path: dict[Path, list[str]] = {}
    for label, path in paths.items():
        by_path.setdefault(path.resolve(), []).append(label)
    collisions = [labels for labels in by_path.values() if len(labels) > 1]
    if collisions:
        raise SocialContractError(
            "release input/output paths must be pairwise distinct: "
            + "; ".join("=".join(labels) for labels in collisions)
        )


def intended_registry_path(rows: list[dict[str, Any]], args: argparse.Namespace) -> Path:
    fallback = args.title or str(rows[0].get("content_id") or "untitled")
    album = title_registry.album_key(args.album_key)
    track = title_registry.title_key(args.title_key, fallback=fallback)
    relative = title_registry.registry_paths(album, track)["output_registry_path"]
    path = (ROOT / relative).resolve()
    try:
        path.relative_to((ROOT / "catalog/albums").resolve())
    except ValueError as exc:
        raise SocialContractError("title registry must stay under catalog/albums") from exc
    if path.name != "output-registry.yaml":
        raise SocialContractError("title registry target must be output-registry.yaml")
    return path


def validate_upload_registry(
    *,
    path: Path,
    run_rel: str,
    content_id: str,
) -> tuple[Path, dict[str, Any], str]:
    """Load the exact active registry that an apply run is allowed to mutate."""

    registry_path, registry = validate_registry_scope(
        repo_root=ROOT,
        run_rel=run_rel,
        content_id=content_id,
        registry=path,
    )
    validate_schema(
        registry,
        ROOT / "schemas/title-output-registry.schema.json",
        label="scoped title output registry",
    )
    status = str(registry.get("status") or "").strip().lower()
    if status == "archived" or "closed" in status:
        raise SocialContractError(
            "title registry is immutable archived/closed state; draft upload cannot reactivate it"
        )
    if status == "hold":
        raise SocialContractError(
            "title registry is on hold; draft upload requires an active release registry"
        )
    return registry_path, registry, sha256_file(registry_path)


def validate_known_release_platforms(rows: list[dict[str, Any]]) -> None:
    unknown = sorted(
        {
            str(row.get("platform") or "<missing>")
            for row in rows
            if str(row.get("platform") or "") not in KNOWN_SOCIAL_RELEASE_PLATFORMS
        }
    )
    if unknown:
        raise SocialContractError(
            "queue contains unknown social platform(s): " + ", ".join(unknown)
        )
    unsupported = sorted(
        {
            str(row.get("platform") or "<missing>")
            for row in rows
            if row.get("delivery_mode") == "platform_draft"
            and str(row.get("platform") or "") not in AUTOMATIC_DRAFT_UPLOAD_PLATFORMS
        }
    )
    if unsupported:
        raise SocialContractError(
            "platform_draft queue contains unsupported automatic uploader platform(s): "
            + ", ".join(unsupported)
        )


def validate_automatic_platform_filters(platforms: set[str]) -> None:
    manual = sorted(platforms - AUTOMATIC_DRAFT_UPLOAD_PLATFORMS)
    if not manual:
        return
    routes = {
        "x": "use the hash-bound dedicated public X adapter",
        "instagram_reels": "use the manual Instagram release package lane",
    }
    detail = "; ".join(f"{platform}: {routes.get(platform, 'no automatic adapter')}" for platform in manual)
    raise SocialContractError(
        "automatic draft uploader cannot execute the requested platform filter(s): "
        + ", ".join(manual)
        + "; "
        + detail
    )


def validate_platform_auth_preflight(platforms: set[str]) -> None:
    if "tiktok" in platforms:
        status = status_for_platform("tiktok", ROOT)
        if not status.get("ready_for_runtime_upload"):
            raise SocialContractError(
                "TikTok credentials are not ready; run "
                "python3 scripts/idol_tiktok_oauth_reauth.py --open-browser"
            )
    if platforms & {"youtube", "youtube_shorts"}:
        status = status_for_platform("youtube", ROOT)
        if not status.get("ready_for_runtime_upload"):
            raise SocialContractError(
                "YouTube credentials are not ready; run "
                "python3 scripts/idol_youtube_oauth_reauth.py --open-browser"
            )


def unresolved_attempts(run_path: Path, content_id: str) -> list[dict[str, str]]:
    attempts_root = validate_run_owned_path(
        ROOT,
        run_path,
        run_path / "exports/social/upload-attempts",
        "upload attempts root",
        must_exist=False,
    )
    if not attempts_root.exists():
        return []
    if not attempts_root.is_dir() or attempts_root.is_symlink():
        raise SocialContractError("upload attempts root must be an owned directory")
    unresolved: list[dict[str, str]] = []
    for path in sorted(attempts_root.glob("*.json")):
        if path.is_symlink() or not path.is_file():
            raise SocialContractError(f"upload attempt record must be an owned file: {path}")
        try:
            document = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            raise SocialContractError(f"unreadable upload attempt record: {path}") from exc
        if not isinstance(document, dict):
            raise SocialContractError(f"upload attempt record must be an object: {path}")
        if str(document.get("content_id") or "") != content_id:
            raise SocialContractError(f"foreign content_id in run-owned upload attempt: {path}")
        status = str(document.get("status") or "unknown")
        resolved_statuses = {"completed", "failed", "reconciled", "cancelled"}
        if status not in resolved_statuses:
            status = status if status in {"started", "unknown"} else "unknown"
            unresolved.append(
                {
                    "attempt_id": str(document.get("attempt_id") or path.stem),
                    "post_id": str(document.get("post_id") or ""),
                    "status": status,
                    "path": path.as_posix(),
                }
            )
    return unresolved


def snapshot_approved_asset(row: dict[str, Any], args: argparse.Namespace) -> tuple[Path, str]:
    post_id = str(row.get("post_id") or "")
    source = validate_run_owned_path(
        ROOT,
        Path(args._run_path),
        str(row.get("asset_or_clip") or ""),
        f"approved source asset for {post_id}",
        must_exist=True,
        file_only=True,
    )
    expected_sha = str(args._approved_asset_sha_by_post[post_id])
    if sha256_file(source) != expected_sha:
        raise SocialContractError(f"approved source asset changed before snapshot for {post_id}")
    suffix = source.suffix.lower() or ".bin"
    snapshot = (
        Path(args._run_path)
        / "exports/social/upload-staging"
        / expected_sha
        / f"asset{suffix}"
    )
    snapshot = validate_run_owned_path(
        ROOT,
        Path(args._run_path),
        snapshot,
        f"content-addressed staging snapshot for {post_id}",
        must_exist=False,
    )
    snapshot.parent.mkdir(parents=True, exist_ok=True)
    if snapshot.exists():
        if snapshot.is_symlink() or not snapshot.is_file() or sha256_file(snapshot) != expected_sha:
            raise SocialContractError(f"content-addressed staging snapshot is invalid for {post_id}")
    else:
        temporary = snapshot.with_name(f".{snapshot.name}.tmp-{uuid.uuid4().hex}")
        try:
            with source.open("rb") as source_handle, temporary.open("wb") as target_handle:
                shutil.copyfileobj(source_handle, target_handle, length=1024 * 1024)
                target_handle.flush()
                os.fsync(target_handle.fileno())
            if sha256_file(temporary) != expected_sha:
                raise SocialContractError(f"staging snapshot hash mismatch for {post_id}")
            os.replace(temporary, snapshot)
            fsync_directory(snapshot.parent)
        finally:
            if temporary.exists():
                temporary.unlink()
    if sha256_file(snapshot) != expected_sha:
        raise SocialContractError(f"staging snapshot changed after install for {post_id}")
    return snapshot, expected_sha


def create_attempt_intent(
    *,
    row: dict[str, Any],
    args: argparse.Namespace,
    snapshot_path: Path,
    snapshot_sha: str,
) -> tuple[Path, dict[str, Any]]:
    stamp = now_iso()
    attempt_id = (
        "UPLOAD_"
        + datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
        + "_"
        + uuid.uuid4().hex[:12].upper()
    )
    path = Path(args._run_path) / "exports/social/upload-attempts" / f"{attempt_id}.json"
    path = validate_run_owned_path(
        ROOT,
        Path(args._run_path),
        path,
        "upload attempt record",
        must_exist=False,
    )
    document = {
        "schema_version": "idol_platform_upload_attempt.v1",
        "attempt_id": attempt_id,
        "status": "started",
        "started_at": stamp,
        "content_id": args.content_id,
        "post_id": str(row.get("post_id") or ""),
        "platform": str(row.get("platform") or ""),
        "approval_artifact": args._approval_rel,
        "approval_artifact_sha256": args._approval_sha,
        "queue_path": repo_relative(ROOT, Path(args._queue_path)),
        "queue_sha256": args._queue_sha,
        "package_contract_path": args._package_contract_rel,
        "package_contract_sha256": args._package_contract_sha,
        "package_deliverable_manifest_sha256": args._package_manifest_sha,
        "asset_source_path": str(row.get("asset_or_clip") or ""),
        "asset_sha256": snapshot_sha,
        "asset_snapshot_path": repo_relative(ROOT, snapshot_path),
        "asset_snapshot_sha256": snapshot_sha,
        "api_upload_quality": getattr(args, "_api_video_quality_by_post", {}).get(
            str(row.get("post_id") or ""), {}
        ),
    }
    atomic_write_json(path, document)
    return path, document


def finalize_attempt(
    path: Path,
    document: dict[str, Any],
    result: UploadResult,
) -> None:
    document = dict(document)
    document["status"] = "completed" if result.ok else result.attempt_status
    document["finished_at"] = now_iso()
    document["result"] = {
        "ok": result.ok,
        "draft_status": result.draft_status,
        "draft_platform_id": result.draft_platform_id,
        "draft_url": result.draft_url,
        "error": result.error,
        "attempt_status": result.attempt_status,
    }
    atomic_write_json(path, document)


def assert_runtime_release_lock(
    row: dict[str, Any],
    args: argparse.Namespace,
    *,
    verify_asset: bool = True,
) -> None:
    if sha256_file(Path(args._approval_path)) != args._approval_sha:
        raise UploadError("Founder approval artifact changed before network execution")
    if sha256_file(Path(args._package_contract_path)) != args._package_contract_sha:
        raise UploadError("05-package.yaml changed before network execution")
    registry_path = getattr(args, "_registry_path", "")
    registry_sha = getattr(args, "_registry_sha", "")
    if registry_path and registry_sha and sha256_file(Path(registry_path)) != registry_sha:
        raise UploadError("title output registry changed before network execution")
    _queue_path, _rows, live_queue_sha = validate_queue_scope(
        ROOT,
        Path(args._run_path),
        args.content_id,
        Path(args._queue_path),
    )
    if live_queue_sha != args._queue_sha:
        raise UploadError("canonical queue changed before network execution")
    if verify_asset:
        row_asset_path(row, args)
        validate_api_upload_video_row(row, args)


def validate_existing_tracker_owner(path: Path, content_id: str) -> None:
    if not path.exists():
        return
    if not path.is_file():
        raise SocialContractError(f"tracker path exists but is not a file: {path}")
    match = re.search(r"^content_id:\s*`?([^`\n]+)`?\s*$", path.read_text(encoding="utf-8"), flags=re.M)
    if not match:
        raise SocialContractError("existing tracker has no content_id owner field")
    if match.group(1).strip() != content_id:
        raise SocialContractError(
            f"tracker content_id {match.group(1).strip()!r} does not match {content_id!r}"
        )


def validate_existing_log_owner(path: Path, content_id: str) -> None:
    if not path.exists():
        return
    if not path.is_file():
        raise SocialContractError(f"log path exists but is not a file: {path}")
    for line_no, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if not line.strip():
            continue
        try:
            row = json.loads(line)
        except json.JSONDecodeError as exc:
            raise SocialContractError(f"invalid existing upload log JSONL at line {line_no}") from exc
        owner = str(row.get("content_id") or "")
        post_id = str(row.get("post_id") or "")
        if owner and owner != content_id:
            raise SocialContractError(
                f"upload log content_id {owner!r} does not match {content_id!r}"
            )
        if not owner and post_id and not post_id.startswith(content_id + "-"):
            raise SocialContractError(
                f"upload log post_id {post_id!r} does not belong to {content_id!r}"
            )


def hashtag_key(tag: Any) -> str:
    return str(tag).strip().lower().replace(" ", "")


def public_hashtags(row: dict[str, Any]) -> list[str]:
    raw = row.get("hashtags") if isinstance(row.get("hashtags"), list) else []
    tags = [str(tag).strip() for tag in raw if str(tag).strip()]
    if row.get("platform") in PUBLIC_PLATFORM_HASHTAG_PLATFORMS:
        seen = {hashtag_key(tag) for tag in tags}
        for required in REQUIRED_PUBLIC_PLATFORM_HASHTAGS:
            if hashtag_key(required) not in seen:
                tags.append(required)
                seen.add(hashtag_key(required))
    return tags


def youtube_tags(row: dict[str, Any], fallback: list[str]) -> list[str]:
    raw = row.get("youtube_tags") if isinstance(row.get("youtube_tags"), list) else fallback
    tags: list[str] = []
    seen: set[str] = set()
    for item in raw:
        tag = str(item).strip().lstrip("#")
        if not tag:
            continue
        key = tag.lower()
        if key in seen:
            continue
        tags.append(tag)
        seen.add(key)
    return tags


def ensure_public_metadata(row: dict[str, Any]) -> None:
    tags = public_hashtags(row)
    row["hashtags"] = tags
    if row.get("platform") not in PUBLIC_PLATFORM_HASHTAG_PLATFORMS:
        return
    caption = str(row.get("caption") or "").rstrip()
    caption_keys = {part.lower() for part in caption.replace("\n", " ").split()}
    missing = [tag for tag in tags if tag.lower() not in caption_keys]
    if missing:
        tag_line = " ".join(missing)
        row["caption"] = (caption + "\n\n" + tag_line).strip() if caption else tag_line


def append_log(
    path: Path, result: UploadResult, content_id: str, approval_row: dict[str, Any]
) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    record = {
        "recorded_at": now_iso(),
        "content_id": content_id,
        "post_id": result.post_id,
        "platform": result.platform,
        "ok": result.ok,
        "draft_status": result.draft_status,
        "draft_platform_id": result.draft_platform_id,
        "draft_url": result.draft_url,
        "error": result.error,
        "attempt_status": result.attempt_status,
        "release_approval_action": approval_row.get("release_approval_action", ""),
        "release_approval_artifact": approval_row.get("release_approval_artifact", ""),
        "release_approval_artifact_sha256": approval_row.get(
            "release_approval_artifact_sha256", ""
        ),
        "release_approval_queue_sha256": approval_row.get(
            "release_approval_queue_sha256", ""
        ),
        "release_package_contract": approval_row.get("release_package_contract", ""),
        "release_package_contract_sha256": approval_row.get(
            "release_package_contract_sha256", ""
        ),
        "release_package_deliverable_manifest_sha256": approval_row.get(
            "release_package_deliverable_manifest_sha256", ""
        ),
        "release_package_output_id": approval_row.get("release_package_output_id", ""),
        "release_package_output_role": approval_row.get("release_package_output_role", ""),
        "release_package_linkage": approval_row.get("release_package_linkage", ""),
        "release_provenance_version": approval_row.get("release_provenance_version", ""),
        "release_production_graph_trace_sha256": approval_row.get(
            "release_production_graph_trace_sha256", ""
        ),
        "release_edit_segment_ids": approval_row.get("release_edit_segment_ids", []),
        "release_screen_progression_node_ids": approval_row.get(
            "release_screen_progression_node_ids", []
        ),
        "release_section_ids": approval_row.get("release_section_ids", []),
        "release_asset_sha256": approval_row.get("release_asset_sha256", ""),
        "release_asset_snapshot": approval_row.get("release_asset_snapshot", ""),
        "release_asset_snapshot_sha256": approval_row.get(
            "release_asset_snapshot_sha256", ""
        ),
        "upload_attempt_id": approval_row.get("upload_attempt_id", ""),
        "upload_attempt_record": approval_row.get("upload_attempt_record", ""),
        "release_api_upload_quality_profile": approval_row.get(
            "release_api_upload_quality_profile", ""
        ),
        "release_api_upload_quality_receipt": approval_row.get(
            "release_api_upload_quality_receipt", ""
        ),
        "release_api_upload_quality_receipt_sha256": approval_row.get(
            "release_api_upload_quality_receipt_sha256", ""
        ),
    }
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(record, ensure_ascii=False, separators=(",", ":")) + "\n")
        handle.flush()
        os.fsync(handle.fileno())
    fsync_directory(path.parent)


def http_request(
    method: str,
    url: str,
    *,
    headers: dict[str, str] | None = None,
    body: bytes | None = None,
    timeout: int = 120,
) -> tuple[int, dict[str, str], bytes]:
    req = request.Request(url, data=body, method=method, headers=headers or {})
    try:
        with request.urlopen(req, timeout=timeout) as resp:
            return resp.status, dict(resp.headers), resp.read()
    except error.HTTPError as exc:
        payload = exc.read().decode("utf-8", errors="replace")
        raise UploadError(f"HTTP {exc.code} for {url}", status=exc.code, body=payload) from exc
    except error.URLError as exc:
        raise UploadError(f"Network error for {url}: {exc.reason}") from exc


def http_json(
    method: str,
    url: str,
    *,
    token: str | None = None,
    headers: dict[str, str] | None = None,
    payload: dict[str, Any] | None = None,
    form: dict[str, str] | None = None,
    timeout: int = 120,
) -> tuple[dict[str, Any], dict[str, str]]:
    req_headers = dict(headers or {})
    body: bytes | None = None
    if token:
        req_headers["Authorization"] = f"Bearer {token}"
    if payload is not None:
        body = json.dumps(payload).encode("utf-8")
        req_headers.setdefault("Content-Type", "application/json; charset=UTF-8")
    if form is not None:
        body = parse.urlencode(form).encode("utf-8")
        req_headers.setdefault("Content-Type", "application/x-www-form-urlencoded")
    status, resp_headers, data = http_request(method, url, headers=req_headers, body=body, timeout=timeout)
    if not data:
        return {}, resp_headers
    try:
        return json.loads(data.decode("utf-8")), resp_headers
    except json.JSONDecodeError as exc:
        raise UploadError(f"Non-JSON response from {url}: HTTP {status}", body=data[:500].decode("utf-8", "replace")) from exc


def make_multipart(fields: dict[str, str], files: dict[str, tuple[str, bytes, str]] | None = None) -> tuple[bytes, str]:
    boundary = "----idol-upload-" + base64.urlsafe_b64encode(os.urandom(12)).decode("ascii").rstrip("=")
    parts: list[bytes] = []
    for key, value in fields.items():
        parts.append(f"--{boundary}\r\n".encode())
        parts.append(f'Content-Disposition: form-data; name="{key}"\r\n\r\n'.encode())
        parts.append(str(value).encode())
        parts.append(b"\r\n")
    for key, (filename, data, content_type) in (files or {}).items():
        parts.append(f"--{boundary}\r\n".encode())
        parts.append(f'Content-Disposition: form-data; name="{key}"; filename="{filename}"\r\n'.encode())
        parts.append(f"Content-Type: {content_type}\r\n\r\n".encode())
        parts.append(data)
        parts.append(b"\r\n")
    parts.append(f"--{boundary}--\r\n".encode())
    return b"".join(parts), boundary


def token_expired(token_data: dict[str, Any], skew_seconds: int = 90) -> bool:
    expires_at = token_data.get("expires_at")
    if not expires_at:
        return False
    try:
        expires = float(expires_at)
        if expires > 10_000_000_000:
            expires = expires / 1000
        return expires <= datetime.now(timezone.utc).timestamp() + skew_seconds
    except (TypeError, ValueError):
        if isinstance(expires_at, str):
            try:
                parsed = datetime.fromisoformat(expires_at.replace("Z", "+00:00"))
                if parsed.tzinfo is None:
                    parsed = parsed.replace(tzinfo=timezone.utc)
                return parsed.timestamp() <= datetime.now(timezone.utc).timestamp() + skew_seconds
            except ValueError:
                return False
        return False


def refresh_youtube_token(client_secret_path: Path, token_path: Path) -> str:
    token_data = read_json(token_path)
    access_token = token_data.get("access_token", "")
    if access_token and not token_expired(token_data):
        return access_token
    client_document = read_json(client_secret_path)
    installed = client_document.get("installed") or client_document.get("web") or {}
    form = {
        "client_id": installed.get("client_id", ""),
        "client_secret": installed.get("client_secret", ""),
        "refresh_token": token_data.get("refresh_token", ""),
        "grant_type": "refresh_token",
    }
    if not all(form.values()):
        raise UploadError(
            "YouTube OAuth token/client secret is incomplete; run "
            "python3 scripts/idol_youtube_oauth_reauth.py --open-browser",
            retry_safe=True,
        )
    try:
        refreshed, _headers = http_json(
            "POST", "https://oauth2.googleapis.com/token", form=form
        )
    except UploadError as exc:
        raise UploadError(
            "YouTube OAuth refresh failed; run "
            "python3 scripts/idol_youtube_oauth_reauth.py --open-browser",
            status=exc.status,
            retry_safe=True,
        ) from exc
    token = refreshed.get("access_token")
    if not token:
        raise UploadError(
            "YouTube OAuth refresh did not return access_token; run "
            "python3 scripts/idol_youtube_oauth_reauth.py --open-browser",
            retry_safe=True,
        )
    merged = dict(token_data)
    merged.update(refreshed)
    if not refreshed.get("refresh_token") and token_data.get("refresh_token"):
        merged["refresh_token"] = token_data["refresh_token"]
    if refreshed.get("expires_in"):
        merged["expires_at"] = (
            datetime.now(timezone.utc).timestamp() + int(refreshed["expires_in"])
        )
    atomic_write_secret_json(token_path, merged)
    return str(token)


def refresh_tiktok_token(env: dict[str, str], token_path: Path) -> str:
    token_data = read_json(token_path)
    access_token = token_data.get("access_token", "")
    if access_token and not token_expired(token_data):
        return access_token
    form = {
        "client_key": env.get("TIKTOK_CLIENT_KEY", ""),
        "client_secret": env.get("TIKTOK_CLIENT_SECRET", ""),
        "grant_type": "refresh_token",
        "refresh_token": token_data.get("refresh_token", ""),
    }
    if not all(form.values()):
        raise UploadError(
            "TikTok token/client config is incomplete; run "
            "python3 scripts/idol_tiktok_oauth_reauth.py --open-browser",
            retry_safe=True,
        )
    try:
        refreshed, _headers = http_json(
            "POST", "https://open.tiktokapis.com/v2/oauth/token/", form=form
        )
    except UploadError as exc:
        raise UploadError(
            "TikTok OAuth refresh failed; run "
            "python3 scripts/idol_tiktok_oauth_reauth.py --open-browser",
            status=exc.status,
            retry_safe=True,
        ) from exc
    token = refreshed.get("access_token")
    if not token:
        raise UploadError(
            "TikTok OAuth refresh did not return access_token; run "
            "python3 scripts/idol_tiktok_oauth_reauth.py --open-browser",
            retry_safe=True,
        )
    merged = dict(token_data)
    merged.update(refreshed)
    if not refreshed.get("refresh_token") and token_data.get("refresh_token"):
        merged["refresh_token"] = token_data["refresh_token"]
    now = datetime.now(timezone.utc).timestamp()
    if refreshed.get("expires_in"):
        merged["expires_at"] = now + int(refreshed["expires_in"])
    if refreshed.get("refresh_expires_in"):
        merged["refresh_expires_at"] = now + int(refreshed["refresh_expires_in"])
    atomic_write_secret_json(token_path, merged)
    return str(token)


def youtube_upload(row: dict[str, Any], args: argparse.Namespace) -> UploadResult:
    assert_runtime_release_lock(row, args)
    file_path = row_asset_path(row, args)
    token = refresh_youtube_token(Path(args.youtube_client_secret), Path(args.youtube_token))
    assert_runtime_release_lock(row, args)
    file_path = row_asset_path(row, args)
    chunk_size = max(1, args.youtube_chunk_mb) * 1024 * 1024
    expected_asset_sha = args._approved_asset_sha_by_post[str(row.get("post_id") or "")]
    size, chunk_locks = build_verified_chunk_manifest(
        file_path,
        chunk_size=chunk_size,
        expected_sha256=expected_asset_sha,
    )
    tags = public_hashtags(row)
    title = str(row.get("title") or row["caption"].splitlines()[0])[:100]
    description = str(row.get("description") or row["caption"])
    if tags:
        description = description.rstrip() + "\n\n" + " ".join(tags)
    body = {
        "snippet": {
            "title": title,
            "description": description,
            "tags": youtube_tags(row, tags),
            "categoryId": "10",
        },
        "status": {
            "privacyStatus": "private",
            "selfDeclaredMadeForKids": False,
        },
    }
    init_url = "https://www.googleapis.com/upload/youtube/v3/videos?uploadType=resumable&part=snippet,status&notifySubscribers=false"
    init_headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json; charset=UTF-8",
        "X-Upload-Content-Length": str(size),
        "X-Upload-Content-Type": "video/mp4",
    }
    assert_runtime_release_lock(row, args)
    _status, headers, _data = http_request(
        "POST",
        init_url,
        headers=init_headers,
        body=json.dumps(body).encode("utf-8"),
    )
    upload_url = headers.get("Location") or headers.get("location")
    if not upload_url:
        raise UploadError("YouTube resumable upload did not return Location header")
    resp = youtube_resumable_upload(
        upload_url,
        file_path,
        token,
        expected_size=size,
        chunk_locks=chunk_locks,
        runtime_assert=lambda: assert_runtime_release_lock(
            row, args, verify_asset=False
        ),
        timeout=args.youtube_upload_timeout,
    )
    video_id = resp.get("id", "")
    if not video_id:
        raise UploadError("YouTube upload did not return video id", body=json.dumps(resp))
    return UploadResult(
        post_id=row["post_id"],
        platform=row["platform"],
        ok=True,
        draft_status="uploaded_private_draft",
        draft_platform_id=video_id,
        draft_url=f"https://studio.youtube.com/video/{video_id}/edit",
        raw={"privacyStatus": "private"},
        attempt_status="completed",
    )


def youtube_resumable_upload(
    upload_url: str,
    file_path: Path,
    token: str,
    *,
    expected_size: int,
    chunk_locks: list[UploadChunkLock],
    runtime_assert: Callable[[], None],
    timeout: int,
) -> dict[str, Any]:
    lock_by_start = {lock.start: lock for lock in chunk_locks}
    offset = 0
    with file_path.open("rb") as handle:
        while offset < expected_size:
            lock = lock_by_start.get(offset)
            if lock is None:
                raise UploadError(
                    "YouTube resumable upload acknowledged an unverified partial chunk; reconcile before retry"
                )
            chunk = read_verified_chunk(
                handle,
                file_path=file_path,
                expected_size=expected_size,
                lock=lock,
            )
            headers = {
                "Authorization": f"Bearer {token}",
                "Content-Type": "video/mp4",
                "Content-Length": str(len(chunk)),
                "Content-Range": f"bytes {lock.start}-{lock.end}/{expected_size}",
            }
            req = request.Request(upload_url, data=chunk, method="PUT", headers=headers)
            runtime_assert()
            try:
                with request.urlopen(req, timeout=timeout) as resp:
                    payload = resp.read()
                    if not payload:
                        raise UploadError("YouTube upload completed without response body")
                    return json.loads(payload.decode("utf-8"))
            except error.HTTPError as exc:
                if exc.code != 308:
                    payload = exc.read().decode("utf-8", errors="replace")
                    raise UploadError("YouTube chunk upload failed", status=exc.code, body=payload) from exc
                range_header = exc.headers.get("Range") or exc.headers.get("range")
                if range_header and "-" in range_header:
                    offset = int(range_header.rsplit("-", 1)[1]) + 1
                else:
                    offset = lock.end + 1
    raise UploadError("YouTube resumable upload ended before final video response")


def tiktok_upload(row: dict[str, Any], args: argparse.Namespace) -> UploadResult:
    assert_runtime_release_lock(row, args)
    file_path = row_asset_path(row, args)
    env = load_env(Path(args.tiktok_env))
    token = refresh_tiktok_token(env, Path(args.tiktok_token))
    assert_runtime_release_lock(row, args)
    file_path = row_asset_path(row, args)
    size = file_path.stat().st_size
    chunk_size, total_chunk_count = tiktok_upload_plan(size, max_chunk_mb=args.tiktok_max_chunk_mb)
    expected_asset_sha = args._approved_asset_sha_by_post[str(row.get("post_id") or "")]
    size, chunk_locks = build_verified_chunk_manifest(
        file_path,
        chunk_size=chunk_size,
        expected_sha256=expected_asset_sha,
    )
    if len(chunk_locks) != total_chunk_count:
        raise UploadError("TikTok chunk plan changed while binding approved upload bytes")
    api_base = env.get("TIKTOK_API_BASE_URL") or "https://open.tiktokapis.com"
    init_url = api_base.rstrip("/") + "/v2/post/publish/inbox/video/init/"
    init_body = {
        "source_info": {
            "source": "FILE_UPLOAD",
            "video_size": size,
            "chunk_size": chunk_size,
            "total_chunk_count": total_chunk_count,
        }
    }
    assert_runtime_release_lock(row, args)
    resp, _headers = http_json("POST", init_url, token=token, payload=init_body)
    error_info = resp.get("error") or {}
    if error_info.get("code") not in (None, "ok"):
        raise UploadError(f"TikTok init failed: {error_info.get('code')}", body=json.dumps(resp, ensure_ascii=False))
    data = resp.get("data") or {}
    publish_id = data.get("publish_id", "")
    upload_url = data.get("upload_url", "")
    if not publish_id or not upload_url:
        raise UploadError("TikTok init did not return publish_id/upload_url", body=json.dumps(resp))
    tiktok_upload_chunks(
        upload_url,
        file_path,
        size=size,
        chunk_locks=chunk_locks,
        runtime_assert=lambda: assert_runtime_release_lock(
            row, args, verify_asset=False
        ),
    )
    return UploadResult(
        post_id=row["post_id"],
        platform=row["platform"],
        ok=True,
        draft_status="uploaded_tiktok_inbox",
        draft_platform_id=publish_id,
        draft_url=f"tiktok-inbox:{publish_id}",
        raw={"caption_prefill": False},
        attempt_status="completed",
    )


def tiktok_upload_plan(size: int, *, max_chunk_mb: int) -> tuple[int, int]:
    min_chunk = 5 * 1024 * 1024
    max_chunk = max(1, max_chunk_mb) * 1024 * 1024
    max_chunk = min(max_chunk, 64 * 1024 * 1024)
    if size < min_chunk:
        return size, 1
    if size <= max_chunk:
        return size, 1
    total_chunk_count = (size + max_chunk - 1) // max_chunk
    if total_chunk_count > 1000:
        raise UploadError("TikTok upload would require more than 1000 chunks")
    chunk_size = (size + total_chunk_count - 1) // total_chunk_count
    if chunk_size < min_chunk:
        raise UploadError("TikTok upload chunk size would be smaller than 5 MB")
    return chunk_size, total_chunk_count


def tiktok_upload_chunks(
    upload_url: str,
    file_path: Path,
    *,
    size: int,
    chunk_locks: list[UploadChunkLock],
    runtime_assert: Callable[[], None],
) -> None:
    content_type = mimetypes.guess_type(file_path.name)[0] or "video/mp4"
    with file_path.open("rb") as handle:
        for lock in chunk_locks:
            media = read_verified_chunk(
                handle,
                file_path=file_path,
                expected_size=size,
                lock=lock,
            )
            headers = {
                "Content-Type": content_type,
                "Content-Length": str(len(media)),
                "Content-Range": f"bytes {lock.start}-{lock.end}/{size}",
            }
            runtime_assert()
            http_request("PUT", upload_url, headers=headers, body=media, timeout=300)


def x_upload_or_block(row: dict[str, Any], args: argparse.Namespace) -> UploadResult:
    env = load_env(Path(args.x_env))
    scopes = set((env.get("X_OAUTH2_SCOPES") or "").split())
    if not env.get("X_OAUTH2_ACCESS_TOKEN"):
        return UploadResult(
            post_id=row["post_id"],
            platform=row["platform"],
            ok=False,
            draft_status="blocked_missing_x_user_token",
            error="X OAuth2 user access token is not present in the local credential store",
            attempt_status="failed",
        )
    missing = sorted({"tweet.write", "media.write"} - scopes)
    if missing:
        return UploadResult(
            post_id=row["post_id"],
            platform=row["platform"],
            ok=False,
            draft_status="blocked_missing_x_write_scope",
            error="Missing X OAuth scopes: " + ",".join(missing),
            attempt_status="failed",
        )
    return UploadResult(
        post_id=row["post_id"],
        platform=row["platform"],
        ok=False,
        draft_status="blocked_x_use_dedicated_public_api_adapter",
        error="Regular X API has no native draft; use the hash-bound public X adapter",
        attempt_status="failed",
    )


def apply_result(rows: list[dict[str, Any]], result: UploadResult) -> None:
    for row in rows:
        if row.get("post_id") != result.post_id:
            continue
        row["draft_status"] = result.draft_status
        row["draft_platform_id"] = result.draft_platform_id
        row["draft_url"] = result.draft_url
        row["draft_checked_at"] = now_iso()
        if result.error:
            row["draft_error"] = result.error
        else:
            row.pop("draft_error", None)
        return
    raise UploadError(f"Could not find row for result {result.post_id}")


def regenerate_tracker(path: Path, rows: list[dict[str, Any]]) -> None:
    clip_rows: dict[str, dict[str, Any]] = {}
    for row in rows:
        clip_rows.setdefault(row["tracking_code"], row)
    content_id = str(rows[0].get("content_id") or "") if rows else ""
    date_label = path.parent.name[:10] if len(path.parent.name) >= 10 else datetime.now().date().isoformat()
    status = "draft_upload_authorized"
    if any(
        str(row.get("draft_status") or "") not in {"", "not_uploaded"}
        or bool(row.get("draft_checked_at"))
        for row in rows
    ):
        status = "draft_upload_attempted"
    if all((row.get("draft_status") or "").startswith("uploaded_") for row in rows):
        status = "draft_uploaded"
    approval_action = str(rows[0].get("release_approval_action") or "") if rows else ""
    approval_artifact = str(rows[0].get("release_approval_artifact") or "") if rows else ""
    approval_sha = str(rows[0].get("release_approval_artifact_sha256") or "") if rows else ""
    approval_queue_sha = str(rows[0].get("release_approval_queue_sha256") or "") if rows else ""
    package_contract = str(rows[0].get("release_package_contract") or "") if rows else ""
    package_contract_sha = str(rows[0].get("release_package_contract_sha256") or "") if rows else ""
    package_manifest_sha = (
        str(rows[0].get("release_package_deliverable_manifest_sha256") or "")
        if rows
        else ""
    )
    lines = [
        f"# Draft Upload Tracker - {date_label}",
        "",
        f"content_id: `{content_id}`",
        f"status: `{status}`",
        f"release_approval_action: `{approval_action}`",
        f"release_approval_artifact: `{approval_artifact}`",
        f"release_approval_artifact_sha256: `{approval_sha}`",
        f"release_approval_queue_sha256: `{approval_queue_sha}`",
        f"release_package_contract: `{package_contract}`",
        f"release_package_contract_sha256: `{package_contract_sha}`",
        f"release_package_deliverable_manifest_sha256: `{package_manifest_sha}`",
        f"api_upload_quality_profile: `{API_VIDEO_QUALITY_PROFILE}`",
        "",
        "## Rule",
        "",
        "Each platform draft keeps the row's `visible_label`, `tracking_code`, draft status, and platform draft id.",
        "",
        "## Clip Map",
        "",
        "| tracking_code | visible_label | local clip file |",
        "| --- | --- | --- |",
    ]
    for code in sorted(clip_rows):
        row = clip_rows[code]
        local = row["asset_or_clip"]
        lines.append(f"| {code} | {row['visible_label']} | `{local}` |")
    lines.extend(
        [
            "",
            "## Platform Draft Rows",
            "",
            "| post_id | platform | tracking_code | package_output | linkage | quality_profile | quality_receipt | asset_sha256 | snapshot | attempt_id | draft_status | draft_platform_id | draft_url |",
            "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |",
        ]
    )
    for row in rows:
        lines.append(
            "| {post_id} | {platform} | {tracking_code} | {package_output} | {linkage} | {quality_profile} | {quality_receipt} | {asset_sha256} | {snapshot} | {attempt_id} | {draft_status} | {draft_platform_id} | {draft_url} |".format(
                post_id=row["post_id"],
                platform=row["platform"],
                tracking_code=row["tracking_code"],
                package_output=row.get("release_package_output_id", ""),
                linkage=row.get("release_package_linkage", ""),
                quality_profile=row.get("release_api_upload_quality_profile", ""),
                quality_receipt=row.get("release_api_upload_quality_receipt", ""),
                asset_sha256=row.get("release_asset_sha256", ""),
                snapshot=row.get("release_asset_snapshot", ""),
                attempt_id=row.get("upload_attempt_id", ""),
                draft_status=row.get("draft_status", ""),
                draft_platform_id=row.get("draft_platform_id", ""),
                draft_url=row.get("draft_url", ""),
            )
        )
    atomic_write_text(path, "\n".join(lines) + "\n")


def register_title_outputs(rows: list[dict[str, Any]], args: argparse.Namespace) -> dict[str, Any] | None:
    if args.skip_title_registry or not rows:
        return None
    content_id = str(rows[0].get("content_id") or "")
    tracker_path = Path(args._tracker_path)
    log_path = Path(args._log_path)
    run_root = str(args._run_rel)
    outputs: list[dict[str, Any]] = [
        {
            "output_type": "social_asset",
            "path": repo_relative(ROOT, tracker_path),
            "source_run_root": run_root,
            "content_id": content_id,
            "source_step": "social",
            "status": "prepared",
            "notes": "platform draft upload tracker",
        },
        {
            "output_type": "social_asset",
            "path": repo_relative(ROOT, log_path),
            "source_run_root": run_root,
            "content_id": content_id,
            "source_step": "social",
            "status": "prepared",
            "notes": "platform draft upload log",
        },
    ]
    for row in rows:
        if row.get("asset_or_clip"):
            outputs.append(
                {
                    "output_type": "social_asset",
                    "path": row["asset_or_clip"],
                    "source_run_root": run_root,
                    "content_id": content_id,
                    "source_step": "social",
                    "status": "prepared",
                    "notes": f"platform draft row {row.get('post_id', '')}: {row.get('draft_status', '')}",
                }
            )
    registry_path, registry, live_registry_sha = validate_upload_registry(
        path=Path(args._registry_path),
        run_rel=run_root,
        content_id=content_id,
    )
    if live_registry_sha != args._registry_sha:
        raise SocialContractError(
            "title output registry changed after approval validation; upload results were not projected into it"
        )
    title_registry.upsert_source_run(
        registry,
        run_root=run_root,
        content_id=content_id,
    )
    output_ids = [title_registry.upsert_output(registry, output) for output in outputs]
    registry["status"] = "packaged"
    validate_schema(
        registry,
        ROOT / "schemas/title-output-registry.schema.json",
        label="updated title output registry",
    )
    atomic_write_text(
        registry_path,
        yaml.safe_dump(registry, allow_unicode=True, sort_keys=False),
    )
    args._registry_sha = sha256_file(registry_path)
    return {
        "registry_path": repo_relative(ROOT, registry_path),
        "write": True,
        "output_count": len(outputs),
        "output_ids": output_ids,
    }


def select_rows(
    rows: list[dict[str, Any]], platforms: set[str], limit: int | None, retry_failed: bool
) -> list[dict[str, Any]]:
    selected = [
        row
        for row in rows
        if row.get("delivery_mode") == "platform_draft"
        and row.get("platform") in platforms
        and (row.get("draft_status") == "not_uploaded" or (retry_failed and row.get("draft_status") == "failed_api_upload"))
    ]
    return selected[:limit] if limit is not None else selected


def run_one(row: dict[str, Any], args: argparse.Namespace) -> UploadResult:
    platform = row["platform"]
    try:
        assert_runtime_release_lock(row, args)
        if platform in {"youtube", "youtube_shorts"}:
            return youtube_upload(row, args)
        if platform == "tiktok":
            return tiktok_upload(row, args)
        if platform == "x":
            return x_upload_or_block(row, args)
        return UploadResult(
            row["post_id"],
            platform,
            False,
            "blocked_unknown_platform",
            error="Unknown platform",
            attempt_status="failed",
        )
    except UploadError as exc:
        body = f" body={exc.body[:500]}" if exc.body else ""
        status = f" HTTP={exc.status}" if exc.status else ""
        return UploadResult(
            post_id=row["post_id"],
            platform=platform,
            ok=False,
            draft_status="failed_api_upload",
            error=f"{exc}{status}{body}",
            attempt_status="failed" if exc.retry_safe else "unknown",
        )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-root", required=True)
    parser.add_argument("--content-id", required=True)
    parser.add_argument("--queue", required=True, help="Run-owned JSONL queue for this upload batch.")
    parser.add_argument("--tracker", required=True, help="Run-owned Markdown tracker path.")
    parser.add_argument("--log", required=True, help="Run-owned JSONL upload log path.")
    parser.add_argument("--package-contract", help="Exact owning run-root 05-package.yaml.")
    parser.add_argument(
        "--platform",
        action="append",
        choices=["x", "tiktok", "youtube", "youtube_shorts", "instagram_reels"],
    )
    parser.add_argument("--limit", type=int)
    parser.add_argument("--apply", action="store_true", help="Actually call APIs and update local ledgers.")
    parser.add_argument("--approval-artifact", help="Run-owned schema-backed Founder approval proof.")
    parser.add_argument("--approval-sha256", help="Expected SHA-256 of --approval-artifact.")
    parser.add_argument("--retry-failed", action="store_true")
    parser.add_argument("--youtube-client-secret", default=str(DEFAULT_YOUTUBE_CLIENT_SECRET))
    parser.add_argument("--youtube-token", default=str(DEFAULT_YOUTUBE_TOKEN))
    parser.add_argument("--youtube-chunk-mb", type=int, default=16)
    parser.add_argument("--youtube-upload-timeout", type=int, default=180)
    parser.add_argument("--tiktok-env", default=str(DEFAULT_TIKTOK_ENV))
    parser.add_argument("--tiktok-token", default=str(DEFAULT_TIKTOK_TOKEN))
    parser.add_argument("--x-env", default=str(DEFAULT_X_ENV))
    parser.add_argument("--tiktok-max-chunk-mb", type=int, default=64)
    parser.add_argument("--tiktok-delay-seconds", type=float, default=11.0)
    parser.add_argument("--album-key", default=title_registry.DEFAULT_ALBUM_KEY)
    parser.add_argument("--title-key", default=None)
    parser.add_argument("--title", default="")
    parser.add_argument("--skip-title-registry", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.apply and args.skip_title_registry:
        print(
            json.dumps(
                {
                    "mode": "blocked",
                    "error": "--apply cannot use --skip-title-registry; release evidence must update the exact active title registry",
                },
                ensure_ascii=False,
            )
        )
        return 2
    try:
        run_path, run_rel = validate_run_scope(ROOT, args.run_root, args.content_id)
        queue_path, rows, queue_sha = validate_queue_scope(ROOT, run_path, args.content_id, args.queue)
        validate_known_release_platforms(rows)
        tracker_path = validate_run_owned_path(
            ROOT, run_path, args.tracker, "tracker", must_exist=False
        )
        log_path = validate_run_owned_path(ROOT, run_path, args.log, "log", must_exist=False)
        if not args.package_contract:
            raise SocialContractError(
                "--package-contract is required for the package/asset manifest and every apply"
            )
        package_contract_path, package_contract, deliverables = validate_package_contract(
            repo_root=ROOT,
            run_path=run_path,
            content_id=args.content_id,
            package_contract=args.package_contract,
            require_final_lineage=False,
        )
        package_contract_rel = repo_relative(ROOT, package_contract_path)
        package_contract_sha = sha256_file(package_contract_path)
        package_manifest = package_deliverable_manifest(
            repo_root=ROOT,
            run_path=run_path,
            document=package_contract,
            deliverables=deliverables,
        )
        package_manifest_sha = canonical_object_sha256(package_manifest)
        publishing_plan_path = (run_path / "publishing-plan.md").resolve()
        registry_path = intended_registry_path(rows, args)
        registry_sha = ""
        if args.apply:
            registry_path, _registry, registry_sha = validate_upload_registry(
                path=registry_path,
                run_rel=run_rel,
                content_id=args.content_id,
            )
        validate_upload_evidence_lane(
            run_path=run_path,
            queue_path=queue_path,
            tracker_path=tracker_path,
            log_path=log_path,
        )
        validate_pairwise_distinct(
            {
                "queue": queue_path,
                "tracker": tracker_path,
                "log": log_path,
                "05-package.yaml": package_contract_path,
                "publishing-plan.md": publishing_plan_path,
                "title registry": registry_path,
            }
        )
        validate_existing_tracker_owner(tracker_path, args.content_id)
        validate_existing_log_owner(log_path, args.content_id)
    except SocialContractError as exc:
        print(json.dumps({"mode": "blocked", "error": str(exc)}, ensure_ascii=False))
        return 2

    args._run_path = str(run_path)
    args._run_rel = run_rel
    args._queue_path = str(queue_path)
    args._tracker_path = str(tracker_path)
    args._log_path = str(log_path)
    args._queue_sha = queue_sha
    args._package_contract_path = str(package_contract_path)
    args._package_contract_rel = package_contract_rel
    args._package_contract_sha = package_contract_sha
    args._package_manifest_sha = package_manifest_sha
    args._registry_path = str(registry_path)
    args._registry_sha = registry_sha
    args._asset_snapshot_by_post = {}
    args._api_video_quality_by_post = {}
    platforms = set(args.platform or AUTOMATIC_DRAFT_UPLOAD_PLATFORMS)
    try:
        validate_automatic_platform_filters(platforms)
    except SocialContractError as exc:
        print(json.dumps({"mode": "blocked", "error": str(exc)}, ensure_ascii=False))
        return 2
    selected = select_rows(rows, platforms, args.limit, args.retry_failed)
    if not args.apply:
        try:
            asset_linkage_manifest = validate_queue_asset_linkage(
                repo_root=ROOT,
                run_path=run_path,
                rows=selected,
                deliverables=deliverables,
            )
            api_video_quality = validate_api_upload_video_rows(selected, args)
        except (SocialContractError, UploadError) as exc:
            print(json.dumps({"mode": "blocked", "error": str(exc)}, ensure_ascii=False))
            return 2
        print(
            json.dumps(
                {
                    "mode": "dry_run",
                    "run_root": run_rel,
                    "content_id": args.content_id,
                    "queue": repo_relative(ROOT, queue_path),
                    "queue_sha256": queue_sha,
                    "package_contract": package_contract_rel,
                    "package_contract_sha256": package_contract_sha,
                    "package_schema_version": package_manifest["schema_version"],
                    "package_content_id": package_manifest["content_id"],
                    "package_deliverable_manifest_sha256": package_manifest_sha,
                    "package_deliverables": package_manifest["deliverables"],
                    "tracker": repo_relative(ROOT, tracker_path),
                    "log": repo_relative(ROOT, log_path),
                    "selected": [row["post_id"] for row in selected],
                    "approval_assets": asset_linkage_manifest,
                    "api_video_quality": api_video_quality,
                    "approval_required_for_apply": True,
                    "external_actions": 0,
                },
                ensure_ascii=False,
                indent=2,
            )
        )
        return 0
    if not args.approval_artifact or not args.approval_sha256:
        print(
            json.dumps(
                {
                    "mode": "blocked",
                    "error": "--apply requires --approval-artifact and --approval-sha256",
                },
                ensure_ascii=False,
            )
        )
        return 2
    try:
        if not publishing_plan_path.is_file():
            raise SocialContractError(
                "--apply requires the run-root active publishing-plan.md"
            )
        if publishing_plan_validator.detect_mode(publishing_plan_path) != "active":
            raise SocialContractError(
                "publishing record is immutable closed state; draft upload cannot mutate it"
            )
        publishing_plan_contract = publishing_plan_validator.extract_contract(
            publishing_plan_path, mode="active"
        )
        validate_schema(
            publishing_plan_contract,
            ROOT / "schemas/publishing-plan.schema.json",
            label="active publishing plan",
        )
        if str(publishing_plan_contract.get("content_id") or "") != args.content_id:
            raise SocialContractError(
                "active publishing-plan.md content_id does not match --content-id"
            )
        approval_path, approval, approval_sha = validate_approval_artifact(
            repo_root=ROOT,
            run_path=run_path,
            run_rel=run_rel,
            content_id=args.content_id,
            queue_path=queue_path,
            queue_rows=rows,
            queue_sha256=queue_sha,
            package_contract_path=package_contract_path,
            package_contract_sha256=package_contract_sha,
            package_deliverable_manifest_sha256=package_manifest_sha,
            artifact=args.approval_artifact,
            expected_sha256=args.approval_sha256,
            required_action="platform_draft_upload",
        )
        approved_platforms = set(approval.get("approved_platforms") or [])
        approved_post_ids = set(approval.get("approved_post_ids") or [])
        approved_asset_sha_by_post = {
            str(item.get("post_id") or ""): str(item.get("sha256") or "")
            for item in (approval.get("approved_assets") or [])
        }
        args._approved_asset_sha_by_post = approved_asset_sha_by_post
        approval_rel = repo_relative(ROOT, approval_path)
        validate_pairwise_distinct(
            {
                "queue": queue_path,
                "tracker": tracker_path,
                "log": log_path,
                "05-package.yaml": package_contract_path,
                "publishing-plan.md": publishing_plan_path,
                "Founder approval": approval_path,
                "title registry": registry_path,
            }
        )
        pending_attempts = unresolved_attempts(run_path, args.content_id)
        if pending_attempts:
            raise SocialContractError(
                "unresolved started/unknown upload attempt blocks automatic retry: "
                + ", ".join(
                    f"{item['attempt_id']}[{item['post_id']}:{item['status']}]"
                    for item in pending_attempts
                )
            )
        queue_by_id = {str(row.get("post_id") or ""): row for row in rows}
        missing_approved = sorted(approved_post_ids - set(queue_by_id))
        if missing_approved:
            raise SocialContractError(
                "approval names post IDs absent from the exact queue: " + ", ".join(missing_approved)
            )
        wrong_delivery = sorted(
            post_id
            for post_id in approved_post_ids
            if queue_by_id[post_id].get("delivery_mode") != "platform_draft"
        )
        if wrong_delivery:
            raise SocialContractError(
                "approval names rows outside delivery_mode=platform_draft: "
                + ", ".join(wrong_delivery)
            )
        wrong_platform = sorted(
            post_id
            for post_id in approved_post_ids
            if str(queue_by_id[post_id].get("platform") or "") not in approved_platforms
        )
        if wrong_platform:
            raise SocialContractError(
                "approval post/platform scope is inconsistent for: " + ", ".join(wrong_platform)
            )
        approved_batch_rows = [
            queue_by_id[post_id] for post_id in sorted(approved_post_ids)
        ]
        asset_linkage_manifest = validate_queue_asset_linkage(
            repo_root=ROOT,
            run_path=run_path,
            rows=approved_batch_rows,
            deliverables=deliverables,
        )
        linkage_by_post = {item["post_id"]: item for item in asset_linkage_manifest}
        selected = [
            row
            for row in select_rows(rows, platforms, None, args.retry_failed)
            if row.get("post_id") in approved_post_ids and row.get("platform") in approved_platforms
        ]
        if args.limit is not None:
            selected = selected[: args.limit]
        if not selected:
            raise SocialContractError("approval and CLI filters select no runnable queue rows")
        api_video_quality = validate_api_upload_video_rows(selected, args)
        args._api_video_quality_by_post = {
            item["post_id"]: item for item in api_video_quality
        }
        validate_platform_auth_preflight(
            {str(row.get("platform") or "") for row in selected}
        )
        for row in selected:
            row_asset_path(row, args)
        snapshot_by_post: dict[str, str] = {}
        for row in selected:
            snapshot_path, _snapshot_sha = snapshot_approved_asset(row, args)
            snapshot_by_post[str(row.get("post_id") or "")] = str(snapshot_path)
        args._asset_snapshot_by_post = snapshot_by_post
        args._approval_path = str(approval_path)
        args._approval_rel = approval_rel
        args._approval_sha = approval_sha
        if sha256_file(package_contract_path) != package_contract_sha:
            raise SocialContractError("05-package.yaml changed after apply validation")
        if sha256_file(approval_path) != approval_sha:
            raise SocialContractError("Founder approval artifact changed after apply validation")
    except (SocialContractError, UploadError) as exc:
        print(json.dumps({"mode": "blocked", "error": str(exc)}, ensure_ascii=False))
        return 2

    tracker_path.parent.mkdir(parents=True, exist_ok=True)
    log_path.parent.mkdir(parents=True, exist_ok=True)
    approval_stamp = {
        "release_approval_status": "approved_for_platform_draft_upload",
        "release_approval_source": str(approval.get("approval_source") or ""),
        "release_approval_artifact": approval_rel,
        "release_approval_artifact_sha256": approval_sha,
        "release_approval_queue_sha256": queue_sha,
        "release_approval_action": "platform_draft_upload",
        "release_approval_updated_at": str(approval.get("approved_at_kst") or ""),
        "release_approved_at": str(approval.get("approved_at_kst") or ""),
        "release_package_contract": package_contract_rel,
        "release_package_contract_sha256": package_contract_sha,
        "release_package_deliverable_manifest_sha256": package_manifest_sha,
        "release_provenance_version": RELEASE_PROVENANCE_VERSION,
        "release_production_graph_trace_sha256": package_manifest[
            "production_graph_trace_sha256"
        ],
    }
    manifest_output_by_id = {
        str(item.get("output_id") or ""): item
        for item in package_manifest["deliverables"]
    }
    for row in rows:
        post_id = str(row.get("post_id") or "")
        if post_id not in approved_post_ids:
            continue
        row.update(approval_stamp)
        row["release_asset_sha256"] = approved_asset_sha_by_post[post_id]
        quality = args._api_video_quality_by_post.get(post_id, {})
        row["release_api_upload_quality_profile"] = quality.get(
            "quality_profile", ""
        )
        row["release_api_upload_quality_receipt"] = quality.get(
            "quality_receipt", ""
        )
        row["release_api_upload_quality_receipt_sha256"] = quality.get(
            "quality_receipt_sha256", ""
        )
        linkage = linkage_by_post[post_id]
        row["release_package_output_id"] = linkage["package_output_id"]
        row["release_package_output_role"] = linkage["package_output_role"]
        row["release_package_linkage"] = linkage["linkage"]
        graph_binding = manifest_output_by_id[linkage["package_output_id"]]
        row["release_edit_segment_ids"] = list(graph_binding["edit_segment_ids"])
        row["release_screen_progression_node_ids"] = list(
            graph_binding["screen_progression_node_ids"]
        )
        row["release_section_ids"] = list(graph_binding["section_ids"])
        snapshot = args._asset_snapshot_by_post.get(post_id)
        if snapshot:
            row["release_asset_snapshot"] = repo_relative(ROOT, snapshot)
            row["release_asset_snapshot_sha256"] = approved_asset_sha_by_post[post_id]
    for row in selected:
        ensure_public_metadata(row)
    write_rows(queue_path, rows)
    approved_batch_rows = [item for item in rows if item.get("post_id") in approved_post_ids]
    regenerate_tracker(tracker_path, approved_batch_rows)

    results: list[UploadResult] = []
    attempt_records: list[str] = []
    for index, row in enumerate(selected):
        try:
            assert_runtime_release_lock(row, args)
        except (SocialContractError, UploadError) as exc:
            print(json.dumps({"mode": "blocked", "error": str(exc)}, ensure_ascii=False))
            return 2 if not results else 1
        snapshot_path = Path(args._asset_snapshot_by_post[str(row.get("post_id") or "")])
        attempt_path, attempt_document = create_attempt_intent(
            row=row,
            args=args,
            snapshot_path=snapshot_path,
            snapshot_sha=approved_asset_sha_by_post[str(row.get("post_id") or "")],
        )
        row["upload_attempt_id"] = attempt_document["attempt_id"]
        row["upload_attempt_record"] = repo_relative(ROOT, attempt_path)
        row["draft_status"] = "upload_in_progress"
        row["draft_checked_at"] = attempt_document["started_at"]
        write_rows(queue_path, rows)
        regenerate_tracker(tracker_path, approved_batch_rows)
        result = run_one(row, args)
        finalize_attempt(attempt_path, attempt_document, result)
        attempt_records.append(repo_relative(ROOT, attempt_path))
        results.append(result)
        apply_result(rows, result)
        if not result.ok and result.attempt_status == "unknown":
            row["draft_attempt_reconciliation_required"] = True
        else:
            row.pop("draft_attempt_reconciliation_required", None)
        write_rows(queue_path, rows)
        append_log(log_path, result, args.content_id, row)
        regenerate_tracker(tracker_path, approved_batch_rows)
        print(json.dumps(result.__dict__, ensure_ascii=False, separators=(",", ":")), flush=True)
        next_row = selected[index + 1] if index + 1 < len(selected) else None
        if result.platform == "tiktok" and result.ok and next_row and next_row.get("platform") == "tiktok":
            time.sleep(args.tiktok_delay_seconds)
    attempted_post_ids = {result.post_id for result in results}
    try:
        registry = register_title_outputs(
            [row for row in rows if row.get("post_id") in attempted_post_ids], args
        )
    except (SocialContractError, ValueError, OSError) as exc:
        print(
            json.dumps(
                {
                    "mode": "blocked_post_upload_registry_update",
                    "error": str(exc),
                    "attempt_records": attempt_records,
                },
                ensure_ascii=False,
            )
        )
        return 1
    ok_count = sum(1 for result in results if result.ok)
    print(
        json.dumps(
            {
                "done": len(results),
                "ok": ok_count,
                "failed_or_blocked": len(results) - ok_count,
                "attempt_records": attempt_records,
                "title_registry": registry,
            },
            ensure_ascii=False,
        )
    )
    return 0 if all(result.ok for result in results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
