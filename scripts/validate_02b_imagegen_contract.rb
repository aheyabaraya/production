#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "optparse"
require "pathname"
require "yaml"
require_relative "lib/idol_02a_storyboard_contract"
require_relative "lib/idol_image_execution_lane_contract"
require_relative "lib/idol_reference_role_plan_contract"
require_relative "lib/idol_xai_api_media_profile_contract"

ROOT = Pathname.new(__dir__).join("..").expand_path
PYTHON = ROOT.join("scripts", "idol-video-python")
SCHEMA_VALIDATOR = ROOT.join("scripts", "validate_json_schema.py")
PROMPT_SCHEMA = ROOT.join("schemas", "prompt-packets.schema.json")
XAI_PROFILE_SCHEMA = ROOT.join("schemas", "xai-api-media-provider-profiles.schema.json")
OPENAI_IMAGE_MODEL = "gpt-image-2"
PROMPT_LABELS = [
  "Identity reference rule",
  "Scene intent",
  "Visible details",
  "Action cue",
  "Avoid"
].freeze
AUTHORED_COMPONENT_ORDER = [
  "identity_reference_rule",
  "scene_intent",
  "visible_details.background_and_space",
  "visible_details.still_camera_and_composition.camera_height",
  "visible_details.still_camera_and_composition.shot_scale_distance",
  "visible_details.still_camera_and_composition.direction_angle",
  "visible_details.still_camera_and_composition.depth_design",
  "visible_details.still_camera_and_composition.subject_placement",
  "visible_details.still_camera_and_composition.crop_negative_space",
  "visible_details.still_camera_and_composition.lens_feel",
  "visible_details.lighting_color_material",
  "action_cue.subject_state_or_pose",
  "action_cue.visible_action_or_hold",
  "action_cue.object_environment_response",
  "avoid"
].freeze
CREATIVE_FILL_POLICY = "human_or_assigned_model_inspects_source_truth_and_authors_every_creative_component_scripts_may_only_validate_hash_and_serialize_fixed_labels"
TEMPORAL_CAMERA_PATTERN = /\b(?:camera\s+(?:push(?:es)?|pull(?:s)?|pan(?:s)?|tilt(?:s)?|track(?:s)?|orbit(?:s)?|doll(?:y|ies)|crane(?:s)?|zoom(?:s)?)|push[- ]?in|pull[- ]?out|dolly[- ]?(?:in|out)|camera\s+speed|motion\s+envelope)\b/i.freeze
METADATA_PATTERN = /\b(?:schema_version|compiler_profile|artifact_sha256|json_pointer|expected_output_path|PKT_BC[0-9A-Z_]+|BC[0-9A-Z_]+|VRB_[A-Z0-9_]+)\b/i.freeze
RETIRED_NO_MIC_PATTERN = %r{(?:^|[/_-])no[-_]mic(?:[-_. /]|$)}i.freeze

options = {
  mode: "authoring",
  export_index: nil,
  run_root: nil,
  self_test_labels: false,
  max_errors: 20
}

OptionParser.new do |opts|
  opts.banner = "usage: ruby scripts/validate_02b_imagegen_contract.rb [--mode authoring|preflight] [--export-index PATH] [--run-root PATH] [--self-test-labels] PATH_TO_02B"
  opts.on("--mode MODE") { |value| options[:mode] = value }
  opts.on("--export-index PATH") { |value| options[:export_index] = value }
  opts.on("--run-root PATH") { |value| options[:run_root] = Pathname.new(value).expand_path }
  opts.on("--self-test-labels") { options[:self_test_labels] = true }
  opts.on("--max-errors COUNT", Integer) do |value|
    raise OptionParser::InvalidArgument, "--max-errors must be zero or greater" if value.negative?
    options[:max_errors] = value
  end
end.parse!

abort "mode must be authoring or preflight" unless %w[authoring preflight].include?(options[:mode])

def load_mapping(path)
  value = if path.extname.downcase == ".json"
            JSON.parse(path.read)
          else
            YAML.safe_load(path.read, permitted_classes: [], permitted_symbols: [], aliases: true)
          end
  raise "document must be an object" unless value.is_a?(Hash)
  value
end

def resolve_repo_path(raw)
  path = Pathname.new(raw.to_s)
  path = ROOT.join(path) unless path.absolute?
  path.expand_path.cleanpath
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

