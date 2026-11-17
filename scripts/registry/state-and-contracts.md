# Graph Engineering state, startup admission, queues, dispatch, and contract routing

Machine source: `automation/idol-script-registry.yaml`.

Read the machine registry and this guide before state, queue, dispatch, startup, or contract work. Run the narrow validator first; preserve exact run paths, hashes, ownership, and Founder gates.

Authority boundary: These scripts validate or transport declared state. They never author creative truth, infer Founder approval, or widen a stage scope.

Route: startup/state → selected profile/contract → exact validator → report or HOLD. Keep path, SHA-256, owner, scope, and Founder gates explicit.

## Registered scripts

- `scripts/idol_graph_production_review.rb` — status: `active`; authority: `mechanical_default`. Projects exact returned-work review inputs and verifies independently returned Director review bytes; no creative decision is authored.

- `scripts/idol_artifact_integrity.py` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_creative_truth_guard.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_concurrency_migration.py` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_director_dispatch_index.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_department_transport_refresh.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_founder_direct_update_commit.rb` — status: `active`; authority: `founder_decision_transport`.
- `scripts/idol_founder_pass_harness.rb` — status: `active`; authority: `founder_decision_transport`.
- `scripts/idol_graph_director_session_router.rb` — status: `active`; authority: `mechanical_default`. Models only Graph-v2 lane-local Director primary/successor shadow readiness, typed-core Goal evidence, state-SHA/generation CAS, and rollback while returning `HOLD`; it grants no provider, prompt, review, canonical-write, Founder-conversation, promotion, or execution authority.
- `scripts/idol_graph_projector.rb` — status: `active`; authority: `mechanical_default`. Projects the six shadow Graph views from a hash-bound ledger; never a canonical writer.
- `scripts/idol_graph_run_controller.rb` — status: `active`; authority: `mechanical_default`. Reads hash-bound current-next/DDI/stage/judgment state and emits one stdout-only dry-run decision, plus a same-stage cohort frontier only when every current head is covered by an exact typed join dependency. It unions creative-stage and paid/download/capture/upload/external/destructive/release authority requirements, but every material receipt remains shadow-missing until a typed DDI producer exists. It never schedules or launches a provider, creates a Goal, writes state, authors a score, grants authority, or promotes work.
- `scripts/idol_harness_action_queue.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_harness_apply_founder_decision.rb` — status: `active`; authority: `founder_decision_transport`.
- `scripts/idol_harness_context_pack.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_department_context.rb` — status: `active`; authority: `mechanical_default`. Freezes and validates explicit Department Pack transport; it does not create a Goal, author creative truth, or grant review/promotion.
- `scripts/idol_role_context_pack.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_harness_current_next.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_harness_expert_gate.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_harness_founder_gate_packet.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_harness_frontier_check.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_harness_next_unit.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_harness_optimization_acceptance.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_harness_record_founder_decision.rb` — status: `active`; authority: `founder_decision_transport`.
- `scripts/idol_harness_refresh.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_harness_run_inventory.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_mv_git_worktree.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_harness_sections.rb` — status: `historical`; authority: `historical_evidence_only`.
- `scripts/idol_harness_shadow_eval.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_harness_stage.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_harness_state_check.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_instruction_surface_audit.py` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_local_image_upscale.py` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_low_source_first_rebuild_plan.py` — status: `one_off`; authority: `one_off_measurement_only`.
- `scripts/idol_run_layout.py` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_script_registry_check.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_skill_contract_check.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_skill_contract_matrix.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_startup_admission.rb` — status: `active`; authority: `startup_admission_transport_only`.
- `scripts/idol_video_source_intake.py` — status: `active`; authority: `mechanical_default`.
- `scripts/validate_department_dispatch.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/validate_company_ops_idol_bridge.rb` — status: `active`; authority: `mechanical_default`. Fail-closed Company Ops grok-build ingress to IDOL Dispatch, Goal, and Role Context Pack.
- `scripts/validate_harness_artifact_contract.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/validate_harness_artifact_routing.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/validate_harness_context_pack.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/validate_harness_contract_version_registry.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/validate_harness_skill_load_profiles.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/validate_harness_surface_version_registry.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/validate_session_helper_operating_lock.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/validate_json_schema.py` — status: `active`; authority: `mechanical_default`.
- `scripts/validate_terminology_guard.rb` — status: `active`; authority: `mechanical_default`.

For profiled work, use this guide and the exact dispatch only. Open the full
[`INDEX.md`](../INDEX.md) only for maintenance, rerouting, or unprofiled discovery.

The controller is a shadow planner, not an executor. Its five outcomes are
`dispatch_or_resume_model`, `await_director_review`,
`route_bounded_correction`, `await_founder_decision`, and `hold`.
Persisting its event intent or invoking a provider requires a separately
registered writer/executor and the relevant authority. A multi-head frontier
is only a shadow representation of mutually disjoint section cohorts at one
stage; it is never a launch instruction. The Graph Director router is separate
from the historical CDD router and remains `HOLD` even with a verified switch
receipt until typed transition receipts and a freshness-enforcing execution
consumer are registered. Never share old/new state or writers.
