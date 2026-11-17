from __future__ import annotations

import subprocess
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from .paths import IDOL_REPO_ROOT, resolve_repo_path


def _iso_from_timestamp(timestamp: float) -> str:
    return datetime.fromtimestamp(timestamp, tz=timezone.utc).astimezone().isoformat(timespec="seconds")


def probe_repo_path(relative_path: str, now: datetime) -> dict[str, Any]:
    """Return metadata only. This function never reads the source file body."""

    try:
        path = resolve_repo_path(relative_path)
    except (ValueError, OSError) as exc:
        return {
            "path": relative_path,
            "exists": False,
            "safe": False,
            "error": str(exc),
        }

    if not path.exists():
        return {
            "path": relative_path,
            "exists": False,
            "safe": True,
            "error": None,
        }

    stat = path.stat()
    modified = datetime.fromtimestamp(stat.st_mtime, tz=timezone.utc).astimezone()
    age_days = max(0.0, (now.astimezone() - modified).total_seconds() / 86400)
    return {
        "path": relative_path,
        "exists": True,
        "safe": True,
        "kind": "directory" if path.is_dir() else "file",
        "modified_at": _iso_from_timestamp(stat.st_mtime),
        "age_days": round(age_days, 2),
        "size_bytes": stat.st_size if path.is_file() else None,
        "error": None,
    }


def _run_git(repo_path: Path, args: list[str], *, timeout: float = 3) -> tuple[str | None, str | None]:
    try:
        completed = subprocess.run(
            ["git", "-C", str(repo_path), *args],
            check=False,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        return None, str(exc)

    if completed.returncode != 0:
        return None, (completed.stderr.strip() or completed.stdout.strip() or "git probe failed")
    return completed.stdout.rstrip("\n"), None


def probe_git_repo(repo_spec: dict[str, Any]) -> dict[str, Any]:
    """Inspect branch, commit and dirty count using read-only Git commands."""

    repo_id = repo_spec.get("id", "unknown")
    relative_path = repo_spec.get("path", ".")
    try:
        repo_path = resolve_repo_path(relative_path, must_exist=True)
    except (ValueError, OSError) as exc:
        return {
            "id": repo_id,
            "label": repo_spec.get("label", repo_id),
            "path": relative_path,
            "available": False,
            "error": str(exc),
        }

    branch, branch_error = _run_git(repo_path, ["branch", "--show-current"])
    if repo_spec.get("scan_tracked_changes", True):
        status, status_error = _run_git(
            repo_path,
            ["status", "--porcelain=v1", "--untracked-files=no"],
            timeout=1.5,
        )
    else:
        status = ""
        status_error = "tracked working-tree scan disabled for this large repository"
    commit, commit_error = _run_git(
        repo_path,
        ["log", "-1", "--format=%H%x1f%aI%x1f%s"],
    )
    error = branch_error or commit_error
    if error:
        return {
            "id": repo_id,
            "label": repo_spec.get("label", repo_id),
            "path": relative_path,
            "available": False,
            "error": error,
        }

    dirty_lines = [line for line in (status or "").splitlines() if line.strip()]
    commit_parts = (commit or "").split("\x1f", 2)
    return {
        "id": repo_id,
        "label": repo_spec.get("label", repo_id),
        "path": relative_path,
        "available": True,
        "branch": branch or "detached",
        "dirty": bool(dirty_lines),
        "dirty_count": len(dirty_lines),
        "dirty_available": status_error is None,
        "dirty_probe_note": status_error,
        "untracked_scanned": False,
        "last_commit_sha": commit_parts[0] if commit_parts else None,
        "last_commit_at": commit_parts[1] if len(commit_parts) > 1 else None,
        "last_commit_subject": commit_parts[2] if len(commit_parts) > 2 else None,
        "error": None,
    }


def collect_source_catalog(state: dict[str, Any], now: datetime) -> list[dict[str, Any]]:
    refs: dict[str, set[str]] = {}

    def register(path: Any, owner: str) -> None:
        if isinstance(path, str) and path.strip():
            refs.setdefault(path, set()).add(owner)

    for lane in state.get("lanes", []):
        register(lane.get("source_ref"), f"lane:{lane.get('id', 'unknown')}")
    for project in state.get("projects", []):
        for path in project.get("source_refs", []):
            register(path, f"project:{project.get('id', 'unknown')}")
        for milestone in project.get("milestones", []):
            for path in milestone.get("evidence_refs", []):
                register(path, f"milestone:{project.get('id', 'unknown')}:{milestone.get('id', 'unknown')}")
    for decision in state.get("decisions", []):
        for path in decision.get("source_refs", []):
            register(path, f"decision:{decision.get('id', 'unknown')}")
    for execution in state.get("executions", []):
        for path in execution.get("evidence_refs", []):
            register(path, f"execution:{execution.get('id', 'unknown')}")

    catalog = []
    for path in sorted(refs):
        item = probe_repo_path(path, now)
        item["used_by"] = sorted(refs[path])
        catalog.append(item)
    return catalog


def repo_identity() -> dict[str, str]:
    return {
        "name": "IDOL",
        "root": str(IDOL_REPO_ROOT),
        "source_mode": "read_only",
    }
