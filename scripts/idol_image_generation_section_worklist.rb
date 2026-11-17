#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "optparse"
require "pathname"
require "tempfile"
require "yaml"
require_relative "lib/idol_image_execution_lane_contract"
require_relative "lib/idol_xai_api_media_profile_contract"

ROOT = Pathname.new(__dir__).join("..").expand_path
PYTHON = ROOT.join("scripts/idol-video-python")
VALIDATOR = ROOT.join("scripts/validate_json_schema.py")
REQUEST_SCHEMA = ROOT.join("schemas/image-generation-request.schema.json")
SELECTION_SCHEMA = ROOT.join("schemas/image-generation-request-selection.schema.json")
WORKLIST_SCHEMA = ROOT.join("schemas/image-generation-section-worklist.schema.json")
XAI_PROFILE_SCHEMA = ROOT.join("schemas/xai-api-media-provider-profiles.schema.json")

options = {write: false}
OptionParser.new do |parser|
  parser.banner = "usage: ruby scripts/idol_image_generation_section_worklist.rb RUN --selection PATH [--output PATH] [--write]"
  parser.on("--selection PATH") { |value| options[:selection] = value }
  parser.on("--output PATH") { |value| options[:output] = value }
  parser.on("--write") { options[:write] = true }
end.parse!
abort "RUN is required" unless ARGV.length == 1
abort "--selection is required" if options[:selection].to_s.empty?

def repo_path(raw, must_exist: false)
  path = Pathname.new(raw.to_s)
  path = ROOT.join(path) unless path.absolute?
  path = path.expand_path.cleanpath
  relative = path.relative_path_from(ROOT).to_s
  abort "path escapes repository: #{raw}" if relative == ".." || relative.start_with?("../")
  abort "required file is missing: #{relative}" if must_exist && !path.file?
  [path, relative]
rescue ArgumentError
  abort "path escapes repository: #{raw}"
end

def load_yaml(path)
  value = YAML.safe_load(path.read, permitted_classes: [], aliases: true)
  abort "#{path} must contain a mapping" unless value.is_a?(Hash)
  value
end

def validate(schema, path, label)
  stdout, stderr, status = Open3.capture3(
    IdolXaiApiMediaProfileContract::NONSECRET_CHILD_ENV,
    PYTHON.to_s,
    VALIDATOR.to_s,
    schema.to_s,
    path.to_s,
    chdir: ROOT.to_s
  )
  abort "#{label} failed schema validation: #{[stderr, stdout].join(' ').strip}" unless status.success?
end

run_path, run_rel = repo_path(ARGV.fetch(0))
abort "run must stay inside runs/" unless run_rel.start_with?("runs/")
run_prefix = "#{run_path}#{File::SEPARATOR}"
selection_path, selection_rel = repo_path(options[:selection], must_exist: true)
abort "selection must stay in the owning run" unless selection_path.to_s.start_with?(run_prefix)
validate(SELECTION_SCHEMA, selection_path, "request selection")
selection = load_yaml(selection_path)
abort "selection belongs to another run" unless selection["run"].to_s == run_rel

source_pointer = selection.fetch("source_02b")
source_path, source_rel = repo_path(source_pointer.fetch("path"), must_exist: true)
abort "source Prompt Packets must stay in the owning run" unless source_path.to_s.start_with?(run_prefix)
abort "selection source Prompt Packets hash is stale" unless Digest::SHA256.file(source_path).hexdigest == source_pointer.fetch("sha256")

