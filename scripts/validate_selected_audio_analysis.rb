#!/usr/bin/env ruby
# frozen_string_literal: true

require "date"
require "digest"
require "json"
require "open3"
require "pathname"
require "yaml"

REPO_ROOT = Pathname.new(__dir__).parent.expand_path
SCHEMA = REPO_ROOT.join("schemas", "selected-audio-analysis.schema.json")
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
  warn "usage: scripts/validate_selected_audio_analysis.rb PATH"
  exit 2
end

document_path = resolve_input(input)
unless document_path.file?
  warn "ERROR: selected-audio analysis is not readable: #{input}"
  exit 1
end

errors = []
warnings = []

begin
  document = load_mapping(document_path)
rescue JSON::ParserError, Psych::SyntaxError, TypeError => e
  warn "ERROR: selected-audio analysis parse error: #{e.message}"
  exit 1
end

run_schema_validation(document_path, errors)

validate_ref(document.dig("source_audio", "source_ref"), "source_audio.source_ref", document_path, errors)
lyrics_ref = document.dig("lyrics_original", "source_ref")
validate_ref(lyrics_ref, "lyrics_original.source_ref", document_path, errors) if lyrics_ref

Array(document.dig("audio_motion_handoff", "precision_marker_sources")).each_with_index do |ref, index|
  validate_ref(ref, "audio_motion_handoff.precision_marker_sources[#{index}]", document_path, errors)
end

craft = document["song_craft_evaluation"].to_h
candidate_ids = Array(craft["candidate_ids"]).map(&:to_s)
score_rows = Array(craft["audition_scorecard"])
score_ids = score_rows.map { |row| row["candidate_id"].to_s if row.is_a?(Hash) }.compact
dimensions = Array(craft["dimensions"]).map(&:to_s)
selected_id = craft["selected_candidate_id"]

errors << "song_craft_evaluation scorecard must cover each candidate exactly once" unless score_ids.sort == candidate_ids.sort
score_rows.each_with_index do |row, index|
  next unless row.is_a?(Hash)

  score_dimensions = row["dimension_scores"].to_h.keys.map(&:to_s)
  errors << "audition_scorecard[#{index}].dimension_scores must match dimensions" unless score_dimensions.sort == dimensions.sort
end
if selected_id && !candidate_ids.include?(selected_id.to_s)
  errors << "song_craft_evaluation.selected_candidate_id must appear in candidate_ids"
end
if craft["evaluation_mode"] == "comparative" && candidate_ids.uniq.length < 2
  errors << "comparative song_craft_evaluation requires at least two candidates"
end

cut = document["selected_cut"].to_h
active_start = cut["active_start_seconds"].to_f
active_end = cut["active_end_seconds"].to_f
selected_duration = cut["selected_duration_seconds"].to_f
source_duration = cut["source_duration_seconds"].to_f
errors << "selected_cut.active_end_seconds must be greater than active_start_seconds" unless active_end > active_start
errors << "selected_cut.active_end_seconds exceeds source duration" if active_end > source_duration + EPSILON
unless (selected_duration - (active_end - active_start)).abs <= EPSILON
  errors << "selected_cut.selected_duration_seconds must equal active_end_seconds - active_start_seconds"
end

sections = Array(document["section_map"])
seen_sections = {}
previous_end = nil
sections.each_with_index do |section, index|
  next unless section.is_a?(Hash)

  section_id = section["section_id"].to_s
  start_seconds = section["start_seconds"].to_f
  end_seconds = section["end_seconds"].to_f

  errors << "section_map[#{index}].section_id is duplicated: #{section_id}" if seen_sections[section_id]
  seen_sections[section_id] = true
  errors << "#{section_id}: end_seconds must be greater than start_seconds" unless end_seconds > start_seconds
  errors << "#{section_id}: starts before selected_cut.active_start_seconds" if start_seconds < active_start - EPSILON
  errors << "#{section_id}: ends after selected_cut.active_end_seconds" if end_seconds > active_end + EPSILON
  errors << "#{section_id}: overlaps the previous section" if previous_end && start_seconds < previous_end - EPSILON
  previous_end = end_seconds

  trigger_ids = {}
  Array(section["audio_triggers"]).each_with_index do |trigger, trigger_index|
    next unless trigger.is_a?(Hash)

    trigger_id = trigger["trigger_id"].to_s
    trigger_time = trigger["time_seconds"].to_f
    errors << "#{section_id}.audio_triggers[#{trigger_index}] duplicates #{trigger_id}" if trigger_ids[trigger_id]
    trigger_ids[trigger_id] = true
    unless trigger_time >= start_seconds - EPSILON && trigger_time <= end_seconds + EPSILON
      errors << "#{section_id}.audio_triggers[#{trigger_index}] falls outside its section"
    end
  end
end

if document["status"] == "founder_selected"
  errors << "founder_selected requires source_audio.founder_selection_status=selected" unless document.dig("source_audio", "founder_selection_status") == "selected"
  errors << "founder_selected requires a selected candidate id" if selected_id.to_s.empty?
end

if errors.empty?
  puts "OK: #{sections.length} selected-audio section record(s) validated"
  warnings.each { |warning| warn "WARNING: #{warning}" }
  exit 0
end

errors.each { |error| warn "ERROR: #{error}" }
warnings.each { |warning| warn "WARNING: #{warning}" }
exit 1
