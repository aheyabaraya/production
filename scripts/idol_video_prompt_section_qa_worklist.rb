#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "digest"
require "optparse"
require "pathname"
require "time"
require "yaml"

ROOT = Pathname.new(Dir.pwd).cleanpath

def finding_action(finding)
  return "" unless finding.is_a?(Hash)

  finding["required_action"].to_s
end

def usage_error(message)
  warn "ERROR: #{message}"
  warn "usage: ruby scripts/idol_video_prompt_section_qa_worklist.rb RUN_ROOT [--manifest PATH] [--qa PATH] [--output PATH] [--output-yaml PATH] [--write]"
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

def section_key(value)
  value.to_s.match(/\b(S\d{2})\b/)&.[](1)
end

def truncate(value, limit = 220)
  text = value.to_s.gsub(/\s+/, " ").strip
  return "" if text.empty?
  return text if text.length <= limit

  "#{text[0, limit - 3]}..."
end

def md_path(value)
  return "`(missing)`" if blank?(value)

  "`#{value}`"
end

def markdown_table_row(values)
  "| #{values.map { |value| value.to_s.gsub("|", "\\|") }.join(" | ")} |"
end

def dir_path?(path)
  resolved = resolve_path(path)
  resolved && Dir.exist?(resolved.to_s)
end

def file_path?(path)
  resolved = resolve_path(path)
  resolved && File.file?(resolved.to_s)
end

def upload_ready_surface(manifest, run_path)
  output_root = manifest["canonical_video_prompt_output_root"].to_s
  unless blank?(output_root)
    candidate = File.join(output_root, "upload-ready")
    return candidate if dir_path?(candidate)
  end

  candidate = rel_path(run_path + "generations/video-prompts/upload-ready")
  return candidate if dir_path?(candidate)

  ""
end

def upload_ready_folder_for(surface, cue, order)
  return "" if blank?(surface) || !cue.is_a?(Hash)

  section = cue["section_id"].to_s
  cue_id = cue["cue_id"].to_s
  return "" if section.empty? || cue_id.empty?

  expected = File.join(surface, "#{format('%03d', order)}_#{section}_#{cue_id}")
  return expected if dir_path?(expected)

  surface_path = resolve_path(surface)
  return "" unless surface_path && Dir.exist?(surface_path.to_s)

  matches = Dir.glob(File.join(surface_path.to_s, "#{format('%03d', order)}_*")).select do |path|
    File.directory?(path) && File.basename(path).end_with?("_#{cue_id}")
  end
  matches.empty? ? "" : rel_path(matches.sort.first)
end

def attach_upload_ready_fields(cue, folder)
  return cue if blank?(folder)

  cue = cue.dup
  cue["upload_ready_folder"] = folder
  cue["upload_ready_prompt"] = File.join(folder, "prompt.txt")
  cue["upload_ready_image1"] = File.join(folder, "image1.png")
  image2 = File.join(folder, "image2.png")
  cue["upload_ready_image2"] = image2 if file_path?(image2)
  cue
end

def prompt_start_image(cue)
  images = Array(cue["source_production_cut_images"]).each_with_object([]) do |image, rows|
    rows << image["path"].to_s if image.is_a?(Hash) && !blank?(image["path"])
  end.first.to_s
  images
end

def prompt_end_image(cue)
  images = Array(cue["source_production_cut_images"]).each_with_object([]) do |image, rows|
    rows << image["path"].to_s if image.is_a?(Hash) && !blank?(image["path"])
  end
  images.length > 1 ? images.last.to_s : ""
end

def cue_timeline(cue)
  timeline = cue["timeline"].is_a?(Hash) ? cue["timeline"] : {}
  return "" if timeline["start_seconds"].nil? || timeline["end_seconds"].nil?

  format("%.3f-%.3f", timeline["start_seconds"].to_f, timeline["end_seconds"].to_f)
end

def cue_upload_pack_type(cue)
  Array(cue["source_production_cut_images"]).length == 1 ? "one-frame-production-cut" : "motion-storyboard-multi-reference-evidence"
end

def playback_only_section?(section)
  false
end

def pass_section?(section)
  section.is_a?(Hash) && section["status"].to_s == "pass"
end

