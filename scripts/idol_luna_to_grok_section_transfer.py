#!/usr/bin/env python3
"""Post-pixel Cursor-Luna-owner -> Grok-CLI-03V-owner transfer.

Existing physical_transfer metadata is topology-only and is not this contract.
This module implements the eight Founder-required steps and opens only when
the Founder names the Luna substitute or sets route_enabled.
"""

from __future__ import annotations

from copy import deepcopy
from typing import Any


TRANSFER_DISABLED_REASON = "founder_explicit_substitute_required"
REQUIRED_RECORD_FIELDS = (
    "source_provider",
    "target_provider",
    "source_session_id",
    "target_session_id",
    "source_dispatch_id",
    "target_dispatch_id",
    "source_goal_id",
    "target_goal_id",
    "attempt_id",
    "section_id",
    "cut_ids",
    "checkpoint",
    "owner_locks",
    "review_receipt",
)
IMMUTABLE_CARRY_FIELDS = (
    "prompts",
    "pixels",
    "attachments",
    "ids",
    "output_paths",
    "hashes",
    "continuity",
    "stop_conditions",
)


def _hold(reason: str, **extra: Any) -> dict[str, Any]:
    result = {
        "status": "hold",
        "reason": reason,
        "fallback": "none",
        "source_owner_active": extra.pop("source_owner_active", True),
        "target_owner_active": extra.pop("target_owner_active", False),
    }
    result.update(extra)
    return result


def transfer_section_owner(state: dict[str, Any]) -> dict[str, Any]:
    """Execute or HOLD the eight-step Luna-to-Grok transfer."""
    working = deepcopy(state)
    if working.get("founder_explicit_substitute") is not True and working.get("route_enabled") is not True:
        return _hold(TRANSFER_DISABLED_REASON, source_owner_active=True, target_owner_active=False)
    if working.get("founder_selected_exact_run_and_section") is not True:
        return _hold("luna_image_requires_explicit_founder_section_selection")
    if working.get("simultaneous_owners"):
        return _hold("simultaneous_owners_forbidden")

    luna = working.get("luna")
    grok = working.get("grok")
    record = working.get("assignment_record")
    if not isinstance(luna, dict) or not isinstance(grok, dict) or not isinstance(record, dict):
        return _hold("transfer_state_incomplete")
    missing = [field for field in REQUIRED_RECORD_FIELDS if not record.get(field)]
    if missing:
        return _hold("transfer_assignment_record_incomplete", missing_fields=missing)
    if record.get("source_provider") != "cursor" or record.get("target_provider") != "grok":
        return _hold("transfer_providers_must_be_cursor_to_grok")

    if luna.get("stage") != "02b_image_pixel_closed":
        return _hold("luna_must_close_02b_image_pixel_before_transfer")
    if luna.get("returned_to") != "creative_development_director":
        return _hold("luna_must_return_exact_bytes_to_cdd")
    if working.get("cdd_review") != "complete":
        return _hold("cdd_exact_review_required_before_transfer")

    if luna.get("active") is not False:
        # Step 4: CAS inactivates Luna before Grok gains authority.
        if working.get("cas_generation") != working.get("expected_cas_generation"):
            return _hold("cas_generation_mismatch", source_owner_active=True)
        luna["active"] = False
        luna["authority"] = "inactive"
        working["cas_committed"] = True

    if luna.get("active") is not False:
        return _hold("luna_still_active", source_owner_active=True)
    if grok.get("authority") == "active" and grok.get("new_dispatch_and_goal") is not True:
        return _hold("grok_cannot_gain_authority_before_new_dispatch_and_goal")

    carry = working.get("carry")
    if not isinstance(carry, dict):
        return _hold("carry_payload_required")
    for field in IMMUTABLE_CARRY_FIELDS:
        if field not in carry:
            return _hold("unchanged_carry_incomplete", missing_field=field)
        if carry.get(f"{field}_rewritten") is True:
            return _hold("carry_must_remain_unchanged", field=field)

    if grok.get("new_dispatch_and_goal") is not True:
        return _hold("grok_must_open_new_dispatch_and_goal_before_reading")
    if grok.get("read_before_goal"):
        return _hold("grok_goal_must_precede_reads")
    grok["active"] = True
    grok["authority"] = "active"

    if working.get("rollback_requested"):
        grok["active"] = False
        grok["authority"] = "denied"
        luna["active"] = True
        luna["authority"] = "restored_checkpoint"
        if grok.get("duplicate_generation"):
            return _hold("duplicate_generation_impossible")
        return {
            "status": "rolled_back",
            "reason": "rollback_denies_grok_and_restores_prior_checkpoint",
            "source_owner_active": True,
            "target_owner_active": False,
            "checkpoint": record.get("checkpoint"),
        }

    if grok.get("duplicate_generation"):
        return _hold("duplicate_generation_impossible", source_owner_active=False, target_owner_active=True)

    return {
        "status": "pass",
        "reason": "luna_inactive_grok_authorized",
        "source_owner_active": False,
        "target_owner_active": True,
        "assignment_record": record,
        "carry": carry,
    }
