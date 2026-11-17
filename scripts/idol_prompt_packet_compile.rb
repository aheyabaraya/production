#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "optparse"
require "pathname"
require "tempfile"
require "yaml"
require_relative "lib/idol_02a_storyboard_contract"
require_relative "lib/idol_image_execution_lane_contract"
require_relative "lib/idol_reference_role_plan_contract"

ROOT = Pathname.new(__dir__).join("..").expand_path
DELTA_SCHEMA_VERSION = "1.6"
COMPILER_VERSION = "1.6"
COMPILER_PROFILE = "provider_neutral_one_cut_one_image_translation_v2_6"
OUTPUT_SCHEMA_VERSION = "2.6"
OUTPUT_FORMAT = "prompt_packets_v2_6"
PYTHON = ROOT.join("scripts", "idol-video-python")
SCHEMA_VALIDATOR = ROOT.join("scripts", "validate_json_schema.py")
DELTA_SCHEMA = ROOT.join("schemas", "prompt-packet-delta.schema.json")
STORYBOARD_SCHEMA = ROOT.join("schemas", "master-storyboard.schema.json")
STORYBOARD_VALIDATOR = ROOT.join("scripts", "validate_master_storyboard.rb")
FRONT_PLANNING_SCHEMA = ROOT.join("schemas", "front-planning-readiness.schema.json")
FRONT_PLANNING_VALIDATOR = ROOT.join("scripts", "validate_front_planning_readiness.rb")
DIRECTION_SCHEMA = ROOT.join("schemas", "song-choreography-performance-mv-map.schema.json")
DIRECTION_VALIDATOR = ROOT.join("scripts", "validate_01_section_direction.rb")
CONTEXT_REVIEW_VALIDATOR = ROOT.join("scripts", "validate_02a_creative_context_review.rb")
PROMPT_PACKET_SCHEMA = ROOT.join("schemas", "prompt-packets.schema.json")

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
COMPONENT_AUTHORING_RULE = "human_or_assigned_model_inspects_exact_02a_storyline_current_title_visuals_and_reference_bindings_then_authors_every_component_scripts_only_validate_and_serialize_fixed_labels"
STORYLINE_LEVELS = %w[whole_film section planning_cut 02a_branch_expansion].freeze
STORYLINE_SENSITIVE_COMPONENTS = [
  "scene_intent",
  "visible_details.background_and_space",
  "visible_details.still_camera_and_composition",
  "visible_details.lighting_color_material",
  "action_cue.subject_state_or_pose",
  "action_cue.visible_action_or_hold",
  "action_cue.object_environment_response",
  "avoid"
].freeze

