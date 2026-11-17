#!/usr/bin/env ruby
# frozen_string_literal: true

require "date"
require "digest"
require "json"
require "open3"
require "optparse"
require "pathname"
require "rbconfig"
require "tempfile"
require "yaml"
require_relative "lib/idol_02a_storyboard_contract"
require_relative "lib/idol_image_execution_lane_contract"
require_relative "lib/idol_reference_role_plan_contract"
require_relative "lib/idol_xai_api_media_profile_contract"

ROOT = Pathname.new(__dir__).join("..").expand_path
PYTHON = ROOT.join("scripts/idol-video-python")
SCHEMA_VALIDATOR = ROOT.join("scripts/validate_json_schema.py")
PACKET_SCHEMA = ROOT.join("schemas/prompt-packets.schema.json")
APPROVAL_SCHEMA = ROOT.join("schemas/image-generation-section-approval.schema.json")
REQUEST_SCHEMA = ROOT.join("schemas/image-generation-request.schema.json")
SOURCE_02B_VALIDATOR = ROOT.join("scripts/validate_02b_imagegen_contract.rb")
XAI_PROFILE_SCHEMA = ROOT.join("schemas/xai-api-media-provider-profiles.schema.json")
LABELS = ["Identity reference rule", "Scene intent", "Visible details", "Action cue", "Avoid"].freeze
PROMPT_PACKET_VERSION = "2.6"
REQUEST_VERSION = "idol_image_generation_request.v12"

class RequestError < StandardError; end

options = {write: false}
OptionParser.new do |parser|
  parser.banner = "usage: ruby scripts/idol_prepare_image_generation_request.rb RUN --source-prompt-packets PATH --packet-id ID [--approval-source PATH] [--output PATH] [--write]"
  parser.on("--source-prompt-packets PATH") { |value| options[:source] = value }
  parser.on("--packet-id ID") { |value| options[:packet_id] = value }
  parser.on("--approval-source PATH") { |value| options[:approval] = value }
  parser.on("--output PATH") { |value| options[:output] = value }
  parser.on("--write") { options[:write] = true }
end.parse!

def load_mapping(path, label)
  value = if path.extname.downcase == ".json"
            JSON.parse(path.read)
          else
            YAML.safe_load(path.read, permitted_classes: [Date, Time], aliases: true)
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
  raise RequestError, "path escapes repository: #{raw}" if relative == ".." || relative.start_with?("../")
  raise RequestError, "required file is missing: #{relative}" if must_exist && !path.file?
  [path, relative]
rescue ArgumentError
  raise RequestError, "path escapes repository: #{raw}"
end

def validate_schema(schema, path, label)
  stdout, stderr, status = Open3.capture3(IdolXaiApiMediaProfileContract::NONSECRET_CHILD_ENV, PYTHON.to_s, SCHEMA_VALIDATOR.to_s, schema.to_s, path.to_s, chdir: ROOT.to_s)
  raise RequestError, "#{label} failed schema validation: #{[stderr, stdout].join(' ').strip}" unless status.success?
end

def validate_source_02b(path, run)
  stdout, stderr, status = Open3.capture3(
    IdolXaiApiMediaProfileContract::NONSECRET_CHILD_ENV,
    RbConfig.ruby,
    SOURCE_02B_VALIDATOR.to_s,
    "--mode", "authoring",
    "--run-root", run.to_s,
    path.to_s,
    chdir: ROOT.to_s
  )
  return if status.success?

  raise RequestError, "source Prompt Packets failed active 02B validation: #{[stderr, stdout].join(' ').strip}"
end

def canonical(value)
  case value
  when Hash
    value.keys.map(&:to_s).sort.each_with_object({}) { |key, result| result[key] = canonical(value[key]) }
  when Array then value.map { |item| canonical(item) }
  else value
  end
end

def value_sha(value)
  Digest::SHA256.hexdigest(JSON.generate(canonical(value)))
end

def verify_attachment!(attachment, run_prefix)
  path, relative = repo_path(attachment["actual_path"], must_exist: true)
  raise RequestError, "attachment must remain in an admitted local repository path" unless path.to_s.start_with?(ROOT.to_s)
  actual = Digest::SHA256.file(path).hexdigest
  raise RequestError, "locked attachment SHA-256 is stale: #{relative}" unless actual == attachment["sha256"].to_s
  raise RequestError, "locked attachment is not pixel-passed: #{relative}" unless attachment["pixel_inspection_status"].to_s == "passed"
  raise RequestError, "attachment must remain locked: #{relative}" unless attachment["locked"] == true
  relative
end

