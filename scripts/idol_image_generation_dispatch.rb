#!/usr/bin/env ruby
# frozen_string_literal: true

require "date"
require "digest"
require "json"
require "open3"
require "optparse"
require "pathname"
require "tempfile"
require "time"
require "yaml"
require_relative "lib/idol_image_execution_lane_contract"
require_relative "lib/idol_xai_api_media_profile_contract"

ROOT = Pathname.new(__dir__).join("..").expand_path
PYTHON = ROOT.join("scripts/idol-video-python")
VALIDATOR = ROOT.join("scripts/validate_json_schema.py")
WORKLIST_SCHEMA = ROOT.join("schemas/image-generation-section-worklist.schema.json")
LEDGER_SCHEMA = ROOT.join("schemas/image-generation-dispatch-ledger.schema.json")
EXECUTION_RECEIPT_SCHEMA = ROOT.join("schemas/image-generation-execution-receipt.schema.json")
XAI_PROFILE_SCHEMA = ROOT.join("schemas/xai-api-media-provider-profiles.schema.json")

class DispatchError < StandardError; end

def repo_path(raw, must_exist: false)
  path = Pathname.new(raw.to_s)
  path = ROOT.join(path) unless path.absolute?
  path = path.expand_path
  relative = path.relative_path_from(ROOT).to_s
  raise DispatchError, "path escapes repository root: #{raw}" if relative == ".." || relative.start_with?("../")
  raise DispatchError, "required file is missing: #{relative}" if must_exist && !path.file?
  [path, relative]
rescue ArgumentError
  raise DispatchError, "path escapes repository root: #{raw}"
end

def load_yaml(path, label)
  value = YAML.safe_load(path.read, permitted_classes: [Date, Time], aliases: true)
  raise DispatchError, "#{label} must be a mapping" unless value.is_a?(Hash)
  value
rescue Psych::Exception => e
  raise DispatchError, "cannot parse #{label}: #{e.message}"
end

def validate_schema(schema, path, label)
  stdout, stderr, status = Open3.capture3(
    IdolXaiApiMediaProfileContract::NONSECRET_CHILD_ENV,
    PYTHON.to_s,
    VALIDATOR.to_s,
    schema.to_s,
    path.to_s,
    chdir: ROOT.to_s
  )
  raise DispatchError, "#{label} failed schema validation: #{[stderr, stdout].join(' ').strip}" unless status.success?
end

def verify_pointer!(pointer, label)
  raise DispatchError, "#{label} must be a source pointer" unless pointer.is_a?(Hash)

  path, relative = repo_path(pointer["path"], must_exist: true)
  actual_sha = Digest::SHA256.file(path).hexdigest
  raise DispatchError, "#{label} SHA-256 is stale: #{relative}" unless actual_sha == pointer["sha256"].to_s
  path
end

