#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "optparse"
require "pathname"
require "tempfile"
require "yaml"
require_relative "lib/idol_run_layout"

CODE_ROOT = Pathname.new(__dir__).join("..").expand_path
PYTHON_RUNNER = CODE_ROOT.join("scripts/idol-video-python")
SCHEMA_VALIDATOR = CODE_ROOT.join("scripts/validate_json_schema.py")
FRONT_SCHEMA = CODE_ROOT.join("schemas/front-planning-readiness.schema.json")
WORKLIST_SCHEMA = CODE_ROOT.join("schemas/01r-reference-gap-worklist.schema.json")
REFERENCE_INDEX_SCHEMA = CODE_ROOT.join("schemas/reference-working-index.schema.json")

options = {
  repo_root: CODE_ROOT,
  write: false
}

OptionParser.new do |parser|
  parser.banner = "Usage: ruby scripts/idol_01r_reference_gap_worklist.rb --front-planning FILE [options]"
  parser.on("--front-planning FILE", "validated active Front Planning v17") { |value| options[:front_planning] = value }
  parser.on("--output FILE", "derived section comparison worklist path") { |value| options[:output] = value }
  parser.on("--write", "write the validated derived worklist") { options[:write] = true }
  parser.on("--repo-root DIR", "repository root override") { |value| options[:repo_root] = Pathname.new(value).expand_path }
end.parse!

abort "--front-planning is required" unless options[:front_planning]

repo_root = Pathname.new(options[:repo_root]).expand_path

def repo_path(root, raw, must_exist: false)
  candidate = Pathname.new(raw)
  candidate = root.join(candidate) unless candidate.absolute?
  candidate = candidate.expand_path
  relative = candidate.relative_path_from(root).to_s
  abort "path escapes repository root: #{raw}" if relative == ".." || relative.start_with?("../")
  abort "required file is missing: #{relative}" if must_exist && !candidate.file?
  [candidate, relative]
rescue ArgumentError
  abort "path escapes repository root: #{raw}"
end

def load_yaml_hash(path, label)
  value = YAML.safe_load(path.read, permitted_classes: [], aliases: true)
  abort "#{label} root must be a mapping" unless value.is_a?(Hash)
  value
rescue Psych::Exception => e
  abort "cannot parse #{label}: #{e.message}"
end

def validate_schema(schema, path, label)
  stdout, stderr, status = Open3.capture3(
    PYTHON_RUNNER.to_s,
    SCHEMA_VALIDATOR.to_s,
    schema.to_s,
    path.to_s,
    chdir: CODE_ROOT.to_s
  )
  return if status.success?

  details = [stderr, stdout].reject { |row| row.to_s.strip.empty? }.join("\n")
  abort "#{label} failed schema validation:\n#{details}"
end

def sha256(path)
  Digest::SHA256.file(path.to_s).hexdigest
end

def owning_run_relative(front_relative, repo_root)
  parts = Pathname.new(front_relative).each_filename.to_a
  abort "Front Planning path must be run-owned" unless parts.first == "runs"

  candidates = []
  candidates << parts.first(4).join("/") if parts.length >= 5
  candidates << parts.first(3).join("/") if parts.length >= 4
  candidates.each do |candidate|
    begin
      address = IdolRunLayout.resolve(candidate, repo_root: repo_root)
      return address.fetch("canonical_run_root")
    rescue ArgumentError
      next
    end
  end
  abort "Front Planning path does not resolve to an active album run or the exact registered transition"
end

front_path, front_rel = repo_path(repo_root, options[:front_planning], must_exist: true)
validate_schema(FRONT_SCHEMA, front_path, "Front Planning")
front = load_yaml_hash(front_path, "Front Planning")
unless front["schema_version"] == "front-planning-readiness.v17"
  abort "Front Planning must use the active front-planning-readiness.v17 contract"
end

