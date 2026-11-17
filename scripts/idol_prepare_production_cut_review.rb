#!/usr/bin/env ruby
# frozen_string_literal: true

require "date"
require "digest"
require "fileutils"
require "json"
require "open3"
require "optparse"
require "pathname"
require "rbconfig"
require "tempfile"
require "yaml"
require_relative "lib/idol_production_cut_review_contract"

ROOT = Pathname.new(__dir__).join("..").expand_path
SCHEMA = ROOT.join("schemas", "production-cut-review.schema.json")
SCHEMA_VALIDATOR = ROOT.join("scripts", "validate_json_schema.py")
STORYBOARD_VALIDATOR = ROOT.join("scripts", "validate_master_storyboard.rb")
BRANCH_REVIEW_VALIDATOR = ROOT.join("scripts", "validate_generated_branch_cut_review.rb")
PYTHON = ROOT.join("scripts", "idol-video-python")

options = {
  root: ROOT,
  run: nil,
  storyboard: nil,
  branch_review: nil,
  write: false,
  json: true
}

parser = OptionParser.new do |opts|
  opts.banner = "usage: ruby scripts/idol_prepare_production_cut_review.rb RUN_ROOT [options]"
  opts.on("--root PATH", "Repository root used to resolve and hash all sources.") { |value| options[:root] = Pathname.new(value).expand_path }
  opts.on("--run PATH", "Run root; alternative to positional RUN_ROOT.") { |value| options[:run] = value }
  opts.on("--master-storyboard PATH", "Explicit active 02A v3 source.") { |value| options[:storyboard] = value }
  opts.on("--generated-branch-cut-review PATH", "Explicit passed generated Branch-Cut review v4 source.") { |value| options[:branch_review] = value }
  opts.on("--write", "Write RUN_ROOT/03-production-cut-review.yaml after all checks pass.") { options[:write] = true }
  opts.on("--no-json", "Print a short text result.") { options[:json] = false }
end

begin
  parser.parse!
rescue OptionParser::ParseError => error
  warn error.message
  warn parser
  exit 2
end

run_arg = options[:run] || ARGV.shift
if run_arg.to_s.strip.empty? || !ARGV.empty?
  warn parser
  exit 2
end

def run_validator(script, path, root)
  stdout, stderr, status = Open3.capture3(
    RbConfig.ruby,
    script.to_s,
    "--root",
    root.to_s,
    path.to_s,
    chdir: root.to_s
  )
  return nil if status.success?

  [stderr, stdout].reject { |value| value.to_s.strip.empty? }.join("\n").strip
end

def validate_schema(document, schema, root)
  Tempfile.create(["idol-production-cut-review-", ".yaml"]) do |file|
    file.write(YAML.dump(document))
    file.flush
    stdout, stderr, status = Open3.capture3(
      PYTHON.to_s,
      SCHEMA_VALIDATOR.to_s,
      schema.to_s,
      file.path,
      chdir: root.to_s
    )
    return nil if status.success?

    [stderr, stdout].reject { |value| value.to_s.strip.empty? }.join("\n").strip
  end
end

root = options[:root].expand_path.cleanpath
run_path = IdolProductionCutReviewContract.resolve_path(run_arg, root)
errors = []
unless IdolProductionCutReviewContract.inside?(run_path, root) && run_path.directory?
  errors << "run root is missing or outside the repository: #{run_arg}"
end

storyboard_path = if options[:storyboard]
                    IdolProductionCutReviewContract.resolve_path(options[:storyboard], root)
                  else
                    run_path.join("02A-master-storyboard.yaml").expand_path.cleanpath
                  end
branch_review_path = if options[:branch_review]
                       IdolProductionCutReviewContract.resolve_path(options[:branch_review], root)
                     else
                       run_path.join("03-generated-branch-cut-review.yaml").expand_path.cleanpath
                     end
output_path = run_path.join(IdolProductionCutReviewContract::CANONICAL_FILENAME).expand_path.cleanpath

{
  "source 02A" => storyboard_path,
  "source generated Branch-Cut review" => branch_review_path
}.each do |label, path|
  errors << "#{label} is missing or outside the repository" unless IdolProductionCutReviewContract.inside?(path, root) && path.file?
  errors << "#{label} must belong to the owning run" unless IdolProductionCutReviewContract.inside?(path, run_path)
end
errors << "canonical output must be RUN_ROOT/#{IdolProductionCutReviewContract::CANONICAL_FILENAME}" unless output_path.parent == run_path && output_path.basename.to_s == IdolProductionCutReviewContract::CANONICAL_FILENAME

