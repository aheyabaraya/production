"""Safe, value-free credential presence contracts for platform runners.

This module may read local credential files internally for an authenticated
operation, but every public status object contains only paths, field names, and
booleans. It never prints, logs, hashes, or returns credential values.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
SECRETS_ROOT = ROOT / ".runtime" / "secrets"
PLATFORMS = ("x", "tiktok", "youtube")
X_POST_RUNTIME_SCOPES = ("tweet.write", "media.write", "users.read")
X_METRIC_RUNTIME_SCOPES = ("tweet.read",)
X_STATUS_SCOPES = X_POST_RUNTIME_SCOPES + X_METRIC_RUNTIME_SCOPES + ("offline.access",)
TIKTOK_UPLOAD_SCOPE = "video.upload"
TIKTOK_METRIC_SCOPE = "video.list"
YOUTUBE_METRIC_SCOPES = (
    "https://www.googleapis.com/auth/youtube.readonly",
    "https://www.googleapis.com/auth/yt-analytics.readonly",
)


def load_env(path: Path) -> dict[str, str]:
    """Load a dotenv-like file for internal use without shell evaluation."""

    values: dict[str, str] = {}
    if not path.is_file():
        return values
    for raw in path.read_text(encoding="utf-8", errors="ignore").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.removeprefix("export ").strip()
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
            value = value[1:-1]
        values[key] = value
    return values


def _json_file(path: Path) -> tuple[dict[str, Any], bool]:
    if not path.is_file():
        return {}, False
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError):
        return {}, False
    return (value, True) if isinstance(value, dict) else ({}, False)


def _relative(root: Path, path: Path) -> str:
    try:
        return path.resolve().relative_to(root.resolve()).as_posix()
    except ValueError:
        return str(path)


def _present(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def _scope_set(value: Any) -> set[str]:
    return {
        item.strip()
        for item in str(value or "").replace(",", " ").split()
        if item.strip()
    }


def _nested(data: dict[str, Any], *keys: str) -> Any:
    current: Any = data
    for key in keys:
        if not isinstance(current, dict):
            return ""
        current = current.get(key, "")
    return current


def _x_status(root: Path) -> dict[str, Any]:
    path = root / ".runtime" / "secrets" / "x.env"
    env = load_env(path)
    field_names = (
        "X_OAUTH2_CLIENT_ID",
        "X_OAUTH2_CLIENT_SECRET",
        "X_OAUTH2_ACCESS_TOKEN",
        "X_OAUTH2_REFRESH_TOKEN",
        "X_OAUTH2_REDIRECT_URI",
        "X_OAUTH2_SCOPES",
    )
    fields = {name: _present(env.get(name)) for name in field_names}
    scopes = _scope_set(env.get("X_OAUTH2_SCOPES") or env.get("X_OAUTH2_SCOPE"))
    scope_presence = {scope: scope in scopes for scope in X_STATUS_SCOPES}
    return {
        "mode": "oauth2_user_regular_api",
        "source_paths": [_relative(root, path)],
        "fields": fields,
        "scopes": scope_presence,
        "ready_for_runtime_post": fields["X_OAUTH2_ACCESS_TOKEN"]
        and all(scope_presence[scope] for scope in X_POST_RUNTIME_SCOPES),
        "ready_for_runtime_metrics": fields["X_OAUTH2_ACCESS_TOKEN"]
        and all(scope_presence[scope] for scope in X_METRIC_RUNTIME_SCOPES),
        "ready_for_reauth": fields["X_OAUTH2_CLIENT_ID"] and fields["X_OAUTH2_REDIRECT_URI"] and fields["X_OAUTH2_SCOPES"],
        "ready_for_refresh": fields["X_OAUTH2_CLIENT_ID"] and fields["X_OAUTH2_REFRESH_TOKEN"],
    }


def _tiktok_status(root: Path) -> dict[str, Any]:
    env_path = root / ".runtime" / "secrets" / "tiktok.env"
    token_path = root / ".runtime" / "secrets" / "tiktok-token.json"
    env = load_env(env_path)
    token, token_valid = _json_file(token_path)
    env_fields = {
        name: _present(env.get(name))
        for name in (
            "TIKTOK_CLIENT_KEY",
            "TIKTOK_CLIENT_SECRET",
            "TIKTOK_REDIRECT_URI",
            "TIKTOK_SCOPES",
        )
    }
    configured_scopes = _scope_set(env.get("TIKTOK_SCOPES"))
    granted_scopes = _scope_set(token.get("scope"))
    token_fields = {
        "access_token": _present(token.get("access_token")),
        "refresh_token": _present(token.get("refresh_token")),
    }
    client_ready = env_fields["TIKTOK_CLIENT_KEY"] and env_fields["TIKTOK_CLIENT_SECRET"]
    return {
        "mode": "oauth2_user_upload",
        "source_paths": [_relative(root, env_path), _relative(root, token_path)],
        "env_fields": env_fields,
        "scopes": {
            "configured_video.upload": TIKTOK_UPLOAD_SCOPE in configured_scopes,
            "granted_video.upload": TIKTOK_UPLOAD_SCOPE in granted_scopes,
            "configured_video.list": TIKTOK_METRIC_SCOPE in configured_scopes,
            "granted_video.list": TIKTOK_METRIC_SCOPE in granted_scopes,
        },
        "token_file_valid": token_valid,
        "token_fields": token_fields,
        "ready_for_runtime_upload": client_ready and token_fields["access_token"],
        "ready_for_runtime_metrics": client_ready
        and token_fields["access_token"]
        and TIKTOK_METRIC_SCOPE in configured_scopes
        and TIKTOK_METRIC_SCOPE in granted_scopes,
        "ready_for_reauth": client_ready
        and env_fields["TIKTOK_REDIRECT_URI"]
        and env_fields["TIKTOK_SCOPES"],
        "ready_for_refresh": client_ready and token_fields["refresh_token"],
        "setup_required": not client_ready,
    }


def _youtube_status(root: Path) -> dict[str, Any]:
    client_path = root / ".runtime" / "secrets" / "youtube-client-secret.json"
    token_path = root / ".runtime" / "secrets" / "youtube-token.json"
    client, client_valid = _json_file(client_path)
    token, token_valid = _json_file(token_path)
    client_root = client.get("installed") or client.get("web") or {}
    client_fields = {
        "client_id": _present(client_root.get("client_id")),
        "client_secret": _present(client_root.get("client_secret")),
    }
    token_fields = {
        "access_token": _present(token.get("access_token")),
        "refresh_token": _present(token.get("refresh_token")),
    }
    granted_scopes = _scope_set(token.get("scope"))
    return {
        "mode": "oauth2_user_upload",
        "source_paths": [_relative(root, client_path), _relative(root, token_path)],
        "client_file_valid": client_valid,
        "client_fields": client_fields,
        "token_file_valid": token_valid,
        "token_fields": token_fields,
        "scopes": {scope: scope in granted_scopes for scope in YOUTUBE_METRIC_SCOPES},
        "ready_for_runtime_upload": token_fields["access_token"],
        "ready_for_runtime_metrics": token_fields["access_token"]
        and all(scope in granted_scopes for scope in YOUTUBE_METRIC_SCOPES),
        "ready_for_refresh": all(client_fields.values()) and token_fields["refresh_token"],
    }


def status_for_platform(platform: str, root: Path = ROOT) -> dict[str, Any]:
    """Return only non-sensitive credential state for one platform."""

    root = root.resolve()
    if platform == "x":
        return _x_status(root)
    if platform == "tiktok":
        return _tiktok_status(root)
    if platform == "youtube":
        return _youtube_status(root)
    raise ValueError(f"unsupported platform: {platform}")


def all_status(root: Path = ROOT, platforms: tuple[str, ...] = PLATFORMS) -> dict[str, Any]:
    """Return a value-free status document for the selected platforms."""

    root = root.resolve()
    return {
        "schema_version": "idol_platform_credentials.v1",
        "secret_values_printed": False,
        "platforms": {platform: status_for_platform(platform, root) for platform in platforms},
    }
