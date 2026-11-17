#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "open3"
require "optparse"
require "pathname"
require "yaml"
require_relative "lib/idol_current_next_v2"

ROOT = Pathname.new(Dir.pwd).cleanpath

def usage_error(message)
  warn "ERROR: #{message}"
  warn "usage: ruby scripts/idol_harness_apply_founder_decision.rb RUN_ROOT (--from-text TEXT | --decision DECISION_ID) [--source-note TEXT] [--decision-note TEXT] [--explicit-approval] [--approved-route TEXT] [--current-next PATH] [--decision-yaml PATH] [--decision-md PATH] [--current-decision-yaml PATH] [--current-decision-md PATH] [--action-queue-yaml PATH] [--action-queue-md PATH] [--next-unit-yaml PATH] [--next-unit-md PATH] [--founder-gate-yaml PATH] [--founder-gate-md PATH] [--current-next-yaml PATH] [--current-next-md PATH] [--write]"
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
  return {} unless resolved && File.file?(resolved.to_s)

  doc = YAML.load_file(resolved.to_s)
  doc.is_a?(Hash) ? doc : {}
rescue Psych::SyntaxError => e
  usage_error("YAML syntax error in #{path}: #{e.message}")
end

def run_command(args)
  stdout, stderr, status = Open3.capture3(*args, chdir: ROOT.to_s)
  unless status.success?
    warn stdout unless stdout.empty?
    warn stderr unless stderr.empty?
    usage_error("command failed: #{args.join(' ')}")
  end
  stdout
end

def validate_schema!(schema_path, document_path)
  return if blank?(document_path)

  stdout = run_command([
    "scripts/idol-video-python",
    "scripts/validate_json_schema.py",
    schema_path,
    document_path
  ])
  puts stdout.strip unless stdout.strip.empty?
end

def ensure_front_03v_gate!(current_next_path, run_rel)
  context = IdolCurrentNextV2.load_active(
    path: current_next_path,
    run: run_rel,
    root: ROOT,
    require_actionable: true,
    require_legacy: %w[source_next_unit source_founder_gate source_action_queue]
  )
  IdolCurrentNextV2.require_03v_legacy_gate!(context)
  context
rescue IdolCurrentNextV2::Error => error
  usage_error(error.message)
end

def command_line(lines, args)
  lines << args.join(" ")
end

def copy_artifact!(source_path, target_path)
  source = resolve_path(source_path)
  target = resolve_path(target_path)
  usage_error("cannot preserve missing artifact: #{source_path}") unless source && File.file?(source.to_s)

  FileUtils.mkdir_p(target.dirname)
  FileUtils.cp(source.to_s, target.to_s)
end

options = {
  from_text: nil,
  decision: nil,
  source_note: "founder_chat",
  decision_note: "",
  explicit_approval: false,
  approved_route: "",
  current_next: "automation/current-next.yaml",
  decision_yaml: nil,
  decision_md: nil,
  current_decision_yaml: "automation/founder-decisions/current.yaml",
  current_decision_md: "automation/founder-decisions/current.md",
  action_queue_yaml: nil,
  action_queue_md: nil,
  next_unit_yaml: nil,
  next_unit_md: nil,
  founder_gate_yaml: nil,
  founder_gate_md: nil,
  current_next_yaml: "automation/current-next.yaml",
  current_next_md: "automation/current-next.md",
  write: false
}

OptionParser.new do |parser|
  parser.on("--from-text TEXT") { |value| options[:from_text] = value }
  parser.on("--decision DECISION_ID") { |value| options[:decision] = value }
  parser.on("--source-note TEXT") { |value| options[:source_note] = value }
  parser.on("--decision-note TEXT") { |value| options[:decision_note] = value }
  parser.on("--explicit-approval") { options[:explicit_approval] = true }
  parser.on("--approved-route TEXT") { |value| options[:approved_route] = value }
  parser.on("--current-next PATH") { |value| options[:current_next] = value }
  parser.on("--decision-yaml PATH") { |value| options[:decision_yaml] = value }
  parser.on("--decision-md PATH") { |value| options[:decision_md] = value }
  parser.on("--current-decision-yaml PATH") { |value| options[:current_decision_yaml] = value }
  parser.on("--current-decision-md PATH") { |value| options[:current_decision_md] = value }
  parser.on("--action-queue-yaml PATH") { |value| options[:action_queue_yaml] = value }
  parser.on("--action-queue-md PATH") { |value| options[:action_queue_md] = value }
  parser.on("--next-unit-yaml PATH") { |value| options[:next_unit_yaml] = value }
  parser.on("--next-unit-md PATH") { |value| options[:next_unit_md] = value }
  parser.on("--founder-gate-yaml PATH") { |value| options[:founder_gate_yaml] = value }
  parser.on("--founder-gate-md PATH") { |value| options[:founder_gate_md] = value }
  parser.on("--current-next-yaml PATH") { |value| options[:current_next_yaml] = value }
  parser.on("--current-next-md PATH") { |value| options[:current_next_md] = value }
  parser.on("--write") { options[:write] = true }