def verify_current_provider_snapshot!(row, boundary)
  request_path = verify_pointer!(row["request"], "request #{row['packet_id']}")
  request = load_yaml(request_path, "generation request")
  row_execution_adapter = row["execution_adapter_id"].to_s
  request_execution = request["execution"]
  request_execution_adapter = request_execution.is_a?(Hash) ? request_execution["execution_adapter_id"].to_s : ""
  unless row_execution_adapter == request_execution_adapter
    raise DispatchError, "#{boundary}: worklist/ledger provider adapter binding differs from the exact request"
  end
  exact_fields = %w[
    execution_adapter_id provider auth_lane provider_profile_id
    provider_profile_sha256 provider_capability_snapshot_sha256 selected_native_tool
  ]
  exact_fields.each do |field|
    unless row[field].to_s == request_execution[field].to_s
      raise DispatchError, "#{boundary}: worklist/ledger #{field} differs from the exact provider request"
    end
  end
  selection_fields = %w[
    image_execution_request image_execution_request_origin
    image_execution_session_provider image_execution_lane
  ]
  selection_fields.each do |field|
    unless row[field].to_s == request.dig("run_execution_selection", field).to_s
      raise DispatchError, "#{boundary}: worklist/ledger #{field} differs from the exact request selection"
    end
  end
  begin
    IdolImageExecutionLaneContract.verify_execution_shape!(
      selection: request["run_execution_selection"],
      execution: request_execution,
      attachment_count: Array(request["attachments"]).length
    )
    if %w[codex_imagegen grok_image].include?(request_execution_adapter)
      IdolImageExecutionLaneContract.verify_registered_native_profile!(
        root: ROOT,
        selection: request["run_execution_selection"],
        execution: request_execution,
        attachment_count: Array(request["attachments"]).length
      )
    end
  rescue IdolImageExecutionLaneContract::ContractError => e
    raise DispatchError, "#{boundary}: #{e.message}"
  end
  if request_execution_adapter == "xai_api_media"
    begin
      registration = IdolXaiApiMediaProfileContract.verify_request!(root: ROOT, request: request)
    rescue IdolXaiApiMediaProfileContract::ContractError => e
      raise DispatchError, "#{boundary}: #{e.message}"
    end
    validate_schema(
      XAI_PROFILE_SCHEMA,
      Pathname.new(registration.fetch("profile_path")),
      "#{boundary} xAI API provider profile source"
    )
  end
  [request_path, request]
end

def validate_execution_receipt!(receipt_path, row)
  request_path, request = verify_current_provider_snapshot!(row, "dispatch pre-inspect/receipt-validation")
  validate_schema(EXECUTION_RECEIPT_SCHEMA, receipt_path, "image execution receipt")
  receipt = load_yaml(receipt_path, "image execution receipt")
  output_path, output_relative = repo_path(row.dig("output", "path"), must_exist: true)
  approval_ref = request.dig("approval", "approval_source")
  approval_path = verify_pointer!(approval_ref, "request approval source")
  expected = {
    "request_path" => row.dig("request", "path"),
    "request_sha256" => row.dig("request", "sha256"),
    "approval_path" => approval_ref["path"],
    "approval_sha256" => Digest::SHA256.file(approval_path).hexdigest,
    "packet_id" => row["packet_id"],
    "mode" => row["mode"],
    "cut_id" => row["cut_id"],
    "execution_adapter_id" => row["execution_adapter_id"],
    "provider" => row["provider"],
    "provider_model_or_tool" => request.dig("execution", "provider_model_or_tool"),
    "selected_native_tool" => request.dig("execution", "selected_native_tool"),
    "auth_lane" => row["auth_lane"],
    "provider_profile_id" => row["provider_profile_id"],
    "runtime_version" => request.dig("execution", "cli_or_api_version"),
    "provider_profile_sha256" => row["provider_profile_sha256"],
    "provider_capability_snapshot_sha256" => row["provider_capability_snapshot_sha256"],
    "founder_generation_authority_id" => request.dig("approval", "founder_generation_authority_id"),
    "spend_envelope" => request.dig("approval", "spend_envelope"),
    "prompt_sha256" => request.dig("prompt", "full_prompt_sha256"),
    "attachment_order_sha256" => request["attachment_order_sha256"],
    "output_path" => output_relative,
    "output_sha256" => Digest::SHA256.file(output_path).hexdigest
  }
  expected.each do |field, value|
    raise DispatchError, "image execution receipt #{field} differs from exact request/output bytes" unless receipt[field].to_s == value.to_s
  end
  raise DispatchError, "image execution receipt must remain pending full-size pixel review" unless receipt["status"] == "generated_pending_pixel_review" &&
                                                                                               receipt["full_size_pixel_review_status"] == "pending" &&
                                                                                               receipt["03v_handoff_allowed"] == false
  receipt
end

def atomic_write(path, document)
  yaml = YAML.dump(document)
  Tempfile.create(["idol-image-dispatch", ".yaml"], path.dirname.to_s) do |temp|
    temp.write(yaml)
    temp.flush
    temp.fsync
    validate_schema(LEDGER_SCHEMA, Pathname.new(temp.path), "dispatch ledger")
    File.rename(temp.path, path)
  end
