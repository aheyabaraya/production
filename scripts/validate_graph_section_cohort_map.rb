#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "optparse"
require "pathname"
require "yaml"

ROOT = Pathname.new(__dir__).join("..").expand_path
SCHEMA = ROOT.join("schemas", "graph-section-cohort-map.schema.json")
PYTHON = ROOT.join("scripts", "idol-video-python")
SCHEMA_VALIDATOR = ROOT.join("scripts", "validate_json_schema.py")

P3_LANE = /\Aplanning_p3_c([1-9][0-9]*)\z/
V_LANE = /\Asection_cluster_v_c([1-9][0-9]*)\z/

options = {json: false, root: ROOT, lineage: nil}
OptionParser.new do |parser|
  parser.banner = "usage: ruby scripts/validate_graph_section_cohort_map.rb [--json] [--root PATH] [--lineage PATH] MAP"
  parser.on("--json") { options[:json] = true }
  parser.on("--root PATH") { |value| options[:root] = Pathname.new(value).expand_path }
  parser.on("--lineage PATH") { |value| options[:lineage] = value }
end.parse!

argument = ARGV.shift
if argument.to_s.empty? || !ARGV.empty?
  warn "graph section cohort map path is required"
  exit 2
end

def document_path(root, raw)
  path = Pathname.new(raw.to_s)
  path = root.join(path) unless path.absolute?
  path.expand_path.cleanpath
end

def repo_path(root, raw)
  path = document_path(root, raw)
  relative = path.relative_path_from(root).to_s
  raise ArgumentError, "path escapes repository: #{raw}" if relative == ".." || relative.start_with?("../")

  [path, relative]
end

def load_document(path)
  text = path.read
  value = path.extname.downcase == ".json" ? JSON.parse(text) : YAML.safe_load(text, aliases: true)
  value.is_a?(Hash) ? value : nil
rescue JSON::ParserError, Psych::Exception
  nil
end

def schema_errors(path)
  stdout, stderr, status = Open3.capture3(
    PYTHON.to_s,
    SCHEMA_VALIDATOR.to_s,
    SCHEMA.to_s,
    path.to_s,
    chdir: ROOT.to_s
  )
  return [] if status.success?

  message = [stderr, stdout].reject { |value| value.to_s.strip.empty? }.join(" ").strip
  message.empty? ? ["JSON Schema validation failed"] : [message]
end

def roster_index(roster)
  Array(roster).each_with_index.to_h { |section_id, index| [section_id.to_s, index] }
end

def contiguous?(section_ids, order)
  indices = Array(section_ids).map { |section_id| order[section_id.to_s] }
  return false if indices.any?(&:nil?)
  return true if indices.length == 1

  indices.each_cons(2).all? { |left, right| right == left + 1 }
end

def canonical_cohort_sizes(section_count)
  count = Integer(section_count)
  return :invalid if count < 1
  return [1] if count == 1

  threes, remainder = count.divmod(3)
  sizes =
    case remainder
    when 0
      Array.new(threes, 3)
    when 1
      return :invalid if threes < 1

      [2, 2] + Array.new(threes - 1, 3)
    when 2
      [2] + Array.new(threes, 3)
    end
  return :invalid unless sizes.sum == count && sizes.all? { |size| [2, 3].include?(size) }

  sizes
end

def lane_index(lane_id, pattern)
  match = lane_id.to_s.match(pattern)
  match && match[1].to_i
end

def validate_pointer(root, errors, label, pointer)
  return unless pointer.is_a?(Hash)

  path, _relative = repo_path(root, pointer["path"])
  unless path.file?
    errors << "#{label} path is missing: #{pointer['path']}"
    return
  end
  actual = Digest::SHA256.file(path.to_s).hexdigest
  errors << "#{label} SHA-256 is stale: #{pointer['path']}" unless actual == pointer["sha256"].to_s
rescue ArgumentError => e
  errors << "#{label} #{e.message}"
end

