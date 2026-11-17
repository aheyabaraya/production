#!/usr/bin/env python3
from __future__ import annotations

import json
import multiprocessing
import os
import tempfile
import threading
import unittest
from pathlib import Path

from scripts.lib import idol_artifact_integrity as integrity_mod
from scripts.lib.idol_artifact_integrity import (
    HashBinder,
    IntegrityCache,
    OperationFreshSha,
    PublicationTarget,
    atomic_cas_replace,
    operation_snapshot,
    publication_lock_path,
    publish_canonical_derived,
    read_publication_snapshot,
    stat_fingerprint,
)


def _coop_publish_worker(dest, previous, content, ready, gate, result_path):
    ready.set()
    if not gate.wait(timeout=15):
        Path(result_path).write_text(
            json.dumps({"error": "gate timeout"}), encoding="utf-8"
        )
        return
    report = publish_canonical_derived(
        canonical=[
            PublicationTarget(Path(dest), content, previous, role="canonical")
        ]
    )
    Path(result_path).write_text(
        json.dumps(
            {
                "holds": report.holds,
                "committed": report.committed,
                "pending": report.pending,
                "text": Path(dest).read_text(encoding="utf-8"),
            }
        ),
        encoding="utf-8",
    )


def _coop_pair_worker(
    canonical, derived, prev_c, prev_d, new_c, new_d, ready, gate, result_path
):
    ready.set()
    if not gate.wait(timeout=15):
        Path(result_path).write_text(
            json.dumps({"error": "gate timeout"}), encoding="utf-8"
        )
        return
    report = publish_canonical_derived(
        canonical=[
            PublicationTarget(Path(canonical), new_c, prev_c, role="canonical")
        ],
        derived=[
            PublicationTarget(Path(derived), new_d, prev_d, role="derived")
        ],
    )
    Path(result_path).write_text(
        json.dumps(
            {
                "holds": report.holds,
                "committed": report.committed,
                "pending": report.pending,
                "canonical": Path(canonical).read_text(encoding="utf-8"),
                "derived": Path(derived).read_text(encoding="utf-8"),
            }
        ),
        encoding="utf-8",
    )


