# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "pathname"
require "rbconfig"
require "yaml"
require_relative "../lib/idol_02a_storyboard_contract"
require_relative "support/active_mv_fixture"

class IdolLocalRevisionPropagationTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  DIRECTION_VALIDATOR = ROOT.join("scripts", "validate_01_section_direction.rb")
  STORYBOARD_VALIDATOR = ROOT.join("scripts", "validate_master_storyboard.rb")

  def setup
    @fixture = ActiveMvFixture.create
  end

  def teardown
    @fixture.cleanup
  end

  def test_front_planning_byte_only_change_does_not_reopen_01_or_02a
    @fixture.front_path.write("# audit-only byte change\n#{@fixture.front_path.read}")

    direction_result = validate(DIRECTION_VALIDATOR, @fixture.direction_path)
    storyboard_result = validate(STORYBOARD_VALIDATOR, @fixture.storyboard_path)

    assert direction_result[:status].success?, direction_result[:stderr]
    assert storyboard_result[:status].success?, storyboard_result[:stderr]
  end

  def test_01_byte_only_change_keeps_locally_bound_02a_section_current
    @fixture.direction_path.write("# audit-only byte change\n#{@fixture.direction_path.read}")

    result = validate(STORYBOARD_VALIDATOR, @fixture.storyboard_path)

    assert result[:status].success?, result[:stderr]
  end

  def test_01_section_value_change_stales_only_its_02a_section_binding
    direction = YAML.safe_load(@fixture.direction_path.read, aliases: true)
    direction.dig("section_directions", 0)["section_story_function"] =
      "The section now performs a materially different story function."
    @fixture.direction_path.write(YAML.dump(direction))

    result = validate(STORYBOARD_VALIDATOR, @fixture.storyboard_path)

    refute result[:status].success?
    assert_includes result[:stderr], "S01 source 01 section hash is stale"
  end

  def test_front_planning_global_value_change_stales_01_projection
    front = YAML.safe_load(@fixture.front_path.read, aliases: true)
    front["target_message_lock"]["core_message"] =
      "A materially different global message must reproject downstream."
    @fixture.front_path.write(YAML.dump(front))

    result = validate(DIRECTION_VALIDATOR, @fixture.direction_path)

    refute result[:status].success?
    assert_includes result[:stderr], "target_message_projection"
  end

  def test_02a_scene_binding_cannot_reuse_authorized_id_with_different_bytes
    storyboard = YAML.safe_load(@fixture.storyboard_path.read, aliases: true)
    branch = storyboard.dig("master_storyboard", 0, "compile_seed", "branch_cuts", 0)
    member_binding = branch.fetch("visual_reference_bindings").find do |binding|
      binding["reference_scope"] == "member_visual"
    end
    scene_binding = branch.fetch("visual_reference_bindings").find do |binding|
      binding["reference_scope"] == "scene_visual"
    end
    scene_binding["actual_path"] = member_binding.fetch("actual_path")
    scene_binding["sha256"] = member_binding.fetch("sha256")
    @fixture.storyboard_path.write(YAML.dump(storyboard))

    result = validate(STORYBOARD_VALIDATOR, @fixture.storyboard_path)

    refute result[:status].success?
    assert_includes result[:stderr], "scene reference path differs from its 01 reference application"
    assert_includes result[:stderr], "scene reference SHA-256 differs from its 01 reference application"
  end

  def test_02a_core_reference_ids_must_exact_cover_branch_scene_bindings
    storyboard = YAML.safe_load(@fixture.storyboard_path.read, aliases: true)
    storyboard["reference_coverage_matrix"] = []
    @fixture.storyboard_path.write(YAML.dump(storyboard))

    result = validate(STORYBOARD_VALIDATOR, @fixture.storyboard_path)

    refute result[:status].success?
    assert_includes result[:stderr], "reference_coverage_matrix must exact-cover every Branch"
  end

  def test_02a_core_camera_roles_must_exact_cover_branch_cuts_in_order
    storyboard = YAML.safe_load(@fixture.storyboard_path.read, aliases: true)
    imported = storyboard.dig("master_storyboard", 0, "imported_core")
    imported["visible_action_or_hold"] = "A mutated 02A rewrite of the imported 01 Official Core action."
    @fixture.storyboard_path.write(YAML.dump(storyboard))

    result = validate(STORYBOARD_VALIDATOR, @fixture.storyboard_path)

    refute result[:status].success?
    assert_includes result[:stderr], "imported Core bytes differ from 01"
  end

  def test_02a_whole_film_storyline_projection_cannot_paraphrase_01
    storyboard = YAML.safe_load(@fixture.storyboard_path.read, aliases: true)
    storyboard.dig("founder_visual_alignment_projection", "projected_value", "whole_film_readout")["story_progression"] =
      "A shorter downstream paraphrase that must not replace the Founder-aligned readout."
    @fixture.storyboard_path.write(YAML.dump(storyboard))

    result = validate(STORYBOARD_VALIDATOR, @fixture.storyboard_path)

    refute result[:status].success?
    assert_includes result[:stderr], "Founder visual alignment value differs from 01"
  end

  def test_02a_branch_storyline_binding_must_keep_exact_planning_cut_value
    storyboard = YAML.safe_load(@fixture.storyboard_path.read, aliases: true)
    binding = storyboard.dig("master_storyboard", 0, "compile_seed", "branch_cuts", 0, "storyline_alignment_binding")
    binding["projected_value"]["visible_action_or_hold"] = "An unrelated replacement action."
    @fixture.storyboard_path.write(YAML.dump(storyboard))

    result = validate(STORYBOARD_VALIDATOR, @fixture.storyboard_path)

    refute result[:status].success?
    assert_includes result[:stderr], "storyline value differs from 01"
  end

  def test_02a_branch_cuts_must_cover_every_founder_aligned_planning_cut
    storyboard = YAML.safe_load(@fixture.storyboard_path.read, aliases: true)
    storyboard.fetch("master_storyboard").each do |core_cut|
      core_cut.dig("compile_seed", "branch_cuts").each do |branch_cut|
        source = storyboard.dig("section_shards", 0, "planning_cut_alignment_projections", 0)
        branch_cut["storyline_alignment_binding"] = source.merge(
          "02a_expansion_delta" => "Reuse only the first planning cut.",
          "prompt_lineage_rule" => "02B_must_read_this_exact_storyline_value_and_hash_before_authoring_the_five_prompt_items"
        )
      end
    end
    @fixture.storyboard_path.write(YAML.dump(storyboard))

    result = validate(STORYBOARD_VALIDATOR, @fixture.storyboard_path)

    refute result[:status].success?
    assert_includes result[:stderr], "Branch Cuts must exact-cover every Founder-aligned planning cut"
  end

  def test_02a_legacy_20_schema_version_is_rejected
    storyboard = YAML.safe_load(@fixture.storyboard_path.read, aliases: true)
    storyboard["schema_version"] = "2.0"
    @fixture.storyboard_path.write(YAML.dump(storyboard))

    result = validate(STORYBOARD_VALIDATOR, @fixture.storyboard_path)

    refute result[:status].success?
    assert_includes result[:stderr], "schema_version"
  end

  def test_one_section_change_leaves_another_section_lineage_current
    storyboard = two_section_storyboard
    assert_empty Idol02AStoryboardContract.section_exact_cover_errors(storyboard)

    s01 = Idol02AStoryboardContract.find_section_shard(storyboard, section_id: "S01")
    s02 = Idol02AStoryboardContract.find_section_shard(storyboard, section_id: "S02")
    s01_before = Idol02AStoryboardContract.section_review_sha256(storyboard, "S01")
    s02_before = section_lineage_snapshot(storyboard, s02)

    storyboard.dig(
      "master_storyboard", 0, "compile_seed", "branch_cuts", 0
    )["visible_action"] = "Synthetic section-one revision with a different visible state."

    refute_equal s01_before, Idol02AStoryboardContract.section_review_sha256(storyboard, "S01")
    assert_equal s02_before, section_lineage_snapshot(storyboard, s02)
    refute_equal(
      Idol02AStoryboardContract.section_review_sha256(storyboard, "S01"),
      Idol02AStoryboardContract.section_review_sha256(storyboard, "S02")
    )
    refute_nil s01
  end

  def test_expanding_one_section_changes_only_its_local_neighborhood
    storyboard = two_section_storyboard
    s01 = Idol02AStoryboardContract.find_section_shard(storyboard, section_id: "S01")
    s02 = Idol02AStoryboardContract.find_section_shard(storyboard, section_id: "S02")
    s01_cuts_before = Idol02AStoryboardContract.section_core_cuts(storyboard, s01)
    s02_before = section_lineage_snapshot(storyboard, s02)
    first_branch_before = s01_cuts_before.fetch(0).dig("compile_seed", "branch_cuts", 0)
    second_branch_before = s01_cuts_before.fetch(1).dig("compile_seed", "branch_cuts", 0)
    first_context_before = Idol02AStoryboardContract.same_section_context_sha256(
      storyboard, s01, s01_cuts_before, 0, first_branch_before, 0
    )
    second_context_before = Idol02AStoryboardContract.same_section_context_sha256(
      storyboard, s01, s01_cuts_before, 1, second_branch_before, 0
    )

    inserted = deep_copy(storyboard.fetch("master_storyboard")[1])
    inserted["core_cut_id"] = "C02A"
    inserted["source_sections"] = ["S01"]
    inserted.dig("compile_seed", "branch_cuts").each_with_index do |branch_cut, index|
      branch_cut["branch_cut_id"] = "BC02A_EXPAND_#{index + 1}"
      branch_cut["packet_id"] = "PKT_BC02_EXPAND_#{index + 1}"
    end
    storyboard.fetch("master_storyboard").insert(2, inserted)
    s01.fetch("core_cut_ids") << "C02A"

    assert_empty Idol02AStoryboardContract.section_exact_cover_errors(storyboard)
    s01_cuts_after = Idol02AStoryboardContract.section_core_cuts(storyboard, s01)
    assert_equal first_context_before, Idol02AStoryboardContract.same_section_context_sha256(
      storyboard, s01, s01_cuts_after, 0,
      s01_cuts_after.fetch(0).dig("compile_seed", "branch_cuts", 0), 0
    )
    refute_equal second_context_before, Idol02AStoryboardContract.same_section_context_sha256(
      storyboard, s01, s01_cuts_after, 1,
      s01_cuts_after.fetch(1).dig("compile_seed", "branch_cuts", 0), 0
    )
    assert_equal s02_before, section_lineage_snapshot(storyboard, s02)
  end

  private

  def validate(script, artifact)
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      script.to_s,
      "--root",
      ROOT.to_s,
      artifact.to_s,
      chdir: ROOT.to_s
    )
    {stdout: stdout, stderr: stderr, status: status}
  end

  def two_section_storyboard
    document = deep_copy(@fixture.storyboard)
    source_cuts = deep_copy(document.fetch("master_storyboard"))
    second_cuts = source_cuts.each_with_index.map do |cut, index|
      core_number = index + 3
      new_id = format("C%02d", core_number)
      cut["core_cut_id"] = new_id
      cut["source_sections"] = ["S02"] if cut.key?("source_sections")
      imported = cut["imported_core"]
      if imported.is_a?(Hash)
        imported["section_id"] = "S02"
        imported["core_cut_id"] = new_id
      end
      Array(cut.dig("compile_seed", "branch_cuts")).each_with_index do |branch_cut, branch_index|
        branch_cut["branch_cut_id"] = "BC#{format('%02d', core_number)}_S02_#{branch_index + 1}"
        branch_cut["packet_id"] = "PKT_BC#{format('%02d', core_number)}_S02_#{branch_index + 1}"
        branch_cut["section_id"] = "S02"
        branch_cut["parent_core_cut_id"] = new_id
      end
      cut
    end
    second_shard = deep_copy(document.fetch("section_shards").first)
    second_shard["shard_id"] = "SHARD_S02_ACTIVE"
    second_shard["section_ids"] = ["S02"]
    second_shard["core_cut_ids"] = second_cuts.map { |cut| cut.fetch("core_cut_id") }
    second_shard["source_01_section"] = {
      "section_id" => "S02",
      "json_pointer" => "/section_directions/1",
      "value_sha256" => "0" * 64
    }
    second_shard["path"] = @fixture.relative(
      @fixture.run_dir.join("work", "02A", "sections", "S02.yaml")
    )
    document.fetch("section_shards") << second_shard
    document.fetch("master_storyboard").concat(second_cuts)
    document
  end

  def section_lineage_snapshot(document, shard)
    core_cuts = Idol02AStoryboardContract.section_core_cuts(document, shard)
    {
      "invariants" => Idol02AStoryboardContract.section_invariant_sha256(document, shard),
      "entry" => Idol02AStoryboardContract.boundary_sha256(shard, "entry"),
      "exit" => Idol02AStoryboardContract.boundary_sha256(shard, "exit"),
      "review" => Idol02AStoryboardContract.section_review_sha256(
        document,
        Idol02AStoryboardContract.section_id_for_shard(shard)
      ),
      "contexts" => core_cuts.each_with_index.flat_map do |core_cut, core_index|
        Array(core_cut.dig("compile_seed", "branch_cuts")).each_with_index.map do |branch_cut, branch_index|
          Idol02AStoryboardContract.same_section_context_sha256(
            document, shard, core_cuts, core_index, branch_cut, branch_index
          )
        end
      end
    }
  end

  def deep_copy(value)
    Marshal.load(Marshal.dump(value))
  end
end
