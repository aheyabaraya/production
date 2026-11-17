# frozen_string_literal: true

require "json"
require "minitest/autorun"
require "open3"
require "pathname"
require "rbconfig"
require "yaml"
require_relative "support/active_03v_fixture"

class Idol03VManifestIndexExactnessTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  VALIDATOR = ROOT.join("scripts", "validate_video_prompt_manifest.rb")

  def teardown
    @fixture&.cleanup
  end

  def test_active_v7_exactly_binds_board_original_production_cut_images_and_03v_camera_route
    build(branch_count: 3)

    result = validate

    assert result[:status].success?, errors(result)
    cue = @document.fetch("cues").first
    assert_equal cue.fetch("source_production_cut_images").map { |row| row.fetch("production_cut_id") },
                 cue.fetch("source_image_ids")
    assert_equal cue.fetch("source_production_cut_images").map { |row| row.fetch("sha256") },
                 cue.fetch("source_pixel_hashes")
    assert_equal "03V_after_passed_production_cut_review_and_audio_production_cut_placement",
                 @document.dig("prompt_authoring_policy", "temporal_camera_owner")
    assert_equal "04_after_passed_03V_playback",
                 @document.dig("prompt_authoring_policy", "edit_owner")
  end

  def test_storyboard_board_byte_drift_fails_closed
    build(branch_count: 2)
    assist = YAML.safe_load(@fixture.assist_path.read, aliases: true)
    board_path = ROOT.join(assist.dig("boards", 0, "board_image", "path"))
    board_path.binwrite("changed storyboard pixels\n")

    result = validate

    refute result[:status].success?
    assert_match(/board_image.*SHA-256 is stale|source storyboard assist failed/i, errors(result))
  end

  def test_original_passed_branch_cut_byte_drift_fails_closed
    build(branch_count: 2)
    image_path = ROOT.join(@document.dig("cues", 0, "source_production_cut_images", 0, "path"))
    original_bytes = image_path.binread
    begin
      image_path.binwrite("changed original Branch-Cut pixels\n")

      result = validate

      refute result[:status].success?
      assert_match(/source_production_cut_images\[0\].*SHA-256 is stale|source storyboard assist failed/i, errors(result))
    ensure
      image_path.binwrite(original_bytes)
    end
  end

  def test_manifest_cannot_reorder_the_original_branch_image_attachments
    build(branch_count: 3)
    @document.dig("cues", 0, "source_production_cut_images").reverse!

    result = validate

    refute result[:status].success?
    assert_match(/source Production Cut images differ/i, errors(result))
  end

  def test_source_image_ids_cannot_name_an_unbound_production_cut
    build(branch_count: 2)
    @document.dig("cues", 0, "source_image_ids") << "BC_FAKE"

    result = validate

    refute result[:status].success?
    assert_match(/source_image_ids must exact-project source order|unique/i, errors(result))
  end

  def test_temporal_camera_route_requires_a_readable_stop_and_reason
    build(branch_count: 2)
    camera = @document.dig("cues", 0, "camera_motion_route")
    camera.delete("stop_trigger")
    camera.delete("readability_reason")

    result = validate

    refute result[:status].success?
    assert_match(/stop_trigger|readability_reason/i, errors(result))
  end

  def test_section_shards_must_exact_cover_every_cue_once
    build(branch_count: 4, board_groups: [[0, 1, 2], [3]])
    @document.fetch("section_shards").first["cue_ids"] =
      [@document.fetch("cues").first.fetch("cue_id")]

    result = validate

    refute result[:status].success?
    assert_includes errors(result), "section shards must exact-cover all cues once"
  end

  def test_core_branch_screen_job_cannot_drift_from_exact_02a_bindings
    build(branch_count: 2)
    cue = @document.fetch("cues").first
    cue["core_branch_screen_job"] = "fabricated screen job"

    result = validate

    refute result[:status].success?
    assert_includes errors(result), "core_branch_screen_job differs from exact 02A screen jobs"
  end

  def test_v3_manifest_is_rejected_instead_of_entering_a_compatibility_branch
    build(branch_count: 2)
    @document["schema_version"] = "idol_video_prompt_manifest.v3"

    result = validate

    refute result[:status].success?
    assert_includes errors(result), "only idol_video_prompt_manifest.v8 is active"
  end

  private

  def build(branch_count:, board_groups: nil)
    @fixture = Active03VFixture.create(branch_count: branch_count, board_groups: board_groups)
    @document = @fixture.video_manifest_document
  end

  def validate
    path = @fixture.run_dir.join("03V-video-prompt-manifest.yaml")
    path.write(YAML.dump(@document))
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      VALIDATOR.to_s,
      "--json",
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
