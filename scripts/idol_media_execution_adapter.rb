#!/usr/bin/env ruby
# frozen_string_literal: true

require "date"
require "digest"
require "json"
require "open3"
require "optparse"
require "pathname"
require "yaml"
require_relative "lib/idol_image_execution_lane_contract"
require_relative "lib/idol_grok_video_execution_package"
require_relative "lib/idol_xai_api_media_profile_contract"

ROOT = Pathname.new(__dir__).join("..").expand_path
PYTHON = ROOT.join("scripts/idol-video-python")
VALIDATOR = ROOT.join("scripts/validate_json_schema.py")
IMAGE_SCHEMA = ROOT.join("schemas/image-generation-request.schema.json")
XAI_PROFILE_SCHEMA = ROOT.join("schemas/xai-api-media-provider-profiles.schema.json")
VIDEO_SCHEMA = ROOT.join("schemas/video-prompt-manifest.schema.json")
VIDEO_VALIDATOR = ROOT.join("scripts/validate_video_prompt_manifest.rb")

class AdapterError < StandardError; end

command = ARGV.shift
options = {dry_run: false, write_package: false}
OptionParser.new do |parser|
  parser.banner = "usage: ruby scripts/idol_media_execution_adapter.rb image REQUEST --dry-run\n       ruby scripts/idol_media_execution_adapter.rb video MANIFEST --cue-id ID --dry-run [--package-root PATH --write-package]"
  parser.on("--cue-id ID") { |value| options[:cue_id] = value }
  parser.on("--package-root PATH", "Derived Grok operator package parent; run execution-ready root or /private/tmp only.") { |value| options[:package_root] = value }
  parser.on("--write-package", "Exact-copy prompt and selected inputs only; no provider call.") { options[:write_package] = true }
  parser.on("--dry-run") { options[:dry_run] = true }
end.parse!

def repo_path(raw, must_exist: false)
  path = Pathname.new(raw.to_s)
  path = ROOT.join(path) unless path.absolute?
  path = path.expand_path.cleanpath
  relative = path.relative_path_from(ROOT).to_s
  raise AdapterError, "path escapes repository: #{raw}" if relative == ".." || relative.start_with?("../")
  raise AdapterError, "required file is missing: #{relative}" if must_exist && !path.file?
  [path, relative]
rescue ArgumentError
  raise AdapterError, "path escapes repository: #{raw}"
end

def load_mapping(path)
  value = if path.extname.downcase == ".json"
            JSON.parse(path.read)
          else
            YAML.safe_load(path.read, permitted_classes: [Date, Time], aliases: true)
          end
  raise AdapterError, "#{path} must contain an object" unless value.is_a?(Hash)
  value
end

def validate_schema(schema, path, label)
  stdout, stderr, status = Open3.capture3(IdolXaiApiMediaProfileContract::NONSECRET_CHILD_ENV, PYTHON.to_s, VALIDATOR.to_s, schema.to_s, path.to_s, chdir: ROOT.to_s)
  raise AdapterError, "#{label} failed schema validation: #{[stderr, stdout].join(' ').strip}" unless status.success?
end

