#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "open3"
require "optparse"
require "pathname"
require "time"
require "yaml"

ROOT = Pathname.new(Dir.pwd).cleanpath

FOCUS_CHECK_LABELS = {
  "start_frame_lock" => "Start frame matches @image1 before motion begins.",
  "endpoint_lock" => "Final readable beat lands on @image2 without drift or hidden crop.",
  "audio_timing" => "Motion hits the stated audio cue and resolves by the endpoint cue; any lyric text remains verbatim.",
  "body_route" => "Feet, weight, torso, hands, gaze, and garment motion connect plausibly.",
  "camera_route" => "Camera height, angle, movement, and framing keep the required body action readable.",
  "identity_body_stability" => "Face identity, performer count, wardrobe, and proportions stay stable.",
  "space_object_evidence" => "Airport/cargo/shutter/floor/object evidence remains visible and usable.",
  "continuity_cut_basis" => "Entry and exit can cut to adjacent packets without pose, direction, camera, or space mismatch."
}.freeze

def usage_error(message)
  warn "ERROR: #{message}"
  warn "usage: ruby scripts/idol_03v_playback_decision_sheet.rb RUN_ROOT [--worklist PATH] [--output-yaml PATH] [--output-md PATH] [--write]"
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
  usage_error("file is not readable: #{path}") unless resolved && File.file?(resolved.to_s)

  doc = YAML.load_file(resolved.to_s)
  return doc if doc.is_a?(Hash)

  usage_error("YAML root must be a mapping: #{path}")
rescue Psych::SyntaxError => e
  usage_error("YAML syntax error in #{path}: #{e.message}")
end

def latest_match(run_path, pattern)
  matches = Dir.glob((run_path + pattern).to_s).select { |path| File.file?(path) }
  return nil if matches.empty?

  matches.sort_by do |path|
    version = File.basename(path).match(/(?:^|[-_])v(\d+)(?:\D|$)/)&.[](1)&.to_i || -1
    [version, File.mtime(path), path]
  end.last
end

def run_command!(*command)
  stdout, stderr, status = Open3.capture3(*command, chdir: ROOT.to_s)
  puts stdout unless stdout.empty?
  warn stderr unless stderr.empty?
  usage_error("command failed: #{command.join(' ')}") unless status.success?
  stdout
end

def validate_schema!(schema_path, document_path)
  run_command!(
    "scripts/idol-video-python",
    "scripts/validate_json_schema.py",
    schema_path,
    document_path
  )
end

def markdown_table_row(values)
  "| #{values.map { |value| value.to_s.gsub("|", "\\|") }.join(" | ")} |"
end

def focus_checks(packet)
  checks = Array(packet["required_checks"]).map do |check|
    next nil unless check.is_a?(Hash)

    check["id"].to_s
  end.compact
  return checks unless checks.empty?

  %w[
    start_frame_lock
    endpoint_lock
    audio_timing
    body_route
    camera_route
    identity_body_stability
    space_object_evidence
    continuity_cut_basis
  ]
end

def packet_clip_file_status(packet)
  explicit = packet["clip_file_status"].to_s
  return explicit unless explicit.empty?

  packet["clip_status"].to_s == "present" ? "present_probe_ok" : "missing"
end

def visible_review_prompt(packet)
  return "Unplayable clip file: replace it and rerun intake before playback review." if packet_clip_file_status(packet) == "present_probe_failed"
  return "Missing clip: import or generate this packet before playback review." unless packet["clip_status"].to_s == "present"

  "Check that the clip opens on @image1, hits the stated cue with readable body/camera motion, lands on @image2, keeps identity/space stable, and leaves a usable cut into the next packet."
end

def pass_blocker(packet)
  return "unplayable_clip" if packet_clip_file_status(packet) == "present_probe_failed"
  return "missing_clip" unless packet["clip_status"].to_s == "present"

  ""
end

def decision_status(summary)
  present = summary["present_clip_count"].to_i
  missing = summary["missing_clip_count"].to_i
  media_probe_issues = summary["media_probe_issue_count"].to_i
  return "waiting_for_clips" if present.zero?
  return "partial_clip_intake" if missing.positive? || media_probe_issues.positive?

  "ready_for_founder_playback_decision"
end

options = {
  worklist: nil,
  output_yaml: nil,
  output_md: nil,
  write: false
}

OptionParser.new do |parser|
  parser.on("--worklist PATH") { |value| options[:worklist] = value }
  parser.on("--output-yaml PATH") { |value| options[:output_yaml] = value }
  parser.on("--output-md PATH") { |value| options[:output_md] = value }
  parser.on("--write") { options[:write] = true }
end.parse!