end.parse!

run_arg = ARGV.shift
usage_error("RUN_ROOT is required") if blank?(run_arg)
if blank?(options[:from_text]) && blank?(options[:decision])
  usage_error("--from-text or --decision is required")
end
unless blank?(options[:from_text]) || blank?(options[:decision])
  usage_error("use only one of --from-text or --decision")
end
usage_error("--write is required to apply a founder decision") unless options[:write]

run_path = resolve_path(run_arg)
usage_error("RUN_ROOT is not a directory: #{run_arg}") unless run_path && Dir.exist?(run_path.to_s)
run_rel = rel_path(run_path)
content_id = run_path.basename.to_s
date_prefix = Time.now.strftime("%Y-%m-%d")

current_next_input = rel_path(options[:current_next])
current_context = ensure_front_03v_gate!(current_next_input, run_rel)
source_founder_gate = current_context.dig("legacy_bindings", "source_founder_gate", "path").to_s
usage_error("current-next does not name a source founder gate") if blank?(source_founder_gate)
founder_gate_source = blank?(options[:founder_gate_yaml]) ? source_founder_gate : options[:founder_gate_yaml]
source_founder_gate_md = source_founder_gate.sub(/\.ya?ml\z/, ".md")
founder_gate_md = options[:founder_gate_md]
founder_gate_md = founder_gate_source.sub(/\.ya?ml\z/, ".md") if blank?(founder_gate_md)

record_args = [
  "ruby",
  "scripts/idol_harness_record_founder_decision.rb",
  run_rel,
  "--source-note",
  options[:source_note],
  "--current-next",
  current_next_input,
  "--current-yaml",
  options[:current_decision_yaml],
  "--current-md",
  options[:current_decision_md],
  "--write"
]
if blank?(options[:decision])
  record_args += ["--from-text", options[:from_text]]
else
  record_args += ["--decision", options[:decision]]
end
record_args += ["--decision-note", options[:decision_note]] unless blank?(options[:decision_note])
record_args << "--explicit-approval" if options[:explicit_approval]
record_args += ["--approved-route", options[:approved_route]] unless blank?(options[:approved_route])
record_args += ["--output-yaml", options[:decision_yaml]] unless blank?(options[:decision_yaml])
record_args += ["--output-md", options[:decision_md]] unless blank?(options[:decision_md])

commands = []
command_line(commands, record_args)
run_command(record_args)
validate_schema!("schemas/harness-founder-decision.schema.json", options[:current_decision_yaml])
validate_schema!("schemas/harness-founder-decision.schema.json", options[:decision_yaml]) unless blank?(options[:decision_yaml])

intake_args = [
  "ruby",
  "scripts/idol_03v_generated_playback_intake.rb",
  run_rel,
  "--route",
  blank?(options[:approved_route]) ? "grok_manual_drive_mirror" : options[:approved_route],
  "--write"
]
command_line(commands, intake_args)
run_command(intake_args)
generated_intake = rel_path(run_path + "review/03v-generated-playback-intake-v1.yaml")
validate_schema!("schemas/03v-generated-playback-intake.schema.json", generated_intake)

review_worklist_args = [
  "ruby",
  "scripts/idol_03v_playback_review_worklist.rb",
  run_rel,
  "--write"
]
command_line(commands, review_worklist_args)
run_command(review_worklist_args)
playback_worklist = rel_path(run_path + "review/03v-playback-review-worklist-v1.yaml")
validate_schema!("schemas/03v-playback-review-worklist.schema.json", playback_worklist)

decision_sheet_args = [
  "ruby",
  "scripts/idol_03v_playback_decision_sheet.rb",
  run_rel,
  "--write"
]
command_line(commands, decision_sheet_args)
run_command(decision_sheet_args)
playback_decision_sheet = rel_path(run_path + "review/03v-playback-decision-sheet-v1.yaml")
validate_schema!("schemas/03v-playback-decision-sheet.schema.json", playback_decision_sheet)

