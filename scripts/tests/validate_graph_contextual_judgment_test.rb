# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "pathname"
require "rbconfig"
require "tmpdir"
require "yaml"
require_relative "../lib/idol_role_context_pack"
require_relative "support/idol_graph_production_review_fixture"

class ValidateGraphContextualJudgmentTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  SCRIPT = ROOT.join("scripts", "validate_graph_contextual_judgment.rb")

  def setup
    @dir = Pathname.new(Dir.mktmpdir("graph-contextual-judgment-", ROOT.join("runs").to_s))
    @source = @dir.join("source.yaml")
    @source.write(YAML.dump(
      "reference_role" => "motion_reference",
      "function_analysis" => [{"purpose" => "still_camera_and_composition"}],
      "performance_scope" => {"performance_mode" => "primary"},
      "no_performance_scope" => {"performance_mode" => "none"},
      "untyped_flag" => "motion_reference",
      "untyped_mode" => "primary",
      "reviewed_evidence" => true
    ))
    @path = @dir.join("judgment.yaml")
    write(document)
  end

  def teardown
    FileUtils.remove_entry(@dir) if @dir&.directory?
  end

  def test_accepts_hash_bound_stage_profile_with_prose_evidence
    result = validate
    assert result[:status].success?, result[:stderr]
  end

  def test_current_authoring_rejects_unresolved_free_text_locator
    payload = document
    payload["criteria"][0]["evidence_locator"] = "unresolved://not-a-bound-source"
    write(payload)
    refute validate[:status].success?
  end

  def test_historical_v1_is_readable_but_never_new_authoring
    payload = document
    payload["schema_version"] = "idol_graph_contextual_judgment.v1"
    payload["criteria"].each { |row| row["evidence_locator"] = "original historical prose locator" }
    write(payload)
    active = validate
    refute active[:status].success?
    assert_includes active[:stderr], "v1 is historical only"
    historical = validate(mode: "historical_audit")
    assert historical[:status].success?, historical[:stderr]
  end

  def test_ordinary_script_word_is_not_an_authorship_claim
    payload = document
    payload["criteria"][0]["do_not_infer"] = "The script checks hashes; an assigned model judges the visible result."
    write(payload)
    result = validate
    assert result[:status].success?, result[:stderr]
    payload["authoring_owner"] = "script"
    write(payload)
    refute validate[:status].success?
  end

  def test_active_promotion_rejects_synthetic_goal_event_but_historical_audit_accepts_it
    payload = document
    event = YAML.safe_load(@goal_event_path.read, aliases: true)
    event["evidence_class"] = "synthetic_fixture"
    event["fixture_notice"] = "synthetic_test_evidence_not_runtime_attestation"
    @goal_event_path.write(YAML.dump(event))
    event_pointer = file_pointer(@goal_event_path)

    dispatch = YAML.safe_load(@dispatch_path.read, aliases: true)
    dispatch.fetch("goal_evidence")["goal_terminal_event_sha256"] = event_pointer.fetch("sha256")
    dispatch.fetch("goal_evidence")["terminal_event"] = event_pointer
    @dispatch_path.write(YAML.dump(dispatch))
    payload.fetch("execution_binding")["goal_terminal_event_sha256"] = event_pointer.fetch("sha256")
    payload.fetch("execution_binding")["dispatch"] = file_pointer(@dispatch_path)
    write(payload)

    active = validate
    refute active[:status].success?
    assert_includes active[:stderr], "active promotion requires provider_native_terminal_event"

    historical = validate(mode: "historical_audit")
    assert historical[:status].success?, historical[:stderr]
    assert_includes historical[:stdout], "historical audit valid; promotion forbidden"
  end

  def test_rejects_new_authoring_that_omits_the_pack_profile_release
    payload = document
    payload.fetch("execution_binding").delete("profile_release")
    write(payload)

    result = validate

    refute result[:status].success?
    assert_includes result[:stderr], "'profile_release' is a required property"
  end

  def test_accepts_launch_projected_rcp_with_distinct_returned_execution_dispatch
    payload = document
    pack = YAML.safe_load(@pack_path.read, aliases: true)

    refute_equal payload.dig("execution_binding", "dispatch"), pack.dig("graph_dispatch_identity", "dispatch")
    assert_equal "launched", pack.dig("graph_dispatch_identity", "dispatch_lifecycle_state_at_projection")
    write(payload)

    result = validate

    assert result[:status].success?, result[:stderr]
  end

  def test_rejects_projection_only_startup_pack_without_dispatch_identity
    payload = document
    startup_pack = IdolRoleContextPack.build(**@pack_build_args.merge(
      source_envelope: {"kind" => "startup_admission", "path" => nil, "sha256" => nil},
      current_state: "prepared"
    ))
    refute startup_pack.key?("graph_dispatch_identity")
    assert_empty IdolRoleContextPack.validate_pack(root: ROOT, pack: startup_pack)
    startup_path = @dir.join("startup-projection-role-context-pack.yaml")
    startup_path.write(YAML.dump(startup_pack))
    payload.fetch("execution_binding")["role_context_pack"] = file_pointer(startup_path)
    write(payload)

    result = validate

    refute result[:status].success?
    assert_includes result[:stderr], "Role Context Pack graph_dispatch_identity is required for judgment validation"
  end

  def test_rejects_rcp_projected_only_after_dispatch_return
    payload = document
    returned_pack = IdolRoleContextPack.build(**@pack_build_args.merge(
      source_envelope: {"kind" => "department_dispatch"}.merge(file_pointer(@dispatch_path)),
      current_state: "returned"
    ))
    assert_equal "returned", returned_pack.dig("graph_dispatch_identity", "dispatch_lifecycle_state_at_projection")
    returned_path = @dir.join("returned-role-context-pack.yaml")
    returned_path.write(YAML.dump(returned_pack))
    payload.fetch("execution_binding")["role_context_pack"] = file_pointer(returned_path)
    write(payload)

    result = validate

    refute result[:status].success?
    assert_includes result[:stderr], "Role Context Pack judgment identity must come from a prepared or launched Dispatch snapshot"
  end

  def test_rejects_ambiguous_reviewed_status_before_director_review
    payload = document
    payload["status"] = "reviewed"
    write(payload)

    result = validate

    refute result[:status].success?
    assert_includes result[:stderr], "ready_for_director_review"
  end

  def test_rejects_composition_below_four
    payload = document
    payload.fetch("criteria").find { |row| row["criterion_id"] == "still_camera_composition_depth_value" }["result"] = 3
    write(payload)
    result = validate
    refute result[:status].success?
    assert_includes result[:stderr], "still_camera_composition_depth_value must be at least grade 4"
  end

  def test_rejects_motion_below_four_when_motion_applies
    payload = document
    payload.fetch("criteria").find { |row| row["criterion_id"] == "motion_temporal_change_and_landing" }["result"] = 3
    write(payload)
    result = validate
    refute result[:status].success?
    assert_includes result[:stderr], "motion_temporal_change_and_landing is a critical grade-4 criterion"
  end

  def test_allows_non_motion_candidate_to_mark_motion_not_applicable
    payload = document
    payload["applicability_tags"] = ["composition_function_present"]
    payload["applicability_evidence"].reject! { |row| row["tag"] == "motion_reference" }
    motion = payload.fetch("criteria").find { |row| row["criterion_id"] == "motion_temporal_change_and_landing" }
    motion["result"] = "not_applicable"
    motion["not_applicable_reason"] = "This candidate is a still composition source; the material Major motion requirement is closed by a separate exact motion unit."
    write(payload)
    result = validate
    assert result[:status].success?, result[:stderr]
  end

  def test_rejects_numeric_conditional_grade_when_evidence_tag_is_absent
    payload = document
    payload["applicability_tags"] = ["composition_function_present"]
    payload["applicability_evidence"].reject! { |row| row["tag"] == "motion_reference" }
    write(payload)
    result = validate
    refute result[:status].success?
    assert_includes result[:stderr], "must be not_applicable when motion_reference is absent"
  end

  def test_hard_gate_cannot_be_averaged_into_eligibility
    payload = document
    payload["hard_gate_findings"] << {
      "finding_id" => "stale_source_lock",
      "evidence_locator" => [file_pointer(@source)],
      "consequence" => "Candidate lineage is not current.",
      "required_action" => "Return to the source owner and refresh the binding."
    }
    write(payload)
    result = validate
    refute result[:status].success?
    assert_includes result[:stderr], "hard-gate findings require hold"

    payload.merge!("decision" => "hold", "next_edge" => "return_to_smallest_owner", "status" => "hold")
    write(payload)
    result = validate
    assert result[:status].success?, result[:stderr]
  end

  def test_zero_one_and_all_floor_vectors_select_only_their_registered_decisions
    payload = document
    payload.fetch("criteria").first["result"] = 0
    write(payload)
    result = validate
    refute result[:status].success?
    assert_includes result[:stderr], "grade 0 requires hold"

    payload.merge!("decision" => "hold", "next_edge" => "return_to_smallest_owner", "status" => "hold")
    write(payload)
    assert validate[:status].success?

    payload = document
    payload.fetch("criteria").first["result"] = 1
    payload.merge!("decision" => "reject", "next_edge" => "stop", "status" => "rejected")
    write(payload)
    assert validate[:status].success?

    payload = document
    payload.merge!("decision" => "reject", "next_edge" => "stop", "status" => "rejected")
    write(payload)
    result = validate
    refute result[:status].success?
    assert_includes result[:stderr], "all applicable floors require eligible_for_director_review"
  end

  def test_rejects_status_and_role_context_pack_binding_drift
    payload = document
    payload["status"] = "hold"
    payload.fetch("execution_binding").fetch("role_context_pack")["sha256"] = "0" * 64
    write(payload)
    result = validate
    refute result[:status].success?
    assert_includes result[:stderr], "status must exact-copy"
    assert_includes result[:stderr], "Role Context Pack SHA-256 is stale"
  end

  def test_rejects_author_session_that_differs_from_dispatch_writer_session
    payload = document
    payload.fetch("execution_binding")["author_session_id"] = "SESSION_OTHER"
    write(payload)

    result = validate

    refute result[:status].success?
    assert_includes result[:stderr], "author_session_id differs from dispatch output_writer.session_id"
  end

  def test_rejects_tampered_output_bytes_through_full_manifest_verification
    payload = document
    @source.write(@source.read + "tampered: true\n")
    write(payload)

    result = validate

    refute result[:status].success?
    assert_includes result[:stderr], "evaluated output manifest failed full verification (stale_output_sha)"
  end

  def test_rejects_declared_source_outside_verified_manifest_outputs
    payload = document
    unrelated = @dir.join("unrelated.yaml")
    unrelated.write("result: unrelated\n")
    payload.fetch("source_artifacts") << {
      "path" => unrelated.relative_path_from(ROOT).to_s,
      "sha256" => Digest::SHA256.file(unrelated).hexdigest,
      "locator" => "not produced by the bound dispatch"
    }
    write(payload)

    result = validate

    refute result[:status].success?
    assert_includes result[:stderr], "source_artifacts must be an exact subset of the fully verified output manifest"
  end

  def test_rejects_free_form_applicability_field_even_when_value_and_hash_match
    payload = document
    evidence = payload.fetch("applicability_evidence").find { |row| row["tag"] == "motion_reference" }
    evidence["json_pointer"] = "/untyped_flag"
    evidence["expected_value"] = "motion_reference"
    evidence["value_sha256"] = structured_sha("motion_reference")
    write(payload)

    result = validate

    refute result[:status].success?
    assert_includes result[:stderr], "does not end at an allowed typed evidence field"
  end

  def test_rejects_applicability_evidence_kind_that_does_not_match_tag
    payload = document
    evidence = payload.fetch("applicability_evidence").find { |row| row["tag"] == "motion_reference" }
    evidence["evidence_kind"] = "scope_applicability"
    write(payload)

    result = validate

    refute result[:status].success?
    assert_includes result[:stderr], "evidence_kind differs from the registered tag kind"
  end

  def test_decision_selects_exact_graph_edge
    payload = document
    payload["decision"] = "combine_or_correct"
    payload["next_edge"] = "director_review"
    write(payload)
    result = validate
    refute result[:status].success?
    assert_includes result[:stderr], "next_edge must exact-copy"
  end

  def test_rejects_stale_source_and_wrong_checkpoint
    payload = document
    payload.fetch("source_artifacts").first["sha256"] = "0" * 64
    payload["checkpoint_id"] = "section_03v_motion"
    write(payload)
    result = validate
    refute result[:status].success?
    assert_includes result[:stderr], "SHA-256 is stale"
    assert_includes result[:stderr], "checkpoint_id is outside"
  end

  def test_rejects_profile_allowed_but_checkpoint_wrong_exact_graph_tuple
    payload = profile_document(
      profile_id: "draft_keyframe_proof",
      checkpoint_id: "p3_draft_keyframe_proof",
      stage_id: "front_planning_integration",
      reviewer_role: "planning_cdd_p3_ci",
      ids: %w[cut_screen_job_neighbor_delta character_visual scene_visual_package action_pose_motion_readiness angle_distance_depth_crop_transition_diversity reference_transfer_generation_feasibility prop_interaction_readability],
      fours: %w[scene_visual_package action_pose_motion_readiness angle_distance_depth_crop_transition_diversity]
    )
    payload["checkpoint_id"] = "p1_g40_integration_handoff"
    write(payload)

    result = validate

    refute result[:status].success?
    assert_includes result[:stderr], "Role Context Pack checkpoint differs from judgment"
    refute_includes result[:stderr], "checkpoint_id is outside the judgment profile"
  end

  def test_rejects_profile_allowed_but_reviewer_wrong_exact_graph_tuple
    payload = profile_document(
      profile_id: "pre_fp_storyline",
      checkpoint_id: "p1_story_audience_lead",
      stage_id: "creative_route_discovery",
      reviewer_role: "planning_cdd_p1",
      ids: %w[whole_film_opening_to_ending_causality target_audience_promise_lock message_progression_without_repetition storyline_reference_influence_accounting],
      fours: %w[whole_film_opening_to_ending_causality],
      target_message_treatment: "score_and_lock_pre_fp_only"
    )
    payload["reviewer_role"] = "overall_director"
    payload.fetch("execution_binding")["author_role"] = "overall_director"
    write(payload)

    result = validate

    refute result[:status].success?
    assert_includes result[:stderr], "Role Context Pack role differs from judgment"
    refute_includes result[:stderr], "reviewer_role is outside the judgment profile"
  end

  def test_rejects_profile_allowed_but_stage_wrong_exact_graph_tuple
    payload = profile_document(
      profile_id: "reference_candidate",
      checkpoint_id: "p2_visual_reference_development",
      stage_id: "creative_route_discovery",
      reviewer_role: "planning_cdd_p2",
      ids: %w[current_work_function_specificity source_evidence_legibility_and_provenance target_section_or_story_gap_fit source_to_screen_transfer_boundary motion_temporal_change_and_landing still_camera_composition_depth_value role_synthesis_collision_risk],
      fours: %w[motion_temporal_change_and_landing still_camera_composition_depth_value],
      tags: %w[motion_reference composition_function_present],
      target_message_treatment: "inherit_pre_fp_locks_check_alignment_only"
    )
    payload["stage_id"] = "front_planning_integration"
    write(payload)

    result = validate

    refute result[:status].success?
    assert_includes result[:stderr], "Role Context Pack stage differs from judgment"
    refute_includes result[:stderr], "stage_id is outside the judgment profile"
  end

  def test_03v_performance_is_optional_only_when_absent
    payload = profile_document(
      profile_id: "playback_03v",
      checkpoint_id: "v_ci_03v_playback_review",
      stage_id: "video_playback_review",
      reviewer_role: "section_cluster_cdd_ci",
      ids: %w[subject_body_action_pose_transition temporal_camera_route_or_locked_hold audio_trigger_landing_edit_handoff depth_parallax_occlusion_reveal_stop neighbor_whole_section_motion_diversity identity_light_state_geometry_stability performance_readability],
      fours: %w[subject_body_action_pose_transition temporal_camera_route_or_locked_hold audio_trigger_landing_edit_handoff]
    )
    performance = payload.fetch("criteria").last
    payload["applicability_tags"] << "no_performance_job"
    payload["applicability_evidence"] << applicability_evidence("no_performance_job")
    performance["result"] = "not_applicable"
    performance["not_applicable_reason"] = "This title has no performance job."
    write(payload)
    result = validate
    assert result[:status].success?, result[:stderr]

    payload["performance_mode"] = "primary"
    payload["applicability_tags"].delete("no_performance_job")
    payload["applicability_evidence"].reject! { |row| row["tag"] == "no_performance_job" }
    payload["performance_mode_evidence"] = performance_mode_evidence
    write(payload)
    result = validate
    refute result[:status].success?
    assert_includes result[:stderr], "performance_readability cannot be not_applicable"

    performance.delete("not_applicable_reason")
    performance["result"] = 3
    write(payload)
    result = validate
    assert result[:status].success?, result[:stderr]
  end

  def test_rejects_unbound_no_performance_assertion
    payload = profile_document(
      profile_id: "playback_03v",
      checkpoint_id: "v_ci_03v_playback_review",
      stage_id: "video_playback_review",
      reviewer_role: "section_cluster_cdd_ci",
      ids: %w[subject_body_action_pose_transition temporal_camera_route_or_locked_hold audio_trigger_landing_edit_handoff depth_parallax_occlusion_reveal_stop neighbor_whole_section_motion_diversity identity_light_state_geometry_stability performance_readability],
      fours: %w[subject_body_action_pose_transition temporal_camera_route_or_locked_hold audio_trigger_landing_edit_handoff]
    )
    performance = payload.fetch("criteria").last
    performance["result"] = "not_applicable"
    performance["not_applicable_reason"] = "The author asserted that this title has no performance job."
    write(payload)

    result = validate

    refute result[:status].success?
    assert_includes result[:stderr], "performance_mode none requires exact no_performance_job applicability evidence"
  end

  def test_rejects_primary_performance_mode_without_exact_source_evidence
    payload = profile_document(
      profile_id: "playback_03v",
      checkpoint_id: "v_ci_03v_playback_review",
      stage_id: "video_playback_review",
      reviewer_role: "section_cluster_cdd_ci",
      ids: %w[subject_body_action_pose_transition temporal_camera_route_or_locked_hold audio_trigger_landing_edit_handoff depth_parallax_occlusion_reveal_stop neighbor_whole_section_motion_diversity identity_light_state_geometry_stability performance_readability],
      fours: %w[subject_body_action_pose_transition temporal_camera_route_or_locked_hold audio_trigger_landing_edit_handoff]
    )
    payload["performance_mode"] = "primary"
    write(payload)

    result = validate

    refute result[:status].success?
    assert_includes result[:stderr], "performance_mode_evidence"
  end

  def test_rejects_primary_performance_evidence_from_untyped_field
    payload = profile_document(
      profile_id: "playback_03v",
      checkpoint_id: "v_ci_03v_playback_review",
      stage_id: "video_playback_review",
      reviewer_role: "section_cluster_cdd_ci",
      ids: %w[subject_body_action_pose_transition temporal_camera_route_or_locked_hold audio_trigger_landing_edit_handoff depth_parallax_occlusion_reveal_stop neighbor_whole_section_motion_diversity identity_light_state_geometry_stability performance_readability],
      fours: %w[subject_body_action_pose_transition temporal_camera_route_or_locked_hold audio_trigger_landing_edit_handoff]
    )
    payload["performance_mode"] = "primary"
    payload["performance_mode_evidence"] = performance_mode_evidence("/untyped_mode")
    write(payload)

    result = validate

    refute result[:status].success?
    assert_includes result[:stderr], "does not end at an allowed typed performance field"
  end

  def test_every_registered_stage_profile_accepts_its_exact_floor_vector
    each_registered_stage_profile do |profile, payload, _selection|
      write(payload)
      result = validate
      if profile.fetch("profile_id") == "pixel_02b"
        refute result[:status].success?, "#{profile.fetch('profile_id')} yaml-only floor must not silently accept empty Cut targets"
        assert_includes result[:stderr], "pixel_02b requires Cut image targets from hash-bound generated image outputs or idol_generated_branch_cut_review.v4 branch_cut_reviews image_path/image_sha256"
        next
      end
      assert result[:status].success?, "#{profile.fetch('profile_id')}: #{result[:stderr]}"
    end
  end

  def test_every_registered_stage_profile_has_an_independent_production_review_consumer
    each_registered_stage_profile do |profile, payload, selection|
      next if profile.fetch("profile_id") == "pixel_02b"
      write(payload)
      review_stage = selection.dig(:reviewer, "role") == "overall_director" ? "mv_storyboard_direction" : selection.fetch(:stage_id)
      fixture = IdolGraphProductionReviewFixture.build(
        root: ROOT, judgment_path: @path, directory: @dir.join("director-#{profile.fetch('profile_id')}"),
        review_stage: review_stage
      )
      result = IdolGraphProductionReviewContract.verify!(
        root: ROOT, review_pointer: file_pointer(fixture["envelope_path"]), expected_judgment: file_pointer(@path)
      )
      assert_equal profile.fetch("profile_id"), result.dig("input", "profile_id")
      assert_equal "accept", result.dig("output", "decision")
      refute_equal result.dig("input", "author_session_id"), result.dig("output", "reviewer_session_id")
    end
  end

  def test_pixel_02b_active_entrypoint_holds_when_no_typed_g2_cut_target_exists
    payload = pixel_02b_payload
    write(payload)
    result = validate
    refute result[:status].success?
    assert_includes result[:stderr], "pixel_02b requires Cut image targets from hash-bound generated image outputs or idol_generated_branch_cut_review.v4 branch_cut_reviews image_path/image_sha256"
    historical = validate(mode: "historical_audit")
    assert historical[:status].success?, historical[:stderr]
  end

  def test_pixel_02b_public_entrypoint_rejects_incomplete_g2_cut_coverage
    payload = pixel_02b_payload
    attach_pixel_02b_manifest_outputs!(payload, g2_reviews: true)
    write(payload)
    result = validate
    refute result[:status].success?
    assert_includes result[:stderr], "evidence does not cover every exact target Cut image"
  end

  def test_pixel_02b_public_entrypoint_keeps_cut_whose_filename_contains_contact_sheet
    payload = pixel_02b_payload
    cuts = attach_pixel_02b_manifest_outputs!(payload, g2_reviews: true, cover_cuts: true)
    write(payload)
    result = validate
    assert result[:status].success?, result[:stderr]
    selection = execution_selection("pixel_02b")
    review_stage = selection.dig(:reviewer, "role") == "overall_director" ? "mv_storyboard_direction" : selection.fetch(:stage_id)
    fixture = IdolGraphProductionReviewFixture.build(
      root: ROOT, judgment_path: @path, directory: @dir.join("director-pixel-02b-g2"),
      review_stage: review_stage
    )
    targets = fixture.fetch("input").fetch("inspection_targets").map { |row| row.fetch("path") }
    assert_includes targets, cuts.fetch("named_cut").fetch("path")
    assert_includes targets, cuts.fetch("branch").fetch("path")
    verified = IdolGraphProductionReviewContract.verify!(
      root: ROOT, review_pointer: file_pointer(fixture["envelope_path"]), expected_judgment: file_pointer(@path)
    )
    assert_equal "accept", verified.dig("output", "decision")
  end

  def test_pixel_02b_public_entrypoint_holds_on_mixed_valid_and_malformed_g2_row
    payload = pixel_02b_payload
    attach_pixel_02b_manifest_outputs!(payload, g2_reviews: true, malformed_row: true)
    write(payload)
    result = validate
    refute result[:status].success?
    assert_includes result[:stderr], "branch_cut_reviews[1] is missing image_path/image_sha256"
  end

  def test_pixel_02b_public_entrypoint_covers_direct_generated_png_without_g2_review
    payload = pixel_02b_payload
    images = attach_pixel_02b_manifest_outputs!(payload, direct_images: 1, cover_direct: 1)
    write(payload)
    result = validate
    assert result[:status].success?, result[:stderr]
    selection = execution_selection("pixel_02b")
    review_stage = selection.dig(:reviewer, "role") == "overall_director" ? "mv_storyboard_direction" : selection.fetch(:stage_id)
    fixture = IdolGraphProductionReviewFixture.build(
      root: ROOT, judgment_path: @path, directory: @dir.join("director-pixel-02b-direct-png"),
      review_stage: review_stage
    )
    targets = fixture.fetch("input").fetch("inspection_targets").map { |row| row.fetch("path") }
    assert_includes targets, images.fetch(0).fetch("path")
    verified = IdolGraphProductionReviewContract.verify!(
      root: ROOT, review_pointer: file_pointer(fixture["envelope_path"]), expected_judgment: file_pointer(@path)
    )
    assert_equal "accept", verified.dig("output", "decision")
  end

  def test_pixel_02b_public_entrypoint_holds_when_two_direct_images_omit_one
    payload = pixel_02b_payload
    attach_pixel_02b_manifest_outputs!(payload, direct_images: 2, cover_direct: 1)
    write(payload)
    result = validate
    refute result[:status].success?
    assert_includes result[:stderr], "evidence does not cover every exact target Cut image"
  end

  def test_rejects_schema_invalid_bound_dispatch
    payload = document
    dispatch = YAML.safe_load(@dispatch_path.read, aliases: true)
    dispatch.delete("provider_binding")
    @dispatch_path.write(YAML.dump(dispatch))
    payload.fetch("execution_binding")["dispatch"] = file_pointer(@dispatch_path)
    write(payload)

    result = validate

    refute result[:status].success?
    assert_includes result[:stderr], "execution dispatch failed Graph Department Dispatch schema validation"
  end

  def test_rejects_tampered_dispatch_goal_terminal_event_bytes
    payload = document
    event = YAML.safe_load(@goal_event_path.read, aliases: true)
    event["goal_text"] = "Tampered Goal text with no matching dispatch update."
    @goal_event_path.write(YAML.dump(event))
    write(payload)

    result = validate

    refute result[:status].success?
    assert_includes result[:stderr], "execution Dispatch Goal terminal event failed exact verification"
    assert_includes result[:stderr], "stale_terminal_event_sha"
  end

  def test_rejects_incomplete_or_tampered_bound_role_context_pack
    payload = document
    pack = YAML.safe_load(@pack_path.read, aliases: true)
    pack.delete("instruction_slices")
    @pack_path.write(YAML.dump(pack))
    payload.fetch("execution_binding")["role_context_pack"] = file_pointer(@pack_path)
    write(payload)

    result = validate

    refute result[:status].success?
    assert_includes result[:stderr], "execution Role Context Pack failed schema validation"

    payload = document
    pack = YAML.safe_load(@pack_path.read, aliases: true)
    pack["unload_after"] = "tampered_checkpoint_boundary"
    @pack_path.write(YAML.dump(pack))
    payload.fetch("execution_binding")["role_context_pack"] = file_pointer(@pack_path)
    write(payload)

    result = validate

    refute result[:status].success?
    assert_includes result[:stderr], "execution Role Context Pack failed full projection validation"
    assert_includes result[:stderr], "graph unload_after differs from the exact profile checkpoint"
  end

  def test_rejects_role_context_pack_dispatch_identity_drift
    payload = document
    pack = YAML.safe_load(@pack_path.read, aliases: true)
    pack.fetch("graph_dispatch_identity")["lane_id"] = "planning_p1"
    @pack_path.write(YAML.dump(pack))
    payload.fetch("execution_binding")["role_context_pack"] = file_pointer(@pack_path)
    write(payload)

    result = validate

    refute result[:status].success?
    assert_includes result[:stderr], "Role Context Pack stable dispatch identity differs from the returned execution Dispatch"
  end

  def test_released_judgment_remains_valid_after_current_profile_changes
    Dir.mktmpdir("graph-contextual-contract-root-") do |directory|
      alternate_root = Pathname.new(directory)
      copy_contract_closure(alternate_root)
      relative_run_dir = @dir.relative_path_from(ROOT)
      alternate_run_dir = alternate_root.join(relative_run_dir)
      alternate_run_dir.dirname.mkpath
      FileUtils.cp_r(@dir, alternate_run_dir)

      registry_path = alternate_root.join("automation", "graph-creative-judgment-registry.yaml")
      registry = YAML.safe_load(registry_path.read, aliases: true)
      registry.fetch("profiles").find { |row| row["profile_id"] == "reference_candidate" }["profile_id"] = "reference_candidate_shadow"
      registry_path.write(YAML.dump(registry))

      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby,
        SCRIPT.to_s,
        "--root",
        alternate_root.to_s,
        "--mode",
        "historical_audit",
        alternate_run_dir.join("judgment.yaml").to_s,
        chdir: ROOT.to_s
      )

      assert status.success?, stderr
      assert_includes stdout, "historical audit valid; promotion forbidden"

      _active_stdout, active_stderr, active_status = Open3.capture3(
        RbConfig.ruby,
        SCRIPT.to_s,
        "--root",
        alternate_root.to_s,
        alternate_run_dir.join("judgment.yaml").to_s,
        chdir: ROOT.to_s
      )
      refute active_status.success?
      assert_includes active_stderr, "graph creative judgment registry failed semantic validation"
    end
  end

  private

  def each_registered_stage_profile
    registry = YAML.safe_load(ROOT.join("automation", "graph-creative-judgment-registry.yaml").read, aliases: true)

    registry.fetch("profiles").each do |profile|
      selection = execution_selection(profile.fetch("profile_id"))
      tags = profile.fetch("criteria").map { |row| row["applies_when"] }.compact
      performance_mode = "none"
      payload = profile_document(
        profile_id: profile.fetch("profile_id"),
        checkpoint_id: selection.fetch(:checkpoint_id),
        stage_id: selection.fetch(:stage_id),
        reviewer_role: selection.fetch(:reviewer_role),
        ids: profile.fetch("criteria").map { |row| row.fetch("criterion_id") },
        fours: profile.fetch("criteria").map { |row| row.fetch("criterion_id") if row.fetch("critical_four") }.compact,
        tags: tags,
        target_message_treatment: profile.fetch("target_message_treatment")
      )
      payload["performance_mode"] = performance_mode
      performance = payload.fetch("criteria").find { |row| row["criterion_id"] == "performance_readability" }
      if performance_mode == "none" && performance
        payload["applicability_tags"] << "no_performance_job"
        payload["applicability_evidence"] << applicability_evidence("no_performance_job")
        performance["result"] = "not_applicable"
        performance["not_applicable_reason"] = "This exact title scope has no performance job."
      end

      yield profile, payload, selection
    end
  end


  def document
    profile_document(
      profile_id: "reference_candidate",
      checkpoint_id: "p2_visual_reference_development",
      stage_id: "creative_route_discovery",
      reviewer_role: "planning_cdd_p2",
      ids: %w[current_work_function_specificity source_evidence_legibility_and_provenance target_section_or_story_gap_fit source_to_screen_transfer_boundary motion_temporal_change_and_landing still_camera_composition_depth_value role_synthesis_collision_risk],
      fours: %w[motion_temporal_change_and_landing still_camera_composition_depth_value],
      tags: %w[motion_reference composition_function_present],
      target_message_treatment: "inherit_pre_fp_locks_check_alignment_only"
    )
  end

  def profile_document(profile_id:, checkpoint_id:, stage_id:, reviewer_role:, ids:, fours:, tags: [], target_message_treatment: nil)
    treatment = target_message_treatment || "inherit_pre_fp_locks_check_playback_realization_only"
    assignment_id = "DISPATCH_#{profile_id.upcase}"
    execution_binding = write_execution_binding(
      assignment_id: assignment_id,
      profile_id: profile_id,
      checkpoint_id: checkpoint_id,
      stage_id: stage_id,
      reviewer_role: reviewer_role
    )
    {
      "schema_version" => "idol_graph_contextual_judgment.v2",
      "artifact_type" => "graph_contextual_judgment",
      "profile_id" => profile_id,
      "checkpoint_id" => checkpoint_id,
      "stage_id" => stage_id,
      "scope_id" => assignment_id,
      "authoring_owner" => "human_or_assigned_model",
      "reviewer_role" => reviewer_role,
      "performance_mode" => "none",
      "applicability_tags" => tags,
      "applicability_evidence" => tags.map { |tag| applicability_evidence(tag) },
      "execution_binding" => execution_binding,
      "source_artifacts" => [{"path" => @source.relative_path_from(ROOT).to_s, "sha256" => Digest::SHA256.file(@source).hexdigest, "locator" => "exact reviewed bytes"}],
      "criteria" => ids.map { |id| criterion(id, fours.include?(id) ? 4 : 3) },
      "hard_gate_findings" => [],
      "decision" => "eligible_for_director_review",
      "next_edge" => "director_review",
      "target_message_treatment" => treatment,
      "aggregate_score_present" => false,
      "automatic_creative_pass" => false,
      "status" => "ready_for_director_review"
    }
  end

  def criterion(id, result)
    {
      "criterion_id" => id,
      "result" => result,
      "evidence_locator" => [file_pointer(@source)],
      "observable_claim" => "The exact evidence visibly supports #{id}.",
      "screen_consequence" => "The named screen or playback job remains legible.",
      "preserve" => "Preserve the verified source function and strongest visible fact.",
      "change" => "Change only the bounded weakness if the grade drops.",
      "do_not_infer" => "Do not infer creative PASS or an unrelated section decision.",
      "correction_action" => "Return the exact scope to its current owner for correction.",
      "acceptance_evidence" => "Re-review exact corrected bytes with the same criterion."
    }
  end

  def applicability_evidence(tag)
    binding = {
      "motion_reference" => ["reference_role", "/reference_role"],
      "composition_function_present" => ["reference_function", "/function_analysis/0/purpose"],
      "no_performance_job" => ["performance_mode", "/no_performance_scope/performance_mode"]
    }.fetch(tag)
    evidence_kind, pointer = binding
    source = YAML.safe_load(@source.read, aliases: true)
    value = pointer_value(source, pointer)
    {
      "tag" => tag,
      "evidence_kind" => evidence_kind,
      "source_path" => @source.relative_path_from(ROOT).to_s,
      "json_pointer" => pointer,
      "value_sha256" => structured_sha(value),
      "expected_value" => value
    }
  end

  def performance_mode_evidence(pointer = "/performance_scope/performance_mode")
    source = YAML.safe_load(@source.read, aliases: true)
    value = pointer_value(source, pointer)
    {
      "evidence_kind" => "performance_mode",
      "source_path" => @source.relative_path_from(ROOT).to_s,
      "json_pointer" => pointer,
      "value_sha256" => structured_sha(value),
      "expected_value" => value
    }
  end

  def write_execution_binding(assignment_id:, profile_id:, checkpoint_id:, stage_id:, reviewer_role:)
    profile = YAML.safe_load(ROOT.join("automation", "graph-creative-judgment-registry.yaml").read, aliases: true)
      .fetch("profiles").find { |row| row.fetch("profile_id") == profile_id }
    input_digest = "4" * 64
    goal_id = "GOAL_#{profile_id.upcase}"
    goal_text = "Validate the exact #{profile_id} contextual judgment fixture."
    goal_text_sha = Digest::SHA256.hexdigest(goal_text.encode(Encoding::UTF_8))
    author_session_id = "SESSION_#{profile_id.upcase}"
    source_path = @source.relative_path_from(ROOT).to_s
    selection = execution_selection(profile_id)
    sections = selection.fetch(:section_ids)
    provider, provider_holds = IdolRoleContextPack.resolve_provider(
      root: ROOT,
      role: reviewer_role,
      provider: "grok",
      runtime_surface: "grok_build_cli_acp",
      logical_profile_alias: "frontier_director"
    )
    raise "fixture provider did not resolve: #{provider_holds.join(', ')}" unless provider_holds.empty?
    manifest_path = @dir.join("#{profile_id}-output-manifest.yaml")
    manifest_path.write(YAML.dump(
      "schema_version" => "idol-graph-output-manifest.v1",
      "artifact_type" => "graph_dispatch_output_manifest",
      "dispatch_id" => assignment_id,
      "assigned_owner" => reviewer_role,
      "input_digest_sha256" => input_digest,
      "output_kind" => "contextual_judgment_fixture",
      "outputs" => [{"path" => source_path, "sha256" => Digest::SHA256.file(@source).hexdigest}]
    ))
    manifest_pointer = file_pointer(manifest_path)
    profile_hash = structured_sha(profile)
    goal_event_path = @dir.join("#{profile_id}-goal-terminal-event.yaml")
    goal_event_path.write(YAML.dump(
      "schema_version" => "idol-graph-provider-goal-terminal-event.v1",
      "artifact_type" => "graph_provider_goal_terminal_event",
      "evidence_class" => "provider_native_terminal_event",
      "provider" => provider.fetch("provider"),
      "native_goal_id" => goal_id,
      "goal_text" => goal_text,
      "goal_text_sha256" => goal_text_sha,
      "goal_semantics" => "grok_goal_completed_admission",
      "terminal_state" => "complete",
      "last_event" => "goal_completed"
    ))
    @goal_event_path = goal_event_path
    goal_event_pointer = file_pointer(goal_event_path)
    goal_event_sha = goal_event_pointer.fetch("sha256")
    dispatch_base = {
      "schema_version" => "idol-graph-department-dispatch.v1",
      "artifact_type" => "graph_department_dispatch",
      "dispatch_id" => assignment_id,
      "run" => "runs/fixture-title/fixture-album/FIXTURE_RUN",
      "lane_id" => selection.fetch(:lane_id),
      "section_cohort_id" => selection.fetch(:section_cohort_id),
      "section_ids" => sections,
      "logical_role" => selection.fetch(:logical_role),
      "assigned_owner" => reviewer_role,
      "output_writer" => {
        "owner" => reviewer_role,
        "role" => selection.fetch(:logical_role),
        "session_id" => author_session_id
      },
      "reviewer" => selection.fetch(:reviewer),
      "return_recipient" => selection.fetch(:return_recipient),
      "provider_binding" => {
        "registered_provider" => provider.fetch("provider"),
        "runtime_surface" => provider.fetch("runtime_surface"),
        "logical_profile_alias" => provider.fetch("logical_profile_alias"),
        "execution_profile_id" => provider.fetch("provider_profile_id"),
        "resolved_provider_model" => provider.fetch("exact_model"),
        "reasoning_effort" => provider.fetch("reasoning_effort"),
        "provider_capability_snapshot_sha256" => provider.fetch("registry_sha256"),
        "fallback_allowed" => false,
        "silent_substitution_allowed" => false
      },
      "goal_evidence" => {
        "native_goal_id" => goal_id,
        "goal_text_sha256" => goal_text_sha,
        "goal_semantics" => "grok_goal_completed_admission",
        "goal_terminal_state" => "complete",
        "goal_last_event" => "goal_completed",
        "goal_terminal_event_sha256" => goal_event_sha,
        "terminal_event" => goal_event_pointer
      },
      "input_digest_sha256" => input_digest,
      "bounded_output" => {
        "output_kind" => "contextual_judgment_fixture",
        "expected_paths" => [source_path],
        "maximum_artifact_count" => 1
      },
      "judgment_profile_id" => profile_id,
      "stop_conditions" => ["stale_bound_source"],
      "assignment_pass" => false
    }
    launch_dispatch_path = @dir.join("#{profile_id}-launch-dispatch.yaml")
    launch_dispatch_path.write(YAML.dump(dispatch_base.merge(
      "output_manifest" => nil,
      "lifecycle_state" => "launched",
      "legal_next" => %w[returned hold],
      "lifecycle_from" => "prepared"
    )))
    @launch_dispatch_path = launch_dispatch_path
    launch_dispatch_pointer = file_pointer(launch_dispatch_path)
    dispatch_path = @dir.join("#{profile_id}-dispatch.yaml")
    dispatch_path.write(YAML.dump(dispatch_base.merge(
      "output_manifest" => manifest_pointer,
      "lifecycle_state" => "returned",
      "legal_next" => %w[reviewed hold],
      "lifecycle_from" => "launched"
    )))
    @dispatch_path = dispatch_path
    dispatch_pointer = file_pointer(dispatch_path)
    switch_receipt = {
      "receipt_id" => "GRAPH_SWITCH_CONTEXTUAL_JUDGMENT_FIXTURE_001",
      "founder_authority" => "founder",
      "graph_revision" => "idol-graph-skill-load-profiles.v1",
      "switch_boundary" => "new_runs_only_after_verified_receipt",
      "source_set_sha256" => IdolRoleContextPack.graph_source_set_sha256(ROOT),
      "verified_at" => "2026-09-03T00:00:00+09:00"
    }
    @switch_receipt = switch_receipt
    @pack_build_args = {
      root: ROOT,
      run_root: "runs/fixture-title/fixture-album/FIXTURE_RUN",
      assignment_id: assignment_id,
      role: reviewer_role,
      profile_id: reviewer_role,
      checkpoint_id: checkpoint_id,
      stage_id: stage_id,
      section_ids: sections,
      source_envelope: {"kind" => "department_dispatch", "path" => launch_dispatch_pointer.fetch("path"), "sha256" => launch_dispatch_pointer.fetch("sha256")},
      current_state: "launched",
      scope: {"stage_id" => stage_id, "section_ids" => sections},
      authority: {"assigned_owner" => reviewer_role, "promotion_owner" => "overall_director"},
      output_contract: {"kind" => "contextual_judgment_fixture"},
      hold_conditions: ["stale_bound_source"],
      return_recipient: selection.fetch(:return_recipient),
      provider: "grok",
      runtime_surface: "grok_build_cli_acp",
      writer: "graph_v2",
      run_class: "new_run",
      switch_receipt: switch_receipt
    }
    pack = IdolRoleContextPack.build(**@pack_build_args)
    pack_path = @dir.join("#{profile_id}-role-context-pack.yaml")
    pack_path.write(YAML.dump(pack))
    @pack_path = pack_path
    {
      "assignment_id" => assignment_id,
      "author_role" => reviewer_role,
      "author_session_id" => author_session_id,
      "dispatch" => dispatch_pointer,
      "goal_id" => goal_id,
      "goal_terminal_event_sha256" => goal_event_sha,
      "role_context_pack" => file_pointer(pack_path),
      "profile_release" => pack.fetch("creative_judgment_contract").fetch("profile_release"),
      "profile_value_sha256" => profile_hash,
      "input_digest_sha256" => input_digest,
      "output_manifest" => manifest_pointer
    }
  end

  def pixel_02b_payload
    registry = YAML.safe_load(ROOT.join("automation", "graph-creative-judgment-registry.yaml").read, aliases: true)
    profile = registry.fetch("profiles").find { |row| row.fetch("profile_id") == "pixel_02b" }
    selection = execution_selection("pixel_02b")
    profile_document(
      profile_id: "pixel_02b",
      checkpoint_id: selection.fetch(:checkpoint_id),
      stage_id: selection.fetch(:stage_id),
      reviewer_role: selection.fetch(:reviewer_role),
      ids: profile.fetch("criteria").map { |row| row.fetch("criterion_id") },
      fours: profile.fetch("criteria").map { |row| row.fetch("criterion_id") if row.fetch("critical_four") }.compact,
      tags: [],
      target_message_treatment: profile.fetch("target_message_treatment")
    )
  end

  def attach_pixel_02b_manifest_outputs!(payload, g2_reviews: false, cover_cuts: false, malformed_row: false, direct_images: 0, cover_direct: 0)
    named = @dir.join("contact-sheet-named-cut.png")
    branch = @dir.join("branch-cut.png")
    named.write("typed generated cut whose filename contains contact-sheet")
    branch.write("typed generated branch cut")
    named_rel = named.relative_path_from(ROOT).to_s
    branch_rel = branch.relative_path_from(ROOT).to_s
    named_sha = Digest::SHA256.file(named).hexdigest
    branch_sha = Digest::SHA256.file(branch).hexdigest
    source_rel = @source.relative_path_from(ROOT).to_s
    outputs = [
      {"path" => source_rel, "sha256" => Digest::SHA256.file(@source).hexdigest}
    ]
    direct_refs = []
    Integer(direct_images).times do |index|
      path = @dir.join("generated-cut-#{index + 1}.png")
      path.write("generated pixel #{index + 1}")
      direct_refs << file_pointer(path)
    end
    outputs.concat(direct_refs)
    review_rel = nil
    named_row = nil
    branch_row = nil
    if g2_reviews
      named_row = {
        "packet_id" => "PKT_BC01_NAMED",
        "branch_cut_id" => "BC01_NAMED",
        "section_id" => "S01",
        "core_cut_id" => "C01",
        "image_path" => named_rel,
        "image_sha256" => named_sha,
        "media_kind" => "contact_sheet"
      }
      branch_row = {
        "packet_id" => "PKT_BC01_ACTION",
        "branch_cut_id" => "BC01_ACTION",
        "section_id" => "S01",
        "core_cut_id" => "C01",
        "image_path" => branch_rel,
        "image_sha256" => branch_sha
      }
      branch_row.delete("image_sha256") if malformed_row
      review_path = @dir.join("g2-review.yaml")
      review_path.write(YAML.dump(
        "schema_version" => "idol_generated_branch_cut_review.v4",
        "branch_cut_reviews" => [named_row, branch_row]
      ))
      review_rel = review_path.relative_path_from(ROOT).to_s
      outputs.insert(1, {"path" => review_rel, "sha256" => Digest::SHA256.file(review_path).hexdigest})
    end
    manifest_path = @dir.join("pixel_02b-output-manifest.yaml")
    manifest = YAML.safe_load(manifest_path.read, aliases: true)
    manifest["outputs"] = outputs
    manifest_path.write(YAML.dump(manifest))
    manifest_pointer = file_pointer(manifest_path)
    dispatch = YAML.safe_load(@dispatch_path.read, aliases: true)
    dispatch["bounded_output"]["expected_paths"] = outputs.map { |row| row["path"] }
    dispatch["bounded_output"]["maximum_artifact_count"] = outputs.length
    dispatch["output_manifest"] = manifest_pointer
    @dispatch_path.write(YAML.dump(dispatch))
    payload.fetch("execution_binding")["dispatch"] = file_pointer(@dispatch_path)
    payload.fetch("execution_binding")["output_manifest"] = manifest_pointer
    launch = YAML.safe_load(@launch_dispatch_path.read, aliases: true)
    returned = YAML.safe_load(@dispatch_path.read, aliases: true)
    pack = YAML.safe_load(@pack_path.read, aliases: true)
    assert_nil launch["output_manifest"]
    assert_equal file_pointer(@launch_dispatch_path).fetch("sha256"), pack.dig("source_envelope", "sha256")
    assert_equal manifest_pointer, returned.fetch("output_manifest")
    assert_equal manifest_pointer, payload.fetch("execution_binding").fetch("output_manifest")
    source_artifacts = [
      {"path" => source_rel, "sha256" => Digest::SHA256.file(@source).hexdigest, "locator" => "exact reviewed bytes"}
    ]
    if review_rel
      source_artifacts << {"path" => review_rel, "sha256" => Digest::SHA256.file(@dir.join("g2-review.yaml")).hexdigest, "locator" => "exact reviewed bytes"}
    end
    payload["source_artifacts"] = source_artifacts
    if cover_cuts && named_row && branch_row && !malformed_row
      locators = [named_row, branch_row].each_with_index.map do |row, index|
        {
          "path" => review_rel,
          "sha256" => Digest::SHA256.file(@dir.join("g2-review.yaml")).hexdigest,
          "json_pointer" => "/branch_cut_reviews/" + index.to_s,
          "value_sha256" => structured_sha(row)
        }
      end
      payload.fetch("criteria").each { |row| row["evidence_locator"] = locators }
    elsif cover_direct.to_i > 0 && !direct_refs.empty?
      locators = direct_refs.first(cover_direct.to_i)
      payload["source_artifacts"] = locators.map { |row| row.merge("locator" => "exact generated Production Cut pixel bytes") }
      payload.fetch("criteria").each { |row| row["evidence_locator"] = locators }
    end
    if !g2_reviews && !direct_refs.empty?
      direct_refs
    else
      {
        "named_cut" => {"path" => named_rel, "sha256" => named_sha},
        "branch" => {"path" => branch_rel, "sha256" => branch_sha}
      }
    end
  end

  def execution_selection(profile_id)
    {
      "pre_fp_storyline" => {
        reviewer_role: "planning_cdd_p1", checkpoint_id: "p1_story_audience_lead",
        stage_id: "creative_route_discovery", lane_id: "planning_p1", section_cohort_id: nil,
        section_ids: [], logical_role: "planning_cdd",
        reviewer: {"owner" => "overall_director", "role" => "overall_director", "lane_id" => "overall"},
        return_recipient: {"owner" => "overall_director", "role" => "overall_director", "return_route" => "overall_reviewed_milestone"}
      },
      "reference_candidate" => {
        reviewer_role: "planning_cdd_p2", checkpoint_id: "p2_visual_reference_development",
        stage_id: "creative_route_discovery", lane_id: "planning_p2", section_cohort_id: nil,
        section_ids: [], logical_role: "planning_cdd",
        reviewer: {"owner" => "planning_cdd_p1", "role" => "planning_cdd_p1", "lane_id" => "planning_p1"},
        return_recipient: {"owner" => "planning_cdd_p1", "role" => "planning_cdd_p1", "return_route" => "planning_cdd_p1_exact_link"}
      },
      "front_planning_close" => {
        reviewer_role: "planning_cdd_p1", checkpoint_id: "p1_g40_integration_handoff",
        stage_id: "front_planning_integration", lane_id: "planning_p1", section_cohort_id: nil,
        section_ids: [], logical_role: "planning_cdd",
        reviewer: {"owner" => "overall_director", "role" => "overall_director", "lane_id" => "overall"},
        return_recipient: {"owner" => "overall_director", "role" => "overall_director", "return_route" => "overall_reviewed_milestone"}
      },
      "draft_keyframe_proof" => {
        reviewer_role: "planning_cdd_p3_ci", checkpoint_id: "p3_draft_keyframe_proof",
        stage_id: "front_planning_integration", lane_id: "planning_p3_c1", section_cohort_id: "C1",
        section_ids: %w[S01 S02 S03], logical_role: "planning_cdd",
        reviewer: {"owner" => "planning_cdd_p1", "role" => "planning_cdd_p1", "lane_id" => "planning_p1"},
        return_recipient: {"owner" => "planning_cdd_p1", "role" => "planning_cdd_p1", "return_route" => "planning_cdd_p1_exact_link"}
      },
      "pixel_02b" => {
        reviewer_role: "section_cluster_cdd_ci", checkpoint_id: "v_ci_02b_pixel_review",
        stage_id: "generated_branch_cut_review", lane_id: "section_cluster_v_c1", section_cohort_id: "C1",
        section_ids: %w[S01 S02 S03], logical_role: "section_cluster_cdd",
        reviewer: {"owner" => "overall_director", "role" => "overall_director", "lane_id" => "overall"},
        return_recipient: {"owner" => "overall_director", "role" => "overall_director", "return_route" => "overall_reviewed_milestone"}
      },
      "playback_03v" => {
        reviewer_role: "section_cluster_cdd_ci", checkpoint_id: "v_ci_03v_playback_review",
        stage_id: "video_playback_review", lane_id: "section_cluster_v_c1", section_cohort_id: "C1",
        section_ids: %w[S01 S02 S03], logical_role: "section_cluster_cdd",
        reviewer: {"owner" => "overall_director", "role" => "overall_director", "lane_id" => "overall"},
        return_recipient: {"owner" => "overall_director", "role" => "overall_director", "return_route" => "overall_reviewed_milestone"}
      },
      "edit_04_playback" => {
        reviewer_role: "edit_director", checkpoint_id: "edit_qc_section",
        stage_id: "edit_assembly_playback_qc", lane_id: "edit_director", section_cohort_id: nil,
        section_ids: %w[S01], logical_role: "edit_director",
        reviewer: {"owner" => "overall_director", "role" => "overall_director", "lane_id" => "overall"},
        return_recipient: {"owner" => "overall_director", "role" => "overall_director", "return_route" => "overall_reviewed_milestone"}
      }
    }.fetch(profile_id)
  end

  def file_pointer(path)
    {"path" => path.relative_path_from(ROOT).to_s, "sha256" => Digest::SHA256.file(path).hexdigest}
  end

  def copy_contract_closure(destination)
    graph_routing = YAML.safe_load(ROOT.join("automation", "graph-default-routing.yaml").read, aliases: true)
    profile_registry = YAML.safe_load(ROOT.join("automation", "graph-skill-load-profiles.yaml").read, aliases: true)
    pack = YAML.safe_load(@pack_path.read, aliases: true)
    paths = Array(graph_routing.dig("writer_boundary", "active_graph_surfaces"))
    paths.concat(Array(profile_registry["skill_bindings"]).map { |row| row.fetch("path") })
    paths.concat(Array(profile_registry["read_bindings"]).map { |row| row.fetch("path") })
    paths.concat(Array(pack["instruction_slices"]).map { |row| row.fetch("path") })
    paths.concat([
      "automation/graph-default-routing.yaml",
      "automation/graph-role-context-projection.yaml",
      "automation/graph-skill-load-profiles.yaml",
      "automation/graph-creative-judgment-registry.yaml",
      "automation/harness-provider-profile-registry.yaml",
      pack.dig("provider_binding", "provider_source_path"),
      "schemas/graph-creative-judgment-registry.schema.json",
      "schemas/graph-creative-judgment-profile-release.schema.json",
      "schemas/graph-creative-judgment-profile-promotion.schema.json",
      "schemas/graph-contextual-judgment.schema.json",
      "schemas/graph-department-dispatch.schema.json",
      "schemas/role-context-pack.schema.json",
      "scripts/idol-video-python",
      "scripts/validate_graph_contextual_judgment.rb",
      "scripts/validate_graph_judgment_profile_promotion.rb",
      "scripts/validate_json_schema.py"
    ])
    judgment_registry = YAML.safe_load(ROOT.join("automation", "graph-creative-judgment-registry.yaml").read, aliases: true)
    paths.concat(judgment_registry.fetch("current_profile_releases").values.map { |row| row.fetch("path") })
    paths.concat(judgment_registry.fetch("current_profile_releases").values.map { |row| row.dig("promotion_binding", "path") })
    paths.compact.uniq.each do |relative|
      source = ROOT.join(relative)
      target = destination.join(relative)
      target.dirname.mkpath
      FileUtils.cp(source, target)
    end
  end

  def structured_sha(value)
    Digest::SHA256.hexdigest(JSON.generate(canonicalize(value)))
  end

  def pointer_value(source, pointer)
    pointer.split("/").drop(1).reduce(source) do |current, token|
      current.is_a?(Array) ? current.fetch(Integer(token, 10)) : current.fetch(token)
    end
  end

  def canonicalize(value)
    case value
    when Hash
      value.keys.map(&:to_s).sort.each_with_object({}) { |key, memo| memo[key] = canonicalize(value[key]) }
    when Array
      value.map { |item| canonicalize(item) }
    else
      value
    end
  end

  def write(payload)
    @path.write(YAML.dump(payload))
  end

  def validate(mode: nil)
    arguments = [RbConfig.ruby, SCRIPT.to_s]
    arguments.concat(["--mode", mode]) unless mode.nil?
    arguments << @path.to_s
    stdout, stderr, status = Open3.capture3(*arguments, chdir: ROOT.to_s)
    {stdout: stdout, stderr: stderr, status: status}
  end
end