run_arg = ARGV.shift
usage_error("RUN_ROOT is required") if blank?(run_arg)

run_path = resolve_path(run_arg)
usage_error("RUN_ROOT is not a directory: #{run_arg}") unless run_path && Dir.exist?(run_path.to_s)
run_rel = rel_path(run_path)

worklist_path = options[:worklist] || latest_match(run_path, "review/03v-playback-review-worklist-v*.yaml")
usage_error("03V playback review worklist could not be inferred") if blank?(worklist_path)
worklist_path = rel_path(worklist_path)
worklist = load_yaml_hash(worklist_path)
usage_error("worklist run=#{worklist['run'].inspect}; expected #{run_rel.inspect}") unless worklist["run"].to_s == run_rel

output_yaml = options[:output_yaml] || rel_path(run_path + "review/03v-playback-decision-sheet-v1.yaml")
output_md = options[:output_md] || output_yaml.sub(/\.ya?ml\z/, ".md")

summary = worklist["summary"].is_a?(Hash) ? worklist["summary"] : {}
status = decision_status(summary)
section_range = worklist["section_range"].to_s
section_ids = Array(worklist["section_ids"]).map(&:to_s)
packet_rows = []
sections = Array(worklist["section_reviews"]).map do |section|
  next unless section.is_a?(Hash)

  packets = Array(section["packets"]).map do |packet|
    next nil unless packet.is_a?(Hash)

    row = {
      "packet_id" => packet["packet_id"].to_s,
      "section_key" => packet["section_key"].to_s,
      "timeline" => packet["timeline"].to_s,
      "clip_status" => packet["clip_status"].to_s,
      "clip_file_status" => packet_clip_file_status(packet),
      "media_probe_status" => packet.dig("media_probe", "status").to_s.empty? ? "not_run" : packet.dig("media_probe", "status").to_s,
      "media_probe_error" => packet.dig("media_probe", "error").to_s,
      "playback_review_status" => packet["playback_review_status"].to_s,
      "generated_clip_path" => packet["generated_clip_path"].to_s,
      "generated_clip_sha256" => packet["generated_clip_sha256"].to_s,
      "visible_review_prompt" => visible_review_prompt(packet),
      "focus_checks" => focus_checks(packet),
      "pass_blocker" => pass_blocker(packet)
    }
    packet_rows << row
    row
  end.compact

  {
    "section_key" => section["section_key"].to_s,
    "section_label" => section["section_label"].to_s,
    "section_status" => section["section_status"].to_s,
    "playback_review_status" => section["playback_review_status"].to_s,
    "packet_count" => section["packet_count"].to_i,
    "present_clip_count" => section["present_clip_count"].to_i,
    "missing_clip_count" => section["missing_clip_count"].to_i,
    "media_probe_issue_count" => section["media_probe_issue_count"].to_i,
    "founder_question" => if section["media_probe_issue_count"].to_i.positive?
                            "Unplayable clip files remain in #{section['section_key']}; replace them before pass."
                          elsif section["missing_clip_count"].to_i.positive?
                            "Missing clips remain in #{section['section_key']}; generate/import them before pass."
                          else
                            "Can #{section['section_key']} pass playback on start frame, endpoint, cue timing, body/camera route, identity/space stability, and continuity?"
                          end,
    "packet_ids" => packets.map { |packet| packet["packet_id"].to_s }
  }
end.compact

response_contract = {
  "pass_reply" => "#{section_range} pass: all clips match start/end frames, cue timing, body/camera route, identity, space, and continuity",
  "hold_reply" => "#{section_range} hold: <visible reason>",
  "fix_reply" => "fix PKT_Bxx: <visible issue and target change>",
  "apply_pass_command_template" => "ruby scripts/idol_03v_apply_playback_decision.rb #{run_rel} --from-text \"#{section_range} pass: <visible playback note>\" --explicit-founder-review --write",
  "apply_hold_command_template" => "ruby scripts/idol_03v_apply_playback_decision.rb #{run_rel} --from-text \"#{section_range} hold: <visible playback note>\" --write",
  "apply_fix_command_template" => "ruby scripts/idol_03v_apply_playback_decision.rb #{run_rel} --from-text \"fix PKT_Bxx: <visible issue and target change>\" --write"
}