rows = Array(selection["requests"]).map do |pointer|
  path, relative = repo_path(pointer.fetch("path"), must_exist: true)
  abort "request must stay in the owning run" unless path.to_s.start_with?(run_prefix)
  digest = Digest::SHA256.file(path).hexdigest
  abort "request hash is stale: #{relative}" unless digest == pointer.fetch("sha256")
  validate(REQUEST_SCHEMA, path, "image request #{relative}")
  request = load_yaml(path)
  abort "request belongs to another run" unless request["run"].to_s == run_rel
  abort "request source Prompt Packet bytes differ" unless request.dig("source_prompt_packet", "path").to_s == source_rel && request.dig("source_prompt_packet", "sha256").to_s == source_pointer.fetch("sha256")
  actual = {
    "section_id" => request["section_id"],
    "packet_id" => request["packet_id"],
    "mode" => request["mode"],
    "cut_id" => request.dig("cut_pointer", "cut_id"),
    "cut_type" => request.dig("cut_pointer", "cut_type"),
    "image_execution_request" => request.dig("run_execution_selection", "image_execution_request"),
    "image_execution_request_origin" => request.dig("run_execution_selection", "image_execution_request_origin"),
    "image_execution_session_provider" => request.dig("run_execution_selection", "image_execution_session_provider"),
    "image_execution_lane" => request.dig("run_execution_selection", "image_execution_lane"),
    "execution_adapter_id" => request.dig("execution", "execution_adapter_id"),
    "provider" => request.dig("execution", "provider"),
    "auth_lane" => request.dig("execution", "auth_lane"),
    "provider_profile_id" => request.dig("execution", "provider_profile_id"),
    "provider_profile_sha256" => request.dig("execution", "provider_profile_sha256"),
    "provider_capability_snapshot_sha256" => request.dig("execution", "provider_capability_snapshot_sha256"),
    "expected_output_path" => request.dig("expected_output", "path")
  }
  actual.each { |key, value| abort "selection #{key} mismatch for #{relative}" unless pointer[key].to_s == value.to_s }
  provider_hold_reason = nil
  begin
    IdolImageExecutionLaneContract.verify_execution_shape!(
      selection: request["run_execution_selection"],
      execution: request["execution"],
      attachment_count: Array(request["attachments"]).length
    )
    if %w[codex_imagegen grok_image].include?(request.dig("execution", "execution_adapter_id").to_s)
      IdolImageExecutionLaneContract.verify_registered_native_profile!(
        root: ROOT,
        selection: request["run_execution_selection"],
        execution: request["execution"],
        attachment_count: Array(request["attachments"]).length
      )
    end
    registration = IdolXaiApiMediaProfileContract.verify_request!(root: ROOT, request: request)
    if registration
      validate(
        XAI_PROFILE_SCHEMA,
        Pathname.new(registration.fetch("profile_path")),
        "xAI API provider profile source"
      )
    end
  rescue IdolImageExecutionLaneContract::ContractError, IdolXaiApiMediaProfileContract::ContractError => e
    provider_hold_reason = "provider-specific request cannot become ready: #{e.message}"
  end
  {"path" => relative, "sha256" => digest, "request" => request, "provider_hold_reason" => provider_hold_reason}
end

duplicate_packets = rows.group_by { |row| row.dig("request", "packet_id") }.select { |_key, group| group.length > 1 }.keys
duplicate_outputs = rows.group_by { |row| row.dig("request", "expected_output", "path") }.select { |_key, group| group.length > 1 }.keys
global_holds = []
global_holds << "duplicate packet ids: #{duplicate_packets.join(', ')}" unless duplicate_packets.empty?
global_holds << "duplicate output paths: #{duplicate_outputs.join(', ')}" unless duplicate_outputs.empty?

