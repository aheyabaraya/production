# Runtime launchers and shared deterministic libraries

Machine source: `automation/idol-script-registry.yaml`.

Load shared libraries through their owning command; use the canonical media launcher for audio/video/schema work and preserve the library's path/hash contracts.

Authority boundary: Libraries are not standalone creative authorities and do not become a new route merely because they are importable.

Route: canonical launcher/shared library → exact path/hash contract → owning command; library code has no standalone creative authority.

## Registered scripts

- `scripts/lib/idol_graph_production_review_contract.rb` — status: `active`; authority: `mechanical_default`. Checks production review projection, independent Director execution and exact returned review output.

- `scripts/lib/idol_graph_criterion_evidence_contract.rb` — status: `active`; authority: `mechanical_default`. Resolves declared criterion sources, exact structured rows and per-Cut image coverage.

- `scripts/idol-edit-desk` — status: `active`; authority: `mechanical_default`.
- `scripts/idol-video-python` — status: `active`; authority: `mechanical_default`.
- `scripts/lib/idol_02a_storyboard_contract.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/lib/idol_03v_language_contract.rb` — status: `historical`; authority: `historical_evidence_only`.
- `scripts/lib/idol_03v_source_discovery.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/lib/idol_api_video_quality.py` — status: `active`; authority: `mechanical_default`.
- `scripts/lib/idol_artifact_integrity.py` — status: `active`; authority: `mechanical_default`.
- `scripts/lib/idol_artifact_integrity.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/lib/idol_camera_direction_contract.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/lib/idol_checkpoint_closure_catalog.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/lib/idol_front_planning_local_pairwise_global.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/lib/idol_front_planning_sequence_core_hold.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/lib/idol_generated_review_post_pass.rb` — status: `active`; authority: `mechanical_default`. Shared status/upscale/eligibility transition used by distinct Founder all-PASS and G2-delegated CDD paths; each caller supplies its exact admissible pending status and no creative verdict is inferred.
- `scripts/lib/idol_current_next_v2.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/lib/idol_direction_projection_contract.rb` — status: `historical`; authority: `historical_evidence_only`.
- `scripts/lib/idol_edit_effect_registry.py` — status: `active`; authority: `mechanical_default`.
- `scripts/lib/idol_handoff_keys.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/lib/idol_helper_consumption_receipts.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/lib/idol_image_execution_lane_contract.rb` — status: `active`; authority: `mechanical_default`. Resolves provider-omitted image work only to the exact current session's registered native surface, binds Codex `imagegen` separately from Grok `image_gen`/`image_edit`, and rejects cross-provider tool/auth aliases or fallback.
- `scripts/lib/idol_grok_video_execution_package.rb` — status: `active`; authority: `mechanical_default`. Revalidates the exact Grok video provider snapshot, selects only the one passed Production Cut or exact Founder-ordered two-to-three reference set, and can materialize a hash-bound local operator package without calling the provider or granting generation/playback authority.
- `scripts/lib/idol_platform_credentials.py` — status: `active`; authority: `mechanical_default`.
- `scripts/lib/idol_prompt_presence_contract.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/lib/idol_production_cut_review_contract.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/lib/idol_reference_interpretation_contract.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/lib/idol_reference_evaluation_contract.rb` — status: `active`; authority: `mechanical_default`. Completeness and exact evidence binding for reference-evaluation cases. JSON Schema is the structural validator; this overlay adds containment, Sequence cadence, provenance, path identity, and drift only. Humans or assigned models author observations. Mechanical completeness is not production PASS.
- `scripts/lib/idol_graph_goal_evidence_contract.rb` — status: `active`; authority: `mechanical_default`. Verifies that Graph Dispatch and Director lineage point to persisted provider-native terminal Goal-event bytes whose path, SHA-256, provider, Goal id, objective digest, event, and terminal state exact-match the declared evidence. Active promotion accepts only provider-native evidence; declared synthetic bytes are limited to historical audit or the exact `scripts/tests/fixtures/` boundary, and every validator result identifies its mode without granting promotion authority.
- `scripts/lib/idol_graph_judgment_profile_promotion_contract.rb` — status: `active`; authority: `mechanical_default`. Verifies the immutable seven-profile bootstrap seed set or an exact old/new pointer change backed by phase-specific typed proposal, representative shadow comparison, Founder-selected real-song pilot, independent Director review, and Founder-authored approval bytes. It rejects generic evidence pointers and cannot tune a profile, move a pointer, grant execution, or authorize the Graph default switch.
- `scripts/lib/idol_graph_output_manifest_contract.rb` — status: `active`; authority: `mechanical_default`. Exact-binds a returned Graph manifest to the dispatch-declared output kind and path set.
- `scripts/lib/idol_graph_provider_binding_contract.rb` — status: `active`; authority: `mechanical_default`. Exact-binds Graph logical tiers to current provider-profile bytes without fallback.
- `scripts/lib/idol_graph_run_controller.rb` — status: `active`; authority: `mechanical_default`. Reduces already-validated graph/legacy migration evidence into a read-only shadow decision set. Multi-head state requires exact typed join dependencies even when only one action is ready, and creative plus material authority requirements are kept as a union. It never launches a provider, grants execution authority, consumes a material receipt, or promotes creative truth.
- `scripts/lib/idol_reference_role_plan_contract.rb` — status: `active`; authority: `mechanical_default`. Verifies four-role attachment coverage and FP function/path/hash/section lineage without judging creative quality.
- `scripts/lib/idol_department_context.rb` — status: `active`; authority: `mechanical_default`. Freezes and validates explicit Department Pack transport; it does not create a Goal, author creative truth, or grant review/promotion.
- `scripts/lib/idol_role_context_pack.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/lib/idol_run_followup_sidecar.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/lib/idol_run_layout.py` — status: `active`; authority: `mechanical_default`.
- `scripts/lib/idol_run_layout.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/lib/idol_post05_trace.py` — status: `active`; authority: `mechanical_default`.
- `scripts/lib/idol_skill_contract_paths.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/lib/idol_source_connection_contract.rb` — status: `active`; authority: `mechanical_default`. Exact-copy disk SHA onto model-authored source pointers; model-facing view omits hex; never fills creative fields.
- `scripts/idol_stamp_source_connections.rb` — status: `active`; authority: `mechanical_default`. Stamp-in CLI over source pointer rows; stdout only.
- `scripts/lib/idol_storyline_density_locator_contract.rb` — status: `active`; authority: `mechanical_default`. Close check for a locator sheet into one full-text storyline: presence, lineage, not-empty / not-PRE-00-restatement. Markdown PRE-00 uses a sibling sheet bound to `source_path`.
- `scripts/idol_validate_storyline_density_locators.rb` — status: `active`; authority: `mechanical_default`. Fail-closed locator-sheet close check for a sheet or markdown/YAML artifact.
- `scripts/lib/idol_kinetic_slot_sheet_contract.rb` — status: `active`; authority: `mechanical_default`. Presence of a change-point slot sheet; Sequence evidence, Core 1--2 nails, Key Screen inheritance; no uniqueness scorer.
- `scripts/idol_validate_kinetic_slot_sheet.rb` — status: `active`; authority: `mechanical_default`. Fail-closed kinetic slot-sheet presence check.
- `scripts/lib/idol_social_release_contracts.py` — status: `active`; authority: `mechanical_default`.
- `scripts/lib/idol_social_taxonomy.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/lib/idol_storyboard_collected_angle_contract.rb` — status: `active`; authority: `mechanical_default`. Structural completeness and exact-binding checks for model-authored full-storyboard camera-angle review. Scripts never infer sameness or uniqueness from labels, families, hashes, or numeric angles.
- `scripts/lib/idol_video_prompt_section_qa_contract.rb` — status: `historical`; authority: `historical_evidence_only`.
- `scripts/lib/idol_xai_api_media_profile_contract.rb` — status: `active`; authority: `mechanical_default`. Shared current-snapshot resolver; registration-required and legacy lanes HOLD, and only an exact hash-bound registered profile resolves without granting readiness or execution authority.

For profiled work, use this guide and the exact dispatch only. Open the full
[`INDEX.md`](../INDEX.md) only for maintenance, rerouting, or unprofiled discovery.
