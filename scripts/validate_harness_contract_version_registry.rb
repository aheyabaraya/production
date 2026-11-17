#!/usr/bin/env ruby
# frozen_string_literal: true

require "date"
require "digest"
require "json"
require "optparse"
require "pathname"
require "yaml"

ROOT = Pathname.new(__dir__).join("..").expand_path
REGISTRY = ROOT.join("automation", "harness-contract-version-registry.yaml")
STAGE_REGISTRY = ROOT.join("automation", "harness-stage-registry.yaml")
INACTIVE_SHARED_SCRIPTS = %w[
  scripts/idol_build_two_cut_source_manifest.py
  scripts/idol_compile_brief_cards.rb
  scripts/idol_cue_bpm_map.rb
  scripts/idol_grok_imagine_drive_sync.py
  scripts/idol_harness_sections.rb
  scripts/idol_video_prompt_drive_sync.rb
  scripts/validate_cue_bpm_map.rb
  scripts/validate_video_prompt_index.rb
  scripts/validate_wardrobe_style_review.rb
].freeze

options = {json: false}
OptionParser.new { |parser| parser.on("--json") { options[:json] = true } }.parse!

def canonical_value(value)
  case value
  when Hash
    value.keys.sort.each_with_object({}) { |key, result| result[key] = canonical_value(value[key]) }
  when Array
    value.map { |item| canonical_value(item) }
  else
    value
  end
end

def version_literals(property)
  return [] unless property.is_a?(Hash)

  values = []
  values << property["const"] if property.key?("const")
  values.concat(Array(property["enum"])) if property.key?("enum")
  values.compact.map(&:to_s).uniq
end

def resolve_local_ref(document, reference)
  return nil unless reference.to_s.start_with?("#/")

  reference.delete_prefix("#/").split("/").reduce(document) do |cursor, token|
    break nil unless cursor.is_a?(Hash)

    cursor[token.gsub("~1", "/").gsub("~0", "~")]
  end
end

def root_schema_versions(document)
  candidates = [document]
  %w[oneOf anyOf allOf].each do |keyword|
    Array(document[keyword]).each do |branch|
      next unless branch.is_a?(Hash)

      candidates << branch
      resolved = resolve_local_ref(document, branch["$ref"])
      candidates << resolved if resolved.is_a?(Hash)
    end
  end

  candidates.flat_map do |candidate|
    version_literals(candidate.dig("properties", "schema_version"))
  end.uniq
end

document = YAML.safe_load(REGISTRY.read, permitted_classes: [Date, Time], aliases: true)
errors = []
rows = Array(document["contracts"])
non_authoring_rows = Array(document["non_authoring_schemas"])
ids = rows.each_with_object([]) { |row, result| result << row["contract_id"].to_s if row.is_a?(Hash) }
duplicates = ids.group_by(&:itself).select { |_id, values| values.length > 1 }.keys
errors.concat(duplicates.map { |id| "duplicate contract_id: #{id}" })
schema_routes = rows.each_with_object([]) { |row, result| result << row["schema"].to_s if row.is_a?(Hash) }
duplicate_schema_routes = schema_routes.group_by(&:itself).select { |path, values| path.empty? || values.length > 1 }.keys
errors.concat(duplicate_schema_routes.map { |path| "duplicate or blank active schema route: #{path.inspect}" })
lifecycle_routes = non_authoring_rows.each_with_object([]) do |row, result|
  result << row["schema"].to_s if row.is_a?(Hash)
end
duplicate_lifecycle_routes = lifecycle_routes.group_by(&:itself).select { |path, values| path.empty? || values.length > 1 }.keys
errors.concat(duplicate_lifecycle_routes.map { |path| "duplicate or blank non-authoring schema route: #{path.inspect}" })
errors.concat((schema_routes & lifecycle_routes).map { |path| "schema cannot be active-authoring and non-authoring: #{path}" })

declared_schema_ids = {}
schema_documents = {}

