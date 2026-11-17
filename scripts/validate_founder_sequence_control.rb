#!/usr/bin/env ruby
# frozen_string_literal: true

require "date"
require "json"
require "open3"
require "optparse"
require "pathname"
require "yaml"

ROOT = Pathname.new(__dir__).join("..").expand_path
IDOL_SCHEMA = ROOT.join("schemas", "idol-founder-sequence-control.schema.json")
CF_SCHEMA = ROOT.join("schemas", "founder-sequence-control.schema.json")
SCHEMA_VALIDATOR = ROOT.join("scripts", "validate_json_schema.py")
PYTHON = ROOT.join("scripts", "idol-video-python")

options = {root: ROOT, json: false, max_errors: 40, mode: "active_authoring"}
OptionParser.new do |opts|
  opts.banner = "usage: ruby scripts/validate_founder_sequence_control.rb [options] PATH"
  opts.on("--root PATH") { |value| options[:root] = Pathname.new(value).expand_path }
  opts.on("--json") { options[:json] = true }
  opts.on("--max-errors COUNT", Integer) { |value| options[:max_errors] = value }
  opts.on("--mode MODE", %w[active_authoring historical_audit]) { |value| options[:mode] = value }
end.parse!

artifact_arg = ARGV.shift
abort "Founder Sequence Control path is required" if artifact_arg.to_s.empty? || !ARGV.empty?

def load_mapping(path)
  value = if path.extname.downcase == ".json"
            JSON.parse(path.read)
          else
            YAML.safe_load(path.read, permitted_classes: [Date, Time], permitted_symbols: [], aliases: true)
          end
  raise TypeError, "document must be an object" unless value.is_a?(Hash)
  value
end

def resolve_path(raw, root)
  path = Pathname.new(raw.to_s)
  path = root.join(path) unless path.absolute?
  path.expand_path.cleanpath
end

def inside?(path, root)
  relative = path.relative_path_from(root).to_s
  relative != ".." && !relative.start_with?("../")
rescue ArgumentError
  false
end

root = options[:root].expand_path.cleanpath
artifact = resolve_path(artifact_arg, root)
errors = []
document = {}

unless inside?(artifact, root) && artifact.file?
  errors << "Founder Sequence Control is missing or outside the repository"
end

if errors.empty?
  begin
    document = load_mapping(artifact)
  rescue JSON::ParserError, Psych::Exception, TypeError => e
    errors << "cannot parse Founder Sequence Control: #{e.message}"
  end
end

schema_path = nil
if errors.empty?
  case document["schema_version"].to_s
  when "idol_founder_sequence_control.v3"
    schema_path = IDOL_SCHEMA
  when "idol_founder_sequence_control.v1"
    if options[:mode] == "historical_audit"
      schema_path = CF_SCHEMA
    else
      errors << "Founder Sequence Control v1 is historical only; CF authoring is inactive. Use --mode historical_audit only to inspect retained evidence."
    end
  else
    errors << "unknown or inactive Founder Sequence Control version; current IDOL authoring requires idol_founder_sequence_control.v3"
  end
end

if schema_path
  stdout, stderr, status = Open3.capture3(
    PYTHON.to_s,
    SCHEMA_VALIDATOR.to_s,
    schema_path.to_s,
    artifact.to_s,
    chdir: ROOT.to_s
  )
  errors << "JSON Schema validation failed: #{[stderr, stdout].join(' ').strip}" unless status.success?
end

