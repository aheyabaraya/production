#!/usr/bin/env python3
"""Import Founder-provided TikTok Studio ZIP exports into local analytics ledgers.

The importer never opens a network connection, reads credentials, publishes,
uploads, schedules, or creates a post record. It accepts the three official
TikTok Studio CSV exports (Overview, Viewers, Content), preserves ZIP/member
hashes, rejects conflicting overlap, and writes a platform-metric snapshot only
when a video ID exactly matches an already-published TikTok post ledger row.
"""

from __future__ import annotations

import argparse
import csv
import fcntl
import hashlib
import io
import json
import os
import subprocess
import sys
import tempfile
import zipfile
from collections import defaultdict
from datetime import date, datetime
from pathlib import Path
from typing import Any
from urllib.parse import urlparse
from zoneinfo import ZoneInfo


ROOT = Path(__file__).resolve().parents[1]
KST = ZoneInfo("Asia/Seoul")
SCHEMA_VERSION = "idol_tiktok_studio_export.v1"
IMPORTER_VERSION = "idol_tiktok_studio_importer.v1"
TIKTOK_SOURCE = "official_tiktok_studio_csv_export"
VALIDATOR = ROOT / "scripts" / "validate_tiktok_studio_exports.py"
MAX_MEMBER_BYTES = 64 * 1024 * 1024

REPORT_FIELDS = {
    "Overview.csv": ("Date", "Video Views", "Profile Views", "Likes", "Comments", "Shares"),
    "Viewers.csv": ("Date", "Total Viewers", "New Viewers", "Returning Viewers"),
    "Content.csv": (
        "Time",
        "Video title",
        "Video link",
        "Post time",
        "Total likes",
        "Total comments",
        "Total shares",
        "Total views",
    ),
}
DETAIL_DIMENSIONS = (
    "country",
    "age_gender",
    "traffic_source",
    "average_watch_time",
    "completion_rate",
    "retention_curve",
)
KNOWN_GAPS = tuple(f"{dimension}_not_in_weekly_tiktok_studio_csv_export" for dimension in DETAIL_DIMENSIONS)
AVAILABLE_METRICS = (
    "daily_video_views",
    "daily_profile_views",
    "daily_likes",
    "daily_comments",
    "daily_shares",
    "daily_total_viewers",
    "daily_new_viewers",
    "daily_returning_viewers",
    "video_total_views",
    "video_total_likes",
    "video_total_comments",
    "video_total_shares",
)


class ImportError(RuntimeError):
    """A stable, value-safe import failure code."""


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while chunk := handle.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def as_iso(value: datetime) -> str:
    return value.astimezone(KST).isoformat(timespec="seconds")


def parse_iso(value: str) -> datetime:
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise ImportError("invalid_captured_at") from exc
    if parsed.tzinfo is None:
        raise ImportError("captured_at_requires_timezone")
    return parsed.astimezone(KST)


def parse_non_negative_int(value: Any, *, field: str, allow_undefined: bool = False) -> int | None:
    text = str(value or "").strip().replace(",", "")
    if allow_undefined and text.lower() == "undefined":
        return None
    if not text.isdigit():
        raise ImportError(f"invalid_non_negative_integer_{field}")
    return int(text)


def parse_month_day(value: Any, captured_at: datetime, *, field: str) -> date:
    text = str(value or "").strip()
    try:
        parsed = datetime.strptime(f"2000 {text}", "%Y %B %d")
    except ValueError as exc:
        raise ImportError(f"invalid_month_day_{field}") from exc
    candidate = date(captured_at.year, parsed.month, parsed.day)
    if candidate > captured_at.date():
        candidate = date(captured_at.year - 1, parsed.month, parsed.day)
    return candidate


def source_ref(archive: dict[str, Any], row_number: int) -> dict[str, Any]:
    return {
        "archive_sha256": archive["archive_sha256"],
        "report_name": archive["report_name"],
        "source_row_number": row_number,
    }


def detail_statuses() -> dict[str, dict[str, Any]]:
    return {
        dimension: {
            "source_dimension": "TikTok Studio weekly CSV ZIP export",
            "status": "not_in_export",
            "row_count": 0,
            "reason_code": "not_exported_in_provided_csv",
        }
        for dimension in DETAIL_DIMENSIONS
    }


