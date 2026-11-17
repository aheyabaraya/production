#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "optparse"
require "pathname"
require "set"
require "time"
require "yaml"

ROOT = Pathname.new(__dir__).join("..").expand_path
DEFAULT_HUB = ROOT.join("source-materials", "video-sources")

options = {hub: DEFAULT_HUB, json: false, write: nil, strict: false}
OptionParser.new do |parser|
  parser.banner = "usage: ruby scripts/idol_video_reference_hub_audit.rb [--hub PATH] [--json] [--write PATH] [--strict]"
  parser.on("--hub PATH") { |value| options[:hub] = Pathname.new(value).expand_path }
  parser.on("--json") { options[:json] = true }
  parser.on("--write PATH") { |value| options[:write] = Pathname.new(value) }
  parser.on("--strict") { options[:strict] = true }
end.parse!

hub = options[:hub].cleanpath
abort "ERROR: video reference hub is missing: #{hub}" unless hub.directory?

def rel(path)
  Pathname.new(path).expand_path.relative_path_from(ROOT).to_s
rescue ArgumentError
  path.to_s
end

def load_yaml(path)
  value = YAML.safe_load(path.read, aliases: true)
  value.is_a?(Hash) ? value : {}
rescue Psych::SyntaxError
  {}
end

def expected_cadence(duration)
  return nil unless duration.is_a?(Numeric)
  return {"lane" => "short_source", "sampling_seconds" => 1, "part_seconds" => 5, "directory" => "segments-5s-1s"} if duration <= 60
  return {"lane" => "long_source", "sampling_seconds" => 3, "part_seconds" => 15, "directory" => "segments-15s"} if duration <= 270

  nil
end

def cadence_from_directory(directory)
  return {"lane" => "short_source", "sampling_seconds" => 1, "part_seconds" => 5, "directory" => "segments-5s-1s"} if directory == "segments-5s-1s"
  return {"lane" => "long_source", "sampling_seconds" => 3, "part_seconds" => 15, "directory" => "segments-15s"} if directory == "segments-15s"

  nil
end

def duration_with_evidence(document, source_root)
  duration = document.dig("discovery_metadata", "duration_seconds")
  return [duration.to_f, "source_manifest"] if duration.is_a?(Numeric)

  Dir.glob(source_root.join("videos", "*.info.json").to_s).sort.each do |path|
    metadata = JSON.parse(File.read(path, encoding: "UTF-8"))
    value = metadata["duration"]
    return [value.to_f, "info_json"] if value.is_a?(Numeric)
  rescue JSON::ParserError, Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError
    next
  end
  [nil, "missing"]
end

def cadence_directory(path)
  value = path.to_s
  return "segments-5s-1s" if value.include?("/segments-5s-1s/")
  return "segments-15s" if value.include?("/segments-15s/")
  return "_bootstrap" if value.include?("/_bootstrap/")

  nil
end

def range_from_name(path)
  match = File.basename(path.to_s).match(/-(\d{8})ms-(\d{8})ms\.[^.]+\z/)
  match ? [match[1].to_i, match[2].to_i] : nil
end

def selected_range_files(source_root)
  sheets = Dir.glob(source_root.join("contact-sheets", "**", "*").to_s).select do |path|
    File.file?(path) && File.basename(path).match?(/selected|detail|one-second/i)
  end
  manifests = Dir.glob(source_root.join("analysis", "*").to_s).select do |path|
    File.file?(path) && File.basename(path).match?(/selected|detail|one-second/i)
  end
  [sheets.sort, manifests.sort]
end

def one_second_manifest?(path)
  document = JSON.parse(File.read(path, encoding: "UTF-8"))
  interval = document["interval_seconds"]
  return true if interval.is_a?(Numeric) && interval <= 1.0
  return true if document["preset"].to_s == "one-second"

  false
rescue JSON::ParserError, Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError
  false
end

def cadence_manifest_proves?(frame_index, expected)
  row = frame_index["contact_sheet_manifest"]
  return false unless row.is_a?(Hash)

  path = Pathname.new(row["path"].to_s)
  path = ROOT.join(path) unless path.absolute?
  return false unless path.file?

  document = JSON.parse(path.read)
  document["interval_seconds"].to_f == expected["sampling_seconds"].to_f &&
    document["segment_duration_seconds"].to_f == expected["part_seconds"].to_f
rescue JSON::ParserError, Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError
  false
end

