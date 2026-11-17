# frozen_string_literal: true

require "digest"
require "fileutils"
require "minitest/autorun"
require "open3"
require "pathname"
require "securerandom"
require "yaml"

class ValidateSkillApplicationReceiptTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  VALIDATOR = ROOT.join("scripts", "validate_skill_application_receipt.rb")

  def setup
    @title_root = ROOT.join("runs", "harness-test", "skill-receipt")
    @run = @title_root.join("SKILL_RECEIPT_#{SecureRandom.hex(4).upcase}")
    @output = @run.join("research", "front-planning-readiness-v5.yaml")
    @receipt = @run.join("work", "skill-application-receipts", "front_planning_integration", "whole.yaml")
    @output.dirname.mkpath
    @receipt.dirname.mkpath
    @output.write("schema_version: idol-front-planning-readiness.v5\nstatus: draft\n")
  end

  def teardown
    FileUtils.remove_entry(@run) if @run&.directory?
    @title_root.rmdir if @title_root&.directory? && @title_root.children.empty?
    album_root = ROOT.join("runs", "harness-test")
    album_root.rmdir if album_root.directory? && album_root.children.empty?
  end

  def test_valid_receipt_binds_stage_owner_reads_application_and_output
    write_receipt(base_receipt)
    _stdout, stderr, status = validate
    assert status.success?, stderr
  end

  def test_application_source_must_be_one_of_the_completed_reads
    document = base_receipt
    document.fetch("application_evidence").first["source_path"] = "policies/section-production.md"
    write_receipt(document)
    _stdout, stderr, status = validate
    refute status.success?
    assert_includes stderr, "was not recorded as a completed read"
  end

  def test_owning_skill_must_match_stage_registry_owner
    document = base_receipt
    wrong_skill = "skills/idol-generation/SKILL.md"
    document["owning_skill"] = read_evidence(wrong_skill, "wrong routed skill")
    write_receipt(document)
    _stdout, stderr, status = validate
    refute status.success?
    assert_includes stderr, "does not match stage front_planning_integration canonical owner"
  end

  def test_complete_receipt_fails_when_output_bytes_change_after_close
    write_receipt(base_receipt)
    @output.write("schema_version: idol-front-planning-readiness.v5\nstatus: changed\n")
    _stdout, stderr, status = validate
    refute status.success?
    assert_includes stderr, "output evidence hash mismatch"
  end

  def test_complete_v3_receipt_requires_exact_output_evidence_coverage
    document = base_receipt
    document["output_evidence"] = []
    write_receipt(document)
    _stdout, stderr, status = validate
    refute status.success?
    assert_match(/output_evidence/, stderr)
  end

  def test_current_receipt_rejects_retired_terra_post_02a_lane
    document = base_receipt
    document.fetch("session_contract")["lane"] = "fresh_terra_section_post_02a"
    write_receipt(document)
    _stdout, stderr, status = validate
    refute status.success?
    assert_includes stderr, "checkpointed_luna_section_post_02a"
  end

  def test_current_receipt_accepts_checkpointed_luna_post_02a_lane
    document = base_receipt
    document.fetch("session_contract")["lane"] = "checkpointed_luna_section_post_02a"
    write_receipt(document)
    _stdout, stderr, status = validate
    assert status.success?, stderr
  end

  def test_v1_remains_readable_but_cannot_satisfy_a_current_gate
    document = base_receipt
    document["schema_version"] = "idol-skill-application-receipt.v1"
    document.delete("output_evidence")
    document["creative_authorship"].delete("authorship_actor")
    document["creative_authorship"].delete("authorship_continuity_id")
    document["creative_authorship"].delete("script_authored_creative_values")
    document["creative_authorship"].delete("script_claimed_model_authorship")
    write_receipt(document)

    _stdout, stderr, status = validate(require_current: false)
    assert status.success?, stderr

    _stdout, stderr, status = validate(require_current: true)
    refute status.success?
    assert_includes stderr, "must use current authoring version"
  end

  private

  def base_receipt
    output_relative = @output.relative_path_from(ROOT).to_s
    {
      "schema_version" => "idol-skill-application-receipt.v3",
      "run" => @run.relative_path_from(ROOT).to_s,
      "stage_id" => "front_planning_integration",
      "scope" => {"mode" => "whole_run", "section_id" => nil},
      "owner" => "test-director",
      "session_contract" => {
        "lane" => "continuous_director_pre_02a",
        "continuity_id" => "TEST-DIRECTOR-CONTINUITY",
        "new_chat_per_pre_02a_section" => false,
        "ordered_section_ids" => ["S00"]
      },
      "owning_skill" => read_evidence("skills/idol-front-planning-director/SKILL.md", "owning skill"),
      "activated_reads" => [read_evidence("AGENTS.md", "repository authority")],
      "application_evidence" => [
        {
          "rule_id" => "front_planning_output_contract",
          "source_path" => "AGENTS.md",
          "applied_to" => "#{output_relative}#/status",
          "application" => "Kept the stage output under the run-owned Front Planning contract."
        }
      ],
      "output_targets" => [output_relative],
      "output_evidence" => [
        {
          "path" => output_relative,
          "sha256" => Digest::SHA256.file(@output.to_s).hexdigest
        }
      ],
      "creative_authorship" => {
        "creative_values_origin" => "human_or_model_authored",
        "script_role" => "validation_hashing_or_hash_bound_exact_copy_only",
        "missing_creative_truth_action" => "hold",
        "authorship_actor" => "codex_model",
        "authorship_continuity_id" => "TEST-DIRECTOR-CONTINUITY",
        "script_authored_creative_values" => false,
        "script_claimed_model_authorship" => false
      },
      "status" => "complete"
    }
  end

  def read_evidence(relative, reason)
    {
      "path" => relative,
      "sha256" => Digest::SHA256.file(ROOT.join(relative).to_s).hexdigest,
      "read_complete" => true,
      "reason" => reason
    }
  end

  def write_receipt(document)
    @receipt.write(YAML.dump(document))
  end

  def validate(require_current: true)
    command = [RbConfig.ruby, VALIDATOR.to_s]
    command << "--require-current" if require_current
    command << @receipt.relative_path_from(ROOT).to_s
    Open3.capture3(*command, chdir: ROOT.to_s)
  end
end
