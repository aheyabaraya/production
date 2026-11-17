#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "optparse"
require "pathname"
require "time"
require "yaml"

ROOT = Pathname.new(Dir.pwd).cleanpath
SUPPORTED_CHECKS = ["video_prompt_section_qa_readiness"].freeze

def usage_error(message)
  warn "ERROR: #{message}"
  warn "usage: ruby scripts/idol_harness_action_queue.rb RUN_ROOT [--worklist PATH] [--output-yaml PATH] [--output-md PATH] [--only-check video_prompt_section_qa_readiness] [--write]"
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
  return {} unless resolved && File.file?(resolved.to_s)

  doc = YAML.load_file(resolved.to_s)
  doc.is_a?(Hash) ? doc : {}
rescue Psych::SyntaxError
  {}
end

def latest_match(run_path, pattern)
  matches = Dir.glob((run_path + pattern).to_s).select { |path| File.file?(path) }
  return nil if matches.empty?

  matches.sort_by do |path|
    version = File.basename(path).match(/(?:^|[-_])v(\d+)(?:\D|$)/)&.[](1)&.to_i || -1
    [version, File.mtime(path), path]
  end.last
end

def active_context_for(run_rel)
  sprint = load_yaml_hash("automation/hermes/current-sprint.yaml")
  active_context = sprint["active_context"].is_a?(Hash) ? sprint["active_context"] : {}
  active_context["active_run"].to_s == run_rel ? active_context : {}
end

def focused_video_prompt_section_qa_payload(run_rel, run_path, worklist_override = nil)
  worklist = worklist_override || latest_match(run_path, "review/03v-section-video-prompt-qa-worklist-v*.yaml")
  usage_error("focused 03V action queue requires a structured 03V worklist YAML") if blank?(worklist)

  worklist_rel = rel_path(worklist)
  worklist_doc = load_yaml_hash(worklist_rel)
  source_artifact = worklist_doc["source_artifact"].to_s
  source_artifact = rel_path(latest_match(run_path, "review/03v-section-video-prompt-qa-v*.yaml")) if blank?(source_artifact)
  usage_error("focused 03V action queue could not find the source section QA artifact") if blank?(source_artifact)

  active_context = active_context_for(run_rel)
  {
    "album_key" => active_context["album_key"].to_s,
    "title_key" => active_context["title_key"].to_s,
    "overall_status" => "focused_03v_front_gate_pending_founder",
    "counts" => {
      "pass" => 1,
      "fail" => 1,
      "missing" => 0
    },
    "blocking_checks" => ["video_prompt_section_qa_readiness"],
    "checks" => [
      {
        "id" => "video_prompt_section_qa_readiness",
        "status" => "fail",
        "artifact" => source_artifact,
        "command" => "ruby scripts/validate_video_prompt_section_qa_readiness.rb #{source_artifact}"
      },
      {
        "id" => "video_prompt_section_qa_worklist",
        "status" => "pass",
        "artifact" => worklist_rel,
        "command" => "ruby scripts/idol_video_prompt_section_qa_worklist.rb #{run_rel} --qa #{source_artifact} --write"
      }
    ],
    "next_actions" => {
      "video_prompt_section_qa_readiness" => "Use the focused 03V section QA worklist; stop at the front playback/generation gate when the front chunk is local-ready."
    }
  }
end

def focused_section_qa_source(run_path)
  worklist = latest_match(run_path, "review/03v-section-video-prompt-qa-worklist-v*.yaml")
  if !blank?(worklist)
    doc = load_yaml_hash(rel_path(worklist))
    source = doc["source_artifact"].to_s
    return source unless blank?(source)
  end

  rel_path(latest_match(run_path, "review/03v-section-video-prompt-qa-v*.yaml"))
end

def check_by_id(payload, id)
  Array(payload["checks"]).find { |check| check["id"].to_s == id.to_s } || {}
end

