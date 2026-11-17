# frozen_string_literal: true

require "json"
require "digest"
require "minitest/autorun"
require "open3"
require "pathname"
require "tmpdir"
require "yaml"
require_relative "../lib/idol_role_context_pack"

class ValidateGraphDirectorLineageTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  VALIDATOR = ROOT.join("scripts", "validate_graph_director_lineage.rb")
  FIXTURES = ROOT.join("scripts", "tests", "fixtures", "graph-authority")

  def test_active_promotion_rejects_synthetic_fixture_goal_evidence
    _stdout, stderr, status = validate(
      FIXTURES.join("valid-department-dispatch-worker.json"),
      validation_mode: "active_promotion"
    )
    refute status.success?
    assert_includes stderr, "active promotion requires provider_native_terminal_event"
  end

  def test_test_boundary_rejects_document_outside_fixture_root
    Dir.mktmpdir("idol-graph-lineage-outside-") do |directory|
      path = Pathname.new(directory).join("document.json")
      path.write(JSON.pretty_generate(load_fixture("valid-department-dispatch-worker.json")) + "\n")
      _stdout, stderr, status = validate(path, validation_mode: "test_boundary")
      refute status.success?
      assert_includes stderr, "test_boundary is restricted to documents under scripts/tests/fixtures"
    end
  end

  def test_valid_planning_lineage_passes
    stdout, stderr, status = validate(FIXTURES.join("valid-lineage-planning.json"))
    assert status.success?, [stdout, stderr].join("\n")
    assert_includes stdout, "graph-director-lineage: pass"

    document = load_fixture("valid-lineage-planning.json")
    active_p3 = document.fetch("lanes").select do |lane|
      lane.fetch("lane_id").start_with?("planning_p3_c") &&
        lane.dig("succession", "authority_state") == "primary_active"
    end
    assert_equal %w[planning_p3_c1 planning_p3_c2], active_p3.map { |lane| lane.fetch("lane_id") }
    p2_and_p3 = document.fetch("lanes").select { |lane| lane["lane_id"] == "planning_p2" || lane["lane_id"].start_with?("planning_p3_c") }
    assert p2_and_p3.all? { |lane| lane.dig("return_recipient", "role") == "planning_cdd_p1" }
    assert p2_and_p3.all? { |lane| lane.dig("return_recipient", "return_route") == "planning_cdd_p1_exact_link" }
  end

  def test_valid_production_lineage_passes
    stdout, stderr, status = validate(FIXTURES.join("valid-lineage-production.json"))
    assert status.success?, [stdout, stderr].join("\n")
    assert_includes stdout, "graph-director-lineage: pass"

    document = load_fixture("valid-lineage-production.json")
    active_v = document.fetch("lanes").select do |lane|
      lane.fetch("lane_id").start_with?("section_cluster_v_c") &&
        lane.dig("succession", "authority_state") == "primary_active"
    end
    assert_equal %w[section_cluster_v_c1 section_cluster_v_c2], active_v.map { |lane| lane.fetch("lane_id") }
  end

  def test_successor_preflight_is_read_only_while_primary_remains_writer
    document = load_fixture("valid-lineage-planning.json")
    p2 = document.fetch("lanes").find { |lane| lane["lane_id"] == "planning_p2" }
    p2.fetch("physical_sessions") << {
      "generation" => "successor",
      "session_id" => "P2_SUCCESSOR",
      "state" => "zero_turn_read_only_preflight",
      "opened_at" => "2026-09-03T01:00:00Z"
    }
    p2.fetch("succession")["successor_session_id"] = "P2_SUCCESSOR"
    p2.fetch("succession")["authority_state"] = "successor_preflight"

    stdout, stderr, status = validate_document(document)
    assert status.success?, [stdout, stderr].join("\n")
  end

  def test_rejects_successor_writer_before_cas
    document = load_fixture("valid-lineage-planning.json")
    p2 = document.fetch("lanes").find { |lane| lane["lane_id"] == "planning_p2" }
    p2.fetch("physical_sessions") << {
      "generation" => "successor",
      "session_id" => "P2_SUCCESSOR",
      "state" => "active_single_writer",
      "opened_at" => "2026-09-03T01:00:00Z"
    }
    p2.fetch("succession")["successor_session_id"] = "P2_SUCCESSOR"
    p2.fetch("succession")["authority_state"] = "successor_preflight"

    _stdout, stderr, status = validate_document(document)
    refute status.success?
    assert_match(/zero-turn read-only before CAS|must have exactly one active writer/, stderr)
  end

  def test_valid_worker_and_cdd_dispatches_pass
    %w[valid-department-dispatch-worker.json valid-department-dispatch-cdd.json valid-department-dispatch-planning-p2.json].each do |name|
      stdout, stderr, status = validate(FIXTURES.join(name))
      assert status.success?, [name, stdout, stderr].join("\n")
      assert_includes stdout, "graph-director-lineage: pass"
    end
  end

  def test_rejects_two_logical_overall_directors
    document = load_fixture("valid-lineage-planning.json")
    clone = Marshal.load(Marshal.dump(document.fetch("lanes").first))
    clone["lane_id"] = "overall"
    clone["active_writer_session_id"] = "OVERALL_SECOND"
    clone["physical_sessions"][0]["session_id"] = "OVERALL_SECOND"
    clone["succession"]["source_session_id"] = "OVERALL_SECOND"
    clone["succession"]["active_writer_session_id"] = "OVERALL_SECOND"
    document.fetch("lanes") << clone
    _stdout, stderr, status = validate_document(document)
    refute status.success?
    assert_includes stderr, "exactly one logical Overall Director is required"
  end

  def test_rejects_two_active_writers_on_one_lane
    document = load_fixture("valid-lineage-planning.json")
    p2 = document.fetch("lanes").find { |lane| lane["lane_id"] == "planning_p2" }
    p2.fetch("physical_sessions") << {
      "generation" => "successor",
      "session_id" => "P2_SUCCESSOR",
      "state" => "active_single_writer",
      "opened_at" => "2026-09-03T01:00:00Z"
    }
    p2["succession"]["successor_session_id"] = "P2_SUCCESSOR"
    _stdout, stderr, status = validate_document(document)
    refute status.success?
    assert_includes stderr, "must have exactly one active writer"
  end

  def test_schema_rejects_third_physical_session
    document = load_fixture("valid-lineage-planning.json")
    p2 = document.fetch("lanes").find { |lane| lane["lane_id"] == "planning_p2" }
    p2.fetch("physical_sessions") << {
      "generation" => "successor",
      "session_id" => "P2_SUCCESSOR",
      "state" => "zero_turn_read_only_preflight",
      "opened_at" => "2026-09-03T01:00:00Z"
    }
    p2.fetch("physical_sessions") << {
      "generation" => "successor",
      "session_id" => "P2_THIRD",
      "state" => "zero_turn_read_only_preflight",
      "opened_at" => "2026-09-03T02:00:00Z"
    }
    _stdout, stderr, status = validate_document(document)
    refute status.success?
    assert_match(/too long|maximum two|third Director session/i, stderr)
  end

  def test_rejects_overlapping_planning_write_scopes
    document = load_fixture("valid-lineage-planning.json")
    p2 = document.fetch("lanes").find { |lane| lane["lane_id"] == "planning_p2" }
    p2.fetch("write_scopes") << {
      "field_id" => "storyline_descendant",
      "scope_kind" => "whole_film",
      "section_ids" => []
    }
    _stdout, stderr, status = validate_document(document)
    refute status.success?
    assert_includes stderr, "P1/P2/P3-Ci write scopes overlap"
  end

  def test_rejects_p2_as_integration_writer
    document = load_fixture("valid-lineage-planning.json")
    p2 = document.fetch("lanes").find { |lane| lane["lane_id"] == "planning_p2" }
    p2["integration_writer"] = true
    _stdout, stderr, status = validate_document(document)
    refute status.success?
    assert_includes stderr, "only planning_p1 may be the planning integration writer"
  end

  def test_rejects_missing_p3_to_v_carry
    document = load_fixture("valid-lineage-production.json")
    document["lanes"].reject! { |lane| lane["lane_id"] == "section_cluster_v_c2" }
    _stdout, stderr, status = validate_document(document)
    refute status.success?
    assert_includes stderr, "P3-Ci to V-Ci cohort carry is missing or inexact"
  end

  def test_planning_provisional_requires_p1_and_p2
    %w[planning_p1 planning_p2].each do |missing_lane|
      document = load_fixture("valid-lineage-planning.json")
      document.fetch("lanes").reject! { |lane| lane["lane_id"] == missing_lane }
      _stdout, stderr, status = validate_document(document)
      refute status.success?
      assert_includes stderr, "planning_provisional requires #{missing_lane}"
    end
  end

  def test_planning_cohort_map_readiness_requires_each_p3_lane
    document = load_fixture("valid-lineage-planning.json")
    map_path = FIXTURES.join("valid-cohort-map-4.json")
    document["section_cohort_map"] = {
      "path" => map_path.relative_path_from(ROOT).to_s,
      "sha256" => Digest::SHA256.file(map_path).hexdigest
    }
    document.fetch("lanes").reject! { |lane| lane["lane_id"] == "planning_p3_c2" }
    _stdout, stderr, status = validate_document(document)
    refute status.success?
    assert_includes stderr, "cohort readiness requires one exact P3-Ci lane per section cohort"
  end

  def test_production_requires_p1_p2_and_at_least_one_exact_p3_v_pair
    {
      "planning_p1" => "production_active requires planning_p1",
      "planning_p2" => "production_active requires planning_p2"
    }.each do |missing_lane, message|
      document = load_fixture("valid-lineage-production.json")
      document.fetch("lanes").reject! { |lane| lane["lane_id"] == missing_lane }
      _stdout, stderr, status = validate_document(document)
      refute status.success?
      assert_includes stderr, message
    end

    document = load_fixture("valid-lineage-production.json")
    document.fetch("lanes").reject! { |lane| lane["lane_id"].start_with?("planning_p3_c", "section_cluster_v_c") }
    _stdout, stderr, status = validate_document(document)
    refute status.success?
    assert_includes stderr, "production_active requires the retired P3-Ci cohort lanes"
    assert_includes stderr, "production_active requires one V-Ci production lane per P3-Ci cohort"
  end

  def test_schema_rejects_provider_fallback
    document = load_fixture("valid-lineage-planning.json")
    document.fetch("provider_policy")["fallback_allowed"] = true
    _stdout, stderr, status = validate_document(document)
    refute status.success?
    assert_match(/fallback|const/i, stderr)
  end

  def test_rejects_director_lane_without_frontier_profile
    document = load_fixture("valid-lineage-planning.json")
    p2 = document.fetch("lanes").find { |lane| lane["lane_id"] == "planning_p2" }
    p2.fetch("provider_binding")["logical_profile_alias"] = "worker_high"
    _stdout, stderr, status = validate_document(document)
    refute status.success?
    assert_includes stderr, "director lane must resolve frontier_director with no fallback"
  end

  def test_rejects_direct_codex_provider_binding
    document = load_fixture("valid-lineage-planning.json")
    p2 = document.fetch("lanes").find { |lane| lane["lane_id"] == "planning_p2" }
    p2.fetch("provider_binding")["registered_provider"] = "codex"

    _stdout, stderr, status = validate_document(document)
    refute status.success?
    assert_match(/direct Codex|is not one of/, stderr)
  end

  def test_rejects_fabricated_provider_profile_model_and_registry_hash
    mutations = {
      "execution_profile_id" => "fabricated_profile",
      "resolved_provider_model" => "fabricated-model",
      "provider_capability_snapshot_sha256" => "f" * 64
    }
    mutations.each do |field, value|
      document = load_fixture("valid-lineage-planning.json")
      p2 = document.fetch("lanes").find { |lane| lane["lane_id"] == "planning_p2" }
      p2.fetch("provider_binding")[field] = value

      _stdout, stderr, status = validate_document(document)
      refute status.success?, field
      assert_includes stderr, "provider binding failed exact resolution", field
      assert_includes stderr, "binding_mismatch", field
    end
  end

  def test_rejects_registered_hold_profile
    document = load_fixture("valid-department-dispatch-cdd.json")
    document["logical_role"] = "department_worker"
    document.fetch("provider_binding").merge!(
      "logical_profile_alias" => "research_medium",
      "execution_profile_id" => "grok_worker_medium",
      "resolved_provider_model" => "grok-4.6",
      "reasoning_effort" => "medium"
    )

    _stdout, stderr, status = validate_document(document)
    refute status.success?
    assert_includes stderr, "profile_not_founder_verified"
  end

  def test_rejects_goal_semantics_that_do_not_match_provider
    document = load_fixture("valid-lineage-planning.json")
    p2 = document.fetch("lanes").find { |lane| lane["lane_id"] == "planning_p2" }
    p2.fetch("goal_evidence")["goal_semantics"] = "codex_thread_goal_active"
    p2.fetch("goal_evidence")["goal_terminal_state"] = "active"
    p2.fetch("goal_evidence")["goal_last_event"] = "goal_active"
    _stdout, stderr, status = validate_document(document)
    refute status.success?
    assert_includes stderr, "Goal evidence does not match registered provider"
  end

  def test_rejects_worker_dispatch_without_cdd_return_recipient
    document = load_fixture("valid-department-dispatch-worker.json")
    document.fetch("return_recipient")["role"] = "overall_director"
    _stdout, stderr, status = validate_document(document)
    refute status.success?
    assert_includes stderr, "section worker return recipient must be the cohort CDD"
  end

  def test_rejects_section_worker_reviewer_lane_owner_route_and_cohort_mismatches
    mutations = {
      "reviewer lane must equal the dispatch lane" => lambda { |doc| doc.fetch("reviewer")["lane_id"] = "section_cluster_v_c2" },
      "reviewer owner must equal the return recipient owner" => lambda { |doc| doc.fetch("return_recipient")["owner"] = "fixture-other-cdd" },
      "return route must be cohort_cdd_exact_byte_review" => lambda { |doc| doc.fetch("return_recipient")["return_route"] = "overall_reviewed_milestone" },
      "V-Ci lane suffix must match section_cohort_id C{N}" => lambda { |doc| doc["section_cohort_id"] = "C2" }
    }
    mutations.each do |message, mutate|
      document = load_fixture("valid-department-dispatch-worker.json")
      mutate.call(document)
      _stdout, stderr, status = validate_document(document)
      refute status.success?, message
      assert_includes stderr, message
    end
  end

  def test_reviewed_section_worker_accepts_only_common_bound_judgment
    document = load_fixture("valid-department-dispatch-worker.json")
    with_common_section_judgment(document) do
      stdout, stderr, status = validate_document(document)
      assert status.success?, [stdout, stderr].join("\n")
      assert_equal "pixel_02b", document.fetch("judgment_profile_id")
      refute document.key?("contextual_grade_vector")
    end
  end

  def test_graph_dispatch_rejects_obsolete_contextual_grade_vector_field
    document = load_fixture("valid-department-dispatch-worker.json")
    document["contextual_grade_vector"] = nil

    _stdout, stderr, status = validate_document(document)

    refute status.success?
    assert_match(/contextual_grade_vector.*unexpected|Additional properties.*contextual_grade_vector/i, stderr)
  end

  def test_rejects_planning_p2_dispatch_that_bypasses_p1
    document = load_fixture("valid-department-dispatch-planning-p2.json")
    document.fetch("reviewer").merge!("owner" => "fixture-overall", "role" => "overall_director", "lane_id" => "overall")
    document.fetch("return_recipient").merge!("owner" => "fixture-overall", "role" => "overall_director", "return_route" => "overall_reviewed_milestone")
    _stdout, stderr, status = validate_document(document)
    refute status.success?
    assert_match(/planning_cdd_p1|const/i, stderr)
  end

  def test_rejects_nine_live_grok_nonroot_physical_sessions_across_disjoint_lanes
    document = capacity_lineage(grok: 9, cursor: 0)
    _stdout, stderr, status = validate_document(document)
    refute status.success?
    assert_includes stderr, "Grok live physical session ceiling exceeded: 9>8"
  end

  def test_rejects_seven_live_cursor_nonroot_physical_sessions_across_disjoint_lanes
    document = capacity_lineage(grok: 0, cursor: 7)
    _stdout, stderr, status = validate_document(document)
    refute status.success?
    assert_includes stderr, "Cursor live physical session ceiling exceeded: 7>6"
  end

  def test_rejects_fifteen_combined_live_nonroot_physical_sessions
    document = capacity_lineage(grok: 8, cursor: 7)
    _stdout, stderr, status = validate_document(document)
    refute status.success?
    assert_includes stderr, "combined live physical session ceiling exceeded: 15>14"
  end

  def test_exact_provider_and_combined_limits_do_not_override_cursor_frontier_readiness_hold
    document = capacity_lineage(grok: 8, cursor: 6)
    _stdout, stderr, status = validate_document(document)
    refute status.success?
    assert_includes stderr, "director_full_owner_not_ready"
    refute_includes stderr, "Grok live physical session ceiling exceeded"
    refute_includes stderr, "Cursor live physical session ceiling exceeded"
    refute_includes stderr, "combined live physical session ceiling exceeded"
  end

  def test_dispatch_goal_evidence_is_required_and_legal_next_matches_state
    document = load_fixture("valid-department-dispatch-cdd.json")
    stdout, stderr, status = validate_document(document)
    assert status.success?, [stdout, stderr].join("\n")
    goal = document.fetch("goal_evidence")
    %w[native_goal_id goal_text_sha256 goal_semantics goal_terminal_state goal_last_event goal_terminal_event_sha256 terminal_event].each do |field|
      assert goal.key?(field), field
    end
    assert_equal %w[returned hold], document.fetch("legal_next")
    assert_equal "launched", document.fetch("lifecycle_state")
    assert_equal false, document.fetch("assignment_pass")
  end

  def test_rejects_illegal_lifecycle_skip_from_prepared_to_reviewed
    document = load_fixture("valid-department-dispatch-cdd.json")
    document["lifecycle_from"] = "prepared"
    document["lifecycle_state"] = "reviewed"
    document["legal_next"] = ["hold"]
    _stdout, stderr, status = validate_document(document)
    refute status.success?
    assert_includes stderr, "illegal lifecycle transition from prepared to reviewed"
  end

  def test_rejects_goal_completed_as_assignment_pass
    document = load_fixture("valid-department-dispatch-cdd.json")
    document["assignment_pass"] = true
    _stdout, stderr, status = validate_document(document)
    refute status.success?
    assert_match(/goal_completed closes successor admission only|const/i, stderr)
  end

  def test_rejects_missing_native_goal_id
    document = load_fixture("valid-department-dispatch-worker.json")
    document.fetch("goal_evidence")["native_goal_id"] = ""
    _stdout, stderr, status = validate_document(document)
    refute status.success?
    assert_match(/native_goal_id is missing|minLength|is too short/i, stderr)
  end

  def test_rejects_goal_without_persisted_terminal_event_pointer
    document = load_fixture("valid-department-dispatch-worker.json")
    document.fetch("goal_evidence").delete("terminal_event")

    _stdout, stderr, status = validate_document(document)
    refute status.success?
    assert_match(/terminal_event.*required|goal_evidence\.terminal_event must be an object/i, stderr)
  end

  def test_rejects_stale_persisted_terminal_event_sha
    document = load_fixture("valid-department-dispatch-worker.json")
    goal = document.fetch("goal_evidence")
    goal.fetch("terminal_event")["sha256"] = "f" * 64
    goal["goal_terminal_event_sha256"] = "f" * 64

    _stdout, stderr, status = validate_document(document)
    refute status.success?
    assert_includes stderr, "stale_terminal_event_sha"
  end

  def test_rejects_terminal_event_identity_provider_state_and_goal_text_mismatches
    mutations = {
      "native_goal_id" => lambda { |event| event["native_goal_id"] = "OTHER_NATIVE_GOAL" },
      "provider" => lambda { |event| event["provider"] = "cursor" },
      "terminal_state" => lambda { |event| event["terminal_state"] = "success" },
      "goal_text_sha256" => lambda { |event| event["goal_text_sha256"] = "a" * 64 }
    }
    mutations.each do |field, mutate|
      document = load_fixture("valid-department-dispatch-worker.json")
      with_mutated_terminal_goal_event(document, mutate) do
        _stdout, stderr, status = validate_document(document)
        refute status.success?, field
        assert_includes stderr, "terminal_event_field_mismatch", field
        assert_includes stderr, field, field
      end
    end

    document = load_fixture("valid-department-dispatch-worker.json")
    with_mutated_terminal_goal_event(document, ->(event) { event["goal_text"] = "Tampered synthetic Goal objective." }) do
      _stdout, stderr, status = validate_document(document)
      refute status.success?
      assert_includes stderr, "goal_text_digest_mismatch"
    end
  end

  def test_rejects_synthetic_terminal_event_without_explicit_fixture_notice
    document = load_fixture("valid-department-dispatch-worker.json")
    with_mutated_terminal_goal_event(document, ->(event) { event.delete("fixture_notice") }) do
      _stdout, stderr, status = validate_document(document)
      refute status.success?
      assert_includes stderr, "synthetic_fixture_not_declared"
    end
  end

  def test_returned_dispatch_requires_non_null_output_manifest
    document = load_fixture("valid-department-dispatch-cdd.json")
    document.merge!("lifecycle_state" => "returned", "legal_next" => %w[reviewed hold], "output_manifest" => nil)

    _stdout, stderr, status = validate_document(document)
    refute status.success?
    assert_includes stderr, "requires a non-null output_manifest"
  end

  def test_reviewed_dispatch_requires_graph_contextual_judgment_and_writer_session
    document = load_fixture("valid-department-dispatch-cdd.json")
    document.merge!("lifecycle_state" => "reviewed", "legal_next" => ["hold"])
    with_output_manifest(document) do
      _stdout, stderr, status = validate_document(document)
      refute status.success?
      assert_match(/contextual_judgment|judgment_profile_id/, stderr)
      assert_match(/session_id/, stderr)
    end
  end

  def test_rejects_stale_returned_output_manifest
    document = load_fixture("valid-department-dispatch-cdd.json")
    document.merge!("lifecycle_state" => "returned", "legal_next" => %w[reviewed hold])
    with_output_manifest(document) do
      document.fetch("output_manifest")["sha256"] = "f" * 64
      _stdout, stderr, status = validate_document(document)
      refute status.success?
      assert_includes stderr, "stale_manifest_sha"
    end
  end

  def test_rejects_output_manifest_reused_by_another_dispatch
    document = load_fixture("valid-department-dispatch-cdd.json")
    document.merge!("lifecycle_state" => "reviewed", "legal_next" => ["hold"])
    with_output_manifest(document) do
      document["dispatch_id"] = "DISPATCH_REUSED_MANIFEST"
      _stdout, stderr, status = validate_document(document)
      refute status.success?
      assert_includes stderr, "manifest_identity_mismatch"
      assert_includes stderr, "dispatch_id"
    end
  end

  def test_non_null_launched_manifest_is_always_verified
    document = load_fixture("valid-department-dispatch-cdd.json")
    with_output_manifest(document) do
      document.fetch("output_manifest")["sha256"] = "e" * 64
      _stdout, stderr, status = validate_document(document)
      refute status.success?
      assert_includes stderr, "stale_manifest_sha"
    end
  end

  def test_rejects_stale_carry_pointer_hash
    document = load_fixture("valid-lineage-production.json")
    carry = document.fetch("lanes").find { |lane| lane["lane_id"] == "section_cluster_v_c1" }.fetch("planning_to_production_carry")
    carry.fetch("planning_handoff")["sha256"] = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    _stdout, stderr, status = validate_document(document)
    refute status.success?
    assert_includes stderr, "SHA-256 is stale"
  end

  private

  def load_fixture(name)
    document = JSON.parse(FIXTURES.join(name).read)
    # Rebind a fresh test copy to today's exact provider source. Historical bytes stay pinned.
    rows = document["lanes"].is_a?(Array) ? document.fetch("lanes") : [document]
    rows.each do |row|
      binding = row.fetch("provider_binding")
      resolved, errors = IdolRoleContextPack.resolve_provider(
        root: ROOT, role: row.fetch("logical_role"),
        provider: binding.fetch("registered_provider"),
        runtime_surface: binding.fetch("runtime_surface"),
        logical_profile_alias: binding.fetch("logical_profile_alias")
      )
      raise errors.join("; ") unless errors.empty?
      binding.merge!(
        "reasoning_effort" => resolved.fetch("reasoning_effort"),
        "provider_capability_snapshot_sha256" => resolved.fetch("registry_sha256")
      )
    end
    document
  end

  def validate(path, validation_mode: "test_boundary")
    if path.dirname == FIXTURES
      return validate_document(load_fixture(path.basename.to_s), validation_mode: validation_mode)
    end
    arguments = ["ruby", VALIDATOR.to_s]
    arguments.concat(["--validation-mode", validation_mode]) if validation_mode
    arguments << path.to_s
    Open3.capture3(*arguments, chdir: ROOT.to_s)
  end

  def validate_document(document, validation_mode: "test_boundary")
    Dir.mktmpdir("idol-graph-lineage-", FIXTURES.to_s) do |directory|
      path = Pathname.new(directory).join("document.json")
      path.write(JSON.pretty_generate(document) + "\n")
      validate(path, validation_mode: validation_mode)
    end
  end

  def with_common_section_judgment(document)
    Dir.mktmpdir("idol-graph-common-section-judgment-", ROOT.join("runs").to_s) do |directory|
      directory = Pathname.new(directory)
      writer_role = "section_image_motion_worker"
      writer_session = "SECTION_S01_WRITER_PRIMARY"
      profile_id = "pixel_02b"
      checkpoint_id = "section_02b_image"
      stage_id = "branch_cut_generation"

      document.fetch("output_writer")["session_id"] = writer_session
      document["judgment_profile_id"] = profile_id
      document.merge!("lifecycle_state" => "returned", "legal_next" => %w[reviewed hold], "lifecycle_from" => "launched")
      bind_output_manifest(document, directory)

      returned_dispatch_path = directory.join("returned-dispatch.yaml")
      returned_dispatch_path.write(YAML.dump(document))
      launched_dispatch = Marshal.load(Marshal.dump(document))
      launched_dispatch.merge!("lifecycle_state" => "launched", "legal_next" => %w[returned hold], "output_manifest" => nil)
      launched_dispatch.delete("lifecycle_from")
      launched_dispatch_path = directory.join("launched-dispatch.yaml")
      launched_dispatch_path.write(YAML.dump(launched_dispatch))

      registry = YAML.safe_load(ROOT.join("automation", "graph-creative-judgment-registry.yaml").read, aliases: true)
      profile = registry.fetch("profiles").find { |row| row.fetch("profile_id") == profile_id }
      profile_hash = structured_sha(profile)
      pack_path = directory.join("role-context-pack.yaml")
      pack = IdolRoleContextPack.build(
        root: ROOT,
        run_root: document.fetch("run"),
        assignment_id: document.fetch("dispatch_id"),
        role: writer_role,
        profile_id: writer_role,
        checkpoint_id: checkpoint_id,
        stage_id: stage_id,
        section_ids: document.fetch("section_ids"),
        source_envelope: file_pointer(launched_dispatch_path).merge("kind" => "department_dispatch"),
        current_state: "launched",
        scope: {"stage_id" => stage_id, "section_ids" => document.fetch("section_ids")},
        authority: {
          "assigned_owner" => document.fetch("assigned_owner"),
          "promotion_owner" => document.dig("reviewer", "owner")
        },
        output_contract: document.fetch("bounded_output"),
        hold_conditions: document.fetch("stop_conditions"),
        return_recipient: document.fetch("return_recipient"),
        provider: document.dig("provider_binding", "registered_provider"),
        runtime_surface: document.dig("provider_binding", "runtime_surface"),
        writer: "graph_v2",
        run_class: "new_run",
        switch_receipt: graph_switch_receipt
      )
      pack_path.write(YAML.dump(pack))

      manifest = YAML.safe_load(ROOT.join(document.dig("output_manifest", "path")).read, aliases: true)
      output = manifest.fetch("outputs").first
      criteria = profile.fetch("criteria").map do |criterion|
        judgment_criterion(
          criterion.fetch("criterion_id"),
          criterion.fetch("critical_four") ? 4 : criterion.fetch("minimum"),
          output.slice("path", "sha256")
        )
      end
      judgment = {
        "schema_version" => "idol_graph_contextual_judgment.v2",
        "artifact_type" => "graph_contextual_judgment",
        "profile_id" => profile_id,
        "checkpoint_id" => checkpoint_id,
        "stage_id" => stage_id,
        "scope_id" => document.fetch("dispatch_id"),
        "authoring_owner" => "human_or_assigned_model",
        "reviewer_role" => writer_role,
        "performance_mode" => "none",
        "applicability_tags" => [],
        "applicability_evidence" => [],
        "execution_binding" => {
          "assignment_id" => document.fetch("dispatch_id"),
          "author_role" => writer_role,
          "author_session_id" => writer_session,
          "dispatch" => file_pointer(returned_dispatch_path),
          "goal_id" => document.dig("goal_evidence", "native_goal_id"),
          "goal_terminal_event_sha256" => document.dig("goal_evidence", "goal_terminal_event_sha256"),
          "role_context_pack" => file_pointer(pack_path),
          "profile_release" => pack.dig("creative_judgment_contract", "profile_release"),
          "profile_value_sha256" => profile_hash,
          "input_digest_sha256" => document.fetch("input_digest_sha256"),
          "output_manifest" => document.fetch("output_manifest")
        },
        "source_artifacts" => [{
          "path" => output.fetch("path"),
          "sha256" => output.fetch("sha256"),
          "locator" => "exact returned section image package bytes"
        }],
        "criteria" => criteria,
        "hard_gate_findings" => [],
        "decision" => "eligible_for_director_review",
        "next_edge" => "director_review",
        "target_message_treatment" => profile.fetch("target_message_treatment"),
        "aggregate_score_present" => false,
        "automatic_creative_pass" => false,
        "status" => "ready_for_director_review"
      }
      judgment_path = directory.join("contextual-judgment.yaml")
      judgment_path.write(YAML.dump(judgment))

      document.merge!(
        "lifecycle_state" => "reviewed",
        "legal_next" => ["hold"],
        "lifecycle_from" => "returned",
        "judgment_profile_id" => profile_id,
        "contextual_judgment" => file_pointer(judgment_path).merge("profile_id" => profile_id)
      )
      yield
    end
  end

  def judgment_criterion(criterion_id, result, evidence_ref)
    {
      "criterion_id" => criterion_id,
      "result" => result,
      "evidence_locator" => [evidence_ref],
      "observable_claim" => "The returned section evidence visibly supports #{criterion_id}.",
      "screen_consequence" => "The named image job remains legible for Director review.",
      "preserve" => "Preserve the verified source function and strongest visible fact.",
      "change" => "Change only the bounded weakness if this grade drops.",
      "do_not_infer" => "Do not infer creative PASS or an unrelated section decision.",
      "correction_action" => "Return the exact section scope to its current owner.",
      "acceptance_evidence" => "Re-review the exact corrected bytes against this criterion."
    }
  end

  def file_pointer(path)
    {
      "path" => path.relative_path_from(ROOT).to_s,
      "sha256" => Digest::SHA256.file(path).hexdigest
    }
  end

  def structured_sha(value)
    Digest::SHA256.hexdigest(JSON.generate(canonicalize(value)))
  end

  def graph_switch_receipt
    {
      "receipt_id" => "GRAPH_SWITCH_LINEAGE_COMMON_JUDGMENT",
      "founder_authority" => "founder",
      "graph_revision" => "idol-graph-skill-load-profiles.v1",
      "switch_boundary" => "new_runs_only_after_verified_receipt",
      "source_set_sha256" => IdolRoleContextPack.graph_source_set_sha256(ROOT),
      "verified_at" => "2026-09-03T00:00:00+09:00"
    }
  end

  def canonicalize(value)
    case value
    when Hash
      value.keys.map(&:to_s).sort.each_with_object({}) { |key, memo| memo[key] = canonicalize(value[key]) }
    when Array
      value.map { |item| canonicalize(item) }
    else
      value
    end
  end

  def with_output_manifest(document)
    Dir.mktmpdir("idol-graph-output-manifest-", ROOT.join("runs").to_s) do |directory|
      bind_output_manifest(document, Pathname.new(directory))
      yield
    end
  end

  def bind_output_manifest(document, directory)
    output_path = directory.join("returned-output.yaml")
    output_path.write(YAML.dump("dispatch_id" => document.fetch("dispatch_id"), "result" => "fixture exact output"))
    manifest_path = directory.join("output-manifest.yaml")
    document["bounded_output"] = {
      "output_kind" => "fixture_exact_output",
      "expected_paths" => [output_path.relative_path_from(ROOT).to_s],
      "maximum_artifact_count" => 1
    }
    manifest_path.write(YAML.dump(
      "schema_version" => "idol-graph-output-manifest.v1",
      "artifact_type" => "graph_dispatch_output_manifest",
      "dispatch_id" => document.fetch("dispatch_id"),
      "assigned_owner" => document.fetch("assigned_owner"),
      "input_digest_sha256" => document.fetch("input_digest_sha256"),
      "output_kind" => document.dig("bounded_output", "output_kind"),
      "outputs" => [{
        "path" => output_path.relative_path_from(ROOT).to_s,
        "sha256" => Digest::SHA256.file(output_path).hexdigest
      }]
    ))
    document["output_manifest"] = {
      "path" => manifest_path.relative_path_from(ROOT).to_s,
      "sha256" => Digest::SHA256.file(manifest_path).hexdigest
    }
  end


  def capacity_lineage(grok:, cursor:)
    document = load_fixture("valid-lineage-planning.json")
    templates = document.fetch("lanes").each_with_object({}) { |lane, memo| memo[lane.fetch("lane_id")] = lane }
    providers = Array.new(grok, "grok") + Array.new(cursor, "cursor")
    lanes = [templates.fetch("overall")]
    providers.each_with_index do |provider, index|
      lane = if index.zero?
               Marshal.load(Marshal.dump(templates.fetch("planning_p1")))
             elsif index == 1
               Marshal.load(Marshal.dump(templates.fetch("planning_p2")))
             else
               Marshal.load(Marshal.dump(templates.fetch("planning_p3_c1"))).tap do |row|
                 cohort_index = index - 1
                 row["lane_id"] = "planning_p3_c#{cohort_index}"
                 row["section_cohort_id"] = "C#{cohort_index}"
                 row.fetch("write_scopes").each { |scope| scope["section_ids"] = [format("S%02d", 90 + cohort_index)] }
               end
             end

      session_id = "CAP_#{provider.upcase}_#{index + 1}"
      lane["active_writer_session_id"] = session_id
      lane["physical_sessions"] = [{
        "generation" => "primary",
        "session_id" => session_id,
        "state" => "active_single_writer",
        "opened_at" => "2026-09-03T00:00:00Z"
      }]
      lane["succession"] = {
        "cas_required" => true,
        "third_session_forbidden" => true,
        "source_session_id" => session_id,
        "successor_session_id" => nil,
        "active_writer_session_id" => session_id,
        "authority_state" => "primary_active"
      }
      lane.fetch("provider_binding")["registered_provider"] = provider
      if provider == "cursor"
        lane.fetch("provider_binding").merge!(
          "runtime_surface" => "cursor_cli_local_physical_chat",
          "execution_profile_id" => "cursor_grok_46_xhigh",
          "resolved_provider_model" => "cursor-grok-4.6-xhigh"
        )
        lane.fetch("goal_evidence").merge!(
          "native_goal_id" => "GOAL_CURSOR_CAPACITY",
          "goal_text_sha256" => "9eeb9c8902cec872fb5d8270c64c442e763eb031aedbc1cbcb13601e8818d7cc",
          "goal_semantics" => "cursor_external_goal_runtime_receipt",
          "goal_terminal_state" => "success",
          "goal_last_event" => "cli_terminal_success",
          "goal_terminal_event_sha256" => "d00b041685ff6b6ff77a8038ed33ae78651eb358b4d903df3b522a8cb38883c9",
          "terminal_event" => {
            "path" => "scripts/tests/fixtures/graph-authority/evidence/goal-events/goal-cursor-capacity.yaml",
            "sha256" => "d00b041685ff6b6ff77a8038ed33ae78651eb358b4d903df3b522a8cb38883c9"
          }
        )
      end
      lanes << lane
    end
    document["lanes"] = lanes
    document
  end

  def with_mutated_terminal_goal_event(document, mutation)
    Dir.mktmpdir("idol-graph-goal-event-", FIXTURES.to_s) do |directory|
      directory = Pathname.new(directory)
      source = ROOT.join(document.dig("goal_evidence", "terminal_event", "path"))
      event = YAML.safe_load(source.read, aliases: false)
      mutation.call(event)
      path = directory.join("terminal-goal-event.yaml")
      path.write(YAML.dump(event))
      sha = Digest::SHA256.file(path).hexdigest
      document.fetch("goal_evidence").merge!(
        "goal_terminal_event_sha256" => sha,
        "terminal_event" => {
          "path" => path.relative_path_from(ROOT).to_s,
          "sha256" => sha
        }
      )
      yield
    end
  end
end
