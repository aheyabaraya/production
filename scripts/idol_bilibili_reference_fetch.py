#!/usr/bin/env python3
"""Fetch public Bilibili reference videos through the IDOL video runtime.

This script intentionally uses Bilibili public, non-login endpoints only. It
does not read browser cookies or account state.
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import tempfile
import time
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36"
)


def tool_path(name: str) -> str:
    for prefix in ["/opt/homebrew/bin", "/usr/local/bin"]:
        preferred = Path(prefix) / name
        if preferred.exists():
            return str(preferred)
    found = shutil.which(name)
    if found:
        return found
    raise SystemExit(f"Missing required tool: {name}")


def request_json(url: str, headers: dict[str, str], query: dict[str, Any] | None = None) -> dict[str, Any]:
    if query:
        url = f"{url}?{urllib.parse.urlencode(query)}"
    last_exc: Exception | None = None
    for attempt in range(4):
        try:
            req = urllib.request.Request(url, headers=headers)
            with urllib.request.urlopen(req, timeout=45) as response:
                return json.loads(response.read().decode("utf-8"))
        except Exception as exc:  # noqa: BLE001 - retry public network flakiness
            last_exc = exc
            if attempt == 3:
                break
            time.sleep(1.5 * (attempt + 1))
    raise last_exc or RuntimeError("unknown request_json failure")


def download_file(url: str, out_path: Path, headers: dict[str, str]) -> None:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    last_exc: Exception | None = None
    for attempt in range(4):
        try:
            req = urllib.request.Request(url, headers=headers)
            with urllib.request.urlopen(req, timeout=90) as response, out_path.open("wb") as handle:
                shutil.copyfileobj(response, handle)
            return
        except Exception as exc:  # noqa: BLE001 - retry public network flakiness
            last_exc = exc
            if attempt == 3:
                break
            time.sleep(2.0 * (attempt + 1))
    raise last_exc or RuntimeError("unknown download_file failure")


def run(cmd: list[str]) -> None:
    subprocess.run(cmd, check=True)


def clean_title(value: str) -> str:
    return " ".join(value.replace("\n", " ").split())


def pick_video(play_data: dict[str, Any]) -> dict[str, Any]:
    videos = play_data.get("dash", {}).get("video") or []
    avc = [item for item in videos if str(item.get("codecs", "")).startswith("avc1")]
    candidates = avc or videos
    if not candidates:
        raise ValueError("No video stream found in Bilibili playurl response")
    return max(candidates, key=lambda item: (int(item.get("height") or 0), int(item.get("bandwidth") or 0)))


def pick_audio(play_data: dict[str, Any]) -> dict[str, Any]:
    audios = play_data.get("dash", {}).get("audio") or []
    if not audios:
        raise ValueError("No audio stream found in Bilibili playurl response")
    return max(audios, key=lambda item: int(item.get("bandwidth") or 0))


def fetch_one(bvid: str, slug: str, output_dir: Path, qn: int) -> dict[str, Any]:
    spi_headers = {"User-Agent": USER_AGENT, "Referer": "https://www.bilibili.com/"}
    spi = request_json("https://api.bilibili.com/x/frontend/finger/spi", spi_headers)
    buvid3 = spi["data"]["b_3"]
    buvid4 = spi["data"]["b_4"]
    cookie = f"buvid3={buvid3}; buvid4={buvid4}; CURRENT_FNVAL=4048"

    page_url = f"https://www.bilibili.com/video/{bvid}"
    headers = {
        "User-Agent": USER_AGENT,
        "Referer": page_url,
        "Cookie": cookie,
    }
    view = request_json(
        "https://api.bilibili.com/x/web-interface/view",
        headers,
        {"bvid": bvid},
    )
    if view.get("code") != 0:
        raise ValueError(f"View API failed for {bvid}: {view.get('message')}")
    data = view["data"]
    cid = data["cid"]

    play = request_json(
        "https://api.bilibili.com/x/player/playurl",
        headers,
        {"bvid": bvid, "cid": cid, "fnval": 16, "qn": qn, "fourk": 1},
    )
    if play.get("code") != 0:
        raise ValueError(f"Play API failed for {bvid}: {play.get('message')}")
    play_data = play["data"]
    video = pick_video(play_data)
    audio = pick_audio(play_data)

    output_dir.mkdir(parents=True, exist_ok=True)
    out_path = output_dir / f"{slug}.mp4"
    if not out_path.exists() or out_path.stat().st_size == 0:
        with tempfile.TemporaryDirectory(prefix=f"{slug}-", dir=output_dir) as tmp_name:
            tmp_dir = Path(tmp_name)
            video_path = tmp_dir / "video.m4s"
            audio_path = tmp_dir / "audio.m4s"
            download_file(video["baseUrl"], video_path, headers)
            download_file(audio["baseUrl"], audio_path, headers)
            run(
                [
                    tool_path("ffmpeg"),
                    "-hide_banner",
                    "-y",
                    "-i",
                    str(video_path),
                    "-i",
                    str(audio_path),
                    "-c",
                    "copy",
                    str(out_path),
                ]
            )

    return {
        "bvid": bvid,
        "source_url": page_url,
        "slug": slug,
        "output_path": str(out_path),
        "title": clean_title(data.get("title") or ""),
        "author": data.get("owner", {}).get("name"),
        "duration_seconds": data.get("duration"),
        "cid": cid,
        "selected_quality": play_data.get("quality"),
        "selected_video": {
            "width": video.get("width"),
            "height": video.get("height"),
            "codecs": video.get("codecs"),
            "bandwidth": video.get("bandwidth"),
        },
        "selected_audio": {
            "codecs": audio.get("codecs"),
            "bandwidth": audio.get("bandwidth"),
        },
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--qn", type=int, default=64)
    parser.add_argument(
        "--source",
        action="append",
        required=True,
        help="Bilibili source as BVID=slug",
    )
    args = parser.parse_args()

    output_dir = (ROOT / args.output_dir).resolve()
    manifest_path = (ROOT / args.manifest).resolve()
    records = []
    for source in args.source:
        if "=" not in source:
            raise SystemExit(f"--source must be BVID=slug, got: {source}")
        bvid, slug = source.split("=", 1)
        records.append(fetch_one(bvid.strip(), slug.strip(), output_dir, args.qn))

    payload = {
        "schema_version": "idol_bilibili_reference_fetch.v1",
        "network_scope": "public_bilibili_non_login",
        "source_count": len(records),
        "sources": records,
    }
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    manifest_path.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps(payload, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
