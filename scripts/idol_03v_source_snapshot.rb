#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "optparse"
require "pathname"
require "time"
require "yaml"
require_relative "lib/idol_03v_source_discovery"

DEFAULT_ROOT = Pathname.new(__dir__).join("..").expand_path

options = {
  root: DEFAULT_ROOT,
  version: "v1",
  generated_at: Time.now.utc.iso8601,
  output: nil,
  write: false,
  json: false
}

parser = OptionParser.new do |opts|
  opts.banner = "usage: ruby scripts/idol_03v_source_snapshot.rb RUN_ROOT [options]"
  opts.on("--root PATH", String, "Repository root used to resolve and relativize sources") { |value| options[:root] = Pathname.new(value).expand_path }
  opts.on("--version VERSION", String, "Snapshot version used by the default output path") { |value| options[:version] = value }
  opts.on("--generated-at ISO8601", String, "Deterministic snapshot timestamp") { |value| options[:generated_at] = value }
  opts.on("--output PATH", String, "Explicit snapshot output path") { |value| options[:output] = Pathname.new(value).expand_path }
  opts.on("--write", "Write the run-owned snapshot") { options[:write] = true }
  opts.on("--json", "Print the complete snapshot document") { options[:json] = true }
end

begin
  parser.parse!
rescue OptionParser::ParseError => e
  warn e.message
  warn parser
  exit 2
end

run_arg = ARGV.shift
if run_arg.to_s.strip.empty? || !ARGV.empty?
  warn parser
  exit 2
end

begin
  Time.iso8601(options[:generated_at])
rescue ArgumentError
  warn "generated-at must be ISO8601"
  exit 2
end

root = options[:root].expand_path.cleanpath
run_path = Pathname.new(run_arg)
run_path = root.join(run_path) unless run_path.absolute?
run_path = run_path.expand_path.cleanpath
unless run_path.directory?
  warn "run root is not readable: #{run_path}"
  exit 1
end

result = Idol03VSourceDiscovery.scan(
  run_path: run_path,
  repo_root: root,
  generated_at: options[:generated_at]
)
snapshot = result.document
errors = Idol03VSourceDiscovery.validate_snapshot(snapshot, repo_root: root)
unless errors.empty?
  errors.each { |error| warn "ERROR: #{error}" }
  exit 1
end

output_path = options[:output] || run_path.join("handoff", "03v-source-snapshot-#{options[:version]}.yaml")
if options[:write]
  FileUtils.mkdir_p(output_path.dirname)
  output_path.write(YAML.dump(snapshot))
end

if options[:json]
  puts JSON.pretty_generate(snapshot)
else
  puts JSON.pretty_generate(
    "write" => options[:write],
    "snapshot_path" => Idol03VSourceDiscovery.relative_path(output_path, root),
    "status" => snapshot["status"],
    "source_count" => snapshot["sources"].length,
    "source_set_sha256" => snapshot["source_set_sha256"],
    "gate_detection" => snapshot["gate_detection"],
    "missing_required_roles" => snapshot["missing_required_roles"]
  )
end
