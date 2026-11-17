#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "optparse"
require "pathname"
require "yaml"
require_relative "lib/idol_graph_run_controller"

ROOT = Pathname.new(__dir__).join("..").expand_path

options = {
  current_next: "automation/current-next.yaml",
  stage_registry: "automation/graph-stage-registry.yaml",
  format: "yaml"
}

parser = OptionParser.new do |opts|
  opts.banner = "usage: ruby scripts/idol_graph_run_controller.rb RUN_ROOT [options]\n\nRead-only Graph v2 shadow probe; never launches, writes, approves, or promotes."
  opts.on("--current-next PATH", "Hash-bound harness-current-next.v2 input") { |value| options[:current_next] = value }
  opts.on("--stage-registry PATH", "Canonical read-only Graph stage registry (alternate paths fail closed)") { |value| options[:stage_registry] = value }
  opts.on("--judgment PATH", "Optional bound judgment; invokes the formal validator before reduction") { |value| options[:judgment] = value }
  opts.on("--previous-event-sha256 SHA", "Optional prior append-only event hash") { |value| options[:previous_event_sha256] = value }
  opts.on("--format FORMAT", %w[yaml json], "stdout format: yaml or json") { |value| options[:format] = value }
  opts.on("-h", "--help", "Show help") do
    puts opts
    exit 0
  end
end

begin
  parser.parse!
  run = ARGV.shift
  raise OptionParser::MissingArgument, "RUN_ROOT" if run.nil? || run.strip.empty?
  raise OptionParser::InvalidArgument, "unexpected arguments: #{ARGV.join(' ')}" unless ARGV.empty?

  result = IdolGraphRunController.build(
    root: ROOT,
    run: run,
    current_next: options.fetch(:current_next),
    stage_registry: options.fetch(:stage_registry),
    judgment: options[:judgment],
    previous_event_sha256: options[:previous_event_sha256]
  )
  if options[:format] == "json"
    puts JSON.pretty_generate(result)
  else
    puts YAML.dump(result)
  end
rescue OptionParser::ParseError, IdolGraphRunController::Error => error
  warn "ERROR: #{error.message}"
  warn parser
  exit 2
end