def validate_cohort_map(root, errors, document)
  roster = Array(document["section_roster"]).map(&:to_s)
  errors << "section_roster is empty" if roster.empty?
  order = roster_index(roster)
  mapped = []
  cohort_ids = []
  sizes = []

  Array(document["cohorts"]).each_with_index do |cohort, index|
    next unless cohort.is_a?(Hash)

    cohort_id = cohort["section_cohort_id"].to_s
    expected_cohort_id = "C#{index + 1}"
    errors << "section_cohort_id must exact-carry canonical #{expected_cohort_id}" unless cohort_id == expected_cohort_id
    errors << "duplicate section_cohort_id #{cohort_id}" if cohort_ids.include?(cohort_id)
    cohort_ids << cohort_id
    section_ids = Array(cohort["section_ids"]).map(&:to_s)
    sizes << section_ids.length
    unless contiguous?(section_ids, order)
      errors << "cohort #{cohort_id} sections are not contiguous"
    end
    if roster.length == 1
      errors << "cohort #{cohort_id} size must be 1 for a one-section title" unless section_ids.length == 1
    elsif section_ids.length < 2 || section_ids.length > 3
      errors << "cohort #{cohort_id} size must be 2 or 3 except a one-section title"
    end

    section_ids.each do |section_id|
      if mapped.include?(section_id)
        errors << "section #{section_id} is mapped more than once"
      else
        mapped << section_id
      end
      errors << "section #{section_id} is not in section_roster" unless order.key?(section_id)
    end

    p3_index = lane_index(cohort["planning_lane_id"], P3_LANE)
    expected = cohort_id[/\AC([1-9][0-9]*)\z/, 1].to_i
    errors << "cohort #{cohort_id} planning_lane_id must be planning_p3_c#{expected}" unless p3_index == expected

    reviewer = cohort["cdd_reviewer"]
    if reviewer.is_a?(Hash)
      errors << "cohort #{cohort_id} must have exactly one CDD reviewer" if reviewer["owner"].to_s.strip.empty?
      errors << "cohort #{cohort_id} CDD reviewer role must be creative_development_director" unless reviewer["role"].to_s == "creative_development_director"
      expected_reviewer_lane = document["phase"].to_s == "planning_provisional" ? cohort["planning_lane_id"] : cohort["production_lane_id"]
      unless reviewer["lane_id"].to_s == expected_reviewer_lane.to_s
        errors << "cohort #{cohort_id} CDD reviewer lane must exact-carry #{expected_reviewer_lane}"
      end
    else
      errors << "cohort #{cohort_id} must have exactly one CDD reviewer"
    end

    recipient = cohort["return_recipient"]
    if recipient.is_a?(Hash)
      errors << "cohort #{cohort_id} return recipient is missing" if recipient["owner"].to_s.strip.empty? || recipient["role"].to_s.strip.empty?
    else
      errors << "cohort #{cohort_id} return recipient is missing"
    end

    writers = Array(cohort["section_output_writers"])
    writer_sections = []
    writers.each do |writer|
      next unless writer.is_a?(Hash)

      section_id = writer["section_id"].to_s
      if writer_sections.include?(section_id)
        errors << "section #{section_id} must have exactly one output writer"
      else
        writer_sections << section_id
      end
      errors << "section #{section_id} output writer role must be section_image_motion_worker" unless writer["role"].to_s == "section_image_motion_worker"
      errors << "section #{section_id} output writer owner is missing" if writer["owner"].to_s.strip.empty?
    end
    section_ids.each do |section_id|
      errors << "section #{section_id} must have exactly one output writer" unless writer_sections.include?(section_id)
    end
    writer_sections.each do |section_id|
      errors << "section #{section_id} writer is outside cohort #{cohort_id}" unless section_ids.include?(section_id)
    end

    phase = document["phase"].to_s
    if phase == "planning_provisional"
      errors << "cohort #{cohort_id} production_lane_id must be null before G-40" unless cohort["production_lane_id"].nil?
    else
      v_index = lane_index(cohort["production_lane_id"], V_LANE)
      errors << "cohort #{cohort_id} production_lane_id must be section_cluster_v_c#{expected}" unless v_index == expected
    end
  end

  roster.each do |section_id|
    errors << "section #{section_id} is not mapped" unless mapped.include?(section_id)
  end
  errors << "cohorts must preserve exact contiguous section_roster order" unless mapped == roster

  canonical_sizes = canonical_cohort_sizes(roster.length)
  unless canonical_sizes != :invalid && sizes == canonical_sizes
    errors << "capacity may not create extra cohorts; partition must match canonical sizes #{canonical_sizes.inspect}"
  end
  errors << "partition_basis must be roster_derived_not_capacity" unless document["partition_basis"].to_s == "roster_derived_not_capacity"

  carry_rows = Array(document["p3_to_v_carry"])
  phase = document["phase"].to_s
  if phase == "planning_provisional"
    errors << "planning_provisional must not declare P3-Ci to V-Ci carry" unless carry_rows.empty?
  else
    errors << "P3-Ci to V-Ci carry count must match cohort count" unless carry_rows.length == Array(document["cohorts"]).length
    Array(document["cohorts"]).each_with_index do |cohort, index|
      next unless cohort.is_a?(Hash)

      cohort_id = cohort["section_cohort_id"].to_s
      match = carry_rows[index]
      unless match.is_a?(Hash) && match["exact_carry"] == true
        errors << "P3-Ci to V-Ci cohort carry is missing or inexact for #{cohort_id}"
        next
      end
      unless match["section_cohort_id"].to_s == cohort_id &&
             match["planning_lane_id"].to_s == cohort["planning_lane_id"].to_s &&
             match["production_lane_id"].to_s == cohort["production_lane_id"].to_s &&
             Array(match["exact_section_ids"]).map(&:to_s) == Array(cohort["section_ids"]).map(&:to_s)
        errors << "P3-Ci to V-Ci cohort carry is missing or inexact for #{cohort_id}"
      end
      validate_pointer(root, errors, "p3_to_v_carry #{cohort_id} planning_handoff", match["planning_handoff"])
    end
  end
