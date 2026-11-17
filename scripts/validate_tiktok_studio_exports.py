#!/usr/bin/env python3
"""Validate normalized local TikTok Studio ZIP-export ledgers.

This validator is deliberately local-only. It checks that an imported CSV
snapshot remains tied to its ZIP hashes, that overlapping reports were merged
only when their values matched, and that a canonical platform metric exists
only for an exact already-published TikTok post ID. It never calls TikTok,
creates publication facts, or fills unavailable audience/retention data.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import datetime
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
SCHEMA_VERSION = "idol_tiktok_studio_export.v1"
IMPORTER_VERSION = "idol_tiktok_studio_importer.v1"
TIKTOK_SOURCE = "official_tiktok_studio_csv_export"
DETAIL_DIMENSIONS = (
    "country",
    "age_gender",
    "traffic_source",
    "average_watch_time",
    "completion_rate",
    "retention_curve",
)
DETAIL_STATUSES = {"populated", "not_in_export", "manual_ui_required", "request_failed"}
SHA256_RE = re.compile(r"^[a-f0-9]{64}$")
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
TIKTOK_ID_RE = re.compile(r"^\d{8,}$")
EXPECTED_GAP_CODES = {f"{dimension}_not_in_weekly_tiktok_studio_csv_export" for dimension in DETAIL_DIMENSIONS}


def path_for(root: Path, supplied: str | None, default: str) -> Path:
    path = Path(supplied) if supplied else root / default
    return path if path.is_absolute() else root / path


def read_jsonl(path: Path, label: str, errors: list[str]) -> list[tuple[int, dict[str, Any]]]:
    if not path.is_file():
        errors.append(f"{label}_missing")
        return []
    rows: list[tuple[int, dict[str, Any]]] = []
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeDecodeError):
        errors.append(f"{label}_unreadable")
        return []
    for line_no, line in enumerate(lines, 1):
        if not line.strip():
            continue
        try:
            value = json.loads(line)
        except json.JSONDecodeError:
            errors.append(f"{label}_invalid_json_line_{line_no}")
            continue
        if not isinstance(value, dict):
            errors.append(f"{label}_row_not_object_{line_no}")
            continue
        rows.append((line_no, value))
    return rows


def as_text(value: Any) -> str:
    return value if isinstance(value, str) else ""


def valid_timestamp(value: Any) -> bool:
    if not isinstance(value, str) or not value:
        return False
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return False
    return parsed.tzinfo is not None


def valid_date(value: Any) -> bool:
    if not isinstance(value, str) or not DATE_RE.fullmatch(value):
        return False
    try:
        datetime.strptime(value, "%Y-%m-%d")
    except ValueError:
        return False
    return True


def non_negative_int(value: Any) -> bool:
    return isinstance(value, int) and not isinstance(value, bool) and value >= 0


def required(record: dict[str, Any], fields: tuple[str, ...], label: str, errors: list[str]) -> None:
    for field in fields:
        if field not in record:
            errors.append(f"{label}_missing_{field}")


def validate_source_refs(
    refs: Any,
    source_archives: dict[str, dict[str, Any]],
    label: str,
    errors: list[str],
) -> None:
    if not isinstance(refs, list) or not refs:
        errors.append(f"{label}_source_refs_invalid")
        return
    seen: set[tuple[str, str, int]] = set()
    for index, ref in enumerate(refs):
        ref_label = f"{label}_source_ref_{index}"
        if not isinstance(ref, dict):
            errors.append(f"{ref_label}_not_object")
            continue
        archive_sha = as_text(ref.get("archive_sha256"))
        report_name = as_text(ref.get("report_name"))
        row_number = ref.get("source_row_number")
        if not SHA256_RE.fullmatch(archive_sha):
            errors.append(f"{ref_label}_invalid_archive_sha256")
        if archive_sha not in source_archives:
            errors.append(f"{ref_label}_unknown_archive")
        elif source_archives[archive_sha].get("report_name") != report_name:
            errors.append(f"{ref_label}_report_name_mismatch")
        if report_name not in {"Overview.csv", "Viewers.csv", "Content.csv"}:
            errors.append(f"{ref_label}_invalid_report_name")
        if not non_negative_int(row_number) or row_number < 2:
            errors.append(f"{ref_label}_invalid_source_row_number")
        if isinstance(row_number, int):
            key = (archive_sha, report_name, row_number)
            if key in seen:
                errors.append(f"{label}_duplicate_source_ref")
            seen.add(key)


def validate_detail_statuses(value: Any, label: str, errors: list[str]) -> None:
    if not isinstance(value, dict):
        errors.append(f"{label}_not_object")
        return
    missing = set(DETAIL_DIMENSIONS) - set(value)
    unexpected = set(value) - set(DETAIL_DIMENSIONS)
    for key in sorted(missing):
        errors.append(f"{label}_missing_{key}")
    for key in sorted(unexpected):
        errors.append(f"{label}_unexpected_{key}")
    for dimension in DETAIL_DIMENSIONS:
        row = value.get(dimension)
        row_label = f"{label}_{dimension}"
        if not isinstance(row, dict):
            errors.append(f"{row_label}_not_object")
            continue
        if not as_text(row.get("source_dimension")):
            errors.append(f"{row_label}_missing_source_dimension")
        if row.get("status") not in DETAIL_STATUSES:
            errors.append(f"{row_label}_invalid_status")
        if not non_negative_int(row.get("row_count")):
            errors.append(f"{row_label}_invalid_row_count")
        if "reason_code" in row and not as_text(row.get("reason_code")):
            errors.append(f"{row_label}_blank_reason_code")


def validate_imports(
    rows: list[tuple[int, dict[str, Any]]], errors: list[str]
) -> dict[str, dict[str, Any]]:
    imports: dict[str, dict[str, Any]] = {}
    fingerprints: set[str] = set()
    for line_no, row in rows:
        label = f"imports_line_{line_no}"
        required(
            row,
            (
                "schema_version",
                "record_type",
                "import_id",
                "import_fingerprint",
                "account_handle",
                "captured_at",
                "captured_at_precision",
                "source_archives",
                "available_metrics",
                "unavailable_detail_dimensions",
                "data_quality_notes",
                "deduplication",
                "mapping_summary",
                "importer_version",
            ),
            label,
            errors,
        )
        if row.get("schema_version") != SCHEMA_VERSION:
            errors.append(f"{label}_unsupported_schema_version")
        if row.get("record_type") != "import":
            errors.append(f"{label}_invalid_record_type")
        import_id = as_text(row.get("import_id"))
        if not import_id:
            errors.append(f"{label}_missing_import_id")
        elif import_id in imports:
            errors.append(f"{label}_duplicate_import_id")
        if not SHA256_RE.fullmatch(as_text(row.get("import_fingerprint"))):
            errors.append(f"{label}_invalid_import_fingerprint")
        elif row["import_fingerprint"] in fingerprints:
            errors.append(f"{label}_duplicate_import_fingerprint")
        if not as_text(row.get("account_handle")):
            errors.append(f"{label}_missing_account_handle")
        if not valid_timestamp(row.get("captured_at")):
            errors.append(f"{label}_invalid_captured_at")
        if row.get("captured_at_precision") not in {"zip_member_minute", "provided_iso8601"}:
            errors.append(f"{label}_invalid_captured_at_precision")
        if row.get("importer_version") != IMPORTER_VERSION:
            errors.append(f"{label}_invalid_importer_version")

        source_archives = row.get("source_archives")
        if not isinstance(source_archives, list) or not source_archives:
            errors.append(f"{label}_source_archives_invalid")
            source_archives = []
        archives_by_sha: dict[str, dict[str, Any]] = {}
        for index, archive in enumerate(source_archives):
            archive_label = f"{label}_source_archive_{index}"
            if not isinstance(archive, dict):
                errors.append(f"{archive_label}_not_object")
                continue
            archive_sha = as_text(archive.get("archive_sha256"))
            member_sha = as_text(archive.get("member_sha256"))
            report_name = as_text(archive.get("report_name"))
            if not as_text(archive.get("file_name")):
                errors.append(f"{archive_label}_missing_file_name")
            if not SHA256_RE.fullmatch(archive_sha):
                errors.append(f"{archive_label}_invalid_archive_sha256")
            if not SHA256_RE.fullmatch(member_sha):
                errors.append(f"{archive_label}_invalid_member_sha256")
            if report_name not in {"Overview.csv", "Viewers.csv", "Content.csv"}:
                errors.append(f"{archive_label}_invalid_report_name")
            if not as_text(archive.get("member_name")):
                errors.append(f"{archive_label}_missing_member_name")
            if not valid_timestamp(archive.get("member_modified_at")):
                errors.append(f"{archive_label}_invalid_member_modified_at")
            if not non_negative_int(archive.get("row_count")):
                errors.append(f"{archive_label}_invalid_row_count")
            if archive_sha in archives_by_sha:
                errors.append(f"{archive_label}_duplicate_archive_sha256")
            if archive_sha:
                archives_by_sha[archive_sha] = archive

        availability = row.get("available_metrics")
        unavailable = row.get("unavailable_detail_dimensions")
        if not isinstance(availability, list) or not availability or any(not as_text(item) for item in availability):
            errors.append(f"{label}_available_metrics_invalid")
        elif len(set(availability)) != len(availability):
            errors.append(f"{label}_available_metrics_not_unique")
        if not isinstance(unavailable, list) or not unavailable or any(not as_text(item) for item in unavailable):
            errors.append(f"{label}_unavailable_detail_dimensions_invalid")
        elif len(set(unavailable)) != len(unavailable):
            errors.append(f"{label}_unavailable_detail_dimensions_not_unique")
        elif set(unavailable) != set(DETAIL_DIMENSIONS):
            errors.append(f"{label}_unavailable_detail_dimensions_mismatch")
        validate_detail_statuses(row.get("detail_statuses"), f"{label}_detail_statuses", errors)

        dedupe = row.get("deduplication")
        if not isinstance(dedupe, dict):
            errors.append(f"{label}_deduplication_invalid")
        else:
            for field in (
                "exact_duplicate_daily_rows_collapsed",
                "exact_duplicate_video_rows_collapsed",
                "conflicting_rows",
            ):
                if not non_negative_int(dedupe.get(field)):
                    errors.append(f"{label}_deduplication_invalid_{field}")
            if dedupe.get("conflicting_rows") not in {0, None}:
                errors.append(f"{label}_deduplication_conflicts_present")
        summary = row.get("mapping_summary")
        if not isinstance(summary, dict):
            errors.append(f"{label}_mapping_summary_invalid")
        else:
            for field in ("exact_platform_post_id_matches", "unmatched_video_count"):
                if not non_negative_int(summary.get(field)):
                    errors.append(f"{label}_mapping_summary_invalid_{field}")

        if import_id and import_id not in imports:
            imports[import_id] = {
                "row": row,
                "source_archives": archives_by_sha,
            }
        fingerprint = as_text(row.get("import_fingerprint"))
        if fingerprint:
            fingerprints.add(fingerprint)
    return imports


def validate_account_daily(
    rows: list[tuple[int, dict[str, Any]]], imports: dict[str, dict[str, Any]], errors: list[str]
) -> None:
    seen_dates: set[str] = set()
    for line_no, row in rows:
        label = f"account_daily_line_{line_no}"
        required(
            row,
            (
                "schema_version", "record_type", "import_id", "account_handle", "observed_date",
                "overview", "viewers", "source_refs", "data_completeness", "known_gaps", "importer_version",
            ),
            label,
            errors,
        )
        if row.get("schema_version") != SCHEMA_VERSION or row.get("record_type") != "account_daily":
            errors.append(f"{label}_invalid_schema_or_type")
        import_id = as_text(row.get("import_id"))
        if import_id not in imports:
            errors.append(f"{label}_unknown_import_id")
            source_archives: dict[str, dict[str, Any]] = {}
        else:
            source_archives = imports[import_id]["source_archives"]
        observed_date = row.get("observed_date")
        if not valid_date(observed_date):
            errors.append(f"{label}_invalid_observed_date")
        elif observed_date in seen_dates:
            errors.append(f"{label}_duplicate_observed_date")
        else:
            seen_dates.add(observed_date)
        if not as_text(row.get("account_handle")):
            errors.append(f"{label}_missing_account_handle")
        for field, expected in (
            ("overview", ("video_views", "profile_views", "likes", "comments", "shares")),
            ("viewers", ("total_viewers", "new_viewers", "returning_viewers")),
        ):
            value = row.get(field)
            if value is None:
                continue
            if not isinstance(value, dict):
                errors.append(f"{label}_{field}_invalid")
                continue
            for key in expected:
                if key not in value:
                    errors.append(f"{label}_{field}_missing_{key}")
                    continue
                if field == "viewers" and key == "total_viewers" and value[key] is None:
                    continue
                if not non_negative_int(value[key]):
                    errors.append(f"{label}_{field}_invalid_{key}")
        if row.get("overview") is None and row.get("viewers") is None:
            errors.append(f"{label}_no_metrics")
        validate_source_refs(row.get("source_refs"), source_archives, label, errors)
        if row.get("data_completeness") != "partial":
            errors.append(f"{label}_invalid_data_completeness")
        gaps = row.get("known_gaps")
        if not isinstance(gaps, list) or not gaps or len(set(gaps)) != len(gaps):
            errors.append(f"{label}_known_gaps_invalid")
        if row.get("importer_version") != IMPORTER_VERSION:
            errors.append(f"{label}_invalid_importer_version")


def published_tiktok_posts(rows: list[tuple[int, dict[str, Any]]], errors: list[str]) -> dict[str, dict[str, Any]]:
    posts: dict[str, dict[str, Any]] = {}
    for line_no, row in rows:
        if row.get("platform") != "tiktok" or row.get("status") != "published":
            continue
        video_id = as_text(row.get("platform_post_id"))
        if not video_id:
            continue
        if video_id in posts:
            errors.append(f"platform_posts_duplicate_tiktok_video_id_{video_id}")
            continue
        posts[video_id] = row
    return posts


def validate_video_snapshots(
    rows: list[tuple[int, dict[str, Any]]],
    imports: dict[str, dict[str, Any]],
    published_posts: dict[str, dict[str, Any]],
    errors: list[str],
) -> dict[tuple[str, str], dict[str, Any]]:
    snapshots: dict[tuple[str, str], dict[str, Any]] = {}
    for line_no, row in rows:
        label = f"video_snapshot_line_{line_no}"
        required(
            row,
            (
                "schema_version", "record_type", "import_id", "captured_at", "captured_at_precision",
                "account_handle", "platform", "platform_video_id", "video_url", "published_date",
                "published_date_year_inferred_from_capture", "video_title", "views", "likes", "comments",
                "shares", "engagement", "snapshot_kind", "mapping", "source_refs", "data_completeness",
                "known_gaps", "importer_version",
            ),
            label,
            errors,
        )
        if row.get("schema_version") != SCHEMA_VERSION or row.get("record_type") != "video_snapshot":
            errors.append(f"{label}_invalid_schema_or_type")
        import_id = as_text(row.get("import_id"))
        import_row = imports.get(import_id)
        source_archives = import_row["source_archives"] if import_row else {}
        if import_row is None:
            errors.append(f"{label}_unknown_import_id")
        if not valid_timestamp(row.get("captured_at")):
            errors.append(f"{label}_invalid_captured_at")
        elif import_row and row.get("captured_at") != import_row["row"].get("captured_at"):
            errors.append(f"{label}_captured_at_does_not_match_import")
        if row.get("captured_at_precision") not in {"zip_member_minute", "provided_iso8601"}:
            errors.append(f"{label}_invalid_captured_at_precision")
        elif import_row and row.get("captured_at_precision") != import_row["row"].get("captured_at_precision"):
            errors.append(f"{label}_captured_at_precision_does_not_match_import")
        video_id = as_text(row.get("platform_video_id"))
        if not TIKTOK_ID_RE.fullmatch(video_id):
            errors.append(f"{label}_invalid_platform_video_id")
        if not as_text(row.get("video_url")):
            errors.append(f"{label}_missing_video_url")
        if not valid_date(row.get("published_date")):
            errors.append(f"{label}_invalid_published_date")
        if not isinstance(row.get("published_date_year_inferred_from_capture"), bool):
            errors.append(f"{label}_invalid_published_date_year_inferred_from_capture")
        if row.get("platform") != "tiktok":
            errors.append(f"{label}_invalid_platform")
        if row.get("snapshot_kind") != "tiktok_studio_content_aggregate":
            errors.append(f"{label}_invalid_snapshot_kind")
        for field in ("views", "likes", "comments", "shares", "engagement"):
            if not non_negative_int(row.get(field)):
                errors.append(f"{label}_invalid_{field}")
        if all(non_negative_int(row.get(field)) for field in ("likes", "comments", "shares", "engagement")):
            if row["engagement"] != row["likes"] + row["comments"] + row["shares"]:
                errors.append(f"{label}_engagement_mismatch")
        mapping = row.get("mapping")
        if not isinstance(mapping, dict):
            errors.append(f"{label}_mapping_invalid")
        elif mapping.get("status") == "exact_platform_post_id":
            post = published_posts.get(video_id)
            if post is None:
                errors.append(f"{label}_mapped_video_not_in_published_posts")
            elif mapping.get("post_id") != post.get("post_id") or mapping.get("content_id") != post.get("content_id"):
                errors.append(f"{label}_mapped_post_values_mismatch")
        elif mapping.get("status") == "unmatched":
            if mapping.get("post_id") is not None or mapping.get("content_id") is not None:
                errors.append(f"{label}_unmatched_mapping_must_be_null")
        else:
            errors.append(f"{label}_invalid_mapping_status")
        validate_source_refs(row.get("source_refs"), source_archives, label, errors)
        if row.get("data_completeness") != "partial":
            errors.append(f"{label}_invalid_data_completeness")
        gaps = row.get("known_gaps")
        if not isinstance(gaps, list) or EXPECTED_GAP_CODES - set(gaps):
            errors.append(f"{label}_known_gaps_missing_detail_dimensions")
        if row.get("importer_version") != IMPORTER_VERSION:
            errors.append(f"{label}_invalid_importer_version")
        key = (video_id, as_text(row.get("captured_at")))
        if video_id and key in snapshots:
            errors.append(f"{label}_duplicate_snapshot_identity")
        elif video_id:
            snapshots[key] = row
    return snapshots


def validate_platform_metrics(
    rows: list[tuple[int, dict[str, Any]]],
    snapshots: dict[tuple[str, str], dict[str, Any]],
    errors: list[str],
) -> None:
    metrics: dict[tuple[str, str], dict[str, Any]] = {}
    for line_no, row in rows:
        if row.get("source") != TIKTOK_SOURCE:
            continue
        label = f"platform_metrics_line_{line_no}"
        import_id = as_text(row.get("snapshot_id"))
        video_id = as_text(row.get("platform_video_id"))
        key = (video_id, as_text(row.get("captured_at")))
        snapshot = snapshots.get(key)
        if snapshot is None:
            errors.append(f"{label}_missing_matching_video_snapshot")
            continue
        if import_id != snapshot.get("import_id"):
            errors.append(f"{label}_snapshot_id_mismatch")
        mapping = snapshot.get("mapping", {})
        if mapping.get("status") != "exact_platform_post_id":
            errors.append(f"{label}_metric_for_unmatched_video")
        for field in ("post_id", "content_id"):
            if row.get(field) != mapping.get(field):
                errors.append(f"{label}_{field}_mismatch")
        if row.get("platform") != "tiktok":
            errors.append(f"{label}_invalid_platform")
        if row.get("observed_date") != str(row.get("captured_at", ""))[:10]:
            errors.append(f"{label}_observed_date_mismatch")
        if "measurement_window" in row:
            errors.append(f"{label}_must_not_claim_fixed_checkpoint")
        if row.get("snapshot_kind") != "tiktok_studio_weekly_csv":
            errors.append(f"{label}_invalid_snapshot_kind")
        if row.get("data_completeness") != "partial":
            errors.append(f"{label}_invalid_data_completeness")
        if row.get("watch_retention") is not None or row.get("completion_rate") is not None:
            errors.append(f"{label}_must_not_infer_retention_or_completion")
        for field in ("views", "likes", "comments", "shares", "engagement"):
            if row.get(field) != snapshot.get(field):
                errors.append(f"{label}_{field}_does_not_match_snapshot")
        validate_detail_statuses(row.get("tiktok_studio_detail_status"), f"{label}_detail_statuses", errors)
        metric_key = (as_text(row.get("post_id")), import_id)
        if metric_key in metrics:
            errors.append(f"{label}_duplicate_post_import_metric")
        metrics[metric_key] = row

    expected = {
        (as_text(snapshot.get("mapping", {}).get("post_id")), as_text(snapshot.get("import_id")))
        for snapshot in snapshots.values()
        if snapshot.get("mapping", {}).get("status") == "exact_platform_post_id"
    }
    actual = set(metrics)
    for post_id, import_id in sorted(expected - actual):
        errors.append(f"platform_metrics_missing_mapped_snapshot_{post_id}_{import_id}")
    for post_id, import_id in sorted(actual - expected):
        errors.append(f"platform_metrics_unexpected_mapped_snapshot_{post_id}_{import_id}")


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", default=str(ROOT))
    parser.add_argument("--imports")
    parser.add_argument("--account-daily")
    parser.add_argument("--video-snapshots")
    parser.add_argument("--posts")
    parser.add_argument("--metrics")
    parser.add_argument("--json", action="store_true")
    return parser.parse_args(argv)


def run(args: argparse.Namespace) -> tuple[dict[str, Any], int]:
    root = Path(args.root).resolve()
    paths = {
        "imports": path_for(root, args.imports, "analytics/records/tiktok-studio-imports.jsonl"),
        "account_daily": path_for(root, args.account_daily, "analytics/records/tiktok-studio-account-daily.jsonl"),
        "video_snapshots": path_for(root, args.video_snapshots, "analytics/records/tiktok-studio-video-snapshots.jsonl"),
        "posts": path_for(root, args.posts, "analytics/records/platform-posts.jsonl"),
        "metrics": path_for(root, args.metrics, "analytics/records/platform-metrics.jsonl"),
    }
    errors: list[str] = []
    import_rows = read_jsonl(paths["imports"], "imports", errors)
    daily_rows = read_jsonl(paths["account_daily"], "account_daily", errors)
    video_rows = read_jsonl(paths["video_snapshots"], "video_snapshots", errors)
    post_rows = read_jsonl(paths["posts"], "platform_posts", errors)
    metric_rows = read_jsonl(paths["metrics"], "platform_metrics", errors)
    imports = validate_imports(import_rows, errors)
    validate_account_daily(daily_rows, imports, errors)
    published_posts = published_tiktok_posts(post_rows, errors)
    snapshots = validate_video_snapshots(video_rows, imports, published_posts, errors)
    validate_platform_metrics(metric_rows, snapshots, errors)
    result = {
        "status": "pass" if not errors else "fail",
        "imports": len(import_rows),
        "account_daily_rows": len(daily_rows),
        "video_snapshot_rows": len(video_rows),
        "mapped_platform_metric_rows": sum(1 for _line, row in metric_rows if row.get("source") == TIKTOK_SOURCE),
        "errors": errors,
    }
    return result, 0 if not errors else 1


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    result, status = run(args)
    if args.json:
        print(json.dumps(result, ensure_ascii=False, indent=2))
    elif status == 0:
        print(
            "OK: "
            f"{result['imports']} import(s), {result['account_daily_rows']} account-day row(s), "
            f"{result['video_snapshot_rows']} video snapshot row(s)"
        )
    else:
        for error in result["errors"]:
            print(f"ERROR: {error}", file=sys.stderr)
    return status


if __name__ == "__main__":
    raise SystemExit(main())