rows.each do |row|
  next unless row.is_a?(Hash)

  id = row["contract_id"].to_s
  schema = ROOT.join(row["schema"].to_s).expand_path
  unless schema.file?
    errors << "#{id}: schema is missing: #{row['schema']}"
    next
  end

  schema_text = schema.read
  begin
    schema_document = JSON.parse(schema_text)
    schema_documents[row["schema"].to_s] = schema_document
    schema_id = schema_document["$id"].to_s
    if schema_id.empty?
      errors << "#{id}: active schema has no $id"
    elsif declared_schema_ids.key?(schema_id)
      errors << "#{id}: duplicate schema $id #{schema_id.inspect} also owned by #{declared_schema_ids[schema_id]}"
    else
      declared_schema_ids[schema_id] = id
    end
    declared_versions = root_schema_versions(schema_document)
    current_version = row["current_authoring_version"].to_s
    if declared_versions.any? && declared_versions != [current_version]
      errors << "#{id}: root schema_version must declare only #{current_version.inspect}, found #{declared_versions.inspect}"
    end
  rescue JSON::ParserError => e
    errors << "#{id}: schema is not valid JSON: #{e.message}"
  end
  ([row["current_authoring_version"]] + Array(row["readable_versions"])).compact.map(&:to_s).uniq.each do |version|
    errors << "#{id}: declared version #{version.inspect} is not present in #{row['schema']}" unless schema_text.include?(version)
  end
  unless Array(row["readable_versions"]) == [row["current_authoring_version"]]
    errors << "#{id}: readable_versions must contain only the current authoring version"
  end

  producer = row["producer"].to_s
  if producer.include?("/") && (producer.end_with?(".yaml") || producer.end_with?(".json") || producer.end_with?(".md") || producer.end_with?(".rb") || producer.end_with?(".py"))
    errors << "#{id}: producer path is missing: #{producer}" unless ROOT.join(producer).file?
  end
end


non_authoring_rows.each do |row|
  next unless row.is_a?(Hash)

  route = row["schema"].to_s
  schema = ROOT.join(route).expand_path
  unless schema.file?
    errors << "non-authoring schema is missing: #{route}"
    next
  end

  digest = Digest::SHA256.file(schema).hexdigest
  errors << "#{route}: lifecycle sha256 is stale" unless digest == row["sha256"].to_s
  errors << "#{route}: new_authoring must be false" unless row["new_authoring"] == false

  unknown_replacements = Array(row["replacement_contracts"]).map(&:to_s) - ids
  unknown_replacements.each do |contract_id|
    errors << "#{route}: replacement contract is not active: #{contract_id}"
  end
  Array(row["allowed_consumers"]).each do |consumer|
    next unless consumer.to_s.include?("/")

    errors << "#{route}: allowed consumer path is missing: #{consumer}" unless ROOT.join(consumer.to_s).file?
  end

  begin
    schema_document = JSON.parse(schema.read)
    schema_documents[route] = schema_document
    schema_id = schema_document["$id"].to_s
    if schema_id.empty?
      errors << "#{route}: non-authoring schema has no $id"
    elsif declared_schema_ids.key?(schema_id)
      errors << "#{route}: duplicate schema $id #{schema_id.inspect} also owned by #{declared_schema_ids[schema_id]}"
    else
      declared_schema_ids[schema_id] = route
    end
  rescue JSON::ParserError => e
    errors << "#{route}: schema is not valid JSON: #{e.message}"
  end
end

content_hash_groups = schema_documents.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |(path, schema_document), groups|
  digest = Digest::SHA256.hexdigest(JSON.generate(canonical_value(schema_document)))
  groups[digest] << path
end
exact_duplicate_schema_groups = content_hash_groups.values.select { |paths| paths.length > 1 }
exact_duplicate_schema_groups.each do |paths|
  errors << "active schemas have byte-independent identical JSON content: #{paths.join(', ')}"
end

overlap_diagnostics = schema_documents.to_a.combination(2).each_with_object([]) do |((left_path, left), (right_path, right)), diagnostics|
  left_properties = left.fetch("properties", {}).keys
  right_properties = right.fetch("properties", {}).keys
  next if [left_properties.length, right_properties.length].min < 4

  common = left_properties & right_properties
  union = left_properties | right_properties
  similarity = union.empty? ? 0.0 : common.length.to_f / union.length
  next if similarity < 0.7

  diagnostics << {
    "left" => left_path,
    "right" => right_path,
    "top_level_property_jaccard" => similarity.round(3),
    "shared_top_level_properties" => common.sort
  }
end