sections = rows.group_by { |row| row.dig("request", "section_id") }.sort.map do |section_id, section_rows|
  holds = global_holds.dup
  requests = section_rows.sort_by { |row| row.dig("request", "packet_id") }.map do |row|
    request = row.fetch("request")
    holds << row["provider_hold_reason"] unless row["provider_hold_reason"].to_s.empty?
    holds.concat(Array(request["hold_reasons"]))
    holds << "request #{request['packet_id']} is not ready" unless request["status"].to_s == "ready"
    Array(request["attachments"]).each do |attachment|
      attachment_path, attachment_rel = repo_path(attachment.fetch("actual_path"), must_exist: true)
      holds << "attachment hash is stale: #{attachment_rel}" unless Digest::SHA256.file(attachment_path).hexdigest == attachment.fetch("sha256")
    end
    request_row = {
      "path" => row["path"],
      "sha256" => row["sha256"],
      "packet_id" => request["packet_id"],
      "mode" => request["mode"],
      "cut_id" => request.dig("cut_pointer", "cut_id"),
      "cut_type" => request.dig("cut_pointer", "cut_type"),
      "parent_core_cut_id" => request.dig("cut_pointer", "parent_core_cut_id"),
      "production_scope_id" => request["production_scope_id"],
      "image_execution_request" => request.dig("run_execution_selection", "image_execution_request"),
      "image_execution_request_origin" => request.dig("run_execution_selection", "image_execution_request_origin"),
      "image_execution_session_provider" => request.dig("run_execution_selection", "image_execution_session_provider"),
      "image_execution_lane" => request.dig("run_execution_selection", "image_execution_lane"),
      "execution_adapter_id" => request.dig("execution", "execution_adapter_id"),
      "provider" => request.dig("execution", "provider"),
      "auth_lane" => request.dig("execution", "auth_lane"),
      "provider_profile_id" => request.dig("execution", "provider_profile_id"),
      "provider_profile_sha256" => request.dig("execution", "provider_profile_sha256"),
      "provider_capability_snapshot_sha256" => request.dig("execution", "provider_capability_snapshot_sha256"),
      "selected_native_tool" => request.dig("execution", "selected_native_tool"),
      "request_status" => request["status"],
      "prompt_sha256" => request.dig("prompt", "full_prompt_sha256"),
      "attachment_order_sha256" => request["attachment_order_sha256"],
      "expected_output_path" => request.dig("expected_output", "path")
    }
    request_row.delete("parent_core_cut_id") if request_row["parent_core_cut_id"].to_s.empty?
    request_row
  end
  holds = holds.reject { |reason| reason.to_s.empty? }.uniq.sort
  {
    "section_id" => section_id,
    "production_scope_ids" => requests.map { |request| request["production_scope_id"] }.uniq,
    "status" => holds.empty? ? "ready" : "hold",
    "requests" => requests,
    "output_paths" => requests.map { |request| request["expected_output_path"] },
    "hold_reasons" => holds,
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
    "return_recipient" => "creative_development_director"
  }
end

ready_count = sections.count { |section| section["status"] == "ready" }
source_set = rows.map { |row| {"path" => row["path"], "sha256" => row["sha256"]} }.sort_by { |row| row["path"] }
worklist = {
  "schema_version" => "idol_image_generation_section_worklist.v9",
  "artifact_type" => "derived_image_generation_section_worklist",
  "run" => run_rel,
  "source_prompt_packets" => {"path" => source_rel, "sha256" => source_pointer.fetch("sha256")},
  "source_selection" => {"path" => selection_rel, "sha256" => Digest::SHA256.file(selection_path).hexdigest},
  "request_set_sha256" => Digest::SHA256.hexdigest(JSON.generate(source_set)),
  "status" => !sections.empty? && ready_count == sections.length ? "ready" : "hold",
  "summary" => {"section_count" => sections.length, "request_count" => rows.length, "ready_section_count" => ready_count, "hold_section_count" => sections.length - ready_count},
  "sections" => sections,
  "coordinator_contract" => {"single_writer_per_job" => true, "bounded_parallel_disjoint_jobs" => true, "same_output_parallel_write_forbidden" => true, "promotion_authority" => "founder_only_after_cdd_pixel_review"},
  "automation_boundaries" => {"derived_noncanonical" => true, "model_called" => false, "external_mutation_performed" => false, "paid_generation_performed" => false, "approval_granted" => false}
}
serialized = YAML.dump(worklist)
Tempfile.create(["idol-image-worklist", ".yaml"]) { |temp| temp.write(serialized); temp.flush; validate(WORKLIST_SCHEMA, Pathname.new(temp.path), "image worklist") }
output_path, output_rel = repo_path(options[:output] || run_path.join("work/image-generation-requests/section-worklist.yaml").to_s)
abort "output must stay in the owning run" unless output_path.to_s.start_with?(run_prefix)
if options[:write]
  output_path.dirname.mkpath
  output_path.write(serialized)
end
puts JSON.pretty_generate("write" => options[:write], "output" => output_rel, "status" => worklist["status"], "summary" => worklist["summary"])