def schema_errors(schema, document)
  stdout, stderr, status = Open3.capture3(
    IdolXaiApiMediaProfileContract::NONSECRET_CHILD_ENV,
    PYTHON.to_s,
    SCHEMA_VALIDATOR.to_s,
    schema.to_s,
    document.to_s,
    chdir: ROOT.to_s
  )
  status.success? ? [] : ["JSON Schema validation failed: #{[stderr, stdout].join(' ').strip}"]
end

def prompt_lines(prompt_text)
  prompt_text.to_s.lines.map(&:chomp)
end

def official_branch_packet?(packet)
  packet["mode"].to_s == "official_branch"
end

def transport_attachments_from_02a_bindings(bindings)
  Array(bindings).map do |row|
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
end

def generic_component_blueprint(packet)
  components = packet["five_line_components"].to_h
  identity = components["identity_reference_rule"].to_h
  scene = components["scene_intent"].to_h
  {
    "identity_reference_rule" => identity["visible_identity"],
    "scene_intent" => scene["core_slot_or_core_component"],
    "visible_details" => components["visible_details"],
    "action_cue" => components["action_cue"],
    "avoid" => components["avoid"]
  }
end

def serialized_blueprint_fields(blueprint)
  blueprint = blueprint.to_h
  visible = blueprint["visible_details"].to_h
  camera = visible["still_camera_and_composition"].to_h
  action = blueprint["action_cue"].to_h
  visible_details = [
    "Background and space — #{visible['background_and_space']}",
    "Still camera and composition — camera height: #{camera['camera_height']}; shot scale/distance: #{camera['shot_scale_distance']}; direction/angle: #{camera['direction_angle']}; depth: #{camera['depth_design']}; subject placement: #{camera['subject_placement']}; crop/negative space: #{camera['crop_negative_space']}; lens feel: #{camera['lens_feel']}",
    "Lighting, color, and material — #{visible['lighting_color_material']}",
    visible["render_quality"].to_s
  ].join("; ")
  action_parts = [
    "Subject state or pose — #{action['subject_state_or_pose']}",
    "Visible action or hold — #{action['visible_action_or_hold']}"
  ]
  response = action["object_environment_response"]
  action_parts << "Object/environment response — #{response}" unless response.nil?
  {
    "identity_reference_rule" => blueprint["identity_reference_rule"].to_s,
    "scene_intent" => blueprint["scene_intent"].to_s,
    "visible_details" => visible_details,
    "action_cue" => action_parts.join("; "),
    "avoid" => blueprint["avoid"].to_s
  }
end

def validate_prompt(packet, errors)
  packet_id = packet["packet_id"].to_s
  block = packet["compiled_prompt_block"] || {}
  if packet.key?("compiled_prompt_block") && packet.key?("rendered_five_lines")
    unless canonical_value(block) == canonical_value(packet["rendered_five_lines"])
      errors << "#{packet_id}: rendered_five_lines must exact-copy compiled_prompt_block"
    end
  end
  blueprint = packet.dig("direct_prompt_revision", "prompt_blueprint")
  if official_branch_packet?(packet) || (blueprint.is_a?(Hash) && !blueprint.empty?)
    serialized_blueprint_fields(blueprint).each do |field, expected_value|
      errors << "#{packet_id}: compiled #{field} differs from the authored structured component serialization" unless block[field].to_s == expected_value
    end
  elsif packet["five_line_components"].is_a?(Hash)
    serialized_blueprint_fields(generic_component_blueprint(packet)).each do |field, expected_value|
      errors << "#{packet_id}: compiled #{field} differs from the authored structured component serialization" unless block[field].to_s == expected_value
    end
  end
  text = block["full_prompt_text"].to_s
  expected = [
    "Identity reference rule: #{block['identity_reference_rule']}",
    "Scene intent: #{block['scene_intent']}",
    "Visible details: #{block['visible_details']}",
    "Action cue: #{block['action_cue']}",
    "Avoid: #{block['avoid']}"
  ]
  errors << "#{packet_id}: full_prompt_text must contain exactly the fixed five lines in order" unless prompt_lines(text) == expected
  errors << "#{packet_id}: full_prompt_sha256 is stale" unless block["full_prompt_sha256"].to_s == Digest::SHA256.hexdigest(text)
  errors << "#{packet_id}: label_order is not canonical" unless Array(block["label_order"]) == PROMPT_LABELS
  %w[4K high\ quality high\ detail].each do |escaped|
    term = escaped.tr("\\", "")
    errors << "#{packet_id}: Visible details is missing literal #{term}" unless block["visible_details"].to_s.include?(term)
  end
  errors << "#{packet_id}: prompt contains temporal camera motion reserved for 03V" if text.match?(TEMPORAL_CAMERA_PATTERN)
  errors << "#{packet_id}: prompt leaks internal metadata" if text.match?(METADATA_PATTERN)
