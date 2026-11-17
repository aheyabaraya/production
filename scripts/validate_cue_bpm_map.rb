#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "pathname"
require "yaml"

path = ARGV.fetch(0) do
  warn "usage: scripts/validate_cue_bpm_map.rb PATH_TO_cue-bpm-map-vN.yaml"
  exit 2
end

root = Pathname.new(Dir.pwd)
errors = []
warnings = []

def resolve_path(path, root)
  return nil if path.nil? || path.to_s.strip.empty?

  raw = Pathname.new(path.to_s)
  raw.absolute? ? raw.cleanpath : (root + raw).cleanpath
end

def readable_file?(path)
  path && File.file?(path.to_s)
end

def load_yaml_hash(path, label, errors)
  unless readable_file?(path)
    errors << "#{label} is not readable: #{path}"
    return {}
  end

  doc = YAML.load_file(path.to_s)
  unless doc.is_a?(Hash)
    errors << "#{label} must be a YAML mapping"
    return {}
  end

  doc
rescue Psych::SyntaxError => e
  errors << "#{label} YAML syntax error: #{e.message}"
  {}
end

def blank?(value)
  value.nil? || value.to_s.strip.empty?
end

def positive_number?(value)
  value.is_a?(Numeric) && value.positive?
end

def close_number?(actual, expected, tolerance = 0.05)
  return false unless actual.is_a?(Numeric) && expected.is_a?(Numeric)

  (actual - expected).abs <= tolerance
end

def markdown_cells(line)
  line.strip.sub(/^\|/, "").sub(/\|$/, "").split("|").map(&:strip)
end

def markdown_separator?(cells)
  !cells.empty? && cells.all? { |cell| cell.match?(/\A:?-{3,}:?\z/) }
end

def parse_cue_sheet(path)
  rows = []
  lines = File.read(path.to_s, encoding: "UTF-8").split("\n")
  index = 0
  while index < lines.length
    line = lines[index]
    unless line.start_with?("|")
      index += 1
      next
    end

    header = markdown_cells(line)
    unless header.include?("Slot") && header.include?("Time")
      index += 1
      next
    end

    index += 1
    if index < lines.length && lines[index].start_with?("|") && markdown_separator?(markdown_cells(lines[index]))
      index += 1
    end

    while index < lines.length && lines[index].start_with?("|")
      cells = markdown_cells(lines[index])
      index += 1
      next if markdown_separator?(cells)

      cells << "" while cells.length < header.length
      row = {}
      header.each_with_index { |key, cell_index| row[key] = cells[cell_index].to_s }
      rows << row if row["Slot"].to_s.match?(/\AR[0-9]{2}[A-Z]?\z/)
    end
  end
  rows
rescue Errno::ENOENT
  []
end

def timecode_to_seconds(value)
  parts = value.to_s.strip.split(":")
  return nil if parts.empty?

  seconds = parts.pop.to_f
  minutes = parts.pop.to_i if parts.any?
  hours = parts.pop.to_i if parts.any?
  seconds + minutes.to_i * 60 + hours.to_i * 3600
end

def parse_time_range(value)
  text = value.to_s.strip
  if (match = text.match(/\A(\d+(?:\.\d+)?)s\s+INSERT\z/i))
    return {
      start_seconds: nil,
      end_seconds: nil,
      duration_seconds: match[1].to_f,
      insert: true
    }
  end

  if (match = text.match(/\A([0-9:.]+)-([0-9:.]+)\z/))
    start_seconds = timecode_to_seconds(match[1])
    end_seconds = timecode_to_seconds(match[2])
    if start_seconds && end_seconds && end_seconds >= start_seconds
      return {
        start_seconds: start_seconds,
        end_seconds: end_seconds,
        duration_seconds: end_seconds - start_seconds,
        insert: false
      }
    end
  end

  {
    start_seconds: nil,
    end_seconds: nil,
    duration_seconds: nil,
    insert: false
  }
