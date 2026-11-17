#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "optparse"
require "pathname"
require "tmpdir"
require "time"
require "yaml"

ROOT = Pathname.new(Dir.pwd).cleanpath
VIDEO_EXTENSIONS = %w[.mp4 .mov .m4v .webm].freeze

def usage_error(message)
  warn "ERROR: #{message}"
  warn "usage: ruby scripts/idol_03v_import_generated_clips.rb RUN_ROOT --source-dir DIR [--intake PATH] [--route ROUTE] [--clips-root PATH] [--mode copy|move] [--overwrite] [--recursive] [--output-yaml PATH] [--output-md PATH] [--refresh-worklists] [--refresh-current-next] [--founder-decision PATH] [--refreshed-intake-yaml PATH] [--refreshed-intake-md PATH] [--refreshed-worklist-yaml PATH] [--refreshed-worklist-md PATH] [--refreshed-decision-sheet-yaml PATH] [--refreshed-decision-sheet-md PATH] [--refreshed-action-queue-yaml PATH] [--refreshed-action-queue-md PATH] [--refreshed-next-unit-yaml PATH] [--refreshed-next-unit-md PATH] [--refreshed-founder-gate-yaml PATH] [--refreshed-founder-gate-md PATH] [--refreshed-current-next-yaml PATH] [--refreshed-current-next-md PATH] [--write]"
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

def inside_path?(path, parent)
  resolved = resolve_path(path)
  base = resolve_path(parent)
  return false unless resolved && base

  resolved.to_s == base.to_s || resolved.to_s.start_with?("#{base}#{File::SEPARATOR}")
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

def normalize_stem(value)
  value.to_s.downcase.gsub(/[^a-z0-9]+/, "")
end

def video_file?(path)
  VIDEO_EXTENSIONS.include?(File.extname(path.to_s).downcase)
end

def list_files(source_dir, recursive)
  pattern = recursive ? File.join(source_dir.to_s, "**", "*") : File.join(source_dir.to_s, "*")
  Dir.glob(pattern).select { |path| File.file?(path) }.sort
end

def upload_pack_slug(upload_pack)
  File.basename(upload_pack.to_s)
end

def clip_stems(clip)
  packet_id = clip["packet_id"].to_s
  stems = Array(clip["candidate_clip_paths"]).map do |candidate|
    File.basename(candidate.to_s, File.extname(candidate.to_s))
  end
  stems << packet_id
  stems << packet_id.sub(/\APKT_/, "")
  stems << upload_pack_slug(clip["upload_pack"])
  stems.reject(&:empty?).uniq
end

def best_match_for_source(source_stem, clips)
  normalized_source = normalize_stem(source_stem)
  matches = []
  clips.each do |clip|
    best = nil
    clip_stems(clip).each do |stem|
      normalized_variant = normalize_stem(stem)
      next if normalized_variant.empty?

      score = if normalized_source == normalized_variant
                100
              elsif normalized_variant.length >= 8 && normalized_source.include?(normalized_variant)
                70
              else
                0
              end
      next if score.zero?

      if best.nil? || score > best["score"]
        best = {
          "packet_id" => clip["packet_id"].to_s,
          "score" => score,
          "matched_stem" => stem,
          "match_method" => score == 100 ? "exact_stem" : "contains_expected_stem",
          "clip" => clip
        }
      end
    end
    matches << best if best
  end

  return { status: "unmatched", matches: [] } if matches.empty?

  top_score = matches.map { |item| item["score"] }.max
  top = matches.select { |item| item["score"] == top_score }
  packet_ids = top.map { |item| item["packet_id"] }.uniq
  return { status: "matched", match: top.first } if packet_ids.length == 1

  { status: "ambiguous", matches: top }
end

