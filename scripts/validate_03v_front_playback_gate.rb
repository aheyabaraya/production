#!/usr/bin/env ruby
# frozen_string_literal: true

require "optparse"
require "pathname"
require "yaml"
require_relative "lib/idol_current_next_v2"

ROOT = Pathname.new(Dir.pwd).cleanpath

FORBIDDEN_COMMAND_PATTERN = /idol_harness_state_check|idol_edit_readiness|edit_map_readiness|04-edit|idol_harness_refresh/.freeze

def usage_error(message)
  warn "ERROR: #{message}"
  warn "usage: ruby scripts/validate_03v_front_playback_gate.rb RUN_ROOT [--worklist PATH] [--playback-intake PATH] [--playback-worklist PATH] [--playback-decision-sheet PATH] [--action-queue PATH] [--next-unit PATH] [--founder-gate PATH] [--current-next PATH]"
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
  unless resolved && File.file?(resolved.to_s)
    warn "ERROR: file is not readable: #{path}"
    exit 1
  end

  doc = YAML.load_file(resolved.to_s)
  return doc if doc.is_a?(Hash)

  warn "ERROR: YAML root must be a mapping: #{path}"
  exit 1
rescue Psych::SyntaxError => e
  warn "ERROR: YAML syntax error in #{path}: #{e.message}"
  exit 1
end

def path_exists?(path, type = :any)
  resolved = resolve_path(path)
  return false unless resolved

  case type
  when :file
    File.file?(resolved.to_s)
  when :directory
    File.directory?(resolved.to_s)
  else
    File.exist?(resolved.to_s)
  end
end

def upload_prompt_path(packet)
  explicit = packet["upload_prompt"].to_s
  return explicit unless explicit.empty?

  upload_pack = packet["upload_pack"].to_s
  return "" if upload_pack.empty?

  File.join(upload_pack, "prompt.txt")
end

def upload_pack_child(packet, filename)
  upload_pack = packet["upload_pack"].to_s
  return "" if upload_pack.empty?

  File.join(upload_pack, filename)
end

def upload_ready_child(packet, filename)
  upload_ready = packet["upload_ready"].to_s
  return "" if upload_ready.empty?

  File.join(upload_ready, filename)
end

def single_beat_packet?(packet)
  type = packet["upload_pack_type"].to_s
  return true if type == "single-beat"

  packet["upload_pack"].to_s.split(File::SEPARATOR).include?("single-beat")
end

def same_resolved_path?(left, right)
  left_path = resolve_path(left)
  right_path = resolve_path(right)
  return false unless left_path && right_path

  left_path == right_path
end

def latest_match(pattern)
  matches = Dir.glob((ROOT + pattern).to_s).select { |path| File.file?(path) }
  return nil if matches.empty?

  matches.max_by { |path| [File.mtime(path), path] }
end

def expand_section_range(range)
  match = range.to_s.match(/\AS(\d{2})-S(\d{2})\z/)
  return range.to_s.split("-", 2) unless match

  first = match[1].to_i
  last = match[2].to_i
  return ["S#{format('%02d', first)}"] if last < first

  (first..last).map { |number| "S#{format('%02d', number)}" }
end

def slug(value)
  value.to_s.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-+\z/, "")
end

def collect_refresh_commands(payload)
  Array(payload["refresh_commands"]).map(&:to_s)
end

def require_refresh_command!(errors, label, payload, expected_substring)
  return if collect_refresh_commands(payload).any? { |command| command.include?(expected_substring) }

  errors << "#{label} refresh_commands must include #{expected_substring}"
end

def decision_by_id(packet, id)
  Array(packet["allowed_decisions"]).find { |decision| decision.is_a?(Hash) && decision["id"].to_s == id.to_s } || {}
end

def section_by_key(worklist, key)
  Array(worklist["section_queue"]).find do |section|
    section.is_a?(Hash) && section["section_key"].to_s == key.to_s
  end || {}
end

def pass_worklist_section?(section)
  return false unless section.is_a?(Hash)
  return true if section["status"].to_s == "pass"

  Array(section["unfinished_checks"]).empty? && Array(section["review_actions"]).empty?
end

def playback_only_worklist_section?(section)
  return false unless section.is_a?(Hash)

  statuses = Array(section["review_actions"]).each_with_object({}) do |action, memo|
    next unless action.is_a?(Hash)

    memo[action["field"].to_s] = action["status"].to_s
  end
  section["status"].to_s == "partial" &&
    Array(section["unfinished_checks"]).map(&:to_s) == ["generation_playback_probe"] &&
    statuses["generation_playback_probe"] == "needs_founder"
end

def review_action_signature(action)
  return {} unless action.is_a?(Hash)

  {
    "field" => action["field"].to_s,
    "status" => action["status"].to_s,
    "action" => action["action"].to_s
  }
end

def packet_signature(packet)
  return {} unless packet.is_a?(Hash)

  {
    "packet_id" => packet["packet_id"].to_s,
    "timeline" => packet["timeline"].to_s,
    "audio_motion_slot" => packet["audio_motion_slot"].to_s,
    "prompt_path" => packet["prompt_path"].to_s,
    "start_image" => packet["start_image"].to_s,
    "end_image" => packet["end_image"].to_s,
    "upload_pack_type" => packet["upload_pack_type"].to_s,
    "upload_ready" => packet["upload_ready"].to_s,
    "upload_ready_prompt" => packet["upload_ready_prompt"].to_s,
    "upload_pack" => packet["upload_pack"].to_s,
    "upload_prompt" => upload_prompt_path(packet),
    "start_audio_cue" => packet["start_audio_cue"].to_s,
    "end_audio_cue" => packet["end_audio_cue"].to_s,
    "prev_end_to_start" => packet["prev_end_to_start"].to_s,
    "end_to_next_start" => packet["end_to_next_start"].to_s
  }
end

def clip_file_status(packet)
  explicit = packet["clip_file_status"].to_s
  return explicit unless explicit.empty?

  packet["clip_status"].to_s == "present" ? "present_probe_ok" : "missing"
end