def resolve_path(root: Path, supplied: str | None, default: str) -> Path:
    path = Path(supplied) if supplied else root / default
    return path if path.is_absolute() else root / path


def read_jsonl(path: Path, *, missing_is_empty: bool, label: str) -> tuple[list[dict[str, Any]], bytes]:
    if not path.is_file():
        if missing_is_empty:
            return [], b""
        raise ImportError(f"missing_{label}")
    raw = path.read_bytes()
    rows: list[dict[str, Any]] = []
    try:
        lines = raw.decode("utf-8").splitlines()
    except UnicodeDecodeError as exc:
        raise ImportError(f"invalid_{label}_encoding") from exc
    for line_no, line in enumerate(lines, 1):
        if not line.strip():
            continue
        try:
            value = json.loads(line)
        except json.JSONDecodeError as exc:
            raise ImportError(f"invalid_{label}_json_line_{line_no}") from exc
        if not isinstance(value, dict):
            raise ImportError(f"invalid_{label}_row_{line_no}")
        rows.append(value)
    return rows, raw


def read_zip_export(path_text: str) -> dict[str, Any]:
    path = Path(path_text).expanduser().resolve()
    if not path.is_file():
        raise ImportError("missing_tiktok_studio_zip")
    if not zipfile.is_zipfile(path):
        raise ImportError("invalid_tiktok_studio_zip")
    archive_sha = sha256_file(path)
    try:
        with zipfile.ZipFile(path) as archive:
            members = [info for info in archive.infolist() if not info.is_dir()]
            if len(members) != 1:
                raise ImportError("tiktok_studio_zip_must_contain_exactly_one_csv")
            member = members[0]
            report_name = Path(member.filename).name
            if report_name not in REPORT_FIELDS:
                raise ImportError("unsupported_tiktok_studio_csv_report")
            if member.file_size > MAX_MEMBER_BYTES:
                raise ImportError("tiktok_studio_csv_too_large")
            member_bytes = archive.read(member)
    except zipfile.BadZipFile as exc:
        raise ImportError("invalid_tiktok_studio_zip") from exc
    try:
        text = member_bytes.decode("utf-8-sig")
    except UnicodeDecodeError as exc:
        raise ImportError("invalid_tiktok_studio_csv_encoding") from exc
    reader = csv.DictReader(io.StringIO(text, newline=""))
    headers = tuple(reader.fieldnames or ())
    missing = [field for field in REPORT_FIELDS[report_name] if field not in headers]
    if missing:
        raise ImportError(f"tiktok_studio_{report_name.removesuffix('.csv').lower()}_missing_required_columns")
    rows = [row for row in reader if isinstance(row, dict) and any(str(value or "").strip() for value in row.values())]
    modified_at = datetime(*member.date_time, tzinfo=KST)
    return {
        "path": path,
        "file_name": path.name,
        "archive_sha256": archive_sha,
        "report_name": report_name,
        "member_name": member.filename,
        "member_sha256": sha256_bytes(member_bytes),
        "member_modified_at": as_iso(modified_at),
        "member_modified_datetime": modified_at,
        "row_count": len(rows),
        "rows": rows,
    }


def unique_archives(paths: list[str]) -> list[dict[str, Any]]:
    archives: list[dict[str, Any]] = []
    seen: set[str] = set()
    for raw_path in paths:
        archive = read_zip_export(raw_path)
        if archive["archive_sha256"] in seen:
            continue
        seen.add(archive["archive_sha256"])
        archives.append(archive)
    if not archives:
        raise ImportError("no_tiktok_studio_zip_inputs")
    return archives


def add_exact(
    destination: dict[str, dict[str, Any]],
    key: str,
    value: dict[str, Any],
    ref: dict[str, Any],
    *,
    conflict_code: str,
    duplicate_counter: dict[str, int],
    counter_key: str,
) -> None:
    current = destination.get(key)
    if current is None:
        destination[key] = {"value": value, "source_refs": [ref]}
        return
    if current["value"] != value:
        raise ImportError(f"{conflict_code}_{key}")
    if ref not in current["source_refs"]:
        current["source_refs"].append(ref)
        duplicate_counter[counter_key] += 1


