#!/usr/bin/env ruby
# Pinned legacy reader only. Do not use for new generation requests.
# frozen_string_literal: true

require "date"
require "digest"
require "json"
require "open3"
require "optparse"
require "pathname"
require "tempfile"
require "yaml"
require_relative "lib/idol_02a_storyboard_contract"

ROOT = Pathname.new(__dir__).join("..").expand_path
REQUEST_SCHEMA = ROOT.join("schemas", "image-generation-request.schema.json")
APPROVAL_SCHEMA = ROOT.join("schemas", "image-generation-section-approval.schema.json")
CONTEXT_PACK_SCHEMA = ROOT.join("schemas", "harness-context-pack.schema.json")
SCHEMA_VALIDATOR = ROOT.join("scripts", "validate_json_schema.py")
PYTHON = ROOT.join("scripts", "idol-video-python")
ADAPTERS = %w[
  openai_api
  codex_builtin_imagegen
  grok_image
  section_image_capable_worker
].freeze
RETIRED_NO_MIC_PATTERN = %r{(?:^|[/_-])no[-_]mic(?:[-_. /]|$)}i.freeze

options = {
  run: nil,
  source_02b: nil,
  packet_id: nil,
  adapter: "codex_builtin_imagegen",
  section_id: nil,
  context_pack: nil,
  planning_source: nil,
  output: nil,
  founder_requested_execution: false,
  paid_generation_approved: false,
  approval_source: nil,
  write: false
}

OptionParser.new do |opts|
  opts.banner = "usage: ruby scripts/idol_prepare_image_generation_request.rb RUN --packet-id PKT_ID --section-id SXX --context-pack PATH --planning-source PATH [options]"
  opts.on("--run PATH") { |value| options[:run] = value }
  opts.on("--source-02b PATH") { |value| options[:source_02b] = value }
  opts.on("--packet-id ID") { |value| options[:packet_id] = value }
  opts.on("--adapter NAME", ADAPTERS) { |value| options[:adapter] = value }
  opts.on("--section-id ID") { |value| options[:section_id] = value }
  opts.on("--context-pack PATH") { |value| options[:context_pack] = value }
  opts.on("--planning-source PATH") { |value| options[:planning_source] = value }
  opts.on("--output PATH") { |value| options[:output] = value }
  opts.on("--founder-requested-execution") { options[:founder_requested_execution] = true }
  opts.on("--paid-generation-approved") { options[:paid_generation_approved] = true }
  opts.on("--approval-source PATH") { |value| options[:approval_source] = value }
  opts.on("--write") { options[:write] = true }
end.parse!

class RequestError < StandardError; end

def load_mapping(path, label)
  raise RequestError, "missing #{label}: #{path}" unless path.file?
  value = if path.extname.downcase == ".json"
            JSON.parse(path.read)
          else
            YAML.safe_load(path.read, permitted_classes: [Date, Time], permitted_symbols: [], aliases: true)
          end
  raise RequestError, "#{label} must be an object" unless value.is_a?(Hash)
  value
rescue JSON::ParserError, Psych::Exception => e
  raise RequestError, "cannot parse #{label}: #{e.message}"
end

def repo_path(raw, must_exist: false)
  path = Pathname.new(raw.to_s)
  path = ROOT.join(path) unless path.absolute?
  path = path.expand_path.cleanpath
  relative = path.relative_path_from(ROOT).to_s
  raise RequestError, "path escapes the IDOL repository: #{raw}" if relative == ".." || relative.start_with?("../")
  raise RequestError, "required file is missing: #{relative}" if must_exist && !path.file?
  [path, relative]
rescue ArgumentError
  raise RequestError, "path escapes the IDOL repository: #{raw}"
end

def file_ref(raw, label)
  path, relative = repo_path(raw, must_exist: true)
  document = load_mapping(path, label)
  [
    path,
    {
      "path" => relative,
      "sha256" => Digest::SHA256.file(path).hexdigest,
      "schema_version" => document["schema_version"].to_s
    },
    document
  ]
end

