#!/usr/bin/env python3
"""Refresh the active IDOL asset context inside drive-sync.

The repo-owned assets remain the source of truth. This script creates a compact
Drive-facing mirror for LLM handoffs that need member images and configuration.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
from datetime import date
from pathlib import Path
from typing import Any


HANDOFF_ROOT = Path("drive-sync/02_GPT_GROK_HANDOFF")
DEFAULT_DESTINATION = HANDOFF_ROOT / "00_ASSET_CONTEXT"
ROOT_MANIFEST = Path("drive-sync/MANIFEST.md")
ROOT_README = Path("drive-sync/README.md")
START_HERE = Path("drive-sync/START-HERE.md")
HANDOFF_README = HANDOFF_ROOT / "README.md"

REGISTRY_FILES = [
    ("assets/member-registry.yaml", "registries/member-registry.yaml", "member registry"),
    ("assets/members/face-only-upscale-manifest.json", "registries/face-only-upscale-manifest.json", "active face-only upscale provenance"),
    ("assets/member-profile-summary.md", "registries/member-profile-summary.md", "member profile summary"),
    ("assets/voice-style-index.md", "registries/voice-style-index.md", "voice and rap style index"),
    ("assets/unit-registry.yaml", "registries/unit-registry.yaml", "unit registry"),
]

MEMBER_IMAGE_PATTERNS = [
    "assets/members/M*/character-board.*",
    "assets/members/M*/face-only-reference.png",
    "assets/members/M*/face-only-reference.PNG",
    "assets/members/M*/face-only-reference-direct-upscaled.png",
]

SECTION_START = "<!-- IDOL_ASSET_CONTEXT_START -->"
SECTION_END = "<!-- IDOL_ASSET_CONTEXT_END -->"

PRODUCTION_SCOPE_NOTE = """### Current production scope

Source-faithful teaser is the active separate direction. Resolve its current
source and approval gates through repo-owned `teaser/AGENTS.md`; this mirror
does not create production authority or replace required source pixels.

CF is frozen in the HQ archive (`../../archive/cf-legacy-20260909/` from the
IDOL repository root). The old IDOL `cf/`
path preserves historical reads and hashes only. Archived CF instructions,
packets and mirrored outputs do not authorize new CF work or generation.
See the archive README and manifest for an explicitly requested restoration.
"""


def json_dump(data: Any) -> str:
    return json.dumps(data, ensure_ascii=False, indent=2) + "\n"


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def collect_asset_files(repo_root: Path) -> list[dict[str, str]]:
    files: list[dict[str, str]] = []
    for source, destination, purpose in REGISTRY_FILES:
        files.append(
            {
                "source": source,
                "destination": destination,
                "kind": "registry",
                "purpose": purpose,
            }
        )

    for pattern in MEMBER_IMAGE_PATTERNS:
        for source_path in sorted(repo_root.glob(pattern)):
            if not source_path.is_file():
                continue
            member_code = source_path.parent.name
            files.append(
                {
                    "source": source_path.as_posix(),
                    "destination": f"members/{member_code}/{source_path.name}",
                    "kind": "member_visual_reference",
                    "purpose": source_path.stem.replace("-", " "),
                }
            )

    return sorted(files, key=lambda item: item["destination"])


def ensure_sources_exist(repo_root: Path, files: list[dict[str, str]]) -> None:
    missing = [item["source"] for item in files if not (repo_root / item["source"]).is_file()]
    if missing:
        raise FileNotFoundError("missing asset sources: " + ", ".join(missing))


def build_readme(sync_date: str, file_count: int, image_count: int) -> str:
    return f"""# IDOL Asset Context

Status: active Drive-facing asset mirror
Refreshed: {sync_date} KST

This folder exists so GPT, Grok app, Grok TUI, Grok CLI, or another LLM handoff can read the
active AURORA-M member configuration and visual references without needing the
whole repository.

Canonical source remains in the repo `assets/` folder. Edit repo-owned assets
first, then re-run:

```text
python3 scripts/idol_asset_drive_sync.py --write --founder-requested
```

## Contents

- `registries/member-registry.yaml`: member roles, local asset paths, signature
  moves, identity locks, and visual language.
- `registries/member-profile-summary.md`: compact member table for quick
  orientation.
- `registries/voice-style-index.md`: vocal and rap role rails.
- `registries/unit-registry.yaml`: active unit membership and unit purpose.
- `members/M01-M13/`: character boards, preserved source face-only references,
  and registry-selected direct-source face-only upscales.
- `registries/face-only-upscale-manifest.json`: source/output hashes,
  dimensions, and the direct non-generative upscale policy for the active face references.
- `asset-context-index.json`: file list with checksums.

## Use Rule

Read the registries before interpreting member images. The images are identity
and character references, not commands to reuse the same outfit, expression,
pose, styling, world, or choreography in every run.

Do not infer ages, birthdays, original fictional identity, or voice comparisons from
these files. If a task needs a member fact not present here, mark it as an open
question.

## Current Mirror

