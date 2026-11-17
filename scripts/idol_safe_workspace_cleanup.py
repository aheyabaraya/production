#!/usr/bin/env python3
"""Conservative cleanup/report helper for the IDOL workspace.

Dry-run is the default. With --apply, this script deletes only low-risk local
temporary files and caches. Production artifacts, generated media, exports,
review boards, and versioned run files are report-only.
"""

from __future__ import annotations

import argparse
import fnmatch
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import yaml

from lib.idol_run_layout import ALBUM_KEY_RE, RUN_ID_RE, TITLE_KEY_RE


SAFE_FILE_NAMES = {
    ".DS_Store",
    "Thumbs.db",
    "npm-debug.log",
    "pnpm-debug.log",
    "yarn-debug.log",
    "yarn-error.log",
}
SAFE_FILE_SUFFIXES = {".pyc", ".pyo"}
SAFE_DIR_NAMES = {"__pycache__", ".pytest_cache", ".mypy_cache", ".ruff_cache"}
SAFE_CLEANUP_ROOT_NAMES = {
    "analytics",
    "automation",
    "handoff",
    "schemas",
    "scripts",
    "skills",
    "source-materials",
    "tools",
    "wiki",
}
VERSION_REPORT_ROOT_NAMES = {"catalog", "cf", "handoff", "runs"}
ACTIVE_VERSION_REPORT_ROOT_NAMES = {"catalog", "handoff", "runs"}
HEAVY_REPORT_ROOT_NAMES = {"cf", "runs"}
SKIP_SCAN_DIR_NAMES = {
    ".git",
    ".next",
    ".turbo",
    ".venv",
    ".venv-imagegen",
    ".venv-video",
    "node_modules",
    "dist",
    "build",
    "coverage",
}
PRIVATE_ROOT_NAMES = {"business-marketing"}
DUPLICATE_HASH_SKIP_DIR_NAMES = {"private", "internal", "backup", "export", ".runtime", ".grok", ".cursor", ".codex"}
DUPLICATE_HASH_SECRET_NAME_TOKENS = {"wallet", "keystore", "seed", "mnemonic", "credential"}
DEFAULT_POLICY_PATH = Path("automation/artifact-lifecycle-policy.yaml")
REPORT_SCHEMA_VERSION = "idol-safe-workspace-cleanup-report.v2"
ARTIFACT_DIR_NAMES = {"exports", "generations", "renders", "frames", "video", "audio"}
VERSIONED_EXTENSIONS = {
    ".json",
    ".jsonl",
    ".md",
    ".txt",
    ".yaml",
    ".yml",
}
VERSION_RE = re.compile(r"^(?P<base>.+?)[-_]v(?P<num>\d+)(?P<suffix>\.[^.]+)$", re.IGNORECASE)
VERSION_DIR_RE = re.compile(r"^(?P<base>.+?)[-_]v(?P<num>\d+)$", re.IGNORECASE)
SHA256_RE = re.compile(r"^[a-f0-9]{64}$")
RESEARCH_INDEX_NAMES = {
    "INDEX.md",
    "index.json",
    "index.yaml",
    "index.yml",
    "manifest.yaml",
    "manifest.yml",
}


@dataclass(frozen=True)
class CleanupTarget:
    path: Path
    kind: str
    reason: str


@dataclass(frozen=True)
class SizeRow:
    path: Path
    size: int
    note: str


@dataclass(frozen=True)
class VersionFamily:
    parent: Path
    base: str
    suffix: str
    versions: tuple[tuple[int, Path], ...]
    max_active: int


@dataclass(frozen=True)
class LifecycleIssue:
    code: str
    severity: str
    path: Path
    detail: str
    legacy_debt: bool = False


@dataclass(frozen=True)
class DuplicateGroup:
    sha256: str
    size: int
    paths: tuple[Path, ...]

    @property
    def reclaimable_size(self) -> int:
        return self.size * (len(self.paths) - 1)


def run_text(args: list[str], cwd: Path) -> tuple[int, str, str]:
    result = subprocess.run(args, cwd=cwd, capture_output=True, text=True, check=False)
    return result.returncode, result.stdout.strip(), result.stderr.strip()


def validate_with_canonical_schema(contract_root: Path, schema_relative: str, document: Path) -> str | None:
    launcher = contract_root / "scripts" / "idol-video-python"
    validator = contract_root / "scripts" / "validate_json_schema.py"
    schema = contract_root / schema_relative
    if not launcher.is_file() or not validator.is_file() or not schema.is_file():
        return f"canonical schema validator is unavailable under {contract_root}"
    code, stdout, stderr = run_text(
        [str(launcher), str(validator), str(schema), str(document)],
        contract_root,
    )
    if code == 0:
        return None
    return stderr or stdout or "canonical schema validation failed without diagnostics"


def repo_root() -> Path:
    code, stdout, _stderr = run_text(["git", "rev-parse", "--show-toplevel"], Path.cwd())
    if code == 0 and stdout:
        return Path(stdout).resolve()
    return Path.cwd().resolve()


def resolve_root(value: str | None) -> Path:
    if value is None:
        return repo_root()
    return Path(value).expanduser().resolve()


def resolve_policy_path(value: str | None, root: Path) -> Path:
    if value is None:
        return (root / DEFAULT_POLICY_PATH).resolve()
    path = Path(value).expanduser()
    if not path.is_absolute():
        path = root / path
    return path.resolve()


