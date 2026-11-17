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
require_relative "lib/idol_production_cut_review_contract"

ROOT = Pathname.new(__dir__).join("..").expand_path
SCHEMA = ROOT.join("schemas", "production-cut-review.schema.json")
SCHEMA_VALIDATOR = ROOT.join("scripts", "validate_json_schema.py")
STORYBOARD_VALIDATOR = ROOT.join("scripts", "validate_master_storyboard.rb")
BRANCH_REVIEW_VALIDATOR = ROOT.join("scripts", "validate_generated_branch_cut_review.rb")
PYTHON = ROOT.join("scripts", "idol-video-python")

options = {root: ROOT, json: false, max_errors: 50}
OptionParser.new do |opts|
  opts.banner = "usage: ruby scripts/validate_production_cut_review.rb [options] PATH"
  opts.on("--root PATH") { |value| options[:root] = Pathname.new(value).expand_path }
  opts.on("--json") { options[:json] = true }
  opts.on("--max-errors COUNT", Integer) { |value| options[:max_errors] = value }
end.parse!

artifact_arg = ARGV.shift
abort "Production Cut review path is required" if artifact_arg.to_s.empty? || !ARGV.empty?

def validate_artifact_ref(ref, label, root, errors)
  unless ref.is_a?(Hash)
    errors << "#{label} must be a path and SHA-256 object"
    return nil
  end
  path = IdolProductionCutReviewContract.resolve_path(ref["path"], root)
  unless IdolProductionCutReviewContract.inside?(path, root) && path.file?
    errors << "#{label} is missing or outside the repository"
    return nil
  end
  errors << "#{label} SHA-256 is stale" unless ref["sha256"].to_s == Digest::SHA256.file(path).hexdigest
  path
end

def run_validator(script, path, root, label, errors)
  return unless path

  stdout, stderr, status = Open3.capture3(
    RbConfig.ruby,
    script.to_s,
    "--root",
    root.to_s,
    path.to_s,
    chdir: root.to_s
  )
  errors << "#{label} failed active validation: #{[stderr, stdout].reject { |value| value.to_s.strip.empty? }.join(' ').strip}" unless status.success?
end

root = options[:root].expand_path.cleanpath
artifact = IdolProductionCutReviewContract.resolve_path(artifact_arg, root)
errors = []
document = {}

unless IdolProductionCutReviewContract.inside?(artifact, root) && artifact.file?
  errors << "Production Cut review is missing or outside the repository"
else
  begin
    document = IdolProductionCutReviewContract.load_mapping(artifact)
  rescue JSON::ParserError, Psych::Exception, TypeError => error
    errors << "cannot parse Production Cut review: #{error.message}"
  end
  stdout, stderr, status = Open3.capture3(
    PYTHON.to_s,
    SCHEMA_VALIDATOR.to_s,
    SCHEMA.to_s,
    artifact.to_s,
    chdir: root.to_s
  )
  errors << "JSON Schema validation failed: #{[stderr, stdout].reject { |value| value.to_s.strip.empty? }.join(' ').strip}" unless status.success?
end

