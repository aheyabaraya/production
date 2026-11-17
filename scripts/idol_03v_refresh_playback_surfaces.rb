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
  warn "usage: ruby scripts/idol_03v_refresh_playback_surfaces.rb RUN_ROOT [--worklist PATH] [--route ROUTE] [--clips-root PATH] [--state PATH] [--force] [--write]"
  exit 2
end

def blank?(value)
  value.nil? || value.to_s.strip.empty?
end

def resolve_path(value)
  return nil if blank?(value)

  raw = Pathname.new(value.to_s)
  raw.absolute? ? raw.cleanpath : (ROOT + raw).cleanpath
end

def rel_path(value)
  path = resolve_path(value)
  return "" unless path

  path.relative_path_from(ROOT).to_s
rescue ArgumentError
  path.to_s
end

def inside_path?(child, parent)
  child = resolve_path(child)
  parent = resolve_path(parent)
  return false unless child && parent

  parent = parent.realpath if parent.exist?
  suffix = []
  ancestor = child
  until ancestor.exist? || ancestor.root?
    suffix.unshift(ancestor.basename.to_s)
    ancestor = ancestor.parent
  end
  return false unless ancestor.exist?
  actual = suffix.reduce(ancestor.realpath) { |current, part| current.join(part) }
  actual.to_s == parent.to_s || actual.to_s.start_with?("#{parent}/")
rescue Errno::ENOENT, Errno::EACCES
  false
end

def latest_match(run_path, pattern)
  matches = Dir.glob((run_path + pattern).to_s).select { |path| File.file?(path) }
  return nil if matches.empty?

  matches.sort_by do |path|
    version = File.basename(path).match(/(?:^|[-_])v(\d+)(?:\D|$)/)&.[](1)&.to_i || -1
    [version, File.mtime(path), path]
  end.last
end

def load_yaml_hash(path)
  resolved = resolve_path(path)
  usage_error("file is not readable: #{path}") unless resolved && File.file?(resolved)
  document = YAML.safe_load(resolved.read, permitted_classes: [], permitted_symbols: [], aliases: true)
  usage_error("YAML root must be a mapping: #{path}") unless document.is_a?(Hash)
  document
rescue Psych::SyntaxError => e
  usage_error("YAML syntax error in #{path}: #{e.message}")
end

def sha256_file(path)
  Digest::SHA256.file(resolve_path(path).to_s).hexdigest
end

def slug(value)
  value.to_s.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-+\z/, "")
end

def run_command!(*command)
  stdout, stderr, status = Open3.capture3(*command, chdir: ROOT.to_s)
  puts stdout unless stdout.empty?
  warn stderr unless stderr.empty?
  usage_error("command failed: #{command.join(' ')}") unless status.success?
end

def validate_schema!(schema, artifact)
  run_command!(
    "scripts/idol-video-python",
    "scripts/validate_json_schema.py",
    schema,
    artifact
  )
end

def derived_outputs_current?(state, expected_outputs)
  recorded = Array(state["outputs"]).each_with_object({}) do |item, memo|
    next unless item.is_a?(Hash)
    memo[item["role"].to_s] = item
  end
  expected_outputs.all? do |role, path|
    item = recorded[role]
    resolved = resolve_path(path)
    item && item["path"].to_s == rel_path(path) && resolved && File.file?(resolved) && item["sha256"].to_s == sha256_file(path)
  end
end

options = {
  worklist: nil,
  route: "grok_manual_drive_mirror",
  clips_root: nil,
  state: nil,
  intake_yaml: nil,
  intake_md: nil,
  playback_worklist_yaml: nil,
  playback_worklist_md: nil,
  decision_sheet_yaml: nil,
  decision_sheet_md: nil,
  force: false,
  write: false
}

OptionParser.new do |parser|
  parser.on("--worklist PATH") { |value| options[:worklist] = value }
  parser.on("--route ROUTE") { |value| options[:route] = value }
  parser.on("--clips-root PATH") { |value| options[:clips_root] = value }
  parser.on("--state PATH") { |value| options[:state] = value }
  parser.on("--intake-yaml PATH") { |value| options[:intake_yaml] = value }
  parser.on("--intake-md PATH") { |value| options[:intake_md] = value }
  parser.on("--playback-worklist-yaml PATH") { |value| options[:playback_worklist_yaml] = value }
  parser.on("--playback-worklist-md PATH") { |value| options[:playback_worklist_md] = value }
  parser.on("--decision-sheet-yaml PATH") { |value| options[:decision_sheet_yaml] = value }
  parser.on("--decision-sheet-md PATH") { |value| options[:decision_sheet_md] = value }
  parser.on("--force") { options[:force] = true }
  parser.on("--write") { options[:write] = true }