def require_mapping(value: Any, label: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ValueError(f"{label} must be a mapping")
    return value


def require_int(value: Any, label: str, minimum: int = 0) -> int:
    if not isinstance(value, int) or isinstance(value, bool) or value < minimum:
        raise ValueError(f"{label} must be an integer >= {minimum}")
    return value


def load_lifecycle_policy(path: Path) -> dict[str, Any]:
    try:
        loaded = yaml.safe_load(path.read_text(encoding="utf-8"))
    except OSError as error:
        raise ValueError(f"cannot read lifecycle policy {path}: {error}") from error
    except yaml.YAMLError as error:
        raise ValueError(f"invalid lifecycle policy YAML {path}: {error}") from error

    policy = require_mapping(loaded, "lifecycle policy")
    contract_root = path.parent.parent
    schema_error = validate_with_canonical_schema(
        contract_root,
        "schemas/artifact-lifecycle-policy.schema.json",
        path,
    )
    if schema_error:
        raise ValueError(f"lifecycle policy schema validation failed: {schema_error}")
    if policy.get("schema_version") != "idol-artifact-lifecycle-policy.v3":
        raise ValueError("unsupported lifecycle policy schema_version")

    versions = require_mapping(policy.get("versions"), "versions")
    require_mapping(policy.get("research"), "research")
    require_mapping(policy.get("final_closeout"), "final_closeout")
    archive = require_mapping(policy.get("archive"), "archive")
    storage = require_mapping(policy.get("storage"), "storage")
    legacy = require_mapping(policy.get("legacy"), "legacy")
    require_int(versions.get("max_active_supporting_revisions_per_family"), "versions.max_active_supporting_revisions_per_family", 1)
    require_int(versions.get("max_rollback_checkpoints_per_family"), "versions.max_rollback_checkpoints_per_family", 0)
    require_int(storage.get("duplicate_scan_min_bytes"), "storage.duplicate_scan_min_bytes", 0)

    retention_reasons = archive.get("allowed_retention_reasons")
    if not isinstance(retention_reasons, list) or not retention_reasons or not all(
        isinstance(reason, str) and reason for reason in retention_reasons
    ):
        raise ValueError("archive.allowed_retention_reasons must be a non-empty string list")
    forbidden_roots = storage.get("forbidden_new_root_directories")
    if not isinstance(forbidden_roots, list) or not all(isinstance(name, str) and name for name in forbidden_roots):
        raise ValueError("storage.forbidden_new_root_directories must be a string list")
    if not isinstance(legacy.get("existing_debt_nonblocking_by_default"), bool):
        raise ValueError("legacy.existing_debt_nonblocking_by_default must be boolean")
    return policy


def is_skipped_scan_dir(name: str) -> bool:
    return name in SKIP_SCAN_DIR_NAMES or name.startswith(".venv")


def rel(path: Path, root: Path) -> str:
    try:
        return path.absolute().relative_to(root.resolve()).as_posix()
    except ValueError:
        pass
    try:
        return path.resolve().relative_to(root.resolve()).as_posix()
    except ValueError:
        return path.as_posix()


def is_inside(path: Path, root: Path) -> bool:
    try:
        path.resolve().relative_to(root.resolve())
        return True
    except ValueError:
        return False


def has_symlink_component(path: Path, root: Path) -> bool:
    """Return true when a repo-relative route crosses a symlink component."""
    try:
        parts = path.relative_to(root).parts
    except ValueError:
        return True
    current = root
    for part in parts:
        current = current / part
        if current.is_symlink():
            return True
    return False


def is_under_any(path: Path, parents: list[Path]) -> bool:
    resolved = path.resolve()
    for parent in parents:
        try:
            resolved.relative_to(parent.resolve())
            return True
        except ValueError:
            continue
    return False


def is_report_only_artifact_dir(path: Path, root: Path) -> bool:
    try:
        parts = path.resolve().relative_to(root.resolve()).parts
    except ValueError:
        return False
    if not parts or parts[0] not in {"runs", "cf"}:
        return False
    name = path.name
    if name in ARTIFACT_DIR_NAMES:
        return True
    if path.parent.name == "review" and (name == "contact-sheets" or name.startswith("storyboard-preview")):
        return True
    return False


def existing_named_roots(root: Path, names: set[str]) -> list[Path]:
    roots: list[Path] = []
    for name in sorted(names):
        path = root / name
        if path.exists() and not path.is_symlink():
            roots.append(path)
    return roots


def safe_file_reason(path: Path) -> str | None:
    if path.name in SAFE_FILE_NAMES:
        return f"temporary file: {path.name}"
    if path.suffix in SAFE_FILE_SUFFIXES:
        return f"compiled Python cache: {path.suffix}"
    return None


def human_size(size: int) -> str:
    units = ["B", "KiB", "MiB", "GiB", "TiB"]
    value = float(size)
    for unit in units:
        if value < 1024 or unit == units[-1]:
            if unit == "B":
                return f"{int(value)} {unit}"
            return f"{value:.1f} {unit}"
        value /= 1024
    return f"{size} B"


def path_size(path: Path) -> int:
    if not path.exists() or path.is_symlink():
        return 0
    code, stdout, _stderr = run_text(["du", "-sk", str(path)], path.parent if path.parent.exists() else Path.cwd())
    if code == 0 and stdout:
        first = stdout.splitlines()[0].split()[0]
        try:
            return int(first) * 1024
        except ValueError:
            pass
    if path.is_file():
        return path.stat().st_size
    total = 0
    for dirpath, dirnames, filenames in os.walk(path, followlinks=False):
        dirnames[:] = [name for name in dirnames if not (Path(dirpath) / name).is_symlink()]
        for filename in filenames:
            file_path = Path(dirpath) / filename
            if not file_path.is_symlink():
                total += file_path.stat().st_size
    return total


def collect_safe_targets(root: Path) -> list[CleanupTarget]:
    targets: list[CleanupTarget] = []
    safe_dirs: list[Path] = []
    scan_roots = existing_named_roots(root, SAFE_CLEANUP_ROOT_NAMES)

    for child in root.iterdir():
        if child.is_file() and not child.is_symlink():
            reason = safe_file_reason(child)
            if reason:
                targets.append(CleanupTarget(child, "file", reason))

    for scan_root in scan_roots:
        for dirpath, dirnames, filenames in os.walk(scan_root, followlinks=False):
            current_dir = Path(dirpath)

            kept_dirs: list[str] = []
            for dirname in dirnames:
                child = current_dir / dirname
                if child.is_symlink():
                    continue
                if dirname in SAFE_DIR_NAMES:
                    safe_dirs.append(child)
                    targets.append(CleanupTarget(child, "dir", f"cache directory: {dirname}"))
                    continue
                if is_skipped_scan_dir(dirname) or is_report_only_artifact_dir(child, root):
                    continue
                kept_dirs.append(dirname)
            dirnames[:] = kept_dirs

            for filename in filenames:
                file_path = current_dir / filename
                if file_path.is_symlink() or is_under_any(file_path, safe_dirs):
                    continue
                reason = safe_file_reason(file_path)
                if reason:
                    targets.append(CleanupTarget(file_path, "file", reason))

    deduped: dict[Path, CleanupTarget] = {}
    for target in targets:
        deduped[target.path.resolve()] = target
    return sorted(deduped.values(), key=lambda target: rel(target.path, root))


def collect_heavy_artifacts(root: Path) -> list[SizeRow]:
    rows: dict[Path, SizeRow] = {}
    for scan_root in existing_named_roots(root, HEAVY_REPORT_ROOT_NAMES):
        for dirpath, dirnames, _filenames in os.walk(scan_root, followlinks=False):
            current_dir = Path(dirpath)
            kept_dirs: list[str] = []
            for dirname in dirnames:
                child = current_dir / dirname
                if child.is_symlink():
                    continue
                if is_skipped_scan_dir(dirname):
                    continue
                if is_report_only_artifact_dir(child, root):
                    resolved = child.resolve()
                    rows[resolved] = SizeRow(path=resolved, size=path_size(resolved), note="report-only artifact directory")
                    continue
                kept_dirs.append(dirname)
            dirnames[:] = kept_dirs
    return sorted(rows.values(), key=lambda row: row.size, reverse=True)


def is_in_inactive_lifecycle_lane(path: Path, root: Path, policy: dict[str, Any]) -> bool:
    try:
        relative = path.resolve().relative_to(root.resolve()).as_posix()
    except ValueError:
        return True
    normalized = f"/{relative.rstrip('/')}/"
    ephemeral = require_mapping(policy["ephemeral"], "ephemeral")
    for marker in ephemeral["allowed_path_markers"]:
        if marker in normalized:
            return True
    for pattern in ephemeral["allowed_path_globs"]:
        if fnmatch.fnmatch(relative, pattern):
            return True
    if "/archive/" in normalized:
        return True
    return False


def active_run_roots(root: Path, policy: dict[str, Any]) -> list[Path]:
    """Return canonical album runs plus exact registered in-flight exceptions."""
    runs_root = root / "runs"
    if not runs_root.is_dir() or runs_root.is_symlink():
        return []

    active: set[Path] = set()
    for candidate in runs_root.glob("*/*/*"):
        if not candidate.is_dir() or candidate.is_symlink():
            continue
        parts = candidate.relative_to(runs_root).parts
        if (
            len(parts) == 3
            and ALBUM_KEY_RE.fullmatch(parts[0]) is not None
            and TITLE_KEY_RE.fullmatch(parts[1]) is not None
            and RUN_ID_RE.fullmatch(parts[2]) is not None
        ):
            active.add(candidate.resolve())

    run_layout = require_mapping(policy["run_layout"], "run_layout")
    registry_value = run_layout.get("transition_registry")
    if isinstance(registry_value, str) and registry_value:
        registry_path = root / registry_value
        try:
            registry = yaml.safe_load(registry_path.read_text(encoding="utf-8"))
        except (OSError, yaml.YAMLError):
            registry = {}
        if isinstance(registry, dict):
            for row in registry.get("in_flight_exceptions", []):
                if not isinstance(row, dict):
                    continue
                run_value = row.get("run_root")
                if not isinstance(run_value, str) or not run_value:
                    continue
                candidate = root / run_value
                if candidate.is_dir() and not candidate.is_symlink():
                    active.add(candidate.resolve())
    return sorted(active, key=lambda item: item.as_posix())


def is_in_active_run(path: Path, active_runs: list[Path]) -> bool:
    resolved = path.resolve()
    for run_root in active_runs:
        try:
            resolved.relative_to(run_root)
            return True
        except ValueError:
            continue
    return False


def is_on_active_run_route(path: Path, active_runs: list[Path]) -> bool:
    resolved = path.resolve()
    for run_root in active_runs:
        try:
            resolved.relative_to(run_root)
            return True
        except ValueError:
            pass
        try:
            run_root.relative_to(resolved)
            return True
        except ValueError:
            continue
    return False


def collect_version_groups(
    root: Path,
    active_only: bool = False,
    policy: dict[str, Any] | None = None,
) -> dict[tuple[Path, str, str], list[tuple[int, Path]]]:
    if active_only and policy is None:
        raise ValueError("active version grouping requires the lifecycle policy")
    groups: dict[tuple[Path, str, str], list[tuple[int, Path]]] = {}
    active_runs = active_run_roots(root, policy) if active_only and policy is not None else []
    scan_root_names = ACTIVE_VERSION_REPORT_ROOT_NAMES if active_only else VERSION_REPORT_ROOT_NAMES
    for scan_root in existing_named_roots(root, scan_root_names):
        for dirpath, dirnames, filenames in os.walk(scan_root, followlinks=False):
            current_dir = Path(dirpath)
            kept_dirs: list[str] = []
            for dirname in dirnames:
                child = current_dir / dirname
                if (
                    is_skipped_scan_dir(dirname)
                    or is_report_only_artifact_dir(child, root)
                    or child.is_symlink()
                ):
                    continue
                inactive = (
                    active_only
                    and policy is not None
                    and (
                        is_in_inactive_lifecycle_lane(child, root, policy)
                        or (
                            scan_root.name == "runs"
                            and not is_on_active_run_route(child, active_runs)
                        )
                    )
                )
                if inactive:
                    continue
                kept_dirs.append(dirname)
                match = VERSION_DIR_RE.match(dirname)
                if match:
                    key = (current_dir.resolve(), match.group("base"), "/")
                    groups.setdefault(key, []).append((int(match.group("num")), child.resolve()))
            dirnames[:] = kept_dirs
            for filename in filenames:
                path = current_dir / filename
                if path.is_symlink() or (
                    active_only
                    and policy is not None
                    and (
                        is_in_inactive_lifecycle_lane(path, root, policy)
                        or (
                            scan_root.name == "runs"
                            and not is_in_active_run(path, active_runs)
                        )
                    )
                ):
                    continue
                if path.suffix.lower() not in VERSIONED_EXTENSIONS:
                    continue
                match = VERSION_RE.match(filename)
                if not match:
                    continue
                key = (current_dir.resolve(), match.group("base"), match.group("suffix").lower())
                groups.setdefault(key, []).append((int(match.group("num")), path.resolve()))
    for versions in groups.values():
        versions.sort(key=lambda item: (item[0], rel(item[1], root)))
    return groups


def collect_older_version_files(root: Path) -> list[SizeRow]:
    groups = collect_version_groups(root)

    older: list[SizeRow] = []
    for _key, versions in groups.items():
        if len(versions) < 2:
            continue
        highest_observed_num = max(num for num, _path in versions)
        for num, path in versions:
            if num != highest_observed_num:
                older.append(SizeRow(path=path, size=path_size(path), note=f"lower-numbered sibling of highest observed numeric version v{highest_observed_num}; canonical pointer not evaluated"))
    return sorted(older, key=lambda row: (rel(row.path.parent, root), row.path.name))


def collect_version_pileups(root: Path, max_active: int, policy: dict[str, Any]) -> list[VersionFamily]:
    pileups: list[VersionFamily] = []
    for (parent, base, suffix), versions in collect_version_groups(root, active_only=True, policy=policy).items():
        if len(versions) <= max_active:
            continue
        pileups.append(
            VersionFamily(
                parent=parent,
                base=base,
                suffix=suffix,
                versions=tuple(versions),
                max_active=max_active,
            )
        )
    return sorted(pileups, key=lambda family: (rel(family.parent, root), family.base, family.suffix))


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while chunk := handle.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def collect_forbidden_root_issues(root: Path, policy: dict[str, Any]) -> list[LifecycleIssue]:
    forbidden = require_mapping(policy["storage"], "storage")["forbidden_new_root_directories"]
    legacy_debt = bool(require_mapping(policy["legacy"], "legacy")["existing_debt_nonblocking_by_default"])
    issues: list[LifecycleIssue] = []
    for name in sorted(forbidden):
        path = root / name
        if path.is_symlink():
            issues.append(
                LifecycleIssue(
                    code="forbidden_root_symlink",
                    severity="error",
                    path=path,
                    detail="forbidden root-level artifact lane cannot be hidden or redirected through a symlink",
                    legacy_debt=False,
                )
            )
        elif path.is_dir():
            issues.append(
                LifecycleIssue(
                    code="forbidden_root_directory",
                    severity="warning",
                    path=path,
                    detail="legacy root-level artifact directory; migrate through an explicit reviewed cleanup",
                    legacy_debt=legacy_debt,
                )
            )
    return issues


def directory_file_stats(path: Path) -> tuple[int, int]:
    count = 0
    size = 0
    for dirpath, dirnames, filenames in os.walk(path, followlinks=False):
        current = Path(dirpath)
        dirnames[:] = [
            name
            for name in dirnames
            if not (current / name).is_symlink() and not is_skipped_scan_dir(name)
        ]
        for filename in filenames:
            file_path = current / filename
            if file_path.is_symlink():
                continue
            try:
                size += file_path.stat().st_size
            except OSError:
                continue
            count += 1
    return count, size


def collect_research_folder_issues(root: Path, policy: dict[str, Any]) -> list[LifecycleIssue]:
    research_policy = require_mapping(policy["research"], "research")
    storage_policy = require_mapping(policy["storage"], "storage")
    ephemeral_names = set(research_policy["ephemeral_research_directories"])
    file_threshold = int(storage_policy["manifest_required_file_count"])
    byte_threshold = int(storage_policy["manifest_required_total_bytes"])
    issues: list[LifecycleIssue] = []

    for run_root in active_run_roots(root, policy):
        research_root = run_root / "research"
        if not research_root.is_dir() or research_root.is_symlink():
            continue
        for child in sorted(research_root.iterdir(), key=lambda item: item.name):
            if not child.is_dir() or child.is_symlink():
                continue
            file_count, total_bytes = directory_file_stats(child)
            if file_count == 0:
                issues.append(
                    LifecycleIssue(
                        code="empty_optional_research_directory",
                        severity="warning",
                        path=child,
                        detail="optional research folders are created only when content exists",
                    )
                )
                continue
            if child.name in ephemeral_names:
                continue
            needs_index = file_count >= file_threshold or total_bytes >= byte_threshold
            has_index = any((child / name).is_file() for name in RESEARCH_INDEX_NAMES)
            if needs_index and not has_index:
                issues.append(
                    LifecycleIssue(
                        code="research_folder_index_missing",
                        severity="warning",
                        path=child,
                        detail=(
                            f"durable research folder has {file_count} files and "
                            f"{total_bytes} bytes but no top-level manifest/index"
                        ),
                    )
                )
    return issues


def discover_run_archive_paths(root: Path) -> tuple[list[Path], list[LifecycleIssue]]:
    runs_root = root / "runs"
    issues: list[LifecycleIssue] = []
    if runs_root.is_symlink():
        issues.append(LifecycleIssue(
            code="archive_owner_symlink",
            severity="error",
            path=runs_root,
            detail="runs root cannot be a symlink because archive ownership would be unverifiable",
        ))
        return [], issues
    if not runs_root.exists():
        return [], issues
    if not runs_root.is_dir():
        issues.append(LifecycleIssue(
            code="archive_owner_path_invalid",
            severity="error",
            path=runs_root,
            detail="runs root must be a real directory",
        ))
        return [], issues

    archives: list[Path] = []
    pending = [runs_root]
    while pending:
        current = pending.pop()
        try:
            entries = sorted(os.scandir(current), key=lambda entry: entry.name)
        except OSError as error:
            issues.append(LifecycleIssue(
                code="archive_scan_incomplete",
                severity="error",
                path=current,
                detail=f"could not inspect directory while discovering physical archives: {error}",
            ))
            continue

        for entry in entries:
            path = Path(entry.path)
            parts = path.relative_to(runs_root).parts
            if entry.is_symlink():
                if len(parts) <= 3:
                    issues.append(LifecycleIssue(
                        code="archive_owner_symlink",
                        severity="error",
                        path=path,
                        detail="run album/title/id ownership paths cannot be symlinks",
                    ))
                if entry.name == "archive":
                    archives.append(path)
                continue
            try:
                is_directory = entry.is_dir(follow_symlinks=False)
            except OSError as error:
                issues.append(LifecycleIssue(
                    code="archive_scan_incomplete",
                    severity="error",
                    path=path,
                    detail=f"could not classify path while discovering physical archives: {error}",
                ))
                continue
            if not is_directory:
                continue
            if entry.name == "archive":
                archives.append(path)
                continue
            pending.append(path)

    unique_archives = sorted(set(archives), key=lambda path: path.as_posix())
    for archive_dir in unique_archives:
        parts = archive_dir.relative_to(runs_root).parts
        valid_owner = (
            len(parts) == 4
            and ALBUM_KEY_RE.fullmatch(parts[0]) is not None
            and TITLE_KEY_RE.fullmatch(parts[1]) is not None
            and RUN_ID_RE.fullmatch(parts[2]) is not None
            and parts[3] == "archive"
        )
        if not valid_owner:
            issues.append(LifecycleIssue(
                code="archive_owner_path_invalid",
                severity="error",
                path=archive_dir,
                detail="physical archive must be runs/ALBUM_KEY/TITLE_KEY/RUN_ID/archive",
            ))
    return unique_archives, issues


def archive_files_and_symlinks(
    archive_dir: Path,
    manifest_path: Path,
) -> tuple[list[Path], list[Path], list[tuple[Path, str]]]:
    files: list[Path] = []
    symlinks: list[Path] = []
    scan_errors: list[tuple[Path, str]] = []

    def record_scan_error(error: OSError) -> None:
        error_path = Path(error.filename) if error.filename else archive_dir
        scan_errors.append((error_path, str(error)))

    for dirpath, dirnames, filenames in os.walk(
        archive_dir,
        followlinks=False,
        onerror=record_scan_error,
    ):
        current = Path(dirpath)
        kept_dirs: list[str] = []
        for name in sorted(dirnames):
            path = current / name
            if path.is_symlink():
                symlinks.append(path)
            else:
                # A physical archive is an evidence vault, not a general
                # workspace scan. Every real child directory must be traversed
                # regardless of names such as build, dist, node_modules, or
                # .next so unindexed bytes cannot hide behind cache filters.
                kept_dirs.append(name)
        dirnames[:] = kept_dirs
        for filename in sorted(filenames):
            path = current / filename
            if path.is_symlink():
                symlinks.append(path)
                continue
            if path == manifest_path:
                continue
            files.append(path)
    return files, symlinks, scan_errors


def collect_archive_manifest_issues(
    root: Path,
    policy: dict[str, Any],
    contract_root: Path,
) -> list[LifecycleIssue]:
    archive_policy = require_mapping(policy["archive"], "archive")
    versions_policy = require_mapping(policy["versions"], "versions")
    manifest_name = str(archive_policy.get("manifest_name", "manifest.yaml"))
    allowed_retention = set(archive_policy["allowed_retention_reasons"])
    max_rollbacks = int(versions_policy["max_rollback_checkpoints_per_family"])
    required_manifest_fields = {"schema_version", "owner_root", "generated_at", "status", "entries"}
    required_entry_fields = {
        "archive_id",
        "artifact_family",
        "path",
        "sha256",
        "size_bytes",
        "retention_reason",
        "canonical_path",
        "protection_status",
        "review_after",
        "source_refs",
        "notes",
    }
    archive_paths, discovery_issues = discover_run_archive_paths(root)
    issues: list[LifecycleIssue] = list(discovery_issues)

    def add(code: str, path: Path, detail: str, severity: str = "error") -> None:
        issues.append(LifecycleIssue(code=code, severity=severity, path=path, detail=detail))

    for archive_dir in archive_paths:
        if archive_dir.is_symlink():
            add("archive_directory_symlink_forbidden", archive_dir, "run-owned archive must be a real directory")
            continue
        manifest_path = archive_dir / manifest_name
        archive_regular_files, archive_symlinks, archive_scan_errors = archive_files_and_symlinks(
            archive_dir,
            manifest_path,
        )
        for path, detail in archive_scan_errors:
            add("archive_scan_incomplete", path, f"could not inspect physical archive completely: {detail}")
        for path in archive_symlinks:
            add("archive_symlink_forbidden", path, "physical archives cannot contain file or directory symlinks")
        if not manifest_path.is_file() or manifest_path.is_symlink():
            add("archive_manifest_missing", archive_dir, f"missing required {manifest_name}")
            for path in archive_regular_files:
                add("archive_path_unindexed", path, "archive file cannot be indexed without a manifest")
            continue
        try:
            manifest = yaml.safe_load(manifest_path.read_text(encoding="utf-8"))
        except (OSError, yaml.YAMLError) as error:
            add("archive_manifest_invalid_yaml", manifest_path, str(error))
            continue
        if not isinstance(manifest, dict):
            add("archive_manifest_invalid", manifest_path, "manifest must be a mapping")
            continue
        schema_error = validate_with_canonical_schema(
            contract_root,
            str(archive_policy["manifest_schema"]),
            manifest_path,
        )
        if schema_error:
            add("archive_manifest_schema_invalid", manifest_path, schema_error)
        missing_manifest = sorted(required_manifest_fields - set(manifest))
        if missing_manifest:
            add("archive_manifest_missing_field", manifest_path, f"missing: {', '.join(missing_manifest)}")
        if manifest.get("schema_version") != "idol-artifact-archive-manifest.v2":
            add("archive_manifest_schema_invalid", manifest_path, "schema_version must be idol-artifact-archive-manifest.v2")

        owner_root = rel(archive_dir.parent, root)
        if manifest.get("owner_root") != owner_root:
            add("archive_owner_root_mismatch", manifest_path, f"expected owner_root {owner_root}")

        entries = manifest.get("entries")
        if not isinstance(entries, list):
            add("archive_manifest_entries_invalid", manifest_path, "entries must be a list")
            entries = []

        indexed_paths: set[str] = set()
        archive_ids: set[str] = set()
        rollback_counts: dict[str, int] = {}
        for index, raw_entry in enumerate(entries):
            label = f"entry[{index}]"
            if not isinstance(raw_entry, dict):
                add("archive_entry_invalid", manifest_path, f"{label} must be a mapping")
                continue
            missing_entry = sorted(required_entry_fields - set(raw_entry))
            if missing_entry:
                add("archive_entry_missing_field", manifest_path, f"{label} missing: {', '.join(missing_entry)}")

            archive_id = raw_entry.get("archive_id")
            if isinstance(archive_id, str) and archive_id:
                if archive_id in archive_ids:
                    add("archive_entry_id_duplicate", manifest_path, f"{label} duplicates archive_id {archive_id}")
                archive_ids.add(archive_id)

            canonical_path = raw_entry.get("canonical_path")
            if canonical_path is not None:
                if not isinstance(canonical_path, str) or not canonical_path or Path(canonical_path).is_absolute():
                    add("archive_entry_canonical_path_invalid", manifest_path, f"{label} canonical_path must be repo-relative or null")
                else:
                    canonical = root / canonical_path
                    if not is_inside(canonical, root) or is_inside(canonical, archive_dir):
                        add("archive_entry_canonical_path_invalid", manifest_path, f"{label} canonical_path escapes the repo or points back into archive")
                    elif has_symlink_component(canonical, root):
                        add("archive_entry_canonical_path_invalid", canonical, f"{label} canonical_path cannot cross a symlink")
                    elif not canonical.exists():
                        add("archive_entry_canonical_path_missing", canonical, f"{label} canonical_path does not exist")

            retention_reason = raw_entry.get("retention_reason")
            if retention_reason not in allowed_retention:
                add("archive_entry_retention_invalid", manifest_path, f"{label} has unsupported retention_reason")
            family = raw_entry.get("artifact_family")
            if retention_reason == "rollback_checkpoint":
                if not isinstance(canonical_path, str) or not canonical_path:
                    add(
                        "archive_rollback_canonical_missing",
                        manifest_path,
                        f"{label} rollback_checkpoint must name its current canonical_path",
                    )
                if isinstance(family, str) and family:
                    rollback_counts[family] = rollback_counts.get(family, 0) + 1

            raw_path = raw_entry.get("path")
            if not isinstance(raw_path, str) or not raw_path or Path(raw_path).is_absolute():
                add("archive_entry_path_invalid", manifest_path, f"{label} path must be a repo-relative string")
                continue
            entry_path = root / raw_path
            if not is_inside(entry_path, archive_dir):
                add("archive_entry_path_invalid", manifest_path, f"{label} path is outside {rel(archive_dir, root)}")
                continue
            normalized = rel(entry_path, root)
            if normalized in indexed_paths:
                add("archive_entry_path_duplicate", manifest_path, f"{label} duplicates {normalized}")
            indexed_paths.add(normalized)

            if entry_path.is_symlink():
                add("archive_entry_symlink", entry_path, f"{label} cannot index a symlink")
                continue
            if not entry_path.is_file():
                add("archive_entry_missing_file", entry_path, f"{label} file does not exist")
                continue

            try:
                actual_size = entry_path.stat().st_size
            except OSError as error:
                add("archive_entry_unreadable", entry_path, f"{label} could not read file metadata: {error}")
                continue
            expected_size = raw_entry.get("size_bytes")
            if not isinstance(expected_size, int) or isinstance(expected_size, bool) or expected_size != actual_size:
                add("archive_entry_size_mismatch", entry_path, f"{label} expected {expected_size!r}, actual {actual_size}")
            expected_sha = raw_entry.get("sha256")
            if not isinstance(expected_sha, str) or not SHA256_RE.fullmatch(expected_sha):
                add("archive_entry_sha256_invalid", entry_path, f"{label} sha256 must be 64 lowercase hex characters")
            else:
                try:
                    actual_sha = sha256_file(entry_path)
                except OSError as error:
                    add("archive_entry_unreadable", entry_path, f"{label} could not hash file bytes: {error}")
                    continue
                if expected_sha != actual_sha:
                    add("archive_entry_sha256_mismatch", entry_path, f"{label} hash does not match file bytes")

        for family, count in sorted(rollback_counts.items()):
            if count > max_rollbacks:
                add(
                    "archive_rollback_limit_exceeded",
                    manifest_path,
                    f"artifact_family {family!r} has {count} rollback checkpoints; maximum is {max_rollbacks}",
                )

        for path in archive_regular_files:
            if rel(path, root) not in indexed_paths:
                add("archive_path_unindexed", path, "archive file is not indexed by manifest")

    if bool(require_mapping(policy["legacy"], "legacy")["existing_debt_nonblocking_by_default"]):
        active_runs = active_run_roots(root, policy)
        normalized: list[LifecycleIssue] = []
        for issue in issues:
            is_historical_archive_debt = (
                issue.path.exists()
                and not issue.path.is_symlink()
                and is_inside(issue.path, root / "runs")
                and not is_on_active_run_route(issue.path, active_runs)
            )
            if is_historical_archive_debt:
                normalized.append(
                    LifecycleIssue(
                        code=issue.code,
                        severity="warning",
                        path=issue.path,
                        detail=issue.detail,
                        legacy_debt=True,
                    )
                )
            else:
                normalized.append(issue)
        issues = normalized
    return sorted(issues, key=lambda issue: (rel(issue.path, root), issue.code, issue.detail))


def collect_lifecycle_issues(root: Path, policy: dict[str, Any], contract_root: Path) -> list[LifecycleIssue]:
    issues = collect_forbidden_root_issues(root, policy)
    issues.extend(collect_research_folder_issues(root, policy))
    issues.extend(collect_archive_manifest_issues(root, policy, contract_root))
    return sorted(issues, key=lambda issue: (rel(issue.path, root), issue.code, issue.detail))


def blocking_lifecycle_issues(
    issues: list[LifecycleIssue],
    policy: dict[str, Any],
) -> list[LifecycleIssue]:
    legacy_nonblocking = bool(
        require_mapping(policy["legacy"], "legacy")["existing_debt_nonblocking_by_default"]
    )
    return [
        issue
        for issue in issues
        if not (legacy_nonblocking and issue.legacy_debt)
    ]


def should_exclude_before_duplicate_hash(path: Path, root: Path) -> bool:
    """Filename/path exclusion only; must not open or hash the file.

    Duplicate groups stay report-only. Reclaimable/theoretical bytes stay theoretical.
    """
    lower = path.name.lower()
    if re.search(r"hax[ ._-]?ai", path.as_posix(), re.IGNORECASE):
        return True
    if lower == ".env" or lower.startswith(".env.") or lower.endswith(".env") or lower == ".envrc":
        return True
    if lower == "id.json":
        return True
    if lower.endswith((".pem", ".key", ".p12", ".pfx", ".db", ".dump")):
        return True
    if ".sqlite" in lower:
        return True
    if any(token in lower for token in DUPLICATE_HASH_SECRET_NAME_TOKENS | {"backup", "export"}):
        return True
    try:
        parent_parts = path.absolute().relative_to(root.absolute()).parts[:-1]
    except ValueError:
        return True
    skip_dirs = DUPLICATE_HASH_SKIP_DIR_NAMES | {name.lower() for name in PRIVATE_ROOT_NAMES}
    return any(part.lower() in skip_dirs or "backup" in part.lower() or "export" in part.lower() for part in parent_parts)


def is_nested_independent_repository(directory: Path, root: Path) -> bool:
    """Treat a nested .git work tree as out of hash scope. Fail closed on OSError."""
    try:
        if directory.resolve() == root.resolve():
            return False
        return (directory / ".git").exists() or (directory / ".git").is_symlink()
    except OSError:
        return True


def git_index_blocks_deletion(path: Path, root: Path, *, kind: str) -> str | None:
    """Skip one target when it is tracked, contains tracked paths, or Git cannot be queried.

    Fail closed per target. Ignored/untracked paths yield empty ls-files output and stay eligible.
    Does not widen deletion scope.
    """
    rel_path = rel(path, root)
    if any(key in os.environ for key in ("GIT_DIR", "GIT_COMMON_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_OBJECT_DIRECTORY", "GIT_CONFIG_COUNT", "GIT_CONFIG_PARAMETERS")):
        return f"{rel_path}: git context overridden; not deleted"
    current = path if kind == "dir" else path.parent
    while current != root and is_inside(current, root):
        if is_nested_independent_repository(current, root):
            return f"{rel_path}: nested repository; not deleted"
        current = current.parent
    args = ["git", "--literal-pathspecs", "ls-files", "-z", "--", rel_path]
    if kind == "dir":
        args.append(f"{rel_path.rstrip('/')}/")
    try:
        code, out, _err = run_text(args, cwd=root)
    except OSError:
        return f"{rel_path}: git check failed; not deleted"
    if code != 0:
        return f"{rel_path}: git check failed; not deleted"
    if out:
        return f"{rel_path}: git-tracked; not deleted"
    return None


def iter_duplicate_scan_files(root: Path, min_size: int) -> list[Path]:
    files: list[Path] = []
    for dirpath, dirnames, filenames in os.walk(root, followlinks=False):
        current = Path(dirpath)
        kept_dirs: list[str] = []
        for dirname in sorted(dirnames):
            child = current / dirname
            if child.is_symlink() or is_skipped_scan_dir(dirname) or dirname in PRIVATE_ROOT_NAMES:
                continue
            if dirname.lower() in DUPLICATE_HASH_SKIP_DIR_NAMES or "backup" in dirname.lower() or "export" in dirname.lower():
                continue
            if is_nested_independent_repository(child, root):
                continue
            kept_dirs.append(dirname)
        dirnames[:] = kept_dirs
        for filename in sorted(filenames):
            path = current / filename
            if should_exclude_before_duplicate_hash(path, root):
                continue
            if path.is_symlink() or not path.is_file():
                continue
            try:
                if path.stat().st_size >= min_size:
                    files.append(path)
            except OSError:
                continue
    return files


def collect_duplicate_groups(root: Path, min_size: int) -> list[DuplicateGroup]:
    by_size: dict[int, list[Path]] = {}
    for path in iter_duplicate_scan_files(root, min_size):
        by_size.setdefault(path.stat().st_size, []).append(path)

    groups: list[DuplicateGroup] = []
    for size, candidates in sorted(by_size.items()):
        if len(candidates) < 2:
            continue
        by_hash: dict[str, list[Path]] = {}
        for path in sorted(candidates, key=lambda item: rel(item, root)):
            try:
                digest = sha256_file(path)
            except OSError:
                continue
            by_hash.setdefault(digest, []).append(path)
        for digest, paths in sorted(by_hash.items()):
            if len(paths) > 1:
                groups.append(DuplicateGroup(sha256=digest, size=size, paths=tuple(paths)))
    return sorted(groups, key=lambda group: (-group.reclaimable_size, group.sha256, rel(group.paths[0], root)))


def collect_git_status(root: Path) -> list[str]:
    code, stdout, _stderr = run_text(["git", "status", "--short"], root)
    if code != 0 or not stdout:
        return []
    return stdout.splitlines()


def collect_git_object_report(root: Path) -> list[str]:
    code, stdout, stderr = run_text(["git", "count-objects", "-vH"], root)
    lines: list[str] = []
    if stderr:
        lines.extend(f"warning: {line}" for line in stderr.splitlines())
    if code == 0 and stdout:
        wanted = {"count", "size", "in-pack", "packs", "size-pack", "garbage", "size-garbage"}
        for line in stdout.splitlines():
            key = line.split(":", 1)[0]
            if key in wanted:
                lines.append(line)
    return lines


def delete_targets(targets: list[CleanupTarget], root: Path) -> tuple[int, int, list[str]]:
    deleted = 0
    reclaimed = 0
    skipped: list[str] = []
    files = [target for target in targets if target.kind == "file"]
    dirs = sorted([target for target in targets if target.kind == "dir"], key=lambda target: len(target.path.parts), reverse=True)

    for target in files + dirs:
        path = target.path
        if re.search(r"hax[ ._-]?ai", path.as_posix(), re.IGNORECASE):
            skipped.append(f"{rel(path, root)}: excluded-owner path")
            continue
        if not is_inside(path, root):
            skipped.append(f"{rel(path, root)}: outside repo root")
            continue
        if path.is_symlink() or has_symlink_component(path, root):
            skipped.append(f"{rel(path, root)}: symlink")
            continue
        if not path.exists():
            continue
        blocked = git_index_blocks_deletion(path, root, kind=target.kind)
        if blocked:
            skipped.append(blocked)
            continue
        size = path_size(path)
        try:
            if target.kind == "dir":
                shutil.rmtree(path)
            else:
                path.unlink()
        except OSError as error:
            skipped.append(f"{rel(path, root)}: {error}")
            continue
        deleted += 1
        reclaimed += size

    return deleted, reclaimed, skipped


def print_rows(title: str, rows: list[SizeRow], root: Path, max_items: int) -> None:
    print(f"\n{title}: {len(rows)}")
    if not rows:
        return
    for row in rows[:max_items]:
        print(f"  {human_size(row.size):>9}  {rel(row.path, root)}  ({row.note})")
    remaining = len(rows) - max_items
    if remaining > 0:
        print(f"  ... {remaining} more not shown")


def print_targets(title: str, targets: list[CleanupTarget], root: Path, max_items: int) -> None:
    total_size = sum(path_size(target.path) for target in targets)
    print(f"\n{title}: {len(targets)} ({human_size(total_size)})")
    if not targets:
        return
    for target in targets[:max_items]:
        print(f"  {target.kind:>4}  {rel(target.path, root)}  ({target.reason})")
    remaining = len(targets) - max_items
    if remaining > 0:
        print(f"  ... {remaining} more not shown")


def print_version_pileups(pileups: list[VersionFamily], root: Path, max_items: int) -> None:
    print(f"\nLifecycle version pileup families: {len(pileups)}")
    for family in pileups[:max_items]:
        versions = ", ".join(f"v{number}" for number, _path in family.versions)
        print(
            f"  {rel(family.parent, root)}/{family.base}-vN{family.suffix}: "
            f"{len(family.versions)} active revisions ({versions}); maximum {family.max_active}"
        )
    remaining = len(pileups) - max_items
    if remaining > 0:
        print(f"  ... {remaining} more not shown")


def print_lifecycle_issues(issues: list[LifecycleIssue], root: Path, max_items: int) -> None:
    print(f"\nLifecycle issues: {len(issues)}")
    for issue in issues[:max_items]:
        debt = ", legacy debt" if issue.legacy_debt else ""
        print(f"  [{issue.severity}{debt}] {issue.code}: {rel(issue.path, root)} ({issue.detail})")
    remaining = len(issues) - max_items
    if remaining > 0:
        print(f"  ... {remaining} more not shown")


def print_duplicate_groups(groups: list[DuplicateGroup], root: Path, max_items: int, enabled: bool) -> None:
    if not enabled:
        print("\nExact duplicate groups: not scanned (use --hash-duplicates)")
        return
    reclaimable = sum(group.reclaimable_size for group in groups)
    print(f"\nExact duplicate groups: {len(groups)} (theoretical duplicate bytes {human_size(reclaimable)})")
    for group in groups[:max_items]:
        print(f"  {human_size(group.size)} x {len(group.paths)}  sha256:{group.sha256}")
        for path in group.paths:
            print(f"    {rel(path, root)}")
    remaining = len(groups) - max_items
    if remaining > 0:
        print(f"  ... {remaining} more groups not shown")


def size_row_dict(row: SizeRow, root: Path) -> dict[str, Any]:
    return {"path": rel(row.path, root), "size_bytes": row.size, "note": row.note}


def build_json_report(
    *,
    root: Path,
    policy_path: Path,
    policy: dict[str, Any],
    args: argparse.Namespace,
    safe_targets: list[CleanupTarget],
    safe_target_sizes: dict[Path, int],
    heavy_artifacts: list[SizeRow],
    older_versions: list[SizeRow],
    version_pileups: list[VersionFamily],
    lifecycle_issues: list[LifecycleIssue],
    duplicate_groups: list[DuplicateGroup],
    git_status: list[str],
    git_objects: list[str],
    applied: dict[str, Any],
) -> dict[str, Any]:
    safe_target_rows = [
        {
            "path": rel(target.path, root),
            "kind": target.kind,
            "reason": target.reason,
            "size_bytes": safe_target_sizes[target.path.resolve()],
        }
        for target in safe_targets
    ]
    pileup_rows = []
    for family in version_pileups:
        pileup_rows.append(
            {
                "family": f"{rel(family.parent, root)}/{family.base}-vN{family.suffix}",
                "parent": rel(family.parent, root),
                "base": family.base,
                "suffix": family.suffix,
                "version_count": len(family.versions),
                "max_active": family.max_active,
                "versions": [
                    {"number": number, "path": rel(path, root), "size_bytes": path_size(path)}
                    for number, path in family.versions
                ],
            }
        )
    issue_rows = [
        {
            "code": issue.code,
            "severity": issue.severity,
            "path": rel(issue.path, root),
            "detail": issue.detail,
            "legacy_debt": issue.legacy_debt,
        }
        for issue in lifecycle_issues
    ]
    duplicate_rows = [
        {
            "sha256": group.sha256,
            "size_bytes": group.size,
            "copy_count": len(group.paths),
            "theoretical_reclaimable_bytes": group.reclaimable_size,
            "paths": [rel(path, root) for path in group.paths],
        }
        for group in duplicate_groups
    ]
    blocking_issues = blocking_lifecycle_issues(lifecycle_issues, policy)
    return {
        "schema_version": REPORT_SCHEMA_VERSION,
        "root": root.as_posix(),
        "mode": "apply_safe_cache_only" if args.apply else "dry_run_report_only",
        "policy": {
            "path": rel(policy_path, root),
            "schema_version": policy["schema_version"],
        },
        "summary": {
            "safe_target_count": len(safe_targets),
            "safe_target_bytes": sum(safe_target_sizes.values()),
            "heavy_artifact_directory_count": len(heavy_artifacts),
            "older_version_file_count": len(older_versions),
            "version_pileup_family_count": len(version_pileups),
            "lifecycle_issue_count": len(lifecycle_issues),
            "blocking_lifecycle_issue_count": len(blocking_issues),
            "duplicate_scan_enabled": bool(args.hash_duplicates),
            "duplicate_group_count": len(duplicate_groups),
            "duplicate_theoretical_reclaimable_bytes": sum(group.reclaimable_size for group in duplicate_groups),
            "git_dirty_entry_count": len(git_status),
            "strict_lifecycle_failed": bool(args.strict_lifecycle and (version_pileups or blocking_issues)),
        },
        "safe_targets": safe_target_rows,
        "applied_cleanup": applied,
        "heavy_artifacts": [size_row_dict(row, root) for row in heavy_artifacts],
        "older_version_files": [size_row_dict(row, root) for row in older_versions],
        "version_pileups": pileup_rows,
        "lifecycle_issues": issue_rows,
        "duplicate_groups": duplicate_rows,
        "git": {"dirty_entries": git_status, "object_summary": git_objects},
    }


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Report IDOL workspace volume risks and optionally delete only safe temporary files."
    )
    parser.add_argument("--apply", action="store_true", help="delete only safe temporary/cache targets")
    parser.add_argument("--root", help="workspace root to inspect; defaults to the current git root")
    parser.add_argument(
        "--policy",
        help="artifact lifecycle policy path; relative paths resolve from --root",
    )
    parser.add_argument("--json", action="store_true", help="emit a machine-readable JSON report")
    parser.add_argument(
        "--hash-duplicates",
        action="store_true",
        help="hash size-matched files at or above the policy threshold; report only",
    )
    parser.add_argument(
        "--strict-lifecycle",
        action="store_true",
        help="exit nonzero when version pileups or lifecycle issues are found",
    )
    parser.add_argument("--max-report-items", type=int, default=40, help="maximum rows to show per section")
    parser.add_argument(
        "--skip-git-temp",
        action="store_true",
        help="deprecated compatibility flag; Git object files are never cleanup targets",
    )
    parser.add_argument(
        "--git-temp-min-age-minutes",
        type=int,
        default=10,
        help="deprecated compatibility value; Git object files are never cleanup targets",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    root = resolve_root(args.root)
    if not root.is_dir():
        print(f"error: workspace root is not a directory: {root}", file=sys.stderr)
        return 2
    policy_path = resolve_policy_path(args.policy, root)
    contract_root = policy_path.parent.parent
    try:
        policy = load_lifecycle_policy(policy_path)
    except ValueError as error:
        print(f"error: {error}", file=sys.stderr)
        return 2
    os.chdir(root)

    safe_targets = collect_safe_targets(root=root)
    safe_target_sizes = {target.path.resolve(): path_size(target.path) for target in safe_targets}
    heavy_artifacts = collect_heavy_artifacts(root)
    older_versions = collect_older_version_files(root)
    max_active = int(policy["versions"]["max_active_supporting_revisions_per_family"])
    version_pileups = collect_version_pileups(root, max_active=max_active, policy=policy)
    lifecycle_issues = collect_lifecycle_issues(root, policy, contract_root)
    blocking_issues = blocking_lifecycle_issues(lifecycle_issues, policy)
    duplicate_groups = (
        collect_duplicate_groups(root, min_size=int(policy["storage"]["duplicate_scan_min_bytes"]))
        if args.hash_duplicates
        else []
    )
    git_status = collect_git_status(root)
    git_objects = collect_git_object_report(root)

    applied: dict[str, Any] = {"deleted_count": 0, "reclaimed_bytes": 0, "skipped": []}
    if args.apply:
        deleted, reclaimed, skipped = delete_targets(safe_targets, root)
        applied = {"deleted_count": deleted, "reclaimed_bytes": reclaimed, "skipped": skipped}

    if args.json:
        report = build_json_report(
            root=root,
            policy_path=policy_path,
            policy=policy,
            args=args,
            safe_targets=safe_targets,
            safe_target_sizes=safe_target_sizes,
            heavy_artifacts=heavy_artifacts,
            older_versions=older_versions,
            version_pileups=version_pileups,
            lifecycle_issues=lifecycle_issues,
            duplicate_groups=duplicate_groups,
            git_status=git_status,
            git_objects=git_objects,
            applied=applied,
        )
        print(json.dumps(report, indent=2, sort_keys=True))
        return 1 if args.strict_lifecycle and (version_pileups or blocking_issues) else 0

    print("IDOL safe workspace cleanup")
    print(f"repo: {root}")
    print(f"mode: {'apply safe deletions' if args.apply else 'dry-run report only'}")
    print(f"policy: {rel(policy_path, root)} ({policy['schema_version']})")

    print_targets("Safe deletion targets", safe_targets, root, args.max_report_items)

    if args.apply:
        print(
            f"\nApplied safe cleanup: deleted {applied['deleted_count']} target(s), "
            f"reclaimed about {human_size(applied['reclaimed_bytes'])}"
        )
        if applied["skipped"]:
            print("Skipped:")
            for item in applied["skipped"][: args.max_report_items]:
                print(f"  {item}")
            if len(applied["skipped"]) > args.max_report_items:
                print(f"  ... {len(applied['skipped']) - args.max_report_items} more not shown")
    else:
        print("\nNo files were changed. Re-run with --apply to delete only the safe targets above.")

    print_rows("Report-only heavy artifact directories", heavy_artifacts, root, args.max_report_items)
    print_rows("Report-only older version files", older_versions, root, args.max_report_items)
    print_version_pileups(version_pileups, root, args.max_report_items)
    print_lifecycle_issues(lifecycle_issues, root, args.max_report_items)
    print_duplicate_groups(duplicate_groups, root, args.max_report_items, args.hash_duplicates)

    print(f"\nGit dirty entries: {len(git_status)}")
    for line in git_status[: args.max_report_items]:
        print(f"  {line}")
    if len(git_status) > args.max_report_items:
        print(f"  ... {len(git_status) - args.max_report_items} more not shown")

    print("\nGit object summary:")
    if git_objects:
        for line in git_objects:
            print(f"  {line}")
    else:
        print("  unavailable")

    return 1 if args.strict_lifecycle and (version_pileups or blocking_issues) else 0


if __name__ == "__main__":
    sys.exit(main())
