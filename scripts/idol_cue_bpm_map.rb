#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "optparse"
require "pathname"
require "yaml"

options = {
  write: false,
  cue_sheet: nil,
  motion_map: nil,
  output: nil
}

parser = OptionParser.new do |opts|
  opts.banner = "usage: scripts/idol_cue_bpm_map.rb RUN_ROOT [--cue-sheet PATH] [--motion-map PATH] [--output PATH] [--write]"
  opts.on("--cue-sheet PATH", "Cue sheet markdown path") { |value| options[:cue_sheet] = value }
  opts.on("--motion-map PATH", "Audio motion director map YAML path") { |value| options[:motion_map] = value }
  opts.on("--output PATH", "Output cue BPM map YAML path") { |value| options[:output] = value }
  opts.on("--write", "Write the output file") { options[:write] = true }
end

parser.parse!

run_root_arg = ARGV.shift
unless run_root_arg
  warn parser.to_s
  exit 2
end

ROOT = Pathname.new(Dir.pwd).cleanpath

def resolve_path(path)
  raw = Pathname.new(path.to_s)
  raw.absolute? ? raw.cleanpath : (ROOT + raw).cleanpath
end

def relative_path(path)
  resolved = resolve_path(path)
  resolved.relative_path_from(ROOT).to_s
rescue ArgumentError
  resolved.to_s
end

def latest_path(paths)
  paths.select(&:file?).max_by do |path|
    version = path.basename.to_s[/v(\d+)/, 1].to_i
    [version, path.mtime.to_f, path.to_s]
  end
end

def latest_motion_map(run_root)
  latest_path((run_root + "research").glob("audio-motion-director-map-v*.yaml"))
end

def latest_cue_sheet(run_root)
  candidates = []
  candidates.concat((run_root + "handoff").glob("02-03-grok-imagine-*-webp/00-review/cue-sheet-v*.md"))
  candidates.concat((run_root + "handoff").glob("grok-imagine-v*/review/cue-sheet-v*.md"))
  candidates.concat((run_root + "handoff").glob("02-03-grok-imagine-v*/00-review-board/cue-sheet-v*.md"))
  latest_path(candidates)
end

def default_output_path(run_root)
  existing = (run_root + "research").glob("cue-bpm-map-v*.yaml")
  latest = latest_path(existing)
  return latest if latest

  run_root + "research" + "cue-bpm-map-v1.yaml"
end

def markdown_cells(line)
  line.strip.sub(/^\|/, "").sub(/\|$/, "").split("|").map(&:strip)
end

def separator_row?(cells)
  !cells.empty? && cells.all? { |cell| cell.match?(/\A:?-{3,}:?\z/) }
end

