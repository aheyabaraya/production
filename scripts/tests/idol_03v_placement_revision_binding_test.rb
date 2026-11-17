# frozen_string_literal: true

require "json"
require "minitest/autorun"
require "open3"
require "pathname"
require "rbconfig"
require "yaml"
require_relative "support/active_audio_branch_cut_placement_fixture"

class Idol03VPlacementRevisionBindingTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  VALIDATOR = ROOT.join("scripts", "validate_audio_branch_cut_placement.rb")

  def setup
    @fixture = ActiveAudioBranchCutPlacementFixture.create
  end

  def teardown
    @fixture&.cleanup
  end

  def test_active_v5_accepts_typed_official_core_and_branch_pixel_lineage
    result = validate(require_ready: true)

    assert result[:status].success?, errors(result)
    assert_equal "idol_audio_production_cut_placement.v5", @fixture.placement.fetch("schema_version")
    assert_equal true, @fixture.placement.dig("automation_boundaries", "storyboard_board_not_created")
    assert_equal false, @fixture.placement.dig("automation_boundaries", "camera_motion_authored")
    units = @fixture.placement.fetch("production_cut_units")
    assert_equal %w[official_core branch branch official_core branch], units.map { |unit| unit.fetch("production_cut_type") }
    assert units.all? { |unit| unit.fetch("camera_motion_unassigned") }
    refute units.any? { |unit| unit.key?("camera_route") }
  end

  def test_previous_placement_versions_are_not_active_compatibility_inputs
    @fixture.placement["schema_version"] = "idol_audio_frame_placement.v3"
    @fixture.rewrite_placement

    result = validate

    refute result[:status].success?
    assert_includes errors(result), "only idol_audio_production_cut_placement.v5 is active"
  end

  def test_camera_motion_cannot_be_pre_authored_in_audio_branch_cut_placement
    unit = @fixture.placement.fetch("production_cut_units").first
    unit["camera_motion_unassigned"] = false
    unit["camera_route"] = "Track left before 03V inspects the pixels."
    @fixture.rewrite_placement

    result = validate

    refute result[:status].success?
    assert_match(/camera_route|camera_motion_unassigned/i, errors(result))
  end

  def test_review_byte_drift_invalidates_only_the_bound_placement_source
    @fixture.production_review.fetch("authority_boundary")["playback_pass_implied"] = true
    @fixture.rewrite_production_review(refresh_placement_hash: false)

    result = validate

    refute result[:status].success?
    assert_includes errors(result), "source_production_cut_review SHA-256 is stale"
  end

  def test_placement_pixel_truth_must_exact_copy_the_passed_review
    @fixture.placement.fetch("production_cut_units").first["actual_visible_state"] =
      "A different unreviewed frontal portrait replaces the passed pixel state."
    @fixture.rewrite_placement

    result = validate

    refute result[:status].success?
    assert_includes errors(result), "actual_visible_state must exact-copy typed pixel review truth"
  end

  def test_passed_review_must_exact_cover_the_approved_02b_packets
    @fixture.review.fetch("branch_cut_reviews").pop
    @fixture.review.fetch("section_reviews").first.fetch("packet_ids").pop
    @fixture.rewrite_review

    result = validate

    refute result[:status].success?
    assert_includes errors(result), "source Production Cut review failed active validation"
  end

  def test_coverage_counts_recompute_from_ordered_branch_timing
    @fixture.placement.fetch("production_cut_units").last["start_seconds"] = 4.25
    @fixture.rewrite_placement

    result = validate

    refute result[:status].success?
    assert_includes errors(result), "coverage.positive_gap_count is stale"
  end

  def test_choreography_policy_must_remain_owned_by_02a
    @fixture.placement.fetch("production_cut_units").first["choreography_presence_policy"] = "primary"
    @fixture.rewrite_placement

    result = validate

    refute result[:status].success?
    assert_includes errors(result), "choreography policy differs from exact 01 Section direction"
  end

  def test_official_core_pixel_path_cannot_be_replaced_by_a_branch_or_arbitrary_image
    core = @fixture.placement.fetch("production_cut_units").find { |unit| unit["production_cut_type"] == "official_core" }
    branch = @fixture.placement.fetch("production_cut_units").find { |unit| unit["production_cut_type"] == "branch" }
    core["passed_source_image"] = branch.fetch("passed_source_image")
    core["placement_image"] = branch.fetch("passed_source_image")
    @fixture.rewrite_placement

    result = validate

    refute result[:status].success?
    assert_includes errors(result), "passed_source_image differs from typed passed pixel authority"
  end

  def test_screen_progression_node_drift_is_rejected_against_typed_review
    @fixture.placement.fetch("production_cut_units").first["screen_progression_node_id"] = "SPN_FABRICATED"
    @fixture.rewrite_placement

    result = validate

    refute result[:status].success?
    assert_includes errors(result), "screen_progression_node_id differs from typed Production Cut review"
  end

  private

  def validate(require_ready: false)
    command = [
      RbConfig.ruby,
      VALIDATOR.to_s,
      "--json"
    ]
    command << "--require-ready" if require_ready
    command << @fixture.placement_path.to_s
    stdout, stderr, status = Open3.capture3(*command, chdir: ROOT.to_s)
    {stdout: stdout, stderr: stderr, status: status}
  end

  def errors(result)
    parsed = JSON.parse(result.fetch(:stdout))
    ([result.fetch(:stderr)] + parsed.fetch("errors")).reject(&:empty?).join("\n")
  end
end
