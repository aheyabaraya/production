#!/usr/bin/env python3
"""Drive shipped 04/05 validators against the live KDA 20260916 restart artifacts."""

from __future__ import annotations

import hashlib
import json
import re
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
RUN = ROOT / "runs/aurora-m/loom-rift-prestige/20260811_LOOM_MAIN_SEAT_FOUR"
VIDEO_PYTHON = ROOT / "scripts/idol-video-python"
EDIT_MAP = RUN / "04-edit-map.yaml"
PACKAGE = RUN / "05-package.yaml"
DELIVERY = RUN / "package/final-delivery/manifest.yaml"
PACK = RUN / "work/role-context-packs/PACK-KDA-CDD-RESTART-20260916.json"
DISPATCH = RUN / "work/department-dispatches/DISP-KDA-CDD-RESTART-20260916.yaml"


class Kda20260916RestartDeliveryContractTest(unittest.TestCase):
    def _run(self, command: list[str]) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            command,
            cwd=ROOT,
            text=True,
            capture_output=True,
            check=False,
        )

    def test_closeout_validator_holds_after_playback_hold_rewrite(self) -> None:
        result = self._run(
            [
                "ruby",
                str(ROOT / "scripts/validate_edit_map_readiness.rb"),
                "--mode",
                "closeout",
                str(EDIT_MAP),
            ]
        )
        combined = result.stderr + result.stdout
        self.assertNotEqual(result.returncode, 0, combined)
        self.assertIn("stale", combined.lower())

    def test_restored_run_manifest_matches_dual_restart_inventory(self) -> None:
        live = hashlib.sha256((RUN / "run-manifest.yaml").read_bytes()).hexdigest()
        self.assertEqual(
            live,
            "642846fe3ca001f479660bd835d8189325959667bf4dee9386412b1f5cb04d2e",
        )
        text = (RUN / "run-manifest.yaml").read_text(encoding="utf-8")
        self.assertNotIn("artifact_revision_owner:", text)
        self.assertNotIn("compatibility_authoring:", text)
        sidecar = RUN / "work/overall/20260916-restart/run-layout-sidecar.yaml"
        sidecar_text = sidecar.read_text(encoding="utf-8")
        self.assertIn("artifact_revision_owner: git", sidecar_text)
        self.assertIn("compatibility_authoring: forbidden", sidecar_text)

    def test_package_readiness_validator_holds_on_restored_run_manifest(self) -> None:
        result = self._run(
            [str(VIDEO_PYTHON), str(ROOT / "scripts/validate_package_readiness.py"), str(PACKAGE)]
        )
        combined = result.stderr + result.stdout
        self.assertNotEqual(result.returncode, 0, combined)
        self.assertIn("artifact_revision_owner", combined)

    def test_final_delivery_validator_holds_on_restored_run_manifest(self) -> None:
        result = self._run(
            [
                str(VIDEO_PYTHON),
                str(ROOT / "scripts/validate_final_delivery_manifest.py"),
                str(DELIVERY),
            ]
        )
        combined = result.stderr + result.stdout
        self.assertNotEqual(result.returncode, 0, combined)
        self.assertIn("artifact_revision_owner", combined)

    def test_role_context_pack_validator_accepts_admitted_pack(self) -> None:
        result = self._run(
            ["ruby", str(ROOT / "scripts/idol_role_context_pack.rb"), "validate", str(PACK)]
        )
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertIn('"status": "pass"', result.stdout)

    def test_department_dispatch_validator_accepts_admitted_dispatch(self) -> None:
        result = self._run(
            ["ruby", str(ROOT / "scripts/validate_department_dispatch.rb"), str(DISPATCH)]
        )
        combined = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, combined)
        self.assertTrue(
            "valid" in combined.lower() or "ok" in combined.lower() or result.returncode == 0
        )
        text = DISPATCH.read_text(encoding="utf-8")
        self.assertRegex(text, r"(?m)^  session_id: 01a0ab1f-6dd8-7113-820b-4dcf59cfeabf$")
        self.assertNotIn("session_id: kda-cdd-restart-20260916", text)
        self.assertIn("fff44368-72e8-4803-a730-0674c7a0f7a7", text)

    def test_restart_x5_closeout_binds_live_cards_without_august13_promotion(self) -> None:
        closeout = (
            RUN / "work/member-visual-identity/20260916-restart/x5-package/identity-closeout.yaml"
        ).read_text(encoding="utf-8")
        self.assertIn("missing_x5: closed_by_restart_x5_package", closeout)
        self.assertIn("august_13_experiment_cards: unbound", closeout)
        self.assertIn("promoted_to_album_assets: false", closeout)
        self.assertIn("founder_pass: false", closeout)
        cards = RUN / "work/member-visual-identity/20260916-restart/x5-package/cards"
        for member in ("M03", "M07", "M08", "M11", "M12"):
            path = cards / f"{member}_three-panel-card.jpg"
            digest = hashlib.sha256(path.read_bytes()).hexdigest()
            self.assertIn(digest, closeout, member)
        experiment = RUN / "generations/mvi-grok-cli-experiment-v1/README.md"
        self.assertIn(hashlib.sha256(experiment.read_bytes()).hexdigest(), closeout)
        manifest = (RUN / "run-manifest.yaml").read_text(encoding="utf-8")
        self.assertIn("member_visual_cards_status: missing_x5", manifest)
        live = hashlib.sha256((RUN / "run-manifest.yaml").read_bytes()).hexdigest()
        self.assertEqual(
            live,
            "642846fe3ca001f479660bd835d8189325959667bf4dee9386412b1f5cb04d2e",
        )

    def test_dual_restart_inventory_binds_live_kda_run_manifest(self) -> None:
        inventory = json.loads(
            (ROOT / "handoff/llm/dual-mv-restart-20260916/source-inventory.json").read_text(
                encoding="utf-8"
            )
        )
        rows = [
            row
            for row in inventory["sources"]
            if row.get("title") == "KDA"
            and str(row.get("path", "")).endswith("20260811_LOOM_MAIN_SEAT_FOUR/run-manifest.yaml")
        ]
        self.assertEqual(len(rows), 1, rows)
        live = hashlib.sha256((RUN / "run-manifest.yaml").read_bytes()).hexdigest()
        self.assertEqual(live, rows[0]["sha256"])

    def test_playback_review_record_is_director_hold_not_script_pass(self) -> None:
        text = (
            RUN / "work/reviews/20260916-restart/03v-playback-review-record.yaml"
        ).read_text(encoding="utf-8")
        self.assertRegex(text, r"(?m)^decision: hold$")
        self.assertRegex(text, r"(?m)^  can_patch_generation_playback_probe: false$")
        self.assertNotIn("pass_recorded", text)
        self.assertIn("packet_id: R06", text)
        self.assertIn("packet_id: R15", text)
        self.assertGreaterEqual(text.count("review_status_after_record: hold_recorded"), 15)
        live_master = hashlib.sha256(
            (RUN / "generations/video/master/final-master-v1.mp4").read_bytes()
        ).hexdigest()
        self.assertIn(live_master, text)
        self.assertNotIn("f9c60fab", text)

    def test_04_playback_review_names_live_master_not_stale_v2(self) -> None:
        review = (RUN / "work/reviews/20260916-restart/04-playback-review.md").read_text(
            encoding="utf-8"
        )
        live_master = hashlib.sha256(
            (RUN / "generations/video/master/final-master-v1.mp4").read_bytes()
        ).hexdigest()
        self.assertIn(live_master, review)
        self.assertIn("3395", review)
        self.assertNotIn("f9c60fab", review)
        self.assertNotIn("3393", review)
        self.assertIn("hold", review.lower())
        self.assertIn("1280x720", review)
        self.assertIn("no pillarbox", review.lower())
        worklist = (RUN / "work/reviews/20260916-restart/03v-worklist.md").read_bytes()
        intake = (RUN / "work/reviews/20260916-restart/03v-intake.md").read_bytes()
        qa = (RUN / "work/reviews/20260916-restart/03v-section-qa.md").read_bytes()
        yaml_text = (
            RUN / "work/reviews/20260916-restart/03v-playback-review-record.yaml"
        ).read_text(encoding="utf-8")
        self.assertIn(hashlib.sha256(worklist).hexdigest(), yaml_text)
        self.assertIn(hashlib.sha256(intake).hexdigest(), yaml_text)
        self.assertIn(hashlib.sha256(qa).hexdigest(), yaml_text)

    def test_02b_pixel_review_binds_live_still_sha256(self) -> None:
        review = (RUN / "work/reviews/20260916-restart/02b-pixel-review.md").read_text(
            encoding="utf-8"
        )
        self.assertNotIn("computed at bind", review)
        stills = sorted((RUN / "work/02b/20260916-restart").glob("*.jpg"))
        self.assertEqual(len(stills), 15)
        for still in stills:
            digest = hashlib.sha256(still.read_bytes()).hexdigest()
            self.assertIn(digest, review)

    def test_independent_spawn_subagent_audits_exist_for_each_stage(self) -> None:
        audits = RUN / "work/reviews/20260916-restart/independent-audits"
        pointer = (RUN / "work/reviews/20260916-restart/independent-stage-audits.md").read_text(
            encoding="utf-8"
        )
        self.assertIn("this file is **not** an independent review", pointer.lower())
        sha_re = re.compile(r"[a-f0-9]{64}")
        for stage in ("FP", "IDENTITY", "01", "02A", "02B", "03V", "04", "05"):
            path = audits / f"AUDIT-{stage}.md"
            self.assertTrue(path.is_file(), path)
            text = path.read_text(encoding="utf-8")
            self.assertIn("independent_grok_spawn_subagent", text)
            self.assertRegex(text, sha_re)
            lowered = text.lower()
            self.assertTrue("next consumer" in lowered or "next_consumer" in lowered, stage)
            self.assertTrue(
                "correction owner" in lowered or "correction_owner" in lowered, stage
            )
            self.assertIn("hold", lowered)

    def test_independent_audits_bind_live_01_cores_and_04_master(self) -> None:
        audits = RUN / "work/reviews/20260916-restart/independent-audits"
        core = hashlib.sha256(
            (RUN / "work/01/20260916-restart/official-cores/C01.jpg").read_bytes()
        ).hexdigest()
        harvest = hashlib.sha256(
            (
                RUN / "work/01/20260916-restart/official-cores-reverse-harvest/C01.jpg"
            ).read_bytes()
        ).hexdigest()
        still = hashlib.sha256(
            (RUN / "work/02b/20260916-restart/S01_micro_jewelry.jpg").read_bytes()
        ).hexdigest()
        self.assertNotEqual(core, harvest)
        self.assertNotEqual(core, still)
        audit01 = (audits / "AUDIT-01.md").read_text(encoding="utf-8")
        self.assertIn(core, audit01)
        self.assertIn(still, audit01)
        master = hashlib.sha256(
            (RUN / "generations/video/master/final-master-v1.mp4").read_bytes()
        ).hexdigest()
        review_sha = hashlib.sha256(
            (RUN / "work/reviews/20260916-restart/04-playback-review.md").read_bytes()
        ).hexdigest()
        yaml_sha = hashlib.sha256(
            (
                RUN / "work/reviews/20260916-restart/03v-playback-review-record.yaml"
            ).read_bytes()
        ).hexdigest()
        audit04 = (audits / "AUDIT-04.md").read_text(encoding="utf-8")
        audit03 = (audits / "AUDIT-03V.md").read_text(encoding="utf-8")
        self.assertIn(master, audit04)
        self.assertIn(review_sha, audit04)
        self.assertIn("3395", audit04)
        self.assertIn(yaml_sha, audit03)
        self.assertIn(master, audit03)

    def test_01_02a_director_review_hash_binds_live_cores_and_branches(self) -> None:
        review = (RUN / "work/reviews/20260916-restart/01-02a-director-review.md").read_text(
            encoding="utf-8"
        )
        lowered = review.lower()
        self.assertIn("hold", lowered)
        self.assertIn("01-first", lowered)
        self.assertNotIn("02b stills are the cores", lowered)
        self.assertNotIn("reverse-harvested from 02b/03v", lowered)
        self.assertIn("work/01/20260916-restart/official-cores/", review)
        self.assertIn("work/02a/20260916-restart/branches/", review)
        for i in range(1, 16):
            cid = f"C{i:02d}"
            core_sha = hashlib.sha256(
                (RUN / f"work/01/20260916-restart/official-cores/{cid}.jpg").read_bytes()
            ).hexdigest()
            branch_sha = hashlib.sha256(
                (RUN / f"work/02a/20260916-restart/branches/BC_{cid}.jpg").read_bytes()
            ).hexdigest()
            imported_sha = hashlib.sha256(
                (RUN / f"work/02a/20260916-restart/imported-cores/{cid}.jpg").read_bytes()
            ).hexdigest()
            self.assertEqual(core_sha, imported_sha, cid)
            self.assertNotEqual(core_sha, branch_sha, cid)
            self.assertIn(core_sha, review, cid)
            self.assertIn(branch_sha, review, cid)

    def test_status_and_01_review_remain_hold_not_05_complete(self) -> None:
        status = (RUN / "work/overall/20260916-restart/STATUS.md").read_text(encoding="utf-8")
        self.assertIn("HOLD", status)
        self.assertNotIn("05_pre_publication_inventory_complete", status)
        review = (RUN / "work/reviews/20260916-restart/01-02a-director-review.md").read_text(
            encoding="utf-8"
        )
        self.assertIn("hold", review.lower())
        self.assertIn("01-first", review.lower())
        self.assertNotIn("reverse-harvested from 02b/03v", review.lower())
        core = RUN / "work/01/20260916-restart/official-cores/C01.jpg"
        imported = RUN / "work/02a/20260916-restart/imported-cores/C01.jpg"
        branch = RUN / "work/02a/20260916-restart/branches/BC_C01.jpg"
        harvest = RUN / "work/01/20260916-restart/official-cores-reverse-harvest/C01.jpg"
        self.assertEqual(core.read_bytes(), imported.read_bytes())
        self.assertNotEqual(core.read_bytes(), branch.read_bytes())
        self.assertNotEqual(core.read_bytes(), harvest.read_bytes())
        manifest = (RUN / "run-manifest.yaml").read_text(encoding="utf-8")
        self.assertIn("member_visual_cards_status: missing_x5", manifest)
        x5 = RUN / "work/member-visual-identity/20260916-restart/x5-package/PACKAGE.md"
        self.assertIn("founder_review_pending", x5.read_text(encoding="utf-8"))

    def test_01_official_cores_are_not_byte_identical_to_02b_stills(self) -> None:
        cores = RUN / "work/01/20260916-restart/official-cores"
        imported = RUN / "work/02a/20260916-restart/imported-cores"
        branches = RUN / "work/02a/20260916-restart/branches"
        harvest = RUN / "work/01/20260916-restart/official-cores-reverse-harvest"
        stills = sorted((RUN / "work/02b/20260916-restart").glob("*.jpg"))
        still_bytes = [p.read_bytes() for p in stills]
        self.assertGreaterEqual(len(stills), 9)
        for i in range(1, 16):
            cid = f"C{i:02d}"
            core = (cores / f"{cid}.jpg").read_bytes()
            self.assertEqual(core, (imported / f"{cid}.jpg").read_bytes(), cid)
            self.assertNotEqual(core, (branches / f"BC_{cid}.jpg").read_bytes(), cid)
            self.assertNotEqual(core, (harvest / f"{cid}.jpg").read_bytes(), cid)
            for raw in still_bytes:
                self.assertNotEqual(core, raw, f"{cid} must not equal a 02B still")

    def test_delivery_and_dual_logs_bind_live_master_without_claiming_05_complete(self) -> None:
        master = RUN / "generations/video/master/final-master-v1.mp4"
        package = PACKAGE.read_bytes()
        delivery_text = DELIVERY.read_text(encoding="utf-8")
        live_master = hashlib.sha256(master.read_bytes()).hexdigest()
        live_package = hashlib.sha256(package).hexdigest()
        live_delivery = hashlib.sha256(DELIVERY.read_bytes()).hexdigest()
        live_size = master.stat().st_size
        self.assertGreater(live_size, 0)
        self.assertIn(live_master, delivery_text)
        self.assertIn(live_package, delivery_text)
        self.assertIn(f"size_bytes: {live_size}", delivery_text)
        self.assertNotIn("28083266", delivery_text)
        self.assertNotIn("465b4fec85235da945167c5766fd748dd1cbec901a2dfb6d6b5937ac24a4f31a", delivery_text)
        reviews = RUN / "work/reviews/20260916-restart"
        for name in ("master-ffprobe-1.log", "master-ffprobe-2.log"):
            text = (reviews / name).read_text(encoding="utf-8")
            self.assertIn(live_master, text)
            self.assertIn("duration=141.458333", text)
            self.assertIn("duration=141.451000", text)
            self.assertIn("nb_frames=3395", text)
            self.assertIn("width=1280", text)
            self.assertIn("height=720", text)
            self.assertIn("sample_aspect_ratio=1:1", text)
            self.assertIn("codec_type=audio", text)
            self.assertIn("codec_type=video", text)
        for name in ("contract-validate-1.log", "contract-validate-2.log"):
            text = (reviews / name).read_text(encoding="utf-8")
            self.assertIn(live_master, text)
            self.assertIn(live_package, text)
            self.assertIn(live_delivery, text)
            self.assertIn("artifact_revision_owner", text)
            self.assertIn("package_readiness_exit=1", text)
            self.assertIn("final_delivery_exit=1", text)
            self.assertIn("65c4ea8439f593843afde1361efbd77e9a5b8116ad7ba54bb00e2751598e5b61", text)
            self.assertIn("df4bab66c0179d8e6302914ede80d44b5f1c7a8767ce65034cbc1a2995496259", text)
        status = (RUN / "work/overall/20260916-restart/STATUS.md").read_text(encoding="utf-8")
        self.assertIn(live_master, status)
        self.assertIn(live_package, status)
        self.assertIn(live_delivery, status)
        self.assertIn("HOLD", status)
        self.assertNotIn("05_pre_publication_inventory_complete", status)

    def test_v8_prompt_manifest_binds_01_cores_and_02a_branches_not_02b_or_03v_frames(self) -> None:
        manifest = (
            RUN / "work/reviews/20260916-restart/03v-video-prompt-manifest-v8.yaml"
        ).read_text(encoding="utf-8")
        self.assertEqual(manifest.splitlines()[2], "status: hold")
        harvest = RUN / "work/01/20260916-restart/official-cores-reverse-harvest"
        for i in range(1, 16):
            cid = f"C{i:02d}"
            core = RUN / f"work/01/20260916-restart/official-cores/{cid}.jpg"
            imported = RUN / f"work/02a/20260916-restart/imported-cores/{cid}.jpg"
            branch = RUN / f"work/02a/20260916-restart/branches/BC_{cid}.jpg"
            core_sha = hashlib.sha256(core.read_bytes()).hexdigest()
            branch_sha = hashlib.sha256(branch.read_bytes()).hexdigest()
            self.assertEqual(core.read_bytes(), imported.read_bytes(), cid)
            self.assertNotEqual(core.read_bytes(), branch.read_bytes(), cid)
            self.assertNotEqual(
                core.read_bytes(),
                (harvest / f"{cid}.jpg").read_bytes(),
                cid,
            )
            core_path = f"work/01/20260916-restart/official-cores/{cid}.jpg"
            branch_path = f"work/02a/20260916-restart/branches/BC_{cid}.jpg"
            self.assertIn(core_path, manifest)
            self.assertIn(branch_path, manifest)
            self.assertIn(core_sha, manifest)
            self.assertIn(branch_sha, manifest)
        self.assertNotIn("work/02b/20260916-restart/", manifest)
        self.assertNotIn("work/03v/20260916-restart/frames/", manifest)


if __name__ == "__main__":
    unittest.main()
