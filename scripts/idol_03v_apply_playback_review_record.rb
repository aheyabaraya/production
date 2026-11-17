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
require_relative "lib/idol_current_next_v2"
require_relative "lib/idol_run_layout"

TOOL_ROOT = Pathname.new(__dir__).join("..").expand_path
$repo_root = TOOL_ROOT

def usage_error(message)
  warn "ERROR: #{message}"
  warn "usage: ruby scripts/idol_03v_apply_playback_review_record.rb RUN_ROOT --record PATH [--root PATH] [--source-qa PATH] [--output-qa PATH] [--patch-record PATH] [--patch-md PATH] [--refresh-focused-queue] [--write]"
  exit 2
end

def blank?(value)
  value.nil? || value.to_s.strip.empty?
end

def resolve_path(path)
  return nil if blank?(path)

  raw = Pathname.new(path.to_s)
  raw.absolute? ? raw.expand_path.cleanpath : ($repo_root + raw).expand_path.cleanpath
end

def rel_path(path)
  resolved = resolve_path(path)
  return "" unless resolved

  resolved.relative_path_from($repo_root).to_s
rescue ArgumentError
  resolved.to_s
end

def within?(path, owner)
  candidate = resolve_path(path)
  boundary = resolve_path(owner)
  return false unless candidate && boundary
  candidate = candidate.realpath if candidate.exist?
  boundary = boundary.realpath if boundary.exist?
  candidate.to_s == boundary.to_s || candidate.to_s.start_with?("#{boundary}/")
rescue Errno::ENOENT, Errno::EACCES
  false
end

def require_run_file!(path, label, run_path, owner: run_path)
  resolved = resolve_path(path)
  usage_error("#{label} is not readable: #{path}") unless resolved&.file?
  usage_error("#{label} must stay inside the owning run: #{path}") unless within?(resolved, run_path) && within?(resolved, owner)
  resolved.realpath
end

def require_run_target!(path, label, run_path, owner: run_path)
  resolved = resolve_path(path)
  usage_error("#{label} must stay inside the owning run: #{path}") unless resolved && within?(resolved, run_path) && within?(resolved, owner)
  ancestor = resolved
  ancestor = ancestor.parent until ancestor.exist? || ancestor.root?
  usage_error("#{label} escapes the owning run through a symlink: #{path}") unless ancestor.exist? && within?(ancestor.realpath, owner.realpath)
  resolved
end

def verify_sha256!(path, expected, label)
  usage_error("#{label} requires a 64-character SHA-256") unless expected.to_s.match?(/\A[a-f0-9]{64}\z/)
  actual = Digest::SHA256.file(path.to_s).hexdigest
  usage_error("#{label} SHA-256 changed") unless actual == expected
end

def live_media_probe!(path, recorded_probe, label)
  ffprobe = ["/opt/homebrew/bin/ffprobe", "/usr/local/bin/ffprobe"].find { |candidate| File.executable?(candidate) }
  ffprobe ||= `command -v ffprobe`.strip
  usage_error("ffprobe is required to apply playback pass") if ffprobe.to_s.empty?
  stdout, stderr, status = Open3.capture3(
    ffprobe,
    "-v", "error",
    "-show_streams",
    "-show_format",
    "-of", "json",
    path.to_s
  )
  usage_error("#{label} live media probe failed: #{stderr.to_s.strip}") unless status.success?
  data = JSON.parse(stdout)
  streams = Array(data["streams"])
  video_streams = streams.select { |stream| stream["codec_type"].to_s == "video" && stream.dig("disposition", "attached_pic").to_i != 1 }
  first_video = video_streams.first || {}
  duration = (data.dig("format", "duration") || first_video["duration"]).to_f
  width = first_video["width"].to_i
  height = first_video["height"].to_i
  usage_error("#{label} is not a positive playable video") unless duration.positive? && !video_streams.empty? && width.positive? && height.positive?
  probe = recorded_probe.is_a?(Hash) ? recorded_probe : {}
  usage_error("#{label} recorded duration does not match live media") if (probe["duration_seconds"].to_f - duration).abs > 0.05
  usage_error("#{label} recorded video_stream_count does not match live media") unless probe["video_stream_count"].to_i == video_streams.length
  usage_error("#{label} recorded dimensions do not match live media") unless probe["width"].to_i == width && probe["height"].to_i == height
  live_codec = first_video["codec_name"].to_s
  unless probe["codec_name"].to_s.empty? || probe["codec_name"].to_s == live_codec
    usage_error("#{label} recorded codec does not match live media")
  end