end.parse!

run_arg = ARGV.shift
usage_error("RUN_ROOT is required") if blank?(run_arg)
usage_error("unexpected arguments: #{ARGV.join(' ')}") unless ARGV.empty?
run_path = resolve_path(run_arg)
usage_error("RUN_ROOT is not a directory: #{run_arg}") unless run_path && Dir.exist?(run_path)
run_rel = rel_path(run_path)

worklist_path = options[:worklist] || latest_match(run_path, "review/03v-section-video-prompt-qa-worklist-v*.yaml")
usage_error("03V section QA worklist could not be inferred") if blank?(worklist_path)
worklist_path = rel_path(worklist_path)
worklist = load_yaml_hash(worklist_path)
section_range = worklist.dig("summary", "front_playback_gate_section_range").to_s
section_range = "S00-S00" if section_range.empty?
route = options[:route].to_s
usage_error("route must be non-empty") if route.empty?
clips_root = options[:clips_root] || rel_path(run_path + "generations/video/generated-clips/03v/#{slug(section_range)}/#{slug(route)}")
clips_root = rel_path(clips_root)

intake_yaml = rel_path(options[:intake_yaml] || run_path + "review/03v-generated-playback-intake-v1.yaml")
intake_md = rel_path(options[:intake_md] || intake_yaml.sub(/\.ya?ml\z/, ".md"))
playback_worklist_yaml = rel_path(options[:playback_worklist_yaml] || run_path + "review/03v-playback-review-worklist-v1.yaml")
playback_worklist_md = rel_path(options[:playback_worklist_md] || playback_worklist_yaml.sub(/\.ya?ml\z/, ".md"))
decision_sheet_yaml = rel_path(options[:decision_sheet_yaml] || run_path + "review/03v-playback-decision-sheet-v1.yaml")
decision_sheet_md = rel_path(options[:decision_sheet_md] || decision_sheet_yaml.sub(/\.ya?ml\z/, ".md"))
state_path = rel_path(options[:state] || run_path + "review/03v-playback-refresh-state-v1.yaml")

usage_error("worklist must stay inside RUN_ROOT: #{worklist_path}") unless inside_path?(worklist_path, run_path)
usage_error("clips root must stay inside RUN_ROOT: #{clips_root}") unless inside_path?(clips_root, run_path)

expected_outputs = {
  "generated_playback_intake_yaml" => intake_yaml,
  "generated_playback_intake_md" => intake_md,
  "playback_review_worklist_yaml" => playback_worklist_yaml,
  "playback_review_worklist_md" => playback_worklist_md,
  "playback_decision_sheet_yaml" => decision_sheet_yaml,
  "playback_decision_sheet_md" => decision_sheet_md
}
expected_outputs.each_value do |path|
  usage_error("refresh output must stay inside RUN_ROOT: #{path}") unless inside_path?(path, run_path)
end
usage_error("refresh state must stay inside RUN_ROOT: #{state_path}") unless inside_path?(state_path, run_path)

clips_path = resolve_path(clips_root)
clip_files = if clips_path && Dir.exist?(clips_path)
               Dir.glob((clips_path + "**/*").to_s).select do |path|
                 File.file?(path) && VIDEO_EXTENSIONS.include?(File.extname(path).downcase)
               end.sort
             else
               []
             end
clip_sources = clip_files.map do |path|
  {
    "path" => rel_path(path),
    "sha256" => Digest::SHA256.file(path).hexdigest,
    "byte_count" => File.size(path)
  }
end
source_worklist_sha = sha256_file(worklist_path)
implementation_paths = %w[
  scripts/idol_03v_refresh_playback_surfaces.rb
  scripts/idol_03v_generated_playback_intake.rb
  scripts/idol_03v_playback_review_worklist.rb
  scripts/idol_03v_playback_decision_sheet.rb
  scripts/validate_json_schema.py
  schemas/03v-playback-refresh-state.schema.json
  schemas/03v-generated-playback-intake.schema.json
  schemas/03v-playback-review-worklist.schema.json
  schemas/03v-playback-decision-sheet.schema.json
]
implementation_sources = implementation_paths.map do |path|
  usage_error("refresh implementation source is missing: #{path}") unless File.file?(resolve_path(path))
  {"path" => path, "sha256" => sha256_file(path)}
