#!/usr/bin/env python3
"""Report platform credential presence without revealing credential values."""

from __future__ import annotations

import argparse
import json

from lib.idol_platform_credentials import PLATFORMS, all_status


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--platform",
        action="append",
        choices=PLATFORMS,
        help="Limit the value-free status report to one or more platforms.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    selected = tuple(args.platform or PLATFORMS)
    print(json.dumps(all_status(platforms=selected), ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
