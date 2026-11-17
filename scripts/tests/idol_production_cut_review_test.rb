# frozen_string_literal: true

require "digest"
require "json"
require "minitest/autorun"
require "open3"
require "pathname"
require "rbconfig"
require "yaml"
require_relative "support/active_production_cut_review_fixture"

class IdolProductionCutReviewTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  VALIDATOR = ROOT.join("scripts", "validate_production_cut_review.rb")

  def teardown
    @fixture&.cleanup
  end

  def test_producer_writes_one_typed_exact_cover_of_passed_official_cores_and_branches
    fixture = build_fixture
    result = run_validator(fixture.review_path)

    assert result.fetch(:status).success?, errors(result)
    assert_equal "idol-production-cut-review.v2", fixture.review.fetch("schema_version")
    assert_equal "passed", fixture.review.fetch("status")
    assert_equal "03-production-cut-review.yaml", fixture.review_path.basename.to_s

    storyboard = fixture.source_fixture.image_fixture.mv.storyboard
    expected_ids = storyboard.fetch("master_storyboard").flat_map do |core|
      [core.fetch("core_cut_id")] + core.dig("compile_seed", "branch_cuts").map { |branch| branch.fetch("branch_cut_id") }
    end
    rows = fixture.review.fetch("production_cut_reviews")
    assert_equal expected_ids, rows.map { |row| row.fetch("production_cut_id") }
    assert_equal %w[official_core branch branch official_core branch], rows.map { |row| row.fetch("production_cut_type") }
    assert_equal expected_ids, fixture.review.dig("coverage", "production_cut_ids")
    assert_equal ["C1"], fixture.review.dig("coverage", "section_cohort_ids")
    assert_equal ["C1"], rows.map { |row| row.fetch("section_cohort_id") }.uniq
    assert_equal [{
      "section_cohort_id" => "C1",
      "section_ids" => ["S01"],
      "source_02b_section_shards" => fixture.review.dig("section_cohort_successions", 0, "source_02b_section_shards"),
      "planning_cdd_lane_id" => "CDD-P3-C1",
      "production_cdd_lane_id" => "CDD-V-C1",
      "carry_policy" => "p3_ci_to_v_ci_exact_same_section_cohort",
      "physical_session_policy" => "primary_plus_successor_max_two_per_stage"
    }], fixture.review.fetch("section_cohort_successions")

    first_core = rows.first
    source_core = storyboard.dig("master_storyboard", 0, "imported_core")
    assert_equal source_core.dig("primary_image", "actual_path"), first_core.fetch("path")
    assert_equal source_core.dig("primary_image", "sha256"), first_core.fetch("sha256")
    assert_nil first_core.fetch("packet_id")
    assert_equal "source_01_direction", first_core.dig("source_pixel_review", "source_artifact_role")
    assert_equal source_core.fetch("active_storyline_version_id"), first_core.fetch("active_storyline_version_id")
    assert_equal source_core.fetch("screen_progression_node_id"), first_core.fetch("screen_progression_node_id")
    assert_equal source_core.fetch("sequence_phase_bindings"), first_core.fetch("sequence_phase_binding_ids")

    first_branch = rows.fetch(1)
    source_branch_review = fixture.source_fixture.review.fetch("branch_cut_reviews").first
    assert_equal source_branch_review.fetch("image_path"), first_branch.fetch("path")
    assert_equal source_branch_review.fetch("image_sha256"), first_branch.fetch("sha256")
    assert_equal source_branch_review.fetch("packet_id"), first_branch.fetch("packet_id")
    assert_equal source_branch_review.fetch("observable_pixel_truth"), first_branch.fetch("observable_pixel_truth")
    assert_equal "source_generated_branch_cut_review", first_branch.dig("source_pixel_review", "source_artifact_role")
    assert_equal "passed_production_cut", first_branch.fetch("pixel_review_status")
  end

  def test_validator_rejects_02b_to_03v_cohort_drift
    fixture = build_fixture
    fixture.review.fetch("production_cut_reviews").first["section_cohort_id"] = "C2"
    fixture.rewrite_review

    result = run_validator(fixture.review_path)

    refute result.fetch(:status).success?
    assert_includes errors(result), "C01 Production Cut review differs from its exact 01/02A/Branch-review projection"
  end

  def test_validator_rejects_storyline_or_screen_lineage_drift_in_a_core_row
    fixture = build_fixture
    fixture.review.fetch("production_cut_reviews").first["active_storyline_version_id"] = "STORY_DRIFT"
    fixture.rewrite_review

    result = run_validator(fixture.review_path)

    refute result.fetch(:status).success?
    assert_includes errors(result), "C01 Production Cut review differs from its exact 01/02A/Branch-review projection"
  end

  def test_validator_rejects_a_branch_review_change_not_reprojected_into_the_typed_row
    fixture = build_fixture
    source = fixture.source_fixture
    source.review.fetch("branch_cut_reviews").first["observable_pixel_truth"] =
      "A revised explicit pixel observation remains bound to the same passed image."
    source.rewrite_review(refresh_placement_hash: false)
    fixture.review["source_generated_branch_cut_review"] = fixture.artifact_ref(source.review_path)
    fixture.rewrite_review

    result = run_validator(fixture.review_path)

    refute result.fetch(:status).success?
    assert_includes errors(result), "BC01_ACTION Production Cut review differs from its exact 01/02A/Branch-review projection"
  end

  def test_producer_does_not_overwrite_canonical_review_when_branch_source_is_not_passed
    fixture = build_fixture
    before = Digest::SHA256.file(fixture.review_path).hexdigest
    source = fixture.source_fixture
    source.review["status"] = "hold"
    source.review.fetch("section_reviews").each { |row| row["decision"] = "hold" }
    source.review.fetch("branch_cut_reviews").each { |row| row["decision"] = "hold" }
    source.review.dig("automation_boundaries")["audio_branch_cut_placement_may_start_after_pass"] = false
    source.rewrite_review(refresh_placement_hash: false)

    result = fixture.run_producer(write: true)

    refute result.fetch(:status).success?
    assert_includes producer_errors(result), "source generated Branch-Cut review must be active passed v4"
    assert_equal before, Digest::SHA256.file(fixture.review_path).hexdigest
  end

  def test_producer_does_not_overwrite_canonical_review_after_official_core_pixel_bytes_change
    fixture = build_fixture
    before = Digest::SHA256.file(fixture.review_path).hexdigest
    storyboard = fixture.source_fixture.image_fixture.mv.storyboard
    core_image = ROOT.join(storyboard.dig("master_storyboard", 0, "imported_core", "primary_image", "actual_path"))
    core_image.binwrite("changed Official Core fixture pixels\n")

    result = fixture.run_producer(write: true)

    refute result.fetch(:status).success?
    assert_includes producer_errors(result), "C01 primary image SHA-256 is stale"
    assert_equal before, Digest::SHA256.file(fixture.review_path).hexdigest
  end

  private

  def build_fixture
    @fixture = ActiveProductionCutReviewFixture.create
  end

  def run_validator(path)
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      VALIDATOR.to_s,
      "--root",
      ROOT.to_s,
      "--json",
      path.to_s,
      chdir: ROOT.to_s
    )
    {stdout: stdout, stderr: stderr, status: status}
  end

  def errors(result)
    payload = JSON.parse(result.fetch(:stdout))
    ([result.fetch(:stderr)] + payload.fetch("errors")).reject(&:empty?).join("\n")
  end

  def producer_errors(result)
    payload = JSON.parse(result.fetch(:stdout))
    ([result.fetch(:stderr)] + payload.fetch("errors")).reject(&:empty?).join("\n")
  end
end