end

def rounded(value)
  value.nil? ? nil : value.round(2)
end

def expected_confidence(duration_seconds, insert)
  return "inherited_insert" if insert
  return "unknown" unless duration_seconds
  return "low_short_cue" if duration_seconds < 5

  "derived_from_global_grid"
end

resolved_path = resolve_path(path, root)
doc = load_yaml_hash(resolved_path, "cue BPM map", errors)

required_top_fields = %w[
  schema_version
  content_id
  status
  source_audio_analysis
  source_audio_analysis_data
  source_audio_motion_director_map
  source_cue_sheet
  purpose
  tempo_basis
  cue_tempo_map
]

required_top_fields.each do |field|
  errors << "missing top-level field: #{field}" unless doc.key?(field)
end

if doc["schema_version"].to_s != "idol_cue_bpm_map.v1"
  errors << "schema_version must be idol_cue_bpm_map.v1"
end

%w[source_audio_analysis source_audio_analysis_data source_audio_motion_director_map source_cue_sheet].each do |field|
  value = doc[field]
  resolved = resolve_path(value, root)
  errors << "#{field} is not readable: #{value}" unless readable_file?(resolved)
end

analysis_data = {}
analysis_path = resolve_path(doc["source_audio_analysis_data"], root)
if readable_file?(analysis_path)
  begin
    analysis_data = JSON.parse(File.read(analysis_path.to_s))
  rescue JSON::ParserError => e
    errors << "source_audio_analysis_data is not valid JSON: #{e.message}"
  end
end
strong_onsets = Array(analysis_data["strong_onset_energy_peaks"])

motion_path = resolve_path(doc["source_audio_motion_director_map"], root)
motion_doc = load_yaml_hash(motion_path, "audio motion director map", errors)
motion_slots = {}
if motion_doc.any?
  if motion_doc["schema_version"].to_s != "idol_audio_motion_director_map.v1"
    errors << "audio motion director map schema_version must be idol_audio_motion_director_map.v1"
  end
  if !blank?(motion_doc["content_id"]) && !blank?(doc["content_id"]) && motion_doc["content_id"].to_s != doc["content_id"].to_s
    errors << "content_id does not match audio motion director map"
  end

  Array(motion_doc["slot_motion_map"]).each do |entry|
    next unless entry.is_a?(Hash)

    motion_slots[entry["slot"].to_s] = entry
  end
  errors << "audio motion director map slot_motion_map must contain records" if motion_slots.empty?
end

cue_sheet_path = resolve_path(doc["source_cue_sheet"], root)
cue_rows = readable_file?(cue_sheet_path) ? parse_cue_sheet(cue_sheet_path) : []
cue_slots = cue_rows.map { |row| row["Slot"].to_s }
cue_by_slot = cue_rows.to_h { |row| [row["Slot"].to_s, row] }
errors << "source_cue_sheet must contain cue rows" if cue_rows.empty?

purpose = doc["purpose"]
if purpose.is_a?(Hash)
  %w[summary use_rule].each do |field|
    errors << "purpose.#{field} is required" if blank?(purpose[field])
  end
else
  errors << "purpose must be a mapping"
end

tempo = doc["tempo_basis"]
main_bpm = nil
double_bpm = nil
if tempo.is_a?(Hash)
  main_bpm = tempo["main_grid_bpm"]
  double_bpm = tempo["double_time_candidate_bpm"]
  errors << "tempo_basis.main_grid_bpm must be positive" unless positive_number?(main_bpm)
  errors << "tempo_basis.double_time_candidate_bpm must be positive" unless positive_number?(double_bpm)
  errors << "tempo_basis.local_bpm_rule is required" if blank?(tempo["local_bpm_rule"])
else
  errors << "tempo_basis must be a mapping"
end

