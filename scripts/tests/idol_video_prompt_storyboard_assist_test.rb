# frozen_string_literal: true

require "digest"
require "json"
require "minitest/autorun"
require "open3"
require "pathname"
require "rbconfig"
require "yaml"
require_relative "support/active_03v_fixture"
require_relative "../lib/idol_grok_video_execution_package"

class IdolVideoPromptStoryboardAssistTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  SCRIPT = ROOT.join("scripts", "validate_video_prompt_storyboard_assist.rb")
  SCHEMA = ROOT.join("schemas", "video-prompt-storyboard-assist.schema.json")

  def teardown
    @fixture&.cleanup
  end

  def test_official_core_and_branch_union_is_active
    @fixture = Active03VFixture.create(branch_count: 3, include_official_core: true)
    result = validate
    assert result[:status].success?, errors(result)
    images = @fixture.assist.dig("boards", 0, "source_production_cut_images")
    assert_equal %w[official_core branch branch], images.map { |image| image["production_cut_type"] }
    assert_equal %w[@image2 @image3 @image4], images.map { |image| image["attachment_slot"] }
  end

  def test_one_image_board_requires_reason
    @fixture = Active03VFixture.create(branch_count: 1, include_official_core: true)
    @fixture.assist.dig("boards", 0)["one_image_board_reason"] = nil
    @fixture.rewrite_assist
    result = validate
    refute result[:status].success?
    assert_match(/one-image board requires|expected.*object/i, errors(result))
  end

  def test_same_parent_is_default_and_cross_core_requires_explicit_transition
    @fixture = Active03VFixture.create(
      branch_count: 4,
      board_groups: [[0, 3]],
      include_official_core: true
    )
    board = @fixture.assist.dig("boards", 0)
    board["relationship_mode"] = "same_parent_core"
    board["cross_core_transition"] = nil
    @fixture.rewrite_assist
    result = validate
    refute result[:status].success?
    assert_includes errors(result), "same-parent board must have exactly one parent Core"
  end

  def test_explicit_cross_core_transition_passes
    @fixture = Active03VFixture.create(
      branch_count: 4,
      board_groups: [[0, 3]],
      include_official_core: true
    )
    result = validate
    assert result[:status].success?, errors(result)
  end

  def test_storyline_sequence_major_and_screen_lineage_drift_all_hold
    @fixture = Active03VFixture.create(branch_count: 2, include_official_core: true)
    board = @fixture.assist.dig("boards", 0)
    board.dig("active_storyline_binding")["source_value_sha256"] = "1" * 64
    board.dig("selected_sequence_binding")["source_value_sha256"] = "2" * 64
    board.dig("major_scene_binding")["major_scene_id"] = "MJ99"
    board.dig("screen_progression_binding", "node_sources", 0)["source_value_sha256"] = "3" * 64
    @fixture.rewrite_assist

    result = validate

    refute result[:status].success?
    detail = errors(result)
    assert_includes detail, "active_storyline_binding source value SHA-256 is stale"
    assert_includes detail, "selected_sequence_binding source value SHA-256 is stale"
    assert_includes detail, "major_scene_id differs from exact FP Major"
    assert_includes detail, "screen_progression_binding.node_sources[0] source value SHA-256 is stale"
  end

  def test_board_panel_count_and_prompt_slots_are_exact
    @fixture = Active03VFixture.create(branch_count: 2)
    @fixture.assist.dig("boards", 0, "board_image")["panel_count"] = 1
    @fixture.assist.dig("boards", 0, "prompt_handoff")["prompt_text"] = "@image1 maps motion. @image2 preserves pixels. @image4 is unbound."
    @fixture.rewrite_assist
    result = validate
    refute result[:status].success?
    assert_includes errors(result), "panel_count must equal source Production Cut image count"
    assert_includes errors(result), "prompt_text must explicitly bind @image3"
    assert_includes errors(result), "prompt_text names unused attachment @image4"
  end

  def test_passed_pixel_hash_drift_holds
    @fixture = Active03VFixture.create(branch_count: 2)
    @fixture.assist.dig("boards", 0, "source_production_cut_images", 0)["sha256"] = "0" * 64
    @fixture.rewrite_assist
    result = validate
    refute result[:status].success?
    assert_match(/SHA-256 is stale|differs from passed Production Cut review/i, errors(result))
  end

  def test_old_branch_only_version_is_rejected
    @fixture = Active03VFixture.create(branch_count: 2)
    @fixture.assist["schema_version"] = "idol_video_prompt_storyboard_assist.v3"
    @fixture.rewrite_assist
    result = validate
    refute result[:status].success?
    assert_includes errors(result), "only idol_video_prompt_storyboard_assist.v4 is active"
  end

  def test_schema_declares_original_pixel_authority_and_one_frame_default
    text = SCHEMA.read
    assert_includes text, "official_core"
    assert_includes text, "branch"
    assert_includes text, "one_passed_production_cut_still_image_one_frame"
    assert_includes text, "if_present_non_visual_alignment_guide_never_render_in_video"
  end

  def test_board_images_must_appear_on_the_full_storyboard_angle_review
    @fixture = Active03VFixture.create(branch_count: 2, include_official_core: true)
    result = validate
    assert result[:status].success?, errors(result)
    storyboard = YAML.safe_load(@fixture.master_storyboard_path.read, aliases: true)
    reviewed = storyboard.dig(
      "camera_diversity_review",
      "collected_image_camera_angle_review",
      "distinct_images"
    ).map { |row| row.fetch("cut_id") }
    board_ids = @fixture.assist.dig("boards", 0, "source_production_cut_images").map { |image| image.fetch("production_cut_id") }
    board_ids.each { |cut_id| assert_includes reviewed, cut_id }
  end

  def test_duplicate_board_pixel_hash_is_not_a_new_image
    @fixture = Active03VFixture.create(branch_count: 2)
    images = @fixture.assist.dig("boards", 0, "source_production_cut_images")
    images[1] = images.fetch(0).merge(images.fetch(1).slice("board_order", "attachment_slot", "unique_state_role"))
    @fixture.rewrite_assist
    result = validate
    refute result[:status].success?
    detail = errors(result)
    refute_match(/SHA-256 is stale/, detail)
    assert_match(/pixel SHA-256 values on one board must be unique/, detail)
  end

  def test_branch_board_transports_placement_upscale_and_keeps_reviewed_original
    @fixture = Active03VFixture.create(branch_count: 2)
    result = validate
    assert result[:status].success?, errors(result)
    images = @fixture.assist.dig("boards", 0, "source_production_cut_images")
    assert images.all? { |image| image.fetch("production_cut_type") == "branch" }
    images.each do |image|
      review_row = @fixture.source_fixture.production_review.fetch("production_cut_reviews").find do |row|
        row.fetch("production_cut_id") == image.fetch("production_cut_id")
      end
      unit = @fixture.source_fixture.placement.fetch("production_cut_units").find do |row|
        row.fetch("production_cut_id") == image.fetch("production_cut_id")
      end
      assert_equal unit.dig("placement_image", "path"), image.fetch("path")
      assert_equal unit.dig("placement_image", "sha256"), image.fetch("sha256")
      assert_equal review_row.fetch("path"), unit.dig("passed_source_image", "path")
      assert_equal review_row.fetch("sha256"), unit.dig("passed_source_image", "sha256")
      refute_equal unit.fetch("passed_source_image"), unit.fetch("placement_image")
      assert_equal "validated_local_upscale", unit.fetch("placement_image_role")
    end
  end

  def test_official_core_board_keeps_reviewed_original
    @fixture = Active03VFixture.create(branch_count: 1, include_official_core: true)
    result = validate
    assert result[:status].success?, errors(result)
    image = @fixture.assist.dig("boards", 0, "source_production_cut_images", 0)
    assert_equal "official_core", image.fetch("production_cut_type")
    review_row = @fixture.source_fixture.production_review.fetch("production_cut_reviews").find do |row|
      row.fetch("production_cut_id") == image.fetch("production_cut_id")
    end
    unit = @fixture.source_fixture.placement.fetch("production_cut_units").find do |row|
      row.fetch("production_cut_id") == image.fetch("production_cut_id")
    end
    assert_equal review_row.fetch("path"), image.fetch("path")
    assert_equal review_row.fetch("sha256"), image.fetch("sha256")
    assert_equal unit.fetch("passed_source_image"), unit.fetch("placement_image")
    assert_equal unit.fetch("passed_source_image"), image.slice("path", "sha256")
    assert_equal "original_passed_pixels", unit.fetch("placement_image_role")
  end

  def test_missing_branch_upscale_holds
    @fixture = Active03VFixture.create(branch_count: 2)
    image = @fixture.assist.dig("boards", 0, "source_production_cut_images", 0)
    image["path"] = @fixture.run_dir.join("work", "03v-fixtures", "missing-branch-upscale.png").relative_path_from(ROOT).to_s
    @fixture.rewrite_assist
    result = validate
    refute result[:status].success?
    assert_match(/missing or outside the repository|board\/execution image must exact-match the audio-placement placement_image/, errors(result))
  end

  def test_stale_branch_upscale_holds
    @fixture = Active03VFixture.create(branch_count: 2)
    image = @fixture.assist.dig("boards", 0, "source_production_cut_images", 0)
    image["sha256"] = "0" * 64
    @fixture.rewrite_assist
    result = validate
    refute result[:status].success?
    assert_match(/SHA-256 is stale/, errors(result))
  end

  def test_foreign_branch_upscale_holds
    @fixture = Active03VFixture.create(branch_count: 2)
    images = @fixture.assist.dig("boards", 0, "source_production_cut_images")
    board_ids = images.map { |image| image.fetch("production_cut_id") }
    foreign = @fixture.source_fixture.placement.fetch("production_cut_units").find do |row|
      row.fetch("production_cut_type") == "branch" && !board_ids.include?(row.fetch("production_cut_id"))
    end
    refute_nil foreign
    images.fetch(0)["path"] = foreign.dig("placement_image", "path")
    images.fetch(0)["sha256"] = foreign.dig("placement_image", "sha256")
    @fixture.rewrite_assist
    result = validate
    refute result[:status].success?
    detail = errors(result)
    refute_match(/SHA-256 is stale/, detail)
    assert_match(/board\/execution image must exact-match the audio-placement placement_image/, detail)
  end

  def test_i2v_execution_prompt_may_not_name_unattached_slots
    @fixture = Active03VFixture.create(branch_count: 2)
    assist_result = validate
    assert assist_result[:status].success?, errors(assist_result)
    manifest = @fixture.video_manifest_document
    cue = manifest.fetch("cues").first
    cue["prompt_text"] = "#{cue.fetch('prompt_text')} @image2 @image3"
    cue.fetch("grok_execution")["prompt_sha256"] = Digest::SHA256.hexdigest(cue.fetch("prompt_text"))
    manifest_path = @fixture.run_dir.join("work", "03v-fixtures", "unattached-slot-manifest.yaml")
    manifest_path.write(YAML.dump(manifest))
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      ROOT.join("scripts", "validate_video_prompt_manifest.rb").to_s,
      "--json",
      manifest_path.to_s,
      chdir: ROOT.to_s
    )
    refute status.success?
    detail = begin
      JSON.parse(stdout).fetch("errors").join("\n")
    rescue JSON::ParserError
      stderr
    end
    assert_match(/unattached @image2/, detail)
  end

  def test_execution_package_consumes_branch_upscale_and_keeps_reviewed_original
    @fixture = Active03VFixture.create(branch_count: 2)
    assist_result = validate
    assert assist_result[:status].success?, errors(assist_result)
    manifest = @fixture.video_manifest_document
    cue = manifest.fetch("cues").first
    inputs = IdolGrokVideoExecutionPackage.ordered_inputs!(
      root: ROOT,
      cue: cue,
      execution: cue.fetch("grok_execution"),
      placement: @fixture.source_fixture.placement,
      production_review: @fixture.source_fixture.production_review
    )
    assert_equal 1, inputs.length
    selected = inputs.first
    unit = @fixture.source_fixture.placement.fetch("production_cut_units").find do |row|
      row.fetch("production_cut_id") == selected.fetch("production_cut_id")
    end
    assert_equal "branch", selected.fetch("production_cut_type")
    assert_equal unit.dig("placement_image", "sha256"), selected.fetch("source_sha256")
    assert_equal unit.dig("passed_source_image", "sha256"), selected.fetch("reviewed_original_sha256")
    refute_equal selected.fetch("source_sha256"), selected.fetch("reviewed_original_sha256")
    assert_equal "validated_local_upscale", selected.fetch("placement_image_role")
  end

  private

  def validate
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, SCRIPT.to_s, "--json", @fixture.assist_path.to_s, chdir: ROOT.to_s)
    {stdout: stdout, stderr: stderr, status: status}
  end

  def errors(result)
    JSON.parse(result[:stdout]).fetch("errors").join("\n")
  rescue JSON::ParserError
    result[:stderr]
  end
end
