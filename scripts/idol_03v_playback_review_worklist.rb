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
  warn "usage: ruby scripts/idol_03v_playback_review_worklist.rb RUN_ROOT [--intake PATH] [--output-yaml PATH] [--output-md PATH] [--write]"
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

def packet_signature(packet)
  return "" unless packet.is_a?(Hash)

  [
    packet["packet_id"],
    packet["timeline"],
    packet["audio_motion_slot"],
    packet["prompt_path"],
    packet["start_image"],
    packet["end_image"],
    packet["upload_pack"]
  ].map(&:to_s).join("|")
end

def markdown_table_row(values)
  "| #{values.map { |value| value.to_s.gsub("|", "\\|") }.join(" | ")} |"
end

def review_checks(packet)
  start_audio = packet["start_audio_cue"].to_s
  end_audio = packet["end_audio_cue"].to_s
  prev_bridge = packet["prev_end_to_start"].to_s
  next_bridge = packet["end_to_next_start"].to_s
  [
    {
      "id" => "start_frame_lock",
      "label" => "Start frame matches @image1",
      "pass_condition" => "The clip opens from the declared @image1 pose, outfit, identity, camera height, and current-run scene space without an invented pre-roll.",
      "hold_or_fix_if" => "Hold if the first visible frame changes identity, outfit, pose, camera angle, or environment before the action begins."
    },
    {
      "id" => "endpoint_lock",
      "label" => "Endpoint lands on @image2",
      "pass_condition" => "The final readable beat lands on @image2 with the declared body position, gaze, camera framing, and space geometry intact.",
      "hold_or_fix_if" => "Hold if the clip drifts past @image2, morphs into a different endpoint, or hides the landing with blur/crop."
    },
    {
      "id" => "audio_timing",
      "label" => "Visible motion follows the cue timing",
      "pass_condition" => "The visible start action answers #{start_audio.empty? ? 'the start cue' : start_audio} and resolves by #{end_audio.empty? ? 'the end cue' : end_audio}.",
      "hold_or_fix_if" => "Hold if the motion floats without hitting the stated audio cue, bass accent, snare, or endpoint timing."
    },
    {
      "id" => "body_route",
      "label" => "Body route remains readable",
      "pass_condition" => "Feet, weight shift, torso, hands, gaze, and garment reaction travel through one plausible route from @image1 to @image2.",
      "hold_or_fix_if" => "Hold if limbs pop, the body teleports, the pose cannot physically connect, or the main action is replaced by generic dancing."
    },
    {
      "id" => "camera_route",
      "label" => "Camera route supports the action",
      "pass_condition" => "Camera height, angle, movement, subject scale, and endpoint framing make the body action and endpoint visible.",
      "hold_or_fix_if" => "Hold if the camera hides feet/hands/face needed for the beat, invents an unrelated angle, or breaks the endpoint frame."
    },
    {
      "id" => "identity_body_stability",
      "label" => "Identity and proportions stay stable",
      "pass_condition" => "Face identity, body proportions, wardrobe, and count of visible performers stay stable across the clip.",
      "hold_or_fix_if" => "Hold if faces drift, performer count changes, limbs distort, wardrobe swaps, or body proportions collapse."
    },
    {
      "id" => "space_object_evidence",
      "label" => "Declared space and object evidence survives",
      "pass_condition" => "The current run's declared environment, depth, floor/reflection, and object evidence stays visible or reacts in the way the prompt requires.",
      "hold_or_fix_if" => "Hold if the clip collapses into a person-only void, generic stage, unrelated room, or object-free close-up."
    },
    {
      "id" => "continuity_cut_basis",
      "label" => "Cut basis remains usable",
      "pass_condition" => "The carried motion from #{prev_bridge.empty? ? 'the previous endpoint' : prev_bridge} and into #{next_bridge.empty? ? 'the next start' : next_bridge} remains plausible for the next packet.",
      "hold_or_fix_if" => "Hold if the clip creates an impossible pose jump, direction reversal, camera mismatch, or space mismatch at either boundary."
    }
  ]
end

def section_status(packets)
  present = packets.count { |packet| packet["clip_status"] == "present" }
  missing = packets.length - present
  return "waiting_clip" if present.zero?
  return "partial_clip_intake" if missing.positive?

  "pending_review"
end

def review_action_for(clip)
  if clip["clip_status"].to_s == "present"
    "Review the generated clip against every required check. Record hold/fix/pass evidence before changing generation_playback_probe."
  elsif clip_file_status(clip) == "present_probe_failed"
    "Replace this unplayable clip file, then rerun intake and this review worklist."
  else
    "Collect or generate this clip at one of the candidate paths, then rerun intake and this review worklist."
  end
end

def clip_file_status(clip)
  explicit = clip["clip_file_status"].to_s
  return explicit unless explicit.empty?

  clip["clip_status"].to_s == "present" ? "present_probe_ok" : "missing"
