#!/usr/bin/env ruby
# frozen_string_literal: true

require "pathname"
require "set"
require "csv"
require "digest"
require "open3"
require "rbconfig"
require "fileutils"
require "tmpdir"
require "yaml"
require_relative "lib/idol_video_prompt_section_qa_contract"
require_relative "lib/idol_03v_source_discovery"
require_relative "lib/idol_03v_language_contract"

self_test_v2_control = ARGV.delete("--self-test-v2-control")
self_test_v3_projection = ARGV.delete("--self-test-v3-projection")
self_test_v3_review = ARGV.delete("--self-test-v3-review")
index_path = unless self_test_v2_control || self_test_v3_projection || self_test_v3_review
               ARGV.fetch(0) do
                 warn "usage: scripts/validate_video_prompt_index.rb PATH_TO_video-prompt-index.yaml [PATH_TO_03-review.yaml] [--self-test-v2-control|--self-test-v3-projection|--self-test-v3-review]"
                 exit 2
               end
             end

root = Pathname.new(Dir.pwd)
errors = []
warnings = []

def readable_path?(path)
  path && !path.to_s.empty? && File.file?(path.to_s)
end

def resolve_path(path, root)
  return nil if path.nil? || path.to_s.strip.empty?

  raw = Pathname.new(path.to_s)
  raw.absolute? ? raw.cleanpath : (root + raw).cleanpath
end

def normalized_existing_path(path, root)
  resolved = resolve_path(path, root)
  return nil unless resolved && readable_path?(resolved)

  resolved.realpath.to_s
rescue Errno::ENOENT
  nil
end

def validate_video_prompt_manifest_semantics(path_value, root, cache, errors, label)
  resolved = resolve_path(path_value, root)
  return unless readable_path?(resolved)

  key = resolved.expand_path.to_s
  result = cache[key]
  unless result
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      File.join(__dir__, "validate_video_prompt_manifest.rb"),
      resolved.to_s,
      "--root",
      root.to_s,
      chdir: root.to_s
    )
    result = {success: status.success?, detail: [stderr, stdout].reject { |value| value.to_s.strip.empty? }.join(" ").strip}
    cache[key] = result
  end
  errors << "#{label}: 03V manifest semantic validation failed: #{result[:detail]}" unless result[:success]
end

def blank?(value)
  value.nil? || value.to_s.strip.empty?
end

def dir_path?(path)
  path && !path.to_s.empty? && File.directory?(path.to_s)
end

def validate_storyboard_reference_copy(label, image_index, path, semantic_fields, errors)
  references = Array(semantic_fields["storyboard_references"])
  reference = references[image_index - 1]
  unless reference.is_a?(Hash)
    errors << "#{label}: authoritative storyboard reference @image#{image_index} is missing"
    return
  end
  unless reference["reference_tag"].to_s == "@image#{image_index}"
    errors << "#{label}: authoritative storyboard reference order does not match @image#{image_index}"
  end

  expected_sha = reference["sha256"].to_s
  unless expected_sha.match?(/\A[a-f0-9]{64}\z/)
    errors << "#{label}: authoritative @image#{image_index} SHA-256 is missing or invalid"
    return
  end
  return unless readable_path?(path)

  actual_sha = Digest::SHA256.file(path.to_s).hexdigest
  errors << "#{label}: @image#{image_index} does not match authoritative storyboard/source SHA-256" unless actual_sha == expected_sha
end

def path_in_segment?(path, segment)
  path.to_s.split(File::SEPARATOR).include?(segment)
end

def upload_ready_folder_for(surface, prompt, idx, root)
  return "" if blank?(surface) || !prompt.is_a?(Hash)

  explicit = prompt["upload_ready_folder"].to_s
  explicit_path = resolve_path(explicit, root)
  return explicit if !blank?(explicit) && dir_path?(explicit_path)

  section = prompt["section"].to_s
  packet_id = prompt["packet_id"].to_s
  return "" if section.empty? || packet_id.empty?

  expected = File.join(surface, "#{format('%03d', idx + 1)}_#{section}_#{packet_id}")
  expected_path = resolve_path(expected, root)
  return expected if dir_path?(expected_path)

  surface_path = resolve_path(surface, root)
  return "" unless surface_path && Dir.exist?(surface_path.to_s)

  matches = Dir.glob(File.join(surface_path.to_s, "#{format('%03d', idx + 1)}_*")).select do |path|
    File.directory?(path) && File.basename(path).end_with?("_#{packet_id}")
  end
  return "" if matches.empty?

  selected = matches.sort.first
  Pathname.new(selected).relative_path_from(root).to_s
rescue ArgumentError
  selected.to_s
end

