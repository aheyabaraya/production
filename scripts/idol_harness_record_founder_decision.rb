#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "optparse"
require "pathname"
require "time"
require "yaml"
require_relative "lib/idol_current_next_v2"

ROOT = Pathname.new(Dir.pwd).cleanpath

def usage_error(message)
  warn "ERROR: #{message}"
  warn "usage: ruby scripts/idol_harness_record_founder_decision.rb RUN_ROOT (--decision DECISION_ID | --from-text TEXT) [--source-note TEXT] [--explicit-approval] [--approved-route TEXT] [--current-next PATH] [--output-yaml PATH] [--output-md PATH] [--current-yaml PATH] [--current-md PATH] [--write]"
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

def decision_by_id(founder_gate, decision_id)
  Array(founder_gate["allowed_decisions"]).find do |decision|
    decision.is_a?(Hash) && decision["id"].to_s == decision_id.to_s
  end || {}
end

def normalize_founder_text(text)
  text.to_s.downcase.gsub(/[[:space:]]+/, " ").strip
end

def direct_decision_id?(value)
  %w[
    approve_front_chunk_generation
    review_or_refine_prompts_only
    continue_local_next_section
    hold_front_gate
  ].include?(value.to_s)
end

def decision_id_from_text(text)
  normalized = normalize_founder_text(text)
  usage_error("--from-text is empty") if normalized.empty?
  return normalized if direct_decision_id?(normalized)

  matches = []
  approval_generation = (normalized.include?("승인") || normalized.include?("approve")) &&
                        (normalized.include?("생성") || normalized.include?("generation") || normalized.include?("generate") || normalized.include?("playback"))
  if approval_generation
    matches << "approve_front_chunk_generation"
  end
  if !approval_generation &&
     ((normalized.match?(/\bs0?\d+\b/) && (normalized.include?("local") || normalized.include?("qa"))) ||
      normalized.include?("다음") || normalized.include?("계속") || normalized.include?("넘어") || normalized.include?("진행"))
    matches << "continue_local_next_section"
  end
  if !approval_generation &&
     (normalized.include?("프롬프트") || normalized.include?("prompt") || normalized.include?("refine") || normalized.include?("review"))
    matches << "review_or_refine_prompts_only"
  end
  if normalized.include?("보류") || normalized.include?("홀드") || normalized.include?("hold") || normalized.include?("대기") || normalized.include?("멈")
    matches << "hold_front_gate"
  end

  matches.uniq!
  usage_error("--from-text matched no known founder decision; use --decision DECISION_ID") if matches.empty?
  if matches.length > 1
    usage_error("--from-text is ambiguous (#{matches.join(', ')}); use --decision DECISION_ID")
  end
  matches.first
end

def ensure_decision_allowed!(decision, options)
  usage_error("decision id is not allowed by the current founder gate") if decision.empty?

  if decision["requires_explicit_approval"] == true || decision["allows_paid_generation"] == true || decision["allows_external_execution"] == true
    unless options[:explicit_approval]
      usage_error("decision #{decision['id']} requires --explicit-approval")
    end
    if blank?(options[:approved_route])
      usage_error("decision #{decision['id']} requires --approved-route TEXT")
    end
  end
end

def build_payload(run_rel, current_next_path, current_context, founder_gate, decision, options)
  current_next = current_context.fetch("document")
  bindings = current_context.fetch("legacy_bindings")
  {
    "schema_version" => "harness-founder-decision.v1",
    "generated_at" => Time.now.iso8601,
    "run" => run_rel,
    "album_key" => current_next["album_key"].to_s,
    "title_key" => current_next["title_key"].to_s,
    "status" => "active",
    "source_current_next" => current_next_path.to_s,
    "source_founder_gate" => bindings.dig("source_founder_gate", "path").to_s,
    "source_next_unit" => bindings.dig("source_next_unit", "path").to_s,
    "source_action_queue" => bindings.dig("source_action_queue", "path").to_s,
    "gate_id" => founder_gate["gate_id"].to_s,
    "gate_type" => founder_gate["gate_type"].to_s,
    "section_range" => founder_gate["section_range"].to_s,
    "section_ids" => Array(founder_gate["section_ids"]).map(&:to_s),
    "packet_count" => founder_gate["packet_count"].to_i,
    "decision_id" => decision["id"].to_s,
    "decision_label" => decision["label"].to_s,
    "decision_input_text" => options[:from_text].to_s,
    "decision_source" => options[:source_note].to_s,
    "decision_note" => options[:decision_note].to_s,
    "requires_explicit_approval" => decision["requires_explicit_approval"] == true,
    "explicit_approval_recorded" => options[:explicit_approval] == true,
    "approved_execution_route" => options[:approved_route].to_s,
    "allows_paid_generation" => decision["allows_paid_generation"] == true,
    "allows_external_execution" => decision["allows_external_execution"] == true,
    "continues_local_qa" => decision["continues_local_qa"] == true,
    "marks_section_qa_pass" => decision["marks_section_qa_pass"] == true,
    "next_local_section" => founder_gate.dig("current_local_status", "next_local_section").to_s,
    "next_action" => decision["next_action"].to_s,
    "automation_boundaries" => Array(founder_gate["automation_boundaries"]).map(&:to_s),
    "forbidden_actions" => Array(founder_gate["forbidden_actions"]).map(&:to_s)
  }
end

