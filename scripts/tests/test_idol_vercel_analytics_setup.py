#!/usr/bin/env python3
"""No-value tests for the localhost-only Vercel analytics setup helper."""

from __future__ import annotations

import json
import stat
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))

import idol_vercel_analytics_setup as setup  # noqa: E402


class VercelAnalyticsSetupTest(unittest.TestCase):
    def test_setup_stores_secret_file_at_0600_without_returning_values(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            env = Path(temporary) / ".runtime" / "secrets" / "vercel.env"
            setup.replace_env_values(
                env,
                {
                    "VERCEL_TOKEN": "dummy-token",
                    "VERCEL_PROJECT_ID": "dummy-project",
                    "VERCEL_TEAM_ID": "dummy-team",
                    "VERCEL_ANALYTICS_FILTER": "environment eq 'production'",
                },
            )
            status = setup.readiness(env)
            self.assertEqual(stat.S_IMODE(env.stat().st_mode), 0o600)
            self.assertEqual(status["status"], "configured")
            rendered = json.dumps(status)
            self.assertNotIn("dummy-token", rendered)
            self.assertNotIn("dummy-project", rendered)
            self.assertFalse(status["secret_values_printed"])


if __name__ == "__main__":
    unittest.main()
