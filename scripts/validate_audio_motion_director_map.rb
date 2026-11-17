#!/usr/bin/env ruby
# frozen_string_literal: true

require "date"
require "digest"
require "json"
require "open3"
require "pathname"
require "yaml"

REPO_ROOT = Pathname.new(__dir__).parent.expand_path
SCHEMA = REPO_ROOT.join("schemas", "audio-motion-director-map.schema.json")
SCHEMA_VALIDATOR = REPO_ROOT.join("scripts", "validate_json_schema.py")
PYTHON = REPO_ROOT.join("scripts", "idol-video-python")
EPSILON = 0.001

def load_mapping(path)
  text = File.read(path)
  parsed = if path.extname.downcase == ".json"
             JSON.parse(text)
           else
             YAML.safe_load(text, permitted_classes: [Date, Time], aliases: true)
           end
  raise TypeError, "document must be a mapping" unless parsed.is_a?(Hash)

  parsed
end

def resolve_input(raw)
  path = Pathname.new(raw.to_s)
  path.absolute? ? path.cleanpath : REPO_ROOT.join(path).cleanpath
end

def resolve_ref(raw, document_path)
  path = Pathname.new(raw.to_s)
  return path.cleanpath if path.absolute?

  local = document_path.dirname.join(path).cleanpath
  return local if local.file?

  REPO_ROOT.join(path).cleanpath
end

def validate_ref(ref, label, document_path, errors)
  unless ref.is_a?(Hash)
    errors << "#{label} must be an artifact reference"
    return nil
  end

  path = resolve_ref(ref["path"], document_path)
  unless path.file?
    errors << "#{label}.path is not readable: #{ref['path']}"
    return path
  end

  actual = Digest::SHA256.file(path).hexdigest
  errors << "#{label}.sha256 is stale" unless actual == ref["sha256"].to_s
  path
end

def run_schema_validation(document_path, errors)
  _stdout, stderr, status = Open3.capture3(
    PYTHON.to_s,
    SCHEMA_VALIDATOR.to_s,
    SCHEMA.to_s,
    document_path.to_s,
    chdir: REPO_ROOT.to_s
  )
  return if status.success?

  errors << "JSON Schema validation failed: #{stderr.strip}"
end

input = ARGV.fetch(0) do
  warn "usage: scripts/validate_audio_motion_director_map.rb PATH"
  exit 2
end

document_path = resolve_input(input)
unless document_path.file?
  warn "ERROR: audio motion evidence map is not readable: #{input}"
  exit 1
end

errors = []

begin
  document = load_mapping(document_path)
rescue JSON::ParserError, Psych::SyntaxError, TypeError => e
  warn "ERROR: audio motion evidence map parse error: #{e.message}"
  exit 1
end

run_schema_validation(document_path, errors)

analysis_path = validate_ref(
  document["source_selected_audio_analysis"],
  "source_selected_audio_analysis",
  document_path,
  errors
)

analysis = {}
if analysis_path&.file?
  begin
    analysis = load_mapping(analysis_path)
    errors << "source_selected_audio_analysis must use idol_selected_audio_analysis.v1" unless analysis["schema_version"] == "idol_selected_audio_analysis.v1"
  rescue JSON::ParserError, Psych::SyntaxError, TypeError => e
    errors << "source_selected_audio_analysis cannot be parsed: #{e.message}"
  end
end

Array(document.dig("stable_audio_extracts", "precision_marker_sources")).each_with_index do |ref, index|
  validate_ref(ref, "stable_audio_extracts.precision_marker_sources[#{index}]", document_path, errors)
end

duration = document.dig("stable_audio_extracts", "duration_seconds").to_f
signals = Array(document.dig("stable_audio_extracts", "signals"))
signal_ids = {}
signals.each_with_index do |signal, index|
  next unless signal.is_a?(Hash)

  signal_id = signal["signal_id"].to_s
  signal_time = signal["time_seconds"].to_f
  errors << "stable_audio_extracts.signals[#{index}] duplicates #{signal_id}" if signal_ids[signal_id]
  signal_ids[signal_id] = true
  errors << "stable_audio_extracts.signals[#{index}] exceeds duration_seconds" if signal_time > duration + EPSILON
end

source_sections = Array(analysis["section_map"]).reject { |section| section["reserve_status"] == "omitted" }
source_by_id = source_sections.each_with_object({}) { |section, memo| memo[section["section_id"].to_s] = section }
source_ids = source_sections.map { |section| section["section_id"].to_s }

sections = Array(document["section_rhythm_map"])
section_ids = sections.map { |section| section["section_id"].to_s if section.is_a?(Hash) }.compact
errors << "section_rhythm_map must preserve selected-audio section order exactly" unless source_ids == section_ids

seen_sections = {}
sections.each_with_index do |section, index|
  next unless section.is_a?(Hash)

  section_id = section["section_id"].to_s
  start_seconds = section["start_seconds"].to_f
  end_seconds = section["end_seconds"].to_f
  source = source_by_id[section_id]

  errors << "section_rhythm_map[#{index}] duplicates #{section_id}" if seen_sections[section_id]
  seen_sections[section_id] = true
  errors << "#{section_id}: end_seconds must be greater than start_seconds" unless end_seconds > start_seconds
  errors << "#{section_id}: end_seconds exceeds duration_seconds" if end_seconds > duration + EPSILON

  next unless source

  unless (start_seconds - source["start_seconds"].to_f).abs <= EPSILON
    errors << "#{section_id}: start_seconds drifted from selected-audio analysis"
  end
  unless (end_seconds - source["end_seconds"].to_f).abs <= EPSILON
    errors << "#{section_id}: end_seconds drifted from selected-audio analysis"
  end
end

handoff_ids = Array(document.dig("song_lock_handoff", "section_ids")).map(&:to_s)
errors << "song_lock_handoff.section_ids must equal section_rhythm_map order" unless handoff_ids == section_ids

trigger_ids = {}
Array(document["trigger_map"]).each_with_index do |trigger, index|
  next unless trigger.is_a?(Hash)

  trigger_id = trigger["trigger_id"].to_s
  section_id = trigger["section_id"].to_s
  time_seconds = trigger["time_seconds"].to_f
  section = sections.find { |row| row.is_a?(Hash) && row["section_id"].to_s == section_id }

  errors << "trigger_map[#{index}] duplicates #{trigger_id}" if trigger_ids[trigger_id]
  trigger_ids[trigger_id] = true
  unless section
    errors << "trigger_map[#{index}] names unknown section #{section_id}"
    next
  end

  unless time_seconds >= section["start_seconds"].to_f - EPSILON && time_seconds <= section["end_seconds"].to_f + EPSILON
    errors << "trigger_map[#{index}] falls outside section #{section_id}"
  end
end

if errors.empty?
  puts "OK: #{sections.length} section rhythm record(s), #{signals.length} audio signal(s), and #{trigger_ids.length} trigger(s) validated"
  exit 0
end

errors.each { |error| warn "ERROR: #{error}" }
exit 1
