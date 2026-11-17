#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "optparse"
require "pathname"
require "time"
require "yaml"

ROOT = Pathname.new(Dir.pwd).cleanpath

def usage_error(message)
  warn "ERROR: #{message}"
  warn "usage: ruby scripts/idol_harness_founder_gate_packet.rb RUN_ROOT [--next-unit PATH] [--output-yaml PATH] [--output-md PATH] [--write]"
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

def load_yaml_hash(path)
  resolved = resolve_path(path)
  return {} unless resolved && File.file?(resolved.to_s)

  doc = YAML.load_file(resolved.to_s)
  doc.is_a?(Hash) ? doc : {}
rescue Psych::SyntaxError => e
  usage_error("YAML syntax error in #{path}: #{e.message}")
end

def latest_next_unit(content_id)
  pattern = (ROOT + "automation/next-units/*-#{content_id}-harness-next-unit.yaml").to_s
  matches = Dir.glob(pattern).select { |path| File.file?(path) }
  return nil if matches.empty?

  matches.max_by { |path| [File.mtime(path), path] }
end

def decision_options(section_range, next_local_section, allow_continue_local = false)
  default_route = "grok_manual_drive_mirror"
  options = [
    {
      "id" => "approve_front_chunk_generation",
      "label" => "Approve #{section_range} generation/playback route",
      "effect" => "#{section_range} may be sent through an explicitly approved video-generation route such as #{default_route}; generated clips still need playback review before any QA pass.",
      "requires_explicit_approval" => true,
      "allows_paid_generation" => true,
      "allows_external_execution" => true,
      "continues_local_qa" => false,
      "marks_section_qa_pass" => false,
      "next_action" => "Generate or collect the #{section_range} clips through the approved route (default route name: #{default_route}), then update only generation_playback_probe evidence after playback review."
    },
    {
      "id" => "review_or_refine_prompts_only",
      "label" => "Review/refine prompts only",
      "effect" => "No paid generation or external execution is approved. Codex or approved review material may refine selected prompts while section QA remains partial.",
      "requires_explicit_approval" => false,
      "allows_paid_generation" => false,
      "allows_external_execution" => false,
      "continues_local_qa" => false,
      "marks_section_qa_pass" => false,
      "next_action" => "Record the selected prompt IDs or notes, patch only the chosen prompt files, then regenerate the 03V worklist and focused queue."
    },
    {
      "id" => "hold_front_gate",
      "label" => "Hold this front gate",
      "effect" => "No downstream state changes. The current next unit stays founder_input_needed.",
      "requires_explicit_approval" => false,
      "allows_paid_generation" => false,
      "allows_external_execution" => false,
      "continues_local_qa" => false,
      "marks_section_qa_pass" => false,
      "next_action" => "Keep #{section_range} partial and keep the focused 03V gate as the next unit."
    }
  ]
  if allow_continue_local && !next_local_section.to_s.empty?
    options.insert(2, {
      "id" => "continue_local_next_section",
      "label" => "Continue local QA on #{next_local_section}",
      "effect" => "No paid generation or external execution is approved. Codex continues local source/prompt QA on #{next_local_section} before any playback route is chosen.",
      "requires_explicit_approval" => false,
      "allows_paid_generation" => false,
      "allows_external_execution" => false,
      "continues_local_qa" => true,
      "marks_section_qa_pass" => false,
      "next_action" => "Open #{next_local_section} in the 03V section-QA worklist and close only local source/prompt checks."
    })
  end
  options
end

def decision_needed_text(section_range, next_local_section, allow_continue_local = false)
  choices = ["approve a generation/playback route such as grok_manual_drive_mirror", "review/refine prompts only"]
  choices << "continue local QA on #{next_local_section}" if allow_continue_local && !next_local_section.to_s.empty?
  choices << "hold the gate"
  "Choose one route for #{section_range}: #{choices.join(', ')}."
end

def front_gate_from_action_queue(next_unit, action_queue)
  Array(action_queue["queues"]).each do |queue_item|
    next unless queue_item.is_a?(Hash)

    Array(queue_item["next_units"]).each do |unit|
      next unless unit.is_a?(Hash)
      next unless unit["id"].to_s.start_with?("front_03v_playback_gate:")
      next unless unit["requires_founder_decision"] == true

      return {
        "schema_version" => next_unit["schema_version"].to_s,
        "generated_at" => next_unit["generated_at"].to_s,
        "run" => next_unit["run"].to_s,
        "album_key" => next_unit["album_key"].to_s,
        "title_key" => next_unit["title_key"].to_s,
        "status" => "founder_input_needed",
        "source_action_queue" => next_unit["source_action_queue"].to_s,
        "selected_unit_id" => unit["id"].to_s,
        "selected_unit_status" => unit["status"].to_s,
        "owner" => "founder",
        "source_artifact" => queue_item["source_artifact"].to_s,
        "worklist_artifact" => queue_item["worklist_artifact"].to_s,
        "action" => unit["action"].to_s,
        "requires_founder_decision" => true,
        "forbidden_actions" => Array(queue_item["forbidden_actions"]).map(&:to_s),
        "details" => unit["details"].is_a?(Hash) ? unit["details"] : {},
        "reason_for_selection" => "front contiguous 03V section batch remains pending for playback/generation approval while local QA continues",
        "automation_boundaries" => Array(action_queue["automation_boundaries"]).map(&:to_s)
      }
    end
  end
  {}
