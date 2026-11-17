#!/usr/bin/env ruby
# frozen_string_literal: true

require "date"
require "digest"
require "json"
require "open3"
require "optparse"
require "pathname"
require "rbconfig"
require "yaml"
require_relative "lib/idol_direction_projection_contract"

ROOT = Pathname.new(__dir__).join("..").expand_path
SCHEMA = ROOT.join("schemas", "schema-repair-candidate.schema.json")
PYTHON = ROOT.join("scripts", "idol-video-python")
SCHEMA_VALIDATOR = ROOT.join("scripts", "validate_json_schema.py")
DEPARTMENT_DISPATCH_VALIDATOR = ROOT.join("scripts", "validate_department_dispatch.rb")
CONTRACT_REGISTRY = ROOT.join("automation", "harness-contract-version-registry.yaml")

options = {json: false}
OptionParser.new do |parser|
  parser.banner = "usage: ruby scripts/validate_schema_repair_candidate.rb [--json] RECEIPT"
  parser.on("--json") { options[:json] = true }
end.parse!

argument = ARGV.shift
if argument.to_s.empty? || !ARGV.empty?
  warn "schema repair candidate receipt path is required"
  exit 2
end

def repo_path(raw)
  path = Pathname.new(raw.to_s)
  path = ROOT.join(path) unless path.absolute?
  path = path.expand_path
  relative = path.relative_path_from(ROOT).to_s
  raise ArgumentError, "path escapes repository: #{raw}" if relative == ".." || relative.start_with?("../")

  [path, relative]
rescue ArgumentError
  raise ArgumentError, "path escapes repository: #{raw}"
end

def load_document(path)
  text = path.read
  value = path.extname.downcase == ".json" ? JSON.parse(text) : YAML.safe_load(text, permitted_classes: [Date, Time], aliases: true)
  value
rescue JSON::ParserError, Psych::SyntaxError
  nil
end

def pointer_value(document, pointer)
  return document if pointer == ""
  return nil unless pointer.start_with?("/")

  pointer.split("/").drop(1).reduce(document) do |current, raw_token|
    token = raw_token.gsub("~1", "/").gsub("~0", "~")
    case current
    when Hash
      return nil unless current.key?(token)
      current[token]
    when Array
      return nil unless token.match?(/\A(?:0|[1-9][0-9]*)\z/) && token.to_i < current.length
      current[token.to_i]
    else
      return nil
    end
  end
end

def check_hash(errors, label, raw_path, expected_sha)
  path, relative = repo_path(raw_path)
  unless path.file?
    errors << "#{label} is missing: #{relative}"
    return [nil, relative]
  end

  actual = Digest::SHA256.file(path.to_s).hexdigest
  errors << "#{label} hash mismatch: #{relative}" unless actual == expected_sha.to_s
  [path, relative]
rescue ArgumentError => e
  errors << e.message
  [nil, raw_path.to_s]
end

receipt_path, receipt_relative = repo_path(argument)
errors = []

if !receipt_path.file?
  errors << "receipt is missing: #{receipt_relative}"
else
  stdout, stderr, status = Open3.capture3(
    PYTHON.to_s,
    SCHEMA_VALIDATOR.to_s,
    SCHEMA.to_s,
    receipt_path.to_s,
    chdir: ROOT.to_s
  )
  errors << "schema validation failed: #{[stderr, stdout].reject { |value| value.to_s.strip.empty? }.join(' ').strip}" unless status.success?
end

document = receipt_path.file? ? load_document(receipt_path) : nil
document = {} unless document.is_a?(Hash)
run = document["run"].to_s
candidate_root = "#{run}/work/schema-repair-candidates/"
unless receipt_relative.start_with?(candidate_root) && %w[receipt.yaml receipt.yml receipt.json].include?(receipt_path.basename.to_s)
  errors << "receipt must be named receipt.yaml, receipt.yml, or receipt.json under #{candidate_root}ID/"
end

source_path, source_relative = check_hash(
  errors,
  "source artifact",
  document.dig("source_artifact", "path"),
  document.dig("source_artifact", "sha256")
)
errors << "source artifact must stay inside declared run" unless source_relative.start_with?("#{run}/")

target_raw = document.dig("target_artifact", "path").to_s
begin
  target_path, target_relative = repo_path(target_raw)
  errors << "target artifact must stay inside declared run" unless target_relative.start_with?("#{run}/")
  errors << "target artifact cannot be a work-layer candidate" if target_relative.start_with?("#{run}/work/")
  case document.dig("target_artifact", "precondition")
  when "exists"
    if !target_path.file?
      errors << "target artifact disappeared after candidate creation: #{target_relative}"
    elsif Digest::SHA256.file(target_path.to_s).hexdigest != document.dig("target_artifact", "sha256_before").to_s
      errors << "canonical target changed after candidate creation: #{target_relative}"
    end
  when "missing"
    errors << "target artifact was created outside the owning human/model route: #{target_relative}" if target_path.exist?
  end
