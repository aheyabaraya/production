#!/usr/bin/env python3
"""Validate a run-owned 05 package and its immutable final-render lineage."""

from __future__ import annotations

import argparse
from pathlib import Path

from lib.idol_social_release_contracts import (
    SocialContractError,
    validate_package_contract,
    validate_run_scope,
)


ROOT = Path(__file__).resolve().parent.parent


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("package", type=Path)
    args = parser.parse_args()

    package_path = args.package.resolve()
    if not package_path.is_file():
        raise SystemExit(f"05 package is not readable: {package_path}")
    run_path = package_path.parent
    content_id = run_path.name
    try:
        validated_run, _run_rel = validate_run_scope(ROOT, run_path, content_id)
        validate_package_contract(
            repo_root=ROOT,
            run_path=validated_run,
            content_id=content_id,
            package_contract=package_path,
            allow_closed=True,
        )
    except SocialContractError as exc:
        raise SystemExit(f"ERROR: {exc}") from exc
    print(
        "OK: 05 package binds its exact output-to-04 segment/screen-node graph, "
        "passed 04 closeout, 04FX compile, final render, and final-master bytes"
    )


if __name__ == "__main__":
    main()
