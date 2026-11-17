from __future__ import annotations

import copy
import json
import sys
import tempfile
import threading
import unittest
from datetime import datetime, timezone
from pathlib import Path
from urllib.request import Request, urlopen


TOOL_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOL_ROOT))

from idol_ops_tracker.actions import TrackerActionError, apply_action  # noqa: E402
from idol_ops_tracker.derive import derive_state  # noqa: E402
from idol_ops_tracker.operations import collect_operations  # noqa: E402
from idol_ops_tracker.paths import DATA_PATH  # noqa: E402
from idol_ops_tracker.server import TrackerHandler, TrackerHTTPServer  # noqa: E402
from idol_ops_tracker.store import TrackerStore  # noqa: E402
from idol_ops_tracker.validation import TrackerValidationError, validate_state  # noqa: E402


NOW = datetime(2026, 8, 12, 9, 0, tzinfo=timezone.utc)


def load_fixture() -> dict:
    return json.loads(DATA_PATH.read_text(encoding="utf-8"))


class TrackerModelTests(unittest.TestCase):
    def test_seed_state_is_valid_and_template_weights_are_100(self) -> None:
        state = load_fixture()
        validate_state(state)
        self.assertEqual(
            [(template["id"], sum(item["weight"] for item in template["milestones"])) for template in state["templates"]],
            [
                ("template-idol-mv", 100),
                ("template-business-marketing", 100),
                ("template-cf", 100),
                ("template-web", 100),
            ],
        )

    def test_progress_is_unavailable_before_founder_baseline_lock(self) -> None:
        derived = derive_state(load_fixture(), NOW)
        project = derived["projects"][0]
        self.assertFalse(project["progress"]["available"])
        self.assertIsNone(project["progress"]["percent"])

    def test_progress_counts_only_complete_pass_with_existing_evidence(self) -> None:
        state = load_fixture()
        project_id = "idol-mv-active-run"
        state = apply_action(state, {"action": "lock_baseline", "project_id": project_id}, NOW)
        state = apply_action(
            state,
            {
                "action": "update_milestone",
                "project_id": project_id,
                "milestone_id": "idol-pre00",
                "patch": {
                    "status": "completed",
                    "gate_status": "pass",
                    "evidence_refs": ["wiki/production-system.md"],
                },
            },
            NOW,
        )
        derived = derive_state(state, NOW)
        project = next(item for item in derived["projects"] if item["id"] == project_id)
        self.assertTrue(project["progress"]["available"])
        self.assertEqual(project["progress"]["percent"], 10.0)

    def test_completed_without_evidence_does_not_count(self) -> None:
        state = load_fixture()
        project_id = "idol-mv-active-run"
        state = apply_action(state, {"action": "lock_baseline", "project_id": project_id}, NOW)
        state = apply_action(
            state,
            {
                "action": "update_milestone",
                "project_id": project_id,
                "milestone_id": "idol-pre00",
                "patch": {"status": "completed", "gate_status": "pass"},
            },
            NOW,
        )
        derived = derive_state(state, NOW)
        project = next(item for item in derived["projects"] if item["id"] == project_id)
        milestone = next(item for item in project["milestones"] if item["id"] == "idol-pre00")
        self.assertEqual(project["progress"]["percent"], 0.0)
        self.assertFalse(milestone["derived"]["verified_complete"])
        self.assertEqual(milestone["derived"]["evidence_state"], "missing")

    def test_directory_reference_does_not_count_as_milestone_evidence(self) -> None:
        state = load_fixture()
        project_id = "idol-mv-active-run"
        state = apply_action(state, {"action": "lock_baseline", "project_id": project_id}, NOW)
        state = apply_action(
            state,
            {
                "action": "update_milestone",
                "project_id": project_id,
                "milestone_id": "idol-pre00",
                "patch": {
                    "status": "completed",
                    "gate_status": "pass",
                    "evidence_refs": ["wiki"],
                },
            },
            NOW,
        )
        derived = derive_state(state, NOW)
        project = next(item for item in derived["projects"] if item["id"] == project_id)
        self.assertEqual(project["progress"]["percent"], 0.0)

    def test_locked_baseline_scope_and_weights_cannot_change(self) -> None:
        state = load_fixture()
        project_id = "idol-mv-active-run"
        state = apply_action(state, {"action": "lock_baseline", "project_id": project_id}, NOW)
        with self.assertRaises(TrackerActionError):
            apply_action(
                state,
                {
                    "action": "update_milestone",
                    "project_id": project_id,
                    "milestone_id": "idol-pre00",
                    "patch": {"weight": 11},
                },
                NOW,
            )
        with self.assertRaises(TrackerActionError):
            apply_action(
                state,
                {"action": "add_milestone", "project_id": project_id, "title": "새 범위", "weight": 1},
                NOW,
            )

    def test_ai_execution_never_changes_verified_progress(self) -> None:
        state = load_fixture()
        project_id = "idol-mv-active-run"
        state = apply_action(state, {"action": "lock_baseline", "project_id": project_id}, NOW)
        before = derive_state(state, NOW)
        before_percent = next(item for item in before["projects"] if item["id"] == project_id)["progress"]["percent"]
        state = apply_action(
            state,
            {
                "action": "add_execution",
                "project_id": project_id,
                "title": "AI 리서치 작업",
                "agent": "Codex",
                "status": "running",
            },
            NOW,
        )
        after = derive_state(state, NOW)
        after_percent = next(item for item in after["projects"] if item["id"] == project_id)["progress"]["percent"]
        self.assertEqual(before_percent, after_percent)
        self.assertFalse(after["executions"][0]["derived"]["counts_toward_progress"])

    def test_project_cannot_be_completed_before_every_milestone_is_verified(self) -> None:
        state = load_fixture()
        project_id = "idol-mv-active-run"
        state = apply_action(state, {"action": "lock_baseline", "project_id": project_id}, NOW)
        with self.assertRaises(TrackerActionError):
            apply_action(
                state,
                {"action": "update_project", "project_id": project_id, "patch": {"status": "completed"}},
                NOW,
            )

    def test_repo_path_escape_is_rejected(self) -> None:
        state = copy.deepcopy(load_fixture())
        state["projects"][0]["source_refs"] = ["../outside"]
        with self.assertRaises(TrackerValidationError):
            validate_state(state)