if motion_doc.any?
  motion_tempo = motion_doc.dig("stable_audio_extracts", "tempo_pair")
  if motion_tempo.is_a?(Hash)
    motion_main = motion_tempo["main_grid_bpm"]
    motion_double = motion_tempo["double_time_candidate_bpm"]
    if positive_number?(main_bpm) && positive_number?(motion_main) && !close_number?(main_bpm, motion_main, 0.01)
      errors << "tempo_basis.main_grid_bpm does not match audio motion director map"
    end
    if positive_number?(double_bpm) && positive_number?(motion_double) && !close_number?(double_bpm, motion_double, 0.01)
      errors << "tempo_basis.double_time_candidate_bpm does not match audio motion director map"
    end
  else
    errors << "audio motion director map stable_audio_extracts.tempo_pair is required"
  end
end

records = doc["cue_tempo_map"]
unless records.is_a?(Array) && !records.empty?
  errors << "cue_tempo_map must be a non-empty array"
  records = []
end

record_slots = []
seen = {}
required_record_fields = %w[
  slot
  time
  audio_section
  measured_energy
  motion_energy
  duration_seconds
  main_grid_bpm
  double_time_candidate_bpm
  beat_count_on_main_grid
  beat_count_on_double_time
  local_bpm_estimate
  confidence
  strong_onset_count
  nearby_strong_onsets_seconds
  motion_tempo
  camera_rhythm
  beat_behavior
  prompt_overlay
  tempo_pulse_summary
  audio_cue_summary
  bpm_use_note
]

