#!/usr/bin/env python3
"""No-network tests for the TikTok OAuth reauthorization helper."""

from __future__ import annotations

import json
import stat
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))

import idol_tiktok_oauth_reauth as reauth  # noqa: E402
from lib.idol_platform_credentials import load_env  # noqa: E402


class TikTokOAuthReauthTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.env = self.root / ".runtime/secrets/tiktok.env"
        self.token = self.root / ".runtime/secrets/tiktok-token.json"

    def tearDown(self) -> None:
        self.temp.cleanup()

    def test_pkce_uses_tiktok_desktop_hex_sha256_shape(self) -> None:
        verifier, challenge = reauth.pkce_pair()
        self.assertGreaterEqual(len(verifier), 43)
        self.assertLessEqual(len(verifier), 128)
        self.assertEqual(len(challenge), 64)
        int(challenge, 16)

    def test_callback_server_allows_immediate_restart_after_interrupt(self) -> None:
        self.assertTrue(reauth.ReusableHTTPServer.allow_reuse_address)

    def test_secret_files_are_written_mode_0600(self) -> None:
        reauth.replace_env_values(
            self.env,
            {
                "TIKTOK_CLIENT_KEY": "dummy-client-key",
                "TIKTOK_CLIENT_SECRET": "dummy-client-secret",
                "TIKTOK_REDIRECT_URI": "http://127.0.0.1:8766/oauth2callback",
                "TIKTOK_SCOPES": "video.upload",
            },
        )
        reauth.save_token(
            self.token,
            {
                "access_token": "dummy-access",
                "refresh_token": "dummy-refresh",
                "scope": "video.upload",
                "expires_in": 86400,
            },
        )
        self.assertEqual(stat.S_IMODE(self.env.stat().st_mode), 0o600)
        self.assertEqual(stat.S_IMODE(self.token.stat().st_mode), 0o600)
        self.assertEqual(load_env(self.env)["TIKTOK_SCOPES"], "video.upload")
        saved = json.loads(self.token.read_text(encoding="utf-8"))
        self.assertIn("expires_at", saved)

    def test_refresh_rotates_and_preserves_token_bundle_without_browser(self) -> None:
        reauth.replace_env_values(
            self.env,
            {
                "TIKTOK_CLIENT_KEY": "dummy-client-key",
                "TIKTOK_CLIENT_SECRET": "dummy-client-secret",
            },
        )
        reauth.save_token(
            self.token,
            {
                "access_token": "old-access",
                "refresh_token": "old-refresh",
                "scope": "video.upload",
            },
        )
        argv = [
            "idol_tiktok_oauth_reauth.py",
            "--env",
            str(self.env),
            "--token",
            str(self.token),
            "--refresh-only",
        ]
        with mock.patch.object(
            reauth,
            "refresh_access_token",
            return_value={
                "access_token": "new-access",
                "refresh_token": "new-refresh",
                "scope": "video.upload",
                "expires_in": 86400,
            },
        ), mock.patch.object(sys, "argv", argv):
            self.assertEqual(reauth.main(), 0)
        saved = json.loads(self.token.read_text(encoding="utf-8"))
        self.assertEqual(saved["access_token"], "new-access")
        self.assertEqual(saved["refresh_token"], "new-refresh")
        self.assertEqual(load_env(self.env)["TIKTOK_SCOPES"], "video.upload")

    def test_exchange_requires_every_requested_scope(self) -> None:
        with mock.patch.object(
            reauth,
            "token_request",
            return_value={
                "access_token": "dummy-access",
                "refresh_token": "dummy-refresh",
                "scope": "video.upload",
            },
        ):
            with self.assertRaisesRegex(reauth.ReauthError, "video.list"):
                reauth.exchange_code(
                    client_key="dummy-key",
                    client_secret="dummy-secret",
                    code="dummy-code",
                    redirect_uri="http://127.0.0.1:8766/oauth2callback",
                    verifier="v" * 43,
                    required_scopes={"video.upload", "video.list"},
                )


if __name__ == "__main__":
    unittest.main()