end

def default_media_probe(status)
  {
    "status" => status == "present_probe_ok" ? "ok" : "not_run",
    "playable" => status == "present_probe_ok",
    "duration_seconds" => 0.0,
    "video_stream_count" => 0,
    "audio_stream_count" => 0,
    "width" => 0,
    "height" => 0,
    "codec_name" => "",
    "error" => status == "present_probe_ok" ? "" : "not_recorded"
  }
end

def media_probe_for(clip, status)
  return clip["media_probe"] if clip["media_probe"].is_a?(Hash)

  default_media_probe(status)
end

options = {
  intake: nil,
  output_yaml: nil,
  output_md: nil,
  write: false
}

OptionParser.new do |parser|
  parser.on("--intake PATH") { |value| options[:intake] = value }
  parser.on("--output-yaml PATH") { |value| options[:output_yaml] = value }
  parser.on("--output-md PATH") { |value| options[:output_md] = value }
  parser.on("--write") { options[:write] = true }
end.parse!

run_arg = ARGV.shift
usage_error("RUN_ROOT is required") if blank?(run_arg)

run_path = resolve_path(run_arg)
usage_error("RUN_ROOT is not a directory: #{run_arg}") unless run_path && Dir.exist?(run_path.to_s)
run_rel = rel_path(run_path)

intake_path = options[:intake] || latest_match(run_path, "review/03v-generated-playback-intake-v*.yaml")
usage_error("03V generated playback intake could not be inferred") if blank?(intake_path)
intake_path = rel_path(intake_path)
intake = load_yaml_hash(intake_path)
usage_error("intake run=#{intake['run'].inspect}; expected #{run_rel.inspect}") unless intake["run"].to_s == run_rel

worklist_path = intake["source_worklist"].to_s
usage_error("intake source_worklist is missing") if blank?(worklist_path)
worklist = load_yaml_hash(worklist_path)

output_yaml = options[:output_yaml] || rel_path(run_path + "review/03v-playback-review-worklist-v1.yaml")
output_md = options[:output_md] || output_yaml.sub(/\.ya?ml\z/, ".md")

sections_by_key = Array(worklist["section_queue"]).each_with_object({}) do |section, memo|
  next unless section.is_a?(Hash)

  memo[section["section_key"].to_s] = section
end

clips_by_packet = Array(intake["clip_queue"]).each_with_object({}) do |clip, memo|
  next unless clip.is_a?(Hash)

  memo[clip["packet_id"].to_s] = clip
end

section_ids = Array(intake["section_ids"]).map(&:to_s)
section_reviews = section_ids.map do |section_key|
  section = sections_by_key[section_key] || {}
  packets = Array(section["packets"]).map do |packet|
    next unless packet.is_a?(Hash)

    clip = clips_by_packet[packet["packet_id"].to_s] || {}
    clip_status = clip["clip_status"].to_s.empty? ? "missing" : clip["clip_status"].to_s
    file_status = clip_file_status(clip)
    probe = media_probe_for(clip, file_status)
    {
      "packet_id" => packet["packet_id"].to_s,
      "section_key" => section_key,
      "timeline" => packet["timeline"].to_s,
      "audio_motion_slot" => packet["audio_motion_slot"].to_s,
      "clip_status" => clip_status,
      "clip_file_status" => file_status,
      "media_probe" => probe,
      "playback_review_status" => clip_status == "present" ? "pending_review" : "waiting_clip",
      "generated_clip_path" => clip["generated_clip_path"].to_s,
      "generated_clip_sha256" => clip["generated_clip_sha256"].to_s,
      "prompt_path" => packet["prompt_path"].to_s,
      "start_image" => packet["start_image"].to_s,
      "end_image" => packet["end_image"].to_s,
      "upload_pack" => packet["upload_pack"].to_s,
      "upload_prompt" => clip["upload_prompt"].to_s.empty? ? File.join(packet["upload_pack"].to_s, "prompt.txt") : clip["upload_prompt"].to_s,
      "start_audio_cue" => packet["start_audio_cue"].to_s,
      "end_audio_cue" => packet["end_audio_cue"].to_s,
      "prev_end_to_start" => packet["prev_end_to_start"].to_s,
      "end_to_next_start" => packet["end_to_next_start"].to_s,
      "required_checks" => review_checks(packet),
      "review_action" => review_action_for(clip)
    }
  end.compact
  present = packets.count { |packet| packet["clip_status"] == "present" }
  missing = packets.length - present
  media_probe_issues = packets.count { |packet| packet["clip_file_status"] == "present_probe_failed" }
  {
    "section_key" => section_key,
    "section_label" => section["section_label"].to_s,
    "section_status" => section["status"].to_s,
    "packet_count" => packets.length,
    "present_clip_count" => present,
    "missing_clip_count" => missing,
    "media_probe_issue_count" => media_probe_issues,
    "playback_review_status" => section_status(packets),
    "section_pass_rule" => "All packets in #{section_key} must have a present generated clip and pass every required playback check before generation_playback_probe can be changed from needs_founder.",
    "entry_continuity" => section["entry_continuity"].to_s,
    "exit_continuity" => section["exit_continuity"].to_s,
    "packets" => packets
  }
