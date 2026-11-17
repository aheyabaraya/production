#!/usr/bin/env python3
"""No-value regression tests for the platform credential status surface."""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))

from lib.idol_platform_credentials import all_status, status_for_platform


class PlatformAuthStatusTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.secrets = self.root / ".runtime" / "secrets"
        self.secrets.mkdir(parents=True)

    def tearDown(self) -> None:
        self.temp.cleanup()

    def test_all_platforms_report_ready_without_returning_values(self) -> None:
        (self.secrets / "x.env").write_text(
            "\n".join(
                [
                    "X_OAUTH2_CLIENT_ID=dummy-client-id",
                    "X_OAUTH2_CLIENT_SECRET=dummy-client-secret",
                    "X_OAUTH2_ACCESS_TOKEN=dummy-access-token",
                    "X_OAUTH2_REFRESH_TOKEN=dummy-refresh-token",
                    "X_OAUTH2_REDIRECT_URI=http://127.0.0.1:8080/callback",
                    "X_OAUTH2_SCOPES=tweet.read tweet.write media.write users.read offline.access",
                ]
            )
            + "\n"
        )
        (self.secrets / "tiktok.env").write_text(
            "\n".join(
                [
                    "TIKTOK_CLIENT_KEY=dummy-key",
                    "TIKTOK_CLIENT_SECRET=dummy-secret",
                    "TIKTOK_REDIRECT_URI=http://127.0.0.1:8766/oauth2callback",
                    "TIKTOK_SCOPES=video.upload,video.list",
                ]
            )
            + "\n"
        )
        (self.secrets / "tiktok-token.json").write_text(
            json.dumps(
                {
                    "access_token": "dummy-access",
                    "refresh_token": "dummy-refresh",
                    "scope": "video.upload,video.list",
                }
            )
        )
        (self.secrets / "youtube-client-secret.json").write_text(
            json.dumps({"installed": {"client_id": "dummy-id", "client_secret": "dummy-secret"}})
        )
        (self.secrets / "youtube-token.json").write_text(
            json.dumps(
                {
                    "access_token": "dummy-access",
                    "refresh_token": "dummy-refresh",
                    "scope": "https://www.googleapis.com/auth/youtube.upload https://www.googleapis.com/auth/youtube.readonly https://www.googleapis.com/auth/yt-analytics.readonly",
                }
            )
        )

        document = all_status(self.root)
        serialized = json.dumps(document, ensure_ascii=False)
        self.assertNotIn("dummy-access-token", serialized)
        self.assertNotIn("dummy-client-secret", serialized)
        self.assertTrue(document["platforms"]["x"]["ready_for_runtime_post"])
        self.assertTrue(document["platforms"]["x"]["ready_for_runtime_metrics"])
        self.assertTrue(document["platforms"]["tiktok"]["ready_for_runtime_upload"])
        self.assertTrue(document["platforms"]["tiktok"]["ready_for_reauth"])
        self.assertTrue(document["platforms"]["tiktok"]["scopes"]["granted_video.upload"])
        self.assertTrue(document["platforms"]["tiktok"]["ready_for_runtime_metrics"])
        self.assertTrue(document["platforms"]["youtube"]["ready_for_runtime_upload"])
        self.assertTrue(document["platforms"]["youtube"]["ready_for_runtime_metrics"])
        self.assertFalse(document["secret_values_printed"])

    def test_missing_or_invalid_files_fail_closed(self) -> None:
        x_status = status_for_platform("x", self.root)
        youtube_status = status_for_platform("youtube", self.root)
        self.assertFalse(x_status["ready_for_runtime_post"])
        self.assertFalse(x_status["ready_for_runtime_metrics"])
        self.assertFalse(x_status["ready_for_reauth"])
        self.assertFalse(youtube_status["ready_for_runtime_upload"])
        self.assertFalse(youtube_status["client_file_valid"])


if __name__ == "__main__":
    unittest.main()