def verify_reference_role_plan!(packet, attachments)
  IdolReferenceRolePlanContract.verify!(
    plan: packet["reference_role_plan"],
    attachments: attachments,
    member_visual_applicability: packet["member_visual_applicability"],
    current_section_id: packet["execution_section_id"],
    root: ROOT,
    label: "#{packet['packet_id']}.reference_role_plan"
  )
rescue IdolReferenceRolePlanContract::ContractError => e
  raise RequestError, e.message
end

begin
  run_arg = ARGV.shift
  raise RequestError, "run path is required" if run_arg.to_s.empty?
  raise RequestError, "unexpected arguments: #{ARGV.join(' ')}" unless ARGV.empty?
  raise RequestError, "--source-prompt-packets is required" if options[:source].to_s.empty?
  raise RequestError, "--packet-id is required" if options[:packet_id].to_s.empty?

  run, run_relative = repo_path(run_arg)
  raise RequestError, "run must stay inside runs/" unless run_relative.start_with?("runs/")
  run_prefix = "#{run}#{File::SEPARATOR}"
  source_path, source_relative = repo_path(options[:source], must_exist: true)
  raise RequestError, "source Prompt Packets must stay in the owning run" unless source_path.to_s.start_with?(run_prefix)
  validate_schema(PACKET_SCHEMA, source_path, "Prompt Packets #{PROMPT_PACKET_VERSION}")
  validate_source_02b(source_path, run)
  source = load_mapping(source_path, "Prompt Packets #{PROMPT_PACKET_VERSION}")
  raise RequestError, "new requests require Prompt Packets #{PROMPT_PACKET_VERSION}" unless source["schema_version"].to_s == PROMPT_PACKET_VERSION
  raise RequestError, "content_id must match run id" unless source["content_id"].to_s == run.basename.to_s
  packet_index = Array(source["prompt_packets"]).index { |row| row.is_a?(Hash) && row["packet_id"].to_s == options[:packet_id] }
  raise RequestError, "packet not found: #{options[:packet_id]}" unless packet_index
  packet = source.fetch("prompt_packets").fetch(packet_index)
  if packet.key?("compiled_prompt_block")
    unless canonical(packet["rendered_five_lines"]) == canonical(packet["compiled_prompt_block"])
      raise RequestError, "rendered_five_lines differs from compiled_prompt_block"
    end
  end
  if packet["mode"].to_s == "official_branch"
    expected_attachments = Array(packet["visual_reference_bindings"]).map do |row|
      {
        "order" => row["order"],
        "role" => row["reference_scope"].to_s == "member_visual" ? "current_title_member_visual" : "governing_scene_or_sequence_reference",
        "binding_id" => row["binding_id"],
        "asset_id" => row["asset_id"],
        "actual_path" => row["actual_path"],
        "sha256" => row["sha256"],
        "pixel_inspection_status" => "passed",
        "locked" => true
      }
    end
    unless canonical(packet["attachments"]) == canonical(expected_attachments)
      raise RequestError, "attachments differ from locked 02A visual_reference_bindings"
    end
  elsif packet.key?("visual_reference_bindings")
    unless canonical(packet["visual_reference_bindings"]) == canonical(packet["attachments"])
      raise RequestError, "visual_reference_bindings must exact-copy attachments"
    end
  end
  prompt = packet.fetch("rendered_five_lines")
  prompt_text = prompt.fetch("full_prompt_text")
  raise RequestError, "prompt must be exactly five labeled lines" unless prompt_text.lines.length == 5 && LABELS.each_with_index.all? { |label, index| prompt_text.lines.fetch(index).start_with?("#{label}:") }
  raise RequestError, "prompt SHA-256 is stale" unless Digest::SHA256.hexdigest(prompt_text) == prompt["full_prompt_sha256"].to_s

  attachments = Array(packet["attachments"])
  raise RequestError, "attachment order must be contiguous from 1" unless attachments.map { |row| row["order"] } == (1..attachments.length).to_a
  member_count = attachments.take_while { |row| row["role"].to_s == "current_title_member_visual" }.length
  if attachments.drop(member_count).any? { |row| row["role"].to_s == "current_title_member_visual" }
    raise RequestError, "current-title Member Visual attachments must precede scene/Sequence references"
  end
  album_key = run.parent.parent.basename.to_s
  title_key = run.parent.basename.to_s
  attachments.each do |row|
    relative = verify_attachment!(row, run_prefix)
    path = ROOT.join(relative)
    admission_error = Idol02AStoryboardContract.visual_source_admission_error(
      path: path,
      root: ROOT,
      run_path: run,
      album_key: album_key,
      title_key: title_key,
      label: "#{packet['packet_id']} attachment #{row['binding_id']}"
    )
    raise RequestError, admission_error if admission_error
    if row["role"].to_s == "current_title_member_visual"
      package_root = ROOT.join("assets", "members", "album-assets", album_key, title_key)
      raise RequestError, "current-title Member Visual is outside the exact title package" unless Idol02AStoryboardContract.inside_real_root?(path, package_root)
    end
  end
  member_attachments = attachments.select { |row| row["role"].to_s == "current_title_member_visual" }
  applicability = packet["member_visual_applicability"].to_s
  if applicability == "meaningfully_visible" && member_attachments.empty?
    raise RequestError, "meaningfully-visible Cut requires at least one current-title Member Visual attachment"
  end
  if %w[visible_but_member_visual_unnecessary not_visible].include?(applicability) && member_attachments.any?
    raise RequestError, "Cut without applicable Member Visual must not attach a current-title Member Visual"
  end
  binding_ids = attachments.map { |row| row["binding_id"].to_s }
  inspected_binding_ids = Array(packet.dig("authoring_inspection_receipt", "inspected_visual_reference_binding_ids")).map(&:to_s)
  raise RequestError, "attachment binding ids differ from the authoring inspection receipt" unless binding_ids == inspected_binding_ids
  member_asset_ids = member_attachments.map { |row| row["asset_id"].to_s }
  identity_asset_ids = Array(packet.dig("five_line_components", "identity_reference_rule", "current_title_visual_bindings")).map(&:to_s)
  raise RequestError, "Member Visual attachments differ from the authored identity bindings" unless member_asset_ids == identity_asset_ids
  reference_role_plan = verify_reference_role_plan!(packet, attachments)

  execution = packet.fetch("execution")
  run_execution_selection = source.fetch("run_execution_selection")
  provider_registration_hold_reason = nil
  begin
    IdolImageExecutionLaneContract.verify_execution_shape!(
      selection: run_execution_selection,
      execution: execution,
      attachment_count: attachments.length
    )
    if %w[codex_imagegen grok_image].include?(execution["execution_adapter_id"].to_s)
      IdolImageExecutionLaneContract.verify_registered_native_profile!(
        root: ROOT,
        selection: run_execution_selection,
        execution: execution,
        attachment_count: attachments.length
      )
    end
  rescue IdolImageExecutionLaneContract::ContractError => e
    provider_registration_hold_reason = e.message
  end
  xai_registration_hold_reason = nil
  if execution["execution_adapter_id"].to_s == "xai_api_media"
    begin
      registration = IdolXaiApiMediaProfileContract.verify!(
        root: ROOT,
        execution: execution,
        attachment_count: attachments.length
      )
      validate_schema(
        XAI_PROFILE_SCHEMA,
        Pathname.new(registration.fetch("profile_path")),
        "xAI API provider profile source"
      )
    rescue IdolXaiApiMediaProfileContract::ContractError, RequestError => e
      xai_registration_hold_reason = e.message
    end
  end
  raise RequestError, "provider/auth/model fallback must be none" unless execution["automatic_fallback"].to_s == "none"
  raise RequestError, "prompt rewrite must be forbidden" unless execution["prompt_rewrite_policy"].to_s == "forbidden"

  expected_output_path, expected_output_relative = repo_path(packet["expected_output_path"])
  raise RequestError, "expected output must stay in the owning run" unless expected_output_path.to_s.start_with?(run_prefix)
  raise RequestError, "packet execution output path differs" unless execution["expected_output_path"].to_s == expected_output_relative

  hold_reasons = []
  hold_reasons << provider_registration_hold_reason if provider_registration_hold_reason
  hold_reasons << xai_registration_hold_reason if xai_registration_hold_reason
  hold_reasons << "prompt packet is not approved" unless source["status"].to_s == "approved" && packet["status"].to_s == "approved"
  approval_ref = nil
  approval = nil
  if options[:approval]
    approval_path, approval_relative = repo_path(options[:approval], must_exist: true)
    raise RequestError, "approval must stay in the owning run" unless approval_path.to_s.start_with?(run_prefix)
    validate_schema(APPROVAL_SCHEMA, approval_path, "image generation approval")
    approval = load_mapping(approval_path, "image generation approval")
    approval_ref = {"path" => approval_relative, "sha256" => Digest::SHA256.file(approval_path).hexdigest, "schema_version" => approval["schema_version"]}
    raise RequestError, "approval content/section/scope mismatch" unless approval["content_id"].to_s == source["content_id"].to_s && approval["section_id"].to_s == packet["execution_section_id"].to_s && approval["production_scope_id"].to_s == packet["production_scope_id"].to_s
    raise RequestError, "approval source hash mismatch" unless approval["source_prompt_packets_sha256"].to_s == Digest::SHA256.file(source_path).hexdigest
    %w[execution_adapter_id provider auth_lane provider_profile_id provider_profile_sha256 provider_capability_snapshot_sha256].each do |key|
      raise RequestError, "approval #{key} mismatch" unless approval[key].to_s == execution[key].to_s
    end
    unless canonical(approval["run_execution_selection"]) == canonical(run_execution_selection)
      raise RequestError, "approval run execution selection differs from exact Prompt Packets 2.6 bytes"
    end
    raise RequestError, "approval fallback is not none" unless approval["automatic_fallback"].to_s == "none"
    row = Array(approval["packets"]).find { |item| item["packet_id"].to_s == packet["packet_id"].to_s }
    raise RequestError, "approval does not include packet" unless row
    expected_hashes = attachments.map { |item| item["sha256"].to_s }
    expected_paths = attachments.map { |item| item["actual_path"].to_s }
    unless row["mode"].to_s == packet["mode"].to_s && row["cut_id"].to_s == packet.dig("cut_pointer", "cut_id").to_s && row["prompt_sha256"].to_s == prompt["full_prompt_sha256"].to_s && Array(row["approved_attachment_sha256s"]).map(&:to_s) == expected_hashes && Array(row["approved_attachment_paths"]).map(&:to_s) == expected_paths && row["expected_output_path"].to_s == expected_output_relative
      raise RequestError, "approval packet bytes/order/output mismatch"
    end
  else
    hold_reasons << "exact Founder generation approval is missing"
  end

  ready = hold_reasons.empty?
  authority_id = approval && approval["founder_generation_authority_id"]
  request = {
    "schema_version" => REQUEST_VERSION,
    "artifact_type" => "image_generation_request",
    "content_id" => source["content_id"],
    "run" => run_relative,
    "prompt_profile" => "idol_one_cut_one_image.v1",
    "mode" => packet["mode"],
    "packet_id" => packet["packet_id"],
    "production_scope_id" => packet["production_scope_id"],
    "cut_pointer" => packet["cut_pointer"],
    "section_id" => packet["execution_section_id"],
    "section_cohort_id" => packet["section_cohort_id"],
    "source_prompt_packet" => {"path" => source_relative, "sha256" => Digest::SHA256.file(source_path).hexdigest, "schema_version" => PROMPT_PACKET_VERSION, "json_pointer" => "/prompt_packets/#{packet_index}", "value_sha256" => value_sha(packet)},
    "run_execution_selection" => canonical(run_execution_selection),
    "prompt" => prompt,
    "attachments" => attachments,
    "reference_role_plan" => reference_role_plan,
    "attachment_order_sha256" => value_sha(attachments),
    "execution" => execution.merge("founder_generation_authority_id" => authority_id),
    "quality_contract" => {"quality" => "highest_available", "render_quality_terms" => ["4K", "high quality", "high detail"], "output_count" => 1, "full_size_pixel_review_required" => true},
    "expected_output" => {"path" => expected_output_relative, "sha256_required" => true, "canonical_ingest_required" => true, "motion_handoff" => "only_after_passed_full_size_pixels"},
    "integrity_contract" => {"prompt_rewrite_policy" => "forbidden", "attachment_omission_policy" => "locked_attachment_missing_hold_no_prose_substitution", "provider_auth_model_fallback" => "none", "one_request_one_output" => true},
    "approval" => {"founder_generation_authority_id" => authority_id, "external_execution_approved" => approval ? approval["external_execution_approved"] : false, "paid_generation_approved" => approval ? approval["paid_generation_approved"] : false, "approval_source" => approval_ref},
    "status" => ready ? "ready" : "hold",
    "hold_reasons" => hold_reasons
  }.reject { |_key, value| value.nil? }

  serialized = YAML.dump(request)
  Tempfile.create(["idol-image-generation-request", ".yaml"]) do |temp|
    temp.write(serialized)
    temp.flush
    validate_schema(REQUEST_SCHEMA, Pathname.new(temp.path), "image generation request")
  end
  output_path, output_relative = repo_path(options[:output] || run.join("work/image-generation-requests/#{packet['packet_id']}.yaml").to_s)
  raise RequestError, "request output must stay in the owning run" unless output_path.to_s.start_with?(run_prefix)
  if options[:write]
    output_path.dirname.mkpath
    output_path.write(serialized)
  end
  puts JSON.pretty_generate("write" => options[:write], "output" => output_relative, "status" => request["status"], "packet_id" => packet["packet_id"], "execution_adapter_id" => execution["execution_adapter_id"], "selected_native_tool" => execution["selected_native_tool"], "hold_reasons" => hold_reasons)
rescue RequestError, KeyError => e
  warn "image generation request failed: #{e.message}"
  exit 1
end