def normalize_overview(
    archives: list[dict[str, Any]], captured_at: datetime, counters: dict[str, int]
) -> dict[str, dict[str, Any]]:
    result: dict[str, dict[str, Any]] = {}
    for archive in archives:
        if archive["report_name"] != "Overview.csv":
            continue
        for row_number, row in enumerate(archive["rows"], 2):
            observed_date = parse_month_day(row.get("Date"), captured_at, field="overview_date").isoformat()
            value = {
                "video_views": parse_non_negative_int(row.get("Video Views"), field="overview_video_views"),
                "profile_views": parse_non_negative_int(row.get("Profile Views"), field="overview_profile_views"),
                "likes": parse_non_negative_int(row.get("Likes"), field="overview_likes"),
                "comments": parse_non_negative_int(row.get("Comments"), field="overview_comments"),
                "shares": parse_non_negative_int(row.get("Shares"), field="overview_shares"),
            }
            add_exact(
                result,
                observed_date,
                value,
                source_ref(archive, row_number),
                conflict_code="conflicting_overview_date",
                duplicate_counter=counters,
                counter_key="exact_duplicate_daily_rows_collapsed",
            )
    return result


def normalize_viewers(
    archives: list[dict[str, Any]], captured_at: datetime, counters: dict[str, int]
) -> dict[str, dict[str, Any]]:
    result: dict[str, dict[str, Any]] = {}
    for archive in archives:
        if archive["report_name"] != "Viewers.csv":
            continue
        for row_number, row in enumerate(archive["rows"], 2):
            observed_date = parse_month_day(row.get("Date"), captured_at, field="viewers_date").isoformat()
            value = {
                "total_viewers": parse_non_negative_int(
                    row.get("Total Viewers"), field="total_viewers", allow_undefined=True
                ),
                "new_viewers": parse_non_negative_int(row.get("New Viewers"), field="new_viewers"),
                "returning_viewers": parse_non_negative_int(
                    row.get("Returning Viewers"), field="returning_viewers"),
            }
            add_exact(
                result,
                observed_date,
                value,
                source_ref(archive, row_number),
                conflict_code="conflicting_viewers_date",
                duplicate_counter=counters,
                counter_key="exact_duplicate_daily_rows_collapsed",
            )
    return result


def tiktok_video_id(value: Any) -> str:
    text = str(value or "").strip()
    parsed = urlparse(text)
    candidate = parsed.path.rstrip("/").split("/")[-1]
    if not candidate.isdigit() or len(candidate) < 8:
        raise ImportError("invalid_tiktok_video_link")
    return candidate


def normalize_content(
    archives: list[dict[str, Any]], captured_at: datetime, counters: dict[str, int]
) -> dict[str, dict[str, Any]]:
    result: dict[str, dict[str, Any]] = {}
    for archive in archives:
        if archive["report_name"] != "Content.csv":
            continue
        for row_number, row in enumerate(archive["rows"], 2):
            video_id = tiktok_video_id(row.get("Video link"))
            value = {
                "video_url": str(row.get("Video link") or "").strip(),
                "published_date": parse_month_day(row.get("Post time"), captured_at, field="content_post_time").isoformat(),
                "video_title": str(row.get("Video title") or ""),
                "views": parse_non_negative_int(row.get("Total views"), field="content_total_views"),
                "likes": parse_non_negative_int(row.get("Total likes"), field="content_total_likes"),
                "comments": parse_non_negative_int(row.get("Total comments"), field="content_total_comments"),
                "shares": parse_non_negative_int(row.get("Total shares"), field="content_total_shares"),
            }
            add_exact(
                result,
                video_id,
                value,
                source_ref(archive, row_number),
                conflict_code="conflicting_content_video",
                duplicate_counter=counters,
                counter_key="exact_duplicate_video_rows_collapsed",
            )
    return result