end
implementation_fingerprint = Digest::SHA256.hexdigest(
  implementation_sources.map { |item| "#{item['path']}:#{item['sha256']}" }.join("\n")
)
input_material = ["implementation:#{implementation_fingerprint}", "worklist:#{source_worklist_sha}", "route:#{route}", "clips_root:#{clips_root}"]
clip_sources.each { |item| input_material << "clip:#{item['path']}:#{item['sha256']}:#{item['byte_count']}" }
input_sha = Digest::SHA256.hexdigest(input_material.join("\n"))

prior_state = File.file?(resolve_path(state_path)) ? load_yaml_hash(state_path) : nil
same_input = prior_state && prior_state["input_sha256"].to_s == input_sha
same_implementation = prior_state && prior_state.dig("refresh_contract", "implementation_fingerprint_sha256").to_s == implementation_fingerprint
outputs_current = prior_state && derived_outputs_current?(prior_state, expected_outputs)
noop = !options[:force] && same_input && same_implementation && outputs_current

unless options[:write]
  puts YAML.dump(
    "run" => run_rel,
    "status" => noop ? "would_noop" : "would_refresh",
    "input_sha256" => input_sha,
    "clip_source_count" => clip_sources.length,
    "state" => state_path
  )
  exit 0
end

if noop
  puts "03v_playback_refresh noop #{input_sha}"
  exit 0
end

refresh_reason = if options[:force]
                   "forced"
                 elsif prior_state.nil?
                   "first_refresh"
                 elsif !same_implementation
                   "implementation_changed"
                 elsif !same_input
                   "source_changed"
                 else
                   "derived_output_stale"
                 end

run_command!(
  "ruby", "scripts/idol_03v_generated_playback_intake.rb", run_rel,
  "--worklist", worklist_path,
  "--route", route,
  "--clips-root", clips_root,
  "--output-yaml", intake_yaml,
  "--output-md", intake_md,
  "--write"
)
run_command!(
  "ruby", "scripts/idol_03v_playback_review_worklist.rb", run_rel,
  "--intake", intake_yaml,
  "--output-yaml", playback_worklist_yaml,
  "--output-md", playback_worklist_md,
  "--write"
)
run_command!(
  "ruby", "scripts/idol_03v_playback_decision_sheet.rb", run_rel,
  "--worklist", playback_worklist_yaml,
  "--output-yaml", decision_sheet_yaml,
  "--output-md", decision_sheet_md,
  "--write"
)

validate_schema!("schemas/03v-generated-playback-intake.schema.json", intake_yaml)
validate_schema!("schemas/03v-playback-review-worklist.schema.json", playback_worklist_yaml)
validate_schema!("schemas/03v-playback-decision-sheet.schema.json", decision_sheet_yaml)

outputs = expected_outputs.map do |role, path|
  usage_error("expected refresh output is missing: #{path}") unless File.file?(resolve_path(path))
  {"role" => role, "path" => path, "sha256" => sha256_file(path)}
end
state = {
  "schema_version" => "idol_03v_playback_refresh_state.v1",
  "generated_at" => Time.now.iso8601,
  "run" => run_rel,
  "status" => "current",
  "route" => route,
  "section_range" => section_range,
  "source_worklist" => worklist_path,
  "source_worklist_sha256" => source_worklist_sha,
  "clips_root" => clips_root,
  "clip_sources" => clip_sources,
  "refresh_contract" => {
    "contract_version" => "idol_03v_playback_refresh.v1",
    "implementation_fingerprint_sha256" => implementation_fingerprint,
    "implementation_sources" => implementation_sources
  },
  "input_sha256" => input_sha,
  "outputs" => outputs,
  "summary" => {
    "clip_source_count" => clip_sources.length,
    "output_count" => outputs.length,
    "refresh_reason" => refresh_reason
  },
  "automation_boundaries" => [
    "This state only suppresses identical 03V intake/worklist/decision-sheet recomputation; it does not record a playback pass.",
    "Any worklist, route, clip path, clip bytes, or derived output change invalidates the no-op path.",
    "Founder playback review and section-QA pass remain explicit gates.",
    "Paid generation, Drive mutation, publishing, packaging, and edit readiness are outside this refresh."
  ]
}
resolved_state = resolve_path(state_path)
FileUtils.mkdir_p(resolved_state.dirname)
resolved_state.write(YAML.dump(state), encoding: "utf-8")
validate_schema!("schemas/03v-playback-refresh-state.schema.json", state_path)
puts "03v_playback_refresh refreshed #{input_sha} reason=#{refresh_reason}"
