#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "optparse"
require "pathname"
require "yaml"

CODE_ROOT = Pathname.new(__dir__).join("..").expand_path
RECEIPT_SCHEMA = CODE_ROOT.join("schemas/terra-section-lifecycle-receipt.schema.json")
EXECUTION_SCHEMA = CODE_ROOT.join("schemas/terra-section-lifecycle-execution-record.schema.json")
SCHEMA_VALIDATOR = CODE_ROOT.join("scripts/validate_json_schema.py")
PYTHON_RUNNER = CODE_ROOT.join("scripts/idol-video-python")

options = {repo_root: CODE_ROOT, json: false}
OptionParser.new do |parser|
  parser.banner = "Usage: ruby scripts/validate_terra_section_lifecycle_receipt.rb RECEIPT [options]"
  parser.on("--repo-root DIR", "repository root") { |value| options[:repo_root] = Pathname.new(value).expand_path }
  parser.on("--json", "emit JSON") { options[:json] = true }
end.parse!

abort "RECEIPT is required" unless ARGV.length == 1
repo_root = Pathname.new(options[:repo_root]).expand_path.cleanpath
receipt_path = Pathname.new(ARGV.fetch(0))
receipt_path = repo_root.join(receipt_path) unless receipt_path.absolute?
receipt_path = receipt_path.expand_path.cleanpath
errors = []

def inside?(root, path)
  path == root || path.to_s.start_with?("#{root}#{File::SEPARATOR}")
end

def resolve_path(root, raw)
  path = Pathname.new(raw.to_s)
  path = root.join(path) unless path.absolute?
  path.expand_path.cleanpath
end

def load_yaml_hash(path, label, errors)
  value = YAML.safe_load(path.read, permitted_classes: [], aliases: true)
  unless value.is_a?(Hash)
    errors << "#{label} must be an object"
    return {}
  end
  value
rescue Errno::ENOENT
  errors << "#{label} does not exist: #{path}"
  {}
rescue Psych::Exception => e
  errors << "cannot parse #{label}: #{e.message}"
  {}
end

def validate_schema(schema, document, label, errors)
  stdout, stderr, status = Open3.capture3(
    PYTHON_RUNNER.to_s,
    SCHEMA_VALIDATOR.to_s,
    schema.to_s,
    document.to_s,
    chdir: CODE_ROOT.to_s
  )
  return if status.success?

  message = [stderr, stdout].reject { |row| row.to_s.strip.empty? }.join(" ").strip
  errors << "#{label} failed JSON Schema validation: #{message}"
end

def verify_pointer(root:, pointer:, label:, errors:, require_inside_run: nil)
  unless pointer.is_a?(Hash)
    errors << "#{label} pointer is required"
    return nil
  end
  path = resolve_path(root, pointer["path"])
  unless inside?(root, path)
    errors << "#{label} escapes repository root: #{path}"
    return nil
  end
  if require_inside_run && !inside?(require_inside_run, path)
    errors << "#{label} must stay inside the owning run: #{path}"
    return nil
  end
  unless path.file?
    errors << "#{label} does not exist: #{path}"
    return path
  end
  actual_sha = Digest::SHA256.file(path.to_s).hexdigest
  errors << "#{label} sha256 mismatch" unless actual_sha == pointer["sha256"].to_s
  path
end

unless inside?(repo_root, receipt_path)
  errors << "receipt escapes repository root: #{receipt_path}"
end
unless receipt_path.file?
  errors << "receipt does not exist: #{receipt_path}"
end

receipt = receipt_path.file? ? load_yaml_hash(receipt_path, "receipt", errors) : {}
validate_schema(RECEIPT_SCHEMA, receipt_path, "receipt", errors) if receipt_path.file?

run_rel = receipt["run"].to_s
run_root = resolve_path(repo_root, run_rel)
errors << "run must resolve inside repository root" unless inside?(repo_root, run_root)
errors << "receipt must live inside its owning run" unless receipt_path == run_root || inside?(run_root, receipt_path)

source_paths = {}
if receipt["sources"].is_a?(Hash)
  receipt["sources"].each do |name, pointer|
    next if pointer.nil?
    source_paths[name] = verify_pointer(root: repo_root, pointer: pointer, label: name, errors: errors)
  end
