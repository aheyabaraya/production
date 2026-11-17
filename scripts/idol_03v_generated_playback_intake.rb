#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "optparse"
require "pathname"
require "time"
require "yaml"

ROOT = Pathname.new(Dir.pwd).cleanpath
VIDEO_EXTENSIONS = %w[.mp4 .mov .m4v .webm].freeze

def usage_error(message)
  warn "ERROR: #{message}"
  warn "usage: ruby scripts/idol_03v_generated_playback_intake.rb RUN_ROOT [--worklist PATH] [--route ROUTE] [--clips-root PATH] [--output-yaml PATH] [--output-md PATH] [--write]"
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

def slug(value)
  value.to_s.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-+\z/, "")
end

def upload_pack_slug(upload_pack)
  File.basename(upload_pack.to_s)
end

def candidate_clip_paths(clips_root, packet_id, upload_pack)
  pack_slug = upload_pack_slug(upload_pack)
  packet_stem = packet_id.to_s.sub(/\APKT_/, "")
  stems = [pack_slug, packet_id.to_s, packet_stem].reject(&:empty?).uniq
  stems.flat_map do |stem|
    VIDEO_EXTENSIONS.map { |ext| File.join(clips_root, "#{stem}#{ext}") }
  end
end

def first_existing_path(paths)
  Array(paths).find { |path| File.file?(resolve_path(path).to_s) }.to_s
end

def run_command!(*command)
  stdout, stderr, status = Open3.capture3(*command, chdir: ROOT.to_s)
  puts stdout unless stdout.empty?
  warn stderr unless stderr.empty?
  usage_error("command failed: #{command.join(' ')}") unless status.success?
  stdout
end