end

def validate_reference_file(packet_id, row, errors)
  path = resolve_repo_path(row["actual_path"])
  unless path.file?
    errors << "#{packet_id}: reference file is missing: #{row['actual_path']}"
    return
  end
  actual = Digest::SHA256.file(path).hexdigest
  errors << "#{packet_id}: reference hash is stale for #{row['binding_id']}" unless actual == row["sha256"].to_s
  if path.to_s.match?(%r{(^|/)face-only-reference(?:-|\.|/)}i)
    errors << "#{packet_id}: face-only asset entered the active visual-reference route"
  end
  if path.to_s.match?(RETIRED_NO_MIC_PATTERN)
    errors << "#{packet_id}: retired no-mic/no_mic path entered the active visual-reference route"
  end
end

def validate_member_visual(packet, errors)
  packet_id = packet["packet_id"].to_s
  identity_rule = packet.dig("compiled_prompt_block", "identity_reference_rule").to_s
  errors << "#{packet_id}: separate face-reference wording is prohibited" if identity_rule.match?(/\bface[- ]?(?:only|reference|ref)\b/i)
  member_attachments = Array(packet["attachments"]).select { |row| row["role"].to_s == "current_title_member_visual" }
  applicability = packet["member_visual_applicability"].to_s
  if applicability == "meaningfully_visible" && member_attachments.empty?
    errors << "#{packet_id}: required current-title member visual is missing"
  end
  if %w[visible_but_member_visual_unnecessary not_visible].include?(applicability) && member_attachments.any?
    errors << "#{packet_id}: no-member Cut still carries a member visual"
  end
  return unless official_branch_packet?(packet)

  lock = packet["member_visual_lock"] || {}
  branch_cut = packet["branch_cut_lock"] || {}
  member_input = branch_cut["member_visual_compile_input"].to_h
  policy = lock["member_visual_reference_policy"].to_s
  input_policy = member_input["member_visual_reference_policy"].to_s
  visible_members = Array(branch_cut["visible_member_focus"]).map(&:to_s)
  input_selected_ids = Array(member_input["selected_album_member_visual_asset_ids"]).map(&:to_s)
  selected = Array(lock["selected_assets"])
  selected_ids = selected.map { |row| row["asset_id"].to_s }
  expected_applicability = Idol02AStoryboardContract.member_visual_applicability(member_input, visible_members)
  lock_applicability = lock["member_visual_applicability"].to_s
  lock_applicability = expected_applicability if lock_applicability.empty?
  bindings = Array(packet["visual_reference_bindings"])
  member_bindings = bindings.select { |row| row["reference_scope"].to_s == "member_visual" }

  errors.concat(
    Idol02AStoryboardContract.member_visual_contract_errors(
      packet_id,
      member_input,
      visible_members,
      input_selected_ids
    )
  )
  unless policy == input_policy
    errors << "#{packet_id}: member visual policy differs from the Branch Cut"
  end
  unless lock_applicability == expected_applicability
    errors << "#{packet_id}: member visual applicability differs from the Branch Cut"
  end
  if policy == "required"
    errors << "#{packet_id}: required member visual has no selected asset" if selected.empty?
  elsif policy == "prohibited"
    errors << "#{packet_id}: prohibited member visual still carries assets" unless selected.empty? && member_bindings.empty?
  else
    errors << "#{packet_id}: invalid member visual policy"
  end

  binding_ids = member_bindings.map { |row| row["asset_id"].to_s }
  errors << "#{packet_id}: member visual selected assets differ from the Branch Cut" unless selected_ids == input_selected_ids
  errors << "#{packet_id}: member visual selected assets and bindings differ" unless selected_ids == binding_ids

  album_key = lock["package_album_key"].to_s
  title_key = lock["package_title_key"].to_s
  selected.each do |row|
    path = resolve_repo_path(row["actual_path"])
    expected = ROOT.join("assets", "members", "album-assets", album_key, title_key).to_s
    errors << "#{packet_id}: member visual is outside current-title package" unless path.to_s.start_with?("#{expected}/")
    if path.file?
      errors << "#{packet_id}: member visual hash is stale" unless Digest::SHA256.file(path).hexdigest == row["sha256"].to_s
    else
      errors << "#{packet_id}: member visual is missing: #{row['actual_path']}"
    end
  end
  bindings.select { |row| row["reference_class"].to_s == "current_title_world_or_background" }.each do |row|
    path = resolve_repo_path(row["actual_path"])
    expected = ROOT.join("assets", "members", "album-assets", album_key, title_key).to_s
    errors << "#{packet_id}: current-title world/background is outside the active album package" unless path.to_s.start_with?("#{expected}/")
    errors << "#{packet_id}: current-title world/background owner drifted" unless row["source_owner"].to_s == "front_planning_album_visual_asset"
  end

