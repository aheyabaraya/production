#!/usr/bin/env python3
"""No-network tests for the local TikTok Studio ZIP-export importer."""

from __future__ import annotations

import csv
import io
import json
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path


SCRIPTS = Path(__file__).resolve().parents[1]
ROOT = SCRIPTS.parent
sys.path.insert(0, str(SCRIPTS))

import idol_import_tiktok_studio_exports as importer  # noqa: E402
import validate_tiktok_studio_exports as validator  # noqa: E402


def write_zip(path: Path, report_name: str, headers: list[str], rows: list[list[str]], *, second: int = 0) -> None:
    stream = io.StringIO(newline="")
    writer = csv.writer(stream)
    writer.writerow(headers)
    writer.writerows(rows)
    info = zipfile.ZipInfo(report_name)
    info.date_time = (2026, 8, 2, 3, 52, second)
    with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        archive.writestr(info, stream.getvalue().encode("utf-8"))


def published_post(video_id: str) -> dict[str, object]:
    return {
        "post_id": "CONTENT_001-TT-20260731-001",
        "content_id": "CONTENT_001",
        "platform": "tiktok",
        "template_type": "clip",
        "message": "One quiet click.",
        "asset_or_clip": "exports/one.mp4",
        "caption": "One quiet click.",
        "hashtags": ["#AI", "#AIIdol", "#Kpop", "#VirtualIdol", "#Loom"],
        "scheduled_at": "2026-07-31T22:10:00+09:00",
        "status": "published",
        "analysis_scope": "date_based",
        "platform_post_id": video_id,
        "published_url": f"https://www.tiktok.com/@loom_idol_m/video/{video_id}",
        "published_at": "2026-07-31T22:20:00+09:00",
    }


class TikTokStudioImportTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        records = self.root / "analytics" / "records"
        records.mkdir(parents=True)
        self.video_id = "7668688515911208212"
        (records / "platform-posts.jsonl").write_text(
            json.dumps(published_post(self.video_id)) + "\n", encoding="utf-8"
        )
        (records / "platform-metrics.jsonl").write_text("", encoding="utf-8")
        self.exports = self.root / "exports"
        self.exports.mkdir()

    def tearDown(self) -> None:
        self.temp.cleanup()

    def export_inputs(self) -> list[str]:
        overview_headers = ["Date", "Video Views", "Profile Views", "Likes", "Comments", "Shares"]
        viewers_headers = ["Date", "Total Viewers", "New Viewers", "Returning Viewers"]
        content_headers = [
            "Time", "Video title", "Video link", "Post time", "Total likes", "Total comments", "Total shares", "Total views"
        ]
        overview_1 = self.exports / "Overview_a.zip"
        overview_2 = self.exports / "Overview_b.zip"
        viewers_1 = self.exports / "Viewers_a.zip"
        viewers_2 = self.exports / "Viewers_b.zip"
        content_1 = self.exports / "Content_a.zip"
        content_2 = self.exports / "Content_b.zip"
        write_zip(overview_1, "Overview.csv", overview_headers, [["July 30", "953", "7", "19", "0", "0"], ["July 31", "554", "2", "7", "0", "0"]])
        write_zip(overview_2, "Overview.csv", overview_headers, [["July 31", "554", "2", "7", "0", "0"]], second=2)
        write_zip(viewers_1, "Viewers.csv", viewers_headers, [["July 31", "808", "618", "190"], ["August 1", "undefined", "0", "0"]])
        write_zip(viewers_2, "Viewers.csv", viewers_headers, [["July 31", "808", "618", "190"]], second=2)
        write_zip(
            content_1,
            "Content.csv",
            content_headers,
            [
                ["August 2", "One quiet click", f"https://www.tiktok.com/@loom_idol_m/video/{self.video_id}", "July 31", "5", "0", "0", "397"],
                ["August 2", "Unmapped video", "https://www.tiktok.com/@loom_idol_m/video/7668260819439848725", "July 30", "19", "0", "0", "906"],
            ],
        )
        write_zip(
            content_2,
            "Content.csv",
            content_headers,
            [["August 2", "One quiet click", f"https://www.tiktok.com/@loom_idol_m/video/{self.video_id}", "July 31", "5", "0", "0", "397"]],
            second=2,
        )
        return [str(path) for path in (overview_1, overview_2, viewers_1, viewers_2, content_1, content_2)]

    def args(self, *, apply: bool) -> object:
        values = ["--root", str(self.root)]
        for path in self.export_inputs():
            values.extend(["--input", path])
        if apply:
            values.append("--apply")
        else:
            values.append("--dry-run")
        return importer.parse_args(values)

    def test_dry_run_validates_without_creating_ledgers(self) -> None:
        before = (self.root / "analytics" / "records" / "platform-metrics.jsonl").read_bytes()
        summary, status = importer.run(self.args(apply=False))
        self.assertEqual(status, 0)
        self.assertEqual(summary["status"], "ready_for_apply")
        self.assertEqual(summary["daily_rows_to_append"], 3)
        self.assertEqual(summary["video_snapshots_to_append"], 2)
        self.assertEqual(summary["duplicate_daily_rows_collapsed"], 2)
        self.assertEqual(summary["duplicate_video_rows_collapsed"], 1)
        self.assertEqual(summary["exact_post_id_matches"], 1)
        self.assertFalse((self.root / "analytics" / "records" / "tiktok-studio-imports.jsonl").exists())
        self.assertEqual((self.root / "analytics" / "records" / "platform-metrics.jsonl").read_bytes(), before)

    def test_apply_records_unmapped_and_exactly_mapped_video_separately(self) -> None:
        summary, status = importer.run(self.args(apply=True))
        self.assertEqual(status, 0)
        self.assertEqual(summary["status"], "imported")
        records = self.root / "analytics" / "records"
        imports = [json.loads(line) for line in (records / "tiktok-studio-imports.jsonl").read_text().splitlines()]
        daily = [json.loads(line) for line in (records / "tiktok-studio-account-daily.jsonl").read_text().splitlines()]
        videos = [json.loads(line) for line in (records / "tiktok-studio-video-snapshots.jsonl").read_text().splitlines()]
        metrics = [json.loads(line) for line in (records / "platform-metrics.jsonl").read_text().splitlines()]
        self.assertEqual(len(imports), 1)
        self.assertEqual(len(daily), 3)
        self.assertEqual(len(videos), 2)
        self.assertEqual(len(metrics), 1)
        august_first = next(row for row in daily if row["observed_date"] == "2026-08-01")
        self.assertIsNone(august_first["viewers"]["total_viewers"])
        mapped = next(row for row in videos if row["platform_video_id"] == self.video_id)
        unmatched = next(row for row in videos if row["platform_video_id"] != self.video_id)
        self.assertEqual(mapped["mapping"]["status"], "exact_platform_post_id")
        self.assertEqual(unmatched["mapping"]["status"], "unmatched")
        self.assertEqual(metrics[0]["post_id"], published_post(self.video_id)["post_id"])
        self.assertNotIn("measurement_window", metrics[0])
        self.assertIsNone(metrics[0]["completion_rate"])
        self.assertEqual(metrics[0]["tiktok_studio_detail_status"]["country"]["status"], "not_in_export")

        validation, validation_status = validator.run(validator.parse_args(["--root", str(self.root)]))
        self.assertEqual(validation_status, 0, validation)
        social = subprocess.run(
            ["ruby", str(ROOT / "scripts" / "validate_social_analytics.rb"), str(records / "platform-posts.jsonl"), str(records / "platform-metrics.jsonl")],
            cwd=ROOT,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(social.returncode, 0, social.stderr)

    def test_reapplying_the_same_export_is_idempotent(self) -> None:
        first, first_status = importer.run(self.args(apply=True))
        second, second_status = importer.run(self.args(apply=True))
        self.assertEqual(first_status, 0)
        self.assertEqual(second_status, 0)
        self.assertEqual(second["status"], "already_imported")
        records = self.root / "analytics" / "records"
        self.assertEqual(len((records / "tiktok-studio-imports.jsonl").read_text().splitlines()), 1)
        self.assertEqual(len((records / "platform-metrics.jsonl").read_text().splitlines()), 1)

    def test_conflicting_daily_overlap_blocks_before_write(self) -> None:
        headers = ["Date", "Video Views", "Profile Views", "Likes", "Comments", "Shares"]
        first = self.exports / "Overview_first.zip"
        second = self.exports / "Overview_second.zip"
        write_zip(first, "Overview.csv", headers, [["July 31", "10", "1", "1", "0", "0"]])
        write_zip(second, "Overview.csv", headers, [["July 31", "11", "1", "1", "0", "0"]], second=2)
        args = importer.parse_args(["--root", str(self.root), "--input", str(first), "--input", str(second), "--apply"])
        with self.assertRaisesRegex(importer.ImportError, "conflicting_overview_date_2026-07-31"):
            importer.run(args)
        self.assertFalse((self.root / "analytics" / "records" / "tiktok-studio-imports.jsonl").exists())


if __name__ == "__main__":
    unittest.main()
