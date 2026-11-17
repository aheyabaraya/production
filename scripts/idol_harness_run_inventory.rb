#!/usr/bin/env ruby
# frozen_string_literal: true

require "date"
require "digest"
require "fileutils"
require "json"
require "optparse"
require "pathname"
require "time"
require "yaml"
require_relative "lib/idol_artifact_integrity"
require_relative "lib/idol_run_layout"

ROOT = Pathname.new(__dir__).join("..").expand_path
STAGE_REGISTRY = ROOT.join("automation", "harness-stage-registry.yaml")
ARTIFACT_ROUTING = ROOT.join("automation", "harness-artifact-routing.yaml")
VERSION_REGISTRY = ROOT.join("automation", "harness-contract-version-registry.yaml")
CURRENT_NEXT_YAML = ROOT.join("automation", "current-next.yaml")
CURRENT_NEXT_MD = ROOT.join("automation", "current-next.md")

options = {album_key: nil, title_key: nil, json: false, write: false, output: nil}
OptionParser.new do |parser|
  parser.banner = "usage: ruby scripts/idol_harness_run_inventory.rb RUN_ROOT [--album-key KEY --title-key KEY] [--json] [--write] [--output PATH]"
  parser.on("--album-key KEY") { |value| options[:album_key] = value }
  parser.on("--title-key KEY") { |value| options[:title_key] = value }
  parser.on("--json") { options[:json] = true }
  parser.on("--write") { options[:write] = true }
  parser.on("--output PATH") { |value| options[:output] = value }
end.parse!

run_arg = ARGV.shift
abort "ERROR: RUN_ROOT is required" if run_arg.to_s.strip.empty?
run_path = Pathname.new(run_arg)
run_path = ROOT.join(run_path) unless run_path.absolute?
run_path = run_path.cleanpath
abort "ERROR: run root is missing: #{run_arg}" unless run_path.directory?
layout_errors = IdolRunLayout.validate(run_path, repo_root: ROOT)
abort "ERROR: #{layout_errors.join('; ')}" unless layout_errors.empty?

def rel(path)
  Pathname.new(path).expand_path.relative_path_from(ROOT).to_s
rescue ArgumentError
  path.to_s
end

def load_yaml(path)
  value = YAML.safe_load(path.read, permitted_classes: [Date, Time], aliases: true)
  value.is_a?(Hash) ? value : {}
rescue Psych::SyntaxError
  {}
end

def load_structured(path)
  case path.extname.downcase
  when ".yaml", ".yml"
    load_yaml(path)
  when ".json"
    value = JSON.parse(path.read)
    value.is_a?(Hash) ? value : {}
  else
    {}
  end
rescue JSON::ParserError
  {}
end

def active_artifact?(path)
  value = path.to_s.downcase
  !value.match?(%r{(?:^|/)(?:archive|archives|backup|backups)(?:/|$)|archived|\.pre[-_]|pre[-_].*backup|\.bak\z})
end

def expand_pattern(pattern, run_path, album_key, title_key)
  expanded = pattern.to_s
                    .gsub("ALBUM_KEY", album_key.to_s)
                    .gsub("TITLE_KEY", title_key.to_s)
                    .gsub("TITLE_SONG_KEY", title_key.to_s)
                    .gsub("CONTENT_ID", run_path.basename.to_s)
                    .gsub("vN", "v*")
  base = expanded.start_with?("catalog/", "automation/", "assets/", "source-materials/") ? ROOT : run_path
  Dir.glob(base.join(expanded).to_s).select { |path| File.file?(path) }.map { |path| Pathname.new(path).cleanpath }
end

def nested_strings(value, output = [])
  case value
  when Hash
    value.each_value { |child| nested_strings(child, output) }
  when Array
    value.each { |child| nested_strings(child, output) }
  when String
    output << value
  end
  output
end

def canonical_value(value)
  case value
  when Hash
    value.keys.map(&:to_s).sort.each_with_object({}) { |key, result| result[key] = canonical_value(value[key]) }
  when Array
    value.map { |item| canonical_value(item) }
  else
    value
  end
end