def media_probe_ok?(probe)
  probe.is_a?(Hash) &&
    probe["status"].to_s == "ok" &&
    probe["playable"] == true &&
    probe["duration_seconds"].to_f.positive? &&
    probe["video_stream_count"].to_i.positive? &&
    probe["width"].to_i.positive? &&
    probe["height"].to_i.positive?
end

def front_gate_packet_ids(worklist, section_ids)
  section_ids.flat_map do |section_id|
    section = section_by_key(worklist, section_id)
    Array(section["packets"]).map { |packet| packet.is_a?(Hash) ? packet["packet_id"].to_s : "" }
  end.reject(&:empty?)
end

def validate_generated_playback_artifacts(errors, run_rel, run_path, worklist_path, worklist, range, section_ids, packet_count, playback_paths)
  intake_path = rel_path(playback_paths[:intake] || (run_path + "review/03v-generated-playback-intake-v1.yaml"))
  playback_worklist_path = rel_path(playback_paths[:worklist] || (run_path + "review/03v-playback-review-worklist-v1.yaml"))
  playback_decision_sheet_path = rel_path(playback_paths[:decision_sheet] || (run_path + "review/03v-playback-decision-sheet-v1.yaml"))
  source_section_qa = worklist["source_artifact"].to_s
  expected_packet_ids = front_gate_packet_ids(worklist, section_ids)

  unless path_exists?(intake_path, :file)
    errors << "generated playback intake is not readable: #{intake_path}"
    return
  end
  unless path_exists?(playback_worklist_path, :file)
    errors << "playback review worklist is not readable: #{playback_worklist_path}"
    return
  end
  unless path_exists?(playback_decision_sheet_path, :file)
    errors << "playback decision sheet is not readable: #{playback_decision_sheet_path}"
    return
  end

  intake = load_yaml_hash(intake_path)
  playback_worklist = load_yaml_hash(playback_worklist_path)
  playback_decision_sheet = load_yaml_hash(playback_decision_sheet_path)
  intake_clips = Array(intake["clip_queue"]).select { |clip| clip.is_a?(Hash) }
  playback_packets = Array(playback_worklist["section_reviews"]).flat_map do |section|
    Array(section.is_a?(Hash) ? section["packets"] : []).select { |packet| packet.is_a?(Hash) }
  end
  decision_rows = Array(playback_decision_sheet["packet_rows"]).select { |packet| packet.is_a?(Hash) }
  intake_packet_ids = intake_clips.map do |clip|
    clip.is_a?(Hash) ? clip["packet_id"].to_s : ""
  end.reject(&:empty?)
  playback_packet_ids = playback_packets.map { |packet| packet["packet_id"].to_s }.reject(&:empty?)

  unless intake["schema_version"].to_s == "idol_03v_generated_playback_intake.v1"
    errors << "generated playback intake schema_version=#{intake['schema_version'].inspect}; expected idol_03v_generated_playback_intake.v1"
  end
  unless intake["run"].to_s == run_rel
    errors << "generated playback intake run=#{intake['run'].inspect}; expected #{run_rel.inspect}"
  end
  unless intake["source_worklist"].to_s == worklist_path
    errors << "generated playback intake source_worklist=#{intake['source_worklist'].inspect}; expected #{worklist_path.inspect}"
  end
  unless intake["source_section_qa"].to_s == source_section_qa
    errors << "generated playback intake source_section_qa=#{intake['source_section_qa'].inspect}; expected #{source_section_qa.inspect}"
  end
  unless intake["section_range"].to_s == range
    errors << "generated playback intake section_range=#{intake['section_range'].inspect}; expected #{range.inspect}"
  end
  unless Array(intake["section_ids"]).map(&:to_s) == section_ids
    errors << "generated playback intake section_ids=#{Array(intake['section_ids']).inspect}; expected #{section_ids.inspect}"
  end
  unless intake.dig("summary", "packet_count").to_i == packet_count
    errors << "generated playback intake packet_count=#{intake.dig('summary', 'packet_count').inspect}; expected #{packet_count}"
  end
  unless intake.dig("summary", "expected_clip_count").to_i == packet_count
    errors << "generated playback intake expected_clip_count=#{intake.dig('summary', 'expected_clip_count').inspect}; expected #{packet_count}"
  end
  intake_present_count = intake_clips.count { |clip| clip["clip_status"].to_s == "present" }
  intake_found_file_count = intake_clips.count { |clip| !clip["generated_clip_path"].to_s.empty? }
  intake_probe_issue_count = intake_clips.count { |clip| clip_file_status(clip) == "present_probe_failed" }
  errors << "generated playback intake summary found_clip_file_count is missing" unless intake.dig("summary", "found_clip_file_count")
  errors << "generated playback intake summary media_probe_issue_count is missing" unless intake.dig("summary", "media_probe_issue_count")
  unless intake.dig("summary", "found_clip_file_count").to_i == intake_found_file_count
    errors << "generated playback intake found_clip_file_count=#{intake.dig('summary', 'found_clip_file_count').inspect}; expected #{intake_found_file_count}"
  end
  unless intake.dig("summary", "discovered_clip_count").to_i == intake_present_count
    errors << "generated playback intake discovered_clip_count=#{intake.dig('summary', 'discovered_clip_count').inspect}; expected present playable count #{intake_present_count}"
  end
  unless intake.dig("summary", "missing_clip_count").to_i == packet_count - intake_present_count
    errors << "generated playback intake missing_clip_count=#{intake.dig('summary', 'missing_clip_count').inspect}; expected #{packet_count - intake_present_count}"
  end
  unless intake.dig("summary", "media_probe_issue_count").to_i == intake_probe_issue_count
    errors << "generated playback intake media_probe_issue_count=#{intake.dig('summary', 'media_probe_issue_count').inspect}; expected #{intake_probe_issue_count}"
  end
  intake_clips.each do |clip|
    packet_id = clip["packet_id"].to_s
    errors << "#{packet_id}: generated playback intake clip_file_status is missing" unless clip.key?("clip_file_status")
    errors << "#{packet_id}: generated playback intake media_probe is missing" unless clip.key?("media_probe")
    file_status = clip_file_status(clip)
    probe = clip["media_probe"]
    case file_status
    when "missing"
      errors << "#{packet_id}: missing clip must not have clip_status present" if clip["clip_status"].to_s == "present"
      errors << "#{packet_id}: missing clip must not point to generated_clip_path" unless clip["generated_clip_path"].to_s.empty?
    when "present_probe_ok"
      errors << "#{packet_id}: present_probe_ok must have clip_status present" unless clip["clip_status"].to_s == "present"
      errors << "#{packet_id}: present_probe_ok must have generated_clip_path" if clip["generated_clip_path"].to_s.empty?
      errors << "#{packet_id}: present_probe_ok must carry ok media_probe" unless media_probe_ok?(probe)
    when "present_probe_failed"
      errors << "#{packet_id}: present_probe_failed must block pass with clip_status missing" unless clip["clip_status"].to_s == "missing"
      errors << "#{packet_id}: present_probe_failed must keep generated_clip_path for replacement" if clip["generated_clip_path"].to_s.empty?
      errors << "#{packet_id}: present_probe_failed must not carry playable ok media_probe" if media_probe_ok?(probe)
    else
      errors << "#{packet_id}: unknown clip_file_status=#{file_status.inspect}"
    end
  end
  unless intake_packet_ids == expected_packet_ids
    errors << "generated playback intake packet ids drifted from front gate: #{intake_packet_ids.inspect}; expected #{expected_packet_ids.inspect}"
  end
  unless intake["clips_root"].to_s.include?("generated-clips/03v/#{slug(range)}/")
    errors << "generated playback intake clips_root=#{intake['clips_root'].inspect}; expected active range slug #{slug(range).inspect}"
  end

  unless playback_worklist["schema_version"].to_s == "idol_03v_playback_review_worklist.v1"
    errors << "playback review worklist schema_version=#{playback_worklist['schema_version'].inspect}; expected idol_03v_playback_review_worklist.v1"
  end
  unless playback_worklist["run"].to_s == run_rel
    errors << "playback review worklist run=#{playback_worklist['run'].inspect}; expected #{run_rel.inspect}"
  end
  unless playback_worklist["source_intake"].to_s == intake_path
    errors << "playback review worklist source_intake=#{playback_worklist['source_intake'].inspect}; expected #{intake_path.inspect}"
  end
  unless playback_worklist["source_worklist"].to_s == worklist_path
    errors << "playback review worklist source_worklist=#{playback_worklist['source_worklist'].inspect}; expected #{worklist_path.inspect}"
  end
  unless playback_worklist["source_section_qa"].to_s == source_section_qa
    errors << "playback review worklist source_section_qa=#{playback_worklist['source_section_qa'].inspect}; expected #{source_section_qa.inspect}"
  end
  unless playback_worklist["section_range"].to_s == range
    errors << "playback review worklist section_range=#{playback_worklist['section_range'].inspect}; expected #{range.inspect}"
  end
  unless Array(playback_worklist["section_ids"]).map(&:to_s) == section_ids
    errors << "playback review worklist section_ids=#{Array(playback_worklist['section_ids']).inspect}; expected #{section_ids.inspect}"
  end
  unless playback_worklist.dig("summary", "packet_count").to_i == packet_count
    errors << "playback review worklist packet_count=#{playback_worklist.dig('summary', 'packet_count').inspect}; expected #{packet_count}"
  end
  playback_present_count = playback_packets.count { |packet| packet["clip_status"].to_s == "present" }
  playback_probe_issue_count = playback_packets.count { |packet| clip_file_status(packet) == "present_probe_failed" }
  errors << "playback review worklist summary media_probe_issue_count is missing" unless playback_worklist.dig("summary", "media_probe_issue_count")
  unless playback_worklist.dig("summary", "present_clip_count").to_i == playback_present_count
    errors << "playback review worklist present_clip_count=#{playback_worklist.dig('summary', 'present_clip_count').inspect}; expected #{playback_present_count}"
  end
  unless playback_worklist.dig("summary", "missing_clip_count").to_i == packet_count - playback_present_count
    errors << "playback review worklist missing_clip_count=#{playback_worklist.dig('summary', 'missing_clip_count').inspect}; expected #{packet_count - playback_present_count}"
  end
  unless playback_worklist.dig("summary", "media_probe_issue_count").to_i == playback_probe_issue_count
    errors << "playback review worklist media_probe_issue_count=#{playback_worklist.dig('summary', 'media_probe_issue_count').inspect}; expected #{playback_probe_issue_count}"
  end
  unless playback_worklist["clips_root"].to_s == intake["clips_root"].to_s
    errors << "playback review worklist clips_root=#{playback_worklist['clips_root'].inspect}; expected intake clips_root #{intake['clips_root'].inspect}"
  end
  unless playback_packet_ids == expected_packet_ids
    errors << "playback review worklist packet ids drifted from front gate: #{playback_packet_ids.inspect}; expected #{expected_packet_ids.inspect}"
  end
  intake_by_packet = intake_clips.each_with_object({}) { |clip, memo| memo[clip["packet_id"].to_s] = clip }
  playback_packets.each do |packet|
    packet_id = packet["packet_id"].to_s
    intake_clip = intake_by_packet[packet_id] || {}
    errors << "#{packet_id}: playback worklist clip_file_status is missing" unless packet.key?("clip_file_status")
    errors << "#{packet_id}: playback worklist media_probe is missing" unless packet.key?("media_probe")
    unless packet["clip_status"].to_s == intake_clip["clip_status"].to_s
      errors << "#{packet_id}: playback worklist clip_status=#{packet['clip_status'].inspect}; expected intake #{intake_clip['clip_status'].inspect}"
    end
    unless clip_file_status(packet) == clip_file_status(intake_clip)
      errors << "#{packet_id}: playback worklist clip_file_status=#{clip_file_status(packet).inspect}; expected intake #{clip_file_status(intake_clip).inspect}"
    end
    unless packet["generated_clip_path"].to_s == intake_clip["generated_clip_path"].to_s
      errors << "#{packet_id}: playback worklist generated_clip_path must match intake"
    end
  end

  decision_sheet_packet_ids = decision_rows.map { |packet| packet["packet_id"].to_s }.reject(&:empty?)
  unless playback_decision_sheet["schema_version"].to_s == "idol_03v_playback_decision_sheet.v1"
    errors << "playback decision sheet schema_version=#{playback_decision_sheet['schema_version'].inspect}; expected idol_03v_playback_decision_sheet.v1"
  end
  unless playback_decision_sheet["run"].to_s == run_rel
    errors << "playback decision sheet run=#{playback_decision_sheet['run'].inspect}; expected #{run_rel.inspect}"
  end
  unless playback_decision_sheet["source_playback_worklist"].to_s == playback_worklist_path
    errors << "playback decision sheet source_playback_worklist=#{playback_decision_sheet['source_playback_worklist'].inspect}; expected #{playback_worklist_path.inspect}"
  end
  unless playback_decision_sheet["source_intake"].to_s == intake_path
    errors << "playback decision sheet source_intake=#{playback_decision_sheet['source_intake'].inspect}; expected #{intake_path.inspect}"
  end
  unless playback_decision_sheet["source_section_qa"].to_s == source_section_qa
    errors << "playback decision sheet source_section_qa=#{playback_decision_sheet['source_section_qa'].inspect}; expected #{source_section_qa.inspect}"
  end
  unless playback_decision_sheet["section_range"].to_s == range
    errors << "playback decision sheet section_range=#{playback_decision_sheet['section_range'].inspect}; expected #{range.inspect}"
  end
  unless Array(playback_decision_sheet["section_ids"]).map(&:to_s) == section_ids
    errors << "playback decision sheet section_ids=#{Array(playback_decision_sheet['section_ids']).inspect}; expected #{section_ids.inspect}"
  end
  unless playback_decision_sheet.dig("summary", "packet_count").to_i == packet_count
    errors << "playback decision sheet packet_count=#{playback_decision_sheet.dig('summary', 'packet_count').inspect}; expected #{packet_count}"
  end
  decision_present_count = decision_rows.count { |packet| packet["clip_status"].to_s == "present" }
  decision_probe_issue_count = decision_rows.count { |packet| clip_file_status(packet) == "present_probe_failed" }
  errors << "playback decision sheet summary media_probe_issue_count is missing" unless playback_decision_sheet.dig("summary", "media_probe_issue_count")
  unless playback_decision_sheet.dig("summary", "present_clip_count").to_i == decision_present_count
    errors << "playback decision sheet present_clip_count=#{playback_decision_sheet.dig('summary', 'present_clip_count').inspect}; expected #{decision_present_count}"
  end
  unless playback_decision_sheet.dig("summary", "missing_clip_count").to_i == packet_count - decision_present_count
    errors << "playback decision sheet missing_clip_count=#{playback_decision_sheet.dig('summary', 'missing_clip_count').inspect}; expected #{packet_count - decision_present_count}"
  end
  unless playback_decision_sheet.dig("summary", "media_probe_issue_count").to_i == decision_probe_issue_count
    errors << "playback decision sheet media_probe_issue_count=#{playback_decision_sheet.dig('summary', 'media_probe_issue_count').inspect}; expected #{decision_probe_issue_count}"
  end
  if decision_probe_issue_count.positive? && playback_decision_sheet["status"].to_s == "ready_for_founder_playback_decision"
    errors << "playback decision sheet must not be ready when media_probe_issue_count is positive"
  end
  unless playback_decision_sheet["clips_root"].to_s == intake["clips_root"].to_s
    errors << "playback decision sheet clips_root=#{playback_decision_sheet['clips_root'].inspect}; expected intake clips_root #{intake['clips_root'].inspect}"
  end
  unless decision_sheet_packet_ids == expected_packet_ids
    errors << "playback decision sheet packet ids drifted from front gate: #{decision_sheet_packet_ids.inspect}; expected #{expected_packet_ids.inspect}"
  end
  playback_by_packet = playback_packets.each_with_object({}) { |packet, memo| memo[packet["packet_id"].to_s] = packet }
  decision_rows.each do |packet|
    packet_id = packet["packet_id"].to_s
    playback_packet = playback_by_packet[packet_id] || {}
    errors << "#{packet_id}: playback decision sheet clip_file_status is missing" unless packet.key?("clip_file_status")
    errors << "#{packet_id}: playback decision sheet media_probe_status is missing" unless packet.key?("media_probe_status")
    errors << "#{packet_id}: playback decision sheet media_probe_error is missing" unless packet.key?("media_probe_error")
    unless packet["clip_status"].to_s == playback_packet["clip_status"].to_s
      errors << "#{packet_id}: playback decision sheet clip_status=#{packet['clip_status'].inspect}; expected worklist #{playback_packet['clip_status'].inspect}"
    end
    unless clip_file_status(packet) == clip_file_status(playback_packet)
      errors << "#{packet_id}: playback decision sheet clip_file_status=#{clip_file_status(packet).inspect}; expected worklist #{clip_file_status(playback_packet).inspect}"
    end
    unless packet["generated_clip_path"].to_s == playback_packet["generated_clip_path"].to_s
      errors << "#{packet_id}: playback decision sheet generated_clip_path must match worklist"
    end
    if clip_file_status(packet) == "present_probe_failed" && packet["pass_blocker"].to_s != "unplayable_clip"
      errors << "#{packet_id}: playback decision sheet must expose unplayable_clip pass_blocker"
    end
  end