end

execution_record_path = verify_pointer(
  root: repo_root,
  pointer: receipt.dig("executor", "execution_record"),
  label: "executor execution record",
  errors: errors,
  require_inside_run: run_root
)
execution_record = {}
if execution_record_path&.file?
  validate_schema(EXECUTION_SCHEMA, execution_record_path, "executor execution record", errors)
  execution_record = load_yaml_hash(execution_record_path, "executor execution record", errors)
end

unless execution_record.empty?
  comparisons = {
    "session_id" => receipt.dig("executor", "session_id"),
    "source_02a_sha256" => receipt.dig("sources", "source_02a", "sha256"),
    "completion_state" => receipt["status"]
  }
  comparisons.each do |field, expected|
    errors << "execution record #{field} must match the receipt" unless execution_record[field].to_s == expected.to_s
  end
  errors << "execution record must assign exactly receipt.section_id" unless Array(execution_record["assigned_section_ids"]) == [receipt["section_id"]]
  errors << "execution record must use active v3" unless execution_record["schema_version"] == "idol_terra_section_lifecycle_execution_record.v3"
  errors << "execution record section_lineage_id must match the receipt" unless execution_record["section_lineage_id"].to_s == receipt.dig("session_contract", "section_lineage_id").to_s
  errors << "execution record checkpoint_id must match the completed checkpoint" unless execution_record["checkpoint_id"].to_s == receipt.dig("session_contract", "completed_checkpoint_id").to_s
end

Array(receipt["direct_script_checks"]).each_with_index do |check, index|
  verify_pointer(
    root: repo_root,
    pointer: {"path" => check["evidence_path"], "sha256" => check["evidence_sha256"]},
    label: "direct_script_checks[#{index}] evidence",
    errors: errors,
    require_inside_run: run_root
  )
end

assets = {}
Array(receipt["inspected_asset_manifest"]).each_with_index do |asset, index|
  asset_id = asset["asset_id"].to_s
  if assets.key?(asset_id)
    errors << "inspected_asset_manifest repeats asset_id #{asset_id}"
  else
    assets[asset_id] = asset
  end
  verify_pointer(
    root: repo_root,
    pointer: {"path" => asset["actual_path"], "sha256" => asset["sha256"]},
    label: "inspected_asset_manifest[#{index}]",
    errors: errors,
    require_inside_run: run_root
  )
end

core_cut_ids = []
branch_cut_ids = []
direct_sequence_core_cut_ids = []
source_02a_path = source_paths["source_02a"]
if source_02a_path&.file?
  source_02a = load_yaml_hash(source_02a_path, "source 02A", errors)
  Array(source_02a["master_storyboard"]).each do |core_cut|
    next unless core_cut.is_a?(Hash)
    core_cut_id = core_cut["core_cut_id"].to_s
    core_cut_ids << core_cut_id unless core_cut_id.empty?
    Array(core_cut.dig("compile_seed", "branch_cuts")).each do |branch_cut|
      branch_cut_id = branch_cut.is_a?(Hash) ? branch_cut["branch_cut_id"].to_s : ""
      branch_cut_ids << branch_cut_id unless branch_cut_id.empty?
    end
    reference_contract = core_cut["reference_contact_sheet_contract"].is_a?(Hash) ? core_cut["reference_contact_sheet_contract"] : core_cut
    references = [reference_contract["primary_exact_scene_reference"], *Array(reference_contract["secondary_exact_scene_references"])]
    if references.any? { |ref| ref.is_a?(Hash) && %w[full_scene_direct sequence_direct].include?(ref["application_mode"].to_s) }
      direct_sequence_core_cut_ids << core_cut_id
    end
  end
end

