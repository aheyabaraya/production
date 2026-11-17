# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "pathname"
require "yaml"
require_relative "../lib/idol_checkpoint_closure_catalog"

class ValidateCheckpointClosureCatalogTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  VALIDATOR = ROOT.join("scripts", "validate_checkpoint_closure_catalog.rb")

  def test_catalog_schema_and_prefix_pass
    stdout, stderr, status = Open3.capture3("ruby", VALIDATOR.to_s, chdir: ROOT.to_s)
    assert status.success?, "#{stdout}\n#{stderr}"
    assert_includes stdout, "checkpoint-closure-catalog: pass"
  end

  def test_front_planning_cdd_readiness_has_fixed_recipe_ids
    ids = IdolCheckpointClosureCatalog.recipe_requirement_ids(
      ROOT,
      profile_id: "creative_development_director",
      checkpoint_id: "cdd_startup"
    )
    assert_equal [
      "OUTPUT-FP-ROUTES-ABC",
      "OUTPUT-SEQUENCE-UNIT-FIVE-FRAME",
      "POLICY-REFERENCE-DISPOSITION",
      "CONTRACT-STORYLINE-ORIGINAL-ACTIVE-HASH",
      "HOLD-CORE-BINDING-OR-FOUNDER-WAIVER",
      "OUTPUT-CAMERA-FOUR-AXIS",
      "FOUNDER-KINETIC-START",
      "HOLD-SEQUENCE-BEFORE-CORE",
      "HOLD-SAME-EVENT-ANCHOR-NOT-HYPOTHESIS-FLOOR",
      "POLICY-CORE-FROM-MAJOR-SEQUENCE",
      "POLICY-PRE00-EXPAND-PLANT-MAJOR-ADD-CORE",
      "POLICY-EXTRA-CORE-FAST-TEMPO",
      "OUTPUT-CORE-MARKS-ON-SEQUENCE-PARENT"
    ], ids
    assert_equal ids, IdolCheckpointClosureCatalog.recipe_requirement_ids(
      ROOT,
      profile_id: "creative_development_director",
      checkpoint_id: "cdd_direction_alignment"
    )
  end

  def test_01_core_checkpoint_has_recipe_ids
    ids = IdolCheckpointClosureCatalog.recipe_requirement_ids(
      ROOT,
      profile_id: "pre_02a_development_block_fp",
      checkpoint_id: "section_01_core_direction"
    )
    assert_equal [
      "OUTPUT-OFFICIAL-CORE-ONE-PRIMARY-IMAGE",
      "HOLD-CORE-GOVERNING-EVENT-NOT-SEQUENCE-PHASE",
      "POLICY-KINETIC-CARRY-01"
    ], ids
    catalog = YAML.load_file(ROOT.join("automation/harness-checkpoint-closure-catalog.yaml"))
    core_event = catalog.fetch("checkpoints").flat_map { |row| row.fetch("rows") }.find do |row|
      row["requirement_id"] == "HOLD-CORE-GOVERNING-EVENT-NOT-SEQUENCE-PHASE"
    end
    assert_includes core_event.fetch("expected"), "a new governing event is a new Major"
    refute_includes core_event.fetch("expected"), "a new Core exists only when the governing event changes"
  end

  def test_02a_branch_checkpoint_has_recipe_ids
    ids = IdolCheckpointClosureCatalog.recipe_requirement_ids(
      ROOT,
      profile_id: "pre_02a_development_block_fp",
      checkpoint_id: "section_02a_coverage"
    )
    assert_equal [
      "OUTPUT-BRANCH-IMPORTS-CORE-UNCHANGED",
      "HOLD-BRANCH-NOT-NEW-CORE",
      "POLICY-KINETIC-CARRY-02A"
    ], ids
    catalog = YAML.load_file(ROOT.join("automation/harness-checkpoint-closure-catalog.yaml"))
    branch_event = catalog.fetch("checkpoints").flat_map { |row| row.fetch("rows") }.find do |row|
      row["requirement_id"] == "HOLD-BRANCH-NOT-NEW-CORE"
    end
    assert_includes branch_event.fetch("expected"), "routes to a new Major"
    refute_includes branch_event.fetch("expected"), "routes to a new Core"
  end

  def test_song_room_checkpoint_has_no_recipe_rows
    ids = IdolCheckpointClosureCatalog.recipe_requirement_ids(
      ROOT,
      profile_id: "song_room_00a",
      checkpoint_id: "selected_audio_analysis"
    )
    assert_empty ids
  end

  def test_generic_follow_skill_detector
    assert IdolCheckpointClosureCatalog.generic_follow_skill?(
      "expected_output_target" => "follow the registered skill"
    )
    refute IdolCheckpointClosureCatalog.generic_follow_skill?(
      "expected_output_target" => "exactly the three route ids FP-A, FP-B, and FP-C"
    )
  end
end