stage_registry = YAML.safe_load(STAGE_REGISTRY.read, permitted_classes: [Date, Time], aliases: true)
active_stage_contracts = Array(stage_registry["stages"])
                         .select { |row| row.is_a?(Hash) && row["active"] == true }
                         .flat_map { |row| Array(row["output_contracts"]).map(&:to_s) }
                         .uniq
missing_stage_contracts = active_stage_contracts - schema_routes
errors.concat(missing_stage_contracts.map { |path| "active stage output contract is not registered: #{path}" })

all_schema_paths = Dir.glob(ROOT.join("schemas", "*.schema.json").to_s)
                      .select { |path| File.file?(path) }
                      .map { |path| Pathname.new(path).relative_path_from(ROOT).to_s }
                      .sort
active_root_schema_routes = schema_routes.select { |path| path.start_with?("schemas/") }
unclassified_schema_routes = all_schema_paths - active_root_schema_routes - lifecycle_routes
errors.concat(unclassified_schema_routes.map { |path| "root schema has no active or non-authoring lifecycle route: #{path}" })
errors.concat((lifecycle_routes - all_schema_paths).map { |path| "non-authoring lifecycle route is not a root schema: #{path}" })

script_schema_refs_by_route = Hash.new { |hash, key| hash[key] = [] }
Dir.glob(ROOT.join("scripts", "**", "*").to_s)
  .reject { |path| path.include?("/scripts/tests/") }
  .reject { |path| path.include?("/__pycache__/") || path.end_with?(".pyc") }
  .select { |path| File.file?(path) }
  .reject do |path|
  relative = Pathname.new(path).relative_path_from(ROOT).to_s
  INACTIVE_SHARED_SCRIPTS.include?(relative)
end
  .each do |path|
    relative = Pathname.new(path).relative_path_from(ROOT).to_s
    references = File.binread(path).scan(%r{schemas/[A-Za-z0-9._-]+\.schema\.json}).uniq
    references.each { |route| script_schema_refs_by_route[route] << relative }
  rescue ArgumentError
    next
  end

script_schema_refs = script_schema_refs_by_route.keys.sort
unknown_script_refs = script_schema_refs - schema_routes - lifecycle_routes
errors.concat(unknown_script_refs.map { |path| "active script references an unclassified schema: #{path}" })

lifecycle_by_route = non_authoring_rows.each_with_object({}) do |row, result|
  result[row["schema"].to_s] = row if row.is_a?(Hash)
end
(script_schema_refs & lifecycle_routes).each do |route|
  allowed = Array(lifecycle_by_route.fetch(route)["allowed_consumers"]).map(&:to_s)
  (script_schema_refs_by_route[route].uniq - allowed).each do |consumer|
    errors << "#{route}: active script consumer is not lifecycle-allowlisted: #{consumer}"
  end
end

lifecycle_state_counts = non_authoring_rows.each_with_object(Hash.new(0)) do |row, counts|
  counts[row["lifecycle_state"].to_s] += 1 if row.is_a?(Hash)
end.sort.to_h

result = {
  "status" => errors.empty? ? "pass" : "fail",
  "contract_count" => rows.length,
  "schema_file_count" => all_schema_paths.length,
  "active_schema_route_count" => schema_routes.length,
  "active_root_schema_route_count" => active_root_schema_routes.length,
  "active_external_schema_route_count" => schema_routes.length - active_root_schema_routes.length,
  "non_authoring_schema_count" => lifecycle_routes.length,
  "unclassified_schema_count" => unclassified_schema_routes.length,
  "lifecycle_state_counts" => lifecycle_state_counts,
  "active_stage_output_contract_count" => active_stage_contracts.length,
  "active_script_referenced_schema_count" => script_schema_refs.length,
  "non_authoring_script_schema_count" => (script_schema_refs & lifecycle_routes).length,
  "exact_duplicate_schema_groups" => exact_duplicate_schema_groups,
  "high_overlap_diagnostics" => overlap_diagnostics,
  "errors" => errors
}

if options[:json]
  puts JSON.pretty_generate(result)
elsif errors.empty?
  puts "OK: #{rows.length} contract version route(s) match their schemas"
else
  errors.each { |error| warn "ERROR: #{error}" }
end

exit(errors.empty? ? 0 : 1)
