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
  warn "usage: ruby scripts/idol_harness_next_unit.rb RUN_ROOT [--action-queue PATH] [--output-yaml PATH] [--output-md PATH] [--write]"
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

def latest_action_queue(content_id)
  patterns = [
    "automation/action-queues/*-#{content_id}-03v-action-queue.yaml",
    "automation/action-queues/*-#{content_id}-harness-action-queue.yaml"
  ]
  matches = patterns.flat_map do |pattern|
    Dir.glob((ROOT + pattern).to_s).select { |path| File.file?(path) }
  end
  return nil if matches.empty?

  matches.max_by { |path| [File.mtime(path), path] }
end

def actionable_status?(status)
  !%w[pass passed complete completed ready ready_for_merge merged resolved accepted].include?(status.to_s.strip.downcase)
end

def founder_status(decision)
  decision["status"].to_s.match?(/needed|pending|not_approved|blocked|review/i)
end

def next_unit_candidates(queue)
  candidates = []
  Array(queue["queues"]).sort_by { |item| item["priority"].to_i }.each do |item|
    Array(item["next_units"]).each_with_index do |unit, index|
      next unless unit.is_a?(Hash)
      next unless actionable_status?(unit["status"])

      candidates << {
        "queue" => item,
        "unit" => unit,
        "order" => index + 1
      }
    end
  end
  candidates
end

def founder_decision_candidates(queue)
  Array(queue["founder_decisions_needed"]).each_with_index.map do |decision, index|
    next unless decision.is_a?(Hash)
    next unless founder_status(decision)

    {
      "queue" => {
        "id" => "founder_decisions_needed",
        "priority" => 99,
        "owner" => "founder",
        "source_check" => "",
        "source_artifact" => "",
        "worklist_artifact" => "",
        "next_command" => "",
        "founder_gate" => decision["gate"].to_s,
        "forbidden_actions" => [
          "Do not infer this decision from surrounding files.",
          "Do not advance paid generation, publishing, external sync, or final lock state without explicit founder approval."
        ]
      },
      "unit" => {
        "id" => decision["id"].to_s,
        "unit_type" => "founder_decision",
        "status" => decision["status"].to_s,
        "action" => decision["decision"].to_s,
        "requires_founder_decision" => true,
        "source_ref" => "founder_decisions_needed.#{decision['id']}",
        "details" => {
          "gate" => decision["gate"].to_s
        }
      },
      "order" => index + 1
    }
  end.compact
end

def section_key_for(unit)
  unit["id"].to_s.split(":", 2).last.to_s
end

def playback_only_section?(candidate)
  unit = candidate["unit"]
  return false unless unit.is_a?(Hash)
  return false unless unit["unit_type"].to_s == "section_qa"
  return false unless unit["requires_founder_decision"] == true
  return false unless unit["status"].to_s == "partial"

  details = unit["details"].is_a?(Hash) ? unit["details"] : {}
  Array(details["first_unfinished_checks"]).map(&:to_s) == ["generation_playback_probe"]
end

def default_front_gate_min_candidates(candidates)
  first_key = section_key_for(Array(candidates).first&.dig("unit") || {})
  first_key == "S00" ? 4 : 3
end

def front_section_playback_gate_candidate(candidates)
  video_candidates = candidates.select do |candidate|
    candidate.dig("queue", "id").to_s == "close_03v_section_qa" &&
      candidate.dig("unit", "unit_type").to_s == "section_qa"
  end.sort_by { |candidate| candidate["order"].to_i }

  prefix = []
  video_candidates.each do |candidate|
    break unless playback_only_section?(candidate)

    prefix << candidate
  end

  min_sections = default_front_gate_min_candidates(video_candidates)
  return nil if prefix.length < min_sections

  section_keys = prefix.map { |candidate| section_key_for(candidate["unit"]) }
  next_local = video_candidates[prefix.length]
  packet_count = prefix.sum do |candidate|
    details = candidate.dig("unit", "details").is_a?(Hash) ? candidate.dig("unit", "details") : {}
    details["packet_count"].to_i
  end

  first = prefix.first
  gate_queue = first["queue"].merge(
    "owner" => "founder",
    "founder_gate" => "Founder approval is required before paid video generation, external execution, or marking generated playback accepted."
  )
  {
    "queue" => gate_queue,
    "unit" => {
      "id" => "front_03v_playback_gate:#{section_keys.first}-#{section_keys.last}",
      "unit_type" => "local_followup",
      "status" => "needs_founder",
      "action" => "#{section_keys.first}-#{section_keys.last} local source/prompt QA is closed; choose the playback/generation route for this front chunk before continuing the next chunk.",
      "requires_founder_decision" => true,
      "source_ref" => "section_queue.#{section_keys.first}-#{section_keys.last}",
      "details" => {
        "section_ids" => section_keys,
        "min_sections" => min_sections,
        "section_count" => section_keys.length,
        "packet_count" => packet_count,
        "remaining_check" => "generation_playback_probe",
        "next_local_section" => next_local ? section_key_for(next_local["unit"]) : ""
      }
    },
    "order" => first["order"].to_i
  }