if document.any?
  errors << "only #{IdolProductionCutReviewContract::ACTIVE_SCHEMA_VERSION} is active" unless document["schema_version"].to_s == IdolProductionCutReviewContract::ACTIVE_SCHEMA_VERSION
  run_path = IdolProductionCutReviewContract.resolve_path(document["run_root"], root)
  unless IdolProductionCutReviewContract.inside?(run_path, root) && run_path.directory?
    errors << "run_root is missing or outside the repository"
  end
  expected_path = run_path.join(IdolProductionCutReviewContract::CANONICAL_FILENAME).expand_path.cleanpath
  errors << "Production Cut review must use canonical RUN_ROOT/#{IdolProductionCutReviewContract::CANONICAL_FILENAME}" unless artifact == expected_path

  direction_path = validate_artifact_ref(document["source_01_direction"], "source_01_direction", root, errors)
  storyboard_path = validate_artifact_ref(document["source_02a"], "source_02a", root, errors)
  source_02b_path = validate_artifact_ref(document["source_02b"], "source_02b", root, errors)
  branch_review_path = validate_artifact_ref(document["source_generated_branch_cut_review"], "source_generated_branch_cut_review", root, errors)
  {
    "source_01_direction" => direction_path,
    "source_02a" => storyboard_path,
    "source_02b" => source_02b_path,
    "source_generated_branch_cut_review" => branch_review_path
  }.each do |label, path|
    errors << "#{label} must belong to run_root" if path && !IdolProductionCutReviewContract.inside?(path, run_path)
  end

  run_validator(STORYBOARD_VALIDATOR, storyboard_path, root, "source 02A", errors)
  run_validator(BRANCH_REVIEW_VALIDATOR, branch_review_path, root, "source generated Branch-Cut review", errors)

  if direction_path && storyboard_path && source_02b_path && branch_review_path
    begin
      direction = IdolProductionCutReviewContract.load_mapping(direction_path)
      storyboard = IdolProductionCutReviewContract.load_mapping(storyboard_path)
      prompt_packets = IdolProductionCutReviewContract.load_mapping(source_02b_path)
      branch_review = IdolProductionCutReviewContract.load_mapping(branch_review_path)
      storyboard_direction_path = IdolProductionCutReviewContract.resolve_path(storyboard.dig("source_01_direction", "path"), root)
      errors << "source_01_direction path differs from 02A's exact 01 owner" unless direction_path == storyboard_direction_path

      review_02a_ref = branch_review["source_02a"].to_h
      review_02a_path = IdolProductionCutReviewContract.resolve_path(review_02a_ref["path"], root)
      errors << "source generated Branch-Cut review points to a different 02A" unless review_02a_path == storyboard_path && review_02a_ref["sha256"].to_s == document.dig("source_02a", "sha256").to_s

      review_02b_ref = branch_review["source_02b"].to_h
      review_02b_path = IdolProductionCutReviewContract.resolve_path(review_02b_ref["path"], root)
      errors << "source_02b differs from the generated Branch-Cut review's exact packet owner" unless review_02b_path == source_02b_path && review_02b_ref["sha256"].to_s == document.dig("source_02b", "sha256").to_s

      source_refs = {
        "source_01_direction" => document["source_01_direction"],
        "source_02a" => document["source_02a"],
        "source_02b" => document["source_02b"],
        "source_generated_branch_cut_review" => document["source_generated_branch_cut_review"]
      }
      expected, build_errors = IdolProductionCutReviewContract.build_document(
        run_path: run_path,
        root: root,
        storyboard: storyboard,
        direction: direction,
        prompt_packets: prompt_packets,
        branch_review: branch_review,
        source_refs: source_refs
      )
      errors.concat(build_errors)

      if build_errors.empty?
        actual_rows = Array(document["production_cut_reviews"])
        expected_rows = Array(expected["production_cut_reviews"])
        actual_ids = actual_rows.map { |row| row.to_h["production_cut_id"].to_s }
        expected_ids = expected_rows.map { |row| row.to_h["production_cut_id"].to_s }
        errors << "Production Cut review roster/order differs from G-40 Core/Branch order" unless actual_ids == expected_ids
        expected_by_id = expected_rows.to_h { |row| [row["production_cut_id"].to_s, row] }
        actual_rows.each do |row|
          id = row.to_h["production_cut_id"].to_s
          expected_row = expected_by_id[id]
          next unless expected_row

          unless IdolProductionCutReviewContract.canonical_value(row) == IdolProductionCutReviewContract.canonical_value(expected_row)
            errors << "#{id} Production Cut review differs from its exact 01/02A/Branch-review projection"
          end
        end
        unless IdolProductionCutReviewContract.canonical_value(document["coverage"]) == IdolProductionCutReviewContract.canonical_value(expected["coverage"])
          errors << "Production Cut coverage differs from exact G-40 authorization"
        end
        unless IdolProductionCutReviewContract.canonical_value(document) == IdolProductionCutReviewContract.canonical_value(expected)
          errors << "Production Cut review differs from the deterministic exact-source projection"
        end
      end
    rescue JSON::ParserError, Psych::Exception, TypeError, KeyError => error
      errors << "cannot read Production Cut review sources: #{error.message}"
    end
  end
end

errors = errors.uniq
errors = errors.first(options[:max_errors]) if options[:max_errors].to_i.positive?
result = {
  "valid" => errors.empty?,
  "schema_version" => document["schema_version"],
  "production_cut_count" => Array(document["production_cut_reviews"]).length,
  "errors" => errors
}
if options[:json]
  puts JSON.pretty_generate(result)
elsif errors.empty?
  puts "OK: typed Production Cut review exact-covers passed 01 Official Core and generated Branch pixels"
else
  errors.each { |error| warn "ERROR: #{error}" }
end
exit(errors.empty? ? 0 : 1)