storyboard = {}
branch_review = {}
direction = {}
direction_path = nil
source_02b_path = nil
prompt_packets = {}

if errors.empty?
  storyboard_error = run_validator(STORYBOARD_VALIDATOR, storyboard_path, root)
  errors << "source 02A failed active validation: #{storyboard_error}" if storyboard_error
  branch_error = run_validator(BRANCH_REVIEW_VALIDATOR, branch_review_path, root)
  errors << "source generated Branch-Cut review failed active validation: #{branch_error}" if branch_error
end

if errors.empty?
  begin
    storyboard = IdolProductionCutReviewContract.load_mapping(storyboard_path)
    branch_review = IdolProductionCutReviewContract.load_mapping(branch_review_path)
    direction_path = IdolProductionCutReviewContract.resolve_path(storyboard.dig("source_01_direction", "path"), root)
    source_02b_path = IdolProductionCutReviewContract.resolve_path(branch_review.dig("source_02b", "path"), root)
    unless IdolProductionCutReviewContract.inside?(direction_path, run_path) && direction_path.file?
      errors << "source 01 direction is missing or outside the owning run"
    end
    unless IdolProductionCutReviewContract.inside?(source_02b_path, run_path) && source_02b_path.file?
      errors << "source 02B is missing or outside the owning run"
    end
    if errors.empty?
      direction = IdolProductionCutReviewContract.load_mapping(direction_path)
      prompt_packets = IdolProductionCutReviewContract.load_mapping(source_02b_path)
      selected_02a_ref = branch_review["source_02a"].to_h
      unless IdolProductionCutReviewContract.resolve_path(selected_02a_ref["path"], root) == storyboard_path &&
             selected_02a_ref["sha256"].to_s == Digest::SHA256.file(storyboard_path).hexdigest
        errors << "generated Branch-Cut review does not bind the selected current 02A bytes"
      end
      unless branch_review.dig("source_02b", "sha256").to_s == Digest::SHA256.file(source_02b_path).hexdigest
        errors << "generated Branch-Cut review source 02B SHA-256 is stale"
      end
    end
  rescue JSON::ParserError, Psych::Exception, TypeError => error
    errors << "cannot read a Production Cut review source: #{error.message}"
  end
end

document = {}
if errors.empty?
  source_refs = {
    "source_01_direction" => IdolProductionCutReviewContract.artifact_ref(direction_path, root),
    "source_02a" => IdolProductionCutReviewContract.artifact_ref(storyboard_path, root),
    "source_02b" => IdolProductionCutReviewContract.artifact_ref(source_02b_path, root),
    "source_generated_branch_cut_review" => IdolProductionCutReviewContract.artifact_ref(branch_review_path, root)
  }
  document, build_errors = IdolProductionCutReviewContract.build_document(
    run_path: run_path,
    root: root,
    storyboard: storyboard,
    direction: direction,
    prompt_packets: prompt_packets,
    branch_review: branch_review,
    source_refs: source_refs
  )
  errors.concat(build_errors)
  schema_error = validate_schema(document, SCHEMA, root)
  errors << "Production Cut review JSON Schema validation failed: #{schema_error}" if schema_error
end

if errors.empty? && options[:write]
  FileUtils.mkdir_p(output_path.dirname)
  Tempfile.create([".#{output_path.basename}", ".tmp"], output_path.dirname.to_s) do |file|
    file.write(YAML.dump(document))
    file.flush
    file.fsync
    File.rename(file.path, output_path)
  end
end

errors = errors.uniq
result = {
  "ok" => errors.empty?,
  "write" => options[:write],
  "schema_version" => document["schema_version"],
  "output_path" => IdolProductionCutReviewContract.inside?(output_path, root) ? IdolProductionCutReviewContract.relative_path(output_path, root) : output_path.to_s,
  "production_cut_count" => Array(document["production_cut_reviews"]).length,
  "official_core_count" => document.dig("coverage", "official_core_count"),
  "branch_count" => document.dig("coverage", "branch_count"),
  "errors" => errors
}

if options[:json]
  puts JSON.pretty_generate(result)
elsif errors.empty?
  puts "OK: #{result['production_cut_count']} passed Production Cuts exact-cover G-40 at #{result['output_path']}"
else
  errors.each { |error| warn "ERROR: #{error}" }
end
exit(errors.empty? ? 0 : 1)