def validate_upload_ready_folder(label, folder, upload_pack_type, semantic_fields, root, errors, exact_sources: {}, canonical_prompt_path: nil)
  return if blank?(folder)

  folder_path = resolve_path(folder, root)
  if !dir_path?(folder_path)
    errors << "#{label}: upload_ready_folder is not a directory: #{folder}"
    return
  end

  prompt_path = folder_path + "prompt.txt"
  image1_path = folder_path + "image1.png"
  image2_path = folder_path + "image2.png"
  errors << "#{label}: upload-ready prompt.txt is not readable: #{prompt_path}" unless readable_path?(prompt_path)
  errors << "#{label}: upload-ready image1.png is not readable: #{image1_path}" unless readable_path?(image1_path)

  if readable_path?(prompt_path)
    prompt_text = File.read(prompt_path)
    validate_prompt_text_semantics("#{label} upload-ready prompt", prompt_text, semantic_fields, errors)
    if canonical_prompt_path
      validate_exact_prompt_copy("#{label} upload-ready prompt", prompt_path, canonical_prompt_path, errors)
    end
    errors << "#{label}: upload-ready prompt must mention @image1" unless prompt_text.match?(/@image1/i)
    if upload_pack_type == "bridge-two-image" && !prompt_text.match?(/@image2/i)
      errors << "#{label}: bridge upload-ready prompt must mention @image2"
    elsif upload_pack_type == "storyboard-assist"
      reference_count = semantic_fields["storyboard_reference_count"].to_i
      (1..reference_count).each do |image_index|
        errors << "#{label}: storyboard-assist upload-ready prompt must mention @image#{image_index}" unless prompt_text.match?(/@image#{image_index}/i)
      end
    end
  end

  if upload_pack_type == "bridge-two-image"
    errors << "#{label}: bridge upload-ready folder must contain image2.png: #{image2_path}" unless readable_path?(image2_path)
    validate_exact_file_copy("#{label} upload-ready image1.png", image1_path, exact_sources["image1"], errors) if exact_sources["image1"]
    validate_exact_file_copy("#{label} upload-ready image2.png", image2_path, exact_sources["image2"], errors) if exact_sources["image2"]
  elsif upload_pack_type == "single-beat"
    errors << "#{label}: single-beat upload-ready folder must not contain image2.png: #{image2_path}" if readable_path?(image2_path)
    validate_exact_file_copy("#{label} upload-ready image1.png", image1_path, exact_sources["image1"], errors) if exact_sources["image1"]
  elsif upload_pack_type == "storyboard-assist"
    reference_count = semantic_fields["storyboard_reference_count"].to_i
    unless (2..4).cover?(reference_count)
      errors << "#{label}: storyboard-assist reference count must be between 2 and 4"
      return
    end
    (1..reference_count).each do |image_index|
      candidate = folder_path + "image#{image_index}.png"
      if readable_path?(candidate)
        validate_storyboard_reference_copy(label, image_index, candidate, semantic_fields, errors)
      else
        errors << "#{label}: storyboard-assist upload-ready folder is missing image#{image_index}.png"
      end
    end
    ((reference_count + 1)..4).each do |image_index|
      candidate = folder_path + "image#{image_index}.png"
      errors << "#{label}: storyboard-assist upload-ready folder has undeclared image#{image_index}.png" if readable_path?(candidate)
    end
  end
end

def parity_prompt_candidate?(path)
  parts = path.to_s.split(File::SEPARATOR)
  return false if parts.include?("upload-packs")
  return false if parts.any? { |part| part.match?(/\A_?backup/i) }
  return false if File.basename(path.to_s).match?(/\A(?:README|section-copy-pack)/i)

  true
end

def section_key_for(value)
  text = value.to_s.strip
  match = text.match(/\A(S\d{2})\b/)
  match ? match[1] : text
end

REQUIRED_SEMANTIC_FIELDS = {
  "audio_pressure" => "audio cue/tension",
  "start_audio_cue" => "start keyframe audio cue",
  "end_audio_cue" => "end keyframe audio cue",
  "visible_start_pose" => "visible start pose",
  "motion_bridge_summary" => "motion bridge summary",
  "bridge_body_route" => "body route",
  "bridge_camera_plan" => "camera route",
  "bridge_landing" => "endpoint",
  "previous_next_continuity" => "previous/next continuity",
  "prev_end_to_start" => "previous end frame to current start frame continuity",
  "end_to_next_start" => "current end frame to next start frame continuity",
  "edit_point_basis" => "future edit point basis"
}.freeze

V2_CONTROL_PROFILES = %w[
  image_locked_motion_camera
  storyboard_assisted_3frame
].freeze
V2_VISUAL_RESTATEMENT_POLICIES = %w[
  image_lock_only
  drift_recovery_minimal
].freeze
V2_GENERATOR_CONTROL_FIELDS = %w[
  start_trigger
  body_route
  camera_route
  pacing_timing
  endpoint
  edit_handoff
].freeze
V2_AUTHORING_TRUTH_FIELDS = {
  "audio_pressure" => "audio cue/tension",
  "start_audio_cue" => "start audio cue",
  "end_audio_cue" => "end audio cue",
  "visible_start_pose" => "visible start pose",
  "previous_next_continuity" => "previous/next continuity",
  "prev_end_to_start" => "previous end to current start continuity",
  "end_to_next_start" => "current end to next start continuity",
  "edit_point_basis" => "future edit-point basis"
}.freeze
V2_CAMERA_CAPTURE_FIELDS = %w[
  camera_height
  shot_scale_distance
  direction_angle
  depth_framing
  screen_placement_crop
].freeze
V2_CAMERA_CAPTURE_AXES = V2_CAMERA_CAPTURE_FIELDS.to_set.freeze
V2_CAMERA_CAPTURE_PATTERNS = {
  "camera_height" => /\b(?:ground|floor|knee|hip|waist|chest|shoulder|eye|head|low|high|overhead|aerial|height)\b/i,
  "shot_scale_distance" => /\b(?:macro|extreme close|close|medium|wide|full[- ]body|distance|body lengths?|meters?|feet)\b/i,
  "direction_angle" => /\b(?:front|rear|back|side|profile|three-quarter|overhead|camera-left|camera-right|left|right|degrees?|angle)\b/i,
  "depth_framing" => /\b(?:foreground|midground|background|behind|ahead|depth|deep|shallow|floor|reflection|layer)\b/i,
  "screen_placement_crop" => /\b(?:left|right|center|centre|third|upper|lower|edge|frame|crop|negative space|headroom|lead room)\b/i
}.freeze

BANNED_GENERIC_BRIDGE_PATTERNS = {
  "follow the beat action placeholder" => /follow the beat action/i,
  "visible poses placeholder" => /move (?:only )?between (?:those two|the two) visible poses/i,
  "crop-pair camera placeholder" => /keep the camera direction.*crop pair/i,
  "generic @image2 arrival" => /arrive at @image2 as the final end pose/i,
  "matching crop pair placeholder" => /matching the crop pair/i
}.freeze

CONCRETE_MOTION_PATTERN = /\b(?:gaze|eyes?|hand|finger|wrist|fist|head|chin|shoulder|chest|torso|hip|knee|boot|foot|feet|step|weight|body|formation|face|breath|belt|strap|scarf|sleeve|jacket|garment|floor|rail|line|shutter|gate|scanner|tray|carousel|cargo|camera|lens|frame|track|push|dolly|hold|stop|snap|freeze|turn|roll|lift|lower|dip|settle|rebound|route|@image[12])\b/i
CONCRETE_REQUIRED_FIELDS = %w[
  visible_start_pose
  motion_bridge_summary
  bridge_body_route
  bridge_camera_plan
  bridge_landing
  previous_next_continuity
  prev_end_to_start
  end_to_next_start
  edit_point_basis
].freeze

CAMERA_GRAMMAR_TOKENS = Set.new(%w[
  camera cameras lens shot shots view angle height low high medium wide close
  track tracks tracking push pushes pull pulls dolly pan pans tilt tilts orbit
  crane zoom rack focus static lock locks locked locking hold holds drift drifts
  follow follows reframe punch widen handheld left right front rear side
]).freeze
CAMERA_USE_SENTENCE_PATTERN = /\bUse\s+([^.\n]+?)\s+without changing to a new angle\b/i
BANNED_GENERATOR_PROMPT_PATTERNS = {
  "internal packet/timeline header" => /^\s*(?:PKT_[A-Z0-9_]+|B\d{2}(?:_[A-Z0-9_]+)?)\s*\|/i
}.freeze
BANNED_ABSTRACT_GENERATOR_TERMS = [
  "private signal",
  "private cue",
  "floor follows",
  "floor-follow",
  "room turn",
  "whole-room-turn",
  "final seal",
  "siren-like",
  "space reacts",
  "emotion grows",
  "controlled pressure",
  "quiet pull",
  "motion proof",
  "bassline grid",
  "pocket pressure",
  "camera evidence",
  "body evidence",
  "close but distant"
].freeze
TOKEN_STOPWORDS = Set.new(%w[
  a an and are as at be but by for from in into is it its of on or that the
  then this to toward towards with within without
  after before between current previous next start end frame frames keyframe
  keyframes image image1 image2 section prompt video cue cues
  bridge continuity motion route plan summary basis body camera
  keep use must should while
]).freeze

SECTION_QA_REQUIRED_CHECKS = IdolVideoPromptSectionQaContract.required_check_ids
SECTION_QA_STATUS_VALUES = IdolVideoPromptSectionQaContract.section_status_values.reject { |value| value == "archived" }.freeze
SECTION_QA_CHECK_STATUS_VALUES = IdolVideoPromptSectionQaContract.check_status_values.reject { |value| value == "archived" }.freeze

def semantic_field_value(prompt, field)
  case field
  when "bridge_camera_plan"
    prompt[field].to_s.empty? ? prompt["camera_route"].to_s : prompt[field].to_s
  when "bridge_landing"
    prompt[field].to_s.empty? ? prompt["endpoint"].to_s : prompt[field].to_s
  when "bridge_body_route"
    prompt[field].to_s.empty? ? prompt["body_route"].to_s : prompt[field].to_s
  else
    prompt[field].to_s
  end
end

def generation_prompt_text(text)
  match = text.to_s.match(/## Ready-to-Use Prompt[^\n]*\n\s*```prompt\s*\n?(.*?)\n?```/m)
  match ? match[1].to_s : text.to_s
end

def abstract_audit_text(text)
  text.to_s.gsub(/Answer the cue\s+"[^"]*"/i, "Answer the cue")
end

def normalized_text(value)
  value.to_s.downcase.gsub(/\s+/, " ").strip
end

def semantic_carry_tokens(value)
  value.to_s
    .downcase
    .scan(/[[:alnum:]가-힣@]+/)
    .map { |token| token.sub(/\A@/, "") }
    .select { |token| token.length >= 3 && !TOKEN_STOPWORDS.include?(token) }
    .uniq
end

def deep_text_values(value)
  case value
  when Hash
    value.values.flat_map { |item| deep_text_values(item) }
  when Array
    value.flat_map { |item| deep_text_values(item) }
  when String
    [value]
  else
    []
  end
end

def dance_activation?(value)
  Idol03VLanguageContract.dance_activation?(value)
end

def dance_token?(value)
  Idol03VLanguageContract.dance_token?(value)
end

def normalized_generation_prompt(value)
  normalized_text(generation_prompt_text(value))
end

def same_declared_path?(left, right, root)
  left_path = resolve_path(left, root)
  right_path = resolve_path(right, root)
  return false unless left_path && right_path

  if readable_path?(left_path) && readable_path?(right_path)
    left_path.realpath.to_s == right_path.realpath.to_s
  else
    left_path.cleanpath.to_s == right_path.cleanpath.to_s
  end
rescue Errno::ENOENT, Errno::EACCES
  false
end

def validate_exact_file_copy(label, actual_path, expected_path, errors)
  actual = Pathname.new(actual_path) if actual_path
  expected = Pathname.new(expected_path) if expected_path
  unless readable_path?(actual) && readable_path?(expected)
    errors << "#{label}: cannot verify exact source copy"
    return
  end

  actual_digest = Digest::SHA256.file(actual.to_s).hexdigest
  expected_digest = Digest::SHA256.file(expected.to_s).hexdigest
  errors << "#{label}: bytes do not match the exact v3 manifest source image" unless actual_digest == expected_digest
end

def validate_exact_prompt_copy(label, actual_path, canonical_path, errors)
  actual = Pathname.new(actual_path) if actual_path
  canonical = Pathname.new(canonical_path) if canonical_path
  unless readable_path?(actual) && readable_path?(canonical)
    errors << "#{label}: cannot verify canonical generator prompt copy"
    return
  end

  actual_text = normalized_generation_prompt(File.read(actual.to_s))
  canonical_text = normalized_generation_prompt(File.read(canonical.to_s))
  errors << "#{label}: generator prompt text differs from canonical output_prompt_path" unless actual_text == canonical_text
end

def semantic_carry_required_count(token_count)
  return token_count if token_count <= 2
  return 2 if token_count <= 5

  [3, (token_count * 0.35).ceil].max
end

def semantic_carry_missing_tokens(generation_tokens, value)
  semantic_carry_tokens(value).reject { |token| generation_tokens.include?(token) }
end

def semantic_value_carried?(generation_text, generation_tokens, value)
  value_text = normalized_text(value)
  return true if !value_text.empty? && normalized_text(generation_text).include?(value_text)

  tokens = semantic_carry_tokens(value)
  return true if tokens.empty?

  required = semantic_carry_required_count(tokens.length)
  matched = tokens.length - semantic_carry_missing_tokens(generation_tokens, value).length
  matched >= [required, tokens.length].min
end

def validate_visible_camera_target(label, field, value, errors)
  return if blank?(value)
  tokens = semantic_carry_tokens(value)
  substantive = tokens.reject { |token| CAMERA_GRAMMAR_TOKENS.include?(token) }
  return unless substantive.empty?

  errors << "#{label}: #{field} must name a visible body/object/space target, not camera grammar alone"
end

def validate_semantic_bridge(label, values, errors)
  return if values["_video_prompt_contract_version"].to_s == "v3"

  REQUIRED_SEMANTIC_FIELDS.each do |field, description|
    value = semantic_field_value(values, field)
    if blank?(value)
      errors << "#{label}: #{field} is required for semantic video-prompt bridge"
      next
    end

    min_length = 24
    errors << "#{label}: #{field} is too thin to preserve #{description}" if value.strip.length < min_length
    if values["_video_prompt_contract_version"].to_s != "v3" && CONCRETE_REQUIRED_FIELDS.include?(field) && !value.match?(CONCRETE_MOTION_PATTERN)
      errors << "#{label}: #{field} must name concrete visible motion/camera evidence"
    end

    BANNED_GENERIC_BRIDGE_PATTERNS.each do |name, pattern|
      errors << "#{label}: #{field} uses banned generic bridge language: #{name}" if value.match?(pattern)
    end
  end

  validate_visible_camera_target(label, "bridge_camera_plan", semantic_field_value(values, "bridge_camera_plan"), errors)
  validate_visible_camera_target(label, "bridge_camera_technique", values["bridge_camera_technique"].to_s, errors)
end

def v2_control_contract?(values)
  %w[v2 v3].include?(values["_video_prompt_contract_version"].to_s)
end

def canonical_motion_route_field(values)
  values["_video_prompt_contract_version"].to_s == "v3" ? "screen_motion_route" : "body_route"
end

def keyframe_boundary_value(values, field)
  boundary = values["keyframe_boundary_contract"]
  return "" unless boundary.is_a?(Hash)

  boundary[field].to_s
end

def validate_v2_authoring_truth(label, values, errors)
  if values["_video_prompt_contract_version"].to_s == "v3"
    boundary = values["keyframe_boundary_contract"]
    unless boundary.is_a?(Hash)
      errors << "#{label}: keyframe_boundary_contract is required as the canonical v3 boundary owner"
      boundary = {}
    end
    %w[
      start_audio_cue
      end_audio_cue
      motion_between_keyframes
      prev_end_to_start
      end_to_next_start
      edit_point_basis
      single_keyframe_exception
    ].each do |field|
      value = boundary[field].to_s
      errors << "#{label}: keyframe_boundary_contract.#{field} is required" if blank?(value)
      if values.key?(field) && values[field].to_s != value
        errors << "#{label}: legacy flat #{field} must exactly derive from keyframe_boundary_contract.#{field}"
      end
    end
  end

  V2_AUTHORING_TRUTH_FIELDS.each do |field, description|
    if values["_video_prompt_contract_version"].to_s == "v3" &&
       %w[start_audio_cue end_audio_cue prev_end_to_start end_to_next_start edit_point_basis].include?(field)
      value = keyframe_boundary_value(values, field)
    else
      value = values[field].to_s
    end
    if blank?(value)
      errors << "#{label}: #{field} is required as v2 index-only authoring truth for #{description}"
      next
    end

    unless values["_video_prompt_contract_version"].to_s == "v3"
      min_length = %w[start_audio_cue end_audio_cue].include?(field) ? 3 : 16
      errors << "#{label}: #{field} is too thin to preserve #{description}" if value.strip.length < min_length
    end
    if values["_video_prompt_contract_version"].to_s != "v3" && %w[visible_start_pose previous_next_continuity prev_end_to_start end_to_next_start edit_point_basis].include?(field) && !value.match?(CONCRETE_MOTION_PATTERN)
      errors << "#{label}: #{field} must name observable body/object/camera/edit evidence"
    end
  end
end

def validate_v2_prompt_control(label, values, root, errors)
  control_profile = values["control_profile"].to_s
  unless V2_CONTROL_PROFILES.include?(control_profile)
    errors << "#{label}: control_profile must be one of #{V2_CONTROL_PROFILES.join(', ')}"
  end

  restatement_policy = values["visual_restatement_policy"].to_s
  unless V2_VISUAL_RESTATEMENT_POLICIES.include?(restatement_policy)
    errors << "#{label}: visual_restatement_policy must be one of #{V2_VISUAL_RESTATEMENT_POLICIES.join(', ')}"
  end
  if restatement_policy == "drift_recovery_minimal" && blank?(values["appearance_recovery_reason"])
    errors << "#{label}: appearance_recovery_reason is required for drift_recovery_minimal"
  end

  motion_route_field = canonical_motion_route_field(values)
  generator_control_fields = V2_GENERATOR_CONTROL_FIELDS.map { |field| field == "body_route" ? motion_route_field : field }
  generator_control_fields.each do |field|
    value = values[field].to_s
    if blank?(value)
      errors << "#{label}: #{field} is required by the v2 motion/camera-first contract"
      next
    end
    unless values["_video_prompt_contract_version"].to_s == "v3"
      errors << "#{label}: #{field} is too thin for generator control" if value.strip.length < 12
      BANNED_ABSTRACT_GENERATOR_TERMS.each do |term|
        errors << "#{label}: #{field} uses abstract generator language: #{term}" if value.match?(/\b#{Regexp.escape(term)}\b/i)
      end
    end
  end

  unless values["_video_prompt_contract_version"].to_s == "v3" || values[motion_route_field].to_s.match?(CONCRETE_MOTION_PATTERN)
    errors << "#{label}: #{motion_route_field} must name concrete visible body/object/environment movement or an intentional hold"
  end
  unless values["_video_prompt_contract_version"].to_s == "v3" || values["endpoint"].to_s.match?(CONCRETE_MOTION_PATTERN)
    errors << "#{label}: endpoint must name a concrete visible final state"
  end
  validate_visible_camera_target(label, "camera_route", values["camera_route"].to_s, errors) unless values["_video_prompt_contract_version"].to_s == "v3"

  camera_capture = values["camera_capture"]
  if values["_video_prompt_contract_version"].to_s == "v3"
    if !camera_capture.nil? && !camera_capture.is_a?(Hash)
      errors << "#{label}: optional camera_capture must be a mapping"
    elsif camera_capture.is_a?(Hash)
      unknown_fields = camera_capture.keys.map(&:to_s) - V2_CAMERA_CAPTURE_FIELDS
      errors << "#{label}: optional camera_capture has unknown fields: #{unknown_fields.join(', ')}" unless unknown_fields.empty?
      camera_capture.each do |field, value|
        errors << "#{label}: optional camera_capture.#{field} cannot be blank" if blank?(value)
      end
    end
  else
    unless camera_capture.is_a?(Hash)
      errors << "#{label}: camera_capture must be a mapping"
      camera_capture = {}
    end
    V2_CAMERA_CAPTURE_FIELDS.each do |field|
      value = camera_capture[field].to_s
      if blank?(value)
        errors << "#{label}: camera_capture.#{field} is required"
        next
      end
      errors << "#{label}: camera_capture.#{field} is too thin" if value.strip.length < 8
      pattern = V2_CAMERA_CAPTURE_PATTERNS.fetch(field)
      errors << "#{label}: camera_capture.#{field} must name concrete frame geometry" unless value.match?(pattern)
    end
  end

  unless control_profile == "storyboard_assisted_3frame"
    errors << "#{label}: storyboard_assist_path must be omitted outside storyboard_assisted_3frame" unless blank?(values["storyboard_assist_path"])
    errors << "#{label}: storyboard_id must be omitted outside storyboard_assisted_3frame" unless blank?(values["storyboard_id"])
    return
  end

  storyboard_path = values["storyboard_assist_path"].to_s
  if blank?(storyboard_path)
    errors << "#{label}: storyboard_assist_path is required for storyboard_assisted_3frame"
  else
    resolved = resolve_path(storyboard_path, root)
    errors << "#{label}: storyboard_assist_path is not readable: #{storyboard_path}" unless readable_path?(resolved)
  end
end

def v2_semantic_fields(values, upload_pack_type, storyboard_reference_bundle = nil)
  camera_capture = values["camera_capture"].is_a?(Hash) ? values["camera_capture"] : {}
  storyboard_reference_count = storyboard_reference_bundle.is_a?(Hash) ? storyboard_reference_bundle["count"] : nil
  storyboard_references = storyboard_reference_bundle.is_a?(Hash) ? storyboard_reference_bundle["references"] : []
  {
    "_video_prompt_contract_version" => values["_video_prompt_contract_version"].to_s.empty? ? "v2" : values["_video_prompt_contract_version"].to_s,
    "control_profile" => values["control_profile"].to_s,
    "visual_restatement_policy" => values["visual_restatement_policy"].to_s,
    "appearance_recovery_reason" => values["appearance_recovery_reason"].to_s,
    "start_trigger" => values["start_trigger"].to_s,
    canonical_motion_route_field(values) => values[canonical_motion_route_field(values)].to_s,
    "camera_route" => values["camera_route"].to_s,
    "pacing_timing" => values["pacing_timing"].to_s,
    "endpoint" => values["endpoint"].to_s,
    "edit_handoff" => values["edit_handoff"].to_s,
    "camera_capture" => camera_capture,
    "storyboard_assist_path" => values["storyboard_assist_path"].to_s,
    "storyboard_reference_count" => storyboard_reference_count,
    "storyboard_references" => storyboard_references,
    "upload_pack_type" => upload_pack_type
  }
end

def owning_run_root_for(index_resolved, root)
  relative = index_resolved.cleanpath.relative_path_from(root.cleanpath).to_s
  parts = Pathname.new(relative).each_filename.to_a
  return nil unless parts[0] == "runs" && parts.length >= 3

  parts.first(3).join(File::SEPARATOR)
rescue ArgumentError
  nil
end

def validate_storyboard_assist_artifact(label, values, index_resolved, root, cache, errors)
  return unless values["control_profile"].to_s == "storyboard_assisted_3frame"

  %w[storyboard_id cut_id clip_id].each do |field|
    errors << "#{label}: #{field} is required for storyboard_assisted_3frame" if blank?(values[field])
  end

  path_value = values["storyboard_assist_path"].to_s
  return if blank?(path_value)

  raw_path = Pathname.new(path_value)
  if raw_path.absolute? || raw_path.each_filename.to_a.include?("..")
    errors << "#{label}: storyboard_assist_path must be a clean repository-relative path"
    return
  end

  run_root = owning_run_root_for(index_resolved, root)
  unless run_root && (path_value == run_root || path_value.start_with?("#{run_root}/"))
    errors << "#{label}: storyboard_assist_path must stay inside the owning run #{run_root || '(unknown)'}"
    return
  end

  resolved = resolve_path(path_value, root)
  cached = cache[path_value]
  if cached.is_a?(Hash) && cached["error"]
    errors << "#{label}: #{cached['error']}"
    return nil
  end

  unless cached.is_a?(Hash) && cached["document"]
    validator = Pathname.new(__dir__).join("validate_video_prompt_storyboard_assist.rb")
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      validator.to_s,
      "--repo-root",
      root.to_s,
      resolved.to_s,
      chdir: root.to_s
    )
    unless status.success?
      detail = [stdout, stderr].reject(&:empty?).join(" ").gsub(/\s+/, " ").strip
      detail = "storyboard assist validator failed" if detail.empty?
      message = "storyboard_assist_path failed authoritative validation: #{detail}"
      cache[path_value] = {"error" => message}
      errors << "#{label}: #{message}"
      return nil
    end

    begin
      document = YAML.safe_load(File.read(resolved.to_s), permitted_classes: [], permitted_symbols: [], aliases: true)
      cache[path_value] = {"document" => document}
      cached = cache[path_value]
    rescue Psych::SyntaxError => e
      message = "storyboard_assist_path could not be loaded after validation: #{e.message}"
      cache[path_value] = {"error" => message}
      errors << "#{label}: #{message}"
      return nil
    end
  end

  document = cached["document"]
  record = Array(document["cut_storyboards"]).find { |row| row.is_a?(Hash) && row["storyboard_id"].to_s == values["storyboard_id"].to_s }
  unless record
    errors << "#{label}: storyboard_id #{values['storyboard_id']} is missing from storyboard_assist_path"
    return nil
  end

  references = Array(record.dig("prompt_handoff", "references"))
  {
    "count" => record.dig("prompt_handoff", "reference_count").to_i,
    "references" => references
  }
end

def validate_upload_pack_profile_compatibility(label, control_profile, upload_pack_type, errors)
  return if blank?(upload_pack_type)

  assisted_profile = control_profile.to_s == "storyboard_assisted_3frame"
  assisted_pack = upload_pack_type.to_s == "storyboard-assist"
  return if assisted_profile == assisted_pack

  errors << "#{label}: storyboard_assisted_3frame and storyboard-assist upload_pack_type must be selected together"
end

def validate_prompt_text_semantics(label, text, values, errors)
  return if values["_video_prompt_contract_version"].to_s == "v3"

  generation_text = generation_prompt_text(text)
  generation_tokens = semantic_carry_tokens(generation_text).to_set

  semantic_fields = if v2_control_contract?(values)
                      V2_GENERATOR_CONTROL_FIELDS.map { |field| field == "body_route" ? canonical_motion_route_field(values) : field }
                    else
                      REQUIRED_SEMANTIC_FIELDS.keys
                    end

  semantic_fields.each do |field|
    value = semantic_field_value(values, field)
    next if blank?(value)

    carried = semantic_value_carried?(generation_text, generation_tokens, value)
    unless carried
      missing = semantic_carry_missing_tokens(generation_tokens, value).first(8).join(", ")
      suffix = missing.empty? ? "" : " (missing concrete token(s): #{missing})"
      errors << "#{label}: output prompt text must carry concrete meaning from #{field}#{suffix}"
    end
  end

  if v2_control_contract?(values)
    camera_capture = values["camera_capture"].is_a?(Hash) ? values["camera_capture"] : {}
    V2_CAMERA_CAPTURE_FIELDS.each do |field|
      value = camera_capture[field].to_s
      next if blank?(value)

      carried = semantic_value_carried?(generation_text, generation_tokens, value)
      unless carried
        missing = semantic_carry_missing_tokens(generation_tokens, value).first(8).join(", ")
        suffix = missing.empty? ? "" : " (missing concrete token(s): #{missing})"
        errors << "#{label}: output prompt text must carry camera_capture.#{field}#{suffix}"
      end
    end

    errors << "#{label}: v2 prompt must use a compact attached-image visual-source lock" unless Idol03VLanguageContract.image_source_lock?(generation_text)
    if values["visual_restatement_policy"].to_s == "image_lock_only" && Idol03VLanguageContract.appearance_restatement_inventory?(generation_text)
      errors << "#{label}: image_lock_only forbids a repeated appearance inventory; trust the attached image pixels"
    end
    if values["control_profile"].to_s == "storyboard_assisted_3frame"
      errors << "#{label}: storyboard-assisted prompt must mention @image1 as the storyboard" unless generation_text.match?(/@image1.{0,120}storyboard/im)
      reference_count = values["_storyboard_reference_count"].to_i
      reference_count = 2 if reference_count < 2
      (2..reference_count).each do |image_index|
        errors << "#{label}: storyboard-assisted prompt must mention @image#{image_index} from the authoritative assist artifact" unless generation_text.match?(/@image#{image_index}/i)
      end
    end
  end

  BANNED_GENERIC_BRIDGE_PATTERNS.each do |name, pattern|
    errors << "#{label}: output prompt text uses banned generic bridge language: #{name}" if generation_text.match?(pattern)
  end

  BANNED_GENERATOR_PROMPT_PATTERNS.each do |name, pattern|
    errors << "#{label}: generator-facing prompt leaks #{name}" if generation_text.match?(pattern)
  end

  audit_text = abstract_audit_text(generation_text)
  BANNED_ABSTRACT_GENERATOR_TERMS.each do |term|
    if audit_text.match?(/\b#{Regexp.escape(term)}\b/i)
      errors << "#{label}: generator-facing prompt uses abstract label instead of observable screen language: #{term}"
    end
  end

  unless v2_control_contract?(values)
    use_matches = generation_text.scan(CAMERA_USE_SENTENCE_PATTERN).flatten
    if values["upload_pack_type"].to_s == "bridge-two-image" && use_matches.empty?
      errors << "#{label}: bridge-two-image generator prompt must include a concrete `Use ... without changing to a new angle` camera guard"
    end

    use_matches.each do |camera_phrase|
      validate_visible_camera_target(label, "generator camera guard `Use #{camera_phrase}`", camera_phrase, errors)
    end
  end
end

def validate_03v_review_execution_record(record_ref, root:, index_sha:, expected_sections:, owner_route:, role:, used_paths:, used_sessions:, errors:, label:)
  unless record_ref.is_a?(Hash)
    errors << "#{label}: review_execution_record must be a path/sha256 mapping"
    return
  end

  path_value = record_ref["path"].to_s
  record_path = resolve_path(path_value, root)
  unless readable_path?(record_path)
    errors << "#{label}: review execution record is not readable: #{path_value}"
    return
  end
  actual_sha = Digest::SHA256.file(record_path.to_s).hexdigest
  unless actual_sha == record_ref["sha256"].to_s
    errors << "#{label}: review execution record sha256 is stale"
    return
  end

  normalized_path = record_path.realpath.to_s
  errors << "#{label}: review execution record is reused" if used_paths.include?(normalized_path)
  used_paths << normalized_path

  begin
    record = YAML.safe_load(File.read(record_path.to_s), permitted_classes: [], permitted_symbols: [], aliases: false)
  rescue Psych::SyntaxError => e
    errors << "#{label}: review execution record YAML syntax error: #{e.message}"
    return
  end
  unless record.is_a?(Hash)
    errors << "#{label}: review execution record must be a mapping"
    return
  end

  errors << "#{label}: execution schema_version is invalid" unless record["schema_version"].to_s == "idol-03v-creative-context-review-execution-record.v1"
  errors << "#{label}: execution source index sha256 does not match" unless record["source_video_prompt_index_sha256"].to_s == index_sha
  errors << "#{label}: execution assigned_section_ids do not match scope" unless Array(record["assigned_section_ids"]).map(&:to_s) == expected_sections
  errors << "#{label}: execution completion_state must be completed" unless record["completion_state"].to_s == "completed"
  errors << "#{label}: execution must not perform canonical semantic writes" unless record["canonical_semantic_write_performed"] == false

  session_id = record["session_id"].to_s
  errors << "#{label}: execution session_id is required" if session_id.empty?
  errors << "#{label}: review session is reused" if !session_id.empty? && used_sessions.include?(session_id)
  used_sessions << session_id unless session_id.empty?

  if owner_route.start_with?("codex_")
    errors << "#{label}: Codex route requires registered Codex reviewer producer" unless record["producer"].to_s == "registered_codex_03v_reviewer_runner"
    errors << "#{label}: Codex route requires surface_owner codex" unless record["surface_owner"].to_s == "codex"
    if role == :section
      errors << "#{label}: Codex section role is invalid" unless record["role_id"].to_s == "idol-03v-section-context-reviewer"
      errors << "#{label}: Codex section session_type is invalid" unless record["session_type"].to_s == "codex_section_review"
      errors << "#{label}: Codex section profile must be sol_xhigh" unless record["profile"].to_s == "sol_xhigh"
    else
      errors << "#{label}: Codex whole-timeline role is invalid" unless record["role_id"].to_s == "idol-03v-whole-timeline-reconciler"
      errors << "#{label}: Codex root session_type is invalid" unless record["session_type"].to_s == "codex_root_reconciliation"
      expected_profile = owner_route == "codex_sol_max" ? "sol_max" : "sol_xhigh"
      errors << "#{label}: Codex whole-timeline profile must be #{expected_profile}" unless record["profile"].to_s == expected_profile
    end
  elsif owner_route == "grok_native"
    errors << "#{label}: Grok route requires registered Grok reviewer producer" unless record["producer"].to_s == "registered_grok_native_03v_reviewer_runner"
    errors << "#{label}: Grok route requires surface_owner grok" unless record["surface_owner"].to_s == "grok"
    if role == :section
      errors << "#{label}: Grok section role is invalid" unless record["role_id"].to_s == "grok-03v-section-context-reviewer"
      errors << "#{label}: Grok section session_type is invalid" unless record["session_type"].to_s == "native_subagent"
      errors << "#{label}: Grok section profile is invalid" unless record["profile"].to_s == "grok_4_5_high_native_subagent"
    else
      errors << "#{label}: Grok whole-timeline role is invalid" unless record["role_id"].to_s == "grok-root-03v-whole-timeline-reconciler"
      errors << "#{label}: Grok root session_type is invalid" unless record["session_type"].to_s == "root_reconciliation"
      errors << "#{label}: Grok root profile is invalid" unless record["profile"].to_s == "grok_4_5_high_root"
    end
  else
    errors << "#{label}: unknown active_owner_route #{owner_route.inspect}"
  end
end

def validate_section_qa(index, index_resolved, prompts, root, errors)
  section_qa = index["section_qa"]
  unless section_qa.is_a?(Hash)
    errors << "section_qa is required; batch authoring is allowed, but video-prompt QA must be section-by-section"
    return
  end

  path_value = section_qa["path"].to_s
  if blank?(path_value)
    errors << "section_qa.path is required"
    return
  end

  qa_path = resolve_path(path_value, root)
  unless readable_path?(qa_path)
    errors << "section_qa.path is not readable: #{path_value}"
    return
  end

  qa = load_yaml_hash(qa_path, "section QA", errors)
  return if qa.empty?

  errors << "section_qa.review_unit must be section" unless section_qa["review_unit"].to_s == "section"
  unless SECTION_QA_STATUS_VALUES.include?(section_qa["status"].to_s)
    errors << "section_qa.status must be one of #{SECTION_QA_STATUS_VALUES.join(', ')}"
  end
  qa_version = qa["schema_version"].to_s
  contextual_v2 = qa_version == "idol_video_prompt_section_qa.v2"
  founder_direct_v3 = qa_version == "idol_video_prompt_section_qa.v3"
  unless %w[idol_video_prompt_section_qa.v1 idol_video_prompt_section_qa.v2 idol_video_prompt_section_qa.v3].include?(qa_version)
    errors << "section QA schema_version must be idol_video_prompt_section_qa.v1, idol_video_prompt_section_qa.v2, or idol_video_prompt_section_qa.v3"
  end
  if index["schema_version"].to_s == "idol_video_prompt_index.v3" && production_capable_index?(index, prompts) && !contextual_v2 && !founder_direct_v3
    errors << "production-capable v3 requires idol_video_prompt_section_qa.v2 contextual review or a v3 Founder-direct delta against a passed v2 baseline; v1 checklist QA is legacy only"
  end
  errors << "section QA review_unit must be section" unless qa["review_unit"].to_s == "section"
  unless SECTION_QA_STATUS_VALUES.include?(qa["overall_status"].to_s)
    errors << "section QA overall_status must be one of #{SECTION_QA_STATUS_VALUES.join(', ')}"
  end
  unless section_qa["status"].to_s == qa["overall_status"].to_s
    errors << "section_qa.status must match section QA overall_status"
  end

  source_index = qa["source_video_prompt_index_path"].to_s
  unless blank?(source_index)
    qa_source_path = resolve_path(source_index, root)
    if qa_source_path && qa_source_path.cleanpath.to_s != index_resolved.cleanpath.to_s
      errors << "section QA source_video_prompt_index_path does not match validated index"
    end
  end

  index_sha = Digest::SHA256.file(index_resolved.to_s).hexdigest
  owner_route = qa["active_owner_route"].to_s
  if contextual_v2 || founder_direct_v3
    errors << "section QA source_video_prompt_index_sha256 does not match validated index" unless qa["source_video_prompt_index_sha256"].to_s == index_sha
  end
  if contextual_v2
    errors << "section QA review_mode must declare contextual LLM section and whole-timeline review" unless qa["review_mode"].to_s == "contextual_llm_section_and_whole_timeline"
    unless %w[codex_sol_xhigh codex_sol_max grok_native].include?(owner_route)
      errors << "section QA active_owner_route is invalid"
    end
  elsif founder_direct_v3
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      File.join(__dir__, "validate_video_prompt_section_qa_readiness.rb"),
      qa_path.to_s,
      "--root",
      root.to_s,
      chdir: root.to_s
    )
    unless status.success?
      detail = [stderr, stdout].reject { |value| value.to_s.strip.empty? }.join(" ").strip
      errors << "section QA Founder-direct delta validation failed: #{detail}"
    end
  end

  expected_sections = prompts
    .select { |prompt| prompt.is_a?(Hash) }
    .group_by { |prompt| section_key_for(prompt["section"]) }
  expected_sections.delete("") if expected_sections.key?("")

  if expected_sections.empty?
    errors << "section QA cannot run because prompts do not carry section keys"
    return
  end

  records = qa["sections"]
  unless records.is_a?(Array) && !records.empty?
    errors << "section QA sections must contain section review records"
    return
  end

  records_by_key = {}
  records.each_with_index do |record, idx|
    unless record.is_a?(Hash)
      errors << "section QA sections[#{idx}] must be a mapping"
      next
    end

    key = record["section_key"].to_s
    if key.empty?
      errors << "section QA sections[#{idx}].section_key is required"
      next
    end

    if records_by_key.key?(key)
      errors << "section QA duplicate section_key #{key}"
    else
      records_by_key[key] = record
    end
  end

  reviewed_sections = expected_sections
  if founder_direct_v3
    affected_ids = Array(qa["affected_section_ids"]).map(&:to_s)
    unknown_affected = affected_ids.to_set - expected_sections.keys.to_set
    unknown_affected.each { |key| errors << "section QA Founder-direct delta names unknown section #{key}" }
    reviewed_sections = expected_sections.select { |key, _value| affected_ids.include?(key) }
  end

  missing_sections = reviewed_sections.keys.to_set - records_by_key.keys.to_set
  extra_sections = records_by_key.keys.to_set - reviewed_sections.keys.to_set
  missing_sections.each { |key| errors << "section QA missing section #{key}" }
  extra_sections.each { |key| errors << "section QA has extra section #{key}" }

  used_execution_paths = Set.new
  used_session_ids = Set.new
  reviewed_sections.each do |key, section_prompts|
    record = records_by_key[key]
    next unless record

    label = "section QA #{key}"
    expected_packets = section_prompts.map { |prompt| prompt["packet_id"].to_s }
    actual_packets = Array(record["packet_ids"]).map(&:to_s)
    if actual_packets != expected_packets
      errors << "#{label}: packet_ids must match video-prompt-index section order"
    end

    expected_count = expected_packets.length
    actual_count = record["reviewed_prompt_count"]
    if actual_count.to_i != expected_count
      errors << "#{label}: reviewed_prompt_count #{actual_count.inspect} does not match #{expected_count}"
    end

    unless SECTION_QA_STATUS_VALUES.include?(record["status"].to_s)
      errors << "#{label}: status must be one of #{SECTION_QA_STATUS_VALUES.join(', ')}"
    end

    if contextual_v2
      errors << "#{label}: review_summary is required" if blank?(record["review_summary"])
      findings = record["findings"]
      unless findings.is_a?(Array)
        errors << "#{label}: findings must be an array"
      else
        findings.each_with_index do |finding, finding_index|
          unless finding.is_a?(Hash)
            errors << "#{label}: findings[#{finding_index}] must be a mapping"
            next
          end
          affected = Array(finding["affected_packet_ids"]).map(&:to_s)
          unknown = affected - expected_packets
          errors << "#{label}: findings[#{finding_index}] has packets outside the section: #{unknown.join(', ')}" unless unknown.empty?
        end
      end
      validate_03v_review_execution_record(
        record["review_execution_record"],
        root: root,
        index_sha: index_sha,
        expected_sections: [key],
        owner_route: owner_route,
        role: :section,
        used_paths: used_execution_paths,
        used_sessions: used_session_ids,
        errors: errors,
        label: label
      )
    elsif !founder_direct_v3
      checked_fields = record["checked_fields"]
      unless checked_fields.is_a?(Hash)
        errors << "#{label}: checked_fields must be a mapping"
      else
        SECTION_QA_REQUIRED_CHECKS.each do |field|
          value = checked_fields[field].to_s
          if blank?(value)
            errors << "#{label}: checked_fields.#{field} is required"
          elsif !SECTION_QA_CHECK_STATUS_VALUES.include?(value)
            errors << "#{label}: checked_fields.#{field} must be one of #{SECTION_QA_CHECK_STATUS_VALUES.join(', ')}"
          end
        end
      end

      %w[section_entry_continuity section_exit_continuity section_transition_audit qa_summary].each do |field|
        value = record[field].to_s
        if blank?(value) || value.strip.length < 24
          errors << "#{label}: #{field} must describe the legacy section-level QA evidence"
        end
      end
    end
  end

  if founder_direct_v3
    if qa["overall_status"].to_s == "pass"
      errors << "section QA pass requires every affected section status to be pass" unless records.all? { |record| record.is_a?(Hash) && record["status"].to_s == "pass" }
    end
    return
  end

  return unless contextual_v2

  whole_review = qa["whole_timeline_review"]
  unless whole_review.is_a?(Hash)
    errors << "section QA whole_timeline_review must be a mapping"
    return
  end
  errors << "section QA whole_timeline_review.review_summary is required" if blank?(whole_review["review_summary"])
  errors << "section QA whole_timeline_review.findings must be an array" unless whole_review["findings"].is_a?(Array)
  if qa["overall_status"].to_s == "pass"
    errors << "section QA pass requires every section status to be pass" unless records.all? { |record| record.is_a?(Hash) && record["status"].to_s == "pass" }
    errors << "section QA pass requires whole_timeline_review.status pass" unless whole_review["status"].to_s == "pass"
  end
  validate_03v_review_execution_record(
    whole_review["review_execution_record"],
    root: root,
    index_sha: index_sha,
    expected_sections: expected_sections.keys,
    owner_route: owner_route,
    role: :whole_timeline,
    used_paths: used_execution_paths,
    used_sessions: used_session_ids,
    errors: errors,
    label: "section QA whole_timeline_review"
  )
end

def load_yaml_hash(path, label, errors)
  unless readable_path?(path)
    errors << "#{label} is not readable: #{path}"
    return {}
  end

  doc = YAML.load_file(path)
  unless doc.is_a?(Hash)
    errors << "#{label} must be a YAML mapping: #{path}"
    return {}
  end

  doc
rescue Psych::SyntaxError => e
  errors << "#{label} YAML syntax error: #{e.message}"
  {}
end

def validate_v2_index_policy(index, root, errors)
  policy = index["prompt_authoring_policy"]
  unless policy.is_a?(Hash)
    errors << "prompt_authoring_policy is required for idol_video_prompt_index.v2/v3"
    return
  end

  expected = {
    "default_control_profile" => "image_locked_motion_camera",
    "visual_source_authority" => "attached_image_pixels",
    "appearance_restatement_policy" => "drift_recovery_only"
  }
  expected.each do |field, value|
    errors << "prompt_authoring_policy.#{field} must be #{value}" unless policy[field].to_s == value
  end

  raw_axes = Array(policy["camera_capture_axes"]).map(&:to_s)
  axes = Set.new(raw_axes)
  if index["schema_version"].to_s == "idol_video_prompt_index.v3"
    if policy.key?("camera_capture_axes")
      errors << "prompt_authoring_policy.camera_capture_axes cannot be empty when declared" if raw_axes.empty?
      unknown_axes = axes - V2_CAMERA_CAPTURE_AXES
      errors << "prompt_authoring_policy.camera_capture_axes has unknown values: #{unknown_axes.to_a.join(', ')}" unless unknown_axes.empty?
      errors << "prompt_authoring_policy.camera_capture_axes cannot contain duplicates" unless axes.length == raw_axes.length
    end
  elsif axes != V2_CAMERA_CAPTURE_AXES
    errors << "prompt_authoring_policy.camera_capture_axes must contain exactly #{V2_CAMERA_CAPTURE_FIELDS.join(', ')}"
  end

  storyboard = policy["storyboard_assist"]
  unless storyboard.is_a?(Hash)
    errors << "prompt_authoring_policy.storyboard_assist must be a mapping"
    return
  end
  errors << "prompt_authoring_policy.storyboard_assist.default must be off" unless storyboard["default"].to_s == "off"
  errors << "prompt_authoring_policy.storyboard_assist.activation must be founder_request_only" unless storyboard["activation"].to_s == "founder_request_only"
  schema_path = storyboard["schema_path"].to_s
  expected_schema_path = "schemas/video-prompt-storyboard-assist.schema.json"
  errors << "prompt_authoring_policy.storyboard_assist.schema_path must be #{expected_schema_path}" unless schema_path == expected_schema_path
  resolved = resolve_path(schema_path, root)
  errors << "prompt_authoring_policy.storyboard_assist.schema_path is not readable: #{schema_path}" unless readable_path?(resolved)
end

def legacy_archive_index?(index)
  index["status"].to_s.match?(/(?:historical|archive|archived|closed|superseded)/i) ||
    index.dig("closure_lock", "status").to_s.match?(/(?:closed|archive|superseded)/i)
end

def draft_only_prompts?(prompts)
  draft_statuses = %w[draft codex_draft codex_prepared_handoff_draft_not_grok_final hold]
  rows = Array(prompts).select { |prompt| prompt.is_a?(Hash) }
  !rows.empty? && rows.all? { |prompt| draft_statuses.include?(prompt["prompt_status"].to_s) }
end

def production_capable_index?(index, prompts)
  return false if legacy_archive_index?(index)

  index_status = index["status"].to_s
  return true if index_status.match?(/(?:ready|selected|complete|production|handoff)/i)

  Array(prompts).any? do |prompt|
    next false unless prompt.is_a?(Hash)
    status = prompt["prompt_status"].to_s
    !%w[draft codex_draft codex_prepared_handoff_draft_not_grok_final hold].include?(status)
  end
end

def ready_v3_manifest?(manifest)
  manifest.is_a?(Hash) &&
    manifest["schema_version"].to_s == "idol_video_prompt_manifest.v3" &&
    %w[ready_for_prompt_authoring complete].include?(manifest["status"].to_s)
end

def validate_index_manifest_readiness(index_schema_version, index, manifest, prompts, errors)
  production_capable = production_capable_index?(index, prompts)
  if %w[idol_video_prompt_index.v1 idol_video_prompt_index.v2].include?(index_schema_version)
    unless legacy_archive_index?(index) || draft_only_prompts?(prompts)
      errors << "v1/v2 video-prompt indexes are legacy draft/archive evidence only; production or founder handoff requires idol_video_prompt_index.v3"
    end
    return
  end

  return unless index_schema_version == "idol_video_prompt_index.v3" && production_capable
  unless ready_v3_manifest?(manifest)
    errors << "production-capable idol_video_prompt_index.v3 requires a ready_for_prompt_authoring or complete idol_video_prompt_manifest.v3"
  end
end

def v3_cues_by_packet(manifest, errors)
  cues_by_packet = {}
  Array(manifest["cues"]).each do |cue|
    next unless cue.is_a?(Hash)

    packet_id = cue.dig("upstream_frame_lineage", "packet_id").to_s
    if packet_id.empty?
      errors << "v3 manifest cue #{cue['cut_id']} is missing upstream_frame_lineage.packet_id"
    elsif cues_by_packet.key?(packet_id)
      errors << "v3 manifest has duplicate packet lineage #{packet_id}"
    else
      cues_by_packet[packet_id] = cue
    end
  end
  cues_by_packet
end

def validate_v3_prompt_source_projection(prompt, cue, root, label, errors)
  source_images = cue["source_images"].is_a?(Hash) ? cue["source_images"] : {}
  expected_start = source_images["start_image"].to_s
  expected_pass = source_images["pass_through_image"].to_s
  expected_end = source_images["end_image"].to_s

  primary_fields = %w[
    source_visual_lock_path
    source_section_keyframe_image_path
    source_keyframe_image_path
    source_review_board_image_path
    source_start_keyframe_image_path
  ]
  declared_primary = primary_fields.each_with_object([]) do |field, values|
    value = prompt[field].to_s
    values << [field, value] unless blank?(value)
  end
  errors << "#{label}: v3 prompt must declare the manifest start image as its source visual" if declared_primary.empty?
  declared_primary.each do |field, value|
    unless same_declared_path?(value, expected_start, root)
      errors << "#{label}: #{field} must match v3 manifest source_images.start_image"
    end
  end

  actual_pass = prompt["source_pass_through_keyframe_image_path"].to_s
  if expected_pass.empty?
    errors << "#{label}: source_pass_through_keyframe_image_path must be omitted when the v3 manifest has no pass-through image" unless actual_pass.empty?
  elsif actual_pass.empty? || !same_declared_path?(actual_pass, expected_pass, root)
    errors << "#{label}: source_pass_through_keyframe_image_path must match the v3 manifest pass-through image"
  end

  actual_end = prompt["source_end_keyframe_image_path"].to_s
  distinct_end = !expected_end.empty? && !same_declared_path?(expected_end, expected_start, root)
  if distinct_end
    if actual_end.empty? || !same_declared_path?(actual_end, expected_end, root)
      errors << "#{label}: source_end_keyframe_image_path must match the distinct v3 manifest end image"
    end
  elsif !actual_end.empty? && (expected_end.empty? || !same_declared_path?(actual_end, expected_end, root))
    errors << "#{label}: source_end_keyframe_image_path does not match the v3 manifest end image"
  end
end

def validate_v3_index_owner_projection(index, manifest, prompts, root, manifest_path, review_path, errors)
  return unless manifest.is_a?(Hash) && manifest["schema_version"].to_s == "idol_video_prompt_manifest.v3"

  expected_review = manifest["source_review_record_path"].to_s
  index_review = index["source_review_record_path"].to_s
  unless same_declared_path?(index_review, expected_review, root) && same_declared_path?(review_path, expected_review, root)
    errors << "v3 index review owner must exactly match manifest.source_review_record_path"
  end

  expected_packets = manifest.dig("planning_projection_sources", "prompt_packets", "path").to_s
  index_packets = index["source_02b_prompt_packets_path"].to_s
  unless same_declared_path?(index_packets, expected_packets, root)
    errors << "v3 index source_02b_prompt_packets_path must exactly match manifest planning_projection_sources.prompt_packets.path"
  end

  expected_audio_motion = manifest["source_audio_motion_director_map_path"].to_s
  index_audio_motion = (index["source_audio_motion_director_map_path"] || index["source_audio_motion_map"]).to_s
  unless same_declared_path?(index_audio_motion, expected_audio_motion, root)
    errors << "v3 index audio-motion owner must exactly match manifest.source_audio_motion_director_map_path"
  end

  cues = v3_cues_by_packet(manifest, errors)
  Array(prompts).each_with_index do |prompt, index_value|
    next unless prompt.is_a?(Hash)

    packet_id = prompt["packet_id"].to_s
    label = packet_id.empty? ? "prompts[#{index_value}]" : packet_id
    explicit_manifest = (prompt["source_03v_video_prompt_manifest_path"] || prompt["source_video_prompt_manifest_path"]).to_s
    unless explicit_manifest.empty? || same_declared_path?(explicit_manifest, manifest_path, root)
      errors << "#{label}: per-prompt 03V manifest path must equal the index-level manifest owner"
    end
    cue = cues[packet_id]
    validate_v3_prompt_source_projection(prompt, cue, root, label, errors) if cue
  end
end

def validate_v3_index_projection(manifest, prompts, errors)
  unless manifest.is_a?(Hash) && manifest["schema_version"].to_s == "idol_video_prompt_manifest.v3"
    errors << "idol_video_prompt_index.v3 requires an idol_video_prompt_manifest.v3 source"
    return
  end

  cues_by_packet = v3_cues_by_packet(manifest, errors)

  seen_packets = Hash.new(0)
  Array(prompts).each_with_index do |prompt, index|
    next unless prompt.is_a?(Hash)

    packet_id = prompt["packet_id"].to_s
    label = packet_id.empty? ? "prompts[#{index}]" : packet_id
    cue = cues_by_packet[packet_id]
    if cue.nil?
      errors << "#{label}: no exact v3 manifest cue projection exists"
      next
    end
    seen_packets[packet_id] += 1

    prompt_cut_id = (prompt["cut_id"] || prompt["beat_id"]).to_s
    errors << "#{label}: cut_id/beat_id does not match v3 manifest cue" unless prompt_cut_id == cue["cut_id"].to_s
    errors << "#{label}: section does not match v3 manifest cue" unless prompt["section"].to_s == cue["section"].to_s

    %w[
      timeline
      source_group
      upstream_frame_lineage
      frame_subject_mode
      choreography_presence_policy
      control_profile
      visual_restatement_policy
      appearance_recovery_reason
      start_trigger
      camera_capture
      keyframe_boundary_contract
      pacing_timing
      audio_pressure
      visible_start_pose
      screen_motion_route
      body_route
      camera_route
      endpoint
      edit_handoff
      previous_next_continuity
      planning_carry
      choreography_bridge
      performance_direction_bridge
      choreography_recovery
      directing_grammar
      generation_qc
      negative
    ].each do |field|
      errors << "#{label}: #{field} must exactly project the v3 manifest cue" unless prompt[field] == cue[field]
    end

    policy = prompt["choreography_presence_policy"].to_s
    if %w[absent minimal_body_gaze_hold_guard].include?(policy)
      errors << "#{label}: #{policy} choreography policy forbids choreography_bridge" unless blank?(prompt["choreography_bridge"])
      errors << "#{label}: #{policy} choreography policy forbids choreography_recovery" unless prompt["choreography_recovery"].nil?
      errors << "#{label}: #{policy} choreography policy forbids the legacy body_route owner" unless blank?(prompt["body_route"])
    end
  end

  missing = cues_by_packet.keys.reject { |packet_id| seen_packets[packet_id] == 1 }
  duplicates = seen_packets.select { |_packet_id, count| count > 1 }.keys
  errors << "v3 index must project every manifest cue exactly once; missing: #{missing.join(', ')}" unless missing.empty?
  errors << "v3 index cannot duplicate manifest cue packets: #{duplicates.join(', ')}" unless duplicates.empty?
end

if self_test_v2_control
  # Synthetic transport calibration only. These values are not creative
  # examples and must never be admitted into an authoring context.
  policy_errors = []
  validate_v2_index_policy(
    {
      "prompt_authoring_policy" => {
        "default_control_profile" => "image_locked_motion_camera",
        "visual_source_authority" => "attached_image_pixels",
        "appearance_restatement_policy" => "drift_recovery_only",
        "camera_capture_axes" => V2_CAMERA_CAPTURE_FIELDS,
        "storyboard_assist" => {
          "default" => "off",
          "activation" => "founder_request_only",
          "schema_path" => "schemas/video-prompt-storyboard-assist.schema.json"
        }
      }
    },
    root,
    policy_errors
  )
  values = {
    "_video_prompt_contract_version" => "v2",
    "control_profile" => "image_locked_motion_camera",
    "visual_restatement_policy" => "image_lock_only",
    "audio_pressure" => "Synthetic pulse A starts marker translation and pulse B stops the test camera.",
    "start_audio_cue" => "synthetic pulse A",
    "end_audio_cue" => "synthetic pulse B",
    "visible_start_pose" => "Calibration marker A holds above reference line 1 inside test frame P1.",
    "previous_next_continuity" => "Carry marker A from test frame P0, then hold it at coordinate P2 for the next fixture row.",
    "prev_end_to_start" => "Carry marker A from coordinate P0 into the declared start frame P1.",
    "end_to_next_start" => "Keep test frame R1 and marker A at coordinate P2 until the next fixture row.",
    "edit_point_basis" => "Cut after marker A and the test camera both stop.",
    "start_trigger" => "On synthetic pulse A, marker A starts to lower from coordinate P1.",
    "body_route" => "Calibration marker A lowers from coordinate P1 to P2 and stops on reference line 2.",
    "camera_route" => "The test camera tracks from calibration coordinate X1 to X2, then stops.",
    "pacing_timing" => "Begin on pulse A, translate for two test intervals, then hold on pulse B.",
    "endpoint" => "Marker A is at coordinate P2 while the test camera holds on crop box R1.",
    "edit_handoff" => "Hold marker A and the stopped test camera for the next fixture row.",
    "camera_capture" => {
      "camera_height" => "calibration height H1",
      "shot_scale_distance" => "measurement distance D1",
      "direction_angle" => "test angle A1 from reference side L",
      "depth_framing" => "foreground plane F, marker plane M, and background plane B",
      "screen_placement_crop" => "marker A centered inside crop box R1"
    },
    "upload_pack_type" => "bridge-two-image"
  }
  compact_prompt = <<~PROMPT
    Use @image1 and @image2 as the complete visual source; keep visible appearance and scene unchanged.
    On synthetic pulse A, calibration marker A lowers from coordinate P1 to P2 and stops on reference line 2. The test camera tracks from calibration coordinate X1 to X2, then stops. Preserve calibration height H1, measurement distance D1, test angle A1, foreground plane F, marker plane M, background plane B, and crop box R1. Translate for two test intervals, then hold on pulse B. Keep marker A stopped at coordinate P2 for the next fixture row.
  PROMPT
  valid_errors = []
  validate_v2_authoring_truth("v2 valid", values, valid_errors)
  validate_v2_prompt_control("v2 valid", values, root, valid_errors)
  validate_prompt_text_semantics("v2 valid", compact_prompt, values, valid_errors)

  inventory_errors = []
  bloated_prompt = compact_prompt + " Preserve identities, styling, outfits, lighting, colors, body proportions, hair, makeup, and jewelry."
  validate_prompt_text_semantics("v2 inventory", bloated_prompt, values, inventory_errors)

  storyboard_errors = []
  storyboard_values = values.merge("control_profile" => "storyboard_assisted_3frame")
  validate_v2_prompt_control("v2 storyboard", storyboard_values, root, storyboard_errors)

  leaked_storyboard_errors = []
  leaked_storyboard_values = values.merge(
    "storyboard_assist_path" => "runs/2026-07-10/TEST/generations/video-prompts/storyboard-assist-v1.yaml",
    "storyboard_id" => "SB01"
  )
  validate_v2_prompt_control("v2 direct storyboard leak", leaked_storyboard_values, root, leaked_storyboard_errors)

  missing_truth_errors = []
  validate_v2_authoring_truth("v2 missing truth", {}, missing_truth_errors)

  abstract_control_errors = []
  abstract_values = values.merge(
    "body_route" => "Controlled pressure grows through the space.",
    "camera_capture" => V2_CAMERA_CAPTURE_FIELDS.to_h { |field| [field, "generic camera value"] }
  )
  validate_v2_prompt_control("v2 abstract control", abstract_values, root, abstract_control_errors)

  storyboard_upload_errors = []
  storyboard_upload_missing_errors = []
  storyboard_upload_hash_errors = []
  Dir.mktmpdir("idol-video-prompt-v2-upload-", "/private/tmp") do |directory|
    folder = Pathname.new(directory)
    storyboard_prompt = "Use @image1 as the storyboard timing and blocking map only; use @image2, @image3, and @image4 as the complete visual source frames.\n#{compact_prompt}"
    File.write((folder + "prompt.txt").to_s, storyboard_prompt)
    (1..4).each { |image_index| File.write((folder + "image#{image_index}.png").to_s, "fixture") }
    storyboard_references = (1..4).map do |image_index|
      image_path = folder + "image#{image_index}.png"
      {
        "reference_tag" => "@image#{image_index}",
        "sha256" => Digest::SHA256.file(image_path.to_s).hexdigest
      }
    end
    storyboard_semantics = v2_semantic_fields(
      values.merge("control_profile" => "storyboard_assisted_3frame"),
      "storyboard-assist",
      {"count" => 4, "references" => storyboard_references}
    )
    validate_upload_ready_folder("v2 storyboard upload", folder.to_s, "storyboard-assist", storyboard_semantics, root, storyboard_upload_errors)
    File.write((folder + "image3.png").to_s, "tampered")
    validate_upload_ready_folder("v2 storyboard upload tampered", folder.to_s, "storyboard-assist", storyboard_semantics, root, storyboard_upload_hash_errors)
    File.write((folder + "image3.png").to_s, "fixture")
    FileUtils.rm_f(folder + "image4.png")
    validate_upload_ready_folder("v2 storyboard upload missing", folder.to_s, "storyboard-assist", storyboard_semantics, root, storyboard_upload_missing_errors)
  end


  storyboard_reference_errors = []
  storyboard_reference_values = values.merge(
    "control_profile" => "storyboard_assisted_3frame",
    "_storyboard_reference_count" => 3
  )
  storyboard_missing_reference_prompt = "Use @image1 as the storyboard timing map and @image2 as the complete visual source.\n#{compact_prompt}"
  validate_prompt_text_semantics(
    "v2 storyboard missing reference",
    storyboard_missing_reference_prompt,
    storyboard_reference_values,
    storyboard_reference_errors
  )

  pack_profile_errors = []
  validate_upload_pack_profile_compatibility(
    "v2 storyboard wrong pack",
    "storyboard_assisted_3frame",
    "bridge-two-image",
    pack_profile_errors
  )
  validate_upload_pack_profile_compatibility(
    "v2 direct wrong pack",
    "image_locked_motion_camera",
    "storyboard-assist",
    pack_profile_errors
  )

  failures = policy_errors.dup
  failures.concat(valid_errors)
  failures << "appearance inventory negative case was not rejected" unless inventory_errors.any? { |error| error.include?("appearance inventory") }
  failures << "missing storyboard_assist_path negative case was not rejected" unless storyboard_errors.any? { |error| error.include?("storyboard_assist_path") }
  failures << "direct profile storyboard-field leak was not rejected" unless leaked_storyboard_errors.any? { |error| error.include?("must be omitted") }
  failures << "missing v2 authoring truth negative case was not rejected" unless missing_truth_errors.any? { |error| error.include?("start_audio_cue") }
  failures << "abstract v2 control negative case was not rejected" unless abstract_control_errors.any? { |error| error.include?("abstract generator language") || error.include?("concrete frame geometry") }
  failures.concat(storyboard_upload_errors)
  failures << "missing storyboard-assist image negative case was not rejected" unless storyboard_upload_missing_errors.any? { |error| error.include?("missing image4.png") }
  failures << "tampered storyboard-assist image negative case was not rejected" unless storyboard_upload_hash_errors.any? { |error| error.include?("authoritative storyboard/source SHA-256") }
  failures << "missing authoritative storyboard reference was not rejected" unless storyboard_reference_errors.any? { |error| error.include?("@image3") }
  failures << "storyboard control/upload pack mismatch was not rejected in both directions" unless pack_profile_errors.count { |error| error.include?("must be selected together") } == 2
  unless failures.empty?
    failures.each { |failure| warn "ERROR: #{failure}" }
    exit 1
  end

  puts "OK: v2 motion/camera-first control self-test passed"
  exit 0
end

if self_test_v3_projection
  # Synthetic transport calibration only. These values are not creative
  # examples and must never be admitted into an authoring context.
  cue = {
    "cut_id" => "C01",
    "section" => "S00",
    "upstream_frame_lineage" => {
      "placement_frame_id" => "FRAME_01",
      "packet_id" => "PKT_C01",
      "cut_id" => "C01",
      "section_id" => "S00"
    },
    "frame_subject_mode" => "world_object_led",
    "choreography_presence_policy" => "absent",
    "control_profile" => "image_locked_motion_camera",
    "visual_restatement_policy" => "image_lock_only",
    "start_trigger" => "On synthetic pulse A, calibration marker A starts to translate from coordinate P1.",
    "camera_capture" => {
      "camera_height" => "calibration height H1",
      "shot_scale_distance" => "measurement distance D1",
      "direction_angle" => "test angle A1 from reference side L",
      "depth_framing" => "foreground plane F, marker plane M, and background plane B",
      "screen_placement_crop" => "marker A centered inside crop box R1"
    },
    "keyframe_boundary_contract" => {
      "start_audio_cue" => "synthetic pulse A",
      "start_keyframe" => {},
      "end_audio_cue" => "synthetic pulse B",
      "end_keyframe" => {},
      "motion_between_keyframes" => "marker A translates from coordinate P1 to P2 and stops",
      "prev_end_to_start" => "carry marker A from fixture coordinate P0",
      "end_to_next_start" => "hold marker A at fixture coordinate P2",
      "edit_point_basis" => "cut when marker A stops on pulse B",
      "single_keyframe_exception" => "synthetic marker hold"
    },
    "pacing_timing" => "Translate on pulse A and stop on pulse B.",
    "audio_pressure" => "Synthetic pulse A starts marker translation and pulse B stops it.",
    "visible_start_pose" => "Calibration marker A holds at coordinate P1 inside test frame R1.",
    "screen_motion_route" => "Calibration marker A translates from coordinate P1 to P2 and stops.",
    "camera_route" => "The test camera tracks from calibration coordinate X1 to X2, then stops.",
    "endpoint" => "Calibration marker A remains at coordinate P2.",
    "edit_handoff" => "Hold marker A at coordinate P2 for the next fixture row.",
    "previous_next_continuity" => "Carry marker A from fixture coordinate P0, then hand off its hold at coordinate P2.",
    "planning_carry" => {
      "source_02a_cut_id" => "C01",
      "source_02b_packet_ids" => ["PKT_C01"]
    }
  }
  manifest = {
    "schema_version" => "idol_video_prompt_manifest.v3",
    "status" => "ready_for_prompt_authoring",
    "cues" => [cue]
  }
  valid_prompt = Marshal.load(Marshal.dump(cue)).merge(
    "packet_id" => "PKT_C01",
    "beat_id" => "C01"
  )
  valid_errors = []
  validate_v3_index_projection(manifest, [valid_prompt], valid_errors)

  drifted_prompt = Marshal.load(Marshal.dump(valid_prompt))
  drifted_prompt["screen_motion_route"] = "Something cinematic happens."
  projection_errors = []
  validate_v3_index_projection(manifest, [drifted_prompt], projection_errors)

  start_drift_prompt = Marshal.load(Marshal.dump(valid_prompt))
  start_drift_prompt["start_trigger"] = "Synthetic pulse C starts a different fixture transition."
  start_drift_errors = []
  validate_v3_index_projection(manifest, [start_drift_prompt], start_drift_errors)

  dance_prompt = Marshal.load(Marshal.dump(valid_prompt))
  dance_prompt["screen_motion_route"] = "Perform a clear K-pop dance phrase while calibration marker A remains in frame."
  dance_errors = []
  validate_v3_index_projection(manifest, [dance_prompt], dance_errors)
  generator_dance_errors = []
  validate_prompt_text_semantics(
    "v3 absent generator prompt",
    "Use @image1 as the complete visual source. Perform a clear K-pop dance phrase and hold.",
    {
      "_video_prompt_contract_version" => "v3",
      "choreography_presence_policy" => "absent"
    },
    generator_dance_errors
  )
  korean_dance_errors = []
  validate_prompt_text_semantics(
    "v3 absent Korean dance prompt",
    "Use @image1 as the complete visual source. 멤버들이 강한 군무와 팝핑 안무를 이어가며 끝에서 멈춘다.",
    {
      "_video_prompt_contract_version" => "v3",
      "choreography_presence_policy" => "absent"
    },
    korean_dance_errors
  )
  camera_locking_errors = []
  validate_prompt_text_semantics(
    "v3 absent camera locking prompt",
    "Use @image1 as the complete visual source. The test camera keeps locking on calibration marker A while it lies flat.",
    {
      "_video_prompt_contract_version" => "v3",
      "choreography_presence_policy" => "absent"
    },
    camera_locking_errors
  )
  negated_dance_errors = []
  validate_prompt_text_semantics(
    "v3 absent negated dance prompt",
    "Use @image1 as the complete visual source. No dance or choreography is added; calibration marker A lies flat.",
    {
      "_video_prompt_contract_version" => "v3",
      "choreography_presence_policy" => "absent"
    },
    negated_dance_errors
  )

  failures = valid_errors.dup
  failures << "v3 projection drift was not rejected" unless projection_errors.any? { |error| error.include?("screen_motion_route must exactly project") }
  failures << "v3 start_trigger drift was not rejected" unless start_drift_errors.any? { |error| error.include?("start_trigger must exactly project") }
  failures << "v3 choreography-field drift was not rejected as exact projection drift" unless dance_errors.any? { |error| error.include?("screen_motion_route must exactly project") }
  failures << "v3 generator prose was mechanically judged from dance vocabulary" unless generator_dance_errors.empty?
  failures << "v3 Korean generator prose was mechanically judged from dance vocabulary" unless korean_dance_errors.empty?
  failures << "v3 negated generator prose was mechanically judged from dance vocabulary" unless negated_dance_errors.empty?
  failures << "v3 camera prose was mechanically judged from vocabulary" unless camera_locking_errors.empty?
  unless failures.empty?
    failures.each { |failure| warn "ERROR: #{failure}" }
    exit 1
  end

  puts "OK: v3 manifest-to-index exact projection passes; generator creativity is section-LLM reviewed"
  exit 0
end

if self_test_v3_review
  Dir.mktmpdir("idol-03v-review-self-test-") do |dir|
    test_root = Pathname.new(dir)
    index_file = test_root.join("video-prompt-index.yaml")
    index_file.write(YAML.dump("schema_version" => "idol_video_prompt_index.v3"), encoding: "utf-8")
    index_sha = Digest::SHA256.file(index_file.to_s).hexdigest
    used_paths = Set.new
    used_sessions = Set.new
    review_errors = []

    section_record = {
      "schema_version" => "idol-03v-creative-context-review-execution-record.v1",
      "producer" => "registered_codex_03v_reviewer_runner",
      "surface_owner" => "codex",
      "session_type" => "codex_section_review",
      "role_id" => "idol-03v-section-context-reviewer",
      "session_id" => "section-session-s00",
      "profile" => "sol_xhigh",
      "source_video_prompt_index_sha256" => index_sha,
      "assigned_section_ids" => ["S00"],
      "completion_state" => "completed",
      "canonical_semantic_write_performed" => false
    }
    section_path = test_root.join("section.yaml")
    section_path.write(YAML.dump(section_record), encoding: "utf-8")
    validate_03v_review_execution_record(
      {"path" => section_path.to_s, "sha256" => Digest::SHA256.file(section_path.to_s).hexdigest},
      root: test_root,
      index_sha: index_sha,
      expected_sections: ["S00"],
      owner_route: "codex_sol_xhigh",
      role: :section,
      used_paths: used_paths,
      used_sessions: used_sessions,
      errors: review_errors,
      label: "self-test section"
    )

    root_record = section_record.merge(
      "session_type" => "codex_root_reconciliation",
      "role_id" => "idol-03v-whole-timeline-reconciler",
      "session_id" => "root-session",
      "assigned_section_ids" => ["S00", "S01"]
    )
    root_path = test_root.join("root.yaml")
    root_path.write(YAML.dump(root_record), encoding: "utf-8")
    validate_03v_review_execution_record(
      {"path" => root_path.to_s, "sha256" => Digest::SHA256.file(root_path.to_s).hexdigest},
      root: test_root,
      index_sha: index_sha,
      expected_sections: ["S00", "S01"],
      owner_route: "codex_sol_xhigh",
      role: :whole_timeline,
      used_paths: used_paths,
      used_sessions: used_sessions,
      errors: review_errors,
      label: "self-test root"
    )

    invalid_errors = []
    invalid_record = section_record.merge("surface_owner" => "grok", "session_id" => "invalid-session")
    invalid_path = test_root.join("invalid.yaml")
    invalid_path.write(YAML.dump(invalid_record), encoding: "utf-8")
    validate_03v_review_execution_record(
      {"path" => invalid_path.to_s, "sha256" => Digest::SHA256.file(invalid_path.to_s).hexdigest},
      root: test_root,
      index_sha: index_sha,
      expected_sections: ["S00"],
      owner_route: "codex_sol_xhigh",
      role: :section,
      used_paths: Set.new,
      used_sessions: Set.new,
      errors: invalid_errors,
      label: "self-test invalid"
    )
    review_errors << "cross-surface execution drift was not rejected" unless invalid_errors.any? { |error| error.include?("surface_owner codex") }

    unless review_errors.empty?
      review_errors.each { |error| warn "ERROR: #{error}" }
      exit 1
    end
  end

  puts "OK: v3 contextual review execution provenance self-test passed"
  exit 0
end

index_resolved = resolve_path(index_path, root)
index = load_yaml_hash(index_resolved, "video prompt index", errors)

index_schema_version = index["schema_version"].to_s
unless %w[idol_video_prompt_index.v1 idol_video_prompt_index.v2 idol_video_prompt_index.v3].include?(index_schema_version)
  errors << "schema_version must be idol_video_prompt_index.v1, idol_video_prompt_index.v2, or idol_video_prompt_index.v3"
end
v2_index = index_schema_version == "idol_video_prompt_index.v2"
v3_index = index_schema_version == "idol_video_prompt_index.v3"
control_index = v2_index || v3_index
validate_v2_index_policy(index, root, errors) if control_index

creator = index["created_by"].to_s
if creator.empty? && index["schema_version"].to_s == "idol_video_prompt_index.v1" && index["note"].to_s.match?(/\bCodex\b/)
  warnings << "created_by is missing; inferred Codex from section-keyframe index note"
elsif creator.empty?
  errors << "created_by is required"
elsif !creator.match?(/\b(Codex|Grok app\/TUI\/CLI)\b/)
  errors << "created_by must identify Codex or Grok app/TUI/CLI"
end

source_02b_prompt_packets_path = index["source_02b_prompt_packets_path"]
unless blank?(source_02b_prompt_packets_path)
  resolved = resolve_path(source_02b_prompt_packets_path, root)
  errors << "source_02b_prompt_packets_path is not readable: #{source_02b_prompt_packets_path}" unless readable_path?(resolved)
end

source_02b_export_index_path = index["source_02b_export_index_path"]
unless blank?(source_02b_export_index_path)
  resolved = resolve_path(source_02b_export_index_path, root)
  errors << "source_02b_export_index_path is not readable: #{source_02b_export_index_path}" unless readable_path?(resolved)
end

{
  "source_section_keyframe_manifest_path" => index["source_section_keyframe_manifest_path"] || index["source_keyframe_manifest"],
  "source_section_directing_grammar_path" => index["source_section_directing_grammar_path"] || index["source_directing_grammar"],
  "source_section_keyframe_qc_path" => index["source_section_keyframe_qc_path"]
}.each do |field, path_value|
  next if blank?(path_value)

  resolved = resolve_path(path_value, root)
  errors << "#{field} is not readable: #{path_value}" unless readable_path?(resolved)
end

audio_motion_path = index["source_audio_motion_director_map_path"] || index["source_audio_motion_map"]
cue_bpm_path = index["source_cue_bpm_map_path"]
if blank?(audio_motion_path) && blank?(cue_bpm_path)
  errors << "source_audio_motion_director_map_path or source_cue_bpm_map_path is required for song-led video prompt readiness"
end

audio_motion_slots = {}
unless blank?(audio_motion_path)
  audio_motion_resolved = resolve_path(audio_motion_path, root)
  audio_motion_doc = load_yaml_hash(audio_motion_resolved, "audio motion director map", errors)
  if audio_motion_doc.any?
    audio_motion_records = audio_motion_doc["slot_motion_map"]
    if audio_motion_records.is_a?(Array)
      audio_motion_records.each do |entry|
        next unless entry.is_a?(Hash)

        audio_motion_slots[entry["slot"].to_s] = entry
      end
    else
      errors << "audio motion director map slot_motion_map must contain records"
    end
  end
end

cue_bpm_slots = {}
unless blank?(cue_bpm_path)
  cue_bpm_resolved = resolve_path(cue_bpm_path, root)
  cue_bpm_doc = load_yaml_hash(cue_bpm_resolved, "cue BPM map", errors)
  if cue_bpm_doc.any?
    cue_records = cue_bpm_doc["cue_tempo_map"]
    if cue_records.is_a?(Array)
      cue_records.each do |entry|
        next unless entry.is_a?(Hash)

        cue_bpm_slots[entry["slot"].to_s] = entry
      end
    else
      errors << "cue BPM map cue_tempo_map must contain records"
    end
  end
end

motion_count_guide_path = index["source_motion_count_guide_path"] || index["source_motion_count_guide"]
unless blank?(motion_count_guide_path)
  motion_count_guide_resolved = resolve_path(motion_count_guide_path, root)
  errors << "source_motion_count_guide_path is not readable: #{motion_count_guide_path}" unless readable_path?(motion_count_guide_resolved)
end

video_prompt_manifest_validation_cache = {}
video_prompt_manifest_path = index["source_03v_video_prompt_manifest_path"] || index["source_video_prompt_manifest_path"]
video_prompt_manifest_doc = {}
unless blank?(video_prompt_manifest_path)
  video_prompt_manifest_resolved = resolve_path(video_prompt_manifest_path, root)
  errors << "source_03v_video_prompt_manifest_path is not readable: #{video_prompt_manifest_path}" unless readable_path?(video_prompt_manifest_resolved)
  validate_video_prompt_manifest_semantics(video_prompt_manifest_path, root, video_prompt_manifest_validation_cache, errors, "index")
  video_prompt_manifest_doc = load_yaml_hash(video_prompt_manifest_resolved, "03V video prompt manifest", errors) if readable_path?(video_prompt_manifest_resolved)
end

review_path = ARGV[1] || index["source_review_record_path"]
review_resolved = resolve_path(review_path, root)
review = {}

if review_path.to_s.strip.empty?
  errors << "source_review_record_path is required in index or as the second argument"
else
  review = load_yaml_hash(review_resolved, "03-review", errors)
end

allowed_skills = %w[
  idol-video-prompt
].freeze
legacy_skills = [].freeze  # Retired skill names have been fully removed from the repository
allowed_prompt_statuses = %w[
  draft
  codex_draft
  codex_prepared_handoff_draft_not_grok_final
  founder_review
  ready_for_founder
  ready_for_founder_review
  selected
  complete
  hold
].freeze

prompts = index["prompts"]
if !prompts.is_a?(Array) || prompts.empty?
  errors << "index.prompts must contain at least one prompt record"
  prompts = []
end

validate_index_manifest_readiness(index_schema_version, index, video_prompt_manifest_doc, prompts, errors)
if v3_index
  validate_v3_index_projection(video_prompt_manifest_doc, prompts, errors)
  validate_v3_index_owner_projection(
    index,
    video_prompt_manifest_doc,
    prompts,
    root,
    video_prompt_manifest_path,
    review_path,
    errors
  )
end
v3_manifest_cues = if v3_index
                      Array(video_prompt_manifest_doc["cues"]).each_with_object({}) do |cue, values|
                        next unless cue.is_a?(Hash)
                        packet_id = cue.dig("upstream_frame_lineage", "packet_id").to_s
                        values[packet_id] = cue unless packet_id.empty?
                      end
                    else
                      {}
                    end

upload_pack_records = []
storyboard_assist_validation_cache = {}

review_records = review["board_reviews"].is_a?(Array) ? review["board_reviews"] : []
review_by_packet = review_records.to_h { |entry| [entry["packet_id"].to_s, entry] }
founder_operator_surface = index.dig("record_rule", "founder_operator_surface").to_s
founder_operator_surface_path = resolve_path(founder_operator_surface, root)
if !blank?(founder_operator_surface) && !dir_path?(founder_operator_surface_path)
  errors << "record_rule.founder_operator_surface directory is not readable: #{founder_operator_surface}"
end

if review.any? && review_records.empty?
  errors << "03-review.board_reviews must contain review records"
end

prompts.each_with_index do |prompt, idx|
  label = prompt.is_a?(Hash) ? (prompt["packet_id"] || prompt["source_keyframe_id"] || prompt["id"]).to_s : "prompts[#{idx}]"
  unless prompt.is_a?(Hash)
    errors << "prompts[#{idx}] must be a mapping"
    next
  end

  validation_values = if control_index
                        prompt.merge("_video_prompt_contract_version" => (v3_index ? "v3" : "v2"))
                      else
                        prompt
                      end

  packet_id = prompt["packet_id"].to_s
  v3_manifest_cue = v3_manifest_cues[packet_id]
  beat_id = prompt["beat_id"].to_s
  founder_status = prompt["founder_review_status"].to_s
  source_review_image = prompt["source_review_board_image_path"].to_s
  source_section_keyframe_image = (prompt["source_section_keyframe_image_path"] || prompt["source_keyframe_image_path"]).to_s
  source_start_keyframe_image = prompt["source_start_keyframe_image_path"].to_s
  source_pass_through_keyframe_image = prompt["source_pass_through_keyframe_image_path"].to_s
  source_end_keyframe_image = prompt["source_end_keyframe_image_path"].to_s
  source_visual_lock_path = prompt["source_visual_lock_path"].to_s
  source_visual_lock_type = prompt["source_visual_lock_type"].to_s
  source_image = if !source_visual_lock_path.empty?
                   source_visual_lock_path
                 elsif !source_section_keyframe_image.empty?
                   source_section_keyframe_image
                 elsif !source_start_keyframe_image.empty?
                   source_start_keyframe_image
                 else
                   source_review_image
                 end
  selected_skill = (prompt["selected_skill"] || prompt["intended_grok_skill"]).to_s
  app_alias_used = (prompt["app_alias_used"] || prompt["current_grok_app_alias"]).to_s
  skill_reason = prompt["skill_selection_reason"].to_s
  audio_motion_slot = prompt["audio_motion_slot"].to_s
  motion_count_summary = (prompt["motion_count_summary"] || prompt["applied_motion_note"]).to_s
  output_prompt = prompt["output_prompt_path"].to_s
  prompt_status = prompt["prompt_status"].to_s
  source_prompt_export = prompt["source_02b_prompt_export_path"].to_s
  source_manifest = prompt["source_02b_manifest_path"].to_s
  source_compiled_hash = prompt["source_compiled_prompt_hash"].to_s
  prompt_03v_manifest = (prompt["source_03v_video_prompt_manifest_path"] || prompt["source_video_prompt_manifest_path"] || video_prompt_manifest_path).to_s
  prompt_section_manifest = (prompt["source_section_keyframe_manifest_path"] || index["source_section_keyframe_manifest_path"] || index["source_keyframe_manifest"]).to_s
  prompt_section_keyframe_id = (prompt["source_section_keyframe_id"] || prompt["source_keyframe_id"]).to_s
  upload_pack_type = prompt["upload_pack_type"].to_s
  upload_pack_folder = prompt["upload_pack_folder"].to_s
  bridge_image_count = [source_start_keyframe_image, source_pass_through_keyframe_image, source_end_keyframe_image].reject(&:empty?).length
  section_keyframe_mode = !source_section_keyframe_image.empty? || !source_start_keyframe_image.empty? || !prompt_section_keyframe_id.empty?
  bridge_mode = source_visual_lock_type == "section_keyframe_sequence" || bridge_image_count >= 2
  exact_upload_sources = {}
  if v3_manifest_cue && %w[bridge-two-image single-beat].include?(upload_pack_type)
    cue_images = v3_manifest_cue["source_images"].is_a?(Hash) ? v3_manifest_cue["source_images"] : {}
    start_source = resolve_path(cue_images["start_image"], root)
    exact_upload_sources["image1"] = start_source if start_source
    if upload_pack_type == "bridge-two-image"
      end_source = resolve_path(cue_images["end_image"], root)
      exact_upload_sources["image2"] = end_source if end_source
    end
  end
  canonical_prompt_for_copy = resolve_path(output_prompt, root)

  if beat_id.empty? && section_keyframe_mode
    beat_id = prompt["id"].to_s
  end
  errors << "#{label}: beat_id is required" if beat_id.empty? && !section_keyframe_mode
  errors << "#{label}: packet_id is required" if packet_id.empty? && !section_keyframe_mode
  if founder_status != "pass"
    if section_keyframe_mode && prompt_status.include?("draft")
      warnings << "#{label}: founder_review_status is not pass; section-keyframe prompt remains draft-only"
    else
      errors << "#{label}: founder_review_status must be pass"
    end
  end
  unless source_visual_lock_type.empty? || %w[passed_review_board section_keyframe_image section_keyframe_sequence].include?(source_visual_lock_type)
    errors << "#{label}: source_visual_lock_type must be passed_review_board, section_keyframe_image, or section_keyframe_sequence"
  end
  if legacy_skills.include?(selected_skill)
    errors << "#{label}: selected_skill #{selected_skill} is retired; translate any old lane intent into idol-video-prompt and set selected_skill idol-video-prompt"
  elsif !allowed_skills.include?(selected_skill)
    errors << "#{label}: selected_skill must be one of #{allowed_skills.join(', ')}"
  end
  errors << "#{label}: app_alias_used/current_grok_app_alias is retired; leave it empty and use selected_skill idol-video-prompt" unless app_alias_used.empty?
  errors << "#{label}: skill_selection_reason is required" if skill_reason.empty?
  if !blank?(audio_motion_path)
    errors << "#{label}: audio_motion_slot is required when source_audio_motion_director_map_path is set" if audio_motion_slot.empty?
    if !audio_motion_slot.empty? && !audio_motion_slots.key?(audio_motion_slot)
      errors << "#{label}: audio_motion_slot #{audio_motion_slot} is missing from audio motion director map"
    end
  end
  unless blank?(motion_count_guide_path)
    prompt_motion_guide_path = (prompt["source_motion_count_guide_path"] || index["source_motion_count_guide_path"] || index["source_motion_count_guide"]).to_s
    errors << "#{label}: source_motion_count_guide_path is required when index source_motion_count_guide_path is set" if prompt_motion_guide_path.empty?
    errors << "#{label}: motion_count_summary is required when source_motion_count_guide_path is set" if motion_count_summary.empty?
    if !prompt_motion_guide_path.empty?
      expected = normalized_existing_path(motion_count_guide_path, root)
      actual = normalized_existing_path(prompt_motion_guide_path, root)
      errors << "#{label}: source_motion_count_guide_path is not readable: #{prompt_motion_guide_path}" unless actual
      if expected && actual && expected != actual
        errors << "#{label}: source_motion_count_guide_path does not match index source_motion_count_guide_path"
      end
    end
  end
  unless blank?(prompt_03v_manifest)
    prompt_03v_manifest_path = resolve_path(prompt_03v_manifest, root)
    errors << "#{label}: source_03v_video_prompt_manifest_path is not readable: #{prompt_03v_manifest}" unless readable_path?(prompt_03v_manifest_path)
    validate_video_prompt_manifest_semantics(prompt_03v_manifest, root, video_prompt_manifest_validation_cache, errors, label)
  end

  unless blank?(cue_bpm_path)
    cue_slot = prompt["cue_slot"].to_s
    tempo_pulse_summary = prompt["tempo_pulse_summary"].to_s
    audio_cue_summary = prompt["audio_cue_summary"].to_s

    errors << "#{label}: cue_slot is required when source_cue_bpm_map_path is set" if cue_slot.empty?
    errors << "#{label}: tempo_pulse_summary is required when source_cue_bpm_map_path is set" if tempo_pulse_summary.empty?
    errors << "#{label}: audio_cue_summary is required when source_cue_bpm_map_path is set" if audio_cue_summary.empty?

    cue_record = cue_bpm_slots[cue_slot]
    if !cue_slot.empty? && cue_record.nil?
      errors << "#{label}: cue_slot #{cue_slot} is missing from cue BPM map"
    elsif cue_record
      expected_tempo = cue_record["tempo_pulse_summary"].to_s
      expected_audio = cue_record["audio_cue_summary"].to_s
      if tempo_pulse_summary != expected_tempo
        errors << "#{label}: tempo_pulse_summary does not match cue BPM map for #{cue_slot}"
      end
      if audio_cue_summary != expected_audio
        errors << "#{label}: audio_cue_summary does not match cue BPM map for #{cue_slot}"
      end
    end
  end
  errors << "#{label}: prompt_status is required" if prompt_status.empty?
  if !prompt_status.empty? && !allowed_prompt_statuses.include?(prompt_status)
    errors << "#{label}: unsupported prompt_status #{prompt_status}"
  end
  unless source_prompt_export.empty?
    source_prompt_export_path = resolve_path(source_prompt_export, root)
    errors << "#{label}: source_02b_prompt_export_path is not readable: #{source_prompt_export}" unless readable_path?(source_prompt_export_path)
  end
  unless source_manifest.empty?
    source_manifest_path = resolve_path(source_manifest, root)
    errors << "#{label}: source_02b_manifest_path is not readable: #{source_manifest}" unless readable_path?(source_manifest_path)
  end
  if !source_manifest.empty? && source_prompt_export.empty?
    errors << "#{label}: source_02b_prompt_export_path is required when source_02b_manifest_path is set"
  end
  if !source_compiled_hash.empty? && !source_compiled_hash.match?(/\A[a-f0-9]{16,64}\z/i)
    warnings << "#{label}: source_compiled_prompt_hash does not look like a compact hex hash"
  end
  unless prompt_section_manifest.empty?
    prompt_section_manifest_path = resolve_path(prompt_section_manifest, root)
    errors << "#{label}: source_section_keyframe_manifest_path is not readable: #{prompt_section_manifest}" unless readable_path?(prompt_section_manifest_path)
    errors << "#{label}: source_section_keyframe_id is required when source_section_keyframe_manifest_path is set" if prompt_section_keyframe_id.empty?
  end

  {
    "source_start_keyframe_image_path" => source_start_keyframe_image,
    "source_pass_through_keyframe_image_path" => source_pass_through_keyframe_image,
    "source_end_keyframe_image_path" => source_end_keyframe_image
  }.each do |field, path_value|
    next if blank?(path_value)

    resolved = resolve_path(path_value, root)
    errors << "#{label}: #{field} is not readable: #{path_value}" unless readable_path?(resolved)
  end
  if bridge_mode
    errors << "#{label}: source_start_keyframe_image_path is required for section_keyframe_sequence" if source_start_keyframe_image.empty?
    errors << "#{label}: source_end_keyframe_image_path is required for section_keyframe_sequence" if source_end_keyframe_image.empty?
    unless control_index
      %w[motion_bridge_summary bridge_body_route bridge_camera_plan bridge_landing].each do |field|
        errors << "#{label}: #{field} is required for section keyframe sequence bridge prompts" if blank?(prompt[field])
      end
    end
  end

  storyboard_reference_bundle = nil
  storyboard_reference_count = nil
  if control_index
    validate_v2_authoring_truth(label, validation_values, errors)
    validate_v2_prompt_control(label, validation_values, root, errors)
    storyboard_reference_bundle = validate_storyboard_assist_artifact(
      label,
      validation_values,
      index_resolved,
      root,
      storyboard_assist_validation_cache,
      errors
    )
    storyboard_reference_count = storyboard_reference_bundle["count"] if storyboard_reference_bundle.is_a?(Hash)
    validation_values["_storyboard_reference_count"] = storyboard_reference_count if storyboard_reference_count
  else
    validate_semantic_bridge(label, prompt, errors)
  end

  validate_upload_pack_profile_compatibility(label, prompt["control_profile"], upload_pack_type, errors) if control_index

  unless upload_pack_type.empty?
    unless %w[bridge-two-image single-beat storyboard-assist].include?(upload_pack_type)
      errors << "#{label}: upload_pack_type must be bridge-two-image, single-beat, or storyboard-assist"
    end
    if upload_pack_type == "storyboard-assist" && (!control_index || prompt["control_profile"].to_s != "storyboard_assisted_3frame")
      errors << "#{label}: storyboard-assist upload packs require the v2 storyboard_assisted_3frame control profile"
    end
    errors << "#{label}: upload_pack_folder is required when upload_pack_type is set" if upload_pack_folder.empty?

    upload_pack_folder_path = resolve_path(upload_pack_folder, root)
    if upload_pack_folder.empty?
      upload_pack_folder_path = nil
    elsif !dir_path?(upload_pack_folder_path)
      errors << "#{label}: upload_pack_folder is not a directory: #{upload_pack_folder}"
    end

    if upload_pack_type == "bridge-two-image"
      errors << "#{label}: bridge-two-image upload pack must use source_visual_lock_type section_keyframe_sequence" unless source_visual_lock_type == "section_keyframe_sequence"
      errors << "#{label}: bridge-two-image upload pack must keep @image1 and @image2 in one clip, so source_start_keyframe_image_path is required" if source_start_keyframe_image.empty?
      errors << "#{label}: bridge-two-image upload pack must keep @image1 and @image2 in one clip, so source_end_keyframe_image_path is required" if source_end_keyframe_image.empty?
      errors << "#{label}: bridge-two-image upload pack must not set source_pass_through_keyframe_image_path; create a separate pack type before using a third attachment" unless source_pass_through_keyframe_image.empty?
      if upload_pack_folder_path
        errors << "#{label}: bridge-two-image upload_pack_folder must live under a bridge-two-image directory" unless path_in_segment?(upload_pack_folder_path, "bridge-two-image")
        {
          "image1.png" => "bridge-two-image upload pack @image1",
          "image2.png" => "bridge-two-image upload pack @image2",
          "prompt.txt" => "bridge-two-image upload pack prompt"
        }.each do |filename, description|
          candidate = upload_pack_folder_path + filename
          errors << "#{label}: #{description} is not readable: #{candidate}" unless readable_path?(candidate)
        end
        validate_exact_file_copy("#{label} typed upload image1.png", upload_pack_folder_path + "image1.png", exact_upload_sources["image1"], errors) if exact_upload_sources["image1"]
        validate_exact_file_copy("#{label} typed upload image2.png", upload_pack_folder_path + "image2.png", exact_upload_sources["image2"], errors) if exact_upload_sources["image2"]
        validate_exact_prompt_copy("#{label} typed upload prompt", upload_pack_folder_path + "prompt.txt", canonical_prompt_for_copy, errors) if v3_index && canonical_prompt_for_copy
      end
    elsif upload_pack_type == "single-beat"
      unless %w[section_keyframe_image passed_review_board].include?(source_visual_lock_type)
        errors << "#{label}: single-beat upload pack must use source_visual_lock_type section_keyframe_image or passed_review_board"
      end
      single_keyframe_exception = if v3_index
                                    keyframe_boundary_value(prompt, "single_keyframe_exception").strip
                                  else
                                    prompt["single_keyframe_exception"].to_s.strip
                                  end
      if single_keyframe_exception.empty? || single_keyframe_exception.match?(/\A(?:none|n\/a|not applicable)\z/i)
        errors << "#{label}: single-beat upload pack requires single_keyframe_exception explaining why one frame is musically and editorially valid"
      end
      if [source_start_keyframe_image, source_pass_through_keyframe_image, source_end_keyframe_image].any? { |value| !value.empty? }
        errors << "#{label}: single-beat upload pack must be one source image only; do not attach start/pass-through/end bridge images"
      end
      if upload_pack_folder_path
        errors << "#{label}: single-beat upload_pack_folder must live under a single-beat directory" unless path_in_segment?(upload_pack_folder_path, "single-beat")
        {
          "image1.png" => "single-beat upload pack @image1",
          "prompt.txt" => "single-beat upload pack prompt"
        }.each do |filename, description|
          candidate = upload_pack_folder_path + filename
          errors << "#{label}: #{description} is not readable: #{candidate}" unless readable_path?(candidate)
        end
        validate_exact_file_copy("#{label} typed upload image1.png", upload_pack_folder_path + "image1.png", exact_upload_sources["image1"], errors) if exact_upload_sources["image1"]
        validate_exact_prompt_copy("#{label} typed upload prompt", upload_pack_folder_path + "prompt.txt", canonical_prompt_for_copy, errors) if v3_index && canonical_prompt_for_copy
        image2_candidate = upload_pack_folder_path + "image2.png"
        errors << "#{label}: single-beat upload pack must not contain image2.png: #{image2_candidate}" if readable_path?(image2_candidate)
      end
    elsif upload_pack_type == "storyboard-assist"
      unless (2..4).cover?(storyboard_reference_count.to_i)
        errors << "#{label}: storyboard-assist must resolve 2-4 references from the authoritative assist artifact"
      end
      if upload_pack_folder_path
        errors << "#{label}: storyboard-assist upload_pack_folder must live under a storyboard-assist directory" unless path_in_segment?(upload_pack_folder_path, "storyboard-assist")
        errors << "#{label}: storyboard-assist upload pack prompt is not readable" unless readable_path?(upload_pack_folder_path + "prompt.txt")
        (1..storyboard_reference_count.to_i).each do |image_index|
          candidate = upload_pack_folder_path + "image#{image_index}.png"
          if readable_path?(candidate)
            validate_storyboard_reference_copy(
              label,
              image_index,
              candidate,
              {"storyboard_references" => storyboard_reference_bundle&.fetch("references", [])},
              errors
            )
          else
            errors << "#{label}: storyboard-assist upload pack @image#{image_index} is not readable: #{candidate}"
          end
        end
        ((storyboard_reference_count.to_i + 1)..4).each do |image_index|
          candidate = upload_pack_folder_path + "image#{image_index}.png"
          errors << "#{label}: storyboard-assist upload pack has undeclared image#{image_index}.png: #{candidate}" if readable_path?(candidate)
        end
      end
    end

    semantic_fields = if control_index
                        v2_semantic_fields(validation_values, upload_pack_type, storyboard_reference_bundle)
                      else
                        REQUIRED_SEMANTIC_FIELDS.keys.to_h { |field| [field, semantic_field_value(prompt, field)] }.merge(
                          "bridge_camera_technique" => prompt["bridge_camera_technique"].to_s,
                          "upload_pack_type" => upload_pack_type
                        )
                      end
    upload_ready_folder = upload_ready_folder_for(founder_operator_surface, prompt, idx, root)
    if !blank?(founder_operator_surface)
      if blank?(upload_ready_folder)
        errors << "#{label}: upload-ready folder could not be found under record_rule.founder_operator_surface"
      else
        validate_upload_ready_folder(
          label,
          upload_ready_folder,
          upload_pack_type,
          semantic_fields,
          root,
          errors,
          exact_sources: exact_upload_sources,
          canonical_prompt_path: (v3_index ? canonical_prompt_for_copy : nil)
        )
      end
    end

    upload_pack_records << {
      "label" => label,
      "packet_id" => packet_id,
      "beat_id" => beat_id,
      "section" => prompt["section"].to_s,
      "timeline" => prompt["timeline"].to_s,
      "upload_pack_type" => upload_pack_type,
      "upload_pack_folder" => upload_pack_folder,
      "semantic_fields" => semantic_fields,
      "exact_upload_sources" => exact_upload_sources,
      "canonical_prompt_path" => canonical_prompt_for_copy,
      "v3_contract" => v3_index
    }
  end

  source_image_path = resolve_path(source_image, root)
  if source_image.empty?
    errors << "#{label}: a source visual lock image is required"
  elsif !readable_path?(source_image_path)
    errors << "#{label}: source visual lock image is not readable: #{source_image}"
  end

  output_prompt_path = resolve_path(output_prompt, root)
  if output_prompt.empty?
    errors << "#{label}: output_prompt_path is required"
  elsif !readable_path?(output_prompt_path)
    errors << "#{label}: output prompt file is not readable: #{output_prompt}"
  else
    text = File.read(output_prompt_path)
    unless text.match?(/Founder Review Status\**\s*:?\**\s*pass/i) || (section_keyframe_mode && prompt_status.include?("draft"))
      errors << "#{label}: output prompt file must state Founder Review Status: pass"
    end
    unless text.include?(selected_skill)
      errors << "#{label}: output prompt file must include selected skill #{selected_skill}"
    end
    validate_prompt_text_semantics(label, text, validation_values, errors)
  end

  review_record = review_by_packet[packet_id]
  if review.any? && !(section_keyframe_mode && packet_id.empty?)
    if review_record.nil?
      errors << "#{label}: packet_id is missing from 03-review.board_reviews"
    else
      errors << "#{label}: 03-review founder_review_status must be pass" unless review_record["founder_review_status"] == "pass"
      if Idol03VSourceDiscovery.review_core_branch_identity_missing?(review_record)
        errors << "#{label}: generated review is missing Core-Cut or Branch-Cut identity"
      end
      if Idol03VSourceDiscovery.review_core_cut_id(review_record) != beat_id
        errors << "#{label}: Core-Cut id does not match generated review"
      end

      review_image_norm = normalized_existing_path(review_record["review_image_path"], root)
      source_review_image_norm = normalized_existing_path(source_review_image, root)
      if !source_review_image.empty? && review_image_norm && source_review_image_norm && review_image_norm != source_review_image_norm
        errors << "#{label}: source_review_board_image_path does not match 03-review.review_image_path"
      elsif source_section_keyframe_image.empty? && source_visual_lock_path.empty? && review_record["review_image_path"].to_s.empty?
        errors << "#{label}: 03-review.review_image_path is required"
      end
    end
  end
end

validate_section_qa(index, index_resolved, prompts, root, errors)

unless upload_pack_records.empty?
  pack_index_paths = upload_pack_records.map do |record|
    folder = resolve_path(record["upload_pack_folder"], root)
    next unless folder

    candidate = folder.dirname.dirname + "PACK_INDEX.csv"
    candidate if readable_path?(candidate)
  end.compact.uniq

  if pack_index_paths.empty?
    errors << "upload packs are declared but no PACK_INDEX.csv was found beside the typed upload-pack directories"
  end

  pack_index_paths.each do |pack_index_path|
    rows = nil
    begin
      rows = CSV.read(pack_index_path.to_s, headers: true)
    rescue CSV::MalformedCSVError => e
      errors << "PACK_INDEX.csv is malformed: #{pack_index_path}: #{e.message}"
      next
    end

    required_headers = %w[order section timeline packet_id beat_id pack_type pack_folder image1 image2 prompt]
    if rows.any? { |row| row["pack_type"].to_s == "storyboard-assist" }
      required_headers.concat(%w[image3 image4])
    end
    missing_headers = required_headers - rows.headers.compact
    unless missing_headers.empty?
      errors << "PACK_INDEX.csv missing required column(s): #{missing_headers.join(', ')}"
      next
    end

    pack_root = pack_index_path.dirname.cleanpath
    expected_records = upload_pack_records.select do |record|
      folder = resolve_path(record["upload_pack_folder"], root)
      folder && folder.cleanpath.to_s.start_with?(pack_root.to_s + File::SEPARATOR)
    end
    expected_by_packet = expected_records.to_h { |record| [record["packet_id"], record] }
    seen_packets = Set.new
    seen_orders = Set.new

    if rows.length != expected_records.length
      errors << "PACK_INDEX.csv row count #{rows.length} does not match upload_pack_type prompt count #{expected_records.length}: #{pack_index_path}"
    end

    rows.each_with_index do |row, idx|
      row_label = "PACK_INDEX.csv row #{idx + 2}"
      packet_id = row["packet_id"].to_s
      pack_type = row["pack_type"].to_s
      order = row["order"].to_s
      expected = expected_by_packet[packet_id]

      errors << "#{row_label}: packet_id is required" if packet_id.empty?
      if expected.nil?
        errors << "#{row_label}: packet_id #{packet_id} is not present as an upload pack prompt record"
      else
        errors << "#{row_label}: pack_type #{pack_type} does not match video-prompt-index upload_pack_type #{expected['upload_pack_type']} for #{packet_id}" unless pack_type == expected["upload_pack_type"]
        errors << "#{row_label}: beat_id does not match video-prompt-index for #{packet_id}" unless row["beat_id"].to_s == expected["beat_id"]
        expected_folder = resolve_path(expected["upload_pack_folder"], root)
        actual_folder = resolve_path(row["pack_folder"], root)
        if expected_folder && actual_folder && expected_folder.cleanpath.to_s != actual_folder.cleanpath.to_s
          errors << "#{row_label}: pack_folder does not match video-prompt-index upload_pack_folder for #{packet_id}"
        end
      end

      if !order.match?(/\A\d+\z/)
        errors << "#{row_label}: order must be a positive integer"
      elsif seen_orders.include?(order)
        errors << "#{row_label}: duplicate order #{order}"
      else
        seen_orders << order
      end
      if seen_packets.include?(packet_id)
        errors << "#{row_label}: duplicate packet_id #{packet_id}"
      else
        seen_packets << packet_id unless packet_id.empty?
      end

      unless %w[bridge-two-image single-beat storyboard-assist].include?(pack_type)
        errors << "#{row_label}: pack_type must be bridge-two-image, single-beat, or storyboard-assist"
      end

      pack_folder = resolve_path(row["pack_folder"], root)
      if blank?(row["pack_folder"])
        errors << "#{row_label}: pack_folder is required"
      elsif !dir_path?(pack_folder)
        errors << "#{row_label}: pack_folder is not a directory: #{row['pack_folder']}"
      elsif !path_in_segment?(pack_folder, pack_type)
        errors << "#{row_label}: pack_folder must live under a #{pack_type} directory"
      end

      {
        "image1" => row["image1"],
        "prompt" => row["prompt"]
      }.each do |field, path_value|
        resolved = resolve_path(path_value, root)
        if blank?(path_value)
          errors << "#{row_label}: #{field} is required"
        elsif !readable_path?(resolved)
          errors << "#{row_label}: #{field} is not readable: #{path_value}"
        end
      end
      if expected && expected["v3_contract"] && !blank?(row["image1"])
        image1_path = resolve_path(row["image1"], root)
        exact_image1 = expected.dig("exact_upload_sources", "image1")
        validate_exact_file_copy("#{row_label} #{packet_id} image1", image1_path, exact_image1, errors) if exact_image1
      end

      if expected && !blank?(row["prompt"])
        prompt_file = resolve_path(row["prompt"], root)
        if readable_path?(prompt_file)
          prompt_text = File.read(prompt_file)
          validate_prompt_text_semantics("#{row_label} #{packet_id} upload prompt", prompt_text, expected["semantic_fields"] || {}, errors)
          unless prompt_text.match?(/@image1/i)
            errors << "#{row_label}: upload prompt must mention @image1"
          end
          if pack_type == "bridge-two-image" && !prompt_text.match?(/@image2/i)
            errors << "#{row_label}: bridge-two-image upload prompt must mention @image2"
          elsif pack_type == "storyboard-assist"
            reference_count = expected.dig("semantic_fields", "storyboard_reference_count").to_i
            (1..reference_count).each do |image_index|
              errors << "#{row_label}: storyboard-assist upload prompt must mention @image#{image_index}" unless prompt_text.match?(/@image#{image_index}/i)
            end
          end
          if expected["v3_contract"] && expected["canonical_prompt_path"]
            validate_exact_prompt_copy("#{row_label} #{packet_id} prompt", prompt_file, expected["canonical_prompt_path"], errors)
          end
        end
      end

      if pack_type == "bridge-two-image"
        image2 = row["image2"].to_s
        resolved_image2 = resolve_path(image2, root)
        if image2.empty?
          errors << "#{row_label}: bridge-two-image must attach image2 in the same PACK_INDEX row as image1"
        elsif !readable_path?(resolved_image2)
          errors << "#{row_label}: image2 is not readable: #{image2}"
        end
        if expected && expected["v3_contract"] && !image2.empty?
          exact_image2 = expected.dig("exact_upload_sources", "image2")
          validate_exact_file_copy("#{row_label} #{packet_id} image2", resolved_image2, exact_image2, errors) if exact_image2
        end
      elsif pack_type == "single-beat"
        errors << "#{row_label}: single-beat must leave image2 empty" unless row["image2"].to_s.empty?
        image2_candidate = pack_folder + "image2.png" if pack_folder
        errors << "#{row_label}: single-beat pack folder must not contain image2.png: #{image2_candidate}" if image2_candidate && readable_path?(image2_candidate)
      elsif pack_type == "storyboard-assist"
        reference_count = expected&.dig("semantic_fields", "storyboard_reference_count").to_i
        unless (2..4).cover?(reference_count)
          errors << "#{row_label}: storyboard-assist reference count must resolve to 2-4"
          next
        end
        image1_value = row["image1"].to_s
        image1_resolved = resolve_path(image1_value, root)
        if readable_path?(image1_resolved)
          validate_storyboard_reference_copy(
            "#{row_label} #{packet_id}",
            1,
            image1_resolved,
            expected["semantic_fields"] || {},
            errors
          )
        end
        (2..reference_count).each do |image_index|
          value = row["image#{image_index}"].to_s
          resolved = resolve_path(value, root)
          if value.empty?
            errors << "#{row_label}: storyboard-assist must attach image#{image_index}"
          elsif !readable_path?(resolved)
            errors << "#{row_label}: image#{image_index} is not readable: #{value}"
          else
            validate_storyboard_reference_copy(
              "#{row_label} #{packet_id}",
              image_index,
              resolved,
              expected["semantic_fields"] || {},
              errors
            )
          end
        end
        ((reference_count + 1)..4).each do |image_index|
          errors << "#{row_label}: storyboard-assist must leave image#{image_index} empty" unless row["image#{image_index}"].to_s.empty?
        end
      end
    end

    missing_packets = expected_by_packet.keys.to_set - seen_packets
    missing_packets.each do |packet_id|
      errors << "PACK_INDEX.csv is missing upload pack prompt #{packet_id}"
    end
  end
end

source_of_truth = index.dig("record_rule", "source_of_truth").to_s
source_dir = blank?(source_of_truth) ? index_resolved.dirname : resolve_path(source_of_truth, root)
if source_dir && Dir.exist?(source_dir.to_s)
  indexed_prompt_paths = prompts
    .map { |prompt| prompt.is_a?(Hash) ? resolve_path(prompt["output_prompt_path"], root) : nil }
    .compact
    .map { |path| path.cleanpath.to_s }
    .to_set
  directory_markdown_paths = Dir.glob(File.join(source_dir.to_s, "**", "*.md"))
    .map { |path| Pathname.new(path).cleanpath.to_s }
    .select { |path| parity_prompt_candidate?(path) }
    .to_set

  missing_from_index = directory_markdown_paths - indexed_prompt_paths
  missing_from_directory = indexed_prompt_paths.select { |path| path.start_with?(source_dir.cleanpath.to_s + File::SEPARATOR) }.to_set - directory_markdown_paths

  missing_from_index.each do |path|
    warnings << "directory/index parity: markdown prompt is not listed in index: #{Pathname.new(path).relative_path_from(root)}"
  end
  missing_from_directory.each do |path|
    errors << "directory/index parity: index output prompt is missing from source directory: #{Pathname.new(path).relative_path_from(root)}"
  end
else
  errors << "record_rule.source_of_truth directory is not readable: #{source_of_truth}"
end

handoff = index["handoff_copy"]
if handoff.is_a?(Hash) && handoff["updated"] == true
  handoff_path = resolve_path(handoff["path"], root)
  errors << "handoff_copy.path is marked updated but not readable: #{handoff['path']}" unless readable_path?(handoff_path)
elsif handoff.nil?
  warnings << "handoff_copy is missing; this is allowed but copy-paste review may be slower"
end

if errors.empty?
  puts "OK: #{prompts.length} video prompt index record(s) validated"
  warnings.each { |warning| warn "WARNING: #{warning}" }
  exit 0
end

errors.each { |error| warn "ERROR: #{error}" }
warnings.each { |warning| warn "WARNING: #{warning}" }
exit 1