rescue JSON::ParserError => e
  usage_error("#{label} live media probe returned invalid JSON: #{e.message}")
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

def next_version_path(run_path, basename)
  matches = Dir.glob((run_path + "review/#{basename}-v*.yaml").to_s)
  versions = matches.map do |path|
    File.basename(path).match(/-v(\d+)\.ya?ml\z/)&.[](1)&.to_i
  end.compact
  next_version = versions.empty? ? 1 : versions.max + 1
  rel_path(run_path + "review/#{basename}-v#{next_version}.yaml")
end

def section_by_key(qa, key)
  Array(qa["sections"]).find { |section| section.is_a?(Hash) && section["section_key"].to_s == key.to_s } || {}
end

def covered_packets_by_section(record)
  Array(record["covered_packets"]).each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |packet, memo|
    next unless packet.is_a?(Hash)

    memo[packet["section_key"].to_s] << packet["packet_id"].to_s
  end
end

def unresolved_findings?(section)
  Array(section["findings"]).any? do |finding|
    finding.is_a?(Hash) && %w[block revise].include?(finding["severity"].to_s)
  end
end

def canonical_value(value)
  case value
  when Hash
    value.keys.map(&:to_s).sort.to_h do |key|
      source_key = value.key?(key) ? key : value.keys.find { |candidate| candidate.to_s == key }
      [key, canonical_value(value[source_key])]
    end
  when Array
    value.map { |item| canonical_value(item) }
  else
    value
  end
end

def structured_sha256(value)
  Digest::SHA256.hexdigest(JSON.generate(canonical_value(value)))
end

def validate_record!(record, run_rel)
  usage_error("record run=#{record['run'].inspect}; expected #{run_rel.inspect}") unless record["run"].to_s == run_rel
  usage_error("record schema_version is not idol_03v_playback_review_record.v1") unless record["schema_version"].to_s == "idol_03v_playback_review_record.v1"
  usage_error("record decision must be pass") unless record["decision"].to_s == "pass"
  usage_error("record must have explicit_founder_review=true") unless record["explicit_founder_review"] == true
  summary = record["summary"].is_a?(Hash) ? record["summary"] : {}
  usage_error("record all_target_clips_present must be true") unless summary["all_target_clips_present"] == true
  usage_error("record can_patch_generation_playback_probe must be true") unless summary["can_patch_generation_playback_probe"] == true
end

def worklist_packets_by_id(review_worklist)
  Array(review_worklist["section_reviews"]).flat_map do |section|
    Array(section.is_a?(Hash) ? section["packets"] : [])
  end.each_with_object({}) do |packet, memo|
    next unless packet.is_a?(Hash)

    packet_id = packet["packet_id"].to_s
    memo[packet_id] = packet unless packet_id.empty?
  end
end

def required_check_ids(packet)
  Array(packet["required_checks"]).map do |check|
    next "" unless check.is_a?(Hash)

    check["id"].to_s
  end.reject(&:empty?)
end

def packets_by_id(rows, label)
  Array(rows).each_with_object({}) do |packet, memo|
    next unless packet.is_a?(Hash)
    packet_id = packet["packet_id"].to_s
    usage_error("#{label} contains an empty packet_id") if packet_id.empty?
    usage_error("#{label} contains duplicate packet_id #{packet_id}") if memo.key?(packet_id)
    memo[packet_id] = packet
  end
end

