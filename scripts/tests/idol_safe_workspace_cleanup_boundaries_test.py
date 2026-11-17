#!/usr/bin/env python3
"""Synthetic boundary tests for idol_safe_workspace_cleanup helpers.

Uses temporary Git repos and dummy paths only. Does not clean a workspace.
Callers are the three patched helpers with constructed targets/paths.
"""

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

_REPO_ROOT = Path(__file__).resolve().parents[2]
_SCRIPTS = _REPO_ROOT / "scripts"
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))
if str(_SCRIPTS) not in sys.path:
    sys.path.insert(0, str(_SCRIPTS))

import idol_safe_workspace_cleanup as cleanup  # noqa: E402


def _git(repo: Path, *args: str) -> None:
    import subprocess

    subprocess.run(
        ["git", "-c", "commit.gpgsign=false", *args],
        cwd=repo,
        check=True,
        capture_output=True,
        text=True,
    )


def _init_repo(repo: Path) -> None:
    _git(repo, "init")
    _git(repo, "config", "user.email", "idol-test@example.com")
    _git(repo, "config", "user.name", "IDOL Test")


class TemporaryRepoTest(unittest.TestCase):
    def new_root(self):
        temporary = tempfile.TemporaryDirectory(prefix="idol-cleanup-boundary-", dir="/private/tmp")
        self.addCleanup(temporary.cleanup)
        return Path(temporary.name)


class VersionDiagnosticTests(TemporaryRepoTest):
    def test_numeric_vn_diagnostic_never_promises_current_or_canonical(self) -> None:
        root = self.new_root()
        v1 = root / "item_v1.json"
        v2 = root / "item_v2.json"
        v3 = root / "item_v3.json"
        for path in (v1, v2, v3):
            path.write_text("{}", encoding="utf-8")

        groups = {("item", ".json"): [(1, v1), (2, v2), (3, v3)]}
        with patch.object(cleanup, "collect_version_groups", return_value=groups):
            with patch.object(cleanup, "path_size", return_value=1):
                rows = cleanup.collect_older_version_files(root)

        names = {row.path.name for row in rows}
        self.assertEqual(names, {"item_v1.json", "item_v2.json"})
        for row in rows:
            note = row.note
            lowered = note.lower()
            self.assertNotIn("latest", lowered)
            self.assertNotIn("current", lowered)
            self.assertIn("lower-numbered sibling", lowered)
            self.assertIn("highest observed numeric version v3", lowered)
            self.assertIn("canonical pointer not evaluated", lowered)


class DuplicateHashExclusionTests(TemporaryRepoTest):
    def test_secret_and_nested_repo_path_excluded_before_hashing(self) -> None:
        root = self.new_root()
        keep = root / "keep.bin"
        keep.write_bytes(b"keep-ok-")
        (root / ".env").write_text("SECRET=1\n", encoding="utf-8")
        (root / "id.json").write_text("{}", encoding="utf-8")
        (root / "walletBackup.json").write_bytes(b"dummy-only")
        (root / "state.sqlite-wal").write_bytes(b"dummy-only")
        (root / "material.pem").write_text("NOT_A_KEY\n", encoding="utf-8")

        nested = root / "vendor_tool"
        nested.mkdir()
        (nested / ".git").mkdir()
        (nested / "dup.bin").write_bytes(b"nested-")

        private = root / "private"
        private.mkdir()
        (private / "copy.bin").write_bytes(b"private")

        runtime = root / ".runtime"
        runtime.mkdir()
        (runtime / "state.bin").write_bytes(b"runtime")

        alias = root / "alias.bin"
        alias.symlink_to(keep)

        found = {cleanup.rel(path, root) for path in cleanup.iter_duplicate_scan_files(root, min_size=1)}
        self.assertIn("keep.bin", found)
        self.assertNotIn(".env", found)
        self.assertNotIn("id.json", found)
        self.assertNotIn("walletBackup.json", found)
        self.assertNotIn("state.sqlite-wal", found)
        self.assertNotIn("material.pem", found)
        self.assertNotIn("vendor_tool/dup.bin", found)
        self.assertNotIn("private/copy.bin", found)
        self.assertNotIn(".runtime/state.bin", found)
        self.assertNotIn("alias.bin", found)