def build_markdown(payload)
  flags = []
  flags << "paid=#{payload['allows_paid_generation']}"
  flags << "external=#{payload['allows_external_execution']}"
  flags << "continue_local=#{payload['continues_local_qa']}"
  flags << "qa_pass=#{payload['marks_section_qa_pass']}"

  lines = []
  lines << "# IDOL Graph Engineering Founder Decision"
  lines << ""
  lines << "generated_at: #{payload['generated_at']}"
  lines << "run: `#{payload['run']}`"
  lines << "status: `#{payload['status']}`"
  lines << ""
  lines << "## Decision"
  lines << ""
  lines << "- gate: `#{payload['gate_id']}`"
  lines << "- section_range: `#{payload['section_range']}`"
  lines << "- decision_id: `#{payload['decision_id']}`"
  lines << "- decision_label: #{payload['decision_label']}"
  lines << "- decision_input_text: #{payload['decision_input_text']}"
  lines << "- flags: #{flags.join(', ')}"
  lines << "- explicit_approval_recorded: `#{payload['explicit_approval_recorded']}`"
  lines << "- approved_execution_route: `#{payload['approved_execution_route']}`"
  lines << "- next_local_section: `#{payload['next_local_section']}`"
  lines << "- next_action: #{payload['next_action']}"
  lines << ""
  lines << "## Sources"
  lines << ""
  lines << "- current_next: `#{payload['source_current_next']}`"
  lines << "- founder_gate: `#{payload['source_founder_gate']}`"
  lines << "- next_unit: `#{payload['source_next_unit']}`"
  lines << "- action_queue: `#{payload['source_action_queue']}`"
  lines << "- decision_source: #{payload['decision_source']}"
  lines << ""
  lines << "## Forbidden Actions"
  lines << ""
  payload["forbidden_actions"].each { |action| lines << "- #{action}" }
  lines.join("\n")
end

options = {
  decision: nil,
  from_text: nil,
  source_note: "founder_chat",
  decision_note: "",
  explicit_approval: false,
  approved_route: "",
  current_next: "automation/current-next.yaml",
  output_yaml: nil,
  output_md: nil,
  current_yaml: "automation/founder-decisions/current.yaml",
  current_md: "automation/founder-decisions/current.md",
  write: false
}

OptionParser.new do |parser|
  parser.on("--decision DECISION_ID") { |value| options[:decision] = value }
  parser.on("--from-text TEXT") { |value| options[:from_text] = value }
  parser.on("--source-note TEXT") { |value| options[:source_note] = value }
  parser.on("--decision-note TEXT") { |value| options[:decision_note] = value }
  parser.on("--explicit-approval") { options[:explicit_approval] = true }
  parser.on("--approved-route TEXT") { |value| options[:approved_route] = value }
  parser.on("--current-next PATH") { |value| options[:current_next] = value }
  parser.on("--output-yaml PATH") { |value| options[:output_yaml] = value }
  parser.on("--output-md PATH") { |value| options[:output_md] = value }
  parser.on("--current-yaml PATH") { |value| options[:current_yaml] = value }
  parser.on("--current-md PATH") { |value| options[:current_md] = value }
  parser.on("--write") { options[:write] = true }
end.parse!

run_arg = ARGV.shift
usage_error("RUN_ROOT is required") if blank?(run_arg)
if blank?(options[:decision]) && blank?(options[:from_text])
  usage_error("--decision or --from-text is required")
end
unless blank?(options[:decision]) || blank?(options[:from_text])
  usage_error("use only one of --decision or --from-text")
end

run_path = resolve_path(run_arg)
usage_error("RUN_ROOT is not a directory: #{run_arg}") unless run_path && Dir.exist?(run_path.to_s)

run_rel = rel_path(run_path)
content_id = run_path.basename.to_s
date_prefix = Time.now.strftime("%Y-%m-%d")
current_next_path = rel_path(options[:current_next])
begin
  current_context = IdolCurrentNextV2.load_active(
    path: current_next_path,
    run: run_rel,
    root: ROOT,
    require_actionable: true,
    require_legacy: %w[source_next_unit source_founder_gate source_action_queue]
  )
  legacy_gate = IdolCurrentNextV2.require_03v_legacy_gate!(current_context)
rescue IdolCurrentNextV2::Error => error
  usage_error(error.message)
end
current_next = current_context.fetch("document")
founder_gate_path = current_context.dig("legacy_bindings", "source_founder_gate", "path").to_s
founder_gate = legacy_gate.fetch("founder_gate")

options[:decision] = decision_id_from_text(options[:from_text]) if blank?(options[:decision])
options[:decision_note] = options[:from_text].to_s if blank?(options[:decision_note]) && !blank?(options[:from_text])
decision = decision_by_id(founder_gate, options[:decision])
ensure_decision_allowed!(decision, options)
payload = build_payload(run_rel, current_next_path, current_context, founder_gate, decision, options)

range_slug = payload["section_range"].downcase
output_yaml = options[:output_yaml] || "automation/founder-decisions/#{date_prefix}-#{content_id}-#{payload['gate_type']}-#{range_slug}-decision.yaml"
output_md = options[:output_md] || "automation/founder-decisions/#{date_prefix}-#{content_id}-#{payload['gate_type']}-#{range_slug}-decision.md"
yaml_text = YAML.dump(payload)
md_text = build_markdown(payload)

if options[:write]
  [output_yaml, output_md, options[:current_yaml], options[:current_md]].each do |path|
    resolved = resolve_path(path)
    FileUtils.mkdir_p(resolved.dirname)
  end
  resolve_path(output_yaml).write(yaml_text, encoding: "utf-8")
  resolve_path(output_md).write(md_text, encoding: "utf-8")
  resolve_path(options[:current_yaml]).write(yaml_text, encoding: "utf-8")
  resolve_path(options[:current_md]).write(md_text, encoding: "utf-8")
  puts "wrote #{rel_path(output_yaml)}"
  puts "wrote #{rel_path(output_md)}"
  puts "wrote #{rel_path(options[:current_yaml])}"
  puts "wrote #{rel_path(options[:current_md])}"
else
  puts yaml_text
end
