from __future__ import annotations

import copy
import re
from datetime import datetime
from typing import Any
from uuid import uuid4

from .constants import (
    WRITABLE_DECISION_FIELDS,
    WRITABLE_EXECUTION_FIELDS,
    WRITABLE_MILESTONE_FIELDS,
    WRITABLE_PROJECT_FIELDS,
)
from .paths import resolve_repo_path


class TrackerActionError(ValueError):
    pass


BASELINE_SCOPE_FIELDS = {"id", "title", "weight", "evidence_required"}


def _find(items: list[dict[str, Any]], item_id: str, label: str) -> dict[str, Any]:
    for item in items:
        if item.get("id") == item_id:
            return item
    raise TrackerActionError(f"{label} not found: {item_id}")


def _patch(target: dict[str, Any], patch: dict[str, Any], allowed: set[str]) -> None:
    unexpected = sorted(set(patch) - allowed)
    if unexpected:
        raise TrackerActionError(f"unsupported fields: {', '.join(unexpected)}")
    for key, value in patch.items():
        target[key] = copy.deepcopy(value)


def _slug(value: str) -> str:
    normalized = re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")
    return normalized[:48] or "project"


def _new_id(prefix: str, title: str) -> str:
    return f"{prefix}-{_slug(title)}-{uuid4().hex[:6]}"


def _template(state: dict[str, Any], template_id: str) -> dict[str, Any]:
    return _find(state.get("templates", []), template_id, "template")


def _copy_milestones(template: dict[str, Any]) -> list[dict[str, Any]]:
    milestones = copy.deepcopy(template.get("milestones", []))
    for milestone in milestones:
        milestone.setdefault("evidence_refs", [])
        milestone.setdefault("start_date", None)
        milestone.setdefault("target_date", None)
        milestone.setdefault("owner", "")
        milestone.setdefault("note", "")
    return milestones


def _guard_locked_baseline(project: dict[str, Any], milestones: Any) -> None:
    """Keep scope and completion criteria immutable after Founder lock."""

    if project.get("baseline", {}).get("state") != "locked":
        return
    if not isinstance(milestones, list):
        raise TrackerActionError("milestones must be a list")
    current = {item.get("id"): item for item in project.get("milestones", [])}
    proposed = {item.get("id"): item for item in milestones if isinstance(item, dict)}
    if set(current) != set(proposed):
        raise TrackerActionError("locked baseline milestone set cannot change")
    for milestone_id, current_item in current.items():
        proposed_item = proposed[milestone_id]
        for field in BASELINE_SCOPE_FIELDS:
            if proposed_item.get(field) != current_item.get(field):
                raise TrackerActionError(
                    f"locked baseline field cannot change: {milestone_id}.{field}"
                )


def _guard_milestone_set(project: dict[str, Any], milestones: Any) -> None:
    if not isinstance(milestones, list) or not all(isinstance(item, dict) for item in milestones):
        raise TrackerActionError("milestones must be a list of objects")
    current_ids = [item.get("id") for item in project.get("milestones", [])]
    proposed_ids = [item.get("id") for item in milestones]
    if current_ids != proposed_ids:
        raise TrackerActionError("milestone identity and order must use dedicated tracker actions")


def _guard_project_completion(project: dict[str, Any]) -> None:
    if project.get("status") != "completed":
        return
    if project.get("baseline", {}).get("state") != "locked":
        raise TrackerActionError("project completion requires a locked Founder baseline")
    if any(blocker.get("status") == "open" for blocker in project.get("blockers", [])):
        raise TrackerActionError("project completion requires all blockers to be resolved")
    for milestone in project.get("milestones", []):
        milestone_id = milestone.get("id", "unknown")
        if milestone.get("status") != "completed":
            raise TrackerActionError(f"project completion requires completed milestone: {milestone_id}")
        if milestone.get("gate_status") not in {"pass", "not_required"}:
            raise TrackerActionError(f"project completion requires PASS gate: {milestone_id}")
        if milestone.get("evidence_required"):
            refs = milestone.get("evidence_refs", [])
            if not refs:
                raise TrackerActionError(f"project completion requires evidence: {milestone_id}")
            for ref in refs:
                if not resolve_repo_path(ref).is_file():
                    raise TrackerActionError(f"project completion evidence is missing: {ref}")


