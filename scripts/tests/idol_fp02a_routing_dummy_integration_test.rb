# frozen_string_literal: true

require "json"
require "minitest/autorun"
require "pathname"
require "set"
require "yaml"

class IdolFp02aRoutingDummyIntegrationTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path

  def setup
    @execution = YAML.safe_load(ROOT.join("automation/harness-execution-contract.yaml").read, aliases: true)
    @profiles = YAML.safe_load(ROOT.join("automation/harness-skill-load-profiles.yaml").read, aliases: true)
    @stages = YAML.safe_load(ROOT.join("automation/harness-stage-registry.yaml").read, aliases: true)
    @front_schema = JSON.parse(ROOT.join("schemas/front-planning-readiness.schema.json").read)
    @storyboard_schema = JSON.parse(ROOT.join("schemas/master-storyboard.schema.json").read)
    @board_schema = JSON.parse(ROOT.join("schemas/html-review-board.schema.json").read)
    @projection_schema = JSON.parse(ROOT.join("schemas/review-projection-source-set.schema.json").read)
  end

  def test_mv_teaser_form_is_explicit_without_forcing_feature_film_grammar
    routing = @execution.fetch("board_decision_semantics")
    assert_equal(
      "complete_mv_teaser_or_selected_song_video_not_feature_film_requirement",
      routing.fetch("legacy_whole_film_transport_token")
    )

    readout = @front_schema.dig("$defs", "wholeFilmAlignmentReadout")
    required = readout.fetch("required").to_set
    %w[video_form form_logic screen_progression progression_turns ending_or_afterimage].each do |field|
      assert_includes required, field
    end

    forms = readout.dig("properties", "video_form", "enum")
    assert_includes forms, "narrative"
    assert_includes forms, "performance_led"
    assert_includes forms, "associative_poetic"
    assert_includes forms, "retention_led_teaser"
    assert_match(/must not invent a narrative-film requirement/, readout.dig("properties", "form_logic", "description"))
    assert_equal "whole_video_and_section_flow", @execution.dig("review_workbench", "hierarchy", 1)
  end

  def test_founder_intervention_is_direction_alignment_then_02a_final_planning
    wave = @execution.dig("studio_session_routing", "pre_02a_development_wave")
    assert_equal "founder_direction_alignment_then_internal_fp_close_then_role_routed_01_then_02a", wave.fetch("development_epoch")
    assert_equal "forbidden", wave.fetch("founder_intermediate_refill")
    assert_equal "exact_hash_bound_preserved_for_02a_final_planning", wave.fetch("fp_close_storyline")
    assert_equal "02a_final_planning", wave.fetch("final_founder_gate")
    assert_equal "affected_02b_route_only_paid_generation_separate", wave.fetch("final_gate_authority")
    assert_equal(
      %w[new_or_fully_restyled_member_visual material_departure_from_aligned_direction identity_conflict safety_conflict source_conflict feasibility_conflict],
      wave.fetch("early_founder_exception_reasons")
    )

    checkpoints = checkpoint_ids("pre_02a_development_block_fp")
    assert_equal(
      %w[fp_close_shard section_01_core_direction section_01_song_story_detail section_01_world_wardrobe_detail section_01_choreography_detail section_01_choreography_board section_01_performance_detail section_01_integration section_02a_coverage],
      checkpoints
    )

    review_stage = @stages.fetch("stages").find { |row| row.fetch("stage_id") == "storyboard_review" }
    assert_equal "idol-front-planning-director", review_stage.fetch("owner_skill")
    assert_match(/CDD planning reviewer/, review_stage.fetch("professional_role"))

    gate = @storyboard_schema.dig("$defs", "founderPlanningGate")
    assert_equal "complete_pre00_root_and_active_full_text_lineage_then_fp_close_and_01_expansion_then_02a_core_and_branch_plan", gate.dig("properties", "storyline_review_order", "const")
    assert_equal "affected_02B_route_only", gate.dig("properties", "authorizes", "const")
    assert_equal false, gate.dig("properties", "paid_generation_authorized", "const")

    expansion = @execution.fetch("section_expansion")
    assert_equal "stage_01", expansion.fetch("official_core_owner")
    assert_equal "exactly_one_passed_primary_image_per_official_core", expansion.fetch("official_core_primary_image_rule")
    assert_equal "immutable_exact_import_no_core_reauthoring", expansion.fetch("stage_02a_core_policy")
    assert_equal "ordered_branch_cuts_only", expansion.fetch("stage_02a_authored_scope")
  end

  def test_reference_workers_are_role_routed_without_thinning_comparison_quality
    wave = @execution.dig("studio_session_routing", "post_song_reference_wave")
    assert_equal "smallest_disjoint_named_gap_assignments_only", wave.fetch("dispatch_policy")
    assert_equal "floor_six_disjoint_then_named_gap_adaptive", wave.fetch("assignment_count_policy")
    assert_equal "adaptive_to_professional_decision_readiness_no_fixed_source_floor_or_ceiling", wave.fetch("source_count_policy")
    routing = wave.fetch("generalist_role_routing")
    refute routing.key?("session_count")
    assert_equal(
      %w[reference_story_sequence_role reference_camera_composition_role reference_world_object_material_role reference_performance_role],
      routing.fetch("eligible_checkpoints")
    )
    assert_equal true, routing.fetch("distinct_role_or_section_territory_required")
    assert_equal "forbidden", routing.fetch("all_role_modules_per_worker")
    assert_equal "professionally_decision_ready_not_minimum_context", routing.fetch("quality_stop")

    profile = profile("reference_research_generalist")
    checkpoints = profile.dig("phase_load", "checkpoints").to_h { |row| [row.fetch("checkpoint_id"), row] }
    assert_equal(
      Set[
        "reference_story_sequence_role",
        "reference_camera_composition_role",
        "reference_world_object_material_role",
        "reference_performance_role",
        "reference_named_gap"
      ],
      checkpoints.keys.to_set
    )

    story_reads = checkpoints.fetch("reference_story_sequence_role").fetch("required_read_ids").to_set
    camera_reads = checkpoints.fetch("reference_camera_composition_role").fetch("required_read_ids").to_set
    world_reads = checkpoints.fetch("reference_world_object_material_role").fetch("required_read_ids").to_set
    assert_includes story_reads, "video_first_read_contract"
    refute_includes story_reads, "world_still_contact_sheet_contract"
    refute_includes story_reads, "mv_camera_module"
    assert_includes camera_reads, "mv_camera_module"
    assert_includes world_reads, "world_still_contact_sheet_contract"
    refute_includes world_reads, "video_first_read_contract"
    refute_includes world_reads, "mv_camera_module"

    skill = ROOT.join("skills/idol-reference-research-department/SKILL.md").read
    assert_includes skill, "decision-ready"
    assert_match(/fewer\s+files is never the goal by itself/i, skill)
  end

  def test_mv_director_loads_core_then_only_declared_professional_detail
    core = checkpoint("pre_02a_development_block_fp", "section_01_core_direction")
    song = checkpoint("pre_02a_development_block_fp", "section_01_song_story_detail")
    world = checkpoint("pre_02a_development_block_fp", "section_01_world_wardrobe_detail")
    choreography = checkpoint("pre_02a_development_block_fp", "section_01_choreography_detail")
    choreography_board = checkpoint("pre_02a_development_block_fp", "section_01_choreography_board")
    performance = checkpoint("pre_02a_development_block_fp", "section_01_performance_detail")
    integration = checkpoint("pre_02a_development_block_fp", "section_01_integration")
    coverage_02a = checkpoint("pre_02a_development_block_fp", "section_02a_coverage")

    core_reads = core.fetch("required_read_ids").to_set
    %w[mv_direction_module mv_camera_module mv_bundle_detail].each { |item| assert_includes core_reads, item }
    %w[mv_song_module mv_screen_flow_wardrobe_module mv_choreography_module mv_performance_module].each do |item|
      refute_includes core_reads, item
    end

    assert_equal Set["mv_song_module"], role_modules(song)
    assert_equal Set["mv_screen_flow_wardrobe_module"], role_modules(world)
    assert_equal Set["mv_choreography_module"], role_modules(choreography)
    assert_equal Set["mv_performance_module"], role_modules(performance)
    assert_includes choreography.fetch("required_skill_ids"), "choreography_performance"
    assert_includes choreography.fetch("required_read_ids"), "choreography_body_module"
    assert_includes choreography.fetch("required_read_ids"), "choreography_capture_module"
    assert_equal ["choreography_board"], choreography_board.fetch("required_skill_ids")
    assert_includes choreography_board.fetch("required_read_ids"), "master_storyboard_schema"
    assert_includes choreography_board.fetch("required_read_ids"), "song_choreography_performance_schema"
    refute_includes performance.fetch("required_skill_ids"), "choreography_performance"
    assert_includes integration.fetch("required_read_ids"), "mv_integration_module"
    assert_includes coverage_02a.fetch("required_read_ids"), "mv_camera_module"
  end

  def test_post_02a_image_motion_and_edit_routes_are_checkpoint_scoped
    assert_equal(
      %w[section_02b_image section_image_generation_release section_generated_image_review section_image_render_correction],
      checkpoint_ids("post_02a_02b_image")
    )
    image_prompt = checkpoint("post_02a_02b_image", "section_02b_image")
    image_release = checkpoint("post_02a_02b_image", "section_image_generation_release")
    image_review = checkpoint("post_02a_02b_image", "section_generated_image_review")
    image_correction = checkpoint("post_02a_02b_image", "section_image_render_correction")
    [image_prompt, image_release, image_review, image_correction].each do |row|
      assert_equal ["generation"], row.fetch("required_skill_ids")
    end
    assert_includes image_prompt.fetch("required_read_ids"), "harness_context_pack_schema"
    refute_includes image_prompt.fetch("required_read_ids"), "mv_camera_module"
    refute_includes image_prompt.fetch("required_read_ids"), "generation_render_correction"
    refute_includes image_prompt.fetch("required_read_ids"), "routing_policy"
    refute_includes image_prompt.fetch("required_read_ids"), "fp_operating_contract"
    refute_includes image_prompt.fetch("required_read_ids"), "luna_section_lifecycle_execution_schema"
    assert_includes image_release.fetch("required_read_ids"), "image_generation_section_approval_schema"
    assert_includes image_review.fetch("required_read_ids"), "generated_review_schema"
    refute_includes image_review.fetch("required_read_ids"), "routing_policy"
    assert_equal false, image_review.fetch("same_lineage")
    assert_includes image_correction.fetch("required_read_ids"), "generation_render_correction"

    assert_equal(
      %w[section_03v_audio_placement section_03v_motion_direction section_03v_playback_review],
      checkpoint_ids("post_02a_03v")
    )
    motion = checkpoint("post_02a_03v", "section_03v_motion_direction")
    playback = checkpoint("post_02a_03v", "section_03v_playback_review")
    assert_equal ["video_prompt"], motion.fetch("required_skill_ids")
    assert_includes motion.fetch("required_read_ids"), "mv_camera_module"
    assert_includes motion.fetch("required_read_ids"), "video_storyboard_assist_detail"
    refute_includes motion.fetch("required_read_ids"), "routing_policy"
    refute_includes playback.fetch("required_read_ids"), "video_storyboard_assist_detail"
    refute_includes playback.fetch("required_read_ids"), "routing_policy"
    assert_equal false, playback.fetch("same_lineage")

    assert_equal %w[edit_qc_section edit_master_closeout edit_social_release], checkpoint_ids("edit_director")
    assert_equal %w[finishing_fx_section finishing_fx_ae_like_detail shot_vfx_section], checkpoint_ids("edit_shard")
    finishing = checkpoint("edit_shard", "finishing_fx_section")
    shot_vfx = checkpoint("edit_shard", "shot_vfx_section")
    assert_equal ["edit_finishing_fx"], finishing.fetch("required_skill_ids")
    assert_equal ["shot_vfx"], shot_vfx.fetch("required_skill_ids")
    refute_includes finishing.fetch("required_read_ids"), "shot_vfx_manual"
    refute_includes shot_vfx.fetch("required_read_ids"), "edit_finishing_fx_schema"
  end

  def test_camera_work_returns_through_existing_director_chain
    assert_equal "creative_development_director", profile("reference_research_generalist").dig("return_route", "recipient_role")
    assert_equal "creative_development_director", profile("pre_02a_development_block_fp").dig("return_route", "recipient_role")
    assert_equal "creative_development_director", profile("post_02a_02b_image").dig("return_route", "recipient_role")
    assert_equal "creative_development_director", profile("post_02a_03v").dig("return_route", "recipient_role")
  end

  def test_pinterest_is_section_scoped_and_separate_from_world_still
    wave = @execution.dig("studio_session_routing", "post_song_reference_wave")
    policy = wave.fetch("pinterest_candidate_policy")
    assert_equal "named_visual_section_major_or_core_gap", policy.fetch("scope")
    assert_equal "stop_when_professionally_decision_ready_with_nearest_alternative_and_risk", policy.fetch("stop_policy")
    assert_equal false, policy.fetch("existing_reference_pool_replacement_allowed")
    assert_equal false, policy.fetch("candidate_pool_is_generation_attachment_quota")
    assert_equal "forbidden_pointer_handoff_only", wave.fetch("world_still_pinterest_access")

    pinterest = profile("pinterest_visual_composition_worker")
    assert_equal ["pinterest_reference_worker"], pinterest.fetch("required_skill_ids")
    assert_includes pinterest.fetch("required_read_ids"), "pinterest_section_comparison_detail"
    refute_includes pinterest.dig("hold_conditions"), "fewer_than_five_readable_pins_per_active_visual_section"

    world = profile("world_still_reference_department")
    %w[pinterest_search pinterest_open pinterest_capture pinterest_quota_ownership].each do |ban|
      assert_includes world.dig("authority", "must_not"), ban
    end
  end

  def test_review_board_coordinator_is_mechanical_and_uses_one_stable_board
    board = profile("board_coordinator")
    assert_equal ["review_board_coordinator"], board.fetch("required_skill_ids")
    refute_includes board.fetch("required_skill_ids"), "orchestrator"
    assert_equal(
      %w[board_direction_alignment board_02a_final_planning board_generated_branch_cut_review board_video_playback_review],
      checkpoint_ids("board_coordinator")
    )
    assert_equal "section_set", board.dig("output_contract", "expected_scope")
    assert_includes checkpoint("board_coordinator", "board_direction_alignment").fetch("required_read_ids"), "fp_founder_visual_contract"
    assert_includes checkpoint("board_coordinator", "board_02a_final_planning").fetch("required_read_ids"), "founder_review_decision_intake_schema"
    assert_includes checkpoint("board_coordinator", "board_generated_branch_cut_review").fetch("required_read_ids"), "generated_review_schema"
    assert_includes checkpoint("board_coordinator", "board_video_playback_review").fetch("required_read_ids"), "video_prompt_manifest_schema"
    assert_equal "RUN/review/founder-workbench.html", @execution.dig("session_route", "founder_review_board")
    assert_equal true, @execution.dig("review_workbench", "one_stable_html_lineage")
    assert_equal "exact_fp_close_storyline_plus_01_expansion_plus_02a_core_branch_plan", @execution.dig("review_workbench", "modes", "fp_final", "required_projection")

    assert_equal "idol-html-review-board.v12", @board_schema.dig("properties", "schema_version", "const")
    assert_equal %w[fp_close planning_02a post_02a], @board_schema.dig("$defs", "reviewPhase", "properties", "phase", "enum")
    assert_equal %w[read_only_fp_close_lineage active_02a_final_planning read_only_projection], @board_schema.dig("$defs", "reviewPhase", "properties", "gate", "enum")

    ordered = @projection_schema.dig("$defs", "orderedReview")
    assert_equal %w[fp_close_source planning_02a_source], ordered.fetch("required")
    assert_match(/read-only storyline lineage/, ordered.dig("properties", "fp_close_source", "description"))
    assert_match(/PASS authorizes affected 02B routing only/, ordered.dig("properties", "planning_02a_source", "description"))
  end

  def test_historical_face_helpers_preserve_used_evidence_but_never_enter_active_profiles
    historical = {
      "idol-human-face-realism-control" => "runs/2026-06-26/0626_FACE_REALISM_REFERENCE_STUDY/research/face-realism-reference-analysis-v1.yaml",
      "idol-photoreal-human-face-lock" => "runs/2026-06-27/PHOTOREAL_FACE_LOCK_18P/research/photoreal-face-lock-18p-generation-packet-v1.md",
      "idol-surgical-face-architecture" => "runs/2026-06-27/PHOTOREAL_SURGICAL_TEASER_5/research/surgical-face-architecture-lock-v1.yaml"
    }
    active_skill_paths = @profiles.fetch("skill_bindings").map { |row| row.fetch("path") }
    matrix_source = ROOT.join("scripts/idol_skill_contract_matrix.rb").read

    historical.each do |name, run_evidence|
      assert ROOT.join("skills", name, "SKILL.md").exist?, "historical skill source is missing: #{name}"
      assert ROOT.join(run_evidence).exist?, "actual historical run evidence is missing: #{run_evidence}"
      refute active_skill_paths.any? { |path| path.include?(name) }, "historical helper became active-profile-bound: #{name}"
      assert_includes matrix_source, name
    end
  end

  def test_adaptive_reference_assignments_do_not_fill_capacity_or_create_a_second_director
    wave = @execution.dig("studio_session_routing", "post_song_reference_wave")
    assert_equal "floor_six_disjoint_then_named_gap_adaptive", wave.fetch("assignment_count_policy")
    assert_equal "never_fill_provider_capacity", wave.fetch("launch_policy")
    assert_equal "provider_cap_cdd_backpressure_owner_path_collision_and_pending_review", wave.fetch("queue_policy")
    %w[generalist_sessions world_still_sessions pinterest_sessions ordinary_sessions supplemental_generalist_sessions_maximum reviewed_maximum_sessions].each do |key|
      refute wave.key?(key), key
    end
    assert_equal 14, wave.fetch("maximum_active_department_sessions")

    overall = profile("overall_director")
    cdd = profile("creative_development_director")
    assert_equal "overall_director", overall.dig("authority", "promotion_owner")
    assert_equal "founder", overall.dig("return_route", "recipient_role")
    assert_equal "forbidden", cdd.dig("output_contract", "canonical_write")
    assert_equal "overall_director", cdd.dig("authority", "review_owner")
    assert_equal "overall_director", cdd.dig("authority", "promotion_owner")
    assert_equal "overall_director", cdd.dig("return_route", "recipient_role")

    front_planning = @stages.fetch("stages").find { |row| row.fetch("stage_id") == "front_planning_integration" }
    assert_equal "creative_development_director", front_planning.fetch("session_route")
    refute_match(/\boverall\b/i, front_planning.fetch("professional_role"))

    board = profile("board_coordinator")
    %w[creative_promotion founder_lock canonical_truth_authoring].each do |ban|
      assert_includes board.dig("authority", "must_not"), ban
    end
  end

  def test_stage_manuals_load_only_on_the_owning_checkpoint
    bindings = @profiles.fetch("read_bindings").each_with_object({}) do |row, memo|
      memo[row.fetch("binding_id")] = row
    end
    %w[
      section_production_policy
      section_production_front_planning
      section_production_02b_pixel
      section_production_04
    ].each do |binding_id|
      row = bindings.fetch(binding_id)
      assert_equal true, row.fetch("eof_required")
      assert ROOT.join(row.fetch("path")).file?, row.fetch("path")
    end

    overall = checkpoint("overall_director", "director_startup").fetch("required_read_ids")
    assert_includes overall, "production_system"
    assert_includes overall, "section_production_policy"
    refute_includes overall, "section_production_02b_pixel"
    refute_includes overall, "section_production_04"

    cdd = checkpoint("creative_development_director", "cdd_direction_alignment").fetch("required_read_ids")
    assert_includes cdd, "section_production_front_planning"
    refute_includes cdd, "section_production_02b_pixel"
    refute_includes cdd, "section_production_04"
    assert_equal ["front_planning_director"], profile("creative_development_director").fetch("required_skill_ids")

    image = checkpoint("post_02a_02b_image", "section_02b_image").fetch("required_read_ids")
    assert_includes image, "section_production_02b_pixel"
    refute_includes image, "section_production_front_planning"
    refute_includes image, "section_production_04"
  end

  private

  def profile(profile_id)
    @profiles.fetch("profiles").find { |row| row.fetch("profile_id") == profile_id } || flunk("missing profile #{profile_id}")
  end

  def checkpoint(profile_id, checkpoint_id)
    profile(profile_id).dig("phase_load", "checkpoints").find do |row|
      row.fetch("checkpoint_id") == checkpoint_id
    end || flunk("missing checkpoint #{profile_id}/#{checkpoint_id}")
  end

  def checkpoint_ids(profile_id)
    profile(profile_id).dig("phase_load", "checkpoints").map { |row| row.fetch("checkpoint_id") }
  end

  def role_modules(checkpoint_row)
    checkpoint_row.fetch("required_read_ids").grep(/^mv_.*_module$/).to_set
  end
end
