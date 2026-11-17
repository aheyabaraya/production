#!/usr/bin/env ruby
# frozen_string_literal: true

require "date"
require "digest"
require "json"
require "open3"
require "optparse"
require "pathname"
require "yaml"

ROOT = Pathname.new(__dir__).join("..").expand_path
SCHEMA = ROOT.join("schemas", "skill-application-receipt.schema.json")
REGISTRY = ROOT.join("automation", "harness-stage-registry.yaml")
CONTRACT_REGISTRY = ROOT.join("automation", "harness-contract-version-registry.yaml")
PYTHON = ROOT.join("scripts", "idol-video-python")
SCHEMA_VALIDATOR = ROOT.join("scripts", "validate_json_schema.py")

options = {json: false, require_current: false}
OptionParser.new do |parser|
  parser.banner = "usage: ruby scripts/validate_skill_application_receipt.rb [--json] [--require-current] RECEIPT"
  parser.on("--json") { options[:json] = true }
  parser.on("--require-current") { options[:require_current] = true }
end.parse!

argument = ARGV.shift
if argument.to_s.empty? || !ARGV.empty?
  warn "receipt path is required"
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

receipt_path, receipt_relative = repo_path(argument)
errors = []

unless receipt_path.file?
  errors << "receipt is missing: #{receipt_relative}"
else
  _stdout, stderr, status = Open3.capture3(
    PYTHON.to_s,
    SCHEMA_VALIDATOR.to_s,
    SCHEMA.to_s,
    receipt_path.to_s,
    chdir: ROOT.to_s
  )
  errors << "schema validation failed: #{stderr.strip}" unless status.success?
end

document = if receipt_path.file?
             YAML.safe_load(receipt_path.read, permitted_classes: [Date, Time], aliases: true)
           else
             {}
           end
document = {} unless document.is_a?(Hash)

contract_registry = YAML.safe_load(CONTRACT_REGISTRY.read, permitted_classes: [], aliases: true)
receipt_contract = Array(contract_registry["contracts"]).find do |row|
  row.is_a?(Hash) && row["contract_id"].to_s == "skill_application_receipt"
end
current_version = receipt_contract.is_a?(Hash) ? receipt_contract["current_authoring_version"].to_s : ""
if options[:require_current] && document["schema_version"].to_s != current_version
  errors << "receipt must use current authoring version #{current_version.inspect}"
end

run = document["run"].to_s
unless receipt_relative.start_with?("#{run}/work/skill-application-receipts/")
  errors << "receipt must stay under its declared run work/skill-application-receipts path"
end

registry = YAML.safe_load(REGISTRY.read, permitted_classes: [], aliases: true)
stage_rows = Array(registry["stages"]).each_with_object([]) do |row, rows|
  rows << row if row.is_a?(Hash)
end
stage_row = stage_rows.find { |row| row["stage_id"].to_s == document["stage_id"].to_s }
errors << "unknown stage_id: #{document['stage_id']}" unless stage_row

read_rows = [document["owning_skill"], *Array(document["activated_reads"])]
read_rows.each_with_index do |row, index|
  unless row.is_a?(Hash)
    errors << "read evidence #{index} is not an object"
    next
  end

  begin
    path, relative = repo_path(row["path"])
    if !path.file?
      errors << "read evidence is missing: #{relative}"
      next
    end
    actual = Digest::SHA256.file(path.to_s).hexdigest
    errors << "read evidence hash mismatch: #{relative}" unless actual == row["sha256"].to_s
  rescue ArgumentError => e
    errors << e.message
  end
end

owning_path = document.dig("owning_skill", "path").to_s
unless owning_path.end_with?("/SKILL.md") && (owning_path.start_with?("skills/") || owning_path.start_with?(".grok/skills/"))
  errors << "owning_skill.path must name an IDOL SKILL.md"
end

