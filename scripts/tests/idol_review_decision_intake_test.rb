# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "pathname"
require "rbconfig"
require "yaml"
require_relative "support/active_review_board_fixture"
require_relative "support/active_audio_branch_cut_placement_fixture"

class IdolReviewDecisionIntakeTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  BOARD_SCRIPT = ROOT.join("scripts", "idol_html_review_board.rb")
  INTAKE_SCRIPT = ROOT.join("scripts", "idol_review_decision_intake.rb")

  def setup
    @fixture = ActiveReviewBoardFixture.create
    @export = @fixture.mv.run_dir.join("review", "local-decision-export.json")
    @output = @fixture.mv.run_dir.join("review", "decision-intake", "active-board-r1.yaml")
  end

  def teardown
    @fixture.cleanup
  end

  def test_complete_numbered_pass_export_routes_without_a_second_creative_verdict
    validate = run_command(RbConfig.ruby, BOARD_SCRIPT, "validate", @fixture.manifest_path, "--json")
    assert validate[:status].success?, validate[:stderr]
    write_export(@fixture.decision_export)

    result = run_intake

    assert result[:status].success?, result[:stderr]
    report = JSON.parse(result[:stdout])
    assert_equal "ready_for_owner_routing", report.fetch("status")
    intake = YAML.safe_load(@output.read, aliases: true)
    assert_equal "idol_founder_review_decision_intake.v12", intake.fetch("schema_version")
    assert_equal "g40_core_branch_authorization", intake.fetch("review_mode")
    assert_equal 4, intake.dig("summary", "pass_count")
    assert_equal 0, intake.dig("summary", "hold_count")
    assert_equal %w[whole_film section core_cut branch_cut],
                 intake.fetch("decisions").map { |row| row.dig("review_target", "level") }
    assert_equal %w[whole_film section core_cut branch_cut],
                 intake.fetch("decisions").map { |row| row.fetch("revision_scope") }
    assert_equal ["g40_core_branch_authorization"], intake.fetch("decisions").map { |row| row.fetch("cycle_kind") }.uniq
    assert intake.fetch("decisions").all? { |row| row.fetch("dispatch_id").start_with?("DISPATCH-") }
    assert intake.fetch("decisions").all? { |row| row.fetch("founder_lineage").key?("decision_export") }
    assert intake.fetch("decisions").all? { |row| row.dig("worker_evidence", "attempt_id").to_s.start_with?("ATTEMPT-") }
    assert intake.fetch("decisions").all? { |row| row.dig("worker_evidence", "director_dispatch_index", "sha256").to_s.match?(/\A[a-f0-9]{64}\z/) }
    assert_equal "founder_direct_decision_skips_additional_llm_creative_verdict",
                 intake.fetch("creative_rereview_policy")
    assert_equal false, intake.dig("automation_boundaries", "canonical_creative_write_performed")
    assert_equal false, intake.dig("automation_boundaries", "downstream_invalidation_authored")
  end

  def test_identical_export_is_idempotent_and_conflicting_existing_intake_holds
    write_export(@fixture.decision_export)
    first = run_intake
    assert first[:status].success?, first[:stderr]
    first_report = JSON.parse(first[:stdout])
    assert_equal false, first_report.fetch("already_ingested")
    first_digest = Digest::SHA256.file(@output).hexdigest

    second = run_intake
    assert second[:status].success?, second[:stderr]
    second_report = JSON.parse(second[:stdout])
    assert_equal true, second_report.fetch("already_ingested")
    assert_equal first_digest, Digest::SHA256.file(@output).hexdigest

    @output.write("conflicting bytes\n")
    conflict = run_intake
    refute conflict[:status].success?
    assert_includes conflict[:stderr], "existing decision intake conflicts"
    assert_equal "conflicting bytes\n", @output.read
  end

  def test_generated_branch_cut_complete_founder_pass_runs_local_upscale_and_opens_03v_only_after_validation
    audio_fixture = ActiveAudioBranchCutPlacementFixture.create
    begin
      board = ActiveReviewBoardFixture.create(
        mv: audio_fixture.image_fixture.mv,
        returned_output_path: audio_fixture.review_path,
        cycle_kind: "g50_branch_results"
      )
      derivatives = remove_passed_derivatives(audio_fixture)
      use_board_paths(board)
      write_export(board.decision_export)

      first = run_intake

      assert first[:status].success?, first[:stderr]
      first_report = JSON.parse(first[:stdout])
      transition = first_report.fetch("post_pass_transition")
      assert_equal true, transition.fetch("triggered")
      assert_equal "explicit_complete_founder_pass_intake", transition.fetch("trigger")
      assert_equal "complete", transition.fetch("local_processing")
      assert_equal derivatives.length, transition.fetch("upscaled_packet_count")
      assert_equal 0, transition.fetch("reused_packet_count")
      assert_equal "video_motion_direction", transition.fetch("next_stage")
      assert_equal true, transition.fetch("03v_may_start")
      derivatives.each do |row|
        assert row.fetch(:output).file?
        assert row.fetch(:receipt).file?
      end

      second = run_intake

      assert second[:status].success?, second[:stderr]
      second_transition = JSON.parse(second[:stdout]).fetch("post_pass_transition")
      assert_equal derivatives.length, second_transition.fetch("reused_packet_count")
      assert_equal true, second_transition.fetch("03v_may_start")
    ensure
      audio_fixture.cleanup
    end
  end

  def test_generated_branch_cut_hold_never_runs_local_upscale_or_routes_03v
    audio_fixture = ActiveAudioBranchCutPlacementFixture.create
    begin
      set_generated_review_pending(audio_fixture)
      board = ActiveReviewBoardFixture.create(
        mv: audio_fixture.image_fixture.mv,
        returned_output_path: audio_fixture.review_path,
        cycle_kind: "g50_branch_results"
      )
      derivatives = remove_passed_derivatives(audio_fixture)
      use_board_paths(board)
      export = board.decision_export(
        decisions: lambda do |rows|
          rows.last["action"] = "hold"
          rows.last["note"] = "Hold this generated Branch Cut; do not process or route it to 03V."
          rows
        end
      )
      write_export(export)

      result = run_intake

      assert result[:status].success?, result[:stderr]
      transition = JSON.parse(result[:stdout]).fetch("post_pass_transition")
      assert_equal false, transition.fetch("triggered")
      assert_equal "founder_decision_is_not_complete_all_pass", transition.fetch("reason")
      pending_review = YAML.safe_load(audio_fixture.review_path.read, aliases: true)
      assert_equal "founder_review", pending_review.fetch("status")
      assert_equal false, pending_review.dig("automation_boundaries", "audio_branch_cut_placement_may_start_after_pass")
      derivatives.each do |row|
        refute row.fetch(:output).exist?
        refute row.fetch(:receipt).exist?
      end
    ensure
      audio_fixture.cleanup
    end
  end

  def test_generated_branch_cut_pass_routes_to_audio_placement_when_03v_prerequisite_is_absent
    audio_fixture = ActiveAudioBranchCutPlacementFixture.create
    begin
      set_generated_review_pending(audio_fixture)
      board = ActiveReviewBoardFixture.create(
        mv: audio_fixture.image_fixture.mv,
        returned_output_path: audio_fixture.review_path,
        cycle_kind: "g50_branch_results"
      )
      derivatives = remove_passed_derivatives(audio_fixture)
      FileUtils.rm_f(audio_fixture.placement_path)
      use_board_paths(board)
      write_export(board.decision_export)

      result = run_intake

      assert result[:status].success?, result[:stderr]
      transition = JSON.parse(result[:stdout]).fetch("post_pass_transition")
      assert_equal true, transition.fetch("triggered")
      assert_equal derivatives.length, transition.fetch("upscaled_packet_count")
      assert_equal "founder_direct_update", transition.fetch("review_pass_application")
      assert_equal "audio_branch_cut_placement", transition.fetch("next_stage")
      assert_equal false, transition.fetch("03v_may_start")
      passed_review = YAML.safe_load(audio_fixture.review_path.read, aliases: true)
      assert_equal "passed", passed_review.fetch("status")
      assert_equal true, passed_review.dig("automation_boundaries", "audio_branch_cut_placement_may_start_after_pass")
    ensure
      audio_fixture.cleanup
    end
  end

  def test_member_visual_identity_upscales_only_the_generated_image_on_an_explicit_pass_card
    board = ActiveReviewBoardFixture.create(cycle_kind: "g20_visual_identity_lock")
    begin
      source = configure_member_visual_generated_output(board)
      use_board_paths(board)
      export = board.decision_export(
        decisions: lambda do |rows|
          rows.each do |row|
            row["action"] = "hold"
            row["note"] = "Keep this card on hold."
          end
          rows.last["action"] = "pass"
          rows.last["note"] = ""
          rows
        end
      )
      write_export(export)

      result = run_intake

      assert result[:status].success?, result[:stderr]
      transition = JSON.parse(result[:stdout]).fetch("post_pass_transition")
      assert_equal true, transition.fetch("triggered")
      assert_equal "g20_visual_identity_lock", transition.fetch("cycle_kind")
      assert_equal 1, transition.fetch("upscaled_visual_count")
      assert_equal "current_title_member_visual_promotion", transition.fetch("next_stage")
      assert_equal false, transition.fetch("03v_may_start")
      visual = transition.fetch("visuals").first
      assert_equal board.relative(source), visual.fetch("source")
      assert ROOT.join(visual.fetch("output")).file?
      receipt = JSON.parse(ROOT.join(visual.fetch("receipt")).read)
      assert_equal "founder_passed_generated_visual", receipt.dig("operations", 0, "purpose")
      assert_equal 3840, receipt.dig("operations", 0, "output", "pixel_dimensions").values.max
    ensure
      board.cleanup
    end
  end

  def test_member_visual_identity_without_any_pass_creates_no_upscaled_visual
    board = ActiveReviewBoardFixture.create(cycle_kind: "g20_visual_identity_lock")
    begin
      source = configure_member_visual_generated_output(board)
      use_board_paths(board)
      export = board.decision_export(
        decisions: lambda do |rows|
          rows.each do |row|
            row["action"] = "hold"
            row["note"] = "No visual is passed in this decision export."
          end
          rows
        end
      )
      write_export(export)

      result = run_intake

      assert result[:status].success?, result[:stderr]
      transition = JSON.parse(result[:stdout]).fetch("post_pass_transition")
      assert_equal false, transition.fetch("triggered")
      assert_equal "no_explicit_founder_pass", transition.fetch("reason")
      refute Pathname.new("#{source}.upscale.json").exist?
    ensure
      board.cleanup
    end
  end

  def test_branch_cut_hold_routes_only_the_declared_local_owner
    export = @fixture.decision_export(
      decisions: lambda do |rows|
        rows.last["action"] = "hold"
        rows.last["note"] = "Keep the section and Core Cut; revise only the hand-token contact Branch Cut."
        rows
      end
    )
    write_export(export)

    result = run_intake

    assert result[:status].success?, result[:stderr]
    intake = YAML.safe_load(@output.read, aliases: true)
    held = intake.fetch("decisions").last
    assert_equal "hold", held.fetch("action")
    assert_equal "founder_hold", held.fetch("routing_status")
    assert_equal "branch_cut", held.fetch("revision_scope")
    assert_equal ["S01"], held.fetch("affected_section_ids")
    assert_equal "BC01_ACTION", held.dig("review_target", "branch_cut_id")
    assert_equal 1, intake.dig("summary", "hold_count")
  end

  def test_hold_without_annotation_fails_closed
    export = @fixture.decision_export(
      decisions: lambda do |rows|
        rows.last["action"] = "hold"
        rows
      end
    )
    write_export(export)

    result = run_intake

    refute result[:status].success?
    assert_includes result[:stderr], "decision export failed schema validation"
    refute @output.exist?
  end

  def test_old_export_version_is_rejected_without_migration
    export = @fixture.decision_export
    export["schema_version"] = "idol-html-review-board.decision-export.v4"
    write_export(export)

    result = run_intake

    refute result[:status].success?
    assert_includes result[:stderr], "'idol-html-review-board.decision-export.v12' was expected"
  end

  def test_export_cannot_expand_a_branch_cut_decision_to_section_scope
    export = @fixture.decision_export
    export.fetch("decisions").last["revision_scope"] = "section"
    write_export(export)

    result = run_intake

    refute result[:status].success?
    assert_includes result[:stderr], "revision_scope drifted from the active workbench manifest"
  end

  def test_partial_export_is_preserved_as_hold_with_missing_review_keys
    export = @fixture.decision_export
    export["decisions"] = export.fetch("decisions").last(1)
    write_export(export)

    result = run_intake

    assert result[:status].success?, result[:stderr]
    intake = YAML.safe_load(@output.read, aliases: true)
    assert_equal "hold", intake.fetch("status")
    assert_equal 3, intake.dig("summary", "missing_review_keys").length
    assert_equal 1, intake.dig("summary", "decision_count")
  end

  def test_discovery_actions_are_captured_for_synthesis_without_gate_or_lock_inference
    make_sectionless_mode("g00_direction_draft")
    export = @fixture.decision_export(
      decisions: lambda do |rows|
        rows.first["action"] = "connect_these"
        rows.first["related_card_ids"] = rows.first(2).map { |row| row.fetch("card_id") }
        rows
      end
    )
    write_export(export)

    result = run_intake

    assert result[:status].success?, result[:stderr]
    intake = YAML.safe_load(@output.read, aliases: true)
    assert_equal "captured_for_director_synthesis", intake.fetch("status")
    assert_equal "g00_direction_draft", intake.fetch("review_mode")
    assert_equal "exploratory_signal", intake.fetch("decisions").first.fetch("routing_status")
    assert_equal false, intake.dig("automation_boundaries", "gate_status_inferred")
    assert_equal false, intake.dig("automation_boundaries", "unnamed_field_lock_created")
  end

  def test_g30_preserves_route_feedback_without_creating_named_field_locks
    make_sectionless_mode("g30_fp_final")
    write_export(@fixture.decision_export)

    result = run_intake

    assert result[:status].success?, result[:stderr]
    intake = YAML.safe_load(@output.read, aliases: true)
    assert_equal "ready_for_owner_routing", intake.fetch("status")
    refute intake.fetch("decisions").any? { |row| row.key?("named_field_locks") }
    assert_equal 1, intake.fetch("decisions").count { |row| row.fetch("routing_status") == "candidate_selected_for_overall_promotion" }
    assert_equal "overall_routes_one_selected_complete_g30_route_without_automatic_merge",
                 intake.fetch("creative_rereview_policy")
  end

  def test_g30_routes_exactly_one_selected_complete_route
    make_sectionless_mode("g30_fp_final")
    export = @fixture.decision_export(decisions: lambda do |rows|
      rows.first["action"] = "select_candidate"
      rows
    end)
    write_export(export)

    result = run_intake

    assert result[:status].success?, result[:stderr]
    intake = YAML.safe_load(@output.read, aliases: true)
    selected = intake.fetch("decisions").select { |row| row.fetch("action") == "select_candidate" }
    assert_equal 1, selected.length
    assert_equal "candidate_selected_for_overall_promotion", selected.first.fetch("routing_status")
    assert_equal "ready_for_owner_routing", intake.fetch("status")
    assert_equal false, intake.dig("automation_boundaries", "gate_status_inferred")
  end

  def test_g30_rejects_multiple_selected_complete_routes
    make_sectionless_mode("g30_fp_final")
    export = @fixture.decision_export(decisions: lambda do |rows|
      rows.first(2).each do |row|
        row["action"] = "select_candidate"
      end
      rows
    end)
    write_export(export)

    result = run_intake

    refute result[:status].success?
    assert_includes result[:stderr], "at most one selected complete route"
    refute @output.exist?
  end

  private

  def make_sectionless_mode(review_mode)
    board = @fixture.manifest.fetch("board")
    board["review_mode"] = review_mode
    cycle = @fixture.manifest.fetch("sections").first
    cycle["review_mode"] = review_mode
    if review_mode == "g00_direction_draft"
      cycle["scope_mode"] = "sectionless"
      cycle["covered_section_ids"] = []
      cycle.delete("section_id")
      @fixture.manifest["decision_options"] = [
        {"id" => "attracted", "label" => "ATTRACTED", "tone" => "pass"},
        {"id" => "reject", "label" => "REJECT", "tone" => "reject"},
        {"id" => "hold", "label" => "HOLD", "tone" => "hold"},
        {"id" => "connect_these", "label" => "CONNECT THESE", "tone" => "neutral"},
        {"id" => "keep_only", "label" => "KEEP ONLY", "tone" => "neutral"},
        {"id" => "search_further", "label" => "SEARCH FURTHER", "tone" => "revise"},
        {"id" => "direct_comment", "label" => "DIRECT COMMENT", "tone" => "neutral"}
      ]
    else
      @fixture.manifest["decision_options"] = [
        {"id" => "select_candidate", "label" => "SELECT COMPLETE ROUTE", "tone" => "pass"},
        {"id" => "hold", "label" => "HOLD", "tone" => "hold"},
        {"id" => "reject", "label" => "REJECT", "tone" => "reject"},
        {"id" => "direct_comment", "label" => "DIRECT COMMENT", "tone" => "neutral"}
      ]
      cycle["cards"] = cycle.fetch("cards").first(3)
    end
    cycle.fetch("cards").each_with_index do |card, index|
      old_target_id = card.dig("review_target", "target_id")
      if review_mode == "g30_fp_final"
        card["variant"] = index.zero? ? "recommendation" : "candidate_alternative"
        card["card_type"] = "candidate_route"
        card["route_id"] = "FP-#{("A".ord + index).chr}"
        card["route_readiness"] = {
          "opening_to_ending_story_complete" => true,
          "section_major_stacks_complete" => true,
          "sequence_composition_sets_complete" => true,
          "core_visual_candidate_sets_complete" => true,
          "selected_exact_reference_or_waiver_complete" => true,
          "required_hero_proof_complete" => true,
          "actual_visual_present" => true,
          "materially_distinct" => true
        }
      end
      card["revision_scope"] = "none"
      card["affected_section_ids"] = [] if review_mode == "g00_direction_draft"
      replacement_target = {
        "target_id" => "TARGET-#{review_mode.upcase}-#{index + 1}",
        "level" => review_mode == "g00_direction_draft" ? "discovery" : "direction",
        "display_number" => "#{review_mode == 'g00_direction_draft' ? 'D' : 'R'}#{index + 1}",
        "label" => "#{review_mode} candidate #{index + 1}"
      }
      card["review_target"] = replacement_target
      @fixture.manifest.fetch("review_assets").each do |asset|
        asset.fetch("bindings").each do |binding|
          next unless binding["target_id"] == old_target_id
          binding["target_id"] = replacement_target.fetch("target_id")
          binding["target_level"] = replacement_target.fetch("level")
          %w[section_id core_cut_id branch_cut_id].each { |field| binding.delete(field) } if review_mode == "g00_direction_draft"
        end
      end
    end
    if review_mode == "g30_fp_final"
      cycle["g30_readiness"] = {
        "route_ids" => %w[FP-A FP-B FP-C],
        "complete_route_count" => 3,
        "route_candidate_set_complete" => true,
        "routes_materially_distinct" => true,
        "actual_visuals_present" => true,
        "reference_complete" => true,
        "hero_generated" => true,
        "controls_enabled" => true,
        "hold_reasons" => []
      }
    end
    @fixture.write_manifest
  end

  def write_export(document)
    @export.dirname.mkpath
    @export.write(JSON.pretty_generate(document))
  end

  def use_board_paths(board)
    @export = board.mv.run_dir.join("review", "local-generated-decision-export.json")
    @output = board.mv.run_dir.join("review", "decision-intake", "generated-board-r1.yaml")
  end

  def remove_passed_derivatives(audio_fixture)
    audio_fixture.review.fetch("branch_cut_reviews").map do |row|
      source = ROOT.join(row.fetch("image_path"))
      receipt = Pathname.new("#{source}.upscale.json")
      operation = JSON.parse(receipt.read).fetch("operations").first
      output = ROOT.join(operation.dig("output", "path"))
      FileUtils.rm_f(output)
      FileUtils.rm_f(receipt)
      {source: source, output: output, receipt: receipt}
    end
  end

  def set_generated_review_pending(audio_fixture)
    audio_fixture.review["status"] = "founder_review"
    audio_fixture.review.fetch("automation_boundaries")["audio_branch_cut_placement_may_start_after_pass"] = false
    audio_fixture.rewrite_review
  end

  def configure_member_visual_generated_output(board)
    cycle = board.manifest.fetch("sections").first
    board.manifest.fetch("board")["stage_id"] = "front_planning_integration"
    cycle["stage_id"] = "front_planning_integration"
    source = board.mv.run_dir.join("work", "member-visual-builds", "M01", "candidate.png")
    source.dirname.mkpath
    code = "from PIL import Image; import sys; Image.new('RGB', (320, 180), (72, 96, 128)).save(sys.argv[1], format='PNG')"
    created = run_command(ROOT.join("scripts", "idol-video-python"), "-c", code, source)
    raise "member visual fixture PNG creation failed: #{created[:stderr]}" unless created[:status].success?
    sha = Digest::SHA256.file(source).hexdigest
    board.manifest.fetch("review_assets").each do |asset|
      asset["canonical_path"] = board.relative(source)
      asset["sha256"] = sha
      asset["media_kind"] = "image"
      asset["role"] = "member_visual"
      asset["inspection_action"] = "pixel_review_generated_output"
      asset["surface_locator"] = {
        "source_asset_id" => "M01-CURRENT-TITLE-CANDIDATE",
        "selected_cell_or_frame_id" => "clean-three-panel-card",
        "surface_kind" => "full_image"
      }
    end
    board.write_manifest
    source
  end

  def run_intake
    run_command(
      RbConfig.ruby,
      INTAKE_SCRIPT,
      @export,
      "--output",
      @output,
      "--write"
    )
  end

  def run_command(*arguments)
    stdout, stderr, status = Open3.capture3(
      *arguments.map(&:to_s),
      chdir: ROOT.to_s
    )
    {stdout: stdout, stderr: stderr, status: status}
  end
end