def founder_decisions_for(run_rel)
  sprint = load_yaml_hash("automation/hermes/current-sprint.yaml")
  active_context = sprint["active_context"].is_a?(Hash) ? sprint["active_context"] : {}
  return [] unless active_context["active_run"].to_s == run_rel

  Array(sprint["founder_decisions_needed"]).map do |item|
    next unless item.is_a?(Hash)

    {
      "id" => item["id"].to_s,
      "decision" => item["decision"].to_s,
      "gate" => item["gate"].to_s,
      "status" => item["status"].to_s
    }
  end.compact
end

def active_founder_gate_decision(run_rel, decision_path)
  return {} if blank?(decision_path)

  decision = load_yaml_hash(decision_path)
  return {} unless decision["schema_version"].to_s == "harness-founder-decision.v1"
  return {} unless decision["run"].to_s == run_rel
  return {} unless decision["status"].to_s == "active"

  decision.merge("source_decision" => rel_path(decision_path))
end

def founder_gate_decision_summary(decision)
  return {} if decision.empty?

  {
    "schema_version" => decision["schema_version"].to_s,
    "status" => decision["status"].to_s,
    "source_decision" => decision["source_decision"].to_s,
    "source_founder_gate" => decision["source_founder_gate"].to_s,
    "source_next_unit" => decision["source_next_unit"].to_s,
    "source_action_queue" => decision["source_action_queue"].to_s,
    "gate_id" => decision["gate_id"].to_s,
    "gate_type" => decision["gate_type"].to_s,
    "section_range" => decision["section_range"].to_s,
    "decision_id" => decision["decision_id"].to_s,
    "allows_paid_generation" => decision["allows_paid_generation"] == true,
    "allows_external_execution" => decision["allows_external_execution"] == true,
    "continues_local_qa" => decision["continues_local_qa"] == true,
    "marks_section_qa_pass" => decision["marks_section_qa_pass"] == true,
    "approved_execution_route" => decision["approved_execution_route"].to_s,
    "next_local_section" => decision["next_local_section"].to_s,
    "next_action" => decision["next_action"].to_s
  }
end

def structured_worklist(path)
  return {} unless path.to_s.end_with?(".yaml", ".yml")

  load_yaml_hash(path)
end

def scalar_summary(hash)
  return {} unless hash.is_a?(Hash)

  hash.each_with_object({}) do |(key, value), memo|
    next unless value.nil? || value.is_a?(String) || value.is_a?(Integer) || value.is_a?(Float) || value == true || value == false

    memo[key.to_s] = value
  end
end

def first_items(values, limit = 4)
  Array(values).first(limit).map(&:to_s)
end

def expand_section_range(range)
  match = range.to_s.match(/\AS(\d{2})-S(\d{2})\z/)
  return range.to_s.split("-", 2) unless match

  first = match[1].to_i
  last = match[2].to_i
  return ["S#{format('%02d', first)}"] if last < first

  (first..last).map { |number| "S#{format('%02d', number)}" }
end

def split_list(value)
  value.to_s.split(",").map(&:strip).reject(&:empty?)
end

def video_front_gate_unit(summary, worklist = {})
  return nil unless summary["front_playback_gate_ready"] == true

  range = summary["front_playback_gate_section_range"].to_s
  section_ids = expand_section_range(range)
  next_local_section = summary["front_playback_gate_next_local_section"].to_s
  passed_section_ids = split_list(summary["front_playback_gate_passed_section_ids"])
  remaining_section_ids = split_list(summary["front_playback_gate_remaining_section_ids"])
  upload_summary = front_gate_upload_summary(worklist, section_ids)
  action = if next_local_section.empty?
             "#{range} local source/prompt QA is closed; choose the playback/generation route or hold/review prompts before any generated playback QA pass."
           elsif !passed_section_ids.empty?
             "#{range} is the active 03V playback chunk; #{passed_section_ids.join(', ')} already passed, so continue playback review for #{remaining_section_ids.join(', ')} before moving to #{next_local_section}."
           else
             "#{range} local source/prompt QA is closed; choose the playback/generation route for this front chunk; if playback is clean, continue the next chunk from #{next_local_section}."
           end
  unless upload_summary["founder_operator_surface"].to_s.empty?
    action = "#{action} Use upload-ready for manual upload: #{upload_summary['founder_operator_surface']}."
  end
  {
    "id" => "front_03v_playback_gate:#{range}",
    "unit_type" => "local_followup",
    "status" => "needs_founder",
    "action" => action,
    "requires_founder_decision" => true,
    "source_ref" => "section_queue.#{range}",
    "details" => {
      "section_range" => range,
      "min_sections" => summary["front_playback_gate_min_sections"].to_i,
      "section_count" => summary["front_playback_gate_section_count"].to_i,
      "section_ids" => section_ids,
      "packet_count" => summary["front_playback_gate_packet_count"].to_i,
      "remaining_check" => "generation_playback_probe",
      "passed_section_ids" => passed_section_ids,
      "remaining_section_ids" => remaining_section_ids,
      "skipped_pass_chunks" => split_list(summary["front_playback_gate_skipped_pass_chunks"]),
      "next_local_section" => next_local_section,
      "next_local_continuation_allowed" => summary["front_playback_gate_next_local_continuation_allowed"] == true
    }.merge(upload_summary)
  }