class IdolArtifactIntegrityTest(unittest.TestCase):
    def test_repeat_validation_reuses_sha_but_gate_forces_recompute(self) -> None:
        with tempfile.TemporaryDirectory(prefix="idol-integrity-") as tmp:
            root = Path(tmp)
            artifact = root / "artifact.bin"
            artifact.write_bytes(b"same bytes")
            cache = IntegrityCache(root)

            first = cache.inspect(artifact, "repeat_local_validation")
            second = cache.inspect(artifact, "repeat_local_validation")
            gate = cache.inspect(artifact, "canonical_gate")

            self.assertEqual("miss", first["cache"])
            self.assertEqual("hit", second["cache"])
            self.assertEqual("forced", gate["cache"])
            self.assertEqual(first["value"], second["value"])
            self.assertEqual(first["value"], gate["value"])

    def test_working_media_uses_stat_fingerprint_and_ephemeral_uses_none(self) -> None:
        with tempfile.TemporaryDirectory(prefix="idol-integrity-") as tmp:
            root = Path(tmp)
            artifact = root / "preview.bin"
            artifact.write_bytes(b"preview")
            cache = IntegrityCache(root)

            working = cache.inspect(artifact, "working_derived_media")
            ephemeral = cache.inspect(artifact, "ephemeral")

            self.assertEqual("stat-v1", working["algorithm"])
            self.assertTrue(str(working["value"]).startswith("stat-v1:"))
            self.assertEqual("none", ephemeral["algorithm"])
            self.assertIsNone(ephemeral["value"])
            self.assertNotIn("ctime_ns", working)

    def test_stat_v1_fingerprint_does_not_include_ctime(self) -> None:
        with tempfile.TemporaryDirectory(prefix="idol-integrity-statv1-") as tmp:
            artifact = Path(tmp) / "artifact.bin"
            artifact.write_bytes(b"bytes")
            fingerprint = stat_fingerprint(artifact)
            snapshot = operation_snapshot(artifact)
            self.assertEqual("stat-v1", fingerprint["algorithm"])
            self.assertNotIn("ctime_ns", fingerprint)
            self.assertIn("ctime_ns", snapshot)

    def test_publication_rehash_holds_after_mtime_preserving_rewrite(self) -> None:
        with tempfile.TemporaryDirectory(prefix="idol-integrity-pub-") as tmp:
            artifact = Path(tmp) / "artifact.bin"
            artifact.write_bytes(b"same bytes")
            memo = OperationFreshSha()
            bound = memo.sha256(artifact)
            self.assertEqual([], memo.holds)
            stat = artifact.stat()
            artifact.write_bytes(b"SAME BYTES")
            os.utime(artifact, ns=(stat.st_atime_ns, stat.st_mtime_ns))
            holds = memo.verify_publication()
            self.assertTrue(any("HOLD snapshot_inconsistent" in item for item in holds))
            self.assertTrue(
                any(
                    "input snapshot changed before publication" in item
                    or "bytes changed since bind" in item
                    for item in holds
                )
            )
            self.assertNotEqual(bound, __import__("hashlib").sha256(b"SAME BYTES").hexdigest())

    def test_second_lookup_holds_mixed_generation_after_ctime_changing_rewrite(self) -> None:
        with tempfile.TemporaryDirectory(prefix="idol-integrity-mix-") as tmp:
            artifact = Path(tmp) / "artifact.bin"
            artifact.write_bytes(b"same bytes")
            memo = OperationFreshSha()
            first = memo.sha256(artifact)
            stat = artifact.stat()
            artifact.write_bytes(b"SAME BYTES")
            os.utime(artifact, ns=(stat.st_atime_ns, stat.st_mtime_ns))
            second = memo.sha256(artifact)
            self.assertEqual(first, second)
            self.assertTrue(
                any("refuse mixed-generation binding" in item for item in memo.holds)
            )
            self.assertTrue(any("snapshot_inconsistent" in item for item in memo.verify_publication()))

    def test_canonical_binder_does_not_use_warm_repeat_cache_for_binding(self) -> None:
        with tempfile.TemporaryDirectory(prefix="idol-integrity-gate-") as tmp:
            root = Path(tmp)
            artifact = root / "artifact.bin"
            artifact.write_bytes(b"same bytes")
            cache = IntegrityCache(root)
            first = cache.inspect(artifact, "repeat_local_validation")
            stat = artifact.stat()
            artifact.write_bytes(b"SAME BYTES")
            os.utime(artifact, ns=(stat.st_atime_ns, stat.st_mtime_ns))
            warm = cache.inspect(artifact, "repeat_local_validation")
            self.assertEqual("hit", warm["cache"])
            self.assertEqual(first["value"], warm["value"])
            binder = HashBinder(root, profile="canonical_gate")
            bound = binder.sha256(artifact)
            self.assertNotEqual(bound, warm["value"])
            self.assertFalse(binder.report()["durable_cache_used_for_binding"])
            self.assertEqual("canonical_gate", binder.report()["write_binding"])

    def test_atomic_cas_replace_holds_when_output_changed(self) -> None:
        with tempfile.TemporaryDirectory(prefix="idol-integrity-cas-") as tmp:
            path = Path(tmp) / "out.yaml"
            path.write_text("old\n", encoding="utf-8")
            hold = atomic_cas_replace(path, "new\n", previous="stale-expected\n")
            self.assertIsNotNone(hold)
            self.assertIn("concurrent_output_change", str(hold))
            self.assertEqual("old\n", path.read_text(encoding="utf-8"))
            ok = atomic_cas_replace(path, "new\n", previous="old\n")
            self.assertIsNone(ok)
            self.assertEqual("new\n", path.read_text(encoding="utf-8"))

    def test_atomic_cas_replace_is_idempotent_when_current_already_intended(self) -> None:
        with tempfile.TemporaryDirectory(prefix="idol-integrity-cas-idemp-") as tmp:
            path = Path(tmp) / "out.yaml"
            path.write_text("new\n", encoding="utf-8")
            hold = atomic_cas_replace(path, "new\n", previous="old\n")
            self.assertIsNone(hold)
            self.assertEqual("new\n", path.read_text(encoding="utf-8"))

    def test_caught_second_write_failure_commits_canonical_and_unlinks_temp(self) -> None:
        with tempfile.TemporaryDirectory(prefix="idol-integrity-pair-fail-") as tmp:
            canonical = Path(tmp) / "registry.yaml"
            derived = Path(tmp) / "READ-FIRST.md"
            canonical.write_text("old-reg\n", encoding="utf-8")
            derived.write_text("old-doc\n", encoding="utf-8")
            real = integrity_mod.os.replace
            count = {"n": 0}

            def flaky(src, dst, *args, **kwargs):
                count["n"] += 1
                if count["n"] >= 2:
                    raise OSError("injected second write failure")
                return real(src, dst, *args, **kwargs)

            integrity_mod.os.replace = flaky
            try:
                report = publish_canonical_derived(
                    canonical=[
                        PublicationTarget(
                            canonical, "new-reg\n", "old-reg\n", role="canonical"
                        )
                    ],
                    derived=[
                        PublicationTarget(
                            derived, "new-doc\n", "old-doc\n", role="derived"
                        )
                    ],
                )
            finally:
                integrity_mod.os.replace = real
            self.assertTrue(
                any("publication_write_failed" in item for item in report.holds)
            )
            self.assertTrue(
                any("derived_publication_incomplete" in item for item in report.holds)
            )
            self.assertEqual([str(canonical)], report.committed)
            self.assertEqual([str(derived)], report.pending)
            self.assertEqual("new-reg\n", canonical.read_text(encoding="utf-8"))
            self.assertEqual("old-doc\n", derived.read_text(encoding="utf-8"))
            leftovers = list(Path(tmp).glob(".READ-FIRST.md.*.tmp"))
            self.assertEqual([], leftovers)
            recovered = publish_canonical_derived(
                canonical=[
                    PublicationTarget(
                        canonical, "new-reg\n", "old-reg\n", role="canonical"
                    )
                ],
                derived=[
                    PublicationTarget(
                        derived, "new-doc\n", "old-doc\n", role="derived"
                    )
                ],
            )
            self.assertEqual([], recovered.holds)
            self.assertEqual("new-reg\n", canonical.read_text(encoding="utf-8"))
            self.assertEqual("new-doc\n", derived.read_text(encoding="utf-8"))

    def test_recovery_refuses_foreign_canonical_and_preserves_it(self) -> None:
        with tempfile.TemporaryDirectory(prefix="idol-integrity-foreign-") as tmp:
            canonical = Path(tmp) / "registry.yaml"
            derived = Path(tmp) / "READ-FIRST.md"
            canonical.write_text("foreign-canonical\n", encoding="utf-8")
            derived.write_text("old-doc\n", encoding="utf-8")
            report = publish_canonical_derived(
                canonical=[
                    PublicationTarget(
                        canonical, "new-reg\n", "old-reg\n", role="canonical"
                    )
                ],
                derived=[
                    PublicationTarget(
                        derived, "new-doc\n", "old-doc\n", role="derived"
                    )
                ],
            )
            self.assertTrue(
                any("concurrent_output_change" in item for item in report.holds)
            )
            self.assertEqual(
                "foreign-canonical\n", canonical.read_text(encoding="utf-8")
            )
            self.assertEqual("old-doc\n", derived.read_text(encoding="utf-8"))
            self.assertEqual([], report.committed)
            self.assertIn(str(canonical), report.pending)
            self.assertIn(str(derived), report.pending)

    def test_recheck_canonical_before_derived_preserves_foreign_canonical(self) -> None:
        with tempfile.TemporaryDirectory(prefix="idol-integrity-recheck-") as tmp:
            canonical = Path(tmp) / "registry.yaml"
            derived = Path(tmp) / "READ-FIRST.md"
            canonical.write_text("old-reg\n", encoding="utf-8")
            derived.write_text("old-doc\n", encoding="utf-8")
            real = integrity_mod.os.replace

            def sneaky(src, dst, *args, **kwargs):
                real(src, dst, *args, **kwargs)
                if Path(dst) == canonical:
                    canonical.write_text("foreign-canonical\n", encoding="utf-8")

            integrity_mod.os.replace = sneaky
            try:
                report = publish_canonical_derived(
                    canonical=[
                        PublicationTarget(
                            canonical, "new-reg\n", "old-reg\n", role="canonical"
                        )
                    ],
                    derived=[
                        PublicationTarget(
                            derived, "new-doc\n", "old-doc\n", role="derived"
                        )
                    ],
                )
            finally:
                integrity_mod.os.replace = real
            self.assertTrue(
                any(
                    "canonical changed before derived publication" in item
                    for item in report.holds
                )
            )
            self.assertEqual(
                "foreign-canonical\n", canonical.read_text(encoding="utf-8")
            )
            self.assertEqual("old-doc\n", derived.read_text(encoding="utf-8"))
            self.assertIn(str(derived), report.pending)

    def test_reader_snapshot_detects_stale_derived_and_ignores_tmp(self) -> None:
        with tempfile.TemporaryDirectory(prefix="idol-integrity-reader-") as tmp:
            canonical = Path(tmp) / "registry.yaml"
            derived = Path(tmp) / "READ-FIRST.md"
            canonical.write_text("new-reg\n", encoding="utf-8")
            derived.write_text("old-doc\n", encoding="utf-8")
            leftover = Path(tmp) / ".registry.yaml.dead.tmp"
            leftover.write_text("not-published\n", encoding="utf-8")
            snapshot, holds = read_publication_snapshot([canonical, derived])
            self.assertEqual([], holds)
            self.assertEqual("new-reg\n", snapshot[str(canonical)])
            self.assertEqual("old-doc\n", snapshot[str(derived)])
            self.assertNotEqual("not-published\n", snapshot[str(canonical)])
            self.assertNotEqual("new-doc\n", snapshot[str(derived)])

    def test_publish_pair_normal_idempotence(self) -> None:
        with tempfile.TemporaryDirectory(prefix="idol-integrity-pair-idemp-") as tmp:
            canonical = Path(tmp) / "registry.yaml"
            derived = Path(tmp) / "READ-FIRST.md"
            first = publish_canonical_derived(
                canonical=[
                    PublicationTarget(canonical, "reg\n", None, role="canonical")
                ],
                derived=[
                    PublicationTarget(derived, "doc\n", None, role="derived")
                ],
            )
            self.assertEqual([], first.holds)
            again = publish_canonical_derived(
                canonical=[
                    PublicationTarget(canonical, "reg\n", "reg\n", role="canonical")
                ],
                derived=[
                    PublicationTarget(derived, "doc\n", "doc\n", role="derived")
                ],
            )
            self.assertEqual([], again.holds)
            self.assertEqual("reg\n", canonical.read_text(encoding="utf-8"))
            self.assertEqual("doc\n", derived.read_text(encoding="utf-8"))

    def test_two_cooperating_processes_one_holds_without_overwrite(self) -> None:
        with tempfile.TemporaryDirectory(prefix="idol-integrity-2p-") as tmp:
            dest = Path(tmp) / "registry.yaml"
            dest.write_text("old\n", encoding="utf-8")
            ctx = multiprocessing.get_context("spawn")
            ready_a = ctx.Event()
            ready_b = ctx.Event()
            gate = ctx.Event()
            result_a = Path(tmp) / "a.json"
            result_b = Path(tmp) / "b.json"
            proc_a = ctx.Process(
                target=_coop_publish_worker,
                args=(str(dest), "old\n", "aaa\n", ready_a, gate, str(result_a)),
            )
            proc_b = ctx.Process(
                target=_coop_publish_worker,
                args=(str(dest), "old\n", "bbb\n", ready_b, gate, str(result_b)),
            )
            proc_a.start()
            proc_b.start()
            self.assertTrue(ready_a.wait(15))
            self.assertTrue(ready_b.wait(15))
            gate.set()
            proc_a.join(15)
            proc_b.join(15)
            self.assertEqual(0, proc_a.exitcode)
            self.assertEqual(0, proc_b.exitcode)
            payload_a = json.loads(result_a.read_text(encoding="utf-8"))
            payload_b = json.loads(result_b.read_text(encoding="utf-8"))
            final = dest.read_text(encoding="utf-8")
            self.assertIn(final, ("aaa\n", "bbb\n"))
            rows = [payload_a, payload_b]
            successes = [row for row in rows if row.get("holds") == []]
            held = [row for row in rows if row.get("holds")]
            self.assertEqual(1, len(successes))
            self.assertEqual(1, len(held))
            self.assertTrue(
                any("concurrent_output_change" in item for item in held[0]["holds"])
            )
            self.assertEqual(final, successes[0]["text"])

    def test_two_cooperating_processes_pair_stays_same_writer(self) -> None:
        with tempfile.TemporaryDirectory(prefix="idol-integrity-2p-pair-") as tmp:
            canonical = Path(tmp) / "registry.yaml"
            derived = Path(tmp) / "READ-FIRST.md"
            canonical.write_text("old-reg\n", encoding="utf-8")
            derived.write_text("old-doc\n", encoding="utf-8")
            ctx = multiprocessing.get_context("spawn")
            ready_a = ctx.Event()
            ready_b = ctx.Event()
            gate = ctx.Event()
            result_a = Path(tmp) / "a.json"
            result_b = Path(tmp) / "b.json"
            proc_a = ctx.Process(
                target=_coop_pair_worker,
                args=(
                    str(canonical),
                    str(derived),
                    "old-reg\n",
                    "old-doc\n",
                    "A-reg\n",
                    "A-doc\n",
                    ready_a,
                    gate,
                    str(result_a),
                ),
            )
            proc_b = ctx.Process(
                target=_coop_pair_worker,
                args=(
                    str(canonical),
                    str(derived),
                    "old-reg\n",
                    "old-doc\n",
                    "B-reg\n",
                    "B-doc\n",
                    ready_b,
                    gate,
                    str(result_b),
                ),
            )
            proc_a.start()
            proc_b.start()
            self.assertTrue(ready_a.wait(15))
            self.assertTrue(ready_b.wait(15))
            gate.set()
            proc_a.join(15)
            proc_b.join(15)
            self.assertEqual(0, proc_a.exitcode)
            self.assertEqual(0, proc_b.exitcode)
            pair = (
                canonical.read_text(encoding="utf-8"),
                derived.read_text(encoding="utf-8"),
            )
            self.assertIn(pair, (("A-reg\n", "A-doc\n"), ("B-reg\n", "B-doc\n")))
            payload_a = json.loads(result_a.read_text(encoding="utf-8"))
            payload_b = json.loads(result_b.read_text(encoding="utf-8"))
            successes = [
                row for row in (payload_a, payload_b) if row.get("holds") == []
            ]
            self.assertEqual(1, len(successes))

    def test_snapshot_symlink_lock_hold_skips_empty_content_compare(self) -> None:
        with tempfile.TemporaryDirectory(prefix="idol-integrity-symlock-") as tmp:
            dest = Path(tmp) / "registry.yaml"
            dest.write_text("ok\n", encoding="utf-8")
            lock = publication_lock_path(dest)
            outside = tempfile.TemporaryDirectory()
            try:
                target = Path(outside.name) / "lock-target"
                target.write_text("x\n", encoding="utf-8")
                lock.symlink_to(target)
                snapshot, holds = read_publication_snapshot([dest])
                self.assertTrue(any("HOLD escaped_path" in item for item in holds))
                self.assertEqual({}, snapshot)
                self.assertFalse(any("stale" in item for item in holds))
                self.assertFalse(
                    any("changed during verify" in item for item in holds)
                )
            finally:
                outside.cleanup()

    def test_pending_lists_every_unwritten_derived_after_first_failure(self) -> None:
        with tempfile.TemporaryDirectory(prefix="idol-integrity-pending-") as tmp:
            canonical = Path(tmp) / "registry.yaml"
            derived_a = Path(tmp) / "a.md"
            derived_b = Path(tmp) / "b.md"
            canonical.write_text("old-reg\n", encoding="utf-8")
            derived_a.write_text("old-a\n", encoding="utf-8")
            derived_b.write_text("old-b\n", encoding="utf-8")
            real = integrity_mod.os.replace
            count = {"n": 0}

            def flaky(src, dst, *args, **kwargs):
                count["n"] += 1
                if count["n"] >= 2:
                    raise OSError("injected first derived failure")
                return real(src, dst, *args, **kwargs)

            integrity_mod.os.replace = flaky
            try:
                report = publish_canonical_derived(
                    canonical=[
                        PublicationTarget(
                            canonical, "new-reg\n", "old-reg\n", role="canonical"
                        )
                    ],
                    derived=[
                        PublicationTarget(
                            derived_a, "new-a\n", "old-a\n", role="derived"
                        ),
                        PublicationTarget(
                            derived_b, "new-b\n", "old-b\n", role="derived"
                        ),
                    ],
                )
            finally:
                integrity_mod.os.replace = real
            self.assertTrue(
                any("derived_publication_incomplete" in item for item in report.holds)
            )
            self.assertEqual([str(canonical)], report.committed)
            self.assertEqual([str(derived_a), str(derived_b)], report.pending)
            self.assertEqual("new-reg\n", canonical.read_text(encoding="utf-8"))
            self.assertEqual("old-a\n", derived_a.read_text(encoding="utf-8"))
            self.assertEqual("old-b\n", derived_b.read_text(encoding="utf-8"))

    def test_pending_excludes_later_derived_already_equal_to_intended(self) -> None:
        with tempfile.TemporaryDirectory(prefix="idol-integrity-pending-present-") as tmp:
            canonical = Path(tmp) / "registry.yaml"
            derived_a = Path(tmp) / "a.md"
            derived_b = Path(tmp) / "b.md"
            canonical.write_text("old-reg\n", encoding="utf-8")
            derived_a.write_text("old-a\n", encoding="utf-8")
            derived_b.write_text("new-b\n", encoding="utf-8")
            real = integrity_mod.os.replace
            count = {"n": 0}

            def flaky(src, dst, *args, **kwargs):
                count["n"] += 1
                if count["n"] >= 2:
                    raise OSError("injected first derived failure")
                return real(src, dst, *args, **kwargs)

            integrity_mod.os.replace = flaky
            try:
                report = publish_canonical_derived(
                    canonical=[
                        PublicationTarget(
                            canonical, "new-reg\n", "old-reg\n", role="canonical"
                        )
                    ],
                    derived=[
                        PublicationTarget(
                            derived_a, "new-a\n", "old-a\n", role="derived"
                        ),
                        PublicationTarget(
                            derived_b, "new-b\n", "old-b\n", role="derived"
                        ),
                    ],
                )
            finally:
                integrity_mod.os.replace = real
            self.assertTrue(
                any("derived_publication_incomplete" in item for item in report.holds)
            )
            self.assertEqual([str(canonical)], report.committed)
            self.assertEqual([str(derived_a)], report.pending)
            self.assertIn(str(derived_b), report.already_present)
            self.assertNotIn(str(derived_b), report.pending)
            self.assertEqual("new-reg\n", canonical.read_text(encoding="utf-8"))
            self.assertEqual("old-a\n", derived_a.read_text(encoding="utf-8"))
            self.assertEqual("new-b\n", derived_b.read_text(encoding="utf-8"))

    def test_two_threads_overlapping_publish_separate_flock_fds(self) -> None:
        with tempfile.TemporaryDirectory(prefix="idol-integrity-2t-") as tmp:
            dest = Path(tmp) / "registry.yaml"
            dest.write_text("old\n", encoding="utf-8")
            barrier = threading.Barrier(2, timeout=10)
            results: list[dict[str, object]] = []

            def worker(content: str) -> None:
                barrier.wait()
                report = publish_canonical_derived(
                    canonical=[
                        PublicationTarget(dest, content, "old\n", role="canonical")
                    ]
                )
                results.append(
                    {"holds": list(report.holds), "content": content}
                )

            first = threading.Thread(target=worker, args=("aaa\n",))
            second = threading.Thread(target=worker, args=("bbb\n",))
            first.start()
            second.start()
            first.join(15)
            second.join(15)
            self.assertFalse(first.is_alive())
            self.assertFalse(second.is_alive())
            final = dest.read_text(encoding="utf-8")
            self.assertIn(final, ("aaa\n", "bbb\n"))
            self.assertEqual(2, len(results))
            successes = [row for row in results if row["holds"] == []]
            held = [row for row in results if row["holds"]]
            self.assertEqual(
                1,
                len(successes),
                msg=f"same-process thread flock result={results!r} final={final!r}",
            )
            self.assertEqual(1, len(held))
            self.assertTrue(
                any(
                    "concurrent_output_change" in str(item)
                    for item in held[0]["holds"]
                )
            )
            self.assertEqual(final, successes[0]["content"])


if __name__ == "__main__":
    unittest.main()
