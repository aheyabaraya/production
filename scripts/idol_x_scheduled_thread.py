#!/usr/bin/env python3
"""Publish one approved CF X reply-chain at a local scheduled time.

The standard X API does not expose a native draft or schedule object. This
adapter keeps the queue local until it is due, then uses the regular X API v2
with an OAuth 2.0 *user* token. It never opens a browser, calls an Ads endpoint,
prints credentials, or stores API response bodies.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import mimetypes
import os
import re
import secrets
import sys
import time
import uuid
from datetime import datetime
from pathlib import Path
from typing import Any
from urllib import error, parse, request
from zoneinfo import ZoneInfo

from lib.idol_platform_credentials import load_env
from lib.idol_api_video_quality import ApiVideoQualityError, inspect_api_upload_video


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_X_ENV = ROOT / ".runtime" / "secrets" / "x.env"
API_ROOT = "https://api.x.com/2"
TOKEN_ENDPOINT = "https://api.x.com/2/oauth2/token"
KST = ZoneInfo("Asia/Seoul")
CHUNK_SIZE = 4 * 1024 * 1024
MAX_PROCESSING_POLLS = 30
CF_RUN_ROOT_RE = re.compile(r"^cf/runs/(CF_[A-Z0-9][A-Z0-9_-]{2,120})$")


class ScheduledPostError(RuntimeError):
    """A safe execution failure whose message contains no secret values."""


def now_kst() -> datetime:
    return datetime.now(KST)


def iso_now() -> str:
    return now_kst().isoformat(timespec="seconds")


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def repo_path(relative: Any, *, kind: str, required: bool = True) -> Path:
    raw = str(relative or "")
    if not raw or Path(raw).is_absolute():
        raise ScheduledPostError(f"{kind} path must be a non-empty repository-relative path")
    candidate = (ROOT / raw).resolve()
    try:
        candidate.relative_to(ROOT)
    except ValueError as exc:
        raise ScheduledPostError(f"{kind} path escapes the repository") from exc
    if required and not candidate.exists():
        raise ScheduledPostError(f"{kind} is missing")
    if required and kind.endswith("file") and not candidate.is_file():
        raise ScheduledPostError(f"{kind} is not a file")
    return candidate


def require_inside(path: Path, parent: Path, *, kind: str) -> None:
    try:
        path.relative_to(parent)
    except ValueError as exc:
        raise ScheduledPostError(f"{kind} must stay inside the owning CF run") from exc


def parse_kst(value: Any, *, label: str) -> datetime:
    try:
        parsed = datetime.fromisoformat(str(value))
    except ValueError as exc:
        raise ScheduledPostError(f"{label} must be ISO-8601 with a timezone") from exc
    if parsed.tzinfo is None:
        raise ScheduledPostError(f"{label} must include a timezone")
    return parsed.astimezone(KST)


def read_json(path: Path, *, label: str) -> tuple[dict[str, Any], bytes]:
    try:
        raw = path.read_bytes()
        document = json.loads(raw.decode("utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ScheduledPostError(f"{label} is not valid JSON") from exc
    if not isinstance(document, dict):
        raise ScheduledPostError(f"{label} must be a JSON object")
    return document, raw


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
    finally:
        if temporary.exists():
            temporary.unlink()


def result_path_for(queue_path: Path) -> Path:
    return queue_path.with_name(f"{queue_path.stem}.result.json")


def queue_asset_rows(posts: list[dict[str, Any]]) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    for post in posts:
        for attachment in post.get("attachments") or []:
            rows.append(
                {
                    "post_id": str(post["post_id"]),
                    "path": str(attachment["path"]),
                    "sha256": str(attachment["sha256"]),
                }
            )
    return rows


def validate_queue(queue_path: Path) -> tuple[dict[str, Any], list[dict[str, Any]], str, Path]:
    queue, raw_queue = read_json(queue_path, label="scheduled queue")
    required = {
        "schema_version",
        "queue_id",
        "status",
        "run_root",
        "content_id",
        "account_handle",
        "claim_guard",
        "scheduled_at",
        "expires_at",
        "source_packet",
        "approval_path",
        "thread",
    }
    if not required.issubset(queue):
        raise ScheduledPostError("scheduled queue is missing required fields")
    if queue.get("schema_version") != "cf_x_scheduled_thread.v1":
        raise ScheduledPostError("unsupported scheduled-queue schema")
    if queue.get("status") != "scheduled":
        raise ScheduledPostError("scheduled queue is not in scheduled state")
    run_root_rel = str(queue["run_root"])
    match = CF_RUN_ROOT_RE.fullmatch(run_root_rel)
    if not match or str(queue["content_id"]) != match.group(1):
        raise ScheduledPostError("queue content_id and CF run_root do not match")
    run_root = repo_path(run_root_rel, kind="CF run directory")
    if not run_root.is_dir():
        raise ScheduledPostError("owning CF run is not a directory")
    require_inside(queue_path, run_root, kind="scheduled queue")
    if not re.fullmatch(r"[A-Za-z0-9_]{1,32}", str(queue["account_handle"])):
        raise ScheduledPostError("account_handle is invalid")
    claim_guard = str(queue["claim_guard"] or "").strip()
    if not claim_guard:
        raise ScheduledPostError("queue claim_guard is required")
    scheduled_at = parse_kst(queue["scheduled_at"], label="scheduled_at")
    expires_at = parse_kst(queue["expires_at"], label="expires_at")
    if expires_at <= scheduled_at:
        raise ScheduledPostError("expires_at must be after scheduled_at")

    source_packet = queue.get("source_packet")
    if not isinstance(source_packet, dict):
        raise ScheduledPostError("source_packet must be an object")
    packet_path = repo_path(source_packet.get("path"), kind="source packet file")
    require_inside(packet_path, run_root, kind="source packet")
    if sha256_file(packet_path) != str(source_packet.get("sha256") or ""):
        raise ScheduledPostError("source packet bytes changed after the queue was prepared")

    thread = queue.get("thread")
    posts = thread.get("posts") if isinstance(thread, dict) else None
    if not isinstance(posts, list) or not posts:
        raise ScheduledPostError("scheduled queue needs at least one thread post")
    seen_post_ids: set[str] = set()
    for index, post in enumerate(posts):
        if not isinstance(post, dict):
            raise ScheduledPostError("thread post must be an object")
        post_id = str(post.get("post_id") or "")
        if not post_id or post_id in seen_post_ids:
            raise ScheduledPostError("thread post IDs must be present and unique")
        seen_post_ids.add(post_id)
        parent = None if index == 0 else str(posts[index - 1].get("post_id") or "")
        if post.get("reply_to") != parent:
            raise ScheduledPostError("thread must be one ordered root-to-reply chain")
        text = str(post.get("text") or "")
        if not text or len(text) > 280:
            raise ScheduledPostError(f"{post_id}: post text must be 1–280 characters")
        if "http://" in text.lower() or "https://" in text.lower():
            raise ScheduledPostError(f"{post_id}: URLs are disallowed for this no-link queue")
        if post.get("made_with_ai") is not True:
            raise ScheduledPostError(f"{post_id}: made_with_ai must be true")
        attachments = post.get("attachments") or []
        if not isinstance(attachments, list) or len(attachments) > 4:
            raise ScheduledPostError(f"{post_id}: attachments must contain 0–4 items")
        categories: set[str] = set()
        for attachment in attachments:
            if not isinstance(attachment, dict):
                raise ScheduledPostError(f"{post_id}: attachment must be an object")
            category = str(attachment.get("media_category") or "")
            if category not in {"tweet_image", "tweet_video"}:
                raise ScheduledPostError(f"{post_id}: unsupported media category")
            categories.add(category)
            asset_path = repo_path(attachment.get("path"), kind="attachment file")
            require_inside(asset_path, run_root, kind="attachment")
            expected_sha = str(attachment.get("sha256") or "")
            if not re.fullmatch(r"[0-9a-f]{64}", expected_sha) or sha256_file(asset_path) != expected_sha:
                raise ScheduledPostError(f"{post_id}: approved attachment bytes changed")
            if category == "tweet_video":
                try:
                    inspect_api_upload_video(asset_path)
                except ApiVideoQualityError as exc:
                    raise ScheduledPostError(f"{post_id}: {exc}") from exc
        if "tweet_video" in categories and len(attachments) != 1:
            raise ScheduledPostError(f"{post_id}: a video cannot share a post with other attachments")
        if index == 0:
            # Root may be CF video, stills board drop (1–4 tweet_image), or text-only.
            if len(attachments) == 1:
                if str(attachments[0].get("media_category")) not in {"tweet_video", "tweet_image"}:
                    raise ScheduledPostError(
                        f"{post_id}: single root attachment must be tweet_video or tweet_image"
                    )
            elif len(attachments) > 1:
                if categories != {"tweet_image"}:
                    raise ScheduledPostError(
                        f"{post_id}: multi-attachment root must be tweet_image only (1–4 stills)"
                    )
            folded = text.lower()
            has_legacy_stack = "made with gpt + grok" in folded
            has_query_stack = ("grok build" in folded and "grok imagine" in folded) or (
                "made with grok build" in folded
            )
            has_gpt_image_only = "made with gpt image" in folded
            if not (has_legacy_stack or has_query_stack or has_gpt_image_only):
                raise ScheduledPostError(
                    f"{post_id}: root must disclose stack credit "
                    "(Made with Grok Imagine · Grok Build., Made with GPT + Grok., "
                    "or made with GPT image)"
                )
            if claim_guard.lower() not in folded:
                raise ScheduledPostError(f"{post_id}: root must include the exact claim guard")
    return queue, posts, sha256_bytes(raw_queue), run_root


def validate_approval(
    queue_path: Path,
    queue: dict[str, Any],
    posts: list[dict[str, Any]],
    queue_sha256: str,
    run_root: Path,
) -> None:
    approval_rel = str(queue.get("approval_path") or "")
    if not approval_rel:
        raise ScheduledPostError("queue has no founder approval artifact")
    approval_path = repo_path(approval_rel, kind="approval artifact file")
    require_inside(approval_path, run_root, kind="approval artifact")
    approval, _raw = read_json(approval_path, label="approval artifact")
    required = {
        "schema_version",
        "approval_id",
        "status",
        "run_root",
        "content_id",
        "queue_path",
        "queue_sha256",
        "allowed_action",
        "approved_post_ids",
        "approved_assets",
        "founder_explicit_approval",
        "approval_source",
        "approved_at_kst",
    }
    if not required.issubset(approval):
        raise ScheduledPostError("approval artifact is missing required fields")
    if approval.get("schema_version") != "cf_x_public_release_approval.v1":
        raise ScheduledPostError("unsupported approval schema")
    if approval.get("status") != "active" or approval.get("allowed_action") != "public_publish":
        raise ScheduledPostError("approval artifact does not allow public publishing")
    if approval.get("founder_explicit_approval") is not True:
        raise ScheduledPostError("approval artifact lacks explicit founder approval")
    if approval.get("run_root") != queue["run_root"] or approval.get("content_id") != queue["content_id"]:
        raise ScheduledPostError("approval artifact targets a different CF run")
    if approval.get("queue_path") != str(queue_path.relative_to(ROOT)) or approval.get("queue_sha256") != queue_sha256:
        raise ScheduledPostError("approval artifact is not bound to the exact scheduled queue")
    post_ids = [str(post["post_id"]) for post in posts]
    if approval.get("approved_post_ids") != post_ids:
        raise ScheduledPostError("approval artifact does not approve this exact reply chain")
    approved_assets = approval.get("approved_assets")
    if not isinstance(approved_assets, list) or approved_assets != queue_asset_rows(posts):
        raise ScheduledPostError("approval artifact does not bind the exact attachment set")
    if not str(approval.get("approval_source") or "").strip() or not str(approval.get("approved_at_kst") or "").strip():
        raise ScheduledPostError("approval artifact needs source and KST time")


def multipart_body(
    fields: dict[str, str],
    *,
    file_field: str = "",
    file_name: str = "",
    file_bytes: bytes = b"",
    mime_type: str = "application/octet-stream",
) -> tuple[bytes, str]:
    boundary = f"----idol-x-{uuid.uuid4().hex}"
    parts: list[bytes] = []
    for key, value in fields.items():
        parts.extend(
            [
                f"--{boundary}\r\n".encode(),
                f'Content-Disposition: form-data; name="{key}"\r\n\r\n'.encode(),
                str(value).encode(),
                b"\r\n",
            ]
        )
    if file_field:
        safe_name = Path(file_name).name.replace('"', "")
        parts.extend(
            [
                f"--{boundary}\r\n".encode(),
                f'Content-Disposition: form-data; name="{file_field}"; filename="{safe_name}"\r\n'.encode(),
                f"Content-Type: {mime_type}\r\n\r\n".encode(),
                file_bytes,
                b"\r\n",
            ]
        )
    parts.append(f"--{boundary}--\r\n".encode())
    return b"".join(parts), f"multipart/form-data; boundary={boundary}"


def _replace_env_values(path: Path, updates: dict[str, str]) -> None:
    """Rewrite named keys in x.env without printing secret values."""
    original = path.read_text(encoding="utf-8") if path.exists() else ""
    lines = original.splitlines()
    seen: set[str] = set()
    output: list[str] = []
    for line in lines:
        stripped = line.strip()
        key = stripped.split("=", 1)[0].strip() if "=" in stripped else ""
        if key in updates:
            output.append(f"{key}={updates[key]}")
            seen.add(key)
        else:
            output.append(line)
    for key, value in updates.items():
        if key not in seen:
            output.append(f"{key}={value}")
    text = "\n".join(output).rstrip("\n") + "\n"
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.refresh-{secrets.token_hex(8)}.tmp")
    try:
        temporary.write_text(text, encoding="utf-8")
        os.chmod(temporary, 0o600)
        os.replace(temporary, path)
    finally:
        if temporary.exists():
            temporary.unlink()


def refresh_x_user_token(*, env_path: Path = DEFAULT_X_ENV) -> str:
    """Refresh the OAuth2 user access token from the stored refresh token.

    Access tokens expire (often ~2h). Browser reauth is only needed when the
    refresh token itself is revoked. Never prints secret values.
    """
    values = load_env(env_path)
    client_id = (values.get("X_OAUTH2_CLIENT_ID") or "").strip()
    client_secret = (values.get("X_OAUTH2_CLIENT_SECRET") or "").strip()
    refresh_token = (values.get("X_OAUTH2_REFRESH_TOKEN") or "").strip()
    if not client_id or not refresh_token:
        raise ScheduledPostError(
            "X OAuth refresh is not configured (need client_id + refresh_token presence)"
        )
    form: dict[str, str] = {
        "grant_type": "refresh_token",
        "refresh_token": refresh_token,
        "client_id": client_id,
    }
    headers = {"Content-Type": "application/x-www-form-urlencoded"}
    if client_secret:
        basic = base64.b64encode(f"{client_id}:{client_secret}".encode("utf-8")).decode("ascii")
        headers["Authorization"] = f"Basic {basic}"
    req = request.Request(
        TOKEN_ENDPOINT,
        data=parse.urlencode(form).encode("utf-8"),
        method="POST",
        headers=headers,
    )
    try:
        with request.urlopen(req, timeout=60) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except error.HTTPError as exc:
        raise ScheduledPostError(
            f"X OAuth refresh failed with HTTP {exc.code}; browser reauth required"
        ) from exc
    except error.URLError as exc:
        raise ScheduledPostError("X OAuth refresh could not reach the token endpoint") from exc
    access = str(payload.get("access_token") or "").strip()
    if not access:
        raise ScheduledPostError("X OAuth refresh returned no access_token")
    updates = {"X_OAUTH2_ACCESS_TOKEN": access}
    new_refresh = str(payload.get("refresh_token") or "").strip()
    if new_refresh:
        updates["X_OAUTH2_REFRESH_TOKEN"] = new_refresh
    _replace_env_values(env_path, updates)
    return access


def load_runtime_x_token(*, force_refresh: bool = False) -> str:
    """Return a usable access token, refreshing first when needed."""
    if force_refresh:
        return refresh_x_user_token()
    values = load_env(DEFAULT_X_ENV)
    token = (values.get("X_OAUTH2_ACCESS_TOKEN") or "").strip()
    # Prefer proactive refresh when a refresh token is present so apply is not
    # blocked by an expired access token from an earlier session.
    if (values.get("X_OAUTH2_REFRESH_TOKEN") or "").strip():
        try:
            return refresh_x_user_token()
        except ScheduledPostError:
            if token:
                return token
            raise
    if not token:
        raise ScheduledPostError("X OAuth 2.0 user token is not available")
    return token


def api_request(
    token: str,
    method: str,
    path: str,
    *,
    body: bytes | None = None,
    content_type: str = "",
    query: dict[str, str] | None = None,
) -> dict[str, Any]:
    url = f"{API_ROOT}{path}"
    if query:
        url += "?" + parse.urlencode(query)
    headers = {"Authorization": f"Bearer {token}", "User-Agent": "IDOL-CF-X-Scheduled-Thread/1.0"}
    if content_type:
        headers["Content-Type"] = content_type
    req = request.Request(url, data=body, headers=headers, method=method)
    try:
        with request.urlopen(req, timeout=90) as response:
            payload = response.read()
    except error.HTTPError as exc:
        # Safe short reason only: HTTP code + X error titles (no tokens/bodies dumped).
        reason = f"HTTP {exc.code}"
        try:
            raw = exc.read()
            decoded = json.loads(raw.decode("utf-8", errors="replace"))
            titles = []
            if isinstance(decoded, dict):
                if decoded.get("title"):
                    titles.append(str(decoded.get("title"))[:80])
                if decoded.get("detail"):
                    titles.append(str(decoded.get("detail"))[:120])
                for item in decoded.get("errors") or []:
                    if isinstance(item, dict):
                        msg = item.get("message") or item.get("title") or item.get("detail")
                        if msg:
                            titles.append(str(msg)[:120])
            if titles:
                reason = f"HTTP {exc.code}: {' | '.join(titles[:3])}"
        except Exception:
            pass
        raise ScheduledPostError(f"X API request failed with {reason}") from exc
    except error.URLError as exc:
        raise ScheduledPostError("X API request could not reach the service") from exc
    try:
        decoded = json.loads(payload.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ScheduledPostError("X API returned a non-JSON response") from exc
    if not isinstance(decoded, dict):
        raise ScheduledPostError("X API returned an unexpected response")
    return decoded


def upload_media(token: str, attachment: dict[str, Any]) -> str:
    """Chunked upload via X API v2 dedicated media endpoints."""

    path = repo_path(attachment["path"], kind="attachment file")
    if sha256_file(path) != attachment["sha256"]:
        raise ScheduledPostError("approved attachment bytes changed before upload")
    category = str(attachment["media_category"])
    if category == "tweet_video":
        try:
            inspect_api_upload_video(path)
        except ApiVideoQualityError as exc:
            raise ScheduledPostError(str(exc)) from exc
    mime_type = str(attachment.get("media_type") or mimetypes.guess_type(path.name)[0] or "application/octet-stream")
    total_bytes = path.stat().st_size
    if total_bytes <= 0:
        raise ScheduledPostError("approved attachment is empty")

    # New v2 endpoints (command=INIT/APPEND/FINALIZE on /media/upload is retired).
    init_payload = {
        "media_type": mime_type,
        "total_bytes": total_bytes,
        "media_category": category,
    }
    initialized = api_request(
        token,
        "POST",
        "/media/upload/initialize",
        body=json.dumps(init_payload).encode("utf-8"),
        content_type="application/json",
    )
    media_id = str((initialized.get("data") or {}).get("id") or "")
    if not media_id:
        raise ScheduledPostError("X API did not return a media ID")

    with path.open("rb") as handle:
        segment = 0
        while chunk := handle.read(CHUNK_SIZE):
            append_body, append_type = multipart_body(
                {"segment_index": str(segment)},
                file_field="media",
                file_name=path.name,
                file_bytes=chunk,
                mime_type=mime_type,
            )
            api_request(
                token,
                "POST",
                f"/media/upload/{media_id}/append",
                body=append_body,
                content_type=append_type,
            )
            segment += 1

    finalized = api_request(
        token,
        "POST",
        f"/media/upload/{media_id}/finalize",
        body=b"{}",
        content_type="application/json",
    )
    processing = (finalized.get("data") or {}).get("processing_info") or {}
    for _ in range(MAX_PROCESSING_POLLS):
        state = str(processing.get("state") or "succeeded")
        if state == "succeeded":
            return media_id
        if state == "failed":
            raise ScheduledPostError("X rejected media processing")
        time.sleep(min(max(int(processing.get("check_after_secs") or 2), 1), 15))
        status = api_request(token, "GET", f"/media/upload", query={"command": "STATUS", "media_id": media_id})
        # Prefer dedicated status if available; fall back to command=STATUS.
        if not (status.get("data") or {}).get("processing_info"):
            try:
                status = api_request(token, "GET", f"/media/upload/{media_id}/status")
            except ScheduledPostError:
                pass
        processing = (status.get("data") or {}).get("processing_info") or {}
    raise ScheduledPostError("X media processing did not finish within the safe polling limit")


def create_post(token: str, post: dict[str, Any], parent_platform_id: str = "") -> str:
    media_ids = [upload_media(token, attachment) for attachment in post.get("attachments") or []]
    payload: dict[str, Any] = {"text": post["text"], "made_with_ai": True}
    if media_ids:
        payload["media"] = {"media_ids": media_ids}
    if parent_platform_id:
        payload["reply"] = {"in_reply_to_tweet_id": parent_platform_id}
    response = api_request(
        token,
        "POST",
        "/tweets",
        body=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
        content_type="application/json",
    )
    platform_id = str((response.get("data") or {}).get("id") or "")
    if not platform_id:
        raise ScheduledPostError("X API did not return a post ID")
    return platform_id


def dry_run_report(
    queue_path: Path,
    queue: dict[str, Any],
    posts: list[dict[str, Any]],
    queue_sha256: str,
    run_root: Path,
) -> dict[str, Any]:
    approval = "pending"
    try:
        validate_approval(queue_path, queue, posts, queue_sha256, run_root)
        approval = "ready"
    except ScheduledPostError:
        pass
    return {
        "mode": "dry_run",
        "queue": str(queue_path.relative_to(ROOT)),
        "scheduled_at": queue["scheduled_at"],
        "post_count": len(posts),
        "approval": approval,
        "estimated_no_url_post_creates_usd": f"{0.015 * len(posts):.3f}",
        "network_requests": 0,
        "checks": [
            "CF_run_scope", "packet_hash", "asset_hashes", "reply_chain",
            "no_urls", "AI_disclosure", "claim_guard",
            "tweet_video_2k30_high_quality_no_transcode",
        ],
    }


def execute(
    queue_path: Path,
    queue: dict[str, Any],
    posts: list[dict[str, Any]],
    token: str,
) -> dict[str, Any]:
    result_path = result_path_for(queue_path)
    existing: dict[str, Any] = {}
    if result_path.exists():
        existing, _ = read_json(result_path, label="execution result")
    if existing.get("status") == "completed":
        return existing
    result = {
        "schema_version": "cf_x_scheduled_thread_result.v1",
        "queue": str(queue_path.relative_to(ROOT)),
        "scheduled_at": queue["scheduled_at"],
        "started_at": iso_now(),
        "status": "running",
        "estimated_no_url_post_creates_usd": f"{0.015 * len(posts):.3f}",
        "posts": existing.get("posts") if isinstance(existing.get("posts"), dict) else {},
    }
    atomic_write_json(result_path, result)
    platform_ids: dict[str, str] = {}
    for index, post in enumerate(posts):
        local_id = str(post["post_id"])
        prior = result["posts"].get(local_id) or {}
        platform_id = str(prior.get("platform_post_id") or "")
        if platform_id:
            platform_ids[local_id] = platform_id
            continue
        parent_platform_id = "" if index == 0 else platform_ids[str(post["reply_to"])]
        try:
            platform_id = create_post(token, post, parent_platform_id)
        except ScheduledPostError as exc:
            result.update({"status": "failed", "failed_at": iso_now(), "failed_post_id": local_id, "error": str(exc)})
            atomic_write_json(result_path, result)
            raise
        platform_ids[local_id] = platform_id
        result["posts"][local_id] = {
            "platform_post_id": platform_id,
            "published_url": f"https://x.com/{queue['account_handle']}/status/{platform_id}",
            "published_at": iso_now(),
        }
        atomic_write_json(result_path, result)
    result.update({"status": "completed", "completed_at": iso_now()})
    atomic_write_json(result_path, result)
    return result


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--queue", required=True, help="Repository-relative CF scheduled-thread JSON queue.")
    parser.add_argument("--apply", action="store_true", help="Publish only after schedule and approval checks pass.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        queue_path = repo_path(args.queue, kind="scheduled queue file")
        queue, posts, queue_sha256, run_root = validate_queue(queue_path)
        if not args.apply:
            print(json.dumps(dry_run_report(queue_path, queue, posts, queue_sha256, run_root), ensure_ascii=False))
            return 0
        validate_approval(queue_path, queue, posts, queue_sha256, run_root)
        if now_kst() < parse_kst(queue["scheduled_at"], label="scheduled_at"):
            raise ScheduledPostError("scheduled time has not arrived")
        if now_kst() > parse_kst(queue["expires_at"], label="expires_at"):
            raise ScheduledPostError("scheduled queue expired without publishing")
        token = load_runtime_x_token()
        try:
            result = execute(queue_path, queue, posts, token)
        except ScheduledPostError as exc:
            # One automatic recovery path: expired access token mid-apply.
            if "HTTP 401" not in str(exc):
                raise
            token = load_runtime_x_token(force_refresh=True)
            result = execute(queue_path, queue, posts, token)
        print(json.dumps({"status": result["status"], "queue": result["queue"], "post_count": len(result["posts"])}, ensure_ascii=False))
        return 0
    except ScheduledPostError as exc:
        print(json.dumps({"status": "blocked_or_failed", "error": str(exc)}, ensure_ascii=False), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
