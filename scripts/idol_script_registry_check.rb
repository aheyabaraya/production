#!/usr/bin/env ruby
# frozen_string_literal: true

# Fail-closed discovery/documentation check for the IDOL script registry.
# The registry, not README prose, declares the executable surface.

require "json"
require "optparse"
require "pathname"
require "set"
require "yaml"

DEFAULT_ROOT = Pathname.new(Dir.pwd).expand_path
DEFAULT_REGISTRY = Pathname.new("automation/idol-script-registry.yaml")

options = { json: false, root: DEFAULT_ROOT, registry: DEFAULT_ROOT + DEFAULT_REGISTRY }
OptionParser.new do |parser|
  parser.banner = "usage: ruby scripts/idol_script_registry_check.rb [--json] [--root PATH] [--registry PATH]"
  parser.on("--json") { options[:json] = true }
  parser.on("--root PATH") { |value| options[:root] = Pathname.new(value).expand_path }
  parser.on("--registry PATH") { |value| options[:registry] = Pathname.new(value).expand_path }
end.parse!

def relative_path(value)
  value.to_s.sub(%r{\A\./}, "")
end

def safe_inside(root, relative)
  return nil unless relative.is_a?(String) && !relative.empty? && !relative.start_with?("/")
  candidate = (root + relative).expand_path
  prefix = "#{root.expand_path}/"
  return nil unless candidate.to_s == root.expand_path.to_s || candidate.to_s.start_with?(prefix)

  candidate
end

def load_registry(path)
  YAML.safe_load(path.read(encoding: "UTF-8"), permitted_classes: [], permitted_symbols: [], aliases: false)
rescue StandardError => error
  raise "unable to parse registry #{path}: #{error.message}"
end

def discover_scripts(root, registry, errors)
  roots = registry["script_roots"]
  unless roots.is_a?(Array) && !roots.empty?
    errors << "script_roots must be a non-empty array"
    return []
  end

  discovered = []
  root_ids = Set.new
  root_paths = Set.new
  roots.each do |entry|
    unless entry.is_a?(Hash)
      errors << "script_roots contains a non-object"
      next
    end
    id = entry["id"]
    path = entry["path"]
    if !id.is_a?(String) || id.empty? || root_ids.include?(id)
      errors << "script root id is missing or duplicated: #{id.inspect}"
    else
      root_ids << id
    end
    root_path = safe_inside(root, path)
    unless root_path
      errors << "script root path escapes repository: #{path.inspect}"
      next
    end
    if root_paths.include?(relative_path(path))
      errors << "script root path is duplicated: #{path}"
    else
      root_paths << relative_path(path)
    end
    unless root_path.directory?
      errors << "script root is missing: #{path}"
      next
    end

    globs = entry["include_globs"]
    globs = [] unless globs.is_a?(Array)
    excludes = Array(entry["exclude_paths"]).map { |item| relative_path(item) }
    globs.each do |pattern|
      unless pattern.is_a?(String) && !pattern.empty?
        errors << "script root #{id} has an invalid include glob"
        next
      end
      Dir.glob((root_path + pattern).to_s).sort.each do |candidate|
        next unless File.file?(candidate)

        rel = relative_path(Pathname.new(candidate).expand_path.relative_path_from(root).to_s)
        next if excludes.include?(rel)
        discovered << rel
      end
    end
  end

  duplicate = discovered.group_by(&:itself).select { |_path, values| values.length > 1 }.keys.sort
  errors << "script roots discover duplicate paths: #{duplicate.join(', ')}" unless duplicate.empty?
  discovered.uniq.sort
end

def documentation_errors(root, registry, discovered)
  errors = []
  docs = registry["documentation_surfaces"]
  unless docs.is_a?(Hash)
    return ["documentation_surfaces must be an object"]
  end

  surfaces = []
  %w[start_here index].each do |key|
    surface = docs[key]
    unless surface.is_a?(Hash)
      errors << "documentation surface #{key} is missing"
      next
    end
    surfaces << surface.merge("_key" => key)
  end
  role_guides = docs["role_guides"]
  unless role_guides.is_a?(Array) && !role_guides.empty?
    errors << "documentation role_guides must be a non-empty array"
    role_guides = []
  end
  surfaces.concat(role_guides.each_with_index.map { |surface, index| surface.merge("_key" => "role_guides[#{index}]") if surface.is_a?(Hash) }.compact)

  ids = Set.new
  paths = Set.new
  surfaces.each do |surface|
    key = surface["_key"]
    id = surface["id"]
    path = surface["path"]
    errors << "#{key} has missing/duplicate id: #{id.inspect}" if !id.is_a?(String) || id.empty? || ids.include?(id)
    ids << id if id.is_a?(String)
    rel = relative_path(path)
    errors << "#{key} has missing/duplicate path: #{path.inspect}" if !path.is_a?(String) || path.empty? || paths.include?(rel)
    paths << rel if path.is_a?(String)
    resolved = safe_inside(root, path)
    errors << "#{key} path escapes repository: #{path.inspect}" unless resolved
    errors << "#{key} path is missing: #{path}" if resolved && !resolved.file?
    errors << "#{key} must be required" unless surface["required"] == true
  end

  start_path = safe_inside(root, docs.dig("start_here", "path"))
  index_path = safe_inside(root, docs.dig("index", "path"))
  if start_path&.file?
    start_text = start_path.read(encoding: "UTF-8")
    %w[scripts/INDEX.md automation/idol-script-registry.yaml scripts/registry/].each do |needle|
      errors << "start_here omits required discovery link #{needle}" unless start_text.include?(needle)
    end
  end
  if index_path&.file?
    index_text = index_path.read(encoding: "UTF-8")
    errors << "index is missing complete-roster marker" unless index_text.include?("idol-script-registry: complete-roster")
    indexed_paths = discovered + Array(registry["local_optional_entries"]).each_with_object([]) do |entry, paths|
      paths << entry["path"] if entry.is_a?(Hash) && entry["path"].is_a?(String)
    end
    indexed_paths.uniq.each do |path|
      index_ref = path.sub(%r{\Ascripts/}, "")
      errors << "index omits discovered script #{path}" unless index_text.include?(path) || index_text.include?(index_ref)
    end
    role_guides.each do |guide|
      next unless guide.is_a?(Hash)

      path = guide["path"].to_s
      index_ref = path.sub(%r{\Ascripts/}, "")
      errors << "index omits role guide #{path}" unless index_text.include?(path) || index_text.include?(index_ref)
    end
  end

  guide_by_id = role_guides.each_with_object({}) { |guide, result| result[guide["id"]] = guide if guide.is_a?(Hash) }
  (Array(registry["script_entries"]) + Array(registry["local_optional_entries"])).each do |entry|
    next unless entry.is_a?(Hash)

    guide = guide_by_id[entry["guide_id"]]
    if guide.nil?
      errors << "script #{entry["path"]} maps to missing guide #{entry["guide_id"]}"
      next
    end
    guide_path = safe_inside(root, guide["path"])
    errors << "guide #{guide["path"]} omits script #{entry["path"]}" if guide_path&.file? && !guide_path.read(encoding: "UTF-8").include?(entry["path"])
  end
  errors