def destination_candidates(clip, intake_clips_root, destination_clips_root)
  Array(clip["candidate_clip_paths"]).map do |candidate|
    value = candidate.to_s
    if !intake_clips_root.to_s.empty? &&
       (value == intake_clips_root.to_s || value.start_with?("#{intake_clips_root}/"))
      suffix = value.sub(/\A#{Regexp.escape(intake_clips_root.to_s)}\/?/, "")
      File.join(destination_clips_root, suffix)
    else
      File.join(destination_clips_root, File.basename(value))
    end
  end.uniq
end

def choose_destination(clip, source_ext, intake_clips_root, destination_clips_root)
  candidates = destination_candidates(clip, intake_clips_root, destination_clips_root)
  same_ext = candidates.find { |path| File.extname(path).downcase == source_ext.downcase }
  same_ext || candidates.first.to_s
end

def ensure_write_allowed!(path, run_path)
  resolved = resolve_path(path)
  usage_error("empty write path") unless resolved

  tmp_roots = [Pathname.new("/private/tmp"), Pathname.new(Dir.tmpdir)].map(&:cleanpath)
  return if inside_path?(resolved, run_path)
  return if tmp_roots.any? { |tmp_root| inside_path?(resolved, tmp_root) }

  usage_error("write path must stay under the run root or /private/tmp: #{resolved}")
end

def ensure_repo_or_tmp_write_allowed!(path)
  resolved = resolve_path(path)
  usage_error("empty write path") unless resolved

  tmp_roots = [Pathname.new("/private/tmp"), Pathname.new(Dir.tmpdir)].map(&:cleanpath)
  return if inside_path?(resolved, ROOT)
  return if tmp_roots.any? { |tmp_root| inside_path?(resolved, tmp_root) }

  usage_error("write path must stay under the repo root or /private/tmp: #{resolved}")
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

def media_probe(path)
  resolved = resolve_path(path)
  return media_probe_failed("file_missing") unless resolved && File.file?(resolved.to_s)

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
    usage_error("media probe failed before clip import could continue: #{resolved}")
  end
  JSON.parse(stdout)
rescue JSON::ParserError => e
  usage_error("media probe returned invalid JSON for #{path}: #{e.message}")
end

def media_probe_failed(reason)
  {
    "status" => "probe_failed",
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

def markdown_table_row(values)
  "| #{values.map { |value| value.to_s.gsub("|", "\\|") }.join(" | ")} |"
end

options = {
  source_dir: nil,
  intake: nil,
  route: nil,
  clips_root: nil,
  mode: "copy",
  overwrite: false,
  recursive: false,
  output_yaml: nil,
  output_md: nil,
  refresh_worklists: false,
  refreshed_intake_yaml: nil,
  refreshed_intake_md: nil,
  refreshed_worklist_yaml: nil,
  refreshed_worklist_md: nil,
  refreshed_decision_sheet_yaml: nil,
  refreshed_decision_sheet_md: nil,
  refresh_current_next: false,
  founder_decision: "automation/founder-decisions/current.yaml",
  refreshed_action_queue_yaml: nil,
  refreshed_action_queue_md: nil,
  refreshed_next_unit_yaml: nil,
  refreshed_next_unit_md: nil,
  refreshed_founder_gate_yaml: nil,
  refreshed_founder_gate_md: nil,
  refreshed_current_next_yaml: nil,
  refreshed_current_next_md: nil,
  write: false
}

OptionParser.new do |parser|
  parser.on("--source-dir DIR") { |value| options[:source_dir] = value }
  parser.on("--intake PATH") { |value| options[:intake] = value }
  parser.on("--route ROUTE") { |value| options[:route] = value }
  parser.on("--clips-root PATH") { |value| options[:clips_root] = value }
  parser.on("--mode MODE") { |value| options[:mode] = value }
  parser.on("--overwrite") { options[:overwrite] = true }
  parser.on("--recursive") { options[:recursive] = true }
  parser.on("--output-yaml PATH") { |value| options[:output_yaml] = value }
  parser.on("--output-md PATH") { |value| options[:output_md] = value }
  parser.on("--refresh-worklists") { options[:refresh_worklists] = true }
  parser.on("--refreshed-intake-yaml PATH") { |value| options[:refreshed_intake_yaml] = value }
  parser.on("--refreshed-intake-md PATH") { |value| options[:refreshed_intake_md] = value }
  parser.on("--refreshed-worklist-yaml PATH") { |value| options[:refreshed_worklist_yaml] = value }
  parser.on("--refreshed-worklist-md PATH") { |value| options[:refreshed_worklist_md] = value }
  parser.on("--refreshed-decision-sheet-yaml PATH") { |value| options[:refreshed_decision_sheet_yaml] = value }
  parser.on("--refreshed-decision-sheet-md PATH") { |value| options[:refreshed_decision_sheet_md] = value }
  parser.on("--refresh-current-next") { options[:refresh_current_next] = true }
  parser.on("--founder-decision PATH") { |value| options[:founder_decision] = value }
  parser.on("--refreshed-action-queue-yaml PATH") { |value| options[:refreshed_action_queue_yaml] = value }
  parser.on("--refreshed-action-queue-md PATH") { |value| options[:refreshed_action_queue_md] = value }
  parser.on("--refreshed-next-unit-yaml PATH") { |value| options[:refreshed_next_unit_yaml] = value }
  parser.on("--refreshed-next-unit-md PATH") { |value| options[:refreshed_next_unit_md] = value }
  parser.on("--refreshed-founder-gate-yaml PATH") { |value| options[:refreshed_founder_gate_yaml] = value }
  parser.on("--refreshed-founder-gate-md PATH") { |value| options[:refreshed_founder_gate_md] = value }
  parser.on("--refreshed-current-next-yaml PATH") { |value| options[:refreshed_current_next_yaml] = value }
  parser.on("--refreshed-current-next-md PATH") { |value| options[:refreshed_current_next_md] = value }
  parser.on("--write") { options[:write] = true }
end.parse!

run_arg = ARGV.shift
usage_error("RUN_ROOT is required") if blank?(run_arg)
usage_error("--source-dir DIR is required") if blank?(options[:source_dir])
usage_error("--mode must be copy or move") unless %w[copy move].include?(options[:mode].to_s)

run_path = resolve_path(run_arg)
usage_error("RUN_ROOT is not a directory: #{run_arg}") unless run_path && Dir.exist?(run_path.to_s)
run_rel = rel_path(run_path)
content_id = run_path.basename.to_s
date_prefix = Time.now.strftime("%Y-%m-%d")

source_dir = resolve_path(options[:source_dir])
usage_error("--source-dir is not a directory: #{options[:source_dir]}") unless source_dir && Dir.exist?(source_dir.to_s)

intake_path = options[:intake] || latest_match(run_path, "review/03v-generated-playback-intake-v*.yaml")
usage_error("03V generated playback intake could not be inferred") if blank?(intake_path)
intake_path = rel_path(intake_path)
intake = load_yaml_hash(intake_path)
usage_error("intake run=#{intake['run'].inspect}; expected #{run_rel.inspect}") unless intake["run"].to_s == run_rel

route = options[:route].to_s.empty? ? intake["route"].to_s : options[:route].to_s
usage_error("route could not be inferred") if route.empty?

intake_clips_root = intake["clips_root"].to_s
destination_clips_root = options[:clips_root].to_s.empty? ? intake_clips_root : options[:clips_root].to_s
usage_error("clips_root could not be inferred") if destination_clips_root.empty?

if options[:refresh_worklists] &&
   !options[:clips_root].to_s.empty? &&
   !inside_path?(destination_clips_root, run_path) &&
   (blank?(options[:refreshed_intake_yaml]) || blank?(options[:refreshed_worklist_yaml]) || blank?(options[:refreshed_decision_sheet_yaml]))
  usage_error("--refresh-worklists with external --clips-root requires --refreshed-intake-yaml, --refreshed-worklist-yaml, and --refreshed-decision-sheet-yaml")
end
if options[:refresh_current_next] && !options[:refresh_worklists]
  usage_error("--refresh-current-next requires --refresh-worklists")
end

timestamp = Time.now.strftime("%Y%m%d-%H%M%S")
section_range = intake["section_range"].to_s
section_ids = Array(intake["section_ids"]).map(&:to_s)
output_yaml = options[:output_yaml] || rel_path(run_path + "review/03v-generated-clip-imports/#{timestamp}-#{slug(section_range)}-#{slug(route)}.yaml")
output_md = options[:output_md] || output_yaml.sub(/\.ya?ml\z/, ".md")

ensure_write_allowed!(output_yaml, run_path)
ensure_write_allowed!(output_md, run_path)
ensure_write_allowed!(destination_clips_root, run_path)

clips = Array(intake["clip_queue"]).select { |clip| clip.is_a?(Hash) }
files = list_files(source_dir, options[:recursive])
video_files = files.select { |path| video_file?(path) }
unsupported_sources = files.reject { |path| video_file?(path) }.map do |path|
  {
    "source_path" => rel_path(path),
    "source_size_bytes" => File.size(path),
    "reason" => "unsupported_extension"
  }
end

matched_sources = []
unmatched_sources = []
ambiguous_sources = []

video_files.each do |source_path|
  source_stem = File.basename(source_path, File.extname(source_path))
  result = best_match_for_source(source_stem, clips)
  source_entry = {
    "source_path" => rel_path(source_path),
    "source_size_bytes" => File.size(source_path)
  }

  case result[:status]
  when "matched"
    match = result[:match]
    clip = match["clip"]
    destination_path = choose_destination(
      clip,
      File.extname(source_path),
      intake_clips_root,
      destination_clips_root
    )
    matched_sources << source_entry.merge(
      "packet_id" => clip["packet_id"].to_s,
      "section_key" => clip["section_key"].to_s,
      "timeline" => clip["timeline"].to_s,
      "destination_path" => rel_path(destination_path),
      "match_method" => match["match_method"],
      "matched_stem" => match["matched_stem"].to_s
    )
  when "ambiguous"
    ambiguous_sources << source_entry.merge(
      "reason" => "ambiguous_packet_match",
      "candidate_packet_ids" => result[:matches].map { |item| item["packet_id"] }.uniq.sort
    )
  else
    unmatched_sources << source_entry.merge("reason" => "no_packet_match")
  end
end

duplicate_target_sources = []
matched_by_packet = matched_sources.group_by { |item| item["packet_id"].to_s }
duplicate_packet_ids = matched_by_packet.select { |_packet_id, items| items.length > 1 }.keys
duplicate_packet_ids.each do |packet_id|
  duplicate_target_sources << {
    "packet_id" => packet_id,
    "section_key" => matched_by_packet[packet_id].first["section_key"].to_s,
    "source_paths" => matched_by_packet[packet_id].map { |item| item["source_path"].to_s },
    "reason" => "multiple_source_files_match_one_packet"
  }
end

importable_sources = matched_sources.reject { |item| duplicate_packet_ids.include?(item["packet_id"].to_s) }
imported_clips = []
skipped_existing = []

importable_sources.each do |item|
  source_path = resolve_path(item["source_path"])
  destination_path = resolve_path(item["destination_path"])
  ensure_write_allowed!(destination_path, run_path)
  existed_before = File.exist?(destination_path.to_s)

  if existed_before && !options[:overwrite]
    skipped_existing << item.merge(
      "destination_existed_before" => true,
      "reason" => "destination_exists",
      "media_probe" => media_probe(destination_path)
    )
    next
  end

  status = if options[:write]
             FileUtils.mkdir_p(destination_path.dirname)
             if options[:mode] == "move"
               FileUtils.mv(source_path.to_s, destination_path.to_s, force: options[:overwrite])
               "moved"
             else
               FileUtils.cp(source_path.to_s, destination_path.to_s)
               "copied"
             end
           else
             options[:mode] == "move" ? "would_move" : "would_copy"
           end

  imported_clips << item.merge(
    "status" => status,
    "destination_existed_before" => existed_before,
    "destination_size_bytes" => File.exist?(destination_path.to_s) ? File.size(destination_path.to_s) : 0,
    "media_probe" => media_probe(options[:write] ? destination_path : source_path)
  )
end

media_probe_issue_count = imported_clips.count { |item| media_probe_issue?(item["media_probe"]) } +
                          skipped_existing.count { |item| media_probe_issue?(item["media_probe"]) }
issue_count = unmatched_sources.length +
              ambiguous_sources.length +
              duplicate_target_sources.length +
              skipped_existing.length +
              media_probe_issue_count
status = if !options[:write]
           "dry_run"
         elsif imported_clips.empty? && issue_count.positive?
           "blocked"
         elsif issue_count.positive?
           "partial"
         else
           "complete"
         end

refreshed_intake_yaml = ""
refreshed_intake_md = ""
refreshed_worklist_yaml = ""
refreshed_worklist_md = ""
refreshed_decision_sheet_yaml = ""
refreshed_decision_sheet_md = ""
refreshed_action_queue_yaml = ""
refreshed_action_queue_md = ""
refreshed_next_unit_yaml = ""
refreshed_next_unit_md = ""
refreshed_founder_gate_yaml = ""
refreshed_founder_gate_md = ""
refreshed_current_next_yaml = ""
refreshed_current_next_md = ""
if options[:refresh_worklists]
  refreshed_intake_yaml = options[:refreshed_intake_yaml] || rel_path(run_path + "review/03v-generated-playback-intake-v1.yaml")
  refreshed_intake_md = options[:refreshed_intake_md] || refreshed_intake_yaml.sub(/\.ya?ml\z/, ".md")
  refreshed_worklist_yaml = options[:refreshed_worklist_yaml] || rel_path(run_path + "review/03v-playback-review-worklist-v1.yaml")
  refreshed_worklist_md = options[:refreshed_worklist_md] || refreshed_worklist_yaml.sub(/\.ya?ml\z/, ".md")
  refreshed_decision_sheet_yaml = options[:refreshed_decision_sheet_yaml] || rel_path(run_path + "review/03v-playback-decision-sheet-v1.yaml")
  refreshed_decision_sheet_md = options[:refreshed_decision_sheet_md] || refreshed_decision_sheet_yaml.sub(/\.ya?ml\z/, ".md")
end
if options[:refresh_current_next]
  gate_slug = slug(section_range)
  refreshed_action_queue_yaml = options[:refreshed_action_queue_yaml] || "automation/action-queues/#{date_prefix}-#{content_id}-03v-action-queue.yaml"
  refreshed_action_queue_md = options[:refreshed_action_queue_md] || refreshed_action_queue_yaml.sub(/\.ya?ml\z/, ".md")
  refreshed_next_unit_yaml = options[:refreshed_next_unit_yaml] || "automation/next-units/#{date_prefix}-#{content_id}-harness-next-unit.yaml"
  refreshed_next_unit_md = options[:refreshed_next_unit_md] || refreshed_next_unit_yaml.sub(/\.ya?ml\z/, ".md")
  refreshed_founder_gate_yaml = options[:refreshed_founder_gate_yaml] || "automation/founder-gates/#{date_prefix}-#{content_id}-03v-front-gate-#{gate_slug}.yaml"
  refreshed_founder_gate_md = options[:refreshed_founder_gate_md] || refreshed_founder_gate_yaml.sub(/\.ya?ml\z/, ".md")
  refreshed_current_next_yaml = options[:refreshed_current_next_yaml] || "automation/current-next.yaml"
  refreshed_current_next_md = options[:refreshed_current_next_md] || refreshed_current_next_yaml.sub(/\.ya?ml\z/, ".md")
end

refreshed_outputs = {
  "refreshed_intake" => refreshed_intake_yaml,
  "refreshed_worklist" => refreshed_worklist_yaml,
  "refreshed_decision_sheet" => refreshed_decision_sheet_yaml,
  "refreshed_action_queue" => refreshed_action_queue_yaml,
  "refreshed_next_unit" => refreshed_next_unit_yaml,
  "refreshed_founder_gate" => refreshed_founder_gate_yaml,
  "refreshed_current_next" => refreshed_current_next_yaml
}

payload = {
  "schema_version" => "idol_03v_generated_clip_import.v1",
  "generated_at" => Time.now.iso8601,
  "run" => run_rel,
  "status" => status,
  "mode" => options[:mode],
  "write" => options[:write],
  "source_dir" => rel_path(source_dir),
  "recursive" => options[:recursive],
  "route" => route,
  "source_intake" => intake_path,
  "section_range" => section_range,
  "section_ids" => section_ids,
  "clips_root" => destination_clips_root,
  "summary" => {
    "expected_clip_count" => clips.length,
    "source_file_count" => files.length,
    "source_video_count" => video_files.length,
    "matched_source_count" => matched_sources.length,
    "imported_clip_count" => imported_clips.length,
    "unmatched_source_count" => unmatched_sources.length,
    "ambiguous_source_count" => ambiguous_sources.length,
    "duplicate_target_count" => duplicate_target_sources.length,
    "skipped_existing_count" => skipped_existing.length,
    "unsupported_source_count" => unsupported_sources.length,
    "media_probe_issue_count" => media_probe_issue_count
  },
  "imported_clips" => imported_clips,
  "skipped_existing" => skipped_existing,
  "unmatched_sources" => unmatched_sources,
  "ambiguous_sources" => ambiguous_sources,
  "duplicate_target_sources" => duplicate_target_sources,
  "unsupported_sources" => unsupported_sources,
  "refreshed_outputs" => refreshed_outputs,
  "automation_boundaries" => [
    "This import only places generated 03V clip files and writes an audit manifest.",
    "Clip import does not mark generation_playback_probe pass.",
    "Playback pass still requires explicit founder-reviewed pass through the 03V playback decision command.",
    "This command does not approve paid generation, Drive mutation, publishing, packaging, or edit readiness."
  ]
}

lines = []
lines << "# 03V Generated Clip Import"
lines << ""
lines << "generated_at: #{payload['generated_at']}"
lines << "run: `#{run_rel}`"
lines << "status: `#{status}`"
lines << "mode: `#{options[:mode]}`"
lines << "source_dir: `#{payload['source_dir']}`"
lines << "route: `#{route}`"
lines << "section_range: `#{section_range}`"
lines << "clips_root: `#{destination_clips_root}`"
lines << "source_intake: `#{intake_path}`"
lines << "structured_manifest: `#{output_yaml}`"
lines << ""
lines << "This import places generated clip files for the current 03V front gate. It does not mark playback or section QA pass."
lines << ""
lines << "## Summary"
lines << ""
payload["summary"].each { |key, value| lines << "- #{key}: #{value}" }
lines << ""
lines << "## Imported Clips"
lines << ""
lines << "| status | packet | section | source | destination | match | probe | duration | size |"
lines << "| --- | --- | --- | --- | --- | --- | --- | --- | --- |"
imported_clips.each do |item|
  probe = item["media_probe"].is_a?(Hash) ? item["media_probe"] : {}
  lines << markdown_table_row([
    "`#{item['status']}`",
    "`#{item['packet_id']}`",
    "`#{item['section_key']}`",
    "`#{item['source_path']}`",
    "`#{item['destination_path']}`",
    item["match_method"],
    "`#{probe['status']}`",
    probe["duration_seconds"],
    "#{probe['width']}x#{probe['height']}"
  ])
end
lines << ""
lines << "## Skipped / Needs Attention"
lines << ""
lines << "- skipped_existing: #{skipped_existing.length}"
lines << "- unmatched_sources: #{unmatched_sources.length}"
lines << "- ambiguous_sources: #{ambiguous_sources.length}"
lines << "- duplicate_target_sources: #{duplicate_target_sources.length}"
lines << "- unsupported_sources: #{unsupported_sources.length}"
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
    validate_schema!("schemas/03v-generated-clip-import.schema.json", rel_path(yaml_path))

  if options[:refresh_worklists]
    if media_probe_issue_count.positive?
      usage_error("import wrote #{rel_path(yaml_path)} but media_probe_issue_count=#{media_probe_issue_count}; fix or replace unplayable clips before refreshing playback worklists/current-next")
    end

    [refreshed_intake_yaml, refreshed_intake_md, refreshed_worklist_yaml, refreshed_worklist_md, refreshed_decision_sheet_yaml, refreshed_decision_sheet_md].each do |path|
      ensure_write_allowed!(path, run_path)
    end
    if options[:refresh_current_next]
      [
        refreshed_action_queue_yaml,
        refreshed_action_queue_md,
        refreshed_next_unit_yaml,
        refreshed_next_unit_md,
        refreshed_founder_gate_yaml,
        refreshed_founder_gate_md,
        refreshed_current_next_yaml,
        refreshed_current_next_md
      ].each { |path| ensure_repo_or_tmp_write_allowed!(path) }
    end

    run_command!(
      "ruby",
      "scripts/idol_03v_refresh_playback_surfaces.rb",
      run_rel,
      "--worklist",
      intake["source_worklist"].to_s,
      "--route",
      route,
      "--clips-root",
      destination_clips_root,
      "--intake-yaml",
      refreshed_intake_yaml,
      "--intake-md",
      refreshed_intake_md,
      "--playback-worklist-yaml",
      refreshed_worklist_yaml,
      "--playback-worklist-md",
      refreshed_worklist_md,
      "--decision-sheet-yaml",
      refreshed_decision_sheet_yaml,
      "--decision-sheet-md",
      refreshed_decision_sheet_md,
      "--write"
    )
    puts "refreshed_intake #{refreshed_intake_yaml}"
    puts "refreshed_worklist #{refreshed_worklist_yaml}"
    puts "refreshed_decision_sheet #{refreshed_decision_sheet_yaml}"

    if options[:refresh_current_next]
      run_command!(
        "ruby",
        "scripts/idol_harness_action_queue.rb",
        run_rel,
        "--worklist",
        intake["source_worklist"].to_s,
        "--only-check",
        "video_prompt_section_qa_readiness",
        "--founder-decision",
        options[:founder_decision],
        "--output-yaml",
        refreshed_action_queue_yaml,
        "--output-md",
        refreshed_action_queue_md,
        "--write"
      )
      validate_schema!("schemas/harness-action-queue.schema.json", refreshed_action_queue_yaml)
      run_command!(
        "ruby",
        "scripts/idol_harness_next_unit.rb",
        run_rel,
        "--action-queue",
        refreshed_action_queue_yaml,
        "--output-yaml",
        refreshed_next_unit_yaml,
        "--output-md",
        refreshed_next_unit_md,
        "--write"
      )
      validate_schema!("schemas/harness-next-unit.schema.json", refreshed_next_unit_yaml)
      run_command!(
        "ruby",
        "scripts/idol_harness_founder_gate_packet.rb",
        run_rel,
        "--next-unit",
        refreshed_next_unit_yaml,
        "--output-yaml",
        refreshed_founder_gate_yaml,
        "--output-md",
        refreshed_founder_gate_md,
        "--write"
      )
      validate_schema!("schemas/harness-founder-gate.schema.json", refreshed_founder_gate_yaml)
      run_command!(
        "ruby",
        "scripts/idol_director_dispatch_index.rb",
        "build",
        run_rel,
        "--json"
      )
      run_command!(
        "ruby",
        "scripts/idol_director_dispatch_index.rb",
        "validate",
        rel_path(run_path + "work/director-dispatch-index.yaml"),
        "--json"
      )
      run_command!(
        "ruby",
        "scripts/idol_harness_current_next.rb",
        run_rel,
        "--next-unit",
        refreshed_next_unit_yaml,
        "--founder-gate",
        refreshed_founder_gate_yaml,
        "--output-yaml",
        refreshed_current_next_yaml,
        "--output-md",
        refreshed_current_next_md,
        "--write"
      )
      validate_schema!("schemas/harness-current-next.schema.json", refreshed_current_next_yaml)
      run_command!(
        "ruby",
        "scripts/validate_03v_front_playback_gate.rb",
        run_rel,
        "--worklist",
        intake["source_worklist"].to_s,
        "--playback-intake",
        refreshed_intake_yaml,
        "--playback-worklist",
        refreshed_worklist_yaml,
        "--playback-decision-sheet",
        refreshed_decision_sheet_yaml,
        "--action-queue",
        refreshed_action_queue_yaml,
        "--next-unit",
        refreshed_next_unit_yaml,
        "--founder-gate",
        refreshed_founder_gate_yaml,
        "--current-next",
        refreshed_current_next_yaml
      )
      puts "refreshed_action_queue #{refreshed_action_queue_yaml}"
      puts "refreshed_next_unit #{refreshed_next_unit_yaml}"
      puts "refreshed_founder_gate #{refreshed_founder_gate_yaml}"
      puts "refreshed_current_next #{refreshed_current_next_yaml}"
    end
  end
else
  puts YAML.dump(payload)
end
