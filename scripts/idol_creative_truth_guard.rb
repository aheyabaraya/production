#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "optparse"
require "pathname"
require "set"

ROOT = Pathname.new(__dir__).join("..").expand_path
SCRIPT_GLOB = "*.{py,rb,js,mjs,cjs,ts}"
ACTIVE_STAGE_FILE_PATTERN = /(?:\A|[\\\/'"])(?:00A-song-lock|01-song-choreography-performance-mv-map|02A-master-storyboard|02B-prompt-packets|03V-video-prompt-manifest|04-edit-map|04FX-finishing-map|05-package)\.(?:ya?ml|json|md)(?:\z|["'])/i
RETIRED_STAGE_FILE_PATTERN = /(?:\A|[\\\/'"])(?:00-creative-nucleus|01A-track-visual-board|02-generation-map)\.(?:ya?ml|json|md)(?:\z|["'])/i
ACTIVE_CREATIVE_RESEARCH_PATTERN = %r{research/(?:front-planning-readiness|section-storyline|direction-composition-lock)[A-Za-z0-9._-]*\.(?:ya?ml|json|md)}i
RETIRED_CREATIVE_RESEARCH_PATTERN = %r{research/(?:mv-direction-reference-mining|reference-fragment-crop-lock)[A-Za-z0-9._-]*\.(?:ya?ml|json|md)}i
CREATIVE_REVIEW_PATTERN = %r{review/[A-Za-z0-9_./-]*(?:creative-context-review|creative-review|founder-review|storyboard-review)[A-Za-z0-9._-]*\.(?:ya?ml|json)}i
ANY_REVIEW_RECORD_PATTERN = %r{review/[A-Za-z0-9_./-]+\.(?:ya?ml|json)}i
SCRIPT_CLAIMED_CREATIVE_TARGET_PATTERN = /(?:model[_-]?authored|creative[_-]?(?:truth|review))[A-Za-z0-9._-]*\.(?:ya?ml|json)/i
RUN_OWNED_CREATIVE_STATE_PATTERN = %r{work/front_planning_integration/(?:canvas-state|planning-state|selected-route-state)\.(?:json|ya?ml)}i
WORK_PATH_PATTERN = /(?:["']work[\\\/]|["'][^"']*[\\\/]work[\\\/])/i
LITERAL_WRITE_CALL_PATTERN = /(?:\.(?:write(?:_text|_bytes)?|save|dump|replace|rename|move|copy)\s*\(|\b(?:File\.(?:write|binwrite|rename)|fs\.(?:writeFile|writeFileSync|renameSync|copyFileSync)|dump_yaml|write_yaml|write_json|atomic_write)\s*\()/i
CREATIVE_VERDICT_PATTERN = /["'](?:verdict|script_substitution_detected|creative_adequacy|creative_quality|founder_decision|professional_decision)["']\s*(?:\]|:|=)/i
SCRIPT_AUTHORSHIP_CLAIM_PATTERN = /["'](?:authoring_owner|authorship_actor|creative_values_origin)["']\s*(?:\]\s*=|:|=)\s*["'](?:human_or_model_authored|model[_ -]?authored(?:_02a)?|codex_model|grok_model)["']/i

options = {json: false}
OptionParser.new do |parser|
  parser.banner = "usage: ruby scripts/idol_creative_truth_guard.rb RUN_ROOT [--json]"
  parser.on("--json") { options[:json] = true }
end.parse!

argument = ARGV.shift
if argument.to_s.empty? || !ARGV.empty?
  warn "run root is required"
  exit 2
end

def resolve_run(raw)
  path = Pathname.new(raw.to_s)
  path = ROOT.join(path) unless path.absolute?
  path = path.expand_path
  relative = path.relative_path_from(ROOT).to_s
  raise ArgumentError, "run path escapes repository: #{raw}" if relative == ".." || relative.start_with?("../")
  raise ArgumentError, "run path must be under runs/: #{relative}" unless relative.start_with?("runs/")

  [path, relative]
rescue ArgumentError
  raise ArgumentError, "invalid run path: #{raw}"
end

def work_layer_path?(text)
  text.match?(WORK_PATH_PATTERN)
end

def canonical_kind(text)
  return "script_claimed_model_authored_candidate" if text.match?(SCRIPT_CLAIMED_CREATIVE_TARGET_PATTERN)
  return "run_owned_creative_planning_state" if text.match?(RUN_OWNED_CREATIVE_STATE_PATTERN)
  return nil if work_layer_path?(text)
  return "retired_stage_artifact" if text.match?(RETIRED_STAGE_FILE_PATTERN)
  return "retired_creative_research" if text.match?(RETIRED_CREATIVE_RESEARCH_PATTERN)
  return "canonical_creative_research" if text.match?(ACTIVE_CREATIVE_RESEARCH_PATTERN)
  return "human_or_model_creative_review" if text.match?(CREATIVE_REVIEW_PATTERN)
  return "canonical_stage_artifact" if text.match?(ACTIVE_STAGE_FILE_PATTERN)

  nil
end

def review_record?(text)
  !work_layer_path?(text) && text.match?(ANY_REVIEW_RECORD_PATTERN)
end

def write_to_variable?(text, variable)
  escaped = Regexp.escape(variable)
  receiver = /\b#{escaped}\s*\.\s*(?:write(?:_text|_bytes)?|open|save|dump|replace|rename|move|copy)\s*\(/i
  first_argument = /\b[A-Za-z0-9_.!?:]*(?:write|dump|save|serialize|materialize|emit|patch|repair)[A-Za-z0-9_.!?:]*\s*\(\s*#{escaped}\b/im
  file_open = /\b(?:File\.)?open\s*\(\s*#{escaped}\s*,\s*["'][wax+]/im
  second_argument = /\b(?:copy|copy2|move|rename|replace)\s*\([^,]+,\s*#{escaped}\b/im
  js_write = /\b(?:fs\.)?(?:writeFile|writeFileSync|renameSync|copyFileSync)\s*\(\s*#{escaped}\b/im
  text.match?(receiver) || text.match?(first_argument) || text.match?(file_open) || text.match?(second_argument) || text.match?(js_write)
end

def literal_canonical_write?(text)
  return false unless canonical_kind(text)

  text.match?(LITERAL_WRITE_CALL_PATTERN) || text.match?(/\.open\s*\([^)]*["'][wax+]/i)
end

def line_number(text, pattern)
  match = text.match(pattern)
  return nil unless match

  text[0...match.begin(0)].count("\n") + 1
end

begin
  run_path, run_relative = resolve_run(argument)
rescue ArgumentError => e
  warn e.message
  exit 2
end

unless run_path.directory?
  warn "run root is missing: #{run_relative}"
  exit 2
end

offenders = []
script_paths = Dir.glob(run_path.join("work", "**", SCRIPT_GLOB).to_s).sort
script_paths.each do |raw_path|
  path = Pathname.new(raw_path)
  text = path.read(encoding: "UTF-8")
  lines = text.lines
  variables = {}
  review_variables = Set.new

  lines.each_with_index do |line, index|
    match = line.match(/^\s*(?:(?:const|let|var)\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$/)
    next unless match

    statement = match[2]
    kind = canonical_kind(statement)
    variables[match[1]] = {kind: kind, assignment_line: index + 1} if kind
    review_variables << match[1] if review_record?(statement)
  end

  # Follow simple aliases such as TARGET = PATH after the concrete path assignment.
  3.times do
    lines.each_with_index do |line, index|
      match = line.match(/^\s*(?:(?:const|let|var)\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*([A-Za-z_][A-Za-z0-9_]*)\s*$/)
      next unless match && variables.key?(match[2])

      variables[match[1]] ||= variables[match[2]].merge(assignment_line: index + 1)
    end
  end

  reasons = []
  variables.each do |variable, metadata|
    next unless write_to_variable?(text, variable)

    reason = case metadata[:kind]
             when "script_claimed_model_authored_candidate"
               "script_claimed_model_authored_output"
             when "run_owned_creative_planning_state"
               "run_owned_creative_state_write"
             when "retired_stage_artifact", "retired_creative_research"
               "retired_active_authoring_target"
             else
               "run_owned_canonical_write_target"
             end
    reasons << {
      "reason" => reason,
      "target_kind" => metadata[:kind],
      "variable" => variable,
      "assignment_line" => metadata[:assignment_line]
    }
  end

  lines.each_with_index do |line, index|
    next unless literal_canonical_write?(line)

    reasons << {
      "reason" => "literal_canonical_write_target",
      "target_kind" => canonical_kind(line),
      "line" => index + 1
    }
  end

  if text.match?(CREATIVE_VERDICT_PATTERN)
    written_review_variables = review_variables.select { |variable| write_to_variable?(text, variable) }
    written_review_variables.each do |variable|
      reasons << {
        "reason" => "script_authored_creative_review_verdict",
        "target_kind" => "human_or_model_creative_review",
        "variable" => variable,
        "line" => line_number(text, CREATIVE_VERDICT_PATTERN)
      }
    end
  end

  if text.match?(SCRIPT_AUTHORSHIP_CLAIM_PATTERN) && reasons.any?
    reasons << {
      "reason" => "script_claimed_model_authorship",
      "target_kind" => "creative_authorship",
      "line" => line_number(text, SCRIPT_AUTHORSHIP_CLAIM_PATTERN)
    }
  end

  reasons.uniq!
  next if reasons.empty?

  offenders << {
    "path" => path.relative_path_from(ROOT).to_s,
    "reasons" => reasons
  }
rescue Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError => e
  offenders << {
    "path" => path.relative_path_from(ROOT).to_s,
    "reasons" => [{"reason" => "unreadable_script_source", "detail" => e.message}]
  }
end

result = {
  "status" => offenders.empty? ? "pass" : "fail",
  "run" => run_relative,
  "scripts_scanned" => script_paths.length,
  "offender_count" => offenders.length,
  "offenders" => offenders,
  "policy" => {
    "canonical_creative_writers" => "human_or_assigned_model_only",
    "run_owned_helper_output" => "diagnostic_candidates_under_work_only",
    "creative_review_verdicts" => "human_or_assigned_model_only"
  }
}

if options[:json]
  puts JSON.pretty_generate(result)
elsif offenders.empty?
  puts "OK: #{script_paths.length} run-owned helper(s) do not write canonical creative truth"
else
  offenders.each do |row|
    reason_labels = row["reasons"].map { |reason| reason["reason"] }.uniq.join(", ")
    warn "ERROR: #{row['path']}: #{reason_labels}"
  end
end

exit(offenders.empty? ? 0 : 1)
