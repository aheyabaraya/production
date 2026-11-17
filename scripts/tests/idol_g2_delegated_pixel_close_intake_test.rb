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
require_relative "../lib/idol_generated_review_post_pass"
require_relative "../lib/idol_role_context_pack"
require_relative "support/idol_graph_production_review_fixture"
require_relative "../idol_graph_projector"

class IdolG2DelegatedPixelCloseIntakeTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  SCRIPT = ROOT.join("scripts", "idol_g2_delegated_pixel_close_intake.rb")
  CRITERIA = %w[
    visible_scene_job_and_neighbor_delta
    identity_and_character_visual
    scene_visual_package_pixels
    still_composition_camera_depth_crop
    motion_pose_action_anchor
    prop_interaction_pixels
    continuity_and_generation_artifact_stability
  ].freeze

  def setup
    token = "RUN_G2_#{Process.pid}_#{rand(1_000_000)}"
    @run = ROOT.join("runs", "g2-delegated-test", "title", token)
    @tmp = @run
    @review_path = @run.join("review", "generated-review.yaml")
    @review_path.dirname.mkpath
  end

  def teardown
    FileUtils.remove_entry(@tmp) if @tmp&.directory?
    [@run&.parent, @run&.parent&.parent].compact.each do |path|
      Dir.rmdir(path) if path.directory? && path.children.empty?
    end
  end

  def test_declared_hold_returns_hold_without_mutating_review_or_using_fallback
    review = review_document("hold", ["Pixel material drift requires Founder authority."])
    @review_path.write(YAML.dump(review))
    before = Digest::SHA256.file(@review_path).hexdigest

    stdout, stderr, status = Open3.capture3(RbConfig.ruby, SCRIPT.to_s, @review_path.to_s, "--write", chdir: ROOT.to_s)

    assert_equal 2, status.exitstatus, stderr
    result = JSON.parse(stdout)
    assert_equal "hold", result.fetch("status")
    assert_equal "none", result.fetch("automatic_fallback")
    assert_equal false, result.fetch("review_mutated")
    assert_equal before, Digest::SHA256.file(@review_path).hexdigest
  end

  def test_stale_g2_envelope_returns_authority_request_without_mutating_review
    review = review_document("pass", [])
    refresh_pixel_binding(review)
    @review_path.write(YAML.dump(review))
    before = Digest::SHA256.file(@review_path).hexdigest

    stdout, stderr, status = Open3.capture3(RbConfig.ruby, SCRIPT.to_s, @review_path.to_s, "--write", chdir: ROOT.to_s)

    refute status.success?, stderr
    result = JSON.parse(stdout)
    assert_equal "authority_request", result.fetch("status")
    assert_includes result.fetch("reason"), "required file is missing"
    assert_equal "none", result.fetch("automatic_fallback")
    assert_equal false, result.fetch("review_mutated")
    assert_equal before, Digest::SHA256.file(@review_path).hexdigest
  end

  def test_validate_only_accepts_exact_g2_scope_provider_budget_cohort_writer_and_pixel_hashes
    review = review_document("pass", [])
    configure_exact_authority(review)
    refresh_pixel_binding(review)
    @review_path.write(YAML.dump(review))
    before = Digest::SHA256.file(@review_path).hexdigest

    stdout, stderr, status = Open3.capture3(RbConfig.ruby, SCRIPT.to_s, @review_path.to_s, "--validate-only", chdir: ROOT.to_s)

    assert status.success?, "#{stderr}\n#{stdout}"
    result = JSON.parse(stdout)
    assert_equal "validated", result.fetch("status")
    assert_equal "C1", result.fetch("section_cohort_id")
    assert_equal ["S01"], result.fetch("section_ids")
    assert_equal ["PKT_BC01_ACTION"], result.fetch("packet_ids")
    assert_equal false, result.fetch("review_mutated")
    assert_equal before, Digest::SHA256.file(@review_path).hexdigest
  end

  def test_motion_anchor_below_four_returns_authority_request_without_status_promotion
    review = review_document("pass", [])
    configure_exact_authority(review, judgment_results: {"motion_pose_action_anchor" => 3})
    refresh_pixel_binding(review)
    @review_path.write(YAML.dump(review))
    before = Digest::SHA256.file(@review_path).hexdigest

    stdout, stderr, status = Open3.capture3(RbConfig.ruby, SCRIPT.to_s, @review_path.to_s, "--validate-only", chdir: ROOT.to_s)

    refute status.success?, stderr
    result = JSON.parse(stdout)
    assert_equal "authority_request", result.fetch("status")
    assert_includes result.fetch("reason"), "motion_pose_action_anchor"
    assert_includes result.fetch("reason"), "grade 4"
    assert_equal false, result.fetch("review_mutated")
    assert_equal before, Digest::SHA256.file(@review_path).hexdigest
  end

  def test_section_worker_production_review_uses_its_assigned_cohort_director
    review = review_document("pass", [])
    configure_exact_authority(review)
    fixture = IdolGraphProductionReviewFixture.build(
      root: ROOT, judgment_path: @run.join("graph", "contextual-judgment.yaml"),
      directory: @run.join("graph", "production-director-review"), review_stage: "generated_branch_cut_review"
    )
    contract = IdolGraphProductionReviewContract
    result = contract.verify!(root: ROOT, review_pointer: contract.pointer(ROOT, fixture["envelope_path"]))
    assert_equal "creative_development_director", result.dig("output", "reviewer_role")
    assert_equal "pixel_02b", result.dig("input", "profile_id")
    assert_equal ["S01"], result.dig("input", "scope", "section_ids")
  end

  def test_section_worker_return_reaches_projector_promotion_with_distinct_owner_and_role
    review = review_document("pass", [])
    configure_exact_authority(review)
    contract = IdolGraphProductionReviewContract
    judgment_path = @run.join("graph", "contextual-judgment.yaml")
    fixture = IdolGraphProductionReviewFixture.build(
      root: ROOT, judgment_path: judgment_path,
      directory: @run.join("graph", "production-director-review"), review_stage: "generated_branch_cut_review"
    )
    input = fixture.fetch("input")
    assert_equal "CDD-V-C1", input.dig("reviewer", "owner")
    assert_equal "creative_development_director", input.dig("reviewer", "role")
    output = input.fetch("candidate_outputs").first
    nodes = {
      "cut" => {"node_id" => "cut", "node_class" => "production_cut", "state" => "promoted", "owner_role" => "section_image_motion_worker",
        "pointers" => {"artifact_path" => output["path"], "artifact_sha256" => output["sha256"]},
        "evidence" => {"review_id" => "review", "input_digest" => contract.digest(input), "result_digest" => contract.digest(fixture["output"]), "output_hash" => output["sha256"]}},
      "review" => {"node_id" => "review", "node_class" => "review", "state" => "reviewed", "owner_role" => "section_cluster_cdd",
        "lane_id" => input.dig("reviewer", "lane_id"), "next_legal_owner" => "section_cluster_cdd",
        "pointers" => {"artifact_path" => contract.pointer(ROOT, fixture["envelope_path"])["path"], "artifact_sha256" => contract.pointer(ROOT, fixture["envelope_path"])["sha256"]}},
      "judgment" => {"node_id" => "judgment", "node_class" => "contextual_judgment", "state" => "ready_for_director_review", "judgment_decision" => "eligible_for_director_review",
        "pointers" => {"artifact_path" => contract.pointer(ROOT, judgment_path)["path"], "artifact_sha256" => contract.pointer(ROOT, judgment_path)["sha256"]}}
    }
    edges = [["promotes", "review", "cut"], ["reviews", "review", "cut"], ["judged_by", "cut", "judgment"], ["selects_next", "judgment", "review"]].to_h do |kind, from, to|
      [kind, {"edge_id" => kind, "edge_type" => kind, "from_node_id" => from, "to_node_id" => to}]
    end
    # Exercise the exact promotion consumer with the real verified G2 return;
    # unrelated graph topology is covered by the full projector suite.
    projector = IdolGraphProjector::Projector.allocate
    {base: ROOT, nodes: nodes, edges: edges,
     contextual_dispatches: {"judgment" => contract.document(ROOT, input["worker_dispatch"], "worker")},
     contextual_judgments: {"judgment" => YAML.safe_load(judgment_path.read, aliases: true)}}.each do |key, value|
      projector.instance_variable_set("@#{key}", value)
    end
    assert_equal ["cut"], projector.send(:validate_promotions!).map { |row| row["node_id"] }
    nodes["review"]["owner_role"] = "overall_director"
    error = assert_raises(IdolGraphProjector::ContractError) { projector.send(:validate_promotions!) }
    assert_match(/owner_role against returned Dispatch reviewer/, error.message)
  end

  def test_director_return_accepts_a_new_exact_terminal_locator_for_the_same_goal
    review = review_document("pass", [])
    configure_exact_authority(review)
    fixture = IdolGraphProductionReviewFixture.build(
      root: ROOT, judgment_path: @run.join("graph", "contextual-judgment.yaml"),
      directory: @run.join("graph", "production-director-review"), review_stage: "generated_branch_cut_review",
      separate_launch_goal_pointer: true
    )
    contract = IdolGraphProductionReviewContract
    result = contract.verify!(root: ROOT, review_pointer: contract.pointer(ROOT, fixture["envelope_path"]))
    assert_equal "accept", result.dig("output", "decision")
  end

  def test_unresolved_criterion_locator_fails_real_g2_intake_after_hash_refresh
    review = review_document("pass", [])
    configure_exact_authority(review)
    judgment_path = @run.join("graph", "contextual-judgment.yaml")
    judgment = YAML.safe_load(judgment_path.read, aliases: true)
    judgment.fetch("criteria").each { |row| row["evidence_locator"] = "unresolved://not-a-bound-source" }
    judgment_path.write(YAML.dump(judgment))
    dispatch_path = @run.join("graph", "dispatch-S01-reviewed.yaml")
    dispatch = YAML.safe_load(dispatch_path.read, aliases: true)
    dispatch["contextual_judgment"] = artifact_ref_for(judgment_path).merge("profile_id" => "pixel_02b")
    dispatch_path.write(YAML.dump(dispatch))
    review.fetch("delegated_pixel_close")["department_dispatches"] = [value_ref_for(dispatch_path, "/")]
    refresh_pixel_binding(review)
    @review_path.write(YAML.dump(review))
    before = Digest::SHA256.file(@review_path).hexdigest
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, SCRIPT.to_s, @review_path.to_s, "--write", chdir: ROOT.to_s)
    refute status.success?, "#{stderr}\n#{stdout}"
    result = JSON.parse(stdout)
    assert_equal "authority_request", result.fetch("status")
    assert_includes result.fetch("reason"), "evidence_locator"
    assert_equal false, result.fetch("review_mutated")
    assert_equal before, Digest::SHA256.file(@review_path).hexdigest
  end

  def test_still_composition_below_four_returns_authority_request_without_status_promotion
    review = review_document("pass", [])
    configure_exact_authority(review, judgment_results: {"still_composition_camera_depth_crop" => 3})
    refresh_pixel_binding(review)
    @review_path.write(YAML.dump(review))
    before = Digest::SHA256.file(@review_path).hexdigest

    stdout, stderr, status = Open3.capture3(RbConfig.ruby, SCRIPT.to_s, @review_path.to_s, "--validate-only", chdir: ROOT.to_s)

    refute status.success?, stderr
    result = JSON.parse(stdout)
    assert_equal "authority_request", result.fetch("status")
    assert_includes result.fetch("reason"), "still_composition_camera_depth_crop"
    assert_includes result.fetch("reason"), "grade 4"
    assert_equal false, result.fetch("review_mutated")
    assert_equal before, Digest::SHA256.file(@review_path).hexdigest
  end

  def test_rejects_legacy_inline_vector_coauthored_with_graph_judgment
    review = review_document("pass", [])
    configure_exact_authority(review)
    review.fetch("branch_cut_reviews").first["generated_production_cut_vector"] = legacy_passing_vector
    refresh_pixel_binding(review)
    @review_path.write(YAML.dump(review))

    stdout, stderr, status = Open3.capture3(RbConfig.ruby, SCRIPT.to_s, @review_path.to_s, "--validate-only", chdir: ROOT.to_s)

    refute status.success?, stderr
    result = JSON.parse(stdout)
    assert_includes result.fetch("reason"), "forbids legacy generated_production_cut_vector co-authoring"
  end

  def test_shared_post_pass_helper_preserves_distinct_founder_and_delegated_status_admission
    Dir.mktmpdir("generated-review-post-pass-") do |dir|
      root = Pathname.new(dir)
      run = root.join("runs", "fixture")
      review_path = run.join("review", "review.yaml")
      review_path.dirname.mkpath
      fake_validator = executable(root.join("validate.rb"), "exit 0\n")
      fake_upscaler = executable(root.join("upscale.rb"), "puts JSON.generate({'results' => [{'reused' => false}]})\n", json: true)
      review_path.write(YAML.dump(simple_post_pass_review("cdd_review")))

      result = IdolGeneratedReviewPostPass.apply!(
        review_path: review_path,
        run_path: run,
        root: root,
        python: RbConfig.ruby,
        schema_validator: fake_validator,
        review_schema: root.join("schema.json"),
        local_upscaler: fake_upscaler,
        generated_review_validator: fake_validator,
        audio_placement_validator: fake_validator,
        trigger: "g2_delegated_cdd_pixel_close",
        allowed_pending_status: "cdd_review",
        pass_application: "g2_delegated_cdd_update"
      )

      assert_equal "g2_delegated_cdd_update", result.fetch("review_pass_application")
      assert_equal "audio_branch_cut_placement", result.fetch("next_stage")
      assert_equal false, result.fetch("03v_may_start")
      promoted = YAML.safe_load(review_path.read, aliases: true)
      assert_equal "passed", promoted.fetch("status")
      assert_equal true, promoted.dig("automation_boundaries", "audio_branch_cut_placement_may_start_after_pass")

      review_path.write(YAML.dump(simple_post_pass_review("founder_review")))
      error = assert_raises(IdolGeneratedReviewPostPass::Error) do
        IdolGeneratedReviewPostPass.apply!(
          review_path: review_path,
          run_path: run,
          root: root,
          python: RbConfig.ruby,
          schema_validator: fake_validator,
          review_schema: root.join("schema.json"),
          local_upscaler: fake_upscaler,
          generated_review_validator: fake_validator,
          audio_placement_validator: fake_validator,
          trigger: "g2_delegated_cdd_pixel_close",
          allowed_pending_status: "cdd_review",
          pass_application: "g2_delegated_cdd_update"
        )
      end
      assert_includes error.message, "cdd_review"

      founder_result = IdolGeneratedReviewPostPass.apply!(
        review_path: review_path,
        run_path: run,
        root: root,
        python: RbConfig.ruby,
        schema_validator: fake_validator,
        review_schema: root.join("schema.json"),
        local_upscaler: fake_upscaler,
        generated_review_validator: fake_validator,
        audio_placement_validator: fake_validator,
        trigger: "explicit_complete_founder_pass_intake",
        allowed_pending_status: "founder_review",
        pass_application: "founder_direct_update"
      )
      assert_equal "founder_direct_update", founder_result.fetch("review_pass_application")
      assert_equal "passed", YAML.safe_load(review_path.read, aliases: true).fetch("status")
    end
  end

  private

  def review_document(decision, reasons)
    close = {
      "schema_version" => "idol_g2_delegated_pixel_close.v1",
      "mode" => "g2_delegated_cdd",
      "decision" => decision,
      "cdd_owner" => "CDD-V-C1",
      "cdd_lane_id" => "section_cluster_v_c1",
      "section_cohort_id" => "C1",
      "section_ids" => ["S01"],
      "g2_envelope" => value_ref("missing-g2.yaml"),
      "cohort_map" => value_ref("missing-cohort.yaml"),
      "department_dispatches" => [value_ref("missing-dispatch.yaml")],
      "generation_approvals" => [artifact_ref("missing-approval.yaml")],
      "image_generation_requests" => [artifact_ref("missing-request.yaml")],
      "execution_receipts" => [artifact_ref("missing-receipt.yaml")],
      "pixel_review_packet_bindings" => [{"packet_id" => "PKT_BC01_ACTION", "review_value_sha256" => "a" * 64}],
      "material_drift" => decision == "pass" ? false : true,
      "target_lock_violation" => false,
      "message_lock_violation" => false,
      "authority_request_reasons" => reasons,
      "automatic_fallback" => "none"
    }
    {
      "schema_version" => "idol_generated_branch_cut_review.v4",
      "content_id" => "TEST",
      "status" => "cdd_review",
      "source_02a" => artifact_ref("missing-02a.yaml"),
      "source_02b" => artifact_ref("missing-02b.yaml"),
      "section_reviews" => [{
        "section_id" => "S01",
        "packet_ids" => ["PKT_BC01_ACTION"],
        "decision" => "pass",
        "continuity_observation" => "Continuity remains observable.",
        "repetition_observation" => "The Cut contributes a distinct view.",
        "note" => ""
      }],
      "branch_cut_reviews" => [{
        "packet_id" => "PKT_BC01_ACTION",
        "branch_cut_id" => "BC01_ACTION",
        "section_id" => "S01",
        "core_cut_id" => "C01",
        "image_path" => "runs/test/output.png",
        "image_sha256" => "b" * 64,
        "pixel_dimensions" => {"width" => 192, "height" => 108},
        "observable_pixel_truth" => "The exact full-size pixel state is visible.",
        "core_event_fidelity_result" => "The Core event remains intact.",
        "distinct_screen_contribution_result" => "The Branch adds a distinct state.",
        "member_visual_result" => "Member identity remains stable.",
        "scene_reference_result" => "Scene transfer remains coherent.",
        "still_camera_result" => "Still camera geometry is readable.",
        "body_and_object_integrity" => "Body and object geometry remain intact.",
        "decision" => "pass",
        "review_note" => "CDD reviewed exact pixels."
      }],
      "review_surface" => {
        "html_contract_version" => "idol-html-review-board.v12",
        "hierarchy" => "target_and_message_then_whole_film_and_section_flow_then_sections_then_core_cuts_then_branch_cuts",
        "decision_values" => %w[PASS HOLD REJECT]
      },
      "automation_boundaries" => {
        "audio_branch_cut_placement_may_start_after_pass" => false,
        "paid_video_generation_approved" => false,
        "external_video_execution_approved" => false,
        "playback_pass_implied" => false,
        "edit_readiness_implied" => false
      },
      "delegated_pixel_close" => close,
      "open_questions" => []
    }
  end

  def configure_exact_authority(review, judgment_results: {})
    run_relative = @run.relative_path_from(ROOT).to_s
    output_relative = @run.join("generations", "passed", "BC01_ACTION.png").relative_path_from(ROOT).to_s
    output_path = ROOT.join(output_relative)
    output_path.dirname.mkpath
    output_path.binwrite("synthetic G2 pixel fixture bytes\n")
    review.fetch("branch_cut_reviews").first["image_path"] = output_relative
    review.fetch("branch_cut_reviews").first["image_sha256"] = Digest::SHA256.file(output_path).hexdigest
    packet_id = "PKT_BC01_ACTION"
    prompt_sha = "1" * 64
    attachment_sha = "2" * 64
    profile_sha = "3" * 64
    capability_sha = "4" * 64
    authority_id = "FOUNDER-G2-AUTH-001"
    spend = "three approved fixture credits maximum"
    production_scope = "SCOPE-G2-C1"
    run_selection = {
      "creative_role_provider" => "grok_build",
      "image_execution_request" => "openai_api_gpt_image_2",
      "image_execution_request_origin" => "founder_explicit",
      "image_execution_session_provider" => "grok_build",
      "image_execution_lane" => "openai_api_gpt_image_2",
      "video_execution_lane" => "grok_build_oauth_subscription",
      "automatic_fallback" => "none"
    }
    provider = {
      "execution_adapter_id" => "openai_api_gpt_image_2",
      "provider" => "openai",
      "provider_profile_id" => "openai_image_api_current",
      "provider_profile_sha256" => profile_sha,
      "provider_capability_snapshot_sha256" => capability_sha
    }
    source_packet = {
      "packet_id" => packet_id,
      "branch_cut_id" => "BC01_ACTION",
      "execution_section_id" => "S01",
      "core_cut_id" => "C01",
      "rendered_five_lines" => {"full_prompt_sha256" => prompt_sha},
      "attachments" => []
    }
    source_02b_path = write_yaml("02B-prompt-packets.yaml", "schema_version" => "2.6", "content_id" => "TEST", "prompt_packets" => [source_packet])
    review["source_02b"] = artifact_ref_for(source_02b_path)

    sequence_frames = 5.times.map do |index|
      write_yaml("planning/motion/frame-#{index + 1}.yaml", "frame" => index + 1)
    end
    sequence_manifest = write_yaml("planning/motion/manifest.yaml", "frame_count" => 5)
    sequence_event = "One continuous G2 motion event reaches a visible landing."
    sequence_unit = {
      "sequence_unit_id" => "SEQU_G2_01",
      "sequence_run_id" => "SRUN_G2_MJ01",
      "event_identity" => sequence_event,
      "frame_selection_mode" => "fixed_cadence",
      "declared_cadence_seconds" => 1,
      "ordered_frames" => sequence_frames.each_with_index.map do |path, index|
        {"order_index" => index + 1, "timestamp_seconds" => index, "source_frame_or_cell_id" => "G2-FRAME-#{index + 1}", "artifact" => artifact_ref_for(path)}
      end,
      "flow_reading" => {"entry_state" => "offset", "trigger" => "move", "visible_transformation" => "alignment", "peak_or_reveal" => "landing", "exit_state" => "held", "camera_composition_depth_progression" => "fixed depth", "continuity_to_next" => "landed state", "direct_observation_vs_inference" => "fixture observation", "storyline_transfer_and_exclusion" => "transfer motion only", "authorship_owner" => "assigned_model"},
      "frame_observations" => 5.times.map do |index|
        {"order_index" => index + 1, "timestamp_seconds" => index, "subject_body_object_space" => "state #{index + 1}", "delta_from_previous" => "delta #{index + 1}", "camera_composition_depth" => "fixed depth", "storyline_function" => "motion proof", "uncertainty" => "none"}
      end,
      "manifest" => artifact_ref_for(sequence_manifest),
      "major_reference_eligible" => true,
      "downstream_cut_count_rule" => "five_source_frames_never_imply_five_core_or_branch_cuts"
    }
    reference_unit = {
      "reference_unit_id" => "REF-G2-01",
      "disposition" => "applied",
      "sequence_unit" => sequence_unit,
      "function_analysis" => [
        {"function_id" => "RFN_G2_WORLD", "purpose" => "background_and_space"},
        {"function_id" => "RFN_G2_COMPOSITION", "purpose" => "still_camera_and_composition"},
        {"function_id" => "RFN_G2_MOTION", "purpose" => "visible_action_or_hold"}
      ]
    }
    front_path = write_yaml(
      "planning/front-planning-readiness.yaml",
      "schema_version" => "front-planning-readiness.v17",
      "reference_connection_research" => {"reference_units" => [reference_unit]}
    )
    lineage_for = lambda do |function_index, bind_sequence = false|
      function = reference_unit.fetch("function_analysis").fetch(function_index)
      row = {
        "attachment_binding_id" => "ATTACH-1",
        "reference_unit_id" => reference_unit.fetch("reference_unit_id"),
        "function_id" => function.fetch("function_id"),
        "purpose" => function.fetch("purpose"),
        "disposition" => reference_unit.fetch("disposition"),
        "source_media_type" => "video_selected_range",
        "source_artifact" => artifact_ref_for(front_path).merge("schema_version" => "front-planning-readiness.v17"),
        "reference_unit_json_pointer" => "/reference_connection_research/reference_units/0",
        "reference_unit_value_sha256" => Digest::SHA256.hexdigest(JSON.generate(canonical_value(reference_unit))),
        "function_json_pointer" => "/reference_connection_research/reference_units/0/function_analysis/#{function_index}",
        "function_value_sha256" => Digest::SHA256.hexdigest(JSON.generate(canonical_value(function)))
      }
      if bind_sequence
        row["sequence_unit_json_pointer"] = "/reference_connection_research/reference_units/0/sequence_unit"
        row["sequence_unit_value_sha256"] = Digest::SHA256.hexdigest(JSON.generate(canonical_value(sequence_unit)))
      end
      row
    end

    approval = {
      "schema_version" => "idol_image_generation_section_approval.v6",
      "artifact_type" => "image_generation_scope_approval",
      "content_id" => "TEST",
      "section_id" => "S01",
      "production_scope_id" => production_scope,
      "source_prompt_packets_sha256" => Digest::SHA256.file(source_02b_path).hexdigest,
      "run_execution_selection" => run_selection,
      "execution_adapter_id" => provider["execution_adapter_id"],
      "provider" => provider["provider"],
      "auth_lane" => "founder_approved_api",
      "provider_profile_id" => provider["provider_profile_id"],
      "provider_profile_sha256" => profile_sha,
      "provider_capability_snapshot_sha256" => capability_sha,
      "founder_generation_authority_id" => authority_id,
      "external_execution_approved" => true,
      "paid_generation_approved" => true,
      "approved_output_count" => 1,
      "spend_envelope" => spend,
      "automatic_fallback" => "none",
      "packets" => [{
        "packet_id" => packet_id,
        "mode" => "official_branch",
        "cut_id" => "BC01_ACTION",
        "prompt_sha256" => prompt_sha,
        "approved_attachment_sha256s" => [],
        "approved_attachment_paths" => [],
        "expected_output_path" => output_relative,
        "output_count" => 1,
        "decision" => "approved_for_current_job"
      }]
    }
    approval_path = write_yaml("approvals/g2-c1.yaml", approval)

    request = {
      "schema_version" => "idol_image_generation_request.v12",
      "artifact_type" => "image_generation_request",
      "content_id" => "TEST",
      "run" => run_relative,
      "prompt_profile" => "idol_one_cut_one_image.v1",
      "mode" => "official_branch",
      "packet_id" => packet_id,
      "production_scope_id" => production_scope,
      "cut_pointer" => {
        "cut_id" => "BC01_ACTION",
        "cut_type" => "branch",
        "section_id" => "S01",
        "major_scene_id" => "MJ01",
        "parent_core_cut_id" => "C01",
        "source_path" => "runs/fixture/source.yaml",
        "source_json_pointer" => "/master_storyboard/0/compile_seed/branch_cuts/0",
        "source_value_sha256" => "6" * 64
      },
      "section_id" => "S01",
      "section_cohort_id" => "C1",
      "source_prompt_packet" => {
        "path" => source_02b_path.relative_path_from(ROOT).to_s,
        "sha256" => Digest::SHA256.file(source_02b_path).hexdigest,
        "schema_version" => "2.6",
        "json_pointer" => "/prompt_packets/0",
        "value_sha256" => Digest::SHA256.hexdigest(JSON.generate(canonical_value(source_packet)))
      },
      "run_execution_selection" => run_selection,
      "prompt" => {
        "identity_reference_rule" => "Preserve current-title identity.",
        "scene_intent" => "Show the exact Branch event.",
        "visible_details" => "4K, high quality, high detail, clear space and light.",
        "action_cue" => "Hold a readable motion anchor.",
        "avoid" => "Avoid collage and identity drift.",
        "full_prompt_text" => "Identity reference rule: Preserve current-title identity.\nScene intent: Show the exact Branch event.\nVisible details: 4K, high quality, high detail, clear space and light.\nAction cue: Hold a readable motion anchor.\nAvoid: Avoid collage and identity drift.",
        "full_prompt_sha256" => prompt_sha,
        "label_order" => ["Identity reference rule", "Scene intent", "Visible details", "Action cue", "Avoid"]
      },
      "attachments" => [],
      "reference_role_plan" => {
        "authoring_owner" => "human_or_assigned_model",
        "scene_character_compile_mode" => "combined",
        "performance_mode" => "none",
        "attachment_order_binding_ids" => ["ATTACH-1"],
        "logical_role_groups" => [
          {"logical_role" => "character_visual", "applicability" => "not_applicable_member_absent", "attachment_binding_ids" => []},
          {"logical_role" => "scene_visual_package", "applicability" => "required", "attachment_binding_ids" => ["ATTACH-1"], "world_look_binding_ids" => ["WORLD-1"], "composition_anchor_binding_id" => "COMP-1", "world_look_function_lineage" => [lineage_for.call(0)], "composition_anchor_function_lineage" => lineage_for.call(1)},
          {"logical_role" => "motion_reference", "applicability" => "required", "attachment_binding_ids" => ["ATTACH-1"], "sequence_unit_id" => "SEQU_G2_01", "source_locator" => "SEQU_G2_01 exact five frames at 00:00-00:04", "sampling_interval_seconds" => 1, "sample_count" => 5, "contiguous_event" => sequence_event, "motion_function_lineage" => [lineage_for.call(2, true)]}
        ]
      },
      "attachment_order_sha256" => attachment_sha,
      "execution" => {
        "execution_adapter_id" => provider["execution_adapter_id"],
        "provider" => provider["provider"],
        "provider_model_or_tool" => "gpt-image-2",
        "selected_native_tool" => nil,
        "auth_lane" => "founder_approved_api",
        "provider_profile_id" => provider["provider_profile_id"],
        "provider_profile_sha256" => profile_sha,
        "provider_capability_snapshot_sha256" => capability_sha,
        "cli_or_api_version" => "fixture-v1",
        "founder_generation_authority_id" => authority_id,
        "prompt_rewrite_policy" => "forbidden",
        "automatic_fallback" => "none",
        "expected_output_path" => output_relative,
        "output_count" => 1
      },
      "quality_contract" => {
        "quality" => "highest_available",
        "render_quality_terms" => ["4K", "high quality", "high detail"],
        "output_count" => 1,
        "full_size_pixel_review_required" => true
      },
      "expected_output" => {
        "path" => output_relative,
        "sha256_required" => true,
        "canonical_ingest_required" => true,
        "motion_handoff" => "only_after_passed_full_size_pixels"
      },
      "integrity_contract" => {
        "prompt_rewrite_policy" => "forbidden",
        "attachment_omission_policy" => "locked_attachment_missing_hold_no_prose_substitution",
        "provider_auth_model_fallback" => "none",
        "one_request_one_output" => true
      },
      "approval" => {
        "founder_generation_authority_id" => authority_id,
        "external_execution_approved" => true,
        "paid_generation_approved" => true,
        "approval_source" => artifact_ref_for(approval_path).merge("schema_version" => "idol_image_generation_section_approval.v6")
      },
      "status" => "ready",
      "hold_reasons" => []
    }
    request_path = write_yaml("requests/#{packet_id}.yaml", request)

    receipt = {
      "schema_version" => "idol_image_generation_execution_receipt.v4",
      "request_schema_version" => "idol_image_generation_request.v12",
      "reference_role_plan_sha256" => Digest::SHA256.hexdigest(JSON.generate(canonical_value(request.fetch("reference_role_plan")))),
      "section_cohort_id" => "C1",
      "artifact_type" => "image_generation_execution_receipt",
      "status" => "generated_pending_pixel_review",
      "external_call_performed" => true,
      "request_path" => request_path.relative_path_from(ROOT).to_s,
      "request_sha256" => Digest::SHA256.file(request_path).hexdigest,
      "approval_path" => approval_path.relative_path_from(ROOT).to_s,
      "approval_sha256" => Digest::SHA256.file(approval_path).hexdigest,
      "packet_id" => packet_id,
      "mode" => "official_branch",
      "cut_id" => "BC01_ACTION",
      "execution_adapter_id" => provider["execution_adapter_id"],
      "provider" => provider["provider"],
      "provider_model_or_tool" => "gpt-image-2",
      "selected_native_tool" => nil,
      "auth_lane" => "founder_approved_api",
      "provider_profile_id" => provider["provider_profile_id"],
      "runtime_version" => "fixture-v1",
      "provider_profile_sha256" => profile_sha,
      "provider_capability_snapshot_sha256" => capability_sha,
      "founder_generation_authority_id" => authority_id,
      "spend_envelope" => spend,
      "prompt_sha256" => prompt_sha,
      "attachment_order_sha256" => attachment_sha,
      "endpoint" => "/v1/images/generations",
      "transport" => "json",
      "response_image_encoding" => "base64_json",
      "native_session_binding" => nil,
      "output_count" => 1,
      "output_path" => output_relative,
      "output_sha256" => review.dig("branch_cut_reviews", 0, "image_sha256"),
      "automatic_fallback" => "none",
      "prompt_rewrite_policy" => "forbidden",
      "full_size_pixel_review_status" => "pending",
      "03v_handoff_allowed" => false,
      "secret_values_recorded" => false
    }
    receipt_path = write_yaml("receipts/#{packet_id}.yaml", receipt)

    handoff_path = @run.join("planning", "p3-c1-handoff.json")
    handoff_path.dirname.mkpath
    handoff_path.write(JSON.pretty_generate("section_cohort_id" => "C1", "section_ids" => ["S01"]))
    cohort = {
      "schema_version" => "idol-graph-section-cohort-map.v1",
      "artifact_type" => "graph_section_cohort_map",
      "run" => run_relative,
      "phase" => "production_active",
      "partition_basis" => "roster_derived_not_capacity",
      "section_roster" => ["S01"],
      "cohorts" => [{
        "section_cohort_id" => "C1",
        "planning_lane_id" => "planning_p3_c1",
        "production_lane_id" => "section_cluster_v_c1",
        "section_ids" => ["S01"],
        "cdd_reviewer" => {"owner" => "CDD-V-C1", "role" => "creative_development_director", "lane_id" => "section_cluster_v_c1", "session_id" => "SESSION-V-C1-A", "logical_lineage_id" => "LINEAGE-V-C1"},
        "return_recipient" => {"owner" => "OVERALL", "role" => "overall_director", "return_route" => "reviewed_cohort_milestone"},
        "section_output_writers" => [{"section_id" => "S01", "owner" => "WORKER-S01", "role" => "section_image_motion_worker"}]
      }],
      "p3_to_v_carry" => [{
        "section_cohort_id" => "C1",
        "planning_lane_id" => "planning_p3_c1",
        "production_lane_id" => "section_cluster_v_c1",
        "exact_section_ids" => ["S01"],
        "exact_carry" => true,
        "planning_handoff" => {"path" => handoff_path.relative_path_from(ROOT).to_s, "sha256" => Digest::SHA256.file(handoff_path).hexdigest, "role" => "p3_c1_g40_handoff"}
      }],
      "founder_partition_waiver" => nil
    }
    cohort_path = write_yaml("graph/cohort-map.yaml", cohort)

    graph_provider, provider_holds = IdolRoleContextPack.resolve_provider(
      root: ROOT,
      role: "section_image_motion_worker",
      provider: "grok",
      runtime_surface: "grok_build_cli_acp",
      logical_profile_alias: "worker_high"
    )
    raise "fixture Graph provider did not resolve: #{provider_holds.join(', ')}" unless provider_holds.empty?
    goal_text = "Review the exact synthetic S01 generated Production Cut pixels."
    goal_text_sha = Digest::SHA256.hexdigest(goal_text.encode(Encoding::UTF_8))
    goal_event_path = write_yaml(
      "graph/evidence/goal-terminal-event.yaml",
      "schema_version" => "idol-graph-provider-goal-terminal-event.v1",
      "artifact_type" => "graph_provider_goal_terminal_event",
      "evidence_class" => "provider_native_terminal_event",
      "provider" => "grok",
      "native_goal_id" => "GOAL-G2-S01",
      "goal_text" => goal_text,
      "goal_text_sha256" => goal_text_sha,
      "goal_semantics" => "grok_goal_completed_admission",
      "terminal_state" => "complete",
      "last_event" => "goal_completed"
    )
    goal_event_ref = artifact_ref_for(goal_event_path)
    input_digest = "c" * 64
    bounded_output = {
      "output_kind" => "section_image_motion_package",
      "expected_paths" => [output_relative],
      "maximum_artifact_count" => 1
    }
    output_manifest_path = write_yaml(
      "graph/output-manifest.yaml",
      "schema_version" => "idol-graph-output-manifest.v1",
      "artifact_type" => "graph_dispatch_output_manifest",
      "dispatch_id" => "DISPATCH-G2-S01",
      "assigned_owner" => "WORKER-S01",
      "input_digest_sha256" => input_digest,
      "output_kind" => bounded_output.fetch("output_kind"),
      "outputs" => [artifact_ref_for(output_path)]
    )
    output_manifest_ref = artifact_ref_for(output_manifest_path)
    returned_dispatch = {
      "schema_version" => "idol-graph-department-dispatch.v1",
      "artifact_type" => "graph_department_dispatch",
      "dispatch_id" => "DISPATCH-G2-S01",
      "run" => run_relative,
      "lane_id" => "section_cluster_v_c1",
      "section_cohort_id" => "C1",
      "section_ids" => ["S01"],
      "logical_role" => "section_image_motion_worker",
      "assigned_owner" => "WORKER-S01",
      "output_writer" => {"owner" => "WORKER-S01", "role" => "section_image_motion_worker", "session_id" => "SESSION-WORKER-S01"},
      "reviewer" => {"owner" => "CDD-V-C1", "role" => "creative_development_director", "lane_id" => "section_cluster_v_c1", "session_id" => "SESSION-V-C1-A", "logical_lineage_id" => "LINEAGE-V-C1"},
      "return_recipient" => {"owner" => "CDD-V-C1", "role" => "creative_development_director", "return_route" => "cohort_cdd_exact_byte_review"},
      "bounded_output" => bounded_output,
      "provider_binding" => {
        "registered_provider" => graph_provider.fetch("provider"),
        "runtime_surface" => graph_provider.fetch("runtime_surface"),
        "logical_profile_alias" => graph_provider.fetch("logical_profile_alias"),
        "execution_profile_id" => graph_provider.fetch("provider_profile_id"),
        "resolved_provider_model" => graph_provider.fetch("exact_model"),
        "reasoning_effort" => graph_provider.fetch("reasoning_effort"),
        "provider_capability_snapshot_sha256" => graph_provider.fetch("registry_sha256"),
        "fallback_allowed" => false,
        "silent_substitution_allowed" => false
      },
      "goal_evidence" => {
        "native_goal_id" => "GOAL-G2-S01",
        "goal_text_sha256" => goal_text_sha,
        "goal_semantics" => "grok_goal_completed_admission",
        "goal_terminal_state" => "complete",
        "goal_last_event" => "goal_completed",
        "goal_terminal_event_sha256" => goal_event_ref.fetch("sha256"),
        "terminal_event" => goal_event_ref
      },
      "input_digest_sha256" => input_digest,
      "output_manifest" => output_manifest_ref,
      "review_checkpoint" => "02b_pixel",
      "judgment_profile_id" => "pixel_02b",
      "stop_conditions" => ["missing_or_stale_authority", "provider_fallback_attempt"],
      "lifecycle_state" => "returned",
      "legal_next" => ["reviewed", "hold"],
      "lifecycle_from" => "launched"
    }
    returned_dispatch_path = write_yaml("graph/dispatch-S01-returned.yaml", returned_dispatch)
    returned_dispatch_ref = artifact_ref_for(returned_dispatch_path)
    launched_dispatch = Marshal.load(Marshal.dump(returned_dispatch))
    launched_dispatch.merge!(
      "output_manifest" => nil,
      "lifecycle_state" => "launched",
      "legal_next" => ["returned", "hold"],
      "lifecycle_from" => "prepared"
    )
    launched_dispatch_path = write_yaml("graph/dispatch-S01-launched.yaml", launched_dispatch)
    launched_dispatch_ref = artifact_ref_for(launched_dispatch_path)
    profile_registry = YAML.safe_load(ROOT.join("automation", "graph-creative-judgment-registry.yaml").read, aliases: true)
    profile = profile_registry.fetch("profiles").find { |row| row.fetch("profile_id") == "pixel_02b" }
    pack = IdolRoleContextPack.build(
      root: ROOT,
      run_root: run_relative,
      assignment_id: returned_dispatch.fetch("dispatch_id"),
      role: "section_image_motion_worker",
      profile_id: "section_image_motion_worker",
      checkpoint_id: "section_02b_image",
      stage_id: "branch_cut_generation",
      section_ids: ["S01"],
      source_envelope: launched_dispatch_ref.merge("kind" => "department_dispatch"),
      current_state: "launched",
      scope: {"stage_id" => "branch_cut_generation", "section_ids" => ["S01"]},
      authority: {"assigned_owner" => "WORKER-S01", "promotion_owner" => "CDD-V-C1"},
      output_contract: bounded_output,
      hold_conditions: returned_dispatch.fetch("stop_conditions"),
      return_recipient: returned_dispatch.fetch("return_recipient"),
      provider: "grok",
      runtime_surface: "grok_build_cli_acp",
      writer: "graph_v2",
      run_class: "new_run",
      switch_receipt: graph_switch_receipt
    )
    pack_path = write_yaml("graph/role-context-pack.yaml", pack)
    judgment = {
      "schema_version" => "idol_graph_contextual_judgment.v2",
      "artifact_type" => "graph_contextual_judgment",
      "profile_id" => "pixel_02b",
      "checkpoint_id" => "section_02b_image",
      "stage_id" => "branch_cut_generation",
      "scope_id" => returned_dispatch.fetch("dispatch_id"),
      "authoring_owner" => "human_or_assigned_model",
      "reviewer_role" => "section_image_motion_worker",
      "performance_mode" => "none",
      "applicability_tags" => [],
      "applicability_evidence" => [],
      "execution_binding" => {
        "assignment_id" => returned_dispatch.fetch("dispatch_id"),
        "author_role" => "section_image_motion_worker",
        "author_session_id" => returned_dispatch.dig("output_writer", "session_id"),
        "dispatch" => returned_dispatch_ref,
        "goal_id" => returned_dispatch.dig("goal_evidence", "native_goal_id"),
        "goal_terminal_event_sha256" => returned_dispatch.dig("goal_evidence", "goal_terminal_event_sha256"),
        "role_context_pack" => artifact_ref_for(pack_path),
        "profile_release" => pack.fetch("creative_judgment_contract").fetch("profile_release"),
        "profile_value_sha256" => pack.fetch("creative_judgment_contract").fetch("profile_value_sha256"),
        "input_digest_sha256" => input_digest,
        "output_manifest" => output_manifest_ref
      },
      "source_artifacts" => [artifact_ref_for(output_path).merge("locator" => "exact synthetic generated Production Cut pixel bytes")],
      "criteria" => CRITERIA.map do |criterion_id|
        default = %w[scene_visual_package_pixels still_composition_camera_depth_crop motion_pose_action_anchor].include?(criterion_id) ? 4 : 3
        graph_judgment_criterion(criterion_id, judgment_results.fetch(criterion_id, default), artifact_ref_for(output_path))
      end,
      "hard_gate_findings" => [],
      "decision" => "eligible_for_director_review",
      "next_edge" => "director_review",
      "target_message_treatment" => profile.fetch("target_message_treatment"),
      "aggregate_score_present" => false,
      "automatic_creative_pass" => false,
      "status" => "ready_for_director_review"
    }
    judgment_path = write_yaml("graph/contextual-judgment.yaml", judgment)
    reviewed_dispatch = Marshal.load(Marshal.dump(returned_dispatch))
    reviewed_dispatch.merge!(
      "lifecycle_state" => "reviewed",
      "legal_next" => ["hold"],
      "lifecycle_from" => "returned",
      "contextual_judgment" => artifact_ref_for(judgment_path).merge("profile_id" => "pixel_02b")
    )
    dispatch_path = write_yaml("graph/dispatch-S01-reviewed.yaml", reviewed_dispatch)

    envelope = {
      "gate_id" => "G2",
      "projection_kind" => "draft_keyframe",
      "decision" => "PASS",
      "section_cohort_id" => "C1",
      "section_ids" => ["S01"],
      "cut_ids" => ["BC01_ACTION"],
      "production_scope_ids" => [production_scope],
      "provider" => provider,
      "founder_generation_authority_id" => authority_id,
      "approved_output_count" => 1,
      "spend_envelope" => spend,
      "packet_authority" => [{
        "packet_id" => packet_id,
        "cut_id" => "BC01_ACTION",
        "prompt_sha256" => prompt_sha,
        "attachment_order_sha256" => attachment_sha,
        "approved_attachment_paths" => [],
        "approved_attachment_sha256s" => [],
        "expected_output_path" => output_relative,
        "output_count" => 1
      }],
      "automatic_fallback" => "none"
    }
    g2_path = write_yaml("review/g2-envelope.yaml", "g2_execution_envelope" => envelope)

    close = review.fetch("delegated_pixel_close")
    close["g2_envelope"] = value_ref_for(g2_path, "/g2_execution_envelope")
    close["cohort_map"] = value_ref_for(cohort_path, "/cohorts/0")
    close["department_dispatches"] = [value_ref_for(dispatch_path, "/")]
    close["generation_approvals"] = [artifact_ref_for(approval_path)]
    close["image_generation_requests"] = [artifact_ref_for(request_path)]
    close["execution_receipts"] = [artifact_ref_for(receipt_path)]
  end

  def graph_judgment_criterion(criterion_id, result, evidence_ref)
    {
      "criterion_id" => criterion_id,
      "result" => result,
      "evidence_locator" => [evidence_ref],
      "observable_claim" => "The exact synthetic pixels visibly support #{criterion_id}.",
      "screen_consequence" => "The generated Production Cut remains reviewable at the named checkpoint.",
      "preserve" => "Preserve the strongest verified visible state.",
      "change" => "Change only the bounded criterion weakness.",
      "do_not_infer" => "Do not infer Founder PASS, playback PASS, or another section decision.",
      "correction_action" => "Return the exact failed pixel scope to its current section owner.",
      "acceptance_evidence" => "Reinspect the corrected exact pixel bytes against this criterion."
    }
  end

  def legacy_passing_vector
    critical = %w[scene_visual_package action_pose_motion_anchor]
    {
      "criteria" => %w[
        character_identity_visual_continuity
        scene_visual_package
        action_pose_motion_anchor
        multi_reference_synthesis
        neighbor_cut_distinct_contribution
        artifact_anatomy_crop_provider_input_stability
        material_prop_scale_contact_state_continuity
      ].map do |criterion_id|
        {
          "criterion_id" => criterion_id,
          "result" => critical.include?(criterion_id) ? 4 : 3,
          "locator" => "legacy parse-only fixture: #{criterion_id}"
        }
      end,
      "target_lock_violation" => false,
      "message_lock_violation" => false,
      "material_drift" => false
    }
  end

  def graph_switch_receipt
    {
      "receipt_id" => "GRAPH_SWITCH_G2_DELEGATED_PIXEL_FIXTURE",
      "founder_authority" => "founder",
      "graph_revision" => "idol-graph-skill-load-profiles.v1",
      "switch_boundary" => "new_runs_only_after_verified_receipt",
      "source_set_sha256" => IdolRoleContextPack.graph_source_set_sha256(ROOT),
      "verified_at" => "2026-09-03T00:00:00+09:00"
    }
  end

  def write_yaml(relative, document)
    path = @run.join(relative)
    path.dirname.mkpath
    path.write(YAML.dump(document))
    path
  end

  def artifact_ref_for(path)
    {"path" => path.relative_path_from(ROOT).to_s, "sha256" => Digest::SHA256.file(path).hexdigest}
  end

  def value_ref_for(path, pointer)
    document = YAML.safe_load(path.read, aliases: true)
    value = if pointer == "/"
      document
    else
      pointer.split("/")[1..].reduce(document) do |memo, token|
        memo.is_a?(Array) ? memo.fetch(Integer(token, 10)) : memo.fetch(token)
      end
    end
    artifact_ref_for(path).merge("json_pointer" => pointer, "value_sha256" => Digest::SHA256.hexdigest(JSON.generate(canonical_value(value))))
  end

  def canonical_value(value)
    case value
    when Hash
      value.keys.map(&:to_s).sort.each_with_object({}) { |key, result| result[key] = canonical_value(value[key]) }
    when Array
      value.map { |item| canonical_value(item) }
    else
      value
    end
  end

  def refresh_pixel_binding(review)
    row = review.fetch("branch_cut_reviews").first
    canonical = lambda do |value|
      case value
      when Hash
        value.keys.map(&:to_s).sort.each_with_object({}) { |key, result| result[key] = canonical.call(value[key]) }
      when Array
        value.map { |item| canonical.call(item) }
      else
        value
      end
    end
    review.dig("delegated_pixel_close", "pixel_review_packet_bindings", 0)["review_value_sha256"] =
      Digest::SHA256.hexdigest(JSON.generate(canonical.call(row)))
  end

  def artifact_ref(name)
    {"path" => @run.join(name).relative_path_from(ROOT).to_s, "sha256" => "c" * 64}
  end

  def value_ref(name)
    artifact_ref(name).merge("json_pointer" => "/", "value_sha256" => "d" * 64)
  end

  def simple_post_pass_review(status)
    {
      "schema_version" => "idol_generated_branch_cut_review.v4",
      "status" => status,
      "section_reviews" => [{"decision" => "pass"}],
      "branch_cut_reviews" => [{"decision" => "pass"}],
      "automation_boundaries" => {"audio_branch_cut_placement_may_start_after_pass" => false}
    }
  end

  def executable(path, body, json: false)
    prefix = json ? "require 'json'\n" : ""
    path.write(prefix + body)
    path
  end
end
