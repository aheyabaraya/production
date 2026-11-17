from __future__ import annotations

PROJECT_STATUSES = {
    "baseline_pending",
    "planned",
    "in_progress",
    "waiting",
    "review",
    "completed",
    "canceled",
}

HEALTH_STATUSES = {"unknown", "on_track", "attention", "blocked"}

MILESTONE_STATUSES = {
    "not_started",
    "in_progress",
    "waiting",
    "review",
    "completed",
    "canceled",
}

GATE_STATUSES = {"not_required", "pending", "pass", "hold", "reject"}

DECISION_STATUSES = {"pending", "approved", "held", "rejected", "superseded"}

EXECUTION_STATUSES = {
    "queued",
    "running",
    "waiting_for_input",
    "awaiting_review",
    "completed",
    "blocked",
    "failed",
    "canceled",
}

EXECUTION_RESULT_STATES = {"unverified", "verified", "hold", "rejected"}

PRIORITIES = {"P0", "P1", "P2", "P3"}

PRIORITY_ORDER = {"P0": 0, "P1": 1, "P2": 2, "P3": 3}

WRITABLE_PROJECT_FIELDS = {
    "title",
    "objective",
    "owner",
    "status",
    "declared_health",
    "priority",
    "start_date",
    "target_date",
    "next_review_at",
    "review_cadence_days",
    "next_action",
    "source_refs",
    "milestones",
}

WRITABLE_MILESTONE_FIELDS = {
    "title",
    "weight",
    "status",
    "gate_status",
    "evidence_required",
    "evidence_refs",
    "start_date",
    "target_date",
    "owner",
    "note",
}

WRITABLE_DECISION_FIELDS = {
    "title",
    "project_id",
    "owner",
    "status",
    "needed_by",
    "impact",
    "source_refs",
    "resolved_at",
    "resolution",
}

WRITABLE_EXECUTION_FIELDS = {
    "title",
    "project_id",
    "agent",
    "thread_ref",
    "status",
    "result_state",
    "started_at",
    "updated_at",
    "expected_output",
    "evidence_refs",
    "next_action",
}
