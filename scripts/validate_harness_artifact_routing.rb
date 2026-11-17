#!/usr/bin/env ruby
# frozen_string_literal: true

require "date"
require "json"
require "open3"
require "optparse"
require "pathname"
require "yaml"

ROOT = Pathname.new(__dir__).join("..").expand_path
DEFAULT_ROUTING = ROOT.join("automation", "harness-artifact-routing.yaml")
DEFAULT_STAGE_REGISTRY = ROOT.join("automation", "harness-stage-registry.yaml")
SCHEMA = ROOT.join("schemas", "harness-artifact-routing.schema.json")
PYTHON = ROOT.join("scripts", "idol-video-python")
SCHEMA_VALIDATOR = ROOT.join("scripts", "validate_json_schema.py")
RETIRED_PATTERN = %r{(?:^|/)(?:00-creative-nucleus|01A-track-visual-board|02-generation-map)(?:\.|/)|mv-direction-reference-mining|reference-fragment-crop-lock}i

options = {
  json: false,
  routing: DEFAULT_ROUTING,
  stage_registry: DEFAULT_STAGE_REGISTRY
}
OptionParser.new do |parser|
  parser.banner = "usage: ruby scripts/validate_harness_artifact_routing.rb [--routing PATH] [--stage-registry PATH] [--json]"
  parser.on("--routing PATH") { |value| options[:routing] = ROOT.join(value).expand_path }
  parser.on("--stage-registry PATH") { |value| options[:stage_registry] = ROOT.join(value).expand_path }
  parser.on("--json") { options[:json] = true }
end.parse!

def load_mapping(path, label, errors)
  unless path.file?
    errors << "#{label} is missing: #{path}"
    return {}
  end
  value = YAML.safe_load(path.read, permitted_classes: [Date, Time], aliases: true)
  return value if value.is_a?(Hash)

  errors << "#{label} root must be an object"
  {}
rescue Psych::Exception => e
  errors << "#{label} cannot be parsed: #{e.message}"
  {}
end

def unsafe_relative?(value)
  path = value.to_s
  path.empty? || path.start_with?("/") || path == ".." || path.start_with?("../") || path.include?("/../")
end

errors = []
routing = load_mapping(options[:routing], "artifact routing", errors)
registry = load_mapping(options[:stage_registry], "stage registry", errors)

if options[:routing].file?
  stdout, stderr, status = Open3.capture3(
    PYTHON.to_s,
    SCHEMA_VALIDATOR.to_s,
    SCHEMA.to_s,
    options[:routing].to_s,
    chdir: ROOT.to_s
  )
  errors << "artifact routing schema failed: #{[stderr, stdout].join(' ').strip}" unless status.success?
end

active_stages = Array(registry["stages"])
                .select { |row| row.is_a?(Hash) && row["active"] == true }
                .sort_by { |row| [row["order"].to_i, row["stage_id"].to_s] }
routing_rows = Array(routing["stages"]).select { |row| row.is_a?(Hash) }
active_ids = active_stages.map { |row| row["stage_id"].to_s }
routing_ids = routing_rows.map { |row| row["stage_id"].to_s }
errors << "routing stage ids must exact-cover active registry order" unless routing_ids == active_ids

duplicate_ids = routing_ids.group_by(&:itself).select { |id, rows| id.empty? || rows.length > 1 }.keys
duplicate_ids.each { |id| errors << "duplicate or blank routing stage id: #{id.inspect}" }

registry_by_id = active_stages.to_h { |row| [row["stage_id"].to_s, row] }
canonical_pattern_owners = Hash.new { |hash, key| hash[key] = [] }
routing_rows.each do |row|
  stage_id = row["stage_id"].to_s
  stage = registry_by_id[stage_id]
  next unless stage

  expected_owner = stage["owner_skill"].to_s
  errors << "#{stage_id}: canonical_owner must match stage owner_skill #{expected_owner}" unless row["canonical_owner"].to_s == expected_owner

  Array(row["canonical_patterns"]).each do |pattern|
    canonical_pattern_owners[pattern.to_s] << stage_id
    errors << "#{stage_id}: unsafe canonical pattern #{pattern.inspect}" if unsafe_relative?(pattern)
    errors << "#{stage_id}: retired artifact pattern is forbidden in active routing: #{pattern}" if pattern.to_s.match?(RETIRED_PATTERN)
  end
  Array(row["supporting_roots"]).each do |root|
    errors << "#{stage_id}: unsafe supporting root #{root.inspect}" if unsafe_relative?(root)
    errors << "#{stage_id}: retired artifact root is forbidden in active routing: #{root}" if root.to_s.match?(RETIRED_PATTERN)
  end
end

canonical_pattern_owners.each do |pattern, owners|
  errors << "canonical pattern #{pattern.inspect} has multiple stage owners: #{owners.join(', ')}" if owners.uniq.length > 1
end

result = {
  "status" => errors.empty? ? "pass" : "fail",
  "active_stage_count" => active_ids.length,
  "routing_stage_count" => routing_ids.length,
  "active_stage_ids" => active_ids,
  "errors" => errors
}

if options[:json]
  puts JSON.pretty_generate(result)
elsif errors.empty?
  puts "OK: artifact routing exact-covers #{active_ids.length} active stages with matching owners"
else
  errors.each { |error| warn "ERROR: #{error}" }
end

exit(errors.empty? ? 0 : 1)