end

def continue_local_decision_for_front_gate?(front_gate, decision)
  return false unless front_gate && decision.is_a?(Hash)

  decision["schema_version"].to_s == "harness-founder-decision.v1" &&
    decision["status"].to_s == "active" &&
    decision["decision_id"].to_s == "continue_local_next_section" &&
    decision["continues_local_qa"] == true &&
    decision["allows_paid_generation"] == false &&
    decision["allows_external_execution"] == false &&
    decision["marks_section_qa_pass"] == false &&
    decision["section_range"].to_s == front_gate.dig("details", "section_range").to_s
end

def upload_root_for(upload_pack)
  path = upload_pack.to_s
  marker = "/bridge-two-image/"
  index = path.index(marker)
  return "" unless index

  path[0...index]
end

def drive_mirror_upload_root(canonical_root, worklist)
  pack_name = File.basename(canonical_root.to_s)
  title_key = pack_name.sub(/-video-input-packs.*\z/, "")
  content_id = File.basename(worklist["run"].to_s)
  return "" if pack_name.empty? || title_key.empty? || title_key == pack_name || content_id.empty?

  File.join(
    "drive-sync/02_GPT_GROK_HANDOFF",
    "03-review_#{title_key}_video-prompts",
    content_id,
    "video-input-packs",
    pack_name
  )
end

def front_gate_upload_summary(worklist, section_ids)
  allowed_sections = Array(section_ids).map(&:to_s)
  upload_packs = Array(worklist["section_queue"]).flat_map do |section|
    next [] unless section.is_a?(Hash)
    next [] unless allowed_sections.include?(section["section_key"].to_s)

    Array(section["packets"]).map { |packet| packet.is_a?(Hash) ? packet["upload_pack"].to_s : "" }
  end.reject(&:empty?).uniq
  upload_ready_folders = Array(worklist["section_queue"]).flat_map do |section|
    next [] unless section.is_a?(Hash)
    next [] unless allowed_sections.include?(section["section_key"].to_s)

    Array(section["packets"]).map { |packet| packet.is_a?(Hash) ? packet["upload_ready"].to_s : "" }
  end.reject(&:empty?).uniq

  canonical_roots = upload_packs.map { |path| upload_root_for(path) }.reject(&:empty?).uniq
  canonical_root = canonical_roots.length == 1 ? canonical_roots.first : ""
  canonical_pack_index = canonical_root.empty? ? "" : File.join(canonical_root, "PACK_INDEX.csv")
  mirror_root = canonical_root.empty? ? "" : drive_mirror_upload_root(canonical_root, worklist)
  mirror_pack_index = mirror_root.empty? ? "" : File.join(mirror_root, "PACK_INDEX.csv")
  founder_operator_surface = worklist["founder_operator_surface"].to_s

  {
    "upload_pack_count" => upload_packs.length,
    "founder_operator_surface" => founder_operator_surface,
    "upload_ready_count" => upload_ready_folders.length,
    "first_upload_ready_folders" => upload_ready_folders.first(5),
    "last_upload_ready_folder" => upload_ready_folders.last.to_s,
    "canonical_upload_root" => canonical_root,
    "canonical_pack_index" => canonical_pack_index,
    "drive_mirror_upload_root" => mirror_root,
    "drive_mirror_pack_index" => mirror_pack_index,
    "first_upload_packs" => upload_packs.first(5),
    "last_upload_pack" => upload_packs.last.to_s
  }
