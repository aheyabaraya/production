#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "optparse"
require "pathname"
require "time"
require "yaml"

ROOT = Pathname.new(Dir.pwd).cleanpath
READY_SHARD_STATUSES = %w[ready_for_merge merged].freeze
STATUS_SEPARATOR = "[_\\s-]"
REVIEW_STATUS_PATTERN = /(?:^|#{STATUS_SEPARATOR})(?:needs_founder|needs.*review|rendered_needs|calibration|timing_test|hold|blocked)(?:$|#{STATUS_SEPARATOR})/i
REJECT_STATUS_PATTERN = /(?:^|#{STATUS_SEPARATOR})(?:rejected|failed|unrecoverable|mismatch)(?:$|#{STATUS_SEPARATOR})/i

def usage_error(message)
  warn "ERROR: #{message}"
  warn "usage: ruby scripts/idol_edit_readiness_worklist.rb RUN_ROOT [--edit-map PATH] [--output PATH] [--output-yaml PATH] [--write]"
  exit 2
end

def blank?(value)
  value.nil? || value.to_s.strip.empty?
end

def resolve_path(path)
  return nil if blank?(path)

  raw = Pathname.new(path.to_s)
  raw.absolute? ? raw.cleanpath : (ROOT + raw).cleanpath
end

def rel_path(path)
  resolved = resolve_path(path)
  return "" unless resolved

  resolved.relative_path_from(ROOT).to_s
rescue ArgumentError
  resolved.to_s
end

def readable_file?(path)
  resolved = resolve_path(path)
  resolved && File.file?(resolved.to_s)
end

def load_yaml_hash(path)
  resolved = resolve_path(path)
  usage_error("file is not readable: #{path}") unless resolved && File.file?(resolved.to_s)

  doc = YAML.load_file(resolved.to_s)
  return doc if doc.is_a?(Hash)

  usage_error("YAML root must be a mapping: #{path}")
rescue Psych::SyntaxError => e
  usage_error("YAML syntax error in #{path}: #{e.message}")
end

def status_kind(status)
  text = status.to_s
  return :rejected if text.match?(REJECT_STATUS_PATTERN)
  return :review if text.match?(REVIEW_STATUS_PATTERN)
  return :ready if READY_SHARD_STATUSES.include?(text)
  return :missing if blank?(text)

  :working
end

def action_for_status(status, scope:)
  case status_kind(status)
  when :rejected
    "Do not promote. Keep as rejected evidence unless a founder explicitly reopens this #{scope}."
  when :review
    "Founder/playback review or targeted QC is required before this #{scope} can become final truth."
  when :ready
    "Keep available for merge only after source-action, audio-marker, boundary, and geometry checks remain clean."
  when :missing
    "Record a status before automation can reason about this #{scope}."
  else
    "Treat as working material; do not promote until the owning readiness validator passes."
  end
end

def truncate(value, limit = 220)
  text = value.to_s.gsub(/\s+/, " ").strip
  return "" if text.empty?
  return text if text.length <= limit

  "#{text[0, limit - 3]}..."
end

def md_path(value)
  return "`(missing)`" if blank?(value)

  "`#{value}`"
end

def markdown_table_row(values)
  "| #{values.map { |value| value.to_s.gsub("|", "\\|") }.join(" | ")} |"
end

def status_counts(records)
  records.each_with_object(Hash.new(0)) do |record, counts|
    status = record.is_a?(Hash) ? record["status"].to_s : "invalid"
    counts[status.empty? ? "missing" : status] += 1
  end
end

def path_summary(paths)
  return "" unless paths.is_a?(Hash)

  preferred = %w[
    timing_test_preview
    proxy_preview
    recipe_fragment
    qc_contact_sheet
    branch_cut_qc_contact_sheet
    one_sec_qc_contact_sheet
    repair_review
    regeneration_prompt
    source_candidate_index
  ]
  preferred.map do |key|
    value = paths[key]
    next if blank?(value)

    "#{key}=#{value}"
  end.compact.join("; ")
end

options = {
  edit_map: nil,
  output: nil,
  output_yaml: nil,
  write: false
}

OptionParser.new do |parser|
  parser.on("--edit-map PATH") { |value| options[:edit_map] = value }
  parser.on("--output PATH") { |value| options[:output] = value }
  parser.on("--output-yaml PATH") { |value| options[:output_yaml] = value }
  parser.on("--write") { options[:write] = true }
end.parse!

run_arg = ARGV.shift
usage_error("RUN_ROOT is required") if blank?(run_arg)

run_path = resolve_path(run_arg)
usage_error("RUN_ROOT is not a directory: #{run_arg}") unless run_path && Dir.exist?(run_path.to_s)

edit_map_path = options[:edit_map] || rel_path(run_path + "04-edit-map.yaml")
edit_map = load_yaml_hash(edit_map_path)
output_path = options[:output] || rel_path(run_path + "review/04-edit-readiness-worklist-v1.md")
output_yaml_path = options[:output_yaml] || output_path.sub(/\.md\z/, ".yaml")

manual = edit_map["manual_adjustment_workflow"].is_a?(Hash) ? edit_map["manual_adjustment_workflow"] : {}
shards = edit_map.dig("section_workflow", "shards")
shards = shards.is_a?(Array) ? shards : []
rough_outputs = edit_map["rough_outputs"].is_a?(Array) ? edit_map["rough_outputs"] : []

top_status = edit_map["status"].to_s
current_final_recipe = manual["current_final_recipe"]
active_candidate_status = manual["active_candidate_status"].to_s
review_outputs = rough_outputs.select { |output| output.is_a?(Hash) && output["status"].to_s.match?(REVIEW_STATUS_PATTERN) }
rejected_outputs = rough_outputs.select { |output| output.is_a?(Hash) && output["status"].to_s.match?(REJECT_STATUS_PATTERN) }
nonready_shards = shards.select do |shard|
  shard.is_a?(Hash) && !READY_SHARD_STATUSES.include?(shard["status"].to_s)
end

blocking_reasons = []
blocking_reasons << "top-level edit status is rejected or non-final: `#{top_status}`" if top_status.match?(REJECT_STATUS_PATTERN)
if blank?(current_final_recipe)
  blocking_reasons << "`manual_adjustment_workflow.current_final_recipe` is blank."
elsif !readable_file?(current_final_recipe)
  blocking_reasons << "`manual_adjustment_workflow.current_final_recipe` is not readable: `#{current_final_recipe}`."
end
unless blank?(active_candidate_status)
  if active_candidate_status.match?(REVIEW_STATUS_PATTERN)
    blocking_reasons << "active candidate still needs review or is held: `#{active_candidate_status}`."
  elsif active_candidate_status.match?(REJECT_STATUS_PATTERN)
    blocking_reasons << "active candidate is rejected/failed: `#{active_candidate_status}`."
  end
end
blocking_reasons << "#{nonready_shards.length} section shard(s) are not ready for merge." unless nonready_shards.empty?
blocking_reasons << "#{review_outputs.length} rough output(s) still need founder/playback review or are timing tests." unless review_outputs.empty?
blocking_reasons << "#{rejected_outputs.length} rough output(s) are rejected evidence and must not be promoted." unless rejected_outputs.empty?

manual_fields = %w[
  current_final_recipe
  current_recut_recipe
  current_recut_preview
  current_recut_review
  current_intro_repair_recipe
  current_intro_repair_preview
  current_intro_repair_review
  regeneration_prompt_for_true_b01_repair
  front_intro_overhaul_goal
  front_intro_overhaul_generated_source_dir
  active_candidate_status
  latest_rejected_recipe
]

manual_field_records = manual_fields.map do |field|
  value = manual[field]
  status_note = blank?(value) ? "missing" : (readable_file?(value) ? "readable" : "recorded")
  record = {
    "field" => field,
    "status" => status_note
  }
  record["value"] = value.to_s unless blank?(value)
  record
end

shard_queue = shards.map do |shard|
  next unless shard.is_a?(Hash)

  paths = shard["paths"].is_a?(Hash) ? shard["paths"].reject { |_key, value| blank?(value) }.transform_values(&:to_s) : {}
  {
    "shard_id" => shard["shard_id"].to_s,
    "status" => shard["status"].to_s,
    "section_ids" => Array(shard["section_ids"]).map(&:to_s),
    "time_range" => truncate(shard["time_range"]),
    "cut_trigger" => truncate(shard["cut_trigger"]),
	    "source_action_marker" => truncate(shard["source_action_marker"]),
	    "story_flow_continuity" => truncate(shard["story_flow_continuity"]),
	    "space_visible_feeling_progression" => truncate(shard["space_visible_feeling_progression"]),
	    "directorial_transition_intent" => truncate(shard["directorial_transition_intent"]),
	    "audio_marker_alignment" => truncate(shard["audio_marker_alignment"]),
    "transition_in" => [
      truncate(shard.dig("transition_in", "audio_or_lyric_trigger")),
      truncate(shard.dig("transition_in", "body_or_formation_bridge"))
    ].reject(&:empty?).join(" / "),
    "transition_out" => [
      truncate(shard.dig("transition_out", "audio_or_lyric_trigger")),
      truncate(shard.dig("transition_out", "body_or_formation_bridge"))
    ].reject(&:empty?).join(" / "),
    "paths" => paths,
    "merge_checks" => Array(shard["merge_checks"]).map(&:to_s),
    "required_action" => action_for_status(shard["status"], scope: "shard")
  }
end.compact

rough_output_queue = rough_outputs.map do |output|
  next unless output.is_a?(Hash)

  review_or_qc = output["review"] || output["repair_review"] || output["verification_report"] || output["qc_contact_sheet"]
  {
    "output_id" => output["output_id"].to_s,
    "status" => output["status"].to_s,
    "duration_seconds" => output["duration_seconds"],
    "preview" => output["path"].to_s,
    "recipe" => output["recipe"].to_s,
    "review_or_qc" => review_or_qc.to_s,
    "qc_note" => truncate(output["qc_note"], 420),
    "action" => action_for_status(output["status"], scope: "rough output")
  }
end.compact

final_promotion_guard = [
  "`manual_adjustment_workflow.current_final_recipe` points to a readable source-clean recipe.",
  "The active candidate has an explicit founder/playback decision and is not a timing test, hold, or review-needed state.",
  "Failed or rejected shards are rebuilt, replaced, or explicitly retired in the edit map.",
	  "Rejected rough outputs remain evidence only and are not referenced as final edit truth.",
	  "Source-action markers, audio-marker alignment, story-flow continuity, space/visible-feeling progression, directorial transition intent, section boundary transitions, geometry consistency, and black-frame/UI-frame checks are recorded cleanly.",
  "The graph-engineering state checker reports `edit_map_readiness` as pass."
]

generated_at = Time.now.iso8601
worklist = {
  "schema_version" => "harness-blocker-worklist.v2",
  "generated_at" => generated_at,
  "run" => rel_path(run_path),
  "worklist_type" => "edit_readiness",
  "source_artifact" => edit_map_path,
  "status" => "worklist_only_not_a_pass_record",
  "summary" => {
    "edit_map_status" => top_status.empty? ? "missing" : top_status,
    "final_recipe_locked" => !blank?(current_final_recipe) && readable_file?(current_final_recipe),
    "active_candidate_status" => active_candidate_status.empty? ? "missing" : active_candidate_status,
    "section_shards" => shards.length,
    "nonready_shards" => nonready_shards.length,
    "rough_outputs" => rough_outputs.length,
    "review_or_timing_outputs" => review_outputs.length,
    "rejected_outputs" => rejected_outputs.length
  },
  "blocking_reasons" => blocking_reasons,
  "manual_fields" => manual_field_records,
  "section_shard_queue" => shard_queue,
  "rough_output_queue" => rough_output_queue,
  "final_promotion_guard" => final_promotion_guard,
  "automation_boundaries" => [
    "This worklist does not approve a final edit.",
    "Do not change shard status or promote previews from this worklist alone.",
    "Founder/playback decisions and source-clean recipe lock remain required before final readiness."
  ]
}

lines = []
lines << "# 04 Edit Readiness Worklist"
lines << ""
lines << "generated_at: #{generated_at}"
lines << "run: `#{rel_path(run_path)}`"
lines << "edit_map: `#{edit_map_path}`"
lines << "structured_worklist: `#{output_yaml_path}`"
lines << "status: `worklist_only_not_a_pass_record`"
lines << ""
lines << "This artifact expands the current `04-edit-map.yaml` blocker state into concrete review and repair work. It does not approve a final edit, change any shard status, or make any preview safe to promote."
lines << ""
lines << "## Summary"
lines << ""
lines << "- edit_map_status: `#{top_status.empty? ? 'missing' : top_status}`"
lines << "- final_recipe_locked: #{!blank?(current_final_recipe) && readable_file?(current_final_recipe) ? 'yes' : 'no'}"
lines << "- active_candidate_status: `#{active_candidate_status.empty? ? 'missing' : active_candidate_status}`"
lines << "- section_shards: #{shards.length}"
lines << "- nonready_shards: #{nonready_shards.length}"
lines << "- rough_outputs: #{rough_outputs.length}"
lines << "- review_or_timing_outputs: #{review_outputs.length}"
lines << "- rejected_outputs: #{rejected_outputs.length}"
lines << ""

lines << "## Blocking Reasons"
lines << ""
if blocking_reasons.empty?
  lines << "- No blocking reason was detected by this worklist script. Rerun `scripts/validate_edit_map_readiness.rb` before changing production status."
else
  blocking_reasons.each { |reason| lines << "- #{reason}" }
end
lines << ""

unless shards.empty?
  lines << "## Shard Status Counts"
  lines << ""
  lines << "| status | count |"
  lines << "| --- | ---: |"
  status_counts(shards).sort.each do |status, count|
    lines << markdown_table_row(["`#{status}`", count])
  end
  lines << ""
end

unless rough_outputs.empty?
  lines << "## Rough Output Status Counts"
  lines << ""
  lines << "| status | count |"
  lines << "| --- | ---: |"
  status_counts(rough_outputs).sort.each do |status, count|
    lines << markdown_table_row(["`#{status}`", count])
  end
  lines << ""
end

lines << "## Immediate Action Queue"
lines << ""
lines << "- Do not promote any current LOW edit preview as master truth while `edit_map_readiness` fails."
lines << "- Keep rejected previews as evidence only; do not reuse them as final recipe input unless the founder explicitly reopens a named output."
lines << "- Review the active candidate preview and review document before changing `manual_adjustment_workflow.current_final_recipe`."
lines << "- Lock `current_final_recipe` only after the selected recipe is readable, source-clean, and section boundary/audio-marker/source-action checks pass."
lines << "- Rerun `scripts/validate_edit_map_readiness.rb #{edit_map_path}` and the graph-engineering state checker after any status or recipe update."
lines << ""

lines << "## Manual Workflow Closeout Fields"
lines << ""
manual_field_records.each do |record|
  lines << "- `#{record['field']}`: `#{record['status']}` #{record['value'] ? md_path(record['value']) : ''}".rstrip
end
lines << ""

lines << "## Section Shard Queue"
lines << ""
if shards.empty?
  lines << "- No section shard records found."
  lines << ""
else
  shards.each do |shard|
    next unless shard.is_a?(Hash)

    shard_id = shard["shard_id"].to_s
    status = shard["status"].to_s
    lines << "### #{shard_id.empty? ? '(missing shard id)' : shard_id}"
    lines << ""
    lines << "- status: `#{status.empty? ? 'missing' : status}`"
    lines << "- section_ids: #{Array(shard['section_ids']).map { |id| "`#{id}`" }.join(', ')}"
    lines << "- time_range: #{truncate(shard['time_range'])}"
    lines << "- cut_trigger: #{truncate(shard['cut_trigger'])}"
    lines << "- source_action_marker: #{truncate(shard['source_action_marker'])}"
    lines << "- audio_marker_alignment: #{truncate(shard['audio_marker_alignment'])}"
    lines << "- transition_in: #{truncate(shard.dig('transition_in', 'audio_or_lyric_trigger'))} / #{truncate(shard.dig('transition_in', 'body_or_formation_bridge'))}"
    lines << "- transition_out: #{truncate(shard.dig('transition_out', 'audio_or_lyric_trigger'))} / #{truncate(shard.dig('transition_out', 'body_or_formation_bridge'))}"
    lines << "- paths: #{truncate(path_summary(shard['paths']), 520)}"
    lines << "- merge_checks: #{Array(shard['merge_checks']).map { |check| "`#{check}`" }.join(', ')}"
    lines << "- required_action: #{action_for_status(status, scope: 'shard')}"
    lines << ""
  end
end

lines << "## Rough Output Queue"
lines << ""
if rough_outputs.empty?
  lines << "- No rough output records found."
  lines << ""
else
  lines << "| output | status | duration | preview | recipe | review/qc | action |"
  lines << "| --- | --- | ---: | --- | --- | --- | --- |"
  rough_outputs.each do |output|
    next unless output.is_a?(Hash)

    review_or_qc = output["review"] || output["repair_review"] || output["verification_report"] || output["qc_contact_sheet"]
    lines << markdown_table_row([
      "`#{output['output_id']}`",
      "`#{output['status']}`",
      output["duration_seconds"],
      md_path(output["path"]),
      md_path(output["recipe"]),
      md_path(review_or_qc),
      action_for_status(output["status"], scope: "rough output")
    ])
  end
  lines << ""
  rough_outputs.each do |output|
    next unless output.is_a?(Hash)

    note = truncate(output["qc_note"], 420)
    next if note.empty?

    lines << "- `#{output['output_id']}` qc_note: #{note}"
  end
  lines << "" unless rough_outputs.empty?
end

lines << "## Final Promotion Guard"
lines << ""
lines << "Before any 04 state can be treated as final-ready, all of these must be true:"
lines << ""
final_promotion_guard.each { |guard| lines << "- #{guard}" }

report = lines.join("\n")

if options[:write]
  resolved_output = resolve_path(output_path)
  resolved_yaml_output = resolve_path(output_yaml_path)
  FileUtils.mkdir_p(resolved_output.dirname)
  FileUtils.mkdir_p(resolved_yaml_output.dirname)
  resolved_output.write(report, encoding: "utf-8")
  resolved_yaml_output.write(YAML.dump(worklist), encoding: "utf-8")
  puts "wrote #{rel_path(resolved_output)}"
  puts "wrote #{rel_path(resolved_yaml_output)}"
else
  puts report
end
