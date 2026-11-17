from __future__ import annotations

from pathlib import Path


TOOL_ROOT = Path(__file__).resolve().parent.parent
IDOL_REPO_ROOT = TOOL_ROOT.parent.parent
DATA_PATH = TOOL_ROOT / "data" / "tracker.json"
WEB_ROOT = TOOL_ROOT / "web"


def resolve_repo_path(relative_path: str, *, must_exist: bool = False) -> Path:
    """Resolve an IDOL-repo-relative path without allowing path escape."""

    if not isinstance(relative_path, str) or not relative_path.strip():
        raise ValueError("source path must be a non-empty repo-relative string")

    candidate = Path(relative_path)
    if candidate.is_absolute():
        raise ValueError("absolute source paths are not allowed")

    resolved = (IDOL_REPO_ROOT / candidate).resolve()
    try:
        resolved.relative_to(IDOL_REPO_ROOT.resolve())
    except ValueError as exc:
        raise ValueError("source path escapes the IDOL repository") from exc

    if must_exist and not resolved.exists():
        raise FileNotFoundError(relative_path)
    return resolved