manifest_paths = Dir.glob(hub.join("{bilibili,youtube}", "by-source", "*", "source-manifest.yaml").to_s).sort
registered_roots = manifest_paths.map { |path| Pathname.new(path).dirname.cleanpath }.to_set
all_source_roots = Dir.glob(hub.join("{bilibili,youtube}", "by-source", "*").to_s).select { |path| File.directory?(path) }.map { |path| Pathname.new(path).cleanpath }

rows = manifest_paths.map do |manifest_string|
  manifest_path = Pathname.new(manifest_string)
  source_root = manifest_path.dirname
  document = load_yaml(manifest_path)
  identity = document["identity"].is_a?(Hash) ? document["identity"] : {}
  sheets = Array(document["contact_sheets"]).select { |row| row.is_a?(Hash) }
  sheet_paths = sheets.map { |row| row["path"].to_s }.reject(&:empty?)
  directories = sheet_paths.each_with_object([]) do |path, result|
    directory = cadence_directory(path)
    result << directory if directory
  end.uniq.sort
  duration, duration_evidence = duration_with_evidence(document, source_root)
  expected = expected_cadence(duration)
  registered_lane_directories = directories & %w[segments-5s-1s segments-15s]
  if expected.nil? && duration.nil? && registered_lane_directories.length == 1
    expected = cadence_from_directory(registered_lane_directories.first)
    duration_evidence = "registered_cadence_only"
  end
  filesystem_directories = Dir.glob(source_root.join("contact-sheets", "segments-*").to_s).select { |path| File.directory?(path) }.map { |path| File.basename(path) }.uniq.sort
  holds = []
  warnings = []
  sampling_note_proves = false

  if duration.nil? && expected.nil?
    holds << "duration_unknown_and_registered_cadence_unprovable"
  elsif duration.nil?
    warnings << "duration_not_manifest_bound_registered_lane_only"
  elsif duration > 270
    holds << "duration_exceeds_270_second_capture_limit"
  end

  if expected
    expected_paths = sheet_paths.select { |path| cadence_directory(path) == expected["directory"] }
    holds << "expected_cadence_not_registered:#{expected['directory']}" if expected_paths.empty?
    expected_paths.each do |path|
      absolute = ROOT.join(path).cleanpath
      holds << "registered_sheet_missing:#{path}" unless absolute.file?
    end
    ranges = expected_paths.each_with_object([]) do |path, result|
      range = range_from_name(path)
      result << range if range
    end.sort_by(&:first)
    holds << "registered_sheet_time_ranges_missing" if !expected_paths.empty? && ranges.length != expected_paths.length
    unless ranges.empty?
      holds << "registered_sheet_time_ranges_do_not_start_at_zero" unless ranges.first.first.zero?
      ranges.each_cons(2) do |left, right|
        holds << "registered_sheet_time_ranges_not_contiguous" unless left.last == right.first
      end
      maximum_ms = expected["part_seconds"] * 1000
      holds << "registered_sheet_part_exceeds_#{expected['part_seconds']}s" if ranges.any? { |start_ms, end_ms| end_ms <= start_ms || end_ms - start_ms > maximum_ms }
    end
    note_token = "#{expected['sampling_seconds']}-second sampling"
    sampling_note_proves = !expected_paths.empty? && expected_paths.all? do |path|
      row = sheets.find { |candidate| candidate["path"].to_s == path }
      row.to_h["sampling_note"].to_s.include?(note_token)
    end
  end

  frame_index_path = document["frame_index_path"].to_s
  if frame_index_path.empty? || !ROOT.join(frame_index_path).file?
    holds << "frame_index_missing"
  else
    frame_index = load_yaml(ROOT.join(frame_index_path))
    holds << "contact_sheet_manifest_missing" if expected && !frame_index["contact_sheet_manifest"].is_a?(Hash)
    if expected && !sampling_note_proves && !cadence_manifest_proves?(frame_index, expected)
      holds << "sampling_evidence_does_not_prove_#{expected['sampling_seconds']}s_in_#{expected['part_seconds']}s_parts"
    end
  end

  selected_sheets, selected_manifests = selected_range_files(source_root)
  selected_cadence_proven = if selected_sheets.empty?
                              true
                            else
                              selected_manifests.any? { |path| one_second_manifest?(path) }
                            end
  warnings << "selected_range_exists_without_machine_readable_1s_cadence_proof" unless selected_cadence_proven

  legacy_extra = filesystem_directories - [expected&.dig("directory")].compact
  warnings << "legacy_extra_cadence_retained:#{legacy_extra.join(',')}" unless legacy_extra.empty?

  {
    "source_key" => identity["source_key"].to_s.empty? ? "#{identity['platform']}:#{identity['platform_id']}" : identity["source_key"].to_s,
    "platform" => identity["platform"].to_s,
    "platform_id" => identity["platform_id"].to_s,
    "source_manifest" => rel(manifest_path),
    "duration_seconds" => duration,
    "duration_evidence" => duration_evidence,
    "expected_cadence" => expected,
    "registered_cadence_directories" => directories,
    "registered_sheet_count" => sheets.length,
    "selected_range_evidence" => {
      "sheet_paths" => selected_sheets.map { |path| rel(path) },
      "manifest_paths" => selected_manifests.map { |path| rel(path) },
      "required_sampling_seconds" => 1,
      "cadence_proven" => selected_cadence_proven
    },
    "legacy_extra_cadence_directories" => legacy_extra,
    "status" => holds.empty? ? "pass" : "hold",
    "holds" => holds.uniq.sort,
    "warnings" => warnings.uniq.sort
  }