def connected_external_artifact?(path, run_path, run_rel, registered_output_paths)
  expanded = path.expand_path.to_s
  return true if expanded.start_with?("#{run_path.expand_path}/")

  path_rel = rel(path)
  return true if registered_output_paths.include?(path_rel)

  document = load_structured(path)
  return true if nested_strings(document).any? { |value| value == run_rel || value.start_with?("#{run_rel}/") }

  return false unless %w[.md .txt].include?(path.extname.downcase)

  path.read.include?(run_rel)
rescue Errno::ENOENT, Errno::EACCES
  false
end

stage_registry = load_yaml(STAGE_REGISTRY)
artifact_routing = load_yaml(ARTIFACT_ROUTING)
version_registry = load_yaml(VERSION_REGISTRY)
run_identity = IdolRunLayout.identity(run_path, repo_root: ROOT)
run_identity_path = run_identity.fetch("identity_path")
run_identity_document = run_identity.fetch("document")
layout_status = run_identity.fetch("layout_status")
integrity_cache = IdolArtifactIntegrity::Cache.new(repo_root: ROOT)
file_binding = lambda do |path, profile = "repeat_local_validation"|
  result = integrity_cache.inspect_path(path, profile: profile)
  {
    "path" => rel(path),
    "sha256" => result.fetch("value"),
    "integrity_profile" => profile,
    "cache" => result.fetch("cache")
  }
end
contracts = Array(version_registry["contracts"]).select { |row| row.is_a?(Hash) }
contract_by_schema = contracts.each_with_object({}) { |row, memo| memo[row["schema"].to_s] = row }
contract_by_producer = contracts.each_with_object({}) { |row, memo| memo[row["producer"].to_s] = row }