records.each_with_index do |record, index|
  label = record.is_a?(Hash) ? record["slot"].to_s : "cue_tempo_map[#{index}]"
  unless record.is_a?(Hash)
    errors << "cue_tempo_map[#{index}] must be a mapping"
    next
  end

  required_record_fields.each do |field|
    errors << "#{label}.#{field} is required" unless record.key?(field)
  end

  slot = record["slot"].to_s
  record_slots << slot
  errors << "#{label}: slot must be R00-style cue id" unless slot.match?(/\AR[0-9]{2}[A-Z]?\z/)
  if seen[slot]
    errors << "#{label}: duplicate slot"
  else
    seen[slot] = true unless slot.empty?
  end

  cue_row = cue_by_slot[slot]
  errors << "#{label}: missing from source cue sheet" unless cue_row
  if cue_row && cue_row["Time"].to_s != record["time"].to_s
    errors << "#{label}: time does not match source cue sheet"
  end

  motion = motion_slots[slot]
  if motion.nil?
    errors << "#{label}: missing from audio motion director map"
  else
    %w[audio_section measured_energy motion_energy motion_tempo camera_rhythm beat_behavior prompt_overlay].each do |field|
      if record[field].to_s != motion[field].to_s
        errors << "#{label}.#{field} does not match audio motion director map"
      end
    end
  end

  errors << "#{label}.main_grid_bpm must match tempo_basis" unless close_number?(record["main_grid_bpm"], main_bpm, 0.01)
  errors << "#{label}.double_time_candidate_bpm must match tempo_basis" unless close_number?(record["double_time_candidate_bpm"], double_bpm, 0.01)

  parsed_time = parse_time_range(record["time"])
  if parsed_time[:duration_seconds].nil?
    errors << "#{label}: time must be a range or Ns INSERT"
  else
    errors << "#{label}.duration_seconds mismatch" unless close_number?(record["duration_seconds"], rounded(parsed_time[:duration_seconds]), 0.01)
  end

  if parsed_time[:insert]
    errors << "#{label}.absolute_start_seconds must be null for insert cues" unless record["absolute_start_seconds"].nil?
    errors << "#{label}.absolute_end_seconds must be null for insert cues" unless record["absolute_end_seconds"].nil?
  elsif parsed_time[:start_seconds] && parsed_time[:end_seconds]
    errors << "#{label}.absolute_start_seconds mismatch" unless close_number?(record["absolute_start_seconds"], rounded(parsed_time[:start_seconds]), 0.01)
    errors << "#{label}.absolute_end_seconds mismatch" unless close_number?(record["absolute_end_seconds"], rounded(parsed_time[:end_seconds]), 0.01)
  end

  if positive_number?(main_bpm) && positive_number?(double_bpm) && parsed_time[:duration_seconds]
    expected_main_beats = rounded(parsed_time[:duration_seconds] * main_bpm / 60.0)
    expected_double_beats = rounded(parsed_time[:duration_seconds] * double_bpm / 60.0)
    errors << "#{label}.beat_count_on_main_grid mismatch" unless close_number?(record["beat_count_on_main_grid"], expected_main_beats)
    errors << "#{label}.beat_count_on_double_time mismatch" unless close_number?(record["beat_count_on_double_time"], expected_double_beats)
  end

  expected_confidence_value = expected_confidence(parsed_time[:duration_seconds], parsed_time[:insert])
  if record["confidence"].to_s != expected_confidence_value
    errors << "#{label}.confidence should be #{expected_confidence_value}"
  end

  unless record["local_bpm_estimate"].nil? || positive_number?(record["local_bpm_estimate"])
    errors << "#{label}.local_bpm_estimate must be null or positive"
  end
  warnings << "#{label}: local_bpm_estimate is set; confirm this came from an edit/audio pass" if positive_number?(record["local_bpm_estimate"])

  expected_onsets = []
  if parsed_time[:start_seconds] && parsed_time[:end_seconds]
    expected_onsets = strong_onsets.each_with_object([]) do |peak, values|
      peak_time = peak["time"].to_f
      values << rounded(peak_time) if peak_time >= parsed_time[:start_seconds] && peak_time < parsed_time[:end_seconds]
    end
  end
  actual_onsets = Array(record["nearby_strong_onsets_seconds"]).map { |value| rounded(value.to_f) }
  if actual_onsets != expected_onsets
    errors << "#{label}.nearby_strong_onsets_seconds mismatch"
  end
  if record["strong_onset_count"] != expected_onsets.length
    errors << "#{label}.strong_onset_count mismatch"
  end

  errors << "#{label}.tempo_pulse_summary is required" if blank?(record["tempo_pulse_summary"])
  errors << "#{label}.audio_cue_summary is required" if blank?(record["audio_cue_summary"])
  errors << "#{label}.bpm_use_note is required" if blank?(record["bpm_use_note"])
  if !blank?(record["tempo_pulse_summary"]) && positive_number?(main_bpm) && !record["tempo_pulse_summary"].include?(main_bpm.to_s)
    warnings << "#{label}: tempo_pulse_summary does not mention main_grid_bpm"
  end
  if !blank?(record["audio_cue_summary"]) && !blank?(record["audio_section"]) && !record["audio_cue_summary"].include?(record["audio_section"].to_s.tr("_", " "))
    warnings << "#{label}: audio_cue_summary does not clearly mention audio_section"
  end
end

missing_from_map = cue_slots - record_slots
extra_in_map = record_slots - cue_slots
errors << "cue_tempo_map missing cue sheet slot(s): #{missing_from_map.join(', ')}" unless missing_from_map.empty?
errors << "cue_tempo_map has slot(s) not in cue sheet: #{extra_in_map.join(', ')}" unless extra_in_map.empty?

if cue_slots == record_slots
  # Keep silent on exact order success.
elsif missing_from_map.empty? && extra_in_map.empty?
  warnings << "cue_tempo_map slot order differs from source cue sheet"
end

if errors.empty?
  puts "OK: #{records.length} cue tempo/audio record(s), #{cue_slots.length} cue sheet slot(s) validated"
  warnings.each { |warning| warn "WARNING: #{warning}" }
  exit 0
end

errors.each { |error| warn "ERROR: #{error}" }
warnings.each { |warning| warn "WARNING: #{warning}" }
exit 1