def validate_review_worklist_against_intake!(review_worklist, intake, run_path, run_rel)
  usage_error("source intake schema_version is not idol_03v_generated_playback_intake.v1") unless intake["schema_version"].to_s == "idol_03v_generated_playback_intake.v1"
  usage_error("source intake run=#{intake['run'].inspect}; expected #{run_rel.inspect}") unless intake["run"].to_s == run_rel
  usage_error("source intake section_range does not match review worklist") unless intake["section_range"].to_s == review_worklist["section_range"].to_s
  usage_error("source intake source_section_qa does not match review worklist") unless intake["source_section_qa"].to_s == review_worklist["source_section_qa"].to_s
  clips_root = resolve_path(intake["clips_root"])
  usage_error("source intake clips_root must stay inside the owning run") unless clips_root && within?(clips_root, run_path)

  intake_packets = packets_by_id(intake["clip_queue"], "source intake clip_queue")
  worklist_packets = packets_by_id(
    Array(review_worklist["section_reviews"]).flat_map { |section| Array(section.is_a?(Hash) ? section["packets"] : []) },
    "playback review worklist"
  )
  usage_error("playback review worklist packet set does not match source intake") unless worklist_packets.keys.sort == intake_packets.keys.sort
  worklist_packets.each do |packet_id, worklist_packet|
    intake_packet = intake_packets.fetch(packet_id)
    %w[section_key timeline clip_status clip_file_status generated_clip_path generated_clip_sha256].each do |field|
      unless worklist_packet[field].to_s == intake_packet[field].to_s
        usage_error("playback worklist packet #{packet_id} #{field} does not match source intake")
      end
    end
    usage_error("playback worklist packet #{packet_id} media_probe does not match source intake") unless worklist_packet["media_probe"] == intake_packet["media_probe"]
    next unless worklist_packet["clip_status"].to_s == "present"

    probe = worklist_packet["media_probe"].is_a?(Hash) ? worklist_packet["media_probe"] : {}
    unless worklist_packet["clip_file_status"].to_s == "present_probe_ok" && probe["status"].to_s == "ok" && probe["playable"] == true &&
           probe["duration_seconds"].to_f.positive? && probe["video_stream_count"].to_i.positive? &&
           probe["width"].to_i.positive? && probe["height"].to_i.positive?
      usage_error("playback worklist packet #{packet_id} cannot pass without a positive playable media probe")
    end
    clip_path = require_run_file!(worklist_packet["generated_clip_path"], "playback worklist packet #{packet_id} clip", run_path)
    usage_error("playback worklist packet #{packet_id} clip is outside intake clips_root") unless within?(clip_path, clips_root)
    verify_sha256!(clip_path, worklist_packet["generated_clip_sha256"], "playback worklist packet #{packet_id} clip")
    live_media_probe!(clip_path, probe, "playback worklist packet #{packet_id} clip")
  end
end

def validate_record_against_review_worklist!(record, review_worklist, run_path, run_rel)
  usage_error("review worklist schema_version is not idol_03v_playback_review_worklist.v1") unless review_worklist["schema_version"].to_s == "idol_03v_playback_review_worklist.v1"
  usage_error("review worklist run=#{review_worklist['run'].inspect}; expected #{run_rel.inspect}") unless review_worklist["run"].to_s == run_rel
  usage_error("record source_intake=#{record['source_intake'].inspect}; expected review worklist source_intake #{review_worklist['source_intake'].inspect}") unless record["source_intake"].to_s == review_worklist["source_intake"].to_s
  usage_error("record section_range=#{record['section_range'].inspect}; expected review worklist section_range #{review_worklist['section_range'].inspect}") unless record["section_range"].to_s == review_worklist["section_range"].to_s

  worklist_packets = worklist_packets_by_id(review_worklist)
  covered_packets = Array(record["covered_packets"]).select { |packet| packet.is_a?(Hash) }
  summary = record["summary"].is_a?(Hash) ? record["summary"] : {}
  usage_error("record summary packet_count=#{summary['packet_count'].inspect}; expected #{covered_packets.length}") unless summary["packet_count"].to_i == covered_packets.length

  present_count = covered_packets.count { |packet| packet["clip_status"].to_s == "present" }
  missing_count = covered_packets.length - present_count
  usage_error("record summary present_clip_count=#{summary['present_clip_count'].inspect}; expected #{present_count}") unless summary["present_clip_count"].to_i == present_count
  usage_error("record summary missing_clip_count=#{summary['missing_clip_count'].inspect}; expected #{missing_count}") unless summary["missing_clip_count"].to_i == missing_count

  covered_packets.each do |record_packet|
    packet_id = record_packet["packet_id"].to_s
    source_packet = worklist_packets[packet_id]
    usage_error("record packet #{packet_id} is missing from source review worklist") unless source_packet

    %w[section_key timeline clip_status generated_clip_path generated_clip_sha256].each do |field|
      unless record_packet[field].to_s == source_packet[field].to_s
        usage_error("record packet #{packet_id} #{field}=#{record_packet[field].inspect}; expected source review worklist #{source_packet[field].inspect}")
      end
    end

    record_check_ids = required_check_ids(record_packet)
    source_check_ids = required_check_ids(source_packet)
    usage_error("record packet #{packet_id} required_check_count=#{record_packet['required_check_count'].inspect}; expected #{record_check_ids.length}") unless record_packet["required_check_count"].to_i == record_check_ids.length
    usage_error("record packet #{packet_id} required_checks=#{record_check_ids.inspect}; expected source review worklist #{source_check_ids.inspect}") unless record_check_ids == source_check_ids
    usage_error("record packet #{packet_id} review_status_after_record=#{record_packet['review_status_after_record'].inspect}; expected pass_recorded") unless record_packet["review_status_after_record"].to_s == "pass_recorded"

    expected_sha = record_packet["generated_clip_sha256"].to_s
    unless expected_sha.match?(/\A[a-f0-9]{64}\z/)
      usage_error("record packet #{packet_id} requires a generated clip sha256 before pass can patch section QA; refresh playback intake and record review again")
    end
    clip_path = require_run_file!(record_packet["generated_clip_path"], "record packet #{packet_id} generated clip", run_path)
    verify_sha256!(clip_path, expected_sha, "record packet #{packet_id} generated clip")
  end