def default_front_gate_min_sections(section_queue)
  first_key = Array(section_queue).find { |section| pass_section?(section) || playback_only_section?(section) }&.dig("section_key").to_s
  first_key == "S00" ? 4 : 3
end

def front_gate_min_sections_for(section)
  section.to_h["section_key"].to_s == "S00" ? 4 : 3
end

def section_range(section_keys)
  return "" if section_keys.empty?

  "#{section_keys.first}-#{section_keys.last}"
end

def list_value(values)
  Array(values).map(&:to_s).reject(&:empty?).join(",")
end

def front_playback_gate_summary(section_queue, min_sections)
  sections = Array(section_queue)
  skipped_pass_sections = 0
  skipped_pass_chunks = []
  start_index = 0
  current_min_sections = min_sections

  loop do
    current_min_sections = min_sections || front_gate_min_sections_for(sections[start_index])
    chunk = sections[start_index, current_min_sections].to_a
    break if chunk.empty?

    if chunk.length == current_min_sections && chunk.all? { |section| pass_section?(section) }
      chunk_keys = chunk.map { |section| section["section_key"].to_s }
      skipped_pass_sections += chunk.length
      skipped_pass_chunks << section_range(chunk_keys)
      start_index += chunk.length
      next
    end

    break
  end

  current_min_sections = min_sections || front_gate_min_sections_for(sections[start_index])
  gate_sections = sections[start_index, current_min_sections].to_a
  gate_ready = gate_sections.length == current_min_sections &&
               gate_sections.any? { |section| playback_only_section?(section) } &&
               gate_sections.all? { |section| pass_section?(section) || playback_only_section?(section) }

  return {
    "front_playback_gate_ready" => false,
    "front_playback_gate_min_sections" => current_min_sections,
    "front_playback_gate_section_count" => 0,
    "front_playback_gate_section_range" => "",
    "front_playback_gate_packet_count" => 0,
    "front_playback_gate_skipped_pass_section_count" => skipped_pass_sections,
    "front_playback_gate_skipped_pass_chunks" => list_value(skipped_pass_chunks),
    "front_playback_gate_next_local_section" => "",
    "front_playback_gate_next_local_continuation_allowed" => false
  } unless gate_ready

  section_keys = gate_sections.map { |section| section["section_key"].to_s }
  next_local = Array(section_queue)[start_index + gate_sections.length]
  next_local_continuation_allowed = next_local &&
                                    !pass_section?(next_local) &&
                                    !playback_only_section?(next_local)
  playback_sections = gate_sections.select { |section| playback_only_section?(section) }
  passed_sections = gate_sections.select { |section| pass_section?(section) }
  remaining_ready_tail = sections[(start_index + gate_sections.length)..].to_a.take_while { |section| playback_only_section?(section) }
  {
    "front_playback_gate_ready" => true,
    "front_playback_gate_min_sections" => current_min_sections,
    "front_playback_gate_section_count" => section_keys.length,
    "front_playback_gate_section_range" => "#{section_keys.first}-#{section_keys.last}",
    "front_playback_gate_packet_count" => gate_sections.sum { |section| Array(section["packet_ids"]).length },
    "front_playback_gate_skipped_pass_section_count" => skipped_pass_sections,
    "front_playback_gate_skipped_pass_chunks" => list_value(skipped_pass_chunks),
    "front_playback_gate_passed_section_ids" => list_value(passed_sections.map { |section| section["section_key"].to_s }),
    "front_playback_gate_remaining_section_ids" => list_value(playback_sections.map { |section| section["section_key"].to_s }),
    "front_playback_gate_total_ready_section_count" => playback_sections.length + remaining_ready_tail.length,
    "front_playback_gate_total_ready_packet_count" => (playback_sections + remaining_ready_tail).sum { |section| Array(section["packet_ids"]).length },
    "front_playback_gate_next_local_section" => next_local ? next_local["section_key"].to_s : "",
    "front_playback_gate_next_local_continuation_allowed" => next_local_continuation_allowed == true
  }
end

options = {
  manifest: nil,
  qa: nil,
  output: nil,
  output_yaml: nil,
  front_gate_min_sections: nil,
  write: false
}

