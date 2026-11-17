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
SCHEMA = ROOT.join("schemas", "audio-branch-cut-placement.schema.json")
SCHEMA_VALIDATOR = ROOT.join("scripts", "validate_json_schema.py")
REVIEW_VALIDATOR = ROOT.join("scripts", "validate_production_cut_review.rb")
PYTHON = ROOT.join("scripts", "idol-video-python")
ACTIVE_SCHEMA_VERSION = "idol_audio_production_cut_placement.v5"

options = {root: ROOT, json: false, require_ready: false, max_errors: 60}
OptionParser.new do |opts|
  opts.banner = "usage: ruby scripts/validate_audio_branch_cut_placement.rb [options] PATH"
  opts.on("--root PATH") { |value| options[:root] = Pathname.new(value).expand_path }
  opts.on("--json") { options[:json] = true }
  opts.on("--require-ready") { options[:require_ready] = true }
  opts.on("--max-errors COUNT", Integer) { |value| options[:max_errors] = value }
end.parse!
artifact_arg = ARGV.shift
abort "Audio Production-Cut Placement path is required" if artifact_arg.to_s.empty? || !ARGV.empty?

def load_mapping(path)
  value = if path.extname.downcase == ".json"
            JSON.parse(path.read)
          else
            YAML.safe_load(path.read, permitted_classes: [Date, Time], permitted_symbols: [], aliases: true)
          end
  raise TypeError, "document must be an object" unless value.is_a?(Hash)

  value
end

def canonical_value(value)
  case value
  when Hash
    value.keys.map(&:to_s).sort.each_with_object({}) do |key, result|
      source_key = value.key?(key) ? key : value.keys.find { |candidate| candidate.to_s == key }
      result[key] = canonical_value(value[source_key])
    end
  when Array
    value.map { |item| canonical_value(item) }
  else
    value
  end
end

def value_sha256(value)
  Digest::SHA256.hexdigest(JSON.generate(canonical_value(value)))
end

def resolve_path(raw, root)
  path = Pathname.new(raw.to_s)
  (path.absolute? ? path : root.join(path)).expand_path.cleanpath
end

def inside?(path, root)
  relative = path.relative_path_from(root).to_s
  relative != ".." && !relative.start_with?("../")
rescue ArgumentError
  false
end

def bound_source(ref, label, root, errors)
  path = resolve_path(ref.to_h["path"], root)
  unless inside?(path, root) && path.file?
    errors << "#{label} is missing or outside the repository"
    return [nil, nil]
  end
  actual = Digest::SHA256.file(path).hexdigest
  errors << "#{label} SHA-256 is stale" unless ref.to_h["sha256"].to_s == actual
  document = %w[.yaml .yml .json].include?(path.extname.downcase) ? load_mapping(path) : nil
  [path, document]
rescue JSON::ParserError, Psych::Exception, TypeError => error
  errors << "#{label} cannot be read: #{error.message}"
  [path, nil]
end

def pointer_value(document, pointer)
  pointer.to_s.split("/")[1..].to_a.reduce(document) do |current, raw_token|
    token = raw_token.gsub("~1", "/").gsub("~0", "~")
    current.is_a?(Array) ? current.fetch(Integer(token, 10)) : current.fetch(token)
  end
end

def validate_upscale_receipt(unit, root, label, errors)
  receipt_path, receipt = bound_source(unit["local_upscale_receipt"], "#{label}.local_upscale_receipt", root, errors)
  return unless receipt_path && receipt

  source_path = resolve_path(unit.dig("passed_source_image", "path"), root)
  output_path = resolve_path(unit.dig("placement_image", "path"), root)
  operations = Array(receipt["operations"])
  matches = operations.select do |operation|
    resolve_path(operation.dig("source", "path"), root) == source_path &&
      resolve_path(operation.dig("output", "path"), root) == output_path
  end
  if matches.length != 1
    errors << "#{label} local upscale receipt must bind exact passed source and placement output exactly once"
    return
  end
  operation = matches.first
  unless operation.dig("source", "sha256").to_s == unit.dig("passed_source_image", "sha256").to_s
    errors << "#{label} local upscale source SHA-256 differs from passed pixels"
  end
  unless operation.dig("output", "sha256").to_s == unit.dig("placement_image", "sha256").to_s
    errors << "#{label} local upscale output SHA-256 differs from placement image"
  end