end

def validate_section_coverage!(qa, record)
  covered = covered_packets_by_section(record)
  usage_error("record covers no sections") if covered.empty?

  covered.each do |section_key, cue_ids|
    source_section = section_by_key(qa, section_key)
    usage_error("source QA is missing section #{section_key}") if source_section.empty?

    expected = Array(source_section["cue_ids"]).map(&:to_s).sort
    actual = cue_ids.uniq.sort
    unless actual == expected
      usage_error("record covers #{section_key} cues #{actual.inspect}; expected full section #{expected.inspect}")
    end
  end
  covered
end

def build_patch_record(run_rel, record_path, review_worklist_path, source_qa_path, output_qa, record, patched_sections, output_overall_status)
  {
    "schema_version" => "idol_03v_section_qa_patch_record.v3",
    "generated_at" => Time.now.iso8601,
    "run" => run_rel,
    "status" => "patched_candidate_written",
    "source_review_record" => record_path,
    "source_review_worklist" => review_worklist_path,
    "source_section_qa" => source_qa_path,
    "output_section_qa" => output_qa,
    "decision" => "pass",
    "patched_sections" => patched_sections,
    "summary" => {
      "patched_section_count" => patched_sections.length,
      "patched_cue_count" => patched_sections.sum { |section| Array(section["cue_ids"]).length },
      "output_overall_status" => output_overall_status,
      "ready_for_global_section_qa_pass" => output_overall_status == "pass"
    },
    "automation_boundaries" => [
      "This patch writes a 03V section-QA candidate only; it does not approve paid generation, publishing, Drive mutation, or edit readiness.",
      "The source playback review record must be pass, explicit founder-reviewed, clip-present, and full-section covered.",
      "If output_overall_status is not pass, continue the next 03V chunk instead of promoting global section-QA readiness."
    ]
  }
end

def markdown_table_row(values)
  "| #{values.map { |value| value.to_s.gsub("|", "\\|") }.join(" | ")} |"
end

def run_command!(*command)
  stdout, stderr, status = Open3.capture3(*command, chdir: TOOL_ROOT.to_s)
  puts stdout unless stdout.empty?
  warn stderr unless stderr.empty?
  usage_error("command failed: #{command.join(' ')}") unless status.success?
end

def validate_schema!(schema_path, document_path)
  document_path = resolve_path(document_path).to_s
  run_command!(
    TOOL_ROOT.join("scripts/idol-video-python").to_s,
    TOOL_ROOT.join("scripts/validate_json_schema.py").to_s,
    TOOL_ROOT.join(schema_path).to_s,
    document_path
  )
end