OptionParser.new do |parser|
  parser.on("--manifest PATH") { |value| options[:manifest] = value }
  parser.on("--qa PATH") { |value| options[:qa] = value }
  parser.on("--output PATH") { |value| options[:output] = value }
  parser.on("--output-yaml PATH") { |value| options[:output_yaml] = value }
  parser.on("--front-gate-min-sections N", Integer) { |value| options[:front_gate_min_sections] = value }
  parser.on("--write") { options[:write] = true }
end.parse!

run_arg = ARGV.shift
usage_error("RUN_ROOT is required") if blank?(run_arg)

run_path = resolve_path(run_arg)
usage_error("RUN_ROOT is not a directory: #{run_arg}") unless run_path && Dir.exist?(run_path.to_s)

manifest_path = options[:manifest] || rel_path(run_path + "03V-video-prompt-manifest.yaml")
manifest = load_yaml_hash(manifest_path)
usage_error("only active idol_video_prompt_manifest.v8 is accepted") unless manifest["schema_version"].to_s == "idol_video_prompt_manifest.v8"

qa_path = options[:qa] || latest_match(run_path, "review/03v-section-video-prompt-qa-v*.yaml")
usage_error("section QA path could not be inferred") if blank?(qa_path)
qa_path = rel_path(qa_path)
qa = load_yaml_hash(qa_path)
usage_error("only active idol_video_prompt_section_qa.v6 is accepted") unless qa["schema_version"].to_s == "idol_video_prompt_section_qa.v6"

manifest_abs = resolve_path(manifest_path)
qa_manifest_abs = resolve_path(qa["source_video_prompt_manifest_path"])
usage_error("section QA is not bound to the selected active 03V manifest") unless qa_manifest_abs == manifest_abs
manifest_sha = Digest::SHA256.file(manifest_abs).hexdigest
unless qa["source_video_prompt_manifest_sha256"].to_s == manifest_sha
  usage_error("section QA source_video_prompt_manifest_sha256 is stale")
end
usage_error("section QA content_id differs from active 03V manifest") unless qa["content_id"].to_s == manifest["content_id"].to_s

output_path = options[:output] || rel_path(run_path + "review/03v-section-video-prompt-qa-worklist-v1.md")
output_yaml_path = options[:output_yaml] || output_path.sub(/\.md\z/, ".yaml")

cues = manifest["cues"].is_a?(Array) ? manifest["cues"] : []
founder_operator_surface = upload_ready_surface(manifest, run_path)
prompt_paths_by_cue = Array(manifest["section_shards"]).each_with_object({}) do |shard, rows|
  next unless shard.is_a?(Hash)

  cue_ids = Array(shard["cue_ids"]).map(&:to_s)
  prompt_paths = Array(shard["output_prompt_paths"]).map(&:to_s)
  usage_error("#{shard['section_id']} cue_ids and output_prompt_paths must have equal ordered coverage") unless cue_ids.length == prompt_paths.length
  cue_ids.zip(prompt_paths).each { |cue_id, prompt_path| rows[cue_id] = prompt_path }
end
cues_by_id = cues.each_with_index.each_with_object({}) do |(cue, idx), hash|
  next unless cue.is_a?(Hash)

  cue_id = cue["cue_id"].to_s
  cue = cue.dup
  cue["output_prompt_path"] = prompt_paths_by_cue[cue_id].to_s
  cue["upload_pack_folder"] = File.dirname(cue["output_prompt_path"]) unless cue["output_prompt_path"].empty?
  cue["upload_pack_type"] = cue_upload_pack_type(cue)
  cue = attach_upload_ready_fields(cue, upload_ready_folder_for(founder_operator_surface, cue, idx + 1))
  hash[cue_id] = cue
end

sections = qa["sections"].is_a?(Array) ? qa["sections"] : []
not_pass_counts = Hash.new(0)
sections.each do |section|
  next unless section.is_a?(Hash)

  Array(section["findings"]).each do |finding|
    next unless finding.is_a?(Hash)

    not_pass_counts[finding["severity"].to_s] += 1
  end
end