if stage_row
  canonical_owner = stage_row["owner_skill"].to_s
  expected_skill_paths = [
    "skills/#{canonical_owner}/SKILL.md",
    ".grok/skills/#{canonical_owner}/SKILL.md"
  ].select { |path| ROOT.join(path).file? }
  if expected_skill_paths.any? && !expected_skill_paths.include?(owning_path)
    errors << "owning_skill.path does not match stage #{document['stage_id']} canonical owner #{canonical_owner}"
  end
end

scope = document["scope"].is_a?(Hash) ? document["scope"] : {}
scope_name = scope["mode"] == "section" ? scope["section_id"].to_s : "whole"
expected_receipt = "#{run}/work/skill-application-receipts/#{document['stage_id']}/#{scope_name}.yaml"
errors << "receipt path must be #{expected_receipt}" unless receipt_relative == expected_receipt

read_paths = read_rows.each_with_object([]) do |row, paths|
  paths << row["path"].to_s if row.is_a?(Hash)
end.uniq
output_targets = Array(document["output_targets"]).map(&:to_s)
output_rows = Array(document["output_evidence"])
output_paths = output_rows.each_with_object([]) do |row, paths|
  paths << row["path"].to_s if row.is_a?(Hash)
end
duplicates = output_paths.group_by(&:itself).select { |path, rows| path.empty? || rows.length > 1 }.keys
duplicates.each { |path| errors << "duplicate or blank output_evidence path: #{path.inspect}" }

output_rows.each_with_index do |row, index|
  unless row.is_a?(Hash)
    errors << "output_evidence[#{index}] is not an object"
    next
  end

  begin
    path, relative = repo_path(row["path"])
    if !path.file?
      errors << "output evidence is missing: #{relative}"
      next
    end
    actual = Digest::SHA256.file(path.to_s).hexdigest
    errors << "output evidence hash mismatch: #{relative}" unless actual == row["sha256"].to_s
    errors << "output evidence must stay inside declared run: #{relative}" unless relative.start_with?("#{run}/")
  rescue ArgumentError => e
    errors << e.message
  end
end

if ["idol-skill-application-receipt.v2", "idol-skill-application-receipt.v3"].include?(document["schema_version"])
  continuity_id = document.dig("session_contract", "continuity_id").to_s
  authorship_continuity_id = document.dig("creative_authorship", "authorship_continuity_id").to_s
  unless continuity_id == authorship_continuity_id
    errors << "creative_authorship.authorship_continuity_id must match session_contract.continuity_id"
  end
end

Array(document["application_evidence"]).each_with_index do |row, index|
  next unless row.is_a?(Hash)

  source_path = row["source_path"].to_s
  applied_to = row["applied_to"].to_s
  errors << "application_evidence[#{index}].source_path was not recorded as a completed read" unless read_paths.include?(source_path)
  unless output_targets.any? { |target| applied_to == target || applied_to.start_with?("#{target}#") }
    errors << "application_evidence[#{index}].applied_to must resolve to one declared output target or its fragment"
  end
end

if document["status"] == "complete"
  if ["idol-skill-application-receipt.v2", "idol-skill-application-receipt.v3"].include?(document["schema_version"]) && output_paths.sort != output_targets.sort
    errors << "complete v2+ receipt output_evidence paths must exactly match output_targets"
  end
  output_targets.each do |raw|
    begin
      path, relative = repo_path(raw)
      errors << "complete receipt output target is missing: #{relative}" unless path.file?
      errors << "complete receipt output target must stay inside declared run: #{relative}" unless relative.start_with?("#{run}/")
    rescue ArgumentError => e
      errors << e.message
    end
  end
end

result = {
  "status" => errors.empty? ? "pass" : "fail",
  "receipt" => receipt_relative,
  "stage_id" => document["stage_id"],
  "scope" => document["scope"],
  "errors" => errors
}

if options[:json]
  puts JSON.pretty_generate(result)
elsif errors.empty?
  puts "OK: #{receipt_relative}"
else
  errors.each { |error| warn "ERROR: #{error}" }
end

exit(errors.empty? ? 0 : 1)
