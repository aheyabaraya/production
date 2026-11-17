#!/usr/bin/env python3
"""Collect approved, read-only Loom platform metrics without exposing secrets.

This runner reads only `published` rows that are due for a fixed post-level
metric checkpoint. It never publishes, uploads, schedules, edits social copy,
or stores API payloads. Only normalized aggregate counters are written after
both local ledgers validate.
"""

from __future__ import annotations

import argparse
import base64
import fcntl
import hashlib
import json
import os
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Iterable
from urllib import error, parse, request
from zoneinfo import ZoneInfo

from lib.idol_platform_credentials import load_env


ROOT = Path(__file__).resolve().parents[1]
KST = ZoneInfo("Asia/Seoul")
COLLECTOR_VERSION = "loom_metric_collector.v1"
METRIC_CHECKPOINTS = (
    ("T+24h", timedelta(hours=24), timedelta(hours=24)),
    ("T+72h", timedelta(hours=72), timedelta(hours=24)),
    ("T+7d", timedelta(days=7), timedelta(hours=24)),
)
SOCIAL_VALIDATOR = "scripts/validate_social_analytics.rb"
TRAFFIC_VALIDATOR = "scripts/validate_signal_deck_traffic.py"
X_METRICS_ENDPOINT = "https://api.x.com/2/tweets/"
X_TOKEN_ENDPOINT = "https://api.x.com/2/oauth2/token"
TIKTOK_TOKEN_ENDPOINT = "https://open.tiktokapis.com/v2/oauth/token/"
TIKTOK_QUERY_ENDPOINT = "https://open.tiktokapis.com/v2/video/query/"
YOUTUBE_TOKEN_ENDPOINT = "https://oauth2.googleapis.com/token"
YOUTUBE_ANALYTICS_ENDPOINT = "https://youtubeanalytics.googleapis.com/v2/reports"
YOUTUBE_DATA_ENDPOINT = "https://www.googleapis.com/youtube/v3/videos"
VERCEL_VISITS_ENDPOINT = "https://api.vercel.com/v1/query/web-analytics/visits/count"
YOUTUBE_FULL_METRICS = (
    "views,likes,comments,shares,estimatedMinutesWatched,averageViewDuration,"
    "averageViewPercentage"
)
YOUTUBE_FALLBACK_METRICS = "views,likes,comments,shares"
YOUTUBE_OPTIONAL_VIDEO_METRICS = "subscribersGained,subscribersLost,engagedViews"
# Keep the breakdown metric set to the combination already proven by the
# portfolio OAuth pull; estimatedMinutesWatched remains available on the base
# video row when the provider supports it.
YOUTUBE_DETAIL_METRICS = "views,averageViewDuration,averageViewPercentage"
YOUTUBE_RETENTION_METRICS = "audienceWatchRatio,relativeRetentionPerformance"
YOUTUBE_REQUIRED_METRIC_SCOPES = {
    "https://www.googleapis.com/auth/youtube.readonly",
    "https://www.googleapis.com/auth/yt-analytics.readonly",
}

# These are best-effort aggregate reports. A dimension can legitimately return
# no rows or HTTP 400/403 for a small video, format, or provider window; that
# must not discard the base video metric row.
YOUTUBE_BREAKDOWN_SPECS = (
    ("country", "country", YOUTUBE_DETAIL_METRICS, 25),
    ("age_group", "ageGroup", YOUTUBE_DETAIL_METRICS, 10),
    ("gender", "gender", YOUTUBE_DETAIL_METRICS, 10),
    ("device_type", "deviceType", YOUTUBE_DETAIL_METRICS, 10),
    ("operating_system", "operatingSystem", YOUTUBE_DETAIL_METRICS, 10),
    ("traffic_source_type", "insightTrafficSourceType", YOUTUBE_DETAIL_METRICS, 25),
    ("playback_location_type", "playbackLocationType", YOUTUBE_DETAIL_METRICS, 10),
    ("subscribed_status", "subscribedStatus", YOUTUBE_DETAIL_METRICS, 10),
    ("youtube_product", "youtubeProduct", YOUTUBE_DETAIL_METRICS, 10),
    ("sharing_service", "sharingService", "views,shares", 25),
)

YOUTUBE_METRIC_FIELD_MAP = {
    "views": "views",
    "averageViewDuration": "average_view_duration_sec",
    "averageViewPercentage": "average_view_percentage",
    "estimatedMinutesWatched": "estimated_minutes_watched",
    "subscribersGained": "subscribers_gained",
    "subscribersLost": "subscribers_lost",
    "engagedViews": "engaged_views",
    "shares": "shares",
}


class CollectorError(RuntimeError):
    """Safe failure whose message is a stable, non-secret code."""


def safe_number(value: Any) -> int | float | None:
    if isinstance(value, bool) or not isinstance(value, (int, float)) or value < 0:
        return None
    return int(value) if isinstance(value, float) and value.is_integer() else value


def api_number(value: Any) -> int | float | None:
    number = safe_number(value)
    if number is not None:
        return number
    if isinstance(value, str):
        try:
            parsed = float(value)
        except ValueError:
            return None
        return safe_number(parsed)
    return None


def number_or_zero(value: Any) -> int | float:
    number = safe_number(value)
    return number if number is not None else 0


def as_iso(dt: datetime) -> str:
    return dt.astimezone(KST).isoformat(timespec="seconds")


def parse_time(value: Any) -> datetime | None:
    if not isinstance(value, str) or not value:
        return None
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    return parsed.replace(tzinfo=KST) if parsed.tzinfo is None else parsed


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def read_jsonl(path: Path) -> tuple[list[dict[str, Any]], bytes]:
    if not path.is_file():
        raise CollectorError("missing_canonical_social_ledger")
    raw = path.read_bytes()
    rows: list[dict[str, Any]] = []
    for line_no, line in enumerate(raw.decode("utf-8").splitlines(), 1):
        text = line.strip()
        if not text:
            continue
        try:
            value = json.loads(text)
        except json.JSONDecodeError as exc:
            raise CollectorError(f"invalid_social_ledger_json_line_{line_no}") from exc
        if not isinstance(value, dict):
            raise CollectorError(f"invalid_social_ledger_row_{line_no}")
        rows.append(value)
    return rows, raw


def secret_json(path: Path) -> dict[str, Any]:
    if not path.is_file():
        raise CollectorError("missing_local_oauth_file")
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise CollectorError("invalid_local_oauth_file") from exc
    if not isinstance(value, dict):
        raise CollectorError("invalid_local_oauth_file")
    return value