def published_tiktok_posts(posts: list[dict[str, Any]]) -> dict[str, dict[str, Any]]:
    result: dict[str, dict[str, Any]] = {}
    for row in posts:
        if row.get("platform") != "tiktok" or row.get("status") != "published":
            continue
        video_id = str(row.get("platform_post_id") or "").strip()
        if not video_id:
            continue
        if video_id in result:
            raise ImportError("duplicate_published_tiktok_platform_post_id")
        result[video_id] = row
    return result


def source_archives_for_record(archives: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return [
        {
            "file_name": archive["file_name"],
            "archive_sha256": archive["archive_sha256"],
            "report_name": archive["report_name"],
            "member_name": archive["member_name"],
            "member_sha256": archive["member_sha256"],
            "member_modified_at": archive["member_modified_at"],
            "row_count": archive["row_count"],
        }
        for archive in sorted(archives, key=lambda item: (item["report_name"], item["archive_sha256"]))
    ]


def import_fingerprint(archives: list[dict[str, Any]]) -> str:
    identity = [
        {
            "archive_sha256": archive["archive_sha256"],
            "member_sha256": archive["member_sha256"],
            "report_name": archive["report_name"],
        }
        for archive in sorted(archives, key=lambda item: item["archive_sha256"])
    ]
    return sha256_bytes(json.dumps(identity, sort_keys=True, separators=(",", ":")).encode("utf-8"))


def import_id(captured_at: datetime, fingerprint: str) -> str:
    return f"TIKTOK_STUDIO_{captured_at.strftime('%Y%m%dT%H%M%S')}_{fingerprint[:12].upper()}"


def daily_record(
    *,
    import_identifier: str,
    account_handle: str,
    observed_date: str,
    overview: dict[str, Any] | None,
    viewers: dict[str, Any] | None,
    source_refs: list[dict[str, Any]],
) -> dict[str, Any]:
    gaps = list(KNOWN_GAPS)
    if overview is None:
        gaps.append("overview_not_present_in_this_import")
    if viewers is None:
        gaps.append("viewers_not_present_in_this_import")
    elif viewers["total_viewers"] is None:
        gaps.append("total_viewers_undefined_in_source_export")
    return {
        "schema_version": SCHEMA_VERSION,
        "record_type": "account_daily",
        "import_id": import_identifier,
        "account_handle": account_handle,
        "observed_date": observed_date,
        "overview": overview,
        "viewers": viewers,
        "source_refs": sorted(source_refs, key=lambda ref: (ref["archive_sha256"], ref["source_row_number"])),
        "data_completeness": "partial",
        "known_gaps": gaps,
        "importer_version": IMPORTER_VERSION,
    }


def video_snapshot_record(
    *,
    import_identifier: str,
    captured_at: datetime,
    captured_at_precision: str,
    account_handle: str,
    video_id: str,
    value: dict[str, Any],
    source_refs: list[dict[str, Any]],
    post: dict[str, Any] | None,
) -> dict[str, Any]:
    mapping = (
        {
            "status": "exact_platform_post_id",
            "post_id": post["post_id"],
            "content_id": post["content_id"],
        }
        if post is not None
        else {"status": "unmatched", "post_id": None, "content_id": None}
    )
    engagement = value["likes"] + value["comments"] + value["shares"]
    return {
        "schema_version": SCHEMA_VERSION,
        "record_type": "video_snapshot",
        "import_id": import_identifier,
        "captured_at": as_iso(captured_at),
        "captured_at_precision": captured_at_precision,
        "account_handle": account_handle,
        "platform": "tiktok",
        "platform_video_id": video_id,
        "video_url": value["video_url"],
        "published_date": value["published_date"],
        "published_date_year_inferred_from_capture": True,
        "video_title": value["video_title"],
        "views": value["views"],
        "likes": value["likes"],
        "comments": value["comments"],
        "shares": value["shares"],
        "engagement": engagement,
        "snapshot_kind": "tiktok_studio_content_aggregate",
        "mapping": mapping,
        "source_refs": sorted(source_refs, key=lambda ref: (ref["archive_sha256"], ref["source_row_number"])),
        "data_completeness": "partial",
        "known_gaps": list(KNOWN_GAPS),
        "importer_version": IMPORTER_VERSION,
    }


def platform_metric_record(snapshot: dict[str, Any]) -> dict[str, Any]:
    mapping = snapshot["mapping"]
    return {
        "captured_at": snapshot["captured_at"],
        "observed_date": snapshot["captured_at"][:10],
        "post_id": mapping["post_id"],
        "content_id": mapping["content_id"],
        "platform": "tiktok",
        "platform_video_id": snapshot["platform_video_id"],
        "views": snapshot["views"],
        "engagement": snapshot["engagement"],
        "likes": snapshot["likes"],
        "comments": snapshot["comments"],
        "shares": snapshot["shares"],
        "watch_retention": None,
        "completion_rate": None,
        "source": TIKTOK_SOURCE,
        "source_locator": f"TikTok Studio ZIP Content.csv > video/{snapshot['platform_video_id']}",
        "metric_scope": "owned_account_video_aggregate",
        "views_semantics": "cumulative TikTok Studio Content.csv total at export capture; not a fixed T+ checkpoint",
        "known_gaps": list(KNOWN_GAPS),
        "data_completeness": "partial",
        "snapshot_id": snapshot["import_id"],
        "snapshot_kind": "tiktok_studio_weekly_csv",
        "tiktok_studio_import_id": snapshot["import_id"],
        "tiktok_studio_detail_status": detail_statuses(),
        "importer_version": IMPORTER_VERSION,
    }


def daily_semantics(row: dict[str, Any]) -> tuple[Any, ...]:
    return (row.get("account_handle"), row.get("observed_date"), row.get("overview"), row.get("viewers"))


def video_semantics(row: dict[str, Any]) -> tuple[Any, ...]:
    return (
        row.get("platform_video_id"),
        row.get("captured_at"),
        row.get("video_url"),
        row.get("published_date"),
        row.get("video_title"),
        row.get("views"),
        row.get("likes"),
        row.get("comments"),
        row.get("shares"),
        row.get("engagement"),
        row.get("mapping"),
    )


def metric_semantics(row: dict[str, Any]) -> tuple[Any, ...]:
    return (
        row.get("post_id"),
        row.get("snapshot_id"),
        row.get("platform_video_id"),
        row.get("captured_at"),
        row.get("views"),
        row.get("likes"),
        row.get("comments"),
        row.get("shares"),
        row.get("engagement"),
    )


def jsonl_append(existing: bytes, rows: list[dict[str, Any]]) -> bytes:
    if not rows:
        return existing
    prefix = existing if not existing or existing.endswith(b"\n") else existing + b"\n"
    payload = b"".join(
        (json.dumps(row, ensure_ascii=False, separators=(",", ":")) + "\n").encode("utf-8") for row in rows
    )
    return prefix + payload


def stage_file(path: Path, content: bytes) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.tiktok-stage-", dir=path.parent)
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        return temporary
    except BaseException:
        if temporary.exists():
            temporary.unlink()
        raise


def validate_staged(
    *,
    root: Path,
    imports_path: Path,
    imports_bytes: bytes,
    daily_path: Path,
    daily_bytes: bytes,
    videos_path: Path,
    videos_bytes: bytes,
    posts_path: Path,
    metrics_path: Path,
    metrics_bytes: bytes,
) -> None:
    staged = [
        stage_file(imports_path, imports_bytes),
        stage_file(daily_path, daily_bytes),
        stage_file(videos_path, videos_bytes),
        stage_file(metrics_path, metrics_bytes),
    ]
    try:
        result = subprocess.run(
            [
                sys.executable,
                str(VALIDATOR),
                "--root",
                str(root),
                "--imports",
                str(staged[0]),
                "--account-daily",
                str(staged[1]),
                "--video-snapshots",
                str(staged[2]),
                "--posts",
                str(posts_path),
                "--metrics",
                str(staged[3]),
                "--json",
            ],
            cwd=root,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
        if result.returncode != 0:
            raise ImportError("tiktok_studio_staged_validation_failed")
    finally:
        for path in staged:
            if path.exists():
                path.unlink()


def atomic_replace(path: Path, content: bytes) -> None:
    temporary = stage_file(path, content)
    try:
        os.replace(temporary, path)
    finally:
        if temporary.exists():
            temporary.unlink()


def lock_path(root: Path) -> Path:
    identity = hashlib.sha256(str(root.resolve()).encode("utf-8")).hexdigest()[:20]
    return Path(tempfile.gettempdir()) / f"idol-tiktok-studio-import-{identity}.lock"


def write_if_unchanged(
    root: Path,
    expected: dict[Path, str],
    replacements: dict[Path, bytes],
) -> None:
    with lock_path(root).open("a+") as handle:
        fcntl.flock(handle.fileno(), fcntl.LOCK_EX)
        try:
            for path, expected_digest in expected.items():
                current = path.read_bytes() if path.exists() else b""
                if sha256_bytes(current) != expected_digest:
                    raise ImportError("source_ledger_changed_during_tiktok_studio_import")
            for path, content in replacements.items():
                current = path.read_bytes() if path.exists() else b""
                if current != content:
                    atomic_replace(path, content)
        finally:
            fcntl.flock(handle.fileno(), fcntl.LOCK_UN)


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", default=str(ROOT))
    parser.add_argument("--input", action="append", required=True, help="One TikTok Studio Overview, Viewers, or Content ZIP export.")
    parser.add_argument("--account-handle", default="loom_idol_m")
    parser.add_argument("--captured-at", help="Optional timezone-aware ISO-8601 export capture time; default is the latest ZIP member timestamp.")
    parser.add_argument("--imports")
    parser.add_argument("--account-daily")
    parser.add_argument("--video-snapshots")
    parser.add_argument("--posts")
    parser.add_argument("--metrics")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--apply", action="store_true", help="Write validated local analytics rows.")
    mode.add_argument("--dry-run", action="store_true", help="Validate and summarize without changing ledgers.")
    parser.add_argument("--json", action="store_true")
    return parser.parse_args(argv)


def run(args: argparse.Namespace) -> tuple[dict[str, Any], int]:
    root = Path(args.root).resolve()
    archives = unique_archives(args.input)
    captured_at = parse_iso(args.captured_at) if args.captured_at else max(
        archive["member_modified_datetime"] for archive in archives
    ).replace(second=0, microsecond=0)
    captured_at_precision = "provided_iso8601" if args.captured_at else "zip_member_minute"
    paths = {
        "imports": resolve_path(root, args.imports, "analytics/records/tiktok-studio-imports.jsonl"),
        "daily": resolve_path(root, args.account_daily, "analytics/records/tiktok-studio-account-daily.jsonl"),
        "videos": resolve_path(root, args.video_snapshots, "analytics/records/tiktok-studio-video-snapshots.jsonl"),
        "posts": resolve_path(root, args.posts, "analytics/records/platform-posts.jsonl"),
        "metrics": resolve_path(root, args.metrics, "analytics/records/platform-metrics.jsonl"),
    }
    imports, imports_bytes = read_jsonl(paths["imports"], missing_is_empty=True, label="tiktok_studio_imports")
    existing_daily, daily_bytes = read_jsonl(paths["daily"], missing_is_empty=True, label="tiktok_studio_account_daily")
    existing_videos, videos_bytes = read_jsonl(paths["videos"], missing_is_empty=True, label="tiktok_studio_video_snapshots")
    posts, posts_bytes = read_jsonl(paths["posts"], missing_is_empty=False, label="platform_posts")
    metrics, metrics_bytes = read_jsonl(paths["metrics"], missing_is_empty=True, label="platform_metrics")

    fingerprint = import_fingerprint(archives)
    if any(row.get("import_fingerprint") == fingerprint for row in imports):
        summary = {
            "schema_version": IMPORTER_VERSION,
            "mode": "apply" if args.apply else "dry_run",
            "status": "already_imported",
            "writes_performed": False,
            "import_fingerprint": fingerprint,
            "source_archive_count": len(archives),
            "secret_values_printed": False,
        }
        return summary, 0

    counters: dict[str, int] = defaultdict(int)
    overview = normalize_overview(archives, captured_at, counters)
    viewers = normalize_viewers(archives, captured_at, counters)
    content = normalize_content(archives, captured_at, counters)
    post_by_video_id = published_tiktok_posts(posts)
    identifier = import_id(captured_at, fingerprint)

    daily_candidates: list[dict[str, Any]] = []
    for observed_date in sorted(set(overview) | set(viewers)):
        overview_entry = overview.get(observed_date)
        viewers_entry = viewers.get(observed_date)
        refs = []
        if overview_entry:
            refs.extend(overview_entry["source_refs"])
        if viewers_entry:
            refs.extend(viewers_entry["source_refs"])
        daily_candidates.append(
            daily_record(
                import_identifier=identifier,
                account_handle=args.account_handle,
                observed_date=observed_date,
                overview=overview_entry["value"] if overview_entry else None,
                viewers=viewers_entry["value"] if viewers_entry else None,
                source_refs=refs,
            )
        )
    video_candidates = [
        video_snapshot_record(
            import_identifier=identifier,
            captured_at=captured_at,
            captured_at_precision=captured_at_precision,
            account_handle=args.account_handle,
            video_id=video_id,
            value=entry["value"],
            source_refs=entry["source_refs"],
            post=post_by_video_id.get(video_id),
        )
        for video_id, entry in sorted(content.items())
    ]
    metrics_candidates = [
        platform_metric_record(snapshot)
        for snapshot in video_candidates
        if snapshot["mapping"]["status"] == "exact_platform_post_id"
    ]

    existing_daily_by_date = {str(row.get("observed_date")): row for row in existing_daily}
    daily_to_append: list[dict[str, Any]] = []
    for row in daily_candidates:
        previous = existing_daily_by_date.get(row["observed_date"])
        if previous is None:
            daily_to_append.append(row)
        elif daily_semantics(previous) != daily_semantics(row):
            raise ImportError(f"conflicting_existing_account_daily_{row['observed_date']}")

    existing_video_by_identity = {
        (str(row.get("platform_video_id")), str(row.get("captured_at"))): row for row in existing_videos
    }
    videos_to_append: list[dict[str, Any]] = []
    for row in video_candidates:
        key = (row["platform_video_id"], row["captured_at"])
        previous = existing_video_by_identity.get(key)
        if previous is None:
            videos_to_append.append(row)
        elif video_semantics(previous) != video_semantics(row):
            raise ImportError(f"conflicting_existing_video_snapshot_{row['platform_video_id']}")

    existing_metric_by_key = {
        (str(row.get("post_id")), str(row.get("snapshot_id"))): row
        for row in metrics
        if row.get("source") == TIKTOK_SOURCE
    }
    metrics_to_append: list[dict[str, Any]] = []
    for row in metrics_candidates:
        key = (row["post_id"], row["snapshot_id"])
        previous = existing_metric_by_key.get(key)
        if previous is None:
            metrics_to_append.append(row)
        elif metric_semantics(previous) != metric_semantics(row):
            raise ImportError(f"conflicting_existing_platform_metric_{row['post_id']}")

    undefined_dates = sorted(
        row["observed_date"] for row in daily_candidates if isinstance(row.get("viewers"), dict) and row["viewers"]["total_viewers"] is None
    )
    capture_note = (
        "The supplied ISO-8601 captured_at value is preserved as the export capture time."
        if args.captured_at
        else "The ZIP member timestamp is a minute-level capture proxy, not a verified TikTok report-generation timestamp."
    )
    import_record = {
        "schema_version": SCHEMA_VERSION,
        "record_type": "import",
        "import_id": identifier,
        "import_fingerprint": fingerprint,
        "account_handle": args.account_handle,
        "captured_at": as_iso(captured_at),
        "captured_at_precision": captured_at_precision,
        "source_archives": source_archives_for_record(archives),
        "available_metrics": list(AVAILABLE_METRICS),
        "unavailable_detail_dimensions": list(DETAIL_DIMENSIONS),
        "detail_statuses": detail_statuses(),
        "data_quality_notes": [
            "CSV month/day labels omit a year; the importer infers the calendar year from the export capture timestamp.",
            capture_note,
            *(
                [f"Total Viewers was exported as undefined for {', '.join(undefined_dates)} and is stored as null."]
                if undefined_dates
                else []
            ),
            "Content.csv contains cumulative per-video totals and is stored separately from daily account overview rows.",
        ],
        "deduplication": {
            "exact_duplicate_daily_rows_collapsed": counters["exact_duplicate_daily_rows_collapsed"],
            "exact_duplicate_video_rows_collapsed": counters["exact_duplicate_video_rows_collapsed"],
            "conflicting_rows": 0,
        },
        "mapping_summary": {
            "exact_platform_post_id_matches": len(metrics_candidates),
            "unmatched_video_count": len(video_candidates) - len(metrics_candidates),
        },
        "importer_version": IMPORTER_VERSION,
    }

    next_imports = jsonl_append(imports_bytes, [import_record])
    next_daily = jsonl_append(daily_bytes, daily_to_append)
    next_videos = jsonl_append(videos_bytes, videos_to_append)
    next_metrics = jsonl_append(metrics_bytes, metrics_to_append)
    validate_staged(
        root=root,
        imports_path=paths["imports"],
        imports_bytes=next_imports,
        daily_path=paths["daily"],
        daily_bytes=next_daily,
        videos_path=paths["videos"],
        videos_bytes=next_videos,
        posts_path=paths["posts"],
        metrics_path=paths["metrics"],
        metrics_bytes=next_metrics,
    )

    summary = {
        "schema_version": IMPORTER_VERSION,
        "mode": "apply" if args.apply else "dry_run",
        "status": "imported" if args.apply else "ready_for_apply",
        "writes_performed": bool(args.apply),
        "import_id": identifier,
        "import_fingerprint": fingerprint,
        "captured_at": as_iso(captured_at),
        "source_archive_count": len(archives),
        "reports": sorted({archive["report_name"] for archive in archives}),
        "daily_rows_in_batch": len(daily_candidates),
        "daily_rows_to_append": len(daily_to_append),
        "video_snapshots_in_batch": len(video_candidates),
        "video_snapshots_to_append": len(videos_to_append),
        "exact_post_id_matches": len(metrics_candidates),
        "platform_metric_rows_to_append": len(metrics_to_append),
        "unmatched_video_count": len(video_candidates) - len(metrics_candidates),
        "duplicate_daily_rows_collapsed": counters["exact_duplicate_daily_rows_collapsed"],
        "duplicate_video_rows_collapsed": counters["exact_duplicate_video_rows_collapsed"],
        "total_viewers_undefined_dates": undefined_dates,
        "secret_values_printed": False,
    }
    if args.apply:
        write_if_unchanged(
            root,
            {
                paths["imports"]: sha256_bytes(imports_bytes),
                paths["daily"]: sha256_bytes(daily_bytes),
                paths["videos"]: sha256_bytes(videos_bytes),
                paths["posts"]: sha256_bytes(posts_bytes),
                paths["metrics"]: sha256_bytes(metrics_bytes),
            },
            {
                paths["imports"]: next_imports,
                paths["daily"]: next_daily,
                paths["videos"]: next_videos,
                paths["metrics"]: next_metrics,
            },
        )
    return summary, 0


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        summary, status = run(args)
    except ImportError as exc:
        summary = {
            "schema_version": IMPORTER_VERSION,
            "mode": "apply" if args.apply else "dry_run",
            "status": "blocked",
            "error": str(exc),
            "writes_performed": False,
            "secret_values_printed": False,
        }
        status = 1
    if args.json:
        print(json.dumps(summary, ensure_ascii=False, indent=2))
    elif status == 0:
        print(
            f"OK: {summary.get('status')} — {summary.get('daily_rows_to_append', 0)} daily row(s), "
            f"{summary.get('video_snapshots_to_append', 0)} video snapshot(s), "
            f"{summary.get('platform_metric_rows_to_append', 0)} mapped metric row(s)"
        )
    else:
        print(f"ERROR: {summary['error']}", file=sys.stderr)
    return status


if __name__ == "__main__":
    raise SystemExit(main())