generated_at = Time.now.iso8601
section_queue = sections.map do |section|
  next unless section.is_a?(Hash)

  cue_ids = Array(section["cue_ids"]).map(&:to_s)
  findings = Array(section["findings"]).select { |finding| finding.is_a?(Hash) }

  {
    "section_key" => section["section_key"].to_s,
    "section_label" => section["section_label"].to_s,
    "status" => section["status"].to_s,
    "packet_ids" => cue_ids,
    "unfinished_checks" => findings.each_index.map { |index| "finding_#{index + 1}" },
    "entry_continuity" => truncate(section["section_entry_continuity"]),
    "exit_continuity" => truncate(section["section_exit_continuity"]),
    "review_actions" => findings.each_with_index.map do |finding, index|
      {
        "field" => "finding_#{index + 1}",
        "status" => finding["severity"].to_s,
        "action" => finding_action(finding)
      }
    end,
    "packets" => cue_ids.map do |cue_id|
      cue = cues_by_id[cue_id] || {}
      audio_cue = cue.dig("timeline", "audio_cue").to_s
      continuity = cue["previous_next_continuity"].to_s
      {
        "packet_id" => cue_id,
        "timeline" => cue_timeline(cue),
        "audio_motion_slot" => cue_id,
        "prompt_path" => cue["output_prompt_path"].to_s,
        "start_image" => prompt_start_image(cue),
        "end_image" => prompt_end_image(cue),
        "upload_pack_type" => cue["upload_pack_type"].to_s,
        "upload_pack" => cue["upload_pack_folder"].to_s,
        "upload_ready" => cue["upload_ready_folder"].to_s,
        "upload_ready_prompt" => cue["upload_ready_prompt"].to_s,
        "upload_ready_image1" => cue["upload_ready_image1"].to_s,
        "upload_ready_image2" => cue["upload_ready_image2"].to_s,
        "start_audio_cue" => truncate(audio_cue),
        "end_audio_cue" => truncate(audio_cue),
        "prev_end_to_start" => truncate(continuity),
        "end_to_next_start" => truncate(continuity),
        "edit_point_basis" => truncate(cue["edit_handoff"])
      }
    end
  }
end.compact

front_gate_min_sections = options[:front_gate_min_sections]
front_gate = front_playback_gate_summary(section_queue, front_gate_min_sections)

worklist = {
  "schema_version" => "harness-blocker-worklist.v2",
  "generated_at" => generated_at,
  "run" => rel_path(run_path),
  "worklist_type" => "video_prompt_section_qa",
  "source_artifact" => qa_path,
  "founder_operator_surface" => founder_operator_surface,
  "related_artifacts" => {
    "video_prompt_manifest" => manifest_path
  },
  "status" => "worklist_only_not_a_pass_record",
  "summary" => {
    "qa_overall_status" => qa["overall_status"].to_s,
    "sections" => sections.length,
    "prompts" => cues.length,
    "finding_severity_count" => not_pass_counts.length
  }.merge(front_gate),
  "unfinished_check_counts" => not_pass_counts.sort.to_h,
  "section_queue" => section_queue,
  "automation_boundaries" => [
    "This worklist does not change section QA status.",
    "Do not clear contextual findings or mark a section pass from structure alone.",
    "Do not treat this worklist as founder approval, paid-generation approval, or canonical readiness."
  ]
}

lines = []
lines << "# 03V Section QA Worklist"
lines << ""
lines << "generated_at: #{generated_at}"
lines << "run: `#{rel_path(run_path)}`"
lines << "video_prompt_manifest: `#{manifest_path}`"
lines << "section_qa: `#{qa_path}`"
lines << "founder_operator_surface: `#{founder_operator_surface.empty? ? '(none)' : founder_operator_surface}`"
lines << "structured_worklist: `#{output_yaml_path}`"
lines << "status: `worklist_only_not_a_pass_record`"
lines << ""
lines << "This artifact lists the source-bound contextual findings that remain before the active manifest-bound 03V section QA can be marked `pass`. It does not change QA status and must not be treated as founder approval, paid-generation approval, or canonical readiness."
lines << ""
lines << "## Summary"
lines << ""
lines << "- qa_overall_status: `#{qa['overall_status'] || 'unknown'}`"
lines << "- sections: #{sections.length}"
lines << "- cues: #{cues.length}"
lines << "- finding_severity_count: #{not_pass_counts.length}"
if front_gate["front_playback_gate_ready"]
  lines << "- front_playback_gate: `#{front_gate['front_playback_gate_section_range']}` current front chunk is local-ready; playback/generation route needs founder decision before this chunk can pass."
  lines << "- front_playback_gate_min_sections: #{front_gate['front_playback_gate_min_sections']}"
  lines << "- front_playback_gate_packet_count: #{front_gate['front_playback_gate_packet_count']}"
  lines << "- front_playback_gate_total_ready_section_count: #{front_gate['front_playback_gate_total_ready_section_count']}"
  lines << "- front_playback_gate_total_ready_packet_count: #{front_gate['front_playback_gate_total_ready_packet_count']}"
  lines << "- next_local_section_after_gate: `#{front_gate['front_playback_gate_next_local_section']}`"