end

def refresh_status!(ledger)
  states = Array(ledger["queue"]).map { |row| row["state"].to_s }
  ledger["status"] = if states.any? { |state| %w[failed hold].include?(state) } ||
                        Array(ledger["queue"]).any? { |row| row.dig("pixel_inspection", "status").to_s == "reject" }
                       "hold"
                     elsif states.all? { |state| state == "passed" }
                       "complete"
                     elsif states.any? { |state| state == "generated" }
                       "awaiting_pixel_inspection"
                     elsif states.any? { |state| state == "claimed" }
                       "in_progress"
                     else
                       "ready"
                     end
end

def mutate_ledger(path)
  path.dirname.mkpath
  lock_path = path.dirname.join(".#{path.basename}.lock")
  File.open(lock_path, File::RDWR | File::CREAT, 0o600) do |lock|
    lock.flock(File::LOCK_EX)
    document = YAML.safe_load(path.read, permitted_classes: [Date, Time], aliases: true)
    raise DispatchError, "dispatch ledger must be a mapping" unless document.is_a?(Hash)
    yield document
    refresh_status!(document)
    atomic_write(path, document)
    document
  end
end

command = ARGV.shift
options = {write: false, limit: nil}
parser = OptionParser.new do |opts|
  opts.banner = <<~USAGE
    usage:
      ruby scripts/idol_image_generation_dispatch.rb init WORKLIST --section-id S00 --capacity N --output LEDGER --write
      ruby scripts/idol_image_generation_dispatch.rb claim LEDGER --runner-id ID [--limit N] --write
      ruby scripts/idol_image_generation_dispatch.rb record LEDGER --packet-id ID --result generated|failed|hold [--output-path PATH --original-provider-output-path PATH --runtime-version VERSION --usage-snapshot TEXT --auth-verified --watermark-present|--watermark-absent] [--note TEXT] --write
      ruby scripts/idol_image_generation_dispatch.rb inspect LEDGER --packet-id ID --decision pass|reject --receipt PATH --write
      ruby scripts/idol_image_generation_dispatch.rb retry LEDGER --packet-id ID --note TEXT --write
  USAGE
  opts.on("--section-id ID") { |value| options[:section_id] = value }
  opts.on("--capacity N", Integer) { |value| options[:capacity] = value }
  opts.on("--output PATH") { |value| options[:output] = value }
  opts.on("--runner-id ID") { |value| options[:runner_id] = value }
  opts.on("--limit N", Integer) { |value| options[:limit] = value }
  opts.on("--packet-id ID") { |value| options[:packet_id] = value }
  opts.on("--result RESULT") { |value| options[:result] = value }
  opts.on("--output-path PATH") { |value| options[:output_path] = value }
  opts.on("--original-provider-output-path PATH") { |value| options[:original_provider_output_path] = value }
  opts.on("--runtime-version VERSION") { |value| options[:runtime_version] = value }
  opts.on("--usage-snapshot TEXT") { |value| options[:usage_snapshot] = value }
  opts.on("--auth-verified") { options[:auth_verified] = true }
  opts.on("--watermark-present") { options[:watermark] = true }
  opts.on("--watermark-absent") { options[:watermark] = false }
  opts.on("--decision DECISION") { |value| options[:decision] = value }
  opts.on("--receipt PATH") { |value| options[:receipt] = value }
  opts.on("--note TEXT") { |value| options[:note] = value }
  opts.on("--write") { options[:write] = true }
end
parser.parse!(ARGV)

