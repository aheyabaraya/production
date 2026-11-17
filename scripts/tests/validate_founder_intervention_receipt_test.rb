# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "pathname"
require "tmpdir"
require "yaml"

class ValidateFounderInterventionReceiptTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  SCRIPT = ROOT.join("scripts", "validate_founder_intervention_receipt.rb")

  def test_receipt_preserves_verbatim_input_and_blocks_stale_artifact_hash
    Dir.mktmpdir("idol-founder-intervention-", "/private/tmp") do |directory|
      root = Pathname.new(directory)
      run_rel = "runs/test-album/intervention/TEST_INTERVENTION"
      run = root.join(run_rel)
      receipt_dir = run.join("review", "founder-interventions")
      receipt_dir.mkpath
      artifact = run.join("01-song-choreography-performance-mv-map.yaml")
      artifact.write("schema_version: '1.4'\n")
      artifact_rel = artifact.relative_path_from(root).to_s
      receipt = receipt_dir.join("FI_TEST_01.yaml")
      receipt.write(YAML.dump(
        "schema_version" => "idol-founder-intervention-receipt.v1",
        "artifact_type" => "founder_intervention_receipt",
        "intervention_id" => "FI_TEST_01",
        "run" => run_rel,
        "recorded_at" => "2026-07-17T22:00:00+09:00",
        "source" => {
          "surface" => "codex_task",
          "locator" => "task:test",
          "founder_input_verbatim" => "S03의 카메라를 더 낮게 유지한다."
        },
        "authority" => {
          "classification" => "clarification",
          "explicit_lock" => false,
          "scope_statement" => "S03 camera clarification only"
        },
        "routing" => {
          "owning_stage_id" => "mv_performance_direction",
          "required_owner_skill" => "idol-mv-director",
          "affected_section_ids" => ["S03"],
          "affected_artifacts" => [{
            "path" => artifact_rel,
            "sha256" => Digest::SHA256.file(artifact).hexdigest,
            "role" => "owning creative artifact"
          }],
          "earliest_reauthor_stage_id" => "mv_performance_direction",
          "downstream_invalidation_targets" => [],
          "integration_order" => "revise_owning_upstream_section_then_reproject_and_revalidate_only_affected_downstream"
        },
        "change_contract" => {
          "preserve" => ["S03 story action"],
          "change" => ["S03 camera height"],
          "do_not_infer" => ["No changes to other sections"]
        },
        "status" => "captured",
        "integration_receipt" => nil
      ))

      stdout, stderr, status = Open3.capture3(
        "ruby", SCRIPT.to_s, receipt.relative_path_from(root).to_s, "--root", root.to_s,
        chdir: ROOT.to_s
      )
      assert status.success?, [stdout, stderr].join("\n")

      artifact.write("schema_version: '1.4'\nchanged: true\n")
      _stdout, stale_stderr, stale_status = Open3.capture3(
        "ruby", SCRIPT.to_s, receipt.relative_path_from(root).to_s, "--root", root.to_s,
        chdir: ROOT.to_s
      )
      refute stale_status.success?
      assert_includes stale_stderr, "SHA-256 is stale"
    end
  end

  def test_v2_founder_direct_update_binds_baseline_fields_and_mandatory_checks
    Dir.mktmpdir("idol-founder-direct-update-", "/private/tmp") do |directory|
      root = Pathname.new(directory)
      run_rel = "runs/test-album/founder-direct/TEST_FOUNDER_DIRECT"
      run = root.join(run_rel)
      receipt_dir = run.join("review", "founder-interventions")
      receipt_dir.mkpath
      baseline = run.join("review", "baseline-review.yaml")
      baseline.write("status: passed\n")
      storyboard = run.join("02A-master-storyboard.yaml")
      storyboard.write(YAML.dump(
        "schema_version" => "1.7",
        "master_storyboard" => [
          {"cut_id" => "C001", "composition" => "Founder selected low three-quarter frame"}
        ]
      ))
      storyboard_doc = YAML.safe_load(storyboard.read)
      selected_value = storyboard_doc.dig("master_storyboard", 0, "composition")
      receipt = receipt_dir.join("FI_TEST_DIRECT_01.yaml")
      required_checks = [
        "schema_and_hash_integrity",
        "reference_and_identity_integrity",
        "safety_and_feasibility",
        "pixel_or_playback_qa_when_output_exists",
        "external_and_paid_approval_when_applicable"
      ]
      receipt.write(YAML.dump(
        "schema_version" => "idol-founder-intervention-receipt.v2",
        "artifact_type" => "founder_intervention_receipt",
        "intervention_id" => "FI_TEST_DIRECT_01",
        "run" => run_rel,
        "recorded_at" => "2026-07-23T22:00:00+09:00",
        "source" => {
          "surface" => "founder_review_artifact",
          "locator" => "review:founder-workbench",
          "founder_input_verbatim" => "C001은 낮은 3/4 구도로 확정한다."
        },
        "authority" => {
          "classification" => "explicit_lock",
          "explicit_lock" => true,
          "scope_statement" => "C001 composition only"
        },
        "intervention_mode" => "founder_direct_update",
        "routing" => {
          "owning_stage_id" => "mv_storyboard_direction",
          "required_owner_skill" => "idol-generation",
          "affected_section_ids" => ["S00"],
          "affected_artifacts" => [{
            "path" => storyboard.relative_path_from(root).to_s,
            "sha256" => Digest::SHA256.file(storyboard).hexdigest,
            "role" => "revised 02A owner"
          }],
          "earliest_reauthor_stage_id" => "mv_storyboard_direction",
          "downstream_invalidation_targets" => [],
          "integration_order" => "revise_owning_upstream_section_then_reproject_and_revalidate_only_affected_downstream"
        },
        "change_contract" => {
          "preserve" => ["all unaffected cuts and upstream bootstrap truth"],
          "change" => ["C001 composition"],
          "do_not_infer" => ["no other scene or prompt change"]
        },
        "founder_direct_update" => {
          "correction_kind" => "image_truth_or_prompt_revision",
          "owning_truth_surface" => "storyboard_02a",
          "decision" => "pass",
          "decision_note" => "Founder directly selected the replacement composition.",
          "baseline_review" => {
            "path" => baseline.relative_path_from(root).to_s,
            "sha256" => Digest::SHA256.file(baseline).hexdigest,
            "role" => "last passed creative baseline"
          },
          "baseline_source" => {
            "path" => storyboard.relative_path_from(root).to_s,
            "sha256" => Digest::SHA256.file(storyboard).hexdigest,
            "role" => "last passed source bytes"
          },
          "authoritative_field_bindings" => [{
            "path" => storyboard.relative_path_from(root).to_s,
            "sha256" => Digest::SHA256.file(storyboard).hexdigest,
            "pointer" => "/master_storyboard/0/composition",
            "value_sha256" => value_sha(selected_value),
            "role" => "Founder selected composition"
          }],
          "creative_review_policy" => "founder_decision_no_creative_advisory_rereview",
          "mandatory_check_ids" => required_checks,
          "downstream_policy" => "patch_smallest_owner_and_reproject_affected_dependents_only"
        },
        "status" => "integrated",
        "integration_receipt" => {
          "integrated_at" => "2026-07-23T22:03:00+09:00",
          "revised_artifacts" => [{
            "path" => storyboard.relative_path_from(root).to_s,
            "sha256" => Digest::SHA256.file(storyboard).hexdigest,
            "role" => "revised 02A owner"
          }],
          "revalidation_results" => required_checks.map do |check_id|
            {"check_id" => check_id, "status" => "pass", "evidence" => "fixture evidence"}
          end,
          "resumable_from_stage_id" => "image_prompt_compilation"
        }
      ))

      stdout, stderr, status = Open3.capture3(
        "ruby", SCRIPT.to_s, receipt.relative_path_from(root).to_s, "--root", root.to_s,
        chdir: ROOT.to_s
      )
      assert status.success?, [stdout, stderr].join("\n")

      document = YAML.safe_load(receipt.read)
      document["founder_direct_update"]["authoritative_field_bindings"][0]["value_sha256"] = "0" * 64
      receipt.write(YAML.dump(document))
      _stdout, stale_stderr, stale_status = Open3.capture3(
        "ruby", SCRIPT.to_s, receipt.relative_path_from(root).to_s, "--root", root.to_s,
        chdir: ROOT.to_s
      )
      refute stale_status.success?
      assert_includes stale_stderr, "value_sha256 is stale"
    end
  end

  private

  def value_sha(value)
    Digest::SHA256.hexdigest(JSON.generate(value))
  end
end
