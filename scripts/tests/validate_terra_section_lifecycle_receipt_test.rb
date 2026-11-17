# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "pathname"
require "tmpdir"
require "yaml"

class ValidateTerraSectionLifecycleReceiptTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("../..").expand_path
  VALIDATOR = ROOT.join("scripts/validate_terra_section_lifecycle_receipt.rb")

  def setup
    @parent = Pathname.new(Dir.mktmpdir("terra-lifecycle-", ROOT.join("runs").to_s))
    @run = @parent.join("terra-lifecycle", "TEST")
    @run.mkpath
    @run_rel = @run.relative_path_from(ROOT).to_s
    @source_02a = write("02A-master-storyboard.yaml", {
      "schema_version" => "2.2",
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
    @source_02b = write("02B-prompt-packets.yaml", {"schema_version" => "2.1", "content_id" => "TEST"})
    @context = write("work/image_prompt_compilation/context-S00.yaml", {"schema_version" => "idol-harness-context-pack.v6"})
    @planning = write("research/front-planning.yaml", {"schema_version" => "front-planning-readiness.v15"})
    @check = write("review/checks/hash-check.json", {"status" => "pass"}.to_json)
    @branch_cut_image = write("generations/branch-cuts/BC01.png", "branch-cut-bytes")
    @clip = write("generations/video/raw/V1.mp4", "03v-clip-bytes")
    @execution_record = write("review/terra-section-lifecycle/S00-execution.yaml", execution_record)
    @receipt_path = @run.join("review/terra-section-lifecycle/S00-receipt.yaml")
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

  def test_selected_asset_must_be_a_candidate
    @receipt["generated_branch_cut_sol_gate"]["selected_asset_ids"] = ["NOT_A_CANDIDATE"]
    persist
    result = run_validator
    refute result[:status].success?
    assert_includes result[:stdout], "subset of candidate_asset_ids"
  end

  def test_complete_receipt_requires_03v_playback
    @receipt["sol_decision_evidence"].reject! { |row| row["stage"] == "03v" }
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

  def test_v3_receipt_rejects_04_stage_evidence
    @receipt["sol_decision_evidence"] << evidence("DS-04", "04", "playback_clip", "V1", "playback", @clip)
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
      "schema_version" => "idol_terra_section_lifecycle_execution_record.v3",
      "producer" => "registered_codex_section_lifecycle_runner",
      "surface_owner" => "codex",
      "session_type" => "terra_section_image_motion_checkpoint",
      "session_id" => "terra-session-S00",
      "profile" => "terra_xhigh",
      "source_02a_sha256" => Digest::SHA256.file(@source_02a.to_s).hexdigest,
      "assigned_section_ids" => ["S00"],
      "fresh_session_boundary" => "sol_approved_02a_section",
      "section_lineage_id" => "IMAGE_MOTION_S00",
      "checkpoint_id" => "03V_COMPLETE",
      "durable_checkpoint_resume" => true,
      "same_physical_session_required" => false,
      "04_edit_session_included" => false,
      "completion_state" => "complete",
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
      "schema_version" => "idol_terra_section_lifecycle_receipt.v3",
      "artifact_type" => "terra_section_lifecycle_receipt",
      "run" => @run_rel,
      "section_id" => "S00",
      "status" => "complete",
      "executor" => {
        "surface" => "codex",
        "agent_name" => "idol_terra_routine_judgment",
        "model_id" => "gpt-5.6-terra",
        "reasoning_effort" => "xhigh",
        "session_id" => "terra-session-S00",
        "execution_record" => pointer(@execution_record)
      },
      "session_contract" => {
        "fresh_session_boundary" => "sol_approved_02a_section",
        "exactly_one_section" => true,
        "sol_physical_shard_execution_forbidden" => true,
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
      "generated_branch_cut_sol_gate" => {
        "status" => "selected",
        "decision_owner" => "continuing_sol_session",
        "candidate_asset_ids" => ["KF1"],
        "selected_asset_ids" => ["KF1"],
        "sol_session_id" => "central-sol-session",
        "selection_note" => "Sol selected the fixture Branch Cut for 03V.",
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
      "sol_decision_evidence" => [
        evidence("DS-BC", "generated_branch_cut_review", "still_frame_set", "KF1", "image", @branch_cut_image),
        evidence("DS-03V", "03v", "playback_clip", "V1", "clip", @clip)
      ],
      "completion_report" => {
        "reported_to_sol" => true,
        "summary" => "Fixture section image-motion lineage completed through 03V.",
        "remaining_risks" => [],
        "sol_final_decision_required" => true
      },
      "authority_boundaries" => {
        "deterministic_check_owner" => "registered_direct_scripts",
        "full_asset_inspection_owner" => "terra",
        "creative_selection_owner" => "sol",
        "prompt_or_motion_rewrite_performed" => false,
        "canonical_creative_write_performed" => false
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