end

def continue_local_front_gate_decision?(queue)
  decision = queue["active_founder_gate_decision"].is_a?(Hash) ? queue["active_founder_gate_decision"] : {}
  decision["schema_version"].to_s == "harness-founder-decision.v1" &&
    decision["status"].to_s == "active" &&
    decision["decision_id"].to_s == "continue_local_next_section" &&
    decision["continues_local_qa"] == true &&
    decision["allows_paid_generation"] == false &&
    decision["allows_external_execution"] == false &&
    decision["marks_section_qa_pass"] == false
end

def approve_generation_front_gate_decision?(queue)
  decision = queue["active_founder_gate_decision"].is_a?(Hash) ? queue["active_founder_gate_decision"] : {}
  decision["schema_version"].to_s == "harness-founder-decision.v1" &&
    decision["status"].to_s == "active" &&
    decision["decision_id"].to_s == "approve_front_chunk_generation" &&
    decision["allows_paid_generation"] == true &&
    decision["allows_external_execution"] == true &&
    decision["continues_local_qa"] == false &&
    decision["marks_section_qa_pass"] == false &&
    !decision["approved_execution_route"].to_s.empty?
end

def local_candidate_for_front_gate(candidates, front_gate)
  details = front_gate.dig("unit", "details").is_a?(Hash) ? front_gate.dig("unit", "details") : {}
  next_local_section = details["next_local_section"].to_s
  return nil if next_local_section.empty?

  candidates.find do |candidate|
    candidate.dig("unit", "requires_founder_decision") != true &&
      candidate.dig("unit", "unit_type").to_s == "section_qa" &&
      section_key_for(candidate["unit"]) == next_local_section
  end
end

def select_candidate(queue)
  candidates = next_unit_candidates(queue)
  skip_front_gate = continue_local_front_gate_decision?(queue)
  approved_generation = approve_generation_front_gate_decision?(queue)
  active_decision = queue["active_founder_gate_decision"].is_a?(Hash) ? queue["active_founder_gate_decision"] : {}
  allow_default_local_continuation = active_decision.empty?
  if approved_generation
    approved = candidates.find do |candidate|
      candidate.dig("unit", "id").to_s.start_with?("prepare_03v_generation_playback:") &&
        candidate.dig("unit", "requires_founder_decision") == false
    end
    return [approved, "founder approved the front 03V generation/playback route; selecting the approved route handoff unit"] if approved
  end
  unless skip_front_gate
    explicit_front_gate = candidates.find do |candidate|
      candidate.dig("unit", "id").to_s.start_with?("front_03v_playback_gate:") &&
        candidate.dig("unit", "requires_founder_decision") == true
    end
    if explicit_front_gate
      local_after_gate = allow_default_local_continuation ? local_candidate_for_front_gate(candidates, explicit_front_gate) : nil
      if local_after_gate
        return [local_after_gate, "front contiguous 03V section batch remains pending for playback/generation approval; selecting the next local 03V section because local QA continuation does not approve generation, external execution, or QA pass"]
      end
      return [explicit_front_gate, "front contiguous 03V section batch is local-ready and should stop at playback/generation gate before broad QA continues"]
    end

    front_gate = front_section_playback_gate_candidate(candidates)
    if front_gate
      local_after_gate = allow_default_local_continuation ? local_candidate_for_front_gate(candidates, front_gate) : nil
      if local_after_gate
        return [local_after_gate, "front contiguous 03V section batch remains pending for playback/generation approval; selecting the next local 03V section because local QA continuation does not approve generation, external execution, or QA pass"]
      end
      return [front_gate, "front contiguous 03V section batch is local-ready and should stop at playback/generation gate before broad QA continues"]
    end
  end

  local = candidates.reject { |candidate| candidate.dig("unit", "requires_founder_decision") == true }
  if skip_front_gate
    next_local_section = queue.dig("active_founder_gate_decision", "next_local_section").to_s
    selected = local.find { |candidate| section_key_for(candidate["unit"]) == next_local_section } || local.first
    return [selected, "founder chose continue_local_next_section for the front 03V gate; selecting the next local 03V section"] if selected
  end
  return [local.first, "first non-founder next unit from the highest-priority blocker queue"] unless local.empty?

  return [candidates.first, "first founder-gated next unit from the highest-priority blocker queue"] unless candidates.empty?

  founder_candidates = founder_decision_candidates(queue)
  return [founder_candidates.first, "no local next units remain; first recorded founder decision is required"] unless founder_candidates.empty?

  [nil, "action queue has no actionable next_units or founder decisions"]
