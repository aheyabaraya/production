#!/usr/bin/env python3
"""Synthetic JSON Schema behavior for source-owned analysis_id values."""
from __future__ import annotations

import json
import unittest
from pathlib import Path

from jsonschema import Draft202012Validator

ROOT = Path(__file__).resolve().parents[2]
SCHEMA_PATH = ROOT / "schemas" / "video-reference-analysis-registry.schema.json"
HEX64 = "a" * 64
FIXTURE_IDS = (
    "BV1vPndzSEn2_source_first_read_v1",
    "BV1vPndzSEn2_source_first_read_v2",
    "source-scene-reading-v1",
    "kU9mHY1gG1s-source-first-read-v1",
    "SOURCE_LAYER_A_B_FIRST_READ_V2_20260801",
)


def load_schema() -> dict:
    return json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))


def file_ref(path: str) -> dict[str, str]:
    return {"path": path, "sha256": HEX64}


def registry_with_analysis_id(analysis_id: object) -> dict:
    return {
        "schema_version": "idol_video_reference_analysis_registry.v2",
        "artifact_type": "video_reference_analysis_registry",
        "hub_root": "source-materials/video-sources",
        "read_first_path": "source-materials/video-sources/READ-FIRST.md",
        "analysis_owner_contract": {
            "shared_hub_role": (
                "source_identity_media_hashes_navigation_and_canonical_source_observation"
            ),
            "creative_owner": (
                "source_owned_human_or_assigned_model_layer_a_b_observation"
            ),
            "complete_requires": [
                "exact_analysis_inputs",
                "whole_source_flow",
                "detailed_timestamped_scene_observations",
                "source_transfer_boundary",
                "source_exclusion_boundary",
            ],
            "machine_validation_boundary": (
                "paths_hashes_required_headings_and_declared_status_only_"
                "no_creative_adequacy_claim"
            ),
        },
        "sources": [
            {
                "source_key": "youtube:TEST123",
                "title": "fixture",
                "duration_seconds": 1.0,
                "source_manifest": file_ref("source-manifest.yaml"),
                "primary_media": file_ref("video.mp4"),
                "analysis_state": "detailed_analysis_available",
                "analysis_records": [
                    {
                        "analysis_id": analysis_id,
                        "owner_scope": "source_materials_video_source",
                        "authoring_stage": "source_first_read",
                        "status": "complete",
                        "analysis": file_ref("analysis.md"),
                        "analysis_inputs": [
                            {
                                "role": "original_video",
                                "path": "video.mp4",
                                "sha256": HEX64,
                            }
                        ],
                        "coverage_summary": "fixture",
                        "missing_analysis": [],
                        "authorship_boundary": (
                            "analysis_prose_is_human_or_assigned_model_authored_"
                            "source_hub_is_canonical_owner"
                        ),
                    }
                ],
            }
        ],
        "automation_boundaries": {
            "network_access": False,
            "creative_authoring": False,
            "analysis_completion_inference": False,
            "download_or_generation_approval": False,
        },
    }


def schema_errors(document: dict) -> list[str]:
    return [
        error.message
        for error in Draft202012Validator(load_schema()).iter_errors(document)
    ]


class VideoReferenceAnalysisSchemaTest(unittest.TestCase):
    def test_schema_is_draft_2020_12(self) -> None:
        Draft202012Validator.check_schema(load_schema())

    def test_fixture_ids_are_accepted_case_sensitively(self) -> None:
        for analysis_id in FIXTURE_IDS:
            document = registry_with_analysis_id(analysis_id)
            self.assertEqual([], schema_errors(document), analysis_id)
            self.assertEqual(
                analysis_id,
                document["sources"][0]["analysis_records"][0]["analysis_id"],
            )

    def test_mixed_case_ids_are_distinct_and_not_normalized(self) -> None:
        upper = registry_with_analysis_id("AbC-id")
        lower = registry_with_analysis_id("abc-id")
        self.assertEqual([], schema_errors(upper))
        self.assertEqual([], schema_errors(lower))
        kept_upper = upper["sources"][0]["analysis_records"][0]["analysis_id"]
        kept_lower = lower["sources"][0]["analysis_records"][0]["analysis_id"]
        self.assertEqual("AbC-id", kept_upper)
        self.assertEqual("abc-id", kept_lower)
        self.assertNotEqual(kept_upper, kept_lower)
        self.assertNotEqual(kept_upper.lower(), kept_upper)

    def test_ascii_length_and_forbidden_characters(self) -> None:
        self.assertTrue(schema_errors(registry_with_analysis_id("")))
        self.assertTrue(schema_errors(registry_with_analysis_id("A")))
        self.assertTrue(schema_errors(registry_with_analysis_id("AB")))
        self.assertEqual([], schema_errors(registry_with_analysis_id("AAA")))
        self.assertEqual([], schema_errors(registry_with_analysis_id("A" + "B" * 100)))
        self.assertTrue(schema_errors(registry_with_analysis_id("A" + "B" * 101)))
        rejected = [
            "../secret",
            "A/../B",
            "A..B",
            "AA\\BB",
            "AA BB",
            " AAA",
            "AAA ",
            "AA\nBB",
            "AA\tBB",
            "AA\x00B",
            "-ABC",
            "_ABC",
            "가나다",
            "AA.B",
        ]
        for analysis_id in rejected:
            self.assertTrue(
                schema_errors(registry_with_analysis_id(analysis_id)),
                repr(analysis_id),
            )

    def test_terminal_newline_and_crlf_are_rejected(self) -> None:
        rejected = [
            "AAA\n",
            "AAA\r\n",
            "BV1vPndzSEn2_source_first_read_v1\n",
            "source-scene-reading-v1\r\n",
        ]
        for analysis_id in rejected:
            self.assertTrue(
                schema_errors(registry_with_analysis_id(analysis_id)),
                repr(analysis_id),
            )

    def test_complete_scoped_requires_parent_ranges_and_keeps_complete(self) -> None:
        self.assertEqual([], schema_errors(registry_with_analysis_id("AAA")))
        scoped = registry_with_analysis_id("SCOPED_ID")
        record = scoped["sources"][0]["analysis_records"][0]
        record["status"] = "complete_scoped"
        self.assertTrue(schema_errors(scoped))
        record["covered_ranges"] = [{"start_seconds": 12.0, "end_seconds": 16.0}]
        record["analysis_inputs"] = [
            {"role": "original_video", "path": "video.mp4", "sha256": HEX64},
            {
                "role": "parent_complete_analysis",
                "path": "parent.md",
                "sha256": HEX64,
            },
        ]
        self.assertEqual([], schema_errors(scoped))
        record["covered_ranges"] = [{"start_seconds": -1, "end_seconds": 4}]
        self.assertTrue(schema_errors(scoped))


if __name__ == "__main__":
    unittest.main()
