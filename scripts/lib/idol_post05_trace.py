"""Provider-neutral 05 -> 04 provenance normalization.

The helpers here are pure: they canonicalize already-authored trace values and
never read, write, approve, promote, publish, or reinterpret creative truth.
Callers remain responsible for validating exact paths and live SHA-256 bytes.
"""

from __future__ import annotations

import hashlib
import json
from typing import Any


CURRENT_PACKAGE_VERSION = "idol_package.v2"
PRODUCTION_GRAPH_TRACE_VERSION = "idol_05_production_graph_trace.v1"
POST05_MUTATION_BOUNDARY = (
    "post05_release_and_analytics_are_append_only_evidence_and_never_mutate_mv_truth"
)
RELEASE_PROVENANCE_VERSION = "idol_release_provenance.v2"
RELEASE_PRODUCTION_TRACE_FIELDS = (
    "release_provenance_version",
    "release_package_contract",
    "release_package_contract_sha256",
    "release_package_deliverable_manifest_sha256",
    "release_package_output_id",
    "release_package_output_role",
    "release_package_linkage",
    "release_production_graph_trace_sha256",
    "release_edit_segment_ids",
    "release_screen_progression_node_ids",
    "release_section_ids",
    "release_asset_sha256",
)
RELEASE_PRODUCTION_TRACE_TRIGGER_FIELDS = (
    "release_provenance_version",
    "release_production_graph_trace_sha256",
    "release_edit_segment_ids",
    "release_screen_progression_node_ids",
    "release_section_ids",
)


def canonical_object_sha256(value: Any) -> str:
    payload = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def normalize_production_graph_trace(trace: dict[str, Any]) -> dict[str, Any]:
    """Return the stable digest surface shared by 05, release, and analytics."""

    source_map = trace.get("source_edit_map") or {}
    source_recipe = trace.get("source_edit_recipe") or {}
    bindings = {
        str(binding.get("output_id") or ""): binding
        for binding in (trace.get("deliverable_bindings") or [])
        if isinstance(binding, dict) and binding.get("output_id")
    }
    return {
        "schema_version": str(trace.get("schema_version") or ""),
        "source_edit_map": {
            "artifact_type": str(source_map.get("artifact_type") or ""),
            "schema_version": str(source_map.get("schema_version") or ""),
            "path": str(source_map.get("path") or ""),
            "sha256": str(source_map.get("sha256") or ""),
            "json_pointer": str(source_map.get("json_pointer") or ""),
        },
        "source_edit_recipe": {
            "artifact_type": str(source_recipe.get("artifact_type") or ""),
            "schema_version": str(source_recipe.get("schema_version") or ""),
            "path": str(source_recipe.get("path") or ""),
            "sha256": str(source_recipe.get("sha256") or ""),
            "json_pointer": str(source_recipe.get("json_pointer") or ""),
        },
        "deliverable_bindings": [
            {
                "output_id": output_id,
                "edit_segment_ids": list(bindings[output_id].get("edit_segment_ids") or []),
                "screen_progression_node_ids": sorted(
                    bindings[output_id].get("screen_progression_node_ids") or []
                ),
                "section_ids": sorted(bindings[output_id].get("section_ids") or []),
            }
            for output_id in sorted(bindings)
        ],
        "post05_mutation_boundary": str(trace.get("post05_mutation_boundary") or ""),
    }


def production_graph_trace_sha256(trace: dict[str, Any]) -> str:
    return canonical_object_sha256(normalize_production_graph_trace(trace))
