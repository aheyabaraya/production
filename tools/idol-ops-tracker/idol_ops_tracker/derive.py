from __future__ import annotations

import copy
from datetime import date, datetime, time, timezone
from typing import Any

from .constants import PRIORITY_ORDER
from .operations import collect_operations
from .sources import collect_source_catalog, probe_git_repo, repo_identity


def _parse_datetime(value: str | None) -> datetime | None:
    if not value:
        return None
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed


def _parse_date(value: str | None) -> date | None:
    if not value:
        return None
    try:
        return date.fromisoformat(value)
    except ValueError:
        return None


def _date_at_end_of_day(value: date, now: datetime) -> datetime:
    return datetime.combine(value, time.max, tzinfo=now.tzinfo)


def _source_map(catalog: list[dict[str, Any]]) -> dict[str, dict[str, Any]]:
    return {item["path"]: item for item in catalog}


def _evidence_state(refs: list[str], source_by_path: dict[str, dict[str, Any]], required: bool) -> tuple[str, list[str]]:
    if not refs:
        return ("missing" if required else "not_required"), ([] if not required else ["증거 경로 미등록"])
    missing = [
        ref
        for ref in refs
        if not source_by_path.get(ref, {}).get("exists")
        or source_by_path.get(ref, {}).get("kind") != "file"
    ]
    if missing:
        return "missing", [f"증거 파일 없음 또는 파일이 아님: {ref}" for ref in missing]
    return "verified", []


def _derive_milestone(
    milestone: dict[str, Any],
    source_by_path: dict[str, dict[str, Any]],
    now: datetime,
) -> dict[str, Any]:
    item = copy.deepcopy(milestone)
    evidence_state, evidence_warnings = _evidence_state(
        item.get("evidence_refs", []),
        source_by_path,
        bool(item.get("evidence_required")),
    )
    gate_ok = item.get("gate_status") in {"pass", "not_required"}
    verified_complete = (
        item.get("status") == "completed"
        and gate_ok
        and evidence_state in {"verified", "not_required"}
    )
    target = _parse_date(item.get("target_date"))
    overdue = bool(
        target
        and _date_at_end_of_day(target, now) < now
        and item.get("status") not in {"completed", "canceled"}
    )
    warnings = list(evidence_warnings)
    if item.get("status") == "completed" and not gate_ok:
        warnings.append("완료 표기지만 gate PASS가 아님")
    if overdue:
        warnings.append("마일스톤 목표일 경과")
    item["derived"] = {
        "evidence_state": evidence_state,
        "gate_ok": gate_ok,
        "verified_complete": verified_complete,
        "overdue": overdue,
        "warnings": warnings,
    }
    return item


def _derive_progress(project: dict[str, Any]) -> dict[str, Any]:
    baseline_locked = project.get("baseline", {}).get("state") == "locked"
    total_weight = sum(float(m.get("weight", 0)) for m in project.get("milestones", []))
    verified_weight = sum(
        float(m.get("weight", 0))
        for m in project.get("milestones", [])
        if m.get("derived", {}).get("verified_complete")
    )
    if not baseline_locked or total_weight <= 0:
        return {
            "available": False,
            "percent": None,
            "verified_weight": round(verified_weight, 2),
            "total_weight": round(total_weight, 2),
            "reason": "Founder 기준선 확정 전",
        }
    return {
        "available": True,
        "percent": round((verified_weight / total_weight) * 100, 1),
        "verified_weight": round(verified_weight, 2),
        "total_weight": round(total_weight, 2),
        "reason": None,
    }


