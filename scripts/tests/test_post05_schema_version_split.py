#!/usr/bin/env python3
"""Guard active-only authoring and isolated post-05 legacy readers."""

from __future__ import annotations

import json
from pathlib import Path
import sys
import unittest

from jsonschema import Draft202012Validator


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

from lib.idol_post05_trace import production_graph_trace_sha256  # noqa: E402


class Post05SchemaVersionSplitTest(unittest.TestCase):
    CASES = (
        (
            "schemas/package.schema.json",
            "idol_package.v2",
            "schemas/package-v1-legacy.schema.json",
            "idol_package.v1",
        ),
        (
            "schemas/final-delivery-manifest.schema.json",
            "idol-final-delivery-manifest.v2",
            "schemas/final-delivery-manifest-v1-legacy.schema.json",
            "idol-final-delivery-manifest.v1",
        ),
        (
            "schemas/social-evidence-snapshot.schema.json",
            "idol_social_evidence_snapshot.v3",
            "schemas/social-evidence-snapshot-v2-legacy.schema.json",
            "idol_social_evidence_snapshot.v2",
        ),
    )

    def test_active_and_legacy_versions_are_mutually_exclusive(self) -> None:
        ids: set[str] = set()
        for active_path, active_version, legacy_path, legacy_version in self.CASES:
            with self.subTest(active=active_path):
                active = json.loads((ROOT / active_path).read_text(encoding="utf-8"))
                legacy = json.loads((ROOT / legacy_path).read_text(encoding="utf-8"))
                Draft202012Validator.check_schema(active)
                Draft202012Validator.check_schema(legacy)
                active_version_schema = active["properties"]["schema_version"]
                legacy_version_schema = legacy["properties"]["schema_version"]
                self.assertEqual({"const": active_version}, active_version_schema)
                self.assertEqual({"const": legacy_version}, legacy_version_schema)
                self.assertTrue(
                    Draft202012Validator(active_version_schema).is_valid(active_version)
                )
                self.assertFalse(
                    Draft202012Validator(active_version_schema).is_valid(legacy_version)
                )
                self.assertTrue(
                    Draft202012Validator(legacy_version_schema).is_valid(legacy_version)
                )
                self.assertFalse(
                    Draft202012Validator(legacy_version_schema).is_valid(active_version)
                )
                self.assertNotEqual(active["$id"], legacy["$id"])
                ids.update((active["$id"], legacy["$id"]))
        self.assertEqual(6, len(ids))

    def test_shared_trace_digest_sorts_sets_but_preserves_edit_order(self) -> None:
        trace = {
            "schema_version": "idol_05_production_graph_trace.v1",
            "source_edit_map": {"path": "runs/a/04-edit-map.yaml", "sha256": "1" * 64},
            "source_edit_recipe": {"path": "runs/a/final-recipe.yaml", "sha256": "2" * 64},
            "deliverable_bindings": [
                {
                    "output_id": "OUT_B",
                    "edit_segment_ids": ["SEG_B01", "SEG_B02"],
                    "screen_progression_node_ids": ["SPN_02", "SPN_01"],
                    "section_ids": ["S02", "S01"],
                },
                {
                    "output_id": "OUT_A",
                    "edit_segment_ids": ["SEG_A01"],
                    "screen_progression_node_ids": ["SPN_A01"],
                    "section_ids": ["S01"],
                },
            ],
            "post05_mutation_boundary": (
                "post05_release_and_analytics_are_append_only_evidence_"
                "and_never_mutate_mv_truth"
            ),
        }
        reordered = json.loads(json.dumps(trace))
        reordered["deliverable_bindings"].reverse()
        out_b = next(
            item for item in reordered["deliverable_bindings"] if item["output_id"] == "OUT_B"
        )
        out_b["screen_progression_node_ids"].reverse()
        out_b["section_ids"].reverse()
        self.assertEqual(
            production_graph_trace_sha256(trace),
            production_graph_trace_sha256(reordered),
        )
        changed_order = json.loads(json.dumps(trace))
        changed_order["deliverable_bindings"][0]["edit_segment_ids"].reverse()
        self.assertNotEqual(
            production_graph_trace_sha256(trace),
            production_graph_trace_sha256(changed_order),
        )


if __name__ == "__main__":
    unittest.main()
