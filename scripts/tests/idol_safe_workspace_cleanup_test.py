#!/usr/bin/env python3
"""Tests for conservative IDOL workspace lifecycle diagnostics."""

from __future__ import annotations

import hashlib
import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import yaml


REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT_PATH = REPO_ROOT / "scripts" / "idol_safe_workspace_cleanup.py"
POLICY_PATH = REPO_ROOT / "automation" / "artifact-lifecycle-policy.yaml"

SPEC = importlib.util.spec_from_file_location("idol_safe_workspace_cleanup", SCRIPT_PATH)
assert SPEC and SPEC.loader
CLEANUP = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = CLEANUP
SPEC.loader.exec_module(CLEANUP)


class WorkspaceCleanupLifecycleTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.policy = CLEANUP.load_lifecycle_policy(POLICY_PATH)

    def make_root(self) -> tuple[tempfile.TemporaryDirectory[str], Path]:
        temp_dir = tempfile.TemporaryDirectory()
        return temp_dir, Path(temp_dir.name)

    def archive_dir(self, root: Path, content: str = "CONTENT_A") -> Path:
        archive = root / "runs" / "album-a" / "title-a" / content / "archive"
        archive.mkdir(parents=True)
        return archive

    def archive_entry(
        self,
        root: Path,
        path: Path,
        *,
        archive_id: str,
        family: str = "storyboard",
        reason: str = "reviewed_learning",
    ) -> dict[str, object]:
        payload = path.read_bytes()
        return {
            "archive_id": archive_id,
            "artifact_family": family,
            "path": path.relative_to(root).as_posix(),
            "sha256": hashlib.sha256(payload).hexdigest(),
            "size_bytes": len(payload),
            "retention_reason": reason,
            "canonical_path": None,
            "protection_status": "protected",
            "review_after": None,
            "source_refs": [],
            "notes": "test fixture",
        }

    def write_manifest(self, root: Path, archive: Path, entries: list[dict[str, object]]) -> Path:
        manifest = {
            "schema_version": "idol-artifact-archive-manifest.v2",
            "owner_root": archive.parent.relative_to(root).as_posix(),
            "generated_at": "2026-07-11T00:00:00Z",
            "status": "active",
            "entries": entries,
        }
        path = archive / "manifest.yaml"
        path.write_text(yaml.safe_dump(manifest, sort_keys=False), encoding="utf-8")
        return path

    def run_cli(self, root: Path, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [
                sys.executable,
                str(SCRIPT_PATH),
                "--root",
                str(root),
                "--policy",
                str(POLICY_PATH),
                "--skip-git-temp",
                *args,
            ],
            text=True,
            capture_output=True,
            check=False,
        )

    def test_version_pileup_reports_only_active_family_over_limit(self) -> None:
        holder, root = self.make_root()
        self.addCleanup(holder.cleanup)
        active = root / "runs" / "album-a" / "title-a" / "CONTENT_A" / "research"
        inactive = root / "runs" / "album-a" / "title-a" / "CONTENT_A" / "work"
        active.mkdir(parents=True)
        inactive.mkdir(parents=True)
        for number in (1, 2, 3):
            (active / f"direction-v{number}.yaml").write_text(f"version: {number}\n", encoding="utf-8")
            (inactive / f"probe-v{number}.yaml").write_text(f"version: {number}\n", encoding="utf-8")

        pileups = CLEANUP.collect_version_pileups(root, max_active=2, policy=self.policy)

        self.assertEqual(len(pileups), 1)
        self.assertEqual(pileups[0].base, "direction")
        self.assertEqual([number for number, _path in pileups[0].versions], [1, 2, 3])

    def test_versioned_directory_family_uses_the_same_limit(self) -> None:
        holder, root = self.make_root()
        self.addCleanup(holder.cleanup)
        research = root / "runs" / "album-a" / "title-a" / "CONTENT_A" / "research"
        for number in (3, 4, 5):
            folder = research / f"stage-styling-reference-intake-v{number}"
            folder.mkdir(parents=True)
            (folder / "manifest.yaml").write_text("status: active\n", encoding="utf-8")

        pileups = CLEANUP.collect_version_pileups(root, max_active=2, policy=self.policy)

        self.assertEqual(len(pileups), 1)
        self.assertEqual(pileups[0].base, "stage-styling-reference-intake")
        self.assertEqual(pileups[0].suffix, "/")
        self.assertEqual([number for number, _path in pileups[0].versions], [3, 4, 5])

    def test_unregistered_date_first_run_is_excluded_from_active_version_pileups(self) -> None:
        holder, root = self.make_root()
        self.addCleanup(holder.cleanup)
        research = root / "runs" / "2026-07-11" / "CONTENT_A" / "research"
        research.mkdir(parents=True)
        for number in (1, 2, 3):
            (research / f"direction-v{number}.yaml").write_text(
                f"version: {number}\n",
                encoding="utf-8",
            )

        pileups = CLEANUP.collect_version_pileups(root, max_active=2, policy=self.policy)

        self.assertEqual(pileups, [])

    def test_large_durable_research_folder_requires_top_level_index(self) -> None:
        holder, root = self.make_root()
        self.addCleanup(holder.cleanup)
        reference_intake = (
            root
            / "runs"
            / "album-a"
            / "title-a"
            / "CONTENT_A"
            / "research"
            / "reference-intake"
        )
        reference_intake.mkdir(parents=True)
        for number in range(20):
            (reference_intake / f"unit-{number:02d}.yaml").write_text(
                f"unit: {number}\n",
                encoding="utf-8",
            )

        issues = CLEANUP.collect_research_folder_issues(root, self.policy)
        self.assertTrue(any(issue.code == "research_folder_index_missing" for issue in issues))

        (reference_intake / "manifest.yaml").write_text("status: active\n", encoding="utf-8")
        issues = CLEANUP.collect_research_folder_issues(root, self.policy)
        self.assertFalse(any(issue.code == "research_folder_index_missing" for issue in issues))

    def test_archive_manifest_valid(self) -> None:
        holder, root = self.make_root()
        self.addCleanup(holder.cleanup)
        archive = self.archive_dir(root)
        artifact = archive / "selected-source.bin"
        artifact.write_bytes(b"irreproducible-selected-source")
        entry = self.archive_entry(root, artifact, archive_id="ARC_SELECTED_SOURCE")
        self.write_manifest(root, archive, [entry])

        issues = CLEANUP.collect_archive_manifest_issues(root, self.policy, REPO_ROOT)

        self.assertEqual(issues, [])

    def test_archive_missing_manifest_reports_missing_and_unindexed(self) -> None:
        holder, root = self.make_root()
        self.addCleanup(holder.cleanup)
        archive = self.archive_dir(root)
        artifact = archive / "orphan.bin"
        artifact.write_bytes(b"orphan")

        codes = {issue.code for issue in CLEANUP.collect_archive_manifest_issues(root, self.policy, REPO_ROOT)}

        self.assertIn("archive_manifest_missing", codes)
        self.assertIn("archive_path_unindexed", codes)

    def test_archive_cache_named_subdirectories_cannot_hide_unindexed_files(self) -> None:
        holder, root = self.make_root()
        self.addCleanup(holder.cleanup)
        archive = self.archive_dir(root)
        artifact = archive / "build" / "hidden.bin"
        artifact.parent.mkdir()
        artifact.write_bytes(b"hidden-archive-evidence")
        self.write_manifest(root, archive, [])

        issues = CLEANUP.collect_archive_manifest_issues(root, self.policy, REPO_ROOT)

        self.assertTrue(any(
            issue.code == "archive_path_unindexed" and issue.path == artifact
            for issue in issues
        ))

    def test_archive_walk_error_is_reported_as_incomplete_scan(self) -> None:
        holder, root = self.make_root()
        self.addCleanup(holder.cleanup)
        archive = self.archive_dir(root)
        self.write_manifest(root, archive, [])
        locked = archive / "locked"

        def failing_walk(_path: Path, *, followlinks: bool, onerror: object):
            self.assertFalse(followlinks)
            self.assertTrue(callable(onerror))
            error = PermissionError("permission denied")
            error.filename = str(locked)
            onerror(error)  # type: ignore[operator]
            yield str(archive), [], ["manifest.yaml"]

        with mock.patch.object(CLEANUP.os, "walk", side_effect=failing_walk):
            issues = CLEANUP.collect_archive_manifest_issues(root, self.policy, REPO_ROOT)

        self.assertTrue(any(
            issue.code == "archive_scan_incomplete" and issue.path == locked
            for issue in issues
        ))

    def test_archive_bad_hash_and_size_are_reported(self) -> None:
        holder, root = self.make_root()
        self.addCleanup(holder.cleanup)
        archive = self.archive_dir(root)
        artifact = archive / "selected-source.bin"
        artifact.write_bytes(b"selected-source")
        entry = self.archive_entry(root, artifact, archive_id="ARC_SELECTED_SOURCE")
        entry["sha256"] = "0" * 64
        entry["size_bytes"] = int(entry["size_bytes"]) + 1
        self.write_manifest(root, archive, [entry])

        codes = {issue.code for issue in CLEANUP.collect_archive_manifest_issues(root, self.policy, REPO_ROOT)}

        self.assertIn("archive_entry_sha256_mismatch", codes)
        self.assertIn("archive_entry_size_mismatch", codes)

    def test_unreadable_indexed_archive_file_is_reported_without_crashing(self) -> None:
        holder, root = self.make_root()
        self.addCleanup(holder.cleanup)
        archive = self.archive_dir(root)
        artifact = archive / "selected-source.bin"
        artifact.write_bytes(b"selected-source")
        entry = self.archive_entry(root, artifact, archive_id="ARC_SELECTED_SOURCE")
        self.write_manifest(root, archive, [entry])

        with mock.patch.object(CLEANUP, "sha256_file", side_effect=PermissionError("permission denied")):
            issues = CLEANUP.collect_archive_manifest_issues(root, self.policy, REPO_ROOT)

        self.assertTrue(any(
            issue.code == "archive_entry_unreadable" and issue.path == artifact
            for issue in issues
        ))

    def test_archive_two_rollbacks_for_one_family_are_reported(self) -> None:
        holder, root = self.make_root()
        self.addCleanup(holder.cleanup)
        archive = self.archive_dir(root)
        canonical = archive.parent / "02A-current.yaml"
        first = archive / "storyboard-rollback-a.yaml"
        second = archive / "storyboard-rollback-b.yaml"
        canonical.write_text("current: true\n", encoding="utf-8")
        first.write_text("a: 1\n", encoding="utf-8")
        second.write_text("b: 2\n", encoding="utf-8")
        entries = [
            self.archive_entry(
                root,
                first,
                archive_id="ARC_ROLLBACK_A",
                family="storyboard",
                reason="rollback_checkpoint",
            ),
            self.archive_entry(
                root,
                second,
                archive_id="ARC_ROLLBACK_B",
                family="storyboard",
                reason="rollback_checkpoint",
            ),
        ]
        for entry in entries:
            entry["canonical_path"] = canonical.relative_to(root).as_posix()
        self.write_manifest(root, archive, entries)

        codes = {issue.code for issue in CLEANUP.collect_archive_manifest_issues(root, self.policy, REPO_ROOT)}

        self.assertIn("archive_rollback_limit_exceeded", codes)

    def test_rollback_archive_requires_current_canonical_relation(self) -> None:
        holder, root = self.make_root()
        self.addCleanup(holder.cleanup)
        archive = self.archive_dir(root)
        rollback = archive / "storyboard-rollback.yaml"
        rollback.write_text("rollback: true\n", encoding="utf-8")
        entry = self.archive_entry(
            root,
            rollback,
            archive_id="ARC_ROLLBACK",
            reason="rollback_checkpoint",
        )
        self.write_manifest(root, archive, [entry])

        codes = {
            issue.code
            for issue in CLEANUP.collect_archive_manifest_issues(root, self.policy, REPO_ROOT)
        }

        self.assertIn("archive_rollback_canonical_missing", codes)
        self.assertIn("archive_manifest_schema_invalid", codes)

    def test_rollback_archive_accepts_real_current_canonical_relation(self) -> None:
        holder, root = self.make_root()
        self.addCleanup(holder.cleanup)
        archive = self.archive_dir(root)
        canonical = archive.parent / "02A-current.yaml"
        rollback = archive / "storyboard-rollback.yaml"
        canonical.write_text("current: true\n", encoding="utf-8")
        rollback.write_text("rollback: true\n", encoding="utf-8")
        entry = self.archive_entry(
            root,
            rollback,
            archive_id="ARC_ROLLBACK",
            reason="rollback_checkpoint",
        )
        entry["canonical_path"] = canonical.relative_to(root).as_posix()
        self.write_manifest(root, archive, [entry])

        issues = CLEANUP.collect_archive_manifest_issues(root, self.policy, REPO_ROOT)

        self.assertEqual(issues, [])

    def test_exact_duplicate_scan_skips_private_and_symlink_files(self) -> None:
        holder, root = self.make_root()
        self.addCleanup(holder.cleanup)
        first = root / "runs" / "album-a" / "title-a" / "CONTENT_A" / "a.bin"
        second = root / "source-materials" / "b.bin"
        private = root / "business-marketing" / "private.bin"
        first.parent.mkdir(parents=True)
        second.parent.mkdir(parents=True)
        private.parent.mkdir(parents=True)
        payload = b"same-payload"
        first.write_bytes(payload)
        second.write_bytes(payload)
        private.write_bytes(payload)
        symlink = first.parent / "linked.bin"
        try:
            symlink.symlink_to(first)
        except OSError:
            pass

        groups = CLEANUP.collect_duplicate_groups(root, min_size=4)

        self.assertEqual(len(groups), 1)
        self.assertEqual([path.relative_to(root).as_posix() for path in groups[0].paths], [
            "runs/album-a/title-a/CONTENT_A/a.bin",
            "source-materials/b.bin",
        ])

    def test_archive_symlinks_and_path_escape_are_rejected(self) -> None:
        holder, root = self.make_root()
        self.addCleanup(holder.cleanup)
        archive = self.archive_dir(root)
        outside = archive.parent / "outside.bin"
        outside.write_bytes(b"outside")
        linked = archive / "linked.bin"
        linked.symlink_to(outside)
        escaped_entry = self.archive_entry(
            root,
            outside,
            archive_id="ARC_ESCAPE",
        )
        escaped_entry["path"] = f"{archive.relative_to(root).as_posix()}/../outside.bin"
        self.write_manifest(root, archive, [escaped_entry])

        codes = {
            issue.code
            for issue in CLEANUP.collect_archive_manifest_issues(root, self.policy, REPO_ROOT)
        }

        self.assertIn("archive_symlink_forbidden", codes)
        self.assertIn("archive_entry_path_invalid", codes)

    def test_archive_directory_symlink_is_rejected(self) -> None:
        holder, root = self.make_root()
        self.addCleanup(holder.cleanup)
        content = root / "runs" / "album-a" / "title-a" / "CONTENT_A"
        external = root / "external-archive"
        content.mkdir(parents=True)
        external.mkdir()
        (content / "archive").symlink_to(external, target_is_directory=True)

        codes = {
            issue.code
            for issue in CLEANUP.collect_archive_manifest_issues(root, self.policy, REPO_ROOT)
        }

        self.assertIn("archive_directory_symlink_forbidden", codes)

    def test_run_album_title_and_id_owner_symlinks_are_rejected(self) -> None:
        holder, root = self.make_root()
        self.addCleanup(holder.cleanup)
        runs = root / "runs"
        runs.mkdir()
        external_album = root / "external-album"
        external_title = root / "external-title"
        external_run = root / "external-run"
        external_album.mkdir()
        external_title.mkdir()
        external_run.mkdir()
        (runs / "album-link").symlink_to(external_album, target_is_directory=True)
        real_album = runs / "album-a"
        real_album.mkdir()
        (real_album / "title-link").symlink_to(external_title, target_is_directory=True)
        real_title = real_album / "title-a"
        real_title.mkdir()
        (real_title / "RUN_LINK").symlink_to(external_run, target_is_directory=True)

        issues = CLEANUP.collect_archive_manifest_issues(root, self.policy, REPO_ROOT)
        owner_symlink_paths = {
            issue.path.relative_to(root).as_posix()
            for issue in issues
            if issue.code == "archive_owner_symlink"
        }

        self.assertEqual(owner_symlink_paths, {
            "runs/album-link",
            "runs/album-a/title-link",
            "runs/album-a/title-a/RUN_LINK",
        })

    def test_runs_root_symlink_is_rejected(self) -> None:
        holder, root = self.make_root()
        self.addCleanup(holder.cleanup)
        external_runs = root / "external-runs"
        external_runs.mkdir()
        (root / "runs").symlink_to(external_runs, target_is_directory=True)

        issues = CLEANUP.collect_archive_manifest_issues(root, self.policy, REPO_ROOT)

        self.assertTrue(any(
            issue.code == "archive_owner_symlink" and issue.path == root / "runs"
            for issue in issues
        ))

    def test_misplaced_archive_is_reported_and_fully_audited(self) -> None:
        holder, root = self.make_root()
        self.addCleanup(holder.cleanup)
        archive = root / "runs" / "not-a-date" / "CONTENT_A" / "archive"
        artifact = archive / "build" / "hidden.bin"
        artifact.parent.mkdir(parents=True)
        artifact.write_bytes(b"misplaced-hidden-evidence")

        codes = {
            issue.code
            for issue in CLEANUP.collect_archive_manifest_issues(root, self.policy, REPO_ROOT)
        }

        self.assertIn("archive_owner_path_invalid", codes)
        self.assertIn("archive_manifest_missing", codes)
        self.assertIn("archive_path_unindexed", codes)

    def test_nested_archive_under_valid_run_is_misplaced(self) -> None:
        holder, root = self.make_root()
        self.addCleanup(holder.cleanup)
        archive = root / "runs" / "album-a" / "title-a" / "CONTENT_A" / "research" / "archive"
        archive.mkdir(parents=True)
        self.write_manifest(root, archive, [])

        codes = {
            issue.code
            for issue in CLEANUP.collect_archive_manifest_issues(root, self.policy, REPO_ROOT)
        }

        self.assertIn("archive_owner_path_invalid", codes)
        self.assertIn("archive_manifest_schema_invalid", codes)

    def test_archive_full_schema_rejects_invalid_status_and_extra_field(self) -> None:
        holder, root = self.make_root()
        self.addCleanup(holder.cleanup)
        archive = self.archive_dir(root)
        artifact = archive / "selected-source.bin"
        artifact.write_bytes(b"selected-source")
        entry = self.archive_entry(root, artifact, archive_id="ARC_SELECTED_SOURCE")
        manifest = self.write_manifest(root, archive, [entry])
        loaded = yaml.safe_load(manifest.read_text(encoding="utf-8"))
        loaded["status"] = "unknown"
        loaded["unexpected"] = True
        manifest.write_text(yaml.safe_dump(loaded, sort_keys=False), encoding="utf-8")

        codes = {
            issue.code
            for issue in CLEANUP.collect_archive_manifest_issues(root, self.policy, REPO_ROOT)
        }

        self.assertIn("archive_manifest_schema_invalid", codes)

    def test_archive_duplicate_id_canonical_path_and_review_date_contracts(self) -> None:
        holder, root = self.make_root()
        self.addCleanup(holder.cleanup)
        archive = self.archive_dir(root)
        first = archive / "first.bin"
        second = archive / "second.bin"
        first.write_bytes(b"first")
        second.write_bytes(b"second")
        first_entry = self.archive_entry(root, first, archive_id="ARC_DUPLICATE")
        second_entry = self.archive_entry(root, second, archive_id="ARC_DUPLICATE")
        first_entry["protection_status"] = "review_due"
        first_entry["review_after"] = None
        second_entry["canonical_path"] = "/absolute/not-allowed.bin"
        self.write_manifest(root, archive, [first_entry, second_entry])

        codes = {
            issue.code
            for issue in CLEANUP.collect_archive_manifest_issues(root, self.policy, REPO_ROOT)
        }

        self.assertIn("archive_entry_id_duplicate", codes)
        self.assertIn("archive_entry_canonical_path_invalid", codes)
        self.assertIn("archive_manifest_schema_invalid", codes)

    def test_canonical_path_cannot_cross_intermediate_symlink(self) -> None:
        holder, root = self.make_root()
        self.addCleanup(holder.cleanup)
        archive = self.archive_dir(root)
        artifact = archive / "selected-source.bin"
        artifact.write_bytes(b"selected-source")
        canonical_dir = root / "canonical"
        canonical_dir.mkdir()
        (canonical_dir / "current.bin").write_bytes(b"current")
        (root / "alias").symlink_to(canonical_dir, target_is_directory=True)
        entry = self.archive_entry(root, artifact, archive_id="ARC_SELECTED_SOURCE")
        entry["canonical_path"] = "alias/current.bin"
        self.write_manifest(root, archive, [entry])

        codes = {
            issue.code
            for issue in CLEANUP.collect_archive_manifest_issues(root, self.policy, REPO_ROOT)
        }

        self.assertIn("archive_entry_canonical_path_invalid", codes)

    def test_forbidden_root_symlink_is_an_error(self) -> None:
        holder, root = self.make_root()
        self.addCleanup(holder.cleanup)
        target = root / "artifact-target"
        target.mkdir()
        (root / "output").symlink_to(target, target_is_directory=True)

        issues = CLEANUP.collect_forbidden_root_issues(root, self.policy)

        self.assertTrue(any(
            issue.code == "forbidden_root_symlink"
            and issue.severity == "error"
            and not issue.legacy_debt
            for issue in issues
        ))

    def test_direct_candidate_globs_do_not_count_as_active_version_pileups(self) -> None:
        holder, root = self.make_root()
        self.addCleanup(holder.cleanup)
        research = root / "runs" / "album-a" / "title-a" / "CONTENT_A" / "research"
        research.mkdir(parents=True)
        for number in (1, 2, 3):
            (research / f"direction-v{number}.yaml").write_text(f"v: {number}\n", encoding="utf-8")
            (research / f"suno-prompt-packet-v{number}.md").write_text(f"draft {number}\n", encoding="utf-8")

        pileups = CLEANUP.collect_version_pileups(root, max_active=2, policy=self.policy)

        self.assertEqual([family.base for family in pileups], ["direction"])

    def test_json_dry_run_is_machine_readable_and_does_not_mutate(self) -> None:
        holder, root = self.make_root()
        self.addCleanup(holder.cleanup)
        cache = root / "scripts" / "__pycache__" / "module.pyc"
        cache.parent.mkdir(parents=True)
        cache.write_bytes(b"cache")

        result = self.run_cli(root, "--json")
        report = json.loads(result.stdout)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(report["schema_version"], "idol-safe-workspace-cleanup-report.v2")
        self.assertEqual(report["summary"]["safe_target_count"], 1)
        self.assertTrue(cache.exists())

    def test_apply_deletes_only_cache_and_keeps_production_artifact(self) -> None:
        holder, root = self.make_root()
        self.addCleanup(holder.cleanup)
        subprocess.run(["git", "init", str(root)], check=True, capture_output=True)
        cache = root / "scripts" / "__pycache__" / "module.pyc"
        production = root / "runs" / "album-a" / "title-a" / "CONTENT_A" / "generations" / "frame.png"
        cache.parent.mkdir(parents=True)
        production.parent.mkdir(parents=True)
        cache.write_bytes(b"cache")
        production.write_bytes(b"production")

        result = self.run_cli(root, "--json", "--apply")
        report = json.loads(result.stdout)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(cache.exists())
        self.assertTrue(production.exists())
        self.assertEqual(report["applied_cleanup"]["deleted_count"], 1)

    def test_apply_never_deletes_git_temporary_objects(self) -> None:
        holder, root = self.make_root()
        self.addCleanup(holder.cleanup)
        git_temp = root / ".git" / "objects" / "ab" / "tmp_obj_active"
        git_temp.parent.mkdir(parents=True)
        git_temp.write_bytes(b"git-internal")

        result = self.run_cli(root, "--json", "--apply")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(git_temp.exists())

    def test_strict_lifecycle_changes_exit_code_only_when_requested(self) -> None:
        holder, root = self.make_root()
        self.addCleanup(holder.cleanup)
        versions = root / "runs" / "album-a" / "title-a" / "CONTENT_A" / "research"
        versions.mkdir(parents=True)
        for number in (1, 2, 3):
            (versions / f"plan-v{number}.yaml").write_text(f"v: {number}\n", encoding="utf-8")

        default_result = self.run_cli(root, "--json")
        strict_result = self.run_cli(root, "--json", "--strict-lifecycle")

        self.assertEqual(default_result.returncode, 0)
        self.assertEqual(strict_result.returncode, 1)
        self.assertTrue(json.loads(strict_result.stdout)["summary"]["strict_lifecycle_failed"])


if __name__ == "__main__":
    unittest.main()