end

def generated_playback_intake_path(worklist)
  run_rel = worklist["run"].to_s
  return "" if run_rel.empty?

  File.join(run_rel, "review/03v-generated-playback-intake-v1.yaml")
end

def playback_review_worklist_path(worklist)
  run_rel = worklist["run"].to_s
  return "" if run_rel.empty?

  File.join(run_rel, "review/03v-playback-review-worklist-v1.yaml")
end

def playback_decision_sheet_path(worklist)
  run_rel = worklist["run"].to_s
  return "" if run_rel.empty?

  File.join(run_rel, "review/03v-playback-decision-sheet-v1.yaml")
end

def approve_generation_decision_for_front_gate?(front_gate, decision)
  return false unless front_gate && decision.is_a?(Hash)

  decision["schema_version"].to_s == "harness-founder-decision.v1" &&
    decision["status"].to_s == "active" &&
    decision["decision_id"].to_s == "approve_front_chunk_generation" &&
    decision["allows_paid_generation"] == true &&
    decision["allows_external_execution"] == true &&
    decision["continues_local_qa"] == false &&
    decision["marks_section_qa_pass"] == false &&
    !decision["approved_execution_route"].to_s.empty? &&
    decision["section_range"].to_s == front_gate.dig("details", "section_range").to_s
end

def approved_generation_unit(front_gate, decision, worklist)
  details = front_gate["details"].is_a?(Hash) ? front_gate["details"] : {}
  range = details["section_range"].to_s
  route = decision["approved_execution_route"].to_s
  upload_summary = front_gate_upload_summary(worklist, details["section_ids"])
  intake_path = generated_playback_intake_path(worklist)
  review_worklist_path = playback_review_worklist_path(worklist)
  decision_sheet_path = playback_decision_sheet_path(worklist)
  action = "#{range} generation/playback is approved through #{route}; prepare the route handoff, collect generated clips, then update only generation_playback_probe after playback review."
  unless upload_summary["founder_operator_surface"].to_s.empty?
    action = "#{action} Founder/operator upload-ready: #{upload_summary['founder_operator_surface']}."
  end
  unless upload_summary["canonical_pack_index"].to_s.empty?
    action = "#{action} Canonical PACK_INDEX: #{upload_summary['canonical_pack_index']}."
  end
  {
    "id" => "prepare_03v_generation_playback:#{range}",
    "unit_type" => "local_followup",
    "status" => "approved_pending_generation",
    "action" => action,
    "requires_founder_decision" => false,
    "source_ref" => "founder_decision.#{decision['source_decision']}",
    "details" => {
      "section_range" => range,
      "section_ids" => Array(details["section_ids"]).map(&:to_s),
      "packet_count" => details["packet_count"].to_i,
      "remaining_check" => "generation_playback_probe",
      "approved_execution_route" => route,
      "approved_decision_source" => decision["source_decision"].to_s,
      "approved_gate" => decision["gate_id"].to_s,
      "next_step" => "Use the flat upload-ready queue for manual founder/operator upload when it exists; keep canonical upload packs or approved mirrors for validation/script compatibility. Do not mark QA pass until generated playback evidence is reviewed.",
      "generated_playback_intake" => intake_path,
      "generated_clip_import_command_template" => "ruby scripts/idol_03v_import_generated_clips.rb #{worklist['run']} --source-dir <downloaded_generated_clips_dir> --route #{route} --refresh-worklists --refresh-current-next --write",
      "generated_playback_intake_command" => "ruby scripts/idol_03v_generated_playback_intake.rb #{worklist['run']} --route #{route} --write",
      "playback_review_worklist" => review_worklist_path,
      "playback_review_worklist_command" => "ruby scripts/idol_03v_playback_review_worklist.rb #{worklist['run']} --write",
      "playback_decision_sheet" => decision_sheet_path,
      "playback_decision_sheet_command" => "ruby scripts/idol_03v_playback_decision_sheet.rb #{worklist['run']} --write",
      "playback_pass_command_template" => "ruby scripts/idol_03v_apply_playback_decision.rb #{worklist['run']} --from-text \"#{range} pass: <visible playback note>\" --explicit-founder-review --write",
      "playback_hold_command_template" => "ruby scripts/idol_03v_apply_playback_decision.rb #{worklist['run']} --from-text \"#{range} hold: <visible playback note>\" --write",
      "playback_fix_command_template" => "ruby scripts/idol_03v_apply_playback_decision.rb #{worklist['run']} --from-text \"fix PKT_Bxx: <visible issue and target change>\" --write",
      "playback_review_record_command_template" => "ruby scripts/idol_03v_record_playback_review.rb #{worklist['run']} --from-text \"#{range} pass: <visible playback note>\" --explicit-founder-review --write",
      "playback_review_apply_command_template" => "ruby scripts/idol_03v_apply_playback_review_record.rb #{worklist['run']} --record #{worklist['run']}/review/03v-playback-review-records/<record>.yaml --write"
    }.merge(upload_summary)
  }