def _derive_schedule(project: dict[str, Any], now: datetime) -> dict[str, Any]:
    start = _parse_date(project.get("start_date"))
    target = _parse_date(project.get("target_date"))
    review = _parse_datetime(project.get("next_review_at"))
    target_overdue = bool(
        target
        and _date_at_end_of_day(target, now) < now
        and project.get("status") not in {"completed", "canceled"}
    )
    review_overdue = bool(review and review < now and project.get("status") not in {"completed", "canceled"})
    elapsed_percent: float | None = None
    if start and target and target >= start:
        total_days = max(1, (target - start).days)
        elapsed_days = max(0, min(total_days, (now.date() - start).days))
        elapsed_percent = round((elapsed_days / total_days) * 100, 1)
    return {
        "start_date": start.isoformat() if start else None,
        "target_date": target.isoformat() if target else None,
        "next_review_at": review.isoformat(timespec="seconds") if review else None,
        "target_overdue": target_overdue,
        "review_overdue": review_overdue,
        "elapsed_percent": elapsed_percent,
        "dates_complete": bool(start and target),
    }


def _derive_source_health(project: dict[str, Any], source_by_path: dict[str, dict[str, Any]]) -> dict[str, Any]:
    refs = project.get("source_refs", [])
    if not refs:
        return {"state": "unverified", "missing": [], "latest_modified_at": None}
    missing = [ref for ref in refs if not source_by_path.get(ref, {}).get("exists")]
    modified = [
        source_by_path[ref].get("modified_at")
        for ref in refs
        if source_by_path.get(ref, {}).get("exists") and source_by_path[ref].get("modified_at")
    ]
    if missing:
        state = "missing"
    else:
        state = "available"
    return {
        "state": state,
        "missing": missing,
        "latest_modified_at": max(modified) if modified else None,
    }


def _derive_observed_health(project: dict[str, Any]) -> tuple[str, list[str]]:
    warnings: list[str] = []
    if project.get("baseline", {}).get("state") != "locked":
        warnings.append("Founder 기준선 미확정")
    if not project.get("next_action", "").strip():
        warnings.append("다음 행동 미등록")
    if project.get("source_health", {}).get("state") == "missing":
        warnings.append("원본 경로 누락")

    open_blockers = [b for b in project.get("blockers", []) if b.get("status") == "open"]
    held_milestones = [m for m in project.get("milestones", []) if m.get("gate_status") in {"hold", "reject"}]
    overdue_milestones = [m for m in project.get("milestones", []) if m.get("derived", {}).get("overdue")]
    schedule = project.get("schedule", {})
    progress = project.get("progress", {})

    if open_blockers:
        warnings.append(f"열린 blocker {len(open_blockers)}개")
    if held_milestones:
        warnings.append(f"HOLD/REJECT 마일스톤 {len(held_milestones)}개")
    if schedule.get("target_overdue"):
        warnings.append("프로젝트 목표일 경과")
    if schedule.get("review_overdue"):
        warnings.append("정기 점검 시각 경과")
    if overdue_milestones:
        warnings.append(f"기한 경과 마일스톤 {len(overdue_milestones)}개")

    behind_schedule = bool(
        progress.get("available")
        and schedule.get("elapsed_percent") is not None
        and progress.get("percent", 0) + 10 < schedule["elapsed_percent"]
        and project.get("status") in {"in_progress", "review"}
    )
    if behind_schedule:
        warnings.append("기간 경과율 대비 검증 완료율 지연")

    if open_blockers or held_milestones:
        return "blocked", warnings
    if schedule.get("target_overdue") or schedule.get("review_overdue") or overdue_milestones or behind_schedule:
        return "attention", warnings
    if project.get("baseline", {}).get("state") != "locked":
        return "unknown", warnings
    return "on_track", warnings


def _derive_decision(decision: dict[str, Any], now: datetime) -> dict[str, Any]:
    item = copy.deepcopy(decision)
    needed_by = _parse_date(item.get("needed_by"))
    item["derived"] = {
        "overdue": bool(
            needed_by
            and _date_at_end_of_day(needed_by, now) < now
            and item.get("status") == "pending"
        )
    }
    return item


def _derive_execution(execution: dict[str, Any], source_by_path: dict[str, dict[str, Any]]) -> dict[str, Any]:
    item = copy.deepcopy(execution)
    evidence_state, evidence_warnings = _evidence_state(
        item.get("evidence_refs", []),
        source_by_path,
        item.get("result_state") == "verified",
    )
    item["derived"] = {
        "evidence_state": evidence_state,
        "warnings": evidence_warnings,
        "counts_toward_progress": False,
    }
    return item