def media_probe(path)
  resolved = resolve_path(path)
  return media_probe_skipped("file_missing") unless resolved && File.file?(resolved.to_s)

  python = <<~'PY'
    import json
    import shutil
    import subprocess
    import sys

    path = sys.argv[1]
    ffprobe = shutil.which("ffprobe")
    if not ffprobe:
        print(json.dumps({"error": "ffprobe missing"}))
        raise SystemExit(127)

    proc = subprocess.run(
        [
            ffprobe,
            "-v",
            "error",
            "-print_format",
            "json",
            "-show_format",
            "-show_streams",
            path,
        ],
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        print(json.dumps({
            "status": "probe_failed",
            "playable": False,
            "duration_seconds": 0.0,
            "video_stream_count": 0,
            "audio_stream_count": 0,
            "width": 0,
            "height": 0,
            "codec_name": "",
            "error": (proc.stderr or proc.stdout or "ffprobe failed").strip()[:500],
        }))
        raise SystemExit(0)

    data = json.loads(proc.stdout or "{}")
    streams = data.get("streams") or []
    video_streams = [stream for stream in streams if stream.get("codec_type") == "video"]
    audio_streams = [stream for stream in streams if stream.get("codec_type") == "audio"]
    first_video = video_streams[0] if video_streams else {}

    duration_value = (data.get("format") or {}).get("duration") or first_video.get("duration") or 0
    try:
        duration = float(duration_value)
    except (TypeError, ValueError):
        duration = 0.0

    width = int(first_video.get("width") or 0)
    height = int(first_video.get("height") or 0)
    playable = duration > 0 and len(video_streams) > 0 and width > 0 and height > 0

    print(json.dumps({
        "status": "ok" if playable else "probe_failed",
        "playable": playable,
        "duration_seconds": round(duration, 6),
        "video_stream_count": len(video_streams),
        "audio_stream_count": len(audio_streams),
        "width": width,
        "height": height,
        "codec_name": str(first_video.get("codec_name") or ""),
        "error": "" if playable else "missing positive duration or video dimensions",
    }))
  PY
  stdout, stderr, status = Open3.capture3(
    "scripts/idol-video-python",
    "-c",
    python,
    resolved.to_s,
    chdir: ROOT.to_s
  )
  unless status.success?
    warn stdout unless stdout.empty?
    warn stderr unless stderr.empty?
    usage_error("media probe failed before generated playback intake could continue: #{resolved}")
  end
  JSON.parse(stdout)
rescue JSON::ParserError => e
  usage_error("media probe returned invalid JSON for #{path}: #{e.message}")
end

def media_probe_skipped(reason)
  {
    "status" => "not_run",
    "playable" => false,
    "duration_seconds" => 0.0,
    "video_stream_count" => 0,
    "audio_stream_count" => 0,
    "width" => 0,
    "height" => 0,
    "codec_name" => "",
    "error" => reason.to_s
  }
end

def media_probe_issue?(probe)
  !probe.is_a?(Hash) || probe["playable"] != true || probe["status"].to_s != "ok"
end

def upload_prompt(upload_pack)
  return "" if blank?(upload_pack)

  File.join(upload_pack, "prompt.txt")
end

def markdown_table_row(values)
  "| #{values.map { |value| value.to_s.gsub("|", "\\|") }.join(" | ")} |"
end

def expand_section_range(range)
  match = range.to_s.match(/\AS(\d{2})-S(\d{2})\z/)
  return range.to_s.split("-", 2).reject(&:empty?) unless match

  first = match[1].to_i
  last = match[2].to_i
  return ["S#{format('%02d', first)}"] if last < first

  (first..last).map { |number| "S#{format('%02d', number)}" }
end

options = {
  worklist: nil,
  route: "grok_manual_drive_mirror",
  clips_root: nil,
  output_yaml: nil,
  output_md: nil,
  write: false
}

OptionParser.new do |parser|
  parser.on("--worklist PATH") { |value| options[:worklist] = value }
  parser.on("--route ROUTE") { |value| options[:route] = value }
  parser.on("--clips-root PATH") { |value| options[:clips_root] = value }
  parser.on("--output-yaml PATH") { |value| options[:output_yaml] = value }
  parser.on("--output-md PATH") { |value| options[:output_md] = value }
  parser.on("--write") { options[:write] = true }
end.parse!

run_arg = ARGV.shift
usage_error("RUN_ROOT is required") if blank?(run_arg)

run_path = resolve_path(run_arg)
usage_error("RUN_ROOT is not a directory: #{run_arg}") unless run_path && Dir.exist?(run_path.to_s)

run_rel = rel_path(run_path)
worklist_path = options[:worklist] || latest_match(run_path, "review/03v-section-video-prompt-qa-worklist-v*.yaml")
usage_error("03V section QA worklist could not be inferred") if blank?(worklist_path)
worklist_path = rel_path(worklist_path)
worklist = load_yaml_hash(worklist_path)

summary = worklist["summary"].is_a?(Hash) ? worklist["summary"] : {}
section_range = summary["front_playback_gate_section_range"].to_s
section_range = "S00-S00" if section_range.empty?
section_ids = expand_section_range(section_range)
route = options[:route].to_s
clips_root = options[:clips_root]
clips_root ||= rel_path(run_path + "generations/video/generated-clips/03v/#{slug(section_range)}/#{slug(route)}")
output_yaml = options[:output_yaml] || rel_path(run_path + "review/03v-generated-playback-intake-v1.yaml")
output_md = options[:output_md] || output_yaml.sub(/\.ya?ml\z/, ".md")

clip_queue = []
Array(worklist["section_queue"]).each do |section|
  next unless section.is_a?(Hash)

  section_key = section["section_key"].to_s
  next unless section_ids.empty? || section_ids.include?(section_key)

  Array(section["packets"]).each do |packet|
    next unless packet.is_a?(Hash)

    packet_id = packet["packet_id"].to_s
    candidates = candidate_clip_paths(clips_root, packet_id, packet["upload_pack"])
    found = first_existing_path(candidates)
    probe = found.empty? ? media_probe_skipped("file_missing") : media_probe(found)
    probe_issue = !found.empty? && media_probe_issue?(probe)
    clip_file_status = if found.empty?
                         "missing"
                       elsif probe_issue
                         "present_probe_failed"
                       else
                         "present_probe_ok"
                       end
    present = clip_file_status == "present_probe_ok"
    review_action = if present
                      "Review playback against @image1/@image2, cue timing, body route, camera route, and endpoint before marking generation_playback_probe pass."
                    elsif clip_file_status == "present_probe_failed"
                      "Replace this unplayable clip file, then rerun intake before playback review."
                    else
                      "Generate or collect this clip, then rerun this intake before playback review."
                    end
    clip_queue << {
      "packet_id" => packet_id,
      "section_key" => section_key,
      "timeline" => packet["timeline"].to_s,
      "upload_pack" => packet["upload_pack"].to_s,
      "upload_prompt" => upload_prompt(packet["upload_pack"]),
      "start_image" => packet["start_image"].to_s,
      "end_image" => packet["end_image"].to_s,
      "candidate_clip_paths" => candidates,
      "generated_clip_path" => found,
      "generated_clip_sha256" => found.empty? ? "" : Digest::SHA256.file(resolve_path(found).to_s).hexdigest,
      "clip_status" => present ? "present" : "missing",
      "clip_file_status" => clip_file_status,
      "media_probe" => probe,
      "playback_review_status" => present ? "pending_review" : "waiting_clip",
      "generation_playback_probe" => "needs_founder",
      "review_action" => review_action
    }
  end
end

found_file_count = clip_queue.count { |item| !item["generated_clip_path"].to_s.empty? }
discovered = clip_queue.count { |item| item["clip_status"] == "present" }
media_probe_issue_count = clip_queue.count { |item| item["clip_file_status"] == "present_probe_failed" }
reviewed = clip_queue.count { |item| item["playback_review_status"] == "reviewed" }
missing = clip_queue.length - discovered
status = if discovered.zero?
           "waiting_for_generated_clips"
         elsif missing.positive?
           "partial_clip_intake"
         else
           "pending_playback_review"
         end

payload = {
  "schema_version" => "idol_03v_generated_playback_intake.v1",
  "generated_at" => Time.now.iso8601,
  "run" => run_rel,
  "status" => status,
  "route" => route,
  "source_worklist" => worklist_path,
  "source_section_qa" => worklist["source_artifact"].to_s,
  "section_range" => section_range,
  "section_ids" => section_ids,
  "clips_root" => clips_root,
  "summary" => {
    "section_count" => section_ids.length,
    "packet_count" => clip_queue.length,
    "expected_clip_count" => clip_queue.length,
    "found_clip_file_count" => found_file_count,
    "discovered_clip_count" => discovered,
    "missing_clip_count" => missing,
    "media_probe_issue_count" => media_probe_issue_count,
    "playback_reviewed_count" => reviewed
  },
  "clip_queue" => clip_queue,
  "automation_boundaries" => [
    "This intake does not approve generation, playback, section QA pass, publishing, Drive mutation, or edit readiness.",
    "A generated clip is present only after the repo video launcher can probe a playable video stream with positive duration and dimensions.",
    "Do not mark generation_playback_probe pass until generated playback has been reviewed.",
    "Do not infer section QA pass from discovered clip files alone."
  ]
}

lines = []
lines << "# 03V Generated Playback Intake"
lines << ""
lines << "generated_at: #{payload['generated_at']}"
lines << "run: `#{run_rel}`"
lines << "status: `#{status}`"
lines << "route: `#{route}`"
lines << "section_range: `#{section_range}`"
lines << "sections: #{section_ids.map { |id| "`#{id}`" }.join(', ')}"
lines << "clips_root: `#{clips_root}`"
lines << "source_worklist: `#{worklist_path}`"
lines << "source_section_qa: `#{payload['source_section_qa']}`"
lines << "structured_intake: `#{output_yaml}`"
lines << ""
lines << "This intake maps expected generated clips back to 03V packet IDs. It does not mark `generation_playback_probe` pass."
lines << ""
lines << "## Summary"
lines << ""
payload["summary"].each { |key, value| lines << "- #{key}: #{value}" }
lines << ""
lines << "## Clip Queue"
lines << ""
lines << "| packet | section | timeline | clip_status | file_status | probe | generated_clip_path | first_candidate | upload_pack |"
lines << "| --- | --- | --- | --- | --- | --- | --- | --- | --- |"
clip_queue.each do |item|
  probe = item["media_probe"].is_a?(Hash) ? item["media_probe"] : {}
  lines << markdown_table_row([
    "`#{item['packet_id']}`",
    "`#{item['section_key']}`",
    item["timeline"],
    "`#{item['clip_status']}`",
    "`#{item['clip_file_status']}`",
    "`#{probe['status']}`",
    item["generated_clip_path"].empty? ? "" : "`#{item['generated_clip_path']}`",
    Array(item["candidate_clip_paths"]).first.to_s.empty? ? "" : "`#{Array(item['candidate_clip_paths']).first}`",
    "`#{item['upload_pack']}`"
  ])
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