end

def video_next_units(worklist, active_decision = {})
  summary = worklist["summary"].is_a?(Hash) ? worklist["summary"] : {}
  units = []
  front_gate = video_front_gate_unit(summary, worklist)
  skip_front_gate = continue_local_decision_for_front_gate?(front_gate, active_decision)
  if approve_generation_decision_for_front_gate?(front_gate, active_decision)
    units << approved_generation_unit(front_gate, active_decision, worklist)
  end
  units << front_gate if front_gate && !skip_front_gate

  section_units = Array(worklist["section_queue"]).map do |section|
    next unless section.is_a?(Hash)

    unfinished = Array(section["unfinished_checks"]).map(&:to_s)
    review_statuses = Array(section["review_actions"]).each_with_object({}) do |action, memo|
      next unless action.is_a?(Hash)

      memo[action["field"].to_s] = action["status"].to_s
    end
    founder_required = unfinished == ["generation_playback_probe"] &&
                       review_statuses["generation_playback_probe"] == "needs_founder"
    packet_ids = Array(section["packet_ids"]).map(&:to_s)
    section_key = section["section_key"].to_s
    {
      "id" => "close_03v_section_qa:#{section_key}",
      "unit_type" => "section_qa",
      "status" => section["status"].to_s,
      "action" => if unfinished.empty?
                    "Confirm section QA evidence remains clean before merge."
                  elsif founder_required
                    "Local source/prompt QA is closed; wait for an actual generated clip or explicit founder-approved playback/generation route before marking playback pass."
                  else
                    "Review #{unfinished.length} unfinished QA check(s); start with #{unfinished.first}."
                  end,
      "requires_founder_decision" => founder_required,
      "source_ref" => "section_queue.#{section_key}",
      "details" => {
        "section_label" => section["section_label"].to_s,
        "packet_count" => packet_ids.length,
        "unfinished_check_count" => unfinished.length,
        "first_unfinished_checks" => first_items(unfinished),
        "first_packet_ids" => first_items(packet_ids),
        "entry_continuity" => section["entry_continuity"].to_s,
        "exit_continuity" => section["exit_continuity"].to_s
      }
    }
  end.compact
  units.concat(section_units)
  units
end

def attach_worklist_details(queue_item, active_decision = {})
  worklist = structured_worklist(queue_item["worklist_artifact"])
  queue_item["worklist_summary"] = scalar_summary(worklist["summary"])
  queue_item["next_units"] =
    case worklist["worklist_type"].to_s
    when "video_prompt_section_qa"
      video_next_units(worklist, active_decision)
    else
      []
    end
  queue_item
end

