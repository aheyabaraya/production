#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "optparse"
require "pathname"
require "tempfile"
require "yaml"
require_relative "lib/idol_run_layout"
require_relative "lib/idol_image_execution_lane_contract"
require_relative "lib/idol_xai_api_media_profile_contract"

ROOT = Pathname.new(__dir__).join("..").expand_path
PYTHON = ROOT.join("scripts/idol-video-python")
VALIDATOR = ROOT.join("scripts/validate_json_schema.py")
REQUEST_SCHEMA = ROOT.join("schemas/image-generation-request.schema.json")
SELECTION_SCHEMA = ROOT.join("schemas/image-generation-request-selection.schema.json")
XAI_PROFILE_SCHEMA = ROOT.join("schemas/xai-api-media-provider-profiles.schema.json")

options = {requests: [], write: false}
OptionParser.new do |parser|
  parser.banner = "Usage: ruby scripts/idol_image_generation_request_selection.rb RUN_ROOT --request REQUEST.yaml [--request ...] [options]"
  parser.on("--request PATH", "Exact active request path; repeat for each packet.") { |value| options[:requests] << value }
  parser.on("--output PATH", "Selection output. Defaults to RUN/work/image_generation_requests/active-selection.yaml.") { |value| options[:output] = value }
  parser.on("--write", "Write the selection.") { options[:write] = true }
end.parse!

abort "RUN_ROOT is required" unless ARGV.length == 1
abort "at least one --request is required" if options[:requests].empty?

def inside_repo(raw)
  path = Pathname.new(raw)
  path = ROOT.join(path) unless path.absolute?
  path = path.expand_path
  relative = path.relative_path_from(ROOT).to_s
  abort "path escapes repository root: #{raw}" if relative == ".." || relative.start_with?("../")
  [path, relative]
rescue ArgumentError
  abort "path escapes repository root: #{raw}"
end

def load_yaml(path, label)
  value = YAML.safe_load(path.read, permitted_classes: [], aliases: true)
  abort "#{label} must be a mapping" unless value.is_a?(Hash)
  value
rescue Psych::Exception => e
  abort "cannot parse #{label}: #{e.message}"
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
  abort "#{label} failed schema validation: #{[stderr, stdout].join(' ').strip}" unless status.success?
end

run_path, run_rel = inside_repo(ARGV.fetch(0))
layout_errors = IdolRunLayout.validate(run_path, repo_root: ROOT)
abort layout_errors.join("; ") unless layout_errors.empty?
source_02b = run_path.join("02B-prompt-packets.yaml")
abort "current 02B is missing: #{source_02b.relative_path_from(ROOT)}" unless source_02b.file?
source_02b_rel = source_02b.relative_path_from(ROOT).to_s
source_02b_sha = Digest::SHA256.file(source_02b).hexdigest

rows = options[:requests].map do |raw|
  path, relative = inside_repo(raw)
  abort "request must stay inside the owning run: #{relative}" unless relative.start_with?("#{run_rel}/")
  abort "request is missing: #{relative}" unless path.file?
  validate_schema(REQUEST_SCHEMA, path, "request #{relative}")
  request = load_yaml(path, "request #{relative}")
  abort "request belongs to another run: #{relative}" unless request["run"].to_s == run_rel
  abort "request is not exact ready: #{relative}" unless request["status"].to_s == "ready" && Array(request["hold_reasons"]).empty?
  pointer = request["source_prompt_packet"] || {}
  unless pointer["path"].to_s == source_02b_rel && pointer["sha256"].to_s == source_02b_sha
    abort "request is not bound to current 02B bytes: #{relative}"
  end
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
      validate_schema(
        XAI_PROFILE_SCHEMA,
        Pathname.new(registration.fetch("profile_path")),
        "xAI API provider profile source"
      )
    end
  rescue IdolImageExecutionLaneContract::ContractError, IdolXaiApiMediaProfileContract::ContractError => e
    abort "provider-specific request cannot enter active selection: #{e.message}"
  end
  execution_selection = request.fetch("run_execution_selection")
  {
    "path" => relative,
    "sha256" => Digest::SHA256.file(path).hexdigest,
    "section_id" => request["section_id"].to_s,
    "packet_id" => request["packet_id"].to_s,
    "mode" => request["mode"].to_s,
    "cut_id" => request.dig("cut_pointer", "cut_id").to_s,
    "cut_type" => request.dig("cut_pointer", "cut_type").to_s,
    "image_execution_request" => execution_selection["image_execution_request"].to_s,
    "image_execution_request_origin" => execution_selection["image_execution_request_origin"].to_s,
    "image_execution_session_provider" => execution_selection["image_execution_session_provider"].to_s,
    "image_execution_lane" => execution_selection["image_execution_lane"].to_s,
    "execution_adapter_id" => request.dig("execution", "execution_adapter_id").to_s,
    "provider" => request.dig("execution", "provider").to_s,
    "auth_lane" => request.dig("execution", "auth_lane").to_s,
    "provider_profile_id" => request.dig("execution", "provider_profile_id").to_s,
    "provider_profile_sha256" => request.dig("execution", "provider_profile_sha256").to_s,
    "provider_capability_snapshot_sha256" => request.dig("execution", "provider_capability_snapshot_sha256").to_s,
    "expected_output_path" => request.dig("expected_output", "path").to_s
  }
end

%w[path packet_id expected_output_path].each do |field|
  duplicates = rows.group_by { |row| row[field] }.select { |_value, grouped| grouped.length > 1 }.keys
  abort "selection has duplicate #{field}: #{duplicates.join(', ')}" unless duplicates.empty?
end

selection = {
  "schema_version" => "idol_image_generation_request_selection.v3",
  "artifact_type" => "active_image_generation_request_selection",
  "run" => run_rel,
  "source_02b" => {"path" => source_02b_rel, "sha256" => source_02b_sha},
  "status" => "active",
  "selection_policy" => "exact_paths_and_hashes_only_no_directory_inference",
  "requests" => rows.sort_by { |row| [row["section_id"], row["packet_id"], row["execution_adapter_id"]] }
}

yaml = YAML.dump(selection)
Tempfile.create(["idol-image-request-selection", ".yaml"]) do |temp|
  temp.write(yaml)
  temp.flush
  validate_schema(SELECTION_SCHEMA, Pathname.new(temp.path), "request selection")
end

output_path, output_rel = inside_repo(options[:output] || run_path.join("work/image_generation_requests/active-selection.yaml").to_s)
abort "selection output must stay inside the owning run" unless output_rel.start_with?("#{run_rel}/")
if options[:write]
  output_path.dirname.mkpath
  output_path.write(yaml)
end

puts JSON.pretty_generate(
  "write" => options[:write],
  "output" => output_rel,
  "request_count" => rows.length,
  "section_ids" => rows.map { |row| row["section_id"] }.uniq
)
