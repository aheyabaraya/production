# frozen_string_literal: true

require "digest"
require "json"
require "minitest/autorun"
require "open3"
require "pathname"
require "rbconfig"
require "yaml"
require_relative "support/active_image_generation_fixture"

class IdolImageGenerationExecutorTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  PYTHON = ROOT.join("scripts", "idol-video-python")
  SCRIPT = ROOT.join("scripts", "idol_execute_image_generation_request.py")
  PREPARER = ROOT.join("scripts", "idol_prepare_image_generation_request.rb")
  REGISTRY = ROOT.join("automation", "harness-provider-profile-registry.yaml")

  def setup
    @fixture = ActiveImageGenerationFixture.create
    @request_path = prepare_request(@fixture)
  end

  def teardown
    @fixture&.cleanup
  end

  def test_openai_v12_preflight_uses_exact_snapshot_without_external_call
    marker = "mock-openai-key-must-never-be-emitted"
    result = run_executor("preflight", @request_path, env: {"OPENAI_API_KEY" => marker, "XAI_API_KEY" => nil})

    assert result[:status].success?, result[:stderr]
    report = JSON.parse(result[:stdout])
    assert_equal true, report["ok"]
    assert_equal false, report["external_call_performed"]
    assert_equal "openai_api_gpt_image_2", report["execution_adapter_id"]
    assert_equal "gpt-image-2", report["provider_model_or_tool"]
    assert_equal "/v1/images/edits", report["endpoint"]
    assert_equal "multipart_form_data_image_array", report["transport"]
    assert_equal "none", report["automatic_fallback"]
    assert_equal true, report["ready_for_execute"]
    refute_includes result[:stdout], marker
    refute_includes result[:stderr], marker
    refute ROOT.join(report.fetch("expected_output_path")).exist?
  end

  def test_missing_openai_process_credential_fails_closed_without_dotenv_read
    result = run_executor(
      "preflight",
      @request_path,
      env: {"OPENAI_API_KEY" => nil, "XAI_API_KEY" => nil},
      extra: ["--process-env-only"]
    )

    refute result[:status].success?
    assert_includes result[:stderr], "OPENAI_API_KEY is not present"
    refute_includes result[:stderr], "sk-"
  end

  def test_openai_execute_requires_runtime_founder_confirmation_before_network
    result = run_executor(
      "execute",
      @request_path,
      env: {"OPENAI_API_KEY" => "mock-openai-key", "XAI_API_KEY" => nil},
      extra: ["--founder-authority-id", "FOUNDER-GEN-AUTH-001"]
    )

    refute result[:status].success?
    assert_includes result[:stderr], "requires --confirm-external-paid-execution"
    request = YAML.safe_load(@request_path.read, aliases: true)
    refute ROOT.join(request.dig("expected_output", "path")).exist?

    authority_mismatch = run_executor(
      "execute",
      @request_path,
      env: {"OPENAI_API_KEY" => "mock-openai-key", "XAI_API_KEY" => nil},
      extra: ["--founder-authority-id", "WRONG-AUTHORITY", "--confirm-external-paid-execution"]
    )
    refute authority_mismatch[:status].success?
    assert_includes authority_mismatch[:stderr], "runtime Founder authority id differs"
    refute ROOT.join(request.dig("expected_output", "path")).exist?
  end

  def test_xai_registration_required_holds_before_credential_and_without_fallback
    @fixture.cleanup
    @fixture = xai_fixture
    @request_path = prepare_request(@fixture, adapter: "xai_api_media")
    marker = "mock-xai-key-must-never-be-emitted"

    result = run_executor("preflight", @request_path, env: {"OPENAI_API_KEY" => nil, "XAI_API_KEY" => marker})
    refute result[:status].success?
    assert_includes result[:stderr], "activation HOLD"
    assert_includes result[:stderr], "no fallback"
    refute_includes result[:stdout], marker
    refute_includes result[:stderr], marker

    execute = run_executor(
      "execute",
      @request_path,
      env: {"OPENAI_API_KEY" => nil, "XAI_API_KEY" => marker},
      extra: ["--founder-authority-id", "FOUNDER-GEN-AUTH-001", "--confirm-external-paid-execution"]
    )
    refute execute[:status].success?
    assert_includes execute[:stderr], "activation HOLD"
    assert_includes execute[:stderr], "no fallback"
  end

  def test_xai_registration_hold_precedes_missing_process_credential
    @fixture.cleanup
    @fixture = xai_fixture
    @request_path = prepare_request(@fixture, adapter: "xai_api_media")
    result = run_executor(
      "preflight",
      @request_path,
      env: {"OPENAI_API_KEY" => nil, "XAI_API_KEY" => nil},
      extra: ["--process-env-only"]
    )

    refute result[:status].success?
    assert_includes result[:stderr], "activation HOLD"
    refute_includes result[:stderr], "XAI_API_KEY is not present"
  end

  private

  def xai_fixture
    ActiveImageGenerationFixture.create(before_compile: lambda do |mv|
      registry_sha = Digest::SHA256.file(REGISTRY).hexdigest
      mv.delta.fetch("run_execution_selection")["image_execution_request"] = "xai_api_media"
      mv.delta.fetch("run_execution_selection")["image_execution_lane"] = "xai_api_media"
      mv.delta.fetch("packets").each do |packet|
        execution = packet.fetch("execution")
        execution.merge!(
          "execution_adapter_id" => "xai_api_media",
          "provider" => "xai_api",
          "provider_model_or_tool" => "fixture-unregistered-xai-model",
          "selected_native_tool" => nil,
          "auth_lane" => "founder_approved_api",
          "provider_profile_id" => "xai_fixture_registration_required",
          "provider_profile_sha256" => registry_sha,
          "provider_capability_snapshot_sha256" => registry_sha,
          "cli_or_api_version" => "fixture-registration-required-v1"
        )
      end
      mv.rewrite_delta
    end)
  end

  def prepare_request(fixture, adapter: "openai_api_gpt_image_2")
    approval = fixture.write_approval(packet_id: "PKT_BC01_ACTION", adapter: adapter)
    output = fixture.mv.run_dir.join("work", "image-generation-requests", "PKT_BC01_ACTION.yaml")
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      PREPARER.to_s,
      fixture.mv.run_dir.to_s,
      "--source-prompt-packets",
      fixture.source_02b_path.to_s,
      "--packet-id",
      "PKT_BC01_ACTION",
      "--approval-source",
      approval.to_s,
      "--output",
      output.to_s,
      "--write",
      chdir: ROOT.to_s
    )
    raise "request fixture failed: #{stderr}\n#{stdout}" unless status.success?
    output
  end

  def run_executor(command, request, env:, extra: [])
    stdout, stderr, status = Open3.capture3(
      env,
      PYTHON.to_s,
      SCRIPT.to_s,
      command,
      request.to_s,
      *extra,
      chdir: ROOT.to_s
    )
    {stdout: stdout, stderr: stderr, status: status}
  end
end
