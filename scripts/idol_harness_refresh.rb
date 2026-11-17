#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"
require "optparse"
require "pathname"
require "time"
require "yaml"

ROOT = Pathname.new(Dir.pwd).cleanpath

def usage_error(message)
  warn "ERROR: #{message}"
  warn "usage: ruby scripts/idol_harness_refresh.rb RUN_ROOT [--write]"
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

def run_command(command, allow_nonzero: false)
  stdout, stderr, status = Open3.capture3(*command, chdir: ROOT.to_s)
  exit_status = status.exitstatus || 1
  if !allow_nonzero && !exit_status.zero?
    warn "ERROR: command failed: #{command.join(' ')}"
    warn stderr unless stderr.empty?
    warn stdout unless stdout.empty?
    exit exit_status
  end

  [stdout, stderr, exit_status]
rescue Errno::ENOENT => e
  warn "ERROR: command not found: #{command.join(' ')}"
  warn e.message
  exit 127
end

def capture_state(run_rel, report_path = nil)
  command = [
    "ruby",
    "scripts/idol_harness_state_check.rb",
    run_rel,
    "--json"
  ]
  command += ["--report", report_path] unless blank?(report_path)
  stdout, stderr, exit_status = run_command(command, allow_nonzero: true)
  payload = JSON.parse(stdout)
  [payload, stderr, exit_status]
rescue JSON::ParserError => e
  warn "ERROR: state checker did not return JSON: #{e.message}"
  warn stdout.to_s
  warn stderr.to_s
  exit 1
end

def load_yaml_hash(path)
  resolved = resolve_path(path)
  return {} unless resolved && File.file?(resolved.to_s)

  doc = YAML.load_file(resolved.to_s)
  doc.is_a?(Hash) ? doc : {}
rescue Psych::SyntaxError => e
  warn "ERROR: YAML syntax error in #{path}: #{e.message}"
  exit 1
end

def refresh_worklists(run_rel, blockers)
  commands = []
  if blockers.include?("video_prompt_section_qa_readiness")
    commands << ["ruby", "scripts/idol_video_prompt_section_qa_worklist.rb", run_rel, "--write"]
  end
  if blockers.include?("edit_map_readiness")
    commands << ["ruby", "scripts/idol_edit_readiness_worklist.rb", run_rel, "--write"]
  end

  commands.each { |command| run_command(command) }
  commands
end

options = {
  write: false
}

OptionParser.new do |parser|
  parser.on("--write") { options[:write] = true }
end.parse!

run_arg = ARGV.shift
usage_error("RUN_ROOT is required") if blank?(run_arg)

run_path = resolve_path(run_arg)
usage_error("RUN_ROOT is not a directory: #{run_arg}") unless run_path && Dir.exist?(run_path.to_s)

run_rel = rel_path(run_path)
content_id = run_path.basename.to_s
date_prefix = Time.now.strftime("%Y-%m-%d")
state_report = "automation/state-reports/#{date_prefix}-#{content_id}-harness-state.md"
action_queue_yaml = "automation/action-queues/#{date_prefix}-#{content_id}-harness-action-queue.yaml"
action_queue_md = "automation/action-queues/#{date_prefix}-#{content_id}-harness-action-queue.md"
next_unit_yaml = "automation/next-units/#{date_prefix}-#{content_id}-harness-next-unit.yaml"
next_unit_md = "automation/next-units/#{date_prefix}-#{content_id}-harness-next-unit.md"
director_dispatch_index_yaml = "#{run_rel}/work/director-dispatch-index.yaml"
current_next_yaml = "automation/current-next.yaml"
current_next_md = "automation/current-next.md"

