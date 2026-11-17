from __future__ import annotations

from datetime import date, datetime
from typing import Any

from .constants import (
    DECISION_STATUSES,
    EXECUTION_RESULT_STATES,
    EXECUTION_STATUSES,
    GATE_STATUSES,
    HEALTH_STATUSES,
    MILESTONE_STATUSES,
    PRIORITIES,
    PROJECT_STATUSES,
)
from .paths import resolve_repo_path


class TrackerValidationError(ValueError):
    def __init__(self, errors: list[str]):
        self.errors = errors
        super().__init__("; ".join(errors))


def _is_non_empty(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def _valid_date(value: Any) -> bool:
    if value in (None, ""):
        return True
    if not isinstance(value, str):
        return False
    try:
        date.fromisoformat(value)
        return True
    except ValueError:
        return False


def _valid_datetime(value: Any) -> bool:
    if value in (None, ""):
        return True
    if not isinstance(value, str):
        return False
    try:
        datetime.fromisoformat(value.replace("Z", "+00:00"))
        return True
    except ValueError:
        return False


def _validate_refs(refs: Any, prefix: str, errors: list[str]) -> None:
    if not isinstance(refs, list):
        errors.append(f"{prefix} must be a list")
        return
    for index, ref in enumerate(refs):
        try:
            resolve_repo_path(ref)
        except (ValueError, OSError) as exc:
            errors.append(f"{prefix}[{index}] is unsafe: {exc}")


def _evidence_file_exists(ref: Any) -> bool:
    try:
        return resolve_repo_path(ref).is_file()
    except (ValueError, OSError):
        return False


def validate_state(state: dict[str, Any]) -> None:
    errors: list[str] = []
    if not isinstance(state, dict):
        raise TrackerValidationError(["tracker state must be an object"])
    if state.get("schema_version") != "idol-ops-tracker.v1":
        errors.append("schema_version must be idol-ops-tracker.v1")

    meta = state.get("meta")
    if not isinstance(meta, dict):
        errors.append("meta must be an object")
    else:
        if not isinstance(meta.get("revision"), int) or meta.get("revision", 0) < 1:
            errors.append("meta.revision must be a positive integer")
        if not _valid_datetime(meta.get("updated_at")):
            errors.append("meta.updated_at must be an ISO timestamp")

    lanes = state.get("lanes")
    lane_ids: set[str] = set()
    if not isinstance(lanes, list) or not lanes:
        errors.append("lanes must be a non-empty list")
        lanes = []
    for index, lane in enumerate(lanes):
        prefix = f"lanes[{index}]"
        if not isinstance(lane, dict):
            errors.append(f"{prefix} must be an object")
            continue
        lane_id = lane.get("id")
        if not _is_non_empty(lane_id):
            errors.append(f"{prefix}.id is required")
        elif lane_id in lane_ids:
            errors.append(f"duplicate lane id: {lane_id}")
        else:
            lane_ids.add(lane_id)
        if not _is_non_empty(lane.get("name")):
            errors.append(f"{prefix}.name is required")
        source_ref = lane.get("source_ref")
        if source_ref:
            _validate_refs([source_ref], f"{prefix}.source_ref", errors)

    projects = state.get("projects")
    project_ids: set[str] = set()
    if not isinstance(projects, list):
        errors.append("projects must be a list")
        projects = []
    for index, project in enumerate(projects):
        prefix = f"projects[{index}]"
        if not isinstance(project, dict):
            errors.append(f"{prefix} must be an object")
            continue
        project_id = project.get("id")
        if not _is_non_empty(project_id):
            errors.append(f"{prefix}.id is required")
        elif project_id in project_ids:
            errors.append(f"duplicate project id: {project_id}")
        else:
            project_ids.add(project_id)
        if project.get("lane_id") not in lane_ids:
            errors.append(f"{prefix}.lane_id must reference an existing lane")
        if not _is_non_empty(project.get("title")):
            errors.append(f"{prefix}.title is required")
        if project.get("status") not in PROJECT_STATUSES:
            errors.append(f"{prefix}.status is invalid")
        if project.get("declared_health") not in HEALTH_STATUSES:
            errors.append(f"{prefix}.declared_health is invalid")
        if project.get("priority") not in PRIORITIES:
            errors.append(f"{prefix}.priority is invalid")
        for field in ("start_date", "target_date"):
            if not _valid_date(project.get(field)):
                errors.append(f"{prefix}.{field} must be YYYY-MM-DD")
        if not _valid_datetime(project.get("next_review_at")):
            errors.append(f"{prefix}.next_review_at must be an ISO timestamp")
        cadence = project.get("review_cadence_days")
        if not isinstance(cadence, int) or cadence < 1 or cadence > 365:
            errors.append(f"{prefix}.review_cadence_days must be 1..365")
        _validate_refs(project.get("source_refs", []), f"{prefix}.source_refs", errors)

        baseline = project.get("baseline")
        if not isinstance(baseline, dict) or baseline.get("state") not in {"draft", "locked"}:
            errors.append(f"{prefix}.baseline.state must be draft or locked")
        elif baseline.get("state") == "locked":
            if not isinstance(baseline.get("revision"), int) or baseline.get("revision", 0) < 1:
                errors.append(f"{prefix}.baseline.revision must be positive when locked")
            if not _valid_datetime(baseline.get("locked_at")) or not baseline.get("locked_at"):
                errors.append(f"{prefix}.baseline.locked_at is required when locked")

        milestones = project.get("milestones")
        milestone_ids: set[str] = set()
        if not isinstance(milestones, list) or not milestones:
            errors.append(f"{prefix}.milestones must be a non-empty list")
            milestones = []
        total_weight = 0.0
        for m_index, milestone in enumerate(milestones):
            m_prefix = f"{prefix}.milestones[{m_index}]"
            if not isinstance(milestone, dict):
                errors.append(f"{m_prefix} must be an object")
                continue
            milestone_id = milestone.get("id")
            if not _is_non_empty(milestone_id):
                errors.append(f"{m_prefix}.id is required")
            elif milestone_id in milestone_ids:
                errors.append(f"duplicate milestone id in {project_id}: {milestone_id}")
            else:
                milestone_ids.add(milestone_id)
            if not _is_non_empty(milestone.get("title")):
                errors.append(f"{m_prefix}.title is required")
            weight = milestone.get("weight")
            if not isinstance(weight, (int, float)) or isinstance(weight, bool) or weight <= 0:
                errors.append(f"{m_prefix}.weight must be positive")
            else:
                total_weight += float(weight)
            if milestone.get("status") not in MILESTONE_STATUSES:
                errors.append(f"{m_prefix}.status is invalid")
            if milestone.get("gate_status") not in GATE_STATUSES:
                errors.append(f"{m_prefix}.gate_status is invalid")
            if not isinstance(milestone.get("evidence_required"), bool):
                errors.append(f"{m_prefix}.evidence_required must be boolean")
            _validate_refs(milestone.get("evidence_refs", []), f"{m_prefix}.evidence_refs", errors)
            for field in ("start_date", "target_date"):
                if not _valid_date(milestone.get(field)):
                    errors.append(f"{m_prefix}.{field} must be YYYY-MM-DD")
        if baseline and baseline.get("state") == "locked" and round(total_weight, 6) != 100.0:
            errors.append(f"{prefix} locked milestone weights must total 100 (got {total_weight:g})")

        blockers = project.get("blockers", [])
        if not isinstance(blockers, list):
            errors.append(f"{prefix}.blockers must be a list")
        else:
            blocker_ids: set[str] = set()
            for b_index, blocker in enumerate(blockers):
                b_prefix = f"{prefix}.blockers[{b_index}]"
                if not isinstance(blocker, dict):
                    errors.append(f"{b_prefix} must be an object")
                    continue
                if not _is_non_empty(blocker.get("id")):
                    errors.append(f"{b_prefix}.id is required")
                elif blocker["id"] in blocker_ids:
                    errors.append(f"duplicate blocker id in {project_id}: {blocker['id']}")
                else:
                    blocker_ids.add(blocker["id"])
                if blocker.get("status") not in {"open", "resolved"}:
                    errors.append(f"{b_prefix}.status is invalid")
                if not _is_non_empty(blocker.get("title")):
                    errors.append(f"{b_prefix}.title is required")

        if project.get("status") == "completed":
            if not baseline or baseline.get("state") != "locked":
                errors.append(f"{prefix} completed project requires a locked baseline")
            if any(blocker.get("status") == "open" for blocker in blockers if isinstance(blocker, dict)):
                errors.append(f"{prefix} completed project cannot have open blockers")
            for m_index, milestone in enumerate(milestones):
                m_prefix = f"{prefix}.milestones[{m_index}]"
                if not isinstance(milestone, dict):
                    continue
                if milestone.get("status") != "completed":
                    errors.append(f"{m_prefix} must be completed when project is completed")
                if milestone.get("gate_status") not in {"pass", "not_required"}:
                    errors.append(f"{m_prefix} must have PASS/not_required when project is completed")
                if milestone.get("evidence_required"):
                    refs = milestone.get("evidence_refs", [])
                    if not refs:
                        errors.append(f"{m_prefix} requires evidence when project is completed")
                    elif any(not _evidence_file_exists(ref) for ref in refs):
                        errors.append(f"{m_prefix} evidence must exist when project is completed")

    decisions = state.get("decisions", [])
    decision_ids: set[str] = set()
    if not isinstance(decisions, list):
        errors.append("decisions must be a list")
        decisions = []
    for index, decision in enumerate(decisions):
        prefix = f"decisions[{index}]"
        if not isinstance(decision, dict):
            errors.append(f"{prefix} must be an object")
            continue
        decision_id = decision.get("id")
        if not _is_non_empty(decision_id):
            errors.append(f"{prefix}.id is required")
        elif decision_id in decision_ids:
            errors.append(f"duplicate decision id: {decision_id}")
        else:
            decision_ids.add(decision_id)
        if decision.get("project_id") not in (None, "") and decision.get("project_id") not in project_ids:
            errors.append(f"{prefix}.project_id must reference an existing project")
        if decision.get("status") not in DECISION_STATUSES:
            errors.append(f"{prefix}.status is invalid")
        if not _valid_date(decision.get("needed_by")):
            errors.append(f"{prefix}.needed_by must be YYYY-MM-DD")
        _validate_refs(decision.get("source_refs", []), f"{prefix}.source_refs", errors)

    executions = state.get("executions", [])
    execution_ids: set[str] = set()
    if not isinstance(executions, list):
        errors.append("executions must be a list")
        executions = []
    for index, execution in enumerate(executions):
        prefix = f"executions[{index}]"
        if not isinstance(execution, dict):
            errors.append(f"{prefix} must be an object")
            continue
        execution_id = execution.get("id")
        if not _is_non_empty(execution_id):
            errors.append(f"{prefix}.id is required")
        elif execution_id in execution_ids:
            errors.append(f"duplicate execution id: {execution_id}")
        else:
            execution_ids.add(execution_id)
        if execution.get("project_id") not in project_ids:
            errors.append(f"{prefix}.project_id must reference an existing project")
        if execution.get("status") not in EXECUTION_STATUSES:
            errors.append(f"{prefix}.status is invalid")
        if execution.get("result_state") not in EXECUTION_RESULT_STATES:
            errors.append(f"{prefix}.result_state is invalid")
        for field in ("started_at", "updated_at"):
            if not _valid_datetime(execution.get(field)):
                errors.append(f"{prefix}.{field} must be an ISO timestamp")
        _validate_refs(execution.get("evidence_refs", []), f"{prefix}.evidence_refs", errors)

    templates = state.get("templates", [])
    if not isinstance(templates, list) or not templates:
        errors.append("templates must be a non-empty list")

    repositories = state.get("source_repositories", [])
    if not isinstance(repositories, list) or not repositories:
        errors.append("source_repositories must be a non-empty list")
    else:
        for index, repository in enumerate(repositories):
            if not isinstance(repository, dict):
                errors.append(f"source_repositories[{index}] must be an object")
                continue
            _validate_refs([repository.get("path", "")], f"source_repositories[{index}].path", errors)

    if errors:
        raise TrackerValidationError(errors)
