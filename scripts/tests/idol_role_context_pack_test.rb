# frozen_string_literal: true

require "digest"
require "json"
require "fileutils"
require "minitest/autorun"
require "open3"
require "pathname"
require "rbconfig"
require "tempfile"
require "tmpdir"
require "yaml"

require_relative "../lib/idol_role_context_pack"

class IdolRoleContextPackTest < Minitest::Test
  REAL_ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  SCHEMA = REAL_ROOT.join("schemas", "role-context-pack.schema.json")
  VALIDATOR = REAL_ROOT.join("scripts", "validate_json_schema.py")
  PYTHON = REAL_ROOT.join("scripts", "idol-video-python")
  PROFILE_CHECKPOINTS = {
    "overall_director" => "director_startup",
    "creative_development_director" => "cdd_startup",
    "pre_song_research" => "pre00_scan"
  }.freeze

  def setup
    @root = Pathname.new(Dir.mktmpdir("idol-role-context-pack"))
    copy_profile_closure
  end

  def teardown
    FileUtils.remove_entry(@root) if @root&.exist?
  end

  def build_profile(role:, profile_id:, checkpoint_id:, stage_id:, provider: "grok", founder_epoch: "FIXTURE_EPOCH", live_run_state: nil,
                    source_envelope: nil, creative_sources: [], founder_quality_context: nil, section_ids: [],
                    requested_logical_profile_alias: nil, requested_provider_profile_id: nil,
                    requested_exact_model: nil, requested_reasoning_effort: nil,
                    requested_provider_source_sha256: nil)
    IdolRoleContextPack.build(
      root: @root,
      run_root: "runs/fixture-title/fixture-album/FIXTURE_RUN",
      assignment_id: "FIXTURE_#{profile_id}_#{checkpoint_id}",
      role: role,
      profile_id: profile_id,
      checkpoint_id: checkpoint_id,
      stage_id: stage_id,
      section_ids: section_ids,
      source_envelope: source_envelope,
      current_state: "prepared",
      scope: {"mode" => "whole_run", "stage_id" => stage_id, "section_ids" => []},
      non_scope: ["paid_generation", "external_mutation"],
      authority: {"assigned_owner" => role, "promotion_owner" => "overall_director"},
      founder_epoch: founder_epoch,
      founder_locks: [],
      creative_sources: creative_sources,
      output_contract: {"kind" => "fixture_output"},
      hold_conditions: ["missing_bound_source"],
      return_recipient: {"role" => role == "overall_director" ? "founder" : "creative_development_director"},
      provider: provider,
      runtime_surface: provider == "grok" ? "grok_cli_acp_or_tui" : "cursor_cli_local_physical_chat",
      live_run_state: live_run_state,
      founder_quality_context: founder_quality_context,
      requested_logical_profile_alias: requested_logical_profile_alias,
      requested_provider_profile_id: requested_provider_profile_id,
      requested_exact_model: requested_exact_model,
      requested_reasoning_effort: requested_reasoning_effort,
      requested_provider_source_sha256: requested_provider_source_sha256
    )
  end

  def test_projection_is_deterministic_schema_valid_and_not_authoritative
    first = build_profile(
      role: "overall_director",
      profile_id: "overall_director",
      checkpoint_id: "director_startup",
      stage_id: "startup_admission"
    )
    second = build_profile(
      role: "overall_director",
      profile_id: "overall_director",
      checkpoint_id: "director_startup",
      stage_id: "startup_admission"
    )

    assert_equal first, second
    assert_equal "pass", first.fetch("status")
    assert_equal "derived_read_only_no_creative_or_promotion_authority", first.fetch("authority")
    assert_equal first.dig("projection", "pack_digest"), second.dig("projection", "pack_digest")
    assert_equal [], IdolRoleContextPack.validate_pack(root: @root, pack: first)

    Tempfile.create(["idol-role-context-pack", ".json"]) do |file|
      file.write(JSON.pretty_generate(first))
      file.flush
      _stdout, stderr, status = Open3.capture3(PYTHON.to_s, VALIDATOR.to_s, SCHEMA.to_s, file.path, chdir: REAL_ROOT.to_s)
      assert status.success?, stderr
    end
  end

  def test_pre_activation_legacy_pack_remains_parse_compatible
    pack = build_profile(
      role: "overall_director",
      profile_id: "overall_director",
      checkpoint_id: "director_startup",
      stage_id: "startup_admission"
    )
    pack.delete("activation_binding")
    source_set = {
      "projection_registry" => {
        "path" => pack.dig("projection", "registry_path"),
        "sha256" => pack.dig("projection", "registry_sha256")
      },
      "profile_registry" => {
        "path" => pack.dig("projection", "profile_registry_path"),
        "sha256" => pack.dig("projection", "profile_registry_sha256")
      },
      "source_envelope" => pack["source_envelope"],
      "instructions" => pack.fetch("instruction_slices").map do |row|
        row.slice("binding_id", "path", "whole_file_sha256", "locator", "fragment_sha256")
      end,
      "creative_sources" => pack["creative_source_pointers"],
      "founder_quality_context" => pack["founder_quality_context"],
      "provider" => pack.fetch("provider_binding").slice("provider", "provider_profile_id", "provider_source_sha256")
    }
    pack["projection"]["source_set_sha256"] = IdolRoleContextPack.structured_sha256(source_set)
    pack["projection"]["pack_digest"] = IdolRoleContextPack.structured_sha256(
      pack.reject { |key, _| key == "projection" }.merge(
        "projection" => pack.fetch("projection").reject { |key, _| key == "pack_digest" }
      )
    )

    assert_equal [], IdolRoleContextPack.validate_pack(root: @root, pack: pack)
    refute_includes IdolRoleContextPack.render_runtime_json(pack), "activation_binding"
  end

  def test_representative_od_cdd_and_worker_instruction_loads_drop_by_half
    cases = [
      ["overall_director", "overall_director", "director_startup", "startup_admission"],
      ["creative_development_director", "creative_development_director", "cdd_startup", "startup_admission"],
      ["department_worker", "pre_song_research", "pre00_scan", "creative_route_discovery"]
    ]

    cases.each do |role, profile_id, checkpoint_id, stage_id|
      pack = build_profile(role: role, profile_id: profile_id, checkpoint_id: checkpoint_id, stage_id: stage_id)
      # CDD Sequence-parent heading plus restored Active Output sits just under
      # the old 0.50 representative floor.
      floor = profile_id == "creative_development_director" ? 0.48 : 0.49
      assert_operator pack.dig("projection", "reduction_ratio"), :>=, floor, "#{profile_id}.#{checkpoint_id}"
      assert_operator pack.dig("projection", "projected_word_count"), :<, pack.dig("projection", "original_word_count")
    end
  end

  def test_grok_and_cursor_resolve_exact_separate_provider_snapshots
    grok = build_profile(
      role: "overall_director",
      profile_id: "overall_director",
      checkpoint_id: "director_startup",
      stage_id: "startup_admission",
      provider: "grok"
    )
    cursor = build_profile(
      role: "overall_director",
      profile_id: "overall_director",
      checkpoint_id: "director_startup",
      stage_id: "startup_admission",
      provider: "cursor"
    )

    assert_equal "grok-4.6", grok.dig("provider_binding", "exact_model")
    assert_equal "xhigh", grok.dig("provider_binding", "reasoning_effort")
    assert_equal "gpt-5.6-sol-xhigh", cursor.dig("provider_binding", "exact_model")
    assert_equal "xhigh", cursor.dig("provider_binding", "reasoning_effort")
    refute_equal grok.dig("provider_binding", "provider_source_path"), cursor.dig("provider_binding", "provider_source_path")
    assert_equal "forbidden", grok.dig("provider_binding", "fallback_policy")
    assert_equal "forbidden", cursor.dig("provider_binding", "fallback_policy")
  end

  def test_legacy_harness_maintenance_checkpoint_stage_builds_and_rejects_creative_stage
    %w[
      wiki/harness-maintenance-rules.md
      wiki/harness-maintenance/skill-profile-routing.md
    ].each do |relative|
      destination = @root.join(relative)
      destination.dirname.mkpath
      FileUtils.cp(REAL_ROOT.join(relative), destination)
    end

    pack = build_profile(
      role: "mechanical_coordinator",
      profile_id: "harness_maintenance",
      checkpoint_id: "skill_profile_routing",
      stage_id: "skill_profile_routing"
    )
    assert_equal "pass", pack.fetch("status")
    assert_equal "harness_maintenance", pack.dig("identity", "profile_id")
    assert_equal "skill_profile_routing", pack.dig("identity", "checkpoint_id")
    assert_equal "skill_profile_routing", pack.dig("identity", "stage_id")
    assert_equal "legacy_pinned", pack.dig("activation_binding", "writer")
    assert_equal [], IdolRoleContextPack.validate_pack(root: @root, pack: pack)

    error = assert_raises(IdolRoleContextPack::ContractError) do
      build_profile(
        role: "mechanical_coordinator",
        profile_id: "harness_maintenance",
        checkpoint_id: "skill_profile_routing",
        stage_id: "front_planning_integration"
      )
    end
    assert_includes error.message, "stage is outside selected profile"
  end

  def test_unknown_provider_holds_without_fallback
    pack = build_profile(
      role: "department_worker",
      profile_id: "pre_song_research",
      checkpoint_id: "pre00_scan",
      stage_id: "creative_route_discovery",
      provider: "unknown"
    )

    assert_equal "hold", pack.fetch("status")
    assert_equal "unresolved", pack.dig("provider_binding", "provider")
    assert_includes pack.fetch("hold_reasons"), "role_context_provider_not_registered:unknown"
  end

  def test_omitted_selected_provider_does_not_copy_resolved_or_change_defaults
    grok = build_profile(
      role: "overall_director",
      profile_id: "overall_director",
      checkpoint_id: "director_startup",
      stage_id: "startup_admission",
      provider: "grok"
    )
    cursor = build_profile(
      role: "overall_director",
      profile_id: "overall_director",
      checkpoint_id: "director_startup",
      stage_id: "startup_admission",
      provider: "cursor"
    )
    assert_equal "pass", grok.fetch("status")
    assert_equal "pass", cursor.fetch("status")
    assert_equal "grok-4.6", grok.dig("provider_binding", "exact_model")
    assert_equal "xhigh", grok.dig("provider_binding", "reasoning_effort")
    assert_equal "director_deep", cursor.dig("provider_binding", "logical_profile_alias")
    assert_equal "cursor_sol_xhigh", cursor.dig("provider_binding", "provider_profile_id")
    assert_equal "gpt-5.6-sol-xhigh", cursor.dig("provider_binding", "exact_model")
    refute grok.fetch("provider_binding").key?("requested_provider_attestation")
    refute cursor.fetch("provider_binding").key?("requested_provider_attestation")
    refute_equal "cursor-grok-4.6-xhigh", cursor.dig("provider_binding", "exact_model")
    assert_equal [], IdolRoleContextPack.validate_pack(root: @root, pack: grok)
    assert_equal [], IdolRoleContextPack.validate_pack(root: @root, pack: cursor)
    assert_pack_schema_valid(grok)
    assert_pack_schema_valid(cursor)
  end

  def test_cursor_harness_maintenance_omitted_selection_stays_luna_not_cursor_grok
    copy_harness_maintenance_wiki
    pack = build_profile(
      role: "mechanical_coordinator",
      profile_id: "harness_maintenance",
      checkpoint_id: "skill_profile_routing",
      stage_id: "skill_profile_routing",
      provider: "cursor"
    )
    assert_equal "pass", pack.fetch("status")
    assert_equal "mechanical_coordinator", pack.dig("identity", "role")
    assert_equal "worker_high", pack.dig("provider_binding", "logical_profile_alias")
    assert_equal "cursor_luna_max", pack.dig("provider_binding", "provider_profile_id")
    assert_equal "gpt-5.6-luna-max", pack.dig("provider_binding", "exact_model")
    refute pack.fetch("provider_binding").key?("requested_provider_attestation")
    refute_equal "cursor_grok_46_xhigh", pack.dig("provider_binding", "provider_profile_id")
    assert_equal [], IdolRoleContextPack.validate_pack(root: @root, pack: pack)
    assert_pack_schema_valid(pack)
  end

  def test_explicit_matching_luna_worker_high_attestation_passes
    copy_harness_maintenance_wiki
    pack = build_profile(
      role: "mechanical_coordinator",
      profile_id: "harness_maintenance",
      checkpoint_id: "skill_profile_routing",
      stage_id: "skill_profile_routing",
      provider: "cursor",
      requested_logical_profile_alias: "worker_high",
      requested_provider_profile_id: "cursor_luna_max",
      requested_exact_model: "gpt-5.6-luna-max",
      requested_reasoning_effort: "max",
      requested_provider_source_sha256: cursor_source_sha256
    )
    assert_equal "pass", pack.fetch("status")
    assert_equal "worker_high", pack.dig("provider_binding", "logical_profile_alias")
    assert_equal "cursor_luna_max", pack.dig("provider_binding", "requested_provider_attestation", "provider_profile_id")
    assert_equal "gpt-5.6-luna-max", pack.dig("provider_binding", "requested_provider_attestation", "exact_model")
    assert_equal cursor_source_sha256, pack.dig("provider_binding", "requested_provider_attestation", "provider_source_sha256")
    assert_equal [], pack.fetch("hold_reasons")
    assert_equal [], IdolRoleContextPack.validate_pack(root: @root, pack: pack)
    assert_pack_schema_valid(pack)
  end

  def test_explicit_cursor_grok_selected_worker_is_usable_for_mechanical_coordinator
    copy_harness_maintenance_wiki
    pack = build_profile(
      role: "mechanical_coordinator",
      profile_id: "harness_maintenance",
      checkpoint_id: "skill_profile_routing",
      stage_id: "skill_profile_routing",
      provider: "cursor",
      requested_logical_profile_alias: "cursor_grok_explicit_selected_worker",
      requested_provider_profile_id: "cursor_grok_46_xhigh",
      requested_exact_model: "cursor-grok-4.6-xhigh",
      requested_reasoning_effort: "xhigh",
      requested_provider_source_sha256: cursor_source_sha256
    )
    attestation = pack.dig("provider_binding", "requested_provider_attestation")
    assert_equal "pass", pack.fetch("status")
    assert_equal "mechanical_coordinator", pack.dig("identity", "role")
    refute_equal "overall_director", pack.dig("identity", "role")
    assert_equal "cursor_grok_explicit_selected_worker", pack.dig("provider_binding", "logical_profile_alias")
    assert_equal "cursor_grok_46_xhigh", pack.dig("provider_binding", "provider_profile_id")
    assert_equal "cursor-grok-4.6-xhigh", pack.dig("provider_binding", "exact_model")
    assert_equal "xhigh", pack.dig("provider_binding", "reasoning_effort")
    assert_equal "cursor_grok_explicit_selected_worker", attestation.fetch("logical_profile_alias")
    assert_equal "cursor_grok_46_xhigh", attestation.fetch("provider_profile_id")
    assert_equal "cursor-grok-4.6-xhigh", attestation.fetch("exact_model")
    assert_equal "xhigh", attestation.fetch("reasoning_effort")
    assert_equal cursor_source_sha256, attestation.fetch("provider_source_sha256")
    assert_equal cursor_source_sha256, pack.dig("provider_binding", "provider_source_sha256")
    assert_equal [], pack.fetch("hold_reasons")
    assert_equal [], IdolRoleContextPack.validate_pack(root: @root, pack: pack)
    assert_pack_schema_valid(pack)
  end

  def test_explicit_cursor_grok_keeps_department_worker_eligible
    pack = build_profile(
      role: "department_worker",
      profile_id: "pre_song_research",
      checkpoint_id: "pre00_scan",
      stage_id: "creative_route_discovery",
      provider: "cursor",
      requested_logical_profile_alias: "cursor_grok_explicit_selected_worker",
      requested_provider_profile_id: "cursor_grok_46_xhigh",
      requested_exact_model: "cursor-grok-4.6-xhigh",
      requested_reasoning_effort: "xhigh",
      requested_provider_source_sha256: cursor_source_sha256
    )
    assert_equal "pass", pack.fetch("status")
    assert_equal "department_worker", pack.dig("identity", "role")
    assert_equal "cursor_grok_explicit_selected_worker", pack.dig("provider_binding", "logical_profile_alias")
    assert_equal "cursor_grok_46_xhigh", pack.dig("provider_binding", "provider_profile_id")
    assert_equal [], IdolRoleContextPack.validate_pack(root: @root, pack: pack)
    assert_pack_schema_valid(pack)
  end

  def test_explicit_cursor_grok_frontier_director_does_not_impersonate_director_for_maintenance
    copy_harness_maintenance_wiki
    pack = build_profile(
      role: "mechanical_coordinator",
      profile_id: "harness_maintenance",
      checkpoint_id: "skill_profile_routing",
      stage_id: "skill_profile_routing",
      provider: "cursor",
      requested_logical_profile_alias: "frontier_director",
      requested_provider_profile_id: "cursor_grok_46_xhigh",
      requested_exact_model: "cursor-grok-4.6-xhigh",
      requested_reasoning_effort: "xhigh",
      requested_provider_source_sha256: cursor_source_sha256
    )
    assert_equal "hold", pack.fetch("status")
    assert_equal "mechanical_coordinator", pack.dig("identity", "role")
    assert_equal "worker_high", pack.dig("provider_binding", "logical_profile_alias")
    assert_equal "cursor_luna_max", pack.dig("provider_binding", "provider_profile_id")
    assert_equal "gpt-5.6-luna-max", pack.dig("provider_binding", "exact_model")
    assert_equal "frontier_director", pack.dig("provider_binding", "requested_provider_attestation", "logical_profile_alias")
    assert_equal "cursor_grok_46_xhigh", pack.dig("provider_binding", "requested_provider_attestation", "provider_profile_id")
    assert pack.fetch("hold_reasons").any? { |row| row.start_with?("role_context_selected_provider_role_unsupported:") }
    assert_equal [], IdolRoleContextPack.validate_pack(root: @root, pack: pack)
    assert_pack_schema_valid(pack)
  end

  def test_overall_director_cannot_use_explicit_selected_worker_alias
    pack = build_profile(
      role: "overall_director",
      profile_id: "overall_director",
      checkpoint_id: "director_startup",
      stage_id: "startup_admission",
      provider: "cursor",
      requested_logical_profile_alias: "cursor_grok_explicit_selected_worker",
      requested_provider_profile_id: "cursor_grok_46_xhigh",
      requested_exact_model: "cursor-grok-4.6-xhigh",
      requested_reasoning_effort: "xhigh",
      requested_provider_source_sha256: cursor_source_sha256
    )
    assert_equal "hold", pack.fetch("status")
    assert_equal "overall_director", pack.dig("identity", "role")
    assert_equal "director_deep", pack.dig("provider_binding", "logical_profile_alias")
    assert_equal "cursor_sol_xhigh", pack.dig("provider_binding", "provider_profile_id")
    assert pack.fetch("hold_reasons").any? { |row| row.start_with?("role_context_selected_provider_role_unsupported:") }
    assert_equal [], IdolRoleContextPack.validate_pack(root: @root, pack: pack)
    assert_pack_schema_valid(pack)
  end

  def test_selected_provider_model_mismatch_holds
    copy_harness_maintenance_wiki
    pack = build_profile(
      role: "mechanical_coordinator",
      profile_id: "harness_maintenance",
      checkpoint_id: "skill_profile_routing",
      stage_id: "skill_profile_routing",
      provider: "cursor",
      requested_logical_profile_alias: "cursor_grok_explicit_selected_worker",
      requested_provider_profile_id: "cursor_grok_46_xhigh",
      requested_exact_model: "gpt-5.6-luna-max",
      requested_reasoning_effort: "xhigh",
      requested_provider_source_sha256: cursor_source_sha256
    )
    attestation = pack.dig("provider_binding", "requested_provider_attestation")
    assert_equal "hold", pack.fetch("status")
    assert_equal "worker_high", pack.dig("provider_binding", "logical_profile_alias")
    assert_equal "cursor_luna_max", pack.dig("provider_binding", "provider_profile_id")
    assert_equal "gpt-5.6-luna-max", pack.dig("provider_binding", "exact_model")
    assert_equal "cursor_grok_46_xhigh", attestation.fetch("provider_profile_id")
    assert_equal "gpt-5.6-luna-max", attestation.fetch("exact_model")
    assert pack.fetch("hold_reasons").any? { |row| row.start_with?("role_context_selected_provider_mismatch:") }
    assert_equal [], IdolRoleContextPack.validate_pack(root: @root, pack: pack)
    assert_pack_schema_valid(pack)
  end

  def test_incomplete_selected_provider_attestation_holds_without_copying_resolved
    copy_harness_maintenance_wiki
    pack = build_profile(
      role: "mechanical_coordinator",
      profile_id: "harness_maintenance",
      checkpoint_id: "skill_profile_routing",
      stage_id: "skill_profile_routing",
      provider: "cursor",
      requested_provider_profile_id: "cursor_grok_46_xhigh"
    )
    attestation = pack.dig("provider_binding", "requested_provider_attestation")
    assert_equal "hold", pack.fetch("status")
    assert_equal "cursor_luna_max", pack.dig("provider_binding", "provider_profile_id")
    assert_equal "gpt-5.6-luna-max", pack.dig("provider_binding", "exact_model")
    assert_equal ({"provider_profile_id" => "cursor_grok_46_xhigh"}), attestation
    refute attestation.key?("exact_model")
    refute attestation.key?("logical_profile_alias")
    refute attestation.key?("reasoning_effort")
    refute attestation.key?("provider_source_sha256")
    assert_includes pack.fetch("hold_reasons"), "role_context_requested_provider_attestation_incomplete"
    assert_equal [], IdolRoleContextPack.validate_pack(root: @root, pack: pack)
    assert_pack_schema_valid(pack)
  end

  def test_source_hub_explicit_grok_worker_high_attestation_passes_as_department_worker
    copy_source_hub_registration_closure
    pack = build_profile(
      role: "department_worker",
      profile_id: "source_hub_registration",
      checkpoint_id: "source_registration_and_reusable_analysis",
      stage_id: "front_planning_integration",
      provider: "grok",
      requested_logical_profile_alias: "worker_high",
      requested_provider_profile_id: "grok_worker_high",
      requested_exact_model: "grok-4.6",
      requested_reasoning_effort: "xhigh",
      requested_provider_source_sha256: grok_source_sha256
    )
    attestation = pack.dig("provider_binding", "requested_provider_attestation")
    assert_equal "pass", pack.fetch("status")
    assert_equal "department_worker", pack.dig("identity", "role")
    refute_equal "worker", pack.dig("identity", "role")
    refute_equal "mechanical_coordinator", pack.dig("identity", "role")
    refute_equal "overall_director", pack.dig("identity", "role")
    assert_equal "source_hub_registration", pack.dig("identity", "profile_id")
    assert_equal "source_registration_and_reusable_analysis", pack.dig("identity", "checkpoint_id")
    assert_equal "front_planning_integration", pack.dig("identity", "stage_id")
    assert_equal "worker_high", pack.dig("provider_binding", "logical_profile_alias")
    assert_equal "grok_worker_high", pack.dig("provider_binding", "provider_profile_id")
    assert_equal "grok-4.6", pack.dig("provider_binding", "exact_model")
    assert_equal "xhigh", pack.dig("provider_binding", "reasoning_effort")
    assert_equal "worker_high", attestation.fetch("logical_profile_alias")
    assert_equal "grok_worker_high", attestation.fetch("provider_profile_id")
    assert_equal "grok-4.6", attestation.fetch("exact_model")
    assert_equal "xhigh", attestation.fetch("reasoning_effort")
    assert_equal grok_source_sha256, attestation.fetch("provider_source_sha256")
    assert_equal grok_source_sha256, pack.dig("provider_binding", "provider_source_sha256")
    refute_equal "research_medium", pack.dig("provider_binding", "logical_profile_alias")
    refute_equal "grok_worker_medium", pack.dig("provider_binding", "provider_profile_id")
    refute_equal "medium", pack.dig("provider_binding", "reasoning_effort")
    assert_equal [], pack.fetch("hold_reasons")
    assert_equal [], IdolRoleContextPack.validate_pack(root: @root, pack: pack)
    assert_pack_schema_valid(pack)
  end

  def test_source_hub_omitted_selection_stays_research_medium
    copy_source_hub_registration_closure
    pack = build_profile(
      role: "department_worker",
      profile_id: "source_hub_registration",
      checkpoint_id: "source_registration_and_reusable_analysis",
      stage_id: "front_planning_integration",
      provider: "grok"
    )
    assert_equal "pass", pack.fetch("status")
    assert_equal "department_worker", pack.dig("identity", "role")
    assert_equal "research_medium", pack.dig("provider_binding", "logical_profile_alias")
    assert_equal "grok_worker_medium", pack.dig("provider_binding", "provider_profile_id")
    assert_equal "grok-4.6", pack.dig("provider_binding", "exact_model")
    assert_equal "medium", pack.dig("provider_binding", "reasoning_effort")
    refute pack.fetch("provider_binding").key?("requested_provider_attestation")
    refute_equal "worker_high", pack.dig("provider_binding", "logical_profile_alias")
    refute_equal "grok_worker_high", pack.dig("provider_binding", "provider_profile_id")
    refute_equal "xhigh", pack.dig("provider_binding", "reasoning_effort")
    assert_equal [], pack.fetch("hold_reasons")
    assert_equal [], IdolRoleContextPack.validate_pack(root: @root, pack: pack)
    assert_pack_schema_valid(pack)
  end

  def test_source_hub_invalid_requested_model_effort_holds_without_switching_default
    copy_source_hub_registration_closure
    pack = build_profile(
      role: "department_worker",
      profile_id: "source_hub_registration",
      checkpoint_id: "source_registration_and_reusable_analysis",
      stage_id: "front_planning_integration",
      provider: "grok",
      requested_logical_profile_alias: "worker_high",
      requested_provider_profile_id: "grok_worker_high",
      requested_exact_model: "gpt-5.6-luna-max",
      requested_reasoning_effort: "high",
      requested_provider_source_sha256: grok_source_sha256
    )
    attestation = pack.dig("provider_binding", "requested_provider_attestation")
    assert_equal "hold", pack.fetch("status")
    assert_equal "department_worker", pack.dig("identity", "role")
    assert_equal "research_medium", pack.dig("provider_binding", "logical_profile_alias")
    assert_equal "grok_worker_medium", pack.dig("provider_binding", "provider_profile_id")
    assert_equal "medium", pack.dig("provider_binding", "reasoning_effort")
    assert_equal "worker_high", attestation.fetch("logical_profile_alias")
    assert_equal "grok_worker_high", attestation.fetch("provider_profile_id")
    assert_equal "gpt-5.6-luna-max", attestation.fetch("exact_model")
    assert_equal "high", attestation.fetch("reasoning_effort")
    assert pack.fetch("hold_reasons").any? { |row| row.start_with?("role_context_selected_provider_mismatch:") }
    refute pack.fetch("hold_reasons").any? { |row| row.start_with?("role_context_selected_provider_role_unsupported:") }
    assert_equal [], IdolRoleContextPack.validate_pack(root: @root, pack: pack)
    assert_pack_schema_valid(pack)
  end

  def test_source_hub_invalid_requested_source_sha_holds_without_switching_default
    copy_source_hub_registration_closure
    pack = build_profile(
      role: "department_worker",
      profile_id: "source_hub_registration",
      checkpoint_id: "source_registration_and_reusable_analysis",
      stage_id: "front_planning_integration",
      provider: "grok",
      requested_logical_profile_alias: "worker_high",
      requested_provider_profile_id: "grok_worker_high",
      requested_exact_model: "grok-4.6",
      requested_reasoning_effort: "xhigh",
      requested_provider_source_sha256: "0" * 64
    )
    assert_equal "hold", pack.fetch("status")
    assert_equal "department_worker", pack.dig("identity", "role")
    assert_equal "research_medium", pack.dig("provider_binding", "logical_profile_alias")
    assert_equal "grok_worker_medium", pack.dig("provider_binding", "provider_profile_id")
    assert_equal "medium", pack.dig("provider_binding", "reasoning_effort")
    assert_includes pack.fetch("hold_reasons"), "role_context_selected_provider_mismatch:source_sha256"
    assert_equal [], IdolRoleContextPack.validate_pack(root: @root, pack: pack)
    assert_pack_schema_valid(pack)
  end

  def test_source_hub_incomplete_attestation_holds_without_copying_resolved
    copy_source_hub_registration_closure
    pack = build_profile(
      role: "department_worker",
      profile_id: "source_hub_registration",
      checkpoint_id: "source_registration_and_reusable_analysis",
      stage_id: "front_planning_integration",
      provider: "grok",
      requested_provider_profile_id: "grok_worker_high"
    )
    attestation = pack.dig("provider_binding", "requested_provider_attestation")
    assert_equal "hold", pack.fetch("status")
    assert_equal "department_worker", pack.dig("identity", "role")
    assert_equal "research_medium", pack.dig("provider_binding", "logical_profile_alias")
    assert_equal "grok_worker_medium", pack.dig("provider_binding", "provider_profile_id")
    assert_equal "medium", pack.dig("provider_binding", "reasoning_effort")
    assert_equal ({"provider_profile_id" => "grok_worker_high"}), attestation
    refute attestation.key?("logical_profile_alias")
    refute attestation.key?("exact_model")
    refute attestation.key?("reasoning_effort")
    refute attestation.key?("provider_source_sha256")
    assert_includes pack.fetch("hold_reasons"), "role_context_requested_provider_attestation_incomplete"
    assert_equal [], IdolRoleContextPack.validate_pack(root: @root, pack: pack)
    assert_pack_schema_valid(pack)
  end

  def test_source_hub_explicit_cursor_luna_worker_high_remains_role_unsupported
    copy_source_hub_registration_closure
    pack = build_profile(
      role: "department_worker",
      profile_id: "source_hub_registration",
      checkpoint_id: "source_registration_and_reusable_analysis",
      stage_id: "front_planning_integration",
      provider: "cursor",
      requested_logical_profile_alias: "worker_high",
      requested_provider_profile_id: "cursor_luna_max",
      requested_exact_model: "gpt-5.6-luna-max",
      requested_reasoning_effort: "max",
      requested_provider_source_sha256: cursor_source_sha256
    )
    assert_equal "hold", pack.fetch("status")
    assert_equal "department_worker", pack.dig("identity", "role")
    assert_equal "research_medium", pack.dig("provider_binding", "logical_profile_alias")
    refute_equal "worker_high", pack.dig("provider_binding", "logical_profile_alias")
    refute_equal "cursor_luna_max", pack.dig("provider_binding", "provider_profile_id")
    assert_includes pack.fetch("hold_reasons"), "role_context_selected_provider_role_unsupported:department_worker:worker_high:cursor_luna_max"
    assert_equal [], IdolRoleContextPack.validate_pack(root: @root, pack: pack)
    assert_pack_schema_valid(pack)
  end

  def test_validate_pack_rejects_pass_when_requested_grok_worker_against_unapplied_luna_snapshot
    copy_harness_maintenance_wiki
    pack = build_profile(
      role: "mechanical_coordinator",
      profile_id: "harness_maintenance",
      checkpoint_id: "skill_profile_routing",
      stage_id: "skill_profile_routing",
      provider: "cursor"
    )
    pack["provider_binding"]["requested_provider_attestation"] = {
      "logical_profile_alias" => "cursor_grok_explicit_selected_worker",
      "provider_profile_id" => "cursor_grok_46_xhigh",
      "exact_model" => "cursor-grok-4.6-xhigh",
      "reasoning_effort" => "xhigh",
      "provider_source_sha256" => cursor_source_sha256
    }
    pack["status"] = "pass"
    pack["hold_reasons"] = []
    errors = IdolRoleContextPack.validate_pack(root: @root, pack: pack)
    assert_includes errors, "role context selected provider alias was not applied"
    assert_includes errors, "role context selected provider profile was not applied"
    refute_includes errors, "role context selected provider attestation holds are missing"
  end

  def test_cli_build_profile_omitted_selection_still_compiles
    request_path = @root.join("work/pack-request-omitted-selection.json")
    output_path = @root.join("work/pack-request-omitted-selection-pack.json")
    request_path.dirname.mkpath
    request_path.write(JSON.pretty_generate(
      "run_root" => "runs/fixture-title/fixture-album/FIXTURE_RUN",
      "assignment_id" => "FIXTURE_CLI_OMITTED_SELECTION",
      "role" => "overall_director",
      "profile_id" => "overall_director",
      "checkpoint_id" => "director_startup",
      "stage_id" => "startup_admission",
      "authority" => {"assigned_owner" => "overall_director", "promotion_owner" => "overall_director"},
      "output_contract" => {"kind" => "fixture_output"},
      "hold_conditions" => ["missing_bound_source"],
      "return_recipient" => {"role" => "founder"},
      "provider" => "grok",
      "runtime_surface" => "grok_cli_acp_or_tui"
    ))
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      REAL_ROOT.join("scripts/idol_role_context_pack.rb").to_s,
      "build-profile",
      "--root", @root.to_s,
      "--request", request_path.to_s,
      "--output", output_path.to_s,
      chdir: @root.to_s
    )
    assert status.success?, [stdout, stderr].join("\n")
    pack = JSON.parse(output_path.read)
    assert_equal "pass", JSON.parse(stdout).fetch("status")
    assert_equal "grok-4.6", pack.dig("provider_binding", "exact_model")
    refute pack.fetch("provider_binding").key?("requested_provider_attestation")
    assert_pack_schema_valid(pack)
  end

  def test_cli_build_profile_accepts_explicit_cursor_grok_maintenance_worker
    copy_harness_maintenance_wiki
    request_path = @root.join("work/pack-request-cursor-grok-worker.json")
    output_path = @root.join("work/pack-request-cursor-grok-worker-pack.json")
    request_path.dirname.mkpath
    request_path.write(JSON.pretty_generate(
      "run_root" => "runs/fixture-title/fixture-album/FIXTURE_RUN",
      "assignment_id" => "FIXTURE_CLI_CURSOR_GROK_WORKER",
      "role" => "mechanical_coordinator",
      "profile_id" => "harness_maintenance",
      "checkpoint_id" => "skill_profile_routing",
      "stage_id" => "skill_profile_routing",
      "authority" => {"assigned_owner" => "mechanical_coordinator", "promotion_owner" => "overall_director"},
      "output_contract" => {"kind" => "fixture_output"},
      "hold_conditions" => ["missing_bound_source"],
      "return_recipient" => {"role" => "overall_director"},
      "provider" => "cursor",
      "runtime_surface" => "cursor_cli_local_physical_chat",
      "requested_logical_profile_alias" => "cursor_grok_explicit_selected_worker",
      "requested_provider_profile_id" => "cursor_grok_46_xhigh",
      "requested_exact_model" => "cursor-grok-4.6-xhigh",
      "requested_reasoning_effort" => "xhigh",
      "requested_provider_source_sha256" => cursor_source_sha256
    ))
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      REAL_ROOT.join("scripts/idol_role_context_pack.rb").to_s,
      "build-profile",
      "--root", @root.to_s,
      "--request", request_path.to_s,
      "--output", output_path.to_s,
      chdir: @root.to_s
    )
    assert status.success?, [stdout, stderr].join("\n")
    pack = JSON.parse(output_path.read)
    assert_equal "pass", JSON.parse(stdout).fetch("status")
    assert_equal "cursor_grok_46_xhigh", pack.dig("provider_binding", "provider_profile_id")
    assert_equal "cursor-grok-4.6-xhigh", pack.dig("provider_binding", "exact_model")
    assert_equal "mechanical_coordinator", pack.dig("identity", "role")
    assert_pack_schema_valid(pack)
  end

  def test_structured_contracts_are_pointer_only_and_markdown_fragments_are_exact
    pack = build_profile(
      role: "overall_director",
      profile_id: "overall_director",
      checkpoint_id: "director_startup",
      stage_id: "startup_admission"
    )
    schema_row = pack.fetch("instruction_slices").find { |row| row["path"] == "schemas/department-dispatch.schema.json" }
    routing_row = pack.fetch("instruction_slices").find do |row|
      row["path"] == "policies/harness-routing-and-sources.md" && row.dig("locator", "heading") == "Role Assignment Binding And Adapter Evidence"
    end

    assert_equal "pointer_with_structural_preflight", schema_row.fetch("runtime_read_mode")
    assert_nil schema_row.fetch("content")
    assert_equal "inline_exact_fragment", routing_row.fetch("runtime_read_mode")
    assert_equal Digest::SHA256.hexdigest(routing_row.fetch("content")), routing_row.fetch("fragment_sha256")
    assert routing_row.fetch("content").start_with?("### Role Assignment Binding And Adapter Evidence\n")
  end

  def test_front_planning_and_pre00_restore_required_headings
    cdd = build_profile(
      role: "creative_development_director",
      profile_id: "creative_development_director",
      checkpoint_id: "cdd_startup",
      stage_id: "startup_admission"
    )
    pre00 = build_profile(
      role: "department_worker",
      profile_id: "pre_song_research",
      checkpoint_id: "pre00_scan",
      stage_id: "creative_route_discovery"
    )
    active_output = cdd.fetch("instruction_slices").find do |row|
      row["path"] == "skills/idol-front-planning-director/SKILL.md" && row.dig("locator", "heading") == "Active Output"
    end
    story_spine = pre00.fetch("instruction_slices").find do |row|
      row["path"] == "skills/idol-research-radar/SKILL.md" && row.dig("locator", "heading") == "Mandatory PRE-00 Story Spine"
    end
    refute_nil active_output, "CDD pack must restore Active Output"
    refute_nil story_spine, "PRE-00 pack must restore Mandatory PRE-00 Story Spine"
    assert active_output.fetch("content").include?("FP-A")
    assert active_output.fetch("content").include?("idol_sequence_motion_analysis.v1")
    refute active_output.fetch("content").include?("Do not count seconds"), "Sequence Parent must not slice Active Output"
    skill_parent = cdd.fetch("instruction_slices").find do |row|
      row["path"] == "skills/idol-front-planning-director/SKILL.md" &&
        row.dig("locator", "heading") == "Sequence Parent, Majors, And Cores"
    end
    refute_nil skill_parent, "CDD pack must carry Sequence Parent, Majors, And Cores"
    assert skill_parent.fetch("content").include?("Sequence is the parent")
    assert skill_parent.fetch("content").include?("Do not count seconds")
    sequence_parent = cdd.fetch("instruction_slices").find do |row|
      row["path"] == "policies/section-production-front-planning.md"
    end
    refute_nil sequence_parent, "CDD pack must carry Front Planning policy"
    assert sequence_parent.fetch("content").include?("Sequence Parent And Core Marks")
    assert sequence_parent.fetch("content").include?("Existing-Flow Compatibility")
  end

  def test_markdown_locator_is_fail_closed_for_missing_or_ambiguous_heading
    missing = assert_raises(IdolRoleContextPack::ContractError) do
      IdolRoleContextPack.markdown_heading("# One\n", "Missing", "fixture.md")
    end
    assert_match(/missing/, missing.message)

    ambiguous = assert_raises(IdolRoleContextPack::ContractError) do
      IdolRoleContextPack.markdown_heading("## Same\na\n## Same\nb\n", "Same", "fixture.md")
    end
    assert_match(/ambiguous/, ambiguous.message)
  end

  def test_runtime_render_is_one_derived_pack_not_a_second_authority
    pack = build_profile(
      role: "overall_director",
      profile_id: "overall_director",
      checkpoint_id: "director_startup",
      stage_id: "startup_admission"
    )
    rendered = IdolRoleContextPack.render_runtime_json(pack)

    assert rendered.start_with?("ROLE_CONTEXT_PACK_V1 ")
    assert_includes rendered, "runtime_pack_replaces_broad_instruction_reads_and_is_not_an_additional_required_layer"
    assert_includes rendered, '"authority":"derived_read_only_no_creative_or_promotion_authority"'
    assert_includes rendered, '"source_envelope":'
    assert_includes rendered, '"dependency_edges":'
    refute_includes rendered, '"authority":"creative_authority"'
    refute_includes rendered, '"authority":"promotion_authority"'
  end

  def test_graph_invalidation_is_dependency_scoped_and_authority_sensitive
    baseline = build_profile(
      role: "overall_director",
      profile_id: "overall_director",
      checkpoint_id: "director_startup",
      stage_id: "startup_admission"
    )
    @root.join("unbound-diagnostic.txt").write("not a graph dependency\n")
    unchanged = build_profile(
      role: "overall_director",
      profile_id: "overall_director",
      checkpoint_id: "director_startup",
      stage_id: "startup_admission"
    )
    authority_changed = build_profile(
      role: "overall_director",
      profile_id: "overall_director",
      checkpoint_id: "director_startup",
      stage_id: "startup_admission",
      founder_epoch: "FIXTURE_EPOCH_2"
    )

    assert_equal baseline, unchanged
    assert_equal baseline.dig("projection", "instruction_content_sha256"), authority_changed.dig("projection", "instruction_content_sha256")
    refute_equal baseline.dig("projection", "pack_digest"), authority_changed.dig("projection", "pack_digest")

    bound = baseline.fetch("instruction_slices").find { |row| row.fetch("content") }
    @root.join(bound.fetch("path")).open("a") { |file| file.write("\nchanged bound bytes\n") }
    errors = IdolRoleContextPack.validate_pack(root: @root, pack: baseline)
    assert errors.any? { |error| error.include?("whole-file SHA-256 is stale") }
  end

  def test_source_envelope_and_creative_sources_invalidate_on_current_byte_change
    envelope_path = @root.join("runs/fixture-title/fixture-album/FIXTURE_RUN/run-manifest.yaml")
    envelope_path.dirname.mkpath
    envelope_path.write("schema_version: fixture-run-manifest.v1\n")
    creative_path = @root.join("runs/fixture-title/fixture-album/FIXTURE_RUN/front-planning.md")
    creative_path.write("# Current Front Planning\n")
    pack = build_profile(
      role: "overall_director",
      profile_id: "overall_director",
      checkpoint_id: "director_startup",
      stage_id: "startup_admission",
      source_envelope: {
        "kind" => "startup_admission",
        "path" => envelope_path.relative_path_from(@root).to_s,
        "sha256" => Digest::SHA256.file(envelope_path).hexdigest
      },
      creative_sources: [{
        "source_id" => "front_planning",
        "path" => creative_path.relative_path_from(@root).to_s,
        "sha256" => Digest::SHA256.file(creative_path).hexdigest,
        "purpose" => "Current creative source."
      }]
    )

    assert_equal [], IdolRoleContextPack.validate_pack(root: @root, pack: pack)
    envelope_path.write("schema_version: changed-run-manifest.v1\n")
    creative_path.write("# Changed Front Planning\n")
    errors = IdolRoleContextPack.validate_pack(root: @root, pack: pack)
    assert_includes errors, "role context source envelope SHA-256 is stale"
    assert_includes errors, "creative_source_pointers[0] SHA-256 is stale"
  end

  def test_pack_projects_model_facing_creative_sources_without_hex
    creative_path = @root.join("runs/fixture-title/fixture-album/FIXTURE_RUN/front-planning.md")
    creative_path.dirname.mkpath
    creative_path.write("# Current Front Planning\n")
    relative = creative_path.relative_path_from(@root).to_s
    sha = Digest::SHA256.file(creative_path).hexdigest
    pack = build_profile(
      role: "overall_director",
      profile_id: "overall_director",
      checkpoint_id: "director_startup",
      stage_id: "startup_admission",
      creative_sources: [{
        "source_id" => "front_planning",
        "path" => relative,
        "sha256" => sha,
        "purpose" => "Current creative source.",
        "locator" => "whole_file",
        "function" => "visible_action_or_hold",
        "disposition" => "applied"
      }]
    )

    envelope = pack.fetch("creative_source_pointers").first
    facing = pack.dig("projection", "model_facing_creative_sources").first
    assert_equal sha, envelope.fetch("sha256")
    refute facing.key?("sha256")
    refute facing.keys.any? { |key| key.to_s.include?("sha256") }
    assert_equal "connected", facing.dig("connection", "status")
    assert_equal "front_planning", facing.fetch("source_id")
    assert_equal relative, facing.fetch("path")
    assert_equal "visible_action_or_hold", facing.fetch("function")
    assert_equal "applied", facing.fetch("disposition")
    assert_equal "whole_file", facing.fetch("locator")
    assert_equal [], IdolRoleContextPack.validate_pack(root: @root, pack: pack)

    runtime = JSON.parse(IdolRoleContextPack.render_runtime_json(pack).sub(/\AROLE_CONTEXT_PACK_V1 /, ""))
    runtime_source = runtime.fetch("creative_source_pointers").first
    refute runtime_source.key?("sha256")
    assert_equal "connected", runtime_source.dig("connection", "status")
    assert_equal sha, pack.fetch("creative_source_pointers").first.fetch("sha256")

    drifted = Marshal.load(Marshal.dump(pack))
    drifted["projection"]["model_facing_creative_sources"].first["path"] = "runs/other.md"
    assert_includes(
      IdolRoleContextPack.validate_pack(root: @root, pack: drifted),
      "projection.model_facing_creative_sources drifted from envelope creative_source_pointers"
    )

    leaked = Marshal.load(Marshal.dump(pack))
    leaked["projection"]["model_facing_creative_sources"].first["sha256"] = sha
    errors = IdolRoleContextPack.validate_pack(root: @root, pack: leaked)
    assert errors.any? { |error| error.include?("leaked sha256") || error.include?("drifted") }
  end

  def test_connection_contract_stamps_then_pack_projects_the_sealed_pointer
    creative_path = @root.join("runs/fixture-title/fixture-album/FIXTURE_RUN/front-planning.md")
    creative_path.dirname.mkpath
    creative_path.write("# Current Front Planning\n")
    relative = creative_path.relative_path_from(@root).to_s
    unstamped = {
      "source_id" => "front_planning",
      "path" => relative,
      "locator" => "whole_file",
      "function" => "visible_action_or_hold",
      "disposition" => "applied"
    }
    projected = IdolSourceConnectionContract.project_rows(@root, [unstamped]).first
    assert_equal "not_connected", projected.dig("connection", "status")
    assert_equal "unstamped", projected.dig("connection", "reason")
    refute projected.key?("sha256")

    missing = IdolSourceConnectionContract.stamp(@root, unstamped.merge("path" => "runs/missing.md"))
    refute missing["stamped"]
    assert_equal "not_connected", missing.dig("connection", "status")
    assert_equal "missing_file", missing.dig("connection", "reason")

    stale = IdolSourceConnectionContract.connection_of(@root, unstamped.merge("sha256" => "a" * 64))
    assert_equal "not_connected", stale["status"]
    assert_equal "stale_sha256", stale["reason"]
    sealed = IdolSourceConnectionContract.stamp(@root, unstamped.merge("sha256" => "a" * 64))
    assert_equal "connected", sealed.dig("connection", "status")
    assert_equal Digest::SHA256.file(creative_path).hexdigest, sealed.dig("row", "sha256")
    assert_equal "visible_action_or_hold", sealed.dig("row", "function")

    pack = build_profile(
      role: "overall_director",
      profile_id: "overall_director",
      checkpoint_id: "director_startup",
      stage_id: "startup_admission",
      creative_sources: [sealed.fetch("row")]
    )
    facing = pack.dig("projection", "model_facing_creative_sources").first
    refute facing.key?("sha256")
    assert_equal "connected", facing.dig("connection", "status")
  end

  def test_registry_provider_content_and_operational_edges_fail_closed
    pack = build_profile(
      role: "overall_director",
      profile_id: "overall_director",
      checkpoint_id: "director_startup",
      stage_id: "startup_admission"
    )
    tampered = Marshal.load(Marshal.dump(pack))
    tampered.fetch("dependency_edges").first["to"] = "OTHER_ASSIGNMENT"
    tampered.fetch("projection")["pack_digest"] = IdolRoleContextPack.structured_sha256(
      tampered.reject { |key, _| key == "projection" }.merge(
        "projection" => tampered.fetch("projection").reject { |key, _| key == "pack_digest" }
      )
    )
    errors = IdolRoleContextPack.validate_pack(root: @root, pack: tampered)
    assert_includes errors, "role context dependency edges differ from the exact operational graph"

    @root.join(IdolRoleContextPack::PROJECTION_REGISTRY_RELATIVE).open("a") { |file| file.write("\n# changed registry bytes\n") }
    @root.join("automation/providers/grok-build-profiles.yaml").open("a") { |file| file.write("\n# changed provider bytes\n") }
    errors = IdolRoleContextPack.validate_pack(root: @root, pack: pack)
    assert_includes errors, "role context projection registry SHA-256 is stale"
    assert errors.any? { |error| error.include?("role context provider binding is stale") }
  end

  def test_live_run_state_is_omitted_when_empty
    pack = build_profile(
      role: "overall_director",
      profile_id: "overall_director",
      checkpoint_id: "director_startup",
      stage_id: "startup_admission"
    )
    refute pack.key?("live_run_state")
    refute_includes IdolRoleContextPack.render_runtime_json(pack), "live_run_state"
    assert_equal [], IdolRoleContextPack.validate_pack(root: @root, pack: pack)
  end

  def test_live_run_state_projects_open_holds_consumed_helpers_and_followup_path
    empty = build_profile(
      role: "overall_director",
      profile_id: "overall_director",
      checkpoint_id: "director_startup",
      stage_id: "startup_admission"
    )
    pack = build_profile(
      role: "overall_director",
      profile_id: "overall_director",
      checkpoint_id: "director_startup",
      stage_id: "startup_admission",
      live_run_state: {
        "open_hold_ids" => ["local_pairwise_global_presence_missing"],
        "consumed_helper_ids" => ["helper_collision_audit"],
        "run_followup_path" => "runs/fixture-title/fixture-album/FIXTURE_RUN/review/harness-improvement-review.yaml"
      }
    )

    state = pack.fetch("live_run_state")
    assert_equal ["local_pairwise_global_presence_missing"], state.fetch("open_hold_ids")
    assert_equal ["helper_collision_audit"], state.fetch("consumed_helper_ids")
    assert_equal "runs/fixture-title/fixture-album/FIXTURE_RUN/review/harness-improvement-review.yaml", state.fetch("run_followup_path")
    refute_equal empty.dig("projection", "pack_digest"), pack.dig("projection", "pack_digest")
    assert_includes IdolRoleContextPack.render_runtime_json(pack), "helper_collision_audit"
    assert_equal [], IdolRoleContextPack.validate_pack(root: @root, pack: pack)

    Tempfile.create(["idol-role-context-pack-live", ".json"]) do |file|
      file.write(JSON.pretty_generate(pack))
      file.flush
      stdout, stderr, status = Open3.capture3(
        PYTHON.to_s,
        VALIDATOR.to_s,
        SCHEMA.to_s,
        file.path,
        chdir: REAL_ROOT.to_s
      )
      assert status.success?, "#{stdout}\n#{stderr}"
    end
  end

  def test_compact_founder_quality_context_enters_director_runtime_pack_without_raw_feedback
    sidecar_path = @root.join("runs/fixture-title/fixture-album/FIXTURE_RUN/review/harness-improvement-review.yaml")
    sidecar_path.dirname.mkpath
    FileUtils.cp(REAL_ROOT.join("scripts/tests/fixtures/run-followup-sidecar-v3-valid.yaml"), sidecar_path)
    context = IdolRoleContextPack.extract_founder_quality_context(
      @root,
      {"run" => "runs/fixture-title/fixture-album/FIXTURE_RUN"},
      role: "creative_development_director",
      profile_id: "creative_development_director",
      stage_id: "startup_admission",
      section_ids: []
    )
    refute_nil context
    assert_equal 1, context.fetch("patterns").length
    pack = build_profile(
      role: "creative_development_director",
      profile_id: "creative_development_director",
      checkpoint_id: "cdd_startup",
      stage_id: "startup_admission",
      founder_quality_context: context
    )
    rendered = IdolRoleContextPack.render_runtime_json(pack)
    assert_includes rendered, "local_section_job_mismatch"
    assert_includes rendered, "Can the viewer name the section job"
    refute_includes rendered, "The selected still does not carry the section job."
    assert pack.fetch("dependency_edges").any? { |row| row["edge_type"] == "semantic" }
    assert_equal [], IdolRoleContextPack.validate_pack(root: @root, pack: pack)

    Tempfile.create(["idol-role-context-pack-quality", ".json"]) do |file|
      file.write(JSON.pretty_generate(pack))
      file.flush
      _stdout, stderr, status = Open3.capture3(PYTHON.to_s, VALIDATOR.to_s, SCHEMA.to_s, file.path, chdir: REAL_ROOT.to_s)
      assert status.success?, stderr
    end
  end

  def test_compact_founder_quality_context_filters_worker_section_scope
    sidecar_path = @root.join("runs/fixture-title/fixture-album/FIXTURE_RUN/review/harness-improvement-review.yaml")
    sidecar_path.dirname.mkpath
    FileUtils.cp(REAL_ROOT.join("scripts/tests/fixtures/run-followup-sidecar-v3-valid.yaml"), sidecar_path)
    included = IdolRoleContextPack.extract_founder_quality_context(
      @root,
      {"run" => "runs/fixture-title/fixture-album/FIXTURE_RUN"},
      role: "department_worker",
      profile_id: "pre_song_research",
      stage_id: "creative_route_discovery",
      section_ids: ["S01"]
    )
    excluded = IdolRoleContextPack.extract_founder_quality_context(
      @root,
      {"run" => "runs/fixture-title/fixture-album/FIXTURE_RUN"},
      role: "department_worker",
      profile_id: "pre_song_research",
      stage_id: "creative_route_discovery",
      section_ids: ["S02"]
    )
    refute_nil included
    assert_nil excluded
  end

  def test_extract_live_run_state_reads_consume_receipts_and_sidecar
    receipt = {
      "schema_version" => "idol-helper-consumption-receipt.v1",
      "receipt_id" => "HCR_PACK_CONSUME_001",
      "parent_dispatch_id" => "DISPATCH_PACK",
      "helper_id" => "helper_pack_audit",
      "inspected_inputs" => ["work/fixture/candidate.yaml"],
      "finding" => "Keep the bound helper return.",
      "director_disposition" => "consume"
    }
    receipt_path = @root.join("work/fixture/helper-receipt.yaml")
    receipt_path.dirname.mkpath
    receipt_path.write(YAML.dump(receipt))
    sidecar = YAML.safe_load(REAL_ROOT.join("scripts/tests/fixtures/run-followup-sidecar-valid.yaml").read)
    sidecar["run"] = "runs/fixture-title/fixture-album/FIXTURE_RUN"
    sidecar_path = @root.join("runs/fixture-title/fixture-album/FIXTURE_RUN/review/harness-improvement-review.yaml")
    sidecar_path.dirname.mkpath
    sidecar_path.write(YAML.dump(sidecar))
    state = IdolRoleContextPack.extract_live_run_state(
      @root,
      "run" => "runs/fixture-title/fixture-album/FIXTURE_RUN",
      "runtime_return" => {
        "hold_reasons" => ["helper_collision_hold"],
        "helper_consumption_receipts" => [{
          "path" => "work/fixture/helper-receipt.yaml",
          "sha256" => Digest::SHA256.file(receipt_path).hexdigest,
          "role" => "helper_consumption_receipt"
        }]
      }
    )
    assert_equal ["helper_collision_hold"], state.fetch("open_hold_ids")
    assert_equal ["helper_pack_audit"], state.fetch("consumed_helper_ids")
    assert_equal "runs/fixture-title/fixture-album/FIXTURE_RUN/review/harness-improvement-review.yaml", state.fetch("run_followup_path")
  end

  def test_explicit_graph_shadow_route_builds_exact_node_packs_only_with_current_switch_receipt
    copy_graph_profile_closure
    source_path = @root.join("work/graph-fixture/current-creative-source.md")
    source_path.dirname.mkpath
    source_path.write("# Exact current creative source\n")
    receipt = graph_switch_receipt
    cases = [
      ["planning_cdd_p1", "p1_story_audience_lead", "creative_route_discovery", []],
      ["planning_cdd_p2", "p2_visual_reference_development", "creative_route_discovery", []],
      ["planning_cdd_p3_ci", "p3_section_kinetic_architecture", "front_planning_integration", %w[S01 S02]],
      ["section_cluster_cdd_ci", "v_ci_03v_playback_review", "video_playback_review", %w[S01 S02]]
    ]

    packs = cases.map do |profile_id, checkpoint_id, stage_id, section_ids|
      assignment_id = "GRAPH_FIXTURE_#{profile_id}_#{checkpoint_id}"
      source_envelope, return_recipient = write_graph_dispatch_snapshot(
        assignment_id: assignment_id,
        profile_id: profile_id,
        section_ids: section_ids
      )
      IdolRoleContextPack.build(
        root: @root,
        run_root: "runs/fixture-title/fixture-album/FIXTURE_RUN",
        assignment_id: assignment_id,
        role: profile_id,
        profile_id: profile_id,
        checkpoint_id: checkpoint_id,
        stage_id: stage_id,
        section_ids: section_ids,
        source_envelope: source_envelope,
        current_state: "launched",
        scope: {"stage_id" => stage_id, "section_ids" => section_ids},
        authority: {"assigned_owner" => profile_id, "promotion_owner" => "overall_director"},
        creative_sources: [{
          "source_id" => "CURRENT_CREATIVE_SOURCE",
          "path" => source_path.relative_path_from(@root).to_s,
          "sha256" => Digest::SHA256.file(source_path).hexdigest,
          "purpose" => "Exact named current creative input.",
          "locator" => "markdown:# Exact current creative source",
          "function" => "current_node_creative_truth",
          "role_groups" => ["story", "motion"],
          "disposition" => "applied"
        }],
        output_contract: {"kind" => "fixture_decision_set"},
        hold_conditions: ["stale_bound_source"],
        return_recipient: return_recipient,
        provider: "grok",
        runtime_surface: "grok_cli_acp_or_tui",
        writer: "graph_v2",
        run_class: "new_run",
        switch_receipt: receipt
      )
    end

    packs.each do |pack|
      assert_equal "pass", pack.fetch("status")
      assert_equal "graph_v2", pack.dig("activation_binding", "writer")
      assert_equal "derived_read_only_no_creative_or_promotion_authority", pack.fetch("authority")
      assert_equal IdolRoleContextPack::GRAPH_PROJECTION_REGISTRY_RELATIVE, pack.dig("projection", "registry_path")
      assert_equal IdolRoleContextPack::GRAPH_PROFILE_REGISTRY_RELATIVE, pack.dig("projection", "profile_registry_path")
      assert_equal "frontier_director", pack.dig("provider_binding", "logical_profile_alias")
      assert_operator pack.dig("projection", "projected_word_count"), :<, pack.dig("projection", "original_word_count")
      Array(pack["instruction_slices"]).each do |slice|
        assert_includes %w[markdown_heading pointer_only whole_file], slice.dig("locator", "type")
        next unless slice["path"].to_s.start_with?("policies/")

        refute_equal "whole_file", slice.dig("locator", "type"), slice["path"]
      end
      source = pack.fetch("creative_source_pointers").first
      assert source["source_id"]
      assert source["locator"]
      assert source["sha256"]
      refute source.key?("url")
      refute source.key?("raw_pool")
      identity = pack.fetch("graph_dispatch_identity")
      assert_equal pack.dig("identity", "assignment_id"), identity.fetch("dispatch_id")
      assert_equal pack.dig("identity", "section_ids"), identity.fetch("section_ids")
      assert_equal pack.dig("current_node", "return_recipient"), identity.fetch("return_recipient")
      assert_equal [], IdolRoleContextPack.validate_pack(root: @root, pack: pack)
    end

    cli_source_envelope, cli_return_recipient = write_graph_dispatch_snapshot(
      assignment_id: "GRAPH_FIXTURE_CLI_P1",
      profile_id: "planning_cdd_p1",
      section_ids: []
    )
    request_path = @root.join("work/graph-fixture/pack-request.yaml")
    request_path.dirname.mkpath
    request_path.write(YAML.dump({
      "run_root" => "runs/fixture-title/fixture-album/FIXTURE_RUN",
      "assignment_id" => "GRAPH_FIXTURE_CLI_P1",
      "role" => "planning_cdd_p1",
      "profile_id" => "planning_cdd_p1",
      "checkpoint_id" => "p1_story_audience_lead",
      "stage_id" => "creative_route_discovery",
      "source_envelope" => cli_source_envelope,
      "current_state" => "launched",
      "authority" => {"assigned_owner" => "planning_cdd_p1", "promotion_owner" => "overall_director"},
      "output_contract" => {"kind" => "fixture_decision_set"},
      "hold_conditions" => ["stale_bound_source"],
      "return_recipient" => cli_return_recipient,
      "provider" => "grok",
      "runtime_surface" => "grok_cli_acp_or_tui",
      "writer" => "graph_v2",
      "run_class" => "new_run",
      "switch_receipt" => receipt
    }))
    output_path = @root.join("work/graph-fixture/role-context-pack.json")
    stdout, stderr, status = Open3.capture3(
      "ruby",
      REAL_ROOT.join("scripts", "idol_role_context_pack.rb").to_s,
      "build-profile",
      "--root",
      @root.to_s,
      "--request",
      request_path.to_s,
      "--output",
      output_path.to_s,
      chdir: @root.to_s
    )
    assert status.success?, [stdout, stderr].join("\n")
    cli_pack = JSON.parse(output_path.read)
    assert_equal "idol-role-context-pack.v1", cli_pack.fetch("schema_version")
    assert_equal "derived_read_only_no_creative_or_promotion_authority", cli_pack.fetch("authority")
    assert_equal "graph_v2", cli_pack.dig("activation_binding", "writer")

    Tempfile.create(["idol-graph-role-context-pack", ".json"]) do |file|
      file.write(JSON.pretty_generate(packs.first))
      file.flush
      _stdout, stderr, status = Open3.capture3(PYTHON.to_s, VALIDATOR.to_s, SCHEMA.to_s, file.path, chdir: REAL_ROOT.to_s)
      assert status.success?, stderr
    end

    request_path = @root.join("work/graph-fixture/request.json")
    output_path = @root.join("work/graph-fixture/pack.json")
    request_path.write(JSON.pretty_generate(
      "run_root" => "runs/fixture-title/fixture-album/FIXTURE_RUN",
      "assignment_id" => "GRAPH_FIXTURE_CLI_P1",
      "role" => "planning_cdd_p1",
      "profile_id" => "planning_cdd_p1",
      "checkpoint_id" => "p1_story_audience_lead",
      "stage_id" => "creative_route_discovery",
      "source_envelope" => cli_source_envelope,
      "current_state" => "launched",
      "scope" => {"stage_id" => "creative_route_discovery", "section_ids" => []},
      "authority" => {"assigned_owner" => "planning_cdd_p1", "promotion_owner" => "overall_director"},
      "creative_sources" => [{
        "source_id" => "CURRENT_CREATIVE_SOURCE",
        "path" => source_path.relative_path_from(@root).to_s,
        "sha256" => Digest::SHA256.file(source_path).hexdigest,
        "purpose" => "Exact named current creative input.",
        "locator" => "markdown:# Exact current creative source",
        "function" => "current_node_creative_truth",
        "role_groups" => ["story"],
        "disposition" => "applied"
      }],
      "output_contract" => {"kind" => "fixture_decision_set"},
      "hold_conditions" => ["stale_bound_source"],
      "return_recipient" => cli_return_recipient,
      "provider" => "grok",
      "runtime_surface" => "grok_cli_acp_or_tui",
      "writer" => "graph_v2",
      "run_class" => "new_run",
      "switch_receipt" => receipt
    ))
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      REAL_ROOT.join("scripts/idol_role_context_pack.rb").to_s,
      "build-profile",
      "--root", @root.to_s,
      "--request", request_path.relative_path_from(@root).to_s,
      "--output", output_path.relative_path_from(@root).to_s,
      chdir: REAL_ROOT.to_s
    )
    assert status.success?, "#{stdout}\n#{stderr}"
    assert_equal "graph_v2", JSON.parse(output_path.read).dig("activation_binding", "writer")
  end

  def test_every_executable_graph_profile_checkpoint_builds_and_maintenance_stays_non_runtime
    copy_graph_profile_closure
    registry = YAML.safe_load(@root.join(IdolRoleContextPack::GRAPH_PROFILE_REGISTRY_RELATIVE).read, aliases: true)
    stage_by_checkpoint = {
      "director_startup" => "creative_route_discovery",
      "g40_planning_cell_handoff" => "front_planning_integration",
      "p1_story_audience_lead" => "creative_route_discovery",
      "p1_g40_integration_handoff" => "front_planning_integration",
      "p2_visual_reference_development" => "creative_route_discovery",
      "p3_section_kinetic_architecture" => "front_planning_integration",
      "p3_draft_keyframe_proof" => "front_planning_integration",
      "v_ci_02b_pixel_review" => "generated_branch_cut_review",
      "v_ci_03v_playback_review" => "video_playback_review",
      "section_02b_image" => "branch_cut_generation",
      "section_03v_motion" => "video_motion_direction",
      "edit_qc_section" => "edit_assembly_playback_qc"
    }
    executable = Array(registry["profiles"]).reject { |profile| profile["profile_kind"] == "maintenance_only" }
    assert_equal 7, executable.length

    execution_cases = executable.flat_map do |profile|
      Array(profile.dig("phase_load", "checkpoints")).flat_map do |checkpoint|
        stages = Array(checkpoint["stage_ids"])
        stages = [stage_by_checkpoint.fetch(checkpoint.fetch("checkpoint_id"))] if stages.empty?
        stages.map { |stage_id| [profile, checkpoint, stage_id] }
      end
    end

    built = execution_cases.map do |profile, checkpoint, stage_id|
        checkpoint_id = checkpoint.fetch("checkpoint_id")
        profile_id = profile.fetch("profile_id")
        section_ids = case profile_id
                      when "planning_cdd_p3_ci", "section_cluster_cdd_ci", "edit_director"
                        %w[S01 S02]
                      when "section_image_motion_worker"
                        %w[S01]
                      else
                        []
                      end
        assignment_id = "GRAPH_ALL_#{profile_id}_#{checkpoint_id}_#{stage_id}"
        graph_execution = if checkpoint["judgment_profile_id"]
                            source_envelope, return_recipient = write_graph_dispatch_snapshot(
                              assignment_id: assignment_id,
                              profile_id: profile_id,
                              section_ids: section_ids
                            )
                            {
                              source_envelope: source_envelope,
                              current_state: "launched",
                              return_recipient: return_recipient
                            }
                          else
                            {
                              current_state: "prepared",
                              return_recipient: {"role" => profile.fetch("role") == "overall_director" ? "founder" : "overall_director"}
                            }
                          end
        pack = IdolRoleContextPack.build(
          root: @root,
          run_root: "runs/fixture-title/fixture-album/FIXTURE_RUN",
          assignment_id: assignment_id,
          role: profile.fetch("role"),
          profile_id: profile_id,
          checkpoint_id: checkpoint_id,
          stage_id: stage_id,
          section_ids: section_ids,
          scope: {"stage_id" => stage_id, "section_ids" => section_ids},
          authority: {"assigned_owner" => profile.fetch("role"), "promotion_owner" => "overall_director"},
          output_contract: {"kind" => "fixture_decision_set"},
          hold_conditions: ["stale_bound_source"],
          provider: "grok",
          runtime_surface: "grok_cli_acp_or_tui",
          writer: "graph_v2",
          run_class: "new_run",
          switch_receipt: graph_switch_receipt,
          **graph_execution
        )
        assert_equal "pass", pack.fetch("status"), "#{profile.fetch('profile_id')}.#{checkpoint_id}"
        assert_equal checkpoint.fetch("unload_after"), pack.fetch("unload_after")
        if checkpoint["judgment_profile_id"]
          contract = pack.fetch("creative_judgment_contract")
          assert_equal checkpoint.fetch("judgment_profile_id"), contract.fetch("profile_id")
          assert_equal "automation/graph-creative-judgment-registry.yaml", contract.dig("registry", "path")
          assert_match %r{\Aautomation/graph-creative-judgment-profile-releases/#{Regexp.escape(contract.fetch("profile_id"))}/[a-f0-9]{64}\.yaml\z}, contract.dig("profile_release", "path")
          assert_match %r{\Aautomation/graph-creative-judgment-profile-promotions/}, contract.dig("profile_promotion", "path")
          assert_equal false, contract.fetch("profile").fetch("criteria").empty?
          assert_equal assignment_id, pack.dig("graph_dispatch_identity", "dispatch_id")
        else
          refute pack.key?("creative_judgment_contract")
          refute pack.key?("graph_dispatch_identity")
        end
        assert_equal [], IdolRoleContextPack.validate_pack(root: @root, pack: pack), "#{profile.fetch('profile_id')}.#{checkpoint_id}"
        pack
    end
    expected = execution_cases.map { |profile, checkpoint, stage_id| [profile.fetch("profile_id"), checkpoint.fetch("checkpoint_id"), stage_id] }
    actual = built.map { |pack| %w[profile_id checkpoint_id stage_id].map { |key| pack.dig("identity", key) } }
    assert_equal expected.sort, actual.sort

    maintenance = Array(registry["profiles"]).find { |profile| profile["profile_kind"] == "maintenance_only" }
    refute_nil maintenance
    assert_equal "graph_engineering_maintenance", maintenance.fetch("profile_id")
    assert_equal [], maintenance.fetch("stage_ids")
    error = assert_raises(IdolRoleContextPack::ContractError) do
      IdolRoleContextPack.build(
        root: @root,
        run_root: "runs/fixture-title/fixture-album/FIXTURE_RUN",
        assignment_id: "GRAPH_MAINTENANCE_NOT_RUNTIME",
        role: maintenance.fetch("role"),
        profile_id: maintenance.fetch("profile_id"),
        checkpoint_id: maintenance.dig("phase_load", "checkpoints", 0, "checkpoint_id"),
        stage_id: "graph_engineering_maintenance",
        authority: {"assigned_owner" => maintenance.fetch("role")},
        output_contract: {"kind" => "fixture_decision_set"},
        return_recipient: {"role" => "overall_director"},
        provider: "grok",
        runtime_surface: "grok_cli_acp_or_tui",
        writer: "graph_v2",
        run_class: "new_run",
        switch_receipt: graph_switch_receipt
      )
    end
    assert_includes error.message, "stage is outside selected profile"
  end

  def test_graph_startup_judgment_profile_is_projection_only_without_dispatch_identity
    copy_graph_profile_closure
    source_path = @root.join("runs/fixture-title/fixture-album/FIXTURE_RUN/run-manifest.yaml")
    source_path.dirname.mkpath
    source_path.write("schema_version: fixture-run-manifest.v1\n")
    pack = IdolRoleContextPack.build(
      root: @root,
      run_root: "runs/fixture-title/fixture-album/FIXTURE_RUN",
      assignment_id: "GRAPH_STARTUP_P1_PROJECTION",
      role: "planning_cdd_p1",
      profile_id: "planning_cdd_p1",
      checkpoint_id: "p1_story_audience_lead",
      stage_id: "creative_route_discovery",
      source_envelope: {
        "kind" => "startup_admission",
        "path" => source_path.relative_path_from(@root).to_s,
        "sha256" => Digest::SHA256.file(source_path).hexdigest
      },
      current_state: "prepared",
      scope: {"stage_id" => "creative_route_discovery", "section_ids" => []},
      authority: {"assigned_owner" => "planning_cdd_p1", "promotion_owner" => "overall_director"},
      output_contract: {"kind" => "startup_projection_only"},
      hold_conditions: ["stale_bound_source"],
      return_recipient: {"role" => "overall_director"},
      provider: "grok",
      runtime_surface: "grok_cli_acp_or_tui",
      writer: "graph_v2",
      run_class: "new_run",
      switch_receipt: graph_switch_receipt
    )

    assert pack.key?("creative_judgment_contract")
    refute pack.key?("graph_dispatch_identity")
    assert_equal "startup_admission", pack.dig("source_envelope", "kind")
    assert_equal "prepared", pack.dig("current_node", "state")
    assert_equal [], IdolRoleContextPack.validate_pack(root: @root, pack: pack)
    Tempfile.create(["idol-graph-startup-projection", ".json"]) do |file|
      file.write(JSON.pretty_generate(pack))
      file.flush
      _stdout, stderr, status = Open3.capture3(PYTHON.to_s, VALIDATOR.to_s, SCHEMA.to_s, file.path, chdir: REAL_ROOT.to_s)
      assert status.success?, stderr
    end

    dispatch_pack = build_graph_fixture(switch_receipt: graph_switch_receipt)
    pack["graph_dispatch_identity"] = dispatch_pack.fetch("graph_dispatch_identity")
    refresh_pack_self_digests(pack)
    errors = IdolRoleContextPack.validate_pack(root: @root, pack: pack)
    assert_includes errors, "Graph startup judgment projection must not carry graph_dispatch_identity"
  end

  def test_graph_dispatch_identity_preserves_prework_lifecycle_at_pack_creation
    copy_graph_profile_closure
    %w[prepared launched returned].each do |lifecycle_state|
      pack = build_graph_fixture(
        switch_receipt: graph_switch_receipt,
        lifecycle_state: lifecycle_state
      )
      identity = pack.fetch("graph_dispatch_identity")
      assert_equal "exact_copy_from_hash_bound_graph_dispatch_at_pack_creation", identity.fetch("authority")
      assert_equal lifecycle_state, identity.fetch("dispatch_lifecycle_state_at_projection")
      assert_equal lifecycle_state, pack.dig("current_node", "state")
      assert_equal [], IdolRoleContextPack.validate_pack(root: @root, pack: pack), lifecycle_state
    end
  end

  def test_graph_dispatch_identity_rejects_lifecycle_mismatch_or_nonprojectable_state
    copy_graph_profile_closure
    mismatch = assert_raises(IdolRoleContextPack::ContractError) do
      build_graph_fixture(
        switch_receipt: graph_switch_receipt,
        lifecycle_state: "launched",
        extra: {current_state: "prepared"}
      )
    end
    assert_includes mismatch.message, "state differs from Department Dispatch at projection"

    nonprojectable = assert_raises(IdolRoleContextPack::ContractError) do
      build_graph_fixture(
        switch_receipt: graph_switch_receipt,
        lifecycle_state: "reviewed"
      )
    end
    assert_includes nonprojectable.message, "lifecycle is not projectable"
  end

  def test_graph_judgment_checkpoint_rejects_another_stage_from_the_same_role_profile
    copy_graph_profile_closure
    error = assert_raises(IdolRoleContextPack::ContractError) do
      IdolRoleContextPack.build(
        root: @root,
        run_root: "runs/fixture-title/fixture-album/FIXTURE_RUN",
        assignment_id: "GRAPH_WRONG_CHECKPOINT_STAGE",
        role: "section_cluster_cdd_ci",
        profile_id: "section_cluster_cdd_ci",
        checkpoint_id: "v_ci_02b_pixel_review",
        stage_id: "video_playback_review",
        section_ids: %w[S01 S02],
        scope: {"stage_id" => "video_playback_review", "section_ids" => %w[S01 S02]},
        authority: {"assigned_owner" => "section_cluster_cdd_ci", "promotion_owner" => "overall_director"},
        output_contract: {"kind" => "fixture_decision_set"},
        hold_conditions: ["wrong_checkpoint_stage"],
        return_recipient: {"role" => "overall_director"},
        provider: "grok",
        runtime_surface: "grok_cli_acp_or_tui",
        writer: "graph_v2",
        run_class: "new_run",
        switch_receipt: graph_switch_receipt
      )
    end
    assert_match(/outside selected checkpoint/, error.message)
  end

  def test_graph_pack_rejects_judgment_profile_or_registry_hash_drift
    copy_graph_profile_closure
    pack = build_graph_fixture(switch_receipt: graph_switch_receipt)
    contract = pack.fetch("creative_judgment_contract")
    contract.fetch("profile").fetch("criteria").first["minimum"] = 0
    errors = IdolRoleContextPack.validate_pack(root: @root, pack: pack)
    assert_includes errors, "graph creative judgment contract profile differs from its immutable release"

    pack = build_graph_fixture(switch_receipt: graph_switch_receipt)
    pack.fetch("creative_judgment_contract").fetch("registry")["sha256"] = "0" * 64
    errors = IdolRoleContextPack.validate_pack(root: @root, pack: pack)
    assert_includes errors, "graph creative judgment contract registry provenance SHA-256 is invalid"

    pack = build_graph_fixture(switch_receipt: graph_switch_receipt)
    pack.fetch("creative_judgment_contract").fetch("profile_release")["sha256"] = "0" * 64
    errors = IdolRoleContextPack.validate_pack(root: @root, pack: pack)
    assert_includes errors, "graph creative judgment profile release SHA-256 is stale"

    pack = build_graph_fixture(switch_receipt: graph_switch_receipt)
    pack.fetch("creative_judgment_contract").fetch("profile_promotion")["sha256"] = "0" * 64
    refresh_pack_self_digests(pack)
    errors = IdolRoleContextPack.validate_pack(root: @root, pack: pack)
    assert errors.any? { |message| message.include?("profile promotion artifact SHA-256 is stale") }
  end

  def test_graph_registry_rejects_current_pointer_without_promotion_binding
    copy_graph_profile_closure
    registry_path = @root.join(IdolRoleContextPack::GRAPH_JUDGMENT_REGISTRY_RELATIVE)
    registry = YAML.safe_load(registry_path.read, aliases: true)
    registry.fetch("current_profile_releases").fetch("front_planning_close").delete("promotion_binding")
    registry_path.write(YAML.dump(registry))

    error = assert_raises(IdolRoleContextPack::ContractError) do
      IdolRoleContextPack.validate_graph_judgment_registry!(root: @root, registry: registry)
    end
    assert_match(/promotion_binding/, error.message)
  end

  def test_graph_pack_keeps_its_immutable_profile_after_current_registry_changes
    copy_graph_profile_closure
    pack = build_graph_fixture(switch_receipt: graph_switch_receipt)
    registry_path = @root.join(IdolRoleContextPack::GRAPH_JUDGMENT_REGISTRY_RELATIVE)
    registry = YAML.safe_load(registry_path.read, aliases: true)
    registry.fetch("profiles").find { |row| row.fetch("profile_id") == "front_planning_close" }["evidence_surface"] = "future_profile_revision"
    registry_path.write(YAML.dump(registry))

    active_errors = IdolRoleContextPack.validate_pack(root: @root, pack: pack)
    refute_empty active_errors

    assert_equal [], IdolRoleContextPack.validate_pack(
      root: @root,
      pack: pack,
      validation_mode: "historical_audit"
    )
  end

  def test_graph_pack_rejects_missing_checkpoint_slice_even_after_self_digests_are_recomputed
    copy_graph_profile_closure
    pack = build_graph_fixture(switch_receipt: graph_switch_receipt)
    removed = pack.fetch("instruction_slices").shift
    assert_equal "planning_cdd", removed.fetch("binding_id")
    refresh_pack_self_digests(pack)

    errors = IdolRoleContextPack.validate_pack(root: @root, pack: pack)

    assert_includes errors, "graph instruction_slices differ from the exact profile checkpoint projection"
    refute_includes errors, "role context source-set SHA-256 is stale"
    refute_includes errors, "role context pack digest is stale"
  end

  def test_legacy_pack_rejects_omitted_checkpoint_slice_even_after_self_digests_are_recomputed
    copy_harness_maintenance_wiki
    pack = build_profile(
      role: "mechanical_coordinator",
      profile_id: "harness_maintenance",
      checkpoint_id: "skill_profile_routing",
      stage_id: "skill_profile_routing"
    )
    removed = pack.fetch("instruction_slices").shift
    refute_nil removed
    refresh_pack_self_digests(pack)
    errors = IdolRoleContextPack.validate_pack(root: @root, pack: pack)
    assert_includes errors, "legacy instruction_slices differ from the exact profile checkpoint projection"
    refute_includes errors, "role context source-set SHA-256 is stale"
    refute_includes errors, "role context pack digest is stale"
  end

  def test_legacy_pack_rejects_extra_checkpoint_slice_even_after_self_digests_are_recomputed
    copy_harness_maintenance_wiki
    pack = build_profile(
      role: "mechanical_coordinator",
      profile_id: "harness_maintenance",
      checkpoint_id: "skill_profile_routing",
      stage_id: "skill_profile_routing"
    )
    pack.fetch("instruction_slices") << Marshal.load(Marshal.dump(pack.fetch("instruction_slices").last))
    refresh_pack_self_digests(pack)
    errors = IdolRoleContextPack.validate_pack(root: @root, pack: pack)
    assert_includes errors, "legacy instruction_slices differ from the exact profile checkpoint projection"
    refute_includes errors, "role context source-set SHA-256 is stale"
    refute_includes errors, "role context pack digest is stale"
  end

  def test_graph_pack_rejects_unload_boundary_drift
    copy_graph_profile_closure
    pack = build_graph_fixture(switch_receipt: graph_switch_receipt)
    pack["unload_after"] = "wrong_checkpoint_return"
    refresh_pack_self_digests(pack)

    errors = IdolRoleContextPack.validate_pack(root: @root, pack: pack)

    assert_includes errors, "graph unload_after differs from the exact profile checkpoint"
    refute_includes errors, "role context pack digest is stale"
  end

  def test_graph_pack_rejects_dispatch_identity_drift_after_self_digests_are_recomputed
    copy_graph_profile_closure
    mutations = {
      "lane" => ->(identity) { identity["lane_id"] = "planning_p2" },
      "cohort" => ->(identity) { identity["section_cohort_id"] = "C9" },
      "run" => ->(identity) { identity["run"] = "runs/other-title/other-album/OTHER_RUN" },
      "projection lifecycle" => ->(identity) { identity["dispatch_lifecycle_state_at_projection"] = "prepared" },
      "writer session" => ->(identity) { identity.fetch("output_writer")["session_id"] = "FORGED_SESSION" },
      "reviewer" => ->(identity) { identity.fetch("reviewer")["owner"] = "forged-reviewer" },
      "return recipient" => ->(identity) { identity.fetch("return_recipient")["return_route"] = "forged-route" }
    }

    mutations.each do |label, mutate|
      pack = build_graph_fixture(switch_receipt: graph_switch_receipt)
      mutate.call(pack.fetch("graph_dispatch_identity"))
      refresh_pack_self_digests(pack)

      errors = IdolRoleContextPack.validate_pack(root: @root, pack: pack)

      assert_includes errors, "graph_dispatch_identity differs from the exact Graph Dispatch snapshot", label
      refute_includes errors, "role context source-set SHA-256 is stale", label
      refute_includes errors, "role context pack digest is stale", label
    end
  end

  def test_role_context_schema_requires_dispatch_identity_for_graph_judgment_contract
    copy_graph_profile_closure
    pack = build_graph_fixture(switch_receipt: graph_switch_receipt)
    pack.delete("graph_dispatch_identity")
    errors = IdolRoleContextPack.validate_pack(root: @root, pack: pack)
    assert_includes errors, "graph_dispatch_identity differs from the exact Graph Dispatch snapshot"

    Tempfile.create(["idol-graph-judgment-pack-without-dispatch", ".json"]) do |file|
      file.write(JSON.pretty_generate(pack))
      file.flush
      _stdout, stderr, status = Open3.capture3(PYTHON.to_s, VALIDATOR.to_s, SCHEMA.to_s, file.path, chdir: REAL_ROOT.to_s)
      refute status.success?
      assert_includes stderr, "not valid under any of the given schemas"
    end
  end

  def test_graph_judgment_pack_rejects_dispatch_lane_or_cohort_for_another_profile
    copy_graph_profile_closure
    assignment_id = "GRAPH_WRONG_P3_LANE"
    source_envelope, return_recipient = write_graph_dispatch_snapshot(
      assignment_id: assignment_id,
      profile_id: "planning_cdd_p3_ci",
      section_ids: %w[S01 S02]
    )
    dispatch_path = @root.join(source_envelope.fetch("path"))
    dispatch = YAML.safe_load(dispatch_path.read, aliases: true)
    dispatch["lane_id"] = "planning_p3_c2"
    dispatch_path.write(YAML.dump(dispatch))
    source_envelope["sha256"] = Digest::SHA256.file(dispatch_path).hexdigest

    error = assert_raises(IdolRoleContextPack::ContractError) do
      IdolRoleContextPack.build(
        root: @root,
        run_root: "runs/fixture-title/fixture-album/FIXTURE_RUN",
        assignment_id: assignment_id,
        role: "planning_cdd_p3_ci",
        profile_id: "planning_cdd_p3_ci",
        checkpoint_id: "p3_section_kinetic_architecture",
        stage_id: "front_planning_integration",
        section_ids: %w[S01 S02],
        source_envelope: source_envelope,
        current_state: "launched",
        scope: {"stage_id" => "front_planning_integration", "section_ids" => %w[S01 S02]},
        authority: {"assigned_owner" => "planning_cdd_p3_ci", "promotion_owner" => "overall_director"},
        output_contract: {"kind" => "fixture_decision_set"},
        hold_conditions: ["wrong_lane_or_cohort"],
        return_recipient: return_recipient,
        provider: "grok",
        runtime_surface: "grok_cli_acp_or_tui",
        writer: "graph_v2",
        run_class: "new_run",
        switch_receipt: graph_switch_receipt
      )
    end
    assert_includes error.message, "lane/cohort differs from profile"
  end

  def test_graph_shadow_route_fails_closed_without_exact_current_switch_receipt
    copy_graph_profile_closure
    missing = assert_raises(IdolRoleContextPack::ContractError) do
      build_graph_fixture(switch_receipt: nil)
    end
    assert_includes missing.message, "verified default-switch receipt"

    dual = assert_raises(IdolRoleContextPack::ContractError) do
      build_graph_fixture(
        switch_receipt: graph_switch_receipt,
        extra: {active_writers: %w[graph_v2 legacy_pinned]}
      )
    end
    assert_includes dual.message, "dual active writer"

    url = assert_raises(IdolRoleContextPack::ContractError) do
      source_path = @root.join("work/graph-fixture/current-creative-source.md")
      source_path.dirname.mkpath
      source_path.write("# Exact current creative source\n")
      IdolRoleContextPack.build(
        root: @root,
        run_root: "runs/fixture-title/fixture-album/FIXTURE_RUN",
        assignment_id: "GRAPH_FIXTURE_URL",
        role: "planning_cdd_p1",
        profile_id: "planning_cdd_p1",
        checkpoint_id: "p1_story_audience_lead",
        stage_id: "creative_route_discovery",
        authority: {"assigned_owner" => "planning_cdd_p1", "promotion_owner" => "overall_director"},
        creative_sources: [{
          "source_id" => "SRC_URL",
          "path" => source_path.relative_path_from(@root).to_s,
          "sha256" => Digest::SHA256.file(source_path).hexdigest,
          "purpose" => "Forbidden URL field.",
          "locator" => "markdown:# Exact current creative source",
          "function" => "scene_visual_package",
          "url" => "https://example.invalid/raw-pool"
        }],
        output_contract: {"kind" => "fixture_decision_set"},
        hold_conditions: ["stale_bound_source"],
        return_recipient: {"role" => "overall_director"},
        provider: "grok",
        runtime_surface: "grok_cli_acp_or_tui",
        writer: "graph_v2",
        run_class: "new_run",
        switch_receipt: graph_switch_receipt
      )
    end
    assert_includes url.message, "forbidden field: url"

    unrecoverable = assert_raises(IdolRoleContextPack::ContractError) do
      source_path = @root.join("work/graph-fixture/current-creative-source.md")
      source_path.dirname.mkpath
      source_path.write("# Exact current creative source\n")
      IdolRoleContextPack.build(
        root: @root,
        run_root: "runs/fixture-title/fixture-album/FIXTURE_RUN",
        assignment_id: "GRAPH_FIXTURE_UNRECOVERABLE",
        role: "planning_cdd_p1",
        profile_id: "planning_cdd_p1",
        checkpoint_id: "p1_story_audience_lead",
        stage_id: "creative_route_discovery",
        authority: {"assigned_owner" => "planning_cdd_p1", "promotion_owner" => "overall_director"},
        creative_sources: [{
          "path" => source_path.relative_path_from(@root).to_s,
          "sha256" => Digest::SHA256.file(source_path).hexdigest,
          "purpose" => "Missing recoverable locator.",
          "function" => "motion_reference"
        }],
        output_contract: {"kind" => "fixture_decision_set"},
        hold_conditions: ["stale_bound_source"],
        return_recipient: {"role" => "overall_director"},
        provider: "grok",
        runtime_surface: "grok_cli_acp_or_tui",
        writer: "graph_v2",
        run_class: "new_run",
        switch_receipt: graph_switch_receipt
      )
    end
    assert_match(/source_id is required|locator is required/, unrecoverable.message)

    stale = graph_switch_receipt.merge("source_set_sha256" => "0" * 64)
    mismatch = assert_raises(IdolRoleContextPack::ContractError) do
      build_graph_fixture(switch_receipt: stale)
    end
    assert_includes mismatch.message, "source set differs"

    existing = assert_raises(IdolRoleContextPack::ContractError) do
      build_graph_fixture(switch_receipt: graph_switch_receipt, run_class: "existing_run")
    end
    assert_includes existing.message, "explicitly classified new run"
  end

  def test_selected_reference_direct_follow_projects_without_whole_production_principle
    heading = "Selected Reference Direct-Follow Preservation"
    constitution_path = "policies/creative-production-constitution.md"

    cdd = build_profile(
      role: "creative_development_director",
      profile_id: "creative_development_director",
      checkpoint_id: "cdd_startup",
      stage_id: "startup_admission"
    )
    assert_selected_reference_follow_slice(cdd, heading, constitution_path)

    copy_graph_profile_closure
    p2_assignment = "GRAPH_FIXTURE_P2_REFERENCE_BOUNDARY"
    p2_envelope, p2_recipient = write_graph_dispatch_snapshot(
      assignment_id: p2_assignment,
      profile_id: "planning_cdd_p2",
      section_ids: []
    )
    p2 = IdolRoleContextPack.build(
      root: @root,
      run_root: "runs/fixture-title/fixture-album/FIXTURE_RUN",
      assignment_id: p2_assignment,
      role: "planning_cdd_p2",
      profile_id: "planning_cdd_p2",
      checkpoint_id: "p2_visual_reference_development",
      stage_id: "creative_route_discovery",
      source_envelope: p2_envelope,
      current_state: "launched",
      scope: {"stage_id" => "creative_route_discovery", "section_ids" => []},
      authority: {"assigned_owner" => "planning_cdd_p2", "promotion_owner" => "overall_director"},
      output_contract: {"kind" => "fixture_decision_set"},
      hold_conditions: ["stale_bound_source"],
      return_recipient: p2_recipient,
      provider: "grok",
      runtime_surface: "grok_cli_acp_or_tui",
      writer: "graph_v2",
      run_class: "new_run",
      switch_receipt: graph_switch_receipt
    )
    assert_selected_reference_follow_slice(p2, heading, constitution_path)

    worker_assignment = "GRAPH_FIXTURE_WORKER_REFERENCE_BOUNDARY"
    worker_envelope, worker_recipient = write_graph_dispatch_snapshot(
      assignment_id: worker_assignment,
      profile_id: "section_image_motion_worker",
      section_ids: %w[S01]
    )
    worker = IdolRoleContextPack.build(
      root: @root,
      run_root: "runs/fixture-title/fixture-album/FIXTURE_RUN",
      assignment_id: worker_assignment,
      role: "section_image_motion_worker",
      profile_id: "section_image_motion_worker",
      checkpoint_id: "section_02b_image",
      stage_id: "branch_cut_generation",
      section_ids: %w[S01],
      source_envelope: worker_envelope,
      current_state: "launched",
      scope: {"stage_id" => "branch_cut_generation", "section_ids" => %w[S01]},
      authority: {"assigned_owner" => "section_image_motion_worker", "promotion_owner" => "overall_director"},
      output_contract: {"kind" => "fixture_decision_set"},
      hold_conditions: ["stale_bound_source"],
      return_recipient: worker_recipient,
      provider: "grok",
      runtime_surface: "grok_cli_acp_or_tui",
      writer: "graph_v2",
      run_class: "new_run",
      switch_receipt: graph_switch_receipt
    )
    assert_selected_reference_follow_slice(worker, heading, constitution_path)

    motion_assignment = "GRAPH_FIXTURE_03V_REFERENCE_BOUNDARY"
    motion_envelope, motion_recipient = write_graph_dispatch_snapshot(
      assignment_id: motion_assignment,
      profile_id: "section_image_motion_worker",
      section_ids: %w[S01]
    )
    motion = IdolRoleContextPack.build(
      root: @root,
      run_root: "runs/fixture-title/fixture-album/FIXTURE_RUN",
      assignment_id: motion_assignment,
      role: "section_image_motion_worker",
      profile_id: "section_image_motion_worker",
      checkpoint_id: "section_03v_motion",
      stage_id: "video_motion_direction",
      section_ids: %w[S01],
      source_envelope: motion_envelope,
      current_state: "launched",
      scope: {"stage_id" => "video_motion_direction", "section_ids" => %w[S01]},
      authority: {"assigned_owner" => "section_image_motion_worker", "promotion_owner" => "overall_director"},
      output_contract: {"kind" => "fixture_decision_set"},
      hold_conditions: ["stale_bound_source"],
      return_recipient: motion_recipient,
      provider: "grok",
      runtime_surface: "grok_cli_acp_or_tui",
      writer: "graph_v2",
      run_class: "new_run",
      switch_receipt: graph_switch_receipt
    )
    assert_selected_reference_follow_slice(motion, heading, constitution_path)

    registry = YAML.safe_load(@root.join(IdolRoleContextPack::GRAPH_JUDGMENT_REGISTRY_RELATIVE).read, aliases: true)
    expected_p2 = Array(registry["profiles"]).find { |row| row["profile_id"] == "reference_candidate" }.fetch("criteria")
    expected_worker = Array(registry["profiles"]).find { |row| row["profile_id"] == "pixel_02b" }.fetch("criteria")
    expected_motion = Array(registry["profiles"]).find { |row| row["profile_id"] == "playback_03v" }.fetch("criteria")
    assert_equal "reference_candidate", p2.dig("creative_judgment_contract", "profile_id")
    assert_equal IdolRoleContextPack.canonical_value(expected_p2),
                 IdolRoleContextPack.canonical_value(p2.dig("creative_judgment_contract", "profile", "criteria"))
    assert_equal "pixel_02b", worker.dig("creative_judgment_contract", "profile_id")
    assert_equal IdolRoleContextPack.canonical_value(expected_worker),
                 IdolRoleContextPack.canonical_value(worker.dig("creative_judgment_contract", "profile", "criteria"))
    assert_equal "section_03v_motion", motion.dig("identity", "checkpoint_id")
    assert_equal "playback_03v", motion.dig("creative_judgment_contract", "profile_id")
    assert_equal IdolRoleContextPack.canonical_value(expected_motion),
                 IdolRoleContextPack.canonical_value(motion.dig("creative_judgment_contract", "profile", "criteria"))
  end

  private

  def build_graph_fixture(switch_receipt:, run_class: "new_run", lifecycle_state: "launched", extra: {})
    assignment_id = "GRAPH_FIXTURE_P1"
    source_envelope, return_recipient = write_graph_dispatch_snapshot(
      assignment_id: assignment_id,
      profile_id: "planning_cdd_p1",
      section_ids: [],
      lifecycle_state: lifecycle_state
    )
    IdolRoleContextPack.build(
      root: @root,
      run_root: "runs/fixture-title/fixture-album/FIXTURE_RUN",
      assignment_id: assignment_id,
      role: "planning_cdd_p1",
      profile_id: "planning_cdd_p1",
      checkpoint_id: "p1_story_audience_lead",
      stage_id: "creative_route_discovery",
      source_envelope: source_envelope,
      current_state: lifecycle_state,
      authority: {"assigned_owner" => "planning_cdd_p1", "promotion_owner" => "overall_director"},
      output_contract: {"kind" => "fixture_decision_set"},
      hold_conditions: ["stale_bound_source"],
      return_recipient: return_recipient,
      provider: "grok",
      runtime_surface: "grok_cli_acp_or_tui",
      writer: "graph_v2",
      run_class: run_class,
      switch_receipt: switch_receipt,
      **extra
    )
  end

  def write_graph_dispatch_snapshot(assignment_id:, profile_id:, section_ids:, lifecycle_state: "launched")
    role_contract = {
      "overall_director" => {
        "lane_id" => "overall",
        "section_cohort_id" => nil,
        "logical_role" => "overall_director",
        "reviewer" => {"owner" => "fixture-overall", "role" => "overall_director", "lane_id" => "overall"},
        "return_recipient" => {"owner" => "fixture-overall", "role" => "overall_director", "return_route" => "overall_exact_review"}
      },
      "planning_cdd_p1" => {
        "lane_id" => "planning_p1",
        "section_cohort_id" => nil,
        "logical_role" => "planning_cdd",
        "reviewer" => {"owner" => "fixture-overall", "role" => "overall_director", "lane_id" => "overall"},
        "return_recipient" => {"owner" => "fixture-overall", "role" => "overall_director", "return_route" => "overall_exact_review"}
      },
      "planning_cdd_p2" => {
        "lane_id" => "planning_p2",
        "section_cohort_id" => nil,
        "logical_role" => "planning_cdd",
        "reviewer" => {"owner" => "fixture-p1", "role" => "planning_cdd_p1", "lane_id" => "planning_p1"},
        "return_recipient" => {"owner" => "fixture-p1", "role" => "planning_cdd_p1", "return_route" => "planning_cdd_p1_exact_link"}
      },
      "planning_cdd_p3_ci" => {
        "lane_id" => "planning_p3_c1",
        "section_cohort_id" => "C1",
        "logical_role" => "planning_cdd",
        "reviewer" => {"owner" => "fixture-p1", "role" => "planning_cdd_p1", "lane_id" => "planning_p1"},
        "return_recipient" => {"owner" => "fixture-p1", "role" => "planning_cdd_p1", "return_route" => "planning_cdd_p1_exact_link"}
      },
      "section_cluster_cdd_ci" => {
        "lane_id" => "section_cluster_v_c1",
        "section_cohort_id" => "C1",
        "logical_role" => "section_cluster_cdd",
        "reviewer" => {"owner" => "fixture-overall", "role" => "overall_director", "lane_id" => "overall"},
        "return_recipient" => {"owner" => "fixture-overall", "role" => "overall_director", "return_route" => "overall_reviewed_milestone"}
      },
      "section_image_motion_worker" => {
        "lane_id" => "section_cluster_v_c1",
        "section_cohort_id" => "C1",
        "logical_role" => "section_image_motion_worker",
        "reviewer" => {
          "owner" => "fixture-cdd-v-c1",
          "role" => "creative_development_director",
          "lane_id" => "section_cluster_v_c1",
          "session_id" => "VC1_PRIMARY",
          "logical_lineage_id" => "VC1_LINEAGE"
        },
        "return_recipient" => {
          "owner" => "fixture-cdd-v-c1",
          "role" => "creative_development_director",
          "return_route" => "cohort_cdd_exact_byte_review"
        }
      },
      "edit_director" => {
        "lane_id" => "edit_director",
        "section_cohort_id" => nil,
        "logical_role" => "edit_director",
        "reviewer" => {"owner" => "fixture-overall", "role" => "overall_director", "lane_id" => "overall"},
        "return_recipient" => {"owner" => "fixture-overall", "role" => "overall_director", "return_route" => "overall_reviewed_milestone"}
      }
    }.fetch(profile_id)
    assigned_owner = profile_id
    dispatch = {
      "schema_version" => "idol-graph-department-dispatch.v1",
      "artifact_type" => "graph_department_dispatch",
      "dispatch_id" => assignment_id,
      "run" => "runs/fixture-title/fixture-album/FIXTURE_RUN",
      "lane_id" => role_contract.fetch("lane_id"),
      "section_cohort_id" => role_contract.fetch("section_cohort_id"),
      "section_ids" => section_ids,
      "logical_role" => role_contract.fetch("logical_role"),
      "assigned_owner" => assigned_owner,
      "output_writer" => {
        "owner" => assigned_owner,
        "role" => role_contract.fetch("logical_role"),
        "session_id" => "SESSION_#{profile_id.upcase}"
      },
      "reviewer" => role_contract.fetch("reviewer"),
      "return_recipient" => role_contract.fetch("return_recipient"),
      "input_digest_sha256" => Digest::SHA256.hexdigest(assignment_id),
      "lifecycle_state" => lifecycle_state
    }
    path = @root.join("work/graph-fixture/#{assignment_id.downcase}-#{lifecycle_state}-dispatch.yaml")
    path.dirname.mkpath
    path.write(YAML.dump(dispatch))
    source_envelope = {
      "kind" => "department_dispatch",
      "path" => path.relative_path_from(@root).to_s,
      "sha256" => Digest::SHA256.file(path).hexdigest
    }
    [source_envelope, role_contract.fetch("return_recipient")]
  end

  def graph_switch_receipt
    {
      "receipt_id" => "GRAPH_SWITCH_FIXTURE_001",
      "founder_authority" => "founder",
      "graph_revision" => "idol-graph-skill-load-profiles.v1",
      "switch_boundary" => "new_runs_only_after_verified_receipt",
      "source_set_sha256" => IdolRoleContextPack.graph_source_set_sha256(@root),
      "verified_at" => "2026-09-03T00:00:00+09:00"
    }
  end

  def refresh_pack_self_digests(pack)
    projection = pack.fetch("projection")
    instruction_content = pack.fetch("instruction_slices").map { |row| row["content"] }.compact.join("\n")
    projection["instruction_content_sha256"] = Digest::SHA256.hexdigest(instruction_content)
    source_set = {
      "projection_registry" => {"path" => projection.fetch("registry_path"), "sha256" => projection.fetch("registry_sha256")},
      "profile_registry" => {"path" => projection.fetch("profile_registry_path"), "sha256" => projection.fetch("profile_registry_sha256")},
      "source_envelope" => pack.fetch("source_envelope"),
      "instructions" => pack.fetch("instruction_slices").map do |row|
        row.slice("binding_id", "path", "whole_file_sha256", "locator", "fragment_sha256")
      end,
      "creative_sources" => pack.fetch("creative_source_pointers"),
      "founder_quality_context" => pack["founder_quality_context"],
      "provider" => pack.fetch("provider_binding").slice("provider", "provider_profile_id", "provider_source_sha256")
    }
    source_set["creative_judgment_contract"] = pack["creative_judgment_contract"] if pack.key?("creative_judgment_contract")
    source_set["graph_dispatch_identity"] = pack["graph_dispatch_identity"] if pack.key?("graph_dispatch_identity")
    source_set["activation_binding"] = pack["activation_binding"] if pack.key?("activation_binding")
    projection["source_set_sha256"] = IdolRoleContextPack.structured_sha256(source_set)
    projection["pack_digest"] = IdolRoleContextPack.structured_sha256(
      pack.reject { |key, _| key == "projection" }.merge(
        "projection" => projection.reject { |key, _| key == "pack_digest" }
      )
    )
  end

  def copy_graph_profile_closure
    registry_path = REAL_ROOT.join(IdolRoleContextPack::GRAPH_PROFILE_REGISTRY_RELATIVE)
    registry = YAML.safe_load(registry_path.read, aliases: true)
    routing = YAML.safe_load(REAL_ROOT.join(IdolRoleContextPack::GRAPH_ROUTING_REGISTRY_RELATIVE).read, aliases: true)
    paths = Array(registry["skill_bindings"]).map { |row| row.fetch("path") }
    paths.concat(Array(registry["read_bindings"]).map { |row| row.fetch("path") })
    paths.concat(Array(routing.dig("writer_boundary", "active_graph_surfaces")))
    paths.concat([
      IdolRoleContextPack::GRAPH_PROJECTION_REGISTRY_RELATIVE,
      IdolRoleContextPack::GRAPH_ROUTING_REGISTRY_RELATIVE,
      IdolRoleContextPack::PROVIDER_REGISTRY_RELATIVE,
      "scripts/idol-video-python",
      "scripts/validate_json_schema.py",
      "automation/providers/grok-build-profiles.yaml",
      "automation/providers/cursor-agent-profiles.yaml"
    ])
    judgment_registry = YAML.safe_load(REAL_ROOT.join(IdolRoleContextPack::GRAPH_JUDGMENT_REGISTRY_RELATIVE).read, aliases: true)
    paths << IdolRoleContextPack::GRAPH_JUDGMENT_PROFILE_RELEASE_SCHEMA_RELATIVE
    paths << IdolGraphJudgmentProfilePromotionContract::SCHEMA_RELATIVE
    paths << IdolGraphJudgmentProfilePromotionContract::VALIDATOR_RELATIVE
    paths.concat(judgment_registry.fetch("current_profile_releases").values.map { |row| row.fetch("path") })
    paths.concat(judgment_registry.fetch("current_profile_releases").values.map { |row| row.dig("promotion_binding", "path") })
    paths.uniq.each do |relative|
      destination = @root.join(relative)
      destination.dirname.mkpath
      FileUtils.cp(REAL_ROOT.join(relative), destination)
    end
    Array(registry["skill_bindings"]).each do |row|
      row["sha256"] = Digest::SHA256.file(@root.join(row.fetch("path"))).hexdigest
    end
    Array(registry["read_bindings"]).each do |row|
      row["sha256"] = Digest::SHA256.file(@root.join(row.fetch("path"))).hexdigest
    end
    @root.join(IdolRoleContextPack::GRAPH_PROFILE_REGISTRY_RELATIVE).write(YAML.dump(registry))
    refresh_copied_provider_hashes
  end

  def copy_profile_closure
    registry_path = REAL_ROOT.join(IdolRoleContextPack::PROFILE_REGISTRY_RELATIVE)
    registry = YAML.safe_load(registry_path.read, aliases: true)
    skill_map = Array(registry["skill_bindings"]).to_h { |row| [row.fetch("binding_id"), row] }
    read_map = Array(registry["read_bindings"]).to_h { |row| [row.fetch("binding_id"), row] }
    selected = PROFILE_CHECKPOINTS.map do |profile_id, checkpoint_id|
      profile = Array(registry["profiles"]).find { |row| row["profile_id"] == profile_id }
      checkpoint = Array(profile.dig("phase_load", "checkpoints")).find { |row| row["checkpoint_id"] == checkpoint_id }
      [profile, checkpoint]
    end
    skill_ids = selected.flat_map { |_profile, checkpoint| Array(checkpoint["required_skill_ids"]) }.uniq
    read_ids = selected.flat_map { |_profile, checkpoint| Array(checkpoint["required_read_ids"]) }.uniq
    paths = skill_ids.map { |id| skill_map.fetch(id).fetch("path") } + read_ids.map { |id| read_map.fetch(id).fetch("path") }
    paths.concat(
      [
        IdolRoleContextPack::PROJECTION_REGISTRY_RELATIVE,
        IdolRoleContextPack::PROVIDER_REGISTRY_RELATIVE,
        "automation/providers/grok-build-profiles.yaml",
        "automation/providers/cursor-agent-profiles.yaml"
      ]
    )
    paths.uniq.each do |relative|
      destination = @root.join(relative)
      destination.dirname.mkpath
      FileUtils.cp(REAL_ROOT.join(relative), destination)
    end
    Array(registry["skill_bindings"]).each do |row|
      row["sha256"] = Digest::SHA256.file(REAL_ROOT.join(row.fetch("path"))).hexdigest if skill_ids.include?(row["binding_id"])
    end
    Array(registry["read_bindings"]).each do |row|
      row["sha256"] = Digest::SHA256.file(REAL_ROOT.join(row.fetch("path"))).hexdigest if read_ids.include?(row["binding_id"])
    end
    destination = @root.join(IdolRoleContextPack::PROFILE_REGISTRY_RELATIVE)
    destination.dirname.mkpath
    destination.write(YAML.dump(registry))
    refresh_copied_provider_hashes
  end

  def assert_selected_reference_follow_slice(pack, heading, constitution_path)
    slices = Array(pack["instruction_slices"]).select { |row| row["path"] == constitution_path }
    headings = slices.map { |row| row.dig("locator", "heading") }
    assert_includes headings, heading, pack.dig("identity", "checkpoint_id")
    refute_includes headings, "Production Principle", pack.dig("identity", "checkpoint_id")
    slices.each do |row|
      refute_equal "whole_file", row.dig("locator", "type"), row["path"]
    end

    boundary = slices.find { |row| row.dig("locator", "heading") == heading }
    refute_nil boundary, pack.dig("identity", "checkpoint_id")
    source = @root.join(constitution_path).read
    extracted = IdolRoleContextPack.markdown_heading(source, heading, constitution_path)
    assert_equal extracted, boundary.fetch("content")
    content = boundary.fetch("content")
    semantic = content.gsub(/\s+/, " ")
    assert_includes semantic, "No general anti-copy rule"
    assert_includes semantic, "full_scene_direct"
    assert_includes semantic, "does not silently reopen every current-title bound reference"
    assert_includes semantic, "Preserve the current-song role, the original event"
    assert_includes semantic, "01 and 02A own still distance, angle, and framing"
    assert_includes semantic, "03V owns temporal camera movement, push-in, and speed"
    assert_includes semantic, "keep the original contact and emotional relationship readable"
    assert_includes semantic, "New camera variation alone never earns a new production cut"
    assert_includes semantic, "policies/examples/reference-method-examples.md"
    refute_includes semantic, "authorized 01/02A closer distance or angle"
    refute_includes semantic, "authorized 03V gentle push-in"
    refute_includes semantic, "hides the hand-object contact"
    refute_includes semantic, "Noncanonical examples, not scores"
    refute_includes Array(pack["instruction_slices"]).map { |row| row["path"] }, "policies/examples/reference-method-examples.md"
    examples = REAL_ROOT.join("policies/examples/reference-method-examples.md").read.gsub(/\s+/, " ")
    assert_includes examples, "authorized 01/02A closer distance or angle"
    assert_includes examples, "authorized 03V gentle push-in"
    assert_includes examples, "hides the hand-object contact"
    refute_includes semantic, "One strong song-backed creative spine"
    refute_includes semantic, "## Production Principle"
  end

  def cursor_source_sha256
    Digest::SHA256.file(@root.join("automation/providers/cursor-agent-profiles.yaml")).hexdigest
  end

  def grok_source_sha256
    Digest::SHA256.file(@root.join("automation/providers/grok-build-profiles.yaml")).hexdigest
  end

  def assert_pack_schema_valid(pack)
    Tempfile.create(["idol-role-context-pack", ".json"]) do |file|
      file.write(JSON.pretty_generate(pack))
      file.flush
      _stdout, stderr, status = Open3.capture3(PYTHON.to_s, VALIDATOR.to_s, SCHEMA.to_s, file.path, chdir: REAL_ROOT.to_s)
      assert status.success?, stderr
    end
  end

  def copy_source_hub_registration_closure
    registry_path = @root.join(IdolRoleContextPack::PROFILE_REGISTRY_RELATIVE)
    registry = YAML.safe_load(registry_path.read, aliases: true)
    profile = Array(registry["profiles"]).find { |row| row["profile_id"] == "source_hub_registration" }
    checkpoint = Array(profile.dig("phase_load", "checkpoints")).find { |row| row["checkpoint_id"] == "source_registration_and_reusable_analysis" }
    skill_map = Array(registry["skill_bindings"]).to_h { |row| [row.fetch("binding_id"), row] }
    read_map = Array(registry["read_bindings"]).to_h { |row| [row.fetch("binding_id"), row] }
    ids = Array(checkpoint["required_skill_ids"]) + Array(checkpoint["required_read_ids"])
    paths = ids.map { |id| (skill_map[id] || read_map[id]).fetch("path") }
    paths.uniq.each do |relative|
      destination = @root.join(relative)
      destination.dirname.mkpath
      FileUtils.cp(REAL_ROOT.join(relative), destination)
    end
    Array(registry["skill_bindings"]).each do |row|
      next unless ids.include?(row["binding_id"])
      row["sha256"] = Digest::SHA256.file(@root.join(row.fetch("path"))).hexdigest
    end
    Array(registry["read_bindings"]).each do |row|
      next unless ids.include?(row["binding_id"])
      row["sha256"] = Digest::SHA256.file(@root.join(row.fetch("path"))).hexdigest
    end
    registry_path.write(YAML.dump(registry))
  end

  def copy_harness_maintenance_wiki
    %w[
      wiki/harness-maintenance-rules.md
      wiki/harness-maintenance/skill-profile-routing.md
    ].each do |relative|
      destination = @root.join(relative)
      destination.dirname.mkpath
      FileUtils.cp(REAL_ROOT.join(relative), destination)
    end
  end

  def refresh_copied_provider_hashes
    registry_path = @root.join(IdolRoleContextPack::PROVIDER_REGISTRY_RELATIVE)
    return unless registry_path.file?

    text = registry_path.read
    registry = YAML.safe_load(text, aliases: true)
    replacements = {}
    profiles = registry["logical_profiles"]
    return unless profiles.is_a?(Hash)

    profiles.each_value do |profile|
      next unless profile.is_a?(Hash)

      providers = profile["providers"]
      next unless providers.is_a?(Hash)

      providers.each_value do |row|
        next unless row.is_a?(Hash)

        source = row["source_path"].to_s
        next if source.empty? || !@root.join(source).file?

        replacements[row["source_sha256"].to_s] = Digest::SHA256.file(@root.join(source)).hexdigest
      end
    end
    replacements.each do |old, actual|
      next if old.empty? || old == actual

      text = text.gsub(old, actual)
    end
    registry_path.write(text)
  end
end