end

def validate_packet_integrity(packet, errors)
  packet_id = packet["packet_id"].to_s
  trace = packet["local_trace"] || {}
  branch_cut = packet["branch_cut_lock"] || {}
  revision = packet["direct_prompt_revision"] || {}
  context = packet["same_section_context"] || {}
  bindings = Array(packet["visual_reference_bindings"])
  member_assets = Array(packet.dig("member_visual_lock", "selected_assets"))

  errors << "#{packet_id}: compiler version must be #{Idol02AStoryboardContract::ACTIVE_COMPILER_VERSION}" unless trace["compiler_version"].to_s == Idol02AStoryboardContract::ACTIVE_COMPILER_VERSION
  errors << "#{packet_id}: compiler profile is inactive" unless trace["compiler_profile"].to_s == Idol02AStoryboardContract::ACTIVE_COMPILER_PROFILE
  unless official_branch_packet?(packet)
    unless canonical_value(bindings) == canonical_value(packet["attachments"])
      errors << "#{packet_id}: visual_reference_bindings must exact-copy attachments"
    end
    receipt = packet["authoring_inspection_receipt"].to_h
    expected_binding_ids = Array(packet["attachments"]).map { |row| row["binding_id"].to_s }
    unless Array(receipt["inspected_visual_reference_binding_ids"]).map(&:to_s) == expected_binding_ids
      errors << "#{packet_id}: authoring inspection must exact-copy every visual binding id in order"
    end
    orders = bindings.map { |row| row["order"] }
    errors << "#{packet_id}: visual reference order must be contiguous from 1" unless orders == (1..bindings.length).to_a
    bindings.each { |row| validate_reference_file(packet_id, row, errors) }
    if packet.key?("reference_role_plan")
      begin
        IdolReferenceRolePlanContract.verify!(
          plan: packet["reference_role_plan"],
          attachments: Array(packet["attachments"]),
          member_visual_applicability: packet["member_visual_applicability"],
          current_section_id: packet["execution_section_id"],
          root: ROOT,
          label: "#{packet_id}.reference_role_plan"
        )
      rescue IdolReferenceRolePlanContract::ContractError => e
        errors << e.message
      end
    end
    return
  end

  branch_cut_hash = value_sha256(branch_cut)
  errors << "#{packet_id}: source Branch Cut trace is stale" unless trace["source_branch_cut_value_sha256"].to_s == branch_cut_hash
  unless revision["source_02a_branch_cut_lock_sha256"].to_s == branch_cut_hash
    errors << "#{packet_id}: direct revision is not bound to the Branch Cut"
  end
  storyline = branch_cut["storyline_alignment_binding"].to_h
  storyline_hash = value_sha256(storyline)
  unless packet["storyline_alignment_lock"] == storyline
    errors << "#{packet_id}: storyline alignment lock differs from the Branch Cut"
  end
  unless trace["source_storyline_alignment_binding_sha256"].to_s == storyline_hash &&
         revision.dig("storyline_authoring_binding", "source_branch_storyline_binding_sha256").to_s == storyline_hash
    errors << "#{packet_id}: storyline authoring lineage is stale"
  end
  errors << "#{packet_id}: direct prompt revision hash is stale" unless trace["direct_prompt_revision_sha256"].to_s == value_sha256(revision)
  receipt = revision["authoring_inspection_receipt"].to_h
  errors << "#{packet_id}: authoring inspection owner differs from the revision owner" unless receipt["inspection_owner"].to_s == revision["authoring_owner"].to_s
  errors << "#{packet_id}: authoring inspection Branch-Cut hash is stale" unless receipt["source_02a_branch_cut_sha256"].to_s == branch_cut_hash
  errors << "#{packet_id}: authoring inspection storyline hash is stale" unless receipt["source_storyline_alignment_binding_sha256"].to_s == storyline_hash
  unless Array(receipt["inspected_storyline_levels"]).map(&:to_s) == %w[whole_film section planning_cut 02a_branch_expansion]
    errors << "#{packet_id}: authoring inspection must exact-cover all storyline levels in order"
  end
  expected_binding_ids = bindings.map { |row| row["binding_id"].to_s }
  unless Array(receipt["inspected_visual_reference_binding_ids"]).map(&:to_s) == expected_binding_ids
    errors << "#{packet_id}: authoring inspection must exact-copy every visual binding id in order"
  end
  expected_current_title_asset_ids = bindings.each_with_object([]) do |row, ids|
    ids << row["asset_id"].to_s if row["reference_class"].to_s.start_with?("current_title_")
  end
  unless Array(receipt["inspected_current_title_asset_ids"]).map(&:to_s) == expected_current_title_asset_ids
    errors << "#{packet_id}: authoring inspection must exact-copy current-title asset ids in binding order"
  end
  unless Array(receipt["authored_component_order"]).map(&:to_s) == AUTHORED_COMPONENT_ORDER
    errors << "#{packet_id}: authored component order is inactive"
  end
  unless receipt["creative_fill_policy"].to_s == CREATIVE_FILL_POLICY
    errors << "#{packet_id}: authoring inspection does not forbid script-authored creative fill"
  end
  errors << "#{packet_id}: member visual input hash is stale" unless trace["member_visual_inputs_sha256"].to_s == value_sha256(member_assets)
  errors << "#{packet_id}: visual reference binding hash is stale" unless trace["visual_reference_bindings_sha256"].to_s == value_sha256(bindings)
  errors << "#{packet_id}: same-section context hash is stale" unless trace["same_section_context_sha256"].to_s == context["context_value_sha256"].to_s
  errors << "#{packet_id}: current Core Cut context mismatch" unless context["current_core_cut_id"].to_s == packet["core_cut_id"].to_s
  errors << "#{packet_id}: current Branch Cut context mismatch" unless context["current_branch_cut_id"].to_s == packet["branch_cut_id"].to_s
  errors << "#{packet_id}: execution section context mismatch" unless context["section_id"].to_s == packet["execution_section_id"].to_s
  errors << "#{packet_id}: Branch Cut packet id mismatch" unless branch_cut["packet_id"].to_s == packet_id
  errors << "#{packet_id}: Branch Cut id mismatch" unless branch_cut["branch_cut_id"].to_s == packet["branch_cut_id"].to_s
  errors << "#{packet_id}: temporal camera route leaked into the 02A Branch Cut" if branch_cut.key?("camera_route_spec")
  errors << "#{packet_id}: legacy identity compile input leaked into the 02A Branch Cut" if branch_cut.key?("identity_compile_input")
  errors << "#{packet_id}: legacy 02A prompt blueprint leaked into the Branch Cut" if branch_cut.key?("prompt_blueprint")
  expected_attachments = transport_attachments_from_02a_bindings(bindings)
  unless canonical_value(packet["attachments"]) == canonical_value(expected_attachments)
    errors << "#{packet_id}: attachments must remain the transport projection of locked 02A visual_reference_bindings"
  end

  orders = bindings.map { |row| row["order"] }
  errors << "#{packet_id}: visual reference order must be contiguous from 1" unless orders == (1..bindings.length).to_a
  bindings.each { |row| validate_reference_file(packet_id, row, errors) }
  if packet.key?("reference_role_plan")
    begin
      IdolReferenceRolePlanContract.verify!(
        plan: packet["reference_role_plan"],
        attachments: Array(packet["attachments"]),
        member_visual_applicability: packet["member_visual_applicability"],
        current_section_id: packet["execution_section_id"],
        root: ROOT,
        label: "#{packet_id}.reference_role_plan"
      )
    rescue IdolReferenceRolePlanContract::ContractError => e
      errors << e.message
    end
  end