current_yaml = load_yaml(CURRENT_NEXT_YAML)
current_md_text = CURRENT_NEXT_MD.file? ? CURRENT_NEXT_MD.read : ""
markdown_run = current_md_text[/^run:\s*`([^`]+)`/i, 1].to_s
markdown_generated = current_md_text[/^generated_at:\s*`([^`]+)`/i, 1].to_s
markdown_status = current_md_text[/^status:\s*`([^`]+)`/i, 1].to_s
markdown_owner = current_md_text[/^owner:\s*`([^`]+)`/i, 1].to_s
yaml_run = current_yaml["run"].to_s
yaml_generated = current_yaml["generated_at"].to_s
yaml_status = current_yaml["status"].to_s
yaml_owner = current_yaml["owner"].to_s

run_rel = rel(run_path)
run_address = run_identity
album_key = run_address.fetch("album_key")
title_key = run_address.fetch("title_key")
run_id = run_address.fetch("run_id")
identity_content_id = run_identity.fetch("content_id").to_s
title_registry_path = if options[:album_key] && options[:title_key]
                        ROOT.join("catalog", "albums", options[:album_key], options[:title_key], "output-registry.yaml")
                      else
                        Dir.glob(ROOT.join("catalog", "albums", "*", "*", "output-registry.yaml").to_s).map { |path| Pathname.new(path) }.find do |path|
                          document = load_yaml(path)
                          Array(document["source_runs"]).any? { |row| row.is_a?(Hash) && row["run_root"].to_s == run_rel }
                        end
                      end
title_registry_path = nil unless title_registry_path&.file?
title_registry = title_registry_path ? load_yaml(title_registry_path) : {}
run_registered = Array(title_registry["source_runs"]).any? { |row| row.is_a?(Hash) && row["run_root"].to_s == run_rel }
linked_outputs = Array(title_registry["outputs"]).select { |row| row.is_a?(Hash) && row["source_run_root"].to_s == run_rel }
registered_output_paths = linked_outputs.map { |row| row["path"].to_s }.reject(&:empty?).uniq

def contract_for(stage, schema_version, contract_by_schema, contract_by_producer)
  stage_contracts = Array(stage["output_contracts"]).map { |schema| contract_by_schema[schema.to_s] }.compact
  unless schema_version.to_s.empty?
    matches = stage_contracts.select { |row| row["current_authoring_version"].to_s == schema_version.to_s }
    return matches.first if matches.length == 1
  end
  return stage_contracts.first if stage_contracts.length == 1

  contract_by_producer[stage["stage_id"].to_s]
end

routing_by_stage = Array(artifact_routing["stages"]).select { |row| row.is_a?(Hash) }.to_h do |row|
  [row["stage_id"].to_s, row]
end
stage_rows = Array(stage_registry["stages"]).select { |row| row.is_a?(Hash) }.sort_by { |row| [row["order"].to_i, row["stage_id"].to_s] }.map do |stage|
  routing = routing_by_stage[stage["stage_id"].to_s].to_h
  patterns = Array(routing["canonical_patterns"]).map(&:to_s)
  paths = patterns
          .flat_map { |pattern| expand_pattern(pattern, run_path, album_key, title_key) }
          .uniq
          .select { |path| active_artifact?(path) }
          .select { |path| connected_external_artifact?(path, run_path, run_rel, registered_output_paths) }
          .sort
  artifacts = paths.map do |path|
    document = load_structured(path)
    schema_version = document["schema_version"]
    schema_version = schema_version.to_s unless schema_version.nil?
    contract = contract_for(stage, schema_version, contract_by_schema, contract_by_producer)
    version_status = if schema_version.nil? || schema_version.empty?
                       "no_schema_version"
                     elsif contract.nil?
                       "unmanaged_contract"
                     elsif contract["current_authoring_version"].to_s == schema_version
                       "current"
                     else
                       "unknown_version"
                     end
    {
      "path" => rel(path),
      "sha256" => integrity_cache.inspect_path(path, profile: "repeat_local_validation").fetch("value"),
      "byte_size" => path.size,
      "schema_version" => schema_version,
      "contract_id" => contract&.dig("contract_id"),
      "version_status" => version_status
    }
  end
  {
    "stage_id" => stage["stage_id"].to_s,
    "order" => stage["order"].to_i,
    "owner" => routing["canonical_owner"].to_s,
    "artifact_class" => routing["artifact_class"].to_s,
    "canonical_patterns" => patterns,
    "supporting_roots" => Array(routing["supporting_roots"]).map(&:to_s),
    "artifacts" => artifacts
  }
end

artifact_rows = stage_rows.flat_map { |row| row["artifacts"] }
holds = []
warnings = []
active_stage_ids = Array(stage_registry["stages"])
                   .select { |row| row.is_a?(Hash) && row["active"] == true }
                   .sort_by { |row| row["order"].to_i }
                   .map { |row| row["stage_id"].to_s }
routing_stage_ids = Array(artifact_routing["stages"]).map { |row| row["stage_id"].to_s }
holds << "artifact routing must exact-cover the active stage registry in order" unless routing_stage_ids == active_stage_ids
holds << "automation/current-next.yaml points to #{yaml_run}, not #{run_rel}" unless yaml_run == run_rel
warnings << "automation/current-next.md run differs from current-next.yaml" unless markdown_run == yaml_run
warnings << "automation/current-next.md generated_at differs from current-next.yaml" unless markdown_generated == yaml_generated
warnings << "automation/current-next.md status differs from current-next.yaml" unless markdown_status == yaml_status
warnings << "automation/current-next.md owner differs from current-next.yaml" unless markdown_owner == yaml_owner
holds << "run is not registered in the selected title output registry" unless run_registered
holds << "run identity status is #{run_identity['status']}, not active" unless run_identity["status"] == "active"
holds << "run identity content_id is blank" if identity_content_id.empty?

semantic_stage_rows = Array(stage_registry["stages"])
                      .select { |row| row.is_a?(Hash) && row["active"] == true }
                      .sort_by { |row| row["order"].to_i }
                      .map do |row|
  %w[stage_id order code owner_skill scope inputs founder_gate].to_h { |key| [key, row[key]] }
end
semantic_stage_sha = Digest::SHA256.hexdigest(JSON.generate(canonical_value(semantic_stage_rows)))
declared_flow_sha = run_identity_document.dig("flow_lock", "stage_sequence_sha256").to_s
unless declared_flow_sha == semantic_stage_sha
  holds << "run identity stage sequence lock differs from the active PRE-00 through 05 flow"
end
declared_registry_sha = run_identity_document.dig("flow_lock", "stage_registry_sha256").to_s
current_registry_sha = Digest::SHA256.file(STAGE_REGISTRY).hexdigest
if declared_registry_sha != current_registry_sha && declared_flow_sha == semantic_stage_sha
  warnings << "stage registry bytes changed but the locked stage sequence semantics are unchanged"
end
artifact_rows.each do |artifact|
  case artifact["version_status"]
  when "unmanaged_contract", "unknown_version"
    holds << "artifact version is not managed by the contract registry: #{artifact['path']} (#{artifact['schema_version']})"
  when "no_schema_version"
    warnings << "non-structured or unversioned connected artifact: #{artifact['path']}"
  end
end

report = {
  "schema_version" => "idol-harness-run-inventory.v2",
  "generated_at" => Time.now.iso8601,
  "run" => run_rel,
  "layout_status" => layout_status,
  "album_key" => album_key,
  "title_key" => title_key,
  "run_id" => run_id,
  "content_id" => identity_content_id,
  "status" => holds.empty? ? "pass" : "hold",
  "run_identity" => file_binding.call(run_identity_path, "canonical_gate"),
  "stage_registry" => file_binding.call(STAGE_REGISTRY),
  "artifact_routing" => file_binding.call(ARTIFACT_ROUTING),
  "contract_version_registry" => file_binding.call(VERSION_REGISTRY),
  "current_next" => {
    "yaml_path" => rel(CURRENT_NEXT_YAML),
    "yaml_run" => yaml_run,
    "yaml_matches_run" => yaml_run == run_rel,
    "markdown_path" => rel(CURRENT_NEXT_MD),
    "markdown_run" => markdown_run,
    "markdown_matches_yaml" => markdown_run == yaml_run,
    "generated_at_matches" => markdown_generated == yaml_generated,
    "yaml_status" => yaml_status,
    "markdown_status" => markdown_status,
    "status_matches" => markdown_status == yaml_status,
    "yaml_owner" => yaml_owner,
    "markdown_owner" => markdown_owner,
    "owner_matches" => markdown_owner == yaml_owner
  },
  "title_registry" => {
    "path" => title_registry_path ? rel(title_registry_path) : nil,
    "album_key" => title_registry.empty? ? album_key : title_registry["album_key"].to_s,
    "title_key" => title_registry.empty? ? title_key : title_registry["title_key"].to_s,
    "run_registered" => run_registered,
    "registered_output_count" => linked_outputs.length,
    "linked_output_paths" => linked_outputs.map { |row| row["path"].to_s }.reject(&:empty?).uniq.sort
  },
  "summary" => {
    "stage_count" => stage_rows.length,
    "connected_stage_count" => stage_rows.count { |row| !row["artifacts"].empty? },
    "connected_artifact_count" => artifact_rows.length,
    "current_version_count" => artifact_rows.count { |row| row["version_status"] == "current" },
    "unmanaged_version_count" => artifact_rows.count { |row| %w[unmanaged_contract unknown_version].include?(row["version_status"]) }
  },
  "stage_connections" => stage_rows,
  "holds" => holds.uniq.sort,
  "warnings" => warnings.uniq.sort
}

integrity_cache.save

if options[:write]
  output = options[:output] ? Pathname.new(options[:output]) : run_path.join("work", "harness-run-inventory.yaml")
  output = ROOT.join(output) unless output.absolute?
  FileUtils.mkdir_p(output.dirname)
  output.write(YAML.dump(report), encoding: "UTF-8")
  puts "wrote #{rel(output)}"
elsif options[:json]
  puts JSON.pretty_generate(report)
else
  puts "Graph Engineering run inventory: #{report['status']} (#{report.dig('summary', 'connected_artifact_count')} connected artifacts)"
  report["holds"].each { |hold| puts "HOLD #{hold}" }
  report["warnings"].each { |warning| puts "WARN #{warning}" }
end

exit(report["status"] == "pass" ? 0 : 1)
