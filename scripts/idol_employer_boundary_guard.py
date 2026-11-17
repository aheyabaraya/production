#!/usr/bin/env python3
"""Fail-closed IDOL / employer-work boundary guard.

Blocks HAXAI inbound and employer-named paths/content outside the allowlisted
boundary files. Does not write inbound prompt or file bodies anywhere.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Any


REASON = (
    "IDOL employer boundary: this repository is independent studio work and "
    "is unrelated to employer AX/content-marketing work. HAXAI inbound is "
    "ignored. Do not search, open, import, cite, or execute it."
)
FREEZE_REASON = (
    "IDOL side-project IP freeze: business-marketing and CF operations are "
    "closed. Keep the bytes as personal side-project IP. Analysis and "
    "extensibility remain. AX-related X posting is paused."
)
AX_POST_REASON = (
    "AX-related X posting is paused under the employment boundary. "
    "Do not draft, schedule, or publish AX-topic posts on X."
)

TOKEN_RE = re.compile(r"(?i)(?:\bhaxai\b|hax\.ai|hax[\s._-]+ai\b)")
PATH_TOKEN_RE = re.compile(r"(?i)haxai|hax\.ai|hax[_-]+ai")
MAINTENANCE_RE = re.compile(
    r"(?is)(?:"
    r"repository-employment-boundary"
    r"|employment boundary"
    r"|side-project-ip-freeze"
    r"|(?:\bidol\b|아이돌).{0,80}(?:boundary|보호|무관|out of scope)"
    r"|(?:boundary|보호|무관|out of scope).{0,80}(?:\bidol\b|아이돌)"
    r"|겸업|확장성|닫을|스탑|personal side-project"
    r")"
)
FREEZE_MAINTENANCE_RE = re.compile(
    r"(?is)(?:side-project-ip-freeze|employment boundary|"
    r"repository-employment-boundary|겸업|확장성|닫을|스탑|"
    r"pause|freeze|personal side-project|개인 사이드)"
)
AX_POST_RE = re.compile(
    r"(?is)(?:\bax\b|에이엑스).{0,80}"
    r"(?:tweet|트윗|스레드|thread|(?:x|twitter).{0,20}(?:post|올려|게시)|올려.{0,20}(?:x|트윗))"
    r"|(?:tweet|트윗|스레드|(?:x|twitter).{0,20}(?:post|올려|게시)).{0,80}"
    r"(?:\bax\b|에이엑스)"
)
CF_LAUNCH_RE = re.compile(
    r"(?is)(?:\bcf-code\b|cf 광고|cf run|cf-code).{0,40}"
    r"(?:시작|만들어|생성|찍어|실행|resume|generate)"
)
WRITE_TOOL_RE = re.compile(
    r"(?i)^(?:write|edit|search_replace|strreplace|delete|apply_patch)$"
)
SOCIAL_PUBLISH_RE = re.compile(
    r"(?i)idol_social_release_sync|idol_platform_draft_upload|"
    r"idol_social_public_closeout"
)
CF_OPS_WRITE_PREFIXES = (
    "cf/runs/",
    "cf/finals/",
    "cf/generations/",
    "cf/output/",
)
CF_FREEZE_WRITE_ALLOW = frozenset(
    {
        "cf/AGENTS.md",
        "cf/README.md",
        "cf/automation/cf-current-run.yaml",
        "cf/automation/cf-surface-version-registry.yaml",
    }
)
LOCAL_SEARCH_RE = re.compile(
    r"(?i)(?:^|[;&|\n]\s*)(?:rg|grep|ag|ack|ripgrep)\b"
)
NETWORK_RE = re.compile(
    r"(?i)\b(?:curl|wget|ssh|scp|rsync|gh|open|osascript|httpx|aria2c)\b"
)
WRITE_RE = re.compile(
    r"(?i)(?:^|[;&|\n]\s*)(?:cp|mv|install|tee|dd)\b|(?:>>|>)"
)

ALLOWLIST = frozenset(
    {
        "AGENTS.md",
        "README.md",
        "CHANGELOG.md",
        "wiki/repository-employment-boundary.md",
        "wiki/INDEX.md",
        "wiki/decision-log.md",
        ".grok/config.toml",
        ".grok/hooks/README.md",
        ".grok/hooks/employer-boundary-guard.json",
        ".cursor/hooks.json",
        ".githooks/pre-commit",
        "scripts/idol_employer_boundary_guard.py",
        "scripts/INDEX.md",
        "scripts/registry/validators.md",
        "automation/idol-script-registry.yaml",
        "automation/harness-surface-version-registry.yaml",
        "automation/side-project-ip-freeze.yaml",
        "cf/AGENTS.md",
        "cf/README.md",
        "cf/automation/cf-current-run.yaml",
        "cf/automation/cf-surface-version-registry.yaml",
        "business-marketing/AGENTS.md",
        "business-marketing/README.md",
        "wiki/social-automation-system.md",
        "wiki/platform-credential-and-draft-upload-ops.md",
    }
)

EXTERNAL_TOOLS = frozenset(
    {
        "web_search",
        "web_fetch",
        "open_page",
        "open_page_with_find",
        "x_user_search",
        "x_semantic_search",
        "x_keyword_search",
        "x_thread_fetch",
        "use_tool",
        "search_tool",
        "image_gen",
        "image_edit",
        "image_to_video",
        "reference_to_video",
        "google_drive",
        "tasks",
    }
)

PATH_KEYS = frozenset(
    {
        "path",
        "paths",
        "target_file",
        "file_path",
        "file",
        "filename",
        "output",
        "output_path",
        "script_path",
        "cwd",
        "url",
    }
)
COMMAND_PATH_RE = re.compile(
    r"(?:(?:\./)?[A-Za-z0-9._/-]+\.(?:md|py|json|ya?ml|toml|js|sh|txt|html)|"
    r"(?:[A-Za-z0-9._-]+/){1,}[A-Za-z0-9._-]+)"
)
PROMPT_EVENTS = frozenset({"userpromptsubmit", "beforesubmitprompt"})

SCAN_BYTES = 262144


def _workspace_root() -> Path:
    env = os.environ.get("GROK_WORKSPACE_ROOT") or os.environ.get("IDOL_ROOT")
    if env:
        return Path(env).expanduser().resolve()
    return Path(__file__).resolve().parents[1]


def contains_token(text: str) -> bool:
    return bool(TOKEN_RE.search(text or ""))


def flatten(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, str):
        return value
    if isinstance(value, bytes):
        return value.decode("utf-8", "replace")
    if isinstance(value, dict):
        return "\n".join(flatten(item) for item in value.values())
    if isinstance(value, (list, tuple)):
        return "\n".join(flatten(item) for item in value)
    return str(value)


def rel_path(raw: str, root: Path) -> str | None:
    if not raw or not isinstance(raw, str):
        return None
    text = raw.strip().strip("\"'")
    if not text or text.startswith("-"):
        return None
    try:
        path = Path(text).expanduser()
        if not path.is_absolute():
            path = (root / path).resolve()
        else:
            path = path.resolve()
    except (OSError, RuntimeError):
        return text.replace("\\", "/")
    try:
        return path.relative_to(root).as_posix()
    except ValueError:
        return path.as_posix()


def extract_command_paths(command: str, root: Path) -> list[str]:
    found: list[str] = []
    for match in COMMAND_PATH_RE.finditer(command or ""):
        token = match.group(0)
        if PATH_TOKEN_RE.search(Path(token).name) and not is_allowlisted(token):
            # Search patterns are not paths; real excluded filenames still count.
            if "/" not in token and "\\" not in token:
                continue
        rel = rel_path(token, root)
        if rel:
            found.append(rel)
    return found


def extract_paths(value: Any, root: Path, acc: list[str] | None = None) -> list[str]:
    found = acc if acc is not None else []
    if isinstance(value, dict):
        for key, item in value.items():
            key_name = str(key)
            if key_name == "command" and isinstance(item, str):
                found.extend(extract_command_paths(item, root))
                continue
            if key_name in PATH_KEYS and isinstance(item, str):
                rel = rel_path(item, root)
                if rel:
                    found.append(rel)
            extract_paths(item, root, found)
    elif isinstance(value, (list, tuple)):
        for item in value:
            extract_paths(item, root, found)
    return found


def is_allowlisted(rel: str) -> bool:
    norm = rel.replace("\\", "/").lstrip("./")
    return norm in ALLOWLIST


def path_is_excluded_name(rel: str) -> bool:
    name = Path(rel).name
    return bool(PATH_TOKEN_RE.search(rel)) or bool(PATH_TOKEN_RE.search(name))


def is_external_tool(name: str) -> bool:
    lowered = (name or "").lower()
    if lowered in EXTERNAL_TOOLS:
        return True
    if "google_drive" in lowered or lowered.startswith("mcp"):
        return True
    return False


def is_local_repo_search(command: str) -> bool:
    if not LOCAL_SEARCH_RE.search(command or ""):
        return False
    if NETWORK_RE.search(command or ""):
        return False
    if WRITE_RE.search(command or ""):
        return False
    return True


def file_has_token(rel: str, root: Path) -> bool:
    path = root / rel
    if not path.is_file():
        return False
    try:
        data = path.read_bytes()[:SCAN_BYTES]
    except OSError:
        return False
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        text = data.decode("latin-1", "replace")
    return contains_token(text)


def prompt_is_employer_work(text: str) -> bool:
    if not contains_token(text):
        return False
    return not MAINTENANCE_RE.search(text)


def is_freeze_maintenance(text: str) -> bool:
    return bool(FREEZE_MAINTENANCE_RE.search(text or ""))


def is_ax_x_post_request(text: str) -> bool:
    if is_freeze_maintenance(text):
        return False
    return bool(AX_POST_RE.search(text or ""))


def is_cf_ops_write(tool: str, paths: list[str], command: str) -> bool:
    hay_parts: list[str] = []
    for path in paths:
        norm = path.replace("\\", "/").lstrip("./")
        if norm in CF_FREEZE_WRITE_ALLOW:
            continue
        hay_parts.append(norm)
    hay = "\n".join(hay_parts) + "\n" + (command or "")
    hay = hay.replace("\\", "/")
    if not any(prefix in hay for prefix in CF_OPS_WRITE_PREFIXES):
        return False
    if WRITE_TOOL_RE.match(tool or ""):
        return True
    if command and WRITE_RE.search(command):
        return True
    return False


def decide_payload(payload: dict[str, Any], root: Path) -> tuple[bool, str]:
    event = str(
        payload.get("hookEventName")
        or payload.get("hook_event_name")
        or os.environ.get("GROK_HOOK_EVENT")
        or ""
    )
    tool = str(payload.get("toolName") or payload.get("tool_name") or "")
    tool_input = payload.get("toolInput")
    if tool_input is None:
        tool_input = payload.get("tool_input")
    blob = "\n".join(
        [
            flatten(payload.get("prompt")),
            flatten(payload.get("text")),
            flatten(payload.get("query")),
            flatten(tool_input),
            flatten(tool),
        ]
    )
    paths = extract_paths(tool_input, root)
    command = ""
    if isinstance(tool_input, dict):
        command = str(tool_input.get("command") or "")
        paths.extend(extract_paths(command, root))

    prompt_text = flatten(payload.get("prompt")) or flatten(payload.get("text"))
    event_l = event.lower()
    if event_l in PROMPT_EVENTS or (prompt_text and not tool):
        if prompt_is_employer_work(prompt_text or blob):
            return False, REASON
        if is_ax_x_post_request(prompt_text or blob):
            return False, AX_POST_REASON
        if CF_LAUNCH_RE.search(prompt_text or blob) and not is_freeze_maintenance(
            prompt_text or blob
        ):
            return False, FREEZE_REASON
        if event_l in PROMPT_EVENTS:
            return True, "allow"

    if is_cf_ops_write(tool, paths, command):
        return False, FREEZE_REASON
    if command and SOCIAL_PUBLISH_RE.search(command) and is_ax_x_post_request(blob):
        return False, AX_POST_REASON

    if any(path_is_excluded_name(path) and not is_allowlisted(path) for path in paths):
        return False, REASON

    if is_external_tool(tool) and contains_token(blob):
        return False, REASON

    if command and contains_token(command):
        if NETWORK_RE.search(command) or WRITE_RE.search(command):
            return False, REASON
        if not is_local_repo_search(command):
            non_allow = [path for path in paths if not is_allowlisted(path)]
            if non_allow or not paths:
                return False, REASON

    if contains_token(blob):
        if paths and all(is_allowlisted(path) for path in paths):
            return True, "allow"
        if command and is_local_repo_search(command):
            return True, "allow"
        if not paths and not command and not is_external_tool(tool):
            # Tool payload names the excluded org but is not a local allowlisted
            # edit or a repo integrity scan.
            return False, REASON
        for path in paths:
            if not is_allowlisted(path) and (
                path_is_excluded_name(path) or file_has_token(path, root)
            ):
                return False, REASON
            if not is_allowlisted(path) and contains_token(blob):
                return False, REASON

    for path in paths:
        if is_allowlisted(path):
            continue
        if path_is_excluded_name(path) or file_has_token(path, root):
            return False, REASON

    return True, "allow"


def grok_response(allowed: bool) -> dict[str, Any]:
    if allowed:
        return {"decision": "allow"}
    return {"decision": "deny", "reason": REASON}


def cursor_response(allowed: bool, event: str) -> dict[str, Any]:
    if event == "preToolUse":
        if allowed:
            return {"permission": "allow"}
        return {
            "permission": "deny",
            "user_message": REASON,
            "agent_message": REASON,
        }
    if event in {"afterAgentResponse", "stop", "sessionStart"}:
        return {}
    if allowed:
        return {"continue": True}
    return {"continue": False, "user_message": REASON}


def git_index_scan(root: Path) -> tuple[bool, str]:
    listing = subprocess.run(
        ["git", "diff", "--cached", "--name-only", "-z"],
        cwd=root,
        capture_output=True,
        check=False,
    )
    if listing.returncode != 0:
        return False, "IDOL employer boundary: unable to read the Git index."
    names = [item for item in listing.stdout.decode("utf-8", "replace").split("\0") if item]
    for rel in names:
        norm = rel.replace("\\", "/")
        if path_is_excluded_name(norm) and not is_allowlisted(norm):
            return False, REASON
        if is_allowlisted(norm):
            continue
        shown = subprocess.run(
            ["git", "show", f":{rel}"],
            cwd=root,
            capture_output=True,
            check=False,
        )
        if shown.returncode != 0:
            continue
        body = shown.stdout[:SCAN_BYTES]
        try:
            text = body.decode("utf-8")
        except UnicodeDecodeError:
            text = body.decode("latin-1", "replace")
        if contains_token(text):
            return False, REASON
    return True, "allow"


def emit(payload: dict[str, Any], allowed: bool) -> int:
    event = str(payload.get("hookEventName") or payload.get("hook_event_name") or "")
    grok_event = os.environ.get("GROK_HOOK_EVENT", "")
    if "hookEventName" in payload or grok_event or event in {
        "PreToolUse",
        "UserPromptSubmit",
        "SessionStart",
    }:
        sys.stdout.write(json.dumps(grok_response(allowed)))
        return 0 if allowed else 2
    sys.stdout.write(json.dumps(cursor_response(allowed, event)))
    return 0


def selftest() -> int:
    root = _workspace_root()
    cases: list[tuple[str, dict[str, Any], bool]] = [
        (
            "bash_ls",
            {
                "hookEventName": "PreToolUse",
                "toolName": "Bash",
                "toolInput": {"command": "ls"},
            },
            True,
        ),
        (
            "web_search_excluded",
            {
                "hookEventName": "PreToolUse",
                "toolName": "web_search",
                "toolInput": {"query": "haxai campaign copy"},
            },
            False,
        ),
        (
            "write_allowlisted",
            {
                "hookEventName": "PreToolUse",
                "toolName": "Write",
                "toolInput": {
                    "file_path": str(root / "wiki/repository-employment-boundary.md"),
                    "content": "HAXAI inbound is ignored.",
                },
            },
            True,
        ),
        (
            "write_new_notes",
            {
                "hookEventName": "PreToolUse",
                "toolName": "Write",
                "toolInput": {
                    "file_path": str(root / "notes.md"),
                    "content": "haxai weekly content calendar",
                },
            },
            False,
        ),
        (
            "local_rg",
            {
                "hookEventName": "PreToolUse",
                "toolName": "Bash",
                "toolInput": {"command": "rg -n haxai wiki/repository-employment-boundary.md"},
            },
            True,
        ),
        (
            "cursor_employer_prompt",
            {
                "hook_event_name": "beforeSubmitPrompt",
                "prompt": "haxai 블로그 초안 작성해줘",
            },
            False,
        ),
        (
            "cursor_boundary_prompt",
            {
                "hook_event_name": "beforeSubmitPrompt",
                "prompt": "아이돌 레포 보호: haxai 관련은 무시하고 무관하다고 기록한다",
            },
            True,
        ),
        (
            "drive_query",
            {
                "hookEventName": "PreToolUse",
                "toolName": "use_tool",
                "toolInput": {
                    "tool_name": "google_drive__search",
                    "tool_input": {"query": "haxai weekly brief"},
                },
            },
            False,
        ),
        (
            "copy_excluded_file",
            {
                "hookEventName": "PreToolUse",
                "toolName": "Bash",
                "toolInput": {"command": "cp ./haxai-brief.md /tmp/out.md"},
            },
            False,
        ),
        (
            "cf_run_write",
            {
                "hookEventName": "PreToolUse",
                "toolName": "Write",
                "toolInput": {
                    "file_path": str(root / "cf/runs/CF_NEW/CF00.yaml"),
                    "content": "new commercial run",
                },
            },
            False,
        ),
        (
            "cf_agents_write",
            {
                "hookEventName": "PreToolUse",
                "toolName": "Write",
                "toolInput": {
                    "file_path": str(root / "cf/AGENTS.md"),
                    "content": "Operational freeze banner",
                },
            },
            True,
        ),
        (
            "ax_x_post_prompt",
            {
                "hook_event_name": "beforeSubmitPrompt",
                "prompt": "X에 AX 스레드 올려줘",
            },
            False,
        ),
        (
            "freeze_prompt",
            {
                "hook_event_name": "beforeSubmitPrompt",
                "prompt": "business-marketing과 cf는 닫을거야. 확장성은 두고 AX는 X에 스탑",
            },
            True,
        ),
    ]
    failed = 0
    for name, payload, expect_allow in cases:
        allowed, _reason = decide_payload(payload, root)
        ok = allowed is expect_allow
        if not ok:
            failed += 1
        print(f"{'PASS' if ok else 'FAIL'} {name}: allowed={allowed} expect={expect_allow}")
    return 1 if failed else 0


def main(argv: list[str]) -> int:
    if "--selftest" in argv:
        return selftest()
    root = _workspace_root()
    if "--git-index" in argv:
        allowed, _reason = git_index_scan(root)
        if not allowed:
            sys.stderr.write(REASON + "\n")
            return 1
        return 0
    try:
        raw = sys.stdin.read()
        payload = json.loads(raw) if raw.strip() else {}
        if not isinstance(payload, dict):
            payload = {}
    except (OSError, json.JSONDecodeError):
        payload = {}
    allowed, _reason = decide_payload(payload, root)
    return emit(payload, allowed)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