PROMPT_METADATA_PATTERNS = {
  "SHA-256 digest" => /\b[0-9a-f]{64}\b/i,
  "SHA-256 label" => /\bsha-?256\b/i,
  "repository path" => %r{(?:^|[\s("'`])(?:runs|assets|schemas|skills|work|exports)/}i,
  "internal artifact id" => /\b(?:PKT_|BC|VRB_|02BPR_)[A-Z0-9_]+\b/,
  "schema/compiler field" => /\b(?:schema_version|compiler_profile|artifact_sha256|json_pointer|expected_output_path)\b/i
}.freeze

TEMPORAL_CAMERA_PATTERN = /
  \b(?:camera\s+(?:push(?:es)?|pull(?:s)?|pan(?:s)?|tilt(?:s)?|track(?:s)?|orbit(?:s)?|doll(?:y|ies)|crane(?:s)?|zoom(?:s)?)|
  push[- ]?in|pull[- ]?out|dolly[- ]?(?:in|out)|orbit(?:ing)?\s+camera|camera\s+speed|motion\s+envelope)\b
/ix.freeze

class CompileError < StandardError; end

def load_structured(path)
  text = path.read
  value = if path.extname.downcase == ".json"
            JSON.parse(text)
          else
            YAML.safe_load(text, permitted_classes: [], permitted_symbols: [], aliases: true)
          end
  value || {}
rescue JSON::ParserError, Psych::Exception => e
  raise CompileError, "failed to parse #{path}: #{e.message}"
end

def deep_copy(value)
  Marshal.load(Marshal.dump(value))
end

def canonical_value(value)
  case value
  when Hash
    value.keys.map(&:to_s).sort.each_with_object({}) do |key, result|
      source_key = value.key?(key) ? key : value.keys.find { |candidate| candidate.to_s == key }
      result[key] = canonical_value(value[source_key])
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

def file_sha256(path)
  Digest::SHA256.file(path.to_s).hexdigest
end

def resolve_repo_path(raw, must_exist: false)
  path = Pathname.new(raw.to_s)
  path = ROOT.join(path) unless path.absolute?
  path = path.expand_path.cleanpath
  relative = path.relative_path_from(ROOT).to_s
  if relative == ".." || relative.start_with?("../")
    raise CompileError, "path escapes the IDOL repository: #{raw}"
  end
  raise CompileError, "required file is missing: #{relative}" if must_exist && !path.file?

  [path, relative]
rescue ArgumentError
  raise CompileError, "path escapes the IDOL repository: #{raw}"
end

def repo_relative(path)
  path.expand_path.cleanpath.relative_path_from(ROOT).to_s
end

def require_mapping(value, label)
  raise CompileError, "#{label} must be an object" unless value.is_a?(Hash)

  value
end

def require_array(value, label)
  raise CompileError, "#{label} must be an array" unless value.is_a?(Array)

  value
end

def require_nonempty(value, label)
  text = value.to_s.strip
  raise CompileError, "#{label} must not be empty" if text.empty?

  text
end

def require_sha256(value, label)
  digest = value.to_s
  raise CompileError, "#{label} must be a lowercase SHA-256 digest" unless digest.match?(/\A[0-9a-f]{64}\z/)

  digest
end

def json_pointer_get(document, pointer)
  return document if pointer.to_s.empty?
  raise CompileError, "JSON pointer must start with '/': #{pointer}" unless pointer.to_s.start_with?("/")

  pointer.to_s.split("/")[1..].reduce(document) do |current, raw_token|
    token = raw_token.gsub("~1", "/").gsub("~0", "~")
    case current
    when Hash
      raise CompileError, "JSON pointer not found: #{pointer}" unless current.key?(token)

      current[token]
    when Array
      raise CompileError, "JSON pointer array token is invalid: #{pointer}" unless token.match?(/\A(?:0|[1-9][0-9]*)\z/)

      index = token.to_i
      raise CompileError, "JSON pointer array index is out of range: #{pointer}" unless index < current.length

      current[index]
    else
      raise CompileError, "JSON pointer traverses a scalar: #{pointer}"
    end
  end
end

def validate_schema_file(schema, document, label)
  stdout, stderr, status = Open3.capture3(
    PYTHON.to_s,
    SCHEMA_VALIDATOR.to_s,
    schema.to_s,
    document.to_s,
    chdir: ROOT.to_s
  )
  return if status.success?

  detail = [stderr, stdout].join(" ").strip
  raise CompileError, "#{label} failed JSON Schema validation: #{detail}"
end

def validate_compiled_schema(document)
  Tempfile.create(["idol-02b-prompt-packets-", ".json"]) do |file|
    file.write(JSON.pretty_generate(document))
    file.flush
    validate_schema_file(PROMPT_PACKET_SCHEMA, Pathname.new(file.path), "compiled 02B packet artifact")
  end
end

def validate_artifact_ref(ref, label, expected_schema: nil)
  require_mapping(ref, label)
  path, relative = resolve_repo_path(require_nonempty(ref["path"], "#{label}.path"), must_exist: true)
  expected_hash = require_sha256(ref["artifact_sha256"], "#{label}.artifact_sha256")
  actual_hash = file_sha256(path)
  raise CompileError, "#{label} hash is stale: expected #{expected_hash}, got #{actual_hash}" unless actual_hash == expected_hash

  document = load_structured(path)
  if expected_schema
    declared = ref["schema_version"].to_s
    actual = document["schema_version"].to_s
    raise CompileError, "#{label}.schema_version must be #{expected_schema}" unless declared == expected_schema
    raise CompileError, "#{label} bytes declare schema #{actual}, expected #{expected_schema}" unless actual == expected_schema
  end
  [path, relative, document, actual_hash]
end

def validate_evidence(ref, label, content_id:, source_02a_path:, source_02a_sha:)
  path, relative, document, digest = validate_artifact_ref(ref, label)
  if label == "readiness_evidence.storyboard_context_review"
    unless document["schema_version"].to_s == "idol-02a-creative-context-review.v7"
      raise CompileError, "#{label} must use idol-02a-creative-context-review.v7"
    end
    raise CompileError, "#{label}.content_id does not match" unless document["content_id"].to_s == content_id
    source = require_mapping(document["source_02a"], "#{label}.source_02a")
    declared_source, = resolve_repo_path(source["path"], must_exist: true)
    raise CompileError, "#{label} points to another 02A artifact" unless declared_source == source_02a_path
    raise CompileError, "#{label} source 02A hash is stale" unless source["sha256"].to_s == source_02a_sha
    unless document["status"].to_s == "passed" && document.dig("founder_gate", "decision").to_s == "pass"
      raise CompileError, "#{label} must be status passed with Founder decision pass"
    end
    stdout, stderr, status = Open3.capture3(
      "ruby",
      CONTEXT_REVIEW_VALIDATOR.to_s,
      path.to_s,
      "--repo-root",
      ROOT.to_s,
      chdir: ROOT.to_s
    )
    unless status.success?
      raise CompileError, "#{label} failed active contextual review validation: #{[stderr, stdout].join(' ').strip}"
    end
  end
  [path, relative, document, digest]
end

def core_cut_id(core_cut)
  require_nonempty(core_cut["core_cut_id"], "02A Core Cut.core_cut_id")
end

def core_time_range(core_cut)
  imported = core_cut.to_h["imported_core"].to_h
  value = imported["time_range"]
  return value unless value.to_s.empty?

  start_value = imported["start_seconds"]
  end_value = imported["end_seconds"]
  return format("%.3f-%.3f", start_value.to_f, end_value.to_f) unless start_value.nil? || end_value.nil?

  "untimed_selected_audio_cue"
end

def validate_scope!(source, scope)
  shards = require_array(source["section_shards"], "source_02a.section_shards")
  shard = shards.find { |row| row.is_a?(Hash) && row["shard_id"].to_s == scope["shard_id"].to_s }
  raise CompileError, "section_compile_scope.shard_id is not declared by source 02A" unless shard

  scope_sections = Array(scope["section_ids"]).map(&:to_s)
  scope_core_cuts = Array(scope["core_cut_ids"]).map(&:to_s)
  shard_sections = Array(shard["section_ids"]).map(&:to_s)
  shard_core_cuts = Array(shard["core_cut_ids"]).map(&:to_s)
  raise CompileError, "section_compile_scope must contain exactly one section" unless scope_sections.length == 1
  raise CompileError, "primary_section_id must equal the one section id" unless scope["primary_section_id"].to_s == scope_sections.first
  raise CompileError, "section_compile_scope.section_ids must exact-copy the selected shard" unless scope_sections == shard_sections
  unless scope_core_cuts == shard_core_cuts
    raise CompileError, "section_compile_scope.core_cut_ids must exact-copy the selected shard in order"
  end

  core_cuts = require_array(source["master_storyboard"], "source_02a.master_storyboard")
  indexed = core_cuts.each_with_index.to_h { |row, index| [core_cut_id(row), [row, index]] }
  missing = scope_core_cuts.reject { |id| indexed.key?(id) }
  raise CompileError, "section_compile_scope names unknown Core Cuts: #{missing.join(', ')}" unless missing.empty?

  section_id = scope_sections.first
  selected = scope_core_cuts.map do |id|
    core_cut, index = indexed.fetch(id)
    unless core_cut.dig("imported_core", "section_id").to_s == section_id
      raise CompileError, "#{id} does not belong to #{section_id}"
    end
    [core_cut, index]
  end
  [shard, selected, section_id]
end

def core_cut_context_projection(core_cut)
  Idol02AStoryboardContract.core_cut_context_projection(core_cut)
end

def context_payload(source, shard, selected_core_cuts, core_position, current_branch_cut, branch_position)
  Idol02AStoryboardContract.same_section_context_payload(
    source,
    shard,
    selected_core_cuts.map(&:first),
    core_position,
    current_branch_cut,
    branch_position
  )
end

def validate_neighbor_core_ref!(declared, expected_core_cut, expected_index, label)
  if expected_core_cut.nil?
    raise CompileError, "#{label} must be null at the section boundary" unless declared.nil?
    return
  end

  ref = require_mapping(declared, label)
  expected_pointer = "/master_storyboard/#{expected_index}"
  unless ref["core_cut_id"].to_s == core_cut_id(expected_core_cut)
    raise CompileError, "#{label}.core_cut_id is not the immediate same-section Core Cut"
  end
  raise CompileError, "#{label}.json_pointer must be #{expected_pointer}" unless ref["json_pointer"].to_s == expected_pointer
  expected_context_sha = value_sha256(
    Idol02AStoryboardContract.core_cut_context_projection(expected_core_cut)
  )
  unless ref["value_sha256"].to_s == expected_context_sha
    raise CompileError, "#{label}.value_sha256 is stale"
  end
end

def validate_neighbor_branch_ref!(declared, expected_branch_cut, core_index, branch_index, label)
  if expected_branch_cut.nil?
    raise CompileError, "#{label} must be null at the Branch-Cut boundary" unless declared.nil?
    return
  end

  ref = require_mapping(declared, label)
  expected_pointer = "/master_storyboard/#{core_index}/compile_seed/branch_cuts/#{branch_index}"
  unless ref["branch_cut_id"].to_s == expected_branch_cut["branch_cut_id"].to_s
    raise CompileError, "#{label}.branch_cut_id is not the immediate Branch-Cut sibling"
  end
  raise CompileError, "#{label}.json_pointer must be #{expected_pointer}" unless ref["json_pointer"].to_s == expected_pointer
  raise CompileError, "#{label}.value_sha256 is stale" unless ref["value_sha256"].to_s == value_sha256(expected_branch_cut)
end

def output_neighbor_ref(ref)
  return nil unless ref.is_a?(Hash)

  ref.reject { |key, _value| key.to_s == "json_pointer" }
end

def validate_same_section_context!(
  declared,
  source:,
  shard:,
  section_id:,
  selected_core_cuts:,
  core_position:,
  current_branch_cut:,
  branch_position:
)
  declared = require_mapping(declared, "direct_prompt_revision.same_section_context")
  current_core_cut, current_core_index = selected_core_cuts.fetch(core_position)
  branch_cuts = Array(current_core_cut.dig("compile_seed", "branch_cuts"))
  previous_branch = branch_position.zero? ? nil : branch_cuts.fetch(branch_position - 1)
  next_branch = branch_position == branch_cuts.length - 1 ? nil : branch_cuts.fetch(branch_position + 1)
  previous_core_pair = core_position.zero? ? nil : selected_core_cuts.fetch(core_position - 1)
  next_core_pair = core_position == selected_core_cuts.length - 1 ? nil : selected_core_cuts.fetch(core_position + 1)

  raise CompileError, "same_section_context.section_id must equal compile scope" unless declared["section_id"].to_s == section_id
  unless declared["current_core_cut_id"].to_s == core_cut_id(current_core_cut)
    raise CompileError, "same_section_context.current_core_cut_id must equal parent Core Cut"
  end
  unless declared["current_branch_cut_id"].to_s == current_branch_cut["branch_cut_id"].to_s
    raise CompileError, "same_section_context.current_branch_cut_id must equal current Branch Cut"
  end
  validate_neighbor_branch_ref!(
    declared["previous_branch_cut"],
    previous_branch,
    current_core_index,
    branch_position - 1,
    "same_section_context.previous_branch_cut"
  )
  validate_neighbor_branch_ref!(
    declared["next_branch_cut"],
    next_branch,
    current_core_index,
    branch_position + 1,
    "same_section_context.next_branch_cut"
  )
  validate_neighbor_core_ref!(
    declared["previous_core_cut"],
    previous_core_pair&.first,
    previous_core_pair&.last,
    "same_section_context.previous_core_cut"
  )
  validate_neighbor_core_ref!(
    declared["next_core_cut"],
    next_core_pair&.first,
    next_core_pair&.last,
    "same_section_context.next_core_cut"
  )

  payload = context_payload(
    source,
    shard,
    selected_core_cuts,
    core_position,
    current_branch_cut,
    branch_position
  )
  digest = value_sha256(payload)
  unless declared["context_value_sha256"].to_s == digest
    raise CompileError, "same_section_context.context_value_sha256 is stale for #{current_branch_cut['branch_cut_id']}"
  end
  [
    {
      "policy" => declared["policy"],
      "section_id" => section_id,
      "current_core_cut_id" => core_cut_id(current_core_cut),
      "current_branch_cut_id" => current_branch_cut["branch_cut_id"],
      "previous_branch_cut" => output_neighbor_ref(declared["previous_branch_cut"]),
      "next_branch_cut" => output_neighbor_ref(declared["next_branch_cut"]),
      "previous_core_cut" => output_neighbor_ref(declared["previous_core_cut"]),
      "next_core_cut" => output_neighbor_ref(declared["next_core_cut"]),
      "first_core_cut_boundary_rule" => "use_current_section_entry_continuity_when_previous_core_cut_is_null",
      "last_core_cut_boundary_rule" => "use_current_section_exit_continuity_when_next_core_cut_is_null",
      "context_value_sha256" => digest
    },
    digest
  ]
end

def validate_reference_binding!(binding, member_visual:, package_album_key:, package_title_key:)
  binding = require_mapping(binding, "02A visual_reference_binding")
  path, relative = resolve_repo_path(binding["actual_path"], must_exist: true)
  actual_hash = file_sha256(path)
  raise CompileError, "#{binding['binding_id']} pixel hash is stale" unless binding["sha256"].to_s == actual_hash
  if relative.match?(%r{(^|/)face-only-reference(?:-|\.|/)}i)
    raise CompileError, "#{binding['binding_id']} uses a prohibited face-only asset path"
  end

  if member_visual
    raise CompileError, "#{binding['binding_id']} member visual must use reference_scope member_visual" unless binding["reference_scope"].to_s == "member_visual"
    raise CompileError, "#{binding['binding_id']} member visual must use current_title_member_visual" unless binding["reference_class"].to_s == "current_title_member_visual"
    expected_segment = "assets/members/album-assets/#{package_album_key}/#{package_title_key}/"
    unless relative.start_with?(expected_segment)
      raise CompileError, "#{binding['binding_id']} is outside the current-title package #{expected_segment}"
    end
  elsif binding["reference_scope"].to_s != "scene_visual"
    raise CompileError, "#{binding['binding_id']} must declare member_visual or scene_visual"
  elsif binding["reference_class"].to_s == "current_title_world_or_background"
    unless binding["source_owner"].to_s == "front_planning_album_visual_asset"
      raise CompileError, "#{binding['binding_id']} current-title world/background must come from the Front Planning album visual package"
    end
    expected_segment = "assets/members/album-assets/#{package_album_key}/#{package_title_key}/"
    unless relative.start_with?(expected_segment)
      raise CompileError, "#{binding['binding_id']} is outside the current-title package #{expected_segment}"
    end
  end
  [path, relative]
end

def validate_member_visuals!(branch_cut)
  input = require_mapping(branch_cut["member_visual_compile_input"], "02A Branch Cut.member_visual_compile_input")
  policy = input["member_visual_reference_policy"].to_s
  selected_ids = Array(input["selected_album_member_visual_asset_ids"]).map(&:to_s)
  visible_members = Array(branch_cut["visible_member_focus"]).map(&:to_s)
  applicability = Idol02AStoryboardContract.member_visual_applicability(input, visible_members)
  bindings = Array(branch_cut["visual_reference_bindings"]).map do |row|
    require_mapping(row, "02A Branch Cut.visual_reference_bindings[]")
  end
  orders = bindings.map { |row| row["order"] }
  expected_orders = (1..bindings.length).to_a
  unless orders == expected_orders
    raise CompileError, "#{branch_cut['branch_cut_id']} visual-reference order must be contiguous from 1"
  end

  member_bindings = bindings.select { |row| row["reference_scope"].to_s == "member_visual" }
  scene_bindings = bindings.select { |row| row["reference_scope"].to_s == "scene_visual" }
  package_album_key = require_nonempty(input["package_album_key"], "member_visual_compile_input.package_album_key")
  package_title_key = require_nonempty(input["package_title_key"], "member_visual_compile_input.package_title_key")

  applicability_errors = Idol02AStoryboardContract.member_visual_contract_errors(
    branch_cut["branch_cut_id"],
    input,
    visible_members,
    selected_ids
  )
  unless applicability_errors.empty?
    raise CompileError, applicability_errors.join("; ")
  end

  case policy
  when "required"
    raise CompileError, "#{branch_cut['branch_cut_id']} requires at least one selected member visual" if selected_ids.empty?
    bound_ids = member_bindings.map { |row| row["asset_id"].to_s }
    unless bound_ids == selected_ids
      raise CompileError, "#{branch_cut['branch_cut_id']} member-visual bindings must exact-copy the selected asset ids in order"
    end
  when "prohibited"
    unless selected_ids.empty? && member_bindings.empty?
      raise CompileError, "#{branch_cut['branch_cut_id']} prohibits member visuals but still selects or binds one"
    end
  else
    raise CompileError, "#{branch_cut['branch_cut_id']} member_visual_reference_policy is invalid"
  end

  bindings.each do |binding|
    validate_reference_binding!(
      binding,
      member_visual: binding["reference_scope"].to_s == "member_visual",
      package_album_key: package_album_key,
      package_title_key: package_title_key
    )
  end

  member_assets = member_bindings.map do |binding|
    {
      "asset_id" => binding["asset_id"],
      "actual_path" => binding["actual_path"],
      "sha256" => binding["sha256"],
      "package_album_key" => package_album_key,
      "package_title_key" => package_title_key,
      "order" => binding["order"]
    }
  end

  member_lock = {
    "member_visual_reference_policy" => policy,
    "member_visual_applicability" => applicability,
    "visible_member_focus" => visible_members,
    "package_album_key" => package_album_key,
    "package_title_key" => package_title_key,
    "selected_assets" => member_assets,
    "selection_rule" => "smallest_branch_cut_relevant_subset_from_front_planning_authorized_current_title_pool",
    "visual_control_policy" => "member_visual_controls_only_appearance_hair_makeup_wardrobe_material_silhouette_and_body_continuity_never_forces_face_frontal_gaze_pose_camera_crop_or_proportions"
  }
  [member_lock, bindings, scene_bindings]
end

def require_authored_line(value, label)
  text = require_nonempty(value, label)
  raise CompileError, "#{label} must be one line" if text.match?(/[\r\n]/)

  text
end

def validate_storyline_authoring_binding!(revision, source:, shard:, branch_cut:)
  source_binding = require_mapping(
    branch_cut["storyline_alignment_binding"],
    "source Branch Cut storyline_alignment_binding"
  )
  whole_readout = source.dig(
    "founder_visual_alignment_projection",
    "projected_value",
    "whole_film_readout"
  )
  section_readout = shard.dig("section_alignment_projection", "projected_value")
  planning_cut_readout = source_binding["projected_value"]
  expansion_delta = require_nonempty(
    source_binding["02a_expansion_delta"],
    "source Branch Cut storyline 02a_expansion_delta"
  )
  raise CompileError, "source 02A whole-film storyline readout is missing" if whole_readout.nil?
  raise CompileError, "source 02A section storyline readout is missing" if section_readout.nil?
  raise CompileError, "source 02A planning-cut storyline readout is missing" if planning_cut_readout.nil?
  unless source_binding["source_value_sha256"].to_s == value_sha256(planning_cut_readout)
    raise CompileError, "source Branch Cut storyline planning-cut hash is stale"
  end

  declared = require_mapping(
    revision["storyline_authoring_binding"],
    "direct_prompt_revision.storyline_authoring_binding"
  )
  expected = {
    "planning_cut_id" => source_binding["planning_cut_id"],
    "source_key_screen_id" => source_binding["source_key_screen_id"],
    "source_branch_storyline_binding_sha256" => value_sha256(source_binding),
    "whole_film_readout_sha256" => value_sha256(whole_readout),
    "section_readout_sha256" => value_sha256(section_readout),
    "planning_cut_readout_sha256" => value_sha256(planning_cut_readout),
    "02a_expansion_delta_sha256" => value_sha256(expansion_delta)
  }
  expected.each do |key, value|
    unless declared[key].to_s == value.to_s
      raise CompileError, "storyline authoring binding #{key} is stale or differs from 02A"
    end
  end

  consumption = require_mapping(
    declared["component_consumption"],
    "storyline_authoring_binding.component_consumption"
  )
  unless consumption.keys.map(&:to_s).sort == STORYLINE_LEVELS.sort
    raise CompileError, "storyline component consumption must exact-cover all four storyline levels"
  end
  consumed = STORYLINE_LEVELS.flat_map do |level|
    values = require_array(consumption[level], "storyline component consumption #{level}").map(&:to_s)
    raise CompileError, "storyline component consumption #{level} must not be empty" if values.empty?
    raise CompileError, "storyline component consumption #{level} repeats a component" unless values.uniq.length == values.length
    unless (values - STORYLINE_SENSITIVE_COMPONENTS).empty?
      raise CompileError, "storyline component consumption #{level} names an inactive prompt component"
    end
    values
  end
  unless consumed.uniq.sort == STORYLINE_SENSITIVE_COMPONENTS.sort
    raise CompileError, "storyline component consumption union must cover every storyline-sensitive prompt component"
  end
  unless declared["coverage_rule"].to_s == "the_union_must_cover_every_storyline_sensitive_prompt_component_before_compile" &&
         declared["semantic_review_rule"].to_s == "mechanical_mapping_is_not_semantic_proof_the_recipient_director_must_read_the_storyline_and_prompt_then_accept_or_hold"
    raise CompileError, "storyline authoring binding policy is inactive"
  end
  [deep_copy(source_binding), value_sha256(source_binding)]
end

def validate_authoring_inspection_receipt!(revision, branch_cut, bindings, storyline_binding_sha)
  receipt = require_mapping(
    revision["authoring_inspection_receipt"],
    "direct_prompt_revision.authoring_inspection_receipt"
  )
  owner = revision["authoring_owner"].to_s
  unless receipt["inspection_owner"].to_s == owner
    raise CompileError, "authoring inspection owner must match direct prompt revision owner"
  end

  branch_hash = value_sha256(branch_cut)
  unless receipt["source_02a_branch_cut_sha256"].to_s == branch_hash &&
         revision["source_02a_branch_cut_lock_sha256"].to_s == branch_hash
    raise CompileError, "authoring inspection receipt is bound to stale 02A Branch-Cut truth"
  end
  unless receipt["source_storyline_alignment_binding_sha256"].to_s == storyline_binding_sha
    raise CompileError, "authoring inspection receipt is bound to stale storyline truth"
  end
  unless Array(receipt["inspected_storyline_levels"]).map(&:to_s) == STORYLINE_LEVELS
    raise CompileError, "authoring inspection receipt must inspect whole-film, section, planning-cut, and 02A expansion storyline levels in order"
  end

  expected_binding_ids = bindings.map { |binding| binding["binding_id"].to_s }
  inspected_binding_ids = Array(receipt["inspected_visual_reference_binding_ids"]).map(&:to_s)
  unless inspected_binding_ids == expected_binding_ids
    raise CompileError, "authoring inspection receipt must exact-copy all visual-reference binding ids in order"
  end

  expected_current_title_asset_ids = bindings.each_with_object([]) do |binding, ids|
    ids << binding["asset_id"].to_s if binding["reference_class"].to_s.start_with?("current_title_")
  end
  inspected_current_title_asset_ids = Array(receipt["inspected_current_title_asset_ids"]).map(&:to_s)
  unless inspected_current_title_asset_ids == expected_current_title_asset_ids
    raise CompileError, "authoring inspection receipt must exact-copy current-title visual asset ids in binding order"
  end

  authored_order = Array(receipt["authored_component_order"]).map(&:to_s)
  unless authored_order == AUTHORED_COMPONENT_ORDER
    raise CompileError, "authoring inspection receipt component order is not active"
  end
  unless receipt["creative_fill_policy"].to_s == CREATIVE_FILL_POLICY
    raise CompileError, "authoring inspection receipt must forbid script-authored creative fill"
  end
  require_authored_line(
    receipt["storyline_inspection_note"],
    "authoring_inspection_receipt.storyline_inspection_note"
  )
  require_authored_line(receipt["inspection_note"], "authoring_inspection_receipt.inspection_note")
  receipt
end

def validate_prompt_blueprint!(revision, _member_visual_policy)
  blueprint = require_mapping(revision["prompt_blueprint"], "direct_prompt_revision.prompt_blueprint")
  if blueprint["authoring_owner"].to_s != revision["authoring_owner"].to_s
    raise CompileError, "direct_prompt_revision authoring_owner must match prompt_blueprint.authoring_owner"
  end

  fields = %w[identity_reference_rule scene_intent avoid].to_h do |key|
    [key, require_authored_line(blueprint[key], "prompt_blueprint.#{key}")]
  end

  visible = require_mapping(blueprint["visible_details"], "prompt_blueprint.visible_details")
  still_camera = require_mapping(
    visible["still_camera_and_composition"],
    "prompt_blueprint.visible_details.still_camera_and_composition"
  )
  background_and_space = require_authored_line(
    visible["background_and_space"],
    "prompt_blueprint.visible_details.background_and_space"
  )
  camera_fields = %w[
    camera_height
    shot_scale_distance
    direction_angle
    depth_design
    subject_placement
    crop_negative_space
    lens_feel
  ].to_h do |key|
    [
      key,
      require_authored_line(
        still_camera[key],
        "prompt_blueprint.visible_details.still_camera_and_composition.#{key}"
      )
    ]
  end
  lighting_color_material = require_authored_line(
    visible["lighting_color_material"],
    "prompt_blueprint.visible_details.lighting_color_material"
  )
  unless visible["render_quality"].to_s == "4K, high quality, high detail"
    raise CompileError, "prompt_blueprint.visible_details.render_quality must use the fixed active quality literal"
  end

  action = require_mapping(blueprint["action_cue"], "prompt_blueprint.action_cue")
  subject_state_or_pose = require_authored_line(
    action["subject_state_or_pose"],
    "prompt_blueprint.action_cue.subject_state_or_pose"
  )
  visible_action_or_hold = require_authored_line(
    action["visible_action_or_hold"],
    "prompt_blueprint.action_cue.visible_action_or_hold"
  )
  object_environment_response = action["object_environment_response"]
  unless object_environment_response.nil?
    object_environment_response = require_authored_line(
      object_environment_response,
      "prompt_blueprint.action_cue.object_environment_response"
    )
  end

  visible_details = [
    "Background and space — #{background_and_space}",
    "Still camera and composition — camera height: #{camera_fields['camera_height']}; shot scale/distance: #{camera_fields['shot_scale_distance']}; direction/angle: #{camera_fields['direction_angle']}; depth: #{camera_fields['depth_design']}; subject placement: #{camera_fields['subject_placement']}; crop/negative space: #{camera_fields['crop_negative_space']}; lens feel: #{camera_fields['lens_feel']}",
    "Lighting, color, and material — #{lighting_color_material}",
    "4K, high quality, high detail"
  ].join("; ")
  action_cue_parts = [
    "Subject state or pose — #{subject_state_or_pose}",
    "Visible action or hold — #{visible_action_or_hold}"
  ]
  if object_environment_response
    action_cue_parts << "Object/environment response — #{object_environment_response}"
  end
  action_cue = action_cue_parts.join("; ")

  identity_rule = fields["identity_reference_rule"]
  if identity_rule.match?(/\bface[- ]?(?:only|reference|ref)\b/i)
    raise CompileError, "Identity reference rule must not create a separate face-reference lane"
  end

  prompt_text = [
    "Identity reference rule: #{fields['identity_reference_rule']}",
    "Scene intent: #{fields['scene_intent']}",
    "Visible details: #{visible_details}",
    "Action cue: #{action_cue}",
    "Avoid: #{fields['avoid']}"
  ].join("\n")

  PROMPT_METADATA_PATTERNS.each do |label, pattern|
    raise CompileError, "render prompt leaks #{label}" if prompt_text.match?(pattern)
  end
  if prompt_text.match?(TEMPORAL_CAMERA_PATTERN)
    raise CompileError, "render prompt authors temporal camera motion; keep push/pull/pan/tilt/track/orbit/speed for 03V"
  end
  [
    {
      "identity_reference_rule" => fields["identity_reference_rule"],
      "scene_intent" => fields["scene_intent"],
      "visible_details" => visible_details,
      "action_cue" => action_cue,
      "avoid" => fields["avoid"],
      "full_prompt_text" => prompt_text,
      "full_prompt_sha256" => Digest::SHA256.hexdigest(prompt_text),
      "label_order" => PROMPT_LABELS
    },
    blueprint
  ]
end

def run_active_validator!(validator, path, label)
  stdout, stderr, status = Open3.capture3(
    "ruby",
    validator.to_s,
    "--root",
    ROOT.to_s,
    path.to_s,
    chdir: ROOT.to_s
  )
  return if status.success?

  raise CompileError, "#{label} failed active semantic validation: #{[stderr, stdout].join(' ').strip}"
end

def validate_embedded_artifact_ref(ref, label, expected_schema: nil)
  ref = require_mapping(ref, label)
  path, relative = resolve_repo_path(require_nonempty(ref["path"], "#{label}.path"), must_exist: true)
  expected_hash = require_sha256(ref["sha256"], "#{label}.sha256")
  actual_hash = file_sha256(path)
  raise CompileError, "#{label} hash is stale" unless actual_hash == expected_hash

  document = load_structured(path)
  if expected_schema && document["schema_version"].to_s != expected_schema
    raise CompileError, "#{label} bytes declare schema #{document['schema_version']}, expected #{expected_schema}"
  end
  [path, relative, document, actual_hash]
end

def selected_fp_route(source)
  routes = require_array(source["candidate_routes"], "Front Planning candidate_routes")
  route = routes.find do |row|
    row.is_a?(Hash) && row["recommendation_rank"].to_i == 1 && row["viability_status"].to_s == "complete_viable"
  end
  raise CompileError, "Front Planning has no rank-1 complete viable route" unless route

  route
end

def fp_core_slot_context(source, core_slot_id)
  matches = []
  Array(selected_fp_route(source)["sections"]).each do |section|
    Array(section["route_major_expansions"]).each do |major|
      Array(major["core_cut_slots"]).each do |slot|
        next unless slot["core_slot_id"].to_s == core_slot_id.to_s

        matches << [section, major, slot]
      end
    end
  end
  raise CompileError, "Front Planning Core Slot #{core_slot_id} must resolve exactly once" unless matches.length == 1

  matches.first
end

def fp_screen_node(source, source_id)
  nodes = Array(source.dig("screen_progression_map", "nodes"))
  matches = nodes.each_with_index.select { |row, _index| row.to_h["source_id"].to_s == source_id.to_s }
  raise CompileError, "screen progression source #{source_id} must resolve exactly once" unless matches.length == 1

  matches.first
end

def fp_selected_reference(source, core_slot_id)
  sets = Array(source["core_visual_candidate_sets"])
  set = sets.find { |row| row.to_h["core_slot_id"].to_s == core_slot_id.to_s }
  raise CompileError, "Front Planning has no visual candidate set for #{core_slot_id}" unless set

  selected_id = require_nonempty(set["selected_candidate_id"], "#{core_slot_id} selected_candidate_id")
  candidate = Array(set["candidates"]).find do |row|
    row.to_h["candidate_id"].to_s == selected_id && row.to_h["disposition"].to_s == "selected"
  end
  raise CompileError, "Front Planning selected reference #{selected_id} is missing or not selected" unless candidate

  candidate
end

def fp_member_assets(source, section_id)
  identity = require_mapping(source["current_title_visual_identity"], "Front Planning current_title_visual_identity")
  assets = Array(identity["assets"]).select do |asset|
    asset.is_a?(Hash) &&
      asset["status"].to_s == "authorized" &&
      Array(asset["section_ids"]).map(&:to_s).include?(section_id.to_s) &&
      asset["asset_type"].to_s == "member_visual_anchor"
  end
  [identity, assets]
end

def packet_attachment_from_source(source, order:, role:, binding_id:, asset_id:)
  path, relative = resolve_repo_path(require_nonempty(source["path"] || source["actual_path"], "attachment source path"), must_exist: true)
  expected_hash = require_sha256(source["sha256"], "attachment source sha256")
  raise CompileError, "attachment source hash is stale: #{relative}" unless file_sha256(path) == expected_hash

  {
    "order" => order,
    "role" => role,
    "binding_id" => binding_id,
    "asset_id" => asset_id,
    "actual_path" => relative,
    "sha256" => expected_hash,
    "pixel_inspection_status" => "passed",
    "locked" => true
  }
end

def generic_expected_attachments(mode, source, source_cut, cut_context)
  section_id = cut_context.fetch("section_id")
  if mode == "fp_hero_core"
    front = source
    core_slot_id = cut_context.fetch("source_core_slot_id")
    scene_source = fp_selected_reference(front, core_slot_id)
    scene_binding_id = scene_source.fetch("candidate_id")
    scene_asset_id = scene_binding_id
  else
    _front_path, _front_relative, front, = validate_embedded_artifact_ref(
      source["source_front_planning"],
      "source 01 source_front_planning",
      expected_schema: "front-planning-readiness.v17"
    )
    reference = require_mapping(source_cut["core_reference_binding"], "Official Core core_reference_binding")
    raise CompileError, "Official Core requires one selected Core reference" unless reference["required"] == true
    scene_source = reference
    scene_binding_id = require_nonempty(reference["binding_id"], "Official Core reference binding_id")
    scene_asset_id = require_nonempty(reference["selected_reference_candidate_id"], "Official Core selected reference candidate id")
  end

  identity, member_assets = fp_member_assets(front, section_id)
  applicability = cut_context.fetch("member_visual_applicability")
  if applicability == "meaningfully_visible"
    raise CompileError, "#{mode} meaningfully-visible Cut has no authorized current-title Member Visual" if member_assets.empty?
  else
    member_assets = []
  end

  attachments = []
  member_assets.each do |asset|
    attachments << packet_attachment_from_source(
      asset,
      order: attachments.length + 1,
      role: "current_title_member_visual",
      binding_id: asset.fetch("asset_id"),
      asset_id: asset.fetch("asset_id")
    )
    asset_root = resolve_repo_path(identity.fetch("asset_root")).first
    actual_path = resolve_repo_path(asset.fetch("path"), must_exist: true).first
    unless actual_path.to_s.start_with?("#{asset_root}#{File::SEPARATOR}")
      raise CompileError, "current-title Member Visual escapes the active title asset root"
    end
  end
  attachments << packet_attachment_from_source(
    scene_source,
    order: attachments.length + 1,
    role: "governing_scene_or_sequence_reference",
    binding_id: scene_binding_id,
    asset_id: scene_asset_id
  )
  attachments
end

def validate_generic_five_lines!(packet, mode)
  components = require_mapping(packet["five_line_components"], "packet.five_line_components")
  unless components["authoring_owner"].to_s == "human_or_assigned_model"
    raise CompileError, "#{packet['packet_id']} five-line components require a human or assigned model author"
  end
  identity = require_mapping(components["identity_reference_rule"], "five_line_components.identity_reference_rule")
  scene = require_mapping(components["scene_intent"], "five_line_components.scene_intent")
  if mode != "official_branch" && !scene["branch_expansion_component"].nil?
    raise CompileError, "#{packet['packet_id']} Hero/Core packet may not author a Branch expansion component"
  end
  scene_line = mode == "official_branch" ? scene["branch_expansion_component"] : scene["core_slot_or_core_component"]
  blueprint = {
    "authoring_owner" => "human_or_assigned_model",
    "identity_reference_rule" => identity["visible_identity"],
    "scene_intent" => scene_line,
    "visible_details" => components["visible_details"],
    "action_cue" => components["action_cue"],
    "avoid" => components["avoid"]
  }
  rendered, = validate_prompt_blueprint!(
    {"authoring_owner" => "human_or_assigned_model", "prompt_blueprint" => blueprint},
    nil
  )
  supplied = require_mapping(packet["rendered_five_lines"], "packet.rendered_five_lines")
  unless canonical_value(supplied) == canonical_value(rendered)
    raise CompileError, "#{packet['packet_id']} rendered_five_lines must be the fixed-label serialization of authored components"
  end
  unless rendered.fetch("full_prompt_text").lines.length == 5
    raise CompileError, "#{packet['packet_id']} must serialize exactly five natural-language lines"
  end
  [deep_copy(components), rendered]
end

def validate_generic_execution!(packet, attachments, run_execution_selection, expected_output)
  execution = require_mapping(packet["execution"], "packet.execution")
  begin
    IdolImageExecutionLaneContract.verify_execution_shape!(
      selection: run_execution_selection,
      execution: execution,
      attachment_count: attachments.length
    )
  rescue IdolImageExecutionLaneContract::ContractError => e
    raise CompileError, "#{packet['packet_id']} #{e.message}"
  end
  unless execution["expected_output_path"].to_s == expected_output && execution["output_count"] == 1
    raise CompileError, "#{packet['packet_id']} execution must preserve the exact one-output path"
  end
  unless execution["prompt_rewrite_policy"].to_s == "forbidden" && execution["automatic_fallback"].to_s == "none"
    raise CompileError, "#{packet['packet_id']} execution must forbid prompt rewrite and provider/auth/model fallback"
  end
  deep_copy(execution)
end

def validate_reference_role_plan!(raw_plan, attachments, member_visual_applicability, current_section_id, packet_id)
  plan = IdolReferenceRolePlanContract.verify!(
    plan: raw_plan,
    attachments: attachments,
    member_visual_applicability: member_visual_applicability,
    current_section_id: current_section_id,
    root: ROOT,
    label: "#{packet_id}.reference_role_plan"
  )
  deep_copy(plan)
rescue IdolReferenceRolePlanContract::ContractError => e
  raise CompileError, e.message
end

def validate_generic_packet!(packet, mode:, source_path:, source_relative:, source:, source_sha:, run_execution_selection:)
  packet_id = require_nonempty(packet["packet_id"], "packet.packet_id")
  raise CompileError, "#{packet_id} mode differs from compile_target" unless packet["mode"].to_s == mode
  source_ref = require_mapping(packet["source_cut_ref"], "#{packet_id}.source_cut_ref")
  pointer = require_nonempty(source_ref["json_pointer"], "#{packet_id}.source_cut_ref.json_pointer")
  source_cut = require_mapping(json_pointer_get(source, pointer), "#{packet_id} source Cut")
  source_cut_sha = value_sha256(source_cut)
  raise CompileError, "#{packet_id} source Cut hash is stale" unless source_ref["value_sha256"].to_s == source_cut_sha
  context = require_mapping(packet["cut_context"], "#{packet_id}.cut_context")

  if mode == "fp_hero_core"
    cut_id = require_nonempty(source_cut["hero_core_id"], "Hero Core id")
    raise CompileError, "#{packet_id} source Cut id mismatch" unless source_ref["cut_id"].to_s == cut_id
    raise CompileError, "#{packet_id} Hero Core is not a selected passed planning candidate" unless source_cut["pixel_review_status"].to_s == "pass" && source_cut["adoption_status"].to_s == "selected_for_01"
    core_slot_id = require_nonempty(source_cut["core_slot_id"], "Hero Core core_slot_id")
    raise CompileError, "#{packet_id} source_core_slot_id mismatch" unless context["source_core_slot_id"].to_s == core_slot_id
    section, major, = fp_core_slot_context(source, core_slot_id)
    node, node_index = fp_screen_node(source, core_slot_id)
    storyline_pointer = "/screen_progression_map/nodes/#{node_index}"
    storyline_version = source.dig("screen_progression_map", "active_storyline_version_id")
    section_id = section.fetch("section_id")
    major_scene_id = major.fetch("major_scene_id")
    applicability = context.fetch("member_visual_applicability")
    authority_status = "planning_candidate_only"
    cut_type = "hero_core"
    parent_core_cut_id = nil
  else
    cut_id = require_nonempty(source_cut["core_cut_id"], "Official Core id")
    raise CompileError, "#{packet_id} source Cut id mismatch" unless source_ref["cut_id"].to_s == cut_id
    raise CompileError, "#{packet_id} Official Core primary image is not pixel PASS" unless source_cut.dig("primary_image", "status").to_s == "pass" && source_cut.dig("primary_image", "pixel_review", "verdict").to_s == "pass"
    projection = require_mapping(source.dig("screen_progression_map_projection", "projected_value"), "01 screen_progression_map_projection.projected_value")
    nodes = Array(projection["nodes"])
    node_index = nodes.index { |row| row.to_h["node_id"].to_s == source_cut["screen_progression_node_id"].to_s }
    raise CompileError, "#{packet_id} Official Core screen progression node is missing" unless node_index
    node = nodes.fetch(node_index)
    storyline_pointer = "/screen_progression_map_projection/projected_value/nodes/#{node_index}"
    storyline_version = source_cut["active_storyline_version_id"]
    section_id = source_cut.fetch("section_id")
    major_scene_id = source_cut.fetch("parent_major_scene_id")
    applicability = source_cut.fetch("member_visual_applicability")
    authority_status = "official_core_storyboard_authorized"
    cut_type = "official_core"
    parent_core_cut_id = cut_id
  end

  expected_context = {
    "section_id" => section_id,
    "major_scene_id" => major_scene_id,
    "active_storyline_version_id" => storyline_version,
    "screen_progression_node_id" => node.fetch("node_id"),
    "member_visual_applicability" => applicability,
    "source_core_slot_id" => context["source_core_slot_id"],
    "source_storyline_binding_ref" => {
      "json_pointer" => storyline_pointer,
      "value_sha256" => value_sha256(node)
    }
  }
  unless canonical_value(context) == canonical_value(expected_context)
    raise CompileError, "#{packet_id} cut_context must exact-copy the source Cut and screen-progression lineage"
  end
  unless packet["production_scope_id"].to_s.strip.length.positive? && packet["derivative_route_id"].to_s.strip.length.positive?
    raise CompileError, "#{packet_id} requires an explicit derivative route and production scope"
  end

  expected_attachments = generic_expected_attachments(mode, source, source_cut, context)
  attachments = require_array(packet["attachments"], "#{packet_id}.attachments")
  unless canonical_value(attachments.take(expected_attachments.length)) == canonical_value(expected_attachments)
    raise CompileError, "#{packet_id} attachments must exact-copy current-title Member Visuals first and the selected governing scene reference"
  end
  attachments.drop(expected_attachments.length).each_with_index do |attachment, extra_index|
    unless attachment["role"].to_s == "supporting_component_reference"
      raise CompileError, "#{packet_id} additional logical-role input must keep the supporting_component_reference transport role"
    end
    normalized = packet_attachment_from_source(
      attachment,
      order: expected_attachments.length + extra_index + 1,
      role: "supporting_component_reference",
      binding_id: require_nonempty(attachment["binding_id"], "#{packet_id} supporting binding_id"),
      asset_id: require_nonempty(attachment["asset_id"], "#{packet_id} supporting asset_id")
    )
    unless canonical_value(attachment) == canonical_value(normalized)
      raise CompileError, "#{packet_id} supporting logical-role attachment must exact-copy its locked path, hash, and order"
    end
  end
  reference_role_plan = validate_reference_role_plan!(
    packet["reference_role_plan"],
    attachments,
    applicability,
    section_id,
    packet_id
  )
  components, rendered = validate_generic_five_lines!(packet, mode)
  identity_ids = Array(components.dig("identity_reference_rule", "current_title_visual_bindings")).map(&:to_s)
  expected_identity_ids = attachments.select { |row| row["role"] == "current_title_member_visual" }.map { |row| row["asset_id"].to_s }
  raise CompileError, "#{packet_id} identity bindings differ from Member Visual attachments" unless identity_ids == expected_identity_ids

  receipt = require_mapping(packet["authoring_inspection_receipt"], "#{packet_id}.authoring_inspection_receipt")
  raise CompileError, "#{packet_id} source Cut inspection hash is stale" unless receipt["source_cut_contract_sha256"].to_s == source_cut_sha
  unless receipt["source_storyline_alignment_binding_sha256"].to_s == value_sha256(node)
    raise CompileError, "#{packet_id} source storyline inspection hash is stale"
  end
  expected_binding_ids = attachments.map { |row| row.fetch("binding_id") }
  expected_asset_ids = expected_identity_ids
  unless Array(receipt["inspected_visual_reference_binding_ids"]).map(&:to_s) == expected_binding_ids
    raise CompileError, "#{packet_id} inspection receipt does not exact-cover attachment order"
  end
  unless Array(receipt["inspected_current_title_asset_ids"]).map(&:to_s) == expected_asset_ids
    raise CompileError, "#{packet_id} inspection receipt does not exact-cover current-title inputs"
  end

  output_path, output_relative = resolve_repo_path(require_nonempty(packet["expected_output_path"], "#{packet_id}.expected_output_path"))
  run_root = source_path.dirname
  unless output_path.to_s.start_with?("#{run_root}#{File::SEPARATOR}")
    raise CompileError, "#{packet_id} expected output must remain inside the source run root"
  end
  execution = validate_generic_execution!(packet, attachments, run_execution_selection, output_relative)

  cut_pointer = {
    "cut_id" => cut_id,
    "cut_type" => cut_type,
    "section_id" => section_id,
    "major_scene_id" => major_scene_id,
    "source_path" => source_relative,
    "source_json_pointer" => pointer,
    "source_value_sha256" => source_cut_sha
  }
  cut_pointer["parent_core_cut_id"] = parent_core_cut_id if parent_core_cut_id
  {
    "packet_id" => packet_id,
    "prompt_profile" => "idol_one_cut_one_image.v1",
    "mode" => mode,
    "authority_status" => authority_status,
    "derivative_route_id" => packet.fetch("derivative_route_id"),
    "production_scope_id" => packet.fetch("production_scope_id"),
    "cut_pointer" => cut_pointer,
    "active_storyline_version_id" => storyline_version,
    "screen_progression_node_id" => node.fetch("node_id"),
    "source_sections" => [section_id],
    "execution_section_id" => section_id,
    "member_visual_applicability" => applicability,
    "authoring_model_profile_id" => packet.fetch("authoring_model_profile_id"),
    "execution" => execution,
    "five_line_components" => components,
    "rendered_five_lines" => deep_copy(rendered),
    "attachments" => deep_copy(attachments),
    "reference_role_plan" => reference_role_plan,
    "authoring_inspection_receipt" => deep_copy(receipt),
    "adoption_lineage" => deep_copy(packet.fetch("adoption_lineage")),
    "expected_output_path" => output_relative,
    "core_cut_id" => mode == "official_core" ? cut_id : nil,
    "local_trace" => {
      "compiler_version" => COMPILER_VERSION,
      "compiler_profile" => COMPILER_PROFILE,
      "source_artifact_sha256" => source_sha,
      "source_cut_value_sha256" => source_cut_sha,
      "source_storyline_binding_value_sha256" => value_sha256(node)
    },
    "visual_reference_bindings" => deep_copy(attachments),
    "compiled_prompt_block" => deep_copy(rendered),
    "export_contract" => {
      "expected_output_path" => output_relative,
      "request_unit" => "one_packet_one_request",
      "provider_neutral_profile" => "idol_one_cut_one_image.v1",
      "approval_state" => "not_inferred"
    },
    "status" => "draft"
  }.reject { |_key, value| value.nil? }
end

def compile_generic_document(delta, source_path, source_relative, source, source_sha)
  mode = delta.fetch("compile_target")
  run_execution_selection = require_mapping(delta["run_execution_selection"], "run_execution_selection")
  raise CompileError, "run execution selection must forbid provider/auth/model fallback" unless run_execution_selection["automatic_fallback"].to_s == "none"
  packets = require_array(delta["packets"], "packets").map do |packet|
    validate_generic_packet!(
      packet,
      mode: mode,
      source_path: source_path,
      source_relative: source_relative,
      source: source,
      source_sha: source_sha,
      run_execution_selection: run_execution_selection
    )
  end
  ids = packets.map { |packet| packet.fetch("packet_id") }
  raise CompileError, "packet translations contain duplicate packet ids" unless ids.uniq.length == ids.length
  section_shards = packets.group_by { |packet| packet.fetch("execution_section_id") }.map do |section_id, rows|
    {
      "section_id" => section_id,
      "packet_ids" => rows.map { |row| row.fetch("packet_id") },
      "status" => "draft"
    }
  end
  {
    "schema_version" => OUTPUT_SCHEMA_VERSION,
    "content_id" => delta.fetch("content_id"),
    "input_files" => {
      "source_cut_artifact" => source_relative,
      "source_cut_artifact_sha256" => source_sha,
      "compile_target" => mode
    },
    "status" => delta.dig("output", "status"),
    "prompt_profile" => "idol_one_cut_one_image.v1",
    "packet_policy" => {
      "unit" => "one_cut_one_image",
      "prompt_structure" => "exactly_five_natural_language_lines",
      "creative_authoring" => "human_or_assigned_model_only",
      "provider_transport" => "exact_bytes_and_locked_attachment_order_only",
      "fallback" => "none",
      "output_count" => 1
    },
    "run_execution_selection" => deep_copy(run_execution_selection),
    "prompt_packets" => packets,
    "section_shards" => section_shards,
    "review_surface" => {
      "recipient" => "creative_development_director",
      "pixel_review_required" => true,
      "mechanical_pass_is_creative_pass" => false
    },
    "open_questions" => Array(delta.dig("output", "open_questions"))
  }
end

def validate_active_packet_contract!(packet_spec, branch_cut:, member_lock:, bindings:, branch_hash:, compiled_prompt:, output_relative:, source_relative:, branch_pointer:, section_id:, section_cohort_id:, run_execution_selection:)
  unless packet_spec["mode"].to_s == "official_branch"
    raise CompileError, "#{packet_spec['packet_id']} 02B compile mode must be official_branch"
  end
  major_scene_id = require_nonempty(packet_spec["major_scene_id"], "packet.major_scene_id")
  unless major_scene_id.match?(/^MJ[0-9]{2,}[A-Z0-9_]*$/)
    raise CompileError, "#{packet_spec['packet_id']} major_scene_id must use MJxx"
  end

  rendered = require_mapping(packet_spec["rendered_five_lines"], "packet.rendered_five_lines")
  unless canonical_value(rendered) == canonical_value(compiled_prompt)
    raise CompileError, "#{packet_spec['packet_id']} rendered_five_lines must exact-copy the validated five-line prompt bytes"
  end
  unless rendered["full_prompt_text"].to_s.lines.length == 5 &&
         rendered["full_prompt_sha256"].to_s == Digest::SHA256.hexdigest(rendered["full_prompt_text"].to_s)
    raise CompileError, "#{packet_spec['packet_id']} rendered_five_lines must contain exactly five hash-bound lines"
  end
  %w[4K high\ quality high\ detail].each do |term|
    raise CompileError, "#{packet_spec['packet_id']} rendered prompt is missing #{term}" unless rendered["full_prompt_text"].include?(term)
  end

  components = require_mapping(packet_spec["five_line_components"], "packet.five_line_components")
  unless components["authoring_owner"].to_s == "human_or_assigned_model"
    raise CompileError, "#{packet_spec['packet_id']} five-line components require a human or assigned model author"
  end

  attachments = require_array(packet_spec["attachments"], "packet.attachments")
  expected_attachments = bindings.map do |binding|
    {
      "order" => binding["order"],
      "role" => binding["reference_scope"].to_s == "member_visual" ? "current_title_member_visual" : "governing_scene_or_sequence_reference",
      "binding_id" => binding["binding_id"],
      "asset_id" => binding["asset_id"],
      "actual_path" => binding["actual_path"],
      "sha256" => binding["sha256"],
      "pixel_inspection_status" => "passed",
      "locked" => true
    }
  end
  unless canonical_value(attachments) == canonical_value(expected_attachments)
    raise CompileError, "#{packet_spec['packet_id']} attachments must exact-copy all locked 02A visual bindings in Member-Visual-first order"
  end
  unless attachments.map { |row| row["order"] } == (1..attachments.length).to_a
    raise CompileError, "#{packet_spec['packet_id']} attachment order must be contiguous from 1"
  end
  reference_role_plan = validate_reference_role_plan!(
    packet_spec["reference_role_plan"],
    attachments,
    member_lock["member_visual_applicability"],
    section_id,
    packet_spec.fetch("packet_id")
  )
  unless packet_spec["section_cohort_id"].to_s == section_cohort_id.to_s
    raise CompileError, "#{packet_spec['packet_id']} section_cohort_id must exact-carry the section compile scope"
  end

  receipt = require_mapping(packet_spec["authoring_inspection_receipt"], "packet.authoring_inspection_receipt")
  unless receipt["source_cut_contract_sha256"].to_s == branch_hash
    raise CompileError, "#{packet_spec['packet_id']} source_cut_contract_sha256 is stale"
  end
  expected_storyline_sha = value_sha256(branch_cut.fetch("storyline_alignment_binding"))
  unless receipt["source_storyline_alignment_binding_sha256"].to_s == expected_storyline_sha
    raise CompileError, "#{packet_spec['packet_id']} source storyline alignment receipt is stale"
  end
  expected_binding_ids = bindings.map { |row| row["binding_id"].to_s }
  unless Array(receipt["inspected_visual_reference_binding_ids"]).map(&:to_s) == expected_binding_ids
    raise CompileError, "#{packet_spec['packet_id']} inspection receipt must exact-cover locked visual bindings"
  end

  execution = require_mapping(packet_spec["execution"], "packet.execution")
  begin
    IdolImageExecutionLaneContract.verify_execution_shape!(
      selection: run_execution_selection,
      execution: execution,
      attachment_count: attachments.length
    )
  rescue IdolImageExecutionLaneContract::ContractError => e
    raise CompileError, "#{packet_spec['packet_id']} #{e.message}"
  end
  unless execution["expected_output_path"].to_s == output_relative && execution["output_count"] == 1
    raise CompileError, "#{packet_spec['packet_id']} execution must preserve the exact one-output path"
  end
  unless execution["prompt_rewrite_policy"].to_s == "forbidden" && execution["automatic_fallback"].to_s == "none"
    raise CompileError, "#{packet_spec['packet_id']} execution must forbid prompt rewrite and provider/auth/model fallback"
  end

  {
    "prompt_profile" => "idol_one_cut_one_image.v1",
    "mode" => "official_branch",
    "authority_status" => "branch_generation_authorized",
    "derivative_route_id" => packet_spec["derivative_route_id"],
    "production_scope_id" => packet_spec["production_scope_id"],
    "cut_pointer" => {
      "cut_id" => branch_cut["branch_cut_id"],
      "cut_type" => "branch",
      "section_id" => section_id,
      "major_scene_id" => major_scene_id,
      "parent_core_cut_id" => packet_spec.dig("parent_core_cut_ref", "core_cut_id"),
      "source_path" => source_relative,
      "source_json_pointer" => branch_pointer,
      "source_value_sha256" => branch_hash
    },
    "active_storyline_version_id" => packet_spec["active_storyline_version_id"],
    "screen_progression_node_id" => packet_spec["screen_progression_node_id"],
    "section_cohort_id" => section_cohort_id,
    "member_visual_applicability" => member_lock["member_visual_applicability"],
    "authoring_model_profile_id" => packet_spec["authoring_model_profile_id"],
    "execution" => deep_copy(execution),
    "five_line_components" => deep_copy(components),
    "rendered_five_lines" => deep_copy(rendered),
    "attachments" => deep_copy(attachments),
    "reference_role_plan" => reference_role_plan,
    "authoring_inspection_receipt" => deep_copy(receipt),
    "adoption_lineage" => deep_copy(packet_spec["adoption_lineage"]),
    "expected_output_path" => output_relative
  }
end

def validate_packet_spec!(
  packet_spec,
  source:,
  source_sha:,
  shard:,
  section_id:,
  section_cohort_id:,
  selected_core_cuts:,
  core_position:,
  core_cut:,
  core_cut_index:,
  branch_cut:,
  branch_index:,
  run_execution_selection:
)
  packet_id = require_nonempty(packet_spec["packet_id"], "packet.packet_id")
  unless packet_id == branch_cut["packet_id"].to_s
    raise CompileError, "#{packet_id} does not match source Branch-Cut packet_id"
  end

  expected_core_pointer = "/master_storyboard/#{core_cut_index}"
  parent_ref = require_mapping(packet_spec["parent_core_cut_ref"], "#{packet_id}.parent_core_cut_ref")
  unless parent_ref["core_cut_id"].to_s == core_cut_id(core_cut)
    raise CompileError, "#{packet_id} parent Core-Cut id mismatch"
  end
  raise CompileError, "#{packet_id} parent pointer mismatch" unless parent_ref["json_pointer"].to_s == expected_core_pointer
  raise CompileError, "#{packet_id} parent hash mismatch" unless parent_ref["value_sha256"].to_s == value_sha256(core_cut)

  expected_branch_pointer = "#{expected_core_pointer}/compile_seed/branch_cuts/#{branch_index}"
  branch_ref = require_mapping(packet_spec["branch_cut_ref"], "#{packet_id}.branch_cut_ref")
  unless branch_ref["branch_cut_id"].to_s == branch_cut["branch_cut_id"].to_s
    raise CompileError, "#{packet_id} Branch-Cut id mismatch"
  end
  raise CompileError, "#{packet_id} Branch-Cut pointer mismatch" unless branch_ref["json_pointer"].to_s == expected_branch_pointer
  branch_hash = value_sha256(branch_cut)
  raise CompileError, "#{packet_id} Branch-Cut hash mismatch" unless branch_ref["value_sha256"].to_s == branch_hash

  revision = require_mapping(packet_spec["direct_prompt_revision"], "#{packet_id}.direct_prompt_revision")
  unless revision["source_02a_branch_cut_lock_sha256"].to_s == branch_hash
    raise CompileError, "#{packet_id} direct prompt revision is bound to stale 02A Branch-Cut truth"
  end
  context, context_sha = validate_same_section_context!(
    revision["same_section_context"],
    source: source,
    shard: shard,
    section_id: section_id,
    selected_core_cuts: selected_core_cuts,
    core_position: core_position,
    current_branch_cut: branch_cut,
    branch_position: branch_index
  )
  storyline_lock, storyline_binding_sha = validate_storyline_authoring_binding!(
    revision,
    source: source,
    shard: shard,
    branch_cut: branch_cut
  )
  member_lock, bindings, = validate_member_visuals!(branch_cut)
  validate_authoring_inspection_receipt!(
    revision,
    branch_cut,
    bindings,
    storyline_binding_sha
  )
  compiled_prompt, = validate_prompt_blueprint!(revision, member_lock["member_visual_reference_policy"])

  output_revision = deep_copy(revision)
  output_revision.delete("same_section_context")
  expected_output_path = require_nonempty(packet_spec["expected_output_path"], "#{packet_id}.expected_output_path")
  output_path, output_relative = resolve_repo_path(expected_output_path)
  source_run_root = resolve_repo_path(source.fetch("__source_path__")).first.dirname
  unless output_path.to_s.start_with?("#{source_run_root}#{File::SEPARATOR}")
    raise CompileError, "#{packet_id} expected output must remain inside the source 02A run root"
  end

  active_contract = validate_active_packet_contract!(
    packet_spec,
    branch_cut: branch_cut,
    member_lock: member_lock,
    bindings: bindings,
    branch_hash: branch_hash,
    compiled_prompt: compiled_prompt,
    output_relative: output_relative,
    source_relative: source.fetch("__source_path__"),
    branch_pointer: expected_branch_pointer,
    section_id: section_id,
    section_cohort_id: section_cohort_id,
    run_execution_selection: run_execution_selection
  )

  active_contract.merge(
    "packet_id" => packet_id,
    "branch_cut_id" => branch_cut["branch_cut_id"],
    "core_cut_id" => core_cut_id(core_cut),
    "source_sections" => [section_id],
    "execution_section_id" => section_id,
    "time_range" => core_time_range(core_cut),
    "status" => "draft",
    "local_trace" => {
      "compiler_version" => COMPILER_VERSION,
      "compiler_profile" => COMPILER_PROFILE,
      "source_02a_artifact_sha256" => source_sha,
      "source_parent_core_cut_value_sha256" => value_sha256(core_cut),
      "source_branch_cut_value_sha256" => branch_hash,
      "source_storyline_alignment_binding_sha256" => storyline_binding_sha,
      "direct_prompt_revision_sha256" => value_sha256(output_revision),
      "member_visual_inputs_sha256" => value_sha256(member_lock["selected_assets"]),
      "visual_reference_bindings_sha256" => value_sha256(bindings),
      "same_section_context_sha256" => context_sha
    },
    "same_section_context" => context,
    "branch_cut_lock" => deep_copy(branch_cut),
    "storyline_alignment_lock" => storyline_lock,
    "member_visual_lock" => member_lock,
    "visual_reference_bindings" => deep_copy(bindings),
    "direct_prompt_revision" => output_revision,
    "compiled_prompt_block" => compiled_prompt,
    "export_contract" => {
      "expected_output_path" => output_relative,
      "request_unit" => "one_packet_one_request",
      "provider_neutral_profile" => "idol_one_cut_one_image.v1",
      "approval_state" => "not_inferred"
    }
  )
end

def expected_output_context(
  source,
  shard,
  section_id,
  selected_core_cuts,
  core_position,
  branch_cut,
  branch_position
)
  current_core_cut, = selected_core_cuts.fetch(core_position)
  branch_cuts = Array(current_core_cut.dig("compile_seed", "branch_cuts"))
  previous_branch = branch_position.zero? ? nil : branch_cuts.fetch(branch_position - 1)
  next_branch = branch_position == branch_cuts.length - 1 ? nil : branch_cuts.fetch(branch_position + 1)
  previous_core_pair = core_position.zero? ? nil : selected_core_cuts.fetch(core_position - 1)
  next_core_pair = core_position == selected_core_cuts.length - 1 ? nil : selected_core_cuts.fetch(core_position + 1)
  context_sha = Idol02AStoryboardContract.same_section_context_sha256(
    source,
    shard,
    selected_core_cuts.map(&:first),
    core_position,
    branch_cut,
    branch_position
  )
  {
    "policy" => "current_branch_plus_parent_core_immediate_branch_siblings_and_immediate_previous_and_next_core_cuts_in_same_section_only",
    "section_id" => section_id,
    "current_core_cut_id" => core_cut_id(current_core_cut),
    "current_branch_cut_id" => branch_cut["branch_cut_id"],
    "previous_branch_cut" => previous_branch && {
      "branch_cut_id" => previous_branch["branch_cut_id"],
      "value_sha256" => value_sha256(previous_branch)
    },
    "next_branch_cut" => next_branch && {
      "branch_cut_id" => next_branch["branch_cut_id"],
      "value_sha256" => value_sha256(next_branch)
    },
    "previous_core_cut" => previous_core_pair && {
      "core_cut_id" => core_cut_id(previous_core_pair.first),
      "value_sha256" => value_sha256(
        Idol02AStoryboardContract.core_cut_context_projection(previous_core_pair.first)
      )
    },
    "next_core_cut" => next_core_pair && {
      "core_cut_id" => core_cut_id(next_core_pair.first),
      "value_sha256" => value_sha256(
        Idol02AStoryboardContract.core_cut_context_projection(next_core_pair.first)
      )
    },
    "first_core_cut_boundary_rule" => "use_current_section_entry_continuity_when_previous_core_cut_is_null",
    "last_core_cut_boundary_rule" => "use_current_section_exit_continuity_when_next_core_cut_is_null",
    "context_value_sha256" => context_sha
  }
end

def validate_carry_forward_source!(carry, source:, shard:, section_id:)
  document = carry.fetch("document")
  raise CompileError, "carry-forward source must be an approved 02B artifact" unless document["status"].to_s == "approved"
  raise CompileError, "carry-forward source content_id differs" unless document["content_id"].to_s == source["content_id"].to_s

  prompt_shard = Array(document["section_shards"]).find do |row|
    row.is_a?(Hash) &&
      row["shard_id"].to_s == shard["shard_id"].to_s &&
      row["section_id"].to_s == section_id
  end
  raise CompileError, "carry-forward source has no matching section shard" unless prompt_shard
  unless Array(prompt_shard["core_cut_ids"]).map(&:to_s) == Array(shard["core_cut_ids"]).map(&:to_s)
    raise CompileError, "carry-forward section Core-Cut ids differ from current 02A"
  end
  lineage = require_mapping(prompt_shard["local_lineage"], "carry-forward section local_lineage")
  unless lineage["contract_version"].to_s == Idol02AStoryboardContract::LOCAL_LINEAGE_VERSION
    raise CompileError, "carry-forward section local lineage is inactive"
  end
  unless lineage["source_02a_section_invariants_sha256"].to_s ==
         Idol02AStoryboardContract.section_invariant_sha256(source, shard)
    raise CompileError, "carry-forward section invariants changed; recompile the full section"
  end
  unless lineage["entry_boundary_sha256"].to_s == Idol02AStoryboardContract.boundary_sha256(shard, "entry") &&
         lineage["exit_boundary_sha256"].to_s == Idol02AStoryboardContract.boundary_sha256(shard, "exit")
    raise CompileError, "carry-forward section boundary changed; recompile the full section"
  end
  [prompt_shard, lineage]
end

def validate_carried_packet!(
  packet,
  prior_state:,
  source:,
  shard:,
  section_id:,
  selected_core_cuts:,
  core_position:,
  core_cut:,
  branch_cut:,
  branch_position:
)
  packet_id = branch_cut["packet_id"].to_s
  raise CompileError, "carry-forward packet #{packet_id} is missing" unless packet.is_a?(Hash)
  raise CompileError, "#{packet_id} was not previously approved" unless packet["status"].to_s == "approved"
  unless prior_state.is_a?(Hash) && prior_state["packet_id"].to_s == packet_id
    raise CompileError, "#{packet_id} has no exact prior local-lineage state"
  end
  unless prior_state["packet_value_sha256"].to_s == value_sha256(packet)
    raise CompileError, "#{packet_id} prior packet value hash is stale"
  end

  branch_sha = value_sha256(branch_cut)
  unless prior_state["source_02a_branch_cut_value_sha256"].to_s == branch_sha &&
         packet.dig("local_trace", "source_branch_cut_value_sha256").to_s == branch_sha &&
         packet.dig("direct_prompt_revision", "source_02a_branch_cut_lock_sha256").to_s == branch_sha
    raise CompileError, "#{packet_id} Branch Cut changed and must be supplied in this delta"
  end
  unless canonical_value(packet["branch_cut_lock"]) == canonical_value(branch_cut)
    raise CompileError, "#{packet_id} Branch-Cut lock changed and must be supplied in this delta"
  end
  storyline_lock, storyline_binding_sha = validate_storyline_authoring_binding!(
    packet["direct_prompt_revision"],
    source: source,
    shard: shard,
    branch_cut: branch_cut
  )
  unless prior_state["source_storyline_alignment_binding_sha256"].to_s == storyline_binding_sha &&
         packet.dig("local_trace", "source_storyline_alignment_binding_sha256").to_s == storyline_binding_sha &&
         canonical_value(packet["storyline_alignment_lock"]) == canonical_value(storyline_lock)
    raise CompileError, "#{packet_id} storyline lineage changed and must be supplied in this delta"
  end

  core_context_sha = value_sha256(Idol02AStoryboardContract.core_cut_context_projection(core_cut))
  unless prior_state["source_core_cut_context_value_sha256"].to_s == core_context_sha
    raise CompileError, "#{packet_id} Core-Cut context changed and must be supplied in this delta"
  end
  expected_context = expected_output_context(
    source,
    shard,
    section_id,
    selected_core_cuts,
    core_position,
    branch_cut,
    branch_position
  )
  unless prior_state["source_same_section_context_sha256"].to_s == expected_context["context_value_sha256"].to_s &&
         canonical_value(packet["same_section_context"]) == canonical_value(expected_context)
    raise CompileError, "#{packet_id} same-section neighborhood changed and must be supplied in this delta"
  end

  member_lock, bindings, = validate_member_visuals!(branch_cut)
  unless canonical_value(packet["member_visual_lock"]) == canonical_value(member_lock) &&
         canonical_value(packet["visual_reference_bindings"]) == canonical_value(bindings)
    raise CompileError, "#{packet_id} visual input set changed and must be supplied in this delta"
  end
  expected_attachments = bindings.map do |binding|
    {
      "order" => binding["order"],
      "role" => binding["reference_scope"].to_s == "member_visual" ? "current_title_member_visual" : "governing_scene_or_sequence_reference",
      "binding_id" => binding["binding_id"],
      "asset_id" => binding["asset_id"],
      "actual_path" => binding["actual_path"],
      "sha256" => binding["sha256"],
      "pixel_inspection_status" => "passed",
      "locked" => true
    }
  end
  unless canonical_value(packet["attachments"]) == canonical_value(expected_attachments)
    raise CompileError, "#{packet_id} attachments changed and must be supplied in this delta"
  end
  validate_authoring_inspection_receipt!(
    packet["direct_prompt_revision"],
    branch_cut,
    bindings,
    storyline_binding_sha
  )
  unless packet.dig("local_trace", "direct_prompt_revision_sha256").to_s ==
         value_sha256(packet["direct_prompt_revision"])
    raise CompileError, "#{packet_id} direct prompt revision trace is stale"
  end
  compiled_prompt, = validate_prompt_blueprint!(
    packet["direct_prompt_revision"],
    member_lock["member_visual_reference_policy"]
  )
  unless canonical_value(packet["compiled_prompt_block"]) == canonical_value(compiled_prompt)
    raise CompileError, "#{packet_id} compiled prompt integrity is stale"
  end
  unless canonical_value(packet["rendered_five_lines"]) == canonical_value(packet["compiled_prompt_block"])
    raise CompileError, "#{packet_id} rendered_five_lines differs from compiled_prompt_block"
  end
  unless packet["core_cut_id"].to_s == core_cut_id(core_cut) &&
         packet["branch_cut_id"].to_s == branch_cut["branch_cut_id"].to_s &&
         packet["execution_section_id"].to_s == section_id &&
         Array(packet["source_sections"]).map(&:to_s) == [section_id] &&
         packet["time_range"].to_s == core_time_range(core_cut).to_s
    raise CompileError, "#{packet_id} section, Core Cut, Branch Cut, or timing ownership changed"
  end
  deep_copy(packet)
end

def packet_lineage_state(packet, core_cut:, branch_cut:, context_sha:, state:, source_section_artifact: nil)
  row = {
    "packet_id" => packet.fetch("packet_id"),
    "state" => state,
    "packet_value_sha256" => value_sha256(packet),
    "source_02a_branch_cut_value_sha256" => value_sha256(branch_cut),
    "source_storyline_alignment_binding_sha256" => value_sha256(branch_cut.fetch("storyline_alignment_binding")),
    "source_core_cut_context_value_sha256" => value_sha256(Idol02AStoryboardContract.core_cut_context_projection(core_cut)),
    "source_same_section_context_sha256" => context_sha
  }
  row["source_section_artifact"] = source_section_artifact if source_section_artifact
  row
end

def compile_document(delta, source_path, source, source_sha, evidence, carry_forward = nil)
  source = deep_copy(source)
  source["__source_path__"] = repo_relative(source_path)
  run_execution_selection = require_mapping(delta["run_execution_selection"], "run_execution_selection")
  unless run_execution_selection["automatic_fallback"].to_s == "none"
    raise CompileError, "run execution selection must forbid provider/auth/model fallback"
  end
  scope = require_mapping(delta["section_compile_scope"], "section_compile_scope")
  shard, selected_core_cuts, section_id = validate_scope!(source, scope)
  section_cohort_id = require_nonempty(scope["section_cohort_id"], "section_compile_scope.section_cohort_id")

  expected_branches = []
  selected_core_cuts.each_with_index do |(core_cut, core_cut_index), core_position|
    branch_cuts = require_array(
      core_cut.dig("compile_seed", "branch_cuts"),
      "#{core_cut_id(core_cut)}.compile_seed.branch_cuts"
    )
    branch_cuts.each_with_index do |branch_cut, branch_index|
      expected_branches << [
        core_position,
        core_cut,
        core_cut_index,
        branch_cut,
        branch_index
      ]
    end
  end
  packet_specs = require_array(delta["packets"], "packets")
  expected_packet_ids = expected_branches.map do |_core_position, _core_cut, _core_index, branch_cut, _branch_index|
    branch_cut["packet_id"].to_s
  end
  supplied_ids = packet_specs.map { |packet| packet.to_h["packet_id"].to_s }
  raise CompileError, "packet translations contain duplicate packet ids" unless supplied_ids.uniq.length == supplied_ids.length
  unless supplied_ids == expected_packet_ids.select { |packet_id| supplied_ids.include?(packet_id) }
    raise CompileError, "packet translations must follow current 02A packet order"
  end

  carry_shard = nil
  carry_lineage = nil
  carry_packet_by_id = {}
  carry_state_by_id = {}
  if carry_forward
    carry_shard, carry_lineage = validate_carry_forward_source!(
      carry_forward,
      source: source,
      shard: shard,
      section_id: section_id
    )
    carry_packet_by_id = Array(carry_forward.fetch("document")["prompt_packets"]).select do |packet|
      packet.is_a?(Hash) && packet["execution_section_id"].to_s == section_id
    end.to_h { |packet| [packet["packet_id"].to_s, packet] }
    carry_state_by_id = Array(carry_lineage["packet_states"]).to_h do |state|
      [state.to_h["packet_id"].to_s, state.to_h]
    end
  elsif supplied_ids != expected_packet_ids
    raise CompileError, "partial packet translation requires carry_forward_source_02b"
  end
  supplied_by_id = packet_specs.to_h { |packet| [packet["packet_id"].to_s, packet] }

  packets = []
  packet_states = []
  expected_branches.each do |core_position, core_cut, core_cut_index, branch_cut, branch_index|
    packet_id = branch_cut["packet_id"].to_s
    packet_spec = supplied_by_id[packet_id]
    if packet_spec
      packet = validate_packet_spec!(
        packet_spec,
        source: source,
        source_sha: source_sha,
        shard: shard,
        section_id: section_id,
        section_cohort_id: section_cohort_id,
        selected_core_cuts: selected_core_cuts,
        core_position: core_position,
        core_cut: core_cut,
        core_cut_index: core_cut_index,
        branch_cut: branch_cut,
        branch_index: branch_index,
        run_execution_selection: run_execution_selection
      )
      state = "compiled"
      source_section_artifact = nil
    else
      packet = validate_carried_packet!(
        carry_packet_by_id[packet_id],
        prior_state: carry_state_by_id[packet_id],
        source: source,
        shard: shard,
        section_id: section_id,
        selected_core_cuts: selected_core_cuts,
        core_position: core_position,
        core_cut: core_cut,
        branch_cut: branch_cut,
        branch_position: branch_index
      )
      state = "carried_forward"
      source_section_artifact = {
        "path" => carry_forward.fetch("relative"),
        "artifact_sha256" => carry_forward.fetch("sha256")
      }
    end
    context_sha = Idol02AStoryboardContract.same_section_context_sha256(
      source,
      shard,
      selected_core_cuts.map(&:first),
      core_position,
      branch_cut,
      branch_index
    )
    packets << packet
    packet_states << packet_lineage_state(
      packet,
      core_cut: core_cut,
      branch_cut: branch_cut,
      context_sha: context_sha,
      state: state,
      source_section_artifact: source_section_artifact
    )
  end

  input_files = {
    "master_storyboard" => repo_relative(source_path),
    "master_storyboard_sha256" => source_sha,
    "storyboard_context_review" => evidence.fetch("storyboard_context_review_relative"),
    "storyboard_context_review_sha256" => evidence.fetch("storyboard_context_review_sha256"),
    "section_compile_shard_id" => scope.fetch("shard_id"),
    "section_compile_scope_sha256" => value_sha256(scope)
  }
  if evidence["founder_direct_intervention_relative"]
    input_files["founder_direct_intervention"] = evidence["founder_direct_intervention_relative"]
    input_files["founder_direct_intervention_sha256"] = evidence["founder_direct_intervention_sha256"]
  end

  {
    "schema_version" => OUTPUT_SCHEMA_VERSION,
    "content_id" => delta["content_id"],
    "input_files" => input_files,
    "status" => delta.dig("output", "status"),
    "prompt_profile" => "idol_one_cut_one_image.v1",
    "packet_policy" => {
      "unit" => "one_cut_one_image",
      "prompt_structure" => "exactly_five_natural_language_lines",
      "creative_authoring" => "human_or_assigned_model_only",
      "provider_transport" => "exact_bytes_and_locked_attachment_order_only",
      "fallback" => "none",
      "output_count" => 1
    },
    "run_execution_selection" => deep_copy(run_execution_selection),
    "prompt_packets" => packets,
    "section_shards" => [
      {
        "shard_id" => scope.fetch("shard_id"),
        "section_cohort_id" => scope.fetch("section_cohort_id"),
        "section_id" => section_id,
        "core_cut_ids" => scope.fetch("core_cut_ids"),
        "packet_ids" => packets.map { |packet| packet.fetch("packet_id") },
        "status" => "draft",
        "review_order" => "core_cut_then_branch_cut_sequence",
        "canonical_merge_policy" => "lossless_ordered_merge_after_section_founder_review_pass",
        "local_lineage" => {
          "contract_version" => Idol02AStoryboardContract::LOCAL_LINEAGE_VERSION,
          "source_02a_section_invariants_sha256" => Idol02AStoryboardContract.section_invariant_sha256(source, shard),
          "entry_boundary_sha256" => Idol02AStoryboardContract.boundary_sha256(shard, "entry"),
          "exit_boundary_sha256" => Idol02AStoryboardContract.boundary_sha256(shard, "exit"),
          "packet_states" => packet_states
        }
      }
    ],
    "review_surface" => {
      "recipient" => "creative_development_director",
      "pixel_review_required" => true,
      "mechanical_pass_is_creative_pass" => false
    },
    "open_questions" => Array(delta.dig("output", "open_questions"))
  }
end

options = {
  output: nil,
  format: nil,
  verify_only: false,
  digest_source: nil,
  pointer: nil
}

parser = OptionParser.new do |opts|
  opts.banner = "usage: ruby scripts/idol_prompt_packet_compile.rb DELTA.yaml [--output PATH] [--format yaml|json] [--verify-only]\n       ruby scripts/idol_prompt_packet_compile.rb --digest-source PATH [--pointer JSON_POINTER]"
  opts.on("--output PATH", "Write the noncanonical 02B section artifact") { |value| options[:output] = Pathname.new(value).expand_path }
  opts.on("--format FORMAT", "yaml or json; inferred from output extension") { |value| options[:format] = value }
  opts.on("--verify-only", "Compile and validate in memory without writing") { options[:verify_only] = true }
  opts.on("--digest-source PATH", "Print artifact and optional canonical JSON-pointer value SHA-256") { |value| options[:digest_source] = Pathname.new(value).expand_path }
  opts.on("--pointer JSON_POINTER", "JSON pointer used with --digest-source") { |value| options[:pointer] = value }
end

begin
  parser.parse!
  if options[:digest_source]
    path = options[:digest_source]
    raise CompileError, "digest source not found: #{path}" unless path.file?
    document = load_structured(path)
    result = {
      "path" => repo_relative(path),
      "artifact_sha256" => file_sha256(path)
    }
    if options[:pointer]
      value = json_pointer_get(document, options[:pointer])
      result["json_pointer"] = options[:pointer]
      result["value_sha256"] = value_sha256(value)
    end
    puts JSON.pretty_generate(result)
    exit 0
  end

  delta_argument = ARGV.shift
  raise CompileError, parser.to_s if delta_argument.to_s.empty?
  raise CompileError, "unexpected arguments: #{ARGV.join(' ')}" unless ARGV.empty?

  delta_path = Pathname.new(delta_argument).expand_path
  raise CompileError, "delta file not found: #{delta_path}" unless delta_path.file?
  validate_schema_file(DELTA_SCHEMA, delta_path, "02B translation input")
  delta = load_structured(delta_path)
  raise CompileError, "only prompt-packet delta version #{DELTA_SCHEMA_VERSION} is active" unless delta["schema_version"].to_s == DELTA_SCHEMA_VERSION
  raise CompileError, "compiler profile is not active" unless delta["compiler_profile"].to_s == COMPILER_PROFILE

  compile_target = require_nonempty(delta["compile_target"], "compile_target")
  if compile_target == "official_branch"
    source_path, source_relative, source, source_sha = validate_artifact_ref(
      delta["source_02a"],
      "source_02a",
      expected_schema: Idol02AStoryboardContract::ACTIVE_SCHEMA_VERSION
    )
    validate_schema_file(STORYBOARD_SCHEMA, source_path, "source 02A storyboard")
    run_active_validator!(STORYBOARD_VALIDATOR, source_path, "source 02A")
    raise CompileError, "content_id does not match source 02A" unless delta["content_id"].to_s == source["content_id"].to_s

    readiness = require_mapping(delta["readiness_evidence"], "readiness_evidence")
    _review_path, review_relative, _review, review_sha = validate_evidence(
      readiness["storyboard_context_review"],
      "readiness_evidence.storyboard_context_review",
      content_id: delta["content_id"].to_s,
      source_02a_path: source_path,
      source_02a_sha: source_sha
    )
    evidence = {
      "storyboard_context_review_relative" => review_relative,
      "storyboard_context_review_sha256" => review_sha
    }
    if readiness["founder_direct_intervention"]
      _path, relative, _document, digest = validate_evidence(
        readiness["founder_direct_intervention"],
        "readiness_evidence.founder_direct_intervention",
        content_id: delta["content_id"].to_s,
        source_02a_path: source_path,
        source_02a_sha: source_sha
      )
      evidence["founder_direct_intervention_relative"] = relative
      evidence["founder_direct_intervention_sha256"] = digest
    end

    carry_forward = nil
    if delta["carry_forward_source_02b"]
      carry_path, carry_relative, carry_document, carry_sha = validate_artifact_ref(
        delta["carry_forward_source_02b"],
        "carry_forward_source_02b"
      )
      raise CompileError, "carry-forward source must use prompt packet schema #{OUTPUT_SCHEMA_VERSION}" unless carry_document["schema_version"].to_s == OUTPUT_SCHEMA_VERSION
      validate_schema_file(PROMPT_PACKET_SCHEMA, carry_path, "carry-forward 02B artifact")
      carry_forward = {
        "path" => carry_path,
        "relative" => carry_relative,
        "document" => carry_document,
        "sha256" => carry_sha
      }
    end
    compiled = compile_document(delta, source_path, source, source_sha, evidence, carry_forward)
  else
    unless %w[fp_hero_core official_core].include?(compile_target)
      raise CompileError, "compile_target must be fp_hero_core, official_core, or official_branch"
    end
    expected_schema = compile_target == "fp_hero_core" ? "front-planning-readiness.v17" : "3.0"
    source_path, source_relative, source, source_sha = validate_artifact_ref(
      delta["source_cut_artifact"],
      "source_cut_artifact",
      expected_schema: expected_schema
    )
    schema = compile_target == "fp_hero_core" ? FRONT_PLANNING_SCHEMA : DIRECTION_SCHEMA
    validator = compile_target == "fp_hero_core" ? FRONT_PLANNING_VALIDATOR : DIRECTION_VALIDATOR
    label = compile_target == "fp_hero_core" ? "source Front Planning" : "source 01 Official Core storyboard"
    validate_schema_file(schema, source_path, label)
    run_active_validator!(validator, source_path, label)
    raise CompileError, "content_id does not match #{label}" unless delta["content_id"].to_s == source["content_id"].to_s
    compiled = compile_generic_document(delta, source_path, source_relative, source, source_sha)
  end

  if !options[:verify_only] && options[:output]&.basename&.to_s == "02B-prompt-packets.yaml"
    raise CompileError, "#{COMPILER_VERSION} emits a noncanonical section artifact; merge only Founder-passed section artifacts separately"
  end

  validate_compiled_schema(compiled)

  if options[:verify_only]
    puts JSON.pretty_generate(
      "verified" => true,
      "compiler_version" => COMPILER_VERSION,
      "compiler_profile" => COMPILER_PROFILE,
      "output_format" => OUTPUT_FORMAT,
      "section_id" => compiled.dig("section_shards", 0, "section_id"),
      "compile_target" => compile_target,
      "core_cut_count" => Array(compiled.dig("section_shards", 0, "core_cut_ids")).length,
      "packet_count" => compiled.fetch("prompt_packets").length,
      "member_visual_packet_count" => compiled.fetch("prompt_packets").count { |packet| packet["member_visual_applicability"] == "meaningfully_visible" },
      "scene_reference_binding_count" => compiled.fetch("prompt_packets").sum { |packet| packet.fetch("attachments").count { |row| row["role"] == "governing_scene_or_sequence_reference" } },
      "five_line_prompt_count" => compiled.fetch("prompt_packets").count { |packet| packet.dig("compiled_prompt_block", "full_prompt_text").to_s.lines.length == 5 },
      "same_section_context_count" => compiled.fetch("prompt_packets").count { |packet| packet["same_section_context"].is_a?(Hash) },
      "compiled_packet_count" => compile_target == "official_branch" ? Array(compiled.dig("section_shards", 0, "local_lineage", "packet_states")).count { |row| row["state"] == "compiled" } : compiled.fetch("prompt_packets").length,
      "carried_forward_packet_count" => Array(compiled.dig("section_shards", 0, "local_lineage", "packet_states")).count { |row| row["state"] == "carried_forward" },
      "separate_face_input_count" => 0,
      "temporal_camera_prompt_count" => 0,
      "compiled_value_sha256" => value_sha256(compiled),
      "output_written" => false
    )
    warn "verified #{compiled.fetch('prompt_packets').length} packet(s); no output written"
    exit 0
  end

  format = options[:format]
  format ||= options[:output]&.extname&.downcase == ".json" ? "json" : "yaml"
  raise CompileError, "format must be yaml or json" unless %w[yaml json].include?(format)
  serialized = format == "json" ? "#{JSON.pretty_generate(compiled)}\n" : YAML.dump(compiled)

  if options[:output]
    options[:output].dirname.mkpath
    options[:output].write(serialized)
    warn "compiled #{compiled.fetch('prompt_packets').length} packet(s) to #{options[:output]}"
  else
    print serialized
  end
rescue CompileError, KeyError => e
  warn "prompt packet compile failed: #{e.message}"
  exit 1
end
