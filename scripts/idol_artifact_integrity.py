#!/usr/bin/env python3
"""Inspect an IDOL artifact using the active cost-aware integrity profiles."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

from lib.idol_artifact_integrity import IntegrityCache, PROFILES


ROOT = Path(__file__).resolve().parent.parent


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("path")
    parser.add_argument(
        "--profile",
        choices=sorted(PROFILES),
        default="repeat_local_validation",
    )
    parser.add_argument("--expected", help="Expected SHA-256 for a binding check")
    parser.add_argument("--no-cache-write", action="store_true")
    args = parser.parse_args()

    path = Path(args.path)
    path = path if path.is_absolute() else ROOT / path
    if not path.is_file():
        parser.error(f"file does not exist: {args.path}")
    cache = IntegrityCache(ROOT)
    result = cache.inspect(path, args.profile)
    if args.expected is not None:
        if result["algorithm"] != "sha256":
            parser.error("--expected requires a SHA-256 profile")
        result["matches_expected"] = result["value"] == args.expected.lower()
    if not args.no_cache_write:
        cache.save()
    print(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True))
    return 0 if result.get("matches_expected", True) else 1


if __name__ == "__main__":
    sys.exit(main())
