#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "optparse"
require "pathname"
require "yaml"

REPO_ROOT = Pathname.new(__dir__).join("..").expand_path
SCHEMA = REPO_ROOT.join("schemas", "founder-intervention-receipt.schema.json")

options = {root: REPO_ROOT, json: false}
OptionParser.new do |parser|
  parser.banner = "usage: ruby scripts/validate_founder_intervention_receipt.rb RECEIPT [--root PATH] [--json]"
  parser.on("--root PATH") { |value| options[:root] = Pathname.new(value).expand_path }
  parser.on("--json") { options[:json] = true }
end.parse!

receipt_arg = ARGV.shift
abort "ERROR: RECEIPT is required" if receipt_arg.to_s.strip.empty?

root = options[:root].cleanpath
receipt = Pathname.new(receipt_arg)
receipt = root.join(receipt) unless receipt.absolute?
receipt = receipt.cleanpath
errors = []

unless receipt.file?
  errors << "receipt is missing: #{receipt_arg}"
else
  command = [
    REPO_ROOT.join("scripts", "idol-video-python").to_s,
    REPO_ROOT.join("scripts", "validate_json_schema.py").to_s,
    SCHEMA.to_s,
    receipt.to_s
  ]
  stdout, stderr, status = Open3.capture3(*command, chdir: root.to_s)
  errors << [stderr, stdout].reject { |value| value.to_s.strip.empty? }.join(" ").strip unless status.success?
end

document = receipt.file? ? YAML.safe_load(receipt.read, aliases: true) : {}
document = {} unless document.is_a?(Hash)

def resolve_inside_root(root, relative, errors, label)
  path = Pathname.new(relative.to_s)
  path = root.join(path) unless path.absolute?
  path = path.cleanpath
  begin
    path.relative_path_from(root)
  rescue ArgumentError
    errors << "#{label} escapes root: #{relative}"
    return nil
  end
  path
end

def validate_binding(root, binding, errors, label)
  return unless binding.is_a?(Hash)

  path = resolve_inside_root(root, binding["path"], errors, label)
  return unless path
  unless path.file?
    errors << "#{label} is missing: #{binding['path']}"
    return
  end
  actual = Digest::SHA256.file(path.to_s).hexdigest
  errors << "#{label} SHA-256 is stale: #{binding['path']}" unless actual == binding["sha256"].to_s
end

def canonicalize(value)
  case value
  when Hash
    value.keys.map(&:to_s).sort.each_with_object({}) do |key, result|
      original_key = value.key?(key) ? key : value.keys.find { |candidate| candidate.to_s == key }
      result[key] = canonicalize(value[original_key])
    end
  when Array
    value.map { |item| canonicalize(item) }
  else
    value
  end
end

def value_sha256(value)
  Digest::SHA256.hexdigest(JSON.generate(canonicalize(value)))
end

def load_structured(path, errors, label)
  case path.extname.downcase
  when ".json"
    JSON.parse(path.read)
  when ".yaml", ".yml"
    YAML.safe_load(path.read, aliases: true)
  else
    errors << "#{label} must point to YAML or JSON: #{path}"
    nil
  end
rescue JSON::ParserError, Psych::Exception => e
  errors << "#{label} cannot be parsed: #{e.message}"
  nil
end

def resolve_pointer(document, pointer, errors, label)
  value = document
  return value if pointer.to_s.empty?

  pointer.to_s.split("/")[1..].each do |raw_token|
    token = raw_token.gsub("~1", "/").gsub("~0", "~")
    if value.is_a?(Array) && token.match?(/\A(?:0|[1-9][0-9]*)\z/)
      index = token.to_i
      if index >= value.length
        errors << "#{label} array index is out of range: #{index}"
        return nil
      end
      value = value[index]
    elsif value.is_a?(Hash) && value.key?(token)
      value = value[token]
    else
      errors << "#{label} does not resolve at token #{token.inspect}"
      return nil
    end
  end
  value
end