def queue_template(blocker_id, run_rel, payload, run_path, active_decision = {})
  check = check_by_id(payload, blocker_id)
  case blocker_id
  when "video_prompt_section_qa_readiness"
    worklist = check_by_id(payload, "video_prompt_section_qa_worklist")["artifact"].to_s
    worklist = rel_path(latest_match(run_path, "review/03v-section-video-prompt-qa-worklist-v*.yaml")) if blank?(worklist)
    worklist = rel_path(latest_match(run_path, "review/03v-section-video-prompt-qa-worklist-v*.md")) if blank?(worklist)
    attach_worklist_details({
      "id" => "close_03v_section_qa",
      "priority" => 1,
      "type" => "validator_blocker",
      "owner" => "codex",
      "status" => "pending",
      "source_check" => blocker_id,
      "source_artifact" => check["artifact"].to_s,
      "worklist_artifact" => worklist,
      "action" => "Complete section QA from the run-owned worklist: source image alignment, previous/next frame continuity, clip-duration music fit, motion/camera fit, space/object reaction, story progression, person-only risk, and playback probe when generated clips exist.",
      "next_command" => "ruby scripts/validate_video_prompt_section_qa_readiness.rb #{check['artifact']}",
      "requires_founder_decision" => false,
      "founder_gate" => "No paid generation or external execution; founder approval is required before new paid video generation or before marking generated playback accepted.",
      "forbidden_actions" => [
        "Do not mark section QA pass from structure alone.",
        "Do not treat Drive mirror prompt files as canonical.",
        "Do not run paid video generation without explicit founder approval."
      ]
    }, active_decision)
  else
    {
      "id" => "repair_#{blocker_id}",
      "priority" => 50,
      "type" => "validator_blocker",
      "owner" => "codex",
      "status" => "pending",
      "source_check" => blocker_id,
      "source_artifact" => check["artifact"].to_s,
      "worklist_artifact" => "",
      "action" => payload.dig("next_actions", blocker_id).to_s,
      "next_command" => check["command"].to_s,
      "requires_founder_decision" => false,
      "founder_gate" => "",
      "forbidden_actions" => [],
      "worklist_summary" => {},
      "next_units" => []
    }
  end
end

def status_for(payload)
  blockers = Array(payload["blocking_checks"])
  return "validator_pass" if blockers.empty?

  checks = Array(payload["checks"])
  missing_current_worklist = checks.any? do |check|
    next false unless check["id"].to_s == "video_prompt_section_qa_worklist"

    check["status"].to_s != "pass"
  end
  missing_current_worklist ? "blocked_without_current_worklists" : "actionable_blocked"
end

def refresh_commands_for(run_rel, blocker_ids, only_check, output_yaml, active_decision = {}, source_qa = "")
  return [] unless blocker_ids.include?("video_prompt_section_qa_readiness")

  qa_source = blank?(source_qa) ? focused_section_qa_source(resolve_path(run_rel)) : source_qa
  worklist_command = "ruby scripts/idol_video_prompt_section_qa_worklist.rb #{run_rel}"
  worklist_command += " --qa #{qa_source}" unless blank?(qa_source)
  worklist_command += " --write"
  commands = [
    worklist_command,
    "ruby scripts/idol_03v_generated_playback_intake.rb #{run_rel} --write",
    "ruby scripts/idol_03v_playback_review_worklist.rb #{run_rel} --write",
    "ruby scripts/idol_03v_playback_decision_sheet.rb #{run_rel} --write",
    "ruby scripts/idol_harness_action_queue.rb #{run_rel} --only-check video_prompt_section_qa_readiness --write",
    "ruby scripts/idol_harness_next_unit.rb #{run_rel} --write"
  ]
  commands << "ruby scripts/idol_harness_founder_gate_packet.rb #{run_rel} --write" unless active_decision["decision_id"].to_s == "continue_local_next_section"
  commands << "ruby scripts/idol_harness_current_next.rb #{run_rel} --write"
  commands << "ruby scripts/validate_03v_front_playback_gate.rb #{run_rel} --action-queue #{output_yaml}"
  commands
end