end

def validate_section_coverage(document, errors)
  packets = Array(document["prompt_packets"])
  packet_ids = packets.map { |row| row["packet_id"].to_s }
  errors << "prompt packet ids must be unique" unless packet_ids.uniq.length == packet_ids.length
  Array(document["section_shards"]).each do |shard|
    expected = Array(shard["packet_ids"]).map(&:to_s)
    actual = packets.select { |row| row["execution_section_id"].to_s == shard["section_id"].to_s }.map { |row| row["packet_id"].to_s }
    errors << "#{shard['shard_id']}: packet coverage/order mismatch" unless expected == actual
  end
end

def exported_attachment_rows(packet)
  Array(packet["attachments"]).map do |row|
    {
      "input_slot" => row["order"],
      "role" => row["role"],
      "binding_id" => row["binding_id"],
      "asset_id" => row["asset_id"],
      "path" => row["actual_path"],
      "sha256" => row["sha256"],
      "pixel_inspection_status" => row["pixel_inspection_status"],
      "locked" => row["locked"]
    }
  end
end

def validate_export_index(index_path, source_02b_path, document, errors)
  unless index_path&.file?
    errors << "preflight export index is missing"
    return
  end
  index = load_mapping(index_path)
  errors << "preflight export index must use idol_02b_export_index.v4" unless index["schema_version"].to_s == "idol_02b_export_index.v4"
  errors << "preflight export index must remain local_export_only" unless index["status"].to_s == "local_export_only"
  source_02b = index["source_02b"].to_h
  errors << "preflight export index source path differs from 02B" unless resolve_repo_path(source_02b["path"]) == source_02b_path.expand_path
  source_path = resolve_repo_path(source_02b["path"])
  if source_path.file?
    errors << "preflight export index source SHA-256 is stale" unless Digest::SHA256.file(source_path).hexdigest == source_02b["sha256"].to_s
  else
    errors << "preflight export index source 02B is missing"
  end
  requests = Array(index["requests"])
  packet_ids = Array(document["prompt_packets"]).map { |row| row["packet_id"].to_s }
  exported_ids = requests.map { |row| row["packet_id"].to_s }
  errors << "preflight export index must exact-cover packet ids" unless exported_ids == packet_ids
  packet_by_id = Array(document["prompt_packets"]).to_h { |row| [row["packet_id"].to_s, row] }
  requests.each do |row|
    packet_id = row["packet_id"].to_s
    packet = packet_by_id[packet_id]
    next errors << "#{packet_id}: export index names an unknown packet" unless packet
    errors << "#{packet_id}: export index Core Cut differs from 02B" unless row["core_cut_id"].to_s == packet["core_cut_id"].to_s
    errors << "#{packet_id}: export index Branch Cut differs from 02B" unless row["branch_cut_id"].to_s == packet["branch_cut_id"].to_s

    manifest_path = resolve_repo_path(row["manifest_path"])
    prompt_path = resolve_repo_path(row["prompt_path"])
    unless manifest_path.file?
      errors << "#{packet_id}: exported manifest is missing"
      next
    end
    errors << "#{packet_id}: exported manifest SHA-256 is stale" unless Digest::SHA256.file(manifest_path).hexdigest == row["manifest_sha256"].to_s
    unless prompt_path.file?
      errors << "#{packet_id}: exported prompt is missing"
      next
    end
    prompt_text = prompt_path.read
    errors << "#{packet_id}: exported prompt SHA-256 is stale" unless Digest::SHA256.hexdigest(prompt_text) == row["prompt_sha256"].to_s
    errors << "#{packet_id}: exported prompt differs from canonical 02B" unless prompt_text == packet.dig("compiled_prompt_block", "full_prompt_text").to_s

    manifest = load_mapping(manifest_path)
    errors << "#{packet_id}: exported manifest version is inactive" unless manifest["schema_version"].to_s == "idol_02b_packet_export_manifest.v4"
    errors << "#{packet_id}: exported manifest Core Cut differs from 02B" unless manifest["core_cut_id"].to_s == packet["core_cut_id"].to_s
    errors << "#{packet_id}: exported manifest Branch Cut differs from 02B" unless manifest["branch_cut_id"].to_s == packet["branch_cut_id"].to_s
    errors << "#{packet_id}: exported manifest packet hash is stale" unless manifest["packet_value_sha256"].to_s == value_sha256(packet)
    expected_attachments = exported_attachment_rows(packet)
    errors << "#{packet_id}: exported combined attachment order differs from 02B" unless canonical_value(manifest["attachment_order"]) == canonical_value(expected_attachments)
    errors << "#{packet_id}: exported attachment order hash is stale" unless manifest["attachment_order_sha256"].to_s == value_sha256(expected_attachments)
    adapter = packet.dig("execution", "execution_adapter_id").to_s
    expected_model = packet.dig("execution", "provider_model_or_tool").to_s
    if adapter == "openai_api_gpt_image_2"
      errors << "#{packet_id}: exported model must be #{OPENAI_IMAGE_MODEL}" unless expected_model == OPENAI_IMAGE_MODEL && manifest.dig("quality_contract", "model").to_s == OPENAI_IMAGE_MODEL
    elsif %w[grok_image codex_imagegen xai_api_media].include?(adapter)
      errors << "#{packet_id}: native execution is missing provider_model_or_tool" if expected_model.empty?
      errors << "#{packet_id}: exported model must exact-copy native provider_model_or_tool" unless manifest.dig("quality_contract", "model").to_s == expected_model
    else
      errors << "#{packet_id}: execution adapter is not active"
    end
    errors << "#{packet_id}: local export must not imply paid generation" unless manifest.dig("execution_boundary", "paid_generation_approved") == false
  end