def validate_patch_outputs!(record_path, output_qa, patch_record_path)
  validate_schema!("schemas/03v-playback-review-record.schema.json", record_path)
  validate_schema!("schemas/video-prompt-section-qa.schema.json", output_qa)
  validate_schema!("schemas/03v-section-qa-patch-record.schema.json", patch_record_path)
end

def validate_refresh_outputs!(run_path, run_rel)
  current_next_path = "automation/current-next.yaml"
  begin
    context = IdolCurrentNextV2.load_active(
      path: current_next_path,
      run: run_rel,
      root: $repo_root,
      require_actionable: true,
      require_legacy: %w[source_next_unit source_founder_gate source_action_queue]
    )
    IdolCurrentNextV2.require_03v_legacy_gate!(context)
  rescue IdolCurrentNextV2::Error => error
    usage_error(error.message)
  end
  action_queue_path = context.dig("legacy_bindings", "source_action_queue", "path").to_s
  next_unit_path = context.dig("legacy_bindings", "source_next_unit", "path").to_s
  founder_gate_path = context.dig("legacy_bindings", "source_founder_gate", "path").to_s
  worklist_path = rel_path(run_path + "review/03v-section-video-prompt-qa-worklist-v1.yaml")
  intake_path = rel_path(run_path + "review/03v-generated-playback-intake-v1.yaml")
  playback_worklist_path = rel_path(run_path + "review/03v-playback-review-worklist-v1.yaml")
  playback_decision_sheet_path = rel_path(run_path + "review/03v-playback-decision-sheet-v1.yaml")

  validate_schema!("schemas/harness-blocker-worklist.schema.json", worklist_path)
  validate_schema!("schemas/03v-generated-playback-intake.schema.json", intake_path)
  validate_schema!("schemas/03v-playback-review-worklist.schema.json", playback_worklist_path)
  validate_schema!("schemas/03v-playback-decision-sheet.schema.json", playback_decision_sheet_path)
  validate_schema!("schemas/harness-action-queue.schema.json", action_queue_path)
  validate_schema!("schemas/harness-next-unit.schema.json", next_unit_path)
  validate_schema!("schemas/harness-founder-gate.schema.json", founder_gate_path)
  validate_schema!("schemas/harness-current-next.schema.json", current_next_path)
  run_command!(
    "ruby",
    "scripts/validate_03v_front_playback_gate.rb",
    run_rel,
    "--current-next",
    current_next_path,
    "--founder-gate",
    founder_gate_path,
    "--action-queue",
    action_queue_path,
    "--next-unit",
    next_unit_path
  )
end

options = {
  root: TOOL_ROOT,
  record: nil,
  source_qa: nil,
  output_qa: nil,
  patch_record: nil,
  patch_md: nil,
  refresh_focused_queue: false,
  write: false
}

OptionParser.new do |parser|
  parser.on("--root PATH") { |value| options[:root] = Pathname.new(value).expand_path }
  parser.on("--record PATH") { |value| options[:record] = value }
  parser.on("--source-qa PATH") { |value| options[:source_qa] = value }
  parser.on("--output-qa PATH") { |value| options[:output_qa] = value }
  parser.on("--patch-record PATH") { |value| options[:patch_record] = value }
  parser.on("--patch-md PATH") { |value| options[:patch_md] = value }
  parser.on("--refresh-focused-queue") { options[:refresh_focused_queue] = true }
  parser.on("--write") { options[:write] = true }
end.parse!

$repo_root = options[:root].expand_path.cleanpath
usage_error("repository root is not a directory: #{$repo_root}") unless $repo_root.directory?
$repo_root = $repo_root.realpath

run_arg = ARGV.shift
usage_error("RUN_ROOT is required") if blank?(run_arg)
usage_error("--record PATH is required") if blank?(options[:record])

run_path = resolve_path(run_arg)
usage_error("RUN_ROOT is not a directory: #{run_arg}") unless run_path && Dir.exist?(run_path.to_s)
run_path = run_path.realpath
run_rel = rel_path(run_path)
layout_errors = IdolRunLayout.validate(run_path, repo_root: $repo_root)
usage_error(layout_errors.join("; ")) unless layout_errors.empty?
usage_error("RUN_ROOT must stay inside the repository") unless within?(run_path, $repo_root)
review_root = run_path.join("review")

