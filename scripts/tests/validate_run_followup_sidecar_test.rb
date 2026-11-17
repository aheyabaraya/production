# frozen_string_literal: true

require "digest"
require "json"
require "minitest/autorun"
require "open3"
require "pathname"
require "tmpdir"
require "yaml"

class ValidateRunFollowupSidecarTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  VALIDATOR = ROOT.join("scripts", "validate_run_followup_sidecar.rb")
  FIXTURE = ROOT.join("scripts", "tests", "fixtures", "run-followup-sidecar-valid.yaml")
  FIXTURE_V2 = ROOT.join("scripts", "tests", "fixtures", "run-followup-sidecar-v2-valid.yaml")
  FIXTURE_V3 = ROOT.join("scripts", "tests", "fixtures", "run-followup-sidecar-v3-valid.yaml")

  def test_valid_fixture_passes
    stdout, stderr, status = run_sidecar(FIXTURE)
    assert status.success?, "#{stdout}\n#{stderr}"
    assert_includes stdout, "run-followup-sidecar: pass"
  end

  def test_v2_valid_fixture_passes
    stdout, stderr, status = run_sidecar(FIXTURE_V2)
    assert status.success?, "#{stdout}\n#{stderr}"
    assert_includes stdout, "run-followup-sidecar: pass"
    assert_empty YAML.safe_load(FIXTURE_V2.read).fetch("issues")
  end

  def test_v3_valid_fixture_passes_without_raw_founder_text
    stdout, stderr, status = run_sidecar(FIXTURE_V3)
    assert status.success?, "#{stdout}\n#{stderr}"
    assert_includes stdout, "run-followup-sidecar: pass"
    document = YAML.safe_load(FIXTURE_V3.read)
    %w[verbatim verbatim_or_marker raw_feedback raw_commentary full_transcript session_transcript].each do |key|
      refute contains_key?(document, key), "v3 fixture must not carry #{key}"
    end
  end

  def test_v2_fixture_artifact_bindings_match_exact_bytes
    closure = YAML.safe_load(FIXTURE_V2.read).fetch("founder_creative_closures").first
    bindings = [
      closure.dig("named_target", "baseline_artifact"),
      *closure.dig("director_interpretation", "observable_evidence_refs"),
      *closure.dig("director_interpretation", "positive_preservation_evidence"),
      closure.fetch("correction_binding"),
      *closure.dig("correction_binding", "frozen_unaffected_outputs"),
      closure.dig("corrected_result", "artifact")
    ]

    bindings.each do |binding|
      path = ROOT.join(binding.fetch("path"))
      assert path.file?, "missing fixture evidence #{binding.fetch('path')}"
      assert_equal Digest::SHA256.file(path.to_s).hexdigest, binding.fetch("sha256")
    end
  end

  def test_v3_raw_founder_feedback_key_is_rejected
    refute_v3_mutation("must not copy raw Founder feedback key verbatim") do |document|
      document["founder_creative_closures"][0]["founder_input"]["verbatim"] = "duplicated raw feedback"
    end
  end

  def test_v3_repeated_reason_must_merge_into_one_recurrence_row
    refute_v3_mutation("recurrence_key must be unique") do |document|
      duplicate = Marshal.load(Marshal.dump(document["founder_creative_closures"][0]))
      duplicate["closure_id"] = "FCF_FIXTURE_LOCAL_002"
      document["founder_creative_closures"] << duplicate
      document["briefing"]["founder_creative_closure_ids"] << duplicate["closure_id"]
    end
  end

  def test_v3_different_reason_adds_a_new_compact_row
    Dir.mktmpdir do |dir|
      document = YAML.safe_load(FIXTURE_V3.read)
      added = Marshal.load(Marshal.dump(document["founder_creative_closures"][0]))
      added["closure_id"] = "FCF_FIXTURE_LOCAL_002"
      added["recurrence_key"] = "local_camera_distance_mismatch"
      added["reason_summary"] = "The camera distance removes the member reaction that carries the named beat."
      added["evidence_rollup_sha256"] = "d" * 64
      document["founder_creative_closures"] << added
      document["briefing"]["founder_creative_closure_ids"] << added["closure_id"]
      path = write_clone(dir, document)
      stdout, stderr, status = run_sidecar(path)
      assert status.success?, "#{stdout}\n#{stderr}"
    end
  end

  def test_v3_evidence_window_is_bounded
    refute_v3_mutation("schema failed") do |document|
      closure = document["founder_creative_closures"][0]
      closure["recurrence_count"] = 10
      closure["later_evidence_refs"] = 9.times.map do |index|
        {
          "path" => "scripts/tests/fixtures/run-followup-sidecar-valid.yaml",
          "sha256" => "bb377b2a054a2f2f0b109f52033d6e09caa6628ad93cc43394201c2cc7616604",
          "role" => "bounded_evidence_#{index}"
        }
      end
    end
  end

  def test_v3_source_pointer_requires_content_digest
    refute_v3_mutation("schema failed") do |document|
      document["founder_creative_closures"][0]["founder_input"]["source"].delete("content_sha256")
    end
  end

  def test_v3_typed_judgment_profile_evolution_proposal_passes
    Dir.mktmpdir do |dir|
      document = YAML.safe_load(FIXTURE_V3.read)
      document["issues"] = [judgment_evolution_issue]
      document["briefing"]["open_issue_ids"] = ["HIR_JUDGMENT_EVOLUTION_001"]
      path = write_clone(dir, document)
      stdout, stderr, status = run_sidecar(path)
      assert status.success?, "#{stdout}\n#{stderr}"
    end
  end

  def test_v3_minimum_floor_evolution_requires_founder_approval
    refute_v3_judgment_evolution_mutation("founder_approval_required") do |proposal|
      proposal["change_kind"] = "minimum_floor"
      proposal["founder_approval_required"] = false
    end
  end

  def test_v3_critical_four_evolution_requires_founder_approval
    refute_v3_judgment_evolution_mutation("founder_approval_required") do |proposal|
      proposal["change_kind"] = "critical_four"
      proposal["founder_approval_required"] = false
    end
  end

  def test_v3_not_applicable_rule_evolution_requires_founder_approval
    refute_v3_judgment_evolution_mutation("founder_approval_required") do |proposal|
      proposal["change_kind"] = "not_applicable_rule"
      proposal["founder_approval_required"] = false
    end
  end

  def test_v3_judgment_evolution_rejects_aggregate_score
    refute_v3_judgment_evolution_mutation("aggregate") do |proposal|
      proposal["aggregate_score"] = 17
    end
  end

  def test_v3_judgment_evolution_cannot_change_current_pointer
    refute_v3_judgment_evolution_mutation("schema failed") do |proposal|
      proposal["authority"]["current_pointer_effect"] = "update"
    end
  end

  def test_v2_correction_binding_matches_department_dispatch_correction_unit
    closure = YAML.safe_load(FIXTURE_V2.read).fetch("founder_creative_closures").first
    binding = closure.fetch("correction_binding")
    source = YAML.safe_load(ROOT.join(binding.fetch("path")).read)
    dispatch_schema = JSON.parse(ROOT.join("schemas", "department-dispatch.schema.json").read)
    sidecar_schema = JSON.parse(ROOT.join("schemas", "harness-improvement-review.schema.json").read)

    assert_equal source.fetch("dispatch_id"), binding.fetch("dispatch_id")
    assert_kind_of Hash, source.dig("director_review", "correction")
    dispatch_pointer = dispatch_schema.dig("$defs", "correctionSource", "properties", "json_pointer", "const")
    sidecar_pointer = sidecar_schema.dig("$defs", "correctionBinding", "properties", "json_pointer", "const")
    assert_equal "/director_review/correction", dispatch_pointer
    assert_equal dispatch_pointer, sidecar_pointer
    assert_equal dispatch_pointer, binding.fetch("json_pointer")
  end

  def test_v1_fixture_still_passes_when_v2_schema_exists
    stdout, stderr, status = run_sidecar(FIXTURE)
    assert status.success?, "#{stdout}\n#{stderr}"
    refute_includes File.read(FIXTURE), "founder_creative_closures"
  end

  def test_missing_sidecar_fails_when_required
    _stdout, stderr, status = Open3.capture3(
      "ruby",
      VALIDATOR.to_s,
      "--run",
      "runs/harness-test/department-dispatch/DISPATCH_MISSING",
      "--require",
      chdir: ROOT.to_s
    )
    refute status.success?
    assert_includes stderr, "run_followup sidecar"
  end

  def test_require_on_material_does_not_fail_for_empty_run
    stdout, stderr, status = Open3.capture3(
      "ruby",
      VALIDATOR.to_s,
      "--run",
      "runs/harness-test/department-dispatch/DISPATCH_MISSING",
      "--require-on-material",
      chdir: ROOT.to_s
    )
    assert status.success?, "#{stdout}\n#{stderr}"
    assert_includes stdout, "run-followup-sidecar: pass"
  end

  def test_auto_skill_save_target_is_rejected
    Dir.mktmpdir do |dir|
      path = write_clone(dir, YAML.safe_load(FIXTURE.read))
      document = YAML.safe_load(path.read)
      document["issues"][0]["harness_followup"]["target_surfaces"] = ["auto_skill_save"]
      path.write(YAML.dump(document))
      _stdout, stderr, status = run_sidecar(path)
      refute status.success?
      assert_includes stderr, "auto_skill_save"
    end
  end

  def test_v2_studio_promotion_without_founder_confirmation_fails
    refute_v2_mutation("studio preference candidate requires Founder confirmation") do |document|
      closure = document["founder_creative_closures"][0]
      closure["status"] = "preference_candidate_recorded"
      closure["preference_scope"] = "studio_preference_candidate"
      closure["preference_candidate"] = {
        "promotion_state" => "studio_preference_candidate",
        "auto_lock" => false,
        "founder_confirmation" => nil,
        "evidence_refs" => []
      }
    end
  end

  def test_v2_auto_lock_is_rejected
    refute_v2_mutation("auto lock") do |document|
      document["founder_creative_closures"][0]["shadow_authority"]["auto_preference_lock"] = true
    end
  end

  def test_v2_preference_scope_must_match_promotion_state
    refute_v2_mutation("preference scope must match promotion state") do |document|
      closure = document["founder_creative_closures"][0]
      closure["status"] = "preference_candidate_recorded"
      closure["preference_scope"] = "same_track_candidate"
      closure["preference_candidate"] = {
        "promotion_state" => "local_named_scope_only",
        "auto_lock" => false,
        "founder_confirmation" => nil,
        "evidence_refs" => []
      }
    end
  end

  def test_v2_same_track_candidate_requires_recurrence_evidence
    refute_v2_mutation("schema failed") do |document|
      closure = document["founder_creative_closures"][0]
      closure["status"] = "preference_candidate_recorded"
      closure["preference_scope"] = "same_track_candidate"
      closure["recurrence_count"] = 1
      closure["later_evidence_refs"] = []
      closure["preference_candidate"] = {
        "promotion_state" => "same_track_candidate",
        "auto_lock" => false,
        "founder_confirmation" => nil,
        "evidence_refs" => []
      }
    end
  end

  def test_v2_worker_self_claim_cannot_close_correction
    refute_v2_mutation("worker self-claim cannot close the correction") do |document|
      document["founder_creative_closures"][0]["corrected_result"]["closed_by"] = "worker_self_claim"
    end
  end

  def test_v2_numeric_or_similarity_scores_are_rejected
    %w[creative_score similarity_score beauty_score numeric_score weighted_total].each do |score_key|
      refute_v2_mutation(score_key) do |document|
        document["founder_creative_closures"][0][score_key] = 4
      end
    end
  end

  def test_v2_active_gate_is_rejected
    refute_v2_mutation("active gate") do |document|
      document["closeout"]["release_gate_effect"] = "blocks_release"
    end
  end

  def test_v2_missing_baseline_or_corrected_sha_fails
    refute_v2_mutation("schema failed") do |document|
      document["founder_creative_closures"][0]["named_target"]["baseline_artifact"].delete("sha256")
    end
  end

  def test_v2_missing_do_not_infer_when_correction_present_fails
    refute_v2_mutation("do_not_infer") do |document|
      document["founder_creative_closures"][0]["director_interpretation"]["change_contract"]["do_not_infer"] = []
    end
  end

  def test_v2_requires_an_issue_or_founder_creative_closure
    refute_v2_mutation("schema failed") do |document|
      document["founder_creative_closures"] = []
      document["briefing"]["founder_creative_closure_ids"] = []
    end
  end

  def test_v1_document_with_v2_only_keys_fails
    Dir.mktmpdir do |dir|
      document = YAML.safe_load(FIXTURE.read)
      document["founder_creative_closures"] = []
      path = write_clone(dir, document)
      _stdout, stderr, status = run_sidecar(path)
      refute status.success?
      assert_includes stderr, "schema failed"
    end
  end

  def test_unknown_schema_version_fails
    Dir.mktmpdir do |dir|
      document = YAML.safe_load(FIXTURE.read)
      document["schema_version"] = "idol_harness_improvement_review.v9"
      path = write_clone(dir, document)
      _stdout, stderr, status = run_sidecar(path)
      refute status.success?
      assert_match(/unknown|schema failed/i, stderr)
    end
  end

  private

  def run_sidecar(path)
    Open3.capture3(
      "ruby",
      VALIDATOR.to_s,
      "--sidecar",
      path.to_s,
      chdir: ROOT.to_s
    )
  end

  def write_clone(dir, document)
    path = Pathname.new(dir).join("harness-improvement-review.yaml")
    path.write(YAML.dump(document))
    path
  end

  def refute_v2_mutation(token)
    Dir.mktmpdir do |dir|
      document = YAML.safe_load(FIXTURE_V2.read)
      yield document
      path = write_clone(dir, document)
      _stdout, stderr, status = run_sidecar(path)
      refute status.success?, stderr
      assert_includes stderr, token
    end
  end

  def refute_v3_mutation(token)
    Dir.mktmpdir do |dir|
      document = YAML.safe_load(FIXTURE_V3.read)
      yield document
      path = write_clone(dir, document)
      _stdout, stderr, status = run_sidecar(path)
      refute status.success?, stderr
      assert_includes stderr, token
    end
  end

  def refute_v3_judgment_evolution_mutation(token)
    Dir.mktmpdir do |dir|
      document = YAML.safe_load(FIXTURE_V3.read)
      issue = judgment_evolution_issue
      yield issue.fetch("harness_followup").fetch("judgment_profile_evolution")
      document["issues"] = [issue]
      document["briefing"]["open_issue_ids"] = [issue.fetch("issue_id")]
      path = write_clone(dir, document)
      _stdout, stderr, status = run_sidecar(path)
      refute status.success?, stderr
      assert_includes stderr, token
    end
  end

  def judgment_evolution_issue
    evidence = {
      "path" => "scripts/tests/fixtures/run-followup-sidecar-valid.yaml",
      "sha256" => "bb377b2a054a2f2f0b109f52033d6e09caa6628ad93cc43394201c2cc7616604",
      "role" => "judgment_profile_evolution_evidence"
    }
    {
      "issue_id" => "HIR_JUDGMENT_EVOLUTION_001",
      "summary" => "A criterion admits a repeatable false positive at this checkpoint.",
      "material_trigger" => "same_failure_recurred",
      "detected_stage_id" => "front_planning",
      "earliest_owner_stage_id" => "pre_00",
      "affected_scope" => "reference_candidate profile at reference selection",
      "recurrence_key" => "judgment_profile_false_positive",
      "recurrence_count" => 2,
      "evidence_refs" => [evidence],
      "current_run_resolution" => {
        "status" => "resolved",
        "note" => "The current run was corrected without changing the profile.",
        "evidence_refs" => [evidence]
      },
      "harness_followup" => {
        "status" => "proposed",
        "target_surfaces" => ["automation/graph-creative-judgment-registry.yaml"],
        "proposal" => "Shadow-test a clearer evidence contract for this criterion.",
        "overfit_guard" => "Require a counterexample and a separate pilot before considering promotion.",
        "verification_status" => "pending_future_run",
        "verification_evidence" => [],
        "judgment_profile_evolution" => {
          "profile_id" => "reference_candidate",
          "checkpoint_ids" => ["p2_visual_reference_development"],
          "criterion_id" => "source_to_screen_transfer_boundary",
          "change_kind" => "evidence_contract",
          "observed_failure_mode" => "A prose-only transfer claim can appear complete without visible source-to-screen evidence.",
          "decision_evidence" => [evidence],
          "counterexample_or_negative_control" => {
            "kind" => "negative_control",
            "claim" => "A visually specific transfer with the same prose should remain eligible under the candidate rule.",
            "evidence_refs" => [evidence]
          },
          "founder_approval_required" => false,
          "lifecycle_stage" => "proposal",
          "authority" => {
            "aggregate_score_usage" => "forbidden",
            "automatic_criterion_tuning" => false,
            "current_pointer_effect" => "none",
            "required_sequence" => "proposal_then_shadow_then_pilot_then_separate_current_pointer_promotion",
            "current_pointer_promotion_requires_founder_approval" => true
          }
        }
      }
    }
  end

  def contains_key?(value, key)
    case value
    when Hash
      value.key?(key) || value.values.any? { |item| contains_key?(item, key) }
    when Array
      value.any? { |item| contains_key?(item, key) }
    else
      false
    end
  end
end
