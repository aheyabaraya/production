# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "pathname"
require "tmpdir"
require "yaml"

class ValidateLunaSectionLifecycleReceiptTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("../..").expand_path
  VALIDATOR = ROOT.join("scripts/validate_luna_section_lifecycle_receipt.rb")

  def setup
    @parent = Pathname.new(Dir.mktmpdir("luna-lifecycle-", ROOT.join("runs").to_s))
    @run = @parent.join("luna-lifecycle", "TEST")
    @run.mkpath
    @run_rel = @run.relative_path_from(ROOT).to_s
    @source_02a = write("02A-master-storyboard.yaml", {
      "schema_version" => "3.0",
      "content_id" => "TEST",
      "master_storyboard" => [
        {
          "core_cut_id" => "C001_S00_TEST",
          "source_sections" => ["S00"],
          "compile_seed" => {
            "branch_cuts" => [
              {"branch_cut_id" => "BC01_TEST_ACTION", "branch_order" => 1}
            ]
          }
        }
      ]
    })
    @source_02b = write("02B-prompt-packets.yaml", {"schema_version" => "2.5", "content_id" => "TEST"})
    @context = write("work/image_prompt_compilation/context-S00.yaml", {"schema_version" => "idol-harness-context-pack.v7"})
    @planning = write("research/front-planning.yaml", {"schema_version" => "front-planning-readiness.v17"})
    @check = write("review/checks/hash-check.json", {"status" => "pass"}.to_json)
    @branch_cut_image = write("generations/branch-cuts/BC01.png", "branch-cut-bytes")
    @clip = write("generations/video/raw/V1.mp4", "03v-clip-bytes")
    @production_cut_review = write("review/03-production-cut-review.yaml", {
      "schema_version" => "idol-production-cut-review.v2",
      "status" => "passed",
      "production_cut_reviews" => [{"section_id" => "S00"}]
    })
    @execution_record = write("review/luna-section-lifecycle/S00-execution.yaml", execution_record)
    @receipt_path = @run.join("review/luna-section-lifecycle/S00-receipt.yaml")
    @receipt = receipt_fixture
    @receipt_path.write(YAML.dump(@receipt))
  end

  def teardown
    FileUtils.remove_entry(@parent) if @parent&.directory?
  end

  def test_complete_receipt_passes
    result = run_validator
    assert result[:status].success?, result[:stderr] + result[:stdout]
    assert_equal true, JSON.parse(result[:stdout]).fetch("valid")
  end

  def test_reviewed_asset_must_be_a_candidate
    @receipt["production_cut_review_gate"]["reviewed_asset_ids"] = ["NOT_A_CANDIDATE"]
    persist
    result = run_validator
    refute result[:status].success?
    assert_includes result[:stdout], "subset of candidate_asset_ids"
  end

  def test_complete_receipt_requires_03v_playback
    @receipt["decision_evidence"].reject! { |row| row["stage"] == "03v" }
    persist
    result = run_validator
    refute result[:status].success?
    assert_includes result[:stdout], "requires a hash-bound 03V playback clip"
  end

  def test_direct_sequence_cut_requires_sequence_evidence
    source = YAML.safe_load(@source_02a.read, aliases: true)
    source["master_storyboard"].first["reference_contact_sheet_contract"] = {
      "primary_exact_scene_reference" => {"application_mode" => "sequence_direct"},
      "secondary_exact_scene_references" => []
    }
    @source_02a.write(YAML.dump(source))
    refresh_source_hashes
    persist
    result = run_validator
    refute result[:status].success?
    assert_includes result[:stdout], "direct-scene/sequence Core Cuts require 02A-validation sequence or playback evidence"
  end

  def test_v2_receipt_rejects_04_stage_evidence
    @receipt["decision_evidence"] << evidence("DS-04", "04", "playback_clip", "V1", "playback", @clip)
    persist
    result = run_validator
    refute result[:status].success?
    assert_includes result[:stdout], "receipt failed JSON Schema validation"
  end

  def test_tampered_inspected_asset_fails_hash_check
    @branch_cut_image.write("tampered")
    result = run_validator
    refute result[:status].success?
    assert_includes result[:stdout], "inspected_asset_manifest[0] sha256 mismatch"
  end

  def test_stale_active_source_contract_is_rejected
    @context.write(YAML.dump({"schema_version" => "idol-harness-context-pack.v6"}))
    @receipt["sources"]["context_pack"] = pointer(@context)
    persist

    result = run_validator
    refute result[:status].success?
    assert_includes result[:stdout], "context_pack must use active schema_version idol-harness-context-pack.v7"
  end

  private

  def write(relative, content)
    path = @run.join(relative)
    path.dirname.mkpath
    path.write(content.is_a?(String) ? content : YAML.dump(content))
    path
  end

  def pointer(path)
    {
      "path" => path.relative_path_from(ROOT).to_s,
      "sha256" => Digest::SHA256.file(path.to_s).hexdigest
    }
  end

  def execution_record
    {
      "schema_version" => "idol_luna_section_lifecycle_execution_record.v2",
      "producer" => "registered_section_image_motion_lifecycle_runner",
      "session_type" => "section_image_motion_checkpoint",
      "session_id" => "luna-session-S00",
      "logical_role" => "section_image_motion_worker",
      "logical_profile_alias" => "worker_high",
      "provider_profile_snapshot_ref" => "automation/harness-provider-profile-registry.yaml#/logical_profiles/worker_high/providers/codex/role_profiles/section_image_motion_worker",
      "provider_capability_snapshot_sha256" => Digest::SHA256.file(ROOT.join("automation/harness-provider-profile-registry.yaml")).hexdigest,
      "automatic_fallback" => "none",
      "source_02a_sha256" => Digest::SHA256.file(@source_02a.to_s).hexdigest,
      "assigned_section_ids" => ["S00"],
      "fresh_session_boundary" => "overall_promoted_02a_section_boundary",
      "section_lineage_id" => "IMAGE_MOTION_S00",
      "checkpoint_id" => "03V_COMPLETE",
      "durable_checkpoint_resume" => true,
      "same_physical_session_required" => false,
      "04_edit_session_included" => false,
      "completion_state" => "complete",
      "return_recipient_role" => "creative_development_director",
      "canonical_creative_write_performed" => false
    }
  end

  def inspected_asset(asset_id, stage, media_type, path)
    {
      "asset_id" => asset_id,
      "stage" => stage,
      "media_type" => media_type,
      "actual_path" => path.relative_path_from(ROOT).to_s,
      "sha256" => Digest::SHA256.file(path.to_s).hexdigest,
      "inspection_status" => "pixel_or_playback_inspected",
      "observable_facts" => ["Fixture surface is readable."],
      "technical_disposition" => "technical_pass"
    }
  end

  def evidence(decision_set_id, stage, kind, asset_id, media_type, path)
    surface = {
      "actual_path" => path.relative_path_from(ROOT).to_s,
      "sha256" => Digest::SHA256.file(path.to_s).hexdigest,
      "source_or_generated_asset_id" => asset_id,
      "maps_to_core_cut_ids" => ["C001_S00_TEST"],
      "maps_to_branch_cut_ids" => ["BC01_TEST_ACTION"],
      "decision_anchor_role" => "section decision anchor",
      "audio_or_section_cue" => "S00 cue",
      "inspected_observable_fact" => "Fixture surface is readable.",
      "relevant_boundary" => "S00 out",
      "media_type" => media_type
    }
    surface["time_range"] = {"start_seconds" => 0.0, "end_seconds" => 1.0} if %w[clip playback].include?(media_type)
    {
      "decision_set_id" => decision_set_id,
      "stage" => stage,
      "evidence_kind" => kind,
      "source_anchor_ids" => ["C001_S00_TEST"],
      "surfaces" => [surface]
    }
  end

  def receipt_fixture
    {
      "schema_version" => "idol_luna_section_lifecycle_receipt.v2",
      "artifact_type" => "luna_section_lifecycle_receipt",
      "run" => @run_rel,
      "section_id" => "S00",
      "status" => "complete",
      "executor" => {
        "logical_role" => "section_image_motion_worker",
        "logical_profile_alias" => "worker_high",
        "provider_profile_snapshot_ref" => "automation/harness-provider-profile-registry.yaml#/logical_profiles/worker_high/providers/codex/role_profiles/section_image_motion_worker",
        "provider_capability_snapshot_sha256" => Digest::SHA256.file(ROOT.join("automation/harness-provider-profile-registry.yaml")).hexdigest,
        "automatic_fallback" => "none",
        "session_id" => "luna-session-S00",
        "execution_record" => pointer(@execution_record)
      },
      "session_contract" => {
        "fresh_session_boundary" => "overall_promoted_02a_section_boundary",
        "exactly_one_section" => true,
        "director_physical_shard_execution_forbidden" => true,
        "section_lineage_id" => "IMAGE_MOTION_S00",
        "durable_checkpoint_resume_allowed" => true,
        "same_physical_session_required" => false,
        "04_edit_session_included" => false,
        "completed_checkpoint_id" => "03V_COMPLETE"
      },
      "sources" => {
        "source_02a" => pointer(@source_02a),
        "source_02b" => pointer(@source_02b),
        "context_pack" => pointer(@context),
        "planning_source" => pointer(@planning)
      },
      "stage_statuses" => {
        "02a_validation" => "complete",
        "02b_exact_compile" => "complete",
        "branch_cut_image_generation" => "complete",
        "generated_branch_cut_review" => "complete",
        "03v_motion_video_work" => "complete"
      },
      "production_cut_review_gate" => {
        "status" => "passed",
        "decision_owner" => "creative_development_director",
        "candidate_asset_ids" => ["KF1"],
        "reviewed_asset_ids" => ["KF1"],
        "production_cut_review" => pointer(@production_cut_review),
        "review_note" => "CDD passed the typed Production Cut review for the fixture.",
        "resume_same_section_lineage_required" => true
      },
      "direct_script_checks" => [
        {
          "check_id" => "hash-check",
          "command_id" => "registered-fixture-check",
          "status" => "pass",
          "evidence_path" => @check.relative_path_from(ROOT).to_s,
          "evidence_sha256" => Digest::SHA256.file(@check.to_s).hexdigest
        }
      ],
      "inspected_asset_manifest" => [
        inspected_asset("KF1", "generated_branch_cut_review", "image", @branch_cut_image),
        inspected_asset("V1", "03v", "clip", @clip)
      ],
      "decision_evidence" => [
        evidence("DS-BC", "generated_branch_cut_review", "still_frame_set", "KF1", "image", @branch_cut_image),
        evidence("DS-03V", "03v", "playback_clip", "V1", "clip", @clip)
      ],
      "completion_report" => {
        "reported_to_cdd" => true,
        "summary" => "Fixture section image-motion lineage completed through 03V.",
        "remaining_risks" => [],
        "cdd_production_cut_review_required" => true,
        "founder_final_selection_required" => true,
        "overall_promotion_required" => true
      },
      "authority_boundaries" => {
        "deterministic_check_owner" => "registered_direct_scripts",
        "full_asset_inspection_owner" => "section_image_motion_worker",
        "creative_review_owner" => "creative_development_director",
        "final_selection_owner" => "founder",
        "promotion_owner" => "overall_director",
        "return_recipient_role" => "creative_development_director",
        "prompt_or_motion_rewrite_performed" => false,
        "canonical_creative_write_performed" => false
      },
      "authority_separation" => {
        "cdd_production_cut_review_status" => "bound_passed_review",
        "founder_final_selection_status" => "pending_external_to_worker_receipt",
        "overall_promotion_status" => "pending_external_to_worker_receipt",
        "worker_selection_or_promotion_inferred" => false
      }
    }
  end

  def refresh_source_hashes
    source_sha = Digest::SHA256.file(@source_02a.to_s).hexdigest
    @receipt["sources"]["source_02a"] = pointer(@source_02a)
    record = YAML.safe_load(@execution_record.read, aliases: true)
    record["source_02a_sha256"] = source_sha
    @execution_record.write(YAML.dump(record))
    @receipt["executor"]["execution_record"] = pointer(@execution_record)
  end

  def persist
    @receipt_path.write(YAML.dump(@receipt))
  end

  def run_validator
    stdout, stderr, status = Open3.capture3(
      "ruby", VALIDATOR.to_s, @receipt_path.to_s, "--repo-root", ROOT.to_s, "--json",
      chdir: ROOT.to_s
    )
    {stdout: stdout, stderr: stderr, status: status}
  end
end