def write_secret_json(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.metric-", dir=path.parent)
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            handle.write(json.dumps(value, ensure_ascii=False, indent=2) + "\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temporary, 0o600)
        os.replace(temporary, path)
        os.chmod(path, 0o600)
    finally:
        if temporary.exists():
            temporary.unlink()


def replace_env_values(path: Path, updates: dict[str, str]) -> None:
    original = path.read_text(encoding="utf-8") if path.exists() else ""
    seen: set[str] = set()
    output: list[str] = []
    for line in original.splitlines():
        stripped = line.strip()
        key = stripped.split("=", 1)[0].removeprefix("export ").strip() if "=" in stripped else ""
        if key in updates:
            output.append(f"{key}={updates[key]}")
            seen.add(key)
        else:
            output.append(line)
    for key, value in updates.items():
        if key not in seen:
            output.append(f"{key}={value}")
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.metric-", dir=path.parent)
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            handle.write("\n".join(output).rstrip("\n") + "\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temporary, 0o600)
        os.replace(temporary, path)
        os.chmod(path, 0o600)
    finally:
        if temporary.exists():
            temporary.unlink()


def http_json(
    url: str,
    *,
    headers: dict[str, str],
    method: str = "GET",
    body: dict[str, Any] | None = None,
) -> Any:
    data = None if body is None else json.dumps(body, separators=(",", ":")).encode("utf-8")
    request_headers = dict(headers)
    if body is not None:
        request_headers.setdefault("Content-Type", "application/json")
    req = request.Request(url, data=data, method=method, headers=request_headers)
    try:
        with request.urlopen(req, timeout=45) as response:
            raw = response.read()
    except error.HTTPError as exc:
        raise CollectorError(f"http_{exc.code}") from None
    except (error.URLError, TimeoutError, OSError):
        raise CollectorError("network_error") from None
    try:
        return json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        raise CollectorError("invalid_api_response") from None


def form_json(url: str, form: dict[str, str], *, headers: dict[str, str] | None = None) -> dict[str, Any]:
    request_headers = {"Content-Type": "application/x-www-form-urlencoded"}
    if headers:
        request_headers.update(headers)
    req = request.Request(
        url,
        data=parse.urlencode(form).encode("utf-8"),
        method="POST",
        headers=request_headers,
    )
    try:
        with request.urlopen(req, timeout=45) as response:
            raw = response.read()
    except error.HTTPError as exc:
        raise CollectorError(f"http_{exc.code}") from None
    except (error.URLError, TimeoutError, OSError):
        raise CollectorError("network_error") from None
    try:
        value = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        raise CollectorError("invalid_api_response") from None
    if not isinstance(value, dict):
        raise CollectorError("invalid_api_response")
    return value


def scopes(value: Any) -> set[str]:
    return {item.strip() for item in str(value or "").replace(",", " ").split() if item.strip()}


def published_rows(rows: Iterable[dict[str, Any]], platform: str) -> list[dict[str, Any]]:
    compatible = {"youtube", "youtube_shorts"} if platform == "youtube" else {platform}
    return [
        row
        for row in rows
        if row.get("status") == "published" and row.get("platform") in compatible
    ]


def metric_eligible_rows(
    rows: Iterable[dict[str, Any]],
    platform: str,
    now: datetime,
    metrics: Iterable[dict[str, Any]],
) -> tuple[list[dict[str, Any]], dict[str, int]]:
    eligible: list[dict[str, Any]] = []
    excluded: dict[str, int] = {}
    captured = {
        (str(metric.get("post_id") or ""), str(metric.get("measurement_window") or ""))
        for metric in metrics
    }
    for row in published_rows(rows, platform):
        published = parse_time(row.get("published_at"))
        if published is None:
            excluded["invalid_published_at"] = excluded.get("invalid_published_at", 0) + 1
            continue
        published = published.astimezone(KST)
        due: list[tuple[str, datetime]] = []
        for checkpoint_id, offset, grace in METRIC_CHECKPOINTS:
            target = published + offset
            closes = target + grace
            if (str(row.get("post_id") or ""), checkpoint_id) in captured:
                continue
            if target <= now < closes:
                due.append((checkpoint_id, target))
        if due:
            checkpoint_id, target = due[0]
            selected = dict(row)
            selected["_metric_checkpoint"] = checkpoint_id
            selected["_checkpoint_target_at"] = as_iso(target)
            selected["_checkpoint_lag_seconds"] = max(0, int((now - target).total_seconds()))
            eligible.append(selected)
        elif now >= published + METRIC_CHECKPOINTS[-1][1] + METRIC_CHECKPOINTS[-1][2]:
            excluded["checkpoint_series_closed"] = excluded.get("checkpoint_series_closed", 0) + 1
        else:
            excluded["no_checkpoint_due_now"] = excluded.get("no_checkpoint_due_now", 0) + 1
    return eligible, excluded


def platform_post_id(row: dict[str, Any]) -> str:
    value = row.get("platform_post_id")
    return value.strip() if isinstance(value, str) else ""


def start_date(row: dict[str, Any], now: datetime) -> str:
    published = parse_time(row.get("published_at"))
    return (published or now).astimezone(KST).date().isoformat()


def base_metric_row(
    row: dict[str, Any],
    *,
    now: datetime,
    views: int | float,
    engagement: int | float,
    source: str,
    source_locator: str,
    metric_scope: str,
    known_gaps: list[str],
) -> dict[str, Any]:
    result = {
        "captured_at": as_iso(now),
        "observed_date": now.astimezone(KST).date().isoformat(),
        "post_id": row["post_id"],
        "content_id": row["content_id"],
        "platform": row["platform"],
        "views": views,
        "engagement": engagement,
        "source": source,
        "source_locator": source_locator,
        "metric_scope": metric_scope,
        "known_gaps": known_gaps,
        "collector_version": COLLECTOR_VERSION,
    }
    checkpoint = row.get("_metric_checkpoint")
    if isinstance(checkpoint, str) and checkpoint:
        result["measurement_window"] = checkpoint
        result["checkpoint_target_at"] = row["_checkpoint_target_at"]
        result["checkpoint_lag_seconds"] = row["_checkpoint_lag_seconds"]
    return result


def add_if_number(target: dict[str, Any], key: str, value: Any) -> None:
    number = safe_number(value)
    if number is not None:
        target[key] = number


def skip(summary: dict[str, Any], code: str, count: int = 1) -> None:
    summary.setdefault("skipped", {})[code] = summary.setdefault("skipped", {}).get(code, 0) + count


def issue(summary: dict[str, Any], code: str, count: int = 1) -> None:
    summary.setdefault("errors", {})[code] = summary.setdefault("errors", {}).get(code, 0) + count


def detail_issue(summary: dict[str, Any], code: str, count: int = 1) -> None:
    summary.setdefault("detail_errors", {})[code] = summary.setdefault("detail_errors", {}).get(code, 0) + count


def refresh_x(env_path: Path, values: dict[str, str]) -> str:
    client_id = values.get("X_OAUTH2_CLIENT_ID", "").strip()
    refresh_token = values.get("X_OAUTH2_REFRESH_TOKEN", "").strip()
    if not client_id or not refresh_token:
        raise CollectorError("missing_x_refresh_configuration")
    client_secret = values.get("X_OAUTH2_CLIENT_SECRET", "").strip()
    headers: dict[str, str] = {}
    if client_secret:
        basic = base64.b64encode(f"{client_id}:{client_secret}".encode("utf-8")).decode("ascii")
        headers["Authorization"] = f"Basic {basic}"
    response = form_json(
        X_TOKEN_ENDPOINT,
        {"grant_type": "refresh_token", "refresh_token": refresh_token, "client_id": client_id},
        headers=headers,
    )
    access = response.get("access_token")
    if not isinstance(access, str) or not access:
        raise CollectorError("x_refresh_returned_no_access_token")
    updates = {"X_OAUTH2_ACCESS_TOKEN": access}
    refreshed = response.get("refresh_token")
    if isinstance(refreshed, str) and refreshed:
        updates["X_OAUTH2_REFRESH_TOKEN"] = refreshed
    replace_env_values(env_path, updates)
    return access


def x_metric(row: dict[str, Any], token: str, now: datetime) -> dict[str, Any] | None:
    identifier = parse.quote(platform_post_id(row), safe="")
    params = {
        "tweet.fields": "public_metrics,non_public_metrics,organic_metrics,attachments",
        "expansions": "attachments.media_keys",
        "media.fields": "public_metrics,non_public_metrics",
    }
    document = http_json(
        f"{X_METRICS_ENDPOINT}{identifier}?{parse.urlencode(params)}",
        headers={"Authorization": f"Bearer {token}"},
    )
    if not isinstance(document, dict) or not isinstance(document.get("data"), dict):
        raise CollectorError("invalid_api_response")
    data = document["data"]
    public = data.get("public_metrics") if isinstance(data.get("public_metrics"), dict) else {}
    non_public = data.get("non_public_metrics") if isinstance(data.get("non_public_metrics"), dict) else {}
    media_items = document.get("includes", {}).get("media", []) if isinstance(document.get("includes"), dict) else []
    media_metrics = [
        item.get("public_metrics")
        for item in media_items
        if isinstance(item, dict) and isinstance(item.get("public_metrics"), dict)
    ]
    video_views = [safe_number(metric.get("view_count")) for metric in media_metrics]
    video_views = [value for value in video_views if value is not None]
    impression_count = safe_number(non_public.get("impression_count"))
    if impression_count is None:
        impression_count = safe_number(public.get("impression_count"))
    if video_views:
        views = sum(video_views)
        view_semantics = "attached_video_view_count"
    elif impression_count is not None:
        views = impression_count
        view_semantics = "post_impression_count"
    else:
        return None
    likes = safe_number(public.get("like_count"))
    comments = safe_number(public.get("reply_count"))
    shares = safe_number(public.get("retweet_count"))
    quotes = safe_number(public.get("quote_count"))
    saves = safe_number(public.get("bookmark_count"))
    engagement = safe_number(non_public.get("engagements"))
    if engagement is None:
        engagement = sum(number_or_zero(value) for value in (likes, comments, shares, quotes, saves))
    result = base_metric_row(
        row,
        now=now,
        views=views,
        engagement=engagement,
        source="official_x_api_v2",
        source_locator="/2/tweets/:id",
        metric_scope="post_and_attached_media" if media_metrics else "post",
        known_gaps=[
            "Attached-video views may aggregate shared-media playback under X provider rules.",
            "Owned non-public metrics can be unavailable after the provider retention window.",
        ],
    )
    result["views_semantics"] = view_semantics
    add_if_number(result, "likes", likes)
    add_if_number(result, "comments", comments)
    add_if_number(result, "shares", shares)
    add_if_number(result, "quotes", quotes)
    add_if_number(result, "saves", saves)
    playback_zero = sum(
        number_or_zero((item.get("non_public_metrics") or {}).get("playback_0_count"))
        for item in media_items
        if isinstance(item, dict)
    )
    playback_fifty = sum(
        number_or_zero((item.get("non_public_metrics") or {}).get("playback_50_count"))
        for item in media_items
        if isinstance(item, dict)
    )
    playback_hundred = sum(
        number_or_zero((item.get("non_public_metrics") or {}).get("playback_100_count"))
        for item in media_items
        if isinstance(item, dict)
    )
    result["watch_retention"] = playback_fifty / playback_zero if playback_zero else None
    result["completion_rate"] = playback_hundred / playback_zero if playback_zero else None
    return result


def collect_x(root: Path, rows: list[dict[str, Any]], now: datetime, summary: dict[str, Any]) -> list[dict[str, Any]]:
    if not rows:
        summary["state"] = "no_posts_in_collection_window" if summary.get("published_found") else "no_published_posts"
        return []
    env_path = root / ".runtime" / "secrets" / "x.env"
    values = load_env(env_path)
    if "tweet.read" not in scopes(values.get("X_OAUTH2_SCOPES") or values.get("X_OAUTH2_SCOPE")):
        summary["state"] = "blocked"
        skip(summary, "missing_tweet_read_scope", len(rows))
        return []
    token = values.get("X_OAUTH2_ACCESS_TOKEN", "").strip()
    if not token:
        summary["state"] = "blocked"
        skip(summary, "missing_access_token", len(rows))
        return []
    result: list[dict[str, Any]] = []
    for row in rows:
        if not platform_post_id(row):
            skip(summary, "missing_platform_post_id")
            continue
        try:
            metric = x_metric(row, token, now)
        except CollectorError as exc:
            if str(exc) == "http_401":
                try:
                    token = refresh_x(env_path, values)
                    metric = x_metric(row, token, now)
                except CollectorError as refresh_error:
                    skip(summary, f"x_auth_{refresh_error}")
                    continue
            else:
                issue(summary, str(exc))
                continue
        if metric is None:
            skip(summary, "unavailable_metric_fields")
            continue
        result.append(metric)
    summary["collected"] = len(result)
    summary["state"] = "collected" if result else "partial"
    return result


def expired(token: dict[str, Any]) -> bool:
    value = token.get("expires_at")
    try:
        return float(value) <= time.time() + 90
    except (TypeError, ValueError):
        return False


def refresh_tiktok(root: Path, token_path: Path, token: dict[str, Any]) -> str:
    values = load_env(root / ".runtime" / "secrets" / "tiktok.env")
    client_key = values.get("TIKTOK_CLIENT_KEY", "").strip()
    client_secret = values.get("TIKTOK_CLIENT_SECRET", "").strip()
    refresh_token = str(token.get("refresh_token") or "").strip()
    if not client_key or not client_secret or not refresh_token:
        raise CollectorError("missing_tiktok_refresh_configuration")
    response = form_json(
        TIKTOK_TOKEN_ENDPOINT,
        {
            "client_key": client_key,
            "client_secret": client_secret,
            "grant_type": "refresh_token",
            "refresh_token": refresh_token,
        },
    )
    access = response.get("access_token")
    if not isinstance(access, str) or not access:
        raise CollectorError("tiktok_refresh_returned_no_access_token")
    merged = dict(token)
    merged.update(response)
    if not response.get("refresh_token"):
        merged["refresh_token"] = refresh_token
    if response.get("expires_in"):
        merged["expires_at"] = time.time() + int(response["expires_in"])
    if response.get("refresh_expires_in"):
        merged["refresh_expires_at"] = time.time() + int(response["refresh_expires_in"])
    write_secret_json(token_path, merged)
    return access


def tiktok_response(token: str, identifiers: list[str]) -> dict[str, Any]:
    query = parse.urlencode({"fields": "id,view_count,like_count,comment_count,share_count"})
    document = http_json(
        f"{TIKTOK_QUERY_ENDPOINT}?{query}",
        headers={"Authorization": f"Bearer {token}"},
        method="POST",
        body={"filters": {"video_ids": identifiers}, "max_count": len(identifiers)},
    )
    if not isinstance(document, dict):
        raise CollectorError("invalid_api_response")
    return document


def collect_tiktok(root: Path, rows: list[dict[str, Any]], now: datetime, summary: dict[str, Any]) -> list[dict[str, Any]]:
    if not rows:
        summary["state"] = "no_posts_in_collection_window" if summary.get("published_found") else "no_published_posts"
        return []
    env = load_env(root / ".runtime" / "secrets" / "tiktok.env")
    token_path = root / ".runtime" / "secrets" / "tiktok-token.json"
    try:
        token_document = secret_json(token_path)
    except CollectorError as exc:
        summary["state"] = "blocked"
        skip(summary, str(exc), len(rows))
        return []
    if "video.list" not in scopes(env.get("TIKTOK_SCOPES")) or "video.list" not in scopes(token_document.get("scope")):
        summary["state"] = "blocked"
        skip(summary, "missing_video_list_scope", len(rows))
        return []
    token = str(token_document.get("access_token") or "").strip()
    if not token:
        summary["state"] = "blocked"
        skip(summary, "missing_access_token", len(rows))
        return []
    try:
        if expired(token_document):
            token = refresh_tiktok(root, token_path, token_document)
    except CollectorError as exc:
        summary["state"] = "blocked"
        skip(summary, f"tiktok_auth_{exc}", len(rows))
        return []
    selected = [(platform_post_id(row), row) for row in rows if platform_post_id(row)]
    skip(summary, "missing_platform_post_id", len(rows) - len(selected))
    result: list[dict[str, Any]] = []
    for offset in range(0, len(selected), 20):
        batch = selected[offset : offset + 20]
        try:
            document = tiktok_response(token, [identifier for identifier, _ in batch])
        except CollectorError as exc:
            if str(exc) == "http_401":
                try:
                    token = refresh_tiktok(root, token_path, token_document)
                    document = tiktok_response(token, [identifier for identifier, _ in batch])
                except CollectorError as refresh_error:
                    skip(summary, f"tiktok_auth_{refresh_error}", len(batch))
                    continue
            else:
                issue(summary, str(exc), len(batch))
                continue
        videos = document.get("data", {}).get("videos", []) if isinstance(document.get("data"), dict) else []
        by_id = {str(video.get("id")): video for video in videos if isinstance(video, dict)}
        for identifier, row in batch:
            video = by_id.get(identifier)
            if not video:
                skip(summary, "video_not_returned")
                continue
            views = safe_number(video.get("view_count"))
            if views is None:
                skip(summary, "unavailable_metric_fields")
                continue
            likes = safe_number(video.get("like_count"))
            comments = safe_number(video.get("comment_count"))
            shares = safe_number(video.get("share_count"))
            metric = base_metric_row(
                row,
                now=now,
                views=views,
                engagement=sum(number_or_zero(value) for value in (likes, comments, shares)),
                source="official_tiktok_api_v2_video_query",
                source_locator="/v2/video/query/",
                metric_scope="owned_video",
                known_gaps=["TikTok video query does not expose retention or completion in this collector."],
            )
            add_if_number(metric, "likes", likes)
            add_if_number(metric, "comments", comments)
            add_if_number(metric, "shares", shares)
            metric["watch_retention"] = None
            metric["completion_rate"] = None
            result.append(metric)
    summary["collected"] = len(result)
    summary["state"] = "collected" if result else "partial"
    return result


def youtube_client(root: Path) -> dict[str, str]:
    document = secret_json(root / ".runtime" / "secrets" / "youtube-client-secret.json")
    client = document.get("installed") or document.get("web")
    if not isinstance(client, dict):
        raise CollectorError("invalid_youtube_client_file")
    client_id = str(client.get("client_id") or "").strip()
    client_secret = str(client.get("client_secret") or "").strip()
    if not client_id or not client_secret:
        raise CollectorError("invalid_youtube_client_file")
    return {"client_id": client_id, "client_secret": client_secret}


def refresh_youtube(root: Path, token_path: Path, token: dict[str, Any]) -> str:
    client = youtube_client(root)
    refresh_token = str(token.get("refresh_token") or "").strip()
    if not refresh_token:
        raise CollectorError("missing_youtube_refresh_token")
    response = form_json(
        YOUTUBE_TOKEN_ENDPOINT,
        {
            "client_id": client["client_id"],
            "client_secret": client["client_secret"],
            "refresh_token": refresh_token,
            "grant_type": "refresh_token",
        },
    )
    access = response.get("access_token")
    if not isinstance(access, str) or not access:
        raise CollectorError("youtube_refresh_returned_no_access_token")
    merged = dict(token)
    merged.update(response)
    merged["refresh_token"] = str(response.get("refresh_token") or refresh_token)
    if response.get("expires_in"):
        merged["expires_at"] = time.time() + int(response["expires_in"])
    write_secret_json(token_path, merged)
    return access


def youtube_report(
    token: str,
    identifier: str,
    start: str,
    end: str,
    metrics: str,
    *,
    dimensions: str = "video",
    filters: str | None = None,
    sort: str | None = None,
    max_results: int | None = None,
) -> dict[str, Any]:
    query_values: dict[str, str | int] = {
        "ids": "channel==MINE",
        "startDate": start,
        "endDate": end,
        "metrics": metrics,
    }
    if dimensions:
        query_values["dimensions"] = dimensions
    if filters is None:
        filters = f"video=={identifier}"
    if filters:
        query_values["filters"] = filters
    if sort:
        query_values["sort"] = sort
    if max_results is not None:
        query_values["maxResults"] = max_results
    query = parse.urlencode(query_values)
    document = http_json(
        f"{YOUTUBE_ANALYTICS_ENDPOINT}?{query}",
        headers={"Authorization": f"Bearer {token}"},
    )
    if not isinstance(document, dict):
        raise CollectorError("invalid_api_response")
    return document


def youtube_report_with_refresh(
    root: Path,
    token_path: Path,
    token_document: dict[str, Any],
    token: str,
    identifier: str,
    start: str,
    end: str,
    metrics: str,
    *,
    dimensions: str = "video",
    filters: str | None = None,
    sort: str | None = None,
    max_results: int | None = None,
) -> tuple[dict[str, Any], str]:
    try:
        return (
            youtube_report(
                token,
                identifier,
                start,
                end,
                metrics,
                dimensions=dimensions,
                filters=filters,
                sort=sort,
                max_results=max_results,
            ),
            token,
        )
    except CollectorError as exc:
        if str(exc) != "http_401":
            raise
        token = refresh_youtube(root, token_path, token_document)
        token_document["access_token"] = token
        return (
            youtube_report(
                token,
                identifier,
                start,
                end,
                metrics,
                dimensions=dimensions,
                filters=filters,
                sort=sort,
                max_results=max_results,
            ),
            token,
        )


def report_rows(document: dict[str, Any]) -> list[dict[str, Any]]:
    headers = document.get("columnHeaders")
    rows = document.get("rows")
    if not isinstance(headers, list) or not isinstance(rows, list):
        return []
    names = [item.get("name") for item in headers if isinstance(item, dict)]
    if not names or any(not isinstance(name, str) for name in names):
        return []
    result: list[dict[str, Any]] = []
    for row in rows:
        if not isinstance(row, list) or len(row) != len(names):
            continue
        result.append({name: value for name, value in zip(names, row)})
    return result


def report_values(document: dict[str, Any]) -> dict[str, Any] | None:
    rows = report_rows(document)
    return rows[0] if rows else None


def add_youtube_metric_fields(target: dict[str, Any], values: dict[str, Any] | None) -> None:
    if not values:
        return
    for source_key, target_key in YOUTUBE_METRIC_FIELD_MAP.items():
        add_if_number(target, target_key, api_number(values.get(source_key)))


def normalize_youtube_breakdown_rows(
    document: dict[str, Any],
    *,
    dimension: str,
    output_key: str,
) -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    for values in report_rows(document):
        dimension_value = values.get(dimension)
        if dimension_value is None or (isinstance(dimension_value, str) and not dimension_value.strip()):
            continue
        row: dict[str, Any] = {output_key: dimension_value}
        for source_key, target_key in YOUTUBE_METRIC_FIELD_MAP.items():
            add_if_number(row, target_key, api_number(values.get(source_key)))
        result.append(row)
    return result


def normalize_youtube_retention_rows(document: dict[str, Any]) -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    for values in report_rows(document):
        elapsed_ratio = api_number(values.get("elapsedVideoTimeRatio"))
        audience_ratio = api_number(values.get("audienceWatchRatio"))
        relative_performance = api_number(values.get("relativeRetentionPerformance"))
        if elapsed_ratio is None:
            continue
        row: dict[str, Any] = {"elapsed_video_time_ratio": elapsed_ratio}
        if audience_ratio is not None:
            row["audience_watch_ratio"] = audience_ratio
        if relative_performance is not None:
            row["relative_retention_performance"] = relative_performance
        result.append(row)
    return result


def detail_status(
    *,
    source_dimension: str,
    status: str,
    row_count: int = 0,
    reason_code: str | None = None,
) -> dict[str, Any]:
    result: dict[str, Any] = {
        "source_dimension": source_dimension,
        "status": status,
        "row_count": row_count,
    }
    if reason_code:
        result["reason_code"] = reason_code
    return result


def is_optional_detail_unavailable(error_code: str) -> bool:
    return error_code in {"http_400", "http_403", "http_404"}


def enrich_youtube_metric(
    root: Path,
    token_path: Path,
    token_document: dict[str, Any],
    token: str,
    identifier: str,
    start: str,
    end: str,
    metric: dict[str, Any],
    summary: dict[str, Any],
) -> str:
    breakdowns: dict[str, list[dict[str, Any]]] = {}
    breakdown_status: dict[str, dict[str, Any]] = {}

    try:
        optional_document, token = youtube_report_with_refresh(
            root,
            token_path,
            token_document,
            token,
            identifier,
            start,
            end,
            YOUTUBE_OPTIONAL_VIDEO_METRICS,
        )
        optional_values = report_values(optional_document)
        add_youtube_metric_fields(metric, optional_values)
        breakdown_status["optional_video_metrics"] = detail_status(
            source_dimension="video",
            status="populated" if optional_values else "no_rows",
            row_count=1 if optional_values else 0,
        )
    except CollectorError as exc:
        code = str(exc)
        breakdown_status["optional_video_metrics"] = detail_status(
            source_dimension="video",
            status="unsupported_or_unavailable" if is_optional_detail_unavailable(code) else "request_failed",
            reason_code=code,
        )
        if not is_optional_detail_unavailable(code):
            detail_issue(summary, f"youtube_optional_video_metrics_{code}")

    for output_key, source_dimension, metrics, max_results in YOUTUBE_BREAKDOWN_SPECS:
        try:
            document, token = youtube_report_with_refresh(
                root,
                token_path,
                token_document,
                token,
                identifier,
                start,
                end,
                metrics,
                dimensions=source_dimension,
                sort="-views",
                max_results=max_results,
            )
            rows = normalize_youtube_breakdown_rows(
                document,
                dimension=source_dimension,
                output_key=output_key,
            )
            breakdowns[output_key] = rows
            breakdown_status[output_key] = detail_status(
                source_dimension=source_dimension,
                status="populated" if rows else "no_rows",
                row_count=len(rows),
            )
        except CollectorError as exc:
            code = str(exc)
            breakdown_status[output_key] = detail_status(
                source_dimension=source_dimension,
                status="unsupported_or_unavailable" if is_optional_detail_unavailable(code) else "request_failed",
                reason_code=code,
            )
            if not is_optional_detail_unavailable(code):
                detail_issue(summary, f"youtube_{output_key}_{code}")

    retention_status: dict[str, Any]
    try:
        retention_document, token = youtube_report_with_refresh(
            root,
            token_path,
            token_document,
            token,
            identifier,
            start,
            end,
            YOUTUBE_RETENTION_METRICS,
            dimensions="elapsedVideoTimeRatio",
            sort="elapsedVideoTimeRatio",
            max_results=100,
        )
        retention_rows = normalize_youtube_retention_rows(retention_document)
        if retention_rows:
            metric["youtube_analytics_retention_curve"] = retention_rows
        retention_status = detail_status(
            source_dimension="elapsedVideoTimeRatio",
            status="populated" if retention_rows else "no_rows",
            row_count=len(retention_rows),
        )
    except CollectorError as exc:
        code = str(exc)
        retention_status = detail_status(
            source_dimension="elapsedVideoTimeRatio",
            status="unsupported_or_unavailable" if is_optional_detail_unavailable(code) else "request_failed",
            reason_code=code,
        )
        if not is_optional_detail_unavailable(code):
            detail_issue(summary, f"youtube_retention_curve_{code}")

    metric["youtube_analytics_breakdowns"] = breakdowns
    metric["youtube_analytics_breakdown_status"] = breakdown_status
    metric["youtube_analytics_retention_status"] = retention_status
    metric["top_countries"] = breakdowns.get("country", [])
    return token


def youtube_public_statistics(token: str, identifier: str) -> dict[str, Any] | None:
    query = parse.urlencode({"part": "statistics", "id": identifier})
    document = http_json(
        f"{YOUTUBE_DATA_ENDPOINT}?{query}",
        headers={"Authorization": f"Bearer {token}"},
    )
    if not isinstance(document, dict) or not isinstance(document.get("items"), list):
        raise CollectorError("invalid_api_response")
    for item in document["items"]:
        if (
            isinstance(item, dict)
            and str(item.get("id") or "") == identifier
            and isinstance(item.get("statistics"), dict)
        ):
            return item["statistics"]
    return None


def collect_youtube(root: Path, rows: list[dict[str, Any]], now: datetime, summary: dict[str, Any]) -> list[dict[str, Any]]:
    if not rows:
        summary["state"] = "no_posts_in_collection_window" if summary.get("published_found") else "no_published_posts"
        return []
    token_path = root / ".runtime" / "secrets" / "youtube-token.json"
    try:
        token_document = secret_json(token_path)
    except CollectorError as exc:
        summary["state"] = "blocked"
        skip(summary, str(exc), len(rows))
        return []
    if not YOUTUBE_REQUIRED_METRIC_SCOPES.issubset(scopes(token_document.get("scope"))):
        summary["state"] = "blocked"
        skip(summary, "missing_youtube_metric_scope", len(rows))
        return []
    token = str(token_document.get("access_token") or "").strip()
    if not token:
        summary["state"] = "blocked"
        skip(summary, "missing_access_token", len(rows))
        return []
    try:
        if expired(token_document):
            token = refresh_youtube(root, token_path, token_document)
    except CollectorError as exc:
        summary["state"] = "blocked"
        skip(summary, f"youtube_auth_{exc}", len(rows))
        return []
    result: list[dict[str, Any]] = []
    end = now.astimezone(KST).date().isoformat()
    for row in rows:
        identifier = platform_post_id(row)
        if not identifier:
            skip(summary, "missing_platform_post_id")
            continue
        used_fallback = False
        start = start_date(row, now)
        try:
            document, token = youtube_report_with_refresh(
                root,
                token_path,
                token_document,
                token,
                identifier,
                start,
                end,
                YOUTUBE_FULL_METRICS,
            )
        except CollectorError as exc:
            if str(exc) == "http_400":
                try:
                    document, token = youtube_report_with_refresh(
                        root,
                        token_path,
                        token_document,
                        token,
                        identifier,
                        start,
                        end,
                        YOUTUBE_FALLBACK_METRICS,
                    )
                    used_fallback = True
                except CollectorError as fallback_error:
                    if str(fallback_error) == "http_401":
                        skip(summary, f"youtube_auth_{fallback_error}")
                    else:
                        issue(summary, str(fallback_error))
                    continue
            else:
                if str(exc) == "http_401":
                    skip(summary, f"youtube_auth_{exc}")
                else:
                    issue(summary, str(exc))
                continue
        values = report_values(document)
        views = api_number(values.get("views")) if values else None
        public_statistics: dict[str, Any] | None = None
        used_public_statistics = False
        if views is None:
            try:
                public_statistics = youtube_public_statistics(token, identifier)
            except CollectorError as exc:
                if str(exc) == "http_401":
                    try:
                        token = refresh_youtube(root, token_path, token_document)
                        public_statistics = youtube_public_statistics(token, identifier)
                    except CollectorError as refresh_error:
                        skip(summary, f"youtube_auth_{refresh_error}")
                        continue
                else:
                    issue(summary, str(exc))
                    continue
            views = (
                safe_number(int(public_statistics["viewCount"]))
                if public_statistics and "viewCount" in public_statistics
                else None
            )
            if views is None:
                skip(summary, "report_and_public_statistics_have_no_views")
                continue
            used_public_statistics = True
        likes = (
            safe_number(int(public_statistics["likeCount"]))
            if used_public_statistics and public_statistics and "likeCount" in public_statistics
            else safe_number(values.get("likes"))
        )
        comments = (
            safe_number(int(public_statistics["commentCount"]))
            if used_public_statistics and public_statistics and "commentCount" in public_statistics
            else safe_number(values.get("comments"))
        )
        shares = None if used_public_statistics else api_number(values.get("shares"))
        average_percentage = None if used_public_statistics else api_number(values.get("averageViewPercentage"))
        gaps = ["YouTube Analytics availability can lag the provider reporting window."]
        if used_public_statistics:
            gaps.extend(
                [
                    "The YouTube Analytics report had no current row, so public video statistics were used.",
                    "YouTube Data API public statistics do not expose shares, retention, or completion.",
                ]
            )
        elif used_fallback:
            gaps.append("Retention fields were unavailable from the provider report, so the fallback metric set was stored.")
        metric = base_metric_row(
            row,
            now=now,
            views=views,
            engagement=sum(number_or_zero(value) for value in (likes, comments, shares)),
            source=(
                "official_youtube_data_api_v3"
                if used_public_statistics
                else "official_youtube_analytics_api_v2"
            ),
            source_locator="/youtube/v3/videos" if used_public_statistics else "/v2/reports",
            metric_scope="public_video_statistics" if used_public_statistics else "owned_channel_video",
            known_gaps=gaps,
        )
        metric["report_start_date"] = start
        metric["report_end_date_requested"] = end
        add_if_number(metric, "likes", likes)
        add_if_number(metric, "comments", comments)
        add_if_number(metric, "shares", shares)
        if not used_public_statistics:
            add_youtube_metric_fields(metric, values)
        metric["watch_retention"] = average_percentage / 100 if average_percentage is not None else None
        direct_completion_rate = api_number(values.get("completionRate")) if values else None
        if direct_completion_rate is None and not used_public_statistics:
            gaps.append(
                "YouTube Analytics does not expose a single-pass completion rate in this collector; "
                "average_view_percentage is stored separately."
            )
        metric["completion_rate"] = direct_completion_rate
        metric["completion_rate_status"] = (
            "reported_by_provider"
            if direct_completion_rate is not None
            else "not_exposed_by_youtube_analytics_api_v2"
        )
        if used_public_statistics:
            metric["completion_rate_status"] = "unavailable_data_api_fallback"
            metric["youtube_analytics_breakdowns"] = {}
            metric["youtube_analytics_breakdown_status"] = {
                "overall": detail_status(
                    source_dimension="video",
                    status="not_requested_public_statistics_fallback",
                )
            }
            metric["youtube_analytics_retention_status"] = detail_status(
                source_dimension="elapsedVideoTimeRatio",
                status="not_requested_public_statistics_fallback",
            )
            metric["top_countries"] = None
        else:
            token = enrich_youtube_metric(
                root,
                token_path,
                token_document,
                token,
                identifier,
                start,
                end,
                metric,
                summary,
            )
        result.append(metric)
    summary["collected"] = len(result)
    summary["state"] = "collected" if result else "partial"
    return result


def vercel_count(document: Any) -> int | None:
    candidates: list[Any] = []
    if isinstance(document, (int, float)) and not isinstance(document, bool):
        candidates.append(document)
    if isinstance(document, dict):
        for key in ("count", "value"):
            candidates.append(document.get(key))
        data = document.get("data")
        if isinstance(data, dict):
            candidates.extend(data.get(key) for key in ("count", "value"))
        else:
            candidates.append(data)
    for value in candidates:
        number = safe_number(value)
        if number is not None and float(number).is_integer():
            return int(number)
    return None


def collect_vercel(root: Path, now: datetime, summary: dict[str, Any]) -> list[dict[str, Any]]:
    env = load_env(root / ".runtime" / "secrets" / "vercel.env")
    token = env.get("VERCEL_TOKEN", "").strip()
    project_id = env.get("VERCEL_PROJECT_ID", "").strip()
    if not token or not project_id:
        summary["state"] = "blocked"
        skip(summary, "missing_vercel_configuration")
        return []
    query: dict[str, str] = {
        "projectId": project_id,
        "filter": env.get("VERCEL_ANALYTICS_FILTER", "").strip() or "environment eq 'production'",
    }
    team_id = env.get("VERCEL_TEAM_ID", "").strip()
    if team_id:
        query["teamId"] = team_id
    try:
        document = http_json(
            f"{VERCEL_VISITS_ENDPOINT}?{parse.urlencode(query)}",
            headers={"Authorization": f"Bearer {token}"},
        )
    except CollectorError as exc:
        summary["state"] = "blocked" if str(exc) in {"http_401", "http_403"} else "partial"
        skip(summary, f"vercel_{exc}")
        return []
    count = vercel_count(document)
    if count is None:
        summary["state"] = "partial"
        skip(summary, "vercel_response_shape_unrecognized")
        return []
    summary["collected"] = 1
    summary["state"] = "collected"
    return [
        {
            "captured_at": as_iso(now),
            "metric_name": "visits_count",
            "count": count,
            "provider": "vercel_web_analytics_api",
            "environment": "production",
            "measurement_window": "provider_default_window",
            "source": "official_vercel_web_analytics_api",
            "source_locator": "/v1/query/web-analytics/visits/count",
            "data_completeness": "partial",
            "known_gaps": [
                "The provider API query does not declare a fixed reporting range in this collector.",
                "No raw event, visitor, session, or clickstream data is retained.",
            ],
            "collector_version": COLLECTOR_VERSION,
        }
    ]


def stage_file(path: Path, content: bytes, *, same_directory: bool = False) -> Path:
    directory = path.parent if same_directory else Path(tempfile.gettempdir())
    if same_directory:
        path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, name = tempfile.mkstemp(prefix=f".{path.name}.metric-stage-", dir=directory)
    temporary = Path(name)
    try:
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temporary, 0o600)
        return temporary
    except OSError as exc:
        if temporary.exists():
            temporary.unlink()
        raise CollectorError("local_ledger_write_failed") from exc
    except BaseException:
        if temporary.exists():
            temporary.unlink()
        raise


def validate_staged(root: Path, posts: Path, metrics_content: bytes, traffic_content: bytes | None, metrics_path: Path, traffic_path: Path) -> None:
    staged_metrics = stage_file(metrics_path, metrics_content)
    staged_traffic = stage_file(traffic_path, traffic_content) if traffic_content is not None else None
    try:
        social = subprocess.run(
            ["ruby", SOCIAL_VALIDATOR, str(posts), str(staged_metrics)],
            cwd=root,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
        if social.returncode != 0:
            raise CollectorError("social_ledger_validation_failed")
        if staged_traffic is not None:
            traffic = subprocess.run(
                [sys.executable, TRAFFIC_VALIDATOR, str(staged_traffic)],
                cwd=root,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
            )
            if traffic.returncode != 0:
                raise CollectorError("signal_deck_traffic_validation_failed")
    finally:
        if staged_metrics.exists():
            staged_metrics.unlink()
        if staged_traffic is not None and staged_traffic.exists():
            staged_traffic.unlink()


def atomic_replace(path: Path, content: bytes) -> None:
    temporary = stage_file(path, content, same_directory=True)
    try:
        os.replace(temporary, path)
    finally:
        if temporary.exists():
            temporary.unlink()


def lock_path(root: Path) -> Path:
    identifier = hashlib.sha256(str(root.resolve()).encode("utf-8")).hexdigest()[:20]
    return Path(tempfile.gettempdir()) / f"idol-metric-collector-{identifier}.lock"


def write_ledgers_if_unchanged(
    root: Path,
    *,
    posts_path: Path,
    metrics_path: Path,
    traffic_path: Path,
    posts_digest: str,
    metrics_digest: str,
    traffic_digest: str,
    metrics_content: bytes,
    traffic_content: bytes | None,
) -> None:
    lock = lock_path(root)
    with lock.open("a+") as handle:
        fcntl.flock(handle.fileno(), fcntl.LOCK_EX)
        try:
            current_posts = posts_path.read_bytes()
            current_metrics = metrics_path.read_bytes() if metrics_path.exists() else b""
            current_traffic = traffic_path.read_bytes() if traffic_path.exists() else b""
            if (
                sha256_bytes(current_posts) != posts_digest
                or sha256_bytes(current_metrics) != metrics_digest
                or sha256_bytes(current_traffic) != traffic_digest
            ):
                raise CollectorError("source_ledger_changed_during_collection")
            if current_metrics != metrics_content:
                atomic_replace(metrics_path, metrics_content)
            if traffic_content is not None and current_traffic != traffic_content:
                atomic_replace(traffic_path, traffic_content)
        finally:
            fcntl.flock(handle.fileno(), fcntl.LOCK_UN)


def jsonl_append(existing: bytes, rows: list[dict[str, Any]]) -> bytes:
    if not rows:
        return existing
    prefix = existing if not existing or existing.endswith(b"\n") else existing + b"\n"
    payload = b"".join(
        (json.dumps(row, ensure_ascii=False, separators=(",", ":")) + "\n").encode("utf-8") for row in rows
    )
    return prefix + payload


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", default=str(ROOT))
    parser.add_argument("--posts", help="Canonical platform-posts ledger path.")
    parser.add_argument("--metrics", help="Canonical platform-metrics ledger path.")
    parser.add_argument("--signal-deck-traffic", help="Signal Deck aggregate traffic ledger path.")
    parser.add_argument("--platform", action="append", choices=("x", "tiktok", "youtube", "vercel"))
    parser.add_argument("--apply", action="store_true", help="Make approved read-only API calls and write normalized snapshots.")
    parser.add_argument("--dry-run", action="store_true", help="Inspect ledger eligibility only; make no network or file writes.")
    parser.add_argument("--now", help="ISO-8601 test timestamp. Do not use for normal automated runs.")
    parser.add_argument("--json", action="store_true", help="Emit the value-free machine summary (the default output).")
    return parser.parse_args()


def resolve_path(root: Path, value: str | None, default: str) -> Path:
    path = Path(value) if value else root / default
    return path if path.is_absolute() else root / path


def run(args: argparse.Namespace) -> tuple[dict[str, Any], int]:
    if args.apply and args.dry_run:
        raise CollectorError("apply_and_dry_run_are_mutually_exclusive")
    root = Path(args.root).resolve()
    posts_path = resolve_path(root, args.posts, "analytics/records/platform-posts.jsonl")
    metrics_path = resolve_path(root, args.metrics, "analytics/records/platform-metrics.jsonl")
    traffic_path = resolve_path(root, args.signal_deck_traffic, "analytics/records/signal-deck-traffic.jsonl")
    now = parse_time(args.now) if args.now else datetime.now(timezone.utc)
    if now is None:
        raise CollectorError("invalid_now_timestamp")
    now = now.astimezone(KST)
    posts, posts_bytes = read_jsonl(posts_path)
    if metrics_path.exists():
        metrics, metrics_bytes = read_jsonl(metrics_path)
    else:
        metrics, metrics_bytes = [], b""
    traffic_bytes = traffic_path.read_bytes() if traffic_path.exists() else b""
    selected_platforms = tuple(dict.fromkeys(args.platform or ("x", "tiktok", "youtube", "vercel")))
    published_groups = {platform: published_rows(posts, platform) for platform in ("x", "tiktok", "youtube")}
    selections = {
        platform: metric_eligible_rows(posts, platform, now, metrics)
        for platform in ("x", "tiktok", "youtube")
    }
    groups = {platform: selections[platform][0] for platform in selections}
    summary: dict[str, Any] = {
        "schema_version": COLLECTOR_VERSION,
        "mode": "apply" if args.apply else "dry_run",
        "secret_values_printed": False,
        "metric_checkpoints": {
            "basis": "per_post_published_at",
            "performance_windows": [checkpoint_id for checkpoint_id, _offset, _grace in METRIC_CHECKPOINTS],
            "t_plus_1h_role": "local_publication_fact_verification_only",
            "as_of": as_iso(now),
        },
        "published_posts_found": {platform: len(published_groups[platform]) for platform in published_groups},
        "published_posts_selected": {platform: len(groups[platform]) for platform in groups},
        "published_posts_excluded": {platform: selections[platform][1] for platform in selections},
        "platforms": {},
        "metrics_rows_written": 0,
        "signal_deck_rows_written": 0,
    }
    for platform in selected_platforms:
        if platform == "vercel":
            summary["platforms"][platform] = {"selected": 1, "collected": 0, "skipped": {}, "errors": {}}
        else:
            summary["platforms"][platform] = {
                "published_found": len(published_groups[platform]),
                "selected": len(groups[platform]),
                "collected": 0,
                "skipped": {},
                "errors": {},
            }
            for code, count in selections[platform][1].items():
                skip(summary["platforms"][platform], code, count)
    if not args.apply:
        for platform, platform_summary in summary["platforms"].items():
            platform_summary["state"] = "dry_run"
            if platform != "vercel":
                missing_ids = sum(1 for row in groups[platform] if not platform_post_id(row))
                if missing_ids:
                    skip(platform_summary, "missing_platform_post_id", missing_ids)
        summary["status"] = "ready_for_apply"
        return summary, 0

    validate_staged(root, posts_path, metrics_bytes, None, metrics_path, traffic_path)
    collected_metrics: list[dict[str, Any]] = []
    collected_traffic: list[dict[str, Any]] = []
    if "x" in selected_platforms:
        collected_metrics.extend(collect_x(root, groups["x"], now, summary["platforms"]["x"]))
    if "tiktok" in selected_platforms:
        collected_metrics.extend(collect_tiktok(root, groups["tiktok"], now, summary["platforms"]["tiktok"]))
    if "youtube" in selected_platforms:
        collected_metrics.extend(collect_youtube(root, groups["youtube"], now, summary["platforms"]["youtube"]))
    if "vercel" in selected_platforms:
        collected_traffic.extend(collect_vercel(root, now, summary["platforms"]["vercel"]))

    staged_metrics = jsonl_append(metrics_bytes, collected_metrics)
    staged_traffic = jsonl_append(traffic_bytes, collected_traffic) if collected_traffic else None
    validate_staged(root, posts_path, staged_metrics, staged_traffic, metrics_path, traffic_path)
    if collected_metrics or collected_traffic:
        write_ledgers_if_unchanged(
            root,
            posts_path=posts_path,
            metrics_path=metrics_path,
            traffic_path=traffic_path,
            posts_digest=sha256_bytes(posts_bytes),
            metrics_digest=sha256_bytes(metrics_bytes),
            traffic_digest=sha256_bytes(traffic_bytes),
            metrics_content=staged_metrics,
            traffic_content=staged_traffic,
        )
    summary["metrics_rows_written"] = len(collected_metrics)
    summary["signal_deck_rows_written"] = len(collected_traffic)
    states = [item.get("state") for item in summary["platforms"].values()]
    summary["status"] = "collected" if "collected" in states else "blocked_or_no_published_posts"
    non_auth_errors = sum(
        sum(values.values())
        for item in summary["platforms"].values()
        for values in [item.get("errors", {})]
    )
    return summary, 1 if non_auth_errors else 0


def main() -> int:
    try:
        summary, exit_code = run(parse_args())
    except CollectorError as exc:
        summary = {
            "schema_version": COLLECTOR_VERSION,
            "status": "failed_before_collection",
            "reason": str(exc),
            "secret_values_printed": False,
        }
        exit_code = 1
    print(json.dumps(summary, ensure_ascii=False, sort_keys=True), flush=True)
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
