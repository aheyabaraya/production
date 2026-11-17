#!/usr/bin/env python3
"""No-network tests for the approved read-only platform metric collector."""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from datetime import datetime
from pathlib import Path
from urllib.parse import parse_qs, urlparse
from unittest import mock


SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))

import idol_collect_platform_metrics as collector  # noqa: E402


def post(
    status: str,
    platform_post_id: str = "video-1",
    published_at: str = "2026-07-30T09:00:00+09:00",
) -> dict[str, object]:
    return {
        "post_id": "POST-001",
        "content_id": "CONTENT-001",
        "platform": "youtube_shorts",
        "template_type": "clip",
        "message": "test",
        "asset_or_clip": "test.mp4",
        "caption": "test",
        "hashtags": ["#Loom"],
        "scheduled_at": "2026-07-30T09:00:00+09:00",
        "status": status,
        "analysis_scope": "date_based",
        "published_at": published_at,
        "platform_post_id": platform_post_id,
    }


class MetricCollectorTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        records = self.root / "analytics" / "records"
        records.mkdir(parents=True)
        (records / "platform-posts.jsonl").write_text(json.dumps(post("published")) + "\n", encoding="utf-8")
        (records / "platform-metrics.jsonl").write_text("", encoding="utf-8")

    def tearDown(self) -> None:
        self.temp.cleanup()

    def test_dry_run_makes_no_http_or_local_writes(self) -> None:
        argv = [
            "idol_collect_platform_metrics.py",
            "--root",
            str(self.root),
            "--platform",
            "youtube",
            "--now",
            "2026-07-30T09:30:00+09:00",
            "--dry-run",
        ]
        with mock.patch.object(sys, "argv", argv), mock.patch.object(collector, "http_json") as request_json:
            summary, status = collector.run(collector.parse_args())
        self.assertEqual(status, 0)
        self.assertEqual(summary["mode"], "dry_run")
        self.assertEqual(summary["published_posts_selected"]["youtube"], 0)
        self.assertEqual(summary["published_posts_excluded"]["youtube"], {"no_checkpoint_due_now": 1})
        request_json.assert_not_called()
        self.assertEqual((self.root / "analytics" / "records" / "platform-metrics.jsonl").read_text(), "")

    def test_only_published_rows_are_eligible(self) -> None:
        rows = [post("published"), post("planned", "video-2")]
        selected, excluded = collector.metric_eligible_rows(
            rows,
            "youtube",
            datetime.fromisoformat("2026-07-30T09:30:00+09:00"),
            [],
        )
        self.assertEqual(selected, [])
        self.assertEqual(excluded, {"no_checkpoint_due_now": 1})

    def test_old_published_rows_are_excluded_before_any_api_call(self) -> None:
        old = post("published", "old-video", "2026-06-17T09:00:00+09:00")
        current = post("published", "current-video", "2026-07-29T09:00:00+09:00")
        old["post_id"] = "POST-OLD"
        current["post_id"] = "POST-CURRENT"
        ledger = self.root / "analytics" / "records" / "platform-posts.jsonl"
        ledger.write_text(
            "\n".join(json.dumps(row) for row in (old, current)) + "\n",
            encoding="utf-8",
        )
        argv = [
            "idol_collect_platform_metrics.py",
            "--root",
            str(self.root),
            "--platform",
            "youtube",
            "--now",
            "2026-07-30T09:30:00+09:00",
            "--dry-run",
        ]
        with mock.patch.object(sys, "argv", argv), mock.patch.object(collector, "http_json") as request_json:
            summary, status = collector.run(collector.parse_args())
        self.assertEqual(status, 0)
        self.assertEqual(summary["published_posts_found"]["youtube"], 2)
        self.assertEqual(summary["published_posts_selected"]["youtube"], 1)
        self.assertEqual(summary["published_posts_excluded"]["youtube"], {"checkpoint_series_closed": 1})
        request_json.assert_not_called()

    def test_only_fixed_performance_checkpoints_are_selected(self) -> None:
        row = post("published", published_at="2026-07-29T09:30:00+09:00")
        before_due, before_excluded = collector.metric_eligible_rows(
            [row],
            "youtube",
            datetime.fromisoformat("2026-07-30T09:29:59+09:00"),
            [],
        )
        at_due, due_excluded = collector.metric_eligible_rows(
            [row],
            "youtube",
            datetime.fromisoformat("2026-07-30T09:30:00+09:00"),
            [],
        )
        self.assertEqual(before_due, [])
        self.assertEqual(before_excluded, {"no_checkpoint_due_now": 1})
        self.assertEqual(len(at_due), 1)
        self.assertEqual(at_due[0]["_metric_checkpoint"], "T+24h")
        self.assertEqual(due_excluded, {})

    def test_captured_checkpoint_is_not_selected_again(self) -> None:
        row = post("published", published_at="2026-07-29T09:30:00+09:00")
        metric = {"post_id": "POST-001", "measurement_window": "T+24h"}
        selected, excluded = collector.metric_eligible_rows(
            [row],
            "youtube",
            datetime.fromisoformat("2026-07-30T10:00:00+09:00"),
            [metric],
        )
        self.assertEqual(selected, [])
        self.assertEqual(excluded, {"no_checkpoint_due_now": 1})

    def test_metric_row_keeps_checkpoint_identity_and_actual_lag(self) -> None:
        row = post("published")
        row["_metric_checkpoint"] = "T+24h"
        row["_checkpoint_target_at"] = "2026-07-31T09:00:00+09:00"
        row["_checkpoint_lag_seconds"] = 1800
        metric = collector.base_metric_row(
            row,
            now=datetime.fromisoformat("2026-07-31T09:30:00+09:00"),
            views=10,
            engagement=1,
            source="test",
            source_locator="test",
            metric_scope="test",
            known_gaps=[],
        )
        self.assertEqual(metric["measurement_window"], "T+24h")
        self.assertEqual(metric["checkpoint_target_at"], "2026-07-31T09:00:00+09:00")
        self.assertEqual(metric["checkpoint_lag_seconds"], 1800)

    def test_vercel_count_accepts_only_non_negative_integral_response(self) -> None:
        self.assertEqual(collector.vercel_count({"data": {"value": 22}}), 22)
        self.assertIsNone(collector.vercel_count({"data": {"value": -1}}))
        self.assertIsNone(collector.vercel_count({"data": {"value": 2.5}}))

    def test_youtube_scope_gap_stops_before_http(self) -> None:
        secrets = self.root / ".runtime" / "secrets"
        secrets.mkdir(parents=True)
        (secrets / "youtube-token.json").write_text(
            json.dumps(
                {
                    "access_token": "dummy-access",
                    "refresh_token": "dummy-refresh",
                    "scope": "https://www.googleapis.com/auth/youtube.upload",
                }
            ),
            encoding="utf-8",
        )
        summary: dict[str, object] = {}
        with mock.patch.object(collector, "http_json") as request_json:
            collected = collector.collect_youtube(
                self.root,
                [post("published")],
                datetime.now(collector.KST),
                summary,
            )
        self.assertEqual(collected, [])
        self.assertEqual(summary["state"], "blocked")
        self.assertEqual(summary["skipped"], {"missing_youtube_metric_scope": 1})
        request_json.assert_not_called()

    def test_youtube_report_supports_breakdown_query_parameters(self) -> None:
        with mock.patch.object(
            collector,
            "http_json",
            return_value={"columnHeaders": [], "rows": []},
        ) as request_json:
            collector.youtube_report(
                "dummy-access",
                "video-1",
                "2026-07-30",
                "2026-08-02",
                collector.YOUTUBE_DETAIL_METRICS,
                dimensions="country",
                filters="video==video-1",
                sort="-views",
                max_results=25,
            )

        url = request_json.call_args.args[0]
        query = parse_qs(urlparse(url).query)
        self.assertEqual(query["dimensions"], ["country"])
        self.assertEqual(query["filters"], ["video==video-1"])
        self.assertEqual(query["sort"], ["-views"])
        self.assertEqual(query["maxResults"], ["25"])

    def test_youtube_uses_public_statistics_when_analytics_row_lags(self) -> None:
        secrets = self.root / ".runtime" / "secrets"
        secrets.mkdir(parents=True)
        (secrets / "youtube-token.json").write_text(
            json.dumps(
                {
                    "access_token": "dummy-access",
                    "refresh_token": "dummy-refresh",
                    "scope": " ".join(sorted(collector.YOUTUBE_REQUIRED_METRIC_SCOPES)),
                }
            ),
            encoding="utf-8",
        )
        summary: dict[str, object] = {}
        with mock.patch.object(
            collector,
            "http_json",
            side_effect=[
                {"columnHeaders": [], "rows": []},
                {
                    "items": [
                        {
                            "id": "video-1",
                            "statistics": {"viewCount": "305", "likeCount": "3", "commentCount": "1"},
                        }
                    ]
                },
            ],
        ) as request_json:
            collected = collector.collect_youtube(
                self.root,
                [post("published")],
                datetime.now(collector.KST),
                summary,
            )
        self.assertEqual(request_json.call_count, 2)
        self.assertEqual(summary["state"], "collected")
        self.assertEqual(len(collected), 1)
        self.assertEqual(collected[0]["views"], 305)
        self.assertEqual(collected[0]["engagement"], 4)
        self.assertEqual(collected[0]["source"], "official_youtube_data_api_v3")
        self.assertIsNone(collected[0]["watch_retention"])

    def test_youtube_collects_detail_breakdowns_and_retention_curve(self) -> None:
        secrets = self.root / ".runtime" / "secrets"
        secrets.mkdir(parents=True)
        (secrets / "youtube-token.json").write_text(
            json.dumps(
                {
                    "access_token": "dummy-access",
                    "refresh_token": "dummy-refresh",
                    "scope": " ".join(sorted(collector.YOUTUBE_REQUIRED_METRIC_SCOPES)),
                }
            ),
            encoding="utf-8",
        )

        base_document = {
            "columnHeaders": [
                {"name": name}
                for name in (
                    "video",
                    "views",
                    "likes",
                    "comments",
                    "shares",
                    "estimatedMinutesWatched",
                    "averageViewDuration",
                    "averageViewPercentage",
                )
            ],
            "rows": [["video-1", 100, 4, 2, 3, 12, 70, 70]],
        }
        optional_document = {
            "columnHeaders": [{"name": name} for name in ("video", "subscribersGained", "subscribersLost", "engagedViews")],
            "rows": [["video-1", 2, 1, 88]],
        }
        country_document = {
            "columnHeaders": [
                {"name": name}
                for name in ("country", "views", "estimatedMinutesWatched", "averageViewDuration", "averageViewPercentage")
            ],
            "rows": [["KR", 60, 7, 11, 68], ["JP", 30, 4, 9, 72]],
        }
        retention_document = {
            "columnHeaders": [
                {"name": name}
                for name in ("elapsedVideoTimeRatio", "audienceWatchRatio", "relativeRetentionPerformance")
            ],
            "rows": [[0.0, 1.0, 1.0], [1.0, 0.65, 0.8]],
        }
        dimensions_seen: list[str] = []

        def fake_report(*args: object, **kwargs: object) -> tuple[dict[str, object], str]:
            token = str(args[3])
            metrics = str(args[7])
            dimension = str(kwargs.get("dimensions") or "video")
            dimensions_seen.append(dimension)
            if metrics == collector.YOUTUBE_FULL_METRICS:
                return base_document, token
            if metrics == collector.YOUTUBE_OPTIONAL_VIDEO_METRICS:
                return optional_document, token
            if dimension == "country":
                return country_document, token
            if dimension == "elapsedVideoTimeRatio":
                return retention_document, token
            return {"columnHeaders": [], "rows": []}, token

        summary: dict[str, object] = {}
        with mock.patch.object(collector, "youtube_report_with_refresh", side_effect=fake_report):
            collected = collector.collect_youtube(
                self.root,
                [post("published")],
                datetime.now(collector.KST),
                summary,
            )

        self.assertEqual(summary["state"], "collected")
        self.assertEqual(len(collected), 1)
        metric = collected[0]
        self.assertEqual(metric["average_view_duration_sec"], 70)
        self.assertEqual(metric["average_view_percentage"], 70)
        self.assertEqual(metric["estimated_minutes_watched"], 12)
        self.assertEqual(metric["subscribers_gained"], 2)
        self.assertEqual(metric["subscribers_lost"], 1)
        self.assertEqual(metric["engaged_views"], 88)
        self.assertEqual(metric["top_countries"][0]["country"], "KR")
        self.assertEqual(metric["top_countries"][0]["average_view_duration_sec"], 11)
        self.assertEqual(metric["youtube_analytics_breakdown_status"]["country"]["status"], "populated")
        self.assertEqual(metric["youtube_analytics_retention_curve"][-1]["audience_watch_ratio"], 0.65)
        self.assertIsNone(metric["completion_rate"])
        self.assertEqual(metric["completion_rate_status"], "not_exposed_by_youtube_analytics_api_v2")
        self.assertIn("country", dimensions_seen)
        self.assertIn("elapsedVideoTimeRatio", dimensions_seen)

    def test_apply_writes_only_aggregate_vercel_snapshot(self) -> None:
        secrets = self.root / ".runtime" / "secrets"
        secrets.mkdir(parents=True)
        (secrets / "vercel.env").write_text(
            "VERCEL_TOKEN=dummy-token\nVERCEL_PROJECT_ID=dummy-project\n",
            encoding="utf-8",
        )
        argv = [
            "idol_collect_platform_metrics.py",
            "--root",
            str(self.root),
            "--platform",
            "vercel",
            "--apply",
        ]
        with (
            mock.patch.object(sys, "argv", argv),
            mock.patch.object(collector, "SOCIAL_VALIDATOR", str(SCRIPTS / "validate_social_analytics.rb")),
            mock.patch.object(collector, "TRAFFIC_VALIDATOR", str(SCRIPTS / "validate_signal_deck_traffic.py")),
            mock.patch.object(collector, "http_json", return_value={"data": {"value": 12}}),
        ):
            summary, status = collector.run(collector.parse_args())
        self.assertEqual(status, 0)
        self.assertEqual(summary["signal_deck_rows_written"], 1)
        rows = (self.root / "analytics" / "records" / "signal-deck-traffic.jsonl").read_text(encoding="utf-8").splitlines()
        self.assertEqual(len(rows), 1)
        saved = json.loads(rows[0])
        self.assertEqual(saved["count"], 12)
        self.assertNotIn("project_id", saved)
        self.assertNotIn("token", json.dumps(saved))


if __name__ == "__main__":
    unittest.main()