end

def build_packet(run_rel, next_unit_path, next_unit, action_queue)
  gate_source = next_unit
  selected_unit_id = gate_source["selected_unit_id"].to_s
  unless selected_unit_id.start_with?("front_03v_playback_gate:")
    gate_source = front_gate_from_action_queue(next_unit, action_queue)
    selected_unit_id = gate_source["selected_unit_id"].to_s
  end
  unless selected_unit_id.start_with?("front_03v_playback_gate:")
    usage_error("next unit is not a front 03V playback gate: #{selected_unit_id}")
  end
  unless gate_source["requires_founder_decision"] == true && gate_source["owner"].to_s == "founder"
    usage_error("next unit must be a founder-required gate")
  end

  details = gate_source["details"].is_a?(Hash) ? gate_source["details"] : {}
  section_range = details["section_range"].to_s
  section_range = selected_unit_id.split(":", 2).last.to_s if section_range.empty?
  section_ids = Array(details["section_ids"]).map(&:to_s)
  packet_count = details["packet_count"].to_i
  remaining_check = details["remaining_check"].to_s
  next_local_section = details["next_local_section"].to_s
  allow_continue_local = details["next_local_continuation_allowed"] == true

  source_summary = "#{section_range} has #{section_ids.length} local-ready section(s) and #{packet_count} packet(s); only #{remaining_check} remains before any section can become pass."
  worklist_command = "ruby scripts/idol_video_prompt_section_qa_worklist.rb #{run_rel}"
  worklist_command += " --qa #{gate_source['source_artifact']}" unless blank?(gate_source["source_artifact"])
  worklist_command += " --write"

  {
    "schema_version" => "harness-founder-gate.v1",
    "generated_at" => Time.now.iso8601,
    "run" => run_rel,
    "album_key" => gate_source["album_key"].to_s,
    "title_key" => gate_source["title_key"].to_s,
    "gate_id" => selected_unit_id.tr(":", "_"),
    "gate_type" => "03v_front_playback_generation",
    "status" => "founder_input_needed",
    "source_next_unit" => next_unit_path.to_s,
    "source_action_queue" => gate_source["source_action_queue"].to_s,
    "source_worklist" => gate_source["worklist_artifact"].to_s,
    "source_artifact" => gate_source["source_artifact"].to_s,
    "selected_unit" => {
      "id" => selected_unit_id,
      "status" => gate_source["selected_unit_status"].to_s,
      "action" => gate_source["action"].to_s,
      "reason" => gate_source["reason_for_selection"].to_s
    },
    "section_range" => section_range,
    "section_ids" => section_ids,
    "packet_count" => packet_count,
    "current_local_status" => {
      "local_ready_sections" => section_ids.dup,
      "remaining_check" => remaining_check,
      "next_local_section" => next_local_section,
      "next_local_continuation_allowed" => allow_continue_local,
      "source_summary" => source_summary
    },
    "decision_needed" => decision_needed_text(section_range, next_local_section, allow_continue_local),
    "allowed_decisions" => decision_options(section_range, next_local_section, allow_continue_local),
    "forbidden_actions" => Array(gate_source["forbidden_actions"]).map(&:to_s) + [
      "Do not mark #{section_range} section QA pass until generated playback evidence exists and is reviewed.",
      "Do not extend approval beyond #{section_range} unless the founder names that wider scope.",
      "Do not use this gate packet as upload, publish, Drive mutation, or platform API approval."
    ],
    "automation_boundaries" => Array(gate_source["automation_boundaries"]).map(&:to_s),
    "refresh_commands" => [
      worklist_command,
      "ruby scripts/idol_03v_generated_playback_intake.rb #{run_rel} --write",
      "ruby scripts/idol_03v_playback_review_worklist.rb #{run_rel} --write",
      "ruby scripts/idol_03v_playback_decision_sheet.rb #{run_rel} --write",
      "ruby scripts/idol_harness_action_queue.rb #{run_rel} --only-check video_prompt_section_qa_readiness --write",
      "ruby scripts/idol_harness_next_unit.rb #{run_rel} --write",
      "ruby scripts/idol_harness_founder_gate_packet.rb #{run_rel} --write",
      "ruby scripts/idol_harness_current_next.rb #{run_rel} --write",
      "ruby scripts/validate_03v_front_playback_gate.rb #{run_rel}"
    ]
  }
