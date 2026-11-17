#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import tempfile
import unittest
from pathlib import Path

import yaml

import sys

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))
import idol_reference_catalog_lookup as lookup  # noqa: E402


def sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def legacy_status_consumer(result: dict) -> dict:
    return {
        "status": result["status"],
        "named_gap_id": result["named_gap_id"],
        "match_count": result["match_count"],
        "returned_count": result["returned_count"],
        "next_cursor": result["next_cursor"],
        "candidates": result["candidates"],
        "ranking": result["ranking"],
        "selection": result["selection"],
        "reason": result["reason"],
    }


class IdolReferenceCatalogLookupTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory(prefix="idol-catalog-lookup-", dir="/private/tmp")
        self.root = Path(self.tmp.name)
        self.catalog = self.root / "catalog/references/reference-catalog.yaml"
        self.catalog.parent.mkdir(parents=True)
        self.document = {
            "schema_version": "idol_reference_management_catalog.v3",
            "artifact_type": "unified_reference_management_catalog",
            "status": "active",
            "catalog_path": "catalog/references/reference-catalog.yaml",
            "reference_units": [
                {
                    "reference_unit_id": "REF_A_UNIT",
                    "source_identity": "youtube:abc",
                    "title": "Official wet alley",
                    "media_type": "video",
                    "source_manifest": {"path": "source-a/source-manifest.yaml", "sha256": "a" * 64},
                    "analysis_ref": {"path": "source-a/first-read.md", "sha256": "b" * 64},
                    "inspection_status": "complete",
                    "reuse_status": "candidate_for_reuse",
                    "purpose_classes": ["visible_action_or_hold"],
                    "search_terms": ["wet alley", "젖은 골목"],
                },
                {
                    "reference_unit_id": "REF_B_RESTRICTED",
                    "source_identity": "youtube:def",
                    "title": "Fan edit",
                    "media_type": "video",
                    "source_manifest": {"path": "source-b/source-manifest.yaml", "sha256": "c" * 64},
                    "analysis_ref": {"path": "source-b/first-read.md", "sha256": "d" * 64},
                    "inspection_status": "restricted",
                    "reuse_status": "do_not_reuse",
                    "purpose_classes": ["visible_action_or_hold"],
                    "search_terms": ["wet alley"],
                },
            ],
        }
        self.catalog.write_text(yaml.safe_dump(self.document, sort_keys=False), encoding="utf-8")

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def test_purpose_and_search_return_pointer_only_candidates(self) -> None:
        result = lookup.lookup(
            root=self.root,
            catalog_rel=Path("catalog/references/reference-catalog.yaml"),
            catalog_sha256=sha256_text(self.catalog.read_text(encoding="utf-8")),
            named_gap_id="mj01-wet-alley",
            source_families=["youtube:"],
            purpose_classes=["visible_action_or_hold"],
            search_terms=["젖은 골목"],
        )
        self.assertEqual("pass", result["status"])
        self.assertEqual(["REF_A_UNIT"], [row["reference_unit_id"] for row in result["candidates"]])
        self.assertEqual("candidate_for_worker_review", result["candidates"][0]["disposition"])
        self.assertIsNone(result["ranking"])
        self.assertIsNone(result["selection"])
        self.assertNotIn("full_analysis_text", result["candidates"][0])
        consumed = legacy_status_consumer(result)
        self.assertEqual("pass", consumed["status"])
        self.assertIsNone(consumed["ranking"])
        self.assertIsNone(consumed["selection"])
        self.assertEqual("found_candidates", result["assessment_scope"]["navigation"])
        self.assertEqual("not_requested", result["assessment_scope"]["selected_page_byte_integrity"])
        self.assertEqual("unknown", result["assessment_scope"]["selection"])
        self.assertEqual("unknown", result["assessment_scope"]["semantic_quality"])
        self.assertEqual(
            "source_identity_string_uniqueness_only",
            result["assessment_scope"]["source_identity_counts"],
        )

    def test_stale_catalog_sha_holds(self) -> None:
        with self.assertRaises(lookup.LookupError) as raised:
            lookup.lookup(
                root=self.root,
                catalog_rel=Path("catalog/references/reference-catalog.yaml"),
                catalog_sha256="0" * 64,
                named_gap_id="gap",
                search_terms=["wet"],
            )
        self.assertEqual("stale_catalog_sha256", str(raised.exception))

    def test_restricted_rows_are_excluded_and_no_match_is_named(self) -> None:
        result = lookup.lookup(
            root=self.root,
            catalog_rel=Path("catalog/references/reference-catalog.yaml"),
            named_gap_id="gap",
            search_terms=["missing term"],
        )
        self.assertEqual("no_match", result["status"])
        self.assertEqual("no_local_fit", result["reason"])
        self.assertEqual("restricted_or_unresolved_origin", result["held_excluded"][0]["reason"])
        self.assertEqual("no_candidates", result["assessment_scope"]["navigation"])
        consumed = legacy_status_consumer(result)
        self.assertEqual("no_match", consumed["status"])
        self.assertIsNone(consumed["ranking"])
        self.assertIsNone(consumed["selection"])

    def test_no_metadata_mode_is_navigation_no_candidates(self) -> None:
        empty = self.root / "catalog/references/empty-catalog.yaml"
        empty.write_text(
            yaml.safe_dump(
                {
                    "schema_version": "idol_reference_management_catalog.v3",
                    "reference_units": [],
                },
                sort_keys=False,
            ),
            encoding="utf-8",
        )
        result = lookup.lookup(
            root=self.root,
            catalog_rel=Path("catalog/references/empty-catalog.yaml"),
            named_gap_id="empty-meta",
        )
        self.assertEqual("no_match", result["status"])
        self.assertEqual("no_local_fit", result["reason"])
        self.assertEqual(0, result["match_count"])
        self.assertEqual(0, result["returned_count"])
        self.assertEqual(0, result["coverage"]["metadata_page_count"])
        self.assertEqual([], result["candidates"])
        self.assertEqual("no_candidates", result["assessment_scope"]["navigation"])
        self.assertEqual("not_requested", result["assessment_scope"]["selected_page_byte_integrity"])
        self.assertEqual("unknown", result["assessment_scope"]["selection"])
        self.assertEqual("unknown", result["assessment_scope"]["semantic_quality"])
        consumed = legacy_status_consumer(result)
        self.assertEqual("no_match", consumed["status"])
        self.assertEqual(0, consumed["match_count"])
        self.assertIsNone(consumed["ranking"])
        self.assertIsNone(consumed["selection"])