record_absolute = require_run_file!(options[:record], "playback review record", run_path, owner: review_root)
record_path = rel_path(record_absolute)
record = load_yaml_hash(record_absolute)
validate_record!(record, run_rel)

review_worklist_path = record["source_review_worklist"].to_s
review_worklist_absolute = require_run_file!(review_worklist_path, "source playback review worklist", run_path, owner: review_root)
verify_sha256!(review_worklist_absolute, record["source_review_worklist_sha256"], "source playback review worklist")
review_worklist_path = rel_path(review_worklist_absolute)
review_worklist = load_yaml_hash(review_worklist_absolute)
validate_record_against_review_worklist!(record, review_worklist, run_path, run_rel)
source_intake_path = review_worklist["source_intake"].to_s
usage_error("record source_intake does not match review worklist") unless record["source_intake"].to_s == source_intake_path
source_intake_absolute = require_run_file!(source_intake_path, "source playback intake", run_path, owner: review_root)
verify_sha256!(source_intake_absolute, record["source_intake_sha256"], "source playback intake")
source_intake_path = rel_path(source_intake_absolute)
source_intake = load_yaml_hash(source_intake_absolute)
usage_error("source playback intake run=#{source_intake['run'].inspect}; expected #{run_rel.inspect}") unless source_intake["run"].to_s == run_rel
validate_review_worklist_against_intake!(review_worklist, source_intake, run_path, run_rel)
refresh_route = source_intake["route"].to_s
refresh_clips_root = source_intake["clips_root"].to_s
usage_error("source playback intake route is missing") if refresh_route.empty?
usage_error("source playback intake clips_root is missing") if refresh_clips_root.empty?
require_run_target!(refresh_clips_root, "source playback clips_root", run_path)
source_qa_path = options[:source_qa] || review_worklist["source_section_qa"].to_s
usage_error("record source_section_qa does not match review worklist") unless record["source_section_qa"].to_s == review_worklist["source_section_qa"].to_s
source_qa_absolute = require_run_file!(source_qa_path, "source section QA", run_path, owner: review_root)
verify_sha256!(source_qa_absolute, record["source_section_qa_sha256"], "source section QA")
source_qa_path = rel_path(source_qa_absolute)
source_qa = load_yaml_hash(source_qa_absolute)
unless source_qa["schema_version"].to_s == "idol_video_prompt_section_qa.v6"
  usage_error("source QA schema_version is not idol_video_prompt_section_qa.v6")
end
unless source_qa["review_mode"].to_s == "contextual_llm_section_and_whole_timeline"
  usage_error("playback pass patch requires contextual_llm_section_and_whole_timeline source QA")
end

covered = validate_section_coverage!(source_qa, record)
patched_qa = Marshal.load(Marshal.dump(source_qa))
patched_sections = []

covered.each do |section_key, cue_ids|
  section = section_by_key(patched_qa, section_key)
  usage_error("#{section_key} has unresolved contextual findings; playback pass cannot erase them") if unresolved_findings?(section)
  usage_error("#{section_key} review_summary is missing") if section["review_summary"].to_s.strip.empty?
  previous_status = section["status"].to_s
  summary_sha = structured_sha256(section["review_summary"])
  findings_sha = structured_sha256(section["findings"])
  section["status"] = "pass"
  patched_sections << {
    "section_key" => section_key,
    "cue_ids" => cue_ids,
    "founder_playback_decision" => "pass",
    "preserved_review_summary_sha256" => summary_sha,
    "preserved_findings_sha256" => findings_sha,
    "previous_status" => previous_status,
    "new_status" => section["status"].to_s
  }
end

sections = Array(patched_qa["sections"])
whole_timeline_pass = patched_qa.dig("whole_timeline_review", "status").to_s == "pass"
patched_qa["overall_status"] =
  sections.all? { |section| section.is_a?(Hash) && section["status"].to_s == "pass" } && whole_timeline_pass ? "pass" : "blocked"