else
  lines << "- front_playback_gate: none"
  lines << "- front_playback_gate_min_sections: #{front_gate['front_playback_gate_min_sections']}"
end
lines << ""
unless not_pass_counts.empty?
  lines << "## Finding Severity Counts"
  lines << ""
  lines << "| severity | finding_count |"
  lines << "| --- | ---: |"
  not_pass_counts.sort.each do |field, count|
    lines << markdown_table_row(["`#{field}`", count])
  end
  lines << ""
end

lines << "## Section Queue"
lines << ""

sections.each do |section|
  next unless section.is_a?(Hash)

  key = section["section_key"].to_s
  label = section["section_label"].to_s
  cue_ids = Array(section["cue_ids"]).map(&:to_s)
  findings = Array(section["findings"]).select { |finding| finding.is_a?(Hash) }

  lines << "### #{key} #{label}"
  lines << ""
  lines << "- status: `#{section['status'] || 'unknown'}`"
  lines << "- cue_count: #{cue_ids.length}"
  lines << "- unresolved_findings: #{findings.empty? ? 'none' : findings.length}"
  lines << "- entry_continuity: #{truncate(section['section_entry_continuity'])}"
  lines << "- exit_continuity: #{truncate(section['section_exit_continuity'])}"
  lines << ""

  unless findings.empty?
    lines << "Contextual findings:"
    findings.each_with_index do |finding, index|
      lines << "- `finding_#{index + 1}` (`#{finding['severity']}`): #{finding['issue']} Required action: #{finding_action(finding)}"
    end
    lines << ""
  end

  lines << "| cue | source mode | timeline | audio cue | prompt | first source image | last source image | upload ready | upload pack |"
  lines << "| --- | --- | --- | --- | --- | --- | --- | --- | --- |"
  cue_ids.each do |cue_id|
    cue = cues_by_id[cue_id] || {}
    lines << markdown_table_row([
      "`#{cue_id}`",
      "`#{cue['upload_pack_type'] || ''}`",
      cue_timeline(cue),
      truncate(cue.dig("timeline", "audio_cue"), 42),
      md_path(cue["output_prompt_path"]),
      md_path(prompt_start_image(cue)),
      md_path(prompt_end_image(cue)),
      md_path(cue["upload_ready_folder"]),
      md_path(cue["upload_pack_folder"])
    ])
  end
  lines << ""

  cue_ids.each do |cue_id|
    cue = cues_by_id[cue_id] || {}
    lines << "**#{cue_id} audio/edit basis**"
    lines << ""
    lines << "- audio_cue: #{truncate(cue.dig('timeline', 'audio_cue'))}"
    lines << "- previous_next_continuity: #{truncate(cue['previous_next_continuity'])}"
    lines << "- edit_handoff: #{truncate(cue['edit_handoff'])}"
    lines << ""
  end
end

report = lines.join("\n")

if options[:write]
  resolved_output = resolve_path(output_path)
  resolved_yaml_output = resolve_path(output_yaml_path)
  FileUtils.mkdir_p(resolved_output.dirname)
  FileUtils.mkdir_p(resolved_yaml_output.dirname)
  resolved_output.write(report, encoding: "utf-8")
  resolved_yaml_output.write(YAML.dump(worklist), encoding: "utf-8")
  puts "wrote #{rel_path(resolved_output)}"
  puts "wrote #{rel_path(resolved_yaml_output)}"
else
  puts report
end