end

def empty_state_summary
  {
    "overall_status" => "",
    "pass" => 0,
    "fail" => 0,
    "missing" => 0,
    "blocking" => 0
  }
end

def video_only_queue?(queue)
  queues = Array(queue["queues"])
  queues.length == 1 && queues.first["source_check"].to_s == "video_prompt_section_qa_readiness"
end

def video_source_qa_command(run_rel, queue)
  source = Array(queue["queues"]).find do |item|
    item.is_a?(Hash) && item["source_check"].to_s == "video_prompt_section_qa_readiness"
  end&.dig("source_artifact").to_s
  command = "ruby scripts/idol_video_prompt_section_qa_worklist.rb #{run_rel}"
  command += " --qa #{source}" unless source.empty?
  "#{command} --write"
end

def next_unit_refresh_commands(run_rel, action_queue_path, queue)
  if video_only_queue?(queue)
    commands = [
      video_source_qa_command(run_rel, queue),
      "ruby scripts/idol_03v_generated_playback_intake.rb #{run_rel} --write",
      "ruby scripts/idol_03v_playback_review_worklist.rb #{run_rel} --write",
      "ruby scripts/idol_03v_playback_decision_sheet.rb #{run_rel} --write",
      "ruby scripts/idol_harness_action_queue.rb #{run_rel} --only-check video_prompt_section_qa_readiness --write",
      "ruby scripts/idol_harness_next_unit.rb #{run_rel} --write"
    ]
    commands << "ruby scripts/idol_harness_founder_gate_packet.rb #{run_rel} --write" unless continue_local_front_gate_decision?(queue)
    commands << "ruby scripts/idol_harness_current_next.rb #{run_rel} --write"
    commands << "ruby scripts/validate_03v_front_playback_gate.rb #{run_rel}"
    return commands
  end

  [
    video_source_qa_command(run_rel, queue),
    "ruby scripts/idol_harness_action_queue.rb #{run_rel} --write",
    "ruby scripts/idol_harness_next_unit.rb #{run_rel} --write"
  ]
end