rescue KeyError, ArgumentError => error
  errors << "#{label} local upscale receipt is malformed: #{error.message}"
end

root = options[:root].expand_path.cleanpath
artifact = resolve_path(artifact_arg, root)
errors = []
document = {}
unless inside?(artifact, root) && artifact.file?
  errors << "Audio Production-Cut Placement is missing or outside the repository"
else
  begin
    document = load_mapping(artifact)
  rescue JSON::ParserError, Psych::Exception, TypeError => error
    errors << "cannot parse Audio Production-Cut Placement: #{error.message}"
  end
  stdout, stderr, status = Open3.capture3(PYTHON.to_s, SCHEMA_VALIDATOR.to_s, SCHEMA.to_s, artifact.to_s, chdir: ROOT.to_s)
  errors << "JSON Schema validation failed: #{[stderr, stdout].join(' ').strip}" unless status.success?
end

if document.any?
  errors << "only #{ACTIVE_SCHEMA_VERSION} is active" unless document["schema_version"].to_s == ACTIVE_SCHEMA_VERSION
  audio_path, = bound_source(document["source_audio"], "source_audio", root, errors)
  motion_path, = bound_source(document["source_audio_motion_map"], "source_audio_motion_map", root, errors)
  review_path, review = bound_source(document["source_production_cut_review"], "source_production_cut_review", root, errors)
  direction_path, direction = bound_source(document["source_01_direction"], "source_01_direction", root, errors)
  storyboard_path, storyboard = bound_source(document["source_02a"], "source_02a", root, errors)
  prompt_path, prompts = bound_source(document["source_02b"], "source_02b", root, errors)
  [audio_path, motion_path, review_path, direction_path, storyboard_path, prompt_path].compact.each do |path|
    errors << "#{path} must not be the placement artifact itself" if path == artifact
  end
  if review_path
    stdout, stderr, status = Open3.capture3("ruby", REVIEW_VALIDATOR.to_s, "--root", root.to_s, review_path.to_s, chdir: ROOT.to_s)
    errors << "source Production Cut review failed active validation: #{[stderr, stdout].join(' ').strip}" unless status.success?
  end

  if review && direction && storyboard && prompts
    errors << "placement content_id differs from Production Cut review" unless document["content_id"].to_s == review["content_id"].to_s
    {
      "source_01_direction" => "source_01_direction",
      "source_02a" => "source_02a",
      "source_02b" => "source_02b"
    }.each do |placement_key, review_key|
      unless canonical_value(document[placement_key]) == canonical_value(review[review_key])
        errors << "placement #{placement_key} differs from Production Cut review"
      end
    end
    reviews = Array(review["production_cut_reviews"])
    units = Array(document["production_cut_units"])
    review_ids = reviews.map { |row| row.to_h["production_cut_id"].to_s }
    unit_ids = units.map { |row| row.to_h["production_cut_id"].to_s }
    errors << "Production Cut placement ids must be unique" unless unit_ids.uniq.length == unit_ids.length
    if %w[ready_for_03v passed].include?(document["status"].to_s)
      errors << "ready placement requires passed typed Production Cut review" unless review["status"].to_s == "passed"
      errors << "ready placement must exact-cover typed Production Cut review order" unless unit_ids == review_ids
    end

    choreography_by_section = Array(direction["section_directions"]).to_h do |section|
      [section.to_h["section_id"].to_s, section.to_h["choreography_presence_policy"].to_s]
    end
    branch_order_by_id = Array(storyboard["master_storyboard"]).flat_map do |core|
      Array(core.to_h.dig("compile_seed", "branch_cuts")).map do |branch|
        [branch.to_h["branch_cut_id"].to_s, branch.to_h["branch_sequence"]]
      end
    end.to_h

    units.each_with_index do |unit, index|
      label = "production_cut_units[#{index}]"
      review_row = reviews[index].to_h
      if review_row.empty?
        errors << "#{label} has no corresponding typed Production Cut review row"
        next
      end
      exact_fields = %w[production_cut_id production_cut_type parent_core_cut_id packet_id section_id major_scene_id active_storyline_version_id screen_progression_node_id scene_phase_context sequence_phase_binding_ids core_reference_binding_id primary_audio_cue]
      exact_fields.each do |field|
        unless canonical_value(unit[field]) == canonical_value(review_row[field])
          errors << "#{label}.#{field} differs from typed Production Cut review"
        end
      end
      errors << "#{label}.production_cut_order must match artifact order" unless unit["production_cut_order"] == index + 1
      expected_parent_order = review_row["production_cut_type"] == "official_core" ? 0 : branch_order_by_id[review_row["production_cut_id"].to_s]
      errors << "#{label}.order_within_parent_core differs from 02A" unless unit["order_within_parent_core"] == expected_parent_order
      errors << "#{label}.end_seconds must be greater than start_seconds" unless unit["end_seconds"].to_f > unit["start_seconds"].to_f
      unless canonical_value(unit["passed_source_image"]) == canonical_value({"path" => review_row["path"], "sha256" => review_row["sha256"]})
        errors << "#{label}.passed_source_image differs from typed passed pixel authority"
      end
      source_image_path, = bound_source(unit["passed_source_image"], "#{label}.passed_source_image", root, errors)
      placement_image_path, = bound_source(unit["placement_image"], "#{label}.placement_image", root, errors)
      [source_image_path, placement_image_path].compact.each do |path|
        errors << "#{label} image is outside the owning run" unless inside?(path, artifact.dirname)
      end
      if unit["production_cut_type"].to_s == "official_core"
        unless canonical_value(unit["placement_image"]) == canonical_value(unit["passed_source_image"])
          errors << "#{label} Official Core placement image must preserve the original passed pixel bytes"
        end
        errors << "#{label} Official Core may not invent a local upscale receipt" unless unit["local_upscale_receipt"].nil?
      else
        validate_upscale_receipt(unit, root, label, errors)
      end
      expected_visible_state = review_row["observable_pixel_truth"].to_s
      expected_visible_state = review_row["review_note"].to_s if expected_visible_state.empty?
      errors << "#{label}.actual_visible_state must exact-copy typed pixel review truth" unless unit["actual_visible_state"].to_s == expected_visible_state
      source_policy = choreography_by_section[unit["section_id"].to_s]
      if source_policy.to_s.empty?
        errors << "#{label} choreography source is missing from exact 01 Section direction"
      elsif unit["choreography_presence_policy"].to_s != source_policy
        errors << "#{label} choreography policy differs from exact 01 Section direction"
      end
    end

    chronological = units.sort_by { |row| [row.to_h["start_seconds"].to_f, row.to_h["end_seconds"].to_f] }
    errors << "production_cut_units must be in chronological order" unless chronological == units
    computed_gaps = 0
    computed_overlaps = 0
    units.each_cons(2) do |previous, current|
      delta = current["start_seconds"].to_f - previous["end_seconds"].to_f
      computed_gaps += 1 if delta.positive?
      computed_overlaps += 1 if delta.negative?
    end
    coverage = document["coverage"].to_h
    errors << "coverage.positive_gap_count is stale" unless coverage["positive_gap_count"].to_i == computed_gaps
    errors << "coverage.overlap_count is stale" unless coverage["overlap_count"].to_i == computed_overlaps
    errors << "coverage.audio_start_seconds must equal first Production Cut start" unless units.empty? || coverage["audio_start_seconds"].to_f == units.first["start_seconds"].to_f
    errors << "coverage.audio_end_seconds must equal last Production Cut end" unless units.empty? || coverage["audio_end_seconds"].to_f == units.last["end_seconds"].to_f
    errors << "coverage.production_cut_ids is stale" unless Array(coverage["production_cut_ids"]).map(&:to_s) == unit_ids
    errors << "coverage.official_core_count is stale" unless coverage["official_core_count"].to_i == units.count { |row| row["production_cut_type"] == "official_core" }
    errors << "coverage.branch_count is stale" unless coverage["branch_count"].to_i == units.count { |row| row["production_cut_type"] == "branch" }
    errors << "coverage.production_cut_count is stale" unless coverage["production_cut_count"].to_i == units.length
  end

  if options[:require_ready] && !%w[ready_for_03v passed].include?(document["status"].to_s)
    errors << "--require-ready needs status ready_for_03v or passed"
  end
end

errors = errors.uniq.first(options[:max_errors])
result = {"valid" => errors.empty?, "schema_version" => document["schema_version"], "errors" => errors}
if options[:json]
  puts JSON.pretty_generate(result)
elsif errors.empty?
  puts "OK: Audio Production-Cut Placement v5 maps typed passed Official Core and Branch pixels to audio without pre-authoring camera motion"
else
  errors.each { |error| warn "ERROR: #{error}" }
end
exit(errors.empty? ? 0 : 1)