end

if options[:self_test_labels]
  sample = {
    "compiled_prompt_block" => {
      "identity_reference_rule" => "No member visual; this Branch Cut contains only the object.",
      "scene_intent" => "A cracked transmitter sits alone in the corridor.",
      "visible_details" => "Low side view, deep corridor layers, 4K, high quality, high detail.",
      "action_cue" => "The indicator changes from red to white.",
      "avoid" => "No person, no text, no extra device."
    },
    "packet_id" => "PKT_BC00_SELFTEST"
  }
  block = sample["compiled_prompt_block"]
  block["full_prompt_text"] = [
    "Identity reference rule: #{block['identity_reference_rule']}",
    "Scene intent: #{block['scene_intent']}",
    "Visible details: #{block['visible_details']}",
    "Action cue: #{block['action_cue']}",
    "Avoid: #{block['avoid']}"
  ].join("\n")
  block["full_prompt_sha256"] = Digest::SHA256.hexdigest(block["full_prompt_text"])
  block["label_order"] = PROMPT_LABELS
  errors = []
  validate_prompt(sample, errors)
  if errors.empty?
    puts "OK: fixed five-line 02B prompt labels"
    exit 0
  end
  errors.each { |error| warn("ERROR: #{error}") }
  exit 1
end

path_arg = ARGV.shift
abort "PATH_TO_02B is required" if path_arg.to_s.empty? || !ARGV.empty?
path = Pathname.new(path_arg).expand_path
errors = schema_errors(PROMPT_SCHEMA, path)

