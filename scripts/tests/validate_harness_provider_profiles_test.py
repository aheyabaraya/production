#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import shutil
import subprocess
import sys
import tempfile
import tomllib
import unittest
from pathlib import Path
from typing import Callable

import yaml


ROOT = Path(__file__).resolve().parents[2]
VALIDATOR = ROOT / "scripts" / "validate_harness_provider_profiles.py"


class ValidateHarnessProviderProfilesTest(unittest.TestCase):
    @staticmethod
    def sha256_lines(values: list[object]) -> str:
        payload = "\n".join(str(value).lower() if isinstance(value, bool) else str(value) for value in values)
        return hashlib.sha256(payload.encode("utf-8")).hexdigest()

    def finalize_assignment(self, assignment: dict) -> dict:
        readiness_evidence = self.sha256_lines([
            "provider_source_readiness.v1",
            assignment["assignment_id"],
            assignment["provider_source_path"],
            assignment["provider_source_sha256"],
            assignment["provider_profile_pointer"],
            assignment["model"],
            assignment["effort"],
            assignment["adapter_id"],
            assignment["auth_lane"],
            assignment.get("auth_authority_ref") or "",
            assignment["provider_capability_status"],
            assignment["provider_harness_status"],
            assignment["provider_full_owner_ready"],
        ])
        assignment["provider_source_readiness"] = {
            "status": "ready",
            "provider_source_rehashed": True,
            "profile_model_effort_exact": True,
            "adapter_exact": True,
            "auth_lane_exact": True,
            "no_fallback": True,
            "evidence_sha256": readiness_evidence,
        }
        assignment["immutable_profile_key"] = self.sha256_lines([
            "sha256_utf8_lf_assignment_profile_fields_v1",
            assignment["assignment_id"],
            assignment["provider"],
            assignment["adapter_id"],
            assignment["runtime_surface"],
            assignment["profile_id"],
            assignment["execution_profile_id"],
            assignment["logical_profile_alias"],
            assignment["model"],
            assignment["effort"],
            assignment["auth_lane"],
            assignment.get("auth_authority_ref") or "",
            assignment["provider_source_path"],
            assignment["provider_source_sha256"],
            assignment["provider_profile_pointer"],
            readiness_evidence,
        ])
        return assignment

    def finalize_grok_runtime_policy(self, assignment: dict) -> dict:
        runtime = assignment["runtime_capabilities"]
        write_paths = sorted(runtime["allowed_write_paths"])
        assignment["runtime_policy_key"] = self.sha256_lines([
            "grok_runtime_capabilities.v1",
            assignment["assignment_id"],
            runtime["execution_mode"],
            runtime["filesystem"],
            len(write_paths),
            *write_paths,
            runtime["web_search"],
            runtime["provider_native_subagents"],
            runtime["memory"],
            runtime["imagine"],
            runtime["authority_boundary"],
        ])
        return assignment

    def fixture(self) -> tuple[tempfile.TemporaryDirectory[str], Path]:
        temporary = tempfile.TemporaryDirectory(prefix="idol-provider-profiles-")
        root = Path(temporary.name)
        (root / ".codex/agents").mkdir(parents=True)
        (root / "automation/providers").mkdir(parents=True)
        (root / "schemas").mkdir(parents=True)
        (root / "development/front-planning-workbench/contracts").mkdir(parents=True)
        (root / "development/front-planning-workbench/docs/evidence").mkdir(parents=True)
        (root / "development/front-planning-workbench/ui/tests").mkdir(parents=True)
        (root / "development/front-planning-workbench/tests").mkdir(parents=True)
        (root / "scripts/tests").mkdir(parents=True)
        (root / "policies").mkdir(parents=True)
        shutil.copy2(ROOT / ".codex/config.toml", root / ".codex/config.toml")
        for path in (ROOT / ".codex/agents").glob("*.toml"):
            shutil.copy2(path, root / ".codex/agents" / path.name)
        shutil.copy2(
            ROOT / "automation/providers/grok-build-profiles.yaml",
            root / "automation/providers/grok-build-profiles.yaml",
        )
        shutil.copy2(
            ROOT / "automation/providers/openai-image-profiles.yaml",
            root / "automation/providers/openai-image-profiles.yaml",
        )
        shutil.copy2(
            ROOT / "automation/providers/codex-native-media-profiles.yaml",
            root / "automation/providers/codex-native-media-profiles.yaml",
        )
        shutil.copy2(
            ROOT / "automation/providers/cursor-agent-profiles.yaml",
            root / "automation/providers/cursor-agent-profiles.yaml",
        )
        shutil.copy2(
            ROOT / "schemas/cursor-agent-provider-profiles.schema.json",
            root / "schemas/cursor-agent-provider-profiles.schema.json",
        )
        shutil.copy2(
            ROOT / "automation/harness-provider-profile-registry.yaml",
            root / "automation/harness-provider-profile-registry.yaml",
        )
        shutil.copy2(
            ROOT / "schemas/harness-provider-profile-registry.schema.json",
            root / "schemas/harness-provider-profile-registry.schema.json",
        )
        shutil.copy2(
            ROOT / "schemas/xai-api-media-provider-profiles.schema.json",
            root / "schemas/xai-api-media-provider-profiles.schema.json",
        )
        shutil.copy2(
            ROOT / "development/front-planning-workbench/contracts/run-route-manifest.schema.json",
            root / "development/front-planning-workbench/contracts/run-route-manifest.schema.json",
        )
        shutil.copy2(
            ROOT / "automation/harness-skill-load-profiles.yaml",
            root / "automation/harness-skill-load-profiles.yaml",
        )
        for relative in (
            "development/front-planning-workbench/docs/evidence/grok-1.0.3-role-lifecycle-receipt-2026-08-14.json",
            "development/front-planning-workbench/docs/evidence/grok-1.0.3-cdd-direct-session-router-receipt-2026-08-17.json",
            "development/front-planning-workbench/docs/evidence/grok-1.0.4-video-lane-readiness-receipt-2026-08-17.json",
            "scripts/idol_director_dispatch_index.rb",
            "schemas/cdd-session-router-state.schema.json",
            "scripts/tests/idol_cdd_session_router_test.rb",
            "policies/harness-routing-and-sources.md",
        ):
            shutil.copy2(ROOT / relative, root / relative)
        self.refresh_fixture_grok_evidence_bindings(root)
        self.refresh_fixture_cursor_bindings(root)
        return temporary, root

    def refresh_fixture_cursor_bindings(self, root: Path) -> None:
        source_path = root / "automation/providers/cursor-agent-profiles.yaml"
        source_sha = hashlib.sha256(source_path.read_bytes()).hexdigest()
        registry_path = root / "automation/harness-provider-profile-registry.yaml"

        def refresh_registry(document: dict) -> None:
            for alias in (
                "frontier_director",
                "director_deep",
                "worker_high",
                "research_medium",
                "cursor_advisory",
                "cursor_grok_explicit_selected_worker",
            ):
                cursor = (
                    document.get("logical_profiles", {})
                    .get(alias, {})
                    .get("providers", {})
                    .get("cursor")
                )
                if isinstance(cursor, dict):
                    cursor["source_sha256"] = source_sha
            luna_lane = (document.get("media_lanes") or {}).get("cursor_luna_optional_image")
            if isinstance(luna_lane, dict):
                luna_lane["provider_profile_source_sha256"] = source_sha

        self.mutate_yaml(registry_path, refresh_registry)

    def refresh_fixture_grok_evidence_bindings(self, root: Path) -> None:
        source_path = root / "automation/providers/grok-build-profiles.yaml"
        source = yaml.safe_load(source_path.read_text(encoding="utf-8"))
        refs = source["nonmedia_activation_evidence"]["evidence_refs"]
        for row in refs.values():
            evidence_path = root / row["path"]
            row["sha256"] = hashlib.sha256(evidence_path.read_bytes()).hexdigest()
        source_path.write_text(
            yaml.safe_dump(source, sort_keys=False, allow_unicode=True),
            encoding="utf-8",
        )
        source_sha = hashlib.sha256(source_path.read_bytes()).hexdigest()
        registry_path = root / "automation/harness-provider-profile-registry.yaml"

        def refresh_registry(document: dict) -> None:
            for alias in ("frontier_director", "director_deep", "worker_high", "research_medium"):
                document["logical_profiles"][alias]["providers"]["grok"][
                    "source_sha256"
                ] = source_sha
            document["media_lanes"]["grok_build_oauth_subscription"][
                "provider_profile_source_sha256"
            ] = source_sha

        self.mutate_yaml(registry_path, refresh_registry)

    def install_grok_director_router_receipt(
        self,
        root: Path,
        *,
        goal_terminal_state: str = "complete",
        goal_last_event: str = "goal_completed",
    ) -> None:
        source_path = root / "automation/providers/grok-build-profiles.yaml"
        source = yaml.safe_load(source_path.read_text(encoding="utf-8"))
        baseline = json.loads(
            (root / "development/front-planning-workbench/docs/evidence/grok-1.0.3-role-lifecycle-receipt-2026-08-14.json").read_text(encoding="utf-8")
        )
        refs = source["nonmedia_activation_evidence"]["evidence_refs"]
        digest = "a" * 64
        receipt = {
            "evidence_kind": "noncanonical_actual_binary_grok_cdd_direct_session_router_receipt",
            "status": "pass",
            "observed_at": "2026-08-17T00:00:00Z",
            "authority": "evidence_only_no_creative_pass_no_provider_default_switch_no_canonical_write",
            "runtime": {
                "model": "grok-4.6",
                "reasoning_effort": "xhigh",
                "auth_lane": "subscription_oauth",
                "xai_api_key_present": False,
                "sandbox": "idol-repo",
                "permission_mode": "plan",
                "web_search": False,
                "memory": False,
                "imagine": False,
                "canonical_or_media_writes_requested": False,
                "external_actions_requested": False,
                "probe_root_class": "bounded_private_tmp_noncanonical_proof",
                "binary": baseline["runtime"]["binary"],
                "binary_sha256": baseline["runtime"]["binary_sha256"],
            },
            "sessions": {
                "source_session_id_sha256": "1" * 64,
                "successor_session_id_sha256": "2" * 64,
                "distinct": True,
                "successor_model_turns_before_admission": 0,
            },
            "goal_admission": {
                "goal_semantics": "grok_goal_completed_admission",
                "goal_terminal_state": goal_terminal_state,
                "goal_last_event": goal_last_event,
                "successor_assignment_state_after_goal": "admitted_read_only",
                "goal_completion_closes_assignment": False,
                "admission_status": "pass",
                "goal_id_sha256": "3" * 64,
                "goal_objective_sha256": "4" * 64,
                "goal_terminal_event_sha256": "5" * 64,
                "admission_digest": "6" * 64,
            },
            "router": {
                "implementation_path": "scripts/idol_director_dispatch_index.rb",
                "implementation_sha256": refs["cdd_session_router_implementation"]["sha256"],
                "state_schema_path": "schemas/cdd-session-router-state.schema.json",
                "state_schema_sha256": refs["cdd_session_router_state_schema"]["sha256"],
                "state_schema_version": "idol-cdd-session-router-state.v1",
                "state_generations": [0, 1, 2, 3],
                "source_active_before": True,
                "successor_read_only_before_commit": True,
                "source_denied_after_commit": True,
                "successor_authorized_after_commit": True,
                "successor_denied_after_rollback": True,
                "source_authorized_after_rollback": True,
                "simultaneous_writer_count_max": 1,
                "authorization_gate_operations": ["prompt", "resume", "dispatch", "review", "canonical_write"],
                "proof_state_root": "bounded_private_tmp_noncanonical_proof",
                "initialize_receipt_sha256": digest,
                "admit_receipt_sha256": digest,
                "commit_receipt_sha256": digest,
                "source_denial_receipt_sha256": digest,
                "successor_authorization_receipt_sha256": digest,
                "rollback_receipt_sha256": digest,
                "successor_denial_receipt_sha256": digest,
                "source_reactivation_authorization_receipt_sha256": digest,
                "final_state_sha256": digest,
            },
            "compatibility_revalidation": {
                "status": "pass",
                "recorded_at": "2026-08-18T09:25:00Z",
                "current_implementation_sha256": refs["cdd_session_router_implementation"]["sha256"],
                "current_state_schema_sha256": refs["cdd_session_router_state_schema"]["sha256"],
                "current_isolated_test_sha256": refs["cdd_session_router_isolated_test"]["sha256"],
                "change_scope": "add_cursor_provider_and_external_goal_runtime_receipt_branch",
                "grok_route_semantics_changed": False,
                "isolated_tests_pass": True,
                "live_grok_execution_repeated": False,
                "external_or_generative_actions": 0,
            },
            "continuation": {
                "successor_session_loaded_exact": True,
                "successor_continue_response_completed": True,
                "successor_continue_durable_terminal": True,
                "clean_stop": True,
                "continue_prompt_sha256": "7" * 64,
                "continue_terminal_event_sha256": "8" * 64,
            },
            "boundary": {
                "tracked_source_status_unchanged": True,
                "repository_write_count": 0,
                "media_generation_count": 0,
                "external_action_count": 0,
                "cross_provider_fallback_count": 0,
                "html_or_review_board_write_count": 0,
                "creative_or_canonical_write_count": 0,
            },
        }
        receipt_path = root / source["nonmedia_activation_evidence"]["director_successor_live_evidence"]["path"]
        receipt_path.write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
        source["nonmedia_activation_evidence"]["director_successor_live_evidence"].update(
            status="present",
            sha256=hashlib.sha256(receipt_path.read_bytes()).hexdigest(),
        )
        ready_decision = {
            "status": "ready",
            "verified_requirements": [
                "create_send_wait_resume_continue",
                "fork_successor_with_retained_session",
                "harness_logical_retire_reactivate",
                "provider_native_goal_admission_event_and_attestation",
                "registered_session_router_active_role_singleton_cas",
                "pre00_to_05_no_fallback_shadow",
                "actual_binary_two_session_successor_receipt",
            ],
            "blocking_requirements": [],
            "required_next_evidence": "none",
        }
        source["nonmedia_activation_evidence"]["profile_decisions"]["grok_director_deep"] = dict(
            ready_decision
        )
        source["nonmedia_activation_evidence"]["profile_decisions"]["grok_director_frontier"] = dict(
            ready_decision
        )
        source["profiles"]["grok_director_deep"].update(
            harness_status="active",
            full_owner_ready=True,
        )
        source["profiles"]["grok_director_frontier"].update(
            harness_status="active",
            full_owner_ready=True,
        )
        source_path.write_text(yaml.safe_dump(source, sort_keys=False, allow_unicode=True), encoding="utf-8")
        source_sha = hashlib.sha256(source_path.read_bytes()).hexdigest()
        registry_path = root / "automation/harness-provider-profile-registry.yaml"

        def refresh_registry(document: dict) -> None:
            for alias in ("frontier_director", "director_deep", "worker_high", "research_medium"):
                document["logical_profiles"][alias]["providers"]["grok"]["source_sha256"] = source_sha
            director = document["logical_profiles"]["director_deep"]["providers"]["grok"]
            director.update(harness_status="active", full_owner_ready=True)
            frontier = document["logical_profiles"]["frontier_director"]["providers"]["grok"]
            frontier.update(harness_status="active", full_owner_ready=True)
            document["media_lanes"]["grok_build_oauth_subscription"]["provider_profile_source_sha256"] = source_sha

        self.mutate_yaml(registry_path, refresh_registry)

    def refresh_codex_profile_bindings(self, root: Path, alias: str) -> None:
        registry_path = root / "automation/harness-provider-profile-registry.yaml"

        def refresh_registry(document: dict) -> None:
            provider = document["logical_profiles"][alias]["providers"]["codex"]
            digest_rows = []
            for row in provider["role_profiles"].values():
                source_path = root / row["source_path"]
                digest = hashlib.sha256(source_path.read_bytes()).hexdigest()
                row["source_sha256"] = digest
                digest_rows.append((row["source_path"], digest))
            payload = "".join(
                f"{path}:{digest}\n" for path, digest in sorted(digest_rows)
            )
            provider["source_set_sha256"] = hashlib.sha256(
                payload.encode("utf-8")
            ).hexdigest()

        self.mutate_yaml(registry_path, refresh_registry)

    def run_validator(
        self,
        root: Path,
        run_route_manifest: Path | None = None,
    ) -> tuple[subprocess.CompletedProcess[str], dict]:
        command = [sys.executable, str(VALIDATOR), "--root", str(root)]
        if run_route_manifest is not None:
            command.extend(["--run-route-manifest", str(run_route_manifest)])
        command.append("--json")
        result = subprocess.run(
            command,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        if not result.stdout.strip():
            self.fail(f"provider validator emitted no JSON\nstdout={result.stdout}\nstderr={result.stderr}")
        return result, json.loads(result.stdout)

    def write_run_route_manifest(self, root: Path) -> Path:
        registry_path = root / "automation/harness-provider-profile-registry.yaml"
        registry = yaml.safe_load(registry_path.read_text(encoding="utf-8"))
        provider = registry["logical_profiles"]["director_deep"]["providers"]["cursor"]
        source_path = provider["source_path"]
        source_document = yaml.safe_load((root / source_path).read_text(encoding="utf-8"))
        profile = source_document["profiles"]["cursor_sol_xhigh"]
        assignments = []
        for role, key in (
            ("overall_director", "main"),
            ("creative_development_director", "development-through-03v"),
            ("edit_director", "edit-through-05"),
        ):
            assignments.append(self.finalize_assignment({
                "assignment_id": f"{role}:{key}",
                "studio_role": role,
                "assignment_key": key,
                "provider": "cursor",
                "adapter_id": "cursor_cli_local",
                "runtime_surface": "cursor_cli_local_physical_chat",
                "profile_id": role,
                "execution_profile_id": "cursor_sol_xhigh",
                "logical_profile_alias": "director_deep",
                "model": profile["exact_model"],
                "effort": profile["reasoning_effort"],
                "provider_source_path": source_path,
                "provider_source_sha256": provider["source_sha256"],
                "provider_profile_pointer": f"{source_path}#/profiles/cursor_sol_xhigh",
                "provider_capability_status": provider["capability_status"],
                "provider_harness_status": provider["harness_status"],
                "provider_full_owner_ready": provider["full_owner_ready"],
                "auth_lane": "cursor_cli_file_credential_store",
                "auth_authority_ref": None,
                "founder_visible": True,
                "owner_authority": role,
                "binding_state": "requires_session_capability_handshake",
                "capability_evidence_ids": [],
                "fallback_behavior": "hold_and_report",
            }))
        skill_registry = root / "automation/harness-skill-load-profiles.yaml"
        manifest = {
            "schema_version": "front-planning-workbench.run-route-manifest.v4",
            "manifest_id": "TEST_RUN_ROUTE_001",
            "run_root": "runs/album-one/title-one/TEST_RUN",
            "scope": "one_run_scoped_role_assignment_manifest",
            "authorizing_actor": "founder",
            "authorization_evidence": "explicit_current_run_route_authorization_or_run_manifest_flag",
            "provider_mode_selection": "forbidden",
            "no_silent_provider_or_model_substitution": True,
            "cross_provider_fallback_allowed": False,
            "profile_compatibility": {
                "registry_path": "automation/harness-skill-load-profiles.yaml",
                "registry_sha256": hashlib.sha256(skill_registry.read_bytes()).hexdigest(),
                "role_profile_allowlist": {
                    "overall_director": ["overall_director"],
                    "creative_development_director": ["creative_development_director"],
                    "song_room": ["song_room_prompt", "song_room_00a"],
                    "department_worker": ["pre_song_research", "reference_research_generalist", "world_still_reference_department", "pinterest_visual_composition_worker", "source_hub_registration", "pre_02a_development_block_fp", "founder_briefing"],
                    "member_visual_identity_owner": ["member_visual_identity"],
                    "section_owner": ["post_02a_02b_image", "post_02a_03v"],
                    "edit_director": ["edit_director"],
                    "edit_shard_worker": ["edit_shard"],
                    "mechanical_coordinator": ["board_coordinator"],
                    "grok_peer": ["grok_peer"],
                },
                "grok_peer_profile_note": "Authority-less peer only; no canonical writer or promotion authority.",
            },
            "provider_profile_registry_binding": {
                "registry_path": "automation/harness-provider-profile-registry.yaml",
                "registry_sha256": hashlib.sha256(registry_path.read_bytes()).hexdigest(),
                "schema_version": "idol-harness-provider-profile-registry.v1",
                "runtime_rehash_required": True,
                "provider_source_rehash_required": True,
                "exact_model_effort_match_required": True,
                "director_full_owner_ready_required": True,
                "mismatch_action": "hold_and_report",
            },
            "immutable_profile_key_algorithm": "sha256_utf8_lf_assignment_profile_fields_v1",
            "runtime_policy_key_algorithm": "sha256_utf8_lf_grok_runtime_capabilities_v1",
            "assignments": assignments,
            "session_capability_evidence": {
                "required_before_reads_or_work": True,
                "minimum_entries_per_active_assignment": 1,
                "accepted_sources": ["native_capability_handshake", "codex_app_server_thread_goal_updated", "cursor_external_goal_runtime_receipt", "grok_acp_goal_updated_event"],
                "native_event_fields_required_by_provider": {
                    "codex": ["threadId", "objective", "status"],
                    "grok": ["id", "objective", "state"],
                    "cursor": ["external_goal_record_sha256", "session_id", "request_id", "terminal_status"],
                },
                "adapter_attestation_fields_required": ["assignment_key", "dispatch_id", "attempt_id", "runtime_surface", "native_session_id", "observed_at", "raw_event_sha256"],
                "self_reported_goal_id_accepted": False,
                "missing_evidence_action": "goal_surface_unavailable_hold_before_reads_or_work",
                "entries": [],
            },
            "derived_capability_validation": {
                "algorithm": "derive_per_assignment_from_bound_adapter_and_session_evidence_only",
                "required_before_work": ["role_binding", "provider_adapter", "native_session", "goal_updated"],
                "full_owner_capability_set": ["overall_and_cdd_role_creation", "all_stage_contracts_and_founder_gates", "native_goal_updated_evidence", "zero_turn_successor_create", "archive_and_unarchive_rollback", "admission_and_compare_and_swap"],
                "unattested_full_owner_claim_allowed": False,
                "self_reported_or_local_goal_ids_accepted": False,
                "cross_provider_fallback_allowed": False,
                "missing_capability_action": "hold_and_report",
                "derived_route_class_is_display_only": True,
            },
        }
        path = root / "runs/album-one/title-one/TEST_RUN/work/front_planning_integration/run-route-manifest.json"
        path.parent.mkdir(parents=True)
        path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
        return path

    def add_cursor_worker_assignment(self, root: Path, manifest_path: Path) -> None:
        registry = yaml.safe_load(
            (root / "automation/harness-provider-profile-registry.yaml").read_text(
                encoding="utf-8"
            )
        )
        provider = registry["logical_profiles"]["worker_high"]["providers"]["cursor"]
        source_path = provider["source_path"]
        source_document = yaml.safe_load((root / source_path).read_text(encoding="utf-8"))
        profile = source_document["profiles"]["cursor_luna_max"]
        assignment = self.finalize_assignment({
            "assignment_id": "department_worker:PHYSICAL-REFERENCE-A",
            "studio_role": "department_worker",
            "assignment_key": "PHYSICAL-REFERENCE-A",
            "provider": "cursor",
            "adapter_id": "cursor_cli_local",
            "runtime_surface": "cursor_cli_local_physical_chat",
            "profile_id": "reference_research_generalist",
            "execution_profile_id": "cursor_luna_max",
            "logical_profile_alias": "worker_high",
            "model": profile["exact_model"],
            "effort": profile["reasoning_effort"],
            "provider_source_path": source_path,
            "provider_source_sha256": provider["source_sha256"],
            "provider_profile_pointer": f"{source_path}#/profiles/cursor_luna_max",
            "provider_capability_status": provider["capability_status"],
            "provider_harness_status": provider["harness_status"],
            "provider_full_owner_ready": provider["full_owner_ready"],
            "auth_lane": "cursor_cli_file_credential_store",
            "auth_authority_ref": None,
            "founder_visible": True,
            "owner_authority": "bounded_department_output_to_cdd_only",
            "binding_state": "requires_session_capability_handshake",
            "capability_evidence_ids": [],
            "fallback_behavior": "hold_and_report",
        })
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        manifest["assignments"].append(assignment)
        manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")

    def add_grok_worker_assignment(
        self,
        root: Path,
        manifest_path: Path,
        *,
        founder_visible: bool = False,
    ) -> None:
        registry = yaml.safe_load(
            (root / "automation/harness-provider-profile-registry.yaml").read_text(encoding="utf-8")
        )
        provider = registry["logical_profiles"]["worker_high"]["providers"]["grok"]
        source_path = provider["source_path"]
        source = yaml.safe_load((root / source_path).read_text(encoding="utf-8"))
        profile_id = provider["provider_profile_id"]
        profile = source["profiles"][profile_id]
        runtime_capabilities = {
            "execution_mode": "registered_work_package",
            "filesystem": "host_commit_only_from_validated_dispatch_output_manifest",
            "allowed_write_paths": [],
            "web_search": True,
            "provider_native_subagents": True,
            "memory": True,
            "imagine": False,
            "authority_boundary": "work_package_only_no_external_mutation_or_promotion_without_separate_gate",
        }
        assignment = {
            "assignment_id": "department_worker:REFERENCE-A",
            "studio_role": "department_worker",
            "assignment_key": "REFERENCE-A",
            "provider": "grok",
            "adapter_id": "grok_acp",
            "runtime_surface": "grok_cli_acp_or_tui",
            "profile_id": "reference_research_generalist",
            "execution_profile_id": profile_id,
            "logical_profile_alias": "worker_high",
            "model": profile["exact_model"],
            "effort": profile["reasoning_effort"],
            "provider_source_path": source_path,
            "provider_source_sha256": provider["source_sha256"],
            "provider_profile_pointer": f"{source_path}#/profiles/{profile_id}",
            "provider_capability_status": provider["capability_status"],
            "provider_harness_status": provider["harness_status"],
            "provider_full_owner_ready": provider["full_owner_ready"],
            "auth_lane": "subscription_oauth",
            "auth_authority_ref": None,
            "runtime_capabilities": runtime_capabilities,
            "founder_visible": founder_visible,
            "owner_authority": "bounded_department_output_to_cdd_only",
            "binding_state": "requires_session_capability_handshake",
            "capability_evidence_ids": [],
            "fallback_behavior": "hold_and_report",
        }
        self.finalize_assignment(assignment)
        self.finalize_grok_runtime_policy(assignment)
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        manifest["assignments"].append(assignment)
        manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")

    def mutate_yaml(self, path: Path, callback: Callable[[dict], None]) -> None:
        document = yaml.safe_load(path.read_text(encoding="utf-8"))
        callback(document)
        path.write_text(
            yaml.safe_dump(document, sort_keys=False, allow_unicode=True),
            encoding="utf-8",
        )

    @staticmethod
    def xai_profile_document() -> dict:
        response_contract = {
            "image_encoding": "base64_json",
            "exact_output_count": 1,
            "items_json_pointer": "/data",
            "image_value_json_pointer": "/b64_json",
            "output_url_allowed_hosts": [],
        }
        operation = lambda endpoint, transport, attachment_policy, attachment_field: {
            "endpoint_path": endpoint,
            "transport": transport,
            "attachment_policy": attachment_policy,
            "request_contract": {
                "model_field": "model",
                "prompt_field": "prompt",
                "output_count_field": "n",
                "attachment_field": attachment_field,
                "fixed_fields": {"quality": "fixture"},
            },
            "response_contract": dict(response_contract),
        }
        return {
            "schema_version": "idol-xai-api-media-provider-profiles.v1",
            "status": "active",
            "provider": "xai_api",
            "runtime_surface": "xai_media_api",
            "profile_source_policy": {
                "exact_model_owner": "this_file",
                "exact_endpoint_owner": "this_file",
                "resolved_snapshot_required": True,
                "requested_observed_match_required": True,
                "silent_model_or_auth_fallback": "forbidden",
            },
            "profiles": {
                "xai_fixture_image_current": {
                    "exact_model": "fixture-xai-image-model",
                    "image_adapter_id": "xai_api_media",
                    "auth_lane": "founder_approved_api",
                    "api_version": "fixture-api-v1",
                    "api_base_url": "https://xai-fixture.invalid",
                    "authorization_scheme": "bearer",
                    "capability_status": "active",
                    "harness_status": "active",
                    "default_enabled": False,
                    "automatic_fallback": "none",
                    "unavailable_or_mismatch_action": "hold_and_report",
                    "operations": {
                        "image_gen": operation(
                            "/fixture/v1/images/generations", "json", "forbidden", None
                        ),
                        "image_edit": operation(
                            "/fixture/v1/images/edits",
                            "json_data_url_array",
                            "required_all_ordered",
                            "images",
                        ),
                    },
                }
            },
        }

    def register_xai_fixture(self, root: Path) -> Path:
        source = root / "automation/providers/xai-fixture.json"
        source.write_text(
            json.dumps(self.xai_profile_document(), indent=2) + "\n",
            encoding="utf-8",
        )
        source_sha = hashlib.sha256(source.read_bytes()).hexdigest()
        index = root / "automation/harness-provider-profile-registry.yaml"

        def register(document: dict) -> None:
            document["media_lanes"]["xai_api_media"] = {
                "provider": "xai",
                "auth_lane": "founder_approved_api",
                "capability_status": "active",
                "harness_status": "active",
                "registration_status": "registered_exact",
                "provider_profile_id": "xai_fixture_image_current",
                "provider_profile_source": "automation/providers/xai-fixture.json",
                "provider_profile_source_sha256": source_sha,
                "image_adapter_id": "xai_api_media",
                "image_output_contract": "exact_expected_output_path_sha256_pixel_review",
                "default_enabled": False,
                "selection_only": False,
                "automatic_fallback": "none",
            }

        self.mutate_yaml(index, register)
        return source

    def test_current_registry_and_provider_sources_pass(self) -> None:
        temporary, root = self.fixture()
        self.addCleanup(temporary.cleanup)
        result, payload = self.run_validator(root)
        self.assertEqual(0, result.returncode, result.stderr or result.stdout)
        self.assertEqual("pass", payload["status"])
        self.assertEqual([], payload["errors"])
        self.assertEqual(0, payload["evidence"]["external_or_generative_actions"])
        self.assertEqual(
            [
                "cursor_advisory",
                "cursor_grok_explicit_selected_worker",
                "director_deep",
                "frontier_director",
                "research_medium",
                "worker_high",
            ],
            payload["evidence"]["logical_profiles"],
        )
        self.assertEqual(
            "active",
            payload["evidence"]["grok_nonmedia_readiness"]["profiles"]["director_deep"]["harness_status"],
        )
        self.assertEqual(
            "active",
            payload["evidence"]["grok_nonmedia_readiness"]["profiles"]["worker_high"]["harness_status"],
        )
        self.assertIs(True, payload["evidence"]["grok_nonmedia_readiness"]["full_route_ready"])
        self.assertIs(True, payload["evidence"]["grok_nonmedia_readiness"]["founder_default_switch_review_allowed"])
        self.assertEqual(
            "openai_api_gpt_image_2",
            payload["evidence"]["resolved_media_lanes"]["openai_image_api_current"][
                "image_adapter_id"
            ],
        )
        xai = payload["evidence"]["resolved_media_lanes"]["xai_api_media"]
        self.assertEqual("registration_required", xai["registration_status"])
        self.assertEqual("hold", xai["harness_status"])
        self.assertIs(False, xai["ready"])

    def test_xai_registered_exact_source_resolves_without_network(self) -> None:
        temporary, root = self.fixture()
        self.addCleanup(temporary.cleanup)
        source = self.register_xai_fixture(root)
        result, payload = self.run_validator(root)
        self.assertEqual(0, result.returncode, payload["errors"])
        xai = payload["evidence"]["resolved_media_lanes"]["xai_api_media"]
        self.assertEqual("registered_exact", xai["registration_status"])
        self.assertEqual("fixture-xai-image-model", xai["model"])
        self.assertEqual(hashlib.sha256(source.read_bytes()).hexdigest(), xai["provider_profile_source_sha256"])
        self.assertIs(True, xai["ready"])
        self.assertEqual(0, payload["evidence"]["external_or_generative_actions"])

    def test_xai_registered_exact_stale_source_hash_is_rejected(self) -> None:
        temporary, root = self.fixture()
        self.addCleanup(temporary.cleanup)
        self.register_xai_fixture(root)
        index = root / "automation/harness-provider-profile-registry.yaml"
        self.mutate_yaml(
            index,
            lambda document: document["media_lanes"]["xai_api_media"].update(
                provider_profile_source_sha256="0" * 64
            ),
        )
        result, payload = self.run_validator(root)
        self.assertNotEqual(0, result.returncode)
        self.assertTrue(
            any("registered xAI API media provider source hash is stale" in error for error in payload["errors"])
        )

    def test_xai_legacy_selection_only_cannot_be_current(self) -> None:
        temporary, root = self.fixture()
        self.addCleanup(temporary.cleanup)
        index = root / "automation/harness-provider-profile-registry.yaml"
        self.mutate_yaml(
            index,
            lambda document: document["media_lanes"].update(
                xai_api_media={
                    "provider": "xai",
                    "auth_lane": "founder_approved_api",
                    "default_enabled": False,
                    "selection_only": True,
                    "automatic_fallback": "none",
                }
            ),
        )
        result, payload = self.run_validator(root)
        self.assertNotEqual(0, result.returncode)
        self.assertTrue(
            any("legacy selection-only evidence cannot be the current central lane" in error for error in payload["errors"])
        )

    def test_project_numeric_agent_override_is_rejected(self) -> None:
        temporary, root = self.fixture()
        self.addCleanup(temporary.cleanup)
        config = root / ".codex/config.toml"
        config.write_text(config.read_text(encoding="utf-8") + "\n[agents]\nmax_depth = 1\n", encoding="utf-8")
        result, payload = self.run_validator(root)
        self.assertNotEqual(0, result.returncode)
        self.assertTrue(any("numeric agent overrides" in error for error in payload["errors"]))

    def test_literal_in_central_index_is_rejected(self) -> None:
        temporary, root = self.fixture()
        self.addCleanup(temporary.cleanup)
        index = root / "automation/harness-provider-profile-registry.yaml"
        self.mutate_yaml(
            index,
            lambda document: document["logical_profiles"]["director_deep"]["providers"]["grok"].update(
                exact_model="grok-9.9"
            ),
        )
        result, payload = self.run_validator(root)
        self.assertNotEqual(0, result.returncode)
        self.assertTrue(any("literal-free index" in error for error in payload["errors"]))

    def test_stale_provider_source_hash_is_rejected(self) -> None:
        temporary, root = self.fixture()
        self.addCleanup(temporary.cleanup)
        source = root / "automation/providers/cursor-agent-profiles.yaml"
        source.write_text(source.read_text(encoding="utf-8") + "\n", encoding="utf-8")
        result, payload = self.run_validator(root)
        self.assertNotEqual(0, result.returncode)
        self.assertTrue(any("provider source hash is stale" in error for error in payload["errors"]))
        self.assertTrue(any("cursor provider source hash is stale" in error for error in payload["errors"]))

    def test_cursor_director_profile_cannot_drift_to_luna_max(self) -> None:
        temporary, root = self.fixture()
        self.addCleanup(temporary.cleanup)
        registry = yaml.safe_load(
            (root / "automation/harness-provider-profile-registry.yaml").read_text(
                encoding="utf-8"
            )
        )
        source = root / "automation/providers/cursor-agent-profiles.yaml"
        document = yaml.safe_load(source.read_text(encoding="utf-8"))
        document["profiles"]["cursor_sol_xhigh"]["exact_model"] = "gpt-5.6-luna-max"
        document["profiles"]["cursor_sol_xhigh"]["reasoning_effort"] = "max"
        source.write_text(yaml.safe_dump(document, sort_keys=False), encoding="utf-8")
        source_sha = hashlib.sha256(source.read_bytes()).hexdigest()
        registry["logical_profiles"]["director_deep"]["providers"]["cursor"]["source_sha256"] = source_sha
        registry["logical_profiles"]["worker_high"]["providers"]["cursor"]["source_sha256"] = source_sha
        registry["logical_profiles"]["cursor_advisory"]["providers"]["cursor"]["source_sha256"] = source_sha
        registry["media_lanes"]["cursor_luna_optional_image"]["provider_profile_source_sha256"] = source_sha
        (root / "automation/harness-provider-profile-registry.yaml").write_text(
            yaml.safe_dump(registry, sort_keys=False), encoding="utf-8"
        )
        result, payload = self.run_validator(root)
        self.assertNotEqual(0, result.returncode)
        self.assertTrue(
            any("director_deep.cursor exact model must be gpt-5.6-sol-xhigh" in error for error in payload["errors"]),
            payload["errors"],
        )

    def test_cursor_worker_profile_cannot_drift_to_sol_xhigh(self) -> None:
        temporary, root = self.fixture()
        self.addCleanup(temporary.cleanup)
        registry = yaml.safe_load(
            (root / "automation/harness-provider-profile-registry.yaml").read_text(
                encoding="utf-8"
            )
        )
        source = root / "automation/providers/cursor-agent-profiles.yaml"
        document = yaml.safe_load(source.read_text(encoding="utf-8"))
        document["profiles"]["cursor_luna_max"]["exact_model"] = "gpt-5.6-sol-xhigh"
        document["profiles"]["cursor_luna_max"]["reasoning_effort"] = "xhigh"
        source.write_text(yaml.safe_dump(document, sort_keys=False), encoding="utf-8")
        source_sha = hashlib.sha256(source.read_bytes()).hexdigest()
        registry["logical_profiles"]["director_deep"]["providers"]["cursor"]["source_sha256"] = source_sha
        registry["logical_profiles"]["worker_high"]["providers"]["cursor"]["source_sha256"] = source_sha
        registry["logical_profiles"]["cursor_advisory"]["providers"]["cursor"]["source_sha256"] = source_sha
        registry["media_lanes"]["cursor_luna_optional_image"]["provider_profile_source_sha256"] = source_sha
        (root / "automation/harness-provider-profile-registry.yaml").write_text(
            yaml.safe_dump(registry, sort_keys=False), encoding="utf-8"
        )
        result, payload = self.run_validator(root)
        self.assertNotEqual(0, result.returncode)
        self.assertTrue(
            any("worker_high.cursor exact model must be gpt-5.6-luna-max" in error for error in payload["errors"]),
            payload["errors"],
        )

    def test_sol_max_profiles_remain_bounded_not_production_directors(self) -> None:
        temporary, root = self.fixture()
        self.addCleanup(temporary.cleanup)
        expected = {
            "idol-sol-primary-validation.toml": "cannot become a second Founder-facing director",
            "idol-sol-bounded-synthesis.toml": "make a final production verdict",
        }
        for filename, boundary_text in expected.items():
            profile = tomllib.loads(
                (root / ".codex/agents" / filename).read_text(encoding="utf-8")
            )
            self.assertEqual("gpt-5.6-sol", profile["model"])
            self.assertEqual("max", profile["model_reasoning_effort"])
            self.assertIn(boundary_text, profile["developer_instructions"])

    def test_grok_profiles_cannot_drift_to_another_shared_build(self) -> None:
        temporary, root = self.fixture()
        self.addCleanup(temporary.cleanup)
        source_path = root / "automation/providers/grok-build-profiles.yaml"
        self.mutate_yaml(
            source_path,
            lambda document: [
                row.update(exact_model="grok-4.7")
                for row in document["profiles"].values()
            ],
        )
        source_sha = hashlib.sha256(source_path.read_bytes()).hexdigest()
        registry_path = root / "automation/harness-provider-profile-registry.yaml"

        def refresh_registry(document: dict) -> None:
            for alias in ("director_deep", "worker_high"):
                document["logical_profiles"][alias]["providers"]["grok"][
                    "source_sha256"
                ] = source_sha
            document["media_lanes"]["grok_build_oauth_subscription"][
                "provider_profile_source_sha256"
            ] = source_sha

        self.mutate_yaml(registry_path, refresh_registry)
        result, payload = self.run_validator(root)
        self.assertNotEqual(0, result.returncode)
        self.assertTrue(
            any("grok exact_model must be 'grok-4.6'" in error for error in payload["errors"]),
            payload["errors"],
        )

    def test_grok_worker_and_shared_director_profiles_are_ready_after_bound_successor_receipt(self) -> None:
        registry = yaml.safe_load(
            (ROOT / "automation/harness-provider-profile-registry.yaml").read_text(encoding="utf-8")
        )
        director = registry["logical_profiles"]["director_deep"]["providers"]["grok"]
        worker = registry["logical_profiles"]["worker_high"]["providers"]["grok"]
        self.assertEqual("active", director["harness_status"])
        self.assertIs(True, director["full_owner_ready"])
        self.assertEqual("active", worker["harness_status"])
        self.assertIs(True, worker["full_owner_ready"])
        self.assertEqual("hold_without_cross_provider_fallback", registry["selection_policy"]["preferred_provider_unavailable_action"])

    def test_current_session_media_defaults_are_provider_specific_and_grok_video_is_registered_active(self) -> None:
        registry = yaml.safe_load(
            (ROOT / "automation/harness-provider-profile-registry.yaml").read_text(encoding="utf-8")
        )
        grok = registry["media_lanes"]["grok_build_oauth_subscription"]
        policy = registry["selection_policy"]
        self.assertNotIn("codex_session_native", registry["media_lanes"])
        self.assertEqual(["image_edit", "image_gen"], grok["image_tools"])
        self.assertEqual("active", grok["image_harness_status"])
        self.assertEqual("active", grok["video_harness_status"])
        self.assertEqual("grok_build_video", grok["video_adapter_id"])
        self.assertEqual(
            "exact_expected_output_path_sha256_playback_review",
            grok["video_output_contract"],
        )
        self.assertTrue(grok["video_runtime_inventory_or_adapter_match_required"])
        self.assertTrue(grok["video_founder_external_generation_authority_required"])
        self.assertEqual("current_session_native", policy["provider_omitted_image_request"])
        self.assertEqual("forbidden", policy["cross_provider_tool_or_auth_aliasing"])
        self.assertTrue(policy["explicit_api_selection_required"])

    def test_grok_video_lane_rejects_status_or_readiness_receipt_drift(self) -> None:
        temporary, root = self.fixture()
        self.addCleanup(temporary.cleanup)
        index = root / "automation/harness-provider-profile-registry.yaml"
        self.mutate_yaml(
            index,
            lambda document: document["media_lanes"]["grok_build_oauth_subscription"].update(
                video_harness_status="migration_pending"
            ),
        )
        result, payload = self.run_validator(root)
        self.assertNotEqual(0, result.returncode)
        self.assertTrue(any("video_harness_status" in error or "literal-free index" in error for error in payload["errors"]))

        temporary_two, root_two = self.fixture()
        self.addCleanup(temporary_two.cleanup)
        source = root_two / "automation/providers/grok-build-profiles.yaml"
        self.mutate_yaml(
            source,
            lambda document: document["media_activation_evidence"]["video_subscription_cli"].update(
                generation_calls=1
            ),
        )
        source_sha = hashlib.sha256(source.read_bytes()).hexdigest()
        index_two = root_two / "automation/harness-provider-profile-registry.yaml"

        def refresh_grok_source(document: dict) -> None:
            for alias in ("director_deep", "worker_high"):
                document["logical_profiles"][alias]["providers"]["grok"]["source_sha256"] = source_sha
            document["media_lanes"]["grok_build_oauth_subscription"][
                "provider_profile_source_sha256"
            ] = source_sha

        self.mutate_yaml(
            index_two,
            refresh_grok_source,
        )
        result, payload = self.run_validator(root_two)
        self.assertNotEqual(0, result.returncode)
        self.assertTrue(any("generation_calls" in error for error in payload["errors"]))

    def test_legacy_codex_native_media_source_is_not_active(self) -> None:
        temporary, root = self.fixture()
        self.addCleanup(temporary.cleanup)
        result, payload = self.run_validator(root)
        self.assertEqual(0, result.returncode, payload["errors"])
        registry = yaml.safe_load(
            (root / "automation/harness-provider-profile-registry.yaml").read_text(encoding="utf-8")
        )
        self.assertNotIn("codex_session_native", registry["media_lanes"])

    def test_cross_provider_tool_aliasing_policy_is_rejected(self) -> None:
        temporary, root = self.fixture()
        self.addCleanup(temporary.cleanup)
        index = root / "automation/harness-provider-profile-registry.yaml"
        self.mutate_yaml(
            index,
            lambda document: document["selection_policy"].update(
                cross_provider_tool_or_auth_aliasing="allowed"
            ),
        )
        result, payload = self.run_validator(root)
        self.assertNotEqual(0, result.returncode)
        self.assertTrue(any("cross_provider_tool_or_auth_aliasing" in error for error in payload["errors"]))

    def test_preferred_grok_director_cannot_enable_cross_provider_fallback(self) -> None:
        temporary, root = self.fixture()
        self.addCleanup(temporary.cleanup)
        index = root / "automation/harness-provider-profile-registry.yaml"
        self.mutate_yaml(
            index,
            lambda document: document["selection_policy"].update(
                preferred_provider_unavailable_action="fallback_to_codex"
            ),
        )
        result, payload = self.run_validator(root)
        self.assertNotEqual(0, result.returncode)
        self.assertTrue(any("hold_without_cross_provider_fallback" in error for error in payload["errors"]))

    def test_grok_worker_activation_rejects_stale_bound_evidence(self) -> None:
        temporary, root = self.fixture()
        self.addCleanup(temporary.cleanup)
        source = root / "automation/providers/grok-build-profiles.yaml"
        self.mutate_yaml(
            source,
            lambda document: document["nonmedia_activation_evidence"]["evidence_refs"][
                "cdd_session_router_isolated_test"
            ].update(sha256="0" * 64),
        )
        source_sha = hashlib.sha256(source.read_bytes()).hexdigest()
        index = root / "automation/harness-provider-profile-registry.yaml"

        def refresh_index(document: dict) -> None:
            for alias in ("director_deep", "worker_high"):
                document["logical_profiles"][alias]["providers"]["grok"]["source_sha256"] = source_sha
            document["media_lanes"]["grok_build_oauth_subscription"][
                "provider_profile_source_sha256"
            ] = source_sha

        self.mutate_yaml(index, refresh_index)
        result, payload = self.run_validator(root)
        self.assertNotEqual(0, result.returncode)
        self.assertTrue(any("cdd_session_router_isolated_test hash is stale" in error for error in payload["errors"]))

    def test_grok_director_cannot_activate_before_successor_parity(self) -> None:
        temporary, root = self.fixture()
        self.addCleanup(temporary.cleanup)
        source = root / "automation/providers/grok-build-profiles.yaml"

        def remove_live_successor_evidence(document: dict) -> None:
            document["nonmedia_activation_evidence"]["director_successor_live_evidence"].update(
                status="required_missing",
                sha256=None,
            )

        self.mutate_yaml(source, remove_live_successor_evidence)
        (root / (
            "development/front-planning-workbench/docs/evidence/"
            "grok-1.0.3-cdd-direct-session-router-receipt-2026-08-17.json"
        )).unlink()
        source_sha = hashlib.sha256(source.read_bytes()).hexdigest()
        index = root / "automation/harness-provider-profile-registry.yaml"

        def refresh_index(document: dict) -> None:
            director = document["logical_profiles"]["director_deep"]["providers"]["grok"]
            director.update(
                source_sha256=source_sha,
                harness_status="active",
                full_owner_ready=True,
            )
            document["logical_profiles"]["worker_high"]["providers"]["grok"][
                "source_sha256"
            ] = source_sha
            document["media_lanes"]["grok_build_oauth_subscription"][
                "provider_profile_source_sha256"
            ] = source_sha

        self.mutate_yaml(index, refresh_index)
        result, payload = self.run_validator(root)
        self.assertNotEqual(0, result.returncode)
        self.assertTrue(any("director_deep.grok profile harness_status must be 'migration_pending'" in error for error in payload["errors"]))
        self.assertTrue(any("director_deep.grok profile full_owner_ready must be False" in error for error in payload["errors"]))

    def test_unbound_grok_director_successor_receipt_is_rejected(self) -> None:
        temporary, root = self.fixture()
        self.addCleanup(temporary.cleanup)
        source = root / "automation/providers/grok-build-profiles.yaml"

        def unbind_receipt(document: dict) -> None:
            document["nonmedia_activation_evidence"]["director_successor_live_evidence"].update(
                status="required_missing",
                sha256=None,
            )

        self.mutate_yaml(source, unbind_receipt)
        source_sha = hashlib.sha256(source.read_bytes()).hexdigest()
        registry = root / "automation/harness-provider-profile-registry.yaml"

        def refresh_registry(document: dict) -> None:
            for alias in ("director_deep", "worker_high"):
                document["logical_profiles"][alias]["providers"]["grok"]["source_sha256"] = source_sha
            document["media_lanes"]["grok_build_oauth_subscription"]["provider_profile_source_sha256"] = source_sha

        self.mutate_yaml(registry, refresh_registry)
        result, payload = self.run_validator(root)
        self.assertNotEqual(0, result.returncode)
        self.assertTrue(any("receipt exists but is not hash-bound as present" in error for error in payload["errors"]))

    def test_grok_director_router_receipt_accepts_completed_goal_as_admission_only(self) -> None:
        temporary, root = self.fixture()
        self.addCleanup(temporary.cleanup)
        self.install_grok_director_router_receipt(root)
        result, payload = self.run_validator(root)
        self.assertEqual(0, result.returncode, payload["errors"])
        self.assertEqual([], payload["errors"])

    def test_grok_director_router_receipt_rejects_impossible_active_goal_terminal(self) -> None:
        temporary, root = self.fixture()
        self.addCleanup(temporary.cleanup)
        self.install_grok_director_router_receipt(
            root,
            goal_terminal_state="active",
            goal_last_event="goal_active",
        )
        result, payload = self.run_validator(root)
        self.assertNotEqual(0, result.returncode)
        self.assertTrue(
            any("goal_admission.goal_terminal_state must be 'complete'" in error for error in payload["errors"]),
            payload["errors"],
        )

    def test_openai_provider_source_hash_drift_is_rejected(self) -> None:
        temporary, root = self.fixture()
        self.addCleanup(temporary.cleanup)
        source = root / "automation/providers/openai-image-profiles.yaml"
        source.write_text(source.read_text(encoding="utf-8") + "\n", encoding="utf-8")
        result, payload = self.run_validator(root)
        self.assertNotEqual(0, result.returncode)
        self.assertTrue(
            any("OpenAI image provider source hash is stale" in error for error in payload["errors"])
        )

    def test_edit_director_cannot_resolve_to_worker_profile(self) -> None:
        temporary, root = self.fixture()
        self.addCleanup(temporary.cleanup)
        index = root / "automation/harness-provider-profile-registry.yaml"

        def mutate(document: dict) -> None:
            document["logical_profiles"]["director_deep"]["providers"]["cursor"][
                "provider_profile_id"
            ] = "cursor_luna_max"

        self.mutate_yaml(index, mutate)
        result, payload = self.run_validator(root)
        self.assertNotEqual(0, result.returncode)
        self.assertTrue(
            any("director_deep.cursor provider profile drifted" in error for error in payload["errors"]),
            payload["errors"],
        )

    def test_run_route_manifest_exact_provider_snapshot_passes_without_actions(self) -> None:
        temporary, root = self.fixture()
        self.addCleanup(temporary.cleanup)
        manifest = self.write_run_route_manifest(root)
        result, payload = self.run_validator(root, manifest)
        self.assertEqual(0, result.returncode, payload["errors"])
        evidence = payload["evidence"]["run_route_manifest"]
        self.assertEqual(hashlib.sha256(manifest.read_bytes()).hexdigest(), evidence["sha256"])
        self.assertEqual(3, len(evidence["assignments"]))
        self.assertEqual(0, payload["evidence"]["external_or_generative_actions"])

    def test_active_grok_worker_run_route_is_exact_and_no_fallback(self) -> None:
        temporary, root = self.fixture()
        self.addCleanup(temporary.cleanup)
        manifest = self.write_run_route_manifest(root)
        self.add_grok_worker_assignment(root, manifest)
        result, payload = self.run_validator(root, manifest)
        self.assertEqual(0, result.returncode, payload["errors"])
        worker = next(
            row
            for row in payload["evidence"]["run_route_manifest"]["assignments"]
            if row["assignment_id"] == "department_worker:REFERENCE-A"
        )
        self.assertEqual("grok", worker["provider"])
        self.assertEqual("worker_high", worker["logical_profile_alias"])
        self.assertEqual("active", worker["harness_status"])
        self.assertIs(True, worker["full_owner_ready"])
        self.assertEqual(0, payload["evidence"]["external_or_generative_actions"])

    def test_founder_visible_physical_cursor_worker_resolves_to_luna_max(self) -> None:
        temporary, root = self.fixture()
        self.addCleanup(temporary.cleanup)
        manifest = self.write_run_route_manifest(root)
        self.add_cursor_worker_assignment(root, manifest)
        result, payload = self.run_validator(root, manifest)
        self.assertEqual(0, result.returncode, payload["errors"])
        worker = next(
            row
            for row in payload["evidence"]["run_route_manifest"]["assignments"]
            if row["assignment_id"] == "department_worker:PHYSICAL-REFERENCE-A"
        )
        self.assertEqual("cursor", worker["provider"])
        self.assertEqual("worker_high", worker["logical_profile_alias"])
        self.assertEqual("gpt-5.6-luna-max", worker["model"])
        self.assertEqual("max", worker["effort"])
        document = json.loads(manifest.read_text(encoding="utf-8"))
        assignment = next(
            row
            for row in document["assignments"]
            if row["assignment_id"] == "department_worker:PHYSICAL-REFERENCE-A"
        )
        self.assertIs(True, assignment["founder_visible"])
        self.assertEqual("hold_and_report", assignment["fallback_behavior"])

    def test_founder_visible_physical_grok_worker_resolves_to_46_xhigh(self) -> None:
        temporary, root = self.fixture()
        self.addCleanup(temporary.cleanup)
        manifest = self.write_run_route_manifest(root)
        self.add_grok_worker_assignment(root, manifest, founder_visible=True)
        result, payload = self.run_validator(root, manifest)
        self.assertEqual(0, result.returncode, payload["errors"])
        worker = next(
            row
            for row in payload["evidence"]["run_route_manifest"]["assignments"]
            if row["assignment_id"] == "department_worker:REFERENCE-A"
        )
        self.assertEqual("grok-4.6", worker["model"])
        self.assertEqual("xhigh", worker["effort"])

    def test_worker_high_supports_department_worker_without_changing_medium_or_cursor_luna(self) -> None:
        temporary, root = self.fixture()
        self.addCleanup(temporary.cleanup)
        registry = yaml.safe_load(
            (root / "automation/harness-provider-profile-registry.yaml").read_text(encoding="utf-8")
        )
        grok = yaml.safe_load(
            (root / "automation/providers/grok-build-profiles.yaml").read_text(encoding="utf-8")
        )
        cursor = yaml.safe_load(
            (root / "automation/providers/cursor-agent-profiles.yaml").read_text(encoding="utf-8")
        )
        self.assertEqual(
            ["worker", "department_worker", "mechanical_coordinator", "section_image_motion_worker"],
            registry["logical_profiles"]["worker_high"]["eligible_logical_roles"],
        )
        self.assertEqual(
            ["worker", "department_worker", "mechanical_coordinator", "section_image_motion_worker"],
            grok["profiles"]["grok_worker_high"]["eligible_logical_roles"],
        )
        self.assertEqual(
            ["research_worker", "department_worker"],
            registry["logical_profiles"]["research_medium"]["eligible_logical_roles"],
        )
        self.assertEqual(
            ["research_worker", "department_worker"],
            grok["profiles"]["grok_worker_medium"]["eligible_logical_roles"],
        )
        self.assertEqual("grok-4.6", grok["profiles"]["grok_worker_high"]["exact_model"])
        self.assertEqual("xhigh", grok["profiles"]["grok_worker_high"]["reasoning_effort"])
        self.assertEqual("medium", grok["profiles"]["grok_worker_medium"]["reasoning_effort"])
        self.assertIs(True, grok["profiles"]["grok_worker_high"]["full_owner_ready"])
        self.assertIs(False, grok["profiles"]["grok_worker_medium"]["full_owner_ready"])
        self.assertEqual("hold", grok["profiles"]["grok_worker_medium"]["harness_status"])
        self.assertNotIn(
            "department_worker",
            cursor["profiles"]["cursor_luna_max"]["eligible_logical_roles"],
        )
        result, payload = self.run_validator(root)
        self.assertEqual(0, result.returncode, payload["errors"])

    def test_grok_worker_runtime_policy_key_drift_is_rejected(self) -> None:
        temporary, root = self.fixture()
        self.addCleanup(temporary.cleanup)
        manifest = self.write_run_route_manifest(root)
        self.add_grok_worker_assignment(root, manifest)
        document = json.loads(manifest.read_text(encoding="utf-8"))
        worker = next(
            row for row in document["assignments"]
            if row["assignment_id"] == "department_worker:REFERENCE-A"
        )
        worker["runtime_policy_key"] = "0" * 64
        manifest.write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")
        result, payload = self.run_validator(root, manifest)
        self.assertNotEqual(0, result.returncode)
        self.assertTrue(any("Grok runtime policy key is stale or inexact" in error for error in payload["errors"]))

    def test_run_route_manifest_model_drift_is_rejected(self) -> None:
        temporary, root = self.fixture()
        self.addCleanup(temporary.cleanup)
        manifest = self.write_run_route_manifest(root)
        document = json.loads(manifest.read_text(encoding="utf-8"))
        document["assignments"][0]["model"] = "stale-provider-model"
        manifest.write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")
        result, payload = self.run_validator(root, manifest)
        self.assertNotEqual(0, result.returncode)
        self.assertTrue(any("model differs from the exact provider source" in error for error in payload["errors"]))

    def test_run_route_manifest_readiness_or_process_key_drift_is_rejected(self) -> None:
        temporary, root = self.fixture()
        self.addCleanup(temporary.cleanup)
        manifest = self.write_run_route_manifest(root)
        document = json.loads(manifest.read_text(encoding="utf-8"))
        document["assignments"][0]["provider_source_readiness"]["evidence_sha256"] = "0" * 64
        document["assignments"][1]["immutable_profile_key"] = "1" * 64
        manifest.write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")
        result, payload = self.run_validator(root, manifest)
        self.assertNotEqual(0, result.returncode)
        self.assertTrue(any("provider source readiness evidence is stale or inexact" in error for error in payload["errors"]))
        self.assertTrue(any("immutable profile key is stale or inexact" in error for error in payload["errors"]))

    def test_run_route_manifest_auth_lane_drift_is_rejected(self) -> None:
        temporary, root = self.fixture()
        self.addCleanup(temporary.cleanup)
        manifest = self.write_run_route_manifest(root)
        document = json.loads(manifest.read_text(encoding="utf-8"))
        document["assignments"][0]["auth_lane"] = "founder_approved_existing_xai_api_key"
        document["assignments"][0]["auth_authority_ref"] = None
        manifest.write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")
        result, payload = self.run_validator(root, manifest)
        self.assertNotEqual(0, result.returncode)
        self.assertTrue(any("Cursor auth lane is not exact" in error for error in payload["errors"]))

    def test_run_route_manifest_stale_skill_registry_hash_is_rejected(self) -> None:
        temporary, root = self.fixture()
        self.addCleanup(temporary.cleanup)
        manifest = self.write_run_route_manifest(root)
        document = json.loads(manifest.read_text(encoding="utf-8"))
        document["profile_compatibility"]["registry_sha256"] = "0" * 64
        manifest.write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")
        result, payload = self.run_validator(root, manifest)
        self.assertNotEqual(0, result.returncode)
        self.assertTrue(any("skill-load profile registry hash is stale" in error for error in payload["errors"]))


if __name__ == "__main__":
    unittest.main()
