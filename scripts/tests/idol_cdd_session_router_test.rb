# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "minitest/autorun"
require "pathname"
require "tmpdir"

require_relative "../idol_director_dispatch_index"

class IdolCddSessionRouterTest < Minitest::Test
  def setup
    @temporary_root = Pathname.new(Dir.mktmpdir("idol-cdd-router-", "/private/tmp"))
    @previous_test_root = ENV["IDOL_CDD_ROUTER_TEST_ROOT"]
    ENV["IDOL_CDD_ROUTER_TEST_ROOT"] = @temporary_root.to_s
    @state_path = @temporary_root.join("router", "cdd-active-session.json")
    @route_manifest = write_file("route-manifest.json", "{\"route\":\"fixture\"}\n")
    @provider_source = write_file("provider-source.yaml", "profile: fixture\n")
    @boot_pack = write_file("boot-pack.json", "{\"boot\":\"fixture\"}\n")
    @source_session = "GROK_SESSION_A_FIXTURE"
    @successor_session = "GROK_SESSION_B_FIXTURE"
  end

  def teardown
    if @previous_test_root.nil?
      ENV.delete("IDOL_CDD_ROUTER_TEST_ROOT")
    else
      ENV["IDOL_CDD_ROUTER_TEST_ROOT"] = @previous_test_root
    end
    FileUtils.remove_entry(@temporary_root) if @temporary_root&.directory?
  end

  def test_grok_goal_completion_admits_then_router_cas_and_rollback_gate_the_actual_writer
    initialized = route_initialize(provider: "grok", runtime_surface: "grok_cli_acp_or_tui")
    assert_equal "successor_preflight", initialized.fetch("phase")
    assert_equal @source_session, initialized.fetch("active_writer_session_id")
    assert_equal true, initialized.fetch("noncanonical_proof_root")

    assert_authorized(initialized, @source_session, "prompt")
    assert_authorized(initialized, @successor_session, "goal_and_preflight")
    assert_denied(initialized, @successor_session, "prompt")

    invalid_goal = goal_receipt(
      semantics: "grok_goal_completed_admission",
      terminal_state: "active",
      last_event: "goal_active"
    )
    error = assert_raises(IdolDirectorDispatchIndex::ValidationError) do
      route_admit(initialized, invalid_goal)
    end
    assert_includes error.errors.join(" "), "provider-native Goal semantics"

    admitted = route_admit(
      initialized,
      goal_receipt(
        semantics: "grok_goal_completed_admission",
        terminal_state: "complete",
        last_event: "goal_completed"
      )
    )
    assert_equal "successor_admitted", admitted.fetch("phase")
    assert_equal @source_session, admitted.fetch("active_writer_session_id")
    assert_authorized(admitted, @successor_session, "goal_and_preflight")
    assert_denied(admitted, @successor_session, "review")

    committed = route_commit(admitted)
    assert_equal "successor_active", committed.fetch("phase")
    assert_equal @successor_session, committed.fetch("active_writer_session_id")
    assert_denied(committed, @source_session, "prompt")
    assert_authorized(committed, @successor_session, "prompt")
    assert_authorized(committed, @successor_session, "canonical_write")

    stale = committed.merge("state_sha256" => admitted.fetch("state_sha256"))
    error = assert_raises(IdolDirectorDispatchIndex::ValidationError) do
      route_rollback(stale, committed.fetch("transition_receipt_sha256"))
    end
    assert_includes error.errors.join(" "), "state SHA changed"

    rolled_back = route_rollback(committed, committed.fetch("transition_receipt_sha256"))
    assert_equal "rolled_back", rolled_back.fetch("phase")
    assert_equal @source_session, rolled_back.fetch("active_writer_session_id")
    assert_authorized(rolled_back, @source_session, "resume")
    assert_denied(rolled_back, @successor_session, "prompt")

    state = JSON.parse(@state_path.read)
    assert_equal %w[initialized admitted committed rolled_back], state.fetch("history").map { |row| row.fetch("event") }
    assert_equal "reactivated_single_writer", state.dig("source_session", "state")
    assert_equal "harness_logically_retired", state.dig("successor_session", "state")
    assert_equal 3, state.fetch("generation")
  end

  def test_codex_uses_active_thread_goal_semantics_without_changing_router_cas
    @source_session = "CODEX_THREAD_A_FIXTURE"
    @successor_session = "CODEX_THREAD_B_FIXTURE"
    initialized = route_initialize(provider: "codex", runtime_surface: "codex_app")

    admitted = route_admit(
      initialized,
      goal_receipt(
        semantics: "codex_thread_goal_active",
        terminal_state: "active",
        last_event: "goal_active"
      )
    )
    committed = route_commit(admitted)
    assert_denied(committed, @source_session, "dispatch")
    assert_authorized(committed, @successor_session, "dispatch")
  end

  def test_cursor_uses_external_goal_runtime_receipt_without_changing_router_cas
    @source_session = "CURSOR_SESSION_A_FIXTURE"
    @successor_session = "CURSOR_SESSION_B_FIXTURE"
    initialized = route_initialize(
      provider: "cursor",
      runtime_surface: "cursor_cli_local_physical_chat"
    )

    admitted = route_admit(
      initialized,
      goal_receipt(
        semantics: "cursor_external_goal_runtime_receipt",
        terminal_state: "success",
        last_event: "cli_terminal_success"
      )
    )
    committed = route_commit(admitted)
    assert_denied(committed, @source_session, "dispatch")
    assert_authorized(committed, @successor_session, "dispatch")
  end

  def test_router_rejects_absolute_state_outside_the_explicit_proof_root
    request = initialize_request(provider: "grok", runtime_surface: "grok_cli_acp_or_tui")
    request["state_path"] = "/private/tmp/not-the-bound-root/cdd-active-session.json"
    error = assert_raises(IdolDirectorDispatchIndex::ValidationError) do
      IdolDirectorDispatchIndex.cdd_successor_command(request)
    end
    assert_includes error.errors.join(" "), "exact bounded /private/tmp proof root"
  end

  private

  def write_file(name, bytes)
    path = @temporary_root.join(name)
    path.dirname.mkpath
    path.write(bytes)
    path
  end

  def pointer(path)
    {"path" => path.to_s, "sha256" => Digest::SHA256.file(path).hexdigest}
  end

  def initialize_request(provider:, runtime_surface:)
    {
      "action" => "route-initialize",
      "state_path" => @state_path.to_s,
      "assignment_id" => IdolDirectorDispatchIndex::CDD_ROUTER_ASSIGNMENT_ID,
      "provider" => provider,
      "runtime_surface" => runtime_surface,
      "run_root" => "noncanonical-proof-fixture",
      "logical_lineage_id" => "CDD_LINEAGE_FIXTURE",
      "source_session_id" => @source_session,
      "successor_session_id" => @successor_session,
      "route_manifest" => pointer(@route_manifest),
      "provider_source" => pointer(@provider_source),
      "boot_pack" => pointer(@boot_pack),
      "recorded_at" => "2026-08-17T00:00:00Z"
    }
  end

  def route_initialize(provider:, runtime_surface:)
    IdolDirectorDispatchIndex.cdd_successor_command(
      initialize_request(provider: provider, runtime_surface: runtime_surface)
    )
  end

  def goal_receipt(semantics:, terminal_state:, last_event:)
    {
      "goal_id" => "GOAL_SUCCESSOR_FIXTURE",
      "goal_semantics" => semantics,
      "objective_sha256" => "1" * 64,
      "terminal_state" => terminal_state,
      "last_event" => last_event,
      "terminal_event_sha256" => "2" * 64
    }
  end

  def route_admit(state, receipt)
    IdolDirectorDispatchIndex.cdd_successor_command(
      "action" => "route-admit",
      "state_path" => @state_path.to_s,
      "expected_state_sha256" => state.fetch("state_sha256"),
      "expected_generation" => state.fetch("generation"),
      "source_session_id" => @source_session,
      "successor_session_id" => @successor_session,
      "admission_digest" => "3" * 64,
      "goal_receipt" => receipt,
      "recorded_at" => "2026-08-17T00:00:01Z"
    )
  end

  def route_commit(state)
    IdolDirectorDispatchIndex.cdd_successor_command(
      "action" => "route-commit",
      "state_path" => @state_path.to_s,
      "expected_state_sha256" => state.fetch("state_sha256"),
      "expected_generation" => state.fetch("generation"),
      "source_session_id" => @source_session,
      "successor_session_id" => @successor_session,
      "admission_digest" => "3" * 64,
      "founder_confirmation_sha256" => "4" * 64,
      "recorded_at" => "2026-08-17T00:00:02Z"
    )
  end

  def route_rollback(state, commit_receipt_sha256)
    IdolDirectorDispatchIndex.cdd_successor_command(
      "action" => "route-rollback",
      "state_path" => @state_path.to_s,
      "expected_state_sha256" => state.fetch("state_sha256"),
      "expected_generation" => state.fetch("generation"),
      "source_session_id" => @source_session,
      "successor_session_id" => @successor_session,
      "commit_receipt_sha256" => commit_receipt_sha256,
      "failure_receipt_sha256" => "5" * 64,
      "recorded_at" => "2026-08-17T00:00:03Z"
    )
  end

  def authorize(state, session_id, operation)
    IdolDirectorDispatchIndex.cdd_successor_command(
      "action" => "route-authorize",
      "state_path" => @state_path.to_s,
      "expected_state_sha256" => state.fetch("state_sha256"),
      "expected_generation" => state.fetch("generation"),
      "session_id" => session_id,
      "operation" => operation
    )
  end

  def assert_authorized(state, session_id, operation)
    result = authorize(state, session_id, operation)
    assert_equal "allowed", result.fetch("authorization")
    assert_match(/\A[a-f0-9]{64}\z/, result.fetch("authorization_receipt_sha256"))
  end

  def assert_denied(state, session_id, operation)
    error = assert_raises(IdolDirectorDispatchIndex::ValidationError) do
      authorize(state, session_id, operation)
    end
    assert_includes error.errors.join(" "), "denied"
  end
end
