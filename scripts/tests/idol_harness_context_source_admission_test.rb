# frozen_string_literal: true

require "json"
require "digest"
require "minitest/autorun"
require "open3"
require "pathname"
require "rbconfig"
require "yaml"
require_relative "support/active_mv_fixture"

class IdolHarnessContextSourceAdmissionTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  BUILDER = ROOT.join("scripts", "idol_harness_context_pack.rb")
  VALIDATOR = ROOT.join("scripts", "validate_harness_context_pack.rb")

  def setup
    @fixture = ActiveMvFixture.create
  end

  def teardown
    @fixture.cleanup
  end

  def test_member_branch_pack_contains_exact_branch_siblings_and_core_neighbors
    output = @fixture.run_dir.join("work", "context-packs", "S01", "BC01_ACTION.yaml")
    result = build_pack("C01", "BC01_ACTION", output)

    assert result[:status].success?, result[:stderr]
    summary = JSON.parse(result[:stdout])
    assert_equal "C01", summary.fetch("core_cut_id")
    assert_equal "BC01_ACTION", summary.fetch("branch_cut_id")
    assert_nil summary.fetch("previous_branch_cut_id")
    assert_equal "BC01_OVERHEAD", summary.fetch("next_branch_cut_id")
    assert_nil summary.fetch("previous_core_cut_id")
    assert_equal "C02", summary.fetch("next_core_cut_id")
    assert_equal 2, summary.fetch("visual_binding_count")

    pack = YAML.safe_load(output.read, aliases: true)
    assert_equal "idol-harness-context-pack.v7", pack.fetch("schema_version")
    assert_equal @fixture.storyboard.dig("storyline_lineage_projection", "projected_value"),
                 pack.dig("storyline_lineage_projection", "projected_value")
    assert_equal "storyline_lineage_projection", pack.fetch("read_order").first
    source_front = YAML.safe_load(@fixture.front_path.read, aliases: true)
    assert_equal source_front.fetch("screen_progression_map"),
                 pack.dig("screen_progression_projection", "projected_value")
    assert_equal "worker_high", pack.dig("provider_profile_snapshot", "logical_profile_alias")
    assert_equal "forbidden", pack.dig("provider_profile_snapshot", "fallback_policy")
    assert_equal ["S01"], pack.dig("task", "active_section_ids")
    assert_nil pack.dig("active_unit", "previous_branch_cut")
    assert_equal "BC01_OVERHEAD", pack.dig("active_unit", "next_branch_cut", "branch_cut_id")
    assert_equal "C02", pack.dig("active_unit", "next_core_cut", "core_cut_id")
    assert_nil pack.dig("active_unit", "cross_section_boundary_detail")
    assert_equal %w[member_visual scene_visual],
                 pack.dig("active_unit", "current_branch_visual_bindings").map { |row| row.fetch("reference_scope") }
    assert_equal [@fixture.album_key, @fixture.title_key],
                 [
                   pack.dig("active_unit", "current_title_package", "album_key"),
                   pack.dig("active_unit", "current_title_package", "title_key")
                 ]
    assert_equal ["VIS-M01"], pack.dig("active_unit", "current_title_package", "member_visual_asset_ids")
    assert_equal @fixture.storyboard.fetch("target_message_summary"),
                 pack.dig("planning_spine", "target_message_summary")
    assert_equal true, pack.dig("automation_boundaries", "derived_context_only")
    assert_equal false, pack.dig("automation_boundaries", "creative_truth_authored")

    validation = validate_pack(output)
    assert validation[:status].success?, validation[:stderr]
  end

  def test_object_only_branch_keeps_scene_reference_without_member_or_background_asset
    output = @fixture.run_dir.join("work", "context-packs", "S01", "BC02_HOLD.yaml")
    result = build_pack("C02", "BC02_HOLD", output)

    assert result[:status].success?, result[:stderr]
    pack = YAML.safe_load(output.read, aliases: true)
    assert_equal "C01", pack.dig("active_unit", "previous_core_cut", "core_cut_id")
    assert_nil pack.dig("active_unit", "next_core_cut")
    assert_equal @fixture.storyboard.dig("section_shards", 0, "transition_out"),
                 pack.dig("active_unit", "branch_neighborhood", "section_exit_continuity")
    assert_equal %w[scene_visual],
                 pack.dig("active_unit", "current_branch_visual_bindings").map { |row| row.fetch("reference_scope") }
    assert_empty pack.dig("active_unit", "current_title_package", "member_visual_asset_ids")
  end

  def test_grok_owner_resolves_the_registered_grok_worker_snapshot_without_fallback
    output = @fixture.run_dir.join("work", "context-packs", "S01", "BC01_ACTION-grok.yaml")
    result = build_pack("C01", "BC01_ACTION", output, owner: "grok")

    assert result[:status].success?, result[:stderr]
    pack = YAML.safe_load(output.read, aliases: true)
    assert_equal "grok", pack.dig("task", "owner")
    assert_equal "grok_worker_high", pack.dig("provider_profile_snapshot", "execution_profile_id")
    assert_match %r{\Aautomation/providers/grok-build-profiles\.yaml#profiles/grok_worker_high#sha256=[a-f0-9]{64}\z},
                 pack.dig("provider_profile_snapshot", "resolved_profile_snapshot_ref")
    refute_includes pack.dig("provider_profile_snapshot", "resolved_profile_snapshot_ref"), ".codex/agents/"

    validation = validate_pack(output)
    assert validation[:status].success?, validation[:stderr]
  end

  def test_cursor_owner_resolves_the_registered_cursor_worker_snapshot_without_fallback
    output = @fixture.run_dir.join("work", "context-packs", "S01", "BC01_ACTION-cursor.yaml")
    result = build_pack("C01", "BC01_ACTION", output, owner: "cursor")

    assert result[:status].success?, result[:stderr]
    pack = YAML.safe_load(output.read, aliases: true)
    assert_equal "cursor", pack.dig("task", "owner")
    assert_equal "cursor_luna_max", pack.dig("provider_profile_snapshot", "execution_profile_id")
    assert_match %r{\Aautomation/providers/cursor-agent-profiles\.yaml#profiles/cursor_luna_max#sha256=[a-f0-9]{64}\z},
                 pack.dig("provider_profile_snapshot", "resolved_profile_snapshot_ref")
    refute_includes pack.dig("provider_profile_snapshot", "resolved_profile_snapshot_ref"), "grok-build-profiles"

    validation = validate_pack(output)
    assert validation[:status].success?, validation[:stderr]
  end

  def test_core_and_branch_from_another_or_unknown_section_are_not_admitted
    output = @fixture.run_dir.join("work", "context-packs", "invalid.yaml")
    result = build_pack("C01", "BC01_ACTION", output, section: "S99")

    refute result[:status].success?
    assert_includes result[:stderr], "section S99 has no 02A shard"
    refute output.exist?
  end

  def test_old_stage_alias_is_rejected
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      BUILDER.to_s,
      @fixture.run_dir.to_s,
      "--storyboard", @fixture.storyboard_path.to_s,
      "--section", "S01",
      "--core-cut-id", "C01",
      "--branch-cut-id", "BC01_ACTION",
      "--task", "Active prompt translation context.",
      "--stage-id", "storyboard",
      chdir: ROOT.to_s
    )

    refute status.success?, stdout
    assert_includes stderr, "only image_prompt_compilation is active"
  end

  def test_validator_rejects_neighbor_tampering
    output = @fixture.run_dir.join("work", "context-packs", "S01", "BC01_ACTION.yaml")
    result = build_pack("C01", "BC01_ACTION", output)
    assert result[:status].success?, result[:stderr]

    pack = YAML.safe_load(output.read, aliases: true)
    pack.dig("active_unit", "next_branch_cut")["branch_cut_id"] = "BC99"
    output.write(YAML.dump(pack))
    validation = validate_pack(output)

    refute validation[:status].success?
    assert_includes validation[:stderr], "active next Branch Cut is not the immediate sibling"
    assert_includes validation[:stderr], "handoff_digest is stale"
  end

  def test_test_fixture_is_rejected_by_source_admission_and_cannot_enter_context
    fixture_source = ROOT.join("scripts", "tests", "support", "active_mv_fixture.rb")
    admission_error = Idol02AStoryboardContract.visual_source_admission_error(
      path: fixture_source,
      root: ROOT,
      run_path: @fixture.run_dir,
      album_key: @fixture.album_key,
      title_key: @fixture.title_key,
      label: "fixture scene reference"
    )
    assert_includes admission_error,
                    "outside admitted current-run, current-title, or selected source-material roots"

    binding = @fixture.storyboard.dig(
      "master_storyboard", 0, "compile_seed", "branch_cuts", 0,
      "visual_reference_bindings", 1
    )
    binding["actual_path"] = fixture_source.relative_path_from(ROOT).to_s
    binding["sha256"] = Digest::SHA256.file(fixture_source).hexdigest
    @fixture.storyboard_path.write(YAML.dump(@fixture.storyboard))

    output = @fixture.run_dir.join("work", "context-packs", "S01", "fixture-leak.yaml")
    result = build_pack("C01", "BC01_ACTION", output)

    refute result[:status].success?
    assert_includes result[:stderr], "scene reference path differs from its 01 reference application"
    refute output.exist?
  end

  private

  def build_pack(core_cut_id, branch_cut_id, output, section: "S01", owner: "grok")
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      BUILDER.to_s,
      @fixture.run_dir.to_s,
      "--storyboard", @fixture.storyboard_path.to_s,
      "--section", section,
      "--core-cut-id", core_cut_id,
      "--branch-cut-id", branch_cut_id,
      "--task", "Translate the exact active 02A Branch Cut into the fixed 02B prompt structure.",
      "--owner", owner,
      "--output", output.to_s,
      "--write",
      chdir: ROOT.to_s
    )
    {stdout: stdout, stderr: stderr, status: status}
  end

  def validate_pack(path)
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      VALIDATOR.to_s,
      path.to_s,
      chdir: ROOT.to_s
    )
    {stdout: stdout, stderr: stderr, status: status}
  end
end