end

def validate_approved_generation_details(errors, label, details, active_decision, packet_count)
  route = active_decision["approved_execution_route"].to_s
  unless details["approved_execution_route"].to_s == route
    errors << "#{label} approved_execution_route=#{details['approved_execution_route'].inspect}; expected #{route.inspect}"
  end
  unless details["upload_pack_count"].to_i == packet_count
    errors << "#{label} upload_pack_count=#{details['upload_pack_count'].inspect}; expected packet_count #{packet_count}"
  end
  unless path_exists?(details["canonical_upload_root"].to_s, :directory)
    errors << "#{label} canonical_upload_root is not a directory: #{details['canonical_upload_root']}"
  end
  unless path_exists?(details["canonical_pack_index"].to_s, :file)
    errors << "#{label} canonical_pack_index is not readable: #{details['canonical_pack_index']}"
  end
  if route == "grok_manual_drive_mirror"
    unless path_exists?(details["drive_mirror_upload_root"].to_s, :directory)
      errors << "#{label} drive_mirror_upload_root is not a directory: #{details['drive_mirror_upload_root']}"
    end
    unless path_exists?(details["drive_mirror_pack_index"].to_s, :file)
      errors << "#{label} drive_mirror_pack_index is not readable: #{details['drive_mirror_pack_index']}"
    end
  end
  if Array(details["first_upload_packs"]).empty?
    errors << "#{label} first_upload_packs is missing"
  end
  if details["last_upload_pack"].to_s.empty?
    errors << "#{label} last_upload_pack is missing"
  end
  unless path_exists?(details["generated_playback_intake"].to_s, :file)
    errors << "#{label} generated_playback_intake is not readable: #{details['generated_playback_intake']}"
  end
  import_command = details["generated_clip_import_command_template"].to_s
  unless import_command.include?("idol_03v_import_generated_clips.rb")
    errors << "#{label} generated_clip_import_command_template is missing"
  end
  unless import_command.include?("--refresh-worklists") && import_command.include?("--refresh-current-next")
    errors << "#{label} generated_clip_import_command_template must refresh playback worklists and current-next"
  end
  unless details["generated_playback_intake_command"].to_s.include?("idol_03v_generated_playback_intake.rb")
    errors << "#{label} generated_playback_intake_command is missing"
  end
  unless path_exists?(details["playback_review_worklist"].to_s, :file)
    errors << "#{label} playback_review_worklist is not readable: #{details['playback_review_worklist']}"
  end
  unless details["playback_review_worklist_command"].to_s.include?("idol_03v_playback_review_worklist.rb")
    errors << "#{label} playback_review_worklist_command is missing"
  end
  unless path_exists?(details["playback_decision_sheet"].to_s, :file)
    errors << "#{label} playback_decision_sheet is not readable: #{details['playback_decision_sheet']}"
  end
  unless details["playback_decision_sheet_command"].to_s.include?("idol_03v_playback_decision_sheet.rb")
    errors << "#{label} playback_decision_sheet_command is missing"
  end
  pass_command = details["playback_pass_command_template"].to_s
  hold_command = details["playback_hold_command_template"].to_s
  fix_command = details["playback_fix_command_template"].to_s
  unless pass_command.include?("idol_03v_apply_playback_decision.rb") &&
         pass_command.include?(" pass:") &&
         pass_command.include?("--explicit-founder-review")
    errors << "#{label} playback_pass_command_template is missing or incomplete"
  end
  unless hold_command.include?("idol_03v_apply_playback_decision.rb") &&
         hold_command.include?(" hold:")
    errors << "#{label} playback_hold_command_template is missing or incomplete"
  end
  unless fix_command.include?("idol_03v_apply_playback_decision.rb") &&
         fix_command.include?("fix PKT_Bxx:")
    errors << "#{label} playback_fix_command_template is missing or incomplete"
  end
  ambiguous_decision_templates = [
    details["playback_review_decision_command_template"].to_s,
    details["playback_review_record_command_template"].to_s,
    pass_command,
    hold_command,
    fix_command
  ].select { |command| command.include?("pass|hold|fix") }
  unless ambiguous_decision_templates.empty?
    errors << "#{label} playback decision command template must not use pass|hold|fix placeholder"
  end
  unless details["playback_review_record_command_template"].to_s.include?("idol_03v_record_playback_review.rb")
    errors << "#{label} playback_review_record_command_template is missing"
  end
  unless details["playback_review_apply_command_template"].to_s.include?("idol_03v_apply_playback_review_record.rb")
    errors << "#{label} playback_review_apply_command_template is missing"
  end
