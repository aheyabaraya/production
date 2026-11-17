# frozen_string_literal: true

require "minitest/autorun"
require "digest"
require "json"
require "open3"
require "pathname"
require "yaml"
require_relative "support/active_mv_fixture"
require_relative "../lib/idol_kinetic_slot_sheet_contract"

class IdolFp0102AV3ContractTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  DIRECTION_VALIDATOR = ROOT.join("scripts", "validate_01_section_direction.rb")
  STORYBOARD_VALIDATOR = ROOT.join("scripts", "validate_master_storyboard.rb")

  def setup
    @fixture = ActiveMvFixture.create
  end

  def teardown
    @fixture.cleanup
  end

  def test_active_01_and_02a_v3_chain_passes
    assert_success(run_contract(DIRECTION_VALIDATOR, @fixture.direction_path))
    assert_success(run_contract(STORYBOARD_VALIDATOR, @fixture.storyboard_path))
  end

  def test_01_rejects_missing_kinetic_slot_sheet
    IdolKineticSlotSheetContract.sheet_path_for(@fixture.front_path, "MJ01").delete
    assert_failure(run_contract(DIRECTION_VALIDATOR, @fixture.direction_path), "kinetic slot sheet missing for MJ01")
  end

  def test_01_rejects_empty_density_locator_passage
    locator_path = Pathname.new(@fixture.front_path.to_s.sub(/\.ya?ml\z/, ".density-locators.yaml"))
    sheet = YAML.safe_load(locator_path.read, aliases: true)
    sheet.fetch("locators").fetch("opening")["passage_locator"] = " "
    locator_path.write(YAML.dump(sheet))
    assert_failure(run_contract(DIRECTION_VALIDATOR, @fixture.direction_path), "empty passage_locator")
  end

  def test_01_rejects_second_selected_major_without_its_slot_sheet
    front = YAML.safe_load(@fixture.front_path.read, aliases: true)
    route = front.fetch("candidate_routes").find { |row| row["candidate_id"] == "FP-A" }
    stack = route.fetch("sections").first.fetch("major_scene_stack").fetch("ordered_major_placements")
    stack << {
      "major_scene_id" => "MJ02",
      "order_within_section" => 2,
      "sequence_composition_candidate_set_id" => "SCSET_MJ01",
      "selected_sequence_composition_id" => "SCOMP_MJ01_01",
      "rhythm_and_information_job" => "Second event on the selected route.",
      "transition_edges" => ["Leave MJ01 into MJ02."]
    }
    route.fetch("sections").first.fetch("route_major_expansions") << {
      "major_scene_id" => "MJ02",
      "section_id" => "S01"
    }
    @fixture.front_path.write(YAML.dump(front))
    assert_failure(run_contract(DIRECTION_VALIDATOR, @fixture.direction_path), "kinetic slot sheet missing for MJ02")
  end

  def test_01_rejects_not_connected_bound_source
    core = YAML.safe_load(@fixture.direction_path.read, aliases: true).fetch("official_core_cuts").first
    image = ROOT.join(core.dig("primary_image", "actual_path"))
    image.delete
    assert_failure(run_contract(DIRECTION_VALIDATOR, @fixture.direction_path), "not_connected")
  end

  def test_01_rejects_stale_overall_authorship_role
    direction = YAML.safe_load(@fixture.direction_path.read, aliases: true)
    direction["director_role"] =
      "overall_mv_director_expanding_founder_passed_front_planning_through_story_staging_visual_choreography_and_still_camera_specialists"
    @fixture.direction_path.write(YAML.dump(direction))
    assert_failure(run_contract(DIRECTION_VALIDATOR, @fixture.direction_path), "director_role")
  end

  def test_02a_rejects_stale_overall_authorship_and_downstream_specialist_role
    @fixture.storyboard["creative_role_harness"] =
      "overall_director_expands_founder_locked_front_planning_through_writer_visual_choreography_image_motion_and_edit_specialists"
    @fixture.rewrite_storyboard
    assert_failure(run_contract(STORYBOARD_VALIDATOR, @fixture.storyboard_path), "creative_role_harness")
  end

  def test_connection_quality_proof_is_reachable_by_existing_fp_unit_id_chain
    front = YAML.safe_load(@fixture.front_path.read, aliases: true)
    direction = YAML.safe_load(@fixture.direction_path.read, aliases: true)
    storyboard = YAML.safe_load(@fixture.storyboard_path.read, aliases: true)
    units = front.dig("reference_connection_research", "reference_units")
    unit_index = units.index { |unit| unit["reference_unit_id"] == "REF-01" }
    unit = units.fetch(unit_index)
    unit_pointer = "/reference_connection_research/reference_units/#{unit_index}"
    unit_sha = value_sha(unit)

    assert_equal Digest::SHA256.file(@fixture.front_path).hexdigest, direction.dig("source_front_planning", "sha256")
    assert_equal Digest::SHA256.file(@fixture.front_path).hexdigest, storyboard.dig("source_front_planning", "sha256")
    application = direction.dig("section_directions", 0, "reference_applications").find do |row|
      row["reference_unit_id"] == unit["reference_unit_id"]
    end
    refute_nil application, "01 must resolve #{unit_pointer}"
    assert_equal unit["source_path"], application["source_path"]
    assert_equal unit["source_sha256"], application["source_sha256"]
    assert_equal unit_sha, value_sha(units.fetch(unit_pointer.split("/").last.to_i))

    scene_binding = storyboard.fetch("master_storyboard").flat_map do |core|
      core.dig("compile_seed", "branch_cuts").flat_map { |branch| branch["visual_reference_bindings"] }
    end.find { |row| row["reference_scope"] == "scene_visual" && row["asset_id"] == unit["reference_unit_id"] }
    refute_nil scene_binding, "02A must retain the same FP reference_unit_id through its 01-authorized binding"
    assert_equal application["source_path"], scene_binding["actual_path"]
    assert_equal application["source_sha256"], scene_binding["sha256"]
    refute_empty unit.fetch("connection_quality_proof")

    direction_result = run_contract_json(DIRECTION_VALIDATOR, @fixture.direction_path)
    storyboard_result = run_contract_json(STORYBOARD_VALIDATOR, @fixture.storyboard_path)
    [direction_result, storyboard_result].each do |result|
      receipt = result.fetch("front_planning_reference_unit_reachability").find do |row|
        row["reference_unit_id"] == unit["reference_unit_id"]
      end
      refute_nil receipt
      assert_equal unit_pointer, receipt["source_json_pointer"]
      assert_equal unit_sha, receipt["source_value_sha256"]
    end
  end

  def test_01_rejects_broad_or_unmatched_core_reference_waiver
    direction = YAML.safe_load(@fixture.direction_path.read, aliases: true)
    binding = direction.dig("official_core_cuts", 0, "core_reference_binding")
    binding.keys.each { |key| binding.delete(key) }
    binding.merge!("required" => false, "founder_reference_waiver" => {"exact_core_cut_id" => "C99", "authored_by" => "founder", "reason" => "Broad waiver."})
    @fixture.direction_path.write(YAML.dump(direction))
    assert_failure(run_contract(DIRECTION_VALIDATOR, @fixture.direction_path), "must name this exact Core")
  end

  def test_01_rejects_pre00_audience_target_lineage_drift
    direction = YAML.safe_load(@fixture.direction_path.read, aliases: true)
    direction.dig("pre00_audience_target_lineage_projection", "projected_value", "title_target_intersection", "value")["selected_target"] = "Drifted target"
    @fixture.direction_path.write(YAML.dump(direction))
    assert_failure(run_contract(DIRECTION_VALIDATOR, @fixture.direction_path), "must exact-copy PRE-00 audience profiles, X envelope, and title target intersection")
  end

  def test_02a_core_row_may_not_reauthor_imported_core_truth
    @fixture.storyboard.fetch("master_storyboard").first["cut_role"] = "02A reauthored meaning"
    @fixture.rewrite_storyboard
    assert_failure(run_contract(STORYBOARD_VALIDATOR, @fixture.storyboard_path), "Additional properties are not allowed")
  end

  def test_02a_rejects_pre00_audience_target_lineage_drift
    @fixture.storyboard.dig("pre00_audience_target_lineage_projection", "projected_value", "title_target_intersection", "value")["selected_target"] = "Drifted target"
    @fixture.rewrite_storyboard
    assert_failure(run_contract(STORYBOARD_VALIDATOR, @fixture.storyboard_path), "must exact-copy 01 PRE-00 audience profiles, X envelope, and title target intersection")
  end

  def test_g40_rejects_stale_draft_keyframe_grade_binding
    @fixture.storyboard.dig("g40_core_branch_authorization", "draft_keyframe_grade_vector")["sha256"] = "0" * 64
    @fixture.rewrite_storyboard
    assert_failure(run_contract(STORYBOARD_VALIDATOR, @fixture.storyboard_path), "Draft Keyframe contextual grade vector SHA-256 is stale")
  end

  def test_g40_invokes_draft_keyframe_grade_validator_before_pass
    grade = YAML.safe_load(@fixture.draft_keyframe_grade_path.read, aliases: true)
    grade.fetch("criteria").find { |row| row["criterion_id"] == "scene_visual_package" }["result"] = 3
    @fixture.draft_keyframe_grade_path.write(YAML.dump(grade))
    @fixture.storyboard.dig("g40_core_branch_authorization", "draft_keyframe_grade_vector")["sha256"] = Digest::SHA256.file(@fixture.draft_keyframe_grade_path).hexdigest
    @fixture.rewrite_storyboard

    result = run_contract(STORYBOARD_VALIDATOR, @fixture.storyboard_path)
    assert_failure(result, "failed active validation")
    assert_includes [result[1], result[0]].join("\n"), "scene_visual_package requires grade 4"
  end

  def test_every_branch_requires_an_exact_scene_or_sequence_reference
    branch = @fixture.storyboard.dig("master_storyboard", 0, "compile_seed", "branch_cuts", 0)
    branch["visual_reference_bindings"].reject! { |row| row["reference_scope"] == "scene_visual" }
    @fixture.rewrite_storyboard
    assert_failure(run_contract(STORYBOARD_VALIDATOR, @fixture.storyboard_path), "requires at least one exact scene or Sequence reference")
  end

  def test_meaningfully_visible_member_requires_member_binding_before_scene
    branch = @fixture.storyboard.dig("master_storyboard", 0, "compile_seed", "branch_cuts", 0)
    branch["visual_reference_bindings"].reverse!
    branch["visual_reference_bindings"].each_with_index { |row, index| row["order"] = index + 1 }
    @fixture.rewrite_storyboard
    assert_failure(run_contract(STORYBOARD_VALIDATOR, @fixture.storyboard_path), "Member Visual bindings before exact scene or Sequence bindings")
  end

  private

  def canonicalize(value)
    case value
    when Hash
      value.keys.map(&:to_s).sort.each_with_object({}) do |key, result|
        source_key = value.key?(key) ? key : value.keys.find { |candidate| candidate.to_s == key }
        result[key] = canonicalize(value[source_key])
      end
    when Array
      value.map { |item| canonicalize(item) }
    else
      value
    end
  end

  def value_sha(value)
    Digest::SHA256.hexdigest(JSON.generate(canonicalize(value)))
  end

  def run_contract(validator, path)
    Open3.capture3("ruby", validator.to_s, "--root", ROOT.to_s, path.to_s, chdir: ROOT.to_s)
  end

  def run_contract_json(validator, path)
    stdout, stderr, status = Open3.capture3(
      "ruby", validator.to_s, "--root", ROOT.to_s, "--json", path.to_s, chdir: ROOT.to_s
    )
    assert status.success?, [stderr, stdout].join("\n")
    JSON.parse(stdout)
  end

  def assert_success(result)
    stdout, stderr, status = result
    assert status.success?, [stderr, stdout].join("\n")
  end

  def assert_failure(result, fragment)
    stdout, stderr, status = result
    refute status.success?, [stderr, stdout].join("\n")
    assert_includes [stderr, stdout].join("\n"), fragment
  end
end