def canonical_value(value)
  case value
  when Hash
    value.keys.map(&:to_s).sort.each_with_object({}) do |key, result|
      result[key] = canonical_value(value[key])
    end
  when Array
    value.map { |item| canonical_value(item) }
  else
    value
  end
end

def value_sha256(value)
  Digest::SHA256.hexdigest(JSON.generate(canonical_value(value)))
end

def validate_schema(schema, document_path, label)
  stdout, stderr, status = Open3.capture3(
    PYTHON.to_s,
    SCHEMA_VALIDATOR.to_s,
    schema.to_s,
    document_path.to_s,
    chdir: ROOT.to_s
  )
  return if status.success?
  raise RequestError, "#{label} failed schema validation: #{[stderr, stdout].join(' ').strip}"
end

def validate_reference_file(row, path_field, label)
  path, relative = repo_path(row[path_field], must_exist: true)
  actual = Digest::SHA256.file(path).hexdigest
  raise RequestError, "#{label} hash is stale" unless row["sha256"].to_s == actual
  if relative.match?(%r{(^|/)face-only-reference(?:-|\.|/)}i)
    raise RequestError, "#{label} uses a prohibited face-only path"
  end
  if relative.match?(RETIRED_NO_MIC_PATTERN)
    raise RequestError, "#{label} uses a retired no-mic/no_mic path"
  end
  [path, relative]
end

def approval_packet_row(approval, packet_id)
  Array(approval["packets"]).find { |row| row.is_a?(Hash) && row["packet_id"].to_s == packet_id }
end

