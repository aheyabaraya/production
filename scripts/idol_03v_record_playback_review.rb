#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "open3"
require "optparse"
require "pathname"
require "time"
require "yaml"

ROOT = Pathname.new(Dir.pwd).cleanpath

def usage_error(message)
  warn "ERROR: #{message}"
  warn "usage: ruby scripts/idol_03v_record_playback_review.rb RUN_ROOT --from-text TEXT [--review-source TEXT] [--explicit-founder-review] [--worklist PATH] [--output-yaml PATH] [--output-md PATH] [--write]"
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

def require_run_file!(path, label, run_path)
  resolved = resolve_path(path)
  usage_error("#{label} is not readable: #{path}") unless resolved&.file?
  usage_error("#{label} must stay inside the owning run: #{path}") unless within?(resolved, run_path)
  resolved.realpath
end

def require_run_target!(path, label, run_path)
  resolved = resolve_path(path)
  usage_error("#{label} must stay inside the owning run: #{path}") unless resolved && within?(resolved, run_path)
  ancestor = resolved
  ancestor = ancestor.parent until ancestor.exist? || ancestor.root?
  usage_error("#{label} escapes the owning run through a symlink: #{path}") unless ancestor.exist? && within?(ancestor.realpath, run_path.realpath)
  resolved
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

def normalize_text(text)
  text.to_s.downcase.gsub(/[[:space:]]+/, " ").strip
end

def decision_from_text(text)
  normalized = normalize_text(text)
  usage_error("--from-text is empty") if normalized.empty?

  matches = []
  if normalized.match?(/\b(pass|passed|ok|okay|accept|accepted|clean|good)\b/) ||
     normalized.include?("통과") || normalized.include?("이상없") || normalized.include?("좋아") || normalized.include?("좋음")
    matches << "pass"
  end
  if normalized.match?(/\b(hold|wait|pending)\b/) || normalized.include?("보류") || normalized.include?("대기") || normalized.include?("잠깐")
    matches << "hold"
  end
  if normalized.match?(/\b(fix|redo|retry|reject|rework|fail|failed)\b/) ||
     normalized.include?("수정") || normalized.include?("다시") || normalized.include?("재생성") || normalized.include?("문제") || normalized.include?("실패")
    matches << "fix"
  end

  matches.uniq!
  usage_error("--from-text matched no playback decision; include pass, hold, or fix") if matches.empty?
  usage_error("--from-text is ambiguous (#{matches.join(', ')}); use a clearer playback decision") if matches.length > 1

  matches.first
end

def packet_id_from_text(text, packets)
  normalized = normalize_text(text)
  packet_ids = Array(packets).map { |packet| packet["packet_id"].to_s }
  packet_ids.find { |packet_id| normalized.include?(packet_id.downcase) } ||
    packet_ids.find do |packet_id|
      short = packet_id.sub(/\APKT_/, "")
      normalized.include?(short.downcase)
    end ||
    begin
      match = normalized.match(/(?:^|[^a-z0-9])(?:pkt[_-]?)?b(\d{1,2})(?=$|[^a-z0-9])/)
      if match
        b_code = "B#{format('%02d', match[1].to_i)}"
        packet_ids.find { |packet_id| packet_id.include?(b_code) }
      end
    end
end

def validate_decision_target!(decision, target_scope, target_id)
  return unless decision == "fix"
  return if target_scope == "packet"

  usage_error("fix decisions must name one packet, e.g. fix PKT_B03: <visible issue>; got #{target_scope} #{target_id}")
end

def decision_note_from_text(text, decision)
  raw = text.to_s.strip
  colon_note = raw.split(/[:：]/, 2)[1].to_s.strip
  return colon_note unless colon_note.empty?

  note = raw.dup
  note.gsub!(/(?:^|[^A-Za-z0-9])(?:PKT[_-]?)?B\d{1,2}(?=$|[^A-Za-z0-9])/i, " ")
  note.gsub!(/\bS\d{1,2}\s*-\s*S?\d{1,2}\b/i, " ")
  note.gsub!(/\bS\d{1,2}\b/i, " ")
  note.gsub!(/\b(pass|passed|ok|okay|accept|accepted|clean|good|hold|wait|pending|fix|redo|retry|reject|rework|fail|failed|gate|front|chunk|all)\b/i, " ")
  note.gsub!(/통과|이상없음?|좋아|좋음|보류|대기|잠깐|수정|다시|재생성|문제|실패|전체|전부|현재|앞/, " ")
  note.gsub(/[[:space:][:punct:]]+/, " ").strip
