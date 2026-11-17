# frozen_string_literal: true

require "fileutils"
require "digest"
require "json"
require "minitest/autorun"
require "open3"
require "pathname"
require "securerandom"
require "yaml"
require_relative "support/department_dispatch_profile_fixture"

class IdolHarnessStateFrontPlanningGateTest < Minitest::Test
  include DepartmentDispatchProfileFixture

  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  SCRIPT = ROOT.join("scripts", "idol_harness_state_check.rb")

  def setup
    @title_root = ROOT.join("runs", "harness-test", "front-planning-gate")
    @run = @title_root.join("FP_GATE_#{SecureRandom.hex(5).upcase}")
    @run.mkpath
    @run.join("run-manifest.yaml").write(
      YAML.dump(
        "schema_version" => "idol-run-manifest.v1",
        "status" => "active",
        "album_key" => "harness-test",
        "title_key" => "front-planning-gate",
        "run_id" => @run.basename.to_s,
        "content_id" => @run.basename.to_s,
        "canonical_run_root" => @run.relative_path_from(ROOT).to_s,
        "artifact_revision_owner" => "git",
        "compatibility_authoring" => "forbidden"
      )
    )
  end

  def teardown
    FileUtils.remove_entry(@run) if @run&.directory?
    @title_root.rmdir if @title_root&.directory? && @title_root.children.empty?
    album_root = ROOT.join("runs", "harness-test")
    album_root.rmdir if album_root.directory? && album_root.children.empty?
  end

  def test_locked_00a_requires_front_planning_disposition_before_01_exists
    @run.join("00A-song-lock.yaml").write("schema_version: '1.5'\nstatus: locked\n")
    legacy_receipt = @run.join("work", "skill-application-receipts", "song_production_lock", "whole.yaml")
    legacy_receipt.dirname.mkpath
    legacy_receipt.write("schema_version: idol-skill-application-receipt.v3\nstatus: complete\n")

    report = run_state_check
    check = report.fetch("checks").find { |row| row["id"] == "front_planning_readiness" }
    refute_nil check
    assert_equal "missing", check["status"]
    assert_equal true, check["blocking"]
    assert_includes report.fetch("blocking_checks"), "front_planning_readiness"

    dispatch_check = report.fetch("checks").find { |row| row["id"] == "stage_department_dispatch" }
    refute_nil dispatch_check
    assert_equal "missing", dispatch_check["status"]
    assert_equal true, dispatch_check["blocking"]
    assert_includes report.fetch("blocking_checks"), "stage_department_dispatch"
    assert_nil report.fetch("checks").find { |row| row["id"] == "stage_skill_application_receipts" }
  end

  def test_empty_pre_stage_run_keeps_front_planning_disposition_nonblocking_until_00a_locks
    report = run_state_check
    check = report.fetch("checks").find { |row| row["id"] == "front_planning_readiness" }
    refute_nil check
    assert_equal "missing", check["status"]
    assert_equal false, check["blocking"]
    refute_includes report.fetch("blocking_checks"), "front_planning_readiness"

    dispatch_check = report.fetch("checks").find { |row| row["id"] == "stage_department_dispatch" }
    refute_nil dispatch_check
    assert_equal "pass", dispatch_check["status"]
    assert_equal false, dispatch_check["blocking"]
  end

  def test_promoted_department_dispatch_satisfies_active_song_lock_gate
    song_lock = @run.join("00A-song-lock.yaml")
    song_lock.write("schema_version: '1.5'\nstatus: locked\n")
    write_promoted_dispatch(song_lock)

    report = run_state_check
    dispatch_check = report.fetch("checks").find { |row| row["id"] == "stage_department_dispatch" }
    refute_nil dispatch_check
    assert_equal "pass", dispatch_check["status"], dispatch_check["details"]
    assert_equal false, dispatch_check["blocking"]
    refute_includes report.fetch("blocking_checks"), "stage_department_dispatch"
    assert_includes dispatch_check["details"], "director_disposition=accept"
  end

  def test_exact_legacy_whole_receipt_carries_only_unchanged_bytes_as_frozen_baseline
    song_lock = @run.join("00A-song-lock.yaml")
    song_lock.write("schema_version: '1.5'\nstatus: locked\n")
    write_legacy_stage_receipt(song_lock, "song_production_lock")

    report = run_state_check
    dispatch_check = report.fetch("checks").find { |row| row["id"] == "stage_department_dispatch" }
    refute_nil dispatch_check
    assert_equal "pass", dispatch_check["status"], dispatch_check["details"]
    assert_includes dispatch_check["details"], "compatibility=evidence_only_non_authoring"
    assert_includes dispatch_check["details"], "next_material_resumption_requires_dispatch=true"
    assert_includes dispatch_check["details"], "must not be refreshed"
  end

  def test_changed_bytes_invalidate_legacy_baseline_and_require_dispatch
    song_lock = @run.join("00A-song-lock.yaml")
    song_lock.write("schema_version: '1.5'\nstatus: locked\n")
    write_legacy_stage_receipt(song_lock, "song_production_lock")
    song_lock.write("schema_version: '1.5'\nstatus: materially_changed\n")

    report = run_state_check
    dispatch_check = report.fetch("checks").find { |row| row["id"] == "stage_department_dispatch" }
    refute_nil dispatch_check
    assert_equal "missing", dispatch_check["status"]
    assert_equal true, dispatch_check["blocking"]
    assert_includes dispatch_check["details"], "No single stage-local legacy receipt independently binds"
    assert_includes dispatch_check["details"], "stale_or_ineligible_whole="
  end

  def test_new_same_stage_launch_disables_legacy_baseline_fallback
    song_lock = @run.join("00A-song-lock.yaml")
    song_lock.write("schema_version: '1.5'\nstatus: locked\n")
    write_legacy_stage_receipt(song_lock, "song_production_lock")
    dispatch_path = write_promoted_dispatch(song_lock)
    dispatch = YAML.safe_load(dispatch_path.read, aliases: true)
    dispatch.fetch("lifecycle")["current_state"] = "launched"
    dispatch.fetch("lifecycle")["events"] = dispatch.fetch("lifecycle").fetch("events").first(2)
    dispatch["runtime_return"] = nil
    dispatch["director_review"] = nil
    dispatch["promotion"] = nil
    dispatch_path.write(YAML.dump(dispatch))

    report = run_state_check
    dispatch_check = report.fetch("checks").find { |row| row["id"] == "stage_department_dispatch" }
    refute_nil dispatch_check
    assert_equal "fail", dispatch_check["status"]
    assert_equal true, dispatch_check["blocking"]
    assert_includes dispatch_check["details"], "must be promoted for this active gate"
    refute_includes dispatch_check["details"], "compatibility=evidence_only_non_authoring"
  end

  def test_su_v12_shape_uses_newest_scoped_exact_receipt_and_rejects_stale_whole
    readiness = @run.join("research", "front-planning-readiness-v12.yaml")
    readiness.dirname.mkpath
    readiness.write("schema_version: front-planning-readiness.v17\nstatus: founder_review\nrevision: 11\n")
    stale_whole = write_legacy_stage_receipt(readiness, "front_planning_integration")
    readiness.write("schema_version: front-planning-readiness.v17\nstatus: founder_review\nrevision: 12\n")
    scoped = write_legacy_stage_receipt(
      readiness,
      "front_planning_integration",
      receipt_name: "M11_CURRENT_V12.yaml",
      scope_mode: "section",
      section_id: "M11_CURRENT_V12"
    )
    newer_time = stale_whole.mtime + 2
    File.utime(newer_time, newer_time, scoped)

    report = run_state_check
    %w[stage_department_dispatch front_planning_department_dispatch].each do |check_id|
      dispatch_check = report.fetch("checks").find { |row| row["id"] == check_id }
      refute_nil dispatch_check
      assert_equal "pass", dispatch_check["status"], dispatch_check["details"]
      assert_includes dispatch_check["details"], "legacy_baseline=#{relative(scoped)}"
      refute_includes dispatch_check["details"], "legacy_baseline=#{relative(stale_whole)}"
      assert_includes dispatch_check["details"], "not combined with another receipt"
    end
  end

  def test_front_planning_entry_gate_requires_the_promoted_readiness_dispatch
    readiness = @run.join("research", "front-planning-readiness-v99.yaml")
    readiness.dirname.mkpath
    readiness.write("schema_version: front-planning-readiness.v17\nstatus: draft\n")
    write_promoted_dispatch(
      readiness,
      dispatch_id: "FRONT_PLANNING_GATE",
      stage_id: "front_planning_integration",
      skill_name: "idol-front-planning-director",
      owner_role: "creative_development_director"
    )

    report = run_state_check
    dispatch_check = report.fetch("checks").find { |row| row["id"] == "front_planning_department_dispatch" }
    refute_nil dispatch_check
    assert_equal "pass", dispatch_check["status"], dispatch_check["details"]
    assert_equal false, dispatch_check["blocking"]
    refute_includes report.fetch("blocking_checks"), "front_planning_department_dispatch"
  end

  def test_superseded_revision_contracts_do_not_block_active_run_state
    superseded = @run.join("work", "superseded", "repair", "sections", "S00.yaml")
    superseded.dirname.mkpath
    superseded.write(<<~YAML)
      schema_version: idol-harness-artifact-envelope.v1
      deliberately_invalid_archive_evidence: true
    YAML

    report = run_state_check
    check = report.fetch("checks").find { |row| row["id"] == "revisioned_artifact_contracts" }
    refute_nil check
    assert_equal "missing", check["status"]
    assert_equal false, check["blocking"]
    refute_includes report.fetch("blocking_checks"), "revisioned_artifact_contracts"
    refute_includes check["artifact"], "superseded"
  end

  def test_grok_handoff_founder_guard_accepts_the_stronger_unconditional_form
    report = run_state_check
    check = report.fetch("checks").find { |row| row["id"] == "grok_drive_write_guards" }

    refute_nil check
    assert_equal "pass", check["status"], check["details"]
  end

  def test_audio_lineage_schema_result_is_not_executed_twice
    source = SCRIPT.read

    assert_includes source, "audio_schema_check = add_schema_check("
    refute_includes source, "_lineage_stdout, _lineage_stderr, lineage_schema_exit = capture_command"
  end

  private

  def relative(path)
    path.relative_path_from(ROOT).to_s
  end

  def file_sha(path)
    Digest::SHA256.file(path.to_s).hexdigest
  end

  def canonicalize(value)
    case value
    when Hash
      value.keys.map(&:to_s).sort.each_with_object({}) do |key, result|
        original_key = value.key?(key) ? key : value.keys.find { |candidate| candidate.to_s == key }
        result[key] = canonicalize(value[original_key])
      end
    when Array
      value.map { |item| canonicalize(item) }
    else
      value
    end
  end

  def structured_sha(value)
    Digest::SHA256.hexdigest(JSON.generate(canonicalize(value)))
  end

  def write_legacy_stage_receipt(artifact, stage_id, receipt_name: "whole.yaml", scope_mode: "whole_run", section_id: nil)
    baseline = @run.join("work", "skill-application-receipts", stage_id, receipt_name)
    baseline.dirname.mkpath
    artifact_binding = {"path" => relative(artifact), "sha256" => file_sha(artifact)}
    baseline.write(YAML.dump(
      "schema_version" => "idol-skill-application-receipt.v3",
      "run" => relative(@run),
      "stage_id" => stage_id,
      "scope" => {"mode" => scope_mode, "section_id" => section_id},
      "owner" => "legacy-fixture-owner",
      "owning_skill" => {
        "path" => "skills/idol-song-lock/SKILL.md",
        "sha256" => "0" * 64,
        "read_complete" => true,
        "reason" => "Frozen pre-dispatch baseline evidence."
      },
      "application_evidence" => [
        {
          "rule_id" => "legacy_fixture",
          "source_path" => "AGENTS.md",
          "applied_to" => relative(artifact),
          "application" => "Historical application evidence only."
        }
      ],
      "output_targets" => [relative(artifact)],
      "output_evidence" => [artifact_binding],
      "creative_authorship" => {"script_authored_creative_values" => false},
      "status" => "complete"
    ))
    baseline
  end

  def write_promoted_dispatch(artifact, dispatch_id: "SONG_LOCK_GATE", stage_id: "song_production_lock", skill_name: "idol-song-lock", owner_role: "song_room")
    cdd_route = skill_name == "idol-front-planning-director"
    document = dispatch_fixture_promoted_document(
      run_path: @run,
      dispatch_id: dispatch_id,
      stage_id: stage_id,
      artifact_path: artifact,
      owner_role: owner_role,
      profile_id: cdd_route ? "creative_development_director" : "song_room_00a",
      checkpoint_id: cdd_route ? "cdd_startup" : "selected_audio_analysis"
    )
    dispatch_path = @run.join("work", "department-dispatches", "#{dispatch_id}.yaml")
    dispatch_path.dirname.mkpath
    dispatch_path.write(YAML.dump(document))
    dispatch_path
  end

  def write_promoted_dispatch_v3_legacy_fixture(artifact, dispatch_id: "SONG_LOCK_GATE", stage_id: "song_production_lock", skill_name: "idol-song-lock", owner_role: "song_room")
    dispatch_path = @run.join("work", "department-dispatches", "#{dispatch_id}.yaml")
    dispatch_path.dirname.mkpath
    authority_source = ROOT.join("AGENTS.md")
    output = {"path" => relative(artifact), "sha256" => file_sha(artifact), "role" => "active stage artifact"}
    prepared_at = "2026-08-03T12:00:00+09:00"
    launched_at = "2026-08-03T12:01:00+09:00"
    returned_at = "2026-08-03T12:02:00+09:00"
    reviewed_at = "2026-08-03T12:03:00+09:00"
    promoted_at = "2026-08-03T12:04:00+09:00"
    cdd_route = skill_name == "idol-front-planning-director"
    profile_id = cdd_route ? "creative_development_director" : "song_room_00a"
    checkpoint_id = cdd_route ? "cdd_startup" : "selected_audio_analysis"
    profile_contract = dispatch_fixture_profile_contract(profile_id: profile_id, checkpoint_id: checkpoint_id)
    compiled_launch = dispatch_fixture_compiled_launch_prompt(
      profile_id: profile_id,
      checkpoint_id: checkpoint_id,
      source_ids: ["repository_authority"]
    )
    launch = {
      "prepared_at" => prepared_at,
      "launched_at" => launched_at,
      "launch_kind" => "worker_dispatch",
      "compiled_launch_prompt" => compiled_launch,
      "task" => {
        "task_id" => dispatch_id,
        "role" => owner_role,
        "objective" => "Return the exact active stage artifact for director review.",
        "exact_scope" => {
          "mode" => "whole_run",
          "stage_id" => stage_id,
          "section_ids" => [],
          "artifact_paths" => [relative(artifact)]
        }
      },
      "founder_context" => {"decision_epoch" => "STATE-GATE-TEST-EPOCH", "locks" => []},
      "required_skills" => profile_contract.fetch("required_skills"),
      "sources" => [
        {
          "source_id" => "repository_authority",
          "path" => relative(authority_source),
          "sha256" => file_sha(authority_source),
          "purpose" => "Repository and stage authority for the bounded song lock."
        }
      ],
      "external_permission" => {"mode" => "closed_local", "allowed_surfaces" => [], "approval_reference" => nil},
      "bounded_output" => {
        "output_kind" => "bounded_artifact",
        "description" => "One active stage artifact.",
        "expected_paths" => [relative(artifact)],
        "maximum_artifact_count" => 1,
        "anti_flat_evidence_requirements" => ["Preserve the selected stage decision and concrete rationale."]
      },
      "authority" => {
        "assigned_owner" => "fixture-worker",
        "director_owner" => "fixture-director",
        "promotion_owner" => "fixture-director",
        "canonical_write" => "bounded_to_expected_paths",
        "external_actions" => "forbidden",
        "may_decide" => ["Bounded active-stage content."],
        "must_not" => ["Change another stage or use an external surface."]
      },
      "hold_conditions" => ["Required source or skill bytes cannot be loaded exactly."],
      "recipient" => {"owner" => "fixture-director", "role" => "overall_mv_director", "return_route" => "director_output_review"}
    }
    skill_revisions = dispatch_fixture_runtime_skill_revisions(launch.fetch("required_skills"))
    runtime_return = {
      "returned_at" => returned_at,
      "runtime_owner" => {"owner" => "fixture-worker", "role" => owner_role, "runtime_surface" => "test-runtime"},
      "skill_revisions" => skill_revisions,
      "input_digest" => {"basis" => "lineage_and_launch_contract_canonical_json_v2", "sha256" => "0" * 64},
      "output_inventory" => {"mode" => "single_artifact", "artifact_count" => 1, "aggregate_manifest" => nil},
      "outputs" => [output],
      "result_digest" => {
        "basis" => "runtime_owner_skill_revisions_output_inventory_outputs_holds_and_wake_event_canonical_json_v3",
        "sha256" => "0" * 64
      },
      "hold_reasons" => [],
      "wake_event" => {
        "event_kind" => "final",
        "recipient_role" => "overall_mv_director",
        "output_pointers" => [output],
        "aggregate_manifest" => nil,
        "hold_or_rejection_pointers" => [],
        "risk_or_unresolved_decision_pointers" => [],
        "raw_commentary_included" => false
      }
    }
    lineage = {
      "lineage_id" => "LINEAGE_#{dispatch_id}",
      "attempt_id" => dispatch_id,
      "attempt_number" => 1,
      "provider" => "codex",
      "runtime_surface" => "test-runtime",
      "session_id" => "SESSION_#{dispatch_id}",
      "parent_session_id" => "SESSION_FIXTURE_DIRECTOR",
      "parent_lineage_id" => "LINEAGE_FIXTURE_DIRECTOR",
      "parent_dispatch_id" => "DISPATCH_FIXTURE_DIRECTOR",
      "previous_attempt_id" => nil,
      "delegation_depth" => 1,
      "lineage_state" => "active",
      "successor_attempt_id" => nil
    }
    runtime_return.fetch("input_digest")["sha256"] = structured_sha({"lineage" => lineage, "launch" => launch})
    result_basis = {
      "runtime_owner" => runtime_return["runtime_owner"],
      "skill_revisions" => runtime_return["skill_revisions"],
      "output_inventory" => runtime_return["output_inventory"],
      "outputs" => runtime_return["outputs"],
      "hold_reasons" => runtime_return["hold_reasons"],
      "wake_event" => runtime_return["wake_event"]
    }
    runtime_return.fetch("result_digest")["sha256"] = structured_sha(result_basis)
    dispatch_path.write(YAML.dump(
      "schema_version" => "idol-department-dispatch.v3",
      "artifact_type" => "department_dispatch",
      "dispatch_id" => dispatch_id,
      "run" => relative(@run),
      "lineage" => lineage,
      "lifecycle" => {
        "current_state" => "promoted",
        "events" => [
          {"state" => "prepared", "at" => prepared_at, "actor" => "fixture-director"},
          {"state" => "launched", "at" => launched_at, "actor" => "test-runtime"},
          {"state" => "returned", "at" => returned_at, "actor" => "fixture-worker"},
          {"state" => "reviewed", "at" => reviewed_at, "actor" => "fixture-director"},
          {"state" => "promoted", "at" => promoted_at, "actor" => "fixture-director"}
        ]
      },
      "launch" => launch,
      "runtime_return" => runtime_return,
      "director_review" => {
        "reviewed_at" => reviewed_at,
        "director" => {"owner" => "fixture-director", "role" => "overall_mv_director"},
        "disposition" => "accept",
        "rubric_results" => [
          {"criterion" => "Source-bound song-lock review", "result" => "pass", "evidence" => "The director reviewed the exact active song-lock bytes."}
        ],
        "reviewed_outputs" => [output],
        "summary" => "The bounded song lock passed director review.",
        "correction" => nil
      },
      "promotion" => {
        "decision" => "promoted",
        "mode" => "direct_canonical_promotion",
        "decided_at" => promoted_at,
        "promoter" => {"owner" => "fixture-director", "role" => "overall_director"},
        "approved_at" => promoted_at,
        "reason" => "The active song lock passed director review.",
        "approved_working_outputs" => [output],
        "coordinator" => nil,
        "copy_completed_at" => nil,
        "canonical_artifacts" => [output],
        "next_recipient" => {"owner" => "fixture-orchestrator", "role" => "next-stage-coordinator", "return_route" => "active_harness_stage"}
      }
    ))
    dispatch_path
  end

  def run_state_check
    stdout, stderr, _status = Open3.capture3(
      RbConfig.ruby,
      SCRIPT.to_s,
      @run.relative_path_from(ROOT).to_s,
      "--json",
      chdir: ROOT.to_s
    )
    JSON.parse(stdout)
  rescue JSON::ParserError => error
    flunk("state checker did not emit JSON: #{error.message}\nstdout=#{stdout}\nstderr=#{stderr}")
  end
end