unless options[:write]
  payload, = capture_state(run_rel)
  blockers = Array(payload["blocking_checks"])
  puts "IDOL Graph Engineering refresh dry-run"
  puts "run: #{run_rel}"
  puts "would_write:"
  puts "- #{state_report}"
  puts "- #{action_queue_yaml}"
  puts "- #{action_queue_md}"
  puts "- #{next_unit_yaml}"
  puts "- #{next_unit_md}"
  puts "- #{director_dispatch_index_yaml}"
  puts "- #{current_next_yaml}"
  puts "- #{current_next_md}"
  puts "would_refresh_worklists:"
  puts "- review/03v-section-video-prompt-qa-worklist-v*.md" if blockers.include?("video_prompt_section_qa_readiness")
  puts "- review/03v-section-video-prompt-qa-worklist-v*.yaml" if blockers.include?("video_prompt_section_qa_readiness")
  puts "- review/04-edit-readiness-worklist-v*.md" if blockers.include?("edit_map_readiness")
  puts "- review/04-edit-readiness-worklist-v*.yaml" if blockers.include?("edit_map_readiness")
  puts "blocking: #{blockers.empty? ? 'none' : blockers.join(', ')}"
  exit 0
end

payload, = capture_state(run_rel, state_report)
blockers = Array(payload["blocking_checks"])
refreshed_worklist_commands = refresh_worklists(run_rel, blockers)

run_command(["ruby", "scripts/idol_harness_action_queue.rb", run_rel, "--write"])
run_command([
  "scripts/idol-video-python",
  "scripts/validate_json_schema.py",
  "schemas/harness-action-queue.schema.json",
  action_queue_yaml
])
run_command(["ruby", "scripts/idol_harness_next_unit.rb", run_rel, "--write"])
run_command([
  "scripts/idol-video-python",
  "scripts/validate_json_schema.py",
  "schemas/harness-next-unit.schema.json",
  next_unit_yaml
])
run_command(["ruby", "scripts/idol_director_dispatch_index.rb", "build", run_rel, "--json"])
run_command([
  "ruby",
  "scripts/idol_director_dispatch_index.rb",
  "validate",
  director_dispatch_index_yaml,
  "--json"
])
run_command([
  "ruby",
  "scripts/idol_harness_current_next.rb",
  run_rel,
  "--next-unit",
  next_unit_yaml,
  "--write"
])
run_command([
  "scripts/idol-video-python",
  "scripts/validate_json_schema.py",
  "schemas/harness-current-next.schema.json",
  current_next_yaml
])

queue = load_yaml_hash(action_queue_yaml)
summary = queue["state_summary"].is_a?(Hash) ? queue["state_summary"] : {}
next_unit = load_yaml_hash(next_unit_yaml)
current_next = load_yaml_hash(current_next_yaml)

puts "IDOL Graph Engineering refresh: #{queue['status'] || 'unknown'}"
puts "run: #{run_rel}"
puts "state_report: #{state_report}"
puts "action_queue: #{action_queue_yaml}"
puts "action_queue_markdown: #{action_queue_md}"
puts "next_unit: #{next_unit_yaml}"
puts "next_unit_markdown: #{next_unit_md}"
puts "next_unit_status: #{next_unit['status'] || 'unknown'}"
puts "selected_unit: #{next_unit['selected_unit_id'] || ''}"
puts "director_dispatch_index: #{director_dispatch_index_yaml}"
puts "current_next: #{current_next_yaml}"
puts "current_next_markdown: #{current_next_md}"
puts "current_next_status: #{current_next['status'] || 'unknown'}"
puts "active_frontier_kind: #{current_next.dig('frontier_binding', 'selection', 'kind') || 'unknown'}"
puts "active_frontier_id: #{current_next.dig('frontier_binding', 'selection', 'id') || ''}"
puts "checks: pass=#{summary['pass'].to_i}, fail=#{summary['fail'].to_i}, missing=#{summary['missing'].to_i}, blocking=#{summary['blocking'].to_i}"
if blockers.empty?
  puts "blocking: none"
else
  puts "blocking:"
  blockers.each { |blocker| puts "- #{blocker}" }
end
unless refreshed_worklist_commands.empty?
  puts "refreshed_worklists:"
  refreshed_worklist_commands.each { |command| puts "- #{command.join(' ')}" }
end

exit 0
