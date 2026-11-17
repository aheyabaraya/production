# frozen_string_literal: true

require "minitest/autorun"
require "pathname"
require "yaml"

class IdolHarnessExecutionPresetTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  CONTRACT = ROOT.join("automation", "harness-execution-contract.yaml")
  PROFILE_REGISTRY = ROOT.join("automation", "harness-skill-load-profiles.yaml")
  STAGE_REGISTRY = ROOT.join("automation", "harness-stage-registry.yaml")
  ORCHESTRATOR = ROOT.join("skills", "idol-orchestrator", "SKILL.md")
  GROK_ADAPTER = ROOT.join(".grok", "skills", "idol-harness-step", "SKILL.md")
  GROK_COMMANDS = ROOT.join("handoff", "grok", "HARNESS-STEP-COMMANDS.md")

  def setup
    @contract = YAML.safe_load(CONTRACT.read, aliases: true)
    @profiles = YAML.safe_load(PROFILE_REGISTRY.read, aliases: true)
    @registry = YAML.safe_load(STAGE_REGISTRY.read, aliases: true)
  end

  def test_active_route_has_no_legacy_multi_stage_preset_or_retired_stage
    assert_equal "idol-harness-execution-contract.v36", @contract.fetch("schema_version")
    refute @contract.key?("execution_presets")
    assert_equal "none", @contract.dig("migration_policy", "compatibility_branch")
    assert_equal %w[00 01A 02], @contract.dig("migration_policy", "retired_active_artifacts")

    route = @contract.fetch("active_route")
    assert_includes route, "front_planning_integration"
    assert_includes route, "mv_performance_direction"
    assert_includes route, "mv_storyboard_direction"
    assert_includes route, "image_prompt_compilation"
    assert_includes route, "branch_cut_generation"
    assert_includes route, "generated_branch_cut_review"
    assert_includes route, "audio_branch_cut_placement"
    refute_includes route, "generation_coverage_plan"
  end

  def test_v20_session_topology_keeps_director_and_worker_boundaries_explicit
    studio = @contract.fetch("studio_session_routing")
    assert_equal true, studio.dig("creative_development_director", "founder_visible")
    assert_equal "creative_development_director", studio.dig("song_room", "reports_to")
    assert_equal "smallest_disjoint_named_gap_assignments_only", studio.dig("pre_song_departments", "dispatch_policy")
    assert_equal true, studio.dig("pre_song_departments", "zero_assignment_when_director_ready")
    assert_equal "provider_cap_and_cdd_backpressure_are_ceilings_not_launch_targets", studio.dig("pre_song_departments", "capacity_policy")
    assert_equal ["reference_research_generalist", "world_still_reference_department", "pinterest_visual_composition_worker"], studio.dig("post_song_reference_wave", "eligible_departments")
    assert_equal "smallest_disjoint_named_gap_assignments_only", studio.dig("post_song_reference_wave", "dispatch_policy")
    assert_equal "floor_six_disjoint_then_named_gap_adaptive", studio.dig("post_song_reference_wave", "assignment_count_policy")
    assert_equal 6, studio.dig("post_song_reference_wave", "assignment_count_floor")
    assert_equal "adaptive_to_professional_decision_readiness_no_fixed_source_floor_or_ceiling", studio.dig("post_song_reference_wave", "source_count_policy")
    assert_equal "adaptive_to_named_gap_no_fixed_discovery_or_application_quota", studio.dig("post_song_reference_wave", "candidate_count_policy")
    refute studio.dig("post_song_reference_wave", "generalist_role_routing").key?("session_count")
    assert_equal "forbidden", studio.dig("post_song_reference_wave", "world_still_video_access")
    assert_equal "forbidden_pointer_handoff_only", studio.dig("post_song_reference_wave", "world_still_pinterest_access")
    assert_equal "required_hash_bound_uncropped_contact_sheet", studio.dig("post_song_reference_wave", "world_still_every_multi_image_comparison")
    limits = studio.dig("post_song_reference_wave", "world_still_candidate_policy")
    assert_equal "dispatched_world_space_object_material_functions", limits.fetch("scope")
    assert_equal "forbidden_pointer_handoff_only", limits.fetch("pinterest_ownership")
    pinterest_limits = studio.dig("post_song_reference_wave", "pinterest_candidate_policy")
    assert_equal "named_visual_section_major_or_core_gap", pinterest_limits.fetch("scope")
    assert_equal "stop_when_professionally_decision_ready_with_nearest_alternative_and_risk", pinterest_limits.fetch("stop_policy")
    assert_equal false, pinterest_limits.fetch("existing_reference_pool_replacement_allowed")
    assert_equal false, pinterest_limits.fetch("candidate_pool_is_generation_attachment_quota")
    assert_equal "reuse_existing_owner_or_add_disjoint_assignment_only_for_remaining_named_gap", studio.dig("post_song_reference_wave", "followup_policy")
    assert_equal "never_fill_provider_capacity", studio.dig("post_song_reference_wave", "launch_policy")
    assert_equal "provider_cap_cdd_backpressure_owner_path_collision_and_pending_review", studio.dig("post_song_reference_wave", "queue_policy")
    assert_equal "explicit_per_dispatch", studio.dig("post_song_reference_wave", "external_discovery_permission")
    assert_equal "explicit_per_dispatch", studio.dig("post_song_reference_wave", "source_registration_permission")
    assert_equal "separate_exact_permission_required", studio.dig("post_song_reference_wave", "download_capture_or_upload")
    assert_equal "creative_development_director", studio.dig("member_visual_identity", "return_recipient_role")
    assert_equal "required_card_missing_or_new_or_full_restyle_authorized", studio.dig("member_visual_identity", "create_when")
    assert_equal true, studio.dig("member_visual_identity", "physical_task")
    assert_equal false, studio.dig("member_visual_identity", "internal_or_nested_worker_route_allowed")
    assert_equal "adaptive_named_component_gap_set_until_professionally_decision_ready", studio.dig("member_visual_identity", "pinterest_styling_candidate_policy")
    assert_equal "forbidden", studio.dig("member_visual_identity", "pinterest_face_identity_use")
    assert_equal "continue_same_physical_task_with_new_immutable_attempt", studio.dig("member_visual_identity", "founder_correction_policy")
    assert_equal "cdd_review_overall_presentation_founder_pass_overall_canonical_promotion", studio.dig("member_visual_identity", "passed_card_promotion")
    stale_quota_keys = %w[
      ordinary_departments
      generalist_sessions
      world_still_sessions
      pinterest_sessions
      ordinary_sessions
      supplemental_generalist_sessions_maximum
      reviewed_generalist_sessions_maximum
      reviewed_maximum_sessions
      primary_sources_per_generalist_session
      ordinary_generalist_source_ceiling
      reviewed_generalist_source_ceiling
      world_still_candidate_limits
      pinterest_candidate_limits
      base_department_policy
      supplemental_trigger
      supplemental_scope
      supplemental_queue_policy
    ]
    stale_quota_keys.each { |key| refute studio.fetch("post_song_reference_wave").key?(key), key }
    refute studio.fetch("member_visual_identity").key?("pinterest_styling_candidate_minimum_per_missing_new_or_full_restyle_member")
    member_profile = @profiles.fetch("profiles").find do |row|
      row.fetch("profile_id") == "member_visual_identity"
    end
    refute_nil member_profile
    member_skill_ids = member_profile.fetch("required_skill_ids")
    refute_includes member_skill_ids, "generation"
    assert_equal 14, studio.dig("pre_02a_development_wave", "maximum_active_department_sessions")
    assert_equal "founder_direction_alignment_then_internal_fp_close_then_role_routed_01_then_02a", studio.dig("pre_02a_development_wave", "development_epoch")
    assert_equal "forbidden", studio.dig("pre_02a_development_wave", "founder_intermediate_refill")
    assert_equal "02a_final_planning", studio.dig("pre_02a_development_wave", "final_founder_gate")
    assert_equal "exact_hash_bound_preserved_for_02a_final_planning", studio.dig("pre_02a_development_wave", "fp_close_storyline")
    assert_equal 1, @contract.dig("delegation", "maximum_creative_worker_depth")
    assert_equal false, @contract.dig("delegation", "ordinary_worker_may_create_creative_grandchildren")
    assert_equal "edit_director", @contract.dig("edit_routing", "edit_shards", "return_recipient_role")
    assert_equal "cli_first_run", studio.dig("provider_adapters", "cursor", "lifecycle_operations", "create")
    grok_adapter = studio.dig("provider_adapters", "grok")
    assert_equal "registered_grok_tui_slash_goal_or_acp_native_goal_session", grok_adapter.fetch("runtime_surface")
    assert_equal "tui_slash_goal_or_acp_native_goal_create", grok_adapter.dig("lifecycle_operations", "create")
    assert_equal %w[interactive_tui_slash_goal acp_matching_native_goal_event], grok_adapter.dig("goal_admission", "admissible_surfaces")
    assert_equal true, grok_adapter.dig("goal_admission", "matching_objective_required")
    assert_equal "forbidden", grok_adapter.dig("goal_admission", "headless_without_matching_native_goal_event")
    assert_equal "goal_surface_unavailable", grok_adapter.dig("goal_admission", "unavailable_status")
    assert_equal "hold_with_zero_work_and_zero_output", grok_adapter.dig("goal_admission", "unavailable_action")
    assert_equal 0, grok_adapter.dig("goal_admission", "work_count_on_unavailable")
    assert_equal 0, grok_adapter.dig("goal_admission", "output_count_on_unavailable")
    assert_equal 8, @contract.dig("live_worker_capacity", "provider_capacity", "grok_nonroot", "ordinary_maximum")
    assert_equal 8, @contract.dig("live_worker_capacity", "provider_capacity", "grok_nonroot", "reviewed_maximum")
    assert_equal false, @contract.dig("live_worker_capacity", "provider_capacity", "launch_to_fill_capacity")
    assert_equal true, @contract.dig("live_worker_capacity", "provider_capacity", "queue_when_director_review_pending")
    assert_equal "next_consumes_pending_bytes_or_owner_path_collision", @contract.dig("live_worker_capacity", "provider_capacity", "queue_launch_when")
    assert_equal "fresh_session_on_returned_artifacts_only", @contract.dig("post_02a_session_routing", "pixel_and_playback_review_window")
    assert_equal true, @contract.dig("post_02a_session_routing", "never_load_generator_chat_into_review")
    assert_equal true, @contract.dig("post_02a_session_routing", "review_window_is_not_a_second_director")
    assert_equal "founder", @contract.dig("session_route", "visible_task_authorization", "authorizing_actor")
    assert_equal "hold_without_creation", @contract.dig("session_route", "visible_task_authorization", "absent_action")
    assert_equal(
      %w[
        source_paths_and_hashes
        dispatch_id
        returned_output_hash
        lineage_id
        attempt_id
        session_id
        director_dispatch_index_path_hash_row
        director_review_row
        review_target
        decision_epoch
        founder_decision_receipt
      ],
      @contract.dig("board_decision_semantics", "board_card_bindings")
    )
    discovery = @contract.dig("review_workbench", "modes", "discovery")
    assert_equal "adaptive_named_gap_set_no_fixed_candidate_floor_or_ceiling", discovery.fetch("candidate_policy")
    assert_equal "actual_visual_units_nearest_alternative_and_material_risk", discovery.fetch("decision_ready_evidence")
    refute discovery.key?("candidate_count")
    direction = @contract.dig("review_workbench", "modes", "direction_synthesis")
    assert_equal "adaptive_complete_directions_no_fixed_candidate_floor_or_ceiling", direction.fetch("candidate_policy")
    assert_equal "cdd_recommends_only_when_evidence_is_decision_ready", direction.fetch("recommendation_policy")
    refute direction.key?("recommended_candidates")
    refute direction.key?("alternative_candidates_maximum")
    refute direction.key?("complete_candidate_count")
    assert_equal "select_candidate", direction.fetch("selection_action")
    assert_equal false, direction.fetch("selection_is_fp_pass")
    assert_equal "compare_reading_evidence_counterreading_screen_consequence_no_auto_filter", direction.fetch("fit_tension_policy")
    assert_equal %w[select_candidate lock_fields hold reject direct_comment], @contract.dig("board_decision_semantics", "modes", "direction_synthesis", "legal_actions")
    assert_equal 1, @contract.dig("board_decision_semantics", "decision_intake", "direction_selected_candidate_maximum")
    assert_equal false, @contract.dig("board_decision_semantics", "decision_intake", "candidate_merge_or_fp_pass_inferred")
    assert_equal %w[direction_alignment 02a_final_planning], @contract.dig("board_decision_semantics", "founder_checkpoint_sequence")
    assert_equal "02A Final Planning", @contract.dig("board_decision_semantics", "modes", "fp_final", "founder_facing_label")

    profile_ids = @profiles.fetch("profiles").map { |row| row.fetch("profile_id") }
    assert_includes profile_ids, "pinterest_visual_composition_worker"
    assert_includes profile_ids, "pre_02a_development_block_fp"
    refute_includes profile_ids, "pre_02a_development_block_01"
    refute_includes profile_ids, "pre_02a_development_block_02a"
  end

  def test_core_and_branch_cut_contract_is_open_ended_and_not_start_end_templated
    expansion = @contract.fetch("section_expansion")
    assert_equal "stage_01", expansion.fetch("official_core_owner")
    assert_equal "exactly_one_passed_primary_image_per_official_core", expansion.fetch("official_core_primary_image_rule")
    assert_equal "immutable_exact_import_no_core_reauthoring", expansion.fetch("stage_02a_core_policy")
    assert_equal "ordered_branch_cuts_only", expansion.fetch("stage_02a_authored_scope")
    assert_includes expansion.fetch("stage_01_job"), "author_every_official_core_cut"
    assert_includes expansion.fetch("stage_02a_job"), "exact_import_01_official_core_bytes_unchanged"
    assert_includes expansion.fetch("core_cut_definition"), "parent_major_event"
    assert_includes expansion.fetch("branch_cut_definition"), "distinct_observable_directorial_job"
    assert_equal(
      "one_to_n_per_core_cut_without_global_cap_or_start_end_template",
      expansion.fetch("branch_cut_cardinality")
    )
    assert_includes expansion.fetch("new_core_cut_rule"), "stage_01_authors_a_new_official_core"
    assert_includes expansion.fetch("new_core_cut_rule"), "02a_returns_any_core_change_to_01"
  end

  def test_stage_registry_exposes_current_branch_cut_route_only
    stage_ids = @registry.fetch("stages").map { |row| row.fetch("stage_id") }
    %w[
      mv_storyboard_direction
      image_prompt_compilation
      branch_cut_generation
      generated_branch_cut_review
      audio_branch_cut_placement
      video_motion_direction
    ].each { |stage_id| assert_includes stage_ids, stage_id }
    refute_includes stage_ids, "generation_coverage_plan"
    assert_equal %w[00 01A 02], @registry.dig("migration_policy", "retired_active_stage_labels")
  end

  def test_codex_and_grok_entry_surfaces_share_the_contract_without_preset_fallback
    [ORCHESTRATOR.read, GROK_ADAPTER.read, GROK_COMMANDS.read].each do |surface|
      assert_includes surface, "automation/harness-execution-contract.yaml"
    end

    assert_includes GROK_ADAPTER.read, "exposes no legacy multi-stage preset compatibility"
    assert_includes GROK_ADAPTER.read, "`fp-to-02a` and `fp-to-02b` are not active"
    assert_includes GROK_COMMANDS.read.gsub(/\s+/, " "), "It is not encoded as a slash-token preset"
    assert_includes GROK_ADAPTER.read, "automation/current-next.yaml"
    assert_includes GROK_ADAPTER.read, "skills/idol-orchestrator/SKILL.md"
  end
end