- file count: {file_count}
- member visual reference count: {image_count}
"""


def replace_marked_section(path: Path, section: str, *, write: bool) -> None:
    if not path.exists():
        return
    text = path.read_text(encoding="utf-8")
    block = f"\n{SECTION_START}\n{section.rstrip()}\n{SECTION_END}\n"
    if SECTION_START in text and SECTION_END in text:
        before, rest = text.split(SECTION_START, 1)
        _, after = rest.split(SECTION_END, 1)
        updated = before.rstrip() + block + after
    else:
        updated = text.rstrip() + "\n" + block
    if write:
        path.write_text(updated.rstrip() + "\n", encoding="utf-8")


def update_drive_docs(destination: Path, *, write: bool) -> None:
    asset_path = destination.as_posix()
    root_section = f"""## Active Asset Context

Active member configuration and visual references are staged for LLM handoffs at:

```text
{asset_path}/
```

This is a controlled mirror of repo-owned `assets/`, not a new source of truth.

{PRODUCTION_SCOPE_NOTE}
"""
    handoff_section = f"""### Active Asset Context

```text
00_ASSET_CONTEXT/
```

LLM handoff packets should read this folder when member identity, unit
configuration, voice role, character boards, or face references matter. Refresh
it with `python3 scripts/idol_asset_drive_sync.py --write --founder-requested`
only when a founder-requested LLM/Grok/Drive handoff needs the mirror.

{PRODUCTION_SCOPE_NOTE}
"""
    manifest_section = f"""## Active Asset Context

Folder:

- `02_GPT_GROK_HANDOFF/00_ASSET_CONTEXT/`

Includes active member registries, voice/unit configuration, and M01-M13
character-board plus face-only visual references for LLM handoffs.

{PRODUCTION_SCOPE_NOTE}
"""
    start_here_section = f"""## Active Asset Context

When a task involves member identity, image references, unit configuration, or
voice-role rails, read this folder before the task-specific handoff packet:

```text
02_GPT_GROK_HANDOFF/00_ASSET_CONTEXT/
```

Use the registries first, then the relevant `members/Mxx/` images.

{PRODUCTION_SCOPE_NOTE}
"""
    replace_marked_section(ROOT_README, root_section, write=write)
    replace_marked_section(START_HERE, start_here_section, write=write)
    replace_marked_section(HANDOFF_README, handoff_section, write=write)
    replace_marked_section(ROOT_MANIFEST, manifest_section, write=write)


def sync_asset_context(
    *,
    repo_root: Path | None = None,
    destination: Path = DEFAULT_DESTINATION,
    sync_date: str | None = None,
    write: bool = False,
    founder_requested: bool = False,
) -> dict[str, Any]:
    if write and not founder_requested:
        raise PermissionError("refusing to write Drive asset mirror without --founder-requested")

    root = repo_root or Path.cwd()
    resolved_sync_date = sync_date or date.today().isoformat()
    files = collect_asset_files(root)
    ensure_sources_exist(root, files)

    destinations = [item["destination"] for item in files]
    duplicates = sorted({path for path in destinations if destinations.count(path) > 1})
    if duplicates:
        raise ValueError("duplicate asset mirror destinations: " + ", ".join(duplicates))

    index_files: list[dict[str, Any]] = []
    if write:
        if destination.exists():
            shutil.rmtree(destination)
        destination.mkdir(parents=True, exist_ok=True)

    for item in files:
        source = root / item["source"]
        target = destination / item["destination"]
        if write:
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
        index_files.append(
            {
                **item,
                "sha256": sha256_file(source),
                "bytes": source.stat().st_size,
            }
        )

    image_count = sum(1 for item in index_files if item["kind"] == "member_visual_reference")
    if write:
        (destination / "README.md").write_text(
            build_readme(resolved_sync_date, len(index_files), image_count),
            encoding="utf-8",
        )
        (destination / "asset-context-index.json").write_text(
            json_dump(
                {
                    "status": "active",
                    "refreshed": resolved_sync_date,
                    "source": "assets/",
                    "destination": destination.as_posix(),
                    "canonical_source_note": "Repo-owned assets remain source truth.",
                    "file_count": len(index_files),
                    "member_visual_reference_count": image_count,
                    "files": index_files,
                }
            ),
            encoding="utf-8",
        )

    update_drive_docs(destination, write=write)

    return {
        "write": write,
        "founder_requested": founder_requested,
        "harness": "asset_drive_sync",
        "destination": destination.as_posix(),
        "sync_date": resolved_sync_date,
        "file_count": len(index_files),
        "registry_count": sum(1 for item in index_files if item["kind"] == "registry"),
        "member_visual_reference_count": image_count,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--destination", default=DEFAULT_DESTINATION.as_posix())
    parser.add_argument("--sync-date", default=date.today().isoformat())
    parser.add_argument("--write", action="store_true")
    parser.add_argument(
        "--founder-requested",
        action="store_true",
        help="Confirm the founder explicitly requested this LLM/Grok/Drive asset-context mirror.",
    )
    args = parser.parse_args()
    if args.write and not args.founder_requested:
        parser.error("refusing to write Drive asset mirror without --founder-requested")

    result = sync_asset_context(
        destination=Path(args.destination),
        sync_date=args.sync_date,
        write=args.write,
        founder_requested=args.founder_requested,
    )
    print(json_dump(result), end="")


if __name__ == "__main__":
    main()