def parse_cue_sheet(path)
  lines = File.read(path.to_s, encoding: "UTF-8").split("\n")
  rows = []
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
    index += 1 if index < lines.length && lines[index].start_with?("|") && separator_row?(markdown_cells(lines[index]))
    while index < lines.length && lines[index].start_with?("|")
      cells = markdown_cells(lines[index])
      index += 1
      next if separator_row?(cells)

      cells << "" while cells.length < header.length
      row = {}
      header.each_with_index { |key, cell_index| row[key] = cells[cell_index].to_s }
      rows << row if row["Slot"].to_s.match?(/\AR[0-9]{2}[A-Z]?\z/)
    end
  end
  rows
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
    duration = match[1].to_f
    return {
      start_seconds: nil,
      end_seconds: nil,
      duration_seconds: duration,
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

def round_number(value, places = 2)
  return nil if value.nil?

  value.round(places)
end

def compact_text(value, limit = 120)
  text = value.to_s.gsub("_", " ").split.join(" ")
  return text if text.length <= limit

  cut = text.rindex(" ", limit - 3) || limit - 3
  text[0...cut].rstrip + "..."
end

def confidence_for(duration_seconds, insert)
  return "inherited_insert" if insert
  return "unknown" unless duration_seconds
  return "low_short_cue" if duration_seconds < 5

  "derived_from_global_grid"
end

def tempo_summary(main_bpm, double_bpm, main_beats, double_beats, confidence, motion_tempo, _beat_behavior)
  confidence_label = case confidence
                     when "derived_from_global_grid"
                       "grid-derived"
                     when "low_short_cue"
                       "low confidence"
                     when "inherited_insert"
                       "insert inherits edit window"
                     else
                       confidence.to_s
                     end
  parts = [
    "#{main_bpm}/#{double_bpm} BPM",
    main_beats && double_beats ? "~#{round_number(main_beats, 1)}/#{round_number(double_beats, 1)} beats" : nil,
    confidence_label,
    motion_tempo.to_s.empty? ? nil : compact_text(motion_tempo, 48)
  ].compact
  compact_text(parts.join("; "), 125)
end

def onset_summary(nearby_onsets)
  return "no strong onset flagged" if nearby_onsets.empty?

  "onsets @#{nearby_onsets.map { |value| "#{value}s" }.join(",")}"
end

def audio_cue_summary(motion, nearby_onsets)
  audio_section = motion["audio_section"].to_s
  measured_energy = motion["measured_energy"].to_s
  motion_energy = motion["motion_energy"].to_s
  camera_rhythm = motion["camera_rhythm"].to_s
  prompt_overlay = motion["prompt_overlay"].to_s
  parts = [
    [audio_section, measured_energy, motion_energy].reject(&:empty?).join(" / "),
    onset_summary(nearby_onsets),
    camera_rhythm.empty? ? nil : compact_text(camera_rhythm, 42),
    prompt_overlay.empty? ? nil : compact_text(prompt_overlay, 80)
  ].compact.reject(&:empty?)
  compact_text(parts.join("; "), 175)
end

run_root = resolve_path(run_root_arg)
motion_map_path = options[:motion_map] ? resolve_path(options[:motion_map]) : latest_motion_map(run_root)
cue_sheet_path = options[:cue_sheet] ? resolve_path(options[:cue_sheet]) : latest_cue_sheet(run_root)
output_path = options[:output] ? resolve_path(options[:output]) : default_output_path(run_root)

unless motion_map_path&.file?
  warn "audio motion director map not found"
  exit 1
end

unless cue_sheet_path&.file?
  warn "cue sheet not found"
  exit 1
end

motion_doc = YAML.load_file(motion_map_path.to_s)
unless motion_doc.is_a?(Hash)
  warn "audio motion director map must be a YAML mapping"
  exit 1
end

stable = motion_doc.fetch("stable_audio_extracts", {})
tempo_pair = stable.fetch("tempo_pair", {})
main_bpm = tempo_pair.fetch("main_grid_bpm").to_f
double_bpm = tempo_pair.fetch("double_time_candidate_bpm").to_f

source_audio_analysis = motion_doc["source_audio_analysis"].to_s
source_audio_analysis_data = motion_doc["source_audio_analysis_data"].to_s
analysis_data_path = source_audio_analysis_data.empty? ? nil : resolve_path(source_audio_analysis_data)
analysis_data = {}
if analysis_data_path&.file?
  analysis_data = JSON.parse(File.read(analysis_data_path.to_s, encoding: "UTF-8"))
end
strong_onsets = Array(analysis_data["strong_onset_energy_peaks"])

slot_motion = {}
Array(motion_doc["slot_motion_map"]).each do |slot|
  next unless slot.is_a?(Hash)

  slot_motion[slot["slot"].to_s] = slot
end

rows = parse_cue_sheet(cue_sheet_path)
cue_tempo_map = rows.map do |row|
  slot_id = row["Slot"].to_s
  motion = slot_motion.fetch(slot_id, {})
  time = row["Time"].to_s.empty? ? motion["time"].to_s : row["Time"].to_s
  parsed_time = parse_time_range(time)
  duration = parsed_time[:duration_seconds]
  main_beats = duration ? round_number(duration * main_bpm / 60.0) : nil
  double_beats = duration ? round_number(duration * double_bpm / 60.0) : nil
  confidence = confidence_for(duration, parsed_time[:insert])
  nearby_onsets = if parsed_time[:start_seconds] && parsed_time[:end_seconds]
                    strong_onsets.each_with_object([]) do |peak, values|
                      peak_time = peak["time"].to_f
                      values << peak_time if peak_time >= parsed_time[:start_seconds] && peak_time < parsed_time[:end_seconds]
                    end.map { |peak_time| round_number(peak_time, 2) }
                  else
                    []
                  end
  motion_tempo = motion["motion_tempo"].to_s
  beat_behavior = motion["beat_behavior"].to_s
  audio_cue = audio_cue_summary(motion, nearby_onsets)

  {
    "slot" => slot_id,
    "time" => time,
    "audio_section" => motion["audio_section"].to_s,
    "measured_energy" => motion["measured_energy"].to_s,
    "motion_energy" => motion["motion_energy"].to_s,
    "duration_seconds" => round_number(duration),
    "absolute_start_seconds" => round_number(parsed_time[:start_seconds]),
    "absolute_end_seconds" => round_number(parsed_time[:end_seconds]),
    "main_grid_bpm" => round_number(main_bpm),
    "double_time_candidate_bpm" => round_number(double_bpm),
    "beat_count_on_main_grid" => main_beats,
    "beat_count_on_double_time" => double_beats,
    "local_bpm_estimate" => nil,
    "confidence" => confidence,
    "strong_onset_count" => nearby_onsets.length,
    "nearby_strong_onsets_seconds" => nearby_onsets,
    "motion_tempo" => motion_tempo,
    "camera_rhythm" => motion["camera_rhythm"].to_s,
    "beat_behavior" => beat_behavior,
    "prompt_overlay" => motion["prompt_overlay"].to_s,
    "tempo_pulse_summary" => tempo_summary(round_number(main_bpm), round_number(double_bpm), main_beats, double_beats, confidence, motion_tempo, beat_behavior),
    "audio_cue_summary" => audio_cue,
    "bpm_use_note" => parsed_time[:insert] ? "No fixed song timestamp yet; inherit the tail section pulse when the editor chooses the replacement window." : "Cue-level BPM is derived from the selected audio's global grid. Do not treat this as a fresh independent BPM estimate for a short cue."
  }
end

doc = {
  "schema_version" => "idol_cue_bpm_map.v1",
  "content_id" => run_root.basename.to_s,
  "status" => "active_reference",
  "source_audio_analysis" => source_audio_analysis,
  "source_audio_analysis_data" => source_audio_analysis_data,
  "source_audio_motion_director_map" => relative_path(motion_map_path),
  "source_cue_sheet" => relative_path(cue_sheet_path),
  "purpose" => {
    "summary" => "Carry the selected audio tempo pair, cue-level pulse counts, energy, onset, and motion-pressure cues into cue sheets, founder review, and post-review video prompt work.",
    "use_rule" => "Use this as timing and energy pressure, not as choreography lock. Short cues inherit the selected audio grid; inserts inherit the final edit placement."
  },
  "tempo_basis" => {
    "main_grid_bpm" => round_number(main_bpm),
    "double_time_candidate_bpm" => round_number(double_bpm),
    "local_bpm_rule" => "Do not estimate a new local BPM from 3-12 second cues unless a later edit/audio pass provides stronger evidence."
  },
  "cue_tempo_map" => cue_tempo_map
}

if options[:write]
  output_path.dirname.mkpath
  File.write(output_path.to_s, YAML.dump(doc), encoding: "UTF-8")
end

puts JSON.pretty_generate(
  {
    write: options[:write],
    output: relative_path(output_path),
    cue_count: cue_tempo_map.length,
    main_grid_bpm: round_number(main_bpm),
    double_time_candidate_bpm: round_number(double_bpm),
    source_cue_sheet: relative_path(cue_sheet_path)
  }
)