end

options = {
  worklist: nil,
  playback_intake: nil,
  playback_worklist: nil,
  playback_decision_sheet: nil,
  action_queue: nil,
  next_unit: nil,
  founder_gate: nil,
  current_next: nil
}

OptionParser.new do |parser|
  parser.on("--worklist PATH") { |value| options[:worklist] = value }
  parser.on("--playback-intake PATH") { |value| options[:playback_intake] = value }
  parser.on("--playback-worklist PATH") { |value| options[:playback_worklist] = value }
  parser.on("--playback-decision-sheet PATH") { |value| options[:playback_decision_sheet] = value }
  parser.on("--action-queue PATH") { |value| options[:action_queue] = value }
  parser.on("--next-unit PATH") { |value| options[:next_unit] = value }
  parser.on("--founder-gate PATH") { |value| options[:founder_gate] = value }
  parser.on("--current-next PATH") { |value| options[:current_next] = value }
end.parse!

run_arg = ARGV.shift
usage_error("RUN_ROOT is required") if blank?(run_arg)

run_path = resolve_path(run_arg)
usage_error("RUN_ROOT is not a directory: #{run_arg}") unless run_path && Dir.exist?(run_path.to_s)

run_rel = rel_path(run_path)
content_id = run_path.basename.to_s
action_queue_path = rel_path(options[:action_queue] || latest_match("automation/action-queues/*-#{content_id}-03v-action-queue.yaml"))
next_unit_path = rel_path(options[:next_unit] || latest_match("automation/next-units/*-#{content_id}-harness-next-unit.yaml"))
founder_gate_path = rel_path(options[:founder_gate] || latest_match("automation/founder-gates/*-#{content_id}-03v-front-gate-*.yaml"))
current_next_path = rel_path(options[:current_next] || "automation/current-next.yaml")