payload = {
  "schema_version" => "idol_03v_playback_decision_sheet.v1",
  "generated_at" => Time.now.iso8601,
  "run" => run_rel,
  "status" => status,
  "route" => worklist["route"].to_s,
  "source_playback_worklist" => worklist_path,
  "source_intake" => worklist["source_intake"].to_s,
  "source_section_qa" => worklist["source_section_qa"].to_s,
  "section_range" => section_range,
  "section_ids" => section_ids,
  "clips_root" => worklist["clips_root"].to_s,
  "summary" => {
    "section_count" => summary["section_count"].to_i,
    "packet_count" => summary["packet_count"].to_i,
    "present_clip_count" => summary["present_clip_count"].to_i,
    "missing_clip_count" => summary["missing_clip_count"].to_i,
    "media_probe_issue_count" => summary["media_probe_issue_count"].to_i,
    "pending_playback_review_count" => summary["pending_playback_review_count"].to_i,
    "required_check_count" => summary["required_check_count"].to_i
  },
  "response_contract" => response_contract,
  "sections" => sections,
  "packet_rows" => packet_rows,
  "automation_boundaries" => [
    "This sheet is a founder/operator decision surface only; it does not mark generation_playback_probe pass.",
    "Pass is blocked until every packet in the target range has a present generated clip with an ok media probe.",
    "Use the apply command only after explicit founder-reviewed playback evidence.",
    "This command does not approve paid generation, Drive mutation, publishing, packaging, or edit readiness."
  ]
}

lines = []
lines << "# 03V Playback Decision Sheet"
lines << ""
lines << "generated_at: #{payload['generated_at']}"
lines << "run: `#{run_rel}`"
lines << "status: `#{status}`"
lines << "section_range: `#{section_range}`"
lines << "clips_root: `#{payload['clips_root']}`"
lines << "source_playback_worklist: `#{worklist_path}`"
lines << "structured_sheet: `#{output_yaml}`"
lines << ""
if status == "ready_for_founder_playback_decision"
  lines << "Founder reply can be one line:"
  lines << ""
  lines << "```text"
  lines << response_contract["pass_reply"]
  lines << "```"
else
  lines << "Playback pass is currently blocked because generated clips are missing, incomplete, or unplayable."
end
lines << ""
lines << "## Reply Options"
lines << ""
lines << "- pass: `#{response_contract['pass_reply']}`"
lines << "- hold: `#{response_contract['hold_reply']}`"
lines << "- fix: `#{response_contract['fix_reply']}`"
lines << ""
lines << "## Summary"
lines << ""
payload["summary"].each { |key, value| lines << "- #{key}: #{value}" }
lines << ""
lines << "## Gate Pass Checklist"
lines << ""
FOCUS_CHECK_LABELS.each do |check_id, label|
  lines << "- `#{check_id}`: #{label}"
end
lines << ""
lines << "## Section Questions"
lines << ""
lines << "| section | packets | clips | question |"
lines << "| --- | --- | --- | --- |"
sections.each do |section|
  clips = "#{section['present_clip_count']} present / #{section['missing_clip_count']} missing / #{section['media_probe_issue_count']} probe issue"
  lines << markdown_table_row([
    "`#{section['section_key']}`",
    section["packet_ids"].join(", "),
    clips,
    section["founder_question"]
  ])
end
lines << ""
lines << "## Packet Review Rows"
lines << ""
lines << "| packet | section | timeline | clip | file_status | probe | focus checks | review prompt | generated clip |"
lines << "| --- | --- | --- | --- | --- | --- | --- | --- | --- |"
packet_rows.each do |row|
  lines << markdown_table_row([
    "`#{row['packet_id']}`",
    "`#{row['section_key']}`",
    row["timeline"],
    "`#{row['clip_status']}`",
    "`#{row['clip_file_status']}`",
    "`#{row['media_probe_status']}`",
    row["focus_checks"].join(", "),
    row["visible_review_prompt"],
    row["generated_clip_path"].empty? ? "" : "`#{row['generated_clip_path']}`"
  ])
end
lines << ""
lines << "## Apply Commands"
lines << ""
lines << "- pass: `#{response_contract['apply_pass_command_template']}`"
lines << "- hold: `#{response_contract['apply_hold_command_template']}`"
lines << "- fix: `#{response_contract['apply_fix_command_template']}`"
lines << ""
lines << "## Boundaries"
lines << ""
payload["automation_boundaries"].each { |boundary| lines << "- #{boundary}" }

if options[:write]
  yaml_path = resolve_path(output_yaml)
  md_path = resolve_path(output_md)
  FileUtils.mkdir_p(yaml_path.dirname)
  FileUtils.mkdir_p(md_path.dirname)
  yaml_path.write(YAML.dump(payload), encoding: "utf-8")
  md_path.write(lines.join("\n"), encoding: "utf-8")
  puts "wrote #{rel_path(yaml_path)}"
  puts "wrote #{rel_path(md_path)}"
  validate_schema!("schemas/03v-playback-decision-sheet.schema.json", rel_path(yaml_path))
else
  puts YAML.dump(payload)
end
