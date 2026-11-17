#!/usr/bin/env python3
"""Regression checks for the TikTok/Instagram short-form research lane."""

from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


class IdolShortFormTrendReportContractTest(unittest.TestCase):
    def read(self, relative: str) -> str:
        return (ROOT / relative).read_text(encoding="utf-8")

    def test_weekly_report_is_separate_public_observation_lane(self) -> None:
        contract = self.read("automation/weekly-short-form-platform-trend-html-report.md")
        self.assertIn("separate from the weekly\nidol activity report", contract)
        self.assertIn("Do not use logged-in TikTok/Instagram sessions", contract)
        self.assertIn("personalized feed", contract)
        self.assertIn("`yt-dlp`", contract)
        self.assertIn("cross_platform_repeated", contract)
        self.assertIn("trend phase", contract)

    def test_weekly_template_preserves_platform_difference_and_lifecycle(self) -> None:
        template = self.read("source-materials/short-form-trend-reports/weekly/TEMPLATE.html")
        for heading in (
            "TikTok 고유 신호",
            "Instagram Reels 고유 신호",
            "교차 플랫폼 공통점과 차이",
            "트렌드 생애주기 매트릭스",
            "아이돌 활동 보고서 교차 검증",
            "격주 트렌드 펄스 승격 후보",
        ):
            self.assertIn(heading, template)
        self.assertIn("official_platform_declared", template)
        self.assertIn("saturated", template)
        self.assertIn("복제·포화·오판 가드", template)

    def test_biweekly_pulse_and_pre00_read_the_separate_latest_pointer(self) -> None:
        pointer = "source-materials/short-form-trend-reports/weekly/latest.md"
        for relative in (
            "automation/biweekly-trend-pulse-refresh.md",
            "automation/pre-00-research-radar.md",
            "wiki/pre-00-song-system.md",
            "skills/idol-research-radar/SKILL.md",
            "skills/idol-front-planning-director/SKILL.md",
            "cf/skills/idol-cf-code/SKILL.md",
        ):
            self.assertIn(pointer, self.read(relative), relative)

    def test_front_planning_does_not_create_a_short_form_quota(self) -> None:
        skill = self.read("skills/idol-front-planning-director/SKILL.md")
        self.assertIn(
            "No short-form extraction, per-Major hook quota, or derivative field",
            skill,
        )
        contract = self.read("automation/pre-00-research-radar.md")
        self.assertIn(
            "source-materials/short-form-trend-reports/weekly/latest.md",
            contract,
        )

    def test_monthly_summary_is_archive_not_active_route_truth(self) -> None:
        contract = self.read("automation/monthly-short-form-platform-trend-summary.md")
        self.assertIn("archive/comparison surface", contract)
        self.assertIn("cannot override the active biweekly trend pulse", contract)
        self.assertTrue(
            (ROOT / "source-materials/short-form-trend-reports/monthly/TEMPLATE.html").is_file()
        )


if __name__ == "__main__":
    unittest.main()