end

packet_reviews = section_reviews.flat_map { |section| Array(section["packets"]) }
present_count = packet_reviews.count { |packet| packet["clip_status"] == "present" }
missing_count = packet_reviews.length - present_count
media_probe_issue_count = packet_reviews.count { |packet| packet["clip_file_status"] == "present_probe_failed" }
pending_count = packet_reviews.count { |packet| packet["playback_review_status"] == "pending_review" }
status = if present_count.zero?
           "waiting_for_clips"
         elsif missing_count.positive?
           "partial_clip_intake"
         else
           "pending_playback_review"
         end

payload = {
  "schema_version" => "idol_03v_playback_review_worklist.v1",
  "generated_at" => Time.now.iso8601,
  "run" => run_rel,
  "status" => status,
  "route" => intake["route"].to_s,
  "source_intake" => intake_path,
  "source_worklist" => worklist_path,
  "source_section_qa" => intake["source_section_qa"].to_s,
  "section_range" => intake["section_range"].to_s,
  "section_ids" => section_ids,
  "clips_root" => intake["clips_root"].to_s,
  "summary" => {
    "section_count" => section_reviews.length,
    "packet_count" => packet_reviews.length,
    "present_clip_count" => present_count,
    "missing_clip_count" => missing_count,
    "media_probe_issue_count" => media_probe_issue_count,
    "pending_playback_review_count" => pending_count,
    "required_check_count" => packet_reviews.sum { |packet| Array(packet["required_checks"]).length }
  },
  "section_reviews" => section_reviews,
  "automation_boundaries" => [
    "This review worklist does not approve generation, section QA pass, publishing, Drive mutation, or edit readiness.",
    "Do not mark generation_playback_probe pass until every packet in the section has a present clip and recorded playback evidence.",
    "A clean S00-S03 playback review may justify continuing the next 03V chunk, but it does not approve wider generation scope by implication."
  ]
}

lines = []
lines << "# 03V Playback Review Worklist"
lines << ""
lines << "generated_at: #{payload['generated_at']}"
lines << "run: `#{run_rel}`"
lines << "status: `#{status}`"
lines << "route: `#{payload['route']}`"
lines << "section_range: `#{payload['section_range']}`"
lines << "sections: #{section_ids.map { |id| "`#{id}`" }.join(', ')}"
lines << "source_intake: `#{intake_path}`"
lines << "source_worklist: `#{worklist_path}`"
lines << "clips_root: `#{payload['clips_root']}`"
lines << "structured_worklist: `#{output_yaml}`"
lines << ""
lines << "This worklist narrows generated playback review to visible evidence checks. It does not mark `generation_playback_probe` pass."
lines << ""
lines << "## Summary"
lines << ""
payload["summary"].each { |key, value| lines << "- #{key}: #{value}" }
lines << ""
payload["section_reviews"].each do |section|
  lines << "## #{section['section_key']} #{section['section_label']}"
  lines << ""
  lines << "- status: `#{section['playback_review_status']}`"
  lines << "- clips: present #{section['present_clip_count']} / missing #{section['missing_clip_count']}"
  lines << "- media_probe_issues: #{section['media_probe_issue_count']}"
  lines << "- pass_rule: #{section['section_pass_rule']}"
  lines << "- entry_continuity: #{section['entry_continuity']}" unless section["entry_continuity"].empty?
  lines << "- exit_continuity: #{section['exit_continuity']}" unless section["exit_continuity"].empty?
  lines << ""
  lines << "| packet | timeline | clip | file_status | probe | review | generated_clip |"
  lines << "| --- | --- | --- | --- | --- | --- | --- |"
  section["packets"].each do |packet|
    probe = packet["media_probe"].is_a?(Hash) ? packet["media_probe"] : {}
    lines << markdown_table_row([
      "`#{packet['packet_id']}`",
      packet["timeline"],
      "`#{packet['clip_status']}`",
      "`#{packet['clip_file_status']}`",
      "`#{probe['status']}`",
      "`#{packet['playback_review_status']}`",
      packet["generated_clip_path"].empty? ? "" : "`#{packet['generated_clip_path']}`"
    ])
  end
  lines << ""
end
lines << "## Required Checks"
lines << ""
lines << "Apply these checks to every present clip before changing `generation_playback_probe`:"
review_checks({}).each do |check|
  lines << "- `#{check['id']}`: #{check['pass_condition']}"
end
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
else
  puts YAML.dump(payload)
end