def build_markdown(queue)
  lines = []
  lines << "# IDOL Graph Engineering Action Queue"
  lines << ""
  lines << "generated_at: #{queue['generated_at']}"
  lines << "run: `#{queue['run']}`"
  lines << "status: `#{queue['status']}`"
  lines << "source_state_report: `#{queue['source_state_report']}`"
  lines << ""
  lines << "## Summary"
  lines << ""
  summary = queue["state_summary"]
  lines << "- overall_status: `#{summary['overall_status']}`"
  lines << "- pass: #{summary['pass']}"
  lines << "- fail: #{summary['fail']}"
  lines << "- missing: #{summary['missing']}"
  lines << "- blocking: #{summary['blocking']}"
  lines << ""
  decision = queue["active_founder_gate_decision"].is_a?(Hash) ? queue["active_founder_gate_decision"] : {}
  unless decision.empty?
    lines << "## Active Founder Gate Decision"
    lines << ""
    lines << "- decision: `#{decision['decision_id']}`"
    lines << "- gate: `#{decision['gate_id']}`"
    lines << "- section_range: `#{decision['section_range']}`"
    lines << "- approved_execution_route: `#{decision['approved_execution_route']}`" unless blank?(decision["approved_execution_route"])
    lines << "- next_local_section: `#{decision['next_local_section']}`"
    lines << "- source: `#{decision['source_decision']}`"
    lines << "- flags: paid=#{decision['allows_paid_generation']}, external=#{decision['allows_external_execution']}, continue_local=#{decision['continues_local_qa']}, qa_pass=#{decision['marks_section_qa_pass']}"
    lines << ""
  end
  lines << "## Queue"
  lines << ""
  if queue["queues"].empty?
    lines << "- No blocking queue items. Rerun the state checker before advancing production."
  else
    queue["queues"].sort_by { |item| item["priority"] }.each do |item|
      lines << "### #{item['priority']}. #{item['id']}"
      lines << ""
      lines << "- owner: `#{item['owner']}`"
      lines << "- source_check: `#{item['source_check']}`"
      lines << "- source_artifact: `#{item['source_artifact']}`"
      lines << "- worklist: `#{item['worklist_artifact']}`"
      lines << "- requires_founder_decision: `#{item['requires_founder_decision']}`"
      lines << "- founder_gate: #{item['founder_gate']}"
      lines << "- action: #{item['action']}"
      lines << "- validate_after: `#{item['next_command']}`"
      unless item["forbidden_actions"].empty?
        lines << "- forbidden_actions: #{item['forbidden_actions'].join(' / ')}"
      end
      unless item["worklist_summary"].empty?
        lines << "- worklist_summary: #{item['worklist_summary'].map { |key, value| "#{key}=#{value}" }.join(', ')}"
      end
      unless item["next_units"].empty?
        lines << ""
        lines << "Next units:"
        item["next_units"].first(12).each do |unit|
          details = unit["details"].is_a?(Hash) ? unit["details"] : {}
          detail_bits = []
          detail_bits << "checks=#{details['unfinished_check_count']}" if details.key?("unfinished_check_count")
          detail_bits << "packets=#{details['packet_count']}" if details.key?("packet_count")
          detail_bits << "sections=#{Array(details['section_ids']).join('+')}" if details.key?("section_ids")
          detail_bits << "duration=#{details['duration_seconds']}" if details.key?("duration_seconds") && !blank?(details["duration_seconds"])
          suffix = detail_bits.empty? ? "" : " (#{detail_bits.join(', ')})"
          lines << "- `#{unit['id']}` #{unit['status']}#{suffix}: #{unit['action']}"
        end
        if item["next_units"].length > 12
          lines << "- ... #{item['next_units'].length - 12} more unit(s) in structured YAML."
        end
      end
      lines << ""
    end
  end

  lines << "## Founder Decisions"
  lines << ""
  if queue["founder_decisions_needed"].empty?
    lines << "- No active founder decisions recorded in Hermes for this run."
  else
    queue["founder_decisions_needed"].each do |decision|
      lines << "- `#{decision['id']}` (`#{decision['status']}`): #{decision['decision']} [gate: #{decision['gate']}]"
    end
  end
  lines << ""
  lines << "## Automation Boundaries"
  lines << ""
  queue["automation_boundaries"].each { |boundary| lines << "- #{boundary}" }
  lines << ""
  lines << "## Refresh Commands"
  lines << ""
  queue["refresh_commands"].each { |command| lines << "- `#{command}`" }
  lines.join("\n")
