#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "open3"
require "optparse"
require "pathname"
require "time"
require "yaml"

ROOT = Pathname.new(Dir.pwd).cleanpath

def usage_error(message)
  warn "ERROR: #{message}"
  warn "usage: ruby scripts/idol_03v_apply_playback_decision.rb RUN_ROOT --from-text TEXT [--review-source TEXT] [--explicit-founder-review] [--worklist PATH] [--record-yaml PATH] [--record-md PATH] [--output-qa PATH] [--patch-record PATH] [--patch-md PATH] [--no-refresh-focused-queue] [--write]"
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

def run_command!(*command)
  stdout, stderr, status = Open3.capture3(*command, chdir: ROOT.to_s)
  puts stdout unless stdout.empty?
  warn stderr unless stderr.empty?
  usage_error("command failed: #{command.join(' ')}") unless status.success?
  stdout
end

def validate_schema!(schema_path, document_path)
  return if blank?(document_path)

  run_command!(
    "scripts/idol-video-python",
    "scripts/validate_json_schema.py",
    schema_path,
    document_path
  )
end

def first_written_yaml(stdout)
  stdout.to_s.each_line do |line|
    match = line.match(/\Awrote\s+(.+\.ya?ml)\s*\z/)
    return match[1].to_s if match
  end
  ""
end

options = {
  from_text: nil,
  review_source: "founder_chat",
  explicit_founder_review: false,
  worklist: nil,
  record_yaml: nil,
  record_md: nil,
  output_qa: nil,
  patch_record: nil,
  patch_md: nil,
  refresh_focused_queue: true,
  write: false
}

OptionParser.new do |parser|
  parser.on("--from-text TEXT") { |value| options[:from_text] = value }
  parser.on("--review-source TEXT") { |value| options[:review_source] = value }
  parser.on("--explicit-founder-review") { options[:explicit_founder_review] = true }
  parser.on("--worklist PATH") { |value| options[:worklist] = value }
  parser.on("--record-yaml PATH") { |value| options[:record_yaml] = value }
  parser.on("--record-md PATH") { |value| options[:record_md] = value }
  parser.on("--output-qa PATH") { |value| options[:output_qa] = value }
  parser.on("--patch-record PATH") { |value| options[:patch_record] = value }
  parser.on("--patch-md PATH") { |value| options[:patch_md] = value }
  parser.on("--no-refresh-focused-queue") { options[:refresh_focused_queue] = false }
  parser.on("--write") { options[:write] = true }
end.parse!

run_arg = ARGV.shift
usage_error("RUN_ROOT is required") if blank?(run_arg)
usage_error("--from-text TEXT is required") if blank?(options[:from_text])
usage_error("--write is required to record/apply a playback decision") unless options[:write]

run_path = resolve_path(run_arg)
usage_error("RUN_ROOT is not a directory: #{run_arg}") unless run_path && Dir.exist?(run_path.to_s)
run_rel = rel_path(run_path)

record_args = [
  "ruby",
  "scripts/idol_03v_record_playback_review.rb",
  run_rel,
  "--from-text",
  options[:from_text],
  "--review-source",
  options[:review_source],
  "--write"
]
record_args << "--explicit-founder-review" if options[:explicit_founder_review]
record_args += ["--worklist", options[:worklist]] unless blank?(options[:worklist])
record_args += ["--output-yaml", options[:record_yaml]] unless blank?(options[:record_yaml])
record_args += ["--output-md", options[:record_md]] unless blank?(options[:record_md])

record_stdout = run_command!(*record_args)
record_path = blank?(options[:record_yaml]) ? first_written_yaml(record_stdout) : options[:record_yaml]
usage_error("could not infer written playback review record path") if blank?(record_path)
record_path = rel_path(record_path)
validate_schema!("schemas/03v-playback-review-record.schema.json", record_path)

record = load_yaml_hash(record_path)
decision = record["decision"].to_s
summary = record["summary"].is_a?(Hash) ? record["summary"] : {}

applied = false
apply_stdout = ""
if decision == "pass"
  if summary["can_patch_generation_playback_probe"] == true
    apply_args = [
      "ruby",
      "scripts/idol_03v_apply_playback_review_record.rb",
      run_rel,
      "--record",
      record_path,
      "--write"
    ]
    apply_args += ["--output-qa", options[:output_qa]] unless blank?(options[:output_qa])
    apply_args += ["--patch-record", options[:patch_record]] unless blank?(options[:patch_record])
    apply_args += ["--patch-md", options[:patch_md]] unless blank?(options[:patch_md])
    apply_args << "--refresh-focused-queue" if options[:refresh_focused_queue]
    apply_stdout = run_command!(*apply_args)
    applied = true
  else
    warn "pass record was written but not applied because can_patch_generation_playback_probe is false"
  end
end

puts "03V playback decision handled"
puts "run: #{run_rel}"
puts "record: #{record_path}"
puts "decision: #{decision}"
puts "target: #{record['target_scope']} #{record['target_id']}"
puts "applied_section_qa_patch: #{applied}"
puts "refresh_focused_queue: #{applied && options[:refresh_focused_queue]}"
puts "next_action: #{record['next_action']}"
puts apply_stdout.lines.grep(/OK: front 03V playback gate/).join.strip unless apply_stdout.empty?