if errors.empty? && document.any?
  lane = document["lane"].to_s
  expected_version = lane == "idol_mv" ? "idol_founder_sequence_control.v3" : "idol_founder_sequence_control.v1"
  errors << "#{lane} Founder Sequence Control must use #{expected_version}" unless document["schema_version"].to_s == expected_version

  majors = Array(document.dig("story_flow", "ordered_major_scenes"))
  major_ids = majors.map { |row| row["control_major_id"].to_s }
  major_order = majors.map { |row| row["order_index"] }
  expected_order = (1..majors.length).to_a
  errors << "control major ids must be unique" unless major_ids.uniq.length == major_ids.length
  errors << "control major order_index must be unique and contiguous from 1" unless major_order == expected_order

  references = Array(document.dig("reference_plan", "references"))
  reference_ids = references.map { |row| row["reference_id"].to_s }
  errors << "reference ids must be unique" unless reference_ids.uniq.length == reference_ids.length
  governing_ids = Array(document.dig("reference_plan", "governing_reference_ids")).map(&:to_s)
  unknown_governing = governing_ids - reference_ids
  errors << "governing_reference_ids name unknown references: #{unknown_governing.join(', ')}" unless unknown_governing.empty?

  references.each do |reference|
    unknown_targets = Array(reference["target_control_major_ids"]).map(&:to_s) - major_ids
    unless unknown_targets.empty?
      errors << "#{reference['reference_id']} targets unknown control majors: #{unknown_targets.join(', ')}"
    end
    if lane == "idol_mv"
      targeted_sections = Array(reference["target_section_ids"]).map(&:to_s)
      expected_sections = majors.select do |major|
        Array(reference["target_control_major_ids"]).map(&:to_s).include?(major["control_major_id"].to_s)
      end.map { |major| major["section_id"].to_s }.uniq
      unless targeted_sections.sort == expected_sections.sort
        errors << "#{reference['reference_id']} target_section_ids must exact-cover its MJxx Major targets"
      end
    end
  end

  majors.each do |major|
    unknown_refs = Array(major["reference_ids"]).map(&:to_s) - reference_ids
    unless unknown_refs.empty?
      errors << "#{major['control_major_id']} names unknown references: #{unknown_refs.join(', ')}"
    end
  end

  translated_ids = Array(document.dig("director_translation", "observable_sequence")).map do |row|
    row["control_major_id"].to_s
  end
  unless translated_ids == major_ids
    errors << "director observable_sequence must map every control Major exactly once in proposed order"
  end

  if lane == "idol_mv" && document["status"].to_s == "director_ready"
    gate = document["startup_gate"].to_h
    errors << "IDOL director-ready control requires explicit start authorization" unless gate["decision"].to_s == "start_authorized"
    errors << "IDOL director-ready control cannot retain unresolved material choices" unless Array(gate["unresolved_material_choices"]).empty?
    errors << "IDOL director-ready control cannot retain held references" if references.any? { |row| row["disposition"].to_s == "held" }
    typed_slots = references.map { |row| row["reference_slot"].to_s }
    %w[A B C X Y Z].each do |slot|
      errors << "IDOL director-ready control requires exactly one typed #{slot} reference" unless typed_slots.count(slot) == 1
    end
  elsif lane == "cf_code" && document["status"].to_s == "passed"
    gate = document["founder_gate"].to_h
    reviewed_major_ids = Array(gate["reviewed_control_major_ids"]).map(&:to_s)
    reviewed_reference_ids = Array(gate["reviewed_reference_ids"]).map(&:to_s)
    errors << "Founder PASS must review every control major" unless reviewed_major_ids.sort == major_ids.sort
    errors << "Founder PASS must review every reference decision" unless reviewed_reference_ids.sort == reference_ids.sort
    errors << "passed control cannot retain held references" if references.any? { |row| row["disposition"].to_s == "held" }
  end
end

errors = errors.uniq
errors = errors.first(options[:max_errors]) if options[:max_errors].to_i.positive?
result = {"valid" => errors.empty?, "schema_version" => document["schema_version"], "validation_mode" => options[:mode], "evidence_only" => options[:mode] == "historical_audit", "errors" => errors}
if options[:json]
  puts JSON.pretty_generate(result)
elsif errors.empty?
  if options[:mode] == "historical_audit"
    puts "OK: historical Founder Sequence Control evidence validates; no current authoring or production authority"
  elsif document["lane"].to_s == "idol_mv"
    puts "OK: IDOL Founder Sequence Control v3 (status: #{document['status']}); structural validation only"
  end
else
  errors.each { |error| warn "ERROR: #{error}" }
end
exit(errors.empty? ? 0 : 1)