evidence_ids = []
evidence_rows = Array(receipt["sol_decision_evidence"])
evidence_rows.each_with_index do |row, row_index|
  evidence_id = row["decision_set_id"].to_s
  evidence_ids << evidence_id
  Array(row["surfaces"]).each_with_index do |surface, surface_index|
    asset_id = surface["source_or_generated_asset_id"].to_s
    asset = assets[asset_id]
    if asset.nil?
      errors << "sol_decision_evidence[#{row_index}].surfaces[#{surface_index}] references uninspected asset #{asset_id}"
      next
    end
    errors << "evidence surface path must match inspected asset #{asset_id}" unless surface["actual_path"].to_s == asset["actual_path"].to_s
    errors << "evidence surface sha256 must match inspected asset #{asset_id}" unless surface["sha256"].to_s == asset["sha256"].to_s
    unknown_core_cuts = Array(surface["maps_to_core_cut_ids"]).map(&:to_s) - core_cut_ids
    errors << "evidence surface #{asset_id} maps to unknown 02A Core Cuts: #{unknown_core_cuts.join(', ')}" unless unknown_core_cuts.empty?
    unknown_branch_cuts = Array(surface["maps_to_branch_cut_ids"]).map(&:to_s) - branch_cut_ids
    errors << "evidence surface #{asset_id} maps to unknown 02A Branch Cuts: #{unknown_branch_cuts.join(', ')}" unless unknown_branch_cuts.empty?
    if %w[clip playback].include?(surface["media_type"].to_s)
      range = surface["time_range"]
      if !range.is_a?(Hash) || range["end_seconds"].to_f <= range["start_seconds"].to_f
        errors << "clip/playback evidence #{asset_id} requires an increasing time_range"
      end
    end
  end
end
duplicate_evidence_ids = evidence_ids.group_by(&:itself).select { |id, rows| !id.empty? && rows.length > 1 }.keys
errors << "sol_decision_evidence repeats decision_set_id: #{duplicate_evidence_ids.join(', ')}" unless duplicate_evidence_ids.empty?

candidate_ids = Array(receipt.dig("generated_branch_cut_sol_gate", "candidate_asset_ids")).map(&:to_s)
selected_ids = Array(receipt.dig("generated_branch_cut_sol_gate", "selected_asset_ids")).map(&:to_s)
errors << "generated Branch-Cut selected_asset_ids must be a subset of candidate_asset_ids" unless (selected_ids - candidate_ids).empty?
(candidate_ids - assets.keys).each { |asset_id| errors << "generated Branch-Cut candidate asset was not inspected: #{asset_id}" }
candidate_ids.each do |asset_id|
  asset = assets[asset_id]
  errors << "generated Branch-Cut candidate #{asset_id} must belong to generated_branch_cut_review" if asset && asset["stage"] != "generated_branch_cut_review"
end

unless direct_sequence_core_cut_ids.empty?
  covered_direct = evidence_rows.select do |row|
    row["stage"] == "02a_validation" && %w[sequence_bundle playback_clip].include?(row["evidence_kind"].to_s)
  end
    .flat_map { |row| Array(row["surfaces"]).flat_map { |surface| Array(surface["maps_to_core_cut_ids"]) } }
    .map(&:to_s).uniq
  missing_direct = direct_sequence_core_cut_ids - covered_direct
  errors << "direct-scene/sequence Core Cuts require 02A-validation sequence or playback evidence: #{missing_direct.join(', ')}" unless missing_direct.empty?
end

if receipt["status"] == "complete"
  has_generated = evidence_rows.any? { |row| row["stage"] == "generated_branch_cut_review" }
  has_03v_playback = evidence_rows.any? { |row| row["stage"] == "03v" && row["evidence_kind"] == "playback_clip" }
  errors << "complete receipt requires generated Branch-Cut decision evidence" unless has_generated
  errors << "complete receipt requires a hash-bound 03V playback clip" unless has_03v_playback
  errors << "active v3 receipt must not include 04 evidence; 04 uses its own edit/QC stage" if evidence_rows.any? { |row| row["stage"] == "04" }
end

result = {
  "valid" => errors.empty?,
  "receipt" => receipt_path.to_s,
  "run" => run_rel,
  "section_id" => receipt["section_id"],
  "status" => receipt["status"],
  "inspected_asset_count" => assets.length,
  "decision_evidence_count" => evidence_rows.length,
  "errors" => errors
}

if options[:json]
  puts JSON.pretty_generate(result)
else
  puts(errors.empty? ? "Terra section lifecycle receipt: valid" : "Terra section lifecycle receipt: invalid")
  errors.each { |error| warn "- #{error}" }
end
exit(errors.empty? ? 0 : 1)
