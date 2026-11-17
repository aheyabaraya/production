from __future__ import annotations

import argparse
import json
import mimetypes
import sys
from datetime import datetime
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import unquote, urlparse

from .actions import TrackerActionError, apply_action
from .derive import derive_state
from .paths import WEB_ROOT
from .store import TrackerStore
from .validation import TrackerValidationError


MAX_BODY_BYTES = 1_000_000


class TrackerHTTPServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, server_address: tuple[str, int], handler_class: type[BaseHTTPRequestHandler], store: TrackerStore):
        super().__init__(server_address, handler_class)
        self.store = store


class TrackerHandler(BaseHTTPRequestHandler):
    server_version = "IDOLOpsTracker/0.1"

    @property
    def tracker_server(self) -> TrackerHTTPServer:
        return self.server  # type: ignore[return-value]

    def log_message(self, format_string: str, *args: Any) -> None:
        sys.stderr.write(f"[idol-ops-tracker] {self.address_string()} {format_string % args}\n")

    def _send_json(self, payload: Any, status: HTTPStatus = HTTPStatus.OK) -> None:
        body = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(body)

    def _read_json(self) -> dict[str, Any]:
        length_header = self.headers.get("Content-Length")
        if not length_header:
            raise TrackerActionError("request body is required")
        try:
            length = int(length_header)
        except ValueError as exc:
            raise TrackerActionError("invalid Content-Length") from exc
        if length < 1 or length > MAX_BODY_BYTES:
            raise TrackerActionError("request body is too large")
        raw = self.rfile.read(length)
        try:
            payload = json.loads(raw.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise TrackerActionError("request body must be valid UTF-8 JSON") from exc
        if not isinstance(payload, dict):
            raise TrackerActionError("request JSON must be an object")
        return payload

    def _serve_static(self, request_path: str) -> None:
        relative = "index.html" if request_path in {"", "/"} else unquote(request_path.lstrip("/"))
        target = (WEB_ROOT / relative).resolve()
        try:
            target.relative_to(WEB_ROOT.resolve())
        except ValueError:
            self.send_error(HTTPStatus.NOT_FOUND)
            return
        if not target.is_file():
            self.send_error(HTTPStatus.NOT_FOUND)
            return
        body = target.read_bytes()
        content_type = mimetypes.guess_type(target.name)[0] or "application/octet-stream"
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", f"{content_type}; charset=utf-8" if content_type.startswith("text/") else content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Content-Security-Policy", "default-src 'self'; style-src 'self' 'unsafe-inline'; script-src 'self'; img-src 'self' data:; connect-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)
        if parsed.path == "/api/health":
            self._send_json({"ok": True, "service": "idol-ops-tracker", "source_mode": "read_only"})
            return
        if parsed.path in {"/api/state", "/api/export"}:
            try:
                state = self.tracker_server.store.load()
                self._send_json(derive_state(state))
            except (OSError, json.JSONDecodeError, TrackerValidationError) as exc:
                details = exc.errors if isinstance(exc, TrackerValidationError) else [str(exc)]
                self._send_json({"ok": False, "error": "tracker_state_invalid", "details": details}, HTTPStatus.INTERNAL_SERVER_ERROR)
            return
        self._serve_static(parsed.path)

    def do_POST(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)
        if parsed.path != "/api/action":
            self.send_error(HTTPStatus.NOT_FOUND)
            return
        try:
            payload = self._read_json()
            now = datetime.now().astimezone()
            state = self.tracker_server.store.load()
            updated = apply_action(state, payload, now)
            self.tracker_server.store.save(updated)
            self._send_json({"ok": True, "state": derive_state(updated, now)})
        except (TrackerActionError, TrackerValidationError, ValueError) as exc:
            details = exc.errors if isinstance(exc, TrackerValidationError) else [str(exc)]
            self._send_json({"ok": False, "error": "action_rejected", "details": details}, HTTPStatus.BAD_REQUEST)
        except (OSError, json.JSONDecodeError) as exc:
            self._send_json({"ok": False, "error": "tracker_write_failed", "details": [str(exc)]}, HTTPStatus.INTERNAL_SERVER_ERROR)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Run the local-only IDOL Ops Tracker")
    parser.add_argument("--host", default="127.0.0.1", help="loopback host only (default: 127.0.0.1)")
    parser.add_argument("--port", type=int, default=4177, help="local port (default: 4177)")
    parser.add_argument("--check", action="store_true", help="validate data and source probes, then exit")
    parser.add_argument("--json", action="store_true", help="with --check, print the full derived JSON")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    if args.host not in {"127.0.0.1", "localhost", "::1"}:
        print("Refusing non-loopback host. This tracker is local-only.", file=sys.stderr)
        return 2
    if args.port < 1 or args.port > 65535:
        print("Port must be between 1 and 65535.", file=sys.stderr)
        return 2

    store = TrackerStore()
    try:
        state = store.load()
        derived = derive_state(state)
    except (OSError, json.JSONDecodeError, TrackerValidationError) as exc:
        details = exc.errors if isinstance(exc, TrackerValidationError) else [str(exc)]
        print(json.dumps({"ok": False, "details": details}, ensure_ascii=False, indent=2), file=sys.stderr)
        return 1

    if args.check:
        payload = derived if args.json else {
            "ok": True,
            "revision": state["meta"]["revision"],
            "summary": derived["derived"]["summary"],
            "source_mode": derived["derived"]["repo"]["source_mode"],
        }
        print(json.dumps(payload, ensure_ascii=False, indent=2))
        return 0

    server = TrackerHTTPServer((args.host, args.port), TrackerHandler, store)
    print(f"IDOL Ops Tracker: http://{args.host}:{args.port}")
    print("Source boundary: IDOL repo read-only; writes limited to tools/idol-ops-tracker/data/tracker.json")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopping IDOL Ops Tracker")
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
