#!/usr/bin/env python3
"""Store Vercel Web Analytics credentials through a local-only setup form."""

from __future__ import annotations

import argparse
import html
import os
import secrets
import time
import webbrowser
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from typing import Any
from urllib import parse

from lib.idol_platform_credentials import load_env


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_ENV = ROOT / ".runtime" / "secrets" / "vercel.env"


class SetupError(RuntimeError):
    """A safe setup failure that contains no secret value."""


class ReusableHTTPServer(HTTPServer):
    allow_reuse_address = True


def replace_env_values(path: Path, updates: dict[str, str]) -> None:
    original = path.read_text(encoding="utf-8") if path.exists() else ""
    output: list[str] = []
    seen: set[str] = set()
    for line in original.splitlines():
        stripped = line.strip()
        key = stripped.split("=", 1)[0].removeprefix("export ").strip() if "=" in stripped else ""
        if key in updates:
            output.append(f"{key}={updates[key]}")
            seen.add(key)
        else:
            output.append(line)
    for key, value in updates.items():
        if key not in seen:
            output.append(f"{key}={value}")
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.setup-{secrets.token_hex(8)}.tmp")
    try:
        temporary.write_text("\n".join(output).rstrip("\n") + "\n", encoding="utf-8")
        os.chmod(temporary, 0o600)
        os.replace(temporary, path)
        os.chmod(path, 0o600)
    finally:
        if temporary.exists():
            temporary.unlink()


def readiness(path: Path) -> dict[str, Any]:
    values = load_env(path)
    return {
        "status": "configured" if values.get("VERCEL_TOKEN", "").strip() and values.get("VERCEL_PROJECT_ID", "").strip() else "setup_required",
        "env_path": str(path),
        "field_presence": {
            "VERCEL_TOKEN": bool(values.get("VERCEL_TOKEN", "").strip()),
            "VERCEL_PROJECT_ID": bool(values.get("VERCEL_PROJECT_ID", "").strip()),
            "VERCEL_TEAM_ID": bool(values.get("VERCEL_TEAM_ID", "").strip()),
            "VERCEL_ANALYTICS_FILTER": bool(values.get("VERCEL_ANALYTICS_FILTER", "").strip()),
        },
        "secret_values_printed": False,
    }


