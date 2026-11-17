#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import re
import tempfile
import unittest
from pathlib import Path
from urllib.parse import unquote, urlparse

import yaml

import sys

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))
import idol_reference_catalog_lookup as lookup  # noqa: E402
import idol_reference_comparison_packet as packet  # noqa: E402
from lib.idol_artifact_integrity import HashBinder  # noqa: E402


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def path_from_file_uri(uri: str) -> Path:
    parsed = urlparse(uri.split("#", 1)[0])
    return Path(unquote(parsed.path))


class RequestGuardTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory(prefix="idol-cmp-guard-", dir="/private/tmp")
        self.root = Path(self.tmp.name)
        (self.root / "catalog/references").mkdir(parents=True)
        catalog = {
            "schema_version": "idol_reference_management_catalog.v3",
            "reference_units": [],
        }
        rel = "catalog/references/reference-catalog.yaml"
        path = self.root / rel
        raw = yaml.safe_dump(catalog, sort_keys=False).encode("utf-8")
        path.write_bytes(raw)
        digest = sha256_bytes(raw)
        self.catalog_rel = rel
        self.digest = digest
        self.lookup = {
            "status": "no_match",
            "named_gap_id": "gap",
            "catalog_digest": digest,
            "query_digest": "b" * 64,
            "candidates": [],
            "held_excluded": [
                {"reference_unit_id": "HELD_ID", "reason": "restricted_or_unresolved_origin"}
            ],
            "coverage": {"verification_scope": "navigation_declared_only"},
            "index_receipts": [
                {
                    "index_id": "REFERENCE_MANAGEMENT_CATALOG",
                    "locator": rel,
                    "digest": digest,
                    "loaded": True,
                    "byte_size": len(raw),
                }
            ],
        }
        self.base_request = {
            "schema_version": packet.CONTRACT,
            "named_gap_id": "gap",
            "source_freshness": {"catalog_sha256": digest},
            "page_budget": {
                "max_candidates": 4,
                "max_evidence_items": 40,
                "max_render_cells": 24,
            },
            "requested_candidates": [
                {
                    "request_id": "slot-a",
                    "identity_kind": "source_sequence_unit",
                    "source_owned_id": "SC01",
                }
            ],
            "evidence_requests": [
                {
                    "request_id": "slot-a",
                    "evidence_kind": "sequence_window",
                    "bind_from_lookup": "frames",
                }
            ],
        }

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def run_packet(self, request: dict, lookup_doc: dict | None = None, **kwargs):
        hasher = HashBinder(self.root, profile="canonical_gate")
        return packet.assemble_packet(
            root=self.root,
            request=request,
            lookup=lookup_doc or self.lookup,
            hasher=hasher,
            **kwargs,
        )

    def test_request_requires_candidates_freshness_and_budget(self) -> None:
        missing_ids = dict(self.base_request)
        missing_ids["requested_candidates"] = []
        with self.assertRaises(packet.PacketError) as raised:
            self.run_packet(missing_ids)
        self.assertEqual("requested_candidates_required", str(raised.exception))

    def test_attested_digest_without_current_bytes_is_not_fresh(self) -> None:
        (self.root / self.catalog_rel).write_bytes(b"changed-catalog\n")
        with self.assertRaises(packet.PacketError) as raised:
            self.run_packet(self.base_request)
        self.assertEqual("stale_index_bytes", str(raised.exception))
        held = packet.hold_packet(str(raised.exception))
        self.assertEqual("not_verified", held["assessment_scope"]["source_freshness"])
        self.assertFalse(held["freshness"]["verified"])

    def test_matching_request_and_lookup_digest_without_receipts_holds(self) -> None:
        lookup_doc = dict(self.lookup)
        lookup_doc["index_receipts"] = []
        with self.assertRaises(packet.PacketError) as raised:
            self.run_packet(self.base_request, lookup_doc)
        self.assertEqual("lookup_index_receipts_required", str(raised.exception))

    def test_owned_and_ref_must_be_consistent(self) -> None:
        request = dict(self.base_request)
        request["requested_candidates"] = [
            {
                "request_id": "slot-a",
                "identity_kind": "source_sequence_unit",
                "source_owned_id": "SC01",
                "reference_unit_id": "SC02",
            }
        ]
        result = self.run_packet(request)
        self.assertEqual("partial", result["status"])
        self.assertEqual("inconsistent_owned_and_ref", result["candidates"][0]["hold_reason"])
        self.assertEqual("malformed", result["candidates"][0]["binding_status"])

    def test_held_id_stays_held(self) -> None:
        request = {
            "schema_version": packet.CONTRACT,
            "named_gap_id": "gap",
            "source_freshness": {"catalog_sha256": self.digest},
            "page_budget": {
                "max_candidates": 4,
                "max_evidence_items": 40,
                "max_render_cells": 24,
            },
            "requested_candidates": [
                {
                    "request_id": "held-slot",
                    "identity_kind": "catalog_reference_unit",
                    "source_owned_id": "HELD_ID",
                    "reference_unit_id": "HELD_ID",
                }
            ],
            "evidence_requests": [
                {
                    "request_id": "held-slot",
                    "evidence_kind": "individual_still",
                    "bind_from_lookup": "selected_evidence",
                }
            ],
        }
        result = self.run_packet(request)
        self.assertEqual("held", result["candidates"][0]["binding_status"])
        self.assertEqual(
            "restricted_or_unresolved_origin", result["candidates"][0]["hold_reason"]
        )

    def test_non_mapping_pointer_does_not_crash(self) -> None:
        lookup_doc = dict(self.lookup)
        lookup_doc["candidates"] = [
            {
                "identity_kind": "catalog_reference_unit",
                "source_owned_id": "REF_STILL",
                "reference_unit_id": "REF_STILL",
                "bindable": True,
                "source_manifest": None,
                "frames": [],
                "selected_evidence": [{"path": "evidence/still-a.png", "sha256": "0" * 64}],
            }
        ]
        request = {
            "schema_version": packet.CONTRACT,
            "named_gap_id": "gap",
            "source_freshness": {"catalog_sha256": self.digest},
            "page_budget": {
                "max_candidates": 4,
                "max_evidence_items": 40,
                "max_render_cells": 24,
            },
            "requested_candidates": [
                {
                    "request_id": "still-slot",
                    "identity_kind": "catalog_reference_unit",
                    "source_owned_id": "REF_STILL",
                }
            ],
            "evidence_requests": [
                {
                    "request_id": "still-slot",
                    "evidence_kind": "individual_still",
                    "pointers": ["not-a-mapping", ["list"], 3, None],
                }
            ],
        }
        result = self.run_packet(request, lookup_doc)
        self.assertEqual("held", result["candidates"][0]["binding_status"])
        self.assertEqual("malformed_pointer", result["candidates"][0]["hold_reason"])


class AssembleFromLookupTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory(prefix="idol-cmp-lookup-", dir="/private/tmp")
        self.root = Path(self.tmp.name)
        self.build_corpus()
        self.lookup_result = lookup.lookup(
            root=self.root,
            catalog_rel=Path("catalog/references/reference-catalog.yaml"),
            named_gap_id="cmp-gap",
            index_mode="multi",
            batch_size=20,
        )

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def hasher(self) -> HashBinder:
        return HashBinder(self.root, profile="canonical_gate")

    def run_packet(self, request: dict, **kwargs):
        return packet.assemble_packet(
            root=self.root,
            request=request,
            lookup=self.lookup_result,
            hasher=self.hasher(),
            **kwargs,
        )

    def write_yaml(self, rel: str, document: dict) -> Path:
        path = self.root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(yaml.safe_dump(document, sort_keys=False), encoding="utf-8")
        return path

    def pointer_for(self, rel: str, data: bytes) -> dict[str, str]:
        path = self.root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        return {"path": rel, "sha256": sha256_bytes(data)}

    def frames(self, prefix: str, start: int) -> list[dict[str, str | int | float]]:
        rows = []
        for order in range(1, 6):
            pointer = self.pointer_for(
                f"source-materials/video-sources/youtube/by-source/srcA/analysis/{prefix}-f{order}.png",
                f"{prefix}-{order}".encode("utf-8"),
            )
            rows.append(
                {
                    "order": order,
                    "path": pointer["path"],
                    "sha256": pointer["sha256"],
                    "source_timestamp_seconds": start + order - 1,
                }
            )
        return rows

    def build_corpus(self) -> None:
        self.video = self.pointer_for(
            "source-materials/video-sources/youtube/by-source/srcA/videos/srcA.mp4",
            b"video-bytes",
        )
        self.foreign_video = self.pointer_for(
            "source-materials/video-sources/youtube/by-source/srcB/videos/srcB.mp4",
            b"other-video",
        )
        manifest_doc = {
            "artifact_type": "source_manifest",
            "identity": {"platform_id": "srcA", "normalized_url": "https://example.invalid/srcA"},
            "canonical_source_root": "source-materials/video-sources/youtube/by-source/srcA",
            "title": "srcA fixture title",
            "discovery_metadata": {"duration_seconds": 120},
            "media": [{"kind": "video", **self.video}],
        }
        manifest_path = self.write_yaml(
            "source-materials/video-sources/youtube/by-source/srcA/source-manifest.yaml",
            manifest_doc,
        )
        self.manifest = {
            "path": manifest_path.relative_to(self.root).as_posix(),
            "sha256": sha256_bytes(manifest_path.read_bytes()),
        }
        self.analysis = self.pointer_for(
            "source-materials/video-sources/youtube/by-source/srcA/analysis/complete.md",
            b"COMPLETE\n",
        )
        self.still = self.pointer_for("evidence/still-a.png", b"still-a")
        self.before = self.pointer_for("evidence/before-a.png", b"before-a")
        self.after = self.pointer_for("evidence/after-a.png", b"after-a")
        self.sheet = self.pointer_for(
            "source-materials/video-sources/youtube/by-source/srcA/contact-sheets/sheet.png",
            b"sheet-bytes",
        )
        self.wrong_sheet = self.pointer_for(
            "source-materials/video-sources/youtube/by-source/srcB/analysis/context.png",
            b"wrong-sheet",
        )
        context_rel = (
            "source-materials/video-sources/youtube/by-source/srcA/analysis/"
            "semantic-boundary-pilot-v1/unit-a/context-manifest.json"
        )
        context_doc = {
            "schema_version": "idol_video_qc_sheet_manifest.v1",
            "video": self.video["path"],
            "source_video": dict(self.video),
            "preset": "half-second",
            "interval_seconds": 0.25,
            "sheets": [
                {
                    "part_index": 1,
                    "path": self.before["path"],
                    "sha256": self.before["sha256"],
                    "source_time_range": "9.000-10.000",
                    "timestamps": [9.0, 9.25, 9.5, 9.75],
                },
                {
                    "part_index": 2,
                    "path": self.after["path"],
                    "sha256": self.after["sha256"],
                    "source_time_range": "14.000-15.000",
                    "timestamps": [14.0, 14.25, 14.5, 14.75],
                },
            ],
        }
        context_path = self.root / context_rel
        context_path.parent.mkdir(parents=True, exist_ok=True)
        context_raw = json.dumps(context_doc, indent=2).encode("utf-8")
        context_path.write_bytes(context_raw)
        self.context_manifest = {"path": context_rel, "sha256": sha256_bytes(context_raw)}
        wrong_rel = (
            "source-materials/video-sources/youtube/by-source/srcB/analysis/"
            "semantic-boundary-pilot-v1/unit-b/context-manifest.json"
        )
        wrong_doc = {
            "schema_version": "idol_video_qc_sheet_manifest.v1",
            "video": self.foreign_video["path"],
            "source_video": dict(self.foreign_video),
            "sheets": [
                {
                    "part_index": 1,
                    "path": self.wrong_sheet["path"],
                    "sha256": self.wrong_sheet["sha256"],
                    "source_time_range": "1.000-6.000",
                    "timestamps": [1.0, 1.25],
                }
            ],
        }
        wrong_path = self.root / wrong_rel
        wrong_path.parent.mkdir(parents=True, exist_ok=True)
        wrong_raw = json.dumps(wrong_doc, indent=2).encode("utf-8")
        wrong_path.write_bytes(wrong_raw)
        self.wrong_context_manifest = {"path": wrong_rel, "sha256": sha256_bytes(wrong_raw)}
        frames_a = self.frames("sc01", 10)
        frames_b = self.frames("sc02", 40)
        batch_path = self.write_yaml(
            "source-materials/video-sources/youtube/by-source/srcA/analysis/reusable-sequence-units-v1.yaml",
            {
                "schema_version": "idol_video_reference_sequence_unit_registry.v1",
                "artifact_type": "reusable_sequence_unit_batch",
                "source_key": "youtube:srcA",
                "source_manifest": self.manifest,
                "units": [
                    {
                        "source_sequence_unit_id": "SC01",
                        "source_key": "youtube:srcA",
                        "source_manifest": self.manifest,
                        "analysis_ref": self.analysis,
                        "event_identity": "event-sc01",
                        "source_time_range": "10.000-14.000s",
                        "frames": frames_a,
                        "purpose_classes": ["visible_action_or_hold"],
                        "search_terms": ["unit-a"],
                        "transfer_boundary": "body",
                        "do_not_transfer": "faces",
                    },
                    {
                        "source_sequence_unit_id": "SC02",
                        "source_key": "youtube:srcA",
                        "source_manifest": self.manifest,
                        "analysis_ref": self.analysis,
                        "event_identity": "event-sc02",
                        "source_time_range": "40.000-44.000s",
                        "frames": frames_b,
                        "purpose_classes": ["visible_action_or_hold"],
                        "search_terms": ["unit-b"],
                    },
                ],
            },
        )
        batch_pointer = {
            "path": batch_path.relative_to(self.root).as_posix(),
            "sha256": sha256_bytes(batch_path.read_bytes()),
        }
        self.write_yaml(
            "catalog/references/reference-catalog.yaml",
            {
                "schema_version": "idol_reference_management_catalog.v3",
                "reference_units": [
                    {
                        "reference_unit_id": "REF_STILL",
                        "source_identity": "youtube:srcA",
                        "title": "still unit",
                        "media_type": "image",
                        "source_manifest": self.manifest,
                        "analysis_ref": self.analysis,
                        "inspection_status": "complete",
                        "reuse_status": "candidate_for_reuse",
                        "purpose_classes": ["subject_state_or_pose"],
                        "search_terms": ["still-a"],
                        "selected_evidence": [self.still],
                    },
                    {
                        "reference_unit_id": "REF_HELD",
                        "source_identity": "youtube:srcA",
                        "title": "held unit",
                        "media_type": "video",
                        "source_manifest": self.manifest,
                        "analysis_ref": self.analysis,
                        "inspection_status": "restricted",
                        "reuse_status": "do_not_reuse",
                        "purpose_classes": ["visible_action_or_hold"],
                        "search_terms": ["held-a"],
                    },
                ],
            },
        )
        self.write_yaml(
            "source-materials/video-sources/reference-hub-catalog.yaml",
            {"schema_version": "idol_downloaded_reference_hub.v1", "sources": []},
        )
        self.write_yaml(
            "source-materials/image-sources/reference-image-catalog.yaml",
            {"schema_version": "idol_image_reference_source_catalog.v1", "sources": []},
        )
        self.write_yaml(
            "source-materials/video-sources/reference-analysis-registry.yaml",
            {"schema_version": "idol_video_reference_analysis_registry.v2", "sources": []},
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
                        "source_time_range": "10.000-14.000s",
                        "purpose_classes": ["visible_action_or_hold"],
                        "batch_pointer": batch_pointer,
                    },
                    {
                        "source_sequence_unit_id": "SC02",
                        "source_key": "youtube:srcA",
                        "source_time_range": "40.000-44.000s",
                        "purpose_classes": ["visible_action_or_hold"],
                        "batch_pointer": batch_pointer,
                    },
                ],
            },
        )

    def request(self, **overrides) -> dict:
        payload = {
            "schema_version": packet.CONTRACT,
            "named_gap_id": "cmp-gap",
            "source_freshness": {"catalog_sha256": self.lookup_result["catalog_digest"]},
            "page_budget": {
                "max_candidates": 4,
                "max_evidence_items": 40,
                "max_render_cells": 24,
            },
            "requested_candidates": [
                {
                    "request_id": "slot-a",
                    "identity_kind": "source_sequence_unit",
                    "source_owned_id": "SC01",
                }
            ],
            "evidence_requests": [
                {
                    "request_id": "slot-a",
                    "evidence_kind": "sequence_window",
                    "bind_from_lookup": "frames",
                    "context_manifest": self.context_manifest,
                    "before_context": self.before,
                    "after_context": self.after,
                }
            ],
        }
        payload.update(overrides)
        return payload

    def test_sequence_is_one_unit_and_frames_are_not(self) -> None:
        result = self.run_packet(self.request())
        self.assertEqual("assembled", result["status"])
        self.assertEqual(
            "verified_current_index_bytes",
            result["assessment_scope"]["source_freshness"],
        )
        self.assertTrue(result["freshness"]["verified"])
        self.assertNotIn("ranking", result)
        self.assertNotIn("best_candidate", result)
        candidate = result["candidates"][0]
        frames = [row for row in candidate["evidence"] if row["role"] == "sequence_frame"]
        self.assertEqual(5, len(frames))
        self.assertTrue(all(row["counts_as_comparison_unit"] is False for row in frames))
        self.assertEqual(1, candidate["sequence_unit"]["unit_count"])
        self.assertTrue(candidate["sequence_unit"]["counts_as_comparison_unit"])
        self.assertEqual(1, candidate["comparison_unit_count"])
        self.assertFalse(candidate["context"]["before_context"]["counts_as_comparison_unit"])
        self.assertEqual("9.000-10.000", candidate["context"]["before_context"]["source_time_range"])
        self.assertIsNone(candidate["context"]["before_context"].get("semantic_event"))
        self.assertEqual(self.video["sha256"], candidate["original_media"]["sha256"])
        self.assertEqual(120, candidate["original_media"]["duration_seconds"])
        self.assertEqual("srcA fixture title", candidate["original_media"]["source_title"])
        self.assertEqual("body", candidate["lookup_row"]["transfer_boundary"])
        self.assertEqual("faces", candidate["lookup_row"]["do_not_transfer"])
        self.assertEqual("event-sc01", candidate["lookup_row"]["event_identity"])

    def test_nested_html_file_uris_resolve_on_filesystem(self) -> None:
        result = self.run_packet(
            self.request(), render_rel="task/G01/live-pilot/view.html"
        )
        html_text = (self.root / "task/G01/live-pilot/view.html").read_text(encoding="utf-8")
        self.assertEqual(result["render"]["sha256"], packet.sha256_text(html_text))
        srcs = re.findall(r'<img src="(file:[^"]+)"', html_text)
        self.assertGreaterEqual(len(srcs), 5)
        for src in srcs:
            parsed = urlparse(src)
            self.assertEqual("file", parsed.scheme)
            path = path_from_file_uri(src)
            self.assertTrue(path.is_absolute())
            self.assertTrue(path.is_file(), msg=src)
            path.relative_to(self.root.resolve())
        hrefs = re.findall(r'<a href="(file:[^"]+)"', html_text)
        self.assertTrue(any("#t=10" in item or "#t=10.0" in item for item in hrefs))
        video_path = path_from_file_uri(hrefs[0])
        self.assertTrue(video_path.is_file())
        self.assertEqual(self.video["sha256"], sha256_bytes(video_path.read_bytes()))
        self.assertIn("<details", html_text)
        self.assertIn("transfer_boundary: body", html_text)
        self.assertIn("do_not_transfer: faces", html_text)
        captions = re.findall(r"<figcaption>([^<]*)</figcaption>", html_text)
        self.assertTrue(captions)
        self.assertTrue(all("sha256=" not in caption for caption in captions))

    def test_render_refuses_collision_and_existing_output(self) -> None:
        frame_rel = next(
            row["path"]
            for row in self.lookup_result["candidates"]
            if row.get("source_owned_id") == "SC01"
            for row in (row.get("frames") or [])
        )
        with self.assertRaises(packet.PacketError) as raised:
            self.run_packet(self.request(), render_rel=frame_rel)
        self.assertEqual("output_collides_with_input", str(raised.exception))
        existing = self.root / "task/G01/live-pilot/view.html"
        existing.parent.mkdir(parents=True, exist_ok=True)
        existing.write_text("unrelated\n", encoding="utf-8")
        with self.assertRaises(packet.PacketError) as exists:
            self.run_packet(self.request(), render_rel="task/G01/live-pilot/view.html")
        self.assertEqual("output_exists_create_only", str(exists.exception))
        self.assertEqual("unrelated\n", existing.read_text(encoding="utf-8"))

    def test_source_window_requires_original_media_and_bounds(self) -> None:
        request = self.request(
            evidence_requests=[
                {
                    "request_id": "slot-a",
                    "evidence_kind": "source_window",
                    "window": {"start_seconds": 10.0, "end_seconds": 14.0},
                }
            ]
        )
        result = self.run_packet(request)
        self.assertEqual("assembled", result["status"])
        window = result["candidates"][0]["evidence"][0]
        self.assertEqual(self.video["sha256"], window["sha256"])
        self.assertEqual("hashed", window["byte_integrity"])
        oob = self.request(
            evidence_requests=[
                {
                    "request_id": "slot-a",
                    "evidence_kind": "source_window",
                    "window": {"start_seconds": 200.0, "end_seconds": 210.0},
                }
            ]
        )
        out = self.run_packet(oob)
        self.assertEqual("timestamp_out_of_bounds", out["candidates"][0]["hold_reason"])
        foreign = self.request(
            evidence_requests=[
                {
                    "request_id": "slot-a",
                    "evidence_kind": "source_window",
                    "window": {"start_seconds": 10.0, "end_seconds": 14.0},
                    "source_media": self.foreign_video,
                }
            ]
        )
        foreign_result = self.run_packet(foreign)
        self.assertEqual("foreign_source_evidence", foreign_result["candidates"][0]["hold_reason"])

    def test_foreign_sequence_frames_do_not_bind(self) -> None:
        sc02 = next(
            row
            for row in self.lookup_result["candidates"]
            if row.get("source_owned_id") == "SC02"
        )
        request = self.request(
            evidence_requests=[
                {
                    "request_id": "slot-a",
                    "evidence_kind": "sequence_window",
                    "pointers": sc02["frames"],
                }
            ]
        )
        result = self.run_packet(request)
        self.assertEqual("foreign_source_evidence", result["candidates"][0]["hold_reason"])

    def test_cli_refuses_overwrite_of_request(self) -> None:
        request = self.request()
        (self.root / "work").mkdir()
        (self.root / "work/request.json").write_text(json.dumps(request), encoding="utf-8")
        (self.root / "work/lookup.json").write_text(
            json.dumps(self.lookup_result), encoding="utf-8"
        )
        code = packet.main(
            [
                "--repo-root",
                str(self.root),
                "--request",
                "work/request.json",
                "--lookup-result",
                "work/lookup.json",
                "--output",
                "work/request.json",
            ]
        )
        self.assertEqual(1, code)

    def test_status_is_never_pass(self) -> None:
        result = self.run_packet(self.request())
        self.assertNotIn('"status": "pass"', json.dumps(result))
        self.assertEqual("assembled", result["status"])
        self.assertEqual("unknown", result["assessment_scope"]["selection"])
        self.assertEqual("unknown", result["assessment_scope"]["semantic_quality"])

    def test_source_window_extra_pointers_cannot_bind_foreign_file(self) -> None:
        request = self.request(
            evidence_requests=[
                {
                    "request_id": "slot-a",
                    "evidence_kind": "source_window",
                    "window": {"start_seconds": 10.0, "end_seconds": 14.0},
                    "pointers": [self.wrong_sheet],
                }
            ]
        )
        result = self.run_packet(
            request, render_rel="task/G01/live-pilot/window-foreign.html"
        )
        self.assertEqual("foreign_source_evidence", result["candidates"][0]["hold_reason"])
        roles = [row.get("role") for row in result["candidates"][0]["evidence"]]
        self.assertEqual(["source_window"], roles)
        html_text = (
            self.root / "task/G01/live-pilot/window-foreign.html"
        ).read_text(encoding="utf-8")
        self.assertNotIn("srcB/analysis/context.png", html_text)
        sc01 = next(
            row
            for row in self.lookup_result["candidates"]
            if row.get("source_owned_id") == "SC01"
        )
        oob = self.request(
            evidence_requests=[
                {
                    "request_id": "slot-a",
                    "evidence_kind": "source_window",
                    "window": {"start_seconds": 12.0, "end_seconds": 14.0},
                    "pointers": [sc01["frames"][0]],
                }
            ]
        )
        oob_result = self.run_packet(oob)
        self.assertEqual(
            "timestamp_out_of_bounds", oob_result["candidates"][0]["hold_reason"]
        )

    def test_source_window_pointers_do_not_bypass_interval(self) -> None:
        request = self.request(
            evidence_requests=[
                {
                    "request_id": "slot-a",
                    "evidence_kind": "source_window",
                    "window": {"start_seconds": 200.0, "end_seconds": 210.0},
                    "pointers": [self.still],
                }
            ]
        )
        result = self.run_packet(request)
        self.assertEqual("timestamp_out_of_bounds", result["candidates"][0]["hold_reason"])

    def test_wrong_source_context_is_held(self) -> None:
        request = self.request(
            evidence_requests=[
                {
                    "request_id": "slot-a",
                    "evidence_kind": "sequence_window",
                    "bind_from_lookup": "frames",
                    "context_manifest": self.wrong_context_manifest,
                    "before_context": self.wrong_sheet,
                }
            ]
        )
        result = self.run_packet(request)
        self.assertEqual("partial", result["status"])
        self.assertEqual("foreign_source_evidence", result["candidates"][0]["hold_reason"])
        self.assertEqual(1, result["candidates"][0]["comparison_unit_count"])

    def test_context_not_in_manifest_is_held(self) -> None:
        request = self.request(
            evidence_requests=[
                {
                    "request_id": "slot-a",
                    "evidence_kind": "sequence_window",
                    "bind_from_lookup": "frames",
                    "context_manifest": self.context_manifest,
                    "before_context": self.sheet,
                }
            ]
        )
        result = self.run_packet(request)
        self.assertEqual("context_not_in_manifest", result["candidates"][0]["hold_reason"])

    def test_preflight_both_outputs_before_writing_either(self) -> None:
        out = self.root / "work/packet.json"
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text("existing-packet\n", encoding="utf-8")
        with self.assertRaises(packet.PacketError) as raised:
            self.run_packet(
                self.request(),
                render_rel="work/view.html",
                output_rel="work/packet.json",
            )
        self.assertEqual("output_exists_create_only", str(raised.exception))
        self.assertFalse((self.root / "work/view.html").exists())
        self.assertEqual("existing-packet\n", out.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