def image_plan(request)
  raise AdapterError, "only ready image requests may be projected" unless request["status"].to_s == "ready"
  execution = request.fetch("execution")
  attachments = Array(request["attachments"])
  selection = request.fetch("run_execution_selection")
  expected_tool = attachments.empty? ? "image_gen" : "image_edit"
  begin
    IdolImageExecutionLaneContract.verify_execution_shape!(
      selection: selection,
      execution: execution,
      attachment_count: attachments.length
    )
    if %w[codex_imagegen grok_image].include?(execution["execution_adapter_id"].to_s)
      IdolImageExecutionLaneContract.verify_registered_native_profile!(
        root: ROOT,
        selection: selection,
        execution: execution,
        attachment_count: attachments.length
      )
    end
  rescue IdolImageExecutionLaneContract::ContractError => e
    raise AdapterError, e.message
  end
  case execution["execution_adapter_id"].to_s
  when "codex_imagegen"
    raise AdapterError, "Codex session-native lane must use the ImageGen tool" unless execution["selected_native_tool"].to_s == "imagegen"
  when "openai_api_gpt_image_2"
    raise AdapterError, "OpenAI lane is locked to gpt-image-2" unless execution["provider_model_or_tool"].to_s == "gpt-image-2" && execution["selected_native_tool"].nil?
  when "grok_image"
    raise AdapterError, "Grok attachment count requires #{expected_tool}" unless execution["selected_native_tool"].to_s == expected_tool
  when "xai_api_media"
    raise AdapterError, "xAI API requires exact Founder generation authority" if execution["founder_generation_authority_id"].to_s.empty?
    begin
      registration = IdolXaiApiMediaProfileContract.verify!(
        root: ROOT,
        execution: execution,
        attachment_count: attachments.length
      )
    rescue IdolXaiApiMediaProfileContract::ContractError => e
      raise AdapterError, e.message
    end
    validate_schema(
      XAI_PROFILE_SCHEMA,
      Pathname.new(registration.fetch("profile_path")),
      "xAI API provider profile source"
    )
  else
    raise AdapterError, "unsupported image adapter"
  end
  raise AdapterError, "adapter fallback must be none" unless execution["automatic_fallback"].to_s == "none"
  raise AdapterError, "adapter may not rewrite prompt bytes" unless execution["prompt_rewrite_policy"].to_s == "forbidden"
  {
    "schema_version" => "idol_media_execution_dry_run.v1",
    "media_type" => "image",
    "external_call_performed" => false,
    "dry_run_only" => true,
    "packet_id" => request["packet_id"],
    "mode" => request["mode"],
    "cut_id" => request.dig("cut_pointer", "cut_id"),
    "execution_adapter_id" => execution["execution_adapter_id"],
    "provider" => execution["provider"],
    "provider_model_or_tool" => execution["provider_model_or_tool"],
    "selected_native_tool" => execution["selected_native_tool"],
    "auth_lane" => execution["auth_lane"],
    "provider_profile_id" => execution["provider_profile_id"],
    "provider_profile_sha256" => execution["provider_profile_sha256"],
    "provider_capability_snapshot_sha256" => execution["provider_capability_snapshot_sha256"],
    "run_execution_selection" => selection,
    "prompt_source" => "rendered_five_lines_exact_bytes",
    "prompt_text" => request.dig("prompt", "full_prompt_text"),
    "prompt_sha256" => request.dig("prompt", "full_prompt_sha256"),
    "ordered_attachments" => attachments.map { |row| {"order" => row["order"], "actual_path" => row["actual_path"], "sha256" => row["sha256"], "role" => row["role"]} },
    "expected_output_path" => request.dig("expected_output", "path"),
    "output_count" => 1,
    "prompt_rewrite_policy" => "forbidden",
    "provider_auth_model_fallback" => "none"
  }
end

def video_plan(manifest, manifest_path, cue_id)
  IdolGrokVideoExecutionPackage.plan!(
    root: ROOT,
    manifest_path: manifest_path,
    manifest: manifest,
    cue_id: cue_id
  )
rescue IdolGrokVideoExecutionPackage::ContractError => e
  raise AdapterError, e.message
end

begin
  raise AdapterError, "command must be image or video" unless %w[image video].include?(command)
  raise AdapterError, "--dry-run is mandatory; this adapter does not execute or call an API" unless options[:dry_run]
  raise AdapterError, "--write-package is video-only" if options[:write_package] && command != "video"
  raise AdapterError, "--write-package requires --package-root" if options[:write_package] && options[:package_root].to_s.empty?
  raise AdapterError, "--package-root requires --write-package" if options[:package_root] && !options[:write_package]
  input = ARGV.shift
  raise AdapterError, "input path is required" if input.to_s.empty?
  raise AdapterError, "unexpected arguments: #{ARGV.join(' ')}" unless ARGV.empty?
  path, = repo_path(input, must_exist: true)
  schema = command == "image" ? IMAGE_SCHEMA : VIDEO_SCHEMA
  validate_schema(schema, path, "#{command} execution source")
  if command == "video"
    stdout, stderr, status = Open3.capture3(IdolXaiApiMediaProfileContract::NONSECRET_CHILD_ENV, RbConfig.ruby, VIDEO_VALIDATOR.to_s, path.to_s, chdir: ROOT.to_s)
    raise AdapterError, "video execution source failed active validation: #{[stderr, stdout].join(' ').strip}" unless status.success?
  end
  document = load_mapping(path)
  plan = command == "image" ? image_plan(document) : video_plan(document, path, options[:cue_id])
  if options[:write_package]
    begin
      materialized = IdolGrokVideoExecutionPackage.materialize!(
        root: ROOT,
        plan: plan,
        package_root: options[:package_root]
      )
      plan = plan.merge("materialized_package" => materialized)
    rescue IdolGrokVideoExecutionPackage::ContractError => e
      raise AdapterError, e.message
    end
  end
  puts JSON.pretty_generate(plan)
rescue AdapterError, KeyError => e
  warn "media execution adapter failed: #{e.message}"
  exit 1
end