end

def validate_against_lineage(errors, map, lineage)
  return unless lineage.is_a?(Hash)

  errors << "lineage run does not match cohort map run" unless lineage["run"].to_s == map["run"].to_s
  errors << "lineage phase does not match cohort map phase" unless lineage["phase"].to_s == map["phase"].to_s
  lanes = Array(lineage["lanes"]).select { |lane| lane.is_a?(Hash) }
  Array(map["cohorts"]).each do |cohort|
    next unless cohort.is_a?(Hash)

    p3 = lanes.find { |lane| lane["lane_id"].to_s == cohort["planning_lane_id"].to_s }
    errors << "lineage is missing planning lane #{cohort['planning_lane_id']}" if p3.nil?
    if p3 && p3["section_cohort_id"].to_s != cohort["section_cohort_id"].to_s
      errors << "P3-Ci to V-Ci cohort carry is missing or inexact for #{cohort['section_cohort_id']}"
    end
    reviewer_lane = p3
    unless map["phase"].to_s == "planning_provisional"
      reviewer_lane = lanes.find { |lane| lane["lane_id"].to_s == cohort["production_lane_id"].to_s }
      errors << "lineage is missing production lane #{cohort['production_lane_id']}" if reviewer_lane.nil?
      if reviewer_lane && reviewer_lane["section_cohort_id"].to_s != cohort["section_cohort_id"].to_s
        errors << "P3-Ci to V-Ci cohort carry is missing or inexact for #{cohort['section_cohort_id']}"
      end
    end

    next unless reviewer_lane.is_a?(Hash)

    reviewer = cohort["cdd_reviewer"]
    next unless reviewer.is_a?(Hash)

    unless reviewer["session_id"].to_s == reviewer_lane["active_writer_session_id"].to_s
      errors << "cohort #{cohort['section_cohort_id']} CDD reviewer session must exact-bind the active writer of #{reviewer_lane['lane_id']}"
    end
    unless reviewer["logical_lineage_id"].to_s == reviewer_lane["logical_lineage_id"].to_s
      errors << "cohort #{cohort['section_cohort_id']} CDD reviewer logical lineage must exact-bind #{reviewer_lane['lane_id']}"
    end
  end
end

path = document_path(options[:root], argument)
unless path.file?
  warn "document is missing: #{argument}"
  exit 2
end

errors = []
document = load_document(path)
if document.nil?
  errors << "document must be a JSON or YAML object"
else
  errors.concat(schema_errors(path))
  if document["artifact_type"].to_s == "graph_section_cohort_map"
    validate_cohort_map(options[:root], errors, document)
  else
    errors << "artifact_type must be graph_section_cohort_map"
  end
end

if options[:lineage]
  begin
    lineage_path, _relative = repo_path(options[:root], options[:lineage])
    lineage = lineage_path.file? ? load_document(lineage_path) : nil
    if lineage.nil?
      errors << "lineage document is missing or invalid: #{options[:lineage]}"
    else
      validate_against_lineage(errors, document, lineage)
    end
  rescue ArgumentError => e
    errors << e.message
  end
end

status = errors.empty? ? "pass" : "fail"
partition =
  if document.is_a?(Hash)
    Array(document["cohorts"]).map { |cohort| Array(cohort.is_a?(Hash) ? cohort["section_ids"] : nil).length }
  else
    []
  end
payload = {
  "status" => status,
  "schema_version" => document.is_a?(Hash) ? document["schema_version"] : nil,
  "artifact_type" => document.is_a?(Hash) ? document["artifact_type"] : nil,
  "partition" => partition,
  "errors" => errors
}

if options[:json]
  puts JSON.pretty_generate(payload)
else
  if errors.empty?
    puts "graph-section-cohort-map: pass partition [#{partition.join(',')}]"
  else
    warn errors.join("\n")
  end
end

exit(errors.empty? ? 0 : 1)