def next_unit_payload(queue, action_queue_path, run_rel)
  candidate, reason = select_candidate(queue)
  summary = queue["state_summary"].is_a?(Hash) ? queue["state_summary"] : empty_state_summary

  if candidate.nil?
    return {
      "schema_version" => "harness-next-unit.v1",
      "generated_at" => Time.now.iso8601,
      "run" => run_rel,
      "album_key" => queue["album_key"].to_s,
      "title_key" => queue["title_key"].to_s,
      "status" => queue.empty? ? "action_queue_missing_or_empty" : "no_actionable_units",
      "source_action_queue" => action_queue_path.to_s,
      "queue_status" => queue["status"].to_s,
      "state_summary" => summary,
      "selected_queue_id" => "",
      "selected_unit_id" => "",
      "selected_unit_type" => "",
      "selected_unit_status" => "",
      "priority" => 0,
      "selection_order" => 0,
      "owner" => "",
      "source_check" => "",
      "source_artifact" => "",
      "worklist_artifact" => "",
      "unit_source_ref" => "",
      "action" => "",
      "validate_after" => "",
      "requires_founder_decision" => false,
      "founder_gate" => "",
      "forbidden_actions" => [],
      "details" => {},
      "reason_for_selection" => reason,
      "automation_boundaries" => Array(queue["automation_boundaries"]).map(&:to_s),
      "refresh_commands" => next_unit_refresh_commands(run_rel, action_queue_path, queue)
    }
  end

  item = candidate["queue"]
  unit = candidate["unit"]
  founder_required = unit["requires_founder_decision"] == true
  {
    "schema_version" => "harness-next-unit.v1",
    "generated_at" => Time.now.iso8601,
    "run" => run_rel,
    "album_key" => queue["album_key"].to_s,
    "title_key" => queue["title_key"].to_s,
    "status" => founder_required ? "founder_input_needed" : "selected",
    "source_action_queue" => action_queue_path.to_s,
    "queue_status" => queue["status"].to_s,
    "state_summary" => summary,
    "selected_queue_id" => item["id"].to_s,
    "selected_unit_id" => unit["id"].to_s,
    "selected_unit_type" => unit["unit_type"].to_s,
    "selected_unit_status" => unit["status"].to_s,
    "priority" => item["priority"].to_i,
    "selection_order" => candidate["order"].to_i,
    "owner" => founder_required ? "founder" : item["owner"].to_s,
    "source_check" => item["source_check"].to_s,
    "source_artifact" => item["source_artifact"].to_s,
    "worklist_artifact" => item["worklist_artifact"].to_s,
    "unit_source_ref" => unit["source_ref"].to_s,
    "action" => unit["action"].to_s,
    "validate_after" => item["next_command"].to_s,
    "requires_founder_decision" => founder_required,
    "founder_gate" => item["founder_gate"].to_s,
    "forbidden_actions" => Array(item["forbidden_actions"]).map(&:to_s),
    "details" => unit["details"].is_a?(Hash) ? unit["details"] : {},
    "reason_for_selection" => reason,
    "automation_boundaries" => Array(queue["automation_boundaries"]).map(&:to_s),
    "refresh_commands" => next_unit_refresh_commands(run_rel, action_queue_path, queue)
  }
end

def build_markdown(payload)
  lines = []
  lines << "# IDOL Graph Engineering Next Unit"
  lines << ""
  lines << "generated_at: #{payload['generated_at']}"
  lines << "run: `#{payload['run']}`"
  lines << "status: `#{payload['status']}`"
  lines << "source_action_queue: `#{payload['source_action_queue']}`"
  lines << ""
  lines << "## Selected Unit"
  lines << ""
  if payload["selected_unit_id"].empty?
    lines << "- No actionable next unit was selected."
  else
    lines << "- queue: `#{payload['selected_queue_id']}`"
    lines << "- unit: `#{payload['selected_unit_id']}`"
    lines << "- type: `#{payload['selected_unit_type']}`"
    lines << "- status: `#{payload['selected_unit_status']}`"
    lines << "- owner: `#{payload['owner']}`"
    lines << "- requires_founder_decision: `#{payload['requires_founder_decision']}`"
    lines << "- source_check: `#{payload['source_check']}`"
    lines << "- worklist: `#{payload['worklist_artifact']}`"
    lines << "- action: #{payload['action']}"
    lines << "- validate_after: `#{payload['validate_after']}`"
    lines << "- reason: #{payload['reason_for_selection']}"
  end
  lines << ""
  lines << "## Boundaries"
  lines << ""
  Array(payload["automation_boundaries"]).each { |boundary| lines << "- #{boundary}" }
  lines << ""
  unless Array(payload["forbidden_actions"]).empty?
    lines << "## Forbidden Actions"
    lines << ""
    Array(payload["forbidden_actions"]).each { |action| lines << "- #{action}" }
    lines << ""
  end
  lines << "## Refresh Commands"
  lines << ""
  Array(payload["refresh_commands"]).each { |command| lines << "- `#{command}`" }
  lines.join("\n")
end

options = {
  action_queue: nil,
  output_yaml: nil,
  output_md: nil,
  write: false
}

OptionParser.new do |parser|
  parser.on("--action-queue PATH") { |value| options[:action_queue] = value }
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
default_action_queue = latest_action_queue(content_id)
action_queue_path = rel_path(options[:action_queue] || default_action_queue || "automation/action-queues/#{date_prefix}-#{content_id}-harness-action-queue.yaml")
output_yaml = options[:output_yaml] || "automation/next-units/#{date_prefix}-#{content_id}-harness-next-unit.yaml"
output_md = options[:output_md] || "automation/next-units/#{date_prefix}-#{content_id}-harness-next-unit.md"

queue = load_yaml_hash(action_queue_path)
payload = next_unit_payload(queue, action_queue_path, run_rel)
yaml_text = YAML.dump(payload)
md_text = build_markdown(payload)

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