reference_index_ref = front.dig("reference_connection_research", "reference_working_index").to_h
reference_index_path, = repo_path(repo_root, reference_index_ref["path"], must_exist: true)
abort "Front Planning Reference Working Index SHA-256 is stale" unless sha256(reference_index_path) == reference_index_ref["sha256"].to_s
validate_schema(REFERENCE_INDEX_SCHEMA, reference_index_path, "Reference Working Index")
reference_index = load_yaml_hash(reference_index_path, "Reference Working Index")
pinterest_index_row_ids = Array(reference_index["rows"]).select do |row|
  row.to_h.dig("source_eligibility", "classification").to_s == "public_pinterest_pin"
end.map { |row| row["row_id"].to_s }

run_rel = owning_run_relative(front_rel, repo_root)
run_path, normalized_run_rel = repo_path(repo_root, run_rel)
layout_errors = IdolRunLayout.validate(run_path, repo_root: repo_root)
abort layout_errors.join("; ") unless layout_errors.empty?
run_identity = IdolRunLayout.identity(run_path, repo_root: repo_root)
unless front["content_id"].to_s == run_identity["content_id"].to_s
  abort "Front Planning content_id differs from the owning run identity"
end
unless front_rel.start_with?("#{normalized_run_rel}/")
  abort "Front Planning artifact must stay inside its owning run"
end

units = Array(front.dig("reference_connection_research", "reference_units"))
unit_by_id = {}
units.each do |unit|
  unit_id = unit["reference_unit_id"].to_s
  abort "duplicate Front Planning reference_unit_id: #{unit_id}" if unit_by_id.key?(unit_id)
  unit_by_id[unit_id] = unit
end

sections = Array(front["section_plan"])
section_ids = sections.map { |section| section["section_id"].to_s }
abort "Front Planning section_plan contains duplicate section ids" unless section_ids.uniq.length == section_ids.length

section_checks = []
work_items = []
sections.each do |section|
  section_id = section.fetch("section_id")
  compared_units = units.select do |unit|
    Array(unit["target_section_ids"]).include?(section_id) &&
      !pinterest_index_row_ids.include?(unit["reference_working_index_row_id"].to_s)
  end
  compared_ids = compared_units.map { |unit| unit.fetch("reference_unit_id") }
  sequence_unit_ids = Array(section["sequence_unit_ids"]).map(&:to_s)
  sequence_reference_ids = units.select do |unit|
    sequence_unit_ids.include?(unit.dig("sequence_unit", "sequence_unit_id").to_s)
  end.map { |unit| unit["reference_unit_id"].to_s }
  assigned_ids = (
    sequence_reference_ids +
    Array(section["scene_reference_unit_ids"]) +
    Array(section["choreography_reference_unit_ids"]) +
    Array(section["major_scene_flow"]).flat_map { |scene| Array(scene["reference_unit_ids"]) }
  ).map(&:to_s).reject(&:empty?).uniq
  unknown_assigned_ids = assigned_ids.reject { |unit_id| unit_by_id.key?(unit_id) }
  mistargeted_assigned_ids = assigned_ids.select do |unit_id|
    unit = unit_by_id[unit_id]
    unit && !Array(unit["target_section_ids"]).include?(section_id)
  end
  source_identity_count = compared_units.map { |unit| unit["source_identity"].to_s }.reject(&:empty?).uniq.length
  directorial_function_count = compared_units.flat_map do |unit|
    Array(unit["function_analysis"]).map { |function| function.to_h["purpose"].to_s }
  end.reject(&:empty?).uniq.length
  selected_sequence_unit_count = sequence_reference_ids.count do |unit_id|
    unit = unit_by_id[unit_id]
    unit &&
      Array(unit["target_section_ids"]).include?(section_id) &&
      %w[applied combined].include?(unit["disposition"].to_s) &&
      unit["sequence_unit"].is_a?(Hash) &&
      unit.dig("sequence_unit", "declared_cadence_seconds") == 1 &&
      Array(unit.dig("sequence_unit", "ordered_frames")).length == 5 &&
      Array(unit.dig("sequence_unit", "frame_observations")).length == 5
  end

  missing = []
  missing << "minimum_one_selected_exact_five_one_second_sequence_unit" if selected_sequence_unit_count < 1
  missing << "unknown_assigned_reference_unit" unless unknown_assigned_ids.empty?
  missing << "assigned_reference_unit_not_targeted_to_section" unless mistargeted_assigned_ids.empty?
  floor_status = missing.empty? ? "decision_ready_evidence_observable_pass" : "named_gap"

  section_checks << {
    "section_id" => section_id,
    "active_reference_unit_ids" => compared_ids,
    "assigned_reference_unit_ids" => assigned_ids,
    "unknown_assigned_reference_unit_ids" => unknown_assigned_ids,
    "mistargeted_assigned_reference_unit_ids" => mistargeted_assigned_ids,
    "comparison_count" => compared_units.length,
    "source_identity_count" => source_identity_count,
    "directorial_function_count" => directorial_function_count,
    "selected_sequence_unit_count" => selected_sequence_unit_count,
    "floor_status" => floor_status,
    "missing_requirements" => missing
  }
  next if missing.empty?

  work_items << {
    "work_item_id" => "01R_GAP_#{section_id}",
    "section_id" => section_id,
    "current_reference_unit_ids" => compared_ids,
    "missing_requirements" => missing,
    "next_action" => "bounded_named_reference_gap_review_required",
    "semantic_owner" => "front_planning_director",
    "automation_scope" => "count_exact_one_second_sequence_units_and_exact_section_bindings_without_fixed_discovery_quota",
    "close_when" => "front_planning_v17_named_reference_gaps_are_observable_and_semantic_owner_accepts_decision_ready_units"
  }