end

def build_markdown(packet)
  lines = []
  lines << "# IDOL Graph Engineering Founder Gate"
  lines << ""
  lines << "generated_at: #{packet['generated_at']}"
  lines << "run: `#{packet['run']}`"
  lines << "gate: `#{packet['gate_id']}`"
  lines << "status: `#{packet['status']}`"
  lines << ""
  lines << "## Decision Needed"
  lines << ""
  lines << packet["decision_needed"]
  lines << ""
  lines << "## Current Local Status"
  lines << ""
  current = packet["current_local_status"]
  lines << "- section_range: `#{packet['section_range']}`"
  lines << "- sections: #{packet['section_ids'].join(', ')}"
  lines << "- packet_count: #{packet['packet_count']}"
  lines << "- remaining_check: `#{current['remaining_check']}`"
  lines << "- next_local_section: `#{current['next_local_section']}`"
  lines << "- next_local_continuation_allowed: `#{current['next_local_continuation_allowed']}`"
  lines << "- summary: #{current['source_summary']}"
  lines << ""
  lines << "## Allowed Decisions"
  lines << ""
  packet["allowed_decisions"].each do |decision|
    flags = []
    flags << "paid=#{decision['allows_paid_generation']}"
    flags << "external=#{decision['allows_external_execution']}"
    flags << "continue_local=#{decision['continues_local_qa']}"
    lines << "### #{decision['label']}"
    lines << ""
    lines << "- id: `#{decision['id']}`"
    lines << "- flags: #{flags.join(', ')}"
    lines << "- effect: #{decision['effect']}"
    lines << "- next_action: #{decision['next_action']}"
    lines << ""
  end
  lines << "## Sources"
  lines << ""
  lines << "- next_unit: `#{packet['source_next_unit']}`"
  lines << "- action_queue: `#{packet['source_action_queue']}`"
  lines << "- worklist: `#{packet['source_worklist']}`"
  lines << "- source_artifact: `#{packet['source_artifact']}`"
  lines << ""
  lines << "## Forbidden Actions"
  lines << ""
  packet["forbidden_actions"].each { |action| lines << "- #{action}" }
  lines << ""
  lines << "## Refresh Commands"
  lines << ""
  packet["refresh_commands"].each { |command| lines << "- `#{command}`" }
  lines.join("\n")
end

options = {
  next_unit: nil,
  output_yaml: nil,
  output_md: nil,
  write: false
}

OptionParser.new do |parser|
  parser.on("--next-unit PATH") { |value| options[:next_unit] = value }
  parser.on("--output-yaml PATH") { |value| options[:output_yaml] = value }
  parser.on("--output-md PATH") { |value| options[:output_md] = value }
  parser.on("--write") { options[:write] = true }
end.parse!

run_arg = ARGV.shift
usage_error("RUN_ROOT is required") if blank?(run_arg)

run_path = resolve_path(run_arg)
usage_error("RUN_ROOT is not a directory: #{run_arg}") unless run_path && Dir.exist?(run_path.to_s)

run_rel = rel_path(run_path)
content_id = run_path.basename.to_s
date_prefix = Time.now.strftime("%Y-%m-%d")
next_unit_path = rel_path(options[:next_unit] || latest_next_unit(content_id))
usage_error("next-unit artifact could not be inferred") if blank?(next_unit_path)

next_unit = load_yaml_hash(next_unit_path)
action_queue_path = next_unit["source_action_queue"].to_s
action_queue = load_yaml_hash(action_queue_path)
usage_error("source action queue is not readable: #{action_queue_path}") if action_queue.empty?

packet = build_packet(run_rel, next_unit_path, next_unit, action_queue)
range_slug = packet["section_range"].downcase
output_yaml = options[:output_yaml] || "automation/founder-gates/#{date_prefix}-#{content_id}-03v-front-gate-#{range_slug}.yaml"
output_md = options[:output_md] || "automation/founder-gates/#{date_prefix}-#{content_id}-03v-front-gate-#{range_slug}.md"

yaml_text = YAML.dump(packet)
md_text = build_markdown(packet)

if options[:write]
  yaml_path = resolve_path(output_yaml)
  md_path = resolve_path(output_md)
  FileUtils.mkdir_p(yaml_path.dirname)
  FileUtils.mkdir_p(md_path.dirname)
  yaml_path.write(yaml_text, encoding: "utf-8")
  md_path.write(md_text, encoding: "utf-8")
  puts "wrote #{rel_path(yaml_path)}"
  puts "wrote #{rel_path(md_path)}"
else
  puts yaml_text
end
