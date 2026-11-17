# frozen_string_literal: true

require "json"
require "minitest/autorun"
require "open3"
require "pathname"
require "rbconfig"
require "tempfile"
require "yaml"

class IdolHarnessStageTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  SCRIPT = ROOT.join("scripts", "idol_harness_stage.rb")
  REGISTRY = ROOT.join("automation", "harness-stage-registry.yaml")
  EXECUTION_CONTRACT = ROOT.join("automation", "harness-execution-contract.yaml")

  EXPECTED_ACTIVE_ROUTE = %w[
    creative_route_discovery
    song_direction_design
    candidate_track_analysis
    audio_screen_motion_map
    song_production_lock
    front_planning_integration
    mv_performance_direction
    mv_storyboard_direction
    storyboard_review
    image_prompt_compilation
    image_generation_release_gate
    branch_cut_generation
    generated_branch_cut_review
    audio_branch_cut_placement
    video_motion_direction
    video_playback_review
    edit_assembly_playback_qc
    edit_finishing_fx
    master_package_release
  ].freeze

  def setup
    @registry = YAML.safe_load(REGISTRY.read, aliases: false)
    @execution_contract = YAML.safe_load(EXECUTION_CONTRACT.read, aliases: false)
  end

  def test_registry_validates_as_active_v8_without_compatibility
    result = run_script("validate")

    assert result[:status].success?, result[:stderr]
    assert_includes result[:stdout], "5 phases, 19 stages"
    assert_equal "none", @registry.dig("migration_policy", "compatibility_branch")
    assert_equal %w[00 01A 02], @registry.dig("migration_policy", "retired_active_stage_labels")
    assert_equal EXPECTED_ACTIVE_ROUTE, ordered_stage_ids
  end

  def test_registry_projects_provider_resolved_native_studio_execution
    execution = @registry.fetch("studio_execution")

    assert_equal "automation/harness-execution-contract.yaml", execution.fetch("execution_contract_path")
    assert_equal "schemas/department-dispatch.schema.json", execution.fetch("department_dispatch_schema")
    assert_equal "schemas/director-dispatch-index.schema.json", execution.fetch("director_dispatch_index_schema")
    assert_equal "schemas/reference-working-index.schema.json", execution.fetch("reference_working_index_schema")
    assert_equal "automation/harness-skill-load-profiles.yaml", execution.fetch("skill_load_profiles_registry")
    assert_equal "automation/harness-provider-profile-registry.yaml", execution.fetch("provider_profile_registry")
    assert_equal "overall_director", execution.fetch("startup_owner")
    assert_equal "creative_development_director", execution.fetch("startup_development_session")
    assert_equal "director_deep", execution.fetch("director_profile_alias")
    assert_equal "worker_high", execution.fetch("worker_profile_alias")
    assert_equal "exactly_one_per_open_logical_role", execution.fetch("active_director_binding_rule")
    assert_equal "provider_resolved_worker_high", execution.fetch("ordinary_department_and_section_worker")
    assert_equal "provider_native_default_without_project_numeric_or_depth_override", execution.fetch("native_subagent_policy")
    assert_equal "overall_director", execution.fetch("canonical_promotion_owner")
    assert_equal "overall_director", execution.fetch("founder_conversation_owner")
    assert_equal "pre_00_through_image_pixels_motion_storyboard_and_03v_playback", execution.fetch("cdd_review_extent")
    assert_equal "stage_04_through_05", execution.fetch("edit_director_review_extent")
    assert_equal "forbidden", execution.fetch("ordinary_terra_route")
  end

  def test_session_routes_keep_pre_and_post_02a_and_04_separate
    routes = @registry.fetch("stages").to_h { |stage| [stage.fetch("stage_id"), stage["session_route"]] }

    assert_equal "pre_02a_luna_development_block", routes.fetch("mv_performance_direction")
    assert_equal "pre_02a_luna_development_block", routes.fetch("mv_storyboard_direction")
    %w[song_direction_design candidate_track_analysis audio_screen_motion_map song_production_lock].each do |stage_id|
      assert_equal "cdd_physical_song_room", routes.fetch(stage_id), stage_id
    end
    assert_equal "cdd_review_then_overall_milestone", routes.fetch("storyboard_review")
    %w[
      image_prompt_compilation image_generation_release_gate branch_cut_generation
      generated_branch_cut_review audio_branch_cut_placement video_motion_direction
      video_playback_review
    ].each do |stage_id|
      assert_equal "post_02a_luna_image_motion_lineage", routes.fetch(stage_id), stage_id
    end
    %w[edit_assembly_playback_qc edit_finishing_fx master_package_release].each do |stage_id|
      assert_equal "edit_director_04_05", routes.fetch(stage_id), stage_id
    end
  end

  def test_phase_coverage_is_exact_and_ordered
    phase_ids = @registry.fetch("phases")
      .sort_by { |phase| phase.fetch("order") }
      .flat_map { |phase| phase.fetch("stage_ids") }

    assert_equal EXPECTED_ACTIVE_ROUTE, phase_ids
    assert_equal EXPECTED_ACTIVE_ROUTE.uniq, phase_ids
  end

  def test_execution_contract_uses_the_exact_stage_registry_route
    assert_equal EXPECTED_ACTIVE_ROUTE, @execution_contract.fetch("active_route")
    assert_equal ordered_stage_ids, @execution_contract.fetch("active_route")
  end

  def test_stage_id_code_and_name_resolve_without_historical_aliases
    @registry.fetch("stages").each do |stage|
      [stage.fetch("stage_id"), stage.fetch("code"), stage.fetch("name")].each do |token|
        result = run_script("--json", "resolve", token)
        assert result[:status].success?, "#{token}: #{result[:stderr]}"
        assert_equal stage.fetch("stage_id"), JSON.parse(result[:stdout]).fetch("stage_id"), token
      end
    end

    %w[00 01A 02].each do |retired|
      result = run_script("--json", "resolve", retired)
      refute result[:status].success?, retired
      assert_includes result[:stderr], "unknown active stage token"
    end
  end

  def test_front_planning_contains_reference_connection_substages
    stage = @registry.fetch("stages").find { |row| row.fetch("stage_id") == "front_planning_integration" }
    substages = stage.fetch("substage_ids")

    assert_includes substages, "reference_connection_01r"
    assert_includes substages, "reference_crop_lock_01r_c"
    assert_equal "PASS_HOLD_REJECT", stage.fetch("founder_gate").upcase
  end

  def test_every_active_stage_owner_resolves_to_a_real_skill
    @registry.fetch("stages").each do |stage|
      skill_path = ROOT.join("skills", stage.fetch("owner_skill"), "SKILL.md")
      assert skill_path.file?, "#{stage.fetch('stage_id')}: #{skill_path}"
    end
  end

  def test_video_motion_owns_both_storyboard_and_manifest_contracts
    stage = @registry.fetch("stages").find { |row| row.fetch("stage_id") == "video_motion_direction" }

    assert_equal [
      "schemas/video-prompt-storyboard-assist.schema.json",
      "schemas/video-prompt-manifest.schema.json"
    ], stage.fetch("output_contracts")
  end

  def test_core_and_branch_ownership_and_cumulative_gates_are_explicit
    stages = @registry.fetch("stages").to_h { |stage| [stage.fetch("stage_id"), stage] }

    assert_equal "Section Direction And Official Core Storyboard", stages.fetch("mv_performance_direction").fetch("name")
    assert_equal "Imported-Core Branch Planning", stages.fetch("mv_storyboard_direction").fetch("name")
    assert_equal "one_production_cut", stages.fetch("branch_cut_generation").fetch("scope")
    assert_equal %w[G-30 G-40 G-50 G-60], @registry.dig("review_model", "cumulative_gate_ids")
  end

  def test_validator_rejects_phase_overlap
    invalid = Marshal.load(Marshal.dump(@registry))
    invalid.fetch("phases")[1].fetch("stage_ids").unshift("creative_route_discovery")

    Tempfile.create(["idol-stage-registry-invalid", ".yaml"]) do |file|
      file.write(YAML.dump(invalid))
      file.flush
      result = run_script("--registry", file.path, "validate")

      refute result[:status].success?
      assert_includes result[:stderr], "phase stage coverage must equal"
    end
  end

  def test_validator_rejects_nonexistent_owner_skill
    invalid = Marshal.load(Marshal.dump(@registry))
    invalid.fetch("stages").first["owner_skill"] = "idol-missing-owner"

    Tempfile.create(["idol-stage-registry-missing-owner", ".yaml"]) do |file|
      file.write(YAML.dump(invalid))
      file.flush
      result = run_script("--registry", file.path, "validate")

      refute result[:status].success?
      assert_includes result[:stderr], "owner_skill does not resolve to an active skill"
    end
  end

  def test_validator_rejects_post_02a_session_route_drift
    invalid = Marshal.load(Marshal.dump(@registry))
    stage = invalid.fetch("stages").find { |row| row.fetch("stage_id") == "video_motion_direction" }
    stage["session_route"] = "pre_02a_luna_development_block"

    Tempfile.create(["idol-stage-registry-route-drift", ".yaml"]) do |file|
      file.write(YAML.dump(invalid))
      file.flush
      result = run_script("--registry", file.path, "validate")

      refute result[:status].success?
      assert_includes result[:stderr], "video_motion_direction: session_route must be post_02a_luna_image_motion_lineage"
    end
  end

  def test_graph_projects_declared_input_edges_from_live_registry_without_writing
    before = REGISTRY.binread
    result = run_script("--json", "graph")

    assert result[:status].success?, result[:stderr]
    atlas = JSON.parse(result[:stdout])
    assert_equal "idol-harness-stage-graph-atlas.v1", atlas.fetch("schema_version")
    assert_equal "read_only_projection", atlas.fetch("authority")
    assert_equal "automation/harness-stage-registry.yaml", atlas.fetch("source")
    assert_equal ordered_stage_ids, atlas.fetch("nodes").map { |node| node.fetch("stage_id") }

    live_edges = @registry.fetch("stages").flat_map do |stage|
      Array(stage["inputs"]).map do |input_id|
        { "from" => input_id.to_s, "to" => stage.fetch("stage_id").to_s, "kind" => "declared_input" }
      end
    end
    assert_equal live_edges, atlas.fetch("data_edges")
    refute_empty atlas.fetch("data_edges")

    atlas.fetch("order_adjacencies_without_declared_input").each do |edge|
      assert_equal "order_adjacent_without_declared_input", edge.fetch("kind")
      to_stage = @registry.fetch("stages").find { |stage| stage.fetch("stage_id") == edge.fetch("to") }
      refute_includes Array(to_stage["inputs"]).map(&:to_s), edge.fetch("from")
    end
    wait_policy = atlas.fetch("operational_wait_policy")
    assert_equal "automation/harness-execution-contract.yaml", wait_policy.fetch("source")
    assert_equal "read_only_projection", wait_policy.fetch("authority")
    assert_equal false, wait_policy.fetch("launch_to_fill_capacity")
    assert_equal true, wait_policy.fetch("queue_when_director_review_pending")
    assert_equal "next_consumes_pending_bytes_or_owner_path_collision", wait_policy.fetch("queue_launch_when")
    assert_equal "fresh_session_on_returned_artifacts_only", wait_policy.fetch("pixel_and_playback_review_window")
    assert_equal true, wait_policy.fetch("does_not_change_stage_spine")
    assert_equal before, REGISTRY.binread
  end

  private

  def ordered_stage_ids
    @registry.fetch("stages")
      .sort_by { |stage| stage.fetch("order") }
      .map { |stage| stage.fetch("stage_id") }
  end

  def run_script(*arguments)
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, SCRIPT.to_s, *arguments, chdir: ROOT.to_s)
    {stdout: stdout, stderr: stderr, status: status}
  end
end