default_action_queue = "automation/action-queues/#{date_prefix}-#{content_id}-03v-action-queue.yaml"
action_args = [
  "ruby",
  "scripts/idol_harness_action_queue.rb",
  run_rel,
  "--only-check",
  "video_prompt_section_qa_readiness",
  "--founder-decision",
  options[:current_decision_yaml],
  "--write"
]
action_args += ["--output-yaml", options[:action_queue_yaml]] unless blank?(options[:action_queue_yaml])
action_args += ["--output-md", options[:action_queue_md]] unless blank?(options[:action_queue_md])
command_line(commands, action_args)
run_command(action_args)
action_queue_source = blank?(options[:action_queue_yaml]) ? default_action_queue : options[:action_queue_yaml]
validate_schema!("schemas/harness-action-queue.schema.json", action_queue_source)

default_next_unit = "automation/next-units/#{date_prefix}-#{content_id}-harness-next-unit.yaml"
next_args = [
  "ruby",
  "scripts/idol_harness_next_unit.rb",
  run_rel,
  "--write"
]
next_args += ["--action-queue", options[:action_queue_yaml]] unless blank?(options[:action_queue_yaml])
next_args += ["--output-yaml", options[:next_unit_yaml]] unless blank?(options[:next_unit_yaml])
next_args += ["--output-md", options[:next_unit_md]] unless blank?(options[:next_unit_md])
command_line(commands, next_args)
run_command(next_args)
next_unit_source = blank?(options[:next_unit_yaml]) ? default_next_unit : options[:next_unit_yaml]
validate_schema!("schemas/harness-next-unit.schema.json", next_unit_source)

active_decision = load_yaml_hash(options[:current_decision_yaml])
if active_decision["decision_id"].to_s == "continue_local_next_section"
  if rel_path(founder_gate_source) != rel_path(source_founder_gate)
    copy_artifact!(source_founder_gate, founder_gate_source)
    command_line(commands, ["preserve", source_founder_gate, founder_gate_source])
    if File.file?(resolve_path(source_founder_gate_md).to_s)
      copy_artifact!(source_founder_gate_md, founder_gate_md)
      command_line(commands, ["preserve", source_founder_gate_md, founder_gate_md])
    end
  end
else
  founder_gate_args = [
    "ruby",
    "scripts/idol_harness_founder_gate_packet.rb",
    run_rel,
    "--next-unit",
    next_unit_source,
    "--output-yaml",
    founder_gate_source,
    "--output-md",
    founder_gate_md,
    "--write"
  ]
  command_line(commands, founder_gate_args)
  run_command(founder_gate_args)
end
validate_schema!("schemas/harness-founder-gate.schema.json", founder_gate_source)

ddi_path = rel_path(run_path + "work/director-dispatch-index.yaml")
ddi_build_args = ["ruby", "scripts/idol_director_dispatch_index.rb", "build", run_rel, "--json"]
command_line(commands, ddi_build_args)
run_command(ddi_build_args)
ddi_validate_args = ["ruby", "scripts/idol_director_dispatch_index.rb", "validate", ddi_path, "--json"]
command_line(commands, ddi_validate_args)
run_command(ddi_validate_args)

current_args = [
  "ruby",
  "scripts/idol_harness_current_next.rb",
  run_rel,
  "--next-unit",
  next_unit_source,
  "--founder-gate",
  founder_gate_source,
  "--output-yaml",
  options[:current_next_yaml],
  "--output-md",
  options[:current_next_md],
  "--write"
]
command_line(commands, current_args)
run_command(current_args)
validate_schema!("schemas/harness-current-next.schema.json", options[:current_next_yaml])

validator_args = [
  "ruby",
  "scripts/validate_03v_front_playback_gate.rb",
  run_rel,
  "--current-next",
  options[:current_next_yaml]
]
validator_args += ["--founder-gate", founder_gate_source]
validator_args += ["--action-queue", options[:action_queue_yaml]] unless blank?(options[:action_queue_yaml])
validator_args += ["--next-unit", options[:next_unit_yaml]] unless blank?(options[:next_unit_yaml])
command_line(commands, validator_args)
validator_output = run_command(validator_args)

begin
  refreshed_context = IdolCurrentNextV2.load_active(
    path: options[:current_next_yaml],
    run: run_rel,
    root: ROOT,
    require_actionable: true,
    require_legacy: %w[source_next_unit source_founder_gate source_action_queue]
  )
rescue IdolCurrentNextV2::Error => error
  usage_error(error.message)
end
current_next = refreshed_context.fetch("document")
puts "applied founder decision"
puts "active_frontier_id: #{refreshed_context.dig('selection', 'id')}"
puts "status: #{current_next['status']}"
puts validator_output.strip unless validator_output.strip.empty?
puts "commands:"
commands.each { |line| puts "- #{line}" }