end

front_pointer = {"path" => front_rel, "sha256" => sha256(front_path)}
worklist = {
  "schema_version" => "idol_01r_reference_gap_worklist.v6",
  "artifact_type" => "derived_section_reference_comparison_worklist",
  "run" => normalized_run_rel,
  "source_front_planning" => front_pointer,
  "input_set_sha256" => Digest::SHA256.hexdigest(JSON.generate([front_pointer])),
  "status" => work_items.empty? ? "decision_ready_evidence_observable_pass" : "open_named_gaps",
  "summary" => {
    "total_sections" => section_checks.length,
    "passing_sections" => section_checks.count { |row| row["floor_status"] == "decision_ready_evidence_observable_pass" },
    "open_sections" => work_items.length
  },
  "section_checks" => section_checks,
  "work_items" => work_items,
  "automation_boundaries" => {
    "derived_noncanonical" => true,
    "network_access_performed" => false,
    "search_executed" => false,
    "candidate_selected" => false,
    "reference_interpreted" => false,
    "creative_adequacy_claimed" => false,
    "comparison_floor_is_not_creative_pass" => true
  }
}

output_path, output_rel = repo_path(
  repo_root,
  options[:output] || run_path.join("work/front_planning_integration/reference-comparison-worklist.yaml").to_s
)
unless output_rel.start_with?("#{normalized_run_rel}/")
  abort "worklist output must stay inside the owning run"
end

yaml = YAML.dump(worklist)
Tempfile.create(["idol-01r-reference-gap-worklist", ".yaml"]) do |temp|
  temp.write(yaml)
  temp.flush
  validate_schema(WORKLIST_SCHEMA, Pathname.new(temp.path), "derived 01R reference comparison worklist")
end

if options[:write]
  output_path.dirname.mkpath
  output_path.write(yaml)
end

puts JSON.pretty_generate(
  "write" => options[:write],
  "output" => output_rel,
  "status" => worklist["status"],
  "input_set_sha256" => worklist["input_set_sha256"],
  "summary" => worklist["summary"]
)
