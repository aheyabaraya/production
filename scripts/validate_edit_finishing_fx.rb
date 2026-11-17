#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "optparse"
require "pathname"
require "set"
require "yaml"
require_relative "lib/idol_run_layout"

ROOT = Pathname.new(__dir__).join("..").expand_path
SCHEMA = ROOT.join("schemas", "edit-finishing-fx.schema.json")
PYTHON = ROOT.join("scripts", "idol-video-python")
SCHEMA_VALIDATOR = ROOT.join("scripts", "validate_json_schema.py")
EFFECT_REGISTRY_PATH = ROOT.join("automation", "edit-effect-registry.yaml")
V2_SCHEMA_VERSION = "idol_edit_finishing_fx.v2"
EDIT_MAP_SCHEMA_VERSION = "idol_edit_map.v4"
EDIT_RECIPE_SCHEMA_VERSION = "idol_edit_recipe.v3"
MARKER_PLAN_SCHEMA_VERSION = "idol_edit_marker_plan.v6"
PASSED_PREVIEW_STATUSES = %w[
  pass
  passed
  local_pass
  locally_accepted
  locally_accepted_for_timing_review
  accepted_for_timing_review
  founder_passed
  section_preview_passed
  chunk_preview_passed
].freeze
FX_ARTIFACT_PATH_PATTERN = %r{
  \Agenerations/video/qc/finishing-fx-v[0-9]+/
  04FX-finishing-map-v[0-9]+\.(?:yaml|yml|json)\z
}x.freeze
RECIPE_PATH_PATTERN = %r{\Agenerations/video/qc/sync-workbench-v[0-9]+/.+\.(?:yaml|yml|json)\z}.freeze
EDIT_MAP_PATH_PATTERN = /\A04-edit-map\.(?:yaml|yml|json)\z/.freeze
MARKER_PATH_PATTERN = %r{\Agenerations/video/qc/(?:sync-workbench-v[0-9]+/)?edit-marker-plan-v[0-9]+\.(?:yaml|yml|json)\z}.freeze
AUDIO_OR_CUE_PATH_PATTERN = %r{\A(?:audio/|research/|generations/video/qc/).+\z}.freeze
PREVIEW_EXTENSIONS = %w[.mp4 .mov .mkv .webm].freeze
CONTACT_SHEET_EXTENSIONS = %w[.png .jpg .jpeg .webp].freeze
REQUIRED_PASSED_FX_CHECKS = %w[
  timing_feel
  identity_body_preserved
  full_space_world_preserved
  tone_manner_preserved
  mobile_readable
  flicker_flash_safe
  source_quality_not_hidden
  repeated_effect_drift_checked
].freeze
RECIPE_SEGMENT_ID_KEY = "segment_id"
EVENT_KIND_PRIORITY = {
  "section_boundary" => 0,
  "lyric_gate" => 1,
  "drop_or_release" => 2,
  "onset_gate" => 3,
  "story_handoff" => 4,
  "other_musical_turn" => 5
}.freeze
AUDIO_ONSET_KEYS = %w[
  strong_onsets_ranked
  top_onset_markers
  strong_onsets_seconds
].freeze
AUDIO_DROP_KEYS = %w[
  energy_jump_candidates
  drop_or_release_seconds
  drop_release_markers
  drop_or_release_gates
].freeze
AUDIO_LYRIC_KEYS = %w[
  lyric_gate_seconds
  lyric_gates
  lyric_markers
  lyric_or_section_gates
  vocal_or_lyric_gates
].freeze

def load_effect_registry
  registry = YAML.safe_load(
    EFFECT_REGISTRY_PATH.read,
    permitted_classes: [],
    permitted_symbols: [],
    aliases: true
  )
  raise "effect registry must be a mapping" unless registry.is_a?(Hash)
  unless registry["schema_version"] == "idol_edit_effect_registry.v1"
    raise "unsupported effect registry version #{registry['schema_version'].inspect}"
  end

  registry
rescue Errno::ENOENT, Psych::SyntaxError => e
  raise "effect registry is unreadable: #{e.message}"
end

def effect_aliases(registry)
  Array(registry["effects"]).to_h.each_with_object({}) do |(canonical, spec), result|
    result[canonical.to_s] = canonical.to_s
    Array(spec["aliases"]).each do |alias_name|
      prior = result[alias_name.to_s]
      if prior && prior != canonical.to_s
        raise "effect alias #{alias_name.inspect} maps to both #{prior} and #{canonical}"
      end
      result[alias_name.to_s] = canonical.to_s
    end
  end
end

def canonical_effect_type(value, registry, label, errors)
  aliases = effect_aliases(registry)
  raw = value.to_s.strip
  canonical = aliases[raw]
  unless canonical
    errors << "#{label} unsupported effect_type #{raw.inspect}; use automation/edit-effect-registry.yaml"
  end
  canonical
end

def effect_render_parameters(record, design, registry, label, errors)
  nested = design["parameters"].is_a?(Hash) ? design["parameters"] : {}
  parameters = nested.dup
  known = registry.fetch("common_parameters", {}).keys + registry.fetch("parameter_specs", {}).keys
  known.each do |key|
    declarations = []
    declarations << ["effect_design.parameters", nested[key]] if nested.key?(key)
    declarations << ["effect_design", design[key]] if design.key?(key)
    declarations << ["fx_record", record[key]] if record.key?(key)
    next if declarations.empty?

    if declarations.map(&:last).uniq.length > 1
      errors << "#{label}.#{key} has conflicting duplicate values across #{declarations.map(&:first).join(', ')}"
    end
    parameters[key] = declarations.first.last
  end
  if design.key?("transition_handle_contract")
    parameters["transition_handle_contract"] = design["transition_handle_contract"]
  end
  parameters
end

