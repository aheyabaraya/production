# Schema, semantic, readiness, and release validators

Machine source: `automation/idol-script-registry.yaml`.

Select the validator matching the active schema/stage, pass the exact artifact path, and treat PASS as structural evidence only. A validator failure is a hold; it is not a creative rewrite instruction.

Authority boundary: Validators check structure, provenance, hashes, paths, and declared gates. Creative adequacy and Founder decisions remain human/model-owned.

Route: select active schema/validator → validate exact artifact → inspect structural result → return creative judgment to the owner.

## Registered scripts

- `scripts/idol_employer_boundary_guard.py` — status: `active`; authority: `mechanical_default`. Fail-closed local boundary guard; it does not grant external authority.
- `scripts/idol_weekly_report_reference_extract.py` — status: `active`; authority: `mechanical_default`.
- `scripts/validate_01_section_direction.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/validate_02b_imagegen_contract.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/validate_cue_bpm_map.rb` — status: `historical`; authority: `historical_evidence_only`.
- `scripts/validate_founder_intervention_receipt.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/validate_founder_sequence_control.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/validate_checkpoint_closure_catalog.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/validate_standing_constraint_catalog.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/validate_helper_consumption_receipt.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/validate_front_planning_sequence_core_hold.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/validate_front_planning_local_pairwise_global.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/validate_run_followup_sidecar.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/validate_front_planning_readiness.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/validate_sequence_motion_analysis.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/validate_generated_branch_cut_review.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/validate_graph_director_lineage.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/validate_graph_runtime_projection.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/validate_graph_section_cohort_map.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/validate_graph_contextual_judgment.rb` — status: `active`; authority: `mechanical_default`. Validates the exact checkpoint profile, 0--4 range, prose fields, source hashes, hard-gate precedence, and next edge; it never authors a grade or creative PASS.
- `scripts/validate_graph_judgment_profile_promotion.rb` — status: `active`; authority: `mechanical_default`. Validates one immutable bootstrap seed or a complete proposal-to-Founder-approval pointer-promotion chain; validation never changes the current pointer.
- `scripts/validate_planning_contextual_grade_vector.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/validate_03v_contextual_grade_vector.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/validate_idol_model_routing_agents.py` — status: `active`; authority: `mechanical_default`.
- `scripts/validate_harness_provider_profiles.py` — status: `active`; authority: `mechanical_default`.
- `scripts/validate_harness_assignment_model_routing.py` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_cursor_assignment_adapter.py` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_cursor_model_guard.py` — status: `active`; authority: `mechanical_default`.
- `scripts/validate_local_image_upscale_receipt.py` — status: `active`; authority: `mechanical_default`.
- `scripts/validate_luna_section_lifecycle_receipt.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/validate_master_storyboard.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/validate_schema_repair_candidate.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/validate_selected_audio_analysis.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/validate_skill_application_receipt.rb` — status: `historical`; authority: `historical_evidence_only`.
- `scripts/validate_terra_section_lifecycle_receipt.rb` — status: `historical`; authority: `historical_evidence_only`.
- `scripts/validate_wardrobe_style_review.rb` — status: `historical`; authority: `historical_evidence_only`.

For profiled work, use this guide and the exact dispatch only. Open the full
[`INDEX.md`](../INDEX.md) only for maintenance, rerouting, or unprofiled discovery.
