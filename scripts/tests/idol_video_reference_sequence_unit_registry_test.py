#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import os
import tempfile
import unittest
from pathlib import Path

import yaml

import sys

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))
import idol_video_reference_sequence_unit_registry as registry  # noqa: E402
from lib.idol_artifact_integrity import (  # noqa: E402
    HashBinder,
    IntegrityCache,
    publication_lock_path,
)


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


class IdolVideoReferenceSequenceUnitRegistryTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory(prefix="idol-seq-units-", dir="/private/tmp")
        self.root = Path(self.tmp.name)
        self.source = self.root / "source-materials/video-sources/youtube/by-source/abc"
        self.analysis = self.source / "analysis"
        self.analysis.mkdir(parents=True)
        self.manifest = self.source / "source-manifest.yaml"
        self.analysis_md = self.analysis / "first-read.md"
        self.manifest.write_text("source: abc\n", encoding="utf-8")
        self.analysis_md.write_text("observation\n", encoding="utf-8")
        self.frames = []
        for index in range(1, 6):
            path = self.analysis / f"frame-{index}.png"
            path.write_bytes(f"frame-{index}".encode("utf-8"))
            self.frames.append(path)

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def unit(
        self,
        unit_id: str,
        frames: list[Path] | None = None,
        timestamps: list[float] | None = None,
        **extra: object,
    ) -> dict:
        used = frames or self.frames
        payload = {
            "source_sequence_unit_id": unit_id,
            "source_key": "youtube:abc",
            "source_manifest": {
                "path": self.manifest.relative_to(self.root).as_posix(),
                "sha256": sha256_bytes(self.manifest.read_bytes()),
            },
            "analysis_ref": {
                "path": self.analysis_md.relative_to(self.root).as_posix(),
                "sha256": sha256_bytes(self.analysis_md.read_bytes()),
            },
            "event_identity": "walk through rain",
            "source_time_range": "12-16",
            "frames": [
                {
                    "order": index,
                    "path": path.relative_to(self.root).as_posix(),
                    "sha256": sha256_bytes(path.read_bytes()),
                    "source_timestamp_seconds": (
                        timestamps[index - 1] if timestamps else 11 + index
                    ),
                }
                for index, path in enumerate(used, start=1)
            ],
            "source_flow_reading": "body advances while camera holds",
            "observed_facts": "body forward, gaze down, camera locked, mid shot, rain in depth",
            "purpose_classes": ["visible_action_or_hold"],
            "search_terms": ["rain walk"],
            "transfer_boundary": "body and rain only",
            "do_not_transfer": "source faces",
            "linked_previous_unit_id": None,
            "linked_next_unit_id": None,
            "authoring_receipt": "human-authored",
            "source_analysis_review_receipt": "cdd-source-pass",
        }
        payload.update(extra)
        return payload

    def write_batch(self, units: list[dict]) -> Path:
        path = self.analysis / "reusable-sequence-units-v1.yaml"
        document = {
            "schema_version": "idol_video_reference_sequence_unit_registry.v1",
            "artifact_type": "reusable_sequence_unit_batch",
            "source_key": "youtube:abc",
            "source_manifest": {
                "path": self.manifest.relative_to(self.root).as_posix(),
                "sha256": sha256_bytes(self.manifest.read_bytes()),
            },
            "units": units,
        }
        path.write_text(yaml.safe_dump(document, sort_keys=False), encoding="utf-8")
        return path

    def test_twelve_authored_units_all_appear_in_registry(self) -> None:
        units = []
        for index in range(12):
            frames = []
            for frame_index in range(1, 6):
                path = self.analysis / f"u{index}-f{frame_index}.png"
                path.write_bytes(f"u{index}-f{frame_index}".encode("utf-8"))
                frames.append(path)
            units.append(self.unit(f"SU_{index:02d}", frames, source_time_range=f"{index}-{index + 4}"))
        self.write_batch(units)
        built, errors = registry.build_registry(self.root)
        self.assertEqual([], errors)
        self.assertEqual(12, len(built["units"]))

    def test_duplicate_id_or_frame_signature_fails(self) -> None:
        self.write_batch([self.unit("SU_01"), self.unit("SU_01")])
        _, errors = registry.build_registry(self.root)
        self.assertTrue(any("duplicate" in item for item in errors))

    def test_linked_units_cannot_share_boundary_frames(self) -> None:
        second_frames = [self.frames[-1]] + [
            self.analysis / f"extra-{index}.png" for index in range(4)
        ]
        for path in second_frames[1:]:
            path.write_bytes(path.name.encode("utf-8"))
        self.write_batch(
            [
                self.unit("SU_01", linked_next_unit_id="SU_02"),
                self.unit("SU_02", second_frames, linked_previous_unit_id="SU_01"),
            ]
        )
        _, errors = registry.build_registry(self.root)
        self.assertTrue(any("boundary" in item for item in errors))

    def test_batch_cannot_carry_current_title_disposition(self) -> None:
        self.write_batch([self.unit("SU_01", album_key="aurora-m", disposition="applied")])
        _, errors = registry.build_registry(self.root)
        self.assertTrue(any("album_key" in item or "disposition" in item for item in errors))

    def test_same_unit_can_be_interpreted_independently_in_two_dummy_runs(self) -> None:
        self.write_batch([self.unit("SU_01")])
        built, errors = registry.build_registry(self.root)
        self.assertEqual([], errors)
        interpretations = {
            "album-a/mj01": {"function": "seed", "flow_reading": "arrival"},
            "album-b/mj07": {"function": "afterimage", "flow_reading": "withdrawal"},
        }
        self.assertNotEqual(interpretations["album-a/mj01"], interpretations["album-b/mj07"])
        self.assertEqual("SU_01", built["units"][0]["source_sequence_unit_id"])
        self.assertNotIn("disposition", built["units"][0])
        self.assertNotIn("source_flow_reading", built["units"][0])

    def extra_frames(self, prefix: str) -> list[Path]:
        frames = []
        for index in range(1, 6):
            path = self.analysis / f"{prefix}-{index}.png"
            path.write_bytes(f"{prefix}-{index}".encode("utf-8"))
            frames.append(path)
        return frames

    def write_second_batch(self, units: list[dict]) -> Path:
        other = (
            self.root
            / "source-materials/video-sources/youtube/by-source/abc-copy/analysis"
        )
        other.mkdir(parents=True)
        path = other / "reusable-sequence-units-v1.yaml"
        document = {
            "schema_version": "idol_video_reference_sequence_unit_registry.v1",
            "artifact_type": "reusable_sequence_unit_batch",
            "source_key": "youtube:abc",
            "source_manifest": {
                "path": self.manifest.relative_to(self.root).as_posix(),
                "sha256": sha256_bytes(self.manifest.read_bytes()),
            },
            "units": units,
        }
        path.write_text(yaml.safe_dump(document, sort_keys=False), encoding="utf-8")
        return path

    def test_nan_and_non_one_second_timestamps_are_hold(self) -> None:
        nan_unit = self.unit("SU_01")
        nan_unit["frames"][0]["source_timestamp_seconds"] = float("nan")
        self.write_batch([nan_unit])
        _, errors = registry.build_registry(self.root)
        self.assertTrue(any("HOLD invalid_timestamp" in item for item in errors))
        self.write_batch(
            [self.unit("SU_02", timestamps=[12.0, 13.0, 15.0, 16.0, 17.0])]
        )
        _, errors = registry.build_registry(self.root)
        self.assertTrue(any("HOLD cadence" in item for item in errors))

    def test_unit_source_manifest_must_exactly_match_batch(self) -> None:
        payload = self.unit("SU_01")
        payload["source_manifest"] = {
            "path": payload["source_manifest"]["path"],
            "sha256": "a" * 64,
        }
        self.write_batch([payload])
        _, errors = registry.build_registry(self.root)
        self.assertTrue(any("HOLD source_manifest_mismatch" in item for item in errors))

    def test_unknown_and_nonreciprocal_links_are_hold(self) -> None:
        self.write_batch([self.unit("SU_01", linked_next_unit_id="SU_MISSING")])
        _, errors = registry.build_registry(self.root)
        self.assertTrue(any("HOLD linked_next_unknown" in item for item in errors))
        self.write_batch(
            [
                self.unit("SU_01", linked_next_unit_id="SU_02"),
                self.unit("SU_02", self.extra_frames("next")),
            ]
        )
        _, errors = registry.build_registry(self.root)
        self.assertTrue(any("HOLD linked_reciprocity" in item for item in errors))

    def test_stale_or_missing_frame_and_analysis_ref_are_hold(self) -> None:
        payload = self.unit("SU_01")
        payload["frames"][0]["sha256"] = "0" * 64
        self.write_batch([payload])
        _, errors = registry.build_registry(self.root)
        self.assertTrue(any("frame sha256 is stale" in item for item in errors))
        payload = self.unit("SU_01")
        payload["frames"][0]["path"] = (
            "source-materials/video-sources/youtube/by-source/abc/analysis/missing.png"
        )
        self.write_batch([payload])
        _, errors = registry.build_registry(self.root)
        self.assertTrue(any("file is missing" in item for item in errors))
        self.write_batch([self.unit("SU_01")])
        self.analysis_md.unlink()
        _, errors = registry.build_registry(self.root)
        self.assertTrue(any("analysis_ref" in item and "missing" in item for item in errors))

    def test_duplicate_id_across_batches_and_missing_batch_hold(self) -> None:
        self.write_batch([self.unit("SU_01")])
        self.write_second_batch([self.unit("SU_01", self.extra_frames("copy"))])
        _, errors = registry.build_registry(self.root)
        self.assertTrue(any("duplicate source_sequence_unit_id" in item for item in errors))
        registry_path = self.root / registry.REGISTRY_REL
        registry_path.parent.mkdir(parents=True, exist_ok=True)
        registry_path.write_text(
            yaml.safe_dump(
                {
                    "schema_version": "idol_video_reference_sequence_unit_registry.v1",
                    "artifact_type": "sequence_unit_pointer_registry",
                    "registry_path": registry.REGISTRY_REL.as_posix(),
                    "units": [
                        {
                            "source_sequence_unit_id": "SU_KEEP",
                            "source_key": "youtube:abc",
                            "source_time_range": "12-16",
                            "purpose_classes": ["visible_action_or_hold"],
                            "batch_pointer": {
                                "path": (
                                    "source-materials/video-sources/youtube/by-source/"
                                    "missing/analysis/reusable-sequence-units-v1.yaml"
                                ),
                                "sha256": "a" * 64,
                            },
                        }
                    ],
                },
                sort_keys=False,
            ),
            encoding="utf-8",
        )
        _, errors = registry.build_registry(self.root)
        self.assertTrue(any("HOLD missing_batch" in item for item in errors))

    def test_canonical_gate_holds_mtime_preserving_frame_rewrite(self) -> None:
        self.write_batch([self.unit("SU_01")])
        hasher = HashBinder(self.root, profile="canonical_gate")
        _, errors = registry.build_registry(self.root, hasher=hasher)
        self.assertEqual([], errors)
        stat = self.frames[0].stat()
        self.frames[0].write_bytes(b"frame-X")
        os.utime(self.frames[0], ns=(stat.st_atime_ns, stat.st_mtime_ns))
        holds = hasher.verify_publication()
        self.assertTrue(any("HOLD snapshot_inconsistent" in item for item in holds))
        self.assertTrue(
            any(
                "input snapshot changed before publication" in item
                or "bytes changed since bind" in item
                for item in holds
            )
        )
        cache = IntegrityCache(self.root)
        cache.inspect(self.frames[0], "repeat_local_validation")
        self.assertFalse(hasher.report()["durable_cache_used_for_binding"])

    def test_escaped_symlink_frame_rejected_in_root_alias_allowed(self) -> None:
        outside = tempfile.TemporaryDirectory(
            prefix="idol-seq-outside-", dir="/private/tmp"
        )
        try:
            secret = Path(outside.name) / "secret.bin"
            secret.write_bytes(b"NOT-A-HUB-SECRET")
            link = self.analysis / "escaped.png"
            link.symlink_to(secret)
            payload = self.unit("SU_01")
            payload["frames"][0]["path"] = link.relative_to(self.root).as_posix()
            payload["frames"][0]["sha256"] = "0" * 64
            self.write_batch([payload])
            _, errors = registry.build_registry(self.root)
            self.assertTrue(any("inside repository" in item for item in errors))
        finally:
            outside.cleanup()
        alias = self.analysis / "alias-frame-1.png"
        alias.symlink_to(self.frames[0])
        payload = self.unit("SU_01")
        payload["frames"][0]["path"] = alias.relative_to(self.root).as_posix()
        payload["frames"][0]["sha256"] = sha256_bytes(self.frames[0].read_bytes())
        self.write_batch([payload])
        _, errors = registry.build_registry(self.root)
        self.assertEqual([], errors)

    def test_escaped_sequence_registry_symlink_is_hold(self) -> None:
        outside = tempfile.TemporaryDirectory(
            prefix="idol-seq-reg-outside-", dir="/private/tmp"
        )
        try:
            secret = Path(outside.name) / "secret-registry.yaml"
            secret.write_text("secret: 1\n", encoding="utf-8")
            dest = self.root / registry.REGISTRY_REL
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.symlink_to(secret)
            self.write_batch([self.unit("SU_01")])
            _, errors, integrity = registry.write_registry(self.root)
            self.assertTrue(any("HOLD escaped_path" in item for item in errors))
            self.assertEqual("canonical_gate", integrity["write_binding"])
            self.assertEqual("secret: 1\n", secret.read_text(encoding="utf-8"))
        finally:
            outside.cleanup()

    def test_linked_units_must_share_event_identity(self) -> None:
        self.write_batch(
            [
                self.unit("SU_01", linked_next_unit_id="SU_02"),
                self.unit(
                    "SU_02",
                    self.extra_frames("next"),
                    linked_previous_unit_id="SU_01",
                    event_identity="other event",
                ),
            ]
        )
        _, errors = registry.build_registry(self.root)
        self.assertTrue(any("HOLD event_identity" in item for item in errors))

    def test_stale_batch_source_manifest_sha256_is_rejected(self) -> None:
        self.write_batch([self.unit("SU_01")])
        self.manifest.write_text("source: changed\n", encoding="utf-8")
        _, errors = registry.build_registry(self.root)
        self.assertTrue(any("source_manifest sha256 is stale" in item for item in errors))

    def test_duplicate_frame_signature_across_batches_is_rejected(self) -> None:
        self.write_batch([self.unit("SU_01")])
        self.write_second_batch([self.unit("SU_02")])
        _, errors = registry.build_registry(self.root)
        self.assertTrue(
            any("duplicates an exact frame/time signature" in item for item in errors)
        )

    def test_canonical_memo_hits_repeated_analysis_ref_without_durable_cache_binding(self) -> None:
        self.write_batch(
            [
                self.unit("SU_01"),
                self.unit("SU_02", self.extra_frames("b")),
                self.unit("SU_03", self.extra_frames("c")),
            ]
        )
        hasher = HashBinder(self.root, profile="canonical_gate")
        _, errors = registry.build_registry(self.root, hasher=hasher)
        self.assertEqual([], errors)
        report = hasher.report()
        self.assertGreaterEqual(report["memo_hits"], 1)
        self.assertFalse(report["durable_cache_used_for_binding"])

    def test_canonical_gate_binds_fresh_frame_sha_when_repeat_cache_is_warm(self) -> None:
        self.write_batch([self.unit("SU_01")])
        cache = IntegrityCache(self.root)
        first = cache.inspect(self.frames[0], "repeat_local_validation")
        stat = self.frames[0].stat()
        self.frames[0].write_bytes(b"frame-X")
        os.utime(self.frames[0], ns=(stat.st_atime_ns, stat.st_mtime_ns))
        warm = cache.inspect(self.frames[0], "repeat_local_validation")
        self.assertEqual("hit", warm["cache"])
        self.assertEqual(first["value"], warm["value"])
        hasher = HashBinder(self.root, profile="canonical_gate")
        _, errors = registry.build_registry(self.root, hasher=hasher)
        self.assertTrue(any("frame sha256 is stale" in item for item in errors))
        self.assertFalse(hasher.report()["durable_cache_used_for_binding"])

    def test_write_registry_injected_failure_then_recovery(self) -> None:
        self.write_batch([self.unit("SU_01")])
        dest = self.root / registry.REGISTRY_REL
        dest.parent.mkdir(parents=True, exist_ok=True)
        old = yaml.safe_dump(
            {
                "schema_version": "idol_video_reference_sequence_unit_registry.v1",
                "artifact_type": "sequence_unit_pointer_registry",
                "registry_path": registry.REGISTRY_REL.as_posix(),
                "units": [],
            },
            sort_keys=False,
        )
        dest.write_text(old, encoding="utf-8")
        import lib.idol_artifact_integrity as integrity_mod
        real = integrity_mod.os.replace

        def boom(src, dst, *args, **kwargs):
            raise OSError("injected write failure")

        integrity_mod.os.replace = boom
        try:
            _, errors, _ = registry.write_registry(self.root)
        finally:
            integrity_mod.os.replace = real
        self.assertTrue(any("publication_write_failed" in item for item in errors))
        self.assertEqual(old, dest.read_text(encoding="utf-8"))
        built, errors, _ = registry.write_registry(self.root)
        self.assertEqual([], errors)
        self.assertEqual(1, len(built["units"]))
        self.assertEqual("SU_01", built["units"][0]["source_sequence_unit_id"])

    def test_write_registry_concurrent_change_is_not_overwritten(self) -> None:
        self.write_batch([self.unit("SU_01")])
        _, errors, _ = registry.write_registry(self.root)
        self.assertEqual([], errors)
        dest = self.root / registry.REGISTRY_REL
        real_publish = registry.publish_canonical_derived

        def mutate_then_publish(*, canonical, derived=None):
            dest.write_text("foreign-concurrent\n", encoding="utf-8")
            return real_publish(canonical=canonical, derived=derived)

        registry.publish_canonical_derived = mutate_then_publish
        try:
            _, errors, _ = registry.write_registry(self.root)
        finally:
            registry.publish_canonical_derived = real_publish
        self.assertTrue(any("concurrent_output_change" in item for item in errors))
        self.assertEqual("foreign-concurrent\n", dest.read_text(encoding="utf-8"))

    def test_write_registry_normal_idempotence_and_check_reader(self) -> None:
        self.write_batch([self.unit("SU_01")])
        first, errors, _ = registry.write_registry(self.root)
        self.assertEqual([], errors)
        dest = self.root / registry.REGISTRY_REL
        first_text = dest.read_text(encoding="utf-8")
        second, errors, _ = registry.write_registry(self.root)
        self.assertEqual([], errors)
        self.assertEqual(first_text, dest.read_text(encoding="utf-8"))
        self.assertEqual(first["units"], second["units"])
        check_registry, check_errors, _ = registry.write_registry(self.root, check=True)
        self.assertEqual([], check_errors)
        self.assertEqual(1, len(check_registry["units"]))
        dest.write_text(first_text.replace("SU_01", "SU_XX", 1), encoding="utf-8")
        _, stale_errors, _ = registry.write_registry(self.root, check=True)
        self.assertTrue(any("stale" in item for item in stale_errors))

    def test_check_symlink_lock_does_not_invent_stale_reason(self) -> None:
        self.write_batch([self.unit("SU_01")])
        _, errors, _ = registry.write_registry(self.root)
        self.assertEqual([], errors)
        dest = self.root / registry.REGISTRY_REL
        lock = publication_lock_path(dest)
        outside = tempfile.TemporaryDirectory()
        try:
            target = Path(outside.name) / "lock-target"
            target.write_text("x\n", encoding="utf-8")
            if lock.is_symlink() or lock.exists():
                lock.unlink()
            lock.symlink_to(target)
            _, check_errors, _ = registry.write_registry(self.root, check=True)
            self.assertTrue(
                any("HOLD escaped_path" in item for item in check_errors)
            )
            self.assertFalse(any("stale" in item for item in check_errors))
        finally:
            outside.cleanup()


if __name__ == "__main__":
    unittest.main()