end

options = {
  worklist: nil,
  output_yaml: nil,
  output_md: nil,
  founder_decision: "automation/founder-decisions/current.yaml",
  only_check: nil,
  write: false
}

OptionParser.new do |parser|
  parser.on("--worklist PATH") { |value| options[:worklist] = value }
  parser.on("--output-yaml PATH") { |value| options[:output_yaml] = value }
  parser.on("--output-md PATH") { |value| options[:output_md] = value }
  parser.on("--founder-decision PATH") { |value| options[:founder_decision] = value }
  parser.on("--only-check CHECK_ID") { |value| options[:only_check] = value }
  parser.on("--write") { options[:write] = true }
end.parse!

run_arg = ARGV.shift
usage_error("RUN_ROOT is required") if blank?(run_arg)

run_path = resolve_path(run_arg)
usage_error("RUN_ROOT is not a directory: #{run_arg}") unless run_path && Dir.exist?(run_path.to_s)
run_rel = rel_path(run_path)
content_id = run_path.basename.to_s
date_prefix = Time.now.strftime("%Y-%m-%d")
if !blank?(options[:only_check]) && !SUPPORTED_CHECKS.include?(options[:only_check].to_s)
  usage_error("unsupported check for focused 03V action queue: #{options[:only_check]}")
end

state_report = "focused_03v_queue_no_state_report"
default_queue_basename = "#{date_prefix}-#{content_id}-03v-action-queue"
output_yaml = options[:output_yaml] || "automation/action-queues/#{default_queue_basename}.yaml"
output_md = options[:output_md] || "automation/action-queues/#{default_queue_basename}.md"

payload = focused_video_prompt_section_qa_payload(run_rel, run_path, options[:worklist])
active_decision = active_founder_gate_decision(run_rel, options[:founder_decision])

blocker_ids = Array(payload["blocking_checks"]).map(&:to_s)
blocker_ids &= SUPPORTED_CHECKS
blocker_ids &= [options[:only_check].to_s] unless blank?(options[:only_check])

queues = blocker_ids.map do |blocker_id|
  queue_template(blocker_id, run_rel, payload, run_path, active_decision)
end.sort_by { |item| item["priority"] }

queue = {
  "schema_version" => "harness-action-queue.v1",
  "generated_at" => Time.now.iso8601,
  "run" => run_rel,
  "album_key" => payload["album_key"].to_s,
  "title_key" => payload["title_key"].to_s,
  "status" => status_for(payload),
  "source_state_report" => state_report,
  "state_summary" => {
    "overall_status" => payload["overall_status"].to_s,
    "pass" => payload.dig("counts", "pass").to_i,
    "fail" => payload.dig("counts", "fail").to_i,
    "missing" => payload.dig("counts", "missing").to_i,
    "blocking" => Array(payload["blocking_checks"]).length
  },
  "active_founder_gate_decision" => founder_gate_decision_summary(active_decision),
  "queues" => queues,
  "founder_decisions_needed" => founder_decisions_for(run_rel),
  "automation_boundaries" => [
    "Automation may read state, validate files, regenerate local worklists, and prepare local reports.",
    "Automation must not infer founder pass/hold/reject decisions.",
    "Automation must not run paid generation, upload, publish, schedule, external sync, Drive mutation, or platform API calls without explicit founder approval.",
    "Drive mirror files are transport/hot copies; run-owned files remain canonical."
  ],
  "refresh_commands" => refresh_commands_for(
    run_rel,
    blocker_ids,
    options[:only_check],
    output_yaml,
    active_decision,
    check_by_id(payload, "video_prompt_section_qa_readiness")["artifact"].to_s
  )
}

yaml_text = YAML.dump(queue)
md_text = build_markdown(queue)

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
