# frozen_string_literal: true

require "json"
require "minitest/autorun"
require "open3"
require "pathname"
require "rbconfig"
require "yaml"
require_relative "support/active_image_generation_fixture"

class IdolPrepareImageGenerationRequestTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  SCRIPT = ROOT.join("scripts", "idol_prepare_image_generation_request.rb")
  CONTRACT_VALIDATOR = ROOT.join("scripts", "validate_02b_imagegen_contract.rb")

  def setup
    @fixture = ActiveImageGenerationFixture.create
  end

  def teardown
    @fixture&.cleanup
  end

  def test_v12_hold_preserves_exact_five_lines_attachment_order_and_role_plan
    output = request_path
    result = run_request(output: output, write: true)
    assert result[:status].success?, result[:stderr]
    summary = JSON.parse(result[:stdout])
    assert_equal "hold", summary["status"]
    request = YAML.safe_load(output.read, aliases: true)
    assert_equal "idol_image_generation_request.v12", request["schema_version"]
    assert_equal "official_branch", request["mode"]
    assert_equal @fixture.packet("PKT_BC01_ACTION").dig("rendered_five_lines", "full_prompt_text"), request.dig("prompt", "full_prompt_text")
    assert_equal [1, 2], request["attachments"].map { |row| row["order"] }
    assert_equal "C1", request["section_cohort_id"]
    assert_equal request["attachments"].map { |row| row["binding_id"] },
                 request.dig("reference_role_plan", "attachment_order_binding_ids")
    assert_equal %w[character_visual scene_visual_package motion_reference],
                 request.dig("reference_role_plan", "logical_role_groups").map { |row| row["logical_role"] }
    assert_equal "gpt-image-2", request.dig("execution", "provider_model_or_tool")
    assert_equal "none", request.dig("integrity_contract", "provider_auth_model_fallback")
  end

  def test_v6_exact_approval_makes_request_ready
    approval = @fixture.write_approval(packet_id: "PKT_BC01_ACTION")
    output = request_path
    result = run_request(output: output, write: true, approval: approval)
    assert result[:status].success?, result[:stderr]
    request = YAML.safe_load(output.read, aliases: true)
    assert_equal "ready", request["status"]
    assert_equal "FOUNDER-GEN-AUTH-001", request.dig("approval", "founder_generation_authority_id")
    assert_equal true, request.dig("approval", "external_execution_approved")
    assert_equal true, request.dig("approval", "paid_generation_approved")
  end

  def test_approval_attachment_order_drift_fails_closed
    approval = @fixture.write_approval(packet_id: "PKT_BC01_ACTION", mutate: lambda do |document|
      document.dig("packets", 0, "approved_attachment_paths").reverse!
    end)
    result = run_request(approval: approval)
    refute result[:status].success?
    assert_includes result[:stderr], "approval packet bytes/order/output mismatch"
  end

  def test_openai_model_drift_fails_schema_before_request
    @fixture.packet("PKT_BC01_ACTION").dig("execution")["provider_model_or_tool"] = "gpt-image-1"
    @fixture.write_source_02b
    result = run_request
    refute result[:status].success?
    assert_match(/gpt-image-2|schema validation/i, result[:stderr])
  end

  def test_meaningfully_visible_packet_rejects_zero_attachments
    @fixture.packet("PKT_BC01_ACTION")["attachments"] = []
    @fixture.write_source_02b

    result = run_request

    refute result[:status].success?
    assert_match(/attachments|current_title_member_visual|schema validation/i, result[:stderr])
  end

  def test_attachment_outside_admitted_visual_roots_is_rejected
    attachment = @fixture.packet("PKT_BC01_ACTION").fetch("attachments").first
    attachment["actual_path"] = "README.md"
    attachment["sha256"] = Digest::SHA256.file(ROOT.join("README.md")).hexdigest
    @fixture.write_source_02b

    result = run_request

    refute result[:status].success?
    assert_includes result[:stderr], "image generation request failed"
    assert_includes result[:stderr], "attachments must remain the transport projection of locked 02A visual_reference_bindings"
  end

  def test_reference_role_plan_attachment_order_drift_is_rejected
    @fixture.packet("PKT_BC01_ACTION").dig("reference_role_plan", "attachment_order_binding_ids").reverse!
    @fixture.write_source_02b

    result = run_request

    refute result[:status].success?
    assert_match(/reference_role_plan|attachment order/i, result[:stderr])
  end

  def test_reference_function_lineage_stale_value_is_rejected_at_request_boundary
    scene = @fixture.packet("PKT_BC01_ACTION").dig("reference_role_plan", "logical_role_groups").find do |row|
      row["logical_role"] == "scene_visual_package"
    end
    scene.dig("composition_anchor_function_lineage")["function_value_sha256"] = "0" * 64
    @fixture.write_source_02b

    result = run_request

    refute result[:status].success?
    assert_includes result[:stderr], "function_value_sha256 is stale"
  end

  def test_reference_function_lineage_stale_value_is_rejected_by_canonical_02b_validator
    motion = @fixture.packet("PKT_BC01_ACTION").dig("reference_role_plan", "logical_role_groups").find do |row|
      row["logical_role"] == "motion_reference"
    end
    motion.dig("motion_function_lineage", 0)["function_value_sha256"] = "0" * 64
    @fixture.write_source_02b

    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      CONTRACT_VALIDATOR.to_s,
      "--mode", "authoring",
      "--run-root", @fixture.mv.run_dir.to_s,
      @fixture.source_02b_path.to_s,
      chdir: ROOT.to_s
    )

    refute status.success?, stdout
    assert_includes stderr, "function_value_sha256 is stale"
  end

  def test_rendered_five_lines_drift_is_rejected_before_generation
    packet = @fixture.packet("PKT_BC01_ACTION")
    rendered = packet.fetch("rendered_five_lines")
    rendered["scene_intent"] = "Silently replace the authored still purpose."
    rendered["full_prompt_text"] = [
      "Identity reference rule: #{rendered.fetch('identity_reference_rule')}",
      "Scene intent: #{rendered.fetch('scene_intent')}",
      "Visible details: #{rendered.fetch('visible_details')}",
      "Action cue: #{rendered.fetch('action_cue')}",
      "Avoid: #{rendered.fetch('avoid')}"
    ].join("\n")
    rendered["full_prompt_sha256"] = Digest::SHA256.hexdigest(rendered.fetch("full_prompt_text"))
    @fixture.write_source_02b

    result = run_request
    refute result[:status].success?
    assert_includes result[:stderr], "rendered_five_lines must exact-copy compiled_prompt_block"
  end

  def test_attachment_store_drift_is_rejected_while_02a_bindings_still_hash
    packet = @fixture.packet("PKT_BC01_ACTION")
    member = packet.fetch("attachments").find { |row| row["role"] == "current_title_member_visual" }
    scene = packet.fetch("attachments").find { |row| row["role"] != "current_title_member_visual" }
    scene["actual_path"] = member.fetch("actual_path")
    scene["sha256"] = member.fetch("sha256")
    @fixture.write_source_02b

    result = run_request
    refute result[:status].success?
    assert_match(/attachments differ from locked 02A visual_reference_bindings|attachments must remain the transport projection/i, result[:stderr])
  end

  private

  def request_path
    @fixture.mv.run_dir.join("work", "image-generation-requests", "PKT_BC01_ACTION.yaml")
  end

  def run_request(output: nil, write: false, approval: nil)
    arguments = [RbConfig.ruby, SCRIPT.to_s, @fixture.mv.run_dir.to_s,
                 "--source-prompt-packets", @fixture.source_02b_path.to_s,
                 "--packet-id", "PKT_BC01_ACTION"]
    arguments.concat(["--approval-source", approval.to_s]) if approval
    arguments.concat(["--output", output.to_s]) if output
    arguments << "--write" if write
    stdout, stderr, status = Open3.capture3(*arguments, chdir: ROOT.to_s)
    {stdout: stdout, stderr: stderr, status: status}
  end
end