usage_error("03V action queue could not be inferred") if blank?(action_queue_path)
usage_error("next-unit artifact could not be inferred") if blank?(next_unit_path)
usage_error("founder gate packet could not be inferred") if blank?(founder_gate_path)
usage_error("current-next pointer could not be inferred") if blank?(current_next_path)

begin
  current_context = IdolCurrentNextV2.load_active(
    path: current_next_path,
    run: run_rel,
    root: ROOT,
    require_actionable: true,
    require_legacy: %w[source_next_unit source_founder_gate source_action_queue],
    expected_legacy_paths: {
      "source_next_unit" => next_unit_path,
      "source_founder_gate" => founder_gate_path,
      "source_action_queue" => action_queue_path
    }
  )
  legacy_gate = IdolCurrentNextV2.require_03v_legacy_gate!(current_context)
rescue IdolCurrentNextV2::Error => error
  usage_error(error.message)
end
current_next = current_context.fetch("document")
action_queue = legacy_gate.fetch("action_queue")
next_unit = legacy_gate.fetch("next_unit")
founder_gate = legacy_gate.fetch("founder_gate")
worklist_path = rel_path(options[:worklist] || Array(action_queue["queues"]).first&.dig("worklist_artifact") || (run_path + "review/03v-section-video-prompt-qa-worklist-v1.yaml"))
worklist = load_yaml_hash(worklist_path)
active_decision = action_queue["active_founder_gate_decision"].is_a?(Hash) ? action_queue["active_founder_gate_decision"] : {}
continue_local_decision = active_decision["schema_version"].to_s == "harness-founder-decision.v1" &&
                          active_decision["status"].to_s == "active" &&
                          active_decision["decision_id"].to_s == "continue_local_next_section" &&
                          active_decision["continues_local_qa"] == true &&
                          active_decision["allows_paid_generation"] == false &&
                          active_decision["allows_external_execution"] == false &&
                          active_decision["marks_section_qa_pass"] == false