def validate_field_binding(root, binding, errors, label)
  before = errors.length
  validate_binding(root, binding, errors, label)
  return if errors.length > before

  path = resolve_inside_root(root, binding["path"], errors, label)
  return unless path&.file?

  document = load_structured(path, errors, label)
  return if document.nil?

  value = resolve_pointer(document, binding["pointer"], errors, "#{label}.pointer")
  return if value.nil? && !binding["pointer"].to_s.empty?

  actual = value_sha256(value)
  errors << "#{label}.value_sha256 is stale" unless actual == binding["value_sha256"].to_s
end

run_rel = document["run"].to_s
run_path = resolve_inside_root(root, run_rel, errors, "run") unless run_rel.empty?
errors << "run is not a directory: #{run_rel}" if run_path && !run_path.directory?
if run_path && receipt.file?
  expected_root = run_path.join("review", "founder-interventions").cleanpath
  begin
    receipt.relative_path_from(expected_root)
  rescue ArgumentError
    errors << "receipt must live under #{expected_root.relative_path_from(root)}"
  end
end

Array(document.dig("routing", "affected_artifacts")).each_with_index do |binding, index|
  validate_binding(root, binding, errors, "routing.affected_artifacts[#{index}]")
end
Array(document.dig("routing", "downstream_invalidation_targets")).each_with_index do |binding, index|
  validate_binding(root, binding, errors, "routing.downstream_invalidation_targets[#{index}]")
end
Array(document.dig("integration_receipt", "revised_artifacts")).each_with_index do |binding, index|
  validate_binding(root, binding, errors, "integration_receipt.revised_artifacts[#{index}]")
end

direct = document["founder_direct_update"]
if document["intervention_mode"].to_s == "founder_direct_update" && direct.is_a?(Hash)
  validate_binding(root, direct["baseline_review"], errors, "founder_direct_update.baseline_review")
  validate_binding(root, direct["baseline_source"], errors, "founder_direct_update.baseline_source")
  field_bindings = Array(direct["authoritative_field_bindings"])
  field_bindings.each_with_index do |binding, index|
    validate_field_binding(root, binding, errors, "founder_direct_update.authoritative_field_bindings[#{index}]")
  end

  if document["status"].to_s == "integrated" && direct["decision"].to_s == "pass"
    revised = Array(document.dig("integration_receipt", "revised_artifacts"))
    revised_pairs = revised.each_with_object([]) do |binding, rows|
      next unless binding.is_a?(Hash)
      rows << [binding["path"].to_s, binding["sha256"].to_s]
    end
    field_bindings.each_with_index do |binding, index|
      pair = [binding["path"].to_s, binding["sha256"].to_s]
      unless revised_pairs.include?(pair)
        errors << "founder_direct_update.authoritative_field_bindings[#{index}] is not present in integration_receipt.revised_artifacts"
      end
    end

    required_checks = Array(direct["mandatory_check_ids"]).map(&:to_s)
    passed_checks = Array(document.dig("integration_receipt", "revalidation_results")).each_with_object([]) do |row, values|
      values << row["check_id"].to_s if row.is_a?(Hash) && row["status"].to_s == "pass"
    end
    missing_checks = required_checks - passed_checks
    unless missing_checks.empty?
      errors << "integrated Founder direct update is missing passed mandatory checks: #{missing_checks.join(', ')}"
    end
  end
end

result = {
  "status" => errors.empty? ? "pass" : "fail",
  "receipt" => begin receipt.relative_path_from(root).to_s rescue receipt.to_s end,
  "intervention_status" => document["status"].to_s,
  "errors" => errors.reject(&:empty?)
}

if options[:json]
  puts JSON.pretty_generate(result)
elsif errors.empty?
  puts "OK: Founder intervention receipt is schema-valid and hash-bound (#{document['status']})"
else
  errors.reject(&:empty?).each { |error| warn "ERROR: #{error}" }
end

exit(errors.empty? ? 0 : 1)
