#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import os
import subprocess
import sys
import tempfile
import unittest
import uuid
from pathlib import Path

import yaml

try:
    import jsonschema
except ImportError:  # The repository media runtime carries schema validation.
    jsonschema = None


SCRIPTS_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS_DIR))

import idol_reference_hub as reference_hub  # noqa: E402


class IdolReferenceHubTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory(
            prefix="idol-reference-hub-", dir="/private/tmp"
        )
        self.root = Path(self.tmp.name)
        self.hub_root = self.root / "source-materials/video-sources"
        self.hub_root.mkdir(parents=True)
        self.hub = reference_hub.ReferenceHub(self.root)
        self.hub.write_catalog()

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def write_index(
        self,
        name: str,
        sources: list[dict] | dict[str, dict],
        *,
        platform: str = "bilibili",
    ) -> Path:
        collection_rel = Path("source-materials/video-sources") / platform / name
        collection = self.root / collection_rel
        collection.mkdir(parents=True, exist_ok=True)
        index = collection / "source-index-v1.yaml"
        payload = {
            "collection_root": collection_rel.as_posix(),
            "source_platform": platform,
            "sources": sources,
        }
        index.write_text(
            yaml.safe_dump(payload, sort_keys=False), encoding="utf-8"
        )
        return collection

    @staticmethod
    def file_evidence(path: Path) -> dict[str, str | int]:
        return {
            "path": path.as_posix(),
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            "size_bytes": path.stat().st_size,
        }

    def write_qc_manifest(
        self, path: Path, video: Path, sheets: list[Path]
    ) -> Path:
        records = []
        for part_index, sheet in enumerate(sheets, start=1):
            evidence = self.file_evidence(sheet)
            records.append(
                {
                    "part_index": part_index,
                    "path": evidence["path"],
                    "source_time_range": f"{part_index - 1:.3f}-{part_index:.3f}",
                    "timestamp_count": 1,
                    "timestamps": [float(part_index - 1)],
                    "cells": [
                        {
                            "cell_id": f"sheet-{part_index:03d}-cell-0001",
                            "order": 1,
                            "source_timestamp_seconds": float(part_index - 1),
                            "label_timestamp_seconds": float(part_index - 1),
                            "label": f"src {part_index - 1:.3f}s",
                        }
                    ],
                    "sha256": evidence["sha256"],
                    "size_bytes": evidence["size_bytes"],
                }
            )
        payload = {
            "schema_version": "idol_video_qc_sheet_manifest.v1",
            "video": video.as_posix(),
            "source_video": self.file_evidence(video),
            "preset": "three-second",
            "interval_seconds": 3.0,
            "label_offset_seconds": 0.0,
            "segment_duration_seconds": 60.0,
            "columns": 5,
            "thumb_width": 280,
            "thumb_height": 158,
            "sheet_count": len(records),
            "sheets": records,
        }
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
        return path

    def test_duplicate_normalized_url_and_platform_id_merge_occurrences(self) -> None:
        first = self.write_index(
            "first",
            [
                {
                    "ref_id": "REF_FIRST",
                    "bvid": "BV17wLmzHEdA",
                    "url": "http://www.bilibili.com/video/BV17wLmzHEdA?utm_source=x",
                    "contact_sheet": "contact-sheets/first.jpg",
                }
            ],
        )
        (first / "contact-sheets").mkdir()
        (first / "contact-sheets/first.jpg").write_bytes(b"first-sheet")
        second = self.write_index(
            "second",
            {
                "REF_SECOND": {
                    "bvid": "BV17wLmzHEdA",
                    "url": "https://www.bilibili.com/video/BV17wLmzHEdA/",
                    "video_file": "videos/second.mp4",
                }
            },
        )
        (second / "videos").mkdir()
        (second / "videos/second.mp4").write_bytes(b"second-video")

        catalog = self.hub.build_catalog()

        self.assertEqual(1, len(catalog["sources"]))
        self.assertEqual(2, len(catalog["sources"][0]["occurrences"]))
        self.assertEqual("evidence_declared", catalog["sources"][0]["registration"]["state"])

    def test_same_media_sha_merges_distinct_platform_id_aliases(self) -> None:
        shared_hash = hashlib.sha256(b"identical-local-bytes").hexdigest()
        self.write_index(
            "sha-first",
            [
                {
                    "ref_id": "REF_A",
                    "bvid": "BV17wLmzHEdA",
                    "url": "https://www.bilibili.com/video/BV17wLmzHEdA/",
                    "sha256": shared_hash,
                    "video_file": "videos/a.mp4",
                },
                {
                    "ref_id": "REF_B",
                    "bvid": "BV1Ui4tz1ExQ",
                    "url": "https://www.bilibili.com/video/BV1Ui4tz1ExQ/",
                    "sha256": shared_hash,
                    "video_file": "videos/b.mp4",
                },
            ],
        )

        self.hub.write_catalog()
        catalog = self.hub.build_catalog()

        self.assertEqual(1, len(catalog["sources"]))
        self.assertEqual(2, len(catalog["sources"][0]["aliases"]))
        self.assertEqual([shared_hash], catalog["sources"][0]["media_sha256s"])
        self.assertEqual(1, len(self.hub.lookup("bilibili:BV1Ui4tz1ExQ")))

    def test_registered_but_missing_source_holds_and_catalog_staleness_is_detected(self) -> None:
        collection = self.write_index(
            "missing",
            [
                {
                    "ref_id": "REF_MISSING",
                    "bvid": "BV17wLmzHEdA",
                    "url": "https://www.bilibili.com/video/BV17wLmzHEdA/",
                    "video_file": "videos/missing.mp4",
                }
            ],
        )
        current, _ = self.hub.write_catalog()
        self.assertFalse(current)
        decision = self.hub.preflight(
            "https://www.bilibili.com/video/BV17wLmzHEdA/"
        )
        self.assertEqual("hold_registered_evidence_missing", decision["decision"])
        self.assertFalse(decision["workflow_eligible"])
        self.assertFalse(decision["capture_eligible"])
        index = collection / "source-index-v1.yaml"
        changed = yaml.safe_load(index.read_text(encoding="utf-8"))
        changed["sources"][0]["title"] = "Index changed after catalog build"
        index.write_text(yaml.safe_dump(changed, sort_keys=False), encoding="utf-8")

        verification = self.hub.verify()
        self.assertFalse(verification["valid"])
        self.assertIn("catalog is stale; run build", verification["issues"])

    def test_registered_partial_evidence_holds_instead_of_silent_redownload(self) -> None:
        collection = self.write_index(
            "partial",
            [
                {
                    "ref_id": "REF_PARTIAL",
                    "bvid": "BV17wLmzHEdA",
                    "url": "https://www.bilibili.com/video/BV17wLmzHEdA/",
                    "video_file": "videos/source.mp4",
                    "contact_sheet": "contact-sheets/missing.jpg",
                }
            ],
        )
        (collection / "videos").mkdir()
        (collection / "videos/source.mp4").write_bytes(b"available-video")
        self.hub.write_catalog()

        decision = self.hub.preflight(
            "https://www.bilibili.com/video/BV17wLmzHEdA/"
        )

        self.assertEqual("hold_registered_evidence_missing", decision["decision"])
        self.assertEqual("registered_partial", decision["runtime_evidence"]["state"])
        self.assertEqual(1, decision["runtime_evidence"]["missing_path_count"])
        self.assertFalse(decision["workflow_eligible"])

    def test_local_ignored_evidence_presence_does_not_change_tracked_catalog_bytes(self) -> None:
        collection = self.write_index(
            "local-presence",
            [
                {
                    "ref_id": "REF_LOCAL_PRESENCE",
                    "bvid": "BV17wLmzHEdA",
                    "url": "https://www.bilibili.com/video/BV17wLmzHEdA/",
                    "video_file": "videos/local.mp4",
                }
            ],
        )
        self.hub.write_catalog()
        before = (self.hub_root / "reference-hub-catalog.yaml").read_bytes()
        (collection / "videos").mkdir()
        (collection / "videos/local.mp4").write_bytes(b"machine-local-evidence")

        after = reference_hub.yaml_bytes(self.hub.build_catalog())
        verification = self.hub.verify()

        self.assertEqual(before, after)
        self.assertTrue(verification["valid"], verification["issues"])
        self.assertEqual([], verification["holds"])

    def test_new_direct_bilibili_source_requires_exact_current_task_binding(self) -> None:
        url = "https://www.bilibili.com/video/BV1Ui4tz1ExQ/"
        denied = self.hub.preflight(url)
        approved = self.hub.preflight(
            url,
            approval_basis="founder-task-BILI-001",
            approved_url="https://www.bilibili.com/video/BV1Ui4tz1ExQ/",
        )

        self.assertEqual(
            "hold_public_bilibili_requires_current_task_approval",
            denied["decision"],
        )
        self.assertFalse(denied["workflow_eligible"])
        self.assertFalse(denied["capture_eligible"])
        self.assertEqual("capture_new_public_bilibili_source", approved["decision"])
        self.assertTrue(approved["workflow_eligible"])
        self.assertTrue(approved["capture_eligible"])
        self.assertTrue(approved["caller_supplied_approval_binding"])
        self.assertFalse(approved["external_execution_approved"])
        self.assertTrue(approved["current_task_approval_required"])

    def test_bilibili_wrapper_has_no_default_approval_and_stops_before_network(self) -> None:
        bvid = "BV" + uuid.uuid4().hex[:10]
        env = os.environ.copy()
        for name in (
            "IDOL_REFERENCE_CAPTURE_APPROVED",
            "IDOL_REFERENCE_CAPTURE_BASIS",
            "IDOL_REFERENCE_APPROVED_URL",
        ):
            env.pop(name, None)
        completed = subprocess.run(
            [
                str(SCRIPTS_DIR / "yt-dlp-bilibili.sh"),
                f"https://www.bilibili.com/video/{bvid}/",
            ],
            cwd=SCRIPTS_DIR.parent,
            env=env,
            capture_output=True,
            text=True,
            check=False,
        )

        self.assertEqual(5, completed.returncode)
        self.assertIn("Reference capture held", completed.stderr)
        self.assertIn("IDOL_REFERENCE_APPROVED_URL", completed.stderr)

    def test_new_youtube_source_fails_closed_without_exact_approval(self) -> None:
        url = "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
        denied = self.hub.preflight(url)
        approved = self.hub.preflight(
            url,
            approval_basis="founder-task-REF-001",
            approved_url="https://youtu.be/dQw4w9WgXcQ",
        )

        self.assertEqual(
            "hold_non_bilibili_requires_exact_founder_approval", denied["decision"]
        )
        self.assertFalse(denied["capture_eligible"])
        self.assertEqual(
            "capture_new_non_bilibili_exact_approval", approved["decision"]
        )
        self.assertTrue(approved["caller_supplied_approval_binding"])
        self.assertFalse(approved["external_execution_approved"])

    def test_youtube_leading_underscore_remains_in_canonical_source_path(self) -> None:
        identity = reference_hub.normalize_identity(
            "https://www.youtube.com/shorts/_fwNImTZlMI"
        )

        self.assertEqual("_fwNImTZlMI", identity["platform_id"])
        self.assertEqual(
            "source-materials/video-sources/youtube/by-source/_fwNImTZlMI",
            reference_hub.canonical_source_root(identity),
        )

    def test_instagram_reel_and_post_identity_normalize_to_shortcode_owners(self) -> None:
        reel = reference_hub.normalize_identity(
            "https://www.instagram.com/reel/AbCdEfGhIjK/?igsh=example"
        )
        post = reference_hub.normalize_identity(
            "https://www.instagram.com/someuser/p/ZYxWvUtSrQp/"
        )

        self.assertEqual("instagram", reel["platform"])
        self.assertEqual("AbCdEfGhIjK", reel["platform_id"])
        self.assertEqual(
            "https://www.instagram.com/reel/AbCdEfGhIjK/",
            reel["normalized_url"],
        )
        self.assertEqual(
            "source-materials/video-sources/instagram/by-source/AbCdEfGhIjK",
            reference_hub.canonical_source_root(reel),
        )
        self.assertEqual("instagram", post["platform"])
        self.assertEqual("ZYxWvUtSrQp", post["platform_id"])
        self.assertEqual(
            "https://www.instagram.com/p/ZYxWvUtSrQp/",
            post["normalized_url"],
        )

    def test_new_instagram_source_fails_closed_without_exact_approval(self) -> None:
        url = "https://www.instagram.com/reel/AbCdEfGhIjK/"
        denied = self.hub.preflight(url)
        approved = self.hub.preflight(
            url,
            approval_basis="founder-task-IG-001",
            approved_url="https://www.instagram.com/reel/AbCdEfGhIjK/",
        )

        self.assertEqual(
            "hold_non_bilibili_requires_exact_founder_approval", denied["decision"]
        )
        self.assertFalse(denied["capture_eligible"])
        self.assertEqual(
            "capture_new_non_bilibili_exact_approval", approved["decision"]
        )
        self.assertTrue(approved["caller_supplied_approval_binding"])
        self.assertFalse(approved["external_execution_approved"])

    def test_lookup_accepts_plain_platform_id_as_documented(self) -> None:
        collection = self.write_index(
            "platform-id-lookup",
            [
                {
                    "ref_id": "REF_PLATFORM_ID",
                    "bvid": "BV17wLmzHEdA",
                    "url": "https://www.bilibili.com/video/BV17wLmzHEdA/",
                    "contact_sheet": "contact-sheets/overview.jpg",
                }
            ],
        )
        (collection / "contact-sheets").mkdir()
        (collection / "contact-sheets/overview.jpg").write_bytes(b"sheet")
        self.hub.write_catalog()

        self.assertEqual(1, len(self.hub.lookup("BV17wLmzHEdA")))

    def test_historical_existing_youtube_evidence_can_be_reused_without_new_permission(self) -> None:
        collection = self.write_index(
            "historical-youtube",
            [
                {
                    "source_id": "REF_HISTORICAL_YT",
                    "video_id": "dQw4w9WgXcQ",
                    "url": "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
                    "local_video": "videos/historical.mp4",
                }
            ],
            platform="youtube",
        )
        (collection / "videos").mkdir()
        (collection / "videos/historical.mp4").write_bytes(b"historical")
        self.hub.write_catalog()

        decision = self.hub.preflight(
            "https://youtu.be/dQw4w9WgXcQ"
        )

        self.assertEqual("reuse_existing", decision["decision"])
        self.assertTrue(decision["workflow_eligible"])
        self.assertFalse(decision["capture_eligible"])
        self.assertFalse(decision["external_execution_approved"])

    def test_path_traversal_in_legacy_index_fails_closed(self) -> None:
        self.write_index(
            "unsafe",
            [
                {
                    "ref_id": "REF_UNSAFE",
                    "bvid": "BV17wLmzHEdA",
                    "url": "https://www.bilibili.com/video/BV17wLmzHEdA/",
                    "video_file": "../../outside.mp4",
                }
            ],
        )

        with self.assertRaisesRegex(reference_hub.HubError, "traversal"):
            self.hub.build_catalog()

    def test_catalog_bytes_are_deterministic_and_checkable(self) -> None:
        self.write_index(
            "deterministic",
            [
                {
                    "ref_id": "REF_DETERMINISTIC",
                    "bvid": "BV17wLmzHEdA",
                    "url": "https://www.bilibili.com/video/BV17wLmzHEdA/",
                }
            ],
        )

        first = reference_hub.yaml_bytes(self.hub.build_catalog())
        second = reference_hub.yaml_bytes(self.hub.build_catalog())
        self.assertEqual(first, second)
        matched_before, _ = self.hub.write_catalog(check=True)
        self.assertFalse(matched_before)
        self.hub.write_catalog()
        matched_after, _ = self.hub.write_catalog(check=True)
        self.assertTrue(matched_after)

    def test_ingest_local_writes_manifest_frame_index_and_pointer_catalog(self) -> None:
        source_root = (
            self.hub_root / "bilibili/by-source/BV17wLmzHEdA"
        )
        media = source_root / "videos/source.mp4"
        sheet = source_root / "contact-sheets/overview.jpg"
        media.parent.mkdir(parents=True)
        sheet.parent.mkdir(parents=True)
        media.write_bytes(b"canonical-media")
        sheet.write_bytes(b"canonical-sheet")
        info_json = source_root / "videos/BV17wLmzHEdA.info.json"
        info_json.write_text(
            json.dumps({"title": "Canonical test source", "duration": 58, "view_count": 987654}),
            encoding="utf-8",
        )
        qc_manifest = self.write_qc_manifest(
            source_root / "contact-sheet-manifest.json", media, [sheet]
        )

        result = self.hub.ingest_local(
            url="https://www.bilibili.com/video/BV17wLmzHEdA/",
            media_paths=[str(media)],
            contact_sheet_paths=[str(sheet)],
            contact_sheet_manifest_path=str(qc_manifest),
            title="Canonical test source",
            approval_basis="current-test-task",
            approved_url="https://www.bilibili.com/video/BV17wLmzHEdA/",
            sampling_note="three-second overview",
            info_json_path=str(info_json),
            duration_seconds=58.0,
            view_count=987654,
            discovery_lane="shorts_reference",
        )

        self.assertEqual("registered_local", result["decision"])
        self.assertTrue((source_root / "source-manifest.yaml").is_file())
        self.assertTrue((source_root / "frame-index.yaml").is_file())
        self.assertTrue((self.hub_root / "reference-hub-catalog.yaml").is_file())
        manifest = yaml.safe_load(
            (source_root / "source-manifest.yaml").read_text(encoding="utf-8")
        )
        self.assertEqual(58.0, manifest["discovery_metadata"]["duration_seconds"])
        self.assertEqual(987654, manifest["discovery_metadata"]["raw_view_count"])
        self.assertEqual("shorts_reference", manifest["discovery_metadata"]["discovery_lane"])
        catalog = yaml.safe_load(
            (self.hub_root / "reference-hub-catalog.yaml").read_text(encoding="utf-8")
        )
        self.assertEqual(987654, catalog["sources"][0]["discovery_metadata"]["raw_view_count"])
        verification = self.hub.verify()
        self.assertTrue(verification["valid"], verification["issues"])

    def test_manifest_and_frame_index_paths_cannot_escape_canonical_source_root(self) -> None:
        source_root = self.hub_root / "bilibili/by-source/BV17wLmzHEdA"
        media = source_root / "videos/source.mp4"
        sheet = source_root / "contact-sheets/overview.jpg"
        media.parent.mkdir(parents=True)
        sheet.parent.mkdir(parents=True)
        media.write_bytes(b"canonical-media")
        sheet.write_bytes(b"canonical-sheet")
        qc_manifest = self.write_qc_manifest(
            source_root / "contact-sheet-manifest.json", media, [sheet]
        )
        self.hub.ingest_local(
            url="https://www.bilibili.com/video/BV17wLmzHEdA/",
            media_paths=[str(media)],
            contact_sheet_paths=[str(sheet)],
            contact_sheet_manifest_path=str(qc_manifest),
            approval_basis="canonical-lane-test",
            approved_url="https://www.bilibili.com/video/BV17wLmzHEdA/",
        )

        manifest = yaml.safe_load(
            (source_root / "source-manifest.yaml").read_text(encoding="utf-8")
        )
        manifest["media"][0]["path"] = "runs/2099-01-01/ESCAPED/source.mp4"
        with self.assertRaisesRegex(reference_hub.HubError, "canonical source root"):
            self.hub.validate_document(manifest, expected_type="source_manifest")

        frame_index = yaml.safe_load(
            (source_root / "frame-index.yaml").read_text(encoding="utf-8")
        )
        frame_index["source_manifest_path"] = "runs/2099-01-01/ESCAPED/source-manifest.yaml"
        with self.assertRaisesRegex(reference_hub.HubError, "canonical source root"):
            self.hub.validate_document(frame_index, expected_type="frame_index")

    def test_new_ingest_rejects_media_outside_canonical_source_lane(self) -> None:
        wrong = self.hub_root / "bilibili/random/source.mp4"
        wrong.parent.mkdir(parents=True)
        wrong.write_bytes(b"wrong-lane")

        with self.assertRaisesRegex(reference_hub.HubError, "canonical source root"):
            self.hub.ingest_local(
                url="https://www.bilibili.com/video/BV17wLmzHEdA/",
                media_paths=[str(wrong)],
                approval_basis="current-test-task",
                approved_url="https://www.bilibili.com/video/BV17wLmzHEdA/",
            )

    def test_new_ingest_requires_contact_sheet_and_hash_bound_qc_manifest(self) -> None:
        source_root = self.hub_root / "bilibili/by-source/BV17wLmzHEdA"
        video = source_root / "videos/source.mp4"
        sheet = source_root / "contact-sheets/overview.jpg"
        video.parent.mkdir(parents=True)
        sheet.parent.mkdir(parents=True)
        video.write_bytes(b"video")
        sheet.write_bytes(b"sheet")

        with self.assertRaisesRegex(reference_hub.HubError, "contact sheet"):
            self.hub.ingest_local(
                url="https://www.bilibili.com/video/BV17wLmzHEdA/",
                media_paths=[str(video)],
                approval_basis="current-test-task",
                approved_url="https://www.bilibili.com/video/BV17wLmzHEdA/",
            )
        with self.assertRaisesRegex(reference_hub.HubError, "QC contact-sheet manifest"):
            self.hub.ingest_local(
                url="https://www.bilibili.com/video/BV17wLmzHEdA/",
                media_paths=[str(video)],
                contact_sheet_paths=[str(sheet)],
                approval_basis="current-test-task",
                approved_url="https://www.bilibili.com/video/BV17wLmzHEdA/",
            )

    def test_qc_manifest_is_hash_bound_pointer_and_owns_sheet_cell_order(self) -> None:
        source_root = self.hub_root / "bilibili/by-source/BV17wLmzHEdA"
        video = source_root / "videos/source.mp4"
        sheet_one = source_root / "contact-sheets/part-one.jpg"
        sheet_two = source_root / "contact-sheets/part-two.jpg"
        video.parent.mkdir(parents=True)
        sheet_one.parent.mkdir(parents=True)
        video.write_bytes(b"qc-video")
        sheet_one.write_bytes(b"qc-sheet-one")
        sheet_two.write_bytes(b"qc-sheet-two")
        qc_manifest = self.write_qc_manifest(
            source_root / "contact-sheet-manifest.json",
            video,
            [sheet_one, sheet_two],
        )

        result = self.hub.ingest_local(
            url="https://www.bilibili.com/video/BV17wLmzHEdA/",
            media_paths=[str(video)],
            contact_sheet_paths=[str(sheet_two), str(sheet_one)],
            contact_sheet_manifest_path=str(qc_manifest),
            approval_basis="qc-manifest-test",
            approved_url="https://www.bilibili.com/video/BV17wLmzHEdA/",
        )

        frame_index = yaml.safe_load(
            (source_root / "frame-index.yaml").read_text(encoding="utf-8")
        )
        pointer = frame_index["contact_sheet_manifest"]
        self.assertEqual(
            "source-materials/video-sources/bilibili/by-source/BV17wLmzHEdA/contact-sheet-manifest.json",
            pointer["path"],
        )
        self.assertEqual(hashlib.sha256(qc_manifest.read_bytes()).hexdigest(), pointer["sha256"])
        self.assertEqual(qc_manifest.stat().st_size, pointer["byte_size"])
        self.assertEqual(
            [
                "source-materials/video-sources/bilibili/by-source/BV17wLmzHEdA/contact-sheets/part-one.jpg",
                "source-materials/video-sources/bilibili/by-source/BV17wLmzHEdA/contact-sheets/part-two.jpg",
            ],
            [item["path"] for item in frame_index["sheets"]],
        )
        self.assertNotIn("cells", json.dumps(frame_index))
        self.assertEqual(pointer, result["contact_sheet_manifest"])

    def test_qc_manifest_source_video_mismatch_fails_closed(self) -> None:
        source_root = self.hub_root / "bilibili/by-source/BV17wLmzHEdA"
        registered_video = source_root / "videos/registered.mp4"
        other_video = source_root / "videos/other.mp4"
        sheet = source_root / "contact-sheets/overview.jpg"
        registered_video.parent.mkdir(parents=True)
        sheet.parent.mkdir(parents=True)
        registered_video.write_bytes(b"registered-video")
        other_video.write_bytes(b"different-video")
        sheet.write_bytes(b"sheet")
        qc_manifest = self.write_qc_manifest(
            source_root / "contact-sheet-manifest.json", other_video, [sheet]
        )

        with self.assertRaisesRegex(reference_hub.HubError, "registered video"):
            self.hub.ingest_local(
                url="https://www.bilibili.com/video/BV17wLmzHEdA/",
                media_paths=[str(registered_video)],
                contact_sheet_paths=[str(sheet)],
                contact_sheet_manifest_path=str(qc_manifest),
                approval_basis="mismatch-test",
                approved_url="https://www.bilibili.com/video/BV17wLmzHEdA/",
            )

    def test_qc_manifest_sheet_set_mismatch_fails_closed(self) -> None:
        source_root = self.hub_root / "bilibili/by-source/BV17wLmzHEdA"
        video = source_root / "videos/source.mp4"
        manifest_sheet = source_root / "contact-sheets/manifest.jpg"
        supplied_sheet = source_root / "contact-sheets/supplied.jpg"
        video.parent.mkdir(parents=True)
        manifest_sheet.parent.mkdir(parents=True)
        video.write_bytes(b"video")
        manifest_sheet.write_bytes(b"manifest-sheet")
        supplied_sheet.write_bytes(b"supplied-sheet")
        qc_manifest = self.write_qc_manifest(
            source_root / "contact-sheet-manifest.json", video, [manifest_sheet]
        )

        with self.assertRaisesRegex(reference_hub.HubError, "does not match"):
            self.hub.ingest_local(
                url="https://www.bilibili.com/video/BV17wLmzHEdA/",
                media_paths=[str(video)],
                contact_sheet_paths=[str(supplied_sheet)],
                contact_sheet_manifest_path=str(qc_manifest),
                approval_basis="mismatch-test",
                approved_url="https://www.bilibili.com/video/BV17wLmzHEdA/",
            )

    def test_replace_contact_sheets_allows_same_path_manifest_refresh(self) -> None:
        source_root = self.hub_root / "bilibili/by-source/BV17wLmzHEdA"
        video = source_root / "videos/source.mp4"
        sheet = source_root / "contact-sheets/segments-15s/source-15s-part-001.jpg"
        video.parent.mkdir(parents=True)
        sheet.parent.mkdir(parents=True)
        video.write_bytes(b"video")
        sheet.write_bytes(b"first-sheet")
        qc_manifest = self.write_qc_manifest(
            source_root / "analysis/source-segments-15s-manifest.json", video, [sheet]
        )
        kwargs = {
            "url": "https://www.bilibili.com/video/BV17wLmzHEdA/",
            "media_paths": [str(video)],
            "contact_sheet_paths": [str(sheet)],
            "contact_sheet_manifest_path": str(qc_manifest),
            "approval_basis": "current-test-task",
            "approved_url": "https://www.bilibili.com/video/BV17wLmzHEdA/",
        }
        self.hub.ingest_local(**kwargs)

        sheet.write_bytes(b"refreshed-sheet")
        self.write_qc_manifest(qc_manifest, video, [sheet])
        result = self.hub.ingest_local(**kwargs, replace_contact_sheets=True)

        self.assertEqual("registered_local", result["decision"])
        verification = self.hub.verify()
        self.assertTrue(verification["valid"], verification["issues"])

    def test_qc_manifest_pointer_tamper_invalidates_verification(self) -> None:
        source_root = self.hub_root / "bilibili/by-source/BV17wLmzHEdA"
        video = source_root / "videos/source.mp4"
        sheet = source_root / "contact-sheets/overview.jpg"
        video.parent.mkdir(parents=True)
        sheet.parent.mkdir(parents=True)
        video.write_bytes(b"video")
        sheet.write_bytes(b"sheet")
        qc_manifest = self.write_qc_manifest(
            source_root / "contact-sheet-manifest.json", video, [sheet]
        )
        self.hub.ingest_local(
            url="https://www.bilibili.com/video/BV17wLmzHEdA/",
            media_paths=[str(video)],
            contact_sheet_paths=[str(sheet)],
            contact_sheet_manifest_path=str(qc_manifest),
            approval_basis="tamper-test",
            approved_url="https://www.bilibili.com/video/BV17wLmzHEdA/",
        )
        qc_manifest.write_text(
            qc_manifest.read_text(encoding="utf-8") + "\n", encoding="utf-8"
        )

        verification = self.hub.verify()

        self.assertFalse(verification["valid"])
        self.assertTrue(
            any("pointer is stale" in issue for issue in verification["issues"]),
            verification["issues"],
        )

    def test_historical_ingest_without_qc_manifest_remains_valid(self) -> None:
        historical_root = self.hub_root / "youtube/historical-existing"
        video = historical_root / "videos/source.mp4"
        sheet = historical_root / "contact-sheets/overview.jpg"
        video.parent.mkdir(parents=True)
        sheet.parent.mkdir(parents=True)
        video.write_bytes(b"historical-video")
        sheet.write_bytes(b"historical-sheet")

        result = self.hub.ingest_local(
            url="https://www.youtube.com/watch?v=dQw4w9WgXcQ",
            media_paths=[str(video)],
            contact_sheet_paths=[str(sheet)],
            historical_existing=True,
        )

        frame_index = yaml.safe_load(
            (self.hub_root / "youtube/by-source/dQw4w9WgXcQ/frame-index.yaml").read_text(
                encoding="utf-8"
            )
        )
        self.assertEqual("registered_historical_existing", result["decision"])
        self.assertIsNone(frame_index["contact_sheet_manifest"])
        self.assertTrue(self.hub.verify()["valid"])

    def test_replace_contact_sheets_retires_the_prior_canonical_sheet_set(self) -> None:
        source_root = self.hub_root / "bilibili/by-source/BV17wLmzHEdA"
        video = source_root / "videos/source.mp4"
        old_sheet = source_root / "contact-sheets/old-overview.jpg"
        new_sheet = source_root / "contact-sheets/segments-15s/part-001.jpg"
        video.parent.mkdir(parents=True)
        old_sheet.parent.mkdir(parents=True)
        new_sheet.parent.mkdir(parents=True)
        video.write_bytes(b"video")
        old_sheet.write_bytes(b"old-sheet")
        new_sheet.write_bytes(b"new-sheet")
        old_manifest = self.write_qc_manifest(
            source_root / "analysis/old-manifest.json", video, [old_sheet]
        )
        new_manifest = self.write_qc_manifest(
            source_root / "analysis/segments-15s-manifest.json", video, [new_sheet]
        )
        self.hub.ingest_local(
            url="https://www.bilibili.com/video/BV17wLmzHEdA/",
            media_paths=[str(video)],
            contact_sheet_paths=[str(old_sheet)],
            contact_sheet_manifest_path=str(old_manifest),
            approval_basis="initial-sheet-test",
            approved_url="https://www.bilibili.com/video/BV17wLmzHEdA/",
        )

        result = self.hub.ingest_local(
            url="https://www.bilibili.com/video/BV17wLmzHEdA/",
            media_paths=[str(video)],
            contact_sheet_paths=[str(new_sheet)],
            contact_sheet_manifest_path=str(new_manifest),
            replace_contact_sheets=True,
            approval_basis="replacement-sheet-test",
            approved_url="https://www.bilibili.com/video/BV17wLmzHEdA/",
        )

        frame_index = yaml.safe_load(
            (source_root / "frame-index.yaml").read_text(encoding="utf-8")
        )
        manifest = yaml.safe_load(
            (source_root / "source-manifest.yaml").read_text(encoding="utf-8")
        )
        new_sheet_rel = new_sheet.relative_to(self.root).as_posix()
        self.assertEqual([new_sheet_rel], [item["path"] for item in frame_index["sheets"]])
        self.assertEqual([new_sheet_rel], [item["path"] for item in manifest["contact_sheets"]])
        self.assertEqual(
            "source-materials/video-sources/bilibili/by-source/BV17wLmzHEdA/analysis/segments-15s-manifest.json",
            result["contact_sheet_manifest"]["path"],
        )
        self.assertTrue(self.hub.verify()["valid"])

    def test_policy_surfaces_keep_hub_first_ownership_without_run_local_originals(self) -> None:
        root = SCRIPTS_DIR.parent
        production_detail = (root / "wiki/production-system-detail.md").read_text(
            encoding="utf-8"
        )
        radar_detail = (
            root
            / "skills/idol-research-radar/references/research-radar-authoring-detail.md"
        ).read_text(encoding="utf-8")

        for text in (production_detail, radar_detail):
            self.assertIn("source-materials/video-sources", text)
        self.assertNotIn("rather than durable source assets", production_detail)
        self.assertNotIn(
            "New local captures belong in the run-local ignored cache",
            production_detail,
        )
        self.assertNotIn(
            "raw media is temporary observation cache only",
            radar_detail,
        )
        self.assertIn("duplicate run-local original", radar_detail)
        self.assertIn("observation provenance only", radar_detail)

    @unittest.skipIf(jsonschema is None, "jsonschema is available in scripts/idol-video-python")
    def test_one_schema_validates_catalog_manifest_and_frame_index(self) -> None:
        source_root = self.hub_root / "bilibili/by-source/BV17wLmzHEdA"
        media = source_root / "videos/source.mp4"
        sheet = source_root / "contact-sheets/overview.jpg"
        media.parent.mkdir(parents=True)
        sheet.parent.mkdir(parents=True)
        media.write_bytes(b"schema-media")
        sheet.write_bytes(b"schema-sheet")
        qc_manifest = self.write_qc_manifest(
            source_root / "contact-sheet-manifest.json", media, [sheet]
        )
        self.hub.ingest_local(
            url="https://www.bilibili.com/video/BV17wLmzHEdA/",
            media_paths=[str(media)],
            contact_sheet_paths=[str(sheet)],
            contact_sheet_manifest_path=str(qc_manifest),
            approval_basis="schema-test-task",
            approved_url="https://www.bilibili.com/video/BV17wLmzHEdA/",
        )
        schema = json.loads(
            (SCRIPTS_DIR.parent / "schemas/downloaded-reference-hub.schema.json").read_text(
                encoding="utf-8"
            )
        )
        validator = jsonschema.Draft202012Validator(schema)
        for path in (
            self.hub_root / "reference-hub-catalog.yaml",
            source_root / "source-manifest.yaml",
            source_root / "frame-index.yaml",
        ):
            document = yaml.safe_load(path.read_text(encoding="utf-8"))
            errors = list(validator.iter_errors(document))
            self.assertEqual([], errors, f"{path}: {errors}")

    def test_ordinary_lookup_does_not_scan_source_tree(self) -> None:
        calls = {"scan": 0}
        original = self.hub.scan

        def counted_scan():
            calls["scan"] += 1
            return original()

        self.hub.scan = counted_scan  # type: ignore[method-assign]
        self.hub.lookup("missing-query")
        self.assertEqual(0, calls["scan"])

    def test_ingest_updates_one_catalog_row_without_requiring_full_rebuild_first(self) -> None:
        source_root = self.hub_root / "bilibili/by-source/BV17wLmzHEdA"
        media = source_root / "videos/source.mp4"
        sheet = source_root / "contact-sheets/overview.jpg"
        media.parent.mkdir(parents=True)
        sheet.parent.mkdir(parents=True)
        media.write_bytes(b"one-row-video")
        sheet.write_bytes(b"one-row-sheet")
        qc_manifest = self.write_qc_manifest(
            source_root / "contact-sheets/overview.qc.json", media, [sheet]
        )
        before = yaml.safe_load(
            (self.hub_root / "reference-hub-catalog.yaml").read_text(encoding="utf-8")
        )
        self.assertEqual([], before["sources"])
        self.hub.ingest_local(
            url="https://www.bilibili.com/video/BV17wLmzHEdA/",
            media_paths=[str(media)],
            contact_sheet_paths=[str(sheet)],
            contact_sheet_manifest_path=str(qc_manifest),
            approval_basis="one-row-update",
            approved_url="https://www.bilibili.com/video/BV17wLmzHEdA/",
        )
        after = yaml.safe_load(
            (self.hub_root / "reference-hub-catalog.yaml").read_text(encoding="utf-8")
        )
        self.assertEqual(1, len(after["sources"]))
        self.assertEqual("bilibili:BV17wLmzHEdA", after["sources"][0]["source_key"])
        self.assertEqual(1, len(self.hub.lookup("bilibili:BV17wLmzHEdA")))


if __name__ == "__main__":
    unittest.main()