class DeleteTargetGitGuardTests(TemporaryRepoTest):
    def test_tracked_ds_store_preserved(self) -> None:
        repo = self.new_root()
        _init_repo(repo)
        ds_store = repo / ".DS_Store"
        ds_store.write_text("finder", encoding="utf-8")
        _git(repo, "add", "-f", "--", ".DS_Store")
        _git(repo, "commit", "-m", "track ds_store")

        deleted, _reclaimed, skipped = cleanup.delete_targets(
            [cleanup.CleanupTarget(ds_store, "file", "macos junk")],
            repo,
        )
        self.assertEqual(deleted, 0)
        self.assertTrue(ds_store.exists())
        self.assertTrue(any("git-tracked" in item for item in skipped))

    def test_tracked_descendant_prevents_cache_dir_removal(self) -> None:
        repo = self.new_root()
        _init_repo(repo)
        cache = repo / "__pycache__"
        cache.mkdir()
        tracked = cache / "kept.py"
        tracked.write_text("x = 1\n", encoding="utf-8")
        _git(repo, "add", "-f", "--", "__pycache__/kept.py")
        _git(repo, "commit", "-m", "track cache descendant")

        deleted, _reclaimed, skipped = cleanup.delete_targets(
            [cleanup.CleanupTarget(cache, "dir", "cache directory: __pycache__")],
            repo,
        )
        self.assertEqual(deleted, 0)
        self.assertTrue(cache.exists())
        self.assertTrue(tracked.exists())
        self.assertTrue(any("git-tracked" in item for item in skipped))

    def test_ignored_cache_dir_remains_eligible(self) -> None:
        repo = self.new_root()
        _init_repo(repo)
        (repo / ".gitignore").write_text("__pycache__/\n", encoding="utf-8")
        _git(repo, "add", "--", ".gitignore")
        _git(repo, "commit", "-m", "ignore cache")
        cache = repo / "__pycache__"
        cache.mkdir()
        (cache / "mod.cpython-311.pyc").write_bytes(b"cache")

        deleted, _reclaimed, skipped = cleanup.delete_targets(
            [cleanup.CleanupTarget(cache, "dir", "cache directory: __pycache__")],
            repo,
        )
        self.assertEqual(deleted, 1)
        self.assertFalse(cache.exists())
        self.assertFalse(any("git-tracked" in item for item in skipped))
        self.assertFalse(any("git check failed" in item for item in skipped))

    def test_literal_brackets_in_tracked_cache_path_are_protected(self) -> None:
        repo = self.new_root()
        _init_repo(repo)
        cache = repo / "[id]" / "__pycache__"
        cache.mkdir(parents=True)
        (cache / "module.pyc").write_bytes(b"tracked")
        _git(repo, "add", "-f", "--", "[id]/__pycache__/module.pyc")
        deleted, _, skipped = cleanup.delete_targets([cleanup.CleanupTarget(cache, "dir", "cache")], repo)
        self.assertEqual(deleted, 0)
        self.assertTrue(cache.exists())
        self.assertTrue(any("git-tracked" in item for item in skipped))

    def test_nested_repository_cache_is_not_parent_cleanup(self) -> None:
        repo = self.new_root()
        _init_repo(repo)
        child = repo / "nested"
        (child / ".git").mkdir(parents=True)
        cache = child / "__pycache__"
        cache.mkdir()
        (cache / "module.pyc").write_bytes(b"child-cache")
        deleted, _, skipped = cleanup.delete_targets([cleanup.CleanupTarget(cache, "dir", "cache")], repo)
        self.assertEqual(deleted, 0)
        self.assertTrue(cache.exists())
        self.assertTrue(any("nested repository" in item for item in skipped))

    def test_alternate_git_index_cannot_hide_tracked_file(self) -> None:
        repo = self.new_root()
        _init_repo(repo)
        target = repo / ".DS_Store"
        target.write_bytes(b"tracked")
        _git(repo, "add", "-f", "--", ".DS_Store")
        with patch.dict(cleanup.os.environ, {"GIT_INDEX_FILE": str(repo / "alternate-index")}):
            deleted, _, skipped = cleanup.delete_targets([cleanup.CleanupTarget(target, "file", "cache")], repo)
        self.assertEqual(deleted, 0)
        self.assertTrue(target.exists())
        self.assertTrue(any("context overridden" in item for item in skipped))

    def test_git_check_failure_fail_closed(self) -> None:
        root = self.new_root()
        ds_store = root / ".DS_Store"
        ds_store.write_text("finder", encoding="utf-8")

        deleted, _reclaimed, skipped = cleanup.delete_targets(
            [cleanup.CleanupTarget(ds_store, "file", "macos junk")],
            root,
        )
        self.assertEqual(deleted, 0)
        self.assertTrue(ds_store.exists())
        self.assertTrue(any("git check failed" in item for item in skipped))


if __name__ == "__main__":
    unittest.main()
