# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "pathname"
require "tmpdir"
require "yaml"

class IdolImageGenerationDispatchTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("../..").expand_path
  SCRIPT = ROOT.join("scripts/idol_image_generation_dispatch.rb")

  def setup
    run_parent = ROOT.join("runs/test-album/image-dispatch")
    run_parent.mkpath
    @run = Pathname.new(Dir.mktmpdir("TEST_IMAGE_DISPATCH_", run_parent.to_s))
    @run_rel = @run.relative_path_from(ROOT).to_s
    @approval = write("review/approvals/S00.yaml", {"schema_version" => "idol_image_generation_section_approval.v6", "status" => "approved"})
    @request_one = write("work/requests/PKT_01.yaml", request_fixture("PKT_01"))
    @request_two = write("work/requests/PKT_02.yaml", request_fixture("PKT_02"))
    @output_one = @run.join("generations/image/PKT_01.png")
    @output_two = @run.join("generations/image/PKT_02.png")
    @worklist = write("work/image-generation-section-worklist.yaml", worklist_fixture)
    @ledger = @run.join("work/dispatch-S00.yaml")
  end

  def teardown
    FileUtils.remove_entry(@run) if @run&.directory?
  end

  def test_bounded_parallel_claim_record_and_pixel_barrier
    init = run_dispatch(
      "init", @worklist.to_s,
      "--section-id", "S00",
      "--capacity", "2",
      "--output", @ledger.to_s,
      "--write"
    )
    assert init[:status].success?, init[:stderr]

    claim = run_dispatch("claim", @ledger.to_s, "--runner-id", "fixture-runner", "--limit", "2", "--write")
    assert claim[:status].success?, claim[:stderr]
    claims = JSON.parse(claim[:stdout]).fetch("claims")
    assert_equal %w[PKT_01 PKT_02], claims.map { |row| row.fetch("packet_id") }
    assert_equal 2, claims.map { |row| row.fetch("idempotency_key") }.uniq.length

    @output_one.dirname.mkpath
    @output_one.binwrite("image-one")
    @output_two.binwrite("image-two")
    [@output_one, @output_two].each_with_index do |output, index|
      packet_id = format("PKT_%02d", index + 1)
      original = @run.join("provider-returns/#{packet_id}.png")
      original.dirname.mkpath
      original.binwrite("provider-#{packet_id}")
      record = run_dispatch(
        "record", @ledger.to_s,
        "--packet-id", packet_id,
        "--result", "generated",
        "--output-path", output.to_s,
        "--original-provider-output-path", original.to_s,
        "--runtime-version", "dry-run-fixture-v1",
        "--usage-snapshot", "fixture_no_paid_generation",
        "--auth-verified",
        "--watermark-absent",
        "--write"
      )
      assert record[:status].success?, record[:stderr]
    end

    awaiting = YAML.safe_load(@ledger.read, permitted_classes: [], aliases: true)
    assert_equal "awaiting_pixel_inspection", awaiting.fetch("status")
    assert awaiting.fetch("queue").all? { |row| row.fetch("state") == "generated" }

    receipt_one = write("review/pixel/PKT_01.yaml", execution_receipt_fixture("PKT_01", @request_one, @output_one))
    receipt_two = write("review/pixel/PKT_02.yaml", execution_receipt_fixture("PKT_02", @request_two, @output_two))
    [receipt_one, receipt_two].each_with_index do |receipt, index|
      packet_id = format("PKT_%02d", index + 1)
      inspect_result = run_dispatch(
        "inspect", @ledger.to_s,
        "--packet-id", packet_id,
        "--decision", "pass",
        "--receipt", receipt.to_s,
        "--write"
      )
      assert inspect_result[:status].success?, inspect_result[:stderr]
    end

    complete = YAML.safe_load(@ledger.read, permitted_classes: [], aliases: true)
    assert_equal "complete", complete.fetch("status")
    assert complete.fetch("queue").all? { |row| row.fetch("state") == "passed" }
  end

  def test_pixel_inspection_rejects_a_tampered_execution_receipt
    assert run_dispatch(
      "init", @worklist.to_s,
      "--section-id", "S00",
      "--capacity", "1",
      "--output", @ledger.to_s,
      "--write"
    )[:status].success?
    assert run_dispatch("claim", @ledger.to_s, "--runner-id", "fixture-runner", "--limit", "1", "--write")[:status].success?
    @output_one.dirname.mkpath
    @output_one.binwrite("image-one")
    original = @run.join("provider-returns/PKT_01.png")
    original.dirname.mkpath
    original.binwrite("provider-PKT_01")
    record = run_dispatch(
      "record", @ledger.to_s,
      "--packet-id", "PKT_01",
      "--result", "generated",
      "--output-path", @output_one.to_s,
      "--original-provider-output-path", original.to_s,
      "--runtime-version", "dry-run-fixture-v1",
      "--usage-snapshot", "fixture_no_paid_generation",
      "--auth-verified",
      "--watermark-absent",
      "--write"
    )
    assert record[:status].success?, record[:stderr]
    receipt = execution_receipt_fixture("PKT_01", @request_one, @output_one)
    receipt["output_sha256"] = "f" * 64
    receipt_path = write("review/pixel/PKT_01-tampered.yaml", receipt)
    inspection = run_dispatch(
      "inspect", @ledger.to_s,
      "--packet-id", "PKT_01",
      "--decision", "pass",
      "--receipt", receipt_path.to_s,
      "--write"
    )
    refute inspection[:status].success?
    assert_includes inspection[:stderr], "output_sha256 differs from exact request/output bytes"
  end

  def test_claim_fails_when_selected_request_bytes_drift
    init = run_dispatch(
      "init", @worklist.to_s,
      "--section-id", "S00",
      "--capacity", "2",
      "--output", @ledger.to_s,
      "--write"
    )
    assert init[:status].success?, init[:stderr]
    @request_one.write(YAML.dump("packet_id" => "TAMPERED"))

    claim = run_dispatch("claim", @ledger.to_s, "--runner-id", "fixture-runner", "--write")
    refute claim[:status].success?
    assert_includes claim[:stderr], "request PKT_01 SHA-256 is stale"
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
      "sha256" => Digest::SHA256.file(path).hexdigest
    }
  end

  def request_row(packet_id, request_path, output_path)
    sequence = packet_id.delete_prefix("PKT_")
    {
      "path" => request_path.relative_path_from(ROOT).to_s,
      "sha256" => Digest::SHA256.file(request_path).hexdigest,
      "packet_id" => packet_id,
      "mode" => "official_branch",
      "cut_id" => "BC#{sequence}_PRIMARY",
      "cut_type" => "branch",
      "parent_core_cut_id" => "C#{sequence}",
      "production_scope_id" => "PRODUCTION_SCOPE_S00",
      "image_execution_request" => "openai_api_gpt_image_2",
      "image_execution_request_origin" => "founder_explicit",
      "image_execution_session_provider" => "codex",
      "image_execution_lane" => "openai_api_gpt_image_2",
      "execution_adapter_id" => "openai_api_gpt_image_2",
      "provider" => "openai",
      "auth_lane" => "founder_approved_api",
      "provider_profile_id" => "openai_image_api_current",
      "provider_profile_sha256" => "2" * 64,
      "provider_capability_snapshot_sha256" => "3" * 64,
      "selected_native_tool" => nil,
      "request_status" => "ready",
      "prompt_sha256" => "1" * 64,
      "attachment_order_sha256" => "4" * 64,
      "expected_output_path" => output_path.relative_path_from(ROOT).to_s
    }
  end

  def request_fixture(packet_id)
    sequence = packet_id.delete_prefix("PKT_")
    {
      "schema_version" => "idol_image_generation_request.v12",
      "packet_id" => packet_id,
      "mode" => "official_branch",
      "cut_pointer" => {"cut_id" => "BC#{sequence}_PRIMARY"},
      "run_execution_selection" => {
        "creative_role_provider" => "codex",
        "image_execution_request" => "openai_api_gpt_image_2",
        "image_execution_request_origin" => "founder_explicit",
        "image_execution_session_provider" => "codex",
        "image_execution_lane" => "openai_api_gpt_image_2",
        "video_execution_lane" => "other_registered",
        "automatic_fallback" => "none"
      },
      "execution" => {
        "execution_adapter_id" => "openai_api_gpt_image_2",
        "provider" => "openai",
        "auth_lane" => "founder_approved_api",
        "provider_model_or_tool" => "gpt-image-2",
        "selected_native_tool" => nil,
        "provider_profile_id" => "openai_image_api_current",
        "cli_or_api_version" => "fixture-openai-api-v1",
        "provider_profile_sha256" => "2" * 64,
        "provider_capability_snapshot_sha256" => "3" * 64,
        "prompt_rewrite_policy" => "forbidden",
        "automatic_fallback" => "none"
      },
      "approval" => {
        "approval_source" => pointer(@approval),
        "founder_generation_authority_id" => "FOUNDER-AUTH-001",
        "spend_envelope" => "one_fixture_image"
      },
      "prompt" => {"full_prompt_sha256" => "1" * 64},
      "reference_role_plan" => {"fixture_id" => "REFERENCE_ROLE_PLAN_#{packet_id}"},
      "attachment_order_sha256" => "4" * 64,
      "attachments" => []
    }
  end

  def execution_receipt_fixture(packet_id, request_path, output_path)
    request = YAML.safe_load(request_path.read, permitted_classes: [], aliases: true)
    {
      "schema_version" => "idol_image_generation_execution_receipt.v4",
      "request_schema_version" => request.fetch("schema_version"),
      "reference_role_plan_sha256" => Digest::SHA256.hexdigest(JSON.generate(request.fetch("reference_role_plan"))),
      "artifact_type" => "image_generation_execution_receipt",
      "status" => "generated_pending_pixel_review",
      "external_call_performed" => true,
      "request_path" => request_path.relative_path_from(ROOT).to_s,
      "request_sha256" => Digest::SHA256.file(request_path).hexdigest,
      "approval_path" => @approval.relative_path_from(ROOT).to_s,
      "approval_sha256" => Digest::SHA256.file(@approval).hexdigest,
      "packet_id" => packet_id,
      "mode" => request.fetch("mode"),
      "cut_id" => request.dig("cut_pointer", "cut_id"),
      "execution_adapter_id" => "openai_api_gpt_image_2",
      "provider" => "openai",
      "provider_model_or_tool" => "gpt-image-2",
      "selected_native_tool" => nil,
      "auth_lane" => "founder_approved_api",
      "provider_profile_id" => "openai_image_api_current",
      "runtime_version" => "fixture-openai-api-v1",
      "provider_profile_sha256" => "2" * 64,
      "provider_capability_snapshot_sha256" => "3" * 64,
      "founder_generation_authority_id" => "FOUNDER-AUTH-001",
      "spend_envelope" => "one_fixture_image",
      "prompt_sha256" => "1" * 64,
      "attachment_order_sha256" => "4" * 64,
      "endpoint" => "/v1/images/generations",
      "transport" => "json",
      "response_image_encoding" => "base64_json",
      "native_session_binding" => nil,
      "output_count" => 1,
      "output_path" => output_path.relative_path_from(ROOT).to_s,
      "output_sha256" => Digest::SHA256.file(output_path).hexdigest,
      "automatic_fallback" => "none",
      "prompt_rewrite_policy" => "forbidden",
      "full_size_pixel_review_status" => "pending",
      "03v_handoff_allowed" => false,
      "secret_values_recorded" => false
    }
  end

  def worklist_fixture
    request_rows = [
      request_row("PKT_01", @request_one, @output_one),
      request_row("PKT_02", @request_two, @output_two)
    ]
    {
      "schema_version" => "idol_image_generation_section_worklist.v9",
      "artifact_type" => "derived_image_generation_section_worklist",
      "run" => @run_rel,
      "request_set_sha256" => Digest::SHA256.hexdigest(JSON.generate(request_rows)),
      "source_prompt_packets" => pointer(@request_one),
      "source_selection" => pointer(@request_two),
      "status" => "ready",
      "summary" => {
        "section_count" => 1,
        "request_count" => 2,
        "ready_section_count" => 1,
        "hold_section_count" => 0
      },
      "sections" => [{
        "section_id" => "S00",
        "production_scope_ids" => ["PRODUCTION_SCOPE_S00"],
        "status" => "ready",
        "dispatch_contract" => {
          "request_unit" => "one_exact_packet_per_generation_call",
          "all_authorized_jobs_preserved" => true,
          "failure_isolation" => "affected_job_only_unless_shared_locked_input_is_invalid",
          "prompt_or_attachment_rewrite" => "forbidden",
          "provider_auth_model_fallback" => "none",
          "result_barrier" => "exact_expected_path_sha256_and_full_size_pixel_review_before_03v",
          "controller_script" => "scripts/idol_image_generation_dispatch.rb",
          "ledger_schema" => "schemas/image-generation-dispatch-ledger.schema.json"
        },
        "requests" => request_rows,
        "output_paths" => request_rows.map { |row| row.fetch("expected_output_path") },
        "hold_reasons" => [],
        "return_recipient" => "creative_development_director"
      }],
      "coordinator_contract" => {
        "single_writer_per_job" => true,
        "bounded_parallel_disjoint_jobs" => true,
        "same_output_parallel_write_forbidden" => true,
        "promotion_authority" => "founder_only_after_cdd_pixel_review"
      },
      "automation_boundaries" => {
        "derived_noncanonical" => true,
        "model_called" => false,
        "external_mutation_performed" => false,
        "paid_generation_performed" => false,
        "approval_granted" => false
      }
    }
  end

  def run_dispatch(*arguments)
    stdout, stderr, status = Open3.capture3(
      "ruby", SCRIPT.to_s, *arguments,
      chdir: ROOT.to_s
    )
    {stdout: stdout, stderr: stderr, status: status}
  end
end