def setup_page(nonce: str) -> bytes:
    token_url = html.escape("https://vercel.com/account/tokens")
    return f"""<!doctype html>
<html lang="ko"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Loom Signal Deck 분석 연결</title>
<style>
body{{font-family:-apple-system,BlinkMacSystemFont,sans-serif;max-width:700px;margin:48px auto;padding:0 20px;line-height:1.55;color:#171717}}
.box{{border:1px solid #ddd;border-radius:16px;padding:24px}} label{{display:block;margin:16px 0 6px;font-weight:650}}
input{{box-sizing:border-box;width:100%;padding:12px;border:1px solid #aaa;border-radius:9px}} button{{margin-top:22px;padding:12px 18px;border:0;border-radius:9px;background:#111;color:#fff;font-weight:700}}
.note{{color:#565656}} code{{word-break:break-all}}
</style><body><h1>Loom Signal Deck 분석 연결</h1><div class="box">
<p>Vercel Web Analytics의 <strong>프로덕션 전체 방문 수</strong>만 수집합니다. 개인·세션·클릭 원문은 저장하지 않습니다.</p>
<ol><li><a href="{token_url}" target="_blank" rel="noreferrer">Vercel Access Tokens</a>에서 읽기 전용으로 사용할 토큰을 만듭니다.</li><li>Vercel 프로젝트 설정에서 프로젝트 ID를 복사합니다.</li><li>아래 <em>이 Mac에서만 열리는 화면</em>에 입력합니다.</li></ol>
<p class="note">토큰은 채팅, 로그, Git에 남지 않고 <code>.runtime/secrets/vercel.env</code>에 권한 0600으로만 저장됩니다.</p>
<form method="post" action="/setup" autocomplete="off"><input type="hidden" name="nonce" value="{html.escape(nonce)}">
<label for="token">Vercel access token</label><input id="token" name="token" type="password" required spellcheck="false">
<label for="project_id">Vercel project ID</label><input id="project_id" name="project_id" required spellcheck="false">
<label for="team_id">Team ID (선택)</label><input id="team_id" name="team_id" spellcheck="false">
<label for="analytics_filter">분석 필터</label><input id="analytics_filter" name="analytics_filter" value="environment eq 'production'" required spellcheck="false">
<button type="submit">로컬에 안전하게 저장</button></form></div></body></html>""".encode("utf-8")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--env", default=str(DEFAULT_ENV))
    parser.add_argument("--status", action="store_true", help="Print value-free setup readiness only.")
    parser.add_argument("--open-browser", action="store_true", help="Open the local-only setup form.")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8768)
    parser.add_argument("--timeout-seconds", type=int, default=600)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    env_path = Path(args.env)
    if args.status:
        import json

        print(json.dumps(readiness(env_path), ensure_ascii=False), flush=True)
        return 0
    if args.host not in {"127.0.0.1", "localhost"}:
        raise SetupError("local setup host must be localhost or 127.0.0.1")
    nonce = secrets.token_urlsafe(32)
    result: dict[str, str] = {}

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, _format: str, *_args: Any) -> None:
            return

        def send_html(self, status: int, payload: bytes) -> None:
            self.send_response(status)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(payload)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(payload)

        def do_GET(self) -> None:
            if parse.urlparse(self.path).path != "/":
                self.send_html(404, b"Not found")
                return
            self.send_html(200, setup_page(nonce))

        def do_POST(self) -> None:
            if parse.urlparse(self.path).path != "/setup":
                self.send_html(404, b"Not found")
                return
            try:
                length = int(self.headers.get("Content-Length") or "0")
            except ValueError:
                length = 0
            if length <= 0 or length > 32768:
                self.send_html(400, b"Invalid form.")
                return
            fields = parse.parse_qs(self.rfile.read(length).decode("utf-8"))
            if fields.get("nonce", [""])[0] != nonce:
                self.send_html(400, b"Setup state mismatch.")
                return
            token = fields.get("token", [""])[0].strip()
            project_id = fields.get("project_id", [""])[0].strip()
            team_id = fields.get("team_id", [""])[0].strip()
            analytics_filter = fields.get("analytics_filter", [""])[0].strip()
            if not token or not project_id or not analytics_filter:
                self.send_html(400, b"Required fields are missing.")
                return
            updates = {
                "VERCEL_TOKEN": token,
                "VERCEL_PROJECT_ID": project_id,
                "VERCEL_TEAM_ID": team_id,
                "VERCEL_ANALYTICS_FILTER": analytics_filter,
            }
            replace_env_values(env_path, updates)
            result["status"] = "saved"
            self.send_html(200, b"Vercel analytics setup saved locally. You can return to Codex.")

    try:
        server = ReusableHTTPServer((args.host, args.port), Handler)
    except OSError as exc:
        raise SetupError(f"unable to start local setup server (errno={exc.errno})") from exc
    server.timeout = 1.0
    url = f"http://{args.host}:{args.port}/"
    import json

    print(json.dumps({"status": "waiting_for_local_setup", "local_entry_url": url, "secret_values_printed": False}, ensure_ascii=False), flush=True)
    if args.open_browser:
        webbrowser.open(url)
    deadline = time.monotonic() + args.timeout_seconds
    while not result and time.monotonic() < deadline:
        server.handle_request()
    server.server_close()
    if result.get("status") != "saved":
        raise SetupError("local_setup_timed_out")
    print(json.dumps(readiness(env_path), ensure_ascii=False), flush=True)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (KeyboardInterrupt, SetupError) as exc:
        import json

        print(json.dumps({"status": "cancelled_or_failed", "reason": str(exc), "secret_values_printed": False}, ensure_ascii=False), flush=True)
        raise SystemExit(1)