end

def validate_decision_note!(decision, note)
  return if decision == "pass"
  return unless note.to_s.strip.empty?

  usage_error("#{decision} decisions must include a visible reason or issue note, e.g. #{decision == 'fix' ? 'fix PKT_B03: foot slide at endpoint' : 'S00-S03 hold: waiting for playback export'}")
end

def target_from_text(text, worklist)
  normalized = normalize_text(text)
  section_ids = Array(worklist["section_ids"]).map(&:to_s)
  packets = Array(worklist["section_reviews"]).flat_map { |section| Array(section["packets"]) }
  packet_id = packet_id_from_text(normalized, packets)
  return ["packet", packet_id] unless blank?(packet_id)

  range = worklist["section_range"].to_s
  explicit_range = begin
    match = normalized.match(/\bs(\d{1,2})\s*-\s*(?:s)?(\d{1,2})\b/)
    "S#{format('%02d', match[1].to_i)}-S#{format('%02d', match[2].to_i)}" if match
  end
  if !blank?(explicit_range)
    usage_error("--from-text names #{explicit_range}, but the current playback gate is #{range}") unless explicit_range == range

    return ["gate", range]
  end

  if normalized.include?("전체") || normalized.include?("전부") || normalized.include?("all") || normalized.include?("gate") ||
     normalized.include?("front") || normalized.include?("chunk") || normalized.include?("현재") || normalized.include?("앞") ||
     (!range.empty? && normalized.include?(range.downcase))
    return ["gate", range]
  end

  section_id = section_ids.find { |id| normalized.match?(/\b#{Regexp.escape(id.downcase)}\b/) } ||
               begin
                 match = normalized.match(/\bs(\d{1,2})\b/)
                 candidate = "S#{format('%02d', match[1].to_i)}" if match
                 section_ids.include?(candidate) ? candidate : nil
               end
  return ["section", section_id] unless blank?(section_id)

  usage_error("--from-text must name a packet, section, or the gate range")
end

def section_by_key(worklist, key)
  Array(worklist["section_reviews"]).find { |section| section.is_a?(Hash) && section["section_key"].to_s == key.to_s } || {}
end

def target_packets(worklist, scope, target_id)
  case scope
  when "packet"
    Array(worklist["section_reviews"]).flat_map { |section| Array(section["packets"]) }.select do |packet|
      packet.is_a?(Hash) && packet["packet_id"].to_s == target_id.to_s
    end
  when "section"
    Array(section_by_key(worklist, target_id)["packets"])
  when "gate"
    Array(worklist["section_reviews"]).flat_map { |section| Array(section["packets"]) }
  else
    []
  end
end

def covered_sections(scope, target_id, packets)
  if scope == "section"
    [target_id.to_s]
  else
    packets.map { |packet| packet["section_key"].to_s }.uniq
  end
end

def review_status(decision)
  {
    "pass" => "pass_recorded",
    "hold" => "hold_recorded",
    "fix" => "fix_recorded"
  }.fetch(decision)
end

def compact_required_checks(packet)
  Array(packet["required_checks"]).map do |check|
    next unless check.is_a?(Hash)

    {
      "id" => check["id"].to_s,
      "label" => check["label"].to_s
    }
  end.compact.reject { |check| check["id"].empty? }
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

def validate_worklist_against_intake!(worklist, intake, run_path, run_rel)
  usage_error("source intake schema_version is not idol_03v_generated_playback_intake.v1") unless intake["schema_version"].to_s == "idol_03v_generated_playback_intake.v1"
  usage_error("source intake run=#{intake['run'].inspect}; expected #{run_rel.inspect}") unless intake["run"].to_s == run_rel
  usage_error("source intake section_range does not match playback worklist") unless intake["section_range"].to_s == worklist["section_range"].to_s
  usage_error("source intake source_section_qa does not match playback worklist") unless intake["source_section_qa"].to_s == worklist["source_section_qa"].to_s
  clips_root = resolve_path(intake["clips_root"])
  usage_error("source intake clips_root must stay inside the owning run") unless clips_root && within?(clips_root, run_path)
  intake_packets = packets_by_id(intake["clip_queue"], "source intake clip_queue")
  worklist_packets = packets_by_id(
    Array(worklist["section_reviews"]).flat_map { |section| Array(section.is_a?(Hash) ? section["packets"] : []) },
    "playback review worklist"
  )
  usage_error("playback review worklist packet set does not match source intake") unless worklist_packets.keys.sort == intake_packets.keys.sort
  worklist_packets.each do |packet_id, packet|
    source = intake_packets.fetch(packet_id)
    %w[section_key timeline clip_status clip_file_status generated_clip_path generated_clip_sha256].each do |field|
      usage_error("playback worklist packet #{packet_id} #{field} does not match source intake") unless packet[field].to_s == source[field].to_s
    end
    usage_error("playback worklist packet #{packet_id} media_probe does not match source intake") unless packet["media_probe"] == source["media_probe"]
    next unless packet["clip_status"].to_s == "present"

    probe = packet["media_probe"].is_a?(Hash) ? packet["media_probe"] : {}
    unless packet["clip_file_status"].to_s == "present_probe_ok" && probe["status"].to_s == "ok" && probe["playable"] == true &&
           probe["duration_seconds"].to_f.positive? && probe["video_stream_count"].to_i.positive? &&
           probe["width"].to_i.positive? && probe["height"].to_i.positive?
      usage_error("playback worklist packet #{packet_id} cannot pass without a positive playable media probe")
    end
    clip_path = require_run_file!(packet["generated_clip_path"], "generated clip #{packet_id}", run_path)
    usage_error("generated clip #{packet_id} is outside intake clips_root") unless within?(clip_path, clips_root)
    expected_sha = packet["generated_clip_sha256"].to_s
    usage_error("generated clip #{packet_id} requires a 64-character SHA-256") unless expected_sha.match?(/\A[a-f0-9]{64}\z/)
    usage_error("generated clip #{packet_id} SHA-256 changed") unless Digest::SHA256.file(clip_path.to_s).hexdigest == expected_sha
  end
end

def next_action(decision, scope, target_id, summary)
  if decision == "pass"
    if summary["can_patch_generation_playback_probe"]
      "Playback pass is recorded for #{scope} #{target_id}; a separate explicit 03V QA patch step may change generation_playback_probe for the covered section(s)."
    else
      "Pass was not allowed because target clips are missing; collect generated clips and rerun playback review."
    end
  elsif decision == "fix"
    "Playback fix is recorded for #{scope} #{target_id}; revise the named prompt/source or regenerate the clip, then rerun intake and playback review."
  else
    "Playback hold is recorded for #{scope} #{target_id}; keep generation_playback_probe as needs_founder until a pass or fix decision is recorded."
  end
end

def markdown_table_row(values)
  "| #{values.map { |value| value.to_s.gsub("|", "\\|") }.join(" | ")} |"
end

def run_command!(*command)
  stdout, stderr, status = Open3.capture3(*command, chdir: ROOT.to_s)
  puts stdout unless stdout.empty?
  warn stderr unless stderr.empty?
  usage_error("command failed: #{command.join(' ')}") unless status.success?
end

def validate_schema!(schema_path, document_path)
  run_command!(
    "scripts/idol-video-python",
    "scripts/validate_json_schema.py",
    schema_path,
    document_path
  )
end

options = {
  from_text: nil,
  review_source: "founder_chat",
  explicit_founder_review: false,
  worklist: nil,
  output_yaml: nil,
  output_md: nil,
  write: false
}

OptionParser.new do |parser|
  parser.on("--from-text TEXT") { |value| options[:from_text] = value }
  parser.on("--review-source TEXT") { |value| options[:review_source] = value }
  parser.on("--explicit-founder-review") { options[:explicit_founder_review] = true }
  parser.on("--worklist PATH") { |value| options[:worklist] = value }
  parser.on("--output-yaml PATH") { |value| options[:output_yaml] = value }
  parser.on("--output-md PATH") { |value| options[:output_md] = value }
  parser.on("--write") { options[:write] = true }
end.parse!

run_arg = ARGV.shift
usage_error("RUN_ROOT is required") if blank?(run_arg)
usage_error("--from-text is required") if blank?(options[:from_text])

run_path = resolve_path(run_arg)
usage_error("RUN_ROOT is not a directory: #{run_arg}") unless run_path && Dir.exist?(run_path.to_s)
run_rel = rel_path(run_path)

worklist_path = options[:worklist] || latest_match(run_path, "review/03v-playback-review-worklist-v*.yaml")
usage_error("03V playback review worklist could not be inferred") if blank?(worklist_path)
worklist_absolute = require_run_file!(worklist_path, "playback review worklist", run_path)
worklist_path = rel_path(worklist_absolute)
worklist = load_yaml_hash(worklist_absolute)
usage_error("worklist run=#{worklist['run'].inspect}; expected #{run_rel.inspect}") unless worklist["run"].to_s == run_rel
source_intake_absolute = require_run_file!(worklist["source_intake"], "generated playback intake", run_path)
source_intake = load_yaml_hash(source_intake_absolute)
usage_error("source intake run=#{source_intake['run'].inspect}; expected #{run_rel.inspect}") unless source_intake["run"].to_s == run_rel
source_qa_absolute = require_run_file!(worklist["source_section_qa"], "source section QA", run_path)
validate_worklist_against_intake!(worklist, source_intake, run_path, run_rel)

decision = decision_from_text(options[:from_text])
target_scope, target_id = target_from_text(options[:from_text], worklist)
validate_decision_target!(decision, target_scope, target_id)
decision_note = decision_note_from_text(options[:from_text], decision)
validate_decision_note!(decision, decision_note)
packets = target_packets(worklist, target_scope, target_id)
usage_error("target #{target_scope} #{target_id} has no packets in the review worklist") if packets.empty?

present = packets.count { |packet| packet["clip_status"].to_s == "present" }
missing = packets.length - present
pending = packets.count { |packet| packet["playback_review_status"].to_s == "pending_review" }
all_present = missing.zero?
if decision == "pass" && !all_present
  usage_error("cannot record pass for #{target_scope} #{target_id}: #{missing} clip(s) are missing")
end

can_patch = decision == "pass" && all_present && options[:explicit_founder_review]
covered_packets = packets.map do |packet|
  if decision == "pass"
    clip_path = require_run_file!(packet["generated_clip_path"], "generated clip #{packet['packet_id']}", run_path)
    expected_sha = packet["generated_clip_sha256"].to_s
    usage_error("generated clip #{packet['packet_id']} requires a 64-character SHA-256") unless expected_sha.match?(/\A[a-f0-9]{64}\z/)
    usage_error("generated clip #{packet['packet_id']} SHA-256 changed before review recording") unless Digest::SHA256.file(clip_path.to_s).hexdigest == expected_sha
  end
  {
    "packet_id" => packet["packet_id"].to_s,
    "section_key" => packet["section_key"].to_s,
    "timeline" => packet["timeline"].to_s,
    "clip_status" => packet["clip_status"].to_s,
    "generated_clip_path" => packet["generated_clip_path"].to_s,
    "generated_clip_sha256" => packet["generated_clip_sha256"].to_s,
    "required_checks" => compact_required_checks(packet),
    "required_check_count" => Array(packet["required_checks"]).length,
    "review_status_after_record" => review_status(decision)
  }
end
summary = {
  "packet_count" => packets.length,
  "present_clip_count" => present,
  "missing_clip_count" => missing,
  "pending_review_count" => pending,
  "all_target_clips_present" => all_present,
  "can_patch_generation_playback_probe" => can_patch
}

payload = {
  "schema_version" => "idol_03v_playback_review_record.v1",
  "generated_at" => Time.now.iso8601,
  "run" => run_rel,
  "status" => "recorded",
  "source_review_worklist" => worklist_path,
  "source_review_worklist_sha256" => Digest::SHA256.file(worklist_absolute.to_s).hexdigest,
  "source_intake" => rel_path(source_intake_absolute),
  "source_intake_sha256" => Digest::SHA256.file(source_intake_absolute.to_s).hexdigest,
  "source_section_qa" => rel_path(source_qa_absolute),
  "source_section_qa_sha256" => Digest::SHA256.file(source_qa_absolute.to_s).hexdigest,
  "section_range" => worklist["section_range"].to_s,
  "target_scope" => target_scope,
  "target_id" => target_id,
  "decision" => decision,
  "decision_input_text" => options[:from_text].to_s,
  "decision_note" => decision_note.empty? ? options[:from_text].to_s : decision_note,
  "review_source" => options[:review_source].to_s,
  "explicit_founder_review" => options[:explicit_founder_review] == true,
  "covered_sections" => covered_sections(target_scope, target_id, covered_packets),
  "covered_packets" => covered_packets,
  "summary" => summary,
  "next_action" => next_action(decision, target_scope, target_id, summary),
  "automation_boundaries" => [
    "This record does not mutate 03V section QA, publish, Drive, or edit readiness.",
    "generation_playback_probe can only be patched in a separate explicit step after a pass record with all target clips present and founder review recorded.",
    "Hold or fix records keep the section partial and require another generated playback review before pass."
  ]
}

date_prefix = Time.now.strftime("%Y-%m-%d")
target_slug = "#{target_scope}-#{target_id}".downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-+\z/, "")
output_yaml = options[:output_yaml] || rel_path(run_path + "review/03v-playback-review-records/#{date_prefix}-#{target_slug}-#{decision}.yaml")
output_md = options[:output_md] || output_yaml.sub(/\.ya?ml\z/, ".md")
output_yaml_absolute = require_run_target!(output_yaml, "playback review record output", run_path)
output_md_absolute = require_run_target!(output_md, "playback review markdown output", run_path)

lines = []
lines << "# 03V Playback Review Record"
lines << ""
lines << "generated_at: #{payload['generated_at']}"
lines << "run: `#{run_rel}`"
lines << "target: `#{target_scope} #{target_id}`"
lines << "decision: `#{decision}`"
lines << "decision_note: #{payload['decision_note']}"
lines << "explicit_founder_review: `#{payload['explicit_founder_review']}`"
lines << "source_review_worklist: `#{worklist_path}`"
lines << ""
lines << "## Summary"
lines << ""
summary.each { |key, value| lines << "- #{key}: #{value}" }
lines << "- next_action: #{payload['next_action']}"
lines << ""
lines << "## Covered Packets"
lines << ""
lines << "| packet | section | timeline | clip | checks | review_status |"
lines << "| --- | --- | --- | --- | --- | --- |"
covered_packets.each do |packet|
  lines << markdown_table_row([
    "`#{packet['packet_id']}`",
    "`#{packet['section_key']}`",
    packet["timeline"],
    "`#{packet['clip_status']}`",
    Array(packet["required_checks"]).map { |check| check["id"].to_s }.join(", "),
    "`#{packet['review_status_after_record']}`"
  ])
end
lines << ""
lines << "## Boundaries"
lines << ""
payload["automation_boundaries"].each { |boundary| lines << "- #{boundary}" }

if options[:write]
  yaml_path = output_yaml_absolute
  md_path = output_md_absolute
  FileUtils.mkdir_p(yaml_path.dirname)
  FileUtils.mkdir_p(md_path.dirname)
  yaml_path.write(YAML.dump(payload), encoding: "utf-8")
  md_path.write(lines.join("\n"), encoding: "utf-8")
  puts "wrote #{rel_path(yaml_path)}"
  puts "wrote #{rel_path(md_path)}"
  validate_schema!("schemas/03v-playback-review-record.schema.json", rel_path(yaml_path))
else
  puts YAML.dump(payload)
end