begin
  run_arg = options[:run] || ARGV.shift
  raise RequestError, "run path is required" if run_arg.to_s.empty?
  raise RequestError, "unexpected arguments: #{ARGV.join(' ')}" unless ARGV.empty?
  raise RequestError, "--packet-id is required" if options[:packet_id].to_s.empty?
  raise RequestError, "--section-id is required" if options[:section_id].to_s.empty?
  raise RequestError, "--context-pack is required" if options[:context_pack].to_s.empty?
  raise RequestError, "--planning-source is required" if options[:planning_source].to_s.empty?

  run, run_relative = repo_path(run_arg)
  raise RequestError, "run must stay inside runs/" unless run_relative.start_with?("runs/")
  run_prefix = "#{run}#{File::SEPARATOR}"
  content_id = run.basename.to_s

  source_02b_path = if options[:source_02b]
                      repo_path(options[:source_02b], must_exist: true).first
                    else
                      run.join("02B-prompt-packets.yaml")
                    end
  raise RequestError, "source 02B must stay inside the owning run" unless source_02b_path.to_s.start_with?(run_prefix)
  source_02b = load_mapping(source_02b_path, "02B prompt packets")
  validate_schema(ROOT.join("schemas", "prompt-packets.schema.json"), source_02b_path, "02B prompt packets")
  raise RequestError, "source 02B schema must be 2.2" unless source_02b["schema_version"].to_s == "2.2"
  raise RequestError, "02B content_id must match the run" unless source_02b["content_id"].to_s == content_id
  source_02b_sha = Digest::SHA256.file(source_02b_path).hexdigest

  packets = Array(source_02b["prompt_packets"])
  packet_index = packets.index { |row| row.is_a?(Hash) && row["packet_id"].to_s == options[:packet_id] }
  raise RequestError, "packet not found: #{options[:packet_id]}" unless packet_index
  packet = packets.fetch(packet_index)
  execution_section_id = packet["execution_section_id"].to_s
  raise RequestError, "--section-id must equal #{execution_section_id}" unless options[:section_id].to_s == execution_section_id
  raise RequestError, "packet must own exactly one section" unless Array(packet["source_sections"]) == [execution_section_id]

  source_02a_raw = source_02b.dig("input_files", "master_storyboard").to_s
  source_02a_path, source_02a_relative = repo_path(source_02a_raw, must_exist: true)
  raise RequestError, "source 02A must stay inside the owning run" unless source_02a_path.to_s.start_with?(run_prefix)
  source_02a_sha = Digest::SHA256.file(source_02a_path).hexdigest
  source_02a = load_mapping(source_02a_path, "source 02A")
  raise RequestError, "source 02A schema must be #{Idol02AStoryboardContract::ACTIVE_SCHEMA_VERSION}" unless source_02a["schema_version"].to_s == Idol02AStoryboardContract::ACTIVE_SCHEMA_VERSION
  packet_shard = Array(source_02b["section_shards"]).find do |shard|
    shard.is_a?(Hash) && shard["section_id"].to_s == execution_section_id
  end
  raise RequestError, "02B has no owning section shard for #{execution_section_id}" unless packet_shard
  if packet_shard["local_lineage"].is_a?(Hash)
    lineage_errors = Idol02AStoryboardContract.prompt_section_lineage_errors(
      source_02a,
      source_02b,
      packet_shard
    )
    unless lineage_errors.empty?
      raise RequestError, "02B local 02A lineage is stale: #{lineage_errors.join('; ')}"
    end
  elsif source_02b.dig("input_files", "master_storyboard_sha256").to_s != source_02a_sha
    raise RequestError, "02B requires local lineage after the 02A whole-artifact baseline changed"
  end

  context_pack_path, context_pack_ref, context_pack = file_ref(options[:context_pack], "section context pack")
  planning_source_path, planning_source_ref, _planning_source = file_ref(options[:planning_source], "planning source")
  raise RequestError, "context pack must stay inside the owning run" unless context_pack_path.to_s.start_with?(run_prefix)
  raise RequestError, "planning source must stay inside the owning run" unless planning_source_path.to_s.start_with?(run_prefix)
  validate_schema(CONTEXT_PACK_SCHEMA, context_pack_path, "section context pack")
  raise RequestError, "planning source must be the exact active 02A storyboard" unless planning_source_path == source_02a_path
  unless context_pack["schema_version"].to_s == "idol-harness-context-pack.v6" &&
         context_pack.dig("task", "context_profile").to_s == "image_prompt_section" &&
         context_pack["content_id"].to_s == content_id &&
         Array(context_pack.dig("task", "active_section_ids")).map(&:to_s) == [execution_section_id] &&
         context_pack.dig("task", "active_core_cut_id").to_s == packet["core_cut_id"].to_s &&
         context_pack.dig("task", "active_branch_cut_id").to_s == packet["branch_cut_id"].to_s
    raise RequestError, "context pack must exact-cover this content, section, Core Cut, and Branch Cut"
  end
  unless context_pack.dig("active_unit", "branch_neighborhood", "context_value_sha256").to_s ==
         packet.dig("same_section_context", "context_value_sha256").to_s
    raise RequestError, "context pack and packet same-section context hashes differ"
  end

  prompt_block = packet.fetch("compiled_prompt_block")
  prompt_text = prompt_block["full_prompt_text"].to_s
  prompt_sha = Digest::SHA256.hexdigest(prompt_text)
  raise RequestError, "compiled prompt hash is stale" unless prompt_block["full_prompt_sha256"].to_s == prompt_sha

  member_visual_lock = packet.fetch("member_visual_lock")
  package_album_key = member_visual_lock["package_album_key"].to_s
  package_title_key = member_visual_lock["package_title_key"].to_s
  member_visual_inputs = Array(member_visual_lock["selected_assets"]).map do |row|
    path, relative = validate_reference_file(row, "actual_path", "#{packet['packet_id']} member visual #{row['asset_id']}")
    admission_error = Idol02AStoryboardContract.visual_source_admission_error(
      path: path,
      root: ROOT,
      run_path: run,
      album_key: package_album_key,
      title_key: package_title_key,
      label: "#{packet['packet_id']} member visual #{row['asset_id']}"
    )
    raise RequestError, admission_error if admission_error
    package_root = ROOT.join("assets", "members", "album-assets", package_album_key, package_title_key)
    unless Idol02AStoryboardContract.inside_real_root?(path, package_root)
      raise RequestError, "#{packet['packet_id']} member visual #{row['asset_id']} is outside the current-title package"
    end
    {
      "asset_id" => row["asset_id"],
      "path" => relative,
      "sha256" => row["sha256"],
      "package_album_key" => row["package_album_key"],
      "package_title_key" => row["package_title_key"],
      "order" => row["order"],
      "visual_control_policy" => "appearance_hair_makeup_wardrobe_material_silhouette_and_body_continuity_only"
    }
  end

  scene_bindings = Array(packet["visual_reference_bindings"]).select { |row| row["reference_scope"].to_s == "scene_visual" }
  scene_reference_inputs = scene_bindings.map do |row|
    path, relative = validate_reference_file(row, "actual_path", "#{packet['packet_id']} scene reference #{row['binding_id']}")
    admission_error = Idol02AStoryboardContract.visual_source_admission_error(
      path: path,
      root: ROOT,
      run_path: run,
      album_key: package_album_key,
      title_key: package_title_key,
      label: "#{packet['packet_id']} scene reference #{row['binding_id']}"
    )
    raise RequestError, admission_error if admission_error
    {
      "binding_id" => row["binding_id"],
      "asset_id" => row["asset_id"],
      "path" => relative,
      "sha256" => row["sha256"],
      "source_kind" => row["source_kind"],
      "role" => row["role"],
      "reference_class" => row["reference_class"],
      "order" => row["order"],
      "preserve" => row["preserve"],
      "discard" => row["discard"]
    }.compact
  end
  attachment_order = Array(packet["visual_reference_bindings"]).map do |row|
    _path, relative = validate_reference_file(row, "actual_path", "#{packet['packet_id']} attachment #{row['binding_id']}")
    {
      "input_slot" => row["order"],
      "reference_scope" => row["reference_scope"],
      "binding_id" => row["binding_id"],
      "asset_id" => row["asset_id"],
      "path" => relative,
      "sha256" => row["sha256"],
      "source_kind" => row["source_kind"],
      "role" => row["role"]
    }.compact
  end
  unless attachment_order.map { |row| row["input_slot"] } == (1..attachment_order.length).to_a
    raise RequestError, "combined attachment order must be contiguous from 1"
  end

  expected_output_raw = packet.dig("export_contract", "expected_output_path").to_s
  expected_output_path, expected_output_relative = repo_path(expected_output_raw)
  raise RequestError, "expected output must stay inside the owning run" unless expected_output_path.to_s.start_with?(run_prefix)

  hold_reasons = []
  hold_reasons << "canonical 02B and packet must be approved" unless source_02b["status"] == "approved" && packet["status"] == "approved"
  hold_reasons << "exact current-job external execution approval is missing" unless options[:founder_requested_execution]
  hold_reasons << "exact current-job paid-generation approval is missing" unless options[:paid_generation_approved]
  hold_reasons << "run-owned approval source is missing" if options[:approval_source].to_s.empty?

  approval_path = nil
  approval_sha = nil
  if options[:approval_source]
    approval_path, approval_relative = repo_path(options[:approval_source], must_exist: true)
    raise RequestError, "approval source must stay inside the owning run" unless approval_path.to_s.start_with?(run_prefix)
    validate_schema(APPROVAL_SCHEMA, approval_path, "image generation section approval")
    approval = load_mapping(approval_path, "image generation section approval")
    approval_sha = Digest::SHA256.file(approval_path).hexdigest
    raise RequestError, "approval content mismatch" unless approval["content_id"].to_s == content_id
    raise RequestError, "approval section mismatch" unless approval["section_id"].to_s == execution_section_id
    raise RequestError, "approval adapter mismatch" unless approval["adapter"].to_s == options[:adapter]
    raise RequestError, "approval source 02B hash mismatch" unless approval["source_02b_sha256"].to_s == source_02b_sha
    raise RequestError, "approval must authorize external and paid execution" unless approval["external_execution_approved"] == true && approval["paid_generation_approved"] == true
    approval_row = approval_packet_row(approval, packet["packet_id"].to_s)
    raise RequestError, "approval does not include this packet" unless approval_row
    raise RequestError, "approval prompt hash mismatch" unless approval_row["prompt_sha256"].to_s == prompt_sha
    expected_member_hashes = member_visual_inputs.map { |row| row["sha256"].to_s }
    expected_scene_hashes = scene_reference_inputs.map { |row| row["sha256"].to_s }
    unless Array(approval_row["approved_member_visual_sha256s"]).map(&:to_s) == expected_member_hashes
      raise RequestError, "approval member-visual order/hash mismatch"
    end
    unless Array(approval_row["approved_scene_reference_sha256s"]).map(&:to_s) == expected_scene_hashes
      raise RequestError, "approval scene-reference order/hash mismatch"
    end
    expected_attachment_ids = attachment_order.map { |row| row["binding_id"].to_s }
    expected_attachment_hashes = attachment_order.map { |row| row["sha256"].to_s }
    unless Array(approval_row["approved_attachment_binding_ids"]).map(&:to_s) == expected_attachment_ids &&
           Array(approval_row["approved_attachment_sha256s"]).map(&:to_s) == expected_attachment_hashes
      raise RequestError, "approval combined attachment order/hash mismatch"
    end
    unless approval_row["expected_output_path"].to_s == expected_output_relative
      raise RequestError, "approval expected output path mismatch"
    end

    attachment_rows = Array(packet["visual_reference_bindings"])
    if attachment_rows.any? { |row| row["attachment_permission"].to_s == "planning_and_prompt_only" }
      hold_reasons << "one or more selected references are planning-only and cannot be attached"
    end
  end

  ready = hold_reasons.empty?
  status = ready ? "ready" : "hold"
  request = {
    "schema_version" => "idol_image_generation_request.v8",
    "content_id" => content_id,
    "run" => run_relative,
    "adapter" => options[:adapter],
    "source_02a" => {
      "path" => source_02a_relative,
      "sha256" => source_02a_sha,
      "schema_version" => Idol02AStoryboardContract::ACTIVE_SCHEMA_VERSION
    },
    "source_02b" => {
      "path" => source_02b_path.relative_path_from(ROOT).to_s,
      "sha256" => source_02b_sha,
      "schema_version" => "2.2"
    },
    "packet_id" => packet["packet_id"],
    "core_cut_id" => packet["core_cut_id"],
    "branch_cut_id" => packet["branch_cut_id"],
    "section_ids" => [execution_section_id],
    "execution_section_id" => execution_section_id,
    "execution_section_assignment" => {
      "mode" => "one_request_one_packet_one_section",
      "section_id" => execution_section_id,
      "packet_ownership" => "disjoint_section_worker",
      "cross_section_rule" => "never_load_or_merge_another_section_inside_this_request"
    },
    "prompt" => {
      "identity_reference_rule" => prompt_block["identity_reference_rule"],
      "scene_intent" => prompt_block["scene_intent"],
      "visible_details" => prompt_block["visible_details"],
      "action_cue" => prompt_block["action_cue"],
      "avoid" => prompt_block["avoid"],
      "full_prompt_text" => prompt_text,
      "full_prompt_sha256" => prompt_sha,
      "label_order" => prompt_block["label_order"]
    },
    "member_visual_inputs" => member_visual_inputs,
    "member_visual_inputs_sha256" => value_sha256(member_visual_inputs),
    "scene_reference_inputs" => scene_reference_inputs,
    "scene_reference_inputs_sha256" => value_sha256(scene_reference_inputs),
    "attachment_order" => attachment_order,
    "attachment_order_sha256" => value_sha256(attachment_order),
    "execution_context" => {
      "context_policy" => "current_branch_plus_parent_core_immediate_branch_siblings_and_immediate_previous_and_next_core_cuts_in_same_section_only",
      "section_id" => execution_section_id,
      "current_core_cut_id" => packet["core_cut_id"],
      "current_branch_cut_id" => packet["branch_cut_id"],
      "previous_branch_cut_id" => packet.dig("same_section_context", "previous_branch_cut", "branch_cut_id"),
      "next_branch_cut_id" => packet.dig("same_section_context", "next_branch_cut", "branch_cut_id"),
      "previous_core_cut_id" => packet.dig("same_section_context", "previous_core_cut", "core_cut_id"),
      "next_core_cut_id" => packet.dig("same_section_context", "next_core_cut", "core_cut_id"),
      "same_section_context_sha256" => packet.dig("same_section_context", "context_value_sha256"),
      "context_pack" => context_pack_ref,
      "planning_source" => planning_source_ref,
      "cross_section_continuity_owner" => "coordinator_review_not_packet_request"
    },
    "quality_contract" => {
      "model" => "gpt-image-2",
      "quality" => "highest_available",
      "dimension_policy" => "maximum_supported_dimensions_for_locked_aspect_ratio",
      "required_prompt_terms" => ["4K", "high quality", "high detail"],
      "pixel_inspection_required" => true
    },
    "integrity_contract" => {
      "packet_value_sha256" => value_sha256(packet),
      "prompt_sha256" => prompt_sha,
      "member_visual_order_sha256" => value_sha256(member_visual_inputs),
      "scene_reference_order_sha256" => value_sha256(scene_reference_inputs),
      "combined_attachment_order_sha256" => value_sha256(attachment_order),
      "expected_output_path_sha256" => Digest::SHA256.hexdigest(expected_output_relative),
      "cross_album_check" => "passed_current_title_package_only",
      "face_only_lane_check" => "passed_no_separate_face_input"
    },
    "expected_output_path" => expected_output_relative,
    "adapter_contract" => {
      "unsupported_reference_behavior" => "hold_never_drop_or_replace_with_prose",
      "prompt_rewrite_policy" => "forbidden",
      "one_request_rule" => "one_packet_per_generation_call"
    },
    "section_execution_contract" => {
      "owner_profile" => "luna_max_section_image_motion_lineage",
      "scope" => "one_declared_section",
      "parallelism_rule" => "bounded_parallel_disjoint_packets_only",
      "post_generation_gate" => "byte_hash_pixel_inspection_and_generated_branch_cut_review",
      "motion_handoff_rule" => "03v_starts_only_from_passed_pixels"
    },
    "approval" => {
      "founder_external_execution_approval" => options[:founder_requested_execution],
      "founder_paid_generation_approval" => options[:paid_generation_approved],
      "approval_source_path" => approval_path ? approval_relative : nil,
      "approval_source_sha256" => approval_sha
    },
    "status" => status,
    "hold_reasons" => hold_reasons
  }

  output = if options[:output]
             repo_path(options[:output]).first
           else
             run.join("work", "image_generation_requests", "sections", execution_section_id, "#{packet['packet_id']}-#{options[:adapter]}.yaml")
           end
  raise RequestError, "request output must stay inside the owning run" unless output.to_s.start_with?(run_prefix)

  yaml = YAML.dump(request)
  Tempfile.create(["idol-image-generation-request-", ".yaml"]) do |temp|
    temp.write(yaml)
    temp.flush
    validate_schema(REQUEST_SCHEMA, Pathname.new(temp.path), "image generation request")
  end
  if options[:write]
    output.dirname.mkpath
    output.write(yaml)
  end

  puts JSON.pretty_generate(
    "write" => options[:write],
    "output" => output.relative_path_from(ROOT).to_s,
    "status" => status,
    "adapter" => options[:adapter],
    "packet_id" => packet["packet_id"],
    "prompt_sha256" => prompt_sha,
    "member_visual_input_count" => member_visual_inputs.length,
    "member_visual_inputs_sha256" => request["member_visual_inputs_sha256"],
    "scene_reference_input_count" => scene_reference_inputs.length,
    "scene_reference_inputs_sha256" => request["scene_reference_inputs_sha256"],
    "attachment_order_sha256" => request["attachment_order_sha256"],
    "hold_reasons" => hold_reasons
  )
rescue RequestError, KeyError => e
  warn "image generation request failed: #{e.message}"
  exit 1
end