def apply_action(state: dict[str, Any], payload: dict[str, Any], now: datetime) -> dict[str, Any]:
    if not isinstance(payload, dict):
        raise TrackerActionError("action payload must be an object")
    action = payload.get("action")
    updated = copy.deepcopy(state)

    if action == "create_project":
        template = _template(updated, str(payload.get("template_id", "")))
        title = str(payload.get("title", "")).strip()
        if not title:
            raise TrackerActionError("project title is required")
        project_id = _new_id("project", title)
        project = {
            "id": project_id,
            "lane_id": template["lane_id"],
            "title": title,
            "objective": str(payload.get("objective", "")).strip(),
            "owner": str(payload.get("owner", "Founder")).strip() or "Founder",
            "status": "baseline_pending",
            "declared_health": "unknown",
            "priority": payload.get("priority", "P2"),
            "start_date": payload.get("start_date") or None,
            "target_date": payload.get("target_date") or None,
            "next_review_at": payload.get("next_review_at") or None,
            "review_cadence_days": int(payload.get("review_cadence_days", 7)),
            "next_action": str(payload.get("next_action", "기준선과 첫 마일스톤 상태 확정")).strip(),
            "source_refs": copy.deepcopy(template.get("source_refs", [])),
            "baseline": {"state": "draft", "revision": 0, "locked_at": None, "locked_by": None},
            "milestones": _copy_milestones(template),
            "blockers": [],
            "created_at": now.isoformat(timespec="seconds"),
        }
        updated.setdefault("projects", []).append(project)

    elif action == "update_project":
        project = _find(updated.get("projects", []), str(payload.get("project_id", "")), "project")
        patch = payload.get("patch")
        if not isinstance(patch, dict):
            raise TrackerActionError("project patch must be an object")
        if "milestones" in patch:
            _guard_milestone_set(project, patch["milestones"])
            _guard_locked_baseline(project, patch["milestones"])
        _patch(project, patch, WRITABLE_PROJECT_FIELDS)
        _guard_project_completion(project)

    elif action == "lock_baseline":
        project = _find(updated.get("projects", []), str(payload.get("project_id", "")), "project")
        total_weight = sum(float(milestone.get("weight", 0)) for milestone in project.get("milestones", []))
        if round(total_weight, 6) != 100.0:
            raise TrackerActionError(f"milestone weights must total 100 before lock (got {total_weight:g})")
        baseline = project.setdefault("baseline", {})
        baseline["state"] = "locked"
        baseline["revision"] = int(baseline.get("revision", 0)) + 1
        baseline["locked_at"] = now.isoformat(timespec="seconds")
        baseline["locked_by"] = str(payload.get("locked_by", "Founder")).strip() or "Founder"
        if project.get("status") == "baseline_pending":
            project["status"] = "planned"

    elif action == "update_milestone":
        project = _find(updated.get("projects", []), str(payload.get("project_id", "")), "project")
        milestone = _find(project.get("milestones", []), str(payload.get("milestone_id", "")), "milestone")
        patch = payload.get("patch")
        if not isinstance(patch, dict):
            raise TrackerActionError("milestone patch must be an object")
        if project.get("baseline", {}).get("state") == "locked" and set(patch) & BASELINE_SCOPE_FIELDS:
            raise TrackerActionError("locked baseline scope and completion criteria cannot change")
        _patch(milestone, patch, WRITABLE_MILESTONE_FIELDS)
        _guard_project_completion(project)

    elif action == "add_milestone":
        project = _find(updated.get("projects", []), str(payload.get("project_id", "")), "project")
        if project.get("baseline", {}).get("state") == "locked":
            raise TrackerActionError("cannot add a milestone to a locked baseline")
        title = str(payload.get("title", "")).strip()
        if not title:
            raise TrackerActionError("milestone title is required")
        project.setdefault("milestones", []).append(
            {
                "id": _new_id("milestone", title),
                "title": title,
                "weight": float(payload.get("weight", 1)),
                "status": "not_started",
                "gate_status": "pending",
                "evidence_required": True,
                "evidence_refs": [],
                "start_date": None,
                "target_date": None,
                "owner": "",
                "note": "",
            }
        )

    elif action == "add_blocker":
        project = _find(updated.get("projects", []), str(payload.get("project_id", "")), "project")
        title = str(payload.get("title", "")).strip()
        if not title:
            raise TrackerActionError("blocker title is required")
        project.setdefault("blockers", []).append(
            {
                "id": _new_id("blocker", title),
                "title": title,
                "status": "open",
                "owner": str(payload.get("owner", "Founder")).strip() or "Founder",
                "opened_at": now.isoformat(timespec="seconds"),
                "resolved_at": None,
            }
        )

    elif action == "resolve_blocker":
        project = _find(updated.get("projects", []), str(payload.get("project_id", "")), "project")
        blocker = _find(project.get("blockers", []), str(payload.get("blocker_id", "")), "blocker")
        blocker["status"] = "resolved"
        blocker["resolved_at"] = now.isoformat(timespec="seconds")

    elif action == "add_decision":
        title = str(payload.get("title", "")).strip()
        if not title:
            raise TrackerActionError("decision title is required")
        project_id = payload.get("project_id") or None
        if project_id:
            _find(updated.get("projects", []), str(project_id), "project")
        decision = {
            "id": _new_id("decision", title),
            "title": title,
            "project_id": project_id,
            "owner": str(payload.get("owner", "Founder")).strip() or "Founder",
            "status": "pending",
            "needed_by": payload.get("needed_by") or None,
            "impact": str(payload.get("impact", "")).strip(),
            "source_refs": list(payload.get("source_refs", [])),
            "created_at": now.isoformat(timespec="seconds"),
            "resolved_at": None,
            "resolution": "",
        }
        updated.setdefault("decisions", []).append(decision)

    elif action == "update_decision":
        decision = _find(updated.get("decisions", []), str(payload.get("decision_id", "")), "decision")
        patch = payload.get("patch")
        if not isinstance(patch, dict):
            raise TrackerActionError("decision patch must be an object")
        _patch(decision, patch, WRITABLE_DECISION_FIELDS)
        if decision.get("status") != "pending" and not decision.get("resolved_at"):
            decision["resolved_at"] = now.isoformat(timespec="seconds")

    elif action == "add_execution":
        title = str(payload.get("title", "")).strip()
        if not title:
            raise TrackerActionError("execution title is required")
        project_id = str(payload.get("project_id", ""))
        _find(updated.get("projects", []), project_id, "project")
        execution = {
            "id": _new_id("execution", title),
            "title": title,
            "project_id": project_id,
            "agent": str(payload.get("agent", "Codex")).strip() or "Codex",
            "thread_ref": str(payload.get("thread_ref", "")).strip(),
            "status": payload.get("status", "queued"),
            "result_state": "unverified",
            "started_at": payload.get("started_at") or now.isoformat(timespec="seconds"),
            "updated_at": now.isoformat(timespec="seconds"),
            "expected_output": str(payload.get("expected_output", "")).strip(),
            "evidence_refs": list(payload.get("evidence_refs", [])),
            "next_action": str(payload.get("next_action", "")).strip(),
        }
        updated.setdefault("executions", []).append(execution)

    elif action == "update_execution":
        execution = _find(updated.get("executions", []), str(payload.get("execution_id", "")), "execution")
        patch = payload.get("patch")
        if not isinstance(patch, dict):
            raise TrackerActionError("execution patch must be an object")
        _patch(execution, patch, WRITABLE_EXECUTION_FIELDS)
        execution["updated_at"] = now.isoformat(timespec="seconds")

    else:
        raise TrackerActionError(f"unsupported action: {action}")

    meta = updated.setdefault("meta", {})
    meta["revision"] = int(meta.get("revision", 0)) + 1
    meta["updated_at"] = now.isoformat(timespec="seconds")
    return updated