begin
  raise DispatchError, parser.to_s unless %w[init claim record inspect retry].include?(command)
  argument = ARGV.shift
  raise DispatchError, "worklist or ledger path is required" if argument.to_s.empty?
  raise DispatchError, "unexpected arguments: #{ARGV.join(' ')}" unless ARGV.empty?
  raise DispatchError, "--write is required for dispatch state transitions" unless options[:write]

  if command == "init"
    worklist_path, worklist_rel = repo_path(argument, must_exist: true)
    validate_schema(WORKLIST_SCHEMA, worklist_path, "section worklist")
    worklist = load_yaml(worklist_path, "section worklist")
    section_id = options[:section_id].to_s
    raise DispatchError, "--section-id is required" if section_id.empty?
    capacity = options[:capacity].to_i
    raise DispatchError, "--capacity must be between 1 and 32" unless capacity.between?(1, 32)
    section = Array(worklist["sections"]).find { |row| row["section_id"].to_s == section_id }
    raise DispatchError, "section is not present in worklist: #{section_id}" unless section
    raise DispatchError, "section worklist is not ready: #{Array(section['hold_reasons']).join(' | ')}" unless section["status"].to_s == "ready"
    output_path, output_rel = repo_path(options[:output] || Pathname.new(worklist_rel).dirname.join("dispatch-#{section_id}.yaml").to_s)
    run_rel = worklist["run"].to_s
    raise DispatchError, "dispatch ledger must stay inside the owning run" unless output_rel.start_with?("#{run_rel}/")
    queue = Array(section["requests"]).map do |row|
      verify_current_provider_snapshot!(
        row.merge("request" => {"path" => row["path"], "sha256" => row["sha256"]}),
        "dispatch init"
      )
      {
        "packet_id" => row["packet_id"],
        "mode" => row["mode"],
        "cut_id" => row["cut_id"],
        "cut_type" => row["cut_type"],
        "parent_core_cut_id" => row["parent_core_cut_id"],
        "production_scope_id" => row["production_scope_id"],
        "image_execution_request" => row["image_execution_request"],
        "image_execution_request_origin" => row["image_execution_request_origin"],
        "image_execution_session_provider" => row["image_execution_session_provider"],
        "image_execution_lane" => row["image_execution_lane"],
        "execution_adapter_id" => row["execution_adapter_id"],
        "provider" => row["provider"],
        "auth_lane" => row["auth_lane"],
        "provider_profile_id" => row["provider_profile_id"],
        "provider_profile_sha256" => row["provider_profile_sha256"],
        "provider_capability_snapshot_sha256" => row["provider_capability_snapshot_sha256"],
        "selected_native_tool" => row["selected_native_tool"],
        "request" => {"path" => row["path"], "sha256" => row["sha256"]},
        "expected_output_path" => row["expected_output_path"],
        "state" => "pending",
        "attempt_count" => 0,
        "claim" => nil,
        "output" => nil,
        "pixel_inspection" => nil
      }
    end
    ledger = {
      "schema_version" => "idol_image_generation_dispatch_ledger.v4",
      "artifact_type" => "image_generation_dispatch_ledger",
      "run" => run_rel,
      "source_worklist" => {"path" => worklist_rel, "sha256" => Digest::SHA256.file(worklist_path).hexdigest},
      "section_id" => section_id,
      "status" => "ready",
      "capacity" => {
        "max_in_flight" => capacity,
        "one_packet_per_call" => true,
        "same_output_parallel_write_forbidden" => true
      },
      "queue" => queue,
      "return_recipient" => "creative_development_director",
      "automation_boundaries" => {
        "model_call_performed_by_ledger" => false,
        "approval_granted" => false,
        "prompt_or_attachment_rewrite_performed" => false,
        "provider_auth_model_fallback" => "none"
      }
    }
    output_path.dirname.mkpath
    atomic_write(output_path, ledger)
    puts JSON.pretty_generate("status" => ledger["status"], "ledger" => output_rel, "queue_count" => queue.length, "max_in_flight" => capacity)
    exit 0
  end

  ledger_path, ledger_rel = repo_path(argument, must_exist: true)
  validate_schema(LEDGER_SCHEMA, ledger_path, "dispatch ledger")
  current_ledger = load_yaml(ledger_path, "dispatch ledger")
  verify_pointer!(current_ledger["source_worklist"], "source worklist")
  Array(current_ledger["queue"]).each do |row|
    verify_pointer!(row["request"], "request #{row['packet_id']}")
  end
  response = {}
  ledger = mutate_ledger(ledger_path) do |document|
    case command
    when "claim"
      runner_id = options[:runner_id].to_s
      raise DispatchError, "--runner-id is required" if runner_id.empty?
      raise DispatchError, "dispatch ledger is held or complete" if %w[hold complete].include?(document["status"].to_s)
      active_count = Array(document["queue"]).count { |row| row["state"].to_s == "claimed" }
      available = document.dig("capacity", "max_in_flight").to_i - active_count
      requested_limit = options[:limit] ? options[:limit].to_i : available
      claim_count = [available, requested_limit].min
      raise DispatchError, "no dispatch capacity is available" unless claim_count.positive?
      claimed = Array(document["queue"]).select { |row| row["state"].to_s == "pending" }.first(claim_count)
      raise DispatchError, "no pending requests are available" if claimed.empty?
      claimed.each do |row|
        verify_current_provider_snapshot!(row, "dispatch pre-claim")
        row["attempt_count"] = row["attempt_count"].to_i + 1
        material = "#{row.dig('request', 'sha256')}|#{row['attempt_count']}"
        digest = Digest::SHA256.hexdigest(material)
        row["claim"] = {
          "attempt_id" => "ATT_#{digest[0, 16].upcase}",
          "runner_id" => runner_id,
          "claimed_at" => Time.now.utc.iso8601,
          "idempotency_key" => digest
        }
        row["state"] = "claimed"
        row.delete("failure_note")
      end
      response["claims"] = claimed.map do |row|
        {
          "packet_id" => row["packet_id"],
          "mode" => row["mode"],
          "cut_id" => row["cut_id"],
          "cut_type" => row["cut_type"],
          "execution_adapter_id" => row["execution_adapter_id"],
          "image_execution_lane" => row["image_execution_lane"],
          "selected_native_tool" => row["selected_native_tool"],
          "request_path" => row.dig("request", "path"),
          "request_sha256" => row.dig("request", "sha256"),
          "expected_output_path" => row["expected_output_path"],
          "attempt_id" => row.dig("claim", "attempt_id"),
          "idempotency_key" => row.dig("claim", "idempotency_key")
        }
      end
    when "record"
      packet_id = options[:packet_id].to_s
      result = options[:result].to_s
      raise DispatchError, "--packet-id is required" if packet_id.empty?
      raise DispatchError, "--result must be generated, failed, or hold" unless %w[generated failed hold].include?(result)
      row = Array(document["queue"]).find { |item| item["packet_id"].to_s == packet_id }
      raise DispatchError, "packet is not present in ledger: #{packet_id}" unless row
      raise DispatchError, "packet must be claimed before record" unless row["state"].to_s == "claimed"
      if result == "generated"
        _request_path, request = verify_current_provider_snapshot!(row, "dispatch pre-record")
        output_path, output_rel = repo_path(options[:output_path], must_exist: true)
        raise DispatchError, "--output-path must equal the request expected output path" unless output_rel == row["expected_output_path"].to_s
        original_path, original_rel = repo_path(options[:original_provider_output_path], must_exist: true)
        raise DispatchError, "--runtime-version is required" if options[:runtime_version].to_s.empty?
        raise DispatchError, "--usage-snapshot is required" if options[:usage_snapshot].to_s.empty?
        raise DispatchError, "--auth-verified is required without recording secret material" unless options[:auth_verified]
        raise DispatchError, "watermark presence must be explicitly recorded" unless options.key?(:watermark)
        output_sha = Digest::SHA256.file(output_path).hexdigest
        exact_model_or_tool = request.dig("execution", "selected_native_tool") || request.dig("execution", "provider_model_or_tool")
        media_receipt = {
          "provider" => request.dig("execution", "provider"),
          "exact_model_or_tool" => exact_model_or_tool,
          "runtime_version" => options[:runtime_version],
          "auth_lane" => request.dig("execution", "auth_lane"),
          "auth_verified_without_secret_material" => true,
          "provider_profile_id" => request.dig("execution", "provider_profile_id"),
          "provider_profile_sha256" => request.dig("execution", "provider_profile_sha256"),
          "provider_capability_snapshot_sha256" => request.dig("execution", "provider_capability_snapshot_sha256"),
          "prompt_sha256" => request.dig("prompt", "full_prompt_sha256"),
          "ordered_input_sha256s" => Array(request["attachments"]).map { |attachment| attachment["sha256"] },
          "expected_output_path" => row["expected_output_path"],
          "original_provider_output_path" => original_rel,
          "canonical_ingested_path" => output_rel,
          "output_sha256" => output_sha,
          "watermark_present" => options[:watermark],
          "usage_snapshot" => options[:usage_snapshot],
          "pixel_review_status" => "generated_unreviewed",
          "provider_auth_model_fallback" => "none"
        }
        row["output"] = {"path" => output_rel, "sha256" => output_sha, "recorded_at" => Time.now.utc.iso8601, "media_execution_receipt" => media_receipt}
        row["pixel_inspection"] = nil
        row["state"] = "generated"
      else
        note = options[:note].to_s.strip
        raise DispatchError, "--note is required for failed or hold" if note.empty?
        row["state"] = result
        row["failure_note"] = note
      end
      response["packet_id"] = packet_id
      response["recorded_result"] = result
    when "inspect"
      packet_id = options[:packet_id].to_s
      decision = options[:decision].to_s
      raise DispatchError, "--packet-id is required" if packet_id.empty?
      raise DispatchError, "--decision must be pass or reject" unless %w[pass reject].include?(decision)
      row = Array(document["queue"]).find { |item| item["packet_id"].to_s == packet_id }
      raise DispatchError, "packet is not present in ledger: #{packet_id}" unless row
      raise DispatchError, "packet must have a generated output before inspection" unless row["state"].to_s == "generated" && row["output"].is_a?(Hash)
      receipt_path, receipt_rel = repo_path(options[:receipt], must_exist: true)
      validate_execution_receipt!(receipt_path, row)
      row["pixel_inspection"] = {
        "status" => decision,
        "receipt" => {"path" => receipt_rel, "sha256" => Digest::SHA256.file(receipt_path).hexdigest},
        "reviewer" => "creative_development_director_or_bounded_image_worker_returned_to_cdd"
      }
      row.dig("output", "media_execution_receipt")["pixel_review_status"] = decision == "pass" ? "passed" : "rejected"
      row["state"] = decision == "pass" ? "passed" : "hold"
      row["failure_note"] = "pixel inspection rejected this generated output" if decision == "reject"
      response["packet_id"] = packet_id
      response["inspection"] = decision
    when "retry"
      packet_id = options[:packet_id].to_s
      note = options[:note].to_s.strip
      raise DispatchError, "--packet-id and --note are required" if packet_id.empty? || note.empty?
      row = Array(document["queue"]).find { |item| item["packet_id"].to_s == packet_id }
      raise DispatchError, "packet is not present in ledger: #{packet_id}" unless row
      raise DispatchError, "only failed or held packets may be retried" unless %w[failed hold].include?(row["state"].to_s)
      row["state"] = "pending"
      row["claim"] = nil
      row["output"] = nil
      row["pixel_inspection"] = nil
      row["failure_note"] = "retry authorized: #{note}"
      response["packet_id"] = packet_id
      response["retry"] = "pending"
    end
  end
  response["ledger"] = ledger_rel
  response["status"] = ledger["status"]
  response["counts"] = Array(ledger["queue"]).group_by { |row| row["state"] }.transform_values(&:length)
  puts JSON.pretty_generate(response)
rescue DispatchError => e
  warn "ERROR: #{e.message}"
  exit 1
end