class IdolReferenceCatalogLookupMultiIndexTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory(
            prefix="idol-catalog-lookup-multi-", dir="/private/tmp"
        )
        self.root = Path(self.tmp.name)
        (self.root / "catalog/references").mkdir(parents=True)

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def write_yaml(self, rel: str, document: dict) -> Path:
        path = self.root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(yaml.safe_dump(document, sort_keys=False), encoding="utf-8")
        return path

    def pointer_for(self, rel: str, data: bytes) -> dict[str, str]:
        path = self.root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        return {"path": rel, "sha256": hashlib.sha256(data).hexdigest()}

    def frame_set(self, prefix: str) -> list[dict[str, str | int | float]]:
        frames = []
        for order in range(1, 6):
            pointer = self.pointer_for(
                f"source-materials/video-sources/youtube/by-source/srcA/analysis/{prefix}-f{order}.png",
                f"{prefix}-{order}".encode("utf-8"),
            )
            frames.append(
                {
                    "order": order,
                    "path": pointer["path"],
                    "sha256": pointer["sha256"],
                    "source_timestamp_seconds": order,
                }
            )
        return frames

    def build_multi_corpus(self) -> None:
        self.manifest_a = self.pointer_for(
            "source-materials/video-sources/youtube/by-source/srcA/source-manifest.yaml",
            b"source: youtube:srcA\n",
        )
        self.manifest_b = self.pointer_for(
            "source-materials/video-sources/bilibili/by-source/srcB/source-manifest.yaml",
            b"source: bilibili:srcB\n",
        )
        self.held_analysis = self.pointer_for(
            "source-materials/video-sources/youtube/by-source/srcA/analysis/held.md",
            b"HELD_RECORD\n",
        )
        self.complete_analysis = self.pointer_for(
            "source-materials/video-sources/youtube/by-source/srcA/analysis/complete.md",
            b"COMPLETE_RECORD\n",
        )
        self.video_a = self.pointer_for(
            "source-materials/video-sources/youtube/by-source/srcA/videos/srcA.mp4",
            b"video-bytes",
        )
        self.one_second = self.pointer_for(
            "source-materials/video-sources/youtube/by-source/srcA/analysis/whole-1s-manifest.json",
            b'{"sheet_count": 1}',
        )
        crop_a = self.pointer_for("evidence/crop-a.png", b"crop-a")
        crop_b = self.pointer_for("evidence/crop-b.png", b"crop-b")
        image_manifest = self.pointer_for(
            "source-materials/image-sources/by-source/IMG_STILL_A/source-manifest.yaml",
            b"source: img\n",
        )
        image_original = self.pointer_for(
            "source-materials/image-sources/by-source/IMG_STILL_A/originals/still.png",
            b"pixels",
        )
        frames_sc01 = self.frame_set("sc01")
        frames_sc10 = self.frame_set("sc10")
        batch_units = [
            {
                "source_sequence_unit_id": "SC01",
                "source_key": "youtube:srcA",
                "source_manifest": self.manifest_a,
                "analysis_ref": self.complete_analysis,
                "event_identity": "event-sc01",
                "source_time_range": "00.000-04.000s",
                "frames": frames_sc01,
                "source_flow_reading": "DO_NOT_COPY_FLOW",
                "observed_facts": "DO_NOT_COPY_FACTS",
                "purpose_classes": ["visible_action_or_hold"],
                "search_terms": ["rain walk"],
                "transfer_boundary": "body and rain",
                "do_not_transfer": "faces",
                "authoring_receipt": "human",
                "source_analysis_review_receipt": "review",
            },
            {
                "source_sequence_unit_id": "SC10",
                "source_key": "youtube:srcA",
                "source_manifest": self.manifest_a,
                "analysis_ref": self.complete_analysis,
                "event_identity": "event-sc10",
                "source_time_range": "00.000-04.000s",
                "frames": frames_sc10,
                "source_flow_reading": "DO_NOT_COPY_FLOW",
                "observed_facts": "DO_NOT_COPY_FACTS",
                "purpose_classes": ["visible_action_or_hold"],
                "search_terms": ["gate turn"],
                "transfer_boundary": "body and rain",
                "do_not_transfer": "faces",
                "authoring_receipt": "human",
                "source_analysis_review_receipt": "review",
            },
        ]
        batch_path = self.write_yaml(
            "source-materials/video-sources/youtube/by-source/srcA/analysis/reusable-sequence-units-v1.yaml",
            {
                "schema_version": "idol_video_reference_sequence_unit_registry.v1",
                "artifact_type": "reusable_sequence_unit_batch",
                "source_key": "youtube:srcA",
                "source_manifest": self.manifest_a,
                "units": batch_units,
            },
        )
        batch_pointer = {
            "path": batch_path.relative_to(self.root).as_posix(),
            "sha256": hashlib.sha256(batch_path.read_bytes()).hexdigest(),
        }
        units = [
            {
                "reference_unit_id": "SC01",
                "source_identity": "youtube:srcA",
                "title": "catalog SC01",
                "media_type": "video",
                "source_manifest": self.manifest_a,
                "analysis_ref": self.complete_analysis,
                "source_locator": "catalog locator SC01",
                "inspection_status": "complete",
                "reuse_status": "candidate_for_reuse",
                "purpose_classes": ["visible_action_or_hold"],
                "search_terms": ["shared-need"],
                "selected_evidence": [crop_a],
            },
            {
                "reference_unit_id": "SC01_POSE",
                "source_identity": "youtube:srcA",
                "title": "same pixels distinct function",
                "media_type": "video",
                "source_manifest": self.manifest_a,
                "analysis_ref": self.complete_analysis,
                "source_locator": "catalog locator SC01",
                "inspection_status": "complete",
                "reuse_status": "candidate_for_reuse",
                "purpose_classes": ["subject_state_or_pose"],
                "search_terms": ["shared-need"],
                "selected_evidence": [crop_b],
            },
            {
                "reference_unit_id": "HELD_EXACT",
                "source_identity": "youtube:srcA",
                "title": "held exact analysis",
                "media_type": "video",
                "source_manifest": self.manifest_a,
                "analysis_ref": self.held_analysis,
                "source_locator": "held locator",
                "inspection_status": "complete",
                "reuse_status": "candidate_for_reuse",
                "purpose_classes": ["visible_action_or_hold"],
                "search_terms": ["held-exact"],
                "selected_evidence": [crop_a],
            },
            {
                "reference_unit_id": "REF_REJECTED",
                "source_identity": "youtube:srcA",
                "title": "rejected",
                "media_type": "video",
                "source_manifest": self.manifest_a,
                "analysis_ref": self.complete_analysis,
                "source_locator": "rejected locator",
                "inspection_status": "rejected",
                "reuse_status": "rejected",
                "purpose_classes": ["visible_action_or_hold"],
                "search_terms": ["shared-need"],
                "selected_evidence": [],
            },
        ]
        many = []
        for index in range(12):
            many.append(
                {
                    "reference_unit_id": f"MANY_{index:02d}",
                    "source_identity": "youtube:srcA",
                    "title": f"many {index}",
                    "media_type": "video",
                    "source_manifest": self.manifest_a,
                    "analysis_ref": self.complete_analysis,
                    "source_locator": f"many {index}",
                    "inspection_status": "complete",
                    "reuse_status": "candidate_for_reuse",
                    "purpose_classes": ["visible_action_or_hold"],
                    "search_terms": ["many-row", f"only-{index:02d}"],
                    "selected_evidence": [crop_a],
                }
            )
        self.write_yaml(
            "catalog/references/reference-catalog.yaml",
            {
                "schema_version": "idol_reference_management_catalog.v3",
                "reference_units": units + many,
                "source_indexes": [
                    {
                        "index_id": "VIDEO_SOURCE_HUB",
                        "locator_kind": "file",
                        "locator": "source-materials/video-sources/reference-hub-catalog.yaml",
                        "status": "active",
                    },
                    {
                        "index_id": "VIDEO_ANALYSIS_REGISTRY",
                        "locator_kind": "file",
                        "locator": "source-materials/video-sources/reference-analysis-registry.yaml",
                        "status": "active",
                    },
                    {
                        "index_id": "IMAGE_SOURCE_HUB",
                        "locator_kind": "file",
                        "locator": "source-materials/image-sources/reference-image-catalog.yaml",
                        "status": "active",
                    },
                ],
            },
        )
        self.write_yaml(
            "source-materials/video-sources/reference-hub-catalog.yaml",
            {
                "schema_version": "idol_downloaded_reference_hub.v1",
                "sources": [
                    {
                        "source_key": "youtube:srcA",
                        "canonical_source_root": "source-materials/video-sources/youtube/by-source/srcA",
                        "titles": ["srcA hub"],
                        "occurrences": [
                            {
                                "source_index_path": self.manifest_a["path"],
                                "source_index_sha256": self.manifest_a["sha256"],
                            }
                        ],
                    },
                    {
                        "source_key": "bilibili:srcB",
                        "canonical_source_root": "source-materials/video-sources/bilibili/by-source/srcB",
                        "titles": ["hub only source"],
                        "occurrences": [
                            {
                                "source_index_path": self.manifest_b["path"],
                                "source_index_sha256": self.manifest_b["sha256"],
                            }
                        ],
                    },
                ],
            },
        )
        self.write_yaml(
            "source-materials/image-sources/reference-image-catalog.yaml",
            {
                "schema_version": "idol_image_reference_source_catalog.v1",
                "sources": [
                    {
                        "source_id": "IMG_STILL_A",
                        "source_identity": "ddragon:splash:still-a",
                        "source_title": "still A",
                        "status": "registered",
                        "local_state": "present",
                        "manifest": image_manifest,
                        "primary_original": image_original,
                    }
                ],
            },
        )
        self.write_yaml(
            "source-materials/video-sources/reference-analysis-registry.yaml",
            {
                "schema_version": "idol_video_reference_analysis_registry.v2",
                "sources": [
                    {
                        "source_key": "youtube:srcA",
                        "analysis_state": "detailed_analysis_available",
                        "analysis_records": [
                            {
                                "status": "hold_incomplete",
                                "analysis": self.held_analysis,
                                "analysis_inputs": [self.video_a],
                            },
                            {
                                "status": "complete",
                                "analysis": self.complete_analysis,
                                "analysis_inputs": [
                                    {"role": "original_video", **self.video_a},
                                    {
                                        "role": "one_second_analysis_surface",
                                        **self.one_second,
                                    },
                                ],
                            },
                        ],
                    }
                ],
            },
        )
        self.write_yaml(
            "source-materials/video-sources/sequence-unit-registry.yaml",
            {
                "schema_version": "idol_video_reference_sequence_unit_registry.v1",
                "artifact_type": "sequence_unit_pointer_registry",
                "units": [
                    {
                        "source_sequence_unit_id": "SC01",
                        "source_key": "youtube:srcA",
                        "source_time_range": "00.000-04.000s",
                        "purpose_classes": ["visible_action_or_hold"],
                        "batch_pointer": batch_pointer,
                    },
                    {
                        "source_sequence_unit_id": "SC10",
                        "source_key": "youtube:srcA",
                        "source_time_range": "00.000-04.000s",
                        "purpose_classes": ["visible_action_or_hold"],
                        "batch_pointer": batch_pointer,
                    },
                ],
            },
        )

    def lookup_multi(self, **kwargs):
        defaults = {
            "root": self.root,
            "catalog_rel": Path("catalog/references/reference-catalog.yaml"),
            "named_gap_id": "multi-gap",
            "index_mode": "multi",
        }
        defaults.update(kwargs)
        return lookup.lookup(**defaults)

    def test_catalog_default_does_not_emit_hub_only_source(self) -> None:
        self.build_multi_corpus()
        result = lookup.lookup(
            root=self.root,
            catalog_rel=Path("catalog/references/reference-catalog.yaml"),
            named_gap_id="catalog-only",
            search_terms=["hub only source"],
        )
        self.assertEqual("no_match", result["status"])

    def test_multi_index_emits_hub_image_and_sequence_without_invented_ids(self) -> None:
        self.build_multi_corpus()
        hub = self.lookup_multi(search_terms=["hub only source"])
        self.assertEqual("video_hub_source", hub["candidates"][0]["identity_kind"])
        self.assertEqual("bilibili:srcB", hub["candidates"][0]["source_owned_id"])
        self.assertIsNone(hub["candidates"][0]["reference_unit_id"])
        self.assertIsNone(hub["candidates"][0]["disposition"])
        images = self.lookup_multi(record_kinds=["image_source"])
        self.assertEqual("IMG_STILL_A", images["candidates"][0]["source_owned_id"])
        sequences = self.lookup_multi(need_kind="sequence", media_kind="video")
        ids = {row["source_owned_id"] for row in sequences["candidates"]}
        self.assertEqual({"SC01", "SC10"}, ids)
        sc01 = next(row for row in sequences["candidates"] if row["source_owned_id"] == "SC01")
        self.assertEqual("video", sc01["media_type"])
        self.assertEqual(5, len(sc01["frames"]))
        self.assertEqual([], sc01["search_term_hits"])
        searched = self.lookup_multi(
            need_kind="sequence",
            media_kind="video",
            search_terms=["rain walk"],
        )
        self.assertEqual({"SC01"}, {row["source_owned_id"] for row in searched["candidates"]})
        self.assertEqual(["rain walk"], searched["candidates"][0]["search_term_hits"])
        self.assertNotIn("DO_NOT_COPY_FLOW", json.dumps(sequences))
        catalog = self.lookup_multi(record_kinds=["catalog_reference_unit"], search_terms=["catalog SC01"])
        self.assertNotIn("sequence_unit_pointers", catalog["candidates"][0])

    def test_held_exact_analysis_is_not_laundered_by_other_complete_record(self) -> None:
        self.build_multi_corpus()
        result = self.lookup_multi(search_terms=["held-exact"])
        cache = result["candidates"][0]["analysis_cache"]
        self.assertEqual("matching_record_not_complete", cache["status"])
        self.assertFalse(result["candidates"][0]["analysis_binding_ready"])
        required = self.lookup_multi(search_terms=["held-exact"], require_analysis=True)
        self.assertEqual("no_match", required["status"])
        self.assertTrue(
            any(row["reason"] == "analysis_evidence_not_ready" for row in required["held_excluded"])
        )

    def test_require_analysis_verifies_bytes_and_default_does_not_claim_ready(self) -> None:
        self.build_multi_corpus()
        declared = self.lookup_multi(search_terms=["catalog SC01"], record_kinds=["catalog_reference_unit"])
        self.assertEqual("declared_complete_agreement", declared["candidates"][0]["analysis_cache"]["status"])
        self.assertFalse(declared["candidates"][0]["analysis_binding_ready"])
        verified = self.lookup_multi(
            search_terms=["catalog SC01"],
            record_kinds=["catalog_reference_unit"],
            require_analysis=True,
        )
        self.assertEqual(
            "verified_complete_agreement",
            verified["candidates"][0]["analysis_cache"]["status"],
        )
        self.assertTrue(verified["candidates"][0]["analysis_binding_ready"])
        self.assertGreaterEqual(verified["cost"]["pointer_files_hashed"], 1)
        self.assertNotIn("COMPLETE_RECORD", json.dumps(verified))

    def test_same_pixels_distinct_bindings_survive_and_conflicting_id_holds(self) -> None:
        self.build_multi_corpus()
        result = self.lookup_multi(
            record_kinds=["catalog_reference_unit"], search_terms=["shared-need"]
        )
        by_id = {row["reference_unit_id"]: row for row in result["candidates"]}
        self.assertIn("SC01", by_id)
        self.assertIn("SC01_POSE", by_id)
        self.assertEqual(by_id["SC01"]["media_identity"], by_id["SC01_POSE"]["media_identity"])
        self.assertNotEqual(by_id["SC01"]["binding_fingerprint"], by_id["SC01_POSE"]["binding_fingerprint"])
        units = yaml.safe_load(
            (self.root / "catalog/references/reference-catalog.yaml").read_text(encoding="utf-8")
        )["reference_units"]
        clone = dict(next(row for row in units if row["reference_unit_id"] == "SC01"))
        clone["purpose_classes"] = ["edit_or_transition"]
        units.append(clone)
        self.write_yaml("catalog/references/reference-catalog.yaml", {
            "schema_version": "idol_reference_management_catalog.v3",
            "reference_units": units,
        })
        conflict = lookup.lookup(
            root=self.root,
            catalog_rel=Path("catalog/references/reference-catalog.yaml"),
            named_gap_id="conflict",
            search_terms=["catalog SC01"],
        )
        self.assertTrue(
            any(row["reason"] == "duplicate_identity_ambiguity" for row in conflict["held_excluded"])
        )
        self.assertNotIn("SC01", [row.get("reference_unit_id") for row in conflict["candidates"]])

    def test_inspection_complete_still_filters_and_rejected_is_diagnostic_only(self) -> None:
        self.build_multi_corpus()
        complete = self.lookup_multi(
            inspection_status="complete", search_terms=["catalog SC01"], record_kinds=["catalog_reference_unit"]
        )
        self.assertEqual(["SC01"], [row["reference_unit_id"] for row in complete["candidates"]])
        rejected = self.lookup_multi(inspection_status="rejected", search_terms=["shared-need"])
        self.assertEqual([], rejected["candidates"])
        self.assertEqual("REF_REJECTED", rejected["nonbindable_diagnostics"][0]["reference_unit_id"])
        self.assertFalse(rejected["nonbindable_diagnostics"][0]["bindable"])
        empty = self.lookup_multi(
            inspection_status="rejected",
            search_terms=["shared-need"],
            max_held_excluded=0,
        )
        self.assertEqual([], empty["nonbindable_diagnostics"])

    def test_verify_hashes_selected_subset_with_memo_not_all_emitted(self) -> None:
        self.build_multi_corpus()
        result = self.lookup_multi(
            search_terms=["only-03"],
            record_kinds=["catalog_reference_unit"],
            require_analysis=True,
        )
        self.assertEqual(1, result["coverage"]["metadata_match_count"])
        self.assertEqual(1, result["coverage"]["page_verified_count"])
        self.assertEqual("selected_metadata_page", result["coverage"]["verification_scope"])
        self.assertLessEqual(result["cost"]["pointer_files_hashed"], 6)
        self.assertNotIn("page_covers_all_matches", result["coverage"])
        self.assertNotIn("page_includes_all_matches", result["coverage"])
        bounded = self.lookup_multi(
            search_terms=["many-row"],
            record_kinds=["catalog_reference_unit"],
            require_analysis=True,
            batch_size=1,
        )
        self.assertGreater(bounded["coverage"]["metadata_match_count"], 1)
        self.assertLessEqual(bounded["coverage"]["page_verified_count"], 1)
        self.assertLessEqual(bounded["returned_count"], 1)
        self.assertIsNotNone(bounded["next_cursor"])
        paged = self.lookup_multi(
            search_terms=["many-row"],
            record_kinds=["catalog_reference_unit"],
            batch_size=1,
            cursor=11,
        )
        self.assertTrue(paged["coverage"]["query_exhausted"])
        self.assertGreater(paged["coverage"]["match_count"], 1)

    def test_parent_escape_and_symlink_are_refused(self) -> None:
        self.build_multi_corpus()
        outside = Path(self.tmp.name) / "outside.txt"
        outside.write_bytes(b"secret")
        leak = self.root / "leak"
        leak.symlink_to(outside.parent)
        units = yaml.safe_load(
            (self.root / "catalog/references/reference-catalog.yaml").read_text(encoding="utf-8")
        )["reference_units"]
        units.append(
            {
                "reference_unit_id": "ESCAPE",
                "source_identity": "youtube:srcA",
                "title": "escape",
                "media_type": "video",
                "source_manifest": {"path": "leak/outside.txt", "sha256": "a" * 64},
                "analysis_ref": self.complete_analysis,
                "source_locator": "escape",
                "inspection_status": "complete",
                "reuse_status": "candidate_for_reuse",
                "purpose_classes": ["visible_action_or_hold"],
                "search_terms": ["escape-row"],
            }
        )
        self.write_yaml(
            "catalog/references/reference-catalog.yaml",
            {"schema_version": "idol_reference_management_catalog.v3", "reference_units": units},
        )
        result = lookup.lookup(
            root=self.root,
            catalog_rel=Path("catalog/references/reference-catalog.yaml"),
            named_gap_id="escape",
            search_terms=["escape-row"],
            check_availability=True,
        )
        self.assertTrue(
            any(row["reason"] in {"symlink_refused", "path must stay inside the repository"} for row in result["held_excluded"])
        )
        link = self.root / "catalog/references/linked-catalog.yaml"
        link.symlink_to(self.root / "catalog/references/reference-catalog.yaml")
        with self.assertRaises(lookup.LookupError) as raised:
            lookup.lookup(
                root=self.root,
                catalog_rel=Path("catalog/references/linked-catalog.yaml"),
                named_gap_id="gap",
            )
        self.assertEqual("symlink_refused", str(raised.exception))

    def test_duplicate_analysis_source_key_is_observable(self) -> None:
        self.build_multi_corpus()
        self.write_yaml(
            "source-materials/video-sources/reference-analysis-registry.yaml",
            {
                "schema_version": "idol_video_reference_analysis_registry.v2",
                "sources": [
                    {"source_key": "youtube:srcA", "analysis_state": "detailed_analysis_available", "analysis_records": []},
                    {"source_key": "youtube:srcA", "analysis_state": "not_analyzed", "analysis_records": []},
                ],
            },
        )
        with self.assertRaises(lookup.LookupError) as raised:
            self.lookup_multi(search_terms=["catalog SC01"])
        self.assertEqual("duplicate_analysis_source_key", str(raised.exception))

    def test_distinct_source_page_is_presentation_not_score(self) -> None:
        self.build_multi_corpus()
        result = self.lookup_multi(page_order="distinct_source", record_kinds=["video_hub_source"], batch_size=2)
        self.assertEqual(
            {"youtube:srcA", "bilibili:srcB"},
            {row["source_identity"] for row in result["candidates"]},
        )
        self.assertIsNone(result["ranking"])
        self.assertIsNone(result["selection"])
        with self.assertRaises(lookup.LookupError) as raised:
            self.lookup_multi(need_kind="scene")
        self.assertEqual("unsupported_need_kind", str(raised.exception))

    def test_analysis_input_tamper_is_not_ready(self) -> None:
        self.build_multi_corpus()
        (self.root / self.video_a["path"]).write_bytes(b"TAMPERED-ORIGINAL-VIDEO")
        result = self.lookup_multi(
            search_terms=["catalog SC01"],
            record_kinds=["catalog_reference_unit"],
            require_analysis=True,
        )
        self.assertEqual([], result["candidates"])
        self.assertFalse(
            any(row.get("analysis_binding_ready") for row in result["candidates"])
        )
        self.assertTrue(
            any(row["reason"] == "analysis_evidence_not_ready" for row in result["held_excluded"])
        )
        (self.root / self.video_a["path"]).write_bytes(b"video-bytes")
        (self.root / self.one_second["path"]).write_bytes(b"TAMPERED-ONE-SECOND")
        second = self.lookup_multi(
            search_terms=["catalog SC01"],
            record_kinds=["catalog_reference_unit"],
            require_analysis=True,
        )
        self.assertEqual([], second["candidates"])
        self.assertFalse(
            any(row.get("analysis_binding_ready") for row in second["candidates"])
        )
        self.assertTrue(
            any(row["reason"] == "analysis_evidence_not_ready" for row in second["held_excluded"])
        )

    def test_page_outside_source_hash_is_not_read(self) -> None:
        self.build_multi_corpus()
        video_z = self.pointer_for(
            "source-materials/video-sources/youtube/by-source/srcZ/videos/srcZ.mp4",
            b"outside-video-bytes",
        )
        analysis_z = self.pointer_for(
            "source-materials/video-sources/youtube/by-source/srcZ/analysis/complete.md",
            b"OUTSIDE_ANALYSIS\n",
        )
        manifest_z = self.pointer_for(
            "source-materials/video-sources/youtube/by-source/srcZ/source-manifest.yaml",
            b"source: youtube:srcZ\n",
        )
        document = yaml.safe_load(
            (self.root / "catalog/references/reference-catalog.yaml").read_text(encoding="utf-8")
        )
        document["reference_units"].extend(
            [
                {
                    "reference_unit_id": "AAA_BOUND",
                    "source_identity": "youtube:srcA",
                    "title": "page unit",
                    "media_type": "video",
                    "source_manifest": self.manifest_a,
                    "analysis_ref": self.complete_analysis,
                    "source_locator": "page locator",
                    "inspection_status": "complete",
                    "reuse_status": "candidate_for_reuse",
                    "purpose_classes": ["visible_action_or_hold"],
                    "search_terms": ["bound-page"],
                    "selected_evidence": [],
                },
                {
                    "reference_unit_id": "ZZZ_OUTSIDE",
                    "source_identity": "youtube:srcZ",
                    "title": "off page unit",
                    "media_type": "video",
                    "source_manifest": manifest_z,
                    "analysis_ref": analysis_z,
                    "source_locator": "outside locator",
                    "inspection_status": "complete",
                    "reuse_status": "candidate_for_reuse",
                    "purpose_classes": ["visible_action_or_hold"],
                    "search_terms": ["bound-page"],
                    "selected_evidence": [],
                },
            ]
        )
        self.write_yaml("catalog/references/reference-catalog.yaml", document)
        registry = yaml.safe_load(
            (
                self.root
                / "source-materials/video-sources/reference-analysis-registry.yaml"
            ).read_text(encoding="utf-8")
        )
        registry["sources"].append(
            {
                "source_key": "youtube:srcZ",
                "analysis_state": "detailed_analysis_available",
                "analysis_records": [
                    {
                        "status": "complete",
                        "analysis": analysis_z,
                        "analysis_inputs": [{"role": "original_video", **video_z}],
                    }
                ],
            }
        )
        self.write_yaml(
            "source-materials/video-sources/reference-analysis-registry.yaml",
            registry,
        )
        (self.root / video_z["path"]).write_bytes(b"TAMPERED-OFFPAGE-VIDEO")
        solo = self.lookup_multi(
            search_terms=["bound-page"],
            record_kinds=["catalog_reference_unit"],
            source_families=["youtube:srcA"],
            require_analysis=True,
        )
        paged = self.lookup_multi(
            search_terms=["bound-page"],
            record_kinds=["catalog_reference_unit"],
            require_analysis=True,
            batch_size=1,
        )
        self.assertGreater(paged["coverage"]["metadata_match_count"], 1)
        self.assertEqual(["AAA_BOUND"], [row["reference_unit_id"] for row in paged["candidates"]])
        self.assertNotIn("ZZZ_OUTSIDE", [row["reference_unit_id"] for row in paged["candidates"]])
        self.assertTrue(paged["candidates"][0]["analysis_binding_ready"])
        self.assertEqual(1, paged["coverage"]["page_verified_count"])
        self.assertEqual(
            solo["cost"]["pointer_files_hashed"],
            paged["cost"]["pointer_files_hashed"],
        )
        self.assertEqual("selected_metadata_page", paged["coverage"]["verification_scope"])

    def test_verify_index_hashes_count_is_ready_not_returned_length(self) -> None:
        self.build_multi_corpus()
        (self.root / self.video_a["path"]).write_bytes(b"TAMPERED-ORIGINAL-VIDEO")
        failed = self.lookup_multi(
            search_terms=["catalog SC01"],
            record_kinds=["catalog_reference_unit"],
            verify_index_hashes=True,
        )
        self.assertEqual(1, failed["returned_count"])
        self.assertFalse(failed["candidates"][0]["analysis_binding_ready"])
        self.assertEqual(0, failed["coverage"]["page_verified_count"])
        missing = self.lookup_multi(
            search_terms=["held-exact"],
            verify_index_hashes=True,
        )
        self.assertEqual(1, missing["returned_count"])
        self.assertFalse(missing["candidates"][0]["analysis_binding_ready"])
        self.assertEqual(0, missing["coverage"]["page_verified_count"])
        (self.root / self.video_a["path"]).write_bytes(b"video-bytes")
        ready = self.lookup_multi(
            search_terms=["catalog SC01"],
            record_kinds=["catalog_reference_unit"],
            verify_index_hashes=True,
        )
        self.assertEqual(1, ready["returned_count"])
        self.assertTrue(ready["candidates"][0]["analysis_binding_ready"])
        self.assertEqual(1, ready["coverage"]["page_verified_count"])
        default = self.lookup_multi(
            search_terms=["catalog SC01"],
            record_kinds=["catalog_reference_unit"],
        )
        self.assertEqual(0, default["coverage"]["page_verified_count"])
        self.assertFalse(default["candidates"][0]["analysis_binding_ready"])
        self.assertEqual("navigation_declared_only", default["coverage"]["verification_scope"])
        self.assertEqual("not_requested", default["assessment_scope"]["selected_page_byte_integrity"])
        self.assertEqual("not_requested", default["candidates"][0]["analysis_cache"]["byte_verify"])

    def test_all_held_page_with_cursor_keeps_legacy_status(self) -> None:
        self.build_multi_corpus()
        (self.root / self.video_a["path"]).write_bytes(b"TAMPERED-ORIGINAL-VIDEO")
        result = self.lookup_multi(
            search_terms=["many-row"],
            record_kinds=["catalog_reference_unit"],
            require_analysis=True,
            batch_size=1,
            cursor=0,
        )
        self.assertEqual("pass", result["status"])
        self.assertEqual([], result["candidates"])
        self.assertEqual(1, result["next_cursor"])
        self.assertGreater(result["match_count"], 1)
        self.assertEqual(1, result["coverage"]["metadata_page_count"])
        self.assertEqual(0, result["returned_count"])
        self.assertEqual(0, result["coverage"]["page_verified_count"])
        self.assertEqual("found_candidates", result["assessment_scope"]["navigation"])
        self.assertEqual(
            "selected_metadata_page",
            result["assessment_scope"]["selected_page_byte_integrity"],
        )
        self.assertEqual("unknown", result["assessment_scope"]["selection"])
        self.assertEqual("unknown", result["assessment_scope"]["semantic_quality"])
        self.assertTrue(
            any(row["reason"] == "analysis_evidence_not_ready" for row in result["held_excluded"])
        )
        consumed = legacy_status_consumer(result)
        self.assertEqual("pass", consumed["status"])
        self.assertEqual([], consumed["candidates"])
        self.assertEqual(1, consumed["next_cursor"])
        self.assertIsNone(consumed["ranking"])
        self.assertIsNone(consumed["selection"])
        last = self.lookup_multi(
            search_terms=["many-row"],
            record_kinds=["catalog_reference_unit"],
            require_analysis=True,
            batch_size=1,
            cursor=11,
        )
        self.assertEqual("no_match", last["status"])
        self.assertEqual("no_local_fit", last["reason"])
        self.assertIsNone(last["next_cursor"])
        self.assertGreater(last["match_count"], 0)
        self.assertEqual("found_candidates", last["assessment_scope"]["navigation"])
        last_consumed = legacy_status_consumer(last)
        self.assertEqual("no_match", last_consumed["status"])
        self.assertEqual("no_local_fit", last_consumed["reason"])

    def test_unverified_mode_does_not_claim_page_byte_integrity(self) -> None:
        self.build_multi_corpus()
        result = self.lookup_multi(
            search_terms=["catalog SC01"],
            record_kinds=["catalog_reference_unit"],
        )
        self.assertEqual("pass", result["status"])
        self.assertEqual("navigation_declared_only", result["coverage"]["verification_scope"])
        self.assertEqual(0, result["coverage"]["page_verified_count"])
        self.assertEqual(result["coverage"]["metadata_page_count"], result["returned_count"])
        self.assertEqual("not_requested", result["assessment_scope"]["selected_page_byte_integrity"])
        self.assertEqual("not_requested", result["candidates"][0]["analysis_cache"]["byte_verify"])
        self.assertFalse(result["candidates"][0]["analysis_binding_ready"])
        self.assertEqual("unknown", result["assessment_scope"]["selection"])
        self.assertEqual("unknown", result["assessment_scope"]["semantic_quality"])
        consumed = legacy_status_consumer(result)
        self.assertEqual("pass", consumed["status"])
        self.assertGreater(consumed["match_count"], 0)
        self.assertIsNone(consumed["ranking"])
        self.assertIsNone(consumed["selection"])

    def test_partial_verified_page_source_count_is_not_event_or_function_diversity(self) -> None:
        self.build_multi_corpus()
        result = self.lookup_multi(
            record_kinds=["catalog_reference_unit"],
            verify_index_hashes=True,
            batch_size=20,
        )
        by_id = {row["reference_unit_id"]: row for row in result["candidates"]}
        self.assertIn("SC01", by_id)
        self.assertIn("SC01_POSE", by_id)
        self.assertIn("HELD_EXACT", by_id)
        self.assertTrue(by_id["SC01"]["analysis_binding_ready"])
        self.assertFalse(by_id["HELD_EXACT"]["analysis_binding_ready"])
        self.assertEqual("agreed", by_id["SC01"]["analysis_cache"]["byte_verify"])
        self.assertEqual("not_eligible", by_id["HELD_EXACT"]["analysis_cache"]["byte_verify"])
        self.assertGreater(result["returned_count"], result["coverage"]["page_verified_count"])
        self.assertGreater(result["coverage"]["page_verified_count"], 0)
        self.assertEqual(1, result["coverage"]["distinct_source_count"])
        self.assertGreater(result["returned_count"], 1)
        self.assertEqual(by_id["SC01"]["media_identity"], by_id["SC01_POSE"]["media_identity"])
        self.assertNotEqual(
            by_id["SC01"]["binding_fingerprint"],
            by_id["SC01_POSE"]["binding_fingerprint"],
        )
        self.assertNotEqual(by_id["SC01"]["purpose_classes"], by_id["SC01_POSE"]["purpose_classes"])
        self.assertEqual(
            "source_identity_string_uniqueness_only",
            result["assessment_scope"]["source_identity_counts"],
        )
        self.assertEqual("unknown", result["assessment_scope"]["selection"])
        self.assertEqual("unknown", result["assessment_scope"]["semantic_quality"])
        self.assertIsNone(result["ranking"])
        self.assertIsNone(result["selection"])
        self.assertEqual(
            "selected_metadata_page",
            result["assessment_scope"]["selected_page_byte_integrity"],
        )
        consumed = legacy_status_consumer(result)
        self.assertEqual("pass", consumed["status"])
        self.assertEqual(result["match_count"], consumed["match_count"])
        self.assertIsNone(consumed["ranking"])
        self.assertIsNone(consumed["selection"])

    def frame_set_at(
        self, prefix: str, timestamps: list[float], source_id: str = "srcA"
    ) -> list[dict[str, str | int | float]]:
        frames = []
        for order, stamp in enumerate(timestamps, start=1):
            pointer = self.pointer_for(
                f"source-materials/video-sources/youtube/by-source/{source_id}/analysis/{prefix}-f{order}.png",
                f"{prefix}-{order}".encode("utf-8"),
            )
            frames.append(
                {
                    "order": order,
                    "path": pointer["path"],
                    "sha256": pointer["sha256"],
                    "source_timestamp_seconds": stamp,
                }
            )
        return frames

    def write_qc_extraction(
        self,
        rel: str,
        video: dict[str, str],
        ranges: list[dict[str, float]],
        *,
        broken: bool = False,
        interval: float = 1.0,
    ) -> dict[str, str]:
        if broken:
            return self.pointer_for(rel, b"{not-json")
        stamps: list[float] = []
        for window in ranges:
            stamp = window["start_seconds"]
            end = window["end_seconds"]
            while stamp <= end + 0.0001:
                stamps.append(stamp)
                stamp += interval
        payload = {
            "schema_version": "idol_video_qc_sheet_manifest.v1",
            "source_video": {"path": video["path"], "sha256": video["sha256"]},
            "interval_seconds": interval,
            "sheets": [{"timestamps": stamps}],
        }
        return self.pointer_for(rel, json.dumps(payload).encode("utf-8"))

    def _sequence_unit(
        self,
        *,
        unit_id: str,
        source_key: str,
        manifest: dict[str, str],
        analysis_ref: dict[str, str],
        frames: list[dict[str, str | int | float]],
        search_terms: list[str],
        source_time_range: str,
    ) -> dict:
        return {
            "source_sequence_unit_id": unit_id,
            "source_key": source_key,
            "source_manifest": manifest,
            "analysis_ref": analysis_ref,
            "event_identity": unit_id,
            "source_time_range": source_time_range,
            "frames": frames,
            "source_flow_reading": "DO_NOT_COPY_FLOW",
            "observed_facts": "DO_NOT_COPY_FACTS",
            "purpose_classes": ["visible_action_or_hold"],
            "search_terms": search_terms,
            "transfer_boundary": "body and rain",
            "do_not_transfer": "faces",
            "authoring_receipt": "human",
            "source_analysis_review_receipt": "review",
        }

    def _commit_batch_and_registry(self, rel: str, document: dict, extra_units: list) -> dict[str, str]:
        document.setdefault("units", []).extend(extra_units)
        self.write_yaml(rel, document)
        pointer = {
            "path": rel,
            "sha256": hashlib.sha256((self.root / rel).read_bytes()).hexdigest(),
        }
        seq_rel = "source-materials/video-sources/sequence-unit-registry.yaml"
        seq = yaml.safe_load((self.root / seq_rel).read_text(encoding="utf-8"))
        for item in seq["units"]:
            if item.get("batch_pointer", {}).get("path") == rel:
                item["batch_pointer"] = pointer
        for unit in extra_units:
            seq["units"].append(
                {
                    "source_sequence_unit_id": unit["source_sequence_unit_id"],
                    "source_key": unit["source_key"],
                    "source_time_range": unit["source_time_range"],
                    "purpose_classes": unit["purpose_classes"],
                    "batch_pointer": pointer,
                }
            )
        self.write_yaml(seq_rel, seq)
        return pointer

    def install_src_a_scoped(
        self,
        *,
        covered_ranges: list[dict[str, float]],
        timestamps: list[float] | None = None,
        parent: dict[str, str] | None = None,
        original_video: dict[str, str] | None = None,
        duration_seconds: float = 120.0,
        extra_sources: list | None = None,
        register_scoped: bool = True,
        catalog_scoped: bool = True,
        extraction: str = "valid",
        duplicate_original: bool = False,
        contradictory_parent: bool = False,
        contradictory_scoped_parent: bool = False,
        include_primary: bool = True,
    ) -> dict:
        self.build_multi_corpus()
        scoped = self.pointer_for(
            "source-materials/video-sources/youtube/by-source/srcA/analysis/scoped.md",
            b"SCOPED_RECORD\n",
        )
        stamps = timestamps or [14.0, 15.0, 16.0, 17.0, 18.0]
        unit = self._sequence_unit(
            unit_id="SC_SCOPED",
            source_key="youtube:srcA",
            manifest=self.manifest_a,
            analysis_ref=scoped,
            frames=self.frame_set_at("sc_scoped", stamps),
            search_terms=["scoped-in-range"],
            source_time_range="14.000-18.000s",
        )
        batch_rel = "source-materials/video-sources/youtube/by-source/srcA/analysis/reusable-sequence-units-v1.yaml"
        batch = yaml.safe_load((self.root / batch_rel).read_text(encoding="utf-8"))
        self._commit_batch_and_registry(batch_rel, batch, [unit])
        video = original_video or self.video_a
        parent_ptr = parent or self.complete_analysis
        records = [
            {
                "status": "hold_incomplete",
                "analysis": self.held_analysis,
                "analysis_inputs": [self.video_a],
            },
            {
                "status": "complete",
                "analysis": self.complete_analysis,
                "analysis_inputs": [
                    {"role": "original_video", **self.video_a},
                    {
                        "role": "one_second_analysis_surface",
                        **self.one_second,
                    },
                ],
            },
        ]
        if contradictory_parent:
            records.append(
                {
                    "status": "hold_incomplete",
                    "analysis": parent_ptr,
                    "analysis_inputs": [{"role": "original_video", **self.video_a}],
                }
            )
        if contradictory_scoped_parent:
            records.append(
                {
                    "status": "complete_scoped",
                    "covered_ranges": covered_ranges,
                    "analysis": parent_ptr,
                    "analysis_inputs": [{"role": "original_video", **self.video_a}],
                }
            )
        if register_scoped:
            scoped_inputs = [
                {"role": "original_video", **video},
                {"role": "parent_complete_analysis", **parent_ptr},
            ]
            if duplicate_original:
                scoped_inputs.append({"role": "original_video", **video})
            if extraction != "missing":
                scoped_inputs.append(
                    {
                        "role": "one_second_analysis_surface",
                        **self.write_qc_extraction(
                            "source-materials/video-sources/youtube/by-source/srcA/analysis/scoped-window.json",
                            video,
                            covered_ranges,
                            broken=extraction == "broken",
                        ),
                    }
                )
            records.append(
                {
                    "status": "complete_scoped",
                    "covered_ranges": covered_ranges,
                    "analysis": scoped,
                    "analysis_inputs": scoped_inputs,
                }
            )
        self.write_yaml(
            "source-materials/video-sources/reference-analysis-registry.yaml",
            {
                "schema_version": "idol_video_reference_analysis_registry.v2",
                "sources": [
                    {
                        "source_key": "youtube:srcA",
                        "analysis_state": "detailed_analysis_available",
                        "duration_seconds": duration_seconds,
                        "source_manifest": self.manifest_a,
                        "primary_media": self.video_a if include_primary else None,
                        "analysis_records": records,
                    },
                    *(extra_sources or []),
                ],
            },
        )
        if catalog_scoped:
            catalog = yaml.safe_load(
                (self.root / "catalog/references/reference-catalog.yaml").read_text(
                    encoding="utf-8"
                )
            )
            catalog["reference_units"].append(
                {
                    "reference_unit_id": "CATALOG_SCOPED",
                    "source_identity": "youtube:srcA",
                    "title": "catalog scoped",
                    "media_type": "video",
                    "source_manifest": self.manifest_a,
                    "analysis_ref": scoped,
                    "source_locator": "catalog locator scoped",
                    "inspection_status": "complete",
                    "reuse_status": "candidate_for_reuse",
                    "purpose_classes": ["visible_action_or_hold"],
                    "search_terms": ["catalog-scoped"],
                    "selected_evidence": [],
                }
            )
            self.write_yaml("catalog/references/reference-catalog.yaml", catalog)
        return {"scoped": scoped, "unit": unit}

    def install_scoped_only_source(self) -> None:
        self.build_multi_corpus()
        scoped = self.pointer_for(
            "source-materials/video-sources/youtube/by-source/srcS/analysis/scoped.md",
            b"SCOPED_ONLY\n",
        )
        video_s = self.pointer_for(
            "source-materials/video-sources/youtube/by-source/srcS/videos/srcS.mp4",
            b"video-s",
        )
        manifest_s = self.pointer_for(
            "source-materials/video-sources/youtube/by-source/srcS/source-manifest.yaml",
            b"source: youtube:srcS\n",
        )
        crop = self.pointer_for(
            "source-materials/video-sources/youtube/by-source/srcS/analysis/scoped-crop.json",
            b"crop-s",
        )
        unit = self._sequence_unit(
            unit_id="SC_SOLO",
            source_key="youtube:srcS",
            manifest=manifest_s,
            analysis_ref=scoped,
            frames=self.frame_set_at("sc_solo", [1.0, 2.0, 3.0, 4.0, 5.0], source_id="srcS"),
            search_terms=["scoped-only-sequence"],
            source_time_range="01.000-05.000s",
        )
        batch_rel = "source-materials/video-sources/youtube/by-source/srcS/analysis/reusable-sequence-units-v1.yaml"
        self._commit_batch_and_registry(
            batch_rel,
            {
                "schema_version": "idol_video_reference_sequence_unit_registry.v1",
                "artifact_type": "reusable_sequence_unit_batch",
                "source_key": "youtube:srcS",
                "source_manifest": manifest_s,
                "units": [],
            },
            [unit],
        )
        analysis = yaml.safe_load(
            (self.root / "source-materials/video-sources/reference-analysis-registry.yaml").read_text(
                encoding="utf-8"
            )
        )
        analysis["sources"].append(
            {
                "source_key": "youtube:srcS",
                "analysis_state": "not_analyzed",
                "duration_seconds": 60.0,
                "primary_media": video_s,
                "analysis_records": [
                    {
                        "status": "complete_scoped",
                        "covered_ranges": [{"start_seconds": 1.0, "end_seconds": 5.0}],
                        "analysis": scoped,
                        "analysis_inputs": [
                            {"role": "original_video", **video_s},
                            {"role": "selected_frame_or_crop", **crop},
                        ],
                    }
                ],
            }
        )
        self.write_yaml(
            "source-materials/video-sources/reference-analysis-registry.yaml", analysis
        )
        hub = yaml.safe_load(
            (self.root / "source-materials/video-sources/reference-hub-catalog.yaml").read_text(
                encoding="utf-8"
            )
        )
        hub["sources"].append(
            {
                "source_key": "youtube:srcS",
                "canonical_source_root": "source-materials/video-sources/youtube/by-source/srcS",
                "titles": ["scoped-only hub"],
                "occurrences": [
                    {
                        "source_index_path": manifest_s["path"],
                        "source_index_sha256": manifest_s["sha256"],
                    }
                ],
            }
        )
        self.write_yaml("source-materials/video-sources/reference-hub-catalog.yaml", hub)
        catalog = yaml.safe_load(
            (self.root / "catalog/references/reference-catalog.yaml").read_text(encoding="utf-8")
        )
        catalog["reference_units"].append(
            {
                "reference_unit_id": "CATALOG_SCOPED_ONLY",
                "source_identity": "youtube:srcS",
                "title": "catalog scoped only",
                "media_type": "video",
                "source_manifest": manifest_s,
                "analysis_ref": scoped,
                "source_locator": "catalog locator scoped only",
                "inspection_status": "complete",
                "reuse_status": "candidate_for_reuse",
                "purpose_classes": ["visible_action_or_hold"],
                "search_terms": ["scoped-only-catalog"],
                "selected_evidence": [],
            }
        )
        self.write_yaml("catalog/references/reference-catalog.yaml", catalog)

    def test_scoped_in_range_sequence_unit_is_ready(self) -> None:
        fixture = self.install_src_a_scoped(
            covered_ranges=[{"start_seconds": 14.0, "end_seconds": 18.0}],
        )
        ready = self.lookup_multi(
            need_kind="sequence",
            search_terms=["scoped-in-range"],
            require_analysis=True,
        )
        self.assertEqual("pass", ready["status"])
        self.assertEqual("SC_SCOPED", ready["candidates"][0]["source_owned_id"])
        self.assertEqual(
            "verified_scoped_agreement",
            ready["candidates"][0]["analysis_cache"]["status"],
        )
        self.assertTrue(ready["candidates"][0]["analysis_binding_ready"])
        self.assertEqual(fixture["scoped"]["path"], ready["candidates"][0]["analysis_ref"]["path"])
        self.assertNotEqual(
            self.complete_analysis["path"], ready["candidates"][0]["analysis_ref"]["path"]
        )
        self.assertEqual("unknown", ready["assessment_scope"]["selection"])
        self.assertEqual("unknown", ready["assessment_scope"]["semantic_quality"])
        catalog = self.lookup_multi(
            search_terms=["catalog-scoped"],
            record_kinds=["catalog_reference_unit"],
            require_analysis=True,
        )
        self.assertEqual("no_match", catalog["status"])
        self.assertTrue(
            any(row["reason"] == "analysis_evidence_not_ready" for row in catalog["held_excluded"])
        )
        legacy = self.lookup_multi(
            need_kind="sequence",
            search_terms=["rain walk"],
            require_analysis=True,
        )
        self.assertEqual("SC01", legacy["candidates"][0]["source_owned_id"])
        self.assertEqual(
            "verified_complete_agreement",
            legacy["candidates"][0]["analysis_cache"]["status"],
        )
        self.assertEqual(
            self.complete_analysis["path"], legacy["candidates"][0]["analysis_ref"]["path"]
        )
        held = self.lookup_multi(search_terms=["held-exact"], require_analysis=True)
        self.assertEqual("no_match", held["status"])

    def test_scoped_out_of_range_and_disjoint_are_not_ready(self) -> None:
        self.install_src_a_scoped(
            covered_ranges=[{"start_seconds": 40.0, "end_seconds": 44.0}],
            catalog_scoped=False,
        )
        outside = self.lookup_multi(
            need_kind="sequence",
            search_terms=["scoped-in-range"],
        )
        self.assertEqual(
            "scoped_timestamps_out_of_range",
            outside["candidates"][0]["analysis_cache"]["status"],
        )
        self.assertFalse(outside["candidates"][0]["analysis_binding_ready"])
        required = self.lookup_multi(
            need_kind="sequence",
            search_terms=["scoped-in-range"],
            require_analysis=True,
        )
        self.assertEqual("no_match", required["status"])
        self.install_src_a_scoped(
            covered_ranges=[
                {"start_seconds": 14.0, "end_seconds": 16.0},
                {"start_seconds": 17.0, "end_seconds": 18.0},
            ],
            catalog_scoped=False,
        )
        disjoint = self.lookup_multi(
            need_kind="sequence",
            search_terms=["scoped-in-range"],
        )
        self.assertEqual(
            "scoped_timestamps_disjoint",
            disjoint["candidates"][0]["analysis_cache"]["status"],
        )
        self.assertFalse(disjoint["candidates"][0]["analysis_binding_ready"])

    def test_foreign_parent_and_unregistered_scoped_are_not_ready(self) -> None:
        self.build_multi_corpus()
        complete_b = self.pointer_for(
            "source-materials/video-sources/bilibili/by-source/srcB/analysis/complete.md",
            b"COMPLETE_B\n",
        )
        video_b = self.pointer_for(
            "source-materials/video-sources/bilibili/by-source/srcB/videos/srcB.mp4",
            b"video-b",
        )
        extra = [
            {
                "source_key": "bilibili:srcB",
                "analysis_state": "detailed_analysis_available",
                "duration_seconds": 90.0,
                "primary_media": video_b,
                "analysis_records": [
                    {
                        "status": "complete",
                        "analysis": complete_b,
                        "analysis_inputs": [
                            {"role": "original_video", **video_b},
                            {
                                "role": "one_second_analysis_surface",
                                **self.one_second,
                            },
                        ],
                    }
                ],
            }
        ]
        self.install_src_a_scoped(
            covered_ranges=[{"start_seconds": 14.0, "end_seconds": 18.0}],
            parent=complete_b,
            extra_sources=extra,
            catalog_scoped=False,
        )
        declared = self.lookup_multi(
            need_kind="sequence",
            search_terms=["scoped-in-range"],
        )
        self.assertEqual(
            "scoped_parent_foreign",
            declared["candidates"][0]["analysis_cache"]["status"],
        )
        self.assertFalse(declared["candidates"][0]["analysis_binding_ready"])
        foreign = self.lookup_multi(
            need_kind="sequence",
            search_terms=["scoped-in-range"],
            require_analysis=True,
        )
        self.assertEqual("no_match", foreign["status"])
        self.install_src_a_scoped(
            covered_ranges=[{"start_seconds": 14.0, "end_seconds": 18.0}],
            register_scoped=False,
            catalog_scoped=False,
        )
        unregistered = self.lookup_multi(
            need_kind="sequence",
            search_terms=["scoped-in-range"],
            require_analysis=True,
        )
        self.assertEqual("no_match", unregistered["status"])

    def test_scoped_only_source_cannot_global_pass(self) -> None:
        self.install_scoped_only_source()
        catalog = self.lookup_multi(
            search_terms=["scoped-only-catalog"],
            record_kinds=["catalog_reference_unit"],
        )
        self.assertEqual(
            "matching_record_not_complete",
            catalog["candidates"][0]["analysis_cache"]["status"],
        )
        self.assertFalse(catalog["candidates"][0]["analysis_binding_ready"])
        catalog_required = self.lookup_multi(
            search_terms=["scoped-only-catalog"],
            record_kinds=["catalog_reference_unit"],
            require_analysis=True,
        )
        self.assertEqual("no_match", catalog_required["status"])
        hub = self.lookup_multi(
            search_terms=["scoped-only hub"],
            record_kinds=["video_hub_source"],
        )
        self.assertEqual("youtube:srcS", hub["candidates"][0]["source_owned_id"])
        self.assertFalse(hub["candidates"][0]["analysis_binding_ready"])
        hub_required = self.lookup_multi(
            search_terms=["scoped-only hub"],
            record_kinds=["video_hub_source"],
            require_analysis=True,
        )
        self.assertEqual("no_match", hub_required["status"])
        sequence = self.lookup_multi(
            need_kind="sequence",
            search_terms=["scoped-only-sequence"],
        )
        self.assertEqual(
            "scoped_parent_missing",
            sequence["candidates"][0]["analysis_cache"]["status"],
        )
        self.assertFalse(sequence["candidates"][0]["analysis_binding_ready"])
        sequence_required = self.lookup_multi(
            need_kind="sequence",
            search_terms=["scoped-only-sequence"],
            require_analysis=True,
        )
        self.assertEqual("no_match", sequence_required["status"])

    def test_legacy_complete_sequence_and_catalog_remain_verified(self) -> None:
        self.build_multi_corpus()
        catalog = self.lookup_multi(
            search_terms=["catalog SC01"],
            record_kinds=["catalog_reference_unit"],
            require_analysis=True,
        )
        self.assertEqual(
            "verified_complete_agreement",
            catalog["candidates"][0]["analysis_cache"]["status"],
        )
        self.assertTrue(catalog["candidates"][0]["analysis_binding_ready"])
        sequence = self.lookup_multi(
            need_kind="sequence",
            search_terms=["rain walk"],
            require_analysis=True,
        )
        self.assertEqual("SC01", sequence["candidates"][0]["source_owned_id"])
        self.assertEqual(
            "verified_complete_agreement",
            sequence["candidates"][0]["analysis_cache"]["status"],
        )
        self.assertEqual(
            self.complete_analysis["path"], sequence["candidates"][0]["analysis_ref"]["path"]
        )
        self.assertEqual("unknown", sequence["assessment_scope"]["selection"])
        self.assertEqual("unknown", sequence["assessment_scope"]["semantic_quality"])

    def test_scoped_missing_or_broken_extraction_is_not_verified(self) -> None:
        self.install_src_a_scoped(
            covered_ranges=[{"start_seconds": 14.0, "end_seconds": 18.0}],
            extraction="missing",
            catalog_scoped=False,
        )
        missing = self.lookup_multi(
            need_kind="sequence",
            search_terms=["scoped-in-range"],
            require_analysis=True,
        )
        self.assertEqual("no_match", missing["status"])
        self.install_src_a_scoped(
            covered_ranges=[{"start_seconds": 14.0, "end_seconds": 18.0}],
            extraction="broken",
            catalog_scoped=False,
        )
        broken = self.lookup_multi(
            need_kind="sequence",
            search_terms=["scoped-in-range"],
            require_analysis=True,
        )
        self.assertEqual("no_match", broken["status"])
        declared = self.lookup_multi(
            need_kind="sequence",
            search_terms=["scoped-in-range"],
        )
        self.assertEqual("declared_scoped_agreement", declared["candidates"][0]["analysis_cache"]["status"])
        self.assertFalse(declared["candidates"][0]["analysis_binding_ready"])

    def test_contradictory_parent_duplicate_input_and_missing_primary_are_not_ready(
        self,
    ) -> None:
        self.install_src_a_scoped(
            covered_ranges=[{"start_seconds": 14.0, "end_seconds": 18.0}],
            contradictory_parent=True,
            catalog_scoped=False,
        )
        contradictory = self.lookup_multi(
            need_kind="sequence",
            search_terms=["scoped-in-range"],
        )
        self.assertEqual(
            "scoped_parent_ambiguous",
            contradictory["candidates"][0]["analysis_cache"]["status"],
        )
        self.assertFalse(contradictory["candidates"][0]["analysis_binding_ready"])
        self.install_src_a_scoped(
            covered_ranges=[{"start_seconds": 14.0, "end_seconds": 18.0}],
            contradictory_scoped_parent=True,
            catalog_scoped=False,
        )
        scoped_twin = self.lookup_multi(
            need_kind="sequence",
            search_terms=["scoped-in-range"],
        )
        self.assertEqual(
            "scoped_parent_ambiguous",
            scoped_twin["candidates"][0]["analysis_cache"]["status"],
        )
        self.assertFalse(scoped_twin["candidates"][0]["analysis_binding_ready"])
        self.install_src_a_scoped(
            covered_ranges=[{"start_seconds": 14.0, "end_seconds": 18.0}],
            duplicate_original=True,
            catalog_scoped=False,
        )
        duplicate = self.lookup_multi(
            need_kind="sequence",
            search_terms=["scoped-in-range"],
        )
        self.assertEqual(
            "scoped_input_role_ambiguous",
            duplicate["candidates"][0]["analysis_cache"]["status"],
        )
        self.assertFalse(duplicate["candidates"][0]["analysis_binding_ready"])
        self.install_src_a_scoped(
            covered_ranges=[{"start_seconds": 14.0, "end_seconds": 18.0}],
            include_primary=False,
            catalog_scoped=False,
        )
        missing_primary = self.lookup_multi(
            need_kind="sequence",
            search_terms=["scoped-in-range"],
            require_analysis=True,
        )
        self.assertEqual("no_match", missing_primary["status"])


if __name__ == "__main__":
    unittest.main()