end

unregistered = all_source_roots.reject { |path| registered_roots.include?(path) }
unregistered_rows = unregistered.sort.map do |source_root|
  platform = source_root.parent.parent.basename.to_s
  platform_id = source_root.basename.to_s
  duration, duration_evidence = duration_with_evidence({}, source_root)
  expected = expected_cadence(duration)
  cadence_directories = Dir.glob(source_root.join("contact-sheets", "segments-*").to_s)
                           .select { |path| File.directory?(path) }
                           .map { |path| File.basename(path) }
                           .uniq
                           .sort
  selected_sheets, selected_manifests = selected_range_files(source_root)
  selected_cadence_proven = !selected_sheets.empty? && selected_manifests.any? { |path| one_second_manifest?(path) }
  holds = ["source_root_is_not_registered"]
  holds << "duration_unknown" if duration.nil?
  holds << "duration_exceeds_270_second_capture_limit" if duration && duration > 270
  if expected && !cadence_directories.include?(expected["directory"])
    holds << "expected_cadence_directory_missing:#{expected['directory']}"
  end
  {
    "source_key" => "#{platform}:#{platform_id}",
    "platform" => platform,
    "platform_id" => platform_id,
    "source_root" => rel(source_root),
    "duration_seconds" => duration,
    "duration_evidence" => duration_evidence,
    "expected_cadence" => expected,
    "available_cadence_directories" => cadence_directories,
    "selected_range_evidence" => {
      "sheet_paths" => selected_sheets.map { |path| rel(path) },
      "manifest_paths" => selected_manifests.map { |path| rel(path) },
      "required_sampling_seconds" => 1,
      "cadence_proven" => selected_cadence_proven
    },
    "status" => "hold",
    "holds" => holds
  }
end
report = {
  "schema_version" => "idol-video-reference-hub-cadence-audit.v1",
  "generated_at" => Time.now.iso8601,
  "hub_root" => rel(hub),
  "overall_status" => rows.any? { |row| row["status"] == "hold" } || !unregistered.empty? ? "needs_attention" : "pass",
  "cadence_policy" => {
    "short_source_max_seconds" => 60,
    "short_sampling_seconds" => 1,
    "short_part_seconds" => 5,
    "long_source_max_seconds" => 270,
    "long_sampling_seconds" => 3,
    "long_part_seconds" => 15,
    "selected_range_sampling_seconds" => 1
  },
  "summary" => {
    "registered_source_count" => rows.length,
    "pass_count" => rows.count { |row| row["status"] == "pass" },
    "hold_count" => rows.count { |row| row["status"] == "hold" },
    "warning_count" => rows.sum { |row| row["warnings"].length },
    "unregistered_local_source_root_count" => unregistered.length
  },
  "unregistered_local_source_roots" => unregistered.map { |path| rel(path) }.sort,
  "unregistered_sources" => unregistered_rows,
  "sources" => rows
}

if options[:write]
  output = options[:write]
  output = ROOT.join(output) unless output.absolute?
  FileUtils.mkdir_p(output.dirname)
  output.write(YAML.dump(report), encoding: "UTF-8")
  puts "wrote #{rel(output)}"
elsif options[:json]
  puts JSON.pretty_generate(report)
else
  summary = report["summary"]
  puts "Video reference hub cadence: #{summary['pass_count']} pass / #{summary['hold_count']} hold / #{summary['registered_source_count']} registered"
  rows.select { |row| row["status"] == "hold" }.each do |row|
    puts "HOLD #{row['source_key']}: #{row['holds'].join(', ')}"
  end
  unregistered_rows.each do |row|
    puts "HOLD #{row['source_key']}: #{row['holds'].join(', ')}; cadence=#{row['available_cadence_directories'].join(',')}"
  end
end

exit 1 if options[:strict] && report["overall_status"] != "pass"
