# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "pathname"
require "rbconfig"
require "tmpdir"
require "yaml"

class Idol03VContextualReviewReadinessTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  VALIDATOR = ROOT.join("scripts/validate_video_prompt_section_qa_readiness.rb")

  def setup
    @tmp = Pathname.new(Dir.mktmpdir("idol-03v-context-review-"))
    @storyboard_assist = @tmp.join("03V-storyboard-assist.yaml")
    @storyboard_assist.write("schema_version: idol_video_prompt_storyboard_assist.v4\nstatus: passed\n", encoding: "utf-8")
    @manifest = @tmp.join("03V-video-prompt-manifest.yaml")
    write_manifest(@manifest, content_id: "TEST", cue_id: "03VCUE_CONTEXTUAL")
    @section_record = @tmp.join("section-execution.yaml")
    @root_record = @tmp.join("root-execution.yaml")
    write_review_execution_record(@section_record, manifest: @manifest, sections: ["S00"])
    write_review_execution_record(@root_record, manifest: @manifest, sections: ["S00"])
    @qa = @tmp.join("section-qa.yaml")
    write_v6_contextual_qa
  end

  def teardown
    FileUtils.remove_entry(@tmp) if @tmp&.directory?
  end

  def test_v6_contextual_section_and_whole_timeline_review_can_close_readiness
    stdout, stderr, status = run_validator
    assert status.success?, "stdout=#{stdout}\nstderr=#{stderr}"
    assert_includes stdout, "contextual section review record"
  end

  def test_manifest_hash_drift_reopens_review
    @manifest.write(@manifest.read + "\nchanged_after_review: true\n", encoding: "utf-8")
    _stdout, stderr, status = run_validator
    refute status.success?
    assert_includes stderr, "source_video_prompt_manifest_sha256 does not match"
  end

  def test_review_execution_record_cannot_bind_a_different_manifest
    record = YAML.safe_load(@section_record.read, aliases: true)
    record["source_03v_video_prompt_manifest_sha256"] = "0" * 64
    @section_record.write(YAML.dump(record), encoding: "utf-8")
    qa = YAML.safe_load(@qa.read, aliases: true)
    qa.dig("sections", 0, "review_execution_record")["sha256"] = Digest::SHA256.file(@section_record).hexdigest
    @qa.write(YAML.dump(qa), encoding: "utf-8")

    _stdout, stderr, status = run_validator
    refute status.success?
    assert_includes stderr, "source 03V manifest SHA-256 differs from section QA"
  end

  def test_legacy_checklist_cannot_claim_active_readiness
    legacy = {
      "schema_version" => "idol_video_prompt_section_qa.v1",
      "content_id" => "TEST",
      "review_unit" => "section",
      "overall_status" => "pass",
      "source_video_prompt_manifest_path" => @manifest.to_s,
      "sections" => []
    }
    @qa.write(YAML.dump(legacy), encoding: "utf-8")
    _stdout, stderr, status = run_validator
    refute status.success?
    assert_includes stderr, "historical index-bound or pre-Production-Cut evidence"
  end

  def test_v6_founder_direct_delta_reuses_passed_v6_contextual_baseline_without_another_llm_review
    run_rel = "runs/test-album/test-03v-direct/TEST_03V_DIRECT"
    run = @tmp.join(run_rel)
    review = run.join("review")
    intervention_dir = review.join("founder-interventions")
    prompt_dir = run.join("generations", "video-prompts")
    intervention_dir.mkpath
    prompt_dir.mkpath

    baseline_manifest = review.join("03V-video-prompt-manifest-baseline.yaml")
    write_manifest(
      baseline_manifest,
      content_id: "TEST_03V_DIRECT",
      cue_id: "03VCUE_BASELINE",
      prompt_text: "Hold the original camera route."
    )
    current_manifest = run.join("03V-video-prompt-manifest.yaml")
    write_manifest(
      current_manifest,
      content_id: "TEST_03V_DIRECT",
      cue_id: "03VCUE_BASELINE",
      prompt_text: "Founder-selected low tracking route."
    )

    baseline_qa = review.join("03v-section-video-prompt-qa-baseline.yaml")
    baseline_section_record = review.join("baseline-section-execution.yaml")
    baseline_root_record = review.join("baseline-root-execution.yaml")
    write_review_execution_record(baseline_section_record, manifest: baseline_manifest, sections: ["S00"])
    write_review_execution_record(baseline_root_record, manifest: baseline_manifest, sections: ["S00"])
    baseline_qa.write(YAML.dump(
      "schema_version" => "idol_video_prompt_section_qa.v6",
      "content_id" => "TEST_03V_DIRECT",
      "review_unit" => "section",
      "overall_status" => "pass",
      "source_video_prompt_manifest_path" => baseline_manifest.relative_path_from(@tmp).to_s,
      "source_video_prompt_manifest_sha256" => Digest::SHA256.file(baseline_manifest).hexdigest,
      "review_mode" => "contextual_llm_section_and_whole_timeline",
      "review_owner" => provider_neutral_review_owner,
      "sections" => [{
        "section_key" => "S00",
        "status" => "pass",
        "reviewed_prompt_count" => 1,
        "cue_ids" => ["03VCUE_BASELINE"],
        "review_summary" => "Passed contextual baseline.",
        "findings" => [],
        "review_execution_record" => record_ref(baseline_section_record)
      }],
      "whole_timeline_review" => {
        "status" => "pass",
        "review_summary" => "Passed whole-timeline baseline.",
        "findings" => [],
        "review_execution_record" => record_ref(baseline_root_record)
      }
    ), encoding: "utf-8")

    required_checks = [
      "schema_and_hash_integrity",
      "reference_and_identity_integrity",
      "safety_and_feasibility",
      "pixel_or_playback_qa_when_output_exists",
      "external_and_paid_approval_when_applicable"
    ]
    receipt = intervention_dir.join("FI_03V_DIRECT_01.yaml")
    current_doc = YAML.safe_load(current_manifest.read)
    receipt.write(YAML.dump(
      "schema_version" => "idol-founder-intervention-receipt.v2",
      "artifact_type" => "founder_intervention_receipt",
      "intervention_id" => "FI_03V_DIRECT_01",
      "run" => run_rel,
      "recorded_at" => "2026-07-23T23:00:00+09:00",
      "source" => {
        "surface" => "founder_review_artifact",
        "locator" => "review:founder-workbench",
        "founder_input_verbatim" => "S00 비디오 프롬프트의 카메라를 낮은 트래킹으로 확정한다."
      },
      "authority" => {
        "classification" => "explicit_lock",
        "explicit_lock" => true,
        "scope_statement" => "S00 video prompt camera route only"
      },
      "intervention_mode" => "founder_direct_update",
      "routing" => {
        "owning_stage_id" => "video_prompt_motion_design",
        "required_owner_skill" => "idol-video-prompt",
        "affected_section_ids" => ["S00"],
        "affected_artifacts" => [artifact_ref(current_manifest, "revised 03V video prompt manifest")],
        "earliest_reauthor_stage_id" => "video_prompt_motion_design",
        "downstream_invalidation_targets" => [],
        "integration_order" => "revise_owning_upstream_section_then_reproject_and_revalidate_only_affected_downstream"
      },
      "change_contract" => {
        "preserve" => ["all unaffected sections and passed whole-timeline baseline"],
        "change" => ["S00 camera route"],
        "do_not_infer" => ["no other motion or section change"]
      },
      "founder_direct_update" => {
        "correction_kind" => "video_prompt_revision",
        "owning_truth_surface" => "video_prompt_03v",
        "decision" => "pass",
        "decision_note" => "Founder directly authored and selected the S00 camera route.",
        "baseline_review" => artifact_ref(baseline_qa, "last passed contextual review"),
        "baseline_source" => artifact_ref(baseline_manifest, "last passed 03V video prompt manifest"),
        "authoritative_field_bindings" => [{
          "path" => current_manifest.relative_path_from(@tmp).to_s,
          "sha256" => Digest::SHA256.file(current_manifest).hexdigest,
          "pointer" => "/cues/0/prompt_text",
          "value_sha256" => Digest::SHA256.hexdigest(JSON.generate(current_doc.dig("cues", 0, "prompt_text"))),
          "role" => "Founder selected video prompt wording"
        }],
        "creative_review_policy" => "founder_decision_no_creative_advisory_rereview",
        "mandatory_check_ids" => required_checks,
        "downstream_policy" => "patch_smallest_owner_and_reproject_affected_dependents_only"
      },
      "status" => "integrated",
      "integration_receipt" => {
        "integrated_at" => "2026-07-23T23:03:00+09:00",
        "revised_artifacts" => [artifact_ref(current_manifest, "revised 03V video prompt manifest")],
        "revalidation_results" => required_checks.map do |check_id|
          {"check_id" => check_id, "status" => "pass", "evidence" => "fixture evidence"}
        end,
        "resumable_from_stage_id" => "video_generation"
      }
    ), encoding: "utf-8")

    @qa = review.join("03v-section-video-prompt-qa.yaml")
    @qa.write(YAML.dump(
      "schema_version" => "idol_video_prompt_section_qa.v6",
      "content_id" => "TEST_03V_DIRECT",
      "review_unit" => "section",
      "overall_status" => "pass",
      "source_video_prompt_manifest_path" => current_manifest.relative_path_from(@tmp).to_s,
      "source_video_prompt_manifest_sha256" => Digest::SHA256.file(current_manifest).hexdigest,
      "review_mode" => "founder_direct_delta",
      "affected_section_ids" => ["S00"],
      "baseline_contextual_qa" => hashed_ref(baseline_qa),
      "founder_direct_intervention" => hashed_ref(receipt),
      "unchanged_scope_policy" => "reuse_last_passed_contextual_review_without_rerun",
      "playback_followup_policy" => "rerun_affected_packets_then_hash_bound_playback_qa",
      "sections" => [{
        "section_key" => "S00",
        "status" => "pass",
        "reviewed_prompt_count" => 1,
        "cue_ids" => ["03VCUE_BASELINE"]
      }]
    ), encoding: "utf-8")

    schema_stdout, schema_stderr, schema_status = Open3.capture3(
      ROOT.join("scripts", "idol-video-python").to_s,
      ROOT.join("scripts", "validate_json_schema.py").to_s,
      ROOT.join("schemas", "video-prompt-section-qa.schema.json").to_s,
      @qa.to_s,
      chdir: ROOT.to_s
    )
    assert schema_status.success?, "stdout=#{schema_stdout}\nstderr=#{schema_stderr}"

    stdout, stderr, status = run_validator(root: @tmp)
    assert status.success?, "stdout=#{stdout}\nstderr=#{stderr}"
    assert_includes stdout, "Founder-direct section delta"

    current_manifest.write(current_manifest.read + "\nchanged_after_lock: true\n", encoding: "utf-8")
    _stdout, stale_stderr, stale_status = run_validator(root: @tmp)
    refute stale_status.success?
    assert_includes stale_stderr, "source_video_prompt_manifest_sha256 does not match"
  end

  private

  def write_manifest(path, content_id:, cue_id:, prompt_text: "Keep the active motion route.")
    path.dirname.mkpath
    path.write(YAML.dump(
      "schema_version" => "idol_video_prompt_manifest.v8",
      "content_id" => content_id,
      "source_storyboard_assist" => record_ref(@storyboard_assist),
      "section_shards" => [{
        "section_id" => "S00",
        "cue_ids" => [cue_id]
      }],
      "cues" => [{
        "cue_id" => cue_id,
        "section_id" => "S00",
        "prompt_text" => prompt_text,
        "source_production_cut_images" => [{"production_cut_type" => "branch"}]
      }]
    ), encoding: "utf-8")
  end

  def write_v6_contextual_qa
    qa = {
      "schema_version" => "idol_video_prompt_section_qa.v6",
      "content_id" => "TEST",
      "review_unit" => "section",
      "overall_status" => "pass",
      "source_video_prompt_manifest_path" => @manifest.to_s,
      "source_video_prompt_manifest_sha256" => Digest::SHA256.file(@manifest.to_s).hexdigest,
      "review_mode" => "contextual_llm_section_and_whole_timeline",
      "review_owner" => provider_neutral_review_owner,
      "sections" => [
        {
          "section_key" => "S00",
          "status" => "pass",
          "reviewed_prompt_count" => 1,
          "cue_ids" => ["03VCUE_CONTEXTUAL"],
          "review_summary" => "Integrated section judgment.",
          "findings" => [],
          "review_execution_record" => record_ref(@section_record)
        }
      ],
      "whole_timeline_review" => {
        "status" => "pass",
        "review_summary" => "Separate whole-timeline reconciliation.",
        "findings" => [],
        "review_execution_record" => record_ref(@root_record)
      }
    }
    @qa.write(YAML.dump(qa), encoding: "utf-8")
  end

  def record_ref(path)
    {"path" => path.to_s, "sha256" => Digest::SHA256.file(path.to_s).hexdigest}
  end

  def write_review_execution_record(path, manifest:, sections:)
    owner = provider_neutral_review_owner
    manifest_document = YAML.safe_load(manifest.read, aliases: true)
    path.write(YAML.dump(
      "schema_version" => "idol-llm-review-execution-record.v2",
      "producer" => "registered_codex_reviewer_runner",
      "surface_owner" => "codex",
      "session_type" => "codex_03v_playback_review",
      "role_id" => "idol-03v-cdd-playback-reviewer",
      "session_id" => "03v-review-#{path.basename(path.extname).to_s}",
      "profile" => "director_deep",
      "provider_profile_snapshot_ref" => owner.fetch("provider_profile_snapshot_ref"),
      "provider_capability_snapshot_sha256" => owner.fetch("provider_capability_snapshot_sha256"),
      "source_03v_video_prompt_manifest_sha256" => Digest::SHA256.file(manifest).hexdigest,
      "source_03v_storyboard_assist_sha256" => manifest_document.dig("source_storyboard_assist", "sha256"),
      "source_03v_production_cut_types" => ["branch"],
      "review_stage" => "03v_480p_playback",
      "return_recipient_role" => "creative_development_director",
      "assigned_section_ids" => sections,
      "completion_state" => "completed",
      "canonical_semantic_write_performed" => false
    ), encoding: "utf-8")
  end

  def provider_neutral_review_owner
    registry = ROOT.join("automation", "harness-provider-profile-registry.yaml")
    {
      "logical_role" => "creative_development_director",
      "logical_profile_alias" => "director_deep",
      "provider_profile_snapshot_ref" => "automation/harness-provider-profile-registry.yaml#/logical_profiles/director_deep/providers/codex/role_profiles/creative_development_director",
      "provider_capability_snapshot_sha256" => Digest::SHA256.file(registry).hexdigest,
      "automatic_fallback" => "none"
    }
  end

  def artifact_ref(path, role)
    {
      "path" => path.relative_path_from(@tmp).to_s,
      "sha256" => Digest::SHA256.file(path).hexdigest,
      "role" => role
    }
  end

  def hashed_ref(path)
    {
      "path" => path.relative_path_from(@tmp).to_s,
      "sha256" => Digest::SHA256.file(path).hexdigest
    }
  end

  def run_validator(root: ROOT)
    Open3.capture3(RbConfig.ruby, VALIDATOR.to_s, @qa.to_s, "--root", root.to_s, chdir: ROOT.to_s)
  end
end