def derive_state(state: dict[str, Any], now: datetime | None = None) -> dict[str, Any]:
    now = now or datetime.now().astimezone()
    result = copy.deepcopy(state)
    source_catalog = collect_source_catalog(result, now)
    source_by_path = _source_map(source_catalog)

    lane_by_id = {lane["id"]: lane for lane in result.get("lanes", [])}
    projects: list[dict[str, Any]] = []
    for project in result.get("projects", []):
        item = copy.deepcopy(project)
        item["lane"] = copy.deepcopy(lane_by_id.get(item.get("lane_id"), {}))
        item["milestones"] = [
            _derive_milestone(milestone, source_by_path, now)
            for milestone in item.get("milestones", [])
        ]
        item["progress"] = _derive_progress(item)
        item["schedule"] = _derive_schedule(item, now)
        item["source_health"] = _derive_source_health(item, source_by_path)
        observed_health, warnings = _derive_observed_health(item)
        item["observed_health"] = observed_health
        item["warnings"] = warnings
        projects.append(item)

    projects.sort(key=lambda project: (PRIORITY_ORDER.get(project.get("priority"), 99), project.get("title", "")))
    decisions = [_derive_decision(decision, now) for decision in result.get("decisions", [])]
    executions = [_derive_execution(execution, source_by_path) for execution in result.get("executions", [])]

    active_projects = [p for p in projects if p.get("status") not in {"completed", "canceled"}]
    measurable = [p for p in active_projects if p.get("progress", {}).get("available")]
    verified_progress = None
    if measurable:
        verified_progress = round(
            sum(p["progress"]["percent"] for p in measurable) / len(measurable),
            1,
        )
    attention_projects = [p for p in active_projects if p.get("observed_health") in {"attention", "blocked"}]
    pending_decisions = [d for d in decisions if d.get("status") == "pending"]
    stale_sources = [source for source in source_catalog if not source.get("exists")]
    running_executions = [
        execution
        for execution in executions
        if execution.get("status") in {"queued", "running", "waiting_for_input", "awaiting_review", "blocked"}
    ]

    focus_items = []
    for project in active_projects:
        if project.get("next_action") or project.get("warnings"):
            focus_items.append(
                {
                    "project_id": project["id"],
                    "title": project["title"],
                    "priority": project["priority"],
                    "next_action": project.get("next_action") or "다음 행동 미등록",
                    "health": project.get("observed_health"),
                    "warnings": project.get("warnings", []),
                }
            )

    result["projects"] = projects
    result["decisions"] = decisions
    result["executions"] = executions
    result["derived"] = {
        "generated_at": now.isoformat(timespec="seconds"),
        "repo": repo_identity(),
        "operations": collect_operations(now=now),
        "summary": {
            "active_projects": len(active_projects),
            "measurable_projects": len(measurable),
            "verified_progress": verified_progress,
            "attention_projects": len(attention_projects),
            "pending_decisions": len(pending_decisions),
            "missing_sources": len(stale_sources),
            "active_executions": len(running_executions),
            "baseline_pending": len([p for p in active_projects if p.get("baseline", {}).get("state") != "locked"]),
        },
        "focus_items": focus_items,
        "source_catalog": source_catalog,
        "git_repositories": [probe_git_repo(spec) for spec in result.get("source_repositories", [])],
        "methodology": {
            "progress": "잠긴 기준선에서 status=completed, gate=PASS/not_required, 필수 evidence 존재를 모두 만족한 가중치만 합산",
            "ai_execution": "AI 실행 상태와 파일 수는 완료율에 포함하지 않음",
            "source_boundary": "IDOL 원본은 metadata와 run/dispatch의 운영 필드만 읽고, 쓰기는 tracker.json으로 제한",
        },
    }
    return result