approved_generation_decision = active_decision["schema_version"].to_s == "harness-founder-decision.v1" &&
                               active_decision["status"].to_s == "active" &&
                               active_decision["decision_id"].to_s == "approve_front_chunk_generation" &&
                               active_decision["allows_paid_generation"] == true &&
                               active_decision["allows_external_execution"] == true &&
                               active_decision["continues_local_qa"] == false &&
                               active_decision["marks_section_qa_pass"] == false &&
                               !active_decision["approved_execution_route"].to_s.empty?

errors = []

unless worklist["run"].to_s == run_rel
  errors << "worklist run=#{worklist['run'].inspect}; expected #{run_rel.inspect}"
end
unless action_queue["run"].to_s == run_rel
  errors << "action queue run=#{action_queue['run'].inspect}; expected #{run_rel.inspect}"
end
unless next_unit["run"].to_s == run_rel
  errors << "next-unit run=#{next_unit['run'].inspect}; expected #{run_rel.inspect}"
end
unless founder_gate["run"].to_s == run_rel
  errors << "founder gate run=#{founder_gate['run'].inspect}; expected #{run_rel.inspect}"
end
unless current_next["run"].to_s == run_rel
  errors << "current-next run=#{current_next['run'].inspect}; expected #{run_rel.inspect}"
end

summary = worklist["summary"].is_a?(Hash) ? worklist["summary"] : {}
unless summary["front_playback_gate_ready"] == true
  errors << "worklist summary front_playback_gate_ready is not true"
end

range = summary["front_playback_gate_section_range"].to_s
section_ids = expand_section_range(range)
min_sections = summary["front_playback_gate_min_sections"].to_i
section_count = summary["front_playback_gate_section_count"].to_i
packet_count = summary["front_playback_gate_packet_count"].to_i
next_local_section = summary["front_playback_gate_next_local_section"].to_s
next_local_continuation_allowed = summary["front_playback_gate_next_local_continuation_allowed"] == true
auto_local_continuation = !continue_local_decision &&
                          active_decision.empty? &&
                          next_local_continuation_allowed &&
                          !next_local_section.empty? &&
                          next_unit["selected_unit_id"].to_s == "close_03v_section_qa:#{next_local_section}" &&
                          next_unit["status"].to_s == "selected" &&
                          next_unit["owner"].to_s == "codex" &&
                          next_unit["requires_founder_decision"] == false

errors << "front gate section range is missing" if range.empty?
errors << "front gate min sections must be positive" if min_sections <= 0
errors << "front gate section count #{section_count} is below minimum #{min_sections}" if section_count < min_sections
errors << "front gate packet count must be positive" if packet_count <= 0
errors << "front gate section ids #{section_ids.inspect} do not match section_count #{section_count}" if !range.empty? && section_ids.length != section_count

validate_generated_playback_artifacts(
  errors,
  run_rel,
  run_path,
  worklist_path,
  worklist,
  range,
  section_ids,
  packet_count,
  {
    intake: options[:playback_intake],
    worklist: options[:playback_worklist],
    decision_sheet: options[:playback_decision_sheet]
  }
)

section_queue = Array(worklist["section_queue"])
front_sections = section_ids.map { |section_id| section_by_key(worklist, section_id) }
front_sections.each_with_index do |section, index|
  unless section.is_a?(Hash) && !section.empty?
    errors << "#{section_ids[index]}: front gate section is missing from worklist"
    next
  end

  key = section["section_key"].to_s
  unless pass_worklist_section?(section) || playback_only_worklist_section?(section)
    errors << "#{key}: front gate section must be pass or partial with only generation_playback_probe=needs_founder"
  end
end

queue_items = Array(action_queue["queues"])
if queue_items.length != 1 || queue_items.first["source_check"].to_s != "video_prompt_section_qa_readiness"
  errors << "action queue must be focused on video_prompt_section_qa_readiness"
end
unless action_queue["source_state_report"].to_s == "focused_03v_queue_no_state_report"
  errors << "focused 03V action queue source_state_report must be focused_03v_queue_no_state_report"
end

front_unit_id = "front_03v_playback_gate:#{range}"
first_unit = Array(queue_items.first && queue_items.first["next_units"]).first || {}
if continue_local_decision
  unless next_local_continuation_allowed
    errors << "continue_local_next_section is active but the current front gate does not allow local continuation"
  end
  if Array(queue_items.first && queue_items.first["next_units"]).any? { |unit| unit.is_a?(Hash) && unit["id"].to_s == front_unit_id }
    errors << "action queue must not keep #{front_unit_id} after continue_local_next_section is active"
  end
  unless active_decision["section_range"].to_s == range
    errors << "active decision section_range=#{active_decision['section_range'].inspect}; expected #{range.inspect}"
  end
  unless active_decision["next_local_section"].to_s == summary["front_playback_gate_next_local_section"].to_s
    errors << "active decision next_local_section=#{active_decision['next_local_section'].inspect}; expected #{summary['front_playback_gate_next_local_section'].inspect}"
  end