rescue ArgumentError => e
  errors << e.message
end

schema_path, _schema_relative = check_hash(
  errors,
  "target schema",
  document.dig("target_contract", "schema_path"),
  document.dig("target_contract", "schema_sha256")
)
errors << "target contract schema must be a JSON Schema file" if schema_path && schema_path.extname.downcase != ".json"
contract_registry = YAML.safe_load(CONTRACT_REGISTRY.read, permitted_classes: [], aliases: true)
target_schema_relative = document.dig("target_contract", "schema_path").to_s
target_contract_row = Array(contract_registry["contracts"]).find do |row|
  row.is_a?(Hash) && row["schema"].to_s == target_schema_relative
end
if !target_contract_row
  errors << "target schema is not routed by the contract-version registry: #{target_schema_relative}"
elsif target_contract_row["current_authoring_version"].to_s != document.dig("target_contract", "current_authoring_version").to_s
  errors << "target current_authoring_version does not match the contract-version registry"
end

candidate_path, candidate_relative = check_hash(
  errors,
  "candidate artifact",
  document.dig("candidate_artifact", "path"),
  document.dig("candidate_artifact", "sha256")
)
unless candidate_relative.start_with?(candidate_root) && candidate_path && candidate_path.dirname == receipt_path.dirname
  errors << "candidate artifact must stay beside its receipt under #{candidate_root}ID/"
end
errors << "candidate artifact cannot equal the canonical target" if candidate_relative == target_raw

Array(document["exact_copy_evidence"]).each_with_index do |row, index|
  next unless row.is_a?(Hash)

  label = "exact_copy_evidence[#{index}]"
  copied_source, copied_relative = check_hash(errors, "#{label} source", row["source_path"], row["source_artifact_sha256"])
  errors << "#{label} source must stay inside declared run" unless copied_relative.start_with?("#{run}/")
  dispatch, dispatch_rel = check_hash(errors, "#{label} department dispatch", row["department_dispatch_path"], row["department_dispatch_sha256"])

  if copied_source
    source_document = load_document(copied_source)
    value = pointer_value(source_document, row["source_json_pointer"].to_s)
    if value.nil?
      errors << "#{label} source_json_pointer does not resolve"
    else
      actual_value_sha = IdolDirectionProjectionContract.structured_value_sha256(value)
      errors << "#{label} source_value_sha256 is stale" unless actual_value_sha == row["source_value_sha256"].to_s
    end
  end

  next unless dispatch

  stdout, stderr, status = Open3.capture3(
    RbConfig.ruby,
    DEPARTMENT_DISPATCH_VALIDATOR.to_s,
    "--require-promoted",
    dispatch_rel,
    chdir: ROOT.to_s
  )
  errors << "#{label} department dispatch is not promoted and valid: #{[stderr, stdout].reject { |value| value.to_s.strip.empty? }.join(' ').strip}" unless status.success?
  dispatch_document = load_document(dispatch)
  dispatch_document = {} unless dispatch_document.is_a?(Hash)
  errors << "#{label} department dispatch belongs to a different run" unless dispatch_document["run"].to_s == run
  output_row = Array(dispatch_document.dig("runtime_return", "outputs")).find do |candidate|
    candidate.is_a?(Hash) && candidate["path"].to_s == copied_relative && candidate["sha256"].to_s == row["source_artifact_sha256"].to_s
  end
  errors << "#{label} department dispatch runtime return does not bind the copied source bytes" unless output_row
  review_row = Array(dispatch_document.dig("director_review", "reviewed_outputs")).find do |candidate|
    candidate.is_a?(Hash) && candidate["path"].to_s == copied_relative && candidate["sha256"].to_s == row["source_artifact_sha256"].to_s
  end
  errors << "#{label} director review does not bind the copied source bytes" unless review_row
  promotion_row = Array(dispatch_document.dig("promotion", "canonical_artifacts")).find do |candidate|
    candidate.is_a?(Hash) && candidate["path"].to_s == copied_relative && candidate["sha256"].to_s == row["source_artifact_sha256"].to_s
  end
  errors << "#{label} promoted canonical artifacts do not bind the copied source bytes" unless promotion_row
end

result = {
  "status" => errors.empty? ? "pass" : "fail",
  "receipt" => receipt_relative,
  "candidate" => candidate_relative,
  "target" => target_raw,
  "gate_effect" => "none_hold_only",
  "errors" => errors
}

if options[:json]
  puts JSON.pretty_generate(result)
elsif errors.empty?
  puts "OK: #{receipt_relative} is a noncanonical diagnostic hold"
else
  errors.each { |error| warn "ERROR: #{error}" }
end

exit(errors.empty? ? 0 : 1)