end

def registry_result(root, registry_path)
  errors = []
  unless registry_path.file?
    errors << "missing registry: #{registry_path}"
    return { "status" => "fail", "registry" => registry_path.to_s, "errors" => errors }
  end

  begin
    registry = load_registry(registry_path)
  rescue StandardError => error
    errors << error.message
    return { "status" => "fail", "registry" => registry_path.to_s, "errors" => errors }
  end
  unless registry.is_a?(Hash)
    errors << "registry root must be an object"
    return { "status" => "fail", "registry" => registry_path.to_s, "errors" => errors }
  end
  errors << "registry schema_version must be idol-script-registry.v1" unless registry["schema_version"] == "idol-script-registry.v1"
  errors << "registry status must be active" unless registry["status"] == "active"

  discovered = discover_scripts(root, registry, errors)
  entries = registry["script_entries"]
  unless entries.is_a?(Array)
    errors << "script_entries must be an array"
    entries = []
  end
  entry_paths = entries.each_with_object([]) do |entry, paths|
    paths << entry["path"] if entry.is_a?(Hash) && entry["path"].is_a?(String)
  end
  duplicate_entries = entry_paths.group_by { |path| path }.select { |_path, values| values.length > 1 }.keys.sort
  errors << "script_entries contains duplicate paths: #{duplicate_entries.join(', ')}" unless duplicate_entries.empty?
  missing_entries = discovered - entry_paths
  stale_entries = entry_paths - discovered
  errors << "registry is missing discovered script entries: #{missing_entries.join(', ')}" unless missing_entries.empty?
  errors << "registry declares stale script entries: #{stale_entries.join(', ')}" unless stale_entries.empty?

  optional_entries = registry["local_optional_entries"]
  unless optional_entries.nil? || optional_entries.is_a?(Array)
    errors << "local_optional_entries must be an array when present"
    optional_entries = []
  end
  optional_present = []
  Array(optional_entries).each do |entry|
    unless entry.is_a?(Hash) && entry["path"].is_a?(String)
      errors << "local_optional_entries contains an invalid entry"
      next
    end
    candidate = safe_inside(root, entry["path"])
    errors << "optional script path escapes repository: #{entry["path"]}" unless candidate
    optional_present << entry["path"] if candidate&.file?
  end

  guide_ids = Array(registry.dig("documentation_surfaces", "role_guides")).each_with_object(Set.new) do |guide, ids|
    ids << guide["id"] if guide.is_a?(Hash) && guide["id"].is_a?(String)
  end
  authority_ids = registry.fetch("authority_profiles", {}).keys.to_set if registry["authority_profiles"].is_a?(Hash)
  entries.each do |entry|
    next unless entry.is_a?(Hash)

    errors << "script entry #{entry["path"]} maps to unknown guide #{entry["guide_id"]}" unless guide_ids.include?(entry["guide_id"])
    errors << "script entry #{entry["path"]} maps to unknown authority profile #{entry["authority_profile"]}" unless authority_ids&.include?(entry["authority_profile"])
  end
  errors.concat(documentation_errors(root, registry, discovered))

  {
    "status" => errors.empty? ? "pass" : "fail",
    "registry" => registry_path.to_s,
    "discovered_count" => discovered.length,
    "declared_count" => entry_paths.uniq.length,
    "optional_present" => optional_present.sort,
    "missing_entries" => missing_entries,
    "stale_entries" => stale_entries,
    "documentation_errors" => documentation_errors(root, registry, discovered),
    "errors" => errors.uniq.sort
  }
end

result = registry_result(options[:root], options[:registry])
if options[:json]
  puts JSON.pretty_generate(result)
elsif result["status"] == "pass"
  puts "OK: scripts registry matches declared files and documentation surfaces (#{result["discovered_count"]} scripts)"
else
  puts "Script registry mismatch"
  result["errors"].each { |error| puts "  #{error}" }
end
exit(result["status"] == "pass" ? 0 : 1)
