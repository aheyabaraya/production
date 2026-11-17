# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "pathname"
require "securerandom"
require "yaml"
require_relative "support/department_dispatch_profile_fixture"

class ValidateSchemaRepairCandidateTest < Minitest::Test
  include DepartmentDispatchProfileFixture

  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  VALIDATOR = ROOT.join("scripts", "validate_schema_repair_candidate.rb")

  def setup
    @title_root = ROOT.join("runs", "harness-test", "schema-repair")
    @run = @title_root.join("SCHEMA_REPAIR_#{SecureRandom.hex(4).upcase}")
    @target = @run.join("research", "front-planning-readiness-v17.yaml")
    @candidate_dir = @run.join("work", "schema-repair-candidates", "FP_TEST")
    @candidate = @candidate_dir.join("candidate.yaml")
    @repair_receipt = @candidate_dir.join("receipt.yaml")
    @dispatch_id = "SCHEMA_REPAIR_SOURCE"
    @department_dispatch = @run.join("work", "department-dispatches", "#{@dispatch_id}.yaml")
    @target.dirname.mkpath
    @candidate_dir.mkpath
    @department_dispatch.dirname.mkpath
    @target.write("schema_version: front-planning-readiness.v17\nstatus: draft\n")
    @candidate.write("schema_version: front-planning-readiness.v17\nstatus: diagnostic\n")
    write_department_dispatch
  end

  def teardown
    FileUtils.remove_entry(@run) if @run&.directory?
    @title_root.rmdir if @title_root&.directory? && @title_root.children.empty?
    album_root = ROOT.join("runs", "harness-test")
    album_root.rmdir if album_root.directory? && album_root.children.empty?
  end

  def test_valid_candidate_proves_noncanonical_hold_and_promoted_dispatch_authorship
    write_repair_receipt(base_repair_receipt)
    _stdout, stderr, status = validate
    assert status.success?, stderr
  end

  def test_canonical_target_change_after_candidate_creation_is_blocked
    write_repair_receipt(base_repair_receipt)
    @target.write("schema_version: front-planning-readiness.v5\nstatus: script-repaired\n")
    _stdout, stderr, status = validate
    refute status.success?
    assert_includes stderr, "canonical target changed after candidate creation"
  end

  def test_creative_script_authority_cannot_be_declared_true
    document = base_repair_receipt
    document.fetch("creative_authority")["creative_defaults_inserted"] = true
    write_repair_receipt(document)
    _stdout, stderr, status = validate
    refute status.success?
    assert_match(/creative_defaults_inserted|False was expected/, stderr)
  end

  def test_candidate_must_stay_beside_receipt_under_work
    outside = @run.join("research", "repair-candidate.yaml")
    outside.write(@candidate.read)
    document = base_repair_receipt
    document["candidate_artifact"] = hashed_artifact(outside)
    write_repair_receipt(document)
    _stdout, stderr, status = validate
    refute status.success?
    assert_includes stderr, "candidate artifact must stay beside its receipt"
  end

  def test_copied_source_requires_director_review_and_promotion_binding
    dispatch = YAML.safe_load(@department_dispatch.read, aliases: true)
    dispatch.fetch("director_review")["reviewed_outputs"] = []
    @department_dispatch.write(YAML.dump(dispatch))
    write_repair_receipt(base_repair_receipt)
    _stdout, stderr, status = validate
    refute status.success?
    assert_includes stderr, "department dispatch is not promoted and valid"
    assert_includes stderr, "director review does not bind the copied source bytes"
  end

  private

  def run_relative
    @run.relative_path_from(ROOT).to_s
  end

  def relative(path)
    path.relative_path_from(ROOT).to_s
  end

  def hashed_artifact(path)
    {"path" => relative(path), "sha256" => Digest::SHA256.file(path.to_s).hexdigest}
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

  def write_department_dispatch
    document = dispatch_fixture_promoted_document(
      run_path: @run,
      dispatch_id: @dispatch_id,
      stage_id: "front_planning_integration",
      artifact_path: @target,
      owner_role: "creative_development_director",
      profile_id: "creative_development_director",
      checkpoint_id: "cdd_startup",
      assigned_owner: "test-owner",
      director_owner: "test-director",
      promotion_owner: "test-director",
      recipient_role: "creative_development_director",
      output_role: "director-reviewed source artifact",
      objective: "Bind the current model-authored source bytes for diagnostic schema repair."
    )
    document.dig("promotion", "next_recipient").merge!(
      "owner" => "schema-repair-validator",
      "role" => "diagnostic-validator",
      "return_route" => "noncanonical_schema_repair_hold"
    )
    @department_dispatch.write(YAML.dump(document))
  end

  def write_department_dispatch_v3_legacy_fixture
    target_relative = relative(@target)
    linked_read = ROOT.join("AGENTS.md")
    profile_contract = dispatch_fixture_profile_contract(
      profile_id: "creative_development_director",
      checkpoint_id: "cdd_startup"
    )
    prepared_at = "2026-08-03T11:00:00+09:00"
    launched_at = "2026-08-03T11:01:00+09:00"
    returned_at = "2026-08-03T11:02:00+09:00"
    reviewed_at = "2026-08-03T11:03:00+09:00"
    promoted_at = "2026-08-03T11:04:00+09:00"
    compiled_launch = dispatch_fixture_compiled_launch_prompt(
      profile_id: "creative_development_director",
      checkpoint_id: "cdd_startup",
      source_ids: ["repository_authority"]
    )
    launch = {
      "prepared_at" => prepared_at,
      "launched_at" => launched_at,
      "launch_kind" => "worker_dispatch",
      "compiled_launch_prompt" => compiled_launch,
      "task" => {
        "task_id" => @dispatch_id,
        "role" => "creative_development_director",
        "objective" => "Bind the current model-authored source bytes for diagnostic schema repair.",
        "exact_scope" => {
          "mode" => "whole_run",
          "stage_id" => "front_planning_integration",
          "section_ids" => [],
          "artifact_paths" => [target_relative]
        }
      },
      "founder_context" => {"decision_epoch" => "SCHEMA-REPAIR-TEST-EPOCH", "locks" => []},
      "required_skills" => profile_contract.fetch("required_skills"),
      "sources" => [
        {
          "source_id" => "repository_authority",
          "path" => relative(linked_read),
          "sha256" => Digest::SHA256.file(linked_read.to_s).hexdigest,
          "purpose" => "Authority for source-bound diagnostic repair."
        }
      ],
      "external_permission" => {"mode" => "closed_local", "allowed_surfaces" => [], "approval_reference" => nil},
      "bounded_output" => {
        "output_kind" => "bounded_artifact",
        "description" => "One source artifact returned for director review.",
        "expected_paths" => [target_relative],
        "maximum_artifact_count" => 1,
        "anti_flat_evidence_requirements" => ["Preserve the original model-authored source value without script paraphrase."]
      },
      "authority" => {
        "assigned_owner" => "test-owner",
        "director_owner" => "test-director",
        "promotion_owner" => "test-director",
        "canonical_write" => "bounded_to_expected_paths",
        "external_actions" => "forbidden",
        "may_decide" => ["Return the existing bounded source bytes."],
        "must_not" => ["Author or repair creative truth by script."]
      },
      "hold_conditions" => ["Exact source bytes or required reads cannot be preserved."],
      "recipient" => {"owner" => "test-director", "role" => "overall_mv_director", "return_route" => "director_output_review"}
    }
    skill_revisions = dispatch_fixture_runtime_skill_revisions(launch.fetch("required_skills"))
    outputs = [hashed_artifact(@target).merge("role" => "director-reviewed source artifact")]
    lineage = {
      "lineage_id" => "LINEAGE_#{@dispatch_id}",
      "attempt_id" => @dispatch_id,
      "attempt_number" => 1,
      "provider" => "codex",
      "runtime_surface" => "test-runtime",
      "session_id" => "SESSION_#{@dispatch_id}",
      "parent_session_id" => "SESSION_TEST_DIRECTOR",
      "parent_lineage_id" => "LINEAGE_TEST_DIRECTOR",
      "parent_dispatch_id" => "DISPATCH_TEST_DIRECTOR",
      "previous_attempt_id" => nil,
      "delegation_depth" => 1,
      "lineage_state" => "active",
      "successor_attempt_id" => nil
    }
    runtime_return = {
      "returned_at" => returned_at,
      "runtime_owner" => {"owner" => "test-owner", "role" => "creative_development_director", "runtime_surface" => "test-runtime"},
      "skill_revisions" => skill_revisions,
      "input_digest" => {"basis" => "lineage_and_launch_contract_canonical_json_v2", "sha256" => structured_sha({"lineage" => lineage, "launch" => launch})},
      "output_inventory" => {"mode" => "single_artifact", "artifact_count" => 1, "aggregate_manifest" => nil},
      "outputs" => outputs,
      "result_digest" => {
        "basis" => "runtime_owner_skill_revisions_output_inventory_outputs_holds_and_wake_event_canonical_json_v3",
        "sha256" => "0" * 64
      },
      "hold_reasons" => [],
      "wake_event" => {
        "event_kind" => "final",
        "recipient_role" => "overall_mv_director",
        "output_pointers" => outputs,
        "aggregate_manifest" => nil,
        "hold_or_rejection_pointers" => [],
        "risk_or_unresolved_decision_pointers" => [],
        "raw_commentary_included" => false
      }
    }
    result_basis = {
      "runtime_owner" => runtime_return["runtime_owner"],
      "skill_revisions" => runtime_return["skill_revisions"],
      "output_inventory" => runtime_return["output_inventory"],
      "outputs" => runtime_return["outputs"],
      "hold_reasons" => runtime_return["hold_reasons"],
      "wake_event" => runtime_return["wake_event"]
    }
    runtime_return.fetch("result_digest")["sha256"] = structured_sha(result_basis)
    document = {
      "schema_version" => "idol-department-dispatch.v3",
      "artifact_type" => "department_dispatch",
      "dispatch_id" => @dispatch_id,
      "run" => run_relative,
      "lineage" => lineage,
      "lifecycle" => {
        "current_state" => "promoted",
        "events" => [
          {"state" => "prepared", "at" => prepared_at, "actor" => "test-director"},
          {"state" => "launched", "at" => launched_at, "actor" => "test-runtime"},
          {"state" => "returned", "at" => returned_at, "actor" => "test-owner"},
          {"state" => "reviewed", "at" => reviewed_at, "actor" => "test-director"},
          {"state" => "promoted", "at" => promoted_at, "actor" => "test-director"}
        ]
      },
      "launch" => launch,
      "runtime_return" => runtime_return,
      "director_review" => {
        "reviewed_at" => reviewed_at,
        "director" => {"owner" => "test-director", "role" => "overall_mv_director"},
        "disposition" => "accept",
        "rubric_results" => [
          {
            "criterion" => "Source-bound creative authorship",
            "result" => "pass",
            "evidence" => "The exact existing source bytes were reviewed without script-authored repair."
          }
        ],
        "reviewed_outputs" => outputs,
        "summary" => "Director accepted the exact source bytes before diagnostic repair.",
        "correction" => nil
      },
      "promotion" => {
        "decision" => "promoted",
        "mode" => "direct_canonical_promotion",
        "decided_at" => promoted_at,
        "promoter" => {"owner" => "test-director", "role" => "overall_director"},
        "approved_at" => promoted_at,
        "reason" => "The exact source bytes passed director review.",
        "approved_working_outputs" => outputs,
        "coordinator" => nil,
        "copy_completed_at" => nil,
        "canonical_artifacts" => outputs,
        "next_recipient" => {
          "owner" => "schema-repair-validator",
          "role" => "diagnostic-validator",
          "return_route" => "noncanonical_schema_repair_hold"
        }
      }
    }
    @department_dispatch.write(YAML.dump(document))
  end

  def base_repair_receipt
    target_sha = Digest::SHA256.file(@target.to_s).hexdigest
    schema_path = ROOT.join("schemas", "front-planning-readiness.schema.json")
    {
      "schema_version" => "idol-schema-repair-candidate.v3",
      "status" => "diagnostic_hold",
      "run" => run_relative,
      "source_artifact" => hashed_artifact(@target),
      "target_artifact" => {
        "path" => relative(@target),
        "precondition" => "exists",
        "sha256_before" => target_sha
      },
      "target_contract" => {
        "schema_path" => relative(schema_path),
        "schema_sha256" => Digest::SHA256.file(schema_path.to_s).hexdigest,
        "current_authoring_version" => "front-planning-readiness.v17"
      },
      "candidate_artifact" => hashed_artifact(@candidate),
      "allowed_operations" => ["exact_copy", "container_rewrap"],
      "exact_copy_evidence" => [
        {
          "source_path" => relative(@target),
          "source_artifact_sha256" => target_sha,
          "source_json_pointer" => "/status",
          "source_value_sha256" => Digest::SHA256.hexdigest(JSON.generate("draft")),
          "target_json_pointer" => "/status",
          "department_dispatch_path" => relative(@department_dispatch),
          "department_dispatch_sha256" => Digest::SHA256.file(@department_dispatch.to_s).hexdigest
        }
      ],
      "creative_authority" => {
        "creative_values_authored_by_script" => false,
        "creative_values_paraphrased_by_script" => false,
        "creative_defaults_inserted" => false,
        "same_value_fanout_used" => false,
        "placeholder_completion_used" => false,
        "script_claimed_model_authorship" => false,
        "canonical_write_performed" => false,
        "creative_review_verdict_authored" => false
      },
      "hold_reasons" => ["Candidate cannot satisfy the Front Planning gate."],
      "promotion" => {
        "allowed" => false,
        "gate_effect" => "none_hold_only",
        "return_route" => "existing_owning_human_or_model_stage"
      }
    }
  end

  def write_repair_receipt(document)
    @repair_receipt.write(YAML.dump(document))
  end

  def validate
    Open3.capture3(
      RbConfig.ruby,
      VALIDATOR.to_s,
      relative(@repair_receipt),
      chdir: ROOT.to_s
    )
  end
end
