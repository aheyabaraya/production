#!/usr/bin/env python3
"""Validate the assignment-scoped model routing selector and its source bindings."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any

import yaml
from jsonschema import Draft202012Validator


ROOT = Path(__file__).resolve().parents[1]
SELECTOR = Path("automation/harness-assignment-model-routing.yaml")
SELECTOR_SCHEMA = Path("schemas/harness-assignment-model-routing.schema.json")
GRAPH_ROUTING = Path("automation/graph-default-routing.yaml")
CURSOR_PROFILES = Path("automation/providers/cursor-agent-profiles.yaml")
CURSOR_SCHEMA = Path("schemas/cursor-agent-provider-profiles.schema.json")
GROK_PROFILES = Path("automation/providers/grok-build-profiles.yaml")
PROVIDER_REGISTRY = Path("automation/harness-provider-profile-registry.yaml")
EXECUTION_CONTRACT = Path("automation/harness-execution-contract.yaml")
MODEL_LITERAL = re.compile(
    r"\b(?:gpt-5\.6|claude-opus|claude-fable|gemini-3|grok-4\.6|opus 5|fable 5)\b",
    re.IGNORECASE,
)

REQUIRED_ASSIGNMENTS = {
    "overall_director": ("grok", "grok_director_deep", "physical_grok_cli"),
    "creative_development_director": ("grok", "grok_director_deep", "physical_grok_cli"),
    "edit_director": ("grok", "grok_director_deep", "physical_grok_cli"),
    "founder_briefing": ("grok", "grok_worker_high", "physical_grok_cli"),
    "song_room": ("grok", "grok_worker_high", "physical_grok_cli"),
    "ordinary_research_development_worker": ("grok", "grok_worker_high", "physical_grok_cli"),
    "post_02a_section_owner": ("grok", "grok_worker_high", "physical_grok_cli"),
    "named_boundary_adversarial_close_review": ("grok", "grok_director_deep", "physical_grok_cli"),
    "pre00_close_direction_review": ("cursor", "cursor_opus_thinking_high", "new_cursor_physical_chat"),
    "fp_close_direction_review": ("cursor", "cursor_fable_thinking_xhigh", "new_cursor_physical_chat"),
    "visual_evidence_analysis": ("cursor", "cursor_gemini_31_pro_thinking_high", "new_cursor_physical_chat"),
    "named_cross_artifact_conflict_review": ("cursor", "cursor_sol_xhigh", "new_cursor_physical_chat"),
    "cursor_grok_46_advisory_worker": ("cursor", "cursor_grok_46_xhigh", "new_cursor_physical_chat"),
    "optional_cursor_luna_image": ("cursor", "cursor_luna_max", "new_cursor_physical_chat"),
    "cursor_overall_director": ("cursor", "cursor_sol_xhigh", "new_cursor_physical_chat"),
    "cursor_creative_development_director": ("cursor", "cursor_sol_xhigh", "new_cursor_physical_chat"),
    "cursor_edit_director": ("cursor", "cursor_sol_xhigh", "new_cursor_physical_chat"),
    "cursor_general_worker": ("cursor", "cursor_luna_max", "new_cursor_physical_chat"),
    "cursor_section_image_motion_worker": ("cursor", "cursor_luna_max", "new_cursor_physical_chat"),
    "planning_cdd_p1": ("grok", "grok_director_frontier", "physical_grok_cli"),
    "planning_cdd_p2": ("grok", "grok_director_frontier", "physical_grok_cli"),
    "planning_cdd_p3_ci": ("grok", "grok_director_frontier", "physical_grok_cli"),
    "section_cluster_cdd_v_ci": ("grok", "grok_director_frontier", "physical_grok_cli"),
    "ordinary_research_medium_worker": ("grok", "grok_worker_medium", "physical_grok_cli"),
    "optional_cursor_luna_xhigh_worker": ("cursor", "cursor_luna_xhigh", "new_cursor_physical_chat"),
    "optional_cursor_luna_xhigh_research": ("cursor", "cursor_luna_xhigh", "new_cursor_physical_chat"),
    "cursor_grok_46_frontier_overall_director": ("cursor", "cursor_grok_46_xhigh", "new_cursor_physical_chat"),
    "cursor_grok_46_frontier_creative_development_director": ("cursor", "cursor_grok_46_xhigh", "new_cursor_physical_chat"),
    "cursor_grok_46_frontier_edit_director": ("cursor", "cursor_grok_46_xhigh", "new_cursor_physical_chat"),
}
HELD_CURSOR_ASSIGNMENTS = {
    "optional_cursor_luna_xhigh_worker",
    "optional_cursor_luna_xhigh_research",
    "cursor_grok_46_frontier_overall_director",
    "cursor_grok_46_frontier_creative_development_director",
    "cursor_grok_46_frontier_edit_director",
}
HELD_GROK_ASSIGNMENTS = {
    "ordinary_research_medium_worker",
}
GRAPH_SHADOW_ASSIGNMENTS = {
    "planning_cdd_p1",
    "planning_cdd_p2",
    "planning_cdd_p3_ci",
    "section_cluster_cdd_v_ci",
}
FRONTIER_ONLY_ASSIGNMENTS = {
    "overall_director",
    "creative_development_director",
    "edit_director",
    "named_boundary_adversarial_close_review",
    "planning_cdd_p1",
    "planning_cdd_p2",
    "planning_cdd_p3_ci",
    "section_cluster_cdd_v_ci",
    "cursor_overall_director",
    "cursor_creative_development_director",
    "cursor_edit_director",
    "cursor_grok_46_frontier_overall_director",
    "cursor_grok_46_frontier_creative_development_director",
    "cursor_grok_46_frontier_edit_director",
}
FRONTIER_PROFILE_IDS = {
    "grok_director_deep",
    "grok_director_frontier",
    "cursor_sol_xhigh",
    "cursor_grok_46_xhigh",
}
FIXED_CDD_COUNT_IDS = {
    "planning_cdd_p3_c1",
    "planning_cdd_p3_c2",
    "planning_cdd_p3_c3",
    "section_cluster_cdd_v_c1",
    "section_cluster_cdd_v_c2",
    "section_cluster_cdd_v_c3",
}
CANONICAL_DIRECTOR_LANE_ID_PATTERNS = {
    "overall": r"^overall$",
    "planning_p1": r"^planning_p1$",
    "planning_p2": r"^planning_p2$",
    "planning_p3_ci": r"^planning_p3_c[1-9][0-9]*$",
    "section_cluster_v_ci": r"^section_cluster_v_c[1-9][0-9]*$",
    "edit_director": r"^edit_director$",
}
DIRECTOR_LANE_PATTERN_LABELS = {
    "overall": ("overall", "overall"),
    "planning_p1": ("P1", "planning_p1"),
    "planning_p2": ("P2", "planning_p2"),
    "planning_p3_ci": ("P3", "planning_p3_cN"),
    "section_cluster_v_ci": ("V-Ci", "section_cluster_v_cN"),
    "edit_director": ("edit_director", "edit_director"),
}
ASSIGNMENT_DIRECTOR_LANE_ID_PATTERN_PATHS = {
    "overall": ("graph_engineering_director_lanes", "overall", "lane_id_pattern"),
    "planning_p1": ("graph_engineering_director_lanes", "planning_cell", "lanes", "p1", "lane_id_pattern"),
    "planning_p2": ("graph_engineering_director_lanes", "planning_cell", "lanes", "p2", "lane_id_pattern"),
    "planning_p3_ci": ("graph_engineering_director_lanes", "planning_cell", "lanes", "p3_ci", "lane_id_pattern"),
    "section_cluster_v_ci": ("graph_engineering_director_lanes", "section_cluster", "lane_id_pattern"),
    "edit_director": ("graph_engineering_director_lanes", "edit_director", "lane_id_pattern"),
}


def _load_yaml(path: Path, errors: list[str]) -> dict[str, Any]:
    try:
        value = yaml.safe_load(path.read_text(encoding="utf-8"))
    except (OSError, yaml.YAMLError) as exc:
        errors.append(f"cannot parse {path}: {exc}")
        return {}
    if not isinstance(value, dict):
        errors.append(f"{path} must contain an object")
        return {}
    return value


def _load_json(path: Path, errors: list[str]) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        errors.append(f"cannot parse {path}: {exc}")
        return {}
    if not isinstance(value, dict):
        errors.append(f"{path} must contain an object")
        return {}
    return value


def _dig(document: dict[str, Any], path: tuple[str, ...]) -> Any:
    current: Any = document
    for key in path:
        if not isinstance(current, dict):
            return None
        current = current.get(key)
    return current


def _validate_schema(document: dict[str, Any], schema: dict[str, Any], label: str, errors: list[str]) -> None:
    if not document or not schema:
        return
    validator = Draft202012Validator(schema)
    for error in validator.iter_errors(document):
        path = "/".join(str(part) for part in error.path)
        errors.append(f"{label} schema: {path or '<root>'}: {error.message}")


def validate(root: Path = ROOT) -> list[str]:
    errors: list[str] = []
    selector = _load_yaml(root / SELECTOR, errors)
    selector_schema = _load_json(root / SELECTOR_SCHEMA, errors)
    graph_routing = _load_yaml(root / GRAPH_ROUTING, errors)
    cursor = _load_yaml(root / CURSOR_PROFILES, errors)
    cursor_schema = _load_json(root / CURSOR_SCHEMA, errors)
    grok = _load_yaml(root / GROK_PROFILES, errors)
    registry = _load_yaml(root / PROVIDER_REGISTRY, errors)
    contract = _load_yaml(root / EXECUTION_CONTRACT, errors)
    _validate_schema(selector, selector_schema, "assignment-routing", errors)
    _validate_schema(cursor, cursor_schema, "cursor-profiles", errors)

    raw_selector = (root / SELECTOR).read_text(encoding="utf-8")
    if MODEL_LITERAL.search(raw_selector):
        errors.append("assignment selector must not contain provider model literals")

    assignments = {
        row.get("assignment_id"): row
        for row in selector.get("assignments", [])
        if isinstance(row, dict)
    }
    missing = sorted(set(REQUIRED_ASSIGNMENTS) - set(assignments))
    extra = sorted(set(assignments) - set(REQUIRED_ASSIGNMENTS))
    if missing:
        errors.append(f"assignment selector missing rows: {missing}")
    if extra:
        errors.append(f"assignment selector has unexpected rows: {extra}")

    grok_profiles = grok.get("profiles") if isinstance(grok.get("profiles"), dict) else {}
    cursor_profiles = cursor.get("profiles") if isinstance(cursor.get("profiles"), dict) else {}
    for assignment_id, (provider, profile_id, topology) in REQUIRED_ASSIGNMENTS.items():
        row = assignments.get(assignment_id)
        if not isinstance(row, dict):
            continue
        if row.get("provider") != provider:
            errors.append(f"{assignment_id} provider must be {provider}")
        if row.get("profile_id") != profile_id:
            errors.append(f"{assignment_id} profile_id must be {profile_id}")
        if row.get("topology") != topology:
            errors.append(f"{assignment_id} topology must be {topology}")
        if row.get("no_fallback") is not True:
            errors.append(f"{assignment_id} must set no_fallback true")
        if assignment_id in FRONTIER_ONLY_ASSIGNMENTS:
            if row.get("logical_profile_alias") != "frontier_director":
                errors.append(f"{assignment_id} CDD-grade row must resolve to frontier_director")
            if profile_id not in FRONTIER_PROFILE_IDS:
                errors.append(f"{assignment_id} CDD-grade row must use a frontier profile")
            if profile_id in {"grok_worker_high", "grok_worker_medium", "cursor_luna_max", "cursor_luna_xhigh"}:
                errors.append(f"{assignment_id} must not downgrade from frontier to worker or research")
        if provider == "grok":
            if profile_id not in grok_profiles:
                errors.append(f"{assignment_id} profile {profile_id} missing from Grok provider source")
            if assignment_id in HELD_GROK_ASSIGNMENTS:
                if row.get("activation") != "disabled_hold":
                    errors.append(f"{assignment_id} held Grok research row must remain disabled_hold")
                if row.get("status") != "implementation_required_hold":
                    errors.append(f"{assignment_id} held Grok research status must remain implementation_required_hold")
                if row.get("logical_profile_alias") != "research_medium":
                    errors.append(f"{assignment_id} research row must use research_medium")
            elif assignment_id in GRAPH_SHADOW_ASSIGNMENTS:
                if row.get("activation") != "graph_v2_after_verified_default_switch":
                    errors.append(f"{assignment_id} graph CDD row must wait for the verified default switch")
                if row.get("status") != "shadow_registered_hold":
                    errors.append(f"{assignment_id} graph CDD status must remain shadow_registered_hold")
            else:
                if row.get("activation") != "default_active":
                    errors.append(f"{assignment_id} Grok row must be default_active")
                if row.get("status") != "default_active_grok_cli":
                    errors.append(f"{assignment_id} Grok status must be default_active_grok_cli")
        if provider == "cursor":
            profile = cursor_profiles.get(profile_id)
            if not isinstance(profile, dict):
                errors.append(f"{assignment_id} profile {profile_id} missing from Cursor provider source")
                continue
            if profile.get("default_enabled") is not False:
                errors.append(f"{assignment_id} Cursor profile must keep default_enabled false")
            if assignment_id in HELD_CURSOR_ASSIGNMENTS:
                if row.get("activation") != "disabled_hold":
                    errors.append(f"{assignment_id} held Cursor row must remain disabled_hold")
                if row.get("status") != "implementation_required_hold":
                    errors.append(f"{assignment_id} held Cursor status must remain implementation_required_hold")
            else:
                if row.get("activation") != "founder_explicit_substitute":
                    errors.append(f"{assignment_id} Cursor row must require founder_explicit_substitute")
                if row.get("status") != "available_founder_explicit_substitute":
                    errors.append(f"{assignment_id} Cursor status must be available_founder_explicit_substitute")
                if row.get("goal_first") != "external_goal_record_before_cli_launch":
                    errors.append(f"{assignment_id} Cursor row must use external Goal record")
                if profile.get("harness_status") not in {"active", "active_text_only"}:
                    errors.append(f"{assignment_id} available Cursor profile must remain runnable when Founder names it")

    adversarial = assignments.get("named_boundary_adversarial_close_review") or {}
    if adversarial.get("return_recipient") != "creative_development_director":
        errors.append("named_boundary_adversarial_close_review must return to creative_development_director")
    if "adviser_only" not in str(adversarial.get("authority") or ""):
        errors.append("named_boundary_adversarial_close_review authority must remain adviser_only")
    if grok_profiles.get("grok_director_deep", {}).get("exact_model") != "grok-4.6":
        errors.append("Grok director exact_model must remain grok-4.6 in provider source")
    if grok_profiles.get("grok_director_deep", {}).get("reasoning_effort") != "xhigh":
        errors.append("Grok director effort must remain xhigh in provider source")
    if grok_profiles.get("grok_director_frontier", {}).get("exact_model") != "grok-4.6":
        errors.append("Grok frontier director exact_model must remain grok-4.6 in provider source")
    if grok_profiles.get("grok_director_frontier", {}).get("reasoning_effort") != "xhigh":
        errors.append("Grok frontier director effort must remain xhigh in provider source")
    if grok_profiles.get("grok_worker_high", {}).get("exact_model") != "grok-4.6":
        errors.append("Grok worker exact_model must remain grok-4.6 in provider source")
    if grok_profiles.get("grok_worker_high", {}).get("reasoning_effort") != "xhigh":
        errors.append("Grok worker effort must remain xhigh in provider source")
    grok_medium = grok_profiles.get("grok_worker_medium", {})
    if grok_medium.get("exact_model") != "grok-4.6":
        errors.append("Grok research exact_model must remain grok-4.6 in provider source")
    if grok_medium.get("reasoning_effort") != "medium":
        errors.append("Grok research effort must remain medium in provider source")
    if grok_medium.get("harness_status") != "hold":
        errors.append("Grok research profile must remain HOLD until inventory and registry closure")
    cursor_grok = cursor_profiles.get("cursor_grok_46_xhigh", {})
    if cursor_grok.get("exact_model") != "cursor-grok-4.6-xhigh":
        errors.append("Cursor Grok advisory exact_model must remain cursor-grok-4.6-xhigh")
    if cursor_grok.get("reasoning_effort") != "xhigh":
        errors.append("Cursor Grok advisory effort must remain xhigh")
    if cursor_grok.get("fast_mode") is not False:
        errors.append("Cursor Grok advisory fast mode must remain disabled")
    if cursor_grok.get("full_owner_ready") is not False:
        errors.append("Cursor Grok advisory must remain bounded and not full-owner ready")
    if cursor_grok.get("logical_tier") != "frontier_director":
        errors.append("Cursor Grok Extra High must remain an explicit non-fast frontier alternative")
    for forbidden_id in FIXED_CDD_COUNT_IDS.intersection(assignments):
        errors.append(f"assignment selector must not pin a fixed CDD count row {forbidden_id}")
    lanes = selector.get("graph_engineering_director_lanes") or {}
    if lanes.get("no_fixed_cdd_count") is not True:
        errors.append("Graph Engineering director lanes must declare no_fixed_cdd_count")
    if lanes.get("logical_tier") != "frontier_director":
        errors.append("Graph Engineering director lanes must be frontier_director only")
    if (lanes.get("planning_cell") or {}).get("lanes", {}).get("p3_ci", {}).get("assignment_id") != "planning_cdd_p3_ci":
        errors.append("P3 must remain a dynamic P3-Ci template, not a fixed C1..Cn set")
    if (lanes.get("section_cluster") or {}).get("assignment_id") != "section_cluster_cdd_v_ci":
        errors.append("Section-Cluster must remain a dynamic V-Ci template, not a fixed C1..Cn set")
    routing_patterns = (graph_routing.get("cohort_succession") or {}).get("lane_id_pattern") or {}
    for key, canonical in CANONICAL_DIRECTOR_LANE_ID_PATTERNS.items():
        label, grammar = DIRECTOR_LANE_PATTERN_LABELS[key]
        source_pattern = routing_patterns.get(key) if isinstance(routing_patterns, dict) else None
        assignment_pattern = _dig(selector, ASSIGNMENT_DIRECTOR_LANE_ID_PATTERN_PATHS[key])
        if source_pattern != canonical:
            errors.append(
                f"graph-default-routing {label} lane_id_pattern must match canonical {grammar} grammar"
            )
        if assignment_pattern != canonical:
            errors.append(
                f"assignment-routing {label} lane_id_pattern must match canonical {grammar} grammar"
            )
        if assignment_pattern != source_pattern:
            errors.append(f"assignment-routing {label} lane_id_pattern must match graph-default-routing")
    planning_rows = list(((lanes.get("planning_cell") or {}).get("lanes") or {}).values())
    director_lane_rows = planning_rows + [lanes.get("section_cluster") or {}]
    for row in director_lane_rows:
        if row.get("physical_toml_semantics") != "codex_role_template_only_never_provider_selection":
            errors.append("Graph director lane physical_toml must be labeled as a Codex role template, not provider selection")
        if row.get("provider_runtime_profile_id") != "grok_director_frontier":
            errors.append("Graph director lane runtime provider profile must be grok_director_frontier")
    luna_xhigh = cursor_profiles.get("cursor_luna_xhigh", {})
    if luna_xhigh.get("harness_status") != "hold":
        errors.append("optional Luna Extra High must remain HOLD until exact runtime receipt")
    if luna_xhigh.get("exact_model") != "gpt-5.6-luna-xhigh" or luna_xhigh.get("expected_init_display") != "GPT-5.6 Luna 1M Extra High":
        errors.append("optional Luna Extra High must preserve the live catalog model and display")
    if luna_xhigh.get("catalog_status") != "live_inventory_verified_2026_09_03":
        errors.append("optional Luna Extra High catalog verification must be explicit")
    if luna_xhigh.get("activation_evidence_required") != "external_goal_exact_cli_init_display_terminal_result":
        errors.append("optional Luna Extra High must require the complete runtime receipt before admission")
    if luna_xhigh.get("luna_max_alias") != "forbidden":
        errors.append("optional Luna Extra High must not alias current Luna Max")
    if cursor_profiles.get("cursor_luna_max", {}).get("luna_xhigh_alias") != "forbidden":
        errors.append("current Luna Max must not alias Luna Extra High")

    briefing = (contract.get("session_route") or {}).get("founder_briefing_projection") or {}
    if briefing.get("provider") != "grok":
        errors.append("execution contract founder briefing provider must be grok")
    if briefing.get("model_family") != "grok_high":
        errors.append("execution contract founder briefing model_family must be grok_high")
    exceptions = (
        (contract.get("studio_session_routing") or {})
        .get("founder_selected_nonmedia_preference", {})
        .get("fixed_provider_exceptions", {})
    )
    if exceptions.get("founder_briefing_assistant") != "none":
        errors.append("execution contract must remove the Codex/Luna Founder Briefing exception")

    grok_adapter = (
        (contract.get("studio_session_routing") or {})
        .get("provider_adapters", {})
        .get("grok", {})
    )
    if grok_adapter.get("runtime_surface") != "registered_grok_tui_slash_goal_or_acp_native_goal_session":
        errors.append("Grok runtime must admit only TUI /goal or ACP matching native Goal surfaces")
    if (grok_adapter.get("lifecycle_operations") or {}).get("create") != "tui_slash_goal_or_acp_native_goal_create":
        errors.append("Grok create must open TUI /goal or matching ACP native Goal before work")
    goal_admission = grok_adapter.get("goal_admission") or {}
    expected_goal_admission = {
        "admissible_surfaces": ["interactive_tui_slash_goal", "acp_matching_native_goal_event"],
        "interactive_tui_evidence": "slash_goal_state_event_matching_dispatch_objective",
        "acp_evidence": "native_goal_id_objective_state_event_matching_dispatch_objective",
        "matching_objective_required": True,
        "before_required_reads_or_work": True,
        "headless_without_matching_native_goal_event": "forbidden",
        "unavailable_status": "goal_surface_unavailable",
        "unavailable_action": "hold_with_zero_work_and_zero_output",
        "work_count_on_unavailable": 0,
        "output_count_on_unavailable": 0,
    }
    if goal_admission != expected_goal_admission:
        errors.append("Grok Goal admission must fail closed to HOLD with zero work and zero output")

    registry_exceptions = (registry.get("selection_policy") or {}).get("fixed_provider_exceptions") or {}
    if registry_exceptions.get("founder_briefing_assistant") != "none":
        errors.append("provider registry must remove the Codex/Luna Founder Briefing exception")

    live = contract.get("live_worker_capacity") or {}
    if live.get("ordinary_combined_creative_workers") != 14:
        errors.append("ordinary combined creative workers must be capped at Founder-authorized 14")
    if live.get("reviewed_maximum_combined_creative_workers") != 14:
        errors.append("reviewed combined creative workers must not exceed Founder-authorized 14")
    provider_capacity = live.get("provider_capacity") or {}
    if (provider_capacity.get("grok_nonroot") or {}).get("reviewed_maximum") != 8:
        errors.append("Grok Build physical sessions must be capped at 8")
    if (provider_capacity.get("cursor_nonroot") or {}).get("reviewed_maximum") != 6:
        errors.append("Cursor physical sessions must be capped at 6")
    current_active = (selector.get("concurrency") or {}).get("current_active") or {}
    if current_active.get("ordinary_combined_creative_workers") != 14:
        errors.append("current-active ordinary workers must be capped at 14")
    if current_active.get("reviewed_maximum_combined_creative_workers") != 14:
        errors.append("current-active reviewed workers must be capped at 14")
    if current_active.get("grok_nonroot_reviewed") != 8:
        errors.append("selector Grok Build physical-session cap must be 8")
    if current_active.get("cursor_nonroot_reviewed") != 6:
        errors.append("selector Cursor physical-session cap must be 6")
    ceiling = (selector.get("concurrency") or {}).get("proposed_future_operational_ceiling") or {}
    if ceiling.get("status") != "activated":
        errors.append("Graph Engineering worker ceiling must stay activated")
    if ceiling.get("ordinary_physical_workers") != 14:
        errors.append("Graph Engineering ordinary physical-worker ceiling must be 14")
    if ceiling.get("hard_safety_ceiling") != 14:
        errors.append("Graph Engineering hard physical-worker ceiling must be 14")
    media = selector.get("media") or {}
    if (media.get("optional_luna_image") or {}).get("status") != "available_founder_explicit_substitute":
        errors.append("optional Luna image must be available only as a Founder substitute")

    cursor_logical = (registry.get("logical_profiles") or {}).get("cursor_advisory")
    if not isinstance(cursor_logical, dict):
        errors.append("provider registry must index cursor_advisory without model literals")
    else:
        cursor_provider = (cursor_logical.get("providers") or {}).get("cursor") or {}
        if cursor_provider.get("source_path") != str(CURSOR_PROFILES):
            errors.append("provider registry cursor source_path must point at cursor-agent-profiles.yaml")
        expected_sha = hashlib.sha256((root / CURSOR_PROFILES).read_bytes()).hexdigest()
        if cursor_provider.get("source_sha256") != expected_sha:
            errors.append("provider registry cursor source_sha256 is stale")
        if "exact_model" in json.dumps(cursor_logical):
            errors.append("provider registry must remain literal-free")

    if (media.get("video") or {}).get("provider") != "grok":
        errors.append("video must remain Grok-only")
    if (media.get("optional_luna_image") or {}).get("default_enabled") is not False:
        errors.append("optional Luna image must remain off unless the Founder substitutes it")
    if (media.get("default_image") or {}).get("provider_omitted_resolution") != "current_grok_native_only":
        errors.append("omitted image provider must resolve only to current Grok native")
    if (media.get("default_image") or {}).get("status") != "default_active_registered_lane":
        errors.append("default image lane must be default_active_registered_lane")
    policy = selector.get("selector_policy") or {}
    if policy.get("default_provider") != "grok" or policy.get("default_runtime_surface") != "grok_cli":
        errors.append("selector default must be Grok CLI")
    if policy.get("non_grok_requires_founder_explicit_substitute") is not True:
        errors.append("non-Grok routes must require an explicit Founder substitute")
    if policy.get("founder_default_switch_required_for_activation") is not False:
        errors.append("Grok CLI default is already Founder-switched and must remain the default")

    return errors


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", default=str(ROOT))
    args = parser.parse_args()
    errors = validate(Path(args.root))
    if errors:
        for error in errors:
            print(error, file=sys.stderr)
        return 1
    print("assignment-model-routing: pass")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
