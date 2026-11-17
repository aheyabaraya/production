# frozen_string_literal: true

require "date"
require "digest"
require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "pathname"
require "rbconfig"
require "securerandom"
require "time"
require "yaml"
require_relative "../lib/idol_department_context"
require_relative "support/department_dispatch_profile_fixture"

class IdolDepartmentContextTest < Minitest::Test
  include DepartmentDispatchProfileFixture

  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  CLI = ROOT.join("scripts", "idol_department_context.rb")
  VALIDATOR = ROOT.join("scripts", "validate_department_dispatch.rb")
  DIRECTIVE = IdolDepartmentContext::INSTRUCTION_DELIVERY_DIRECTIVE

  def setup
    @title_root = ROOT.join("runs", "harness-test", "department-context")
    @run = @title_root.join("M01_SAEYAN_#{SecureRandom.hex(4).upcase}")
    @source = @run.join("research", "m01-saeyan-structural.yaml")
    @output = @run.join("00A-m01-saeyan-structural.yaml")
    @dispatch_id = "M01_SAEYAN_#{SecureRandom.hex(3).upcase}"
    @dispatch = @run.join("work", "department-dispatches", "#{@dispatch_id}.yaml")
    @source.dirname.mkpath
    @dispatch.dirname.mkpath
    @source.write("member_code: M01\nmember_name: Saeyan\nkind: structural_fixture\nproduction_song: false\n")
    @output.write("member_code: M01\nmember_name: Saeyan\nstatus: structural_fixture\n")
  end

  def teardown
    FileUtils.remove_entry(@run) if @run&.directory?
    @title_root.rmdir if @title_root&.directory? && @title_root.children.empty?
    album_root = ROOT.join("runs", "harness-test")
    album_root.rmdir if album_root.directory? && album_root.children.empty?
  end

  def test_prepare_m01_saeyan_freezes_snapshot_prompt_prefix_and_pack
    launched, goal = write_launched_m01
    result = IdolDepartmentContext.prepare(
      root: ROOT,
      dispatch_path: relative(@dispatch),
      dispatch_sha256: sha(@dispatch),
      runtime_goal: goal
    )

    packet = JSON.parse(result.fetch("packet_text"))
    snapshot = ROOT.join(packet.dig("source_dispatch", "path"))
    context = ROOT.join(result.dig("context_packet", "path"))
    original_prompt = launched.dig("launch", "compiled_launch_prompt", "rendered_prompt")

    assert_equal %w[context_packet packet_text], result.keys.sort
    export = m01_saeyan_compiler_boundary_fixture(result, packet)
    assert_equal result.fetch("packet_text"), export.fetch("packet_text")
    assert_equal result.fetch("context_packet"), export.fetch("context_packet")
    assert export.fetch("worker_prompt").start_with?(original_prompt)
    assert_equal Digest::SHA256.hexdigest(result.fetch("packet_text")), result.dig("context_packet", "sha256")
    assert_equal context.binread, result.fetch("packet_text").b
    assert_equal Encoding::UTF_8, result.fetch("packet_text").encoding
    assert result.fetch("packet_text").valid_encoding?
    assert_equal @dispatch.binread, snapshot.binread
    assert_equal sha(@dispatch), packet.dig("source_dispatch", "sha256")
    assert packet.fetch("worker_prompt").start_with?(original_prompt)
    assert_includes packet.fetch("worker_prompt"), DIRECTIVE
    refute_includes packet.fetch("worker_prompt"), result.dig("context_packet", "sha256")
    assert_equal Digest::SHA256.hexdigest(packet.fetch("worker_prompt")), packet.fetch("worker_prompt_sha256")
    assert_equal goal, packet.fetch("goal_binding")
    assert_equal "M01 Saeyan", packet.dig("goal_binding", "objective").slice(/M01 Saeyan/)
    assert_equal [], IdolRoleContextPack.validate_pack(
      root: ROOT,
      pack: packet.fetch("role_context_pack"),
      validation_mode: "active_promotion"
    )
    assert_equal "pass", packet.dig("role_context_pack", "status")
    assert_equal "grok-4.6", packet.dig("role_context_pack", "provider_binding", "exact_model")
    assert_equal "xhigh", packet.dig("role_context_pack", "provider_binding", "reasoning_effort")
  end

  def test_prepare_identical_m01_binding_reuses_immutable_files
    _launched, goal = write_launched_m01
    first = IdolDepartmentContext.prepare(
      root: ROOT,
      dispatch_path: relative(@dispatch),
      dispatch_sha256: sha(@dispatch),
      runtime_goal: goal
    )
    snapshot = ROOT.join(JSON.parse(first.fetch("packet_text")).dig("source_dispatch", "path"))
    context = ROOT.join(first.dig("context_packet", "path"))
    snapshot_mtime = snapshot.mtime
    context_mtime = context.mtime

    second = IdolDepartmentContext.prepare(
      root: ROOT,
      dispatch_path: relative(@dispatch),
      dispatch_sha256: sha(@dispatch),
      runtime_goal: goal
    )

    assert_equal first, second
    assert_equal snapshot_mtime, snapshot.mtime
    assert_equal context_mtime, context.mtime
  end

  def test_prepare_holds_goal_session_and_source_races_without_overwrite
    _launched, goal = write_launched_m01
    first = IdolDepartmentContext.prepare(
      root: ROOT,
      dispatch_path: relative(@dispatch),
      dispatch_sha256: sha(@dispatch),
      runtime_goal: goal
    )
    original_snapshot = ROOT.join(JSON.parse(first.fetch("packet_text")).dig("source_dispatch", "path")).binread
    original_context = ROOT.join(first.dig("context_packet", "path")).binread

    other_goal = goal.merge("native_goal_id" => "GOAL-OTHER-OWNER")
    error = assert_raises(IdolDepartmentContext::ContractError) do
      IdolDepartmentContext.prepare(
        root: ROOT,
        dispatch_path: relative(@dispatch),
        dispatch_sha256: sha(@dispatch),
        runtime_goal: other_goal
      )
    end
    assert_match(/cannot be overwritten|does not match/, error.message)

    document = load_dispatch
    document.dig("lineage")["session_id"] = "SESSION_OTHER_M01"
    write_dispatch(document)
    session_goal = goal.merge("native_session_id" => "SESSION_OTHER_M01")
    error = assert_raises(IdolDepartmentContext::ContractError) do
      IdolDepartmentContext.prepare(
        root: ROOT,
        dispatch_path: relative(@dispatch),
        dispatch_sha256: sha(@dispatch),
        runtime_goal: session_goal
      )
    end
    assert_match(/launched dispatch SHA-256 does not match|cannot be overwritten|does not match/, error.message)

    write_launched_m01
    document = load_dispatch
    document.dig("launch", "sources", 0)["sha256"] = "0" * 64
    write_dispatch(document)
    error = assert_raises(IdolDepartmentContext::ContractError) do
      IdolDepartmentContext.prepare(
        root: ROOT,
        dispatch_path: relative(@dispatch),
        dispatch_sha256: sha(@dispatch),
        runtime_goal: goal
      )
    end
    assert_match(/failed validation|stale|cannot be overwritten|does not match/, error.message)

    context_path = ROOT.join(first.dig("context_packet", "path"))
    snapshot_path = ROOT.join(JSON.parse(first.fetch("packet_text")).dig("source_dispatch", "path"))
    if snapshot_path.file?
      assert_equal original_snapshot, snapshot_path.binread
    end
    if context_path.file?
      assert_equal original_context, context_path.binread
    end
  end

  def test_validate_application_accepts_actual_m01_receipt_and_times
    launched, goal = write_launched_m01
    result = IdolDepartmentContext.prepare(
      root: ROOT,
      dispatch_path: relative(@dispatch),
      dispatch_sha256: sha(@dispatch),
      runtime_goal: goal
    )
    packet = JSON.parse(result.fetch("packet_text"))
    prepared = DateTime.iso8601(packet.fetch("prepared_at"))
    applied = (prepared.to_time.utc + 60).iso8601
    started = (prepared.to_time.utc + 120).iso8601
    returned = (prepared.to_time.utc + 180).iso8601
    receipt = application_receipt(result, packet, applied)

    assert_equal true, IdolDepartmentContext.validate_application!(
      root: ROOT,
      dispatch: launched,
      runtime_goal: goal,
      application: receipt,
      work_started_at: started,
      returned_at: returned
    )
  end

  def test_validate_application_holds_missing_live_request_id_without_copying_frozen_packet
    launched, goal = write_launched_m01
    result = IdolDepartmentContext.prepare(
      root: ROOT,
      dispatch_path: relative(@dispatch),
      dispatch_sha256: sha(@dispatch),
      runtime_goal: goal
    )
    packet = JSON.parse(result.fetch("packet_text"))
    prepared = DateTime.iso8601(packet.fetch("prepared_at"))
    applied = (prepared.to_time.utc + 60).iso8601
    started = (prepared.to_time.utc + 120).iso8601
    returned = (prepared.to_time.utc + 180).iso8601
    receipt = application_receipt(result, packet, applied)
    live_goal = goal.dup
    live_goal.delete("request_id")

    error = assert_raises(IdolDepartmentContext::ContractError) do
      IdolDepartmentContext.validate_application!(
        root: ROOT,
        dispatch: launched,
        runtime_goal: live_goal,
        application: receipt,
        work_started_at: started,
        returned_at: returned
      )
    end
    assert_match(/request_id/, error.message)
  end

  def test_validate_application_holds_source_goal_session_owner_epoch_and_receipt_mismatch
    launched, goal = write_launched_m01
    result = IdolDepartmentContext.prepare(
      root: ROOT,
      dispatch_path: relative(@dispatch),
      dispatch_sha256: sha(@dispatch),
      runtime_goal: goal
    )
    packet = JSON.parse(result.fetch("packet_text"))
    prepared = DateTime.iso8601(packet.fetch("prepared_at"))
    applied = (prepared.to_time.utc + 60).iso8601
    started = (prepared.to_time.utc + 120).iso8601
    returned = (prepared.to_time.utc + 180).iso8601
    receipt = application_receipt(result, packet, applied)

    source_drift = deep_copy(launched)
    source_drift.dig("launch", "sources", 0)["purpose"] = "tampered M01 source purpose"
    error = assert_raises(IdolDepartmentContext::ContractError) do
      IdolDepartmentContext.validate_application!(
        root: ROOT,
        dispatch: source_drift,
        runtime_goal: goal,
        application: receipt,
        work_started_at: started,
        returned_at: returned
      )
    end
    assert_match(/launch|source|does not match/, error.message)

    error = assert_raises(IdolDepartmentContext::ContractError) do
      IdolDepartmentContext.validate_application!(
        root: ROOT,
        dispatch: launched,
        runtime_goal: goal.merge("native_goal_id" => "GOAL-DRIFT-M01"),
        application: receipt,
        work_started_at: started,
        returned_at: returned
      )
    end
    assert_match(/Goal binding|native_goal/, error.message)

    session_drift = deep_copy(launched)
    session_drift.dig("lineage")["session_id"] = "SESSION_DRIFT_M01"
    error = assert_raises(IdolDepartmentContext::ContractError) do
      IdolDepartmentContext.validate_application!(
        root: ROOT,
        dispatch: session_drift,
        runtime_goal: goal,
        application: receipt,
        work_started_at: started,
        returned_at: returned
      )
    end
    assert_match(/session|lineage|does not match/, error.message)

    owner_drift = deep_copy(launched)
    owner_drift.dig("launch", "authority")["assigned_owner"] = "other-m01-owner"
    error = assert_raises(IdolDepartmentContext::ContractError) do
      IdolDepartmentContext.validate_application!(
        root: ROOT,
        dispatch: owner_drift,
        runtime_goal: goal,
        application: receipt,
        work_started_at: started,
        returned_at: returned
      )
    end
    assert_match(/authority|owner|does not match/, error.message)

    epoch_drift = deep_copy(launched)
    epoch_drift.dig("launch", "founder_context")["decision_epoch"] = "FOUNDER-EPOCH-OTHER-M01"
    error = assert_raises(IdolDepartmentContext::ContractError) do
      IdolDepartmentContext.validate_application!(
        root: ROOT,
        dispatch: epoch_drift,
        runtime_goal: goal,
        application: receipt,
        work_started_at: started,
        returned_at: returned
      )
    end
    assert_match(/epoch|does not match/, error.message)

    bad_receipt = receipt.merge("pack_digest" => "0" * 64)
    error = assert_raises(IdolDepartmentContext::ContractError) do
      IdolDepartmentContext.validate_application!(
        root: ROOT,
        dispatch: launched,
        runtime_goal: goal,
        application: bad_receipt,
        work_started_at: started,
        returned_at: returned
      )
    end
    assert_match(/pack identity|pack_digest/, error.message)

    extra = receipt.merge("creative_pass" => true)
    error = assert_raises(IdolDepartmentContext::ContractError) do
      IdolDepartmentContext.validate_application!(
        root: ROOT,
        dispatch: launched,
        runtime_goal: goal,
        application: extra,
        work_started_at: started,
        returned_at: returned
      )
    end
    assert_match(/unknown fields/, error.message)
  end

  def test_legacy_eof_acceptance_and_rejection_unchanged
    document = grok_bind!(m01_promoted_document)
    write_dispatch(document)
    stdout, stderr, status = validate_dispatch("--json")
    assert status.success?, [stdout, stderr].join("\n")
    assert_equal "pass", JSON.parse(stdout).fetch("status")

    empty = deep_copy(document)
    empty.dig("runtime_return")["skill_revisions"] = []
    refresh_result_digest!(empty)
    write_dispatch(empty)
    _stdout, stderr, status = validate_dispatch
    refute status.success?
    assert_includes stderr, "runtime skill revisions must exact-copy launch skill/read revisions and record EOF"

    error = assert_raises(IdolDepartmentContext::ContractError) do
      IdolDepartmentContext.prepare(
        root: ROOT,
        dispatch_path: relative(@dispatch),
        dispatch_sha256: sha(@dispatch),
        runtime_goal: native_goal_for(document)
      )
    end
    assert_match(/instruction_delivery|launched|unsupported|role_context_pack/, error.message)
  end

  def test_projected_return_uses_receipt_and_rejects_legacy_eof_bytes
    promoted = grok_bind!(m01_promoted_document)
    promoted.dig("launch")["instruction_delivery"] = "role_context_pack"
    refresh_input_digest!(promoted)
    launched = to_launched(promoted)
    write_dispatch(launched)
    goal = native_goal_for(launched)
    result = IdolDepartmentContext.prepare(
      root: ROOT,
      dispatch_path: relative(@dispatch),
      dispatch_sha256: sha(@dispatch),
      runtime_goal: goal
    )
    packet = JSON.parse(result.fetch("packet_text"))
    prepared = DateTime.iso8601(packet.fetch("prepared_at"))
    returned = finish_projected_promoted!(promoted, result, packet, prepared)
    write_dispatch(returned)

    stdout, stderr, status = validate_dispatch("--json")
    assert status.success?, [stdout, stderr].join("\n")
    payload = JSON.parse(stdout)
    assert_equal "pass", payload.fetch("status")
    assert_equal "promoted", payload.fetch("lifecycle_state")
    assert_equal goal.fetch("request_id"), packet.dig("goal_binding", "request_id")
    assert_equal goal.fetch("request_id"), returned.dig("runtime_return", "runtime_goal", "request_id")
    js_basis = {
      "work_started_at" => returned.dig("runtime_return", "work_started_at"),
      "runtime_owner" => returned.dig("runtime_return", "runtime_owner"),
      "runtime_goal" => returned.dig("runtime_return", "runtime_goal"),
      "role_context_receipt" => returned.dig("runtime_return", "role_context_receipt"),
      "skill_revisions" => returned.dig("runtime_return", "skill_revisions"),
      "mechanical_compliance_receipt" => returned.dig("runtime_return", "mechanical_compliance_receipt"),
      "worker_fulfillment_claims" => returned.dig("runtime_return", "worker_fulfillment_claims"),
      "output_inventory" => returned.dig("runtime_return", "output_inventory"),
      "outputs" => returned.dig("runtime_return", "outputs"),
      "hold_reasons" => returned.dig("runtime_return", "hold_reasons"),
      "wake_event" => returned.dig("runtime_return", "wake_event")
    }
    assert_equal dispatch_fixture_structured_sha(js_basis), returned.dig("runtime_return", "result_digest", "sha256")

    leftover = deep_copy(returned)
    leftover.dig("runtime_return")["skill_revisions"] = dispatch_fixture_runtime_skill_revisions(
      leftover.dig("launch", "required_skills"),
      read_completed_at: leftover.dig("runtime_return", "work_started_at")
    )
    refresh_result_digest!(leftover)
    write_dispatch(leftover)
    _stdout, stderr, status = validate_dispatch
    refute status.success?
    assert_match(/empty skill_revisions|schema validation failed|maxItems/, stderr)
  end

  def test_projected_return_holds_missing_attested_request_id_without_packet_fallback
    promoted = grok_bind!(m01_promoted_document)
    promoted.dig("launch")["instruction_delivery"] = "role_context_pack"
    refresh_input_digest!(promoted)
    launched = to_launched(promoted)
    write_dispatch(launched)
    goal = native_goal_for(launched)
    result = IdolDepartmentContext.prepare(
      root: ROOT,
      dispatch_path: relative(@dispatch),
      dispatch_sha256: sha(@dispatch),
      runtime_goal: goal
    )
    packet = JSON.parse(result.fetch("packet_text"))
    prepared = DateTime.iso8601(packet.fetch("prepared_at"))
    returned = finish_projected_promoted!(promoted, result, packet, prepared)
    assert_equal goal.fetch("request_id"), packet.dig("goal_binding", "request_id")
    returned.dig("runtime_return", "runtime_goal").delete("request_id")
    refresh_result_digest!(returned)
    write_dispatch(returned)

    stdout, stderr, status = validate_dispatch("--json")
    refute status.success?
    assert_match(/request_id/, [stdout, stderr].join("\n"))
  end

  def test_prepare_refuses_other_provider_and_graph_v2
    launched, goal = write_launched_m01
    launched.dig("lineage")["provider"] = "cursor"
    launched.dig("routing_identity")["provider"] = "cursor"
    write_dispatch(launched)
    error = assert_raises(IdolDepartmentContext::ContractError) do
      IdolDepartmentContext.prepare(
        root: ROOT,
        dispatch_path: relative(@dispatch),
        dispatch_sha256: sha(@dispatch),
        runtime_goal: goal.merge("provider" => "cursor")
      )
    end
    assert_match(/provider other than grok|must be grok/, error.message)

    launched, goal = write_launched_m01
    launched["schema_version"] = "idol-graph-department-dispatch.v1"
    launched["artifact_type"] = "graph_department_dispatch"
    write_dispatch(launched)
    error = assert_raises(IdolDepartmentContext::ContractError) do
      IdolDepartmentContext.prepare(
        root: ROOT,
        dispatch_path: relative(@dispatch),
        dispatch_sha256: sha(@dispatch),
        runtime_goal: goal
      )
    end
    assert_match(/Graph v2/, error.message)
  end

  def test_failed_partial_publish_holds_and_cli_round_trip
    _launched, goal = write_launched_m01
    document = load_dispatch
    snapshot_rel, context_rel = IdolDepartmentContext.derived_context_paths(
      document.fetch("run"),
      document.fetch("dispatch_id"),
      document.dig("lineage", "attempt_id")
    )
    context_path = ROOT.join(context_rel)
    context_path.dirname.mkpath
    context_path.mkpath
    error = assert_raises(IdolDepartmentContext::ContractError) do
      IdolDepartmentContext.prepare(
        root: ROOT,
        dispatch_path: relative(@dispatch),
        dispatch_sha256: sha(@dispatch),
        runtime_goal: goal
      )
    end
    assert_match(/partial|cannot be overwritten|not a file/, error.message)
    FileUtils.remove_entry(context_path)

    stdout, stderr, status = cli(
      "action" => "prepare",
      "dispatch_path" => relative(@dispatch),
      "dispatch_sha256" => sha(@dispatch),
      "runtime_goal" => goal
    )
    assert status.success?, [stdout, stderr].join("\n")
    prepared = JSON.parse(stdout)
    packet = JSON.parse(prepared.fetch("packet_text"))
    applied = (DateTime.iso8601(packet.fetch("prepared_at")).to_time.utc + 60).iso8601
    started = (DateTime.iso8601(packet.fetch("prepared_at")).to_time.utc + 120).iso8601
    returned = (DateTime.iso8601(packet.fetch("prepared_at")).to_time.utc + 180).iso8601
    stdout, stderr, status = cli(
      "action" => "validate",
      "dispatch_path" => relative(@dispatch),
      "dispatch_sha256" => sha(@dispatch),
      "runtime_goal" => goal,
      "application" => application_receipt(prepared, packet, applied),
      "work_started_at" => started,
      "returned_at" => returned
    )
    assert status.success?, [stdout, stderr].join("\n")
    assert_equal({"ok" => true}, JSON.parse(stdout))

    stdout, _stderr, status = cli("action" => "media")
    refute status.success?
    assert_equal "hold", JSON.parse(stdout).fetch("status")
    assert_match(/unsupported action/, JSON.parse(stdout).fetch("error"))
  end

  def test_prepare_accepts_genuine_17_field_goal_and_rejects_wrong_assignment_key
    launched, goal = write_launched_m01
    goal17 = goal.merge(
      "state" => "active",
      "command" => "open",
      "turn_id" => "turn-m01-saeyan-1",
      "provider_prompt_id" => "prompt-m01-saeyan-1"
    )
    result = IdolDepartmentContext.prepare(
      root: ROOT,
      dispatch_path: relative(@dispatch),
      dispatch_sha256: sha(@dispatch),
      runtime_goal: goal17
    )
    packet = JSON.parse(result.fetch("packet_text"))
    assert_equal goal, packet.fetch("goal_binding")
    refute packet.fetch("goal_binding").key?("state")

    error = assert_raises(IdolDepartmentContext::ContractError) do
      IdolDepartmentContext.prepare(
        root: ROOT,
        dispatch_path: relative(@dispatch),
        dispatch_sha256: sha(@dispatch),
        runtime_goal: goal.merge("assignment_key" => "wrong-m01-key")
      )
    end
    assert_match(/assignment_key/, error.message)

    launched.dig("launch", "authority")["assigned_owner"] = "department_worker:m01-saeyan"
    write_dispatch(launched)
    prefixed = goal.merge("assignment_key" => "m01-saeyan")
    FileUtils.remove_entry(@run.join("work", "department-dispatches", "contexts"), force: true)
    result = IdolDepartmentContext.prepare(
      root: ROOT,
      dispatch_path: relative(@dispatch),
      dispatch_sha256: sha(@dispatch),
      runtime_goal: prefixed
    )
    assert_equal "m01-saeyan", JSON.parse(result.fetch("packet_text")).dig("goal_binding", "assignment_key")
  end

  def test_prepare_same_second_goal_observed_orders_before_prepared_at
    launched, goal = write_launched_m01
    now = Time.now.utc
    observed = Time.utc(now.year, now.month, now.day, now.hour, now.min, now.sec, 1)
    result = IdolDepartmentContext.prepare(
      root: ROOT,
      dispatch_path: relative(@dispatch),
      dispatch_sha256: sha(@dispatch),
      runtime_goal: goal.merge("observed_at" => observed.iso8601(6))
    )
    prepared = DateTime.iso8601(JSON.parse(result.fetch("packet_text")).fetch("prepared_at"))
    assert prepared >= DateTime.iso8601(observed.iso8601(6))
    assert_match(/\.\d{6}/, JSON.parse(result.fetch("packet_text")).fetch("prepared_at"))
  end

  def test_prepare_holds_symlink_parent_inside_and_outside_root_and_hardlink
    _launched, goal = write_launched_m01
    contexts = @run.join("work", "department-dispatches", "contexts")
    FileUtils.mkdir_p(contexts.dirname)

    outside = ROOT.join("..", "m01-saeyan-outside-#{SecureRandom.hex(2)}")
    FileUtils.rm_rf(contexts)
    File.symlink(outside, contexts)
    error = assert_raises(IdolDepartmentContext::ContractError) do
      IdolDepartmentContext.prepare(
        root: ROOT,
        dispatch_path: relative(@dispatch),
        dispatch_sha256: sha(@dispatch),
        runtime_goal: goal
      )
    end
    assert_match(/symlink/, error.message)
    FileUtils.rm_f(contexts)

    File.symlink(@run.join("research"), contexts)
    error = assert_raises(IdolDepartmentContext::ContractError) do
      IdolDepartmentContext.prepare(
        root: ROOT,
        dispatch_path: relative(@dispatch),
        dispatch_sha256: sha(@dispatch),
        runtime_goal: goal
      )
    end
    assert_match(/symlink/, error.message)
    FileUtils.rm_f(contexts)

    sibling = @dispatch.dirname.join("sibling-#{@dispatch_id}.yaml")
    File.link(@dispatch, sibling)
    error = assert_raises(IdolDepartmentContext::ContractError) do
      IdolDepartmentContext.prepare(
        root: ROOT,
        dispatch_path: relative(@dispatch),
        dispatch_sha256: sha(@dispatch),
        runtime_goal: goal
      )
    end
    assert_match(/hardlink/, error.message)
    File.delete(sibling)
  end

  def test_prepare_holds_raced_selected_source_bytes
    _launched, goal = write_launched_m01
    old_sha = sha(@dispatch)
    @dispatch.write(@dispatch.binread + "# raced-m01-source\n")
    error = assert_raises(IdolDepartmentContext::ContractError) do
      IdolDepartmentContext.prepare(
        root: ROOT,
        dispatch_path: relative(@dispatch),
        dispatch_sha256: old_sha,
        runtime_goal: goal
      )
    end
    assert_match(/SHA-256 does not match/, error.message)
  end

  def test_validate_application_holds_recomputed_pack_digest_and_prompt_suffix
    launched, goal = write_launched_m01
    result = IdolDepartmentContext.prepare(
      root: ROOT,
      dispatch_path: relative(@dispatch),
      dispatch_sha256: sha(@dispatch),
      runtime_goal: goal
    )
    packet = JSON.parse(result.fetch("packet_text"))
    prepared = DateTime.iso8601(packet.fetch("prepared_at"))
    applied = (prepared.to_time.utc + 60).iso8601
    started = (prepared.to_time.utc + 120).iso8601
    returned = (prepared.to_time.utc + 180).iso8601
    context_rel = result.dig("context_packet", "path")

    tampered_pack = deep_copy(packet)
    tampered_pack.dig("role_context_pack", "founder_context")["locks"] = [{"lock_id" => "tampered-m01"}]
    projection = tampered_pack.dig("role_context_pack", "projection")
    projection["pack_digest"] = IdolRoleContextPack.structured_sha256(
      tampered_pack.fetch("role_context_pack").reject { |key, _| key == "projection" }.merge(
        "projection" => projection.reject { |key, _| key == "pack_digest" }
      )
    )
    tampered_bytes = JSON.pretty_generate(tampered_pack) + "\n"
    File.open(ROOT.join(context_rel), File::WRONLY | File::TRUNC) { |file| file.write(tampered_bytes) }
    receipt = application_receipt(result, tampered_pack, applied)
    receipt["context_packet"] = {"path" => context_rel, "sha256" => Digest::SHA256.hexdigest(tampered_bytes)}
    receipt["pack_digest"] = projection["pack_digest"]
    error = assert_raises(IdolDepartmentContext::ContractError) do
      IdolDepartmentContext.validate_application!(
        root: ROOT,
        dispatch: launched,
        runtime_goal: goal,
        application: receipt,
        work_started_at: started,
        returned_at: returned
      )
    end
    assert_match(/role_context_pack|worker_prompt|does not equal/, error.message)

    suffix = JSON.parse(result.fetch("packet_text"))
    suffix["worker_prompt"] = "#{suffix['worker_prompt']}\nmalicious M01 suffix"
    suffix["worker_prompt_sha256"] = Digest::SHA256.hexdigest(suffix["worker_prompt"])
    suffix_bytes = JSON.pretty_generate(suffix) + "\n"
    File.open(ROOT.join(context_rel), File::WRONLY | File::TRUNC) { |file| file.write(suffix_bytes) }
    suffix_receipt = application_receipt(result, suffix, applied)
    suffix_receipt["context_packet"] = {"path" => context_rel, "sha256" => Digest::SHA256.hexdigest(suffix_bytes)}
    error = assert_raises(IdolDepartmentContext::ContractError) do
      IdolDepartmentContext.validate_application!(
        root: ROOT,
        dispatch: launched,
        runtime_goal: goal,
        application: suffix_receipt,
        work_started_at: started,
        returned_at: returned
      )
    end
    assert_match(/worker_prompt/, error.message)
  end

  def write_launched_m01
    promoted = grok_bind!(m01_promoted_document)
    promoted.dig("launch")["instruction_delivery"] = "role_context_pack"
    refresh_input_digest!(promoted)
    launched = to_launched(promoted)
    write_dispatch(launched)
    [launched, native_goal_for(launched)]
  end

  def m01_promoted_document
    dispatch_fixture_promoted_document(
      run_path: @run,
      dispatch_id: @dispatch_id,
      stage_id: "song_production_lock",
      artifact_path: @output,
      owner_role: "song_room",
      profile_id: "song_room_00a",
      checkpoint_id: "selected_audio_analysis",
      assigned_owner: "fixture-m01-saeyan-worker",
      director_owner: "fixture-m01-saeyan-director",
      objective: "Return the exact M01 Saeyan structural fixture record for independent Director review. This is not a production song or media run."
    )
  end

  def grok_bind!(document)
    document.fetch("lineage").merge!(
      "provider" => "grok",
      "runtime_surface" => "grok_build_cli_acp"
    )
    routing = document.fetch("routing_identity")
    routing["provider"] = "grok"
    routing["resolved_provider_model"] = "grok-4.6"
    routing["reasoning_effort"] = "xhigh"
    routing["execution_profile_id"] = routing["logical_profile_alias"].to_s == "director_deep" ? "grok_director_deep" : "grok_worker_high"
    if document["runtime_return"].is_a?(Hash)
      document.dig("runtime_return", "runtime_goal")["provider"] = "grok"
      document.dig("runtime_return", "runtime_owner")["runtime_surface"] = "grok_build_cli_acp"
    end
    refresh_input_digest!(document)
    refresh_result_digest!(document) if document["runtime_return"].is_a?(Hash)
    document
  end

  def to_launched(document)
    launched = deep_copy(document)
    launched["runtime_return"] = nil
    launched["director_review"] = nil
    launched["promotion"] = nil
    launched["lifecycle"] = {
      "current_state" => "launched",
      "events" => Array(document.dig("lifecycle", "events")).first(2)
    }
    launched["review_control"] = {
      "queue_policy" => document.dig("review_control", "queue_policy"),
      "queue_state" => "not_eligible",
      "queued_at" => nil,
      "queue_priority" => document.dig("review_control", "queue_priority"),
      "review_lease" => nil,
      "promotion_lease" => nil
    }
    launched
  end

  def native_goal_for(document, observed_at: "2026-08-03T12:01:10+09:00")
    objective = document.dig("launch", "task", "objective").to_s
    {
      "provider" => "grok",
      "native_goal_id" => "GOAL-M01-SAEYAN-#{document['dispatch_id']}",
      "native_session_id" => document.dig("lineage", "session_id"),
      "assignment_key" => document.dig("launch", "authority", "assigned_owner"),
      "dispatch_id" => document["dispatch_id"],
      "attempt_id" => document.dig("lineage", "attempt_id"),
      "runtime_surface" => "grok_build_cli_acp",
      "goal_text_sha256" => Digest::SHA256.hexdigest(objective),
      "raw_event_sha256" => Digest::SHA256.hexdigest("m01-saeyan-acp-goal-#{document['dispatch_id']}"),
      "observed_at" => observed_at,
      "evidence_source" => "grok_acp_goal_updated_event",
      "objective" => objective,
      "request_id" => "REQ-M01-SAEYAN-#{document['dispatch_id']}"
    }
  end

  def self.m01_saeyan_compiler_boundary_fixture(result, packet)
    {
      "context_packet" => result.fetch("context_packet"),
      "packet_text" => result.fetch("packet_text"),
      "worker_prompt" => packet.fetch("worker_prompt"),
      "goal_binding" => packet.fetch("goal_binding"),
      "role_context_pack" => packet.fetch("role_context_pack"),
      "source_dispatch" => packet.fetch("source_dispatch")
    }
  end

  def m01_saeyan_compiler_boundary_fixture(result, packet)
    self.class.m01_saeyan_compiler_boundary_fixture(result, packet)
  end

  def application_receipt(result, packet, applied_at)
    pack = packet.fetch("role_context_pack")
    goal = packet.fetch("goal_binding")
    {
      "schema_version" => "idol-department-context-application.v1",
      "context_packet" => result.fetch("context_packet"),
      "dispatch_id" => packet.fetch("dispatch_id"),
      "attempt_id" => packet.fetch("attempt_id"),
      "dispatch_input_sha256" => packet.fetch("dispatch_input_sha256"),
      "native_goal_id" => goal.fetch("native_goal_id"),
      "native_session_id" => goal.fetch("native_session_id"),
      "native_goal_raw_event_sha256" => goal.fetch("raw_event_sha256"),
      "pack_id" => pack.fetch("pack_id"),
      "pack_digest" => pack.dig("projection", "pack_digest"),
      "source_set_sha256" => pack.dig("projection", "source_set_sha256"),
      "instruction_content_sha256" => pack.dig("projection", "instruction_content_sha256"),
      "applied_at" => applied_at
    }
  end

  def finish_projected_promoted!(document, result, packet, prepared)
    returned = deep_copy(document)
    utc = prepared.to_time.utc
    work = (utc + 60).iso8601
    mech = (utc + 120).iso8601
    done = (utc + 180).iso8601
    review_acq = (utc + 240).iso8601
    reviewed = (utc + 300).iso8601
    review_rel = (utc + 360).iso8601
    promo_acq = (utc + 420).iso8601
    promoted_at = (utc + 480).iso8601
    promo_rel = (utc + 540).iso8601
    runtime = returned.fetch("runtime_return")
    runtime["skill_revisions"] = []
    runtime["work_started_at"] = work
    runtime["returned_at"] = done
    runtime["role_context_receipt"] = application_receipt(result, packet, (utc + 30).iso8601)
    runtime.dig("runtime_goal")["opened_at"] = packet.dig("goal_binding", "observed_at")
    runtime.dig("runtime_goal")["observed_at"] = packet.dig("goal_binding", "observed_at")
    runtime.dig("runtime_goal")["native_goal_id"] = packet.dig("goal_binding", "native_goal_id")
    runtime.dig("runtime_goal")["request_id"] = packet.dig("goal_binding", "request_id")
    runtime.dig("runtime_goal")["provider"] = packet.dig("goal_binding", "provider")
    runtime.dig("runtime_goal")["objective"] = packet.dig("goal_binding", "objective")
    runtime.dig("runtime_goal")["native_session_id"] = packet.dig("goal_binding", "native_session_id")
    runtime.dig("runtime_goal")["assignment_key"] = packet.dig("goal_binding", "assignment_key")
    runtime.dig("runtime_goal")["dispatch_id"] = packet.dig("goal_binding", "dispatch_id")
    runtime.dig("runtime_goal")["attempt_id"] = packet.dig("goal_binding", "attempt_id")
    runtime.dig("runtime_goal")["runtime_surface"] = packet.dig("goal_binding", "runtime_surface")
    runtime.dig("runtime_goal")["raw_event_sha256"] = packet.dig("goal_binding", "raw_event_sha256")
    runtime.dig("runtime_goal")["evidence_source"] = packet.dig("goal_binding", "evidence_source")
    runtime.dig("runtime_goal")["goal_text_sha256"] = packet.dig("goal_binding", "goal_text_sha256")
    runtime.dig("mechanical_compliance_receipt")["validated_at"] = mech
    refresh_mechanical!(returned)
    runtime.dig("wake_event")
    events = returned.dig("lifecycle", "events")
    events[2]["at"] = done
    events[3]["at"] = reviewed
    events[4]["at"] = promoted_at
    returned.dig("review_control")["queued_at"] = done
    returned.dig("review_control", "review_lease")["acquired_at"] = review_acq
    returned.dig("review_control", "review_lease")["released_at"] = review_rel
    returned.dig("review_control", "promotion_lease")["acquired_at"] = promo_acq
    returned.dig("review_control", "promotion_lease")["released_at"] = promo_rel
    returned.dig("director_review")["reviewed_at"] = reviewed
    Array(returned.dig("director_review", "reviewer_read_closure")).each do |row|
      row["read_completed_at"] = (utc + 270).iso8601
    end
    returned.dig("director_review")["mechanical_receipt_sha256"] = runtime.dig("mechanical_compliance_receipt", "receipt_sha256")
    returned.dig("promotion")["decided_at"] = promoted_at
    returned.dig("promotion")["approved_at"] = promoted_at
    refresh_input_digest!(returned)
    refresh_result_digest!(returned)
    refresh_promotion_baseline!(returned)
    returned
  end

  def refresh_mechanical!(document)
    receipt = document.dig("runtime_return", "mechanical_compliance_receipt")
    receipt["receipt_sha256"] = dispatch_fixture_structured_sha(receipt.reject { |key, _value| key == "receipt_sha256" })
  end

  def refresh_input_digest!(document)
    runtime = document["runtime_return"]
    return unless runtime.is_a?(Hash)

    runtime["input_digest"]["sha256"] = dispatch_fixture_structured_sha(
      "lineage" => document["lineage"],
      "review_submission" => document["review_submission"],
      "launch" => document["launch"]
    )
  end

  def refresh_result_digest!(document)
    runtime = document.fetch("runtime_return")
    completion = {
      "mechanical_compliance_receipt_sha256" => runtime.dig("mechanical_compliance_receipt", "receipt_sha256"),
      "worker_fulfillment_claims" => runtime["worker_fulfillment_claims"],
      "outputs" => runtime["outputs"],
      "hold_reasons" => runtime["hold_reasons"]
    }
    runtime.dig("runtime_goal")["completion_evidence_sha256"] = dispatch_fixture_structured_sha(completion)
    basis = {
      "work_started_at" => runtime["work_started_at"],
      "runtime_owner" => runtime["runtime_owner"],
      "runtime_goal" => runtime["runtime_goal"],
      "skill_revisions" => runtime["skill_revisions"],
      "mechanical_compliance_receipt" => runtime["mechanical_compliance_receipt"],
      "worker_fulfillment_claims" => runtime["worker_fulfillment_claims"],
      "output_inventory" => runtime["output_inventory"],
      "outputs" => runtime["outputs"],
      "hold_reasons" => runtime["hold_reasons"],
      "wake_event" => runtime["wake_event"]
    }
    if runtime["role_context_receipt"]
      basis["role_context_receipt"] = runtime["role_context_receipt"]
    end
    runtime.fetch("result_digest")["sha256"] = dispatch_fixture_structured_sha(basis)
  end

  def refresh_promotion_baseline!(document)
    promotion = document.fetch("promotion")
    basis = {
      "dispatch_id" => document.fetch("dispatch_id"),
      "review_lease_id" => document.dig("director_review", "review_lease_id"),
      "promotion_lease_id" => promotion["promotion_lease_id"],
      "decision" => promotion["decision"],
      "approved_working_outputs" => promotion["approved_working_outputs"],
      "canonical_artifacts" => promotion["canonical_artifacts"],
      "decided_at" => promotion["decided_at"]
    }
    promotion["baseline_refresh_evidence_sha256"] = dispatch_fixture_structured_sha(basis)
  end

  def write_dispatch(document)
    @dispatch.write(YAML.dump(document))
  end

  def load_dispatch
    YAML.safe_load(@dispatch.read, permitted_classes: [Date, Time], aliases: true)
  end

  def relative(path)
    path.relative_path_from(ROOT).to_s
  end

  def sha(path)
    Digest::SHA256.file(path.to_s).hexdigest
  end

  def deep_copy(value)
    Marshal.load(Marshal.dump(value))
  end

  def validate_dispatch(*arguments)
    Open3.capture3(
      RbConfig.ruby,
      VALIDATOR.to_s,
      *arguments,
      relative(@dispatch),
      chdir: ROOT.to_s
    )
  end

  def cli(payload)
    Open3.capture3(
      RbConfig.ruby,
      CLI.to_s,
      "--root",
      ROOT.to_s,
      stdin_data: JSON.generate(payload),
      chdir: ROOT.to_s
    )
  end
end