begin
  document = load_mapping(path)
rescue StandardError => e
  warn "ERROR: cannot load #{path}: #{e.message}"
  exit 1
end

errors << "schema_version must be 2.6" unless document["schema_version"].to_s == "2.6"
run_execution_selection = document["run_execution_selection"]
packets = Array(document["prompt_packets"])
packets.each do |packet|
  execution = packet["execution"].to_h
  begin
    IdolImageExecutionLaneContract.verify_execution_shape!(
      selection: run_execution_selection,
      execution: execution,
      attachment_count: Array(packet["attachments"]).length
    )
    if %w[codex_imagegen grok_image].include?(execution["execution_adapter_id"].to_s)
      IdolImageExecutionLaneContract.verify_registered_native_profile!(
        root: ROOT,
        selection: run_execution_selection,
        execution: execution,
        attachment_count: Array(packet["attachments"]).length
      )
    end
  rescue IdolImageExecutionLaneContract::ContractError => e
    errors << "#{packet['packet_id']}: #{e.message}"
  end
  case execution["execution_adapter_id"].to_s
  when "codex_imagegen"
    errors << "#{packet['packet_id']}: Codex session-native execution must use ImageGen" unless execution["selected_native_tool"].to_s == "imagegen"
  when "openai_api_gpt_image_2"
    errors << "#{packet['packet_id']}: OpenAI execution must stay on #{OPENAI_IMAGE_MODEL}" unless execution["provider_model_or_tool"].to_s == OPENAI_IMAGE_MODEL
  when "grok_image"
    expected_tool = Array(packet["attachments"]).empty? ? "image_gen" : "image_edit"
    errors << "#{packet['packet_id']}: Grok attachment count requires #{expected_tool}" unless execution["selected_native_tool"].to_s == expected_tool
  when "xai_api_media"
    begin
      registration = IdolXaiApiMediaProfileContract.verify!(
        root: ROOT,
        execution: execution,
        attachment_count: Array(packet["attachments"]).length
      )
      schema_errors(
        XAI_PROFILE_SCHEMA,
        Pathname.new(registration.fetch("profile_path"))
      ).each do |error|
        errors << "#{packet['packet_id']}: xAI API provider profile #{error}"
      end
    rescue IdolXaiApiMediaProfileContract::ContractError => e
      errors << "#{packet['packet_id']}: #{e.message}"
    end
  else
    errors << "#{packet['packet_id']}: execution adapter is not active"
  end
  validate_prompt(packet, errors)
  validate_member_visual(packet, errors)
  validate_packet_integrity(packet, errors)
  expected_output = resolve_repo_path(packet.dig("export_contract", "expected_output_path"))
  run_root = options[:run_root] || path.dirname
  unless expected_output.to_s.start_with?("#{run_root.expand_path}/")
    errors << "#{packet['packet_id']}: expected output path must remain inside the run root"
  end
