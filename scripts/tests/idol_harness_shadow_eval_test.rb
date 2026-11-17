# frozen_string_literal: true

require "json"
require "digest"
require "fileutils"
require "minitest/autorun"
require "open3"
require "pathname"
require "tmpdir"
require "yaml"

class IdolHarnessShadowEvalTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  SCRIPT = ROOT.join("scripts", "idol_harness_shadow_eval.rb")

  def test_policy_exposes_provider_registry_adaptive_runtime
    payload = policy
    routing = payload.fetch("routing_policy")
    assert_equal "provider_registry_adaptive_runtime_v31", routing["policy_id"]
    assert_equal "provider_registry_logical_aliases_v31", routing.dig("effort_policy", "mode")
    assert_equal false, routing.dig("agent_governance", "standing_final_director_allowed")
    assert_equal "default", routing.dig("agent_governance", "provider_native_helper_availability")
    assert_equal "none", routing.dig("agent_governance", "project_numeric_gate")
    assert_equal "none", routing.dig("agent_governance", "depth_gate")
    assert_equal "adaptive_registered_assignment", routing.dig("agent_governance", "physical_session_selection")
    assert_equal "idol_sol_creative_development_director", routing.dig("agent_governance", "codex_role_adapters", "creative_development_director", "standard")
    assert_equal "idol_luna_studio_department", routing.dig("agent_governance", "codex_role_adapters", "department_worker", "standard")
    assert_equal true, routing.dig("agent_governance", "grok_role_adapters", "same_dispatch_contract_as_codex")
    assert_equal false, routing.dig("agent_governance", "grok_role_adapters", "creative_contract_rewrite_allowed")
    suite = YAML.safe_load(ROOT.join("automation", "harness-shadow-eval-suite.yaml").read, aliases: true)
    selection_basis = suite.dig("operator_profile_policy", "selection_basis")
    assert_includes selection_basis, "Provider capacity supplies backpressure, never a launch quota"
    refute_includes selection_basis, "no more than three Luna sessions active"
    refute_includes selection_basis, "no more than four Luna sessions"
    departments = suite.dig("operator_profile_policy", "routing_policy", "routing_continuity_contract", "luna_department_contract")
    assert_equal "adaptive_named_gap_assignments_no_fixed_worker_or_source_count", departments.fetch("reference_assignment_policy")
    assert_equal "adaptive_to_professional_decision_readiness", departments.dig("reference_generalist_assignments", "primary_source_count")
    assert_equal "adaptive_to_disjoint_named_gaps_under_capacity_and_backpressure", departments.dig("world_still_assignments", "cardinality")
    assert_equal({"minimum" => 2, "ordinary_maximum" => 4, "reviewed_exception_maximum" => 5}, departments.fetch("development_blocks"))
    assert_equal 14, departments.fetch("maximum_active_sessions")
    refute departments.key?("reference_generalist_sessions")
    refute departments.key?("world_still_sessions")
    refute departments.key?("fifth_reference_group_allowed")
    visual = suite.dig("operator_profile_policy", "routing_policy", "agent_governance", "grok_worker_session_governance", "visual_analysis")
    assert_equal "adaptive_to_named_unresolved_observation_leaves_and_material_disagreement", visual.fetch("assignment_policy")
    assert_equal "smallest_role_set_needed_for_professional_decision_readiness", visual.fetch("reader_selection_policy")
    refute visual.key?("default_independent_inspectors")
    refute visual.key?("risk_triggered_recommended_inspectors")
    refute visual.key?("expansion_cap")
    refute visual.key?("same_image_reader_cap")
    goal_admission = suite.dig("operator_profile_policy", "routing_policy", "agent_governance", "grok_worker_session_governance", "goal_admission")
    assert_equal %w[interactive_tui_slash_goal acp_matching_native_goal_event], goal_admission.fetch("admissible_surfaces")
    assert_equal true, goal_admission.fetch("objective_match_required")
    assert_equal "forbidden", goal_admission.fetch("headless_without_matching_native_goal_event")
    assert_equal "hold_zero_work_zero_output", goal_admission.fetch("goal_surface_unavailable_action")
    peer_headless = suite.dig("operator_profile_policy", "routing_policy", "agent_governance", "grok_worker_session_governance", "peer_headless_sessions")
    assert_equal "matching_acp_native_goal_event", peer_headless.fetch("admission_requires")
    assert_equal "hold_zero_work_zero_output", peer_headless.fetch("goal_surface_unavailable_action")

    continuity = suite.dig("operator_profile_policy", "routing_policy", "routing_continuity_contract")
    section_lifecycle = continuity.fetch("luna_section_lifecycle_contract")
    assert_equal 14, section_lifecycle.fetch("ordinary_maximum_live_sections")
    assert_equal 14, section_lifecycle.fetch("reviewed_maximum_live_sections")
    assert_equal true, section_lifecycle.fetch("provider_lower_capacity_takes_precedence")
    capacity = continuity.fetch("capacity_and_backpressure_contract")
    assert_equal({"ordinary" => 8, "reviewed_maximum" => 8}, capacity.fetch("grok_nonroot_workers"))
    assert_equal({"ordinary" => 6, "reviewed_maximum" => 6}, capacity.fetch("cursor_nonroot_workers"))
    assert_equal({"ordinary" => 14, "reviewed_maximum" => 14}, capacity.fetch("combined_creative_workers"))
    assert_equal true, capacity.fetch("lower_provider_runtime_cap_wins")
    assert_equal true, capacity.fetch("pause_when_director_review_waits")
    assert_equal false, capacity.fetch("free_slot_requires_launch")

    edit_contract = suite.dig("operator_profile_policy", "routing_policy", "routing_continuity_contract", "edit_qc_04_execution_contract")
    assert_equal "idol_sol_edit_director", edit_contract.fetch("edit_director_agent_name")
    assert_equal "idol_luna_studio_department", edit_contract.fetch("edit_shard_agent_name")
    governance = suite.dig("operator_profile_policy", "routing_policy", "agent_governance")
    assert_includes governance.fetch("canonical_write_exception_agent_names"), "idol_sol_edit_director"
    assert_includes governance.fetch("canonical_write_exception_paths"), "runs/ALBUM_KEY/TITLE_KEY/RUN_ID/04-edit-map.yaml"
    refute_includes governance.fetch("canonical_write_exception_paths"), "runs/ALBUM_KEY/TITLE_KEY/RUN_ID/05-package.yaml"

    mv_director = ROOT.join("skills", "idol-mv-director", "SKILL.md").read
    assert_includes mv_director, "run-resolved provider snapshot"
    refute_includes mv_director, "at most three Luna/Max sessions"
    refute_includes mv_director, "No more than four Luna/Max development sessions"

    acceptance = ROOT.join("scripts", "idol_harness_optimization_acceptance.rb").read
    assert_equal 1, acceptance.scan("run: -> { validate_current_routing }").length
    refute_includes acceptance, "next validate_current_routing"
    refute_includes acceptance, "def validate_v19_routing"
    refute_includes acceptance, "founder_only_ultra_v17"
  end

  def test_policy_rejects_edit_director_without_exact_physical_write_exception
    base = YAML.safe_load(ROOT.join("automation", "harness-shadow-eval-suite.yaml").read, aliases: true)
    mutations = {
      "missing-agent" => lambda do |suite|
        suite.dig("operator_profile_policy", "routing_policy", "agent_governance", "canonical_write_exception_agent_names").delete("idol_sol_edit_director")
      end,
      "missing-path" => lambda do |suite|
        suite.dig("operator_profile_policy", "routing_policy", "agent_governance", "canonical_write_exception_paths").delete("runs/ALBUM_KEY/TITLE_KEY/RUN_ID/04-edit-map.yaml")
      end,
      "illegal-05-package" => lambda do |suite|
        suite.dig("operator_profile_policy", "routing_policy", "agent_governance", "canonical_write_exception_paths") << "runs/ALBUM_KEY/TITLE_KEY/RUN_ID/05-package.yaml"
      end
    }

    Dir.mktmpdir("idol-shadow-suite-", "/private/tmp") do |directory|
      mutations.each do |label, mutate|
        suite = Marshal.load(Marshal.dump(base))
        mutate.call(suite)
        suite_path = Pathname.new(directory).join("#{label}.yaml")
        suite_path.write(YAML.dump(suite))
        _stdout, stderr, status = Open3.capture3(
          "ruby", SCRIPT.to_s, "policy", "--suite", suite_path.to_s, "--json", chdir: ROOT.to_s
        )
        refute status.success?, label
        assert_includes stderr, "Edit Director physical canonical-write authority must include", label
      end
    end
  end

  def test_policy_rejects_headless_grok_without_matching_native_goal
    base = YAML.safe_load(ROOT.join("automation", "harness-shadow-eval-suite.yaml").read, aliases: true)
    governance = base.dig("operator_profile_policy", "routing_policy", "agent_governance", "grok_worker_session_governance")
    governance.fetch("goal_admission")["headless_without_matching_native_goal_event"] = "allowed"
    governance.fetch("peer_headless_sessions").delete("admission_requires")

    Dir.mktmpdir("idol-shadow-suite-", "/private/tmp") do |directory|
      suite_path = Pathname.new(directory).join("headless-without-goal.yaml")
      suite_path.write(YAML.dump(base))
      _stdout, stderr, status = Open3.capture3(
        "ruby", SCRIPT.to_s, "policy", "--suite", suite_path.to_s, "--json", chdir: ROOT.to_s
      )
      refute status.success?
      assert_includes stderr, "HOLD with zero work/output"
      assert_includes stderr, "matching ACP native Goal before work"
    end
  end

  def test_ordinary_routes_never_use_terra
    routes = policy.dig("routing_policy", "route_classes")
    routes.each do |route|
      next if route["route_id"] == "weekly_visual_idol_research"
      descriptors = [route["default_route"], *Array(route["explicit_alternatives"])]
      refute descriptors.any? { |row| row["model_id"] == "gpt-5.6-terra" }, route["route_id"]
    end
    weekly = routes.find { |row| row["route_id"] == "weekly_visual_idol_research" }
    assert_equal "idol_luna_studio_department", weekly.dig("default_route", "agent_name")
    assert_equal "max", weekly.dig("default_route", "model_reasoning_effort")
  end

  def test_overall_is_xhigh_and_max_is_advisory_only
    default = route("creative_core_and_founder_direction", "stage_execution")
    assert_equal "idol_sol_creative_synthesis", default.dig("selected_route", "agent_name")
    _stdout, stderr, status = Open3.capture3(
      "ruby", SCRIPT.to_s, "route", "creative_core_and_founder_direction",
      "--execution-scope", "stage_execution", "--select-agent",
      "idol_sol_primary_validation", "--json", chdir: ROOT.to_s
    )
    refute status.success?
    assert_includes stderr, "not registered for route creative_core_and_founder_direction"
    advisory = route("high_stakes_repair_and_final_qc", "stage_execution")
    assert_equal "idol_sol_primary_validation", advisory.dig("selected_route", "agent_name")
    assert_equal "advisory_to_overall_director", advisory.dig("route_class", "output_authority")
  end

  def test_cdd_department_development_and_post02a_routes
    expected = {
      "creative_development_direction" => ["idol_sol_creative_development_director", "advisory_development_report_to_overall_director"],
      "physical_song_room" => ["idol_luna_studio_department", "bounded_song_package_to_cdd_only"],
      "media_research_department" => ["idol_luna_studio_department", "bounded_decision_set_only"],
      "member_visual_identity" => ["idol_luna_studio_department", "bounded_identity_candidates_to_cdd_only"],
      "development_block" => ["idol_luna_studio_department", "noncanonical_pre02a_section_shards"],
      "physical_section_shard" => ["idol_luna_section_image_motion", "section_image_motion_outputs_and_handoff_only"],
      "edit_director" => ["idol_sol_edit_director", "reviewed_edit_merge_to_overall_only"],
      "edit_shard" => ["idol_luna_studio_department", "noncanonical_edit_shard_only"]
    }
    expected.each do |route_id, (agent, authority)|
      payload = route(route_id, "stage_execution")
      assert_equal agent, payload.dig("selected_route", "agent_name")
      assert_equal authority, payload.dig("route_class", "output_authority")
      assert_equal "max", payload.dig("selected_route", "model_reasoning_effort") if agent.start_with?("idol_luna_")
    end
    section = route("physical_section_shard", "stage_execution").fetch("route_class")
    assert_equal "worker_high", section["logical_profile_alias"]
    assert_equal "section_image_motion_worker", section["logical_role"]
    assert_equal "exact_run_snapshot_no_fallback", section["provider_resolution"]
    assert_equal "idol_luna_section_image_motion", section["codex_physical_realization"]
    assert_equal "grok_worker_high", section["grok_physical_realization"]
    assert_equal true, section["provider_native_media_tools_must_remain_distinct"]
  end

  def test_max_review_is_advisory_and_result_schema_uses_v19_effort_policy
    review = route("high_stakes_repair_and_final_qc", "stage_execution")
    assert_equal "advisory_to_overall_director", review.dig("route_class", "output_authority")
    assert_equal true, review.dig("route_class", "owner_review_required_for_canonical_write")
    schema = JSON.parse(ROOT.join("schemas", "harness-shadow-eval-result.schema.json").read)
    assert_equal "overall_cdd_luna_studio_post02a_section", schema.dig("$defs", "profileDescriptor", "properties", "effort_policy", "const")
  end

  def test_named_offline_route_shadows_emit_separate_zero_action_results
    grok = route_shadow("grok_only_pre00_to_05")
    assert_equal "pass", grok["status"]
    assert_equal "eligible_for_founder_default_switch_review", grok["activation_status"]
    assert_equal true, grok["founder_default_switch_review_allowed"]
    assert_equal "grok", grok["provider_lane"]
    assert_equal true, grok.dig("resolved_profiles", "director_deep", "full_owner_ready")
    assert_equal "active", grok.dig("resolved_profiles", "director_deep", "harness_status")
    assert_equal true, grok.dig("resolved_profiles", "worker_high", "full_owner_ready")
    assert_equal "active", grok.dig("resolved_profiles", "worker_high", "harness_status")
    assert_equal %w[director_deep worker_high], grok["ready_logical_aliases"]
    assert_empty grok["held_logical_aliases"]
    assert_nil grok.dig("registered_media_lane", "harness_status")
    assert_equal false, grok.dig("registered_media_lane", "promoted_by_nonmedia_activation")
    assert_equal 0, grok["codex_fallback_count"]

    cursor = route_shadow("cursor_reference_pre00_to_05")
    assert_equal "pass", cursor["status"]
    assert_equal "eligible_for_founder_default_switch_review", cursor["activation_status"]
    assert_equal true, cursor["founder_default_switch_review_allowed"]
    assert_equal "cursor", cursor["provider_lane"]
    assert_equal true, cursor.dig("resolved_profiles", "director_deep", "full_owner_ready")
    assert_equal %w[director_deep worker_high], cursor["ready_logical_aliases"]
    assert_empty cursor["held_logical_aliases"]

    [grok, cursor].each do |payload|
      assert_equal "offline_deterministic_dry_run", payload["mode"]
      assert_equal 19, payload.fetch("stages").length
      refute_includes payload.fetch("nonmedia_provider_stages"), "branch_cut_generation"
      assert_includes payload.fetch("nonmedia_provider_stages"), "video_motion_direction"
      assert_equal %w[02b_image_generation_execution 03v_video_generation_execution_only],
                   payload.fetch("registered_media_generation_handoffs").map { |row| row.fetch("action_scope") }
      assert payload.fetch("registered_media_generation_handoffs").all? { |row| row["nonmedia_provider_ownership"] == false }
      assert_equal 0, payload["live_model_call_count"]
      assert_equal 0, payload["external_action_count"]
      assert_equal 0, payload["generative_action_count"]
      assert_equal 0, payload["unauthorized_media_generation_count"]
      assert_equal 2, payload["registered_media_handoff_count"]
    end
  end

  def test_runtime_route_shadow_rejects_optimistic_default_switch_over_held_director
    Dir.mktmpdir("idol-shadow-suite-", ROOT.to_s) do |directory|
      suite_path = Pathname.new(directory).join("suite.yaml")
      suite = YAML.safe_load(ROOT.join("automation", "harness-shadow-eval-suite.yaml").read, aliases: true)
      grok = suite.dig("runtime_route_shadow", "offline_fixtures").find { |row| row["fixture_id"] == "grok_only_pre00_to_05" }
      grok["provider_lane"] = "codex"
      grok["founder_default_switch_review_allowed_expected"] = true
      suite_path.write(YAML.dump(suite))

      _stdout, stderr, status = Open3.capture3(
        "ruby", SCRIPT.to_s, "policy", "--suite", suite_path.to_s, "--json", chdir: ROOT.to_s
      )
      refute status.success?
      assert_includes stderr, "Founder default-switch review expectation bypasses a held profile"
    end
  end

  def test_runtime_route_shadow_rejects_media_generation_as_nonmedia_provider_ownership
    Dir.mktmpdir("idol-shadow-suite-", ROOT.to_s) do |directory|
      suite_path = Pathname.new(directory).join("suite.yaml")
      suite = YAML.safe_load(ROOT.join("automation", "harness-shadow-eval-suite.yaml").read, aliases: true)
      suite.dig("runtime_route_shadow", "registered_media_generation_handoffs", 0)["nonmedia_provider_ownership"] = true
      suite_path.write(YAML.dump(suite))

      _stdout, stderr, status = Open3.capture3(
        "ruby", SCRIPT.to_s, "policy", "--suite", suite_path.to_s, "--json", chdir: ROOT.to_s
      )
      refute status.success?
      assert_includes stderr, "must exact-bind the existing 02B image and 03V video generation handoffs"
    end
  end

  def test_runtime_route_shadow_rejects_branch_cut_generation_in_nonmedia_provider_scope
    Dir.mktmpdir("idol-shadow-suite-", ROOT.to_s) do |directory|
      suite_path = Pathname.new(directory).join("suite.yaml")
      suite = YAML.safe_load(ROOT.join("automation", "harness-shadow-eval-suite.yaml").read, aliases: true)
      grok = suite.dig("runtime_route_shadow", "offline_fixtures").find { |row| row["fixture_id"] == "grok_only_pre00_to_05" }
      grok.fetch("nonmedia_provider_stages").insert(11, "branch_cut_generation")
      suite_path.write(YAML.dump(suite))

      _stdout, stderr, status = Open3.capture3(
        "ruby", SCRIPT.to_s, "policy", "--suite", suite_path.to_s, "--json", chdir: ROOT.to_s
      )
      refute status.success?
      assert_includes stderr, "nonmedia provider stages must exclude 02B image generation"
    end
  end

  def test_read_only_closeout_preserves_canonical_hashes_and_downstream_absence
    with_closeout_fixture do |run_root|
      output = run_root.join("work", "harness-maintenance", "v19-shadow-closeout-v1.yaml")
      inputs = canonical_inputs(run_root)
      before = inputs.to_h { |path| [path.to_s, Digest::SHA256.file(path).hexdigest] }

      stdout, stderr, status = Open3.capture3(
        "ruby", SCRIPT.to_s, "closeout",
        "--run-root", run_root.to_s,
        "--output", output.to_s,
        "--json",
        chdir: ROOT.to_s
      )
      assert status.success?, stderr
      payload = JSON.parse(stdout)
      assert_equal "complete", payload["status"]
      assert_equal "founder_review", payload["front_planning_status"]
      assert_equal false, payload["downstream_01_opened"]
      assert_equal false, payload["downstream_02a_opened"]
      assert_equal before, inputs.to_h { |path| [path.to_s, Digest::SHA256.file(path).hexdigest] }

      validation_stdout, validation_stderr, validation_status = Open3.capture3(
        "ruby", SCRIPT.to_s, "validate-closeout", output.to_s, "--json",
        chdir: ROOT.to_s
      )
      assert validation_status.success?, validation_stderr
      assert_equal "pass", JSON.parse(validation_stdout)["status"]

      evidence = YAML.safe_load(output.read, aliases: true)
      assert_equal false, evidence.dig("routing_contract", "comparison_performed")
      assert_equal false, evidence.dig("routing_contract", "model_execution_performed")
      assert_equal false, evidence.dig("canonical_state", "promotion_or_authorization_performed")
      assert_equal false, evidence.dig("boundary", "may_open_01_or_02a")
    end
  end

  def test_read_only_closeout_refuses_passed_front_planning_or_open_downstream
    with_closeout_fixture do |run_root|
      output = run_root.join("work", "harness-maintenance", "v19-shadow-closeout-v1.yaml")
      readiness_path = run_root.join("research", "front-planning-readiness-v12.yaml")
      readiness = YAML.safe_load(readiness_path.read)
      readiness["status"] = "pass"
      readiness_path.write(YAML.dump(readiness))

      _stdout, stderr, status = Open3.capture3(
        "ruby", SCRIPT.to_s, "closeout",
        "--run-root", run_root.to_s,
        "--output", output.to_s,
        chdir: ROOT.to_s
      )
      refute status.success?
      assert_includes stderr, "must remain founder_review"
      refute output.exist?
    end

    with_closeout_fixture do |run_root|
      output = run_root.join("work", "harness-maintenance", "v19-shadow-closeout-v1.yaml")
      run_root.join("01-song-choreography-performance-mv-map.yaml").write("---\nstatus: draft\n")

      _stdout, stderr, status = Open3.capture3(
        "ruby", SCRIPT.to_s, "closeout",
        "--run-root", run_root.to_s,
        "--output", output.to_s,
        chdir: ROOT.to_s
      )
      refute status.success?
      assert_includes stderr, "downstream 01 is already open"
      refute output.exist?
    end
  end

  private

  def policy
    @policy ||= begin
      stdout, stderr, status = Open3.capture3("ruby", SCRIPT.to_s, "policy", "--json", chdir: ROOT.to_s)
      assert status.success?, stderr
      JSON.parse(stdout)
    end
  end

  def route(route_id, scope, *extra)
    stdout, stderr, status = Open3.capture3("ruby", SCRIPT.to_s, "route", route_id, "--execution-scope", scope, *extra, "--json", chdir: ROOT.to_s)
    assert status.success?, stderr
    JSON.parse(stdout)
  end

  def route_shadow(fixture_id)
    stdout, stderr, status = Open3.capture3(
      "ruby", SCRIPT.to_s, "route-shadow", fixture_id, "--json", chdir: ROOT.to_s
    )
    assert status.success?, stderr
    JSON.parse(stdout)
  end

  def with_closeout_fixture
    Dir.mktmpdir("idol-shadow-closeout-", ROOT.to_s) do |directory|
      run_root = Pathname.new(directory)
      run_relative = run_root.relative_path_from(ROOT).to_s
      write_yaml(
        run_root.join("run-manifest.yaml"),
        "schema_version" => "idol-run-manifest.v1",
        "status" => "active",
        "run_id" => "TEST_SU",
        "canonical_run_root" => run_relative
      )
      write_yaml(
        run_root.join("research", "front-planning-readiness-v12.yaml"),
        "schema_version" => "front-planning-readiness.v17",
        "content_id" => "TEST_SU",
        "status" => "founder_review"
      )
      write_yaml(
        run_root.join("review", "manifests", "front-planning-reauthor-v3.yaml"),
        "schema_version" => "idol-html-review-board.v12",
        "board" => {"status" => "founder_review"},
        "sections" => [{"section_id" => "WHOLE_FILM", "status" => "founder_review"}]
      )
      FileUtils.mkdir_p(run_root.join("work", "harness-maintenance"))
      yield run_root
    end
  end

  def write_yaml(path, payload)
    FileUtils.mkdir_p(path.dirname)
    path.write(YAML.dump(payload))
  end

  def canonical_inputs(run_root)
    [
      run_root.join("research", "front-planning-readiness-v12.yaml"),
      run_root.join("review", "manifests", "front-planning-reauthor-v3.yaml"),
      run_root.join("run-manifest.yaml")
    ]
  end
end
