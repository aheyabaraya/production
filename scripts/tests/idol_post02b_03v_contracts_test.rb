# frozen_string_literal: true

require "json"
require "fileutils"
require "minitest/autorun"
require "open3"
require "pathname"
require "rbconfig"
require "yaml"
require_relative "support/active_03v_fixture"
require_relative "support/active_audio_branch_cut_placement_fixture"

class IdolPost02B03VContractsTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  REVIEW_VALIDATOR = ROOT.join("scripts", "validate_generated_branch_cut_review.rb")
  PLACEMENT_VALIDATOR = ROOT.join("scripts", "validate_audio_branch_cut_placement.rb")
  STORYBOARD_VALIDATOR = ROOT.join("scripts", "validate_video_prompt_storyboard_assist.rb")
  MANIFEST_VALIDATOR = ROOT.join("scripts", "validate_video_prompt_manifest.rb")

  def teardown
    @fixtures&.each(&:cleanup)
  end

  def test_approved_02b_passed_pixels_and_audio_placement_form_one_exact_active_lineage
    fixture = track(ActiveAudioBranchCutPlacementFixture.create)

    review_result = run_json(REVIEW_VALIDATOR, fixture.review_path)
    placement_result = run_json(PLACEMENT_VALIDATOR, fixture.placement_path, "--require-ready")

    assert review_result[:status].success?, errors(review_result)
    assert placement_result[:status].success?, errors(placement_result)
    assert_equal fixture.review.dig("source_02a", "sha256"),
                 fixture.placement.dig("source_02a", "sha256")
    assert_equal fixture.review.dig("source_02b", "sha256"),
                 fixture.placement.dig("source_02b", "sha256")
    assert_equal fixture.review.fetch("branch_cut_reviews").map { |row| row.fetch("packet_id") },
                 fixture.placement.fetch("production_cut_units").select { |row| row["production_cut_type"] == "branch" }.map { |row| row.fetch("packet_id") }
  end

  def test_active_02b_export_round_trip_preserves_prompt_bytes_and_attachment_order
    fixture = track(Active03VFixture.create(branch_count: 1))
    source = YAML.safe_load(fixture.prompt_packets_path.read, aliases: true)
    stdout, stderr, status = Open3.capture3(
      ROOT.join("scripts", "idol-video-python").to_s,
      ROOT.join("scripts", "idol_export_02b_prompt_manifests.py").to_s,
      fixture.prompt_packets_path.to_s,
      chdir: ROOT.to_s
    )
    assert status.success?, [stderr, stdout].join("\n")
    index_path = ROOT.join(JSON.parse(stdout).fetch("index"))
    index = YAML.safe_load(index_path.read, aliases: true)
    assert_equal source.fetch("schema_version"), index.dig("source_02b", "schema_version")
    index.fetch("requests").zip(source.fetch("prompt_packets")).each do |row, packet|
      prompt = ROOT.join(row.fetch("prompt_path")).binread
      assert_equal packet.dig("compiled_prompt_block", "full_prompt_text").b, prompt
      assert_equal row.fetch("prompt_sha256"), Digest::SHA256.hexdigest(prompt)
      manifest = YAML.safe_load(ROOT.join(row.fetch("manifest_path")).read, aliases: true)
      assert_equal packet.fetch("attachments").map { |item| item.fetch("binding_id") },
                   manifest.fetch("attachment_order").map { |item| item.fetch("binding_id") }
    end
    command = [RbConfig.ruby, ROOT.join("scripts", "validate_02b_imagegen_contract.rb").to_s,
               "--mode", "preflight", "--export-index", index_path.to_s, fixture.prompt_packets_path.to_s]
    out, err, checked = Open3.capture3(*command, chdir: ROOT.to_s)
    assert checked.success?, [err, out].join("\n")

    # A changed file must not be accepted after silently trimming its bytes.
    prompt_path = ROOT.join(index.fetch("requests").first.fetch("prompt_path"))
    prompt_path.binwrite(prompt_path.binread + "\n")
    out, err, checked = Open3.capture3(*command, chdir: ROOT.to_s)
    refute checked.success?
    assert_includes [err, out].join("\n"), "exported prompt differs from canonical 02B"
  end

  def test_passed_generated_image_without_local_upscale_receipt_is_held
    fixture = track(ActiveAudioBranchCutPlacementFixture.create)
    source = ROOT.join(fixture.review.fetch("branch_cut_reviews").first.fetch("image_path"))
    FileUtils.rm_f("#{source}.upscale.json")

    result = run_json(REVIEW_VALIDATOR, fixture.review_path)

    refute result[:status].success?
    assert_includes errors(result), "passed image is missing its local upscale receipt"
  end

  def test_audio_placement_rejects_reviewed_raw_image_instead_of_upscaled_derivative
    fixture = track(ActiveAudioBranchCutPlacementFixture.create)
    review_row = fixture.review.fetch("branch_cut_reviews").first
    branch_unit = fixture.placement.fetch("production_cut_units").find { |row| row["production_cut_type"] == "branch" }
    branch_unit["placement_image"] = {
      "path" => review_row.fetch("image_path"),
      "sha256" => review_row.fetch("image_sha256")
    }
    fixture.rewrite_placement

    result = run_json(PLACEMENT_VALIDATOR, fixture.placement_path, "--require-ready")

    refute result[:status].success?
    assert_match(
      /placement image path differs from the passed local upscale|placement_image|local upscale receipt must bind exact passed source and placement output/i,
      errors(result)
    )
  end

  def test_one_founder_corrected_pixel_truth_reprojects_only_its_placement_branch
    fixture = track(ActiveAudioBranchCutPlacementFixture.create)
    source_02a_before = fixture.placement.dig("source_02a", "sha256")
    source_02b_before = fixture.placement.dig("source_02b", "sha256")
    revised_truth = "Founder-corrected passed pixel truth for the first Branch Cut only."

    fixture.review.fetch("branch_cut_reviews").first["observable_pixel_truth"] = revised_truth
    fixture.rewrite_review(refresh_placement_hash: false)
    fixture.refresh_production_review
    stale_result = run_json(PLACEMENT_VALIDATOR, fixture.placement_path, "--require-ready")

    refute stale_result[:status].success?
    assert_includes errors(stale_result), "actual_visible_state must exact-copy typed pixel review truth"

    fixture.placement.fetch("production_cut_units").find { |row| row["production_cut_type"] == "branch" }["actual_visible_state"] = revised_truth
    fixture.rewrite_placement
    repaired_result = run_json(PLACEMENT_VALIDATOR, fixture.placement_path, "--require-ready")

    assert repaired_result[:status].success?, errors(repaired_result)
    assert_equal source_02a_before, fixture.placement.dig("source_02a", "sha256")
    assert_equal source_02b_before, fixture.placement.dig("source_02b", "sha256")
  end

  def test_generated_pixel_reviews_carry_forward_after_unrelated_whole_02b_sha_change
    fixture = track(ActiveAudioBranchCutPlacementFixture.create)
    prepare_carried_generated_review(fixture)

    result = run_json(REVIEW_VALIDATOR, fixture.review_path)

    assert result[:status].success?, errors(result)
  end

  def test_delegated_02b_pass_thresholds_and_valid_na_results
    fixture = track(ActiveAudioBranchCutPlacementFixture.create)
    attach_delegated_pixel_close(fixture)
    criterion(fixture, "character_identity_visual_continuity")["result"] = "not_applicable_member_absent"
    criterion(fixture, "material_prop_scale_contact_state_continuity")["result"] = "not_applicable_no_material_prop"
    refresh_delegated_bindings(fixture)
    fixture.rewrite_review(refresh_placement_hash: false)

    passed = run_json(REVIEW_VALIDATOR, fixture.review_path)
    assert passed[:status].success?, errors(passed)

    criterion(fixture, "scene_visual_package")["result"] = 3
    refresh_delegated_bindings(fixture)
    fixture.rewrite_review(refresh_placement_hash: false)
    scene_held = run_json(REVIEW_VALIDATOR, fixture.review_path)
    refute scene_held[:status].success?
    assert_includes errors(scene_held), "still-camera/composition close must equal 4"

    criterion(fixture, "scene_visual_package")["result"] = 4
    criterion(fixture, "action_pose_motion_anchor")["result"] = 3
    refresh_delegated_bindings(fixture)
    fixture.rewrite_review(refresh_placement_hash: false)
    motion_held = run_json(REVIEW_VALIDATOR, fixture.review_path)
    refute motion_held[:status].success?
    assert_includes errors(motion_held), "motion-anchor readability must equal 4"

    criterion(fixture, "action_pose_motion_anchor")["result"] = 4
    criterion(fixture, "multi_reference_synthesis")["result"] = 2
    refresh_delegated_bindings(fixture)
    fixture.rewrite_review(refresh_placement_hash: false)
    held = run_json(REVIEW_VALIDATOR, fixture.review_path)

    refute held[:status].success?
    assert_includes errors(held), "multi_reference_synthesis must be at least 3"
  end

  def test_carried_generated_pixel_review_cannot_change_its_prior_review_content
    fixture = track(ActiveAudioBranchCutPlacementFixture.create)
    prepare_carried_generated_review(fixture)
    fixture.review.fetch("branch_cut_reviews").last["observable_pixel_truth"] =
      "This silently changes a carried pixel judgment."
    fixture.rewrite_review

    result = run_json(REVIEW_VALIDATOR, fixture.review_path)

    refute result[:status].success?
    assert_includes errors(result), "carried review content differs from the bound prior row"
  end

  def test_camera_motion_starts_only_after_audio_branch_cut_placement_and_pixel_inspection
    placement_fixture = track(ActiveAudioBranchCutPlacementFixture.create)
    story_fixture = track(Active03VFixture.create(branch_count: 2))
    board = story_fixture.assist.fetch("boards").first

    assert_equal false,
                 placement_fixture.placement.dig("automation_boundaries", "camera_motion_authored")
    assert placement_fixture.placement.fetch("production_cut_units").all? { |row| row.fetch("camera_motion_unassigned") }
    assert_equal "03V_after_passed_production_cut_review_and_audio_production_cut_placement",
                 story_fixture.video_manifest_document.dig("prompt_authoring_policy", "temporal_camera_owner")
    assert_equal "track",
                 board.dig("prompt_handoff", "camera_motion_route", "movement_family")
    refute_empty board.dig("prompt_handoff", "camera_motion_route", "readability_reason")
  end

  def test_standard_03v_board_uses_one_to_three_production_cut_images_and_exact_attachment_order
    two = track(Active03VFixture.create(branch_count: 2))
    three = track(Active03VFixture.create(branch_count: 3))

    assert_equal %w[@image1 @image2 @image3],
                 two.assist.dig("boards", 0, "prompt_handoff", "attachment_order")
    assert_equal %w[@image1 @image2 @image3 @image4],
                 three.assist.dig("boards", 0, "prompt_handoff", "attachment_order")
    assert_nil two.assist.dig("boards", 0, "one_image_board_reason")
    assert_nil three.assist.dig("boards", 0, "one_image_board_reason")
  end

  def test_storyboard_assist_and_video_manifest_validate_as_separate_active_03v_artifacts
    fixture = track(Active03VFixture.create(branch_count: 3))
    storyboard_result = run_json(STORYBOARD_VALIDATOR, fixture.assist_path)
    manifest = fixture.video_manifest_document
    manifest_path = fixture.run_dir.join("03V-video-prompt-manifest.yaml")
    manifest_path.write(YAML.dump(manifest))
    manifest_result = run_json(MANIFEST_VALIDATOR, manifest_path)

    assert storyboard_result[:status].success?, errors(storyboard_result)
    assert manifest_result[:status].success?, errors(manifest_result)
    assert_equal "04_after_passed_03V_playback",
                 manifest.dig("prompt_authoring_policy", "edit_owner")
    assert manifest.fetch("cues").all? { |cue| cue.fetch("prompt_text").include?("@image1") }
  end

  def test_more_than_three_production_cut_images_split_into_ordered_linked_boards
    fixture = track(
      Active03VFixture.create(branch_count: 4, board_groups: [[0, 1, 2], [3]])
    )
    result = run_json(STORYBOARD_VALIDATOR, fixture.assist_path)
    first, second = fixture.assist.fetch("boards")

    assert result[:status].success?, errors(result)
    assert_equal 3, first.fetch("source_production_cut_images").length
    assert_equal 1, second.fetch("source_production_cut_images").length
    assert_equal first.fetch("storyboard_id"), second.fetch("previous_board_id")
    assert_equal second.fetch("storyboard_id"), first.fetch("next_board_id")
    refute_empty second.dig("one_image_board_reason", "temporal_route_sufficiency")
  end

  def test_old_02b_to_03v_contract_versions_fail_instead_of_migrating
    placement_fixture = track(ActiveAudioBranchCutPlacementFixture.create)
    placement_fixture.placement["schema_version"] = "idol_audio_frame_placement.v3"
    placement_fixture.rewrite_placement
    placement_result = run_json(PLACEMENT_VALIDATOR, placement_fixture.placement_path)

    story_fixture = track(Active03VFixture.create(branch_count: 2))
    manifest = story_fixture.video_manifest_document
    manifest["schema_version"] = "idol_video_prompt_manifest.v3"
    manifest_path = story_fixture.run_dir.join("03V-video-prompt-manifest.yaml")
    manifest_path.write(YAML.dump(manifest))
    manifest_result = run_json(MANIFEST_VALIDATOR, manifest_path)

    refute placement_result[:status].success?
    refute manifest_result[:status].success?
    assert_includes errors(placement_result), "only idol_audio_production_cut_placement.v5 is active"
    assert_includes errors(manifest_result), "only idol_video_prompt_manifest.v8 is active"
  end

  private

  def attach_delegated_pixel_close(fixture)
    fixture.review.fetch("branch_cut_reviews").each do |review|
      review["generated_production_cut_vector"] = {
        "criteria" => %w[
          character_identity_visual_continuity
          scene_visual_package
          action_pose_motion_anchor
          multi_reference_synthesis
          neighbor_cut_distinct_contribution
          artifact_anatomy_crop_provider_input_stability
          material_prop_scale_contact_state_continuity
        ].map do |id|
          {"criterion_id" => id, "result" => %w[scene_visual_package action_pose_motion_anchor].include?(id) ? 4 : 3, "locator" => "full-size pixels: #{id}"}
        end,
        "target_lock_violation" => false,
        "message_lock_violation" => false,
        "material_drift" => false
      }
    end
    source = fixture.review.fetch("source_02a")
    value_ref = source.merge("json_pointer" => "/", "value_sha256" => "0" * 64)
    fixture.review["delegated_pixel_close"] = {
      "schema_version" => "idol_g2_delegated_pixel_close.v1",
      "mode" => "g2_delegated_cdd",
      "decision" => "pass",
      "cdd_owner" => "CDD-V-C1",
      "cdd_lane_id" => "section_cluster_v_c1",
      "section_cohort_id" => "C1",
      "section_ids" => fixture.review.fetch("branch_cut_reviews").map { |row| row.fetch("section_id") }.uniq,
      "g2_envelope" => value_ref,
      "cohort_map" => value_ref,
      "department_dispatches" => [value_ref],
      "generation_approvals" => [source],
      "image_generation_requests" => [source],
      "execution_receipts" => [source],
      "pixel_review_packet_bindings" => [],
      "material_drift" => false,
      "target_lock_violation" => false,
      "message_lock_violation" => false,
      "authority_request_reasons" => [],
      "automatic_fallback" => "none"
    }
    refresh_delegated_bindings(fixture)
  end

  def criterion(fixture, criterion_id)
    fixture.review.fetch("branch_cut_reviews").first.fetch("generated_production_cut_vector").fetch("criteria").find do |row|
      row.fetch("criterion_id") == criterion_id
    end
  end

  def refresh_delegated_bindings(fixture)
    fixture.review.fetch("delegated_pixel_close")["pixel_review_packet_bindings"] =
      fixture.review.fetch("branch_cut_reviews").map do |review|
        {
          "packet_id" => review.fetch("packet_id"),
          "review_value_sha256" => fixture.image_fixture.mv.send(:value_sha, review)
        }
      end
  end

  def prepare_carried_generated_review(fixture)
    prior_review = Marshal.load(Marshal.dump(fixture.review))
    prior_path = fixture.run_dir.join("review", "generated-branch-cut-review-prior.yaml")
    prior_path.write(YAML.dump(prior_review))
    prior_ref = fixture.artifact_ref(prior_path)

    fixture.image_fixture.source_02b.fetch("open_questions") <<
      "An audit-only note changes the whole 02B file SHA."
    fixture.image_fixture.write_source_02b
    fixture.review["source_02b"] = fixture.artifact_ref(fixture.image_fixture.source_02b_path)

    fixture.review.fetch("branch_cut_reviews").each_with_index do |row, index|
      prior_row = prior_review.fetch("branch_cut_reviews").fetch(index)
      row["review_lineage"] = {
        "mode" => "carried_forward_unchanged_packet",
        "source_review" => prior_ref,
        "source_branch_cut_review_value_sha256" =>
          fixture.image_fixture.mv.value_sha(prior_row)
      }
    end
    fixture.review.fetch("section_reviews").each_with_index do |row, index|
      prior_row = prior_review.fetch("section_reviews").fetch(index)
      row["review_lineage"] = {
        "mode" => "carried_forward_unchanged_section",
        "source_review" => prior_ref,
        "source_section_review_value_sha256" =>
          fixture.image_fixture.mv.value_sha(prior_row)
      }
    end
    fixture.rewrite_review
  end

  def track(fixture)
    @fixtures ||= []
    @fixtures << fixture
    fixture
  end

  def run_json(script, path, *options)
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      script.to_s,
      "--json",
      *options,
      path.to_s,
      chdir: ROOT.to_s
    )
    {stdout: stdout, stderr: stderr, status: status}
  end

  def errors(result)
    parsed = JSON.parse(result.fetch(:stdout))
    ([result.fetch(:stderr)] + parsed.fetch("errors")).reject(&:empty?).join("\n")
  end
end