elsif approved_generation_decision
  approved_unit_id = "prepare_03v_generation_playback:#{range}"
  unless first_unit["id"].to_s == approved_unit_id
    errors << "first action queue unit=#{first_unit['id'].inspect}; expected #{approved_unit_id.inspect}"
  end
  unless first_unit["requires_founder_decision"] == false
    errors << "approved generation action queue unit must not require another founder decision"
  end
  unless first_unit.dig("details", "approved_execution_route").to_s == active_decision["approved_execution_route"].to_s
    errors << "approved generation unit route=#{first_unit.dig('details', 'approved_execution_route').inspect}; expected #{active_decision['approved_execution_route'].inspect}"
  end
  validate_approved_generation_details(errors, "approved action queue unit", first_unit["details"].is_a?(Hash) ? first_unit["details"] : {}, active_decision, packet_count)
  unless Array(queue_items.first && queue_items.first["next_units"]).any? { |unit| unit.is_a?(Hash) && unit["id"].to_s == front_unit_id }
    errors << "action queue must keep #{front_unit_id} as the source gate audit unit after approval"
  end
  unless active_decision["section_range"].to_s == range
    errors << "active decision section_range=#{active_decision['section_range'].inspect}; expected #{range.inspect}"
  end
else
  unless first_unit["id"].to_s == front_unit_id
    errors << "first action queue unit=#{first_unit['id'].inspect}; expected #{front_unit_id.inspect}"
  end
  unless first_unit["requires_founder_decision"] == true
    errors << "front action queue unit must require founder decision"
  end
end

unless next_unit["source_action_queue"].to_s == action_queue_path
  errors << "next-unit source_action_queue=#{next_unit['source_action_queue'].inspect}; expected #{action_queue_path.inspect}"
end
if continue_local_decision || auto_local_continuation
  expected_next_unit = "close_03v_section_qa:#{next_local_section}"
  unless next_unit["selected_unit_id"].to_s == expected_next_unit
    errors << "next-unit selected_unit_id=#{next_unit['selected_unit_id'].inspect}; expected #{expected_next_unit.inspect}"
  end
  unless next_unit["status"].to_s == "selected" && next_unit["owner"].to_s == "codex"
    errors << "next-unit must be selected with owner codex when local QA continues past the front gate"
  end
  unless next_unit["requires_founder_decision"] == false
    errors << "next-unit must not require founder decision when local QA continues past the front gate"
  end
elsif approved_generation_decision
  expected_next_unit = "prepare_03v_generation_playback:#{range}"
  unless next_unit["selected_unit_id"].to_s == expected_next_unit
    errors << "next-unit selected_unit_id=#{next_unit['selected_unit_id'].inspect}; expected #{expected_next_unit.inspect}"
  end
  unless next_unit["status"].to_s == "selected" && next_unit["owner"].to_s == "codex"
    errors << "next-unit must be selected with owner codex after approved generation route"
  end
  unless next_unit["requires_founder_decision"] == false
    errors << "next-unit must not require another founder decision after approved generation route"
  end
  unless next_unit.dig("details", "approved_execution_route").to_s == active_decision["approved_execution_route"].to_s
    errors << "next-unit approved_execution_route must match active decision"
  end
  validate_approved_generation_details(errors, "approved next-unit", next_unit["details"].is_a?(Hash) ? next_unit["details"] : {}, active_decision, packet_count)
else
  unless next_unit["selected_unit_id"].to_s == front_unit_id
    errors << "next-unit selected_unit_id=#{next_unit['selected_unit_id'].inspect}; expected #{front_unit_id.inspect}"
  end
  unless next_unit["status"].to_s == "founder_input_needed" && next_unit["owner"].to_s == "founder"
    errors << "next-unit must be founder_input_needed with owner founder"
  end
  unless next_unit["requires_founder_decision"] == true
    errors << "next-unit must require founder decision"
  end
end

unless founder_gate["schema_version"].to_s == "harness-founder-gate.v1"
  errors << "founder gate schema_version=#{founder_gate['schema_version'].inspect}; expected harness-founder-gate.v1"
end
unless founder_gate["gate_type"].to_s == "03v_front_playback_generation"
  errors << "founder gate gate_type=#{founder_gate['gate_type'].inspect}; expected 03v_front_playback_generation"
end
unless founder_gate["status"].to_s == "founder_input_needed"
  errors << "founder gate status=#{founder_gate['status'].inspect}; expected founder_input_needed"
end
unless founder_gate["source_next_unit"].to_s == next_unit_path
  unless continue_local_decision && founder_gate["source_next_unit"].to_s == active_decision["source_next_unit"].to_s
    errors << "founder gate source_next_unit=#{founder_gate['source_next_unit'].inspect}; expected #{next_unit_path.inspect}"
  end
end
unless founder_gate["source_action_queue"].to_s == action_queue_path
  unless continue_local_decision && founder_gate["source_action_queue"].to_s == active_decision["source_action_queue"].to_s
    errors << "founder gate source_action_queue=#{founder_gate['source_action_queue'].inspect}; expected #{action_queue_path.inspect}"
  end
end
unless founder_gate["source_worklist"].to_s == worklist_path
  errors << "founder gate source_worklist=#{founder_gate['source_worklist'].inspect}; expected #{worklist_path.inspect}"
end
unless founder_gate["source_artifact"].to_s == next_unit["source_artifact"].to_s
  errors << "founder gate source_artifact=#{founder_gate['source_artifact'].inspect}; expected #{next_unit['source_artifact'].inspect}"
end
unless founder_gate.dig("selected_unit", "id").to_s == front_unit_id
  errors << "founder gate selected_unit.id=#{founder_gate.dig('selected_unit', 'id').inspect}; expected #{front_unit_id.inspect}"
end
unless founder_gate["section_range"].to_s == range
  errors << "founder gate section_range=#{founder_gate['section_range'].inspect}; expected #{range.inspect}"
