# frozen_string_literal: true

require "json"
require "minitest/autorun"
require "open3"
require "pathname"
require "yaml"
require_relative "support/active_mv_fixture"

class Idol01rReferenceGapWorklistTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  SCRIPT = ROOT.join("scripts/idol_01r_reference_gap_worklist.rb")

  def setup
    @fixture = ActiveMvFixture.create
  end

  def teardown
    @fixture.cleanup
  end

  def test_v17_named_binding_gap_opens_and_closes_deterministically
    document = YAML.safe_load(@fixture.front_path.read, aliases: true)
    ref_03 = document.dig("reference_connection_research", "reference_units").find do |row|
      row["reference_unit_id"] == "REF-03"
    end
    ref_03["target_section_ids"] = ["S02"]
    @fixture.front_path.write(YAML.dump(document))

    result = run_builder
    assert_equal "open_named_gaps", result.fetch("status")
    assert_equal 1, result.dig("summary", "open_sections")
    output = @fixture.run_dir.join("work/front_planning_integration/reference-comparison-worklist.yaml")
    worklist = YAML.safe_load(output.read, aliases: true)
    assert_equal "idol_01r_reference_gap_worklist.v6", worklist.fetch("schema_version")
    assert_includes worklist.dig("work_items", 0, "missing_requirements"), "assigned_reference_unit_not_targeted_to_section"
    assert_equal false, worklist.dig("automation_boundaries", "creative_adequacy_claimed")

    ref_03["target_section_ids"] = ["S01"]
    @fixture.front_path.write(YAML.dump(document))
    result = run_builder
    assert_equal "decision_ready_evidence_observable_pass", result.fetch("status")
    assert_equal 0, result.dig("summary", "open_sections")
    worklist = YAML.safe_load(output.read, aliases: true)
    assert_empty worklist.fetch("work_items")
    assert_equal "decision_ready_evidence_observable_pass", worklist.dig("section_checks", 0, "floor_status")
  end

  def test_sequence_unit_id_must_resolve_to_one_selected_exact_five_one_second_unit
    document = YAML.safe_load(@fixture.front_path.read, aliases: true)
    document.dig("section_plan", 0)["sequence_unit_ids"] = ["SEQU_UNKNOWN"]
    @fixture.front_path.write(YAML.dump(document))

    result = run_builder
    assert_equal "open_named_gaps", result.fetch("status")
    output = @fixture.run_dir.join("work/front_planning_integration/reference-comparison-worklist.yaml")
    worklist = YAML.safe_load(output.read, aliases: true)
    check = worklist.fetch("section_checks").first
    assert_equal 0, check.fetch("selected_sequence_unit_count")
    assert_includes check.fetch("missing_requirements"), "minimum_one_selected_exact_five_one_second_sequence_unit"
  end

  private

  def run_builder
    stdout, stderr, status = Open3.capture3(
      "ruby",
      SCRIPT.to_s,
      "--repo-root", ROOT.to_s,
      "--front-planning", @fixture.front_path.to_s,
      "--write",
      chdir: ROOT.to_s
    )
    assert status.success?, [stderr, stdout].join("\n")
    JSON.parse(stdout)
  end
end
