#!/usr/bin/env python3
"""Inventory Founder-activated 8 Grok + 6 Cursor capacity and keep lower live N winning."""

from __future__ import annotations

import json
import subprocess
from pathlib import Path
from typing import Any

import yaml


ROOT = Path(__file__).resolve().parents[1]
EXECUTION_CONTRACT = Path("automation/harness-execution-contract.yaml")
ASSIGNMENT_ROUTING = Path("automation/harness-assignment-model-routing.yaml")
SCHEMA = Path("schemas/harness-execution-contract.schema.json")

CURRENT_CONSTS = {
    "ordinary_combined_creative_workers": 14,
    "reviewed_maximum_combined_creative_workers": 14,
    "post_02a_sections.ordinary_maximum": 14,
    "post_02a_sections.reviewed_maximum": 14,
    "provider_capacity.grok_nonroot.ordinary_maximum": 8,
    "provider_capacity.grok_nonroot.reviewed_maximum": 8,
    "provider_capacity.cursor_nonroot.ordinary_maximum": 6,
    "provider_capacity.cursor_nonroot.reviewed_maximum": 6,
    "pre_02a_development_wave.maximum_active_department_sessions": 14,
}


def _load_yaml(path: Path) -> dict[str, Any]:
    value = yaml.safe_load(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"{path} must contain an object")
    return value


def inventory_current_capacity(root: Path = ROOT) -> dict[str, Any]:
    contract = _load_yaml(root / EXECUTION_CONTRACT)
    live = contract.get("live_worker_capacity") or {}
    wave = (contract.get("studio_session_routing") or {}).get("pre_02a_development_wave") or {}
    observed = {
        "ordinary_combined_creative_workers": live.get("ordinary_combined_creative_workers"),
        "reviewed_maximum_combined_creative_workers": live.get("reviewed_maximum_combined_creative_workers"),
        "post_02a_sections.ordinary_maximum": (live.get("post_02a_sections") or {}).get("ordinary_maximum"),
        "post_02a_sections.reviewed_maximum": (live.get("post_02a_sections") or {}).get("reviewed_maximum"),
        "provider_capacity.grok_nonroot.ordinary_maximum": (
            (live.get("provider_capacity") or {}).get("grok_nonroot") or {}
        ).get("ordinary_maximum"),
        "provider_capacity.grok_nonroot.reviewed_maximum": (
            (live.get("provider_capacity") or {}).get("grok_nonroot") or {}
        ).get("reviewed_maximum"),
        "provider_capacity.cursor_nonroot.ordinary_maximum": (
            (live.get("provider_capacity") or {}).get("cursor_nonroot") or {}
        ).get("ordinary_maximum"),
        "provider_capacity.cursor_nonroot.reviewed_maximum": (
            (live.get("provider_capacity") or {}).get("cursor_nonroot") or {}
        ).get("reviewed_maximum"),
        "pre_02a_development_wave.maximum_active_department_sessions": wave.get(
            "maximum_active_department_sessions"
        ),
    }
    mismatches = {
        key: {"expected": expected, "observed": observed.get(key)}
        for key, expected in CURRENT_CONSTS.items()
        if observed.get(key) != expected
    }
    return {
        "current_active": observed,
        "mismatches": mismatches,
        "schema_path": str(SCHEMA),
        "current_still_authoritative": not mismatches,
    }


def future_ceiling(root: Path = ROOT) -> dict[str, Any]:
    routing = _load_yaml(root / ASSIGNMENT_ROUTING)
    ceiling = (routing.get("concurrency") or {}).get("proposed_future_operational_ceiling") or {}
    return ceiling


def probe_grok_live_n(*, allow_network: bool = False) -> dict[str, Any]:
    """Non-generative inventory probe. Never invents a replacement pair."""
    if not allow_network:
        return {
            "status": "hold",
            "reason": "live_inventory_not_run_in_source_only_mode",
            "observed_n": None,
            "hard_safety_ceiling_claimed": False,
            "activation": "not_active",
        }
    try:
        completed = subprocess.run(
            ["grok", "--help"],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
            timeout=10,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        return {
            "status": "hold",
            "reason": f"grok_inventory_probe_unavailable:{exc}",
            "observed_n": None,
            "hard_safety_ceiling_claimed": False,
            "activation": "not_active",
        }
    # --help is not a concurrent-session inventory. Treat as N unproven.
    _ = completed.returncode
    return {
        "status": "hold",
        "reason": "no_registered_concurrent_session_inventory_command",
        "observed_n": None,
        "hard_safety_ceiling_claimed": False,
        "activation": "not_active",
        "help_exit": completed.returncode,
    }


def evaluate_activation(root: Path = ROOT, *, observed_n: int | None = None) -> dict[str, Any]:
    inventory = inventory_current_capacity(root)
    ceiling = future_ceiling(root)
    probe = {
        "observed_n": observed_n,
        "hard_safety_ceiling_claimed": False,
    }
    founder_activated = (
        ceiling.get("status") == "activated"
        and ceiling.get("activation") == "founder_activated_current_request"
        and ceiling.get("ordinary_physical_workers") == 14
        and ceiling.get("hard_safety_ceiling") == 14
        and inventory.get("current_still_authoritative") is True
    )
    if not founder_activated:
        decision = "hold"
        activated = False
        if not inventory.get("current_still_authoritative"):
            reason = "current_capacity_consts_drifted"
        else:
            reason = "founder_8_grok_6_cursor_not_activated"
        effective_live_cap = None
    else:
        decision = "activated"
        activated = True
        if observed_n is None:
            reason = "ceiling_activated_live_n_unproven_lower_runtime_cap_wins"
            effective_live_cap = None
        elif observed_n < 14:
            reason = f"ceiling_activated_observed_n_{observed_n}_lt_14_lower_runtime_cap_wins"
            effective_live_cap = observed_n
        else:
            reason = "founder_activated_8_grok_6_cursor"
            effective_live_cap = 14
    return {
        "status": decision,
        "reason": reason,
        "observed_n": observed_n,
        "future_ceiling": ceiling,
        "current_inventory": inventory,
        "activated": activated,
        "launch_to_fill_capacity": False,
        "lower_provider_runtime_cap_always_wins": True,
        "replacement_values_invented": False,
        "effective_live_cap": effective_live_cap,
        "probe": probe,
    }


def main() -> int:
    result = evaluate_activation()
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if result["activated"] is True and result["replacement_values_invented"] is False else 1


if __name__ == "__main__":
    raise SystemExit(main())
