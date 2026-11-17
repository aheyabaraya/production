#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import tempfile
import unittest
from pathlib import Path

import yaml

from scripts.lib.idol_run_layout import (
    _active_stage_sequence_sha256,
    build_run_root,
    parse_run_root,
    resolve_run_identity,
    validate_run_manifest,
)


class IdolRunLayoutTest(unittest.TestCase):
    def test_builds_album_title_run_address(self) -> None:
        self.assertEqual(
            "runs/aurora-m/one-move/ONE_MOVE_R02",
            build_run_root("aurora-m", "one-move", "ONE_MOVE_R02"),
        )

    def test_rejects_date_first_active_address(self) -> None:
        with self.assertRaisesRegex(ValueError, "ALBUM_KEY/TITLE_KEY/RUN_ID"):
            parse_run_root("runs/2026-07-29/0729_ONE_MOVE")

    def test_manifest_must_bind_folder_keys(self) -> None:
        with tempfile.TemporaryDirectory(prefix="idol-run-layout-") as tmp:
            root = Path(tmp)
            run = root / "runs/aurora-m/one-move/ONE_MOVE_R02"
            run.mkdir(parents=True)
            manifest = {
                "schema_version": "idol-run-manifest.v1",
                "album_key": "aurora-m",
                "title_key": "wrong-title",
                "run_id": "ONE_MOVE_R02",
                "canonical_run_root": "runs/aurora-m/one-move/ONE_MOVE_R02",
                "artifact_revision_owner": "git",
                "compatibility_authoring": "forbidden",
            }
            (run / "run-manifest.yaml").write_text(
                yaml.safe_dump(manifest, sort_keys=False),
                encoding="utf-8",
            )
            errors = validate_run_manifest(run, root)
            self.assertTrue(any("title_key" in error for error in errors))

    def test_only_exact_hash_bound_transition_may_finish_in_place(self) -> None:
        with tempfile.TemporaryDirectory(prefix="idol-run-transition-") as tmp:
            root = Path(tmp)
            run_rel = "runs/2026-07-29/0729_ONE_MOVE"
            target_rel = "runs/aurora-m/one-move/0729_ONE_MOVE"
            run = root / run_rel
            run.mkdir(parents=True)
            automation = root / "automation"
            automation.mkdir()
            stage_registry = {
                "schema_version": "test",
                "stages": [
                    {
                        "stage_id": "test_stage",
                        "order": 1,
                        "code": "PRE-00",
                        "owner_skill": "test",
                        "scope": "test",
                        "inputs": [],
                        "founder_gate": "none",
                        "active": True,
                    }
                ],
            }
            stage_path = automation / "harness-stage-registry.yaml"
            stage_path.write_text(
                yaml.safe_dump(stage_registry, sort_keys=False),
                encoding="utf-8",
            )
            plan = {
                "schema_version": "idol-run-migration-plan.v1",
                "status": "hold",
                "source_run_root": run_rel,
                "target_run_root": target_rel,
                "automatic_move_performed": False,
            }
            plan_path = run / "work/run-layout-migration-plan-v1.yaml"
            plan_path.parent.mkdir()
            plan_path.write_text(
                yaml.safe_dump(plan, sort_keys=False),
                encoding="utf-8",
            )
            transition = {
                "schema_version": "idol-run-layout-transition.v1",
                "status": "active",
                "active_run_template": "runs/ALBUM_KEY/TITLE_KEY/RUN_ID",
                "generic_date_first_authoring": "forbidden",
                "new_date_first_run_creation": "forbidden",
                "quality_flow_change_authority": "none",
                "in_flight_exceptions": [
                    {
                        "run_root": run_rel,
                        "album_key": "aurora-m",
                        "title_key": "one-move",
                        "run_id": "0729_ONE_MOVE",
                        "content_id": "0729_ONE_MOVE",
                        "state": "in_flight_finish_in_place",
                        "current_next_allowed": True,
                        "existing_canonical_continuation_allowed": True,
                        "new_run_creation_allowed": False,
                        "migration_execution_allowed": False,
                        "target_run_root": target_rel,
                        "expires_when": "run_closed_or_validated_migration_completed",
                        "migration_plan": {
                            "path": (
                                "runs/2026-07-29/0729_ONE_MOVE/work/"
                                "run-layout-migration-plan-v1.yaml"
                            ),
                            "sha256": hashlib.sha256(plan_path.read_bytes()).hexdigest(),
                            "required_status": "hold",
                        },
                        "flow_lock": {
                            "stage_registry_path": (
                                "automation/harness-stage-registry.yaml"
                            ),
                            "stage_registry_sha256": hashlib.sha256(
                                stage_path.read_bytes()
                            ).hexdigest(),
                            "stage_sequence_sha256": (
                                _active_stage_sequence_sha256(stage_registry)
                            ),
                        },
                    }
                ],
            }
            (automation / "run-layout-transition.yaml").write_text(
                yaml.safe_dump(transition, sort_keys=False),
                encoding="utf-8",
            )

            self.assertEqual([], validate_run_manifest(run, root))
            identity = resolve_run_identity(run, root)
            self.assertEqual(
                "registered_in_flight_transition",
                identity["layout_status"],
            )
            self.assertEqual("aurora-m", identity["address"].album_key)
            self.assertTrue(
                validate_run_manifest("runs/2026-07-30/UNREGISTERED", root)
            )

            plan_path.write_text(
                plan_path.read_text(encoding="utf-8") + "# changed\n",
                encoding="utf-8",
            )
            self.assertTrue(
                any(
                    "migration plan SHA-256 mismatch" in error
                    for error in validate_run_manifest(run, root)
                )
            )


if __name__ == "__main__":
    unittest.main()
