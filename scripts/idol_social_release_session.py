#!/usr/bin/env python3
"""Build or refresh one idempotent post-05 social release decision session.

The command is local-only. It validates exact run-owned inputs, discovers valid
Founder approvals, observes publication/Web/metric closeout facts, and writes a
single decision packet plus a schema-backed read model. It never authors copy,
infers approval, uploads, publishes, deploys, calls a provider, or reads secret
values.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import tempfile
from datetime import datetime
from pathlib import Path
from typing import Any

import yaml  # type: ignore

import validate_publishing_plan as publishing_plan_validator
from lib.idol_social_release_contracts import (
    SocialContractError,
    canonical_object_sha256,
    load_structured,
    package_deliverable_manifest,
    repo_relative,
    sha256_file,
    validate_approval_artifact,
    validate_package_contract,
    validate_queue_asset_linkage,
    validate_queue_scope,
    validate_registry_scope,
    validate_run_owned_path,
    validate_run_scope,
    validate_schema,
)


ROOT = Path(__file__).resolve().parents[1]
SESSION_SCHEMA = ROOT / "schemas/social-release-session.schema.json"
PLAN_SCHEMA = ROOT / "schemas/publishing-plan.schema.json"
GLOBAL_POSTS = ROOT / "analytics/records/platform-posts.jsonl"
GLOBAL_METRICS = ROOT / "analytics/records/platform-metrics.jsonl"
WEB_PUBLICATIONS = ROOT / "web/data/signalDeckPublications.json"
FIXED_WINDOWS = ("T+24h", "T+72h", "T+7d")
APPROVAL_ACTIONS = ("platform_draft_upload", "manual_draft_upload", "public_publish")
SESSION_NAME = "social-release-session-v1.json"
PACKET_NAME = "social-release-decision-packet.md"


class SessionError(SocialContractError):
    """Raised before a session write when the release surface is ambiguous."""


def parse_timestamp(value: str | None) -> str:
    if value:
        try:
            parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError as exc:
            raise SessionError("--at must be an ISO-8601 timestamp") from exc
        if parsed.tzinfo is None or parsed.utcoffset() is None:
            raise SessionError("--at must include a timezone offset")
        return value
    return datetime.now().astimezone().isoformat(timespec="seconds")


def read_jsonl(path: Path) -> list[dict[str, Any]]:
    if not path.is_file():
        return []
    rows: list[dict[str, Any]] = []
    for line_no, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip():
            continue
        try:
            value = json.loads(line)
        except json.JSONDecodeError as exc:
            raise SessionError(f"invalid JSONL at {repo_relative(ROOT, path)}:{line_no}") from exc
        if not isinstance(value, dict):
            raise SessionError(f"JSONL row must be an object at {repo_relative(ROOT, path)}:{line_no}")
        rows.append(value)
    return rows


def read_json(path: Path) -> dict[str, Any]:
    if not path.is_file():
        return {}
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise SessionError(f"invalid JSON: {repo_relative(ROOT, path)}") from exc
    if not isinstance(value, dict):
        raise SessionError(f"JSON root must be an object: {repo_relative(ROOT, path)}")
    return value


def atomic_write(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        mode="wb", prefix=f".{path.name}.", suffix=".tmp", delete=False, dir=path.parent
    ) as handle:
        handle.write(data)
        handle.flush()
        os.fsync(handle.fileno())
        temporary = Path(handle.name)
    try:
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def canonical_digest(value: Any) -> str:
    return canonical_object_sha256(value)


def session_id(content_id: str) -> str:
    compact = "".join(character if character.isalnum() else "_" for character in content_id.upper())
    compact = "_".join(part for part in compact.split("_") if part)
    return f"SOCIAL_{compact}"[:127]


def discover_queue(run_path: Path, content_id: str, explicit: str | None) -> Path:
    if explicit:
        path, _rows, _digest = validate_queue_scope(ROOT, run_path, content_id, explicit)
        return path
    candidates: list[Path] = []
    for path in sorted((run_path / "exports/social").glob("**/platform-posts.jsonl")):
        try:
            validate_queue_scope(ROOT, run_path, content_id, path)
        except SocialContractError:
            continue
        candidates.append(path.resolve())
    if not candidates:
        raise SessionError("no valid run-owned social queue was found; author one mixed-platform queue first")
    if len(candidates) > 1:
        joined = ", ".join(repo_relative(ROOT, path) for path in candidates)
        raise SessionError(
            "multiple valid run-owned queues exist; select --queue once when registering: " + joined
        )
    return candidates[0]


def discover_registry(run_path: Path, run_rel: str, content_id: str, explicit: str | None) -> Path:
    if explicit:
        path, _document = validate_registry_scope(
            repo_root=ROOT, run_rel=run_rel, content_id=content_id, registry=explicit
        )
        return path
    parts = Path(run_rel).parts
    candidates: list[Path] = []
    if len(parts) >= 4:
        direct = ROOT / "catalog/albums" / parts[1] / parts[2] / "output-registry.yaml"
        if direct.is_file():
            candidates.append(direct.resolve())
    if not candidates:
        for path in sorted((ROOT / "catalog/albums").glob("*/*/output-registry.yaml")):
            try:
                validate_registry_scope(
                    repo_root=ROOT, run_rel=run_rel, content_id=content_id, registry=path
                )
            except SocialContractError:
                continue
            candidates.append(path.resolve())
    valid: list[Path] = []
    for path in dict.fromkeys(candidates):
        try:
            validate_registry_scope(
                repo_root=ROOT, run_rel=run_rel, content_id=content_id, registry=path
            )
        except SocialContractError:
            continue
        valid.append(path)
    if len(valid) != 1:
        raise SessionError(
            "expected exactly one title output registry for this run; pass --registry once after resolving ownership"
        )
    return valid[0]


def validate_plan(plan_path: Path, content_id: str) -> dict[str, Any]:
    contract = publishing_plan_validator.extract_contract(plan_path, mode="active")
    validate_schema(contract, PLAN_SCHEMA, label="active publishing plan")
    if str(contract.get("content_id") or "") != content_id:
        raise SessionError("publishing-plan.md content_id does not match the run")
    return contract


def valid_approvals(
    *,
    run_path: Path,
    run_rel: str,
    content_id: str,
    queue_path: Path,
    queue_rows: list[dict[str, Any]],
    queue_action_sha: str,
    package_path: Path,
    package_sha: str,
    package_manifest_sha: str,
) -> tuple[list[dict[str, Any]], list[str]]:
    approvals: list[dict[str, Any]] = []
    warnings: list[str] = []
    review = run_path / "review"
    if not review.is_dir():
        return approvals, warnings
    for path in sorted(review.glob("platform-release-approval-*.*")):
        if path.suffix.lower() not in {".json", ".yaml", ".yml"}:
            continue
        try:
            candidate = load_structured(path)
        except (SocialContractError, OSError, ValueError, json.JSONDecodeError, yaml.YAMLError):
            warnings.append(f"unreadable_approval:{repo_relative(ROOT, path)}")
            continue
        if str(candidate.get("run_root") or "") != run_rel or str(
            candidate.get("content_id") or ""
        ) != content_id:
            continue
        actions = [str(action) for action in (candidate.get("allowed_actions") or [])]
        required = next((action for action in actions if action in APPROVAL_ACTIONS), "")
        if not required:
            warnings.append(f"invalid_approval_actions:{repo_relative(ROOT, path)}")
            continue
        digest = sha256_file(path)
        try:
            _approved_path, document, _sha = validate_approval_artifact(
                repo_root=ROOT,
                run_path=run_path,
                run_rel=run_rel,
                content_id=content_id,
                queue_path=queue_path,
                queue_rows=queue_rows,
                queue_sha256=queue_action_sha,
                package_contract_path=package_path,
                package_contract_sha256=package_sha,
                package_deliverable_manifest_sha256=package_manifest_sha,
                artifact=path,
                expected_sha256=digest,
                required_action=required,
            )
        except SocialContractError as exc:
            warnings.append(f"stale_or_invalid_approval:{repo_relative(ROOT, path)}:{exc}")
            continue
        approvals.append(
            {
                "path": repo_relative(ROOT, path),
                "sha256": digest,
                "allowed_actions": list(document.get("allowed_actions") or []),
                "approved_post_ids": list(document.get("approved_post_ids") or []),
            }
        )
    return approvals, warnings


def external_facts(content_id: str) -> tuple[dict[str, dict[str, Any]], dict[str, set[str]], set[str]]:
    posts = {
        str(row.get("post_id") or ""): row
        for row in read_jsonl(GLOBAL_POSTS)
        if str(row.get("content_id") or "") == content_id
    }
    metric_windows: dict[str, set[str]] = {}
    for row in read_jsonl(GLOBAL_METRICS):
        if str(row.get("content_id") or "") != content_id:
            continue
        window = str(row.get("measurement_window") or "")
        if window in FIXED_WINDOWS:
            metric_windows.setdefault(str(row.get("post_id") or ""), set()).add(window)
    publications = read_json(WEB_PUBLICATIONS).get("publications") or []
    web_ids = {
        str(row.get("post_id") or "")
        for row in publications
        if isinstance(row, dict) and str(row.get("content_id") or "") == content_id
    }
    return posts, metric_windows, web_ids


def target_rows(
    queue_rows: list[dict[str, Any]], approvals: list[dict[str, Any]], content_id: str
) -> list[dict[str, Any]]:
    approved: dict[str, set[str]] = {}
    for approval in approvals:
        for post_id in approval["approved_post_ids"]:
            approved.setdefault(str(post_id), set()).update(approval["allowed_actions"])
    global_posts, metric_windows, web_ids = external_facts(content_id)
    targets: list[dict[str, Any]] = []
    for row in queue_rows:
        post_id = str(row["post_id"])
        public_row = global_posts.get(post_id) or {}
        published_url = str(public_row.get("published_url") or row.get("published_url") or "")
        published_at = str(public_row.get("published_at") or row.get("published_at") or "")
        published = bool(
            (public_row.get("status") == "published" or row.get("status") == "published")
            and published_at
            and (published_url or public_row.get("platform_post_id") or row.get("platform_post_id"))
        )
        platform = str(row.get("platform") or "")
        target: dict[str, Any] = {
            "post_id": post_id,
            "platform": platform,
            "delivery_mode": str(row.get("delivery_mode") or "manual"),
            "post_status": "published" if published else str(row.get("status") or "planned"),
            "draft_status": str(row.get("draft_status") or ""),
            "approval_actions": sorted(approved.get(post_id, set())),
            "published": published,
            "published_url": published_url,
            "published_at": published_at,
            "web_projection": (
                "not_applicable_x"
                if platform == "x"
                else ("registered" if post_id in web_ids else "not_registered")
            ),
            "metric_windows": [window for window in FIXED_WINDOWS if window in metric_windows.get(post_id, set())],
        }
        targets.append(target)
    return targets


def derive_state(targets: list[dict[str, Any]], blockers: list[str]) -> tuple[str, str]:
    if blockers:
        return "hold", "resolve_blocker"
    active = [target for target in targets if target["post_status"] != "skipped"]
    published = [target for target in active if target["published"]]
    terminal = bool(active) and len(published) == len(active)
    if terminal:
        complete = all(set(target["metric_windows"]) == set(FIXED_WINDOWS) for target in published)
        return ("measured", "none") if complete else ("closed_metrics_due", "fixed_checkpoint_collection")
    draft_ready = any(
        str(target.get("draft_status") or "").startswith("uploaded_")
        or str(target.get("draft_status") or "") in {"draft_ready", "manual_package_ready"}
        for target in active
    )
    if draft_ready:
        return "publication_facts_required", "public_url_and_published_at"
    pending = [target for target in active if not target["published"]]
    if pending and all(target["approval_actions"] for target in pending):
        return "approved_waiting_external", "external_action_requires_current_authority"
    return "founder_review", "founder_decision"


def packet_text(
    *,
    content_id: str,
    run_rel: str,
    state_digest: str,
    status: str,
    next_action: str,
    queue_rows: list[dict[str, Any]],
    targets: list[dict[str, Any]],
    warnings: list[str],
    blockers: list[str],
) -> str:
    by_id = {target["post_id"]: target for target in targets}
    lines = [
        f"# SNS Release Decision — {content_id}",
        "",
        f"- 상태: `{status}`",
        f"- 다음 동작: `{next_action}`",
        f"- 상태 해시: `{state_digest}`",
        f"- 런: `{run_rel}`",
        "- 외부 업로드·게시·배포 실행: `0`",
        "",
        "## 한 번에 판단할 대상",
        "",
        "| Post ID | 플랫폼 | 전달 | 현재 상태 | 승인 범위 | Web | 측정 |",
        "| --- | --- | --- | --- | --- | --- | --- |",
    ]
    for row in queue_rows:
        target = by_id[str(row["post_id"])]
        approval = ", ".join(target["approval_actions"]) or "미승인"
        metrics = ", ".join(target["metric_windows"]) or "없음"
        lines.append(
            "| {post_id} | {platform} | {delivery} | {state} | {approval} | {web} | {metrics} |".format(
                post_id=str(row["post_id"]).replace("|", "\\|"),
                platform=target["platform"],
                delivery=target["delivery_mode"],
                state="published" if target["published"] else (target["draft_status"] or target["post_status"]),
                approval=approval,
                web=target["web_projection"],
                metrics=metrics,
            )
        )
    lines.extend(["", "## 플랫폼별 최종 문구", ""])
    for row in queue_rows:
        lines.extend(
            [
                f"### {row['post_id']} · {row.get('platform', '')}",
                "",
                f"- 파일: `{row.get('asset_or_clip', '')}`",
                f"- 예약 시각: `{row.get('scheduled_at', '')}`",
                f"- 제목: {row.get('title') or '(없음)' }",
                "- 캡션:",
                "",
            ]
        )
        caption = str(row.get("caption") or "")
        lines.extend([f"    {line}" if line else "    " for line in caption.splitlines() or [""]])
        lines.extend(["", f"- 해시태그: {' '.join(row.get('hashtags') or [])}", ""])
    if warnings:
        lines.extend(["## 자동 확인 경고", ""] + [f"- `{warning}`" for warning in warnings] + [""])
    if blockers:
        lines.extend(["## 중단 사유", ""] + [f"- `{blocker}`" for blocker in blockers] + [""])
    if status == "founder_review":
        lines.extend(
            [
                "## 답변은 한 번만",
                "",
                "아래 중 하나만 답하면 됩니다. 답변 뒤에는 정확한 큐·파일 해시에 묶인 승인 기록을 만들고, 같은 입력은 다시 묻지 않습니다.",
                "",
                "- `PASS DRAFT` — 표의 exact bytes를 승인된 플랫폼 초안 업로드 범위로 진행",
                "- `PASS MANUAL` — 로컬 수동 업로드 패키지만 확정",
                "- `PASS PUBLIC` — 표의 exact bytes와 문구에 대한 공개 게시 승인",
                "- `수정 — POST_ID: 바꿀 내용`",
                "- `HOLD — 이유`",
                "",
                "`PASS`만으로는 외부 업로드나 공개 게시 권한을 추정하지 않습니다.",
            ]
        )
    elif next_action == "external_action_requires_current_authority":
        lines.extend(
            [
                "## 재판단 불필요",
                "",
                "현재 exact approval이 유효합니다. 허용된 외부 동작만 별도 실행하고 결과를 같은 세션에 이어 붙이면 됩니다.",
            ]
        )
    elif next_action == "public_url_and_published_at":
        lines.extend(
            [
                "## 남은 사실 입력",
                "",
                "공개가 끝난 항목의 실제 public URL과 `published_at`만 받으면 원장·Signal Deck·고정 체크포인트를 한 번에 닫습니다.",
            ]
        )
    elif next_action == "fixed_checkpoint_collection":
        lines.extend(
            [
                "## 자동 분석 대기",
                "",
                "공개 시각을 기준으로 T+24h, T+72h, T+7d만 수집합니다. 장기 백필·임의 스냅샷은 고정 체크포인트로 재분류하지 않습니다.",
            ]
        )
    return "\n".join(lines).rstrip() + "\n"


def build_session(
    *,
    run_path: Path,
    run_rel: str,
    content_id: str,
    queue_path: Path,
    registry_path: Path,
    manual_package: Path,
    at: str,
    existing: dict[str, Any] | None,
) -> tuple[dict[str, Any], bytes, bool, list[str]]:
    package_path, package_document, deliverables = validate_package_contract(
        repo_root=ROOT,
        run_path=run_path,
        content_id=content_id,
        package_contract=run_path / "05-package.yaml",
        require_final_lineage=False,
    )
    package_sha = sha256_file(package_path)
    package_manifest = package_deliverable_manifest(
        repo_root=ROOT, run_path=run_path, document=package_document, deliverables=deliverables
    )
    package_manifest_sha = canonical_digest(package_manifest)
    queue_path, queue_rows, queue_action_sha = validate_queue_scope(
        ROOT, run_path, content_id, queue_path
    )
    plan_path = validate_run_owned_path(
        ROOT,
        run_path,
        run_path / "publishing-plan.md",
        "publishing plan",
        must_exist=True,
        file_only=True,
    )
    validate_plan(plan_path, content_id)
    registry_path, _registry = validate_registry_scope(
        repo_root=ROOT, run_rel=run_rel, content_id=content_id, registry=registry_path
    )
    linkages = validate_queue_asset_linkage(
        repo_root=ROOT, run_path=run_path, rows=queue_rows, deliverables=deliverables
    )
    assets = [
        {
            "post_id": item["post_id"],
            "path": item["asset_path"],
            "sha256": item["asset_sha256"],
            "package_output_id": item["package_output_id"],
            "package_output_role": item["package_output_role"],
            "linkage": item["linkage"],
        }
        for item in linkages
    ]
    approvals, warnings = valid_approvals(
        run_path=run_path,
        run_rel=run_rel,
        content_id=content_id,
        queue_path=queue_path,
        queue_rows=queue_rows,
        queue_action_sha=queue_action_sha,
        package_path=package_path,
        package_sha=package_sha,
        package_manifest_sha=package_manifest_sha,
    )
    targets = target_rows(queue_rows, approvals, content_id)
    blockers: list[str] = []
    if any(bool(row.get("draft_attempt_reconciliation_required")) for row in queue_rows):
        blockers.append("ambiguous_external_attempt_requires_reconciliation")
    status, next_action = derive_state(targets, blockers)
    source_bindings = {
        "queue": {
            "path": repo_relative(ROOT, queue_path),
            "sha256": sha256_file(queue_path),
            "action_sha256": queue_action_sha,
        },
        "package_contract": {
            "path": repo_relative(ROOT, package_path),
            "sha256": package_sha,
            "deliverable_manifest_sha256": package_manifest_sha,
        },
        "publishing_plan": {
            "path": repo_relative(ROOT, plan_path),
            "sha256": sha256_file(plan_path),
        },
        "title_registry": {
            "path": repo_relative(ROOT, registry_path),
            "sha256": sha256_file(registry_path),
        },
    }
    state_material = {
        "source_bindings": source_bindings,
        "assets": assets,
        "targets": targets,
        "approval_artifacts": approvals,
        "status": status,
        "next_action": next_action,
        "blockers": blockers,
        "warnings": warnings,
    }
    state_digest = canonical_digest(state_material)
    old_digest = str((existing or {}).get("state_digest") or "")
    changed = old_digest != state_digest
    packet_path = run_path / "review" / PACKET_NAME
    packet = packet_text(
        content_id=content_id,
        run_rel=run_rel,
        state_digest=state_digest,
        status=status,
        next_action=next_action,
        queue_rows=queue_rows,
        targets=targets,
        warnings=warnings,
        blockers=blockers,
    ).encode("utf-8")
    registered_at = str((existing or {}).get("registered_at") or at)
    refreshed_at = at if changed or not existing else str(existing.get("refreshed_at") or at)
    session = {
        "schema_version": "idol_social_release_session.v1",
        "session_id": session_id(content_id),
        "run_root": run_rel,
        "content_id": content_id,
        "status": status,
        "registered_at": registered_at,
        "refreshed_at": refreshed_at,
        "state_digest": state_digest,
        "source_bindings": source_bindings,
        "assets": assets,
        "targets": targets,
        "approval_artifacts": approvals,
        "decision_packet": {
            "path": repo_relative(ROOT, packet_path),
            "sha256": hashlib.sha256(packet).hexdigest(),
        },
        "manual_package": repo_relative(ROOT, manual_package),
        "next_action": next_action,
        "blockers": blockers,
        "external_actions_performed": 0,
    }
    validate_schema(session, SESSION_SCHEMA, label="social release session")
    return session, packet, changed, warnings


def print_result(mode: str, session: dict[str, Any], changed: bool, warnings: list[str]) -> None:
    print(
        json.dumps(
            {
                "mode": mode,
                "session": session["decision_packet"]["path"].replace(PACKET_NAME, SESSION_NAME),
                "decision_packet": session["decision_packet"]["path"],
                "status": session["status"],
                "next_action": session["next_action"],
                "state_digest": session["state_digest"],
                "changed": changed,
                "warnings": warnings,
                "external_actions": 0,
            },
            ensure_ascii=False,
            indent=2,
        )
    )


def register(args: argparse.Namespace) -> int:
    at = parse_timestamp(args.at)
    package = load_structured((ROOT / args.run_root / "05-package.yaml").resolve())
    content_id = str(package.get("content_id") or "")
    if not content_id:
        raise SessionError("05-package.yaml is missing content_id")
    run_path, run_rel = validate_run_scope(ROOT, args.run_root, content_id)
    session_path = run_path / "review" / SESSION_NAME
    if session_path.exists():
        raise SessionError("social release session already exists; use refresh instead of registering twice")
    queue_path = discover_queue(run_path, content_id, args.queue)
    registry_path = discover_registry(run_path, run_rel, content_id, args.registry)
    manual_package = (
        validate_run_owned_path(
            ROOT, run_path, args.manual_package, "manual package", must_exist=False
        )
        if args.manual_package
        else run_path / "exports/social/release-package" / queue_path.parent.name
    )
    session, packet, changed, warnings = build_session(
        run_path=run_path,
        run_rel=run_rel,
        content_id=content_id,
        queue_path=queue_path,
        registry_path=registry_path,
        manual_package=manual_package,
        at=at,
        existing=None,
    )
    if args.apply:
        atomic_write(run_path / "review" / PACKET_NAME, packet)
        atomic_write(session_path, (json.dumps(session, ensure_ascii=False, indent=2) + "\n").encode())
        mode = "registered"
    else:
        mode = "dry_run"
    print_result(mode, session, changed, warnings)
    return 0


def refresh(args: argparse.Namespace) -> int:
    at = parse_timestamp(args.at)
    session_path = (ROOT / args.session).resolve() if not Path(args.session).is_absolute() else Path(args.session).resolve()
    if session_path.name != SESSION_NAME or not session_path.is_file():
        raise SessionError(f"--session must be an existing run-owned review/{SESSION_NAME}")
    existing = read_json(session_path)
    validate_schema(existing, SESSION_SCHEMA, label="existing social release session")
    run_path, run_rel = validate_run_scope(ROOT, existing["run_root"], existing["content_id"])
    try:
        session_path.relative_to(run_path / "review")
    except ValueError as exc:
        raise SessionError("session must stay under its declared run review folder") from exc
    queue_path = validate_run_owned_path(
        ROOT,
        run_path,
        existing["source_bindings"]["queue"]["path"],
        "session queue",
        must_exist=True,
        file_only=True,
    )
    registry_path = (ROOT / existing["source_bindings"]["title_registry"]["path"]).resolve()
    manual_package = validate_run_owned_path(
        ROOT, run_path, existing["manual_package"], "manual package", must_exist=False
    )
    session, packet, changed, warnings = build_session(
        run_path=run_path,
        run_rel=run_rel,
        content_id=existing["content_id"],
        queue_path=queue_path,
        registry_path=registry_path,
        manual_package=manual_package,
        at=at,
        existing=existing,
    )
    packet_path = run_path / "review" / PACKET_NAME
    bytes_changed = not packet_path.is_file() or packet_path.read_bytes() != packet
    if args.apply and (changed or bytes_changed):
        atomic_write(packet_path, packet)
        atomic_write(session_path, (json.dumps(session, ensure_ascii=False, indent=2) + "\n").encode())
        mode = "refreshed"
    elif args.apply:
        mode = "unchanged"
    else:
        mode = "dry_run"
    print_result(mode, session, changed or bytes_changed, warnings)
    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    register_parser = subparsers.add_parser("register", help="Register one finished-content run once.")
    register_parser.add_argument("--run-root", required=True)
    register_parser.add_argument("--queue")
    register_parser.add_argument("--registry")
    register_parser.add_argument("--manual-package")
    register_parser.add_argument("--at")
    register_parser.add_argument("--apply", action="store_true")
    refresh_parser = subparsers.add_parser("refresh", help="Refresh from stored pointers and skip unchanged work.")
    refresh_parser.add_argument("--session", required=True)
    refresh_parser.add_argument("--at")
    refresh_parser.add_argument("--apply", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        return register(args) if args.command == "register" else refresh(args)
    except (SocialContractError, OSError, ValueError, KeyError) as exc:
        print(json.dumps({"mode": "blocked", "error": str(exc), "external_actions": 0}, ensure_ascii=False))
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