output_qa = options[:output_qa] || next_version_path(run_path, "03v-section-video-prompt-qa")
default_patch_record = rel_path(run_path + "review/03v-section-qa-patch-records/#{Time.now.strftime('%Y-%m-%d')}-#{record['target_scope']}-#{record['target_id']}-pass.yaml")
patch_record_path = options[:patch_record] || default_patch_record
patch_md_path = options[:patch_md] || patch_record_path.sub(/\.ya?ml\z/, ".md")
output_qa_absolute = require_run_target!(output_qa, "output section QA", run_path, owner: review_root)
patch_record_absolute = require_run_target!(patch_record_path, "section QA patch record", run_path, owner: review_root)
patch_md_absolute = require_run_target!(patch_md_path, "section QA patch markdown", run_path, owner: review_root)
output_qa = rel_path(output_qa_absolute)
patch_record_path = rel_path(patch_record_absolute)
patch_md_path = rel_path(patch_md_absolute)

patch_record = build_patch_record(
  run_rel,
  record_path,
  review_worklist_path,
  source_qa_path,
  output_qa,
  record,
  patched_sections,
  patched_qa["overall_status"].to_s
)

lines = []
lines << "# 03V Section QA Patch Record"
lines << ""
lines << "generated_at: #{patch_record['generated_at']}"
lines << "run: `#{run_rel}`"
lines << "source_review_record: `#{record_path}`"
lines << "source_section_qa: `#{source_qa_path}`"
lines << "output_section_qa: `#{output_qa}`"
lines << "output_overall_status: `#{patch_record.dig('summary', 'output_overall_status')}`"
lines << ""
lines << "## Patched Sections"
lines << ""
lines << "| section | cues | founder_playback_decision | previous_status | new_status |"
lines << "| --- | --- | --- | --- | --- |"
patched_sections.each do |section|
  lines << markdown_table_row([
    "`#{section['section_key']}`",
    Array(section["cue_ids"]).join(", "),
    "`#{section['founder_playback_decision']}`",
    "`#{section['previous_status']}`",
    "`#{section['new_status']}`"
  ])
end
lines << ""
lines << "## Boundaries"
lines << ""
patch_record["automation_boundaries"].each { |boundary| lines << "- #{boundary}" }

if options[:write]
  qa_path = output_qa_absolute
  record_out_path = patch_record_absolute
  md_path = patch_md_absolute
  FileUtils.mkdir_p(qa_path.dirname)
  FileUtils.mkdir_p(record_out_path.dirname)
  FileUtils.mkdir_p(md_path.dirname)
  qa_path.write(YAML.dump(patched_qa), encoding: "utf-8")
  record_out_path.write(YAML.dump(patch_record), encoding: "utf-8")
  md_path.write(lines.join("\n"), encoding: "utf-8")
  puts "wrote #{rel_path(qa_path)}"
  puts "wrote #{rel_path(record_out_path)}"
  puts "wrote #{rel_path(md_path)}"
  validate_patch_outputs!(record_path, output_qa, patch_record_path)
  if options[:refresh_focused_queue]
    run_command!("ruby", "scripts/idol_video_prompt_section_qa_worklist.rb", run_rel, "--qa", output_qa, "--write")
    run_command!(
      "ruby",
      "scripts/idol_03v_refresh_playback_surfaces.rb",
      run_rel,
      "--worklist",
      rel_path(run_path + "review/03v-section-video-prompt-qa-worklist-v1.yaml"),
      "--route",
      refresh_route,
      "--clips-root",
      refresh_clips_root,
      "--write"
    )
    run_command!("ruby", "scripts/idol_harness_action_queue.rb", run_rel, "--only-check", "video_prompt_section_qa_readiness", "--write")
    run_command!("ruby", "scripts/idol_harness_next_unit.rb", run_rel, "--write")
    run_command!("ruby", "scripts/idol_harness_founder_gate_packet.rb", run_rel, "--write")
    run_command!("ruby", "scripts/idol_director_dispatch_index.rb", "build", run_rel, "--json")
    run_command!("ruby", "scripts/idol_director_dispatch_index.rb", "validate", rel_path(run_path + "work/director-dispatch-index.yaml"), "--json")
    run_command!("ruby", "scripts/idol_harness_current_next.rb", run_rel, "--write")
    validate_refresh_outputs!(run_path, run_rel)
  end
else
  puts YAML.dump(patch_record)
end