end
unless Array(founder_gate["section_ids"]).map(&:to_s) == section_ids
  errors << "founder gate section_ids=#{Array(founder_gate['section_ids']).inspect}; expected #{section_ids.inspect}"
end
unless founder_gate["packet_count"].to_i == packet_count
  errors << "founder gate packet_count=#{founder_gate['packet_count'].inspect}; expected #{packet_count}"
end
unless Array(founder_gate.dig("current_local_status", "local_ready_sections")).map(&:to_s) == section_ids
  errors << "founder gate local_ready_sections must match front gate section ids"
end
unless founder_gate.dig("current_local_status", "remaining_check").to_s == "generation_playback_probe"
  errors << "founder gate remaining_check must be generation_playback_probe"
end
unless founder_gate.dig("current_local_status", "next_local_section").to_s == summary["front_playback_gate_next_local_section"].to_s
  errors << "founder gate next_local_section=#{founder_gate.dig('current_local_status', 'next_local_section').inspect}; expected #{summary['front_playback_gate_next_local_section'].inspect}"
end
unless founder_gate.dig("current_local_status", "next_local_continuation_allowed") == next_local_continuation_allowed
  errors << "founder gate next_local_continuation_allowed=#{founder_gate.dig('current_local_status', 'next_local_continuation_allowed').inspect}; expected #{next_local_continuation_allowed.inspect}"
end

decision_ids = Array(founder_gate["allowed_decisions"]).map { |decision| decision.is_a?(Hash) ? decision["id"].to_s : "" }
expected_decision_ids = %w[
  approve_front_chunk_generation
  review_or_refine_prompts_only
  hold_front_gate
]
expected_decision_ids.insert(2, "continue_local_next_section") if next_local_continuation_allowed && !next_local_section.empty?
unless decision_ids == expected_decision_ids
  errors << "founder gate allowed decision ids=#{decision_ids.inspect}; expected #{expected_decision_ids.inspect}"
end
approve = decision_by_id(founder_gate, "approve_front_chunk_generation")
unless approve["requires_explicit_approval"] == true &&
       approve["allows_paid_generation"] == true &&
       approve["allows_external_execution"] == true &&
       approve["marks_section_qa_pass"] == false
  errors << "approve_front_chunk_generation must require explicit approval, allow only scoped generation/external execution, and not mark QA pass"
end

review = decision_by_id(founder_gate, "review_or_refine_prompts_only")
unless review["allows_paid_generation"] == false &&
       review["allows_external_execution"] == false &&
       review["continues_local_qa"] == false &&
       review["marks_section_qa_pass"] == false
  errors << "review_or_refine_prompts_only must not allow generation/external execution/local S04 continuation/QA pass"
end

continue = decision_by_id(founder_gate, "continue_local_next_section")
if !next_local_continuation_allowed || next_local_section.empty?
  errors << "continue_local_next_section must not be offered when no local continuation is available" unless continue.empty?
else
  unless continue["allows_paid_generation"] == false &&
         continue["allows_external_execution"] == false &&
         continue["continues_local_qa"] == true &&
         continue["marks_section_qa_pass"] == false
    errors << "continue_local_next_section must only allow local QA continuation and not generation/external execution/QA pass"
  end
end

hold = decision_by_id(founder_gate, "hold_front_gate")
unless hold["allows_paid_generation"] == false &&
       hold["allows_external_execution"] == false &&
       hold["continues_local_qa"] == false &&
       hold["marks_section_qa_pass"] == false
  errors << "hold_front_gate must not allow generation/external execution/local continuation/QA pass"
end

if Array(founder_gate["forbidden_actions"]).none? { |action| action.to_s.include?(range) && action.to_s.include?("section QA pass") }
  errors << "founder gate must explicitly forbid marking #{range} section QA pass without playback evidence"
end
if Array(founder_gate["forbidden_actions"]).none? { |action| action.to_s.include?("wider scope") || action.to_s.include?("beyond #{range}") }
  errors << "founder gate must explicitly forbid wider-scope approval inference"
end

[
  ["action queue", action_queue],
  ["next-unit", next_unit],
  ["founder gate", founder_gate]
].each do |label, payload|
  require_refresh_command!(errors, label, payload, "idol_03v_generated_playback_intake.rb")
  require_refresh_command!(errors, label, payload, "idol_03v_playback_review_worklist.rb")
  require_refresh_command!(errors, label, payload, "idol_03v_playback_decision_sheet.rb")
end
require_refresh_command!(errors, "current-next", current_next, "idol_director_dispatch_index.rb build")
require_refresh_command!(errors, "current-next", current_next, "idol_director_dispatch_index.rb validate")
require_refresh_command!(errors, "current-next", current_next, "idol_harness_current_next.rb")
require_refresh_command!(errors, "current-next", current_next, "idol_harness_frontier_check.rb")

forbidden_commands = (collect_refresh_commands(action_queue) + collect_refresh_commands(next_unit) + collect_refresh_commands(founder_gate)).select do |command|
  command.match?(FORBIDDEN_COMMAND_PATTERN)
end
forbidden_commands += collect_refresh_commands(current_next).select do |command|
  command.match?(FORBIDDEN_COMMAND_PATTERN)
end
unless forbidden_commands.empty?
  errors << "focused 03V queue/next-unit/founder-gate/current-next contains forbidden edit/full-refresh command(s): #{forbidden_commands.join(' | ')}"
end

if errors.empty?
  mode = if continue_local_decision
           "continue_local_next_section"
         elsif approved_generation_decision
           "approved_generation_route_pending_playback"
         elsif auto_local_continuation
           "auto_local_next_section"
         else
           "founder_gate_pending"
         end
  frontier = current_context.fetch("selection")
  puts "OK: front 03V playback gate #{range} verified (mode=#{mode}, sections=#{section_count}, packets=#{packet_count}, min=#{min_sections}, founder_gate=#{founder_gate_path}, current_next=#{current_next_path}, ddi_frontier=#{frontier['id']})"
  exit 0
end

errors.each { |error| warn "ERROR: #{error}" }
exit 1