end
validate_section_coverage(document, errors)

official_branch_document = packets.any? { |row| row["mode"].to_s == "official_branch" }
master_storyboard = document.dig("input_files", "master_storyboard").to_s
if official_branch_document || !master_storyboard.empty?
  source_02a_path = resolve_repo_path(master_storyboard)
  if source_02a_path.file?
    begin
      source_02a = load_mapping(source_02a_path)
      errors << "source 02A schema must be #{Idol02AStoryboardContract::ACTIVE_SCHEMA_VERSION}" unless source_02a["schema_version"].to_s == Idol02AStoryboardContract::ACTIVE_SCHEMA_VERSION
      Array(document["section_shards"]).each do |shard|
        unless shard["local_lineage"].is_a?(Hash)
          errors << "#{shard['shard_id']}: active 2.6 requires local_lineage; no compatibility fallback is available"
          next
        end
        Idol02AStoryboardContract.prompt_section_lineage_errors(source_02a, document, shard).each do |error|
          errors << error
        end
      end
    rescue StandardError => e
      errors << "cannot validate local 02A lineage: #{e.message}"
    end
  else
    errors << "source 02A is missing"
  end
else
  source_cut_path = resolve_repo_path(document.dig("input_files", "source_cut_artifact"))
  if source_cut_path.file?
    expected_sha = document.dig("input_files", "source_cut_artifact_sha256").to_s
    errors << "source cut artifact SHA-256 is stale" unless Digest::SHA256.file(source_cut_path).hexdigest == expected_sha
  else
    errors << "source cut artifact is missing"
  end
end

if document["status"].to_s == "approved"
  review_refs = Array(document.dig("input_files", "section_context_reviews"))
  shard_sections = Array(document["section_shards"]).map { |shard| shard["section_id"].to_s }
  errors << "approved 02B section context reviews must exact-cover sections in order" unless review_refs.map { |row| row.to_h["section_id"].to_s } == shard_sections
  review_refs.each do |row|
    review_path = resolve_repo_path(row.to_h["path"])
    if !review_path.file?
      errors << "#{row.to_h['section_id']}: storyboard context review is missing"
    elsif Digest::SHA256.file(review_path).hexdigest != row.to_h["artifact_sha256"].to_s
      errors << "#{row.to_h['section_id']}: storyboard context review SHA-256 is stale"
    end
  end
end

if options[:mode] == "preflight"
  index_path = options[:export_index] && Pathname.new(options[:export_index]).expand_path
  errors << "preflight requires canonical approved 02B" unless document["status"].to_s == "approved" && packets.all? { |row| row["status"].to_s == "approved" }
  validate_export_index(index_path, path, document, errors)
end

unique_errors = errors.uniq
visible_errors = options[:max_errors].zero? ? unique_errors : unique_errors.first(options[:max_errors])
visible_errors.each { |error| warn("ERROR: #{error}") }
omitted = unique_errors.length - visible_errors.length
warn("ERROR: ... #{omitted} additional error(s) omitted; rerun with --max-errors 0") if omitted.positive?
exit 1 unless unique_errors.empty?

puts "OK: #{path} #{options[:mode]} contract covers #{packets.length} packet(s)"
