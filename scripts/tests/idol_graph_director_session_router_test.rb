# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "minitest/autorun"
require "pathname"
require "tmpdir"

require_relative "../idol_graph_director_session_router"

class IdolGraphDirectorSessionRouterTest < Minitest::Test
  FIXTURE = Pathname.new(__dir__).join("fixtures", "graph-director-session-router", "valid-initialize-request.json")
  LINEAGE_FIXTURE = Pathname.new(__dir__).join("fixtures", "graph-authority", "valid-lineage-planning.json")
  LANE_STAGES = {
    "overall" => "planning_cell",
    "planning_p1" => "planning_cell",
    "planning_p2" => "planning_cell",
    "planning_p3_c2" => "planning_cell",
    "section_cluster_v_c2" => "section_cluster_production",
    "edit_director" => "edit_and_package"
  }.freeze

  def setup
    @root = Pathname.new(Dir.mktmpdir("idol-graph-director-router-", "/private/tmp"))
    @previous_root = ENV["IDOL_GRAPH_DIRECTOR_ROUTER_TEST_ROOT"]
    ENV["IDOL_GRAPH_DIRECTOR_ROUTER_TEST_ROOT"] = @root.to_s
    @pointers = %w[verified_switch_receipt director_lineage role_context_pack successor_pack provider_source safe_checkpoint].each_with_object({}) do |name, memo|
      path = @root.join("evidence", "#{name}.json")
      path.dirname.mkpath
      path.write(JSON.generate("kind" => name, "fixture" => true) + "\n")
      memo[name] = pointer(path)
    end
    lineage = JSON.parse(LINEAGE_FIXTURE.read)
    @provider_binding = deep_copy(lineage.fetch("lanes").find { |lane| lane.fetch("lane_id") == "planning_p2" }.fetch("provider_binding"))
    @goal_evidence = write_goal_terminal_event
  end

  def teardown
    if @previous_root.nil?
      ENV.delete("IDOL_GRAPH_DIRECTOR_ROUTER_TEST_ROOT")
    else
      ENV["IDOL_GRAPH_DIRECTOR_ROUTER_TEST_ROOT"] = @previous_root
    end
    FileUtils.remove_entry(@root) if @root&.directory?
  end

  def test_all_registered_director_lane_families_admit_the_same_two_session_boundary
    LANE_STAGES.each do |lane_id, stage_id|
      request = initialize_request(lane_id: lane_id, macro_stage_id: stage_id)
      result = IdolGraphDirectorSessionRouter.command(request)
      assert_equal "successor_preflight", result.fetch("phase")
      assert_equal "hold", result.fetch("status")
      assert_equal false, result.fetch("execution_authority")
      assert_equal "hold_shadow_not_execution_ready", result.fetch("activation_status")
      assert_equal false, result.fetch("founder_confirmation_required")
      state = JSON.parse(Pathname.new(result.fetch("state_path")).read)
      assert_equal 2, state.fetch("physical_session_limit")
      assert_equal "active_single_writer", state.dig("primary_session", "state")
      assert_equal "zero_turn_read_only_preflight", state.dig("successor_session", "state")
      assert_equal %w[G0 G1 G2 G3 G4], state.dig("founder_gate_contract", "normal_cycle")
    end
  end

  def test_graph_cas_has_no_founder_confirmation_and_rollback_restores_only_primary
    initialized = IdolGraphDirectorSessionRouter.command(initialize_request)
    assert_shadow_observation(initialized, primary_id, "canonical_write")
    assert_shadow_observation(initialized, successor_id, "goal_and_preflight")
    assert_denied(initialized, successor_id, "canonical_write")

    admitted = admit(initialized)
    assert_equal "successor_admitted", admitted.fetch("phase")
    assert_match(/\A[a-f0-9]{64}\z/, admitted.fetch("admission_digest"))
    assert_denied(admitted, successor_id, "review")

    legacy_shaped_commit = commit_request(admitted).merge("founder_confirmation_sha256" => "f" * 64)
    error = assert_raises(IdolGraphDirectorSessionRouter::ValidationError) do
      IdolGraphDirectorSessionRouter.command(legacy_shaped_commit)
    end
    assert_includes error.errors.join(" "), "keys must be exactly"

    committed = IdolGraphDirectorSessionRouter.command(commit_request(admitted))
    assert_equal successor_id, committed.fetch("active_writer_session_id")
    assert_denied(committed, primary_id, "prompt")
    assert_shadow_observation(committed, successor_id, "canonical_write")
    assert_equal false, committed.fetch("execution_authority")

    stale = rollback_request(committed).merge("expected_state_sha256" => admitted.fetch("state_sha256"))
    error = assert_raises(IdolGraphDirectorSessionRouter::ValidationError) do
      IdolGraphDirectorSessionRouter.command(stale)
    end
    assert_includes error.errors.join(" "), "state SHA changed"

    rolled_back = IdolGraphDirectorSessionRouter.command(rollback_request(committed))
    assert_equal "rolled_back", rolled_back.fetch("phase")
    assert_equal primary_id, rolled_back.fetch("active_writer_session_id")
    assert_shadow_observation(rolled_back, primary_id, "resume")
    assert_denied(rolled_back, successor_id, "prompt")

    state = snapshot.fetch("state")
    assert_equal %w[initialized admitted committed rolled_back], state.fetch("history").map { |row| row.fetch("event") }
    assert_equal "reactivated_single_writer", state.dig("primary_session", "state")
    assert_equal "graph_logically_retired", state.dig("successor_session", "state")
    assert_equal false, state.dig("founder_gate_contract", "same_lane_succession_confirmation_required")
    assert_equal false, state.dig("transition_receipt_contract", "hash_claim_opens_execution_authority")
    assert_equal true, state.dig("transition_receipt_contract", "typed_receipt_required_before_activation")
    refute_includes JSON.generate(state), "founder_confirmation_sha256"
  end

  def test_admission_exact_verifies_persisted_goal_event_and_provider_binding
    initialized = IdolGraphDirectorSessionRouter.command(initialize_request)
    admitted = admit(initialized)
    state = snapshot.fetch("state")

    assert_equal "typed_goal_terminal_event_and_provider_binding_verified", state.dig("admission", "verification_status")
    assert_equal "test_boundary", state.dig("admission", "validation_mode")
    assert_equal @goal_evidence.fetch("terminal_event"), state.dig("admission", "goal_evidence", "terminal_event")
    assert_equal "synthetic_fixture", state.dig("admission", "verified_terminal_event", "evidence_class")
    assert_equal "typed_test_boundary_valid", state.dig("evidence_validation", "checks", "successor_goal_admission")
    refute_includes state.dig("evidence_validation", "blockers"), "successor_goal_admission_not_yet_verified"
    assert_equal admitted.fetch("admission_digest"), state.dig("admission", "admission_digest")
  end

  def test_admission_rejects_missing_terminal_event_pointer
    initialized = IdolGraphDirectorSessionRouter.command(initialize_request)
    goal = deep_copy(@goal_evidence)
    goal.delete("terminal_event")

    error = assert_raises(IdolGraphDirectorSessionRouter::ValidationError) do
      IdolGraphDirectorSessionRouter.command(admit_request(initialized, goal_evidence: goal))
    end

    assert_includes error.errors.join(" "), "terminal_event"
    assert_equal "successor_preflight", snapshot.fetch("phase")
  end

  def test_admission_rejects_stale_terminal_event_sha
    initialized = IdolGraphDirectorSessionRouter.command(initialize_request)
    goal = deep_copy(@goal_evidence)
    goal["terminal_event"]["sha256"] = "f" * 64
    goal["goal_terminal_event_sha256"] = "f" * 64

    error = assert_raises(IdolGraphDirectorSessionRouter::ValidationError) do
      IdolGraphDirectorSessionRouter.command(admit_request(initialized, goal_evidence: goal))
    end

    assert_includes error.errors.join(" "), "stale_terminal_event_sha"
    assert_equal "successor_preflight", snapshot.fetch("phase")
  end

  def test_admission_rejects_provider_binding_that_does_not_match_the_router
    initialized = IdolGraphDirectorSessionRouter.command(initialize_request)
    binding = deep_copy(@provider_binding)
    binding["registered_provider"] = "cursor"

    error = assert_raises(IdolGraphDirectorSessionRouter::ValidationError) do
      IdolGraphDirectorSessionRouter.command(admit_request(initialized, provider_binding: binding))
    end

    assert_includes error.errors.join(" "), "provider binding failed exact resolution"
    assert_equal "successor_preflight", snapshot.fetch("phase")
  end

  def test_persisted_admission_fails_closed_after_terminal_event_bytes_change
    initialized = IdolGraphDirectorSessionRouter.command(initialize_request)
    admit(initialized)
    @goal_event_path.write(@goal_event_path.read.sub("goal_completed", "goal_completed_tampered"))

    error = assert_raises(IdolGraphDirectorSessionRouter::ValidationError) { snapshot }

    assert_includes error.errors.join(" "), "stale_terminal_event_sha"
  end

  def test_only_overall_active_writer_may_use_founder_conversation_or_promotion_operations
    planning = IdolGraphDirectorSessionRouter.command(initialize_request)
    assert_denied(planning, primary_id, "founder_conversation")
    assert_denied(planning, primary_id, "promotion")

    overall = IdolGraphDirectorSessionRouter.command(initialize_request(lane_id: "overall", macro_stage_id: "planning_cell"))
    assert_shadow_observation(overall, primary_id("overall"), "founder_conversation")
    assert_shadow_observation(overall, primary_id("overall"), "promotion")
  end

  def test_existing_state_forbids_any_reinitialize_or_third_session
    IdolGraphDirectorSessionRouter.command(initialize_request)
    replacement = initialize_request
    replacement["successor_session_id"] = "P1_THIRD_FIXTURE"
    error = assert_raises(IdolGraphDirectorSessionRouter::ValidationError) do
      IdolGraphDirectorSessionRouter.command(replacement)
    end
    assert_includes error.errors.join(" "), "third physical session is forbidden"
  end

  def test_lane_cannot_create_an_alias_macro_stage_to_evade_the_two_session_cap
    request = initialize_request(lane_id: "planning_p3_c2", macro_stage_id: "planning_cell_alias")

    error = assert_raises(IdolGraphDirectorSessionRouter::ValidationError) do
      IdolGraphDirectorSessionRouter.command(request)
    end

    assert_includes error.errors.join(" "), "macro_stage_id is not registered"
    refute Pathname.new(request.fetch("state_path")).exist?
  end

  def test_legacy_router_contract_and_implementation_remain_separate
    legacy_schema = Pathname.new(__dir__).join("..", "..", "schemas", "cdd-session-router-state.schema.json").read
    legacy_runner = Pathname.new(__dir__).join("..", "idol_director_dispatch_index.rb").read
    assert_includes legacy_schema, "idol-cdd-session-router-state.v1"
    assert_includes legacy_runner, "founder_confirmation_sha256"
    refute_includes legacy_schema, "idol-graph-director-session-router-state.v1"
  end

  def test_noncanonical_hash_only_evidence_is_an_explicit_activation_hold
    initialized = IdolGraphDirectorSessionRouter.command(initialize_request)
    state = snapshot.fetch("state")

    assert_equal "hold_unverified_or_incomplete", state.dig("evidence_validation", "status")
    assert_equal "invalid_shadow_hold", state.dig("evidence_validation", "checks", "verified_switch_receipt")
    assert_includes state.dig("evidence_validation", "blockers"), "noncanonical_proof_evidence_is_not_activation_evidence"
    assert_includes state.dig("evidence_validation", "blockers"), "typed_commit_authority_receipt_not_registered"
    observation = authorize(initialized, primary_id, "canonical_write")
    assert_equal "shadow_observation_only", observation.fetch("authorization")
    assert_equal true, observation.fetch("operation_must_remain_blocked")
    assert_equal false, observation.fetch("execution_authority")
  end

  def test_symlinked_state_parent_is_rejected_before_external_directory_creation
    outside = Pathname.new(Dir.mktmpdir("idol-graph-director-router-outside-", "/private/tmp"))
    link = @root.join("linked-parent")
    File.symlink(outside, link)
    request = initialize_request
    request["state_path"] = link.join("must-not-create", "active-session.json").to_s

    error = assert_raises(IdolGraphDirectorSessionRouter::ValidationError) do
      IdolGraphDirectorSessionRouter.command(request)
    end

    assert_includes error.errors.join(" "), "symlink ancestor"
    refute outside.join("must-not-create").exist?
  ensure
    FileUtils.remove_entry(outside) if outside&.directory?
  end

  def test_arbitrary_private_tmp_root_cannot_claim_the_router_test_boundary
    arbitrary_root = Pathname.new(Dir.mktmpdir("arbitrary-graph-proof-", "/private/tmp"))
    ENV["IDOL_GRAPH_DIRECTOR_ROUTER_TEST_ROOT"] = arbitrary_root.to_s
    request = initialize_request
    request["state_path"] = arbitrary_root.join("states", "active-session.json").to_s

    error = assert_raises(IdolGraphDirectorSessionRouter::ValidationError) do
      IdolGraphDirectorSessionRouter.command(request)
    end

    assert_includes error.errors.join(" "), "dedicated idol-graph-director-router-* proof-root pattern"
  ensure
    ENV["IDOL_GRAPH_DIRECTOR_ROUTER_TEST_ROOT"] = @root.to_s
    FileUtils.remove_entry(arbitrary_root) if arbitrary_root&.directory?
  end

  def test_typed_lineage_correlation_binds_lane_lineage_provider_and_primary
    lineage = JSON.parse(LINEAGE_FIXTURE.read)
    params = {
      "run_root" => lineage.fetch("run"),
      "lane_id" => "planning_p2",
      "macro_stage_id" => "planning_cell",
      "logical_lineage_id" => "P2_LINEAGE_G6",
      "provider" => "grok",
      "runtime_surface" => "grok_build_cli_acp",
      "primary_session_id" => "P2_PRIMARY",
      "successor_session_id" => "P2_SUCCESSOR_NEW"
    }

    assert_equal true, IdolGraphDirectorSessionRouter.correlated_lineage!(lineage, params)

    params["logical_lineage_id"] = "FORGED_LINEAGE"
    error = assert_raises(IdolGraphDirectorSessionRouter::ValidationError) do
      IdolGraphDirectorSessionRouter.correlated_lineage!(lineage, params)
    end
    assert_includes error.errors, "Director lineage logical_lineage_id differs"
  end

  private

  def initialize_request(lane_id: "planning_p1", macro_stage_id: "planning_cell")
    request = JSON.parse(FIXTURE.read)
    request["state_path"] = @root.join("states", lane_id, macro_stage_id, "active-session.json").to_s
    request["lane_id"] = lane_id
    request["macro_stage_id"] = macro_stage_id
    request["logical_lineage_id"] = "#{lane_id.upcase}_LINEAGE_FIXTURE"
    request["primary_session_id"] = primary_id(lane_id)
    request["successor_session_id"] = successor_id(lane_id)
    @pointers.each { |name, value| request[name] = value }
    request
  end

  def primary_id(lane_id = "planning_p1")
    "#{lane_id.upcase}_PRIMARY_FIXTURE"
  end

  def successor_id(lane_id = "planning_p1")
    "#{lane_id.upcase}_SUCCESSOR_FIXTURE"
  end

  def pointer(path)
    {"path" => path.to_s, "sha256" => Digest::SHA256.file(path).hexdigest}
  end

  def admit(state)
    IdolGraphDirectorSessionRouter.command(admit_request(state))
  end

  def admit_request(state, provider_binding: @provider_binding, goal_evidence: @goal_evidence)
    {
      "action" => "route-admit",
      "state_path" => state.fetch("state_path"),
      "expected_state_sha256" => state.fetch("state_sha256"),
      "expected_generation" => state.fetch("generation"),
      "primary_session_id" => primary_id,
      "successor_session_id" => successor_id,
      "provider_binding" => provider_binding,
      "goal_evidence" => goal_evidence,
      "recorded_at" => "2026-09-03T00:00:01Z"
    }
  end

  def commit_request(state)
    {
      "action" => "route-commit",
      "state_path" => state.fetch("state_path"),
      "expected_state_sha256" => state.fetch("state_sha256"),
      "expected_generation" => state.fetch("generation"),
      "primary_session_id" => primary_id,
      "successor_session_id" => successor_id,
      "admission_digest" => state.fetch("admission_digest"),
      "director_succession_authority_sha256" => "d" * 64,
      "recorded_at" => "2026-09-03T00:00:02Z"
    }
  end

  def rollback_request(state)
    {
      "action" => "route-rollback",
      "state_path" => state.fetch("state_path"),
      "expected_state_sha256" => state.fetch("state_sha256"),
      "expected_generation" => state.fetch("generation"),
      "primary_session_id" => primary_id,
      "successor_session_id" => successor_id,
      "commit_receipt_sha256" => state.fetch("transition_receipt_sha256"),
      "failure_receipt_sha256" => "e" * 64,
      "recorded_at" => "2026-09-03T00:00:03Z"
    }
  end

  def authorize(state, session_id, operation)
    IdolGraphDirectorSessionRouter.command(
      "action" => "route-authorize",
      "state_path" => state.fetch("state_path"),
      "expected_state_sha256" => state.fetch("state_sha256"),
      "expected_generation" => state.fetch("generation"),
      "session_id" => session_id,
      "operation" => operation
    )
  end

  def assert_shadow_observation(state, session_id, operation)
    result = authorize(state, session_id, operation)
    assert_equal "shadow_observation_only", result.fetch("authorization")
    assert_equal false, result.fetch("execution_authority")
    assert_equal true, result.fetch("operation_must_remain_blocked")
  end

  def assert_denied(state, session_id, operation)
    error = assert_raises(IdolGraphDirectorSessionRouter::ValidationError) { authorize(state, session_id, operation) }
    assert_includes error.errors.join(" "), "denied"
  end

  def snapshot
    IdolGraphDirectorSessionRouter.command("action" => "route-snapshot", "state_path" => @root.join("states", "planning_p1", "planning_cell", "active-session.json").to_s)
  end

  def deep_copy(value)
    JSON.parse(JSON.generate(value))
  end

  def write_goal_terminal_event
    goal_text = "Continue the same bounded Director lane from the verified successor pack."
    goal_text_sha = Digest::SHA256.hexdigest(goal_text.encode(Encoding::UTF_8))
    @goal_event_path = @root.join("goal-events", "successor-admission.json")
    @goal_event_path.dirname.mkpath
    @goal_event_path.write(
      JSON.pretty_generate(
        "schema_version" => "idol-graph-provider-goal-terminal-event.v1",
        "artifact_type" => "graph_provider_goal_terminal_event",
        "evidence_class" => "synthetic_fixture",
        "provider" => "grok",
        "native_goal_id" => "GOAL_P1_SUCCESSOR_FIXTURE",
        "goal_text" => goal_text,
        "goal_text_sha256" => goal_text_sha,
        "goal_semantics" => "grok_goal_completed_admission",
        "terminal_state" => "complete",
        "last_event" => "goal_completed",
        "fixture_notice" => "synthetic_test_evidence_not_runtime_attestation"
      ) + "\n"
    )
    event_sha = Digest::SHA256.file(@goal_event_path).hexdigest
    {
      "native_goal_id" => "GOAL_P1_SUCCESSOR_FIXTURE",
      "goal_text_sha256" => goal_text_sha,
      "goal_semantics" => "grok_goal_completed_admission",
      "goal_terminal_state" => "complete",
      "goal_last_event" => "goal_completed",
      "goal_terminal_event_sha256" => event_sha,
      "terminal_event" => {
        "path" => @goal_event_path.relative_path_from(@root).to_s,
        "sha256" => event_sha
      },
      "goal_completed_closes" => "successor_admission_only",
      "idol_assignment_pass" => false
    }
  end
end