def validate_registry_value(value, spec, label, errors)
  expected = spec["type"].to_s
  valid = case expected
          when "number" then value.is_a?(Numeric)
          when "integer" then value.is_a?(Integer)
          when "string" then value.is_a?(String)
          when "object" then value.is_a?(Hash)
          when "color"
            (value.is_a?(String) && value.match?(/\A(?:#[0-9A-Fa-f]{6}|0x[0-9A-Fa-f]{6}|[A-Za-z][A-Za-z0-9_-]{0,31})\z/)) || (
              value.is_a?(Array) && value.length == 3 &&
                value.all? { |item| item.is_a?(Integer) && item.between?(0, 255) }
            )
          else false
          end
  unless valid
    errors << "#{label} must be #{expected}"
    return
  end

  if spec.key?("enum") && !Array(spec["enum"]).include?(value)
    errors << "#{label} must be one of #{Array(spec['enum']).inspect}"
  end
  if value.is_a?(String)
    if spec.key?("min_length") && value.length < spec["min_length"].to_i
      errors << "#{label} is shorter than #{spec['min_length']} characters"
    end
    if spec.key?("max_length") && value.length > spec["max_length"].to_i
      errors << "#{label} exceeds #{spec['max_length']} characters"
    end
    begin
      if spec.key?("pattern") && !value.match?(Regexp.new("\\A(?:#{spec['pattern']})\\z"))
        errors << "#{label} contains unsupported filter syntax"
      end
      if spec.key?("forbidden_pattern") && value.match?(Regexp.new(spec["forbidden_pattern"].to_s))
        errors << "#{label} contains a forbidden control character"
      end
    rescue RegexpError => e
      errors << "#{label} registry pattern is invalid: #{e.message}"
    end
  end
  return unless value.is_a?(Numeric)

  errors << "#{label} is below #{spec['minimum']}" if spec.key?("minimum") && value < spec["minimum"]
  if spec.key?("exclusive_minimum") && value <= spec["exclusive_minimum"]
    errors << "#{label} must exceed #{spec['exclusive_minimum']}"
  end
  errors << "#{label} exceeds #{spec['maximum']}" if spec.key?("maximum") && value > spec["maximum"]
end

def validate_xfade_handle_contract(handles, design, label, errors)
  unless handles.is_a?(Hash)
    errors << "#{label}.transition_handle_contract must be a mapping"
    return
  end
  required = %w[
    mode fixed_program_cut_frame transition_frames pre_cut_frames post_cut_frames
  ]
  missing = required.reject { |key| handles.key?(key) }
  errors << "#{label}.transition_handle_contract missing #{missing.join(', ')}" unless missing.empty?
  return unless missing.empty?

  unless handles["mode"] == "duration_preserving"
    errors << "#{label}.transition_handle_contract.mode must be duration_preserving"
  end
  transition_frames = handles["transition_frames"]
  pre_frames = handles["pre_cut_frames"]
  post_frames = handles["post_cut_frames"]
  if [transition_frames, pre_frames, post_frames].all? { |value| value.is_a?(Integer) }
    unless transition_frames.positive? && pre_frames >= 0 && post_frames >= 0
      errors << "#{label}.transition_handle_contract frame counts must be nonnegative and transition_frames > 0"
    end
    unless pre_frames + post_frames == transition_frames
      errors << "#{label}.transition_handle_contract pre_cut_frames + post_cut_frames must equal transition_frames"
    end
    duration_frames = design["duration_frames"]
    if duration_frames.is_a?(Integer) && duration_frames != transition_frames
      errors << "#{label}.duration_frames must equal transition_handle_contract.transition_frames"
    end
  end
  fixed_cut_frame = handles["fixed_program_cut_frame"]
  unless fixed_cut_frame.is_a?(Integer) && fixed_cut_frame >= 0
    errors << "#{label}.transition_handle_contract.fixed_program_cut_frame must be an integer >= 0"
  end
end

def validate_effect_against_registry(record, registry, label, errors, final:)
  design = record["effect_design"].is_a?(Hash) ? record["effect_design"] : {}
  canonical = canonical_effect_type(design["effect_type"], registry, label, errors)
  return nil unless canonical

  spec = registry.fetch("effects").fetch(canonical)
  parameters = effect_render_parameters(record, design, registry, label, errors)
  allowed = registry.fetch("common_parameters").keys + Array(spec["parameters"])
  unknown = parameters.keys - allowed
  errors << "#{label} unsupported render parameters: #{unknown.sort.join(', ')}" unless unknown.empty?

  required = Array(spec["required_parameters"])
  required -= ["transition_handle_contract"] unless final
  missing = required.reject { |key| parameters.key?(key) && !parameters[key].to_s.empty? }
  errors << "#{label} missing registry parameters: #{missing.join(', ')}" unless missing.empty?

  parameter_specs = registry.fetch("common_parameters").merge(registry.fetch("parameter_specs"))
  parameters.each do |key, value|
    next unless parameter_specs[key]

    validate_registry_value(value, parameter_specs[key], "#{label}.#{key}", errors)
  end

  if canonical == "xfade"
    transition = (parameters["transition"] || parameters["xfade_transition"] || "fade").to_s
    unless Array(registry["xfade_transitions"]).include?(transition)
      errors << "#{label} unsupported xfade transition #{transition.inspect}; custom expressions are not supported"
    end
    handles = parameters["transition_handle_contract"]
    validate_xfade_handle_contract(handles, design, label, errors) if final || handles
  end

  renderer_status = design.fetch("renderer_status", "supported_now").to_s
  if record["status"].to_s == "pass"
    registry_renderer_status = spec["renderer_status"].to_s
    if registry_renderer_status == "metadata_only"
      errors << "#{label} metadata-only records cannot pass as finishing FX; use audit disposition=none_needed"
    elsif registry_renderer_status != "supported_now"
      errors << "#{label} registry renderer_status=#{registry_renderer_status} cannot pass"
    elsif renderer_status != "supported_now"
      errors << "#{label} pass requires renderer_status=supported_now"
    end
  end
  canonical
end

def load_yaml_mapping(path)
  document = YAML.safe_load(path.read, permitted_classes: [], permitted_symbols: [], aliases: true)
  return document if document.is_a?(Hash)

  raise "artifact must be a YAML/JSON mapping"
rescue Errno::ENOENT
  raise "artifact is not readable: #{path}"
rescue Psych::SyntaxError => e
  raise "artifact YAML syntax error: #{e.message}"
end

def path_within?(path, parent)
  value = path.to_s
  root = parent.to_s.sub(%r{/+\z}, "")
  value == root || value.start_with?("#{root}/")
end

def canonical_run_root?(path)
  parts = path.expand_path.each_filename.to_a
  runs_index = parts.rindex("runs")
  return false unless runs_index && parts.length == runs_index + 4

  IdolRunLayout::ACTIVE_RUN_ROOT_PATTERN.match?(parts[runs_index, 4].join("/"))
end

def infer_run_root(artifact_path)
  current = artifact_path.dirname
  loop do
    return current if canonical_run_root?(current)
    return nil if current.root?

    current = current.parent
  end
end

def canonical_run_prefix(run_root)
  return nil unless canonical_run_root?(run_root)

  parts = run_root.expand_path.each_filename.to_a
  runs_index = parts.rindex("runs")
  parts[runs_index, 4].join("/")
end

def resolve_run_root(value, repo_root)
  raw = Pathname.new(value.to_s)
  resolved = raw.absolute? ? raw.expand_path : repo_root.join(raw).expand_path
  return [nil, "run root is not a readable directory: #{value}"] unless resolved.directory?

  [resolved.realpath, nil]
rescue Errno::ENOENT, ArgumentError => e
  [nil, "run root is not a readable directory: #{value} (#{e.message})"]
end

def allowed_preview_path?(relative_path)
  return false unless relative_path.start_with?("generations/video/qc/")
  return false if relative_path.match?(%r{\Agenerations/video/qc/finishing-fx-v[0-9]+/})

  PREVIEW_EXTENSIONS.include?(Pathname.new(relative_path).extname.downcase)
end

def resolve_run_owned_file(run_root, declared_path, label:, allowed_path:)
  value = declared_path.to_s.strip
  return [nil, "#{label} path is blank"] if value.empty?

  raw = Pathname.new(value)
  if !raw.absolute? && (raw.each_filename.to_a.include?("..") || value.start_with?("./"))
    return [nil, "#{label} path must not use . or .. traversal: #{value}"]
  end

  resolved = if raw.absolute?
               raw.expand_path
             elsif value.start_with?("runs/")
               expected_prefix = canonical_run_prefix(run_root)
               unless expected_prefix && value.start_with?("#{expected_prefix}/")
                 return [nil, "#{label} points to a different run than #{run_root}: #{value}"]
               end
               run_root.join(value.delete_prefix("#{expected_prefix}/")).expand_path
             elsif value.start_with?("generations/")
               run_root.join(value).expand_path
             else
               run_root.join(value).expand_path
             end

  unless path_within?(resolved.to_s, run_root.expand_path.to_s)
    return [nil, "#{label} escapes owning run #{run_root}: #{value}"]
  end

  relative_path = resolved.relative_path_from(run_root.expand_path).to_s
  unless allowed_path.call(relative_path)
    return [nil, "#{label} is not in an allowed run-owned location: #{relative_path}"]
  end

  return [nil, "#{label} file is not readable: #{value}"] unless resolved.file? && resolved.readable?

  real_root = run_root.realpath
  real_file = resolved.realpath
  unless path_within?(real_file.to_s, real_root.to_s)
    return [nil, "#{label} resolved file escapes owning run #{run_root}: #{value}"]
  end

  [real_file, nil]
rescue Errno::ENOENT, ArgumentError => e
  [nil, "#{label} file is not readable: #{value} (#{e.message})"]
end

def sha256_matches?(path, declared_sha, label, errors)
  actual_sha = Digest::SHA256.file(path.to_s).hexdigest
  return if actual_sha == declared_sha.to_s

  errors << "#{label} sha256 mismatch: bound file is stale or was modified"
end

def collect_recipe_segment_ids(value, result = Set.new)
  case value
  when Hash
    value.each do |key, child|
      if key.to_s == RECIPE_SEGMENT_ID_KEY && (child.is_a?(String) || child.is_a?(Numeric))
        result << child.to_s
      end
      collect_recipe_segment_ids(child, result)
    end
  when Array
    value.each { |child| collect_recipe_segment_ids(child, result) }
  end
  result
end

def same_content_id_error(path, expected_content_id, label)
  document = load_yaml_mapping(path)
  actual = document["content_id"].to_s
  return nil if actual.empty? || actual == expected_content_id

  "#{label} content_id=#{actual.inspect} does not match #{expected_content_id.inspect}"
rescue StandardError => e
  "#{label} is not a readable mapping: #{e.message}"
end

def nested_value(document, keys)
  Array(keys).reduce(document) do |value, key|
    break nil unless value.is_a?(Hash)

    value[key]
  end
end

def resolve_lineage_pointer(run_root, value, label, errors)
  binding = value.is_a?(Hash) ? value : nil
  pointer = binding ? binding["path"] : value
  if pointer.to_s.strip.empty?
    errors << "#{label} is required for 04FX v2 lineage"
    return nil
  end

  path, error = resolve_run_owned_file(
    run_root,
    pointer,
    label: label,
    allowed_path: ->(_relative_path) { true }
  )
  errors << error if error
  if path && binding
    expected_sha = binding["sha256"].to_s
    if expected_sha.empty?
      errors << "#{label}.sha256 is required"
    elsif Digest::SHA256.file(path.to_s).hexdigest != expected_sha
      errors << "#{label}.sha256 mismatch"
    end
  end
  path
end

def resolve_lineage_pointer_set(document, specs, run_root, group_label, errors)
  rows = Array(specs).each_with_object([]) do |(label, keys), values|
    raw_value = nested_value(document, keys)
    next if raw_value.to_s.strip.empty?

    path = resolve_lineage_pointer(run_root, raw_value, label, errors)
    values << [label, path] if path
  end
  errors << "#{group_label} must expose at least one current run-owned pointer" if rows.empty?
  rows
end

def require_same_path(expected, actual, label, errors)
  return unless expected && actual
  return if expected.realpath == actual.realpath

  errors << "#{label} must match #{expected} (got #{actual})"
end

def recipe_fps(document)
  value = document.dig("render_spec", "fps") || document.dig("timebase", "fps") || document["fps"] || 24
  if value.is_a?(Hash)
    numerator = value["numerator"].to_i
    denominator = value["denominator"].to_i
    return nil unless numerator.positive? && denominator.positive?

    numerator.to_f / denominator
  elsif value.to_s.include?("/")
    numerator, denominator = value.to_s.split("/", 2).map(&:to_f)
    return nil unless numerator.positive? && denominator.positive?

    numerator / denominator
  else
    fps = value.to_f
    fps.positive? ? fps : nil
  end
end

def recipe_fps_fraction(document)
  value = document.dig("render_spec", "fps") || document.dig("timebase", "fps") || document["fps"] || 24
  if value.is_a?(Hash)
    numerator = value["numerator"].to_i
    denominator = value["denominator"].to_i
    return nil unless numerator.positive? && denominator.positive?

    Rational(numerator, denominator)
  elsif value.to_s.include?("/")
    numerator, denominator = value.to_s.split("/", 2).map(&:to_i)
    return nil unless numerator.positive? && denominator.positive?

    Rational(numerator, denominator)
  else
    fps = Rational(value.to_s)
    fps.positive? ? fps : nil
  end
rescue ArgumentError, TypeError, ZeroDivisionError
  nil
end

def coverage_frame_from_seconds(value, fps)
  (Rational(Float(value).to_s) * fps + Rational(1, 2)).floor
end

def coverage_digest(event_ids)
  payload = Array(event_ids).map(&:to_s).uniq.sort.map { |event_id| "#{event_id}\n" }.join
  Digest::SHA256.hexdigest(payload)
end

def coverage_number_list(values, *keys)
  rows = values.is_a?(Array) ? values : (values.nil? ? [] : [values])
  rows.each_with_object([]) do |value, result|
    raw = value
    if value.is_a?(Hash)
      raw = nil
      keys.each do |key|
        next unless value.key?(key) && !value[key].nil?

        raw = value[key]
        break
      end
    end
    number = Float(raw)
    result << number if number.finite?
  rescue ArgumentError, TypeError
    next
  end
end

def coverage_time_values(payload, keys)
  Array(keys).flat_map do |key|
    coverage_number_list(
      payload[key],
      "time_seconds",
      "time_sec",
      "seconds",
      "start_seconds",
      "program_time"
    )
  end
end

def coverage_audio_gate_times(payload)
  onsets = coverage_time_values(payload, AUDIO_ONSET_KEYS)
  drops = coverage_time_values(payload, AUDIO_DROP_KEYS)
  lyrics = coverage_time_values(payload, AUDIO_LYRIC_KEYS)
  Array(payload["cue_tempo_map"]).each do |row|
    next unless row.is_a?(Hash)

    onsets.concat(coverage_number_list(row["nearby_strong_onsets_seconds"]))
    drops.concat(coverage_time_values(row, AUDIO_DROP_KEYS))
    lyrics.concat(coverage_time_values(row, AUDIO_LYRIC_KEYS))
  end
  Array(payload.dig("stable_audio_extracts", "signals")).each do |signal|
    next unless signal.is_a?(Hash) && signal["time_seconds"].is_a?(Numeric)

    time = signal["time_seconds"].to_f
    case signal["signal_type"].to_s
    when "onset", "drum_or_percussion", "high_transient", "beat"
      onsets << time
    when "section_boundary", "texture_change", "silence_or_breath"
      drops << time
    when "vocal_entry", "vocal_hold", "motif_return"
      lyrics << time
    end
  end
  {
    "onset_gate" => onsets.uniq.sort,
    "drop_or_release" => drops.uniq.sort,
    "lyric_gate" => lyrics.uniq.sort
  }
end

def coverage_segment_slot(segment)
  (segment["slot"] || segment["marker_slot_ref"]).to_s.strip
end

def coverage_segment_sections(segment)
  values = segment["section_ids"]
  values = [segment["section_id"]] if values.nil? && segment["section_id"]
  values = [values] if values.is_a?(String)
  Array(values).map(&:to_s).reject(&:empty?)
end

def coverage_segment_frame_range(segment, fps)
  start_frame = if !segment["output_in_frame"].nil?
                  Integer(segment["output_in_frame"])
                else
                  coverage_frame_from_seconds(segment.fetch("output_in", 0.0), fps)
                end
  end_frame = if !segment["output_out_frame"].nil?
                Integer(segment["output_out_frame"])
              else
                coverage_frame_from_seconds(segment.fetch("output_out", 0.0), fps)
              end
  [start_frame, end_frame]
end

def coverage_cut_frame(segment, fps)
  return Integer(segment["output_out_frame"]) unless segment["output_out_frame"].nil?

  seconds = segment["output_out"] || segment["output_in"] || 0.0
  (Float(seconds) * fps.to_f).round(half: :even)
end

def coverage_sections_for_frame(timeline, frame, fps)
  timeline.each do |segment|
    next unless segment.is_a?(Hash)

    start_frame, end_frame = coverage_segment_frame_range(segment, fps)
    return coverage_segment_sections(segment) if start_frame <= frame && frame < end_frame
  end
  []
end

def add_coverage_event(events, event_id, frame, kind, source, section_ids, detail = {})
  program_end = detail.delete(:program_end)
  return if frame.negative? || (program_end && frame >= program_end)

  events[event_id] = {
    "event_id" => event_id,
    "program_frame" => frame,
    "kind" => kind,
    "source" => source,
    "section_ids" => Array(section_ids).map(&:to_s).uniq.sort
  }.merge(detail.transform_keys(&:to_s))
end

def expected_coverage_events(recipe, marker_plan, audio_or_cue, fps)
  timeline = Array(recipe["timeline"]).select { |row| row.is_a?(Hash) }
  return [] if timeline.empty?

  _program_start, program_end = coverage_segment_frame_range(timeline.last, fps)
  events = {}
  timeline.each_cons(2).with_index do |(left, right), index|
    left_slot = coverage_segment_slot(left)
    right_slot = coverage_segment_slot(right)
    left_slot = format("IDX%03d", index + 1) if left_slot.empty?
    right_slot = format("IDX%03d", index + 2) if right_slot.empty?
    frame = coverage_cut_frame(left, fps)
    left_sections = coverage_segment_sections(left).uniq.sort
    right_sections = coverage_segment_sections(right).uniq.sort
    section_ids = (left_sections + right_sections).uniq.sort
    add_coverage_event(
      events,
      "recipe_cut:#{left_slot}:#{right_slot}:f#{frame}",
      frame,
      "story_handoff",
      "recipe",
      section_ids,
      program_end: program_end,
      outgoing_slot: left_slot,
      incoming_slot: right_slot
    )
    next unless left_sections.any? && right_sections.any? && left_sections != right_sections

    add_coverage_event(
      events,
      "recipe_section:#{left_sections.join('+')}>#{right_sections.join('+')}:f#{frame}",
      frame,
      "section_boundary",
      "recipe",
      section_ids,
      program_end: program_end,
      outgoing_slot: left_slot,
      incoming_slot: right_slot
    )
  end

  Array(marker_plan["timeline_slots"]).each_with_index do |row, index|
    next unless row.is_a?(Hash)

    slot = (row["slot"] || format("IDX%03d", index + 1)).to_s.strip
    sections = row["section_id"] ? [row["section_id"].to_s] : []
    nearby = row["nearby_markers"].is_a?(Hash) ? row["nearby_markers"] : {}
    coverage_number_list(nearby["strong_onsets_seconds"]).each do |value|
      frame = coverage_frame_from_seconds(value, fps)
      add_coverage_event(
        events, "marker_onset:#{slot}:f#{frame}", frame, "onset_gate", "marker_plan",
        sections.any? ? sections : coverage_sections_for_frame(timeline, frame, fps),
        program_end: program_end, marker_slot: slot
      )
    end
    coverage_number_list(nearby["feature_boundaries_seconds"]).each do |value|
      frame = coverage_frame_from_seconds(value, fps)
      add_coverage_event(
        events, "marker_drop:#{slot}:f#{frame}", frame, "drop_or_release", "marker_plan",
        sections.any? ? sections : coverage_sections_for_frame(timeline, frame, fps),
        program_end: program_end, marker_slot: slot
      )
    end
    lyric_handoff = nearby["lyric_or_section_handoff"]
    next if !lyric_handoff || lyric_handoff.to_s.strip.empty?

    output_range = row["output_range"].is_a?(Hash) ? row["output_range"] : {}
    frame = if !output_range["start_frame"].nil?
              Integer(output_range["start_frame"])
            else
              coverage_frame_from_seconds(output_range.fetch("start_seconds", 0.0), fps)
            end
    add_coverage_event(
      events, "marker_lyric:#{slot}:f#{frame}", frame, "lyric_gate", "marker_plan",
      sections.any? ? sections : coverage_sections_for_frame(timeline, frame, fps),
      program_end: program_end, marker_slot: slot
    )
  end

  prefixes = {
    "onset_gate" => "audio_onset",
    "drop_or_release" => "audio_drop",
    "lyric_gate" => "audio_lyric"
  }
  coverage_audio_gate_times(audio_or_cue).each do |kind, values|
    values.each do |value|
      frame = coverage_frame_from_seconds(value, fps)
      add_coverage_event(
        events, "#{prefixes.fetch(kind)}:f#{frame}", frame, kind, "audio_or_cue_map",
        coverage_sections_for_frame(timeline, frame, fps), program_end: program_end
      )
    end
  end
  events.values.sort_by { |row| [row["program_frame"], row["event_id"]] }
end

def load_optional_structured_mapping(path, label, errors)
  return {} unless path
  return {} unless %w[.json .yaml .yml].include?(path.extname.downcase)

  load_yaml_mapping(path)
rescue StandardError => e
  errors << "#{label} cannot be inspected for exact coverage: #{e.message}"
  {}
end

def validate_full_master_coverage(artifact, audit, recipe, marker_plan, audio_or_cue, fps, errors)
  unless artifact.dig("preview_gate", "gate_type") == "full_master"
    errors << "passed_for_final_render requires preview_gate.gate_type=full_master"
  end

  timeline = Array(recipe["timeline"]).select { |row| row.is_a?(Hash) }
  if timeline.empty?
    errors << "passed_for_final_render requires a nonempty source_recipe.timeline"
    return
  end

  empty_section_rows = timeline.each_index.select do |index|
    coverage_segment_sections(timeline[index]).empty?
  end
  unless empty_section_rows.empty?
    errors << "passed_for_final_render requires section_ids on every source_recipe.timeline row: #{empty_section_rows.join(', ')}"
  end
  recipe_sections = timeline.flat_map { |row| coverage_segment_sections(row) }.map(&:to_s).uniq.sort
  gate_sections = Array(artifact.dig("preview_gate", "section_ids")).map(&:to_s).uniq.sort
  if recipe_sections.empty?
    errors << "passed_for_final_render requires at least one source_recipe timeline section"
  elsif gate_sections != recipe_sections
    errors << "full_master preview_gate.section_ids must exactly match source_recipe timeline sections: expected #{recipe_sections.inspect}, got #{gate_sections.inspect}"
  end

  expected_events = expected_coverage_events(recipe, marker_plan, audio_or_cue, fps)
  expected_by_id = expected_events.to_h { |event| [event["event_id"], event] }
  expected_without_sections = expected_events.select { |event| Array(event["section_ids"]).empty? }
  unless expected_without_sections.empty?
    errors << "exact coverage events lack section attribution: #{expected_without_sections.map { |event| event['event_id'] }.join(', ')}"
  end

  seen = {}
  covered_ids = []
  Array(audit["points"]).each_with_index do |point, index|
    next unless point.is_a?(Hash)

    label = "transition_opportunity_audit.points[#{index}] #{point['point_id']}"
    event_ids = Array(point["coverage_event_ids"]).map(&:to_s)
    event_ids.each do |event_id|
      if seen.key?(event_id)
        errors << "#{label}.coverage_event_ids duplicates #{event_id.inspect} already covered by #{seen[event_id]}"
      else
        seen[event_id] = point["point_id"].to_s
      end
    end
    covered_ids.concat(event_ids)
    known_events = event_ids.each_with_object([]) do |event_id, values|
      values << expected_by_id[event_id] if expected_by_id[event_id]
    end
    unknown_ids = event_ids.reject { |event_id| expected_by_id.key?(event_id) }
    errors << "#{label}.coverage_event_ids contains unknown events: #{unknown_ids.join(', ')}" unless unknown_ids.empty?
    next if known_events.empty?

    expected_frames = known_events.map { |event| event["program_frame"] }.uniq
    if expected_frames != [point["program_frame"]]
      errors << "#{label}.program_frame must equal covered event frame(s) #{expected_frames.inspect}"
    end
    expected_kinds = known_events.map { |event| event["kind"] }.uniq.sort_by { |kind| EVENT_KIND_PRIORITY.fetch(kind) }
    actual_kinds = Array(point["coverage_kinds"]).map(&:to_s).uniq.sort_by { |kind| EVENT_KIND_PRIORITY.fetch(kind, 99) }
    if actual_kinds != expected_kinds
      errors << "#{label}.coverage_kinds must exactly match #{expected_kinds.inspect}"
    end
    expected_sections = known_events.flat_map { |event| Array(event["section_ids"]) }.map(&:to_s).uniq.sort
    actual_sections = Array(point["section_ids"]).map(&:to_s).uniq.sort
    if actual_sections != expected_sections
      errors << "#{label}.section_ids must exactly match covered events #{expected_sections.inspect}"
    end
    expected_primary_kind = expected_kinds.first
    if point["kind"].to_s != expected_primary_kind
      errors << "#{label}.kind must be highest-priority covered kind #{expected_primary_kind.inspect}"
    end
  end

  expected_ids = expected_by_id.keys.sort
  actual_ids = covered_ids.uniq.sort
  missing = expected_ids - actual_ids
  extra = actual_ids - expected_ids
  errors << "full_master exact coverage is missing events: #{missing.join(', ')}" unless missing.empty?
  errors << "full_master exact coverage has extra events: #{extra.join(', ')}" unless extra.empty?

  contract = audit["coverage_contract"]
  unless contract.is_a?(Hash)
    errors << "passed_for_final_render requires transition_opportunity_audit.coverage_contract"
    return
  end
  expected_contract = {
    "coverage_version" => "recipe_marker_audio_exact_v1",
    "coverage_scope" => "full_master",
    "digest_algorithm" => "sha256_sorted_utf8_lines_v1",
    "expected_event_count" => expected_ids.length,
    "covered_event_count" => actual_ids.length,
    "expected_event_ids_sha256" => coverage_digest(expected_ids),
    "covered_event_ids_sha256" => coverage_digest(actual_ids)
  }
  expected_contract.each do |key, value|
    next if contract[key] == value

    errors << "transition_opportunity_audit.coverage_contract.#{key} must equal recomputed #{value.inspect}"
  end
end

options = { repo_root: ROOT, run_root: nil, immutable_receipt: false }
parser = OptionParser.new do |opts|
  opts.banner = (
    "usage: scripts/validate_edit_finishing_fx.rb " \
    "[--repo-root PATH] [--run-root PATH] ARTIFACT.yaml"
  )
  opts.on("--repo-root PATH", "Workspace root used to resolve relative artifact/run paths") do |path|
    options[:repo_root] = Pathname.new(path).expand_path
  end
  opts.on("--run-root PATH", "Explicit owning run root; useful for isolated tests") do |path|
    options[:run_root] = path
  end
  opts.on(
    "--immutable-receipt",
    "Keep all FX/recipe/marker/audio/preview/coverage checks but do not compare the historical pre-render edit-map digest to the post-render live edit map"
  ) do
    options[:immutable_receipt] = true
  end
end

begin
  parser.parse!
rescue OptionParser::ParseError => e
  warn "ERROR: #{e.message}"
  warn parser
  exit 2
end

artifact_arg = ARGV.shift
if artifact_arg.nil? || !ARGV.empty?
  warn parser
  exit 2
end

unless options[:repo_root].directory?
  warn "ERROR: --repo-root is not a readable directory: #{options[:repo_root]}"
  exit 2
end

artifact_raw_path = Pathname.new(artifact_arg)
artifact_path = if artifact_raw_path.absolute?
                  artifact_raw_path.expand_path
                else
                  options[:repo_root].join(artifact_raw_path).expand_path
                end
unless artifact_path.file? && artifact_path.readable?
  warn "ERROR: artifact is not readable: #{artifact_path}"
  exit 1
end
artifact_path = artifact_path.realpath

run_root, run_root_error = if options[:run_root]
                             resolve_run_root(options[:run_root], options[:repo_root])
                           else
                             [infer_run_root(artifact_path), nil]
                           end
if run_root_error
  warn "ERROR: #{run_root_error}"
  exit 1
end
unless run_root
  warn(
    "ERROR: cannot infer owning runs/ALBUM_KEY/TITLE_KEY/RUN_ID root from artifact; " \
    "pass --run-root for an isolated test"
  )
  exit 1
end
unless path_within?(artifact_path.to_s, run_root.to_s)
  warn "ERROR: artifact is outside explicit owning run #{run_root}: #{artifact_path}"
  exit 1
end

artifact_relative_path = artifact_path.relative_path_from(run_root).to_s
unless artifact_relative_path.match?(FX_ARTIFACT_PATH_PATTERN)
  warn(
    "ERROR: artifact must use generations/video/qc/finishing-fx-vN/" \
    "04FX-finishing-map-vN.yaml inside its owning run " \
    "(got #{artifact_relative_path})"
  )
  exit 1
end

schema_stdout, schema_stderr, schema_status = Open3.capture3(
  PYTHON.to_s,
  SCHEMA_VALIDATOR.to_s,
  SCHEMA.to_s,
  artifact_path.to_s,
  chdir: ROOT.to_s
)
unless schema_status.success?
  warn schema_stdout unless schema_stdout.empty?
  warn schema_stderr unless schema_stderr.empty?
  exit 1
end

begin
  artifact = load_yaml_mapping(artifact_path)
rescue StandardError => e
  warn "ERROR: #{e.message}"
  exit 1
end

schema_version = artifact["schema_version"].to_s
dependency_lock = artifact["dependency_lock"]
errors = []
if options[:immutable_receipt] && (
  schema_version != V2_SCHEMA_VERSION || artifact["status"].to_s != "passed_for_final_render"
)
  errors << "--immutable-receipt requires idol_edit_finishing_fx.v2 status=passed_for_final_render"
end
effect_registry = begin
  load_effect_registry
rescue StandardError => e
  errors << e.message
  {"effects" => {}, "common_parameters" => {}, "parameter_specs" => {}, "xfade_transitions" => []}
end
if artifact["content_id"].to_s != run_root.basename.to_s
  errors << "content_id must match owning run basename #{run_root.basename}"
end

unless dependency_lock.is_a?(Hash)
  errors << "dependency_lock is required for #{V2_SCHEMA_VERSION}"
  dependency_lock = {}
end

preview_status = artifact.dig("preview_gate", "edit_preview_status").to_s.strip.downcase
unless PASSED_PREVIEW_STATUSES.include?(preview_status)
  errors << (
    "preview_gate.edit_preview_status must record an explicit " \
    "passed/local-accepted state before dependency locking " \
    "(got #{preview_status.inspect})"
  )
end

recipe_path, recipe_error = resolve_run_owned_file(
  run_root,
  artifact["source_recipe"],
  label: "source_recipe",
  allowed_path: ->(path) { path.match?(RECIPE_PATH_PATTERN) }
)
preview_path, preview_error = resolve_run_owned_file(
  run_root,
  artifact.dig("preview_gate", "preview_path"),
  label: "preview_gate.preview_path",
  allowed_path: ->(path) { allowed_preview_path?(path) }
)
errors << recipe_error if recipe_error
errors << preview_error if preview_error

edit_map_path = nil
marker_plan_path = nil
audio_or_cue_path = nil
edit_map_document = nil
recipe_document = nil
marker_plan_document = nil
audio_or_cue_document = nil
fps = nil
if schema_version == V2_SCHEMA_VERSION
  edit_map_path, edit_map_error = resolve_run_owned_file(
    run_root,
    artifact["source_edit_map"],
    label: "source_edit_map",
    allowed_path: ->(path) { path.match?(EDIT_MAP_PATH_PATTERN) }
  )
  marker_plan_path, marker_plan_error = resolve_run_owned_file(
    run_root,
    artifact["source_edit_marker_plan"],
    label: "source_edit_marker_plan",
    allowed_path: ->(path) { path.match?(MARKER_PATH_PATTERN) }
  )
  audio_or_cue_path, audio_or_cue_error = resolve_run_owned_file(
    run_root,
    artifact["source_audio_or_cue_map"],
    label: "source_audio_or_cue_map",
    allowed_path: ->(path) { path.match?(AUDIO_OR_CUE_PATH_PATTERN) }
  )
  errors << edit_map_error if edit_map_error
  errors << marker_plan_error if marker_plan_error
  errors << audio_or_cue_error if audio_or_cue_error
end

if recipe_path
  actual_recipe_sha = Digest::SHA256.file(recipe_path.to_s).hexdigest
  declared_recipe_sha = dependency_lock["source_recipe_sha256"].to_s
  unless actual_recipe_sha == declared_recipe_sha
    errors << "dependency_lock.source_recipe_sha256 mismatch: source recipe is stale or was modified"
  end
end

if preview_path
  actual_preview_sha = Digest::SHA256.file(preview_path.to_s).hexdigest
  declared_preview_sha = dependency_lock["passed_preview_sha256"].to_s
  unless actual_preview_sha == declared_preview_sha
    errors << "dependency_lock.passed_preview_sha256 mismatch: passed preview is stale or was modified"
  end
end

if schema_version == V2_SCHEMA_VERSION
  unless options[:immutable_receipt]
    sha256_matches?(edit_map_path, dependency_lock["source_edit_map_sha256"], "dependency_lock.source_edit_map", errors) if edit_map_path
  end
  sha256_matches?(marker_plan_path, dependency_lock["source_edit_marker_plan_sha256"], "dependency_lock.source_edit_marker_plan", errors) if marker_plan_path
  sha256_matches?(audio_or_cue_path, dependency_lock["source_audio_or_cue_map_sha256"], "dependency_lock.source_audio_or_cue_map", errors) if audio_or_cue_path

  [
    [edit_map_path, "source_edit_map"],
    [recipe_path, "source_recipe"],
    [marker_plan_path, "source_edit_marker_plan"]
  ].each do |path, label|
    next unless path

    content_error = same_content_id_error(path, artifact["content_id"].to_s, label)
    errors << content_error if content_error
  end

  if edit_map_path && recipe_path && marker_plan_path && audio_or_cue_path
    begin
      edit_map_document = load_yaml_mapping(edit_map_path)
      recipe_document = load_yaml_mapping(recipe_path)
      marker_plan_document = load_yaml_mapping(marker_plan_path)
      audio_or_cue_document = load_optional_structured_mapping(
        audio_or_cue_path,
        "source_audio_or_cue_map",
        errors
      )
      unless edit_map_document["schema_version"].to_s == EDIT_MAP_SCHEMA_VERSION
        errors << "source_edit_map must use active #{EDIT_MAP_SCHEMA_VERSION}"
      end
      unless recipe_document["schema_version"].to_s == EDIT_RECIPE_SCHEMA_VERSION
        errors << "source_recipe must use active #{EDIT_RECIPE_SCHEMA_VERSION}"
      end
      unless marker_plan_document["schema_version"].to_s == MARKER_PLAN_SCHEMA_VERSION
        errors << "source_edit_marker_plan must use active #{MARKER_PLAN_SCHEMA_VERSION}"
      end
      unless edit_map_document.dig("edit_marker_plan_ref", "schema").to_s == MARKER_PLAN_SCHEMA_VERSION
        errors << "source_edit_map.edit_marker_plan_ref.schema must be #{MARKER_PLAN_SCHEMA_VERSION}"
      end
      marker_ref_sha = edit_map_document.dig("edit_marker_plan_ref", "sha256").to_s
      if marker_ref_sha.empty?
        errors << "source_edit_map.edit_marker_plan_ref.sha256 is required"
      elsif Digest::SHA256.file(marker_plan_path.to_s).hexdigest != marker_ref_sha
        errors << "source_edit_map.edit_marker_plan_ref.sha256 mismatch"
      end

      fps = recipe_fps(recipe_document)
      errors << "source_recipe must expose a positive render_spec/timebase fps" unless fps
      recipe_handles = Array(recipe_document["boundary_handle_contracts"]).each_with_object({}) do |handle, result|
        next unless handle.is_a?(Hash) && !handle["handle_id"].to_s.empty?

        if result.key?(handle["handle_id"].to_s)
          errors << "source_recipe has duplicate boundary handle #{handle['handle_id']}"
        else
          result[handle["handle_id"].to_s] = handle
        end
      end
      Array(artifact["fx_records"]).each_with_index do |record, index|
        next unless record.is_a?(Hash)

        design = record["effect_design"].is_a?(Hash) ? record["effect_design"] : {}
        canonical = effect_aliases(effect_registry)[design["effect_type"].to_s]
        next unless canonical == "xfade"

        label = "fx_records[#{index}] #{record['fx_id']}"
        handle_ref = design["transition_handle_ref"].to_s
        if record["status"].to_s == "pass" && handle_ref.empty?
          errors << "#{label} passed xfade requires transition_handle_ref owned by source_recipe"
          next
        end
        next if handle_ref.empty?

        handle = recipe_handles[handle_ref]
        unless handle
          errors << "#{label}.transition_handle_ref #{handle_ref.inspect} is not in source_recipe.boundary_handle_contracts"
          next
        end
        if design["from_slot"] && design["from_slot"].to_s != handle["from_slot"].to_s
          errors << "#{label}.from_slot must match #{handle_ref}"
        end
        if design["to_slot"] && design["to_slot"].to_s != handle["to_slot"].to_s
          errors << "#{label}.to_slot must match #{handle_ref}"
        end
        if design["duration_frames"].is_a?(Integer) && design["duration_frames"] != handle["transition_frames"]
          errors << "#{label}.duration_frames must match #{handle_ref}.transition_frames"
        end
        if design["program_start_frame"].is_a?(Integer) && design["program_start_frame"] != handle["fixed_program_cut_frame"]
          errors << "#{label}.program_start_frame must match #{handle_ref}.fixed_program_cut_frame"
        end
        if fps && design["program_start_seconds"].is_a?(Numeric) && design["program_start_frame"].is_a?(Integer)
          projected = design["program_start_frame"] / fps
          if (design["program_start_seconds"].to_f - projected).abs > 0.5 / fps
            errors << "#{label}.program_start_seconds is more than half a frame from program_start_frame"
          end
        end
      end

      edit_recipe_rows = resolve_lineage_pointer_set(
        edit_map_document,
        [
          ["source_edit_map.recipe_qc_contract.current_final_recipe", %w[recipe_qc_contract current_final_recipe]],
          ["source_edit_map.manual_adjustment_workflow.current_final_recipe", %w[manual_adjustment_workflow current_final_recipe]],
          ["source_edit_map.edit_marker_plan_ref.source_recipe", %w[edit_marker_plan_ref source_recipe]]
        ],
        run_root,
        "source_edit_map current recipe lineage",
        errors
      )
      edit_recipe_rows.each do |label, pointer_path|
        require_same_path(recipe_path, pointer_path, label, errors)
      end

      edit_marker_pointer = resolve_lineage_pointer(
        run_root,
        edit_map_document.dig("edit_marker_plan_ref", "path"),
        "source_edit_map.edit_marker_plan_ref.path",
        errors
      )
      require_same_path(marker_plan_path, edit_marker_pointer, "source_edit_map.edit_marker_plan_ref.path", errors)

      marker_recipe_pointer = resolve_lineage_pointer(
        run_root,
        marker_plan_document["source_recipe"],
        "source_edit_marker_plan.source_recipe",
        errors
      )
      require_same_path(recipe_path, marker_recipe_pointer, "source_edit_marker_plan.source_recipe", errors)

      recipe_audio_rows = resolve_lineage_pointer_set(
        recipe_document,
        [
          ["source_recipe.audio_path", ["audio_path"]],
          ["source_recipe.source_audio", ["source_audio"]],
          ["source_recipe.audio_summary.audio_path", %w[audio_summary audio_path]]
        ],
        run_root,
        "source_recipe selected-audio lineage",
        errors
      )
      recipe_audio_path = recipe_audio_rows.first&.last
      recipe_audio_rows.each do |label, pointer_path|
        require_same_path(recipe_audio_path, pointer_path, label, errors)
      end

      marker_selected_audio = resolve_lineage_pointer(
        run_root,
        marker_plan_document["source_audio"],
        "source_edit_marker_plan.source_audio",
        errors
      )
      require_same_path(recipe_audio_path, marker_selected_audio, "source_edit_marker_plan.source_audio", errors)

      edit_selected_audio = resolve_lineage_pointer(
        run_root,
        edit_map_document.dig("audio_marker_handoff", "source_audio"),
        "source_edit_map.audio_marker_handoff.source_audio",
        errors
      )
      require_same_path(recipe_audio_path, edit_selected_audio, "source_edit_map.audio_marker_handoff.source_audio", errors)

      marker_audio_rows = resolve_lineage_pointer_set(
        marker_plan_document,
        [
          ["source_edit_marker_plan.source_audio_motion_director_map", ["source_audio_motion_director_map"]]
        ],
        run_root,
        "source_edit_marker_plan current audio timing lineage",
        errors
      )
      unless marker_audio_rows.any? { |_label, pointer_path| pointer_path.realpath == audio_or_cue_path.realpath }
        errors << "source_audio_or_cue_map must match source_edit_marker_plan.source_audio_motion_director_map"
      end

      edit_audio_rows = resolve_lineage_pointer_set(
        edit_map_document,
        [
          ["source_edit_map.audio_marker_handoff.audio_motion_director_map", %w[audio_marker_handoff audio_motion_director_map]]
        ],
        run_root,
        "source_edit_map current audio timing lineage",
        errors
      )
      unless edit_audio_rows.any? { |_label, pointer_path| pointer_path.realpath == audio_or_cue_path.realpath }
        errors << "source_audio_or_cue_map must match source_edit_map.audio_marker_handoff.audio_motion_director_map"
      end
    rescue StandardError => e
      errors << "04FX v2 lineage cross-binding failed: #{e.message}"
    end
  end

  recipe_segment_ids = Set.new
  if recipe_path
    begin
      recipe_segment_ids = collect_recipe_segment_ids(load_yaml_mapping(recipe_path))
    rescue StandardError => e
      errors << "source_recipe cannot be inspected for source_edit_segment_refs: #{e.message}"
    end
  end

  gate_sections = Set.new(Array(artifact.dig("preview_gate", "section_ids")).map(&:to_s))
  finishing_root = Pathname.new(artifact_relative_path).dirname.to_s
  fx_preview_allowed = lambda do |path|
    path.start_with?("#{finishing_root}/") && PREVIEW_EXTENSIONS.include?(Pathname.new(path).extname.downcase)
  end
  fx_contact_sheet_allowed = lambda do |path|
    path.start_with?("#{finishing_root}/") && CONTACT_SHEET_EXTENSIONS.include?(Pathname.new(path).extname.downcase)
  end

  fx_records = Array(artifact["fx_records"])
  fx_ids = fx_records.each_with_object([]) do |record, values|
    values << record["fx_id"].to_s if record.is_a?(Hash) && !record["fx_id"].to_s.empty?
  end
  duplicate_fx_ids = fx_ids.group_by(&:itself).select { |_key, values| values.length > 1 }.keys
  errors << "fx_records fx_id values must be unique: #{duplicate_fx_ids.sort.join(', ')}" unless duplicate_fx_ids.empty?

  canonical_effect_by_fx_id = {}
  fx_records.each_with_index do |record, index|
    next unless record.is_a?(Hash)

    canonical = validate_effect_against_registry(
      record,
      effect_registry,
      "fx_records[#{index}] #{record['fx_id']}",
      errors,
      final: false
    )
    canonical_effect_by_fx_id[record["fx_id"].to_s] = canonical if canonical
  end

  audit = artifact["transition_opportunity_audit"]
  if artifact["status"].to_s == "passed_for_final_render" && !audit.is_a?(Hash)
    errors << "passed_for_final_render requires transition_opportunity_audit"
  end
  if audit.is_a?(Hash)
    points = Array(audit["points"])
    point_ids = points.each_with_object([]) do |point, values|
      values << point["point_id"].to_s if point.is_a?(Hash) && !point["point_id"].to_s.empty?
    end
    duplicate_point_ids = point_ids.group_by(&:itself).select { |_key, values| values.length > 1 }.keys
    errors << "transition_opportunity_audit point_id values must be unique: #{duplicate_point_ids.sort.join(', ')}" unless duplicate_point_ids.empty?

    linked_fx_ids = Set.new
    proposal_count = 0
    points.each_with_index do |point, index|
      next unless point.is_a?(Hash)

      disposition = point["disposition"].to_s
      point_label = "transition_opportunity_audit.points[#{index}] #{point['point_id']}"
      if schema_version == V2_SCHEMA_VERSION
        program_frame = point["program_frame"]
        program_time = point["program_time"]
        unless program_frame.is_a?(Integer) && program_frame >= 0
          errors << "#{point_label}.program_frame must be an integer >= 0"
        end
        if fps && program_frame.is_a?(Integer) && program_time.is_a?(Numeric)
          projected = program_frame / fps
          if (program_time.to_f - projected).abs > 0.5 / fps
            errors << "#{point_label}.program_time is more than half a frame from program_frame"
          end
        end
      end
      if %w[safe_default_proposed manual_fx_proposed].include?(disposition)
        proposal_count += 1
        fx_id_ref = point["fx_id_ref"].to_s
        unless fx_ids.include?(fx_id_ref)
          errors << "#{point_label}.fx_id_ref #{fx_id_ref.inspect} does not link to fx_records"
          next
        end
        linked_fx_ids << fx_id_ref
        proposed = canonical_effect_type(
          point["proposed_effect_type"], effect_registry, "#{point_label}.proposed_effect_type", errors
        )
        actual = canonical_effect_by_fx_id[fx_id_ref]
        if proposed && actual && proposed != actual
          errors << "#{point_label}.proposed_effect_type #{proposed} does not match #{fx_id_ref} effect_type #{actual}"
        end
      elsif !point["fx_id_ref"].to_s.empty?
        errors << "#{point_label}.fx_id_ref is allowed only for an FX proposal disposition"
      end
    end

    audit_status = audit["audit_status"].to_s
    if audit_status == "complete_no_fx_needed"
      errors << "complete_no_fx_needed requires every point disposition=none_needed" unless points.all? { |point| point.is_a?(Hash) && point["disposition"] == "none_needed" }
      errors << "complete_no_fx_needed requires fx_records to be empty" unless fx_records.empty?
    elsif audit_status == "complete_fx_passed"
      errors << "complete_fx_passed requires at least one linked FX proposal" if proposal_count.zero?
      non_pass_linked = linked_fx_ids.select do |fx_id|
        fx_records.find { |record| record.is_a?(Hash) && record["fx_id"].to_s == fx_id }.to_h["status"].to_s != "pass"
      end
      errors << "complete_fx_passed requires every linked FX to pass: #{non_pass_linked.to_a.sort.join(', ')}" unless non_pass_linked.empty?
      unlinked_pass = fx_records.each_with_object([]) do |record, values|
        next unless record.is_a?(Hash) && record["status"].to_s == "pass"
        next if linked_fx_ids.include?(record["fx_id"].to_s)

        values << record["fx_id"].to_s
      end
      errors << "complete_fx_passed requires every passed FX to be linked from the audit: #{unlinked_pass.sort.join(', ')}" unless unlinked_pass.empty?
    end

    if artifact["status"].to_s == "passed_for_final_render"
      unresolved = points.each_with_object([]) do |point, values|
        next unless point.is_a?(Hash)
        next unless %w[review_candidate return_to_04].include?(point["disposition"].to_s)

        values << "#{point['point_id']}(#{point['disposition']})"
      end
      errors << "passed_for_final_render has unresolved audit points: #{unresolved.join(', ')}" unless unresolved.empty?
      coverage_fps = recipe_document && recipe_fps_fraction(recipe_document)
      if coverage_fps && marker_plan_document && audio_or_cue_document
        validate_full_master_coverage(
          artifact,
          audit,
          recipe_document,
          marker_plan_document,
          audio_or_cue_document,
          coverage_fps,
          errors
        )
      else
        errors << "passed_for_final_render cannot recompute exact full-master coverage from its hash-bound sources"
      end
    end
  end

  if artifact["status"].to_s == "passed_for_final_render" && schema_version != V2_SCHEMA_VERSION
    non_pass = fx_records.map do |record|
      next unless record.is_a?(Hash) && record["status"].to_s != "pass"

      "#{record['fx_id']}(#{record['status']})"
    end.compact
    errors << "passed_for_final_render requires every FX record to be pass: #{non_pass.join(', ')}" unless non_pass.empty?
  end

  fx_records.each_with_index do |record, index|
    next unless record.is_a?(Hash)

    label = "fx_records[#{index}] #{record['fx_id']}"
    record_sections = Set.new(Array(record["section_ids"]).map(&:to_s))
    outside_sections = record_sections - gate_sections
    errors << "#{label} section_ids are outside preview_gate.section_ids: #{outside_sections.to_a.sort.join(', ')}" unless outside_sections.empty?

    Array(record["source_edit_segment_refs"]).each do |segment_ref|
      next if recipe_segment_ids.include?(segment_ref.to_s)

      errors << "#{label} source_edit_segment_ref #{segment_ref.inspect} is not present in source_recipe"
    end

    next unless record["status"].to_s == "pass"

    preview_qc = record["preview_qc"].is_a?(Hash) ? record["preview_qc"] : {}
    fx_preview_path, fx_preview_error = resolve_run_owned_file(
      run_root,
      preview_qc["preview_path"],
      label: "#{label}.preview_qc.preview_path",
      allowed_path: fx_preview_allowed
    )
    fx_contact_sheet_path, fx_contact_sheet_error = resolve_run_owned_file(
      run_root,
      preview_qc["contact_sheet_path"],
      label: "#{label}.preview_qc.contact_sheet_path",
      allowed_path: fx_contact_sheet_allowed
    )
    errors << fx_preview_error if fx_preview_error
    errors << fx_contact_sheet_error if fx_contact_sheet_error
    sha256_matches?(fx_preview_path, preview_qc["preview_sha256"], "#{label}.preview_qc.preview", errors) if fx_preview_path
    sha256_matches?(fx_contact_sheet_path, preview_qc["contact_sheet_sha256"], "#{label}.preview_qc.contact_sheet", errors) if fx_contact_sheet_path

    missing_checks = REQUIRED_PASSED_FX_CHECKS - Array(preview_qc["checks"]).map(&:to_s)
    errors << "#{label} passed preview QC is missing checks: #{missing_checks.join(', ')}" unless missing_checks.empty?
  end

end

if errors.empty?
  puts(
    "OK: edit finishing FX recipe/preview dependency lock valid; " \
    "recorded preview gate preserved; no pass inferred"
  )
  exit 0
end

errors.each { |error| warn "ERROR: #{error}" }
exit 1
