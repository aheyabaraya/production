#!/usr/bin/env python3
"""Project one run-owned social release state across local IDOL artifacts.

The projector is deterministic for the same explicit inputs and never performs
network I/O.  It refuses global queues, foreign content rows, cross-run package
paths, immutable closed publishing records, and mismatched title registries.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
from datetime import datetime
from pathlib import Path
from typing import Any

import idol_title_output_registry as title_registry
import validate_publishing_plan as publishing_plan_validator
from lib.idol_social_release_contracts import (
    SocialContractError,
    canonical_object_sha256,
    package_deliverable_manifest,
    repo_relative,
    sha256_file,
    validate_approval_artifact,
    validate_package_contract,
    validate_queue_scope,
    validate_queue_asset_linkage,
    validate_registry_scope,
    validate_run_owned_path,
    validate_run_scope,
    validate_schema,
)
from lib.idol_post05_trace import RELEASE_PROVENANCE_VERSION


ROOT = Path(__file__).resolve().parents[1]
STATUS_CHOICES = [
    "pending_founder_approval",
    "approved_for_manual_draft_upload",
    "approved_for_public_publish",
]
APPROVAL_ACTION = {
    "approved_for_manual_draft_upload": "manual_draft_upload",
    "approved_for_public_publish": "public_publish",
}


def validate_timestamp(value: str) -> str:
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise SocialContractError("--projected-at must be an ISO-8601 timestamp") from exc
    if parsed.tzinfo is None:
        raise SocialContractError("--projected-at must include a timezone offset")
    return value


def slug(value: str) -> str:
    value = value.replace("#", "")
    value = re.sub(r"[^A-Za-z0-9가-힣]+", "-", value).strip("-")
    value = re.sub(r"-+", "-", value)
    return value[:80] or "untitled"


def platform_dir(platform: str) -> str:
    mapping = {
        "x": "01_X",
        "tiktok": "02_TikTok",
        "youtube_shorts": "03_YouTube_Shorts",
        "youtube": "04_YouTube",
        "instagram_reels": "05_Instagram_Reels",
    }
    if platform not in mapping:
        raise SocialContractError(f"unsupported platform in queue: {platform}")
    return mapping[platform]


def platform_prefix(platform: str) -> str:
    return {
        "x": "X",
        "tiktok": "TT",
        "youtube_shorts": "YS",
        "youtube": "YT",
        "instagram_reels": "IG",
    }[platform]


def write_rows(path: Path, rows: list[dict[str, Any]]) -> None:
    payload = "\n".join(
        json.dumps(row, ensure_ascii=False, separators=(",", ":")) for row in rows
    ) + "\n"
    path.write_text(payload, encoding="utf-8")


def package_names(row: dict[str, Any]) -> tuple[str, str]:
    tracking = str(row.get("tracking_code") or row["post_id"])
    clip_no = tracking.split("C")[-1]
    title = str(row.get("caption") or row["post_id"]).splitlines()[0]
    prefix = platform_prefix(str(row["platform"]))
    safe_title = slug(title)
    return (
        f"{prefix}-{clip_no}__{safe_title}.mp4",
        f"{prefix}-{clip_no}__{safe_title}__title-caption.txt",
    )


def approval_fields(
    *,
    status: str,
    projected_at: str,
    queue_sha: str,
    package_contract_rel: str,
    package_contract_sha: str,
    package_deliverable_manifest_sha: str,
    package_rel: str,
    plan_rel: str,
    approval_path_rel: str,
    approval_sha: str,
    approval: dict[str, Any] | None,
) -> dict[str, str]:
    fields = {
        "release_approval_status": status,
        "release_approval_source": (
            str((approval or {}).get("approval_source") or "local_projection_no_approval")
        ),
        "release_approval_artifact": approval_path_rel,
        "release_approval_artifact_sha256": approval_sha,
        "release_approval_queue_sha256": queue_sha,
        "release_approval_action": APPROVAL_ACTION.get(status, "local_projection_only"),
        "release_approval_updated_at": projected_at,
        "release_package_contract": package_contract_rel,
        "release_package_contract_sha256": package_contract_sha,
        "release_package_deliverable_manifest_sha256": package_deliverable_manifest_sha,
        "manual_upload_package": package_rel,
        "publishing_plan": plan_rel,
    }
    if status.startswith("approved_"):
        fields["release_approved_at"] = str((approval or {}).get("approved_at_kst") or projected_at)
    return fields


def update_rows(
    rows: list[dict[str, Any]], fields: dict[str, str], approved_post_ids: set[str] | None
) -> list[dict[str, Any]]:
    updated: list[dict[str, Any]] = []
    for row in rows:
        if row.get("delivery_mode") != "platform_draft":
            continue
        if approved_post_ids is not None and row.get("post_id") not in approved_post_ids:
            continue
        row.update(fields)
        if not fields["release_approval_artifact"]:
            row.pop("release_approved_at", None)
        updated.append(row)
    if not updated:
        raise SocialContractError("release projection selected no platform_draft rows")
    return updated


def sidecar_text(row: dict[str, Any]) -> str:
    title = str(row.get("caption") or row["post_id"]).splitlines()[0]
    parts = [
        f"post_id: {row['post_id']}",
        f"platform: {row['platform']}",
        f"tracking_code: {row.get('tracking_code', '')}",
        f"visible_label: {row.get('visible_label', '')}",
        f"draft_status: {row.get('draft_status', '')}",
        f"release_approval_status: {row.get('release_approval_status', 'pending_founder_approval')}",
        f"release_approval_source: {row.get('release_approval_source', '')}",
        f"release_approval_artifact: {row.get('release_approval_artifact', '')}",
        f"release_approval_artifact_sha256: {row.get('release_approval_artifact_sha256', '')}",
        f"release_approval_queue_sha256: {row.get('release_approval_queue_sha256', '')}",
        f"release_approval_action: {row.get('release_approval_action', '')}",
        f"release_package_contract: {row.get('release_package_contract', '')}",
        f"release_package_contract_sha256: {row.get('release_package_contract_sha256', '')}",
        f"release_package_deliverable_manifest_sha256: {row.get('release_package_deliverable_manifest_sha256', '')}",
        f"release_package_output_id: {row.get('release_package_output_id', '')}",
        f"release_package_output_role: {row.get('release_package_output_role', '')}",
        f"release_package_linkage: {row.get('release_package_linkage', '')}",
        f"release_provenance_version: {row.get('release_provenance_version', '')}",
        f"release_production_graph_trace_sha256: {row.get('release_production_graph_trace_sha256', '')}",
        "release_edit_segment_ids: "
        + json.dumps(row.get("release_edit_segment_ids") or [], ensure_ascii=False),
        "release_screen_progression_node_ids: "
        + json.dumps(row.get("release_screen_progression_node_ids") or [], ensure_ascii=False),
        "release_section_ids: "
        + json.dumps(row.get("release_section_ids") or [], ensure_ascii=False),
        f"release_asset_sha256: {row.get('release_asset_sha256', '')}",
    ]
    if row.get("release_approved_at"):
        parts.append(f"release_approved_at: {row['release_approved_at']}")
    for key in ("draft_platform_id", "draft_url", "draft_verified_status"):
        if row.get(key):
            parts.append(f"{key}: {row[key]}")
    parts.extend(
        [
            "",
            "TITLE_OR_FIRST_LINE:",
            title,
            "",
            "CAPTION:",
            str(row.get("caption") or ""),
            "",
            "HASHTAGS:",
            " ".join(row.get("hashtags") or []),
            "",
            "LOCAL_SOURCE:",
            str(row.get("asset_or_clip") or ""),
        ]
    )
    return "\n".join(parts) + "\n"


def package_readme(
    rows: list[dict[str, Any]], *, content_id: str, status: str, projected_at: str
) -> str:
    approval_path = str(rows[0].get("release_approval_artifact") or "") if rows else ""
    approval_sha = str(rows[0].get("release_approval_artifact_sha256") or "") if rows else ""
    approval_proof = (
        f"`{approval_path}` / `{approval_sha}`"
        if approval_path and approval_sha
        else "none; local projection only"
    )
    package_contract = str(rows[0].get("release_package_contract") or "") if rows else ""
    package_contract_sha = (
        str(rows[0].get("release_package_contract_sha256") or "") if rows else ""
    )
    package_manifest_sha = (
        str(rows[0].get("release_package_deliverable_manifest_sha256") or "")
        if rows
        else ""
    )
    approval_queue_sha = (
        str(rows[0].get("release_approval_queue_sha256") or "") if rows else ""
    )
    approval_action = str(rows[0].get("release_approval_action") or "") if rows else ""
    lines = [
        "# Manual Upload Package",
        "",
        f"content_id: `{content_id}`",
        f"projected_at: `{projected_at}`",
        "rule: upload as drafts/private unless an exact Founder approval artifact permits public publish",
        f"release_approval_status: `{status}`",
        f"release_approval_action: `{approval_action}`",
        f"release_approval_proof: {approval_proof}",
        f"release_approval_queue_sha256: `{approval_queue_sha}`",
        f"release_package_contract: `{package_contract}` / `{package_contract_sha}`",
        f"release_package_deliverable_manifest_sha256: `{package_manifest_sha}`",
        "",
        "## Approval Rule",
        "",
        "- `pending_founder_approval`: package is prepared locally but no external action is approved.",
        "- `approved_for_manual_draft_upload`: only the approved post IDs may be opened in a draft/private upload surface.",
        "- `approved_for_public_publish`: only the approved post IDs and platforms may be publicly released.",
        "- Published URLs or platform post IDs must still be recorded in the owning run queue or ledger.",
        "",
        "## Files",
        "",
        "| platform | tracking | asset SHA-256 | video file | title/caption file |",
        "| --- | --- | --- | --- | --- |",
    ]
    for row in rows:
        video_name, text_name = package_names(row)
        dirname = platform_dir(str(row["platform"]))
        lines.append(
            f"| {row['platform']} | {row.get('tracking_code', row['post_id'])} | "
            f"`{row.get('release_asset_sha256', '')}` | "
            f"`{dirname}/{video_name}` | `{dirname}/{text_name}` |"
        )
    return "\n".join(lines) + "\n"


def sync_packages(
    rows: list[dict[str, Any]],
    *,
    package_root: Path,
    run_path: Path,
    content_id: str,
    status: str,
    projected_at: str,
) -> None:
    package_root.mkdir(parents=True, exist_ok=True)
    (package_root / "README.md").write_text(
        package_readme(rows, content_id=content_id, status=status, projected_at=projected_at),
        encoding="utf-8",
    )
    for row in rows:
        source = validate_run_owned_path(
            ROOT,
            run_path,
            str(row.get("asset_or_clip") or ""),
            f"asset_or_clip for {row.get('post_id', '<unknown>')}",
            must_exist=True,
            file_only=True,
        )
        dirname = platform_dir(str(row["platform"]))
        video_name, text_name = package_names(row)
        package_dir = package_root / dirname
        package_dir.mkdir(parents=True, exist_ok=True)
        target_video = package_dir / video_name
        source_sha = sha256_file(source)
        expected_sha = str(row.get("release_asset_sha256") or "")
        if expected_sha and source_sha != expected_sha:
            raise SocialContractError(
                f"source asset changed after release approval/projection: {row.get('post_id', '<unknown>')}"
            )
        if source.resolve() == target_video.resolve():
            pass
        elif not target_video.exists() or sha256_file(target_video) != source_sha:
            shutil.copy2(source, target_video)
        if sha256_file(target_video) != source_sha:
            raise SocialContractError(
                f"manual package copy hash mismatch: {row.get('post_id', '<unknown>')}"
            )
        (package_dir / text_name).write_text(sidecar_text(row), encoding="utf-8")


def plan_is_closed(text: str) -> bool:
    status_match = re.search(r"^status:\s*`?([^`\n]+)`?\s*$", text, flags=re.M)
    status = status_match.group(1).strip().lower() if status_match else ""
    immutable_status = any(marker in status for marker in ("closed", "archived", "final_complete"))
    immutable_section = any(
        marker in text
        for marker in ("## Closed Upload History", "## Archived Upload History")
    )
    return immutable_status or immutable_section


def validate_plan_owner(path: Path, run_path: Path, content_id: str) -> None:
    if path != (run_path / "publishing-plan.md").resolve():
        raise SocialContractError("--publishing-plan must be the run-root publishing-plan.md")
    text = path.read_text(encoding="utf-8")
    match = re.search(r"^content_id:\s*`?([^`\n]+)`?\s*$", text, flags=re.M)
    if not match or match.group(1).strip() != content_id:
        raise SocialContractError("publishing-plan.md content_id does not match --content-id")


def validate_package_owner(path: Path, run_path: Path, content_id: str) -> None:
    relative = path.relative_to(run_path)
    if len(relative.parts) < 3 or relative.parts[:2] != ("exports", "social"):
        raise SocialContractError("--package must be a run-owned exports/social package directory")
    readme = path / "README.md"
    if not readme.exists():
        return
    match = re.search(
        r"^content_id:\s*`?([^`\n]+)`?\s*$",
        readme.read_text(encoding="utf-8"),
        flags=re.M,
    )
    if match and match.group(1).strip() != content_id:
        raise SocialContractError("existing manual-upload package belongs to another content_id")


def validate_package_file_set(path: Path, expected_targets: set[str]) -> None:
    if not path.exists():
        return
    symlinks = sorted(
        item.relative_to(path).as_posix() for item in path.rglob("*") if item.is_symlink()
    )
    if symlinks:
        raise SocialContractError(
            "manual package must contain owned files, not symlinks: " + ", ".join(symlinks[:10])
        )
    existing = {
        item.relative_to(path).as_posix()
        for item in path.rglob("*")
        if item.is_file() and item.name != ".DS_Store"
    }
    unexpected = sorted(existing - expected_targets - {"README.md"})
    if unexpected:
        raise SocialContractError(
            "manual package contains files outside the exact projected row set; "
            "use a new package path or an explicit cleanup pass: "
            + ", ".join(unexpected[:10])
        )


def render_plan(
    path: Path,
    *,
    status: str,
    projected_at: str,
    queue_sha: str,
    package_contract_rel: str,
    package_contract_sha: str,
    package_deliverable_manifest_sha: str,
    approval_path_rel: str,
    approval_sha: str,
    updated_count: int,
) -> str:
    text = path.read_text(encoding="utf-8")
    if plan_is_closed(text):
        raise SocialContractError("publishing record is immutable closed state; release sync cannot modify it")
    proof = (
        f"`{approval_path_rel}` / `{approval_sha}`"
        if approval_path_rel
        else "none; local projection only"
    )
    block = (
        "## Release Approval Sync\n\n"
        f"- Current release approval status: `{status}`.\n"
        f"- Projection timestamp: `{projected_at}`.\n"
        f"- Canonical action queue SHA-256: `{queue_sha}`.\n"
        f"- 05 deliverable source: `{package_contract_rel}` / `{package_contract_sha}`.\n"
        f"- 05 deliverable manifest SHA-256: `{package_deliverable_manifest_sha}`.\n"
        f"- Schema-backed Founder approval proof: {proof}.\n"
        f"- Queue rows in this projection: `{updated_count}`.\n"
        "- The same state is projected only into the run-owned queue, manual-upload package, publishing plan, and scoped title registry.\n"
        "- Do not mark rows `published` until platform URLs or post IDs are recorded.\n"
    )
    if "## Release Approval Sync" in text:
        text = re.sub(
            r"## Release Approval Sync\n\n.*?(?=\n## |\Z)", block.rstrip(), text, flags=re.S
        )
    else:
        text = text.rstrip() + "\n\n" + block
    return text.rstrip() + "\n"


def projection_digest(
    *,
    run_rel: str,
    content_id: str,
    queue_sha: str,
    package_contract_rel: str,
    package_contract_sha: str,
    package_deliverable_manifest_sha: str,
    package_rel: str,
    plan_rel: str,
    registry_rel: str,
    status: str,
    projected_at: str,
    approval_sha: str,
) -> str:
    payload = {
        "run_root": run_rel,
        "content_id": content_id,
        "queue_sha256": queue_sha,
        "package_contract": package_contract_rel,
        "package_contract_sha256": package_contract_sha,
        "package_deliverable_manifest_sha256": package_deliverable_manifest_sha,
        "package": package_rel,
        "publishing_plan": plan_rel,
        "registry": registry_rel,
        "approval_status": status,
        "projected_at": projected_at,
        "approval_artifact_sha256": approval_sha,
    }
    canonical = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def project_registry(
    registry: dict[str, Any],
    *,
    run_rel: str,
    content_id: str,
    package_rel: str,
    plan_rel: str,
    projected_at: str,
) -> None:
    current_status = str(registry.get("status") or "")
    if "closed" in current_status.lower() or current_status == "archived":
        raise SocialContractError("title registry is immutable closed state; release sync cannot modify it")
    outputs = registry.setdefault("outputs", [])
    specs = [
        ("package", package_rel, "run-owned manual upload package"),
        ("social_asset", plan_rel, "run-owned publishing plan approval projection"),
    ]
    for output_type, path, notes in specs:
        oid = title_registry.output_id(output_type, path)
        existing = next(
            (
                item
                for item in outputs
                if item.get("output_id") == oid
                or (item.get("output_type") == output_type and item.get("path") == path)
            ),
            None,
        )
        registered_at = str((existing or {}).get("registered_at") or projected_at)
        row = {
            "output_id": oid,
            "output_type": output_type,
            "path": path,
            "source_run_root": run_rel,
            "content_id": content_id,
            "packet_id": None,
            "core_cut_id": None,
            "branch_cut_id": None,
            "beat_id": None,
            "source_step": "social_release_projection",
            "status": "packaged" if output_type == "package" else "prepared",
            "registered_at": registered_at,
            "last_seen_at": projected_at,
            "notes": notes,
        }
        if existing is None:
            outputs.append(row)
        else:
            existing.clear()
            existing.update(row)
        registry.setdefault("latest_pointers", {})[output_type] = path
    for source in registry.get("source_runs") or []:
        if isinstance(source, dict) and source.get("run_root") == run_rel:
            source["last_updated_at"] = projected_at
    if current_status != "hold":
        registry["status"] = "packaged"


def remove_local_path(path: Path) -> None:
    if not path.exists() and not path.is_symlink():
        return
    if path.is_dir() and not path.is_symlink():
        shutil.rmtree(path)
    else:
        path.unlink()


def atomic_write_json(path: Path, document: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.tmp")
    temporary.write_text(
        json.dumps(document, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    os.replace(temporary, path)


def commit_projection(
    *,
    staged_destinations: list[tuple[Path, Path]],
    journal_path: Path,
    projection_digest_value: str,
) -> None:
    token = projection_digest_value[:12]
    entries: list[dict[str, Any]] = []
    for stage, destination in staged_destinations:
        backup = destination.with_name(f".{destination.name}.backup-{token}")
        if backup.exists() or backup.is_symlink():
            raise SocialContractError(f"release projection backup already exists: {backup}")
        if not stage.exists() and not stage.is_symlink():
            raise SocialContractError(f"release projection stage is missing: {stage}")
        entries.append(
            {
                "stage": str(stage),
                "destination": str(destination),
                "backup": str(backup),
                "had_destination": destination.exists() or destination.is_symlink(),
                "installed": False,
            }
        )

    existing_journal: dict[str, Any] = {}
    if journal_path.exists():
        try:
            existing_journal = json.loads(journal_path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError) as exc:
            raise SocialContractError(f"unreadable prior release projection journal: {journal_path}") from exc
    if existing_journal.get("status") in {"prepared", "applying", "rollback_failed"}:
        raise SocialContractError(
            f"unfinished release projection journal requires recovery review: {journal_path}"
        )

    journal = {
        "schema_version": "idol_release_projection_journal.v1",
        "projection_digest": projection_digest_value,
        "status": "prepared",
        "entries": entries,
        "cleanup_warnings": [],
    }
    atomic_write_json(journal_path, journal)
    installed: list[dict[str, Any]] = []
    active_entry: dict[str, Any] | None = None
    try:
        journal["status"] = "applying"
        atomic_write_json(journal_path, journal)
        for entry in entries:
            active_entry = entry
            stage = Path(entry["stage"])
            destination = Path(entry["destination"])
            backup = Path(entry["backup"])
            destination.parent.mkdir(parents=True, exist_ok=True)
            if entry["had_destination"]:
                os.replace(destination, backup)
            try:
                os.replace(stage, destination)
            except Exception:
                if backup.exists() or backup.is_symlink():
                    os.replace(backup, destination)
                raise
            entry["installed"] = True
            installed.append(entry)
            active_entry = None
            atomic_write_json(journal_path, journal)
    except Exception as exc:
        rollback_errors: list[str] = []
        if active_entry is not None:
            destination = Path(active_entry["destination"])
            backup = Path(active_entry["backup"])
            if not destination.exists() and (backup.exists() or backup.is_symlink()):
                try:
                    os.replace(backup, destination)
                except Exception as rollback_exc:  # pragma: no cover - catastrophic filesystem failure
                    rollback_errors.append(str(rollback_exc))
        for entry in reversed(installed):
            destination = Path(entry["destination"])
            backup = Path(entry["backup"])
            try:
                remove_local_path(destination)
                if backup.exists() or backup.is_symlink():
                    os.replace(backup, destination)
            except Exception as rollback_exc:  # pragma: no cover - catastrophic filesystem failure
                rollback_errors.append(str(rollback_exc))
        journal["status"] = "rollback_failed" if rollback_errors else "rolled_back"
        journal["rollback_errors"] = rollback_errors
        atomic_write_json(journal_path, journal)
        message = f"release projection commit failed and was rolled back: {exc}"
        if rollback_errors:
            message += "; rollback errors: " + "; ".join(rollback_errors)
        raise SocialContractError(message) from exc

    cleanup_warnings: list[str] = []
    for entry in entries:
        backup = Path(entry["backup"])
        try:
            remove_local_path(backup)
        except OSError as exc:  # pragma: no cover - cleanup warning only
            cleanup_warnings.append(f"{backup}: {exc}")
    journal["status"] = "committed_with_cleanup_warning" if cleanup_warnings else "committed"
    journal["cleanup_warnings"] = cleanup_warnings
    atomic_write_json(journal_path, journal)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-root", required=True)
    parser.add_argument("--content-id", required=True)
    parser.add_argument("--queue", required=True)
    parser.add_argument("--package-contract", required=True, help="Run-root 05-package.yaml.")
    parser.add_argument("--package", required=True, help="Run-owned manual-upload package directory.")
    parser.add_argument("--publishing-plan", required=True)
    parser.add_argument("--registry", required=True)
    parser.add_argument("--projected-at", required=True)
    parser.add_argument("--approval-status", choices=STATUS_CHOICES, default="pending_founder_approval")
    parser.add_argument("--approval-artifact")
    parser.add_argument("--approval-sha256")
    parser.add_argument("--skip-title-registry", action="store_true")
    parser.add_argument("--apply", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.apply and args.skip_title_registry:
        print(
            json.dumps(
                {
                    "mode": "blocked",
                    "error": "--apply cannot use --skip-title-registry; the local release projection must include its exact title registry",
                },
                ensure_ascii=False,
            )
        )
        return 2
    try:
        projected_at = validate_timestamp(args.projected_at)
        run_path, run_rel = validate_run_scope(ROOT, args.run_root, args.content_id)
        queue_path, rows, queue_sha = validate_queue_scope(ROOT, run_path, args.content_id, args.queue)
        package_contract_path, _package_contract, deliverables = validate_package_contract(
            repo_root=ROOT,
            run_path=run_path,
            content_id=args.content_id,
            package_contract=args.package_contract,
            require_final_lineage=False,
        )
        package_contract_rel = repo_relative(ROOT, package_contract_path)
        package_contract_sha = sha256_file(package_contract_path)
        package_manifest = package_deliverable_manifest(
            repo_root=ROOT,
            run_path=run_path,
            document=_package_contract,
            deliverables=deliverables,
        )
        package_deliverable_manifest_sha = canonical_object_sha256(package_manifest)
        package_path = validate_run_owned_path(
            ROOT, run_path, args.package, "manual upload package", must_exist=False
        )
        if package_path.exists() and not package_path.is_dir():
            raise SocialContractError("manual upload package path exists but is not a directory")
        validate_package_owner(package_path, run_path, args.content_id)
        plan_path = validate_run_owned_path(
            ROOT,
            run_path,
            args.publishing_plan,
            "publishing plan",
            must_exist=True,
            file_only=True,
        )
        validate_plan_owner(plan_path, run_path, args.content_id)
        registry_path, registry = validate_registry_scope(
            repo_root=ROOT,
            run_rel=run_rel,
            content_id=args.content_id,
            registry=args.registry,
        )
        registry_status = str(registry.get("status") or "")
        if "closed" in registry_status.lower() or registry_status == "archived":
            raise SocialContractError(
                "title registry is immutable closed state; release sync cannot modify it"
            )
        validate_schema(
            registry,
            ROOT / "schemas/title-output-registry.schema.json",
            label="scoped title output registry",
        )
        if plan_is_closed(plan_path.read_text(encoding="utf-8")):
            raise SocialContractError(
                "publishing record is immutable closed state; use the closed-record validator, not release sync"
            )
        package_rel = repo_relative(ROOT, package_path)
        plan_rel = repo_relative(ROOT, plan_path)
        registry_rel = repo_relative(ROOT, registry_path)

        approval: dict[str, Any] | None = None
        approval_path_rel = ""
        approval_sha = ""
        approved_post_ids: set[str] | None = None
        approved_asset_sha_by_post: dict[str, str] = {}
        if args.approval_status in APPROVAL_ACTION:
            if not args.approval_artifact or not args.approval_sha256:
                raise SocialContractError(
                    "approved release status requires --approval-artifact and --approval-sha256"
                )
            approval_path, approval, approval_sha = validate_approval_artifact(
                repo_root=ROOT,
                run_path=run_path,
                run_rel=run_rel,
                content_id=args.content_id,
                queue_path=queue_path,
                queue_rows=rows,
                queue_sha256=queue_sha,
                package_contract_path=package_contract_path,
                package_contract_sha256=package_contract_sha,
                package_deliverable_manifest_sha256=package_deliverable_manifest_sha,
                artifact=args.approval_artifact,
                expected_sha256=args.approval_sha256,
                required_action=APPROVAL_ACTION[args.approval_status],
            )
            approval_path_rel = repo_relative(ROOT, approval_path)
            approved_post_ids = set(approval.get("approved_post_ids") or [])
            approved_asset_sha_by_post = {
                str(item.get("post_id") or ""): str(item.get("sha256") or "")
                for item in (approval.get("approved_assets") or [])
            }
            queue_by_id = {str(row.get("post_id") or ""): row for row in rows}
            missing = sorted(approved_post_ids - set(queue_by_id))
            if missing:
                raise SocialContractError(
                    "approval names post IDs absent from the exact queue: " + ", ".join(missing)
                )
            wrong_delivery = sorted(
                post_id
                for post_id in approved_post_ids
                if queue_by_id[post_id].get("delivery_mode") != "platform_draft"
            )
            if wrong_delivery:
                raise SocialContractError(
                    "approval names rows outside delivery_mode=platform_draft: "
                    + ", ".join(wrong_delivery)
                )
            approved_platforms = set(approval.get("approved_platforms") or [])
            wrong_platform = sorted(
                post_id
                for post_id in approved_post_ids
                if str(queue_by_id[post_id].get("platform") or "") not in approved_platforms
            )
            if wrong_platform:
                raise SocialContractError(
                    "approval post/platform scope is inconsistent for: " + ", ".join(wrong_platform)
                )

        fields = approval_fields(
            status=args.approval_status,
            projected_at=projected_at,
            queue_sha=queue_sha,
            package_contract_rel=package_contract_rel,
            package_contract_sha=package_contract_sha,
            package_deliverable_manifest_sha=package_deliverable_manifest_sha,
            package_rel=package_rel,
            plan_rel=plan_rel,
            approval_path_rel=approval_path_rel,
            approval_sha=approval_sha,
            approval=approval,
        )
        projected_rows = [dict(row) for row in rows]
        updated = update_rows(projected_rows, fields, approved_post_ids)
        for row in updated:
            post_id = str(row.get("post_id") or "")
            if post_id in approved_asset_sha_by_post:
                row["release_asset_sha256"] = approved_asset_sha_by_post[post_id]
            else:
                asset_path = validate_run_owned_path(
                    ROOT,
                    run_path,
                    str(row.get("asset_or_clip") or ""),
                    f"asset_or_clip for {post_id}",
                    must_exist=True,
                    file_only=True,
                )
                row["release_asset_sha256"] = sha256_file(asset_path)
        asset_linkage_manifest = validate_queue_asset_linkage(
            repo_root=ROOT,
            run_path=run_path,
            rows=updated,
            deliverables=deliverables,
        )
        linkage_by_post = {item["post_id"]: item for item in asset_linkage_manifest}
        trace_by_output = {
            str(item.get("output_id") or ""): item
            for item in package_manifest["deliverables"]
        }
        production_trace_sha = str(
            package_manifest.get("production_graph_trace_sha256") or ""
        )
        if not production_trace_sha:
            raise SocialContractError(
                "05 package deliverable manifest has no production graph trace"
            )
        for row in updated:
            linkage = linkage_by_post[str(row.get("post_id") or "")]
            row["release_package_output_id"] = linkage["package_output_id"]
            row["release_package_output_role"] = linkage["package_output_role"]
            row["release_package_linkage"] = linkage["linkage"]
            row["release_provenance_version"] = RELEASE_PROVENANCE_VERSION
            output_trace = trace_by_output.get(linkage["package_output_id"])
            if output_trace is None:
                raise SocialContractError(
                    f"package output has no production graph projection: {linkage['package_output_id']}"
                )
            row["release_production_graph_trace_sha256"] = production_trace_sha
            row["release_edit_segment_ids"] = list(
                output_trace.get("edit_segment_ids") or []
            )
            row["release_screen_progression_node_ids"] = list(
                output_trace.get("screen_progression_node_ids") or []
            )
            row["release_section_ids"] = list(output_trace.get("section_ids") or [])
        package_targets: set[str] = set()
        for row in updated:
            video_name, text_name = package_names(row)
            dirname = platform_dir(str(row["platform"]))
            for target in (f"{dirname}/{video_name}", f"{dirname}/{text_name}"):
                if target in package_targets:
                    raise SocialContractError(f"manual package target collision: {target}")
                package_targets.add(target)
        validate_package_file_set(package_path, package_targets)
        digest = projection_digest(
            run_rel=run_rel,
            content_id=args.content_id,
            queue_sha=queue_sha,
            package_contract_rel=package_contract_rel,
            package_contract_sha=package_contract_sha,
            package_deliverable_manifest_sha=package_deliverable_manifest_sha,
            package_rel=package_rel,
            plan_rel=plan_rel,
            registry_rel=registry_rel,
            status=args.approval_status,
            projected_at=projected_at,
            approval_sha=approval_sha,
        )
    except SocialContractError as exc:
        print(json.dumps({"mode": "blocked", "error": str(exc)}, ensure_ascii=False))
        return 2

    if not args.apply:
        print(
            json.dumps(
                {
                    "mode": "dry_run",
                    "run_root": run_rel,
                    "content_id": args.content_id,
                    "queue": repo_relative(ROOT, queue_path),
                    "queue_sha256": queue_sha,
                    "package_contract": package_contract_rel,
                    "package_contract_sha256": package_contract_sha,
                    "package_deliverable_manifest_sha256": package_deliverable_manifest_sha,
                    "package_deliverables": package_manifest["deliverables"],
                    "asset_linkage_manifest": asset_linkage_manifest,
                    "package": package_rel,
                    "publishing_plan": plan_rel,
                    "registry": registry_rel,
                    "approval_status": args.approval_status,
                    "approval_artifact": approval_path_rel,
                    "approval_artifact_sha256": approval_sha,
                    "updated_post_ids": [row["post_id"] for row in updated],
                    "projection_digest": digest,
                },
                ensure_ascii=False,
                indent=2,
            )
        )
        return 0

    if sha256_file(package_contract_path) != package_contract_sha:
        print(
            json.dumps(
                {
                    "mode": "blocked",
                    "error": "05-package.yaml changed after release validation",
                },
                ensure_ascii=False,
            )
        )
        return 2

    token = digest[:12]
    queue_stage = queue_path.with_name(f".{queue_path.name}.stage-{token}")
    plan_stage = plan_path.with_name(f".{plan_path.name}.stage-{token}")
    package_stage = package_path.with_name(f".{package_path.name}.stage-{token}")
    registry_stage = registry_path.with_name(f".{registry_path.name}.stage-{token}")
    stage_paths = [queue_stage, plan_stage, package_stage]
    if not args.skip_title_registry:
        stage_paths.append(registry_stage)
    journal_path = (
        run_path
        / "exports/social/release-projection-journals"
        / f"release-projection-{digest}.json"
    )
    try:
        leftovers = [str(path) for path in stage_paths if path.exists() or path.is_symlink()]
        if leftovers:
            raise SocialContractError(
                "release projection staging paths already exist; inspect prior recovery journal: "
                + ", ".join(leftovers)
            )
        write_rows(queue_stage, projected_rows)
        staged_queue_path, _staged_rows, staged_queue_sha = validate_queue_scope(
            ROOT, run_path, args.content_id, queue_stage
        )
        if staged_queue_path != queue_stage or staged_queue_sha != queue_sha:
            raise SocialContractError("staged queue changed canonical action-bearing digest")

        plan_stage.write_text(
            render_plan(
                plan_path,
                status=args.approval_status,
                projected_at=projected_at,
                queue_sha=queue_sha,
                package_contract_rel=package_contract_rel,
                package_contract_sha=package_contract_sha,
                package_deliverable_manifest_sha=package_deliverable_manifest_sha,
                approval_path_rel=approval_path_rel,
                approval_sha=approval_sha,
                updated_count=len(updated),
            ),
            encoding="utf-8",
        )
        staged_plan_contract = publishing_plan_validator.extract_contract(plan_stage, mode="active")
        validate_schema(
            staged_plan_contract,
            ROOT / "schemas/publishing-plan.schema.json",
            label="staged active publishing plan",
        )

        sync_packages(
            updated,
            package_root=package_stage,
            run_path=run_path,
            content_id=args.content_id,
            status=args.approval_status,
            projected_at=projected_at,
        )
        validate_package_file_set(package_stage, package_targets)

        registry_result: dict[str, Any] | None = None
        staged_destinations: list[tuple[Path, Path]] = [
            (package_stage, package_path),
            (plan_stage, plan_path),
        ]
        if not args.skip_title_registry:
            project_registry(
                registry,
                run_rel=run_rel,
                content_id=args.content_id,
                package_rel=package_rel,
                plan_rel=plan_rel,
                projected_at=projected_at,
            )
            validate_schema(
                registry,
                ROOT / "schemas/title-output-registry.schema.json",
                label="staged title output registry",
            )
            title_registry.dump_yaml(registry_stage, registry)
            staged_destinations.append((registry_stage, registry_path))
            registry_result = {
                "registry_path": registry_rel,
                "status": registry.get("status"),
            }
        staged_destinations.append((queue_stage, queue_path))
        commit_projection(
            staged_destinations=staged_destinations,
            journal_path=journal_path,
            projection_digest_value=digest,
        )
    except (SocialContractError, OSError, ValueError) as exc:
        for path in stage_paths:
            try:
                remove_local_path(path)
            except OSError:
                pass
        print(
            json.dumps(
                {
                    "mode": "blocked_before_or_during_atomic_projection",
                    "error": str(exc),
                    "recovery_journal": repo_relative(ROOT, journal_path),
                },
                ensure_ascii=False,
            )
        )
        return 2

    print(
        json.dumps(
            {
                "mode": "applied_local_projection",
                "updated_rows": len(updated),
                "approval_status": args.approval_status,
                "projection_digest": digest,
                "title_registry": registry_result,
                "recovery_journal": repo_relative(ROOT, journal_path),
                "external_actions": 0,
            },
            ensure_ascii=False,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