class TrackerStoreTests(unittest.TestCase):
    def test_default_store_rejects_write_target_outside_tool_root(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            with self.assertRaises(ValueError):
                TrackerStore(Path(temp_dir) / "tracker.json")

    def test_atomic_store_round_trip_in_explicit_test_root(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            store = TrackerStore(root / "data" / "tracker.json", allowed_root=root)
            state = load_fixture()
            store.save(state)
            self.assertEqual(store.load()["schema_version"], "idol-ops-tracker.v1")


class OperationsProjectionTests(unittest.TestCase):
    def test_mv_deadline_and_worker_heads_are_read_only_projections(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            run_root = root / "runs" / "aurora-m" / "demo" / "DEMO_RUN_R2"
            dispatch_root = run_root / "work" / "department-dispatches"
            dispatch_root.mkdir(parents=True)
            (run_root / "run-manifest.yaml").write_text(
                """schema_version: idol-run-manifest.v1
status: active
album_key: aurora-m
title_key: demo
run_id: DEMO_RUN_R2
content_id: DEMO
canonical_run_root: runs/aurora-m/demo/DEMO_RUN_R2
created_at: '2026-08-10T00:00:00+00:00'
run_sequence: 2
previous_run_root: runs/aurora-m/demo/DEMO_RUN_R1
""",
                encoding="utf-8",
            )
            output_path = run_root / "work" / "outputs" / "section.yaml"
            output_path.parent.mkdir(parents=True)
            output_path.write_text("status: candidate\n", encoding="utf-8")

            def write_dispatch(name: str, lineage: str, attempt: int, state: str, previous: str = "") -> None:
                (dispatch_root / f"{name}.yaml").write_text(
                    f"""schema_version: idol-department-dispatch.v4
artifact_type: department_dispatch
dispatch_id: {name}
run: runs/aurora-m/demo/DEMO_RUN_R2
lineage:
  lineage_id: {lineage}
  attempt_id: {name}
  attempt_number: {attempt}
  provider: codex
  runtime_surface: test
  session_id: SESSION_{name}
  previous_attempt_id: {previous or 'null'}
  lineage_state: active
  successor_attempt_id: null
lifecycle:
  current_state: {state}
  events:
    - state: prepared
      at: '2026-08-10T01:00:00+00:00'
      actor: TEST
    - state: {state}
      at: '2026-08-10T02:00:00+00:00'
      actor: TEST
launch:
  prepared_at: '2026-08-10T01:00:00+00:00'
  launched_at: '2026-08-10T01:30:00+00:00'
  task:
    role: department_worker
    exact_scope:
      stage_id: mv_storyboard_direction
      section_ids: [S01]
      artifact_paths:
        - runs/aurora-m/demo/DEMO_RUN_R2/work/outputs/section.yaml
recipient:
  owner: CDD_DEMO
  role: creative_development_director
runtime_return: null
director_review: null
promotion: null
""",
                    encoding="utf-8",
                )

            write_dispatch("DEMO_A01", "DEMO_LINEAGE", 1, "launched")
            write_dispatch("DEMO_A02", "DEMO_LINEAGE", 2, "returned", "DEMO_A01")
            write_dispatch("DEMO_OTHER_A01", "DEMO_OTHER", 1, "promoted")
            (root / "cf" / "runs" / "CF_DEMO_001").mkdir(parents=True)

            operations = collect_operations(root, NOW)
            selected = operations["selected_mv_run"]
            self.assertEqual(selected["run_id"], "DEMO_RUN_R2")
            self.assertEqual(selected["deadline"]["days"], 7)
            self.assertEqual(selected["deadline"]["at"], "2026-08-17T09:00:00+09:00")
            projection = selected["worker_projection"]
            self.assertFalse(projection["projection_complete"])
            self.assertEqual(projection["counts"]["registered_heads"], 2)
            self.assertEqual(projection["counts"]["history_attempts"], 1)
            self.assertEqual(projection["counts"]["returned"], 1)
            self.assertEqual(projection["counts"]["promoted"], 1)
            returned = next(worker for worker in projection["workers"] if worker["dispatch_id"] == "DEMO_A02")
            self.assertEqual(returned["recipient_owner"], "CDD_DEMO")
            self.assertEqual(returned["outputs"], {"declared": 1, "existing": 1})
            self.assertEqual(operations["selected_cf_run"]["deadline"]["days"], 3)

    def test_mv_family_folds_base_and_labels_main_with_two_sub_runs(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            title_root = root / "runs" / "aurora-m" / "demo"

            def write_manifest(run_id: str, sequence: int, previous_root: str | None = None) -> None:
                run_root = title_root / run_id
                run_root.mkdir(parents=True)
                previous_line = f"previous_run_root: {previous_root}\n" if previous_root else ""
                (run_root / "run-manifest.yaml").write_text(
                    f"""schema_version: idol-run-manifest.v1
status: active
album_key: aurora-m
title_key: demo
run_id: {run_id}
content_id: DEMO
canonical_run_root: runs/aurora-m/demo/{run_id}
created_at: '2026-08-{9 + sequence:02d}T00:00:00+00:00'
run_sequence: {sequence}
{previous_line}""",
                    encoding="utf-8",
                )

            base_root = "runs/aurora-m/demo/DEMO_BASE"
            write_manifest("DEMO_BASE", 1)
            write_manifest("DEMO_GENERATE", 2, base_root)
            write_manifest("DEMO_GENERATE_R2", 3, base_root)
            write_manifest("DEMO_GENERATE_R3", 4, base_root)

            excluded_root = root / "runs" / "aurora-m" / "cf-demo" / "CF_DEMO"
            excluded_root.mkdir(parents=True)
            (excluded_root / "run-manifest.yaml").write_text(
                """status: active
album_key: aurora-m
title_key: cf-demo
run_id: CF_DEMO
content_id: CF_DEMO
canonical_run_root: runs/aurora-m/cf-demo/CF_DEMO
created_at: '2026-08-13T00:00:00+00:00'
run_sequence: 1
""",
                encoding="utf-8",
            )

            operations = collect_operations(root, NOW)
            family = operations["selected_mv_family"]
            self.assertEqual(family["relationship_basis"], "shared_previous_run_root")
            self.assertEqual(family["base_run"]["run_id"], "DEMO_BASE")
            self.assertEqual(
                [(run["presentation_label"], run["run_id"]) for run in family["runs"]],
                [
                    ("MAIN", "DEMO_GENERATE_R3"),
                    ("SUB 1", "DEMO_GENERATE_R2"),
                    ("SUB 2", "DEMO_GENERATE"),
                ],
            )
            self.assertEqual(operations["summary"]["mv_open_runs"], 3)
            self.assertEqual(operations["summary"]["mv_excluded_non_mv_runs"], 1)


class TrackerHTTPTests(unittest.TestCase):
    def test_local_health_and_action_round_trip(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            store = TrackerStore(root / "tracker.json", allowed_root=root)
            store.save(load_fixture())
            try:
                server = TrackerHTTPServer(("127.0.0.1", 0), TrackerHandler, store)
            except PermissionError:
                self.skipTest("sandbox does not permit loopback socket binding")
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            base_url = f"http://127.0.0.1:{server.server_address[1]}"
            try:
                with urlopen(f"{base_url}/api/health", timeout=5) as response:
                    health = json.load(response)
                self.assertTrue(health["ok"])
                self.assertEqual(health["source_mode"], "read_only")

                body = json.dumps(
                    {
                        "action": "update_project",
                        "project_id": "idol-mv-active-run",
                        "patch": {"next_action": "테스트 다음 행동"},
                    }
                ).encode("utf-8")
                request = Request(
                    f"{base_url}/api/action",
                    data=body,
                    headers={"Content-Type": "application/json"},
                    method="POST",
                )
                with urlopen(request, timeout=10) as response:
                    result = json.load(response)
                self.assertTrue(result["ok"])
                self.assertEqual(store.load()["projects"][0]["next_action"], "테스트 다음 행동")
            finally:
                server.shutdown()
                server.server_close()
                thread.join(timeout=5)


if __name__ == "__main__":
    unittest.main()
